package com.phonecam.stream4k

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

class Stream4kControllerTest {

    private class FakeContext : android.content.ContextWrapper(null) {
        override fun getApplicationContext(): android.content.Context {
            return this
        }
        override fun getSystemService(name: String): Any? {
            return null
        }
    }

    private class FakeEncoder : HevcEncoder() {
        var lastBitrate = 0
        override fun setBitrate(bitrateBps: Int) {
            lastBitrate = bitrateBps
        }
    }

    private class FakeCapabilitiesSource(
        private val supported: Set<Triple<Int, Int, Int>>,
        private val normal: Set<Triple<Int, Int, Int>> = supported
    ) : DeviceCapabilitiesSource {
        override fun supportedCombos(): Set<Triple<Int, Int, Int>> = supported
        override fun normalSessionCombos(): Set<Triple<Int, Int, Int>> = normal
        override fun hasHevcEncoder(): Boolean = true
        override fun hevcEncoderSupports(width: Int, height: Int, fps: Int): Boolean = true
        override fun encoderNames(): List<String> = listOf("OMX.google.h265.encoder")
    }

    private class TestStream4kController(context: android.content.Context) : Stream4kController(context) {
        override fun start(ladder: Ladder, targetIp: String, targetPort: Int): Boolean {
            activeLadder = ladder
            currentBitrate = ladder.bitrateBps
            consecutiveGoodReports = 0
            return true
        }
    }

    @Test
    fun testNegotiatedLadderIsSaved() {
        val controller = TestStream4kController(FakeContext())
        controller.probe = FakeCapabilitiesSource(
            supported = setOf(Triple(1920, 1080, 60))
        )
        val peerAddress = InetAddress.getByName("127.0.0.1")
        
        val connectMsg = "{\"version\":\"1.0\",\"type\":\"connect\",\"selected_ladder\":{\"width\":1920,\"height\":1080,\"fps\":60},\"transport\":\"udp\",\"stream_port\":5004}"
        controller.handleControlCommand(connectMsg, peerAddress, 5004)
        
        assertNotNull(controller.negotiatedLadder)
        assertEquals(1920, controller.negotiatedLadder!!.width)
        assertEquals(1080, controller.negotiatedLadder!!.height)
        assertEquals(60, controller.negotiatedLadder!!.fps)
    }

    @Test
    fun testAbpJitterIntegrationFeedbackExtraction() {
        val controller = TestStream4kController(FakeContext())
        val ladder = Ladder(1920, 1080, 60, false, 12_000_000, "1080p60")
        controller.activeLadder = ladder
        controller.currentBitrate = ladder.bitrateBps
        
        val fakeEncoder = FakeEncoder()
        controller.encoder = fakeEncoder
        
        val peerAddress = InetAddress.getByName("127.0.0.1")
        
        val feedbackMsg = "{\"version\":\"1.0\",\"type\":\"feedback\",\"loss_fraction\":0.03,\"jitter_ms\":5.0}"
        controller.handleControlCommand(feedbackMsg, peerAddress, 5004)
        
        val expectedBitrate = (12_000_000 * 0.9).toInt()
        assertEquals(expectedBitrate, controller.currentBitrate)
        assertEquals(expectedBitrate, fakeEncoder.lastBitrate)
        assertEquals(0, controller.consecutiveGoodReports)
    }

    @Test
    fun testStatefulGoodReportsIncreasesBitrate() {
        val controller = TestStream4kController(FakeContext())
        val ladder = Ladder(1920, 1080, 60, false, 12_000_000, "1080p60")
        controller.activeLadder = ladder
        controller.currentBitrate = 8_000_000
        val fakeEncoder = FakeEncoder()
        controller.encoder = fakeEncoder
        
        for (i in 1..9) {
            controller.handleBitrateAdaptation(0.001, 4.0)
            assertEquals(8_000_000, controller.currentBitrate)
            assertEquals(i, controller.consecutiveGoodReports)
        }
        
        controller.handleBitrateAdaptation(0.001, 4.0)
        assertEquals(0, controller.consecutiveGoodReports)
        val expectedBitrate = (8_000_000 * 1.10).toInt()
        assertEquals(expectedBitrate, controller.currentBitrate)
        assertEquals(expectedBitrate, fakeEncoder.lastBitrate)
    }

