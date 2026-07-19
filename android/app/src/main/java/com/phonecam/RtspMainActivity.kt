package com.phonecam

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Build.MANUFACTURER
import android.os.Build.MODEL
import android.view.ScaleGestureDetector
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.RadioGroup
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import com.phonecam.stream4k.Stream4kController
import com.pedro.common.ConnectChecker
import com.pedro.encoder.input.sources.audio.NoAudioSource
import com.pedro.encoder.input.sources.video.Camera1Source
import com.pedro.encoder.input.sources.video.Camera2Source
import com.pedro.encoder.input.video.CameraHelper
import com.pedro.library.util.BitrateAdapter
import com.pedro.library.view.TakePhotoCallback
import com.pedro.rtspserver.RtspServerStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.LinkedHashSet
import java.util.Locale

class RtspMainActivity : AppCompatActivity(), ConnectChecker {
    private lateinit var prefs: SharedPreferences
    private lateinit var rtspServerStream: RtspServerStream

    private lateinit var connectionPage: View
    private lateinit var previewPage: View
    private lateinit var urlText: TextView
    private lateinit var pairingCodeText: TextView
    private lateinit var statusText: TextView
    private lateinit var previewBadgeText: TextView
    private lateinit var streamHeadlineText: TextView
    private lateinit var streamStatusText: TextView
    private lateinit var profileSummaryText: TextView
    private lateinit var zoomLabel: TextView
    private lateinit var startBtn: Button
    private lateinit var disconnectBtn: Button
    private lateinit var switchCameraBtn: Button
    private lateinit var rotateCounterClockwiseBtn: Button
    private lateinit var rotateStreamBtn: Button
    private lateinit var diagnosticsToggleBtn: Button
    private lateinit var profileGroup: RadioGroup
    private lateinit var previewSurfaceView: SurfaceView
    private lateinit var statusPanel: View
    private lateinit var blackoutOverlay: View
    private lateinit var stream4kCapabilityText: TextView
    private lateinit var stream4kTargetIpEdit: EditText
    private lateinit var stream4kTargetPortEdit: EditText
    private lateinit var stream4kToggleBtn: Button
    private lateinit var stream4kStatsText: TextView
    private lateinit var stream4kController: Stream4kController
    private var stream4kRunning = false
    private var lastReceiverIp: String? = null

    private val uiHandler = Handler(Looper.getMainLooper())
    private var blackoutRunnable: Runnable? = null
    private var originalBrightness: Float = -1f

    private var currentProfile = StreamProfile.DEFAULT
    private var currentCameraFacing = CameraHelper.Facing.BACK
    private var currentZoom = 1.0f
    private var backCameraRotationCorrectionDegrees = 0
    private var frontCameraRotationCorrectionDegrees = 0
    private var maxZoom = 1.0f
    private var minZoom = 1.0f
    private var isPrepared = false
    private var isSurfaceReady = false
    private var previewFrameSeen = false
    private var previewFrameProbePending = false
    private var previewProbeTimedOut = false
    private var previewProbeTimeoutRunnable: Runnable? = null
    private var pendingStart = false
    private var connectionState = "Waiting for receiver"
    private var latestBitrateBps: Long? = null
    private var pairingCode = ""
    private var diagnosticsVisible = false
    @Volatile private var discoveryBeaconRunning = false
    private var discoveryBeaconThread: Thread? = null
    private var displayManager: DisplayManager? = null

    private lateinit var scaleGestureDetector: ScaleGestureDetector

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = Unit
        override fun onDisplayRemoved(displayId: Int) = Unit

