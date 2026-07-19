package com.phonecam

internal object DiscoveryBeaconProtocol {
    const val PORT = 47821
    const val INTERVAL_MS = 1_000L
    const val BROADCAST_ADDRESS = "255.255.255.255"

    private const val MAGIC = "PHONECAM"
    private const val VERSION = 1

    fun payload(
        rtspUrl: String,
        width: Int,
        height: Int,
        fps: Int,
        bitrateBps: Int,
        deviceName: String,
        pairingCode: String
    ): String {
        return listOf(
            MAGIC,
            VERSION.toString(),
            rtspUrl,
            width.toString(),
            height.toString(),
            fps.toString(),
            bitrateBps.toString(),
            sanitizeDeviceName(deviceName),
            sanitizePairingCode(pairingCode)
        ).joinToString("|")
    }

    fun sanitizeDeviceName(deviceName: String): String {
        return deviceName.replace('|', ' ').trim().ifEmpty { "Android Phone" }
    }

    fun sanitizePairingCode(pairingCode: String): String {
        return pairingCode.filter { it.isDigit() }.take(6).padStart(6, '0')
    }
}
