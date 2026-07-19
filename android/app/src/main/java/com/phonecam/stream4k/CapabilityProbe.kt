package com.phonecam.stream4k

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.MediaCodecList
import android.media.MediaFormat
import android.util.Log
import android.util.Size

/**
 * Decides the best 4K60-capable streaming ladder for this device.
 *
 * The decision itself ([chooseLadder]) is pure and unit-testable; all
 * framework access lives behind [DeviceCapabilitiesSource].
 */
data class Ladder(
    val width: Int,
    val height: Int,
    val fps: Int,
    val needsHighSpeedSession: Boolean,
    val bitrateBps: Int,
    val reason: String
) {
    val summary: String
        get() = "${width}x$height @ $fps fps HEVC, ${bitrateBps / 1_000_000f} Mbps" +
            if (needsHighSpeedSession) " (high-speed session)" else ""
}

/** Framework-facing capability queries, isolated so tests can stub them. */
interface DeviceCapabilitiesSource {
    /** All (width, height, fps) combos the camera can feed an encoder with. */
    fun supportedCombos(): Set<Triple<Int, Int, Int>>

    /** Combos reachable in a normal (non high-speed) capture session. */
    fun normalSessionCombos(): Set<Triple<Int, Int, Int>>

    /** True when at least one HEVC video encoder is present. */
    fun hasHevcEncoder(): Boolean

    /** True when some HEVC encoder claims support for this size/rate. */
    fun hevcEncoderSupports(width: Int, height: Int, fps: Int): Boolean

    fun encoderNames(): List<String>
}

object CapabilityProbe {
    private val CANDIDATES = listOf(
        Ladder(3840, 2160, 60, false, 35_000_000, "4K60 HEVC"),
        Ladder(3840, 2160, 30, false, 25_000_000, "4K30 HEVC fallback"),
        Ladder(1920, 1080, 60, false, 12_000_000, "1080p60 HEVC fallback")
    )

    /** Pure decision over camera combos; assumes every combo works in a normal session. */
    fun chooseLadder(supported: Set<Triple<Int, Int, Int>>, hevcOk: Boolean): Ladder? {
        return chooseLadder(supported, hevcOk, supported)
    }

    /**
     * Pure decision. [supported] is every reachable (w, h, fps) combo,
     * [normalSessionSupported] the subset usable without a high-speed session.
     */
    fun chooseLadder(
        supported: Set<Triple<Int, Int, Int>>,
        hevcOk: Boolean,
        normalSessionSupported: Set<Triple<Int, Int, Int>>
    ): Ladder? {
        if (!hevcOk) return null
        for (candidate in CANDIDATES) {
            val combo = Triple(candidate.width, candidate.height, candidate.fps)
            if (combo in supported) {
                val needsHighSpeed = combo !in normalSessionSupported
                return candidate.copy(
                    needsHighSpeedSession = needsHighSpeed,
                    reason = candidate.reason + if (needsHighSpeed) " via constrained high-speed session" else ""
                )
            }
        }
        return null
    }
}

/**
 * Probes Camera2 + MediaCodec once, caches the result, and renders a
 * human-readable report for the UI.
 */
class AndroidCapabilityProbe(context: Context) : DeviceCapabilitiesSource {
    private val cameraManager = context.getSystemService(CameraManager::class.java)

    @Volatile private var cachedLadder: Ladder? = null
    @Volatile private var cachedReport: String? = null
    @Volatile private var probed = false

    /** Cached probe result; null when no ladder is supported. Safe to call from any thread. */
    @Synchronized
    fun probe(): Ladder? {
        if (probed) return cachedLadder
        probed = true
        cachedLadder = try {
            val combos = supportedCombos()
            val hevcOk = hasHevcEncoder()
            val chosen = CapabilityProbe.chooseLadder(combos, hevcOk, normalSessionCombos())
            // Camera and encoder must agree; drop combos no encoder claims.
            if (chosen != null && !hevcEncoderSupports(chosen.width, chosen.height, chosen.fps)) {
                Log.w(TAG, "No HEVC encoder confirms ${chosen.summary}; keeping it as best effort")
            }
            chosen
        } catch (e: Exception) {
            Log.e(TAG, "Capability probe failed", e)
            null
        }
        cachedReport = buildReport(cachedLadder)
        return cachedLadder
    }