    @Test
    fun testNeutralReportResetsConsecutiveCounter() {
        val controller = TestStream4kController(FakeContext())
        val ladder = Ladder(1920, 1080, 60, false, 12_000_000, "1080p60")
        controller.activeLadder = ladder
        controller.currentBitrate = 8_000_000
        val fakeEncoder = FakeEncoder()
        controller.encoder = fakeEncoder

        for (i in 1..5) {
            controller.handleBitrateAdaptation(0.001, 4.0)
        }
        assertEquals(5, controller.consecutiveGoodReports)

        controller.handleBitrateAdaptation(0.01, 4.0)
        assertEquals(0, controller.consecutiveGoodReports)
        assertEquals(8_000_000, controller.currentBitrate)
    }

    @Test
    fun testBadReportResetsConsecutiveCounterAndDowngrades() {
        val controller = TestStream4kController(FakeContext())
        val ladder = Ladder(1920, 1080, 60, false, 12_000_000, "1080p60")
        controller.activeLadder = ladder
        controller.currentBitrate = 8_000_000
        val fakeEncoder = FakeEncoder()
        controller.encoder = fakeEncoder

        for (i in 1..5) {
            controller.handleBitrateAdaptation(0.001, 4.0)
        }
        assertEquals(5, controller.consecutiveGoodReports)

        controller.handleBitrateAdaptation(0.03, 4.0)
        assertEquals(0, controller.consecutiveGoodReports)
        val expectedBitrate = (8_000_000 * 0.9).toInt()
        assertEquals(expectedBitrate, controller.currentBitrate)
    }

    @Test
    fun testGetNextHigherLadder() {
        val controller = TestStream4kController(FakeContext())
        controller.probe = FakeCapabilitiesSource(
            supported = setOf(
                Triple(1920, 1080, 60),
                Triple(3840, 2160, 30),
                Triple(3840, 2160, 60)
            )
        )
        
        val l1080p60 = Ladder(1920, 1080, 60, false, 12_000_000, "1080p60 HEVC fallback")
        val l4k30 = Ladder(3840, 2160, 30, false, 25_000_000, "4K30 HEVC fallback")
        val l4k60 = Ladder(3840, 2160, 60, false, 35_000_000, "4K60 HEVC")
        
        assertEquals(l4k30.width, controller.getNextHigherLadder(l1080p60)?.width)
        assertEquals(l4k30.fps, controller.getNextHigherLadder(l1080p60)?.fps)
        
        assertEquals(l4k60.width, controller.getNextHigherLadder(l4k30)?.width)
        assertEquals(l4k60.fps, controller.getNextHigherLadder(l4k30)?.fps)
        
        assertNull(controller.getNextHigherLadder(l4k60))
    }

    @Test
    fun testStepUpBoundedByNegotiatedLadder() {
        val controller = TestStream4kController(FakeContext())
        controller.probe = FakeCapabilitiesSource(
            supported = setOf(
                Triple(1920, 1080, 60),
                Triple(3840, 2160, 30),
                Triple(3840, 2160, 60)
            )
        )
        
        val l1080p60 = Ladder(1920, 1080, 60, false, 12_000_000, "1080p60 HEVC fallback")
        val l4k30 = Ladder(3840, 2160, 30, false, 25_000_000, "4K30 HEVC fallback")
        
        controller.negotiatedLadder = l4k30
        controller.activeLadder = l1080p60
        controller.currentBitrate = l1080p60.bitrateBps
        
        val fakeEncoder = FakeEncoder()
        controller.encoder = fakeEncoder
        
        for (i in 1..10) {
            controller.handleBitrateAdaptation(0.001, 5.0)
        }
        
        Thread.sleep(200)
        
        assertEquals(l4k30.width, controller.activeLadder?.width)
        assertEquals(l4k30.fps, controller.activeLadder?.fps)
        
        controller.currentBitrate = l4k30.bitrateBps
        controller.consecutiveGoodReports = 0
        
        for (i in 1..10) {
            controller.handleBitrateAdaptation(0.001, 5.0)
        }
        Thread.sleep(200)
        
        assertEquals(l4k30.width, controller.activeLadder?.width)
        assertEquals(l4k30.fps, controller.activeLadder?.fps)
    }
}
