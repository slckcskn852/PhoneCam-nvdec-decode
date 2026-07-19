package com.phonecam

internal enum class StreamProfile(
    val id: String,
    val label: String,
    val width: Int,
    val height: Int,
    val fps: Int,
    val bitrateBps: Int
) {
    EFFICIENT("efficient", "Efficient", 960, 540, 30, 1_200_000),
    BALANCED("balanced", "Balanced", 1280, 720, 30, 1_800_000),
    MOTION("motion", "Motion", 1280, 720, 60, 2_800_000);

    val summary: String
        get() = "$label: ${width}x$height @ ${fps} fps, ${bitrateBps / 1_000_000f} Mbps"

    companion object {
        val DEFAULT = EFFICIENT
        val MAX_BITRATE_BPS = entries.maxOf { it.bitrateBps }

        fun fromId(id: String?): StreamProfile {
            return entries.firstOrNull { it.id == id } ?: DEFAULT
        }
    }
}
