# PhoneCam Android

The Android app serves the phone camera as an RTSP stream on the local Wi-Fi network.

The MVP is video-only. It requests camera permission but does not request microphone permission.

## Build

```bash
./gradlew :app:testDebugUnitTest :app:assembleDebug --console=plain
```

From the repo root, `scripts/build_android_debug.sh` runs the same debug build with Gradle home/temp paths under `/private/tmp`. Set `FORCE_ANDROID_TESTS=1` when the evidence needs freshly regenerated JVM test XMLs instead of Gradle up-to-date results.

The JVM unit tests check the UDP discovery beacon payload contract, the low-bandwidth stream profile budget, the profile selector UI contract, constrained preview-status overlay with `PREVIEW LIVE` / `PREVIEW CHECKING` badge states, the preview-frame probe watchdog/retry path, the launcher manifest, fixed-landscape streaming lock, RootEncoder orientation handoff, Camera2 sensor-orientation diagnostics, live-preview status reporting, and removal of the old raw TCP streamer from the active source set.

Device or emulator smoke QA from the repo root:

```bash
scripts/android_device_smoke.sh
```

Android RTSP sender to native receiver smoke QA from the repo root:

```bash
scripts/android_rtsp_receiver_smoke.sh
```

The RTSP helper forwards host TCP port `8556` to the Android app's device port `8554` and runs the native receiver against the forwarded URL. This validates the Android sender plus receiver decode path on a development host, but final quality/orientation validation still requires a physical phone on Wi-Fi.

Physical Android Wi-Fi sender to native receiver smoke QA from the repo root:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_receiver_smoke.sh
```

The Wi-Fi helper selects a non-emulator adb target by default, refuses emulator targets unless explicitly allowed, extracts the phone's LAN RTSP URL and pairing code from the UI, captures Android Wi-Fi/network state, decodes frames from the direct LAN URL, records receiver FPS/bitrate/decode-error metrics and decoded frame snapshots, tries pair-code auto-discovery, then switches to the front camera and decodes again. It also records whether the sender UI reached `Preview: live`, captures compact pre-diagnostics and diagnostics-expanded Android screenshots, captures Android display/window/input rotation artifacts, records the sender `Camera diagnostics` line for foldable debugging, and only counts orientation as accepted when `STREAM_ORIENTATION_STATUS=passed`, `STREAM_ORIENTATION_NOTES`, `STREAM_DEVICE_POSTURE`, `FRONT_CAMERA_ORIENTATION_STATUS=passed`, `FRONT_CAMERA_ORIENTATION_NOTES`, and `FRONT_CAMERA_DEVICE_POSTURE` are set after inspecting the physical output. The helper exits nonzero when the sender never reaches `Preview: live`, and final MVP validation rejects evidence where `previewLive` is missing or false, where the compact sender UI dump does not contain `PREVIEW LIVE`, or where the recorded Android screenshots are missing, empty, or not PNG/JPEG/BMP image files. By default it fails before touching the phone if those acceptance fields are missing; use `ALLOW_UNVERIFIED_ORIENTATION=1` only for exploratory collection that cannot satisfy final MVP validation. This is the preferred scripted evidence path before declaring the Android sender usable over real Wi-Fi.

Before the final Z Fold orientation run, use calibration mode to capture the receiver output at every output rotation:

```bash
ORIENTATION_CALIBRATION=1 CALIBRATION_FRAMES=20 \
  RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_receiver_smoke.sh
```

Calibration writes `orientation-calibration.json`, `orientation-calibration-summary.txt`, and decoded receiver snapshots for each 0/90/180/270 output rotation for back and front cameras. It is exploratory evidence only; inspect the snapshots, choose the upright `STREAM_OUTPUT_ROTATION_DEGREES` and `FRONT_CAMERA_OUTPUT_ROTATION_DEGREES`, then run the final profile matrix with acceptance status, notes, and posture. The helper chooses the shortest `Rotate Left` or `Rotate Right` path from the currently persisted correction to the requested target.

For full profile evidence, run:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_profile_matrix_smoke.sh
```

