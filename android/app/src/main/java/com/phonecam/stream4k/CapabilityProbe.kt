package com.phonecam.stream4k

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.util.Size

/** A mode belongs to one camera and encoder; never merge capabilities across lenses. */
data class Ladder(
    val width: Int,
    val height: Int,
    val fps: Int,
    val needsHighSpeedSession: Boolean,
    val bitrateBps: Int,
    val reason: String,
    val cameraId: String? = null,
    val encoderName: String? = null
) {
    val summary: String
        get() = "${width}x$height @ $fps fps HEVC, ${bitrateBps / 1_000_000f} Mbps" +
            if (needsHighSpeedSession) " (high-speed session)" else ""
    val combo: Triple<Int, Int, Int> get() = Triple(width, height, fps)
}

interface DeviceCapabilitiesSource {
    fun supportedCombos(): Set<Triple<Int, Int, Int>>
    fun normalSessionCombos(): Set<Triple<Int, Int, Int>>
    fun hasHevcEncoder(): Boolean
    fun hevcEncoderSupports(width: Int, height: Int, fps: Int): Boolean
    fun encoderNames(): List<String>
    fun availableLadders(): List<Ladder> {
        if (!hasHevcEncoder()) return emptyList()
        val supported = supportedCombos()
        val normal = normalSessionCombos()
        return CapabilityProbe.CANDIDATES.filter {
            it.combo in supported && (it.combo in normal || it.fps >= 120) &&
                hevcEncoderSupports(it.width, it.height, it.fps)
        }.map { it.copy(needsHighSpeedSession = it.combo !in normal) }
    }
}

object CapabilityProbe {
    // Default preference is resolution. A receiver can explicitly request any exposed mode.
    val CANDIDATES = listOf(
        Ladder(3840, 2160, 60, false, 35_000_000, "4K60 HEVC"),
        Ladder(3840, 2160, 30, false, 25_000_000, "4K30 HEVC fallback"),
        Ladder(1920, 1080, 240, true, 45_000_000, "1080p240 HEVC"),
        Ladder(1920, 1080, 120, true, 28_000_000, "1080p120 HEVC"),
        Ladder(1920, 1080, 60, false, 12_000_000, "1080p60 HEVC fallback"),
        Ladder(1920, 1080, 30, false, 8_000_000, "1080p30 HEVC fallback")
    )

    fun chooseLadder(supported: Set<Triple<Int, Int, Int>>, hevcOk: Boolean): Ladder? =
        chooseLadder(supported, hevcOk, supported)

    fun chooseLadder(
        supported: Set<Triple<Int, Int, Int>>,
        hevcOk: Boolean,
        normalSessionSupported: Set<Triple<Int, Int, Int>>
    ): Ladder? {
        if (!hevcOk) return null
        return CANDIDATES.firstOrNull {
            it.combo in supported && (it.combo in normalSessionSupported || it.fps >= 120)
        }?.let { it.copy(needsHighSpeedSession = it.combo !in normalSessionSupported) }
    }
}

/** Public Camera2 metadata only. OEM-only stock-camera modes cannot be assumed available. */
class AndroidCapabilityProbe(context: Context) : DeviceCapabilitiesSource {
    private val cameraManager = context.getSystemService(CameraManager::class.java)
    @Volatile private var cached: List<Ladder>? = null

    fun probe(): Ladder? = availableLadders().firstOrNull()
    fun invalidate() { synchronized(this) { cached = null } }