        override fun onDisplayChanged(displayId: Int) {
            uiHandler.post { handleOrientationInputsChanged() }
        }
    }

    private val bitrateAdapter = BitrateAdapter { bitrate ->
        rtspServerStream.setVideoBitrateOnFly(bitrate)
    }

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            statusText.text = "Ready. Start the camera server. Windows can use the URL or --auto-discover."
        } else {
            statusText.text = "Camera permission is required."
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_rtsp)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        prefs = getSharedPreferences("phonecam_prefs", Context.MODE_PRIVATE)
        loadPreferences()

        connectionPage = findViewById(R.id.connectionPage)
        previewPage = findViewById(R.id.previewPage)
        urlText = findViewById(R.id.rtspUrlText)
        pairingCodeText = findViewById(R.id.pairingCodeText)
        statusText = findViewById(R.id.statusText)
        previewBadgeText = findViewById(R.id.previewBadgeText)
        streamHeadlineText = findViewById(R.id.streamHeadlineText)
        streamStatusText = findViewById(R.id.streamStatusText)
        profileSummaryText = findViewById(R.id.profileSummaryText)
        zoomLabel = findViewById(R.id.zoomLabel)
        startBtn = findViewById(R.id.connectBtn)
        disconnectBtn = findViewById(R.id.disconnectBtn)
        switchCameraBtn = findViewById(R.id.switchCameraBtn)
        rotateCounterClockwiseBtn = findViewById(R.id.rotateCounterClockwiseBtn)
        rotateStreamBtn = findViewById(R.id.rotateStreamBtn)
        diagnosticsToggleBtn = findViewById(R.id.diagnosticsToggleBtn)
        profileGroup = findViewById(R.id.profileGroup)
        previewSurfaceView = findViewById(R.id.cameraPreview)
        statusPanel = findViewById(R.id.statusPanel)
        blackoutOverlay = findViewById(R.id.blackoutOverlay)
        stream4kCapabilityText = findViewById(R.id.stream4kCapabilityText)
        stream4kTargetIpEdit = findViewById(R.id.stream4kTargetIpEdit)
        stream4kTargetPortEdit = findViewById(R.id.stream4kTargetPortEdit)
        stream4kToggleBtn = findViewById(R.id.stream4kToggleBtn)
        stream4kStatsText = findViewById(R.id.stream4kStatsText)

        rtspServerStream = createRtspServerStream()
        displayManager = getSystemService(DisplayManager::class.java)
        displayManager?.registerDisplayListener(displayListener, uiHandler)

        configureBitrateAdapter()
        setupControls()
        setupStream4kControls()
        setupPreviewSurface()
        updateRtspUrl()
        updatePairingCode()

        blackoutOverlay.setOnClickListener { cancelBlackout() }

        if (hasCameraPermission()) {
            statusText.text = "Ready. Start the camera server. Windows can use the URL or --auto-discover."
        } else {
            statusText.text = "Camera permission required."
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private fun setupControls() {
        updateProfileSummary()
        profileGroup.check(profileToViewId(currentProfile))
        profileGroup.setOnCheckedChangeListener { _, checkedId ->
            if (rtspServerStream.isStreaming) {
                Toast.makeText(this, "Stop streaming before changing quality", Toast.LENGTH_SHORT).show()
                profileGroup.check(profileToViewId(currentProfile))
                return@setOnCheckedChangeListener
            }
            currentProfile = viewIdToProfile(checkedId)
            savePreferences()
            configureBitrateAdapter()
            updateProfileSummary()
            if (isPrepared) {
                reprepareStream()
            }
        }

        scaleGestureDetector = ScaleGestureDetector(this, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val source = rtspServerStream.videoSource
                if (source is Camera2Source) {
                    try {
                        val zoomRange = source.getZoomRange()
                        minZoom = zoomRange.lower ?: 1.0f
                        maxZoom = zoomRange.upper ?: 1.0f
                        currentZoom = (source.getZoom() * detector.scaleFactor).coerceIn(minZoom, maxZoom)
                        source.setZoom(currentZoom)
                        zoomLabel.text = String.format(Locale.US, "Zoom: %.1fx", currentZoom)
                    } catch (_: Exception) {
                        zoomLabel.text = "Zoom unavailable"
                    }
                }
                return true
            }
        })

        previewPage.setOnTouchListener { _, event ->
            scaleGestureDetector.onTouchEvent(event)
            true
        }

        startBtn.setOnClickListener {
            if (!hasCameraPermission()) {
                permissionLauncher.launch(Manifest.permission.CAMERA)
                return@setOnClickListener
            }
            startStreaming()
        }

        disconnectBtn.setOnClickListener {
            stopStreaming()
            showConnectionPage()
        }

        switchCameraBtn.setOnClickListener {
            switchCameraSafely()
        }

        rotateCounterClockwiseBtn.setOnClickListener {
            rotateStreamCorrection(-90)
        }

        rotateStreamBtn.setOnClickListener {
            rotateStreamCorrection(90)
        }

        diagnosticsToggleBtn.setOnClickListener {
            diagnosticsVisible = !diagnosticsVisible
            updateDiagnosticsVisibility()
        }
    }

    private fun setupStream4kControls() {
        stream4kController = Stream4kController(applicationContext).apply {
            listener = object : Stream4kController.Listener {
                override fun onStatus(message: String) {
                    runOnUiThread {
                        if (::stream4kStatsText.isInitialized) {
                            stream4kStatsText.text = message
                        }
                        stream4kRunning = isStreaming()
                        updateStream4kToggleButton()
                    }
                }
            }
            startControlListener()
        }
        prefillStream4kTarget()

        stream4kToggleBtn.setOnClickListener {
            if (stream4kRunning || stream4kController.isStreaming()) {
                stream4kController.stopStreaming()
                stream4kRunning = false
                updateStream4kToggleButton()
                stream4kStatsText.text = "4K UDP stopped."
                return@setOnClickListener
            }
            if (!hasCameraPermission()) {
                permissionLauncher.launch(Manifest.permission.CAMERA)
                return@setOnClickListener
            }
            val ip = stream4kTargetIpEdit.text.toString().trim().ifEmpty {
                stream4kController.lastPeerAddress?.hostAddress ?: lastReceiverIp ?: ""
            }
            if (ip.isEmpty()) {
                stream4kStatsText.text = "4K UDP needs a receiver IP address."
                return@setOnClickListener
            }
            val port = stream4kTargetPortEdit.text.toString().toIntOrNull()
                ?: Stream4kController.DEFAULT_STREAM_PORT
            stream4kStatsText.text = "4K UDP starting..."
            Thread({
                val ladder = stream4kController.probeLadder()
                if (ladder == null) {
                    runOnUiThread {
                        stream4kStatsText.text = "4K UDP unsupported on this device."
                    }
                    return@Thread
                }
                val started = stream4kController.start(ladder, ip, port)
                runOnUiThread {
                    stream4kRunning = started
                    updateStream4kToggleButton()
                    stream4kStatsText.text = if (started) {
                        "4K UDP streaming to $ip:$port (${ladder.summary})"
                    } else {
                        "4K UDP start failed."
                    }
                }
            }, "PhoneCam4kStart").apply {
                isDaemon = true
                start()
            }
        }
    }

    private fun updateStream4kToggleButton() {
        stream4kToggleBtn.text = if (stream4kRunning) "Stop 4K60 UDP" else "Start 4K60 UDP"
    }

    private fun prefillStream4kTarget() {
        val candidate = stream4kController.lastPeerAddress?.hostAddress ?: lastReceiverIp
        if (!candidate.isNullOrBlank() && stream4kTargetIpEdit.text.isBlank()) {
            stream4kTargetIpEdit.setText(candidate)
        }
        if (stream4kTargetPortEdit.text.isBlank()) {
            stream4kTargetPortEdit.setText(Stream4kController.DEFAULT_STREAM_PORT.toString())
        }
    }

    private fun refreshStream4kCapabilityReport() {
        Thread({
            val report = stream4kController.capabilityReport()
            runOnUiThread {
                if (::stream4kCapabilityText.isInitialized) {
                    stream4kCapabilityText.text = report
                }
            }
        }, "PhoneCam4kProbe").apply {
            isDaemon = true
            start()
        }
    }

    private fun setupPreviewSurface() {
        previewSurfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                isSurfaceReady = true
                rtspServerStream.getGlInterface().setPreviewResolution(
                    previewSurfaceView.width,
                    previewSurfaceView.height
                )
                if (!rtspServerStream.isOnPreview && isPrepared) {
                    startPreviewSurface()
                }
                if (pendingStart) {
                    prepareStream()
                    startStreamingNow()
                }
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                rtspServerStream.getGlInterface().setPreviewResolution(width, height)
                restartPreviewForSurfaceChange()
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                isSurfaceReady = false
                previewFrameSeen = false
                previewProbeTimedOut = false
                cancelPreviewFrameProbe()
                if (rtspServerStream.isOnPreview) {
                    rtspServerStream.stopPreview()
                }
            }
        })

        if (previewSurfaceView.holder.surface.isValid) {
            isSurfaceReady = true
            rtspServerStream.getGlInterface().setPreviewResolution(
                previewSurfaceView.width,
                previewSurfaceView.height
            )
        }
    }

    private fun profileToViewId(profile: StreamProfile): Int {
        return when (profile) {
            StreamProfile.EFFICIENT -> R.id.profileEfficient
            StreamProfile.BALANCED -> R.id.profileBalanced
            StreamProfile.MOTION -> R.id.profileMotion
        }
    }

    private fun viewIdToProfile(viewId: Int): StreamProfile {
        return when (viewId) {
            R.id.profileBalanced -> StreamProfile.BALANCED
            R.id.profileMotion -> StreamProfile.MOTION
            else -> StreamProfile.EFFICIENT
        }
    }

    private fun configureBitrateAdapter() {
        bitrateAdapter.setMaxBitrate(currentProfile.bitrateBps)
    }

    private fun updateProfileSummary() {
        profileSummaryText.text = currentProfile.summary
    }

    private fun updateCameraFacingFromSource() {
        currentCameraFacing = when (val source = rtspServerStream.videoSource) {
            is Camera1Source -> source.getCameraFacing()
            is Camera2Source -> source.getCameraFacing()
            else -> currentCameraFacing
        }
    }

    private fun switchCameraSafely() {
        try {
            when (val source = rtspServerStream.videoSource) {
                is Camera1Source -> source.switchCamera()
                is Camera2Source -> source.switchCamera()
                else -> return
            }
            updateCameraFacingFromSource()
            applyCameraTextureOrientation()
            applyLandscapeStreamRotationCorrection()
            currentZoom = 1.0f
            restartPreviewForSurfaceChange()
            updateStreamStatusText()
        } catch (e: Exception) {
            Toast.makeText(this, "Camera switch failed: ${e.message}", Toast.LENGTH_SHORT).show()
            restartPreviewForSurfaceChange()
        }
    }

    private fun restartPreviewForSurfaceChange() {
        if (!isPrepared || !isSurfaceReady) return
        try {
            applyCameraTextureOrientation()
            applyLandscapeStreamRotationCorrection()
            if (rtspServerStream.isOnPreview) {
                rtspServerStream.stopPreview()
            }
            startPreviewSurface()
            updateZoomLabel()
        } catch (e: Exception) {
            streamStatusText.text = "Preview restart failed: ${e.message}"
        }
    }

    private fun startPreviewSurface() {
        rtspServerStream.startPreview(previewSurfaceView)
        updateStreamStatusText()
        requestPreviewFrameProbe()
    }

    private fun requestPreviewFrameProbe() {
        if (previewFrameProbePending || !rtspServerStream.isOnPreview) return
        previewFrameProbePending = true
        schedulePreviewFrameProbeTimeout()
        try {
            rtspServerStream.getGlInterface().takePhoto(object : TakePhotoCallback {
                override fun onTakePhoto(bitmap: android.graphics.Bitmap) {
                    uiHandler.post {
                        cancelPreviewFrameProbeTimeout()
                        previewFrameProbePending = false
                        if (rtspServerStream.isOnPreview && isSurfaceReady && !previewFrameSeen) {
                            previewFrameSeen = true
                            previewProbeTimedOut = false
                            updateStreamStatusText()
                        }
                        bitmap.recycle()
                    }
                }
            })
        } catch (_: Exception) {
            previewFrameProbePending = false
            cancelPreviewFrameProbeTimeout()
            retryPreviewFrameProbe()
        }
    }

    private fun schedulePreviewFrameProbeTimeout() {
        cancelPreviewFrameProbeTimeout()
        previewProbeTimeoutRunnable = Runnable {
            if (!previewFrameProbePending) return@Runnable
            previewFrameProbePending = false
            previewProbeTimedOut = true
            updateStreamStatusText()
            retryPreviewFrameProbe()
        }
        uiHandler.postDelayed(previewProbeTimeoutRunnable!!, PREVIEW_FRAME_PROBE_TIMEOUT_MS)
    }

    private fun cancelPreviewFrameProbe() {
        previewFrameProbePending = false
        cancelPreviewFrameProbeTimeout()
    }

    private fun cancelPreviewFrameProbeTimeout() {
        previewProbeTimeoutRunnable?.let { uiHandler.removeCallbacks(it) }
        previewProbeTimeoutRunnable = null
    }

    private fun retryPreviewFrameProbe() {
        if (!rtspServerStream.isOnPreview || !isSurfaceReady || previewFrameSeen) return
        uiHandler.postDelayed({ requestPreviewFrameProbe() }, PREVIEW_FRAME_PROBE_RETRY_MS)
    }

    private fun prepareStream() {
        if (isPrepared) return
        val profile = currentProfile
        val encoderRotation = landscapeStreamRotation()
        val videoPrepared = try {
            rtspServerStream.prepareVideo(
                profile.width,
                profile.height,
                profile.bitrateBps,
                fps = profile.fps,
                iFrameInterval = 1,
                rotation = encoderRotation
            )
        } catch (e: IllegalArgumentException) {
            statusText.text = "Video configuration failed: ${e.message}"
            false
        }

        if (videoPrepared) {
            applyCameraTextureOrientation()
            applyLandscapeStreamRotationCorrection()
        }

        isPrepared = videoPrepared && try {
            // StreamBase always starts its audio encoder. NoAudioSource keeps
            // microphone access disabled while allowing video-only RTSP startup.
            rtspServerStream.prepareAudio(
                sampleRate = 44_100,
                isStereo = false,
                bitrate = 64 * 1024,
                echoCanceler = false,
                noiseSuppressor = false
            )
        } catch (e: IllegalArgumentException) {
            statusText.text = "Video-only audio stub failed: ${e.message}"
            false
        }

        if (isPrepared && isSurfaceReady && !rtspServerStream.isOnPreview) {
            startPreviewSurface()
            updateCameraFacingFromSource()
        }
    }

    private fun reprepareStream() {
        if (rtspServerStream.isOnPreview) {
            rtspServerStream.stopPreview()
        }
        rtspServerStream.release()
        isPrepared = false
        rtspServerStream = createRtspServerStream()
        prepareStream()
        updateRtspUrl()
    }

    private fun startStreaming() {
        pendingStart = true
        previewFrameSeen = false
        previewProbeTimedOut = false
        showPreviewPage()
        if (isSurfaceReady) {
            prepareStream()
            if (!isPrepared) return
            startStreamingNow()
        } else {
            streamStatusText.text = "Waiting for camera preview surface..."
        }
    }

    private fun startStreamingNow() {
        if (!pendingStart) return
        if (!isPrepared) {
            streamStatusText.text = "Camera encoder is not ready."
            return
        }
        pendingStart = false

        if (!rtspServerStream.isOnPreview && isSurfaceReady) {
            startPreviewSurface()
            updateZoomLabel()
        }

        if (!rtspServerStream.isStreaming) {
            rtspServerStream.startStream()
            startDiscoveryBeacon()
            cancelBlackout()
            val url = buildRtspUrl()
            connectionState = "Waiting for receiver"
            latestBitrateBps = null
            updateStreamStatusText()
            statusText.text = "Streaming: $url. ${currentProfile.summary}. Discovery beacon active."
        }
    }

    private fun updateStreamStatusText() {
        streamHeadlineText.text = streamHeadlineLine()
        streamStatusText.text = streamStatusLine()
        previewBadgeText.text = previewBadgeLine()
        previewBadgeText.setTextColor(if (previewFrameSeen) PREVIEW_LIVE_COLOR else PREVIEW_STARTING_COLOR)
    }

    private fun streamStatusLine(): String {
        val status = currentStreamStatus()
        return listOf(
            "Streaming: ${buildRtspUrl()}",
            currentProfile.summary,
            "Camera: ${status.cameraName}",
            "Preview: ${status.previewState}",
            "RootEncoder rotation: ${cameraTextureRotationDegrees()} deg",
            cameraDiagnosticsLine(),
            "Pairing code: $pairingCode",
            "Output rotation: ${effectiveStreamRotationCorrection()} deg",
            "Connection: $connectionState",
            status.bitrateLine,
            "Discovery beacon active"
        ).joinToString("\n")
    }

    private fun streamHeadlineLine(): String {
        val status = currentStreamStatus()
        return listOf(
            "Preview: ${status.previewState}",
            "Camera: ${status.cameraName}",
            "Output rotation: ${effectiveStreamRotationCorrection()} deg",
            "Pairing code: $pairingCode"
        ).joinToString(" | ")
    }

    private fun previewBadgeLine(): String {
        return when {
            previewFrameSeen -> "PREVIEW LIVE"
            previewProbeTimedOut -> "PREVIEW CHECKING"
            else -> "PREVIEW STARTING"
        }
    }

    private fun currentStreamStatus(): StreamStatus {
        val cameraName = if (currentCameraFacing == CameraHelper.Facing.FRONT) "Front" else "Back"
        val bitrateLine = latestBitrateBps?.let { bitrate ->
            String.format(Locale.US, "Live bitrate: %.1f Mbps", bitrate / 1_000_000f)
        } ?: "Live bitrate: waiting"
        val previewState = when {
            previewFrameSeen -> "live"
            !isSurfaceReady -> "waiting for surface"
            previewProbeTimedOut -> "not confirmed"
            previewFrameProbePending -> "starting"
            else -> "starting"
        }
        return StreamStatus(cameraName, previewState, bitrateLine)
    }

    private fun stopStreaming() {
        pendingStart = false
        cancelBlackout()
        if (rtspServerStream.isStreaming) {
            rtspServerStream.stopStream()
        }
        releaseCameraSessionForStop()
        stopDiscoveryBeacon()
        connectionState = "Stopped"
        latestBitrateBps = null
        statusText.text = "Stopped. Start the camera server when ready."
        streamStatusText.text = ""
    }

    private fun releaseCameraSessionForStop() {
        if (rtspServerStream.isOnPreview) {
            rtspServerStream.stopPreview()
        }
        rtspServerStream.release()
        rtspServerStream = createRtspServerStream()
        configureBitrateAdapter()
        isPrepared = false
        previewFrameSeen = false
        previewProbeTimedOut = false
        cancelPreviewFrameProbe()
        currentZoom = 1.0f
        currentCameraFacing = CameraHelper.Facing.BACK
        updateRtspUrl()
    }

    private fun showConnectionPage() {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        WindowCompat.setDecorFitsSystemWindows(window, true)
        connectionPage.visibility = View.VISIBLE
        previewPage.visibility = View.GONE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
    }

    private fun showPreviewPage() {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        diagnosticsVisible = false
        connectionPage.visibility = View.GONE
        previewPage.visibility = View.VISIBLE
        updateDiagnosticsVisibility()
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        }
        originalBrightness = window.attributes.screenBrightness
    }

    private fun updateDiagnosticsVisibility() {
        if (::statusPanel.isInitialized) {
            statusPanel.visibility = if (diagnosticsVisible) View.VISIBLE else View.GONE
        }
        if (::diagnosticsToggleBtn.isInitialized) {
            diagnosticsToggleBtn.text = if (diagnosticsVisible) "Hide" else "Info"
        }
    }

    private fun scheduleBlackout() {
        blackoutRunnable?.let { uiHandler.removeCallbacks(it) }
        blackoutRunnable = Runnable { showBlackoutOverlay() }
        uiHandler.postDelayed(blackoutRunnable!!, BLACKOUT_DELAY_MS)
    }

    private fun cancelBlackout() {
        blackoutRunnable?.let { uiHandler.removeCallbacks(it) }
        blackoutRunnable = null
        blackoutOverlay.visibility = View.GONE
        val lp = window.attributes
        lp.screenBrightness = originalBrightness
        window.attributes = lp
    }

    private fun showBlackoutOverlay() {
        val lp = window.attributes
        lp.screenBrightness = 0.01f
        window.attributes = lp
        blackoutOverlay.visibility = View.VISIBLE
    }

    private fun updateRtspUrl() {
        urlText.text = buildRtspUrl()
    }

    private fun buildRtspUrl(): String {
        return "rtsp://${getLocalIpAddress()}:$RTSP_PORT/"
    }

    private fun startDiscoveryBeacon() {
        if (discoveryBeaconRunning) return
        discoveryBeaconRunning = true
        discoveryBeaconThread = Thread({
            try {
                DatagramSocket().use { socket ->
                    socket.broadcast = true
                    while (discoveryBeaconRunning) {
                        val payload = buildDiscoveryPayload().toByteArray(StandardCharsets.UTF_8)
                        val targets = getDiscoveryTargets()
                        try {
                            targets.forEach { target ->
                                val packet = DatagramPacket(payload, payload.size, target, DiscoveryBeaconProtocol.PORT)
                                socket.send(packet)
                            }
                            Thread.sleep(DiscoveryBeaconProtocol.INTERVAL_MS)
                        } catch (_: InterruptedException) {
                            break
                        } catch (_: Exception) {
                            // Discovery is best-effort. The visible RTSP URL remains usable.
                            try {
                                Thread.sleep(DiscoveryBeaconProtocol.INTERVAL_MS)
                            } catch (_: InterruptedException) {
                                break
                            }
                        }
                    }
                }
            } catch (_: Exception) {
                // If UDP broadcast is unavailable, manual RTSP URL entry still works.
            }
        }, "PhoneCamDiscoveryBeacon").apply {
            isDaemon = true
            start()
        }
    }

    private fun stopDiscoveryBeacon() {
        discoveryBeaconRunning = false
        discoveryBeaconThread?.interrupt()
        discoveryBeaconThread = null
    }

    private fun buildDiscoveryPayload(): String {
        return DiscoveryBeaconProtocol.payload(
            rtspUrl = buildRtspUrl(),
            width = currentProfile.width,
            height = currentProfile.height,
            fps = currentProfile.fps,
            bitrateBps = currentProfile.bitrateBps,
            deviceName = "$MANUFACTURER $MODEL",
            pairingCode = pairingCode
        )
    }

    private fun getDiscoveryTargets(): List<InetAddress> {
        val targets = LinkedHashSet<InetAddress>()
        targets.add(InetAddress.getByName(DiscoveryBeaconProtocol.BROADCAST_ADDRESS))

        try {
            NetworkInterface.getNetworkInterfaces().asSequence()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.interfaceAddresses.asSequence() }
                .mapNotNull { it.broadcast }
                .forEach { targets.add(it) }
        } catch (_: Exception) {
            // Fall back to the global IPv4 broadcast address.
        }

        return targets.toList()
    }

    private fun createRtspServerStream(): RtspServerStream {
        return RtspServerStream(
            applicationContext,
            RTSP_PORT,
            this,
            Camera2Source(applicationContext),
            NoAudioSource()
        ).apply {
            getGlInterface().autoHandleOrientation = true
            getStreamClient().setReTries(3)
            getStreamClient().setOnlyVideo(true)
        }
    }

    private fun landscapeStreamRotation(): Int {
        return 0
    }

    private fun applyCameraTextureOrientation() {
        rtspServerStream.setOrientation(cameraTextureRotationDegrees())
    }

    private fun cameraTextureRotationDegrees(): Int {
        return CameraHelper.getCameraOrientation(this)
    }

    private fun cameraSensorOrientationDegrees(facing: CameraHelper.Facing): Int? {
        return cameraCharacteristicsForFacing(facing)
            ?.get(CameraCharacteristics.SENSOR_ORIENTATION)
    }

    private fun cameraCharacteristicsForFacing(facing: CameraHelper.Facing): CameraCharacteristics? {
        val manager = getSystemService(CameraManager::class.java) ?: return null
        val lensFacing = if (facing == CameraHelper.Facing.FRONT) {
            CameraCharacteristics.LENS_FACING_FRONT
        } else {
            CameraCharacteristics.LENS_FACING_BACK
        }
        return try {
            currentCameraId()?.let { cameraId ->
                val characteristics = manager.getCameraCharacteristics(cameraId)
                val lens = characteristics.get(CameraCharacteristics.LENS_FACING)
                if (lens == lensFacing) {
                    return characteristics
                }
            }
            manager.cameraIdList.asSequence()
                .mapNotNull { cameraId ->
                    val characteristics = manager.getCameraCharacteristics(cameraId)
                    val lens = characteristics.get(CameraCharacteristics.LENS_FACING)
                    if (lens == lensFacing) characteristics else null
                }
                .firstOrNull()
        } catch (_: Exception) {
            null
        }
    }

    private fun currentCameraId(): String? {
        val source = rtspServerStream.videoSource
        return if (source is Camera2Source) {
            try {
                source.getCurrentCameraId().takeIf { it.isNotBlank() }
            } catch (_: Exception) {
                null
            }
        } else {
            null
        }
    }

    private fun cameraDiagnosticsLine(): String {
        val sensor = cameraSensorOrientationDegrees(currentCameraFacing)?.toString() ?: "unknown"
        val cameraId = currentCameraId() ?: "unknown"
        val rootEncoderDeviceRotation = CameraHelper.getCameraOrientation(this)
        val windowSize = if (::previewSurfaceView.isInitialized && previewSurfaceView.width > 0 && previewSurfaceView.height > 0) {
            "${previewSurfaceView.width}x${previewSurfaceView.height}"
        } else {
            "unknown"
        }
        return "Camera diagnostics: id $cameraId, sensor $sensor deg, display ${displayRotationDegrees()} deg, root $rootEncoderDeviceRotation deg, window $windowSize"
    }

    private fun handleOrientationInputsChanged() {
        if (isPrepared) {
            applyCameraTextureOrientation()
            applyLandscapeStreamRotationCorrection()
        }
        if (::streamStatusText.isInitialized) {
            updateStreamStatusText()
        }
    }

    private fun displayRotationDegrees(): Int {
        @Suppress("DEPRECATION")
        val rotation = windowManager.defaultDisplay.rotation
        return when (rotation) {
            Surface.ROTATION_0 -> 0
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> normalizeDegrees(90 - CameraHelper.getCameraOrientation(this))
        }
    }

    private fun applyLandscapeStreamRotationCorrection() {
        val rotation = effectiveStreamRotationCorrection()
        rtspServerStream.getGlInterface().setStreamRotation(rotation)
        rtspServerStream.getGlInterface().setPreviewRotation(0)
        rotateCounterClockwiseBtn.text = "Rotate Left"
        rotateStreamBtn.text = if (rotation == 0) "Rotate Right" else "Rotate Right ($rotation)"
    }

    private fun effectiveStreamRotationCorrection(): Int {
        return normalizeDegrees(defaultLandscapeStreamRotationCorrection() + currentCameraRotationCorrectionDegrees())
    }

    private fun defaultLandscapeStreamRotationCorrection(): Int {
        return 0
    }

    private fun rotateStreamCorrection(deltaDegrees: Int) {
        setCurrentCameraRotationCorrectionDegrees(currentCameraRotationCorrectionDegrees() + deltaDegrees)
        savePreferences()
        applyLandscapeStreamRotationCorrection()
        updateStreamStatusText()
    }

    private fun currentCameraRotationCorrectionDegrees(): Int {
        return if (currentCameraFacing == CameraHelper.Facing.FRONT) {
            frontCameraRotationCorrectionDegrees
        } else {
            backCameraRotationCorrectionDegrees
        }
    }

    private fun setCurrentCameraRotationCorrectionDegrees(degrees: Int) {
        val normalized = normalizeDegrees(degrees)
        if (currentCameraFacing == CameraHelper.Facing.FRONT) {
            frontCameraRotationCorrectionDegrees = normalized
        } else {
            backCameraRotationCorrectionDegrees = normalized
        }
    }

    private fun normalizeDegrees(degrees: Int): Int {
        return CameraOrientationMath.normalizeDegrees(degrees)
    }

    private fun updateZoomLabel() {
        val source = rtspServerStream.videoSource
        if (source is Camera2Source) {
            try {
                val zoomRange = source.getZoomRange()
                minZoom = zoomRange.lower ?: 1.0f
                maxZoom = zoomRange.upper ?: 1.0f
                currentZoom = source.getZoom().coerceIn(minZoom, maxZoom)
                zoomLabel.text = String.format(Locale.US, "Zoom: %.1fx", currentZoom)
            } catch (_: Exception) {
                zoomLabel.text = "Zoom unavailable"
            }
        }
    }

    private fun getLocalIpAddress(): String {
        return getActiveNetworkIpv4Address()?.hostAddress
            ?: getInterfaceIpv4Address()?.hostAddress
            ?: "phone-ip"
    }

    private fun getActiveNetworkIpv4Address(): InetAddress? {
        return try {
            val connectivityManager = getSystemService(ConnectivityManager::class.java)
            val activeNetwork = connectivityManager.activeNetwork ?: return null
            val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork)
            val isLanTransport = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true ||
                capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true
            val candidates = connectivityManager.getLinkProperties(activeNetwork)
                ?.linkAddresses
                ?.asSequence()
                ?.map { it.address }
                ?.filterIsInstance<Inet4Address>()
                ?.filter { !it.isLoopbackAddress && !it.isLinkLocalAddress }
                ?.toList()
                .orEmpty()

            if (isLanTransport) {
                candidates.firstOrNull { it.isSiteLocalAddress } ?: candidates.firstOrNull()
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun getInterfaceIpv4Address(): InetAddress? {
        return try {
            val preferredPrefixes = listOf("wlan", "eth", "ap", "swlan")
            val candidates = NetworkInterface.getNetworkInterfaces().asSequence()
                .filter { it.isUp && !it.isLoopback && !it.isPointToPoint }
                .flatMap { networkInterface ->
                    networkInterface.inetAddresses.asSequence()
                        .filterIsInstance<Inet4Address>()
                        .filter { !it.isLoopbackAddress && !it.isLinkLocalAddress }
                        .map { networkInterface.name to it }
                }
                .toList()

            candidates.firstOrNull { (name, address) ->
                address.isSiteLocalAddress && preferredPrefixes.any { prefix -> name.startsWith(prefix) }
            }?.second
                ?: candidates.firstOrNull { (_, address) -> address.isSiteLocalAddress }?.second
                ?: candidates.firstOrNull()?.second
        } catch (_: Exception) {
            null
        }
    }

    private fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }

    private fun loadPreferences() {
        currentProfile = StreamProfile.fromId(prefs.getString(PREF_PROFILE, StreamProfile.DEFAULT.id))
        backCameraRotationCorrectionDegrees = normalizeDegrees(prefs.getInt(PREF_BACK_ROTATION_DEGREES, 0))
        frontCameraRotationCorrectionDegrees = normalizeDegrees(prefs.getInt(PREF_FRONT_ROTATION_DEGREES, 0))
        val savedPairingCode = prefs.getString(PREF_PAIRING_CODE, null)
        pairingCode = DiscoveryBeaconProtocol.sanitizePairingCode(savedPairingCode ?: generatePairingCode())
        if (savedPairingCode != pairingCode) {
            savePreferences()
        }
    }

    private fun savePreferences() {
        prefs.edit()
            .putString(PREF_PROFILE, currentProfile.id)
            .putString(PREF_PAIRING_CODE, pairingCode)
            .putInt(PREF_BACK_ROTATION_DEGREES, normalizeDegrees(backCameraRotationCorrectionDegrees))
            .putInt(PREF_FRONT_ROTATION_DEGREES, normalizeDegrees(frontCameraRotationCorrectionDegrees))
            .apply()
    }

    private fun updatePairingCode() {
        pairingCodeText.text = pairingCode
    }

    private fun generatePairingCode(): String {
        return String.format(Locale.US, "%06d", SecureRandom().nextInt(1_000_000))
    }

    override fun onConnectionStarted(url: String) {
        runOnUiThread {
            lastReceiverIp = url.removePrefix("rtsp://").substringBefore(':').takeIf { it.isNotBlank() }
            connectionState = "Client connecting"
            updateStreamStatusText()
        }
    }

    override fun onConnectionSuccess() {
        runOnUiThread {
            connectionState = "Client connected"
            updateStreamStatusText()
            scheduleBlackout()
        }
    }

    override fun onConnectionFailed(reason: String) {
        runOnUiThread {
            cancelBlackout()
            connectionState = "Client failed: $reason"
            updateStreamStatusText()
            statusText.text = "Client failed: $reason"
        }
    }

    override fun onNewBitrate(bitrate: Long) {
        runOnUiThread {
            latestBitrateBps = bitrate
            bitrateAdapter.adaptBitrate(bitrate, rtspServerStream.getStreamClient().hasCongestion())
            updateStreamStatusText()
        }
    }

    override fun onDisconnect() {
        runOnUiThread {
            cancelBlackout()
            connectionState = "Client disconnected"
            updateStreamStatusText()
        }
    }

    override fun onAuthError() {
        runOnUiThread {
            connectionState = "RTSP auth error"
            updateStreamStatusText()
        }
    }

    override fun onAuthSuccess() {
        runOnUiThread {
            connectionState = "RTSP auth success"
            updateStreamStatusText()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (rtspServerStream.isStreaming) {
            stopStreaming()
            showConnectionPage()
        } else {
            savePreferences()
            @Suppress("DEPRECATION")
            super.onBackPressed()
        }
    }

    override fun onPause() {
        super.onPause()
        savePreferences()
    }

    override fun onResume() {
        super.onResume()
        handleOrientationInputsChanged()
        if (::stream4kController.isInitialized) {
            refreshStream4kCapabilityReport()
            prefillStream4kTarget()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        cancelBlackout()
        stopDiscoveryBeacon()
        if (::stream4kController.isInitialized) {
            stream4kController.listener = null
            stream4kController.stop()
        }
        displayManager?.unregisterDisplayListener(displayListener)
        rtspServerStream.release()
    }

    companion object {
        private const val RTSP_PORT = 8554
        private const val BLACKOUT_DELAY_MS = 120_000L
        private const val PREVIEW_FRAME_PROBE_TIMEOUT_MS = 2_500L
        private const val PREVIEW_FRAME_PROBE_RETRY_MS = 1_000L
        private const val PREF_PROFILE = "profile"
        private const val PREF_PAIRING_CODE = "pairing_code"
        private const val PREF_BACK_ROTATION_DEGREES = "back_rotation_degrees"
        private const val PREF_FRONT_ROTATION_DEGREES = "front_rotation_degrees"
        private const val PREVIEW_LIVE_COLOR = -0xcb2c67
        private const val PREVIEW_STARTING_COLOR = -0x440dc
    }

    private data class StreamStatus(
        val cameraName: String,
        val previewState: String,
        val bitrateLine: String
    )
}