This exercises Efficient, Balanced, and Motion separately, requires pair-code auto-discovery decode by default, records per-profile FPS/bitrate/decode-error metrics and decoded frame snapshots, keeps the front-camera switch/decode/orientation check on the final profile, and writes top-level `summary.txt` plus `matrix-evidence.json` files beside the per-profile evidence folders. The matrix JSON summarizes each profile's observed pairing code, RTSP URL, live-preview status, and whether unverified orientation collection was explicitly allowed when the per-profile evidence exists.

The matrix at `/private/tmp/phonecam-android-wifi-profile-matrix-20260523-003143` is recorded in `../docs/verification-report.md` and still proves physical Wi-Fi decode/discovery. Its orientation acceptance is invalidated by later Galaxy Z Fold 5 review, so final MVP evidence needs a fresh matrix after the SurfaceView preview, RootEncoder orientation, fixed-landscape streaming lock, foldable diagnostics, and per-camera Rotate patches. Current physical orientation evidence must be `orientationEvidenceVersion >= 4` with `orientationLockMode: "fixed-landscape"`.

## Install

```bash
./gradlew :app:installDebug --console=plain
```

## Runtime

1. Grant camera permission.
2. Choose the profile.
   - Efficient default: `960x540 @ 30 fps`, `1.2 Mbps`.
   - Balanced: `1280x720 @ 30 fps`, `1.8 Mbps`.
   - Motion: `1280x720 @ 60 fps`, `2.8 Mbps`.
   Adaptive bitrate is capped to the selected profile, so Efficient remains the low-bandwidth default during runtime adaptation.
3. Note the six-digit pairing code if the Windows receiver should filter to this phone.
4. Tap `Start Camera Server`.
5. If the receiver output is sideways or upside down, tap `Rotate Left` or `Rotate Right` until the current camera's stream is upright.
6. Open the shown RTSP URL from the Windows receiver, or run the receiver with `--auto-discover --pair-code CODE`.

The displayed URL is the app-generated LAN IPv4 URL, for example `rtsp://192.168.1.50:8554/`.

While streaming, the app uses a SurfaceView local live preview behind the controls and shows a `PREVIEW LIVE` badge plus `Preview: live` only after RootEncoder returns a preview-frame probe. If that probe times out, the badge changes to `PREVIEW CHECKING`, the status says `Preview: not confirmed`, and the app keeps retrying the probe so physical QA can distinguish a real live sender preview from an unconfirmed surface. The default overlay is a compact camera/pairing/rotation strip so the live view remains visually obvious on foldable landscape screens. Tap `Info` to show the full diagnostics panel with RTSP URL, front/back camera, RootEncoder input rotation, output rotation, receiver connection state, live bitrate, discovery-beacon state, and camera/display diagnostics; tap `Hide` to collapse it again. The selected profile and Rotate corrections are saved. Rotate correction is stored separately for back and front cameras. Tapping `Stop` stops RTSP, stops the hidden preview, releases the camera session, and creates a fresh stream object for the next run.

While streaming, the app sends best-effort UDP discovery beacons to port `47821` once per second. It sends to the global IPv4 broadcast address and to any directed broadcast addresses exposed by active network interfaces. The beacon contains the RTSP URL, resolution, FPS, bitrate, Android device name, and six-digit pairing code. Manual RTSP URL entry remains the fallback if a router or OS firewall blocks broadcast traffic.

## Active Files

- `app/src/main/java/com/phonecam/RtspMainActivity.kt`
- `app/src/main/java/com/phonecam/StreamProfile.kt`
- `app/src/main/java/com/phonecam/DiscoveryBeaconProtocol.kt`
- `app/src/test/java/com/phonecam/DiscoveryBeaconProtocolTest.kt`
- `app/src/test/java/com/phonecam/StreamProfileTest.kt`
- `app/src/test/java/com/phonecam/AndroidConfigurationContractTest.kt`
- `app/src/main/res/layout/activity_rtsp.xml`
- `app/build.gradle`

The old raw TCP streamer has been removed from the active source set.