    @Synchronized
    override fun availableLadders(): List<Ladder> {
        cached?.let { return it }
        val result = mutableListOf<Ladder>()
        val manager = cameraManager ?: return emptyList()
        try {
            val cameras = manager.cameraIdList.mapNotNull { id ->
                try { id to manager.getCameraCharacteristics(id) } catch (_: Exception) { null }
            }.sortedBy { (_, info) ->
                if (info.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK) 0 else 1
            }
            for ((id, info) in cameras) {
                val map = info.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: continue
                val sizes = map.getOutputSizes(MediaCodec::class.java)?.toSet().orEmpty()
                val aeRanges = info.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES).orEmpty()
                val highSpeed = info.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)?.contains(
                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_CONSTRAINED_HIGH_SPEED_VIDEO
                ) == true
                for (candidate in CapabilityProbe.CANDIDATES) {
                    val size = Size(candidate.width, candidate.height)
                    val duration = if (size in sizes) {
                        try { map.getOutputMinFrameDuration(MediaCodec::class.java, size) } catch (_: Exception) { 0L }
                    } else 0L
                    // Unknown duration is not evidence of 60/120/240 FPS. Require a real
                    // duration and the exact fixed AE range used by the capture request.
                    val normal = duration > 0 && duration <= 1_000_000_000L / candidate.fps + 1 &&
                        aeRanges.any { it.lower == candidate.fps && it.upper == candidate.fps }
                    val constrained = !normal && candidate.fps >= 120 && highSpeed && try {
                        map.highSpeedVideoSizes?.contains(size) == true &&
                            map.getHighSpeedVideoFpsRangesFor(size).any {
                                it.lower == candidate.fps && it.upper == candidate.fps
                            }
                    } catch (_: Exception) { false }
                    if (!normal && !constrained) continue
                    val encoder = encoderFor(candidate) ?: continue
                    result += candidate.copy(
                        needsHighSpeedSession = constrained,
                        cameraId = id,
                        encoderName = encoder.name,
                        reason = "${candidate.reason}; camera $id; ${encoder.name}" +
                            if (constrained) "; public Camera2 constrained high-speed" else "; normal capture"
                    )
                }
            }
        } catch (error: Exception) {
            Log.w(TAG, "Camera capability scan failed", error)
        }
        // Preserve back-camera preference when multiple lenses expose the same mode.
        val sorted = result.distinctBy { it.combo }.sortedBy { mode ->
            CapabilityProbe.CANDIDATES.indexOfFirst { it.combo == mode.combo }
        }
        cached = sorted
        return sorted
    }

    override fun supportedCombos() = availableLadders().map { it.combo }.toSet()
    override fun normalSessionCombos() = availableLadders().filter { !it.needsHighSpeedSession }.map { it.combo }.toSet()
    override fun hasHevcEncoder() = encoderInfos().isNotEmpty()
    override fun hevcEncoderSupports(width: Int, height: Int, fps: Int) =
        encoderFor(Ladder(width, height, fps, false, 1, "probe")) != null
    override fun encoderNames() = encoderInfos().map { it.name }

    private fun encoderFor(mode: Ladder): MediaCodecInfo? = encoderInfos().firstOrNull { info ->
        try {
            val caps = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_HEVC)
            val hardware = if (Build.VERSION.SDK_INT >= 29) info.isHardwareAccelerated
                else !info.name.startsWith("OMX.google.") && !info.name.startsWith("c2.android.")
            (mode.fps <= 60 || hardware) &&
                caps.colorFormats.contains(MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface) &&
                caps.videoCapabilities?.areSizeAndRateSupported(mode.width, mode.height, mode.fps.toDouble()) == true
        } catch (_: Exception) { false }
    }

    private fun encoderInfos(): List<MediaCodecInfo> = try {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { info ->
            info.isEncoder && info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, true) }
        }.sortedBy { if (Build.VERSION.SDK_INT >= 29 && it.isHardwareAccelerated) 0 else 1 }
    } catch (_: Exception) { emptyList() }

    fun report(): String {
        val modes = availableLadders()
        return if (modes.isEmpty()) {
            "No supported HEVC stream mode exposed by Camera2 and MediaCodec. " +
                "Stock Samsung camera recording modes may be unavailable to other apps."
        } else {
            "Available camera/encoder modes (device verification required):\n" +
                modes.joinToString("\n") { "${it.summary} • camera ${it.cameraId}" }
        }
    }

    companion object { private const val TAG = "CapabilityProbe" }
}
