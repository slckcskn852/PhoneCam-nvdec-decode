package com.phonecam.stream4k

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JsonHelperTest {

    @Test
    fun testParseSimpleJson() {
        val json = "{\"version\":\"1.0\",\"type\":\"ping\"}"
        val parsed = JsonHelper.parse(json)
        assertEquals("1.0", parsed["version"])
        assertEquals("ping", parsed["type"])
    }

    @Test
    fun testParseConnectJson() {
        val json = "{\"version\":\"1.0\",\"type\":\"connect\",\"selected_ladder\":{\"width\":3840,\"height\":2160,\"fps\":60},\"transport\":\"udp\",\"stream_port\":5004}"
        val parsed = JsonHelper.parse(json)
        assertEquals("1.0", parsed["version"])
        assertEquals("connect", parsed["type"])
        assertEquals("udp", parsed["transport"])
        assertEquals(5004, parsed["stream_port"])
        
        val ladder = parsed["selected_ladder"] as? Map<*, *>
        assertTrue(ladder != null)
        assertEquals(3840, ladder?.get("width"))
        assertEquals(2160, ladder?.get("height"))
        assertEquals(60, ladder?.get("fps"))
    }

    @Test
    fun testParseFeedbackJson() {
        val json = "{\"version\":\"1.0\",\"type\":\"feedback\",\"loss_fraction\":0.015,\"jitter_ms\":4.5}"
        val parsed = JsonHelper.parse(json)
        assertEquals("1.0", parsed["version"])
        assertEquals("feedback", parsed["type"])
        assertEquals(0.015, parsed["loss_fraction"])
        assertEquals(4.5, parsed["jitter_ms"])
    }

    @Test
    fun testParseNackJson() {
        val json = "{\"version\":\"1.0\",\"type\":\"nack\",\"seqs\":[8001,8002]}"
        val parsed = JsonHelper.parse(json)
        assertEquals("nack", parsed["type"])
        val seqs = parsed["seqs"] as? List<*>
        assertTrue(seqs != null)
        assertEquals(2, seqs?.size)
        assertEquals(8001, seqs?.get(0))
        assertEquals(8002, seqs?.get(1))
    }
}
