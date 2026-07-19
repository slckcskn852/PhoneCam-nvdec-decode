package com.phonecam

import org.junit.Assert.assertEquals
import org.junit.Test

class DiscoveryBeaconProtocolTest {
    @Test
    fun payloadMatchesReceiverContract() {
        val payload = DiscoveryBeaconProtocol.payload(
            rtspUrl = "rtsp://192.168.1.23:8554/",
            width = 1280,
            height = 720,
            fps = 60,
            bitrateBps = 2_800_000,
            deviceName = "Samsung S23 Ultra",
            pairingCode = "123456"
        )

        assertEquals(
            "PHONECAM|1|rtsp://192.168.1.23:8554/|1280|720|60|2800000|Samsung S23 Ultra|123456",
            payload
        )
    }

    @Test
    fun deviceNameCannotBreakPipeDelimitedPayload() {
        assertEquals(
            "Google Pixel 9 Pro",
            DiscoveryBeaconProtocol.sanitizeDeviceName("Google|Pixel 9|Pro")
        )
    }

    @Test
    fun blankDeviceNameFallsBackToAndroidPhone() {
        assertEquals("Android Phone", DiscoveryBeaconProtocol.sanitizeDeviceName("  |  "))
    }

    @Test
    fun pairingCodeUsesSixDigitsOnly() {
        assertEquals("123456", DiscoveryBeaconProtocol.sanitizePairingCode("12 34|56"))
        assertEquals("000042", DiscoveryBeaconProtocol.sanitizePairingCode("42"))
    }
}
