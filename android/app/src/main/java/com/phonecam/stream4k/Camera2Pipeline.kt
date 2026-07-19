package com.phonecam.stream4k

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraConstrainedHighSpeedCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.view.Surface
import java.util.concurrent.Executor

/**
 * Camera2 capture pipeline that feeds the HEVC encoder input surface only
 * (no preview, no image reader). Uses a constrained high-speed capture
 * session when the chosen ladder requires one.
 */
class Camera2Pipeline(context: Context) {
    interface StateCallback {
        fun onStreamingStarted()
        fun onStreamingStopped()
        fun onError(message: String)
    }

    var stateCallback: StateCallback? = null

    private val cameraManager = context.getSystemService(CameraManager::class.java)
    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    @Volatile private var active = false

    // Caller verifies CAMERA permission before calling open().
    @SuppressLint("MissingPermission")
    @Synchronized
    fun open(ladder: Ladder, encoderSurface: Surface) {
        close()
        val manager = cameraManager
        if (manager == null) {
            stateCallback?.onError("CameraManager unavailable")
            return
        }
        val thread = HandlerThread("PhoneCam4kCamera").apply { start() }
        handlerThread = thread
        val cameraHandler = Handler(thread.looper)
        handler = cameraHandler
        val cameraId = findBackCameraId(manager)
        if (cameraId == null) {
            stateCallback?.onError("No back camera found")
            stopHandlerThread()
            return
        }
        try {
            active = true
            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    synchronized(this@Camera2Pipeline) {
                        if (!active) {
                            device.close()
                            return
                        }
                        cameraDevice = device
                    }
                    createSession(device, ladder, encoderSurface, cameraHandler)
                }

                override fun onDisconnected(device: CameraDevice) {
                    device.close()
                    stateCallback?.onError("Camera disconnected")
                    close()
                }

                override fun onError(device: CameraDevice, error: Int) {
                    device.close()
                    stateCallback?.onError("Camera error $error")
                    close()
                }
            }, cameraHandler)
        } catch (e: Exception) {
            active = false
            stateCallback?.onError("Camera open failed: ${e.message}")
            stopHandlerThread()
        }
    }

    @Synchronized
    fun close() {
        active = false
        try {
            captureSession?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Session close failed", e)
        }
        captureSession = null
        try {
            cameraDevice?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Camera close failed", e)
        }
        cameraDevice = null
        stopHandlerThread()
    }

    private fun stopHandlerThread() {
        handlerThread?.quitSafely()
        handlerThread = null
        handler = null
    }

    private fun createSession(device: CameraDevice, ladder: Ladder, surface: Surface, cameraHandler: Handler) {
        try {
            val request = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                addTarget(surface)
                set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(ladder.fps, ladder.fps))
            }.build()

            val sessionStateCallback = object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    synchronized(this@Camera2Pipeline) {
                        if (!active) {
                            session.close()
                            return
                        }
                        captureSession = session
                    }
                    startRepeating(session, ladder, request, cameraHandler)
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    stateCallback?.onError("Capture session configuration failed")
                    close()
                }

                override fun onClosed(session: CameraCaptureSession) {
                    stateCallback?.onStreamingStopped()
                }
            }

            if (ladder.needsHighSpeedSession) {
                if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.P) {
                    stateCallback?.onError("High-speed sessions require Android 9+")
                    close()
                    return
                }
                val configuration = SessionConfiguration(
                    SessionConfiguration.SESSION_HIGH_SPEED,
                    listOf(OutputConfiguration(surface)),
                    HandlerExecutor(cameraHandler),
                    sessionStateCallback
                )
                device.createCaptureSession(configuration)
            } else {
                @Suppress("DEPRECATION")
                device.createCaptureSession(listOf(surface), sessionStateCallback, cameraHandler)
            }
        } catch (e: Exception) {
            stateCallback?.onError("Capture session create failed: ${e.message}")
            close()
        }
    }

    private fun startRepeating(
        session: CameraCaptureSession,
        ladder: Ladder,
        request: CaptureRequest,
        cameraHandler: Handler
    ) {
        try {
            if (ladder.needsHighSpeedSession) {
                val highSpeedSession = session as CameraConstrainedHighSpeedCaptureSession
                val burst = highSpeedSession.createHighSpeedRequestList(request)
                highSpeedSession.setRepeatingBurst(burst, null, cameraHandler)
            } else {
                session.setRepeatingRequest(request, null, cameraHandler)
            }
            stateCallback?.onStreamingStarted()
        } catch (e: Exception) {
            stateCallback?.onError("Repeating request failed: ${e.message}")
            close()
        }
    }

    private fun findBackCameraId(manager: CameraManager): String? {
        return try {
            manager.cameraIdList.firstOrNull { cameraId ->
                val characteristics = manager.getCameraCharacteristics(cameraId)
                characteristics.get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK &&
                    characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) != null
            } ?: manager.cameraIdList.firstOrNull()
        } catch (e: Exception) {
            null
        }
    }

    private class HandlerExecutor(private val handler: Handler) : Executor {
        override fun execute(command: Runnable) {
            handler.post(command)
        }
    }

    companion object {
        private const val TAG = "Camera2Pipeline"
    }
}
