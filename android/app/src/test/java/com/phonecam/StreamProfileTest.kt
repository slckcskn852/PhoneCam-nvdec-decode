package com.phonecam

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamProfileTest {
    @Test
    fun defaultProfileKeepsBandwidthBelowOldLowSetting() {
        assertEquals(StreamProfile.EFFICIENT, StreamProfile.DEFAULT)
        assertTrue(StreamProfile.DEFAULT.bitrateBps < 3_000_000)
    }

    @Test
    fun presetsStayWithinWifiFirstMvpBudget() {
        assertTrue(StreamProfile.EFFICIENT.bitrateBps <= 1_200_000)
        assertTrue(StreamProfile.BALANCED.bitrateBps <= 1_800_000)
        assertTrue(StreamProfile.MOTION.bitrateBps <= 2_800_000)
        assertTrue(StreamProfile.MAX_BITRATE_BPS <= 2_800_000)
    }

    @Test
    fun unknownStoredProfileFallsBackToEfficient() {
        assertEquals(StreamProfile.EFFICIENT, StreamProfile.fromId("1080p60-old"))
    }
}