    fun report(): String {
        probe()
        return cachedReport ?: "4K60 UDP probe failed"
    }

    fun invalidate() {
        probed = false
        cachedLadder = null
        cachedReport = null
    }

    override fun supportedCombos(): Set<Triple<Int, Int, Int>> {
        val combos = mutableSetOf<Triple<Int, Int, Int>>()
        combos.addAll(normalSessionCombos())
        val map = backCameraConfigurationMap() ?: return combos
        try {
            for (size in map.highSpeedVideoSizes.orEmpty()) {
                for (range in map.getHighSpeedVideoFpsRangesFor(size).orEmpty()) {
                    if (range.upper >= 60) {
                        combos.add(Triple(size.width, size.height, range.upper))
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "High-speed size query failed", e)
        }
        return combos
    }

    override fun normalSessionCombos(): Set<Triple<Int, Int, Int>> {
        val combos = mutableSetOf<Triple<Int, Int, Int>>()
        val map = backCameraConfigurationMap() ?: return combos
        val sizes = try {
            map.getOutputSizes(android.media.MediaCodec::class.java).orEmpty().toList()
        } catch (e: Exception) {
            emptyList()
        }
        for (size in sizes) {
            val maxFps = normalSessionMaxFps(map, size) ?: continue
            if (maxFps >= 30) combos.add(Triple(size.width, size.height, 30))
            if (maxFps >= 60) combos.add(Triple(size.width, size.height, 60))
        }
        return combos
    }

    private fun normalSessionMaxFps(map: StreamConfigurationMap, size: Size): Int? {
        return try {
            val minFrameDurationNs = map.getOutputMinFrameDuration(android.media.MediaCodec::class.java, size)
            if (minFrameDurationNs <= 0L) {
                60
            } else {
                (1_000_000_000.0 / minFrameDurationNs).toInt()
            }
        } catch (e: Exception) {
            null
        }
    }

    override fun hasHevcEncoder(): Boolean {
        return hevcEncoderInfos().isNotEmpty()
    }

    override fun hevcEncoderSupports(width: Int, height: Int, fps: Int): Boolean {
        return hevcEncoderInfos().any { info ->
            try {
                val capabilities = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_HEVC)
                capabilities.videoCapabilities?.areSizeAndRateSupported(width, height, fps.toDouble()) == true
            } catch (e: Exception) {
                try {
                    val capabilities = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_HEVC)
                    capabilities.videoCapabilities?.isSizeSupported(width, height) == true
                } catch (e2: Exception) {
                    false
                }
            }
        }
    }

    override fun encoderNames(): List<String> {
        return hevcEncoderInfos().map { it.name }
    }

    private fun hevcEncoderInfos() = try {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, true) }
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun backCameraConfigurationMap(): StreamConfigurationMap? {
        val manager = cameraManager ?: return null
        return try {
            manager.cameraIdList.asSequence()
                .mapNotNull { cameraId ->
                    try {
                        val characteristics = manager.getCameraCharacteristics(cameraId)
                        if (characteristics.get(CameraCharacteristics.LENS_FACING) ==
                            CameraCharacteristics.LENS_FACING_BACK
                        ) {
                            characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                        } else {
                            null
                        }
                    } catch (e: Exception) {
                        null
                    }
                }
                .firstOrNull()
        } catch (e: Exception) {
            null
        }
    }

    private fun buildReport(ladder: Ladder?): String {
        val encoders = encoderNames()
        return if (ladder == null) {
            listOf(
                "4K60 UDP: unsupported on this device",
                "Needs 3840x2160@60/30 or 1920x1080@60 camera output plus an HEVC encoder.",
                "HEVC encoders: ${if (encoders.isEmpty()) "none" else encoders.joinToString()}"
            ).joinToString("\n")
        } else {
            listOf(
                "4K60 UDP: ${ladder.summary}",
                ladder.reason,
                "HEVC encoders: ${if (encoders.isEmpty()) "none" else encoders.joinToString()}"
            ).joinToString("\n")
        }
    }

    companion object {
        private const val TAG = "CapabilityProbe"
    }
}
