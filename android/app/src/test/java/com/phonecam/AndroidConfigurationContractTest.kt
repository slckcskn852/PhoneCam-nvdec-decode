package com.phonecam

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidConfigurationContractTest {
    @Test
    fun layoutUsesSingleLowBandwidthProfileSelector() {
        val layout = readProjectFile("src/main/res/layout/activity_rtsp.xml")

        assertTrue(layout.contains("android:id=\"@+id/profileGroup\""))
        assertTrue(layout.contains("android:id=\"@+id/profileEfficient\""))
        assertTrue(layout.contains("android:id=\"@+id/profileBalanced\""))
        assertTrue(layout.contains("android:id=\"@+id/profileMotion\""))
        assertTrue(layout.contains("android:id=\"@+id/pairingCodeText\""))
        assertTrue(layout.contains("android:id=\"@+id/rotateCounterClockwiseBtn\""))
        assertTrue(layout.contains("android:id=\"@+id/rotateStreamBtn\""))
        assertTrue(layout.contains("<SurfaceView"))
        assertTrue(layout.contains("android:id=\"@+id/previewBadgeText\""))
        assertTrue(layout.contains("android:id=\"@+id/streamHeadlineText\""))
        assertTrue(layout.contains("android:id=\"@+id/diagnosticsToggleBtn\""))
        assertTrue(layout.contains("android:id=\"@+id/statusPanel\""))
        assertTrue(layout.contains("android:layout_width=\"340dp\""))
        assertTrue(layout.contains("android:visibility=\"gone\""))
        assertTrue(layout.contains("PREVIEW STARTING"))
        assertTrue(layout.contains("Rotate Left"))
        assertTrue(layout.contains("Rotate Right"))
        assertTrue(layout.contains("android:maxLines=\"2\""))
        assertTrue(layout.contains("Pairing Code"))
        assertTrue(layout.contains("Efficient: 960x540 @ 30 fps, 1.2 Mbps"))
        assertFalse(Regex("""<(TextureView|SurfaceView)[^>]*android:background=""").containsMatchIn(layout))

        assertFalse(layout.contains("bitrateSlider"))
        assertFalse(layout.contains("resolutionGroup"))
        assertFalse(layout.contains("fpsGroup"))
        assertFalse(layout.contains("8 Mbps"))
    }

    @Test
    fun manifestLaunchesRtspMainActivity() {
        val manifest = readProjectFile("src/main/AndroidManifest.xml")

        assertTrue(manifest.contains("android:name=\"com.phonecam.RtspMainActivity\""))
        assertFalse(manifest.contains("android:name=\".MainActivity\""))
    }

    @Test
    fun activeActivityKeepsCameraSwitchAndOrientationSafeguards() {
        val activity = readProjectFile("src/main/java/com/phonecam/RtspMainActivity.kt")

        assertTrue(activity.contains("CameraHelper.getCameraOrientation(this)"))
        assertTrue(activity.contains("private fun landscapeStreamRotation()"))
        assertTrue(activity.contains("val encoderRotation = landscapeStreamRotation()"))
        assertTrue(activity.contains("rotation = encoderRotation"))
        assertTrue(activity.contains("CameraCharacteristics.SENSOR_ORIENTATION"))
        assertTrue(activity.contains("CameraCharacteristics.LENS_FACING_FRONT"))
        assertTrue(activity.contains("private fun cameraTextureRotationDegrees()"))
        assertTrue(activity.contains("return CameraHelper.getCameraOrientation(this)"))
        assertTrue(activity.contains("getGlInterface().autoHandleOrientation = true"))
        assertTrue(activity.contains("DisplayManager.DisplayListener"))
        assertTrue(activity.contains("registerDisplayListener(displayListener"))
        assertTrue(activity.contains("handleOrientationInputsChanged()"))
        assertTrue(activity.contains("source.getCurrentCameraId()"))
        assertTrue(activity.contains("rtspServerStream.setOrientation(cameraTextureRotationDegrees())"))
        assertTrue(activity.contains("setStreamRotation(rotation)"))
        assertTrue(activity.contains("setPreviewRotation(0)"))
        assertTrue(activity.contains("SurfaceHolder.Callback"))
        assertTrue(activity.contains("Preview: \${status.previewState}"))
        assertTrue(activity.contains("previewBadgeText.text = previewBadgeLine()"))
        assertTrue(activity.contains("private fun previewBadgeLine()"))
        assertTrue(activity.contains("PREVIEW LIVE"))
        assertTrue(activity.contains("private fun startPreviewSurface()"))
        assertTrue(activity.contains("private fun requestPreviewFrameProbe()"))
        assertTrue(activity.contains("private fun schedulePreviewFrameProbeTimeout()"))
        assertTrue(activity.contains("private fun retryPreviewFrameProbe()"))
        assertTrue(activity.contains("PREVIEW_FRAME_PROBE_TIMEOUT_MS"))
        assertTrue(activity.contains("PREVIEW CHECKING"))
        assertTrue(activity.contains("previewProbeTimedOut -> \"not confirmed\"\n            previewFrameProbePending -> \"starting\""))
        assertTrue(activity.contains("TakePhotoCallback"))
        assertTrue(activity.contains("rtspServerStream.startPreview(previewSurfaceView)"))
        assertTrue(activity.contains("defaultLandscapeStreamRotationCorrection()"))
        assertTrue(activity.contains("backCameraRotationCorrectionDegrees"))
        assertTrue(activity.contains("frontCameraRotationCorrectionDegrees"))
        assertTrue(activity.contains("currentCameraRotationCorrectionDegrees()"))
        assertTrue(activity.contains("setCurrentCameraRotationCorrectionDegrees"))
        assertTrue(activity.contains("PREF_BACK_ROTATION_DEGREES"))
        assertTrue(activity.contains("PREF_FRONT_ROTATION_DEGREES"))
        assertTrue(activity.contains("prefs.getInt(PREF_BACK_ROTATION_DEGREES, 0)"))
        assertTrue(activity.contains("prefs.getInt(PREF_FRONT_ROTATION_DEGREES, 0)"))
        assertTrue(activity.contains(".putInt(PREF_BACK_ROTATION_DEGREES, normalizeDegrees(backCameraRotationCorrectionDegrees))"))
        assertTrue(activity.contains(".putInt(PREF_FRONT_ROTATION_DEGREES, normalizeDegrees(frontCameraRotationCorrectionDegrees))"))
        assertTrue(activity.contains("rotateCounterClockwiseBtn.setOnClickListener"))
        assertTrue(activity.contains("rotateStreamCorrection(-90)"))
        assertTrue(activity.contains("rotateStreamCorrection(90)"))
        assertTrue(activity.contains("setCurrentCameraRotationCorrectionDegrees(currentCameraRotationCorrectionDegrees() + deltaDegrees)\n        savePreferences()"))
        assertTrue(activity.contains("currentProfile = viewIdToProfile(checkedId)\n            savePreferences()"))
        assertTrue(activity.contains("RootEncoder rotation:"))
        assertTrue(activity.contains("Output rotation:"))
        assertTrue(activity.contains("requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE"))
        assertFalse(activity.contains("requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE"))
        assertTrue(activity.contains("private fun switchCameraSafely()"))
        assertTrue(activity.contains("source.switchCamera()"))
        assertTrue(activity.contains("restartPreviewForSurfaceChange()"))
        assertTrue(activity.contains("private fun releaseCameraSessionForStop()"))
        assertTrue(activity.contains("releaseCameraSessionForStop()"))
        assertTrue(activity.contains("rtspServerStream.release()\n        rtspServerStream = createRtspServerStream()"))
        assertTrue(activity.contains("isPrepared = false\n        previewFrameSeen = false"))
        assertTrue(activity.contains("currentCameraFacing = CameraHelper.Facing.BACK"))
        assertTrue(activity.contains("private fun setupPreviewSurface()"))
        assertTrue(activity.contains("Connection: \$connectionState"))
        assertTrue(activity.contains("Pairing code: \$pairingCode"))
        assertTrue(activity.contains("Camera diagnostics:"))
        assertTrue(activity.contains("private fun streamHeadlineLine()"))
        assertTrue(activity.contains("private fun updateDiagnosticsVisibility()"))
        assertTrue(activity.contains("diagnosticsVisible = false"))
        assertTrue(activity.contains("statusPanel.visibility = if (diagnosticsVisible) View.VISIBLE else View.GONE"))
        assertTrue(activity.contains("Live bitrate:"))
        assertTrue(activity.contains("private const val BLACKOUT_DELAY_MS = 120_000L"))
        assertTrue(activity.contains("uiHandler.postDelayed(blackoutRunnable!!, BLACKOUT_DELAY_MS)"))
        assertTrue(activity.contains("scheduleBlackout()"))
        assertTrue(activity.contains("updateStreamStatusText()"))
        assertTrue(activity.contains("latestBitrateBps = bitrate"))
        assertTrue(activity.contains("pairingCode = pairingCode"))
        assertTrue(activity.contains("if (savedPairingCode != pairingCode)"))
        assertTrue(activity.contains("private fun configureBitrateAdapter()"))
        assertTrue(activity.contains("bitrateAdapter.setMaxBitrate(currentProfile.bitrateBps)"))
        assertFalse(activity.contains("bitrateAdapter.setMaxBitrate(StreamProfile.MAX_BITRATE_BPS)"))
    }

    @Test
    fun oldRawTcpStreamerIsNotInActiveSourceSet() {
        val root = findProjectRoot()

        assertFalse(Files.exists(root.resolve("src/main/java/com/phonecam/RtspStreamer.kt")))
        assertFalse(Files.exists(root.resolve("src/main/java/com/phonecam/RtspClient.kt")))
        assertFalse(Files.exists(root.resolve("src/main/res/layout/activity_main.xml")))
    }

    private fun readProjectFile(relativePath: String): String {
        return String(Files.readAllBytes(findProjectRoot().resolve(relativePath)), Charsets.UTF_8)
    }

    private fun findProjectRoot(): Path {
        val cwd = Paths.get("").toAbsolutePath()
        val candidates = sequenceOf(cwd, cwd.resolve("app"), cwd.parent, cwd.parent?.resolve("app"))
            .filterNotNull()

        return candidates.firstOrNull { Files.exists(it.resolve("src/main/AndroidManifest.xml")) }
            ?: error("Unable to locate Android app project from $cwd")
    }
}
