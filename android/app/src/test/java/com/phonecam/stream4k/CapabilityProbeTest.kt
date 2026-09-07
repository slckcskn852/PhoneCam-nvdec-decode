package com.phonecam.stream4k

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CapabilityProbeTest {
    private val combo4k60 = Triple(3840, 2160, 60)
    private val combo4k30 = Triple(3840, 2160, 30)
    private val combo1080p60 = Triple(1920, 1080, 60)
    private val allCombos = setOf(combo4k60, combo4k30, combo1080p60)

    @Test
    fun prefers4k60WhenAvailable() {
        val ladder = CapabilityProbe.chooseLadder(allCombos, hevcOk = true)

        assertNotNull(ladder)
        assertEquals(3840, ladder!!.width)
        assertEquals(2160, ladder.height)
        assertEquals(60, ladder.fps)
        assertEquals(35_000_000, ladder.bitrateBps)
        assertTrue(ladder.reason.isNotEmpty())
    }

    @Test
    fun fallsBackTo4k30When60Unavailable() {
        val ladder = CapabilityProbe.chooseLadder(setOf(combo4k30, combo1080p60), hevcOk = true)

        assertNotNull(ladder)
        assertEquals(3840, ladder!!.width)
        assertEquals(2160, ladder.height)
        assertEquals(30, ladder.fps)
        assertEquals(25_000_000, ladder.bitrateBps)
        assertTrue(ladder.reason.isNotEmpty())
    }

    @Test
    fun fallsBackTo1080p60When4kUnavailable() {
        val ladder = CapabilityProbe.chooseLadder(setOf(combo1080p60), hevcOk = true)

        assertNotNull(ladder)
        assertEquals(1920, ladder!!.width)
        assertEquals(1080, ladder.height)
        assertEquals(60, ladder.fps)
        assertEquals(12_000_000, ladder.bitrateBps)
        assertTrue(ladder.reason.isNotEmpty())
    }

    @Test
    fun returnsNullWhenHevcMissing() {
        assertNull(CapabilityProbe.chooseLadder(allCombos, hevcOk = false))
    }

    @Test
    fun returnsNullWhenNoComboMatches() {
        assertNull(CapabilityProbe.chooseLadder(emptySet(), hevcOk = true))
        assertNull(CapabilityProbe.chooseLadder(setOf(Triple(1280, 720, 30)), hevcOk = true))
    }

    @Test
    fun rejects60FpsConstrainedModeAndFallsBackToNormalSession() {
        val normalSession = setOf(combo4k30, combo1080p60)

        val ladder = CapabilityProbe.chooseLadder(allCombos, hevcOk = true, normalSessionSupported = normalSession)

        assertNotNull(ladder)
        assertEquals(30, ladder!!.fps)
        assertFalse(ladder.needsHighSpeedSession)
        assertTrue(ladder.reason.isNotEmpty())
    }

    @Test
    fun doesNotFlagHighSpeedSessionWhenComboWorksInNormalSession() {
        val ladder = CapabilityProbe.chooseLadder(allCombos, hevcOk = true, normalSessionSupported = allCombos)

        assertNotNull(ladder)
        assertFalse(ladder!!.needsHighSpeedSession)
    }

    @Test
    fun rejects1080p60WhenOnlyHighSpeed() {
        assertNull(CapabilityProbe.chooseLadder(setOf(combo1080p60), true, emptySet()))
    }

    @Test
    fun highFrameRateModesUseConstrainedSessions() {
        for (fps in listOf(120, 240)) {
            val mode = CapabilityProbe.chooseLadder(setOf(Triple(1920, 1080, fps)), true, emptySet())!!
            assertEquals(fps, mode.fps)
            assertTrue(mode.needsHighSpeedSession)
        }
    }

    @Test
    fun cameraAndEncoderMustAgreeBeforeAdvertisingMode() {
        val source = object : DeviceCapabilitiesSource {
            override fun supportedCombos() = allCombos + Triple(1920, 1080, 240)
            override fun normalSessionCombos() = allCombos
            override fun hasHevcEncoder() = true
            override fun hevcEncoderSupports(width: Int, height: Int, fps: Int) = width == 1920 && fps == 60
            override fun encoderNames() = listOf("test.encoder")
        }
        assertEquals(listOf(combo1080p60), source.availableLadders().map { it.combo })
    }

    @Test
    fun everyLadderHasNonEmptyReason() {
        listOf(allCombos, setOf(combo4k30), setOf(combo1080p60)).forEach { combos ->
            val ladder = CapabilityProbe.chooseLadder(combos, hevcOk = true)
            assertNotNull(ladder)
            assertTrue(ladder!!.reason.isNotBlank())
        }
    }
}
