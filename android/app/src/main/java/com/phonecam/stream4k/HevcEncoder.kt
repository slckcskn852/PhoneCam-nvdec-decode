package com.phonecam.stream4k

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Bundle
import android.util.Log
import android.view.Surface

/**
 * Thin MediaCodec wrapper producing Annex-B HEVC access units from a Surface
 * input. Drains output on a dedicated thread and forwards each access unit to
 * [onAccessUnit]. MediaCodec HEVC output is Annex B de-facto; start-code
 * handling is left to [RtpHevcPacketizer.splitAnnexB].
 */
open class HevcEncoder {
    interface Callback {
        fun onAccessUnit(annexB: ByteArray, ptsUs: Long, isKeyFrame: Boolean)
        fun onError(message: String)
    }

    var callback: Callback? = null

    @Volatile var inputSurface: Surface? = null
        private set
    @Volatile private var ownsInputSurface = true
    @Volatile private var csd: ByteArray? = null
    @Volatile private var running = false
    private var codec: MediaCodec? = null
    private var drainThread: Thread? = null

    @Synchronized
    fun configure(
        width: Int,
        height: Int,
        bitrateBps: Int,
        fps: Int,
        iFrameIntervalSec: Int = 1,
        useCbr: Boolean = false,
        persistentInputSurface: Surface? = null,
        encoderName: String? = null
    ) {
        check(codec == null) { "HevcEncoder already configured" }
        val encoder = if (encoderName != null) MediaCodec.createByCodecName(encoderName) else createCodec(width, height, fps)
        codec = encoder
        try {
        val format = buildFormat(width, height, bitrateBps, fps, iFrameIntervalSec, useCbr, true)
        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        } catch (e: Exception) {
            // Some encoders reject an explicit profile/level. Retry without it.
            Log.w(TAG, "Encoder rejected profile/level, retrying without", e)
            encoder.reset()
            encoder.configure(
                buildFormat(width, height, bitrateBps, fps, iFrameIntervalSec, useCbr, false),
                null,
                null,
                MediaCodec.CONFIGURE_FLAG_ENCODE
            )
        }
        inputSurface = if (persistentInputSurface != null) {
            ownsInputSurface = false
            encoder.setInputSurface(persistentInputSurface)
            persistentInputSurface
        } else {
            ownsInputSurface = true
            encoder.createInputSurface()
        }
        } catch (error: Exception) {
            release()
            throw error
        }
    }

    @Synchronized
    fun start() {
        val encoder = codec ?: throw IllegalStateException("HevcEncoder not configured")
        encoder.start()
        running = true
        drainThread = Thread({ drainLoop(encoder) }, "PhoneCam4kEncoderDrain").apply {
            isDaemon = true
            start()
        }
    }

    @Synchronized
    fun stop() {
        running = false
        drainThread?.takeIf { it !== Thread.currentThread() }?.join()
        drainThread = null
        try {
            codec?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "MediaCodec stop failed", e)
        }
    }

    @Synchronized
    fun release() {
        if (drainThread != null) {
            stop()
        }
        try {
            codec?.release()
        } catch (e: Exception) {
            Log.w(TAG, "MediaCodec release failed", e)
        }
        codec = null
        if (ownsInputSurface) {
            inputSurface?.release()
        }
        inputSurface = null
        csd = null
    }

    open fun requestKeyFrame() {
        try {
            codec?.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
        } catch (e: Exception) {
            Log.w(TAG, "requestKeyFrame failed", e)
        }
    }

    open fun setBitrate(bitrateBps: Int) {
        try {
            codec?.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bitrateBps) })
        } catch (e: Exception) {
            Log.w(TAG, "setBitrate failed", e)
        }
    }

    private fun drainLoop(encoder: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        while (running) {
            val index = try {
                encoder.dequeueOutputBuffer(info, DRAIN_TIMEOUT_US)
            } catch (e: Exception) {
                if (running) callback?.onError("Encoder dequeue failed: ${e.message}")
                break
            }
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    // csd-0 carries VPS+SPS+PPS as one Annex-B blob.
                    val csdBuffer = encoder.outputFormat.getByteBuffer("csd-0")
                    if (csdBuffer != null) {
                        val bytes = ByteArray(csdBuffer.remaining())
                        csdBuffer.get(bytes)
                        csd = bytes
                    }
                }
                index >= 0 -> {
                    val buffer = try {
                        encoder.getOutputBuffer(index)
                    } catch (e: Exception) {
                        null
                    }
                    try {
                        if (buffer != null && info.size > 0) {
                            val bytes = ByteArray(info.size)
                            buffer.position(info.offset)
                            buffer.get(bytes, 0, info.size)
                            handleOutputBuffer(bytes, info)
                        }
                    } catch (error: Exception) {
                        if (running) callback?.onError("Encoder output failed: ${error.message}")
                    } finally {
                        try {
                            encoder.releaseOutputBuffer(index, false)
                        } catch (error: Exception) {
                            if (running) callback?.onError("Encoder buffer release failed: ${error.message}")
                        }
                    }
                }
            }
        }
    }

    private fun handleOutputBuffer(bytes: ByteArray, info: MediaCodec.BufferInfo) {
        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
            // Codec-config-only buffer: store and skip.
            csd = bytes
            return
        }
        val isKeyFrame = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
        val storedCsd = csd
        val accessUnit = if (isKeyFrame && storedCsd != null) {
            ByteArray(storedCsd.size + bytes.size).also { merged ->
                System.arraycopy(storedCsd, 0, merged, 0, storedCsd.size)
                System.arraycopy(bytes, 0, merged, storedCsd.size, bytes.size)
            }
        } else {
            bytes
        }
        callback?.onAccessUnit(accessUnit, info.presentationTimeUs, isKeyFrame)
    }

    private fun buildFormat(
        width: Int,
        height: Int,
        bitrateBps: Int,
        fps: Int,
        iFrameIntervalSec: Int,
        useCbr: Boolean,
        withProfileLevel: Boolean
    ): MediaFormat {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_HEVC, width, height)
        format.setInteger(
            MediaFormat.KEY_COLOR_FORMAT,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
        )
        format.setInteger(MediaFormat.KEY_BIT_RATE, bitrateBps)
        format.setInteger(MediaFormat.KEY_FRAME_RATE, fps)
        format.setInteger(MediaFormat.KEY_OPERATING_RATE, fps)
        if (android.os.Build.VERSION.SDK_INT >= 29) format.setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, iFrameIntervalSec)
        format.setInteger(
            MediaFormat.KEY_BITRATE_MODE,
            if (useCbr) {
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
            } else {
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR
            }
        )
        format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
        format.setInteger(MediaFormat.KEY_PRIORITY, 0)
        format.setInteger(MediaFormat.KEY_LATENCY, 0)
        if (withProfileLevel) {
            format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.HEVCProfileMain)
            format.setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.HEVCMainTierLevel52)
        }
        return format
    }

    private fun createCodec(width: Int, height: Int, fps: Int): MediaCodec {
        try {
            val infos = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            for (info in infos) {
                if (!info.isEncoder || !info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, true) }) {
                    continue
                }
                val supported = try {
                    val capabilities = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_HEVC)
                    capabilities.videoCapabilities?.areSizeAndRateSupported(width, height, fps.toDouble()) == true
                } catch (e: Exception) {
                    false
                }
                if (supported) {
                    Log.i(TAG, "Using HEVC encoder ${info.name} for ${width}x$height@$fps")
                    return MediaCodec.createByCodecName(info.name)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Encoder scan failed, falling back to default", e)
        }
        throw IllegalStateException("No HEVC surface encoder supports ${width}x$height@$fps")
    }

    companion object {
        private const val TAG = "HevcEncoder"
        private const val DRAIN_TIMEOUT_US = 10_000L
    }
}
