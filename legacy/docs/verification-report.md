# Verification Report

Date: 2026-05-23

Host used for this report: macOS plus one physical Android phone. This host can build Android, run emulator UI checks, compile the receiver core, exercise RTSP/UDP fixtures, and prove physical Android-to-Mac-host Wi-Fi RTSP/discovery behavior. It cannot prove Windows DirectShow registration, OBS/Zoom camera enumeration, or real Android-to-Windows virtual-camera behavior.

## Android Build

Command:

```bash
cd /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android
GRADLE_USER_HOME=/private/tmp/phonecam-gradle-home ./gradlew -Djava.io.tmpdir=/private/tmp/phonecam-gradle-tmp :app:testDebugUnitTest :app:assembleDebug --console=plain
```

Equivalent helper:

```bash
scripts/build_android_debug.sh
```

Result:

```text
BUILD SUCCESSFUL in 912ms
45 actionable tasks: 4 executed, 41 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after the TextureView/Rotate patch:

```text
BUILD SUCCESSFUL in 418ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after the physical-rotation evidence helper update:

```text
BUILD SUCCESSFUL in 423ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after the Camera2 sensor-orientation and live-preview status patch:

```text
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after the emulator crash fix, gesture-safe controls, and receiver-connected blackout delay:

```text
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after the physical matrix rotation/orientation forwarding fix:

```text
BUILD SUCCESSFUL in 476ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after the orientation-acceptance preflight helper update:

```text
BUILD SUCCESSFUL in 371ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after the foldable/display-rotation diagnostics patch:

```text
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh final local rerun after the evidence-gate documentation cleanup:

```text
BUILD SUCCESSFUL in 470ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after confirming the per-camera Rotate correction and documentation update:

```text
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun inside the local verification harness after Windows evidence skip-guard hardening:

```text
BUILD SUCCESSFUL in 314ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun inside the local verification harness after Windows pair-code normalization hardening:

```text
BUILD SUCCESSFUL in 606ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun inside the local verification harness after manual RTSP matrix preflight hardening:

```text
BUILD SUCCESSFUL in 430ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun inside the local verification harness after portable bundle manifest hardening:

```text
BUILD SUCCESSFUL in 401ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun inside the local verification harness after bundle source-input fingerprint hardening:

```text
BUILD SUCCESSFUL in 377ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Notes:

- The normal sandboxed Gradle invocation cannot use `~/.gradle` and Gradle file-lock sockets from this Codex environment.
- The `/private/tmp` Gradle home and Java temp directory are the current local workaround.
- APK output path: `android/app/build/outputs/apk/debug/app-debug.apk`.
- The connection-screen placeholder URL now matches the active RTSP server root path: `rtsp://phone-ip:8554/`.
- Selcuk's bandwidth feedback is implemented with Efficient `960x540 @ 30 fps / 1.2 Mbps`, Balanced `1280x720 @ 30 fps / 1.8 Mbps`, and Motion `1280x720 @ 60 fps / 2.8 Mbps`.
- RootEncoder bitrate adaptation is now capped to the active profile's bitrate, not the global Motion profile ceiling, so Efficient remains the real low-bandwidth default under adaptation.
- Stream preparation now happens after entering a `SurfaceView` preview surface, locks the streaming screen to fixed landscape, keeps the encoded webcam stream in fixed landscape dimensions, uses RootEncoder's own orientation path with `autoHandleOrientation = true` and `CameraHelper.getCameraOrientation(this)`, exposes `RootEncoder rotation`, `Preview: live`, `Output rotation`, and `Camera diagnostics` status lines, leaves `Rotate` as an output-only correction control, restarts preview after surface changes, reapplies RootEncoder input orientation after front/back camera switching, and reapplies orientation when Android reports display changes. The sender marks `Preview: live` only after RootEncoder returns a preview-frame probe through `takePhoto(...)`. Rotate correction is stored separately for back and front cameras; current source exposes explicit `Rotate Left` and `Rotate Right` controls so a 90-degree-right or 90-degree-left fold-mode error can be corrected with one intentional tap. New physical orientation evidence must be `orientationEvidenceVersion: 4`, `rotationControlMode: "per-camera-output"`, and `orientationLockMode: "fixed-landscape"` so pre-landscape-lock or pre-per-camera Rotate runs cannot satisfy the final gate. The diagnostics line still records current camera id, sensor orientation, display rotation, RootEncoder device rotation, and preview window size so the next Galaxy Z Fold run can explain any fold-mode rotation mismatch from captured UI artifacts. It still requires a fresh physical run before orientation can be accepted.
- The main preview is now a `SurfaceView`, matching RootEncoder's recommended StreamBase preview pattern more closely than the earlier `TextureView` path. `AndroidConfigurationContractTest` guards against reintroducing a preview background on either preview surface type.
- The streaming screen defaults to a compact URL/profile/pairing/preview strip so the live SurfaceView preview remains visually obvious on foldable landscape runs. The full camera diagnostics panel is hidden behind an `Info`/`Hide` button; Android smoke helpers capture the compact UI first, then tap `Info` before collecting diagnostic UI XML and camera diagnostics.
- Landscape controls sit above the bottom gesture area, and the smoke helpers retry a `Rotate` tap only when the UI still reports the same `Output rotation`.
- The blackout overlay is no longer scheduled while the sender is just waiting for a receiver. It starts only after `onConnectionSuccess()` and waits `120000ms`, keeping the live preview visible during setup and QA.
- The streaming status panel now preserves URL, active profile, camera facing, connection state, live bitrate, and discovery status when bitrate/connection callbacks fire.
- The Android connection screen now shows a six-digit pairing code, persists the generated code immediately, and discovery beacons include that code for receiver-side filtering.

## Android Unit Tests

Fresh test command:

```bash
cd /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android
./gradlew :app:testDebugUnitTest --rerun-tasks
```

Test results:

```text
android/app/build/test-results/testDebugUnitTest/TEST-com.phonecam.CameraOrientationMathTest.xml
android/app/build/test-results/testDebugUnitTest/TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml
android/app/build/test-results/testDebugUnitTest/TEST-com.phonecam.StreamProfileTest.xml
android/app/build/test-results/testDebugUnitTest/TEST-com.phonecam.AndroidConfigurationContractTest.xml
```

Result summary:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-22T23:17:54.017Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-22T23:17:54.031Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-22T23:17:54.035Z
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
```

Fresh rerun after the foldable/display-rotation diagnostics patch:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:03:09.696Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:03:09.711Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:03:09.712Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:03:09.717Z
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
```

Fresh rerun after constraining the preview diagnostics panel:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:17:09.883Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:17:09.900Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:17:09.901Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:17:09.906Z
BUILD SUCCESSFUL in 2s
45 actionable tasks: 18 executed, 27 up-to-date
```

Fresh rerun after confirming per-camera Rotate correction:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T01:04:06.769Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T01:04:06.783Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T01:04:06.784Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T01:04:06.788Z
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
```

This verifies the Android discovery beacon payload format, pipe sanitization, blank device-name fallback, pairing-code sanitization, low-bandwidth default profile, max preset bitrate budget, active-profile bitrate-adapter cap, single profile selector UI, constrained preview diagnostics panel, launcher activity manifest, source-level camera/orientation/diagnostic safeguards, RootEncoder orientation handoff through `CameraHelper.getCameraOrientation(this)`, Camera2 sensor-orientation diagnostics, display-change orientation reapplication, live-preview status reporting, output-only per-camera Rotate control wiring, immediate generated-pairing-code persistence, preview-background regression guard, receiver-connected blackout delay guard, and removal of the old raw TCP streamer from the active source set without requiring an emulator.

## Android Emulator QA

Fresh emulator sequence on AVD `Pixel_9_Pro_XL`:

```text
/private/tmp/phonecam-android-smoke-20260523-021022
  failed at launch; logcat showed TextureView does not support a background drawable.

/private/tmp/phonecam-android-smoke-20260523-021135
  passed launch, live preview, start, pairing-code, and front-camera switch;
  rotate tap was visible but the UI did not observe output-rotation change.

/private/tmp/phonecam-android-smoke-20260523-021758
  final clean pass after removing the TextureView background, moving controls
  above the gesture area, adding rotate retry-on-no-change, and delaying blackout.
```

Captured Test Android Apps evidence from the clean run:

```text
/private/tmp/phonecam-android-smoke-20260523-021758/summary.txt
/private/tmp/phonecam-android-smoke-20260523-021758/ui.xml
/private/tmp/phonecam-android-smoke-20260523-021758/screenshot.png
/private/tmp/phonecam-android-smoke-20260523-021758/logcat.txt
/private/tmp/phonecam-android-smoke-20260523-021758/ui-after-start.xml
/private/tmp/phonecam-android-smoke-20260523-021758/screenshot-after-start.png
/private/tmp/phonecam-android-smoke-20260523-021758/ui-after-rotate.xml
/private/tmp/phonecam-android-smoke-20260523-021758/screenshot-after-rotate.png
/private/tmp/phonecam-android-smoke-20260523-021758/ui-after-switch.xml
/private/tmp/phonecam-android-smoke-20260523-021758/screenshot-after-switch.png
/private/tmp/phonecam-android-smoke-20260523-021758/logcat-after-switch.txt
/private/tmp/phonecam-android-smoke-20260523-021758/force-stop.txt
```

Verified from captured UI/log artifacts:

- App resolves to `com.phonecam/.RtspMainActivity`.
- Connection screen renders `rtsp://10.0.2.16:8554/`, six-digit pairing code `244591`, Efficient/Balanced/Motion controls, Efficient selected, and `Start Camera Server`.
- Starting the camera server reaches the landscape preview/streaming screen.
- Streaming screen shows `Streaming: rtsp://10.0.2.16:8554/`, `Efficient: 960x540 @ 30 fps, 1.2 Mbps`, `Camera: Back`, `Preview: live`, `Input rotation: 180 deg`, `Pairing code: 244591`, `Output rotation: 0 deg`, `Connection: Waiting for receiver`, `Live bitrate: waiting`, `Discovery beacon active`, `Switch`, `Rotate`, and `Stop`.
- Tapping `Rotate` changes `Output rotation` from `0 deg` to `90 deg`; the button text changes to `Rotate (90)`.
- Tapping `Switch` changes the streaming status to `Camera: Front` while keeping `Preview: live` and `Output rotation: 90 deg`.
- That emulator capture predates the per-camera Rotate-control patch. Current source exposes `Rotate Left` and `Rotate Right` while keeping the front/back correction values separate; fresh physical orientation evidence is still required.
- Post-start logcat shows camera open, video encoder start, audio stub encoder start, RTSP server start, and waiting-for-client state.
- The earlier failed run at `/private/tmp/phonecam-android-smoke-20260523-021022` captured the launch root cause: `java.lang.UnsupportedOperationException: TextureView doesn't support displaying a background drawable`. The clean run has no PhoneCam fatal exception.
- No `com.phonecam` fatal exception, previous `AudioEncoder not prepared` failure, camera-switch failure, or video/audio configuration failure was found in the launch, post-start, or post-switch logcat artifacts.
- The smoke helper force-stopped `com.phonecam` after evidence capture so the emulator RTSP server is not left running.

Helper summary:

```text
PASS: Start Camera Server visible
PASS: Efficient/Balanced/Motion controls visible
PASS: six-digit pairing code visible
PASS: Start Camera Server reached streaming screen
PASS: output rotation status visible
PASS: TextureView preview reported live frames
PASS: Rotate changes output rotation from 0 to 90 degrees
PASS: Switch changes status to front camera
PASS: no PhoneCam crash marker in logcat
PASS: no stream configuration failure marker in logcat
```

Limitations:

- Emulator checks do not prove physical camera quality, real Wi-Fi broadcast traversal, thermal behavior, or hardware encoder behavior on user phones.
- Emulator camera switching is not proof that front camera orientation is correct on real phones; the physical validation is recorded separately in the Wi-Fi matrix section below.
- The fresh QA used `emulator-5554` from AVD `Pixel_9_Pro_XL`, which booted successfully on this Mac. The physical Wi-Fi helper still refuses emulator targets by default, so this emulator pass is not counted as physical Android evidence.

## Android Emulator RTSP Receiver Smoke

Command:

```bash
scripts/android_rtsp_receiver_smoke.sh
```

Captured evidence:

```text
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/summary.txt
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/ui.xml
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/screenshot.png
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/ui-after-start.xml
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/screenshot-after-start.png
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/logcat-after-start.txt
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/logcat-after-receiver.txt
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/receiver.stdout.log
/private/tmp/phonecam-android-rtsp-receiver-20260523-022829/receiver.stderr.log
```

This helper starts the Android app in the emulator, taps `Start Camera Server`, forwards host port `8556` to device port `8554` with adb, then runs the native receiver against `rtsp://127.0.0.1:8556/`.

Receiver result:

```text
Opening rtsp://127.0.0.1:8556/ with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8556, path=/
Using RTSP stream FPS metadata: 29.97
Headless/null sink active: 960x540 @ 29.97 fps
Receiver summary: 30 frames, avg 27.9722 fps, incoming 1.17688 Mbps, decode errors 0
```

Helper summary:

```text
Forwarded RTSP URL: rtsp://127.0.0.1:8556/
PASS: Android RTSP server reached streaming screen
PASS: receiver decoded 30 frames from Android RTSP stream
PASS: no PhoneCam crash marker in logcat
PASS: no stream configuration failure marker in logcat
```

The captured UI showed `Preview: live`, `Input rotation: 180 deg`, `Output rotation: 0 deg`, pairing code `181577`, and `Discovery beacon active`. `receiver.stderr.log` contained FFmpeg's `getaddrinfo(localhost)` warning during the adb-forwarded emulator run, but the receiver still decoded the requested 30 frames with zero decode errors. This proves the current APK's Android RTSP sender and receiver decode path work through an emulator tunnel. It still does not prove physical Android Wi-Fi behavior, hardware encoder behavior, LAN broadcast discovery, or Windows DirectShow output.

## Physical Android Wi-Fi Receiver Smoke

Helpers:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_receiver_smoke.sh
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_profile_matrix_smoke.sh
```

The single-profile helper refuses emulator targets by default, installs the APK on a physical Android target, launches `com.phonecam/.RtspMainActivity`, extracts the concrete LAN RTSP URL and six-digit pairing code from the UI, taps `Start Camera Server`, optionally taps the Android `Rotate` control before direct decode with `STREAM_ROTATE_TAPS=0..3`, captures Android Wi-Fi/network state and direct stream/back-camera orientation artifacts, then runs direct LAN RTSP decode, pair-code auto-discovery decode, optional front-camera switch/decode, optional front-camera `Rotate` taps with `FRONT_CAMERA_ROTATE_TAPS=0..3`, and front-camera orientation artifact capture. The matrix helper runs that flow for Efficient, Balanced, and Motion, requiring per-profile frame snapshots, positive FPS/bitrate metrics, zero decode errors, bounded incoming Mbps, captured Android UI/screenshot/logcat artifacts, stable pairing code, recorded output rotation degrees, manually confirmed direct stream/back-camera orientation on every profile, and manually confirmed front-camera orientation on the final profile.

Fresh script review caught and fixed a matrix-wrapper issue: `scripts/android_wifi_profile_matrix_smoke.sh` accepted `STREAM_ROTATE_TAPS` and `FRONT_CAMERA_ROTATE_TAPS`, but did not forward them into each per-profile `android_wifi_receiver_smoke.sh` run. It now forwards both rotate-tap values plus the direct/back and front orientation status/notes/posture fields, and `scripts/check_windows_static_contracts.rb` guards that propagation.

Fresh follow-up review also added an early acceptance-mode preflight to both physical Wi-Fi helpers. By default the single-profile and matrix helpers now exit before installing or launching the Android app unless direct stream/back-camera orientation status, notes, and physical posture are supplied, plus front-camera orientation status, notes, and posture when front-camera verification is enabled. Exploratory runs can set `ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1`, but that evidence remains invalid for the final MVP validator. The helpers also copy the sender UI's `Camera diagnostics` line into `wifi-evidence.json` for direct/back and front-camera orientation evidence, so final evidence now records the camera id, sensor orientation, display rotation, RootEncoder device rotation, and preview window size seen by the Android app.

No-phone preflight check:

```bash
scripts/android_wifi_profile_matrix_smoke.sh
```

Result:

```text
Physical orientation acceptance inputs are required before running the final Android Wi-Fi matrix.
Missing: STREAM_ORIENTATION_STATUS=passed STREAM_ORIENTATION_NOTES STREAM_DEVICE_POSTURE FRONT_CAMERA_ORIENTATION_STATUS=passed FRONT_CAMERA_ORIENTATION_NOTES FRONT_CAMERA_DEVICE_POSTURE
Inspect the physical receiver output first, then set the status fields to passed only when the stream is landscape-correct.
For exploratory collection only, set ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1; that evidence will not satisfy final MVP validation.
```

Previous physical-phone matrix command:

```bash
FRONT_CAMERA_ORIENTATION_STATUS=passed \
FRONT_CAMERA_ORIENTATION_NOTES='phone physically landscape; decoded front-camera receiver snapshot is 1280x720 with level room/shelves after switch; Android display rotation artifacts captured' \
RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver \
scripts/android_wifi_profile_matrix_smoke.sh
```

Important correction after human review:

```text
Device: Samsung Galaxy Z Fold 5
Posture: opened about 90 degrees in fold mode, effectively landscape
Observed app screen: no obvious live preview, only the streaming controls and status/debug text
Observed receiver snapshots: front camera rotated 90 degrees right; back camera appeared upside down in one image and upright in another
```

This means the matrix below remains useful for physical Wi-Fi RTSP decode, bandwidth, pair-code discovery, and camera-switch decode evidence, but it must not be treated as final orientation acceptance evidence. The final MVP validator now requires direct stream/back-camera orientation evidence for every profile, front-camera orientation evidence on the final profile, orientation evidence version 4, `rotationControlMode: "per-camera-output"`, `orientationLockMode: "fixed-landscape"`, output rotation degrees, notes, recorded device posture, and sender camera diagnostics, so this old matrix intentionally no longer satisfies the Android orientation gate.

Evidence:

```text
Matrix root: /private/tmp/phonecam-android-wifi-profile-matrix-20260523-003143
Matrix JSON: /private/tmp/phonecam-android-wifi-profile-matrix-20260523-003143/matrix-evidence.json
status=passed
generatedAt=2026-05-22T21:35:22Z
matrixExitStatus=0
androidSerial=RFCW70YEQ1R
rtspUrl=rtsp://192.168.1.175:8554/
pairingCode=789395
```

Profile results:

```text
Efficient: 960x540 @ 30 fps, 1.2 Mbps
  direct:    60 frames, 28.9041 fps, 1.12865 Mbps, decode errors 0
  discovery: 60 frames, 29.0131 fps, 1.12719 Mbps, decode errors 0

Balanced: 1280x720 @ 30 fps, 1.8 Mbps
  direct:    60 frames, 28.701 fps, 1.64748 Mbps, decode errors 0
  discovery: 60 frames, 28.8079 fps, 1.77275 Mbps, decode errors 0

Motion: 1280x720 @ 60 fps, 2.8 Mbps
  direct:    60 frames, 6.50775 fps, 2.57842 Mbps, decode errors 0
  discovery: 60 frames, 6.49168 fps, 2.48137 Mbps, decode errors 0
  front:     60 frames, 6.50228 fps, 2.58792 Mbps, decode errors 0
```

Motion front-camera evidence recorded by the old matrix:

```text
PASS: Switch changes status to front camera
PASS: receiver decoded 60 frames after physical front-camera switch within 4.5 Mbps and with zero decode errors
PASS: physical front-camera orientation was manually verified and rotation artifacts were captured
orientationStatus=passed
orientationNotes=phone physically landscape; decoded front-camera receiver snapshot is 1280x720 with level room/shelves after switch; Android display rotation artifacts captured
orientationSummary contains ROTATION_270 / landscape app bounds
accelerometerRotation=1
userRotation=0
```

The decoded receiver snapshots were re-opened after the user report and the front-camera frame is visibly rotated. Treat the `orientationStatus=passed` value in this historical JSON as superseded by the human review above.

This proves the Android sender can stream over the real phone's Wi-Fi LAN to the native receiver built on macOS, including profile-bounded bitrates, pair-code discovery filtering, and front-camera switch/decode. It does not prove orientation correctness after the new fix, and it does not prove Windows DirectShow/OBS/browser enumeration because no Windows host was available in this run.

Troubleshooting history:

- `/private/tmp/phonecam-android-wifi-profile-matrix-20260522-235553` was an earlier no-device run and is superseded by the successful matrix above.
- An earlier physical run decoded `540x960` instead of landscape `960x540`; that exposed the RootEncoder orientation issue fixed with `landscapeStreamRotation()` and disabled GL auto-orientation.
- A later matrix attempt failed after another foreground app took focus on the phone; force-stopping that app and `com.phonecam` before rerun produced the decode/discovery matrix above.
- The Galaxy Z Fold 5 human review invalidated that run's orientation acceptance. The Android app now locks the streaming screen to fixed landscape, computes camera input rotation from Camera2 sensor orientation plus display rotation and facing, shows `Preview: live`, keeps `Rotate` as output-only correction with separate front/back correction memory, reapplies orientation on display changes, records camera/display diagnostics in the UI and evidence JSON, and final validation rejects old orientation evidence that lacks direct stream/back-camera orientation evidence, `orientationEvidenceVersion >= 4`, `rotationControlMode: "per-camera-output"`, `orientationLockMode: "fixed-landscape"`, output rotation degrees, notes, `devicePosture`, and `cameraDiagnostics`.

## Windows Receiver Core Build

Command:

```bash
cmake -S desktop/windows -B /private/tmp/phonecam-windows-receiver-build -DFFMPEG_ROOT=/opt/homebrew -DPHONECAM_WITH_SOFTCAM=OFF
cmake --build /private/tmp/phonecam-windows-receiver-build --config Release
```

Result:

```text
[100%] Built target phonecam-receiver
```

Earlier configure/build output for the same build directory:

```text
-- The OBJCXX compiler identification is AppleClang 21.0.0.21000101
-- Configuring done
-- Generating done
-- Build files have been written to: /private/tmp/phonecam-windows-receiver-build
[ 50%] Building OBJCXX object CMakeFiles/phonecam-receiver.dir/src/main.cpp.o
[100%] Linking OBJCXX executable phonecam-receiver
[100%] Built target phonecam-receiver
```

Notes:

- The Win32 preview window title now mirrors live receiver diagnostics: target, connection state, resolution, average FPS, incoming Mbps, frame count, and decode errors.
- On Apple hosts, CMake compiles the receiver as Objective-C++ and links Cocoa so the same native receiver can show a macOS preview window for local development.
- Manual `--rtsp` runs now infer sink FPS from RTSP stream metadata when `--fps` is not supplied. Auto-discovery still preserves the Android beacon's advertised FPS unless the operator passes an explicit `--fps`.

## Mac Receiver Dev Smoke

Added helper:

```bash
RTSP_URL=rtsp://PHONE_IP:8554/ RECEIVER_BIN=/path/to/phonecam-receiver scripts/mac_receiver_dev_smoke.sh
PAIR_CODE=123456 RECEIVER_BIN=/path/to/phonecam-receiver scripts/mac_receiver_dev_smoke.sh
```

The helper builds or runs the same native receiver on macOS with Softcam disabled, captures stdout/stderr, writes the exact receiver command, requires a decoded `receiver-frame.ppm` snapshot, and writes structured `mac-receiver-evidence.json`. Its JSON includes `macDevOnly: true` and a `doesNotProve` list for Windows DirectShow registration, virtual-camera enumeration, OBS/browser rendering, and Windows firewall/LAN behavior.

Synthetic RTSP fixture verification:

```text
Mac receiver dev evidence: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.ypmodi/mac-evidence/mac-receiver-evidence.json
Opening rtsp://127.0.0.1:8565/phonecam-mac-dev with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8565, path=/phonecam-mac-dev
Headless/null sink active: 1280x720 @ 30 fps
Receiver summary: 30 frames, avg 27.8686 fps, incoming 3.92829 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.ypmodi/mac-evidence/receiver-frame.ppm
Mac receiver fixture passed.
Evidence JSON: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.ypmodi/mac-evidence/mac-receiver-evidence.json
MediaMTX log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.ypmodi/mediamtx.log
FFmpeg log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.ypmodi/ffmpeg.log
```

Fresh rerun after the Windows package README contract update:

```text
Mac receiver dev evidence: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.LJvu7K/mac-evidence/mac-receiver-evidence.json
Opening rtsp://127.0.0.1:8565/phonecam-mac-dev with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8565, path=/phonecam-mac-dev
Headless/null sink active: 1280x720 @ 30 fps
Receiver summary: 30 frames, avg 27.4541 fps, incoming 3.86986 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.LJvu7K/mac-evidence/receiver-frame.ppm
Mac receiver fixture passed.
Evidence JSON: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.LJvu7K/mac-evidence/mac-receiver-evidence.json
MediaMTX log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.LJvu7K/mediamtx.log
FFmpeg log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.LJvu7K/ffmpeg.log
```

The fixture now configures MediaMTX with `rtspTransports: [tcp]` and publishes with FFmpeg `-rtsp_transport tcp`, which avoids opening MediaMTX UDP RTP/RTCP listeners while matching the receiver's RTSP-over-TCP path. It still requires localhost bind permission in the Codex sandbox. This is a macOS shared transport/decode helper, not final Windows virtual-camera evidence.

The macOS dev app packaging helper wraps the same receiver binary as `dist/PhoneCam-Mac/PhoneCam Receiver.app`:

```bash
scripts/package_mac_receiver_app.sh
```

The app bundle uses the receiver's no-argument discovery startup and Cocoa preview sink. It exists to make Mac-side RTSP/discovery debugging easier while a Windows host is unavailable; the bundle README explicitly says it does not prove Windows DirectShow registration, `PhoneCam Virtual Camera` enumeration, or OBS/browser camera rendering.

macOS preview sink sanity check:

```bash
/private/tmp/phonecam-windows-receiver-build/phonecam-receiver --self-test --frames 2 --fps 30 --no-softcam
```

Result:

```text
macOS preview sink active: 320x240
Self-test sent 2 generated frames.
```

This verifies that the local Cocoa preview sink starts and accepts generated frames. It still does not create or validate a virtual camera.

## Windows Receiver CTest

Command:

```bash
ctest --test-dir /private/tmp/phonecam-windows-receiver-build -C Release --output-on-failure
```

Result:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.27 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.24 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.25 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.25 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.26 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.05 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.34 sec
```

Fresh rerun after the physical matrix rotation/orientation forwarding fix:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.24 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.24 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.26 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.26 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.26 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.05 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.33 sec
```

Fresh rerun after the orientation-acceptance preflight helper update:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.25 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.25 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.25 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.53 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.25 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.04 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.57 sec
```

Fresh final local rerun after the foldable diagnostics and evidence-gate cleanup:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.30 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.24 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.22 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.25 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.26 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.05 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.33 sec
```

The sixth test intentionally points the receiver at an unavailable RTSP endpoint and verifies that the command fails with the `Failed to open RTSP stream` diagnostic. Discovery-related CTests now use CTest `RESOURCE_LOCK phonecam_udp_discovery`, because they all bind UDP port `47821` and must not run in parallel with each other or with a manual receiver discovery run.

The self-test also exercises `--snapshot` and writes `/private/tmp/phonecam-windows-receiver-build/phonecam-receiver-self-test.ppm`. The pair-code discovery CTest verifies that `--pair-code 123456` can filter synthetic discovery beacons before auto-connection. The mismatch CTest verifies that a mismatched pairing code rejects a synthetic beacon. The auto-discovery selection CTest verifies that the receiver applies the discovered RTSP URL and advertised 60 fps metadata before opening RTSP, while still allowing an explicit `--fps` override.

## Receiver Error Semantics

Command:

```bash
/private/tmp/phonecam-windows-receiver-build/phonecam-receiver --rtsp rtsp://127.0.0.1:65534/no-stream --frames 1 --no-preview --no-softcam
```

Result:

```text
Opening rtsp://127.0.0.1:65534/no-stream with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=65534, path=/no-stream
Failed to open RTSP stream: Connection refused
```

The command exited with status 2. Bounded receiver runs now also return status 2 when zero frames decode or when `--frames N` exits before N frames.

## Softcam Build Guard

Commands:

```bash
cmake -S desktop/windows -B /private/tmp/phonecam-require-softcam-negative -DFFMPEG_ROOT=/opt/homebrew -DPHONECAM_WITH_SOFTCAM=OFF -DPHONECAM_REQUIRE_SOFTCAM=ON
cmake -S desktop/windows -B /private/tmp/phonecam-missing-softcam-negative -DFFMPEG_ROOT=/opt/homebrew -DPHONECAM_WITH_SOFTCAM=ON -DPHONECAM_REQUIRE_SOFTCAM=ON
```

Results:

```text
PHONECAM_REQUIRE_SOFTCAM=ON requires PHONECAM_WITH_SOFTCAM=ON.
Softcam not found, but PHONECAM_REQUIRE_SOFTCAM=ON. Set -DSOFTCAM_ROOT=... to a built PhoneCam-branded Softcam checkout.
```

This verifies the CMake guard now fails when a Softcam-required build would otherwise silently degrade to preview-only.

Source review note: the receiver intentionally converts decoded frames to BGR24 before preview/Softcam delivery. Upstream Softcam's [`softcam.h`](https://github.com/tshino/softcam/blob/main/src/softcam/softcam.h) sender API accepts a raw frame pointer through `scSendFrame(...)`, and its [sender sample](https://github.com/tshino/softcam/blob/main/examples/sender/sender.cpp) documents the 24-bit byte order as BGR rather than RGB. This matches the receiver's `AV_PIX_FMT_BGR24` conversion and avoids a red/blue channel swap in the virtual camera path.

Workflow and manifest syntax checks:

```bash
ruby scripts/check_windows_static_contracts.rb
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "workflow yaml ok"'
ruby -rjson -e 'manifest=JSON.parse(File.read("desktop/windows/vcpkg.json")); ffmpeg=manifest.fetch("dependencies").find { |dep| dep.is_a?(Hash) && dep["name"]=="ffmpeg" }; abort("missing ffmpeg dep") unless ffmpeg; abort("ffmpeg default-features must be false") unless ffmpeg["default-features"] == false; forbidden=%w[gpl nonfree all-gpl all-nonfree x264 x265 fdk-aac]; used=Array(ffmpeg["features"]); bad=used & forbidden; abort("forbidden ffmpeg features: #{bad.join(",")}") unless bad.empty?; puts "vcpkg manifest json and ffmpeg LGPL feature guard ok"'
```

Result:

```text
windows static contracts ok
workflow yaml ok
vcpkg manifest json and ffmpeg LGPL feature guard ok
```

Android-only stale matrix preflight:

```bash
ruby scripts/validate_mvp_evidence.rb \
  --android-matrix /private/tmp/phonecam-android-wifi-profile-matrix-20260523-003143/matrix-evidence.json \
  --android-only
```

Result:

```text
Android matrix evidence validation failed:
 - Android Efficient streamRotateTaps must be recorded as 0..3
 - Android Efficient stream output rotation degrees must be recorded
 - Android Efficient stream orientation status must be passed
 - Android Efficient stream orientation evidence must be captured
 - Android Efficient stream orientation evidence must be version 4 or newer
 - Android Efficient stream orientation rotationControlMode must be per-camera-output
 - Android Efficient stream orientation output rotation degrees must be recorded
 - Android Efficient stream orientation notes must be recorded
 - Android Efficient stream orientation device posture must be recorded
 - Android Efficient stream orientation cameraDiagnostics must be recorded
 - Android Efficient stream orientation input dump path must be recorded
 - Android Efficient stream orientation window dump path must be recorded
 - Android Efficient stream orientation display dump path must be recorded
 - Android Efficient stream orientation accelerometer_rotation setting path must be recorded
 - Android Efficient stream orientation user_rotation setting path must be recorded
 - Android Efficient stream rotation UI dump path must be recorded
 - Android Efficient stream rotation screenshot path must be recorded
 - Android Balanced streamRotateTaps must be recorded as 0..3
 - Android Balanced stream output rotation degrees must be recorded
 - Android Balanced stream orientation status must be passed
 - Android Balanced stream orientation evidence must be captured
 - Android Balanced stream orientation evidence must be version 4 or newer
 - Android Balanced stream orientation rotationControlMode must be per-camera-output
 - Android Balanced stream orientation output rotation degrees must be recorded
 - Android Balanced stream orientation notes must be recorded
 - Android Balanced stream orientation device posture must be recorded
 - Android Balanced stream orientation cameraDiagnostics must be recorded
 - Android Balanced stream orientation input dump path must be recorded
 - Android Balanced stream orientation window dump path must be recorded
 - Android Balanced stream orientation display dump path must be recorded
 - Android Balanced stream orientation accelerometer_rotation setting path must be recorded
 - Android Balanced stream orientation user_rotation setting path must be recorded
 - Android Balanced stream rotation UI dump path must be recorded
 - Android Balanced stream rotation screenshot path must be recorded
 - Android Motion streamRotateTaps must be recorded as 0..3
 - Android Motion stream output rotation degrees must be recorded
 - Android Motion stream orientation status must be passed
 - Android Motion stream orientation evidence must be captured
 - Android Motion stream orientation evidence must be version 4 or newer
 - Android Motion stream orientation rotationControlMode must be per-camera-output
 - Android Motion stream orientation output rotation degrees must be recorded
 - Android Motion stream orientation notes must be recorded
 - Android Motion stream orientation device posture must be recorded
 - Android Motion stream orientation cameraDiagnostics must be recorded
 - Android Motion stream orientation input dump path must be recorded
 - Android Motion stream orientation window dump path must be recorded
 - Android Motion stream orientation display dump path must be recorded
 - Android Motion stream orientation accelerometer_rotation setting path must be recorded
 - Android Motion stream orientation user_rotation setting path must be recorded
 - Android Motion stream rotation UI dump path must be recorded
 - Android Motion stream rotation screenshot path must be recorded
 - Android Motion front-camera orientation evidence must be version 4 or newer
 - Android Motion front-camera orientation rotationControlMode must be per-camera-output
 - Android Motion front-camera output rotation degrees must be recorded
 - Android Motion front-camera device posture must be recorded
 - Android Motion front-camera cameraDiagnostics must be recorded
 - Android Motion front-camera final switch UI dump path must be recorded
 - Android Motion front-camera final switch screenshot path must be recorded
 - Android Motion front-camera rotation UI dump path must be recorded
 - Android Motion front-camera rotation screenshot path must be recorded
 - Android matrix must include a passed front-camera switch and decode evidence
```

This is intentional. The Windows evidence collector now runs the same Android-only validator before Windows preflight, DirectShow capture, and `-FinalizeOnly` bundling, so a stale Android matrix cannot be combined with fresh Windows evidence. The old Galaxy Z Fold matrix remains valid decode/discovery evidence, but it is not acceptable orientation evidence after human review.

`scripts/check_windows_static_contracts.rb` also runs fixture coverage for the final MVP evidence gate. It verifies that `scripts/validate_mvp_evidence.rb` accepts a complete Android matrix plus Windows runtime/manual evidence set only when Android per-profile `wifi-evidence.json` files prove physical-device LAN RTSP decode against the profile RTSP URL, captured Wi-Fi/network state, a stable six-digit pairing code, pair-code discovery decode against the same profile RTSP URL, zero decode errors, positive receiver FPS/bitrate metrics within profile ceilings, decoded receiver frame snapshots, non-empty Android UI/screenshot/logcat artifacts, physical direct stream/back-camera orientation evidence for every profile with `orientationEvidenceVersion >= 4`, `rotationControlMode: "per-camera-output"`, `orientationLockMode: "fixed-landscape"`, recorded output rotation degrees, `orientationStatus: "passed"`, non-empty orientation notes, a non-empty device posture, sender camera diagnostics, and non-empty input/window/display/settings artifacts, front-camera switch/decode evidence against the same profile RTSP URL, and matching physical front-camera orientation evidence plus sender camera diagnostics on the final profile, when the Windows runtime evidence includes a real LAN-shaped Android RTSP URL that matches one of the physical Android matrix RTSP URLs, when Windows auto-discovery uses the same pair code, when runtime summary, receiver stdout, DirectShow device-list, capture, DirectShow snapshot log, manual-checklist, and manual-template artifacts exist and are non-empty, when receiver stdout contains the selected Android RTSP URL, when the DirectShow device-list log, FFmpeg capture log, and FFmpeg DirectShow snapshot log contain the camera name, when the capture log shows at least `requestedFrames`, when DirectShow captured frames meet `requestedFrames`, when a saved DirectShow frame snapshot exists and is non-empty, when the manual evidence explicitly confirms `directShowFrameMatchesExpectedAndroidStream` with a non-empty review note, and when the OBS/browser manual evidence is tied to the same camera name, RTSP URL, receiver process id, and generated manual evidence template as the runtime DirectShow capture with non-empty, distinct screenshot files present that do not reuse the saved DirectShow frame snapshot. It rejects Android evidence from emulator serials, Android direct/front-camera decode URL mismatches, Android evidence without Wi-Fi network evidence, Android evidence without UI/screenshot/snapshot artifacts, Android evidence without pair-code discovery decode, Android evidence without a six-digit pairing code, stale Android direct stream or front-camera orientation evidence without versioned posture context, per-camera rotation-control mode, fixed-landscape lock metadata, camera diagnostics, or output rotation degrees, Android direct stream or front-camera orientation evidence that is not manually marked passed or lacks notes, Android decode errors, Android incoming Mbps above the profile ceiling, unrelated Windows runtime RTSP evidence, Windows runtime pair-code mismatches, manual evidence from a different receiver process or a different manual template path, manual evidence that lacks DirectShow snapshot review confirmation, missing or empty Windows runtime logs, Windows runtime logs missing the selected Android RTSP URL or camera name, capture logs missing the camera name or below `requestedFrames`, DirectShow capture counts below `requestedFrames`, missing DirectShow snapshot artifacts, missing, empty, duplicated, or DirectShow-snapshot-reused OBS/browser screenshots, and Windows runtime evidence whose `sourceMode` is `generated self-test` or whose selected RTSP URL is localhost or the emulator `10.0.2.*` network. The static contract also now requires the GitHub Actions Softcam-linked Windows job to run the receiver CTest suite before packaging the Windows MVP artifact.

Script/static checks:

```bash
ruby scripts/check_windows_static_contracts.rb
bash -n scripts/build_android_debug.sh scripts/smoke_receiver_fixture.sh scripts/mac_receiver_dev_smoke.sh scripts/mac_receiver_fixture_smoke.sh scripts/android_device_smoke.sh scripts/android_rtsp_receiver_smoke.sh scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh
ruby -c scripts/check_windows_static_contracts.rb
ruby -c scripts/bundle_mvp_evidence.rb
ruby -c scripts/validate_mvp_evidence.rb
scripts/android_wifi_profile_matrix_smoke.sh
git diff --check
```

Result:

```text
windows static contracts ok
bash -n: passed
ruby -c scripts/check_windows_static_contracts.rb: Syntax OK
ruby -c scripts/bundle_mvp_evidence.rb: Syntax OK
ruby -c scripts/validate_mvp_evidence.rb: Syntax OK
scripts/android_wifi_profile_matrix_smoke.sh: expected exit 2 before adb; missing orientation acceptance fields listed
git diff --check: passed with the existing android/gradlew.bat CRLF normalization warning only
```

Fresh rerun on 2026-05-23 03:28 +03 after DirectShow snapshot evidence hardening:

```text
scripts/build_android_debug.sh: BUILD SUCCESSFUL in 375ms; 45 actionable tasks: 1 executed, 44 up-to-date
./gradlew :app:testDebugUnitTest --rerun-tasks: BUILD SUCCESSFUL in 3s; 28 actionable tasks: 28 executed
AndroidConfigurationContractTest: tests=4, failures=0, errors=0, timestamp=2026-05-23T00:28:03.488Z
CameraOrientationMathTest: tests=3, failures=0, errors=0, timestamp=2026-05-23T00:28:03.503Z
DiscoveryBeaconProtocolTest: tests=4, failures=0, errors=0, timestamp=2026-05-23T00:28:03.505Z
StreamProfileTest: tests=3, failures=0, errors=0, timestamp=2026-05-23T00:28:03.509Z
cmake --build /private/tmp/phonecam-windows-receiver-build --config Release: [100%] Built target phonecam-receiver
ctest --test-dir /private/tmp/phonecam-windows-receiver-build -C Release --output-on-failure: 6/6 passed, total 9.29 sec
scripts/smoke_receiver_fixture.sh: 60 frames, avg 28.8293 fps, incoming 3.97972 Mbps, decode errors 0
scripts/mac_receiver_fixture_smoke.sh: first sandbox run failed at localhost bind; escalated rerun passed with 30 frames, avg 27.7087 fps, incoming 3.90575 Mbps, decode errors 0
ruby scripts/check_windows_static_contracts.rb: windows static contracts ok
workflow YAML parse: workflow yaml ok
bash -n helper scripts: passed
ruby -c scripts/check_windows_static_contracts.rb: Syntax OK
ruby -c scripts/bundle_mvp_evidence.rb: Syntax OK
ruby -c scripts/validate_mvp_evidence.rb: Syntax OK
scripts/android_wifi_profile_matrix_smoke.sh: expected exit 2 before adb; missing final orientation acceptance fields listed
git diff --check: passed with the existing android/gradlew.bat CRLF normalization warning only
```

Fresh rerun on 2026-05-23 03:37 +03 after macOS dev app packaging:

```text
scripts/package_mac_receiver_app.sh with RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver: Mac receiver app written to /private/tmp/phonecam-mac-app-test/PhoneCam Receiver.app
Mac app bundle check: executable, Info.plist, and README.txt present/non-empty
scripts/build_android_debug.sh: BUILD SUCCESSFUL in 650ms; 45 actionable tasks: 2 executed, 43 up-to-date
cmake --build /private/tmp/phonecam-windows-receiver-build --config Release: [100%] Built target phonecam-receiver
ctest --test-dir /private/tmp/phonecam-windows-receiver-build -C Release --output-on-failure: 6/6 passed, total 9.27 sec
ruby scripts/check_windows_static_contracts.rb: windows static contracts ok
workflow YAML parse: workflow yaml ok
bash -n helper scripts including scripts/package_mac_receiver_app.sh: passed
ruby -c scripts/check_windows_static_contracts.rb: Syntax OK
ruby -c scripts/bundle_mvp_evidence.rb: Syntax OK
ruby -c scripts/validate_mvp_evidence.rb: Syntax OK
git diff --check: passed with the existing android/gradlew.bat CRLF normalization warning only
```

The local verification harness now groups the Mac-available checks without touching adb or claiming Windows proof:

```bash
scripts/local_verification.sh
```

It writes a timestamped `/private/tmp/phonecam-local-verification-*` folder with `summary.txt` plus per-step logs, runs repository/static checks, Android debug build/fresh JVM tests, receiver build/CTest when the configured build tree exists, macOS dev app packaging when possible, and `git diff --check`. The Android build helper now supports `FORCE_ANDROID_TESTS=1`, and the local harness uses it so the unit-test XML summaries are regenerated instead of silently reusing Gradle up-to-date reports. The summary ends by restating the external blockers: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration. `RUN_RTSP_FIXTURE=1` can add the synthetic RTSP fixture when localhost bind permission is available.

Fresh local harness run on 2026-05-23 03:40 +03:

```text
RUN_RTSP_FIXTURE=0 scripts/local_verification.sh
Initial sandbox run failed during Gradle startup with java.net.SocketException: Operation not permitted while creating Gradle's FileLockContentionHandler.
Escalated rerun passed.
Summary: /private/tmp/phonecam-local-verification-20260523-034025/summary.txt
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default
PASS: Git diff whitespace check
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh local harness run on 2026-05-23 03:51 +03 after manual runtime-artifact cross-checking:

```text
RUN_RTSP_FIXTURE=0 scripts/local_verification.sh
Initial sandbox run failed during Gradle startup with java.net.SocketException: Operation not permitted while creating Gradle's FileLockContentionHandler.
After checking likely fixes for the repeated Gradle socket failure, the efficient local fix remained running the same command outside the sandbox because this repo already uses /private/tmp Gradle home/temp directories and the escalated rerun passes without code changes.
Escalated rerun passed.
Summary: /private/tmp/phonecam-local-verification-20260523-035105/summary.txt
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default
PASS: Git diff whitespace check
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

The Android build portion of that harness passed:

```text
scripts/build_android_debug.sh: BUILD SUCCESSFUL in 326ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Forced Android JVM test rerun after the harness:

```text
GRADLE_USER_HOME=/private/tmp/phonecam-gradle-home ./gradlew -Djava.io.tmpdir=/private/tmp/phonecam-gradle-tmp :app:testDebugUnitTest --rerun-tasks --console=plain
BUILD SUCCESSFUL in 1s
28 actionable tasks: 28 executed
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:52:42.711Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:52:42.725Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:52:42.726Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:52:42.730Z
```

Receiver CTest from the same harness:

```text
ctest --test-dir /private/tmp/phonecam-windows-receiver-build -C Release --output-on-failure
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.25 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.26 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.26 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.26 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.26 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.05 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.35 sec
```

Fresh local harness run on 2026-05-23 03:59 +03 after compact-preview diagnostics toggle:

```text
RUN_RTSP_FIXTURE=0 scripts/local_verification.sh
Initial sandbox run failed during Gradle startup with java.net.SocketException: Operation not permitted while creating Gradle's FileLockContentionHandler.
Escalated rerun passed.
Summary: /private/tmp/phonecam-local-verification-20260523-035927/summary.txt
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default
PASS: Git diff whitespace check
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

The Android build/test portion of that harness passed:

```text
scripts/build_android_debug.sh: BUILD SUCCESSFUL in 320ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:58:30.282Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:58:30.296Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:58:30.297Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T00:58:30.301Z
```

Receiver CTest from that harness:

```text
ctest --test-dir /private/tmp/phonecam-windows-receiver-build -C Release --output-on-failure
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.54 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.25 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.26 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.26 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.26 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.06 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.64 sec
```

Fresh RTSP fixture run:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.8979 fps, incoming 3.9892 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.YfJ3iy/receiver-frame.ppm
Fixture passed.
```

Fresh local harness run on 2026-05-23 04:17 +03 after adding the Windows package README guard for version-4 orientation evidence:

```text
RUN_RTSP_FIXTURE=0 scripts/local_verification.sh
Escalated rerun passed.
Summary: /private/tmp/phonecam-local-verification-20260523-041714/summary.txt
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default
PASS: Git diff whitespace check
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic receiver fixture after the same review:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.7727 fps, incoming 3.97192 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.6T0KV3/receiver-frame.ppm
Fixture passed.
```

Fresh synthetic receiver fixture after the Windows package README guard:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.7926 fps, incoming 3.97466 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.rcmwmp/receiver-frame.ppm
Fixture passed.
```

Fresh Mac receiver fixture run:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/mac_receiver_fixture_smoke.sh
Initial sandbox run failed at listen tcp :8565: bind: operation not permitted.
Escalated rerun passed.
Mac receiver dev evidence: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.W4G8MV/mac-evidence/mac-receiver-evidence.json
Opening rtsp://127.0.0.1:8565/phonecam-mac-dev with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 30 fps
Receiver summary: 30 frames, avg 27.7547 fps, incoming 3.91223 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.W4G8MV/mac-evidence/receiver-frame.ppm
Mac receiver fixture passed.
```

Fresh physical Android matrix acceptance preflight:

```text
scripts/android_wifi_profile_matrix_smoke.sh
Physical orientation acceptance inputs are required before running the final Android Wi-Fi matrix.
Missing: STREAM_ORIENTATION_STATUS=passed STREAM_ORIENTATION_NOTES STREAM_DEVICE_POSTURE FRONT_CAMERA_ORIENTATION_STATUS=passed FRONT_CAMERA_ORIENTATION_NOTES FRONT_CAMERA_DEVICE_POSTURE
Inspect the physical receiver output first, then set the status fields to passed only when the stream is landscape-correct.
For exploratory collection only, set ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1; that evidence will not satisfy final MVP validation.
```

Final MVP evidence gate:

```bash
ruby scripts/validate_mvp_evidence.rb \
  --android-matrix /private/tmp/phonecam-android-wifi-profile-matrix-20260523-003143/matrix-evidence.json \
  --windows-runtime /private/tmp/phonecam-missing-runtime-evidence.json \
  --windows-manual /private/tmp/phonecam-missing-manual-app-evidence.json
```

Expected current result:

```text
MVP evidence validation failed:
 - Windows runtime evidence file not found: /private/tmp/phonecam-missing-runtime-evidence.json
 - Windows manual app evidence file not found: /private/tmp/phonecam-missing-manual-app-evidence.json
 - Android Efficient streamRotateTaps must be recorded as 0..3
 - Android Efficient stream output rotation degrees must be recorded
 - Android Efficient stream orientation status must be passed
 - Android Efficient stream orientation evidence must be captured
 - Android Efficient stream orientation evidence must be version 4 or newer
 - Android Efficient stream orientation rotationControlMode must be per-camera-output
 - Android Efficient stream orientation output rotation degrees must be recorded
 - Android Efficient stream orientation notes must be recorded
 - Android Efficient stream orientation device posture must be recorded
 - Android Efficient stream orientation cameraDiagnostics must be recorded
 - Android Efficient stream orientation input dump path must be recorded
 - Android Efficient stream orientation window dump path must be recorded
 - Android Efficient stream orientation display dump path must be recorded
 - Android Efficient stream orientation accelerometer_rotation setting path must be recorded
 - Android Efficient stream orientation user_rotation setting path must be recorded
 - Android Efficient stream rotation UI dump path must be recorded
 - Android Efficient stream rotation screenshot path must be recorded
 - Android Balanced streamRotateTaps must be recorded as 0..3
 - Android Balanced stream output rotation degrees must be recorded
 - Android Balanced stream orientation status must be passed
 - Android Balanced stream orientation evidence must be captured
 - Android Balanced stream orientation evidence must be version 4 or newer
 - Android Balanced stream orientation rotationControlMode must be per-camera-output
 - Android Balanced stream orientation output rotation degrees must be recorded
 - Android Balanced stream orientation notes must be recorded
 - Android Balanced stream orientation device posture must be recorded
 - Android Balanced stream orientation cameraDiagnostics must be recorded
 - Android Balanced stream orientation input dump path must be recorded
 - Android Balanced stream orientation window dump path must be recorded
 - Android Balanced stream orientation display dump path must be recorded
 - Android Balanced stream orientation accelerometer_rotation setting path must be recorded
 - Android Balanced stream orientation user_rotation setting path must be recorded
 - Android Balanced stream rotation UI dump path must be recorded
 - Android Balanced stream rotation screenshot path must be recorded
 - Android Motion streamRotateTaps must be recorded as 0..3
 - Android Motion stream output rotation degrees must be recorded
 - Android Motion stream orientation status must be passed
 - Android Motion stream orientation evidence must be captured
 - Android Motion stream orientation evidence must be version 4 or newer
 - Android Motion stream orientation rotationControlMode must be per-camera-output
 - Android Motion stream orientation output rotation degrees must be recorded
 - Android Motion stream orientation notes must be recorded
 - Android Motion stream orientation device posture must be recorded
 - Android Motion stream orientation cameraDiagnostics must be recorded
 - Android Motion stream orientation input dump path must be recorded
 - Android Motion stream orientation window dump path must be recorded
 - Android Motion stream orientation display dump path must be recorded
 - Android Motion stream orientation accelerometer_rotation setting path must be recorded
 - Android Motion stream orientation user_rotation setting path must be recorded
 - Android Motion stream rotation UI dump path must be recorded
 - Android Motion stream rotation screenshot path must be recorded
 - Android Motion front-camera orientation evidence must be version 4 or newer
 - Android Motion front-camera orientation rotationControlMode must be per-camera-output
 - Android Motion front-camera output rotation degrees must be recorded
 - Android Motion front-camera device posture must be recorded
 - Android Motion front-camera cameraDiagnostics must be recorded
 - Android Motion front-camera final switch UI dump path must be recorded
 - Android Motion front-camera final switch screenshot path must be recorded
 - Android Motion front-camera rotation UI dump path must be recorded
 - Android Motion front-camera rotation screenshot path must be recorded
 - Android matrix must include a passed front-camera switch and decode evidence
```

This is the correct current result after the Galaxy Z Fold 5 review: the old physical Android matrix still proves Wi-Fi decode/discovery but is no longer acceptable direct/back or front-camera orientation evidence, and full MVP validation also remains blocked by missing real Windows runtime DirectShow capture plus OBS/browser manual enumeration evidence.

## Windows Packaging

Added packaging helper:

```powershell
.\desktop\windows\scripts\Package-PhoneCamWindows.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -FfmpegBinDir C:\deps\ffmpeg\bin `
  -OutputDir .\dist\PhoneCam-Windows
```

The helper creates a Windows package directory and zip containing the Softcam-linked receiver, `softcam.dll`, `softcam_installer.exe`, FFmpeg/vcpkg runtime DLLs, runtime verification scripts, `Collect-PhoneCamWindowsEvidence.ps1`, the local RTSP fixture helper, the Softcam preparation helper, the final `validate_mvp_evidence.rb` gate, the portable `bundle_mvp_evidence.rb` evidence bundler, docs, and a `PACKAGE-CONTENTS.txt` manifest. The package docs now include the repo testing runbook, this verification report, and the Softcam branding guide so the Windows operator has the current evidence and virtual-camera build requirements inside the delivered archive. The packager copies every `*.dll` from the resolved FFmpeg/vcpkg runtime bin directory while still requiring the core `avcodec`, `avformat`, `avutil`, and `swscale` DLLs. This avoids clean-host package failures from missing transitive vcpkg DLLs. The GitHub Actions Softcam job runs this packager and uploads `phonecam-windows-mvp-package`.

The workflow now has a `static-contracts` job that runs `ruby scripts/check_windows_static_contracts.rb` and shell syntax checks before platform builds. The static guard parses the workflow and vcpkg manifest, enforces the LGPL-clean FFmpeg feature posture, checks that the package path requires Softcam in CI, checks that the Windows packager copies all runtime DLLs from the FFmpeg/vcpkg bin directory, and checks that the packaged Windows artifact includes the Softcam prep script, RTSP fixture helper, evidence bundler, and Softcam branding guide. It also checks that the generated Windows package README documents the Android-only preflight requirement for physical orientation evidence with `orientationEvidenceVersion >= 4`, `rotationControlMode` per-camera-output, `orientationLockMode` fixed-landscape, device posture, recorded `Rotate Left`/`Rotate Right` direction, rotation request mode, 0/90/180/270 output-rotation degrees, target/output consistency for absolute rotation targets, and sender camera diagnostics before Windows DirectShow evidence is collected. The same static guard builds a complete synthetic evidence set, bundles it with `bundle_mvp_evidence.rb`, and validates the bundled copies so the final physical evidence can be archived without absolute temp-path breakage.

The static guard now also protects license hygiene for legacy prototype material: the Windows MVP package script must not include UnityCapture or pyvirtualcam, and `docs/third-party-notices.md` must document the checked-in `UnityCapture-master` reference tree, its MIT/zlib split from the local README, and pyvirtualcam's GPLv2 legacy-only status. This keeps the delivered MVP on the Softcam + LGPL-clean FFmpeg path while leaving old prototype files available for reference.

The workflow now also includes a `mac-receiver` job on `macos-latest`. It installs FFmpeg with Homebrew, configures the same receiver with `PHONECAM_WITH_SOFTCAM=OFF`, builds the Apple Objective-C++/Cocoa preview-capable path, runs the receiver CTest suite, and uploads the macOS dev receiver binary. This protects the Mac development receiver path only; it is not Windows DirectShow evidence.

The evidence bundler now runs the final MVP validator on source evidence before copying and again on the rewritten bundled evidence after copying. It copies `validate_mvp_evidence.rb` into `tools/`, writes bundle-relative evidence paths, source input SHA-256 fingerprints, and a bundled-validator command into `bundle-manifest.json`, and refuses to bundle failing or preflight-only evidence by default; `--skip-validation` is reserved for diagnostics while investigating evidence path problems.

Fresh portable evidence bundle hardening:

```text
scripts/bundle_mvp_evidence.rb
  bundle-manifest.json now stores bundle-relative androidMatrix/windowsRuntime/windowsManual paths.
  sourceInputs now stores source basenames, byte sizes, and SHA-256 fingerprints instead of absolute source paths.
  tools/validate_mvp_evidence.rb is copied into the evidence bundle.
  validateCommand now uses the bundled validator and relative evidence paths, so the evidence folder can be moved as a portable archive.

scripts/check_windows_static_contracts.rb
  now rejects absolute host paths anywhere in bundle-manifest.json and validates the bundled fixture with the bundled validator copy.
```

Fresh bundle source-input fingerprint hardening:

```text
scripts/bundle_mvp_evidence.rb
  sourceInputs no longer stores the original host paths.
  each source input records basename, bytes, and sha256.

scripts/check_windows_static_contracts.rb
  recursively rejects absolute host paths anywhere in bundle-manifest.json.
  requires sourceInputs.androidMatrix/windowsRuntime/windowsManual fingerprints.
```

The package README now changes its runtime verification command depending on whether `ffmpeg.exe` is present in the FFmpeg runtime directory. Minimal vcpkg library builds may package only FFmpeg DLLs, so the generated README points `-Ffmpeg` at `C:\deps\ffmpeg\bin\ffmpeg.exe` and tells the operator to install an LGPL-clean FFmpeg CLI when `bin\ffmpeg.exe` is not bundled. It also includes the final Ruby evidence-gate command for combining Android matrix, Windows runtime, and OBS/browser manual evidence, and it now explicitly says the Windows collector first runs Android-only validation so stale or missing physical orientation diagnostics stop the run before DirectShow registration. The packaged instructions now name the current version-4/per-camera/fixed-landscape orientation fields, explicit `Rotate Left`/`Rotate Right` direction, rotation request mode, and absolute-target/output consistency rule so a Windows operator does not attempt DirectShow validation with an older Android matrix. The Windows workflow now checks the packaged required files and verifies that README-WINDOWS.txt points at bundled `bin\ffmpeg.exe` only when that executable exists.

The Windows workflow now also parses the PowerShell scripts with PowerShell's parser before building, so syntax errors fail on `windows-latest`. A local bug in `Test-PhoneCamWindowsRuntime.ps1` where `Resolve-ExistingDirectory` was referenced but not defined was fixed in this tree.

The package now includes `Install-PhoneCamFirewallRules.ps1`, which adds private-network firewall rules for inbound UDP discovery on port `47821` and outbound RTSP-over-TCP on port `8554`, scoped to `phonecam-receiver.exe`.

Fresh follow-up hardening: `Prepare-PhoneCamSoftcam.ps1` now requires the built `softcam_installer.exe` and writes `PHONECAM-SOFTCAM-BUILD.txt` with the upstream repository, requested revision, resolved commit, expected `PhoneCam Virtual Camera` filter name, PhoneCam CLSID, DLL path, and installer path. `Package-PhoneCamWindows.ps1` now verifies the Softcam source or that metadata before copying `softcam.dll`, fails if the PhoneCam branding cannot be proven, and includes `docs\SOFTCAM-BUILD.txt` in the Windows MVP package. `.github/workflows/build.yml` and `scripts/check_windows_static_contracts.rb` now require that packaged branding report, and the workflow validates that the report contains the `PhoneCam Virtual Camera` filter name and PhoneCam CLSID before uploading `phonecam-windows-mvp-package`.

The Windows runtime verifier now prefers Softcam's `softcam_installer.exe register/unregister` path for DirectShow registration, matching upstream Softcam's own batch files, and writes `runtime-summary.txt` plus structured `runtime-evidence.json` alongside receiver, FFmpeg DirectShow-device, capture, and DirectShow snapshot logs. It falls back to `regsvr32` only if the installer executable is not available. It can verify generated receiver frames by default, or validate the real Android-to-Windows path with `-AutoDiscover -PairCode PHONE_CODE` or `-RtspUrl rtsp://PHONE_IP:8554/`; in those modes, the receiver feeds the Android RTSP stream into Softcam while FFmpeg captures from `PhoneCam Virtual Camera`. Runtime evidence now records selected/opened/effective RTSP URL fields from the receiver stdout, receiver process id, runtime log paths, generated manual checklist/template paths, DirectShow capture `requestedFrames`, and a saved `directshow-frame.bmp` artifact from the virtual camera. The generated manual evidence template also includes `runtimeArtifacts.directShowFrameSnapshot`, `runtimeArtifacts.directShowSnapshotLog`, `runtimeArtifacts.directShowCaptureLog`, `directShowFrameMatchesExpectedAndroidStream`, and `directShowFrameReviewNote` so the Windows operator must inspect the virtual-camera frame artifact before filling OBS/browser evidence, and both the PowerShell manual validator and final Ruby MVP validator cross-check those paths against `runtime-evidence.json` plus require the snapshot review fields. The runtime helper records the maximum FFmpeg `frame=` count from the capture log, bounds the single-frame snapshot capture with `-t CaptureSeconds`, writes it via FFmpeg's `image2` muxer with `-update 1`, and fails immediately when the capture log does not name the expected camera, reports fewer frames than requested, or cannot save a non-empty DirectShow frame snapshot. Final validation also rejects capture logs that do not name the expected camera and rejects missing/empty DirectShow snapshot artifacts. This lets runtime and final validation reject generated, localhost, emulator, placeholder, missing-log, empty-log, log-content-mismatch, wrong-camera-capture, short-capture, missing-DirectShow-snapshot, missing-manual-artifact, mismatched-manual-template, mismatched-manual-runtime-artifact, and missing-DirectShow-snapshot-review evidence. `-KeepReceiverRunning` leaves that same receiver process live after successful FFmpeg capture and writes `manual-app-enumeration-checklist.txt` plus `manual-app-evidence-template.json` for OBS/browser camera-picker evidence, including a `-ValidateManualEvidence ... -RuntimeEvidence ...` check for completed manual evidence tied to the same runtime capture, receiver process id, generated template path, DirectShow frame/log artifacts, and DirectShow snapshot review fields, plus an explicit `-UnregisterOnly` cleanup command. If DirectShow verification fails, the helper now stops the receiver and writes failed `runtime-summary.txt` / `runtime-evidence.json` artifacts instead of leaving a failed validation process running.

Fresh cleanup-path hardening: `Test-PhoneCamWindowsRuntime.ps1 -UnregisterOnly` now checks elevation explicitly and fails with `Elevated PowerShell is required for -UnregisterOnly.` before invoking Softcam unregister. The README, Windows README, and testing runbook now state that cleanup must run from an elevated PowerShell.

The Windows runtime verifier also has a `-PreflightOnly` mode. It resolves the receiver, FFmpeg, Softcam DLL, optional `softcam_installer.exe`, source mode, and administrator state, then writes `windows-preflight-summary.txt` and `windows-preflight-evidence.json` without registering Softcam or capturing DirectShow frames. The preflight evidence includes a `doesNotProve` list so it cannot be mistaken for final DirectShow/OBS/browser evidence.

`Collect-PhoneCamWindowsEvidence.ps1` now orchestrates the real Windows evidence pass: it requires the physical Android matrix evidence, refuses `-SkipPreflight`, runs runtime preflight in a child PowerShell process, can install scoped firewall rules, runs Android pair-code discovery or manual RTSP with `-KeepReceiverRunning`, then prints the generated manual checklist/template paths and a deterministic `-FinalizeOnly` command. `Test-PhoneCamWindowsRuntime.ps1` also rejects `-KeepReceiverRunning -SkipCapture`, so OBS/browser evidence cannot be generated without the same run first proving FFmpeg DirectShow capture and a saved `directshow-frame.bmp` snapshot. Finalize-only mode validates the completed manual OBS/browser evidence, runs `validate_mvp_evidence.rb`, and bundles the evidence with `bundle_mvp_evidence.rb` by default. This wrapper is packaging/workflow guarded, but it still requires an actual Windows host for runtime proof.

Both Windows evidence scripts now normalize `-PairCode` to digits and reject values that do not contain exactly six digits before receiver startup or preflight work. This keeps typed separators from breaking a legitimate run while still preventing malformed or wrong pairing codes from reaching DirectShow registration.

The Windows collector now also validates manual `-RtspUrl` fallback against the physical Android matrix before Windows preflight or Softcam registration. That prevents a manual fallback run from feeding DirectShow with a different phone or stale URL only to fail at final evidence validation later.

Fresh manual RTSP matrix preflight hardening:

```text
desktop/windows/scripts/Collect-PhoneCamWindowsEvidence.ps1
  now collects canonical RTSP endpoints from the Android matrix and per-profile wifi-evidence.json files.
  manual -RtspUrl is rejected before Windows runtime preflight when it does not match any Android matrix RTSP URL.

scripts/check_windows_static_contracts.rb
  now requires Get-AndroidMatrixRtspEndpoints, Get-CanonicalRtspEndpoint, and the manual RTSP mismatch failure before Windows preflight.
```

Fresh Windows pair-code normalization hardening:

```text
desktop/windows/scripts/Collect-PhoneCamWindowsEvidence.ps1
  normalizes -PairCode to digits, requires exactly six digits, then compares it with the Android matrix code before Windows preflight.

desktop/windows/scripts/Test-PhoneCamWindowsRuntime.ps1
  normalizes -PairCode to digits and requires exactly six digits before receiver startup.

scripts/check_windows_static_contracts.rb
  now guards the normalization helpers and malformed-pair-code failure strings.
```

The Windows PowerShell RTSP fixture helper was aligned with the shell fixture: it defaults to host port `8555`, pair-code filter `123456`, a silent AAC track for FFmpeg publishing, forces MediaMTX and FFmpeg RTSP-over-TCP transport, and derives the MediaMTX listen port from a custom `-RtspUrl` when one is supplied.

The Windows vcpkg manifest now disables FFmpeg default features and enables only `avcodec`, `avformat`, and `swscale`, avoiding accidental GPL/nonfree feature selection in the CI/package path.

Local limitation: `pwsh` is not installed on this Mac host, so the PowerShell script parser/runtime checks still need validation on Windows or a host with PowerShell. The GitHub Actions workflow includes a PowerShell parser step for `desktop/windows/scripts/*.ps1`.

## Receiver Frame-Sink Self-Test

Command:

```bash
/private/tmp/phonecam-windows-receiver-build/phonecam-receiver --self-test --frames 5 --fps 30 --no-preview --no-softcam
```

Result:

```text
Headless/null sink active: 320x240 @ 30 fps
Self-test sent 5 generated frames.
```

## Receiver Discovery Self-Test

Command:

```bash
/private/tmp/phonecam-windows-receiver-build/phonecam-receiver --discovery-self-test
```

Result:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds...
Discovered Synthetic Android at rtsp://127.0.0.1:8554/ (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1)
Discovery complete: 1 PhoneCam device(s) found.
Discovery self-test passed.
```

## Receiver Auto-Discovery Selection Self-Test

Command:

```bash
/private/tmp/phonecam-windows-receiver-build/phonecam-receiver --auto-discovery-selection-self-test
```

Result:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8554/ (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery selection self-test passed.
```

This protects the no-argument and `--auto-discover` pairing path from silently creating a 30 fps preview/Softcam sink when the selected phone advertises the Motion 60 fps profile.

## Receiver No-Argument Pairing Path

The receiver now defaults to LAN discovery when launched without arguments.

Command:

```bash
/private/tmp/phonecam-windows-receiver-build/phonecam-receiver
```

Expected result without a running Android phone:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 15 seconds...
No PhoneCam devices discovered. Start the Android camera server on the same LAN, or pass the shown URL with --rtsp rtsp://PHONE_IP:8554/.
Discovery complete: 0 PhoneCam device(s) found.
```

## Auto-Discovery Plus RTSP Decode Fixture

Fixture setup:

```bash
/private/tmp/phonecam-mediamtx/mediamtx /private/tmp/phonecam-mediamtx/mediamtx.yml
ffmpeg -hide_banner -loglevel info -re -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i anullsrc=channel_layout=mono:sample_rate=48000 -pix_fmt yuv420p -c:v libx264 -preset veryfast -tune zerolatency -g 30 -b:v 4M -c:a aac -b:a 96k -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8555/phonecam-test
```

Receiver command:

```bash
/private/tmp/phonecam-windows-receiver-build/phonecam-receiver --auto-discover-self-test rtsp://127.0.0.1:8555/phonecam-test --pair-code 123456 --frames 60 --snapshot /tmp/receiver-frame.ppm --no-preview --no-softcam
```

Equivalent helper:

```bash
scripts/smoke_receiver_fixture.sh
```

Receiver result:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
[swscaler @ 0xbf642c000] No accelerated colorspace conversion found from yuv420p to bgr24.
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.8943 fps, incoming 4.00016 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.834 fps, incoming 3.98037 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.93KNAP/receiver-frame.ppm
Fixture passed.
MediaMTX log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.93KNAP/mediamtx.log
FFmpeg log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.93KNAP/ffmpeg.log
Receiver snapshot: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.93KNAP/receiver-frame.ppm
```

Fresh rerun after the physical matrix rotation/orientation forwarding fix:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9017 fps, incoming 4.00118 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8794 fps, incoming 3.98664 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.YMuxZ4/receiver-frame.ppm
Fixture passed.
MediaMTX log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.YMuxZ4/mediamtx.log
FFmpeg log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.YMuxZ4/ffmpeg.log
Receiver snapshot: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.YMuxZ4/receiver-frame.ppm
```

Fresh rerun after the orientation-acceptance preflight helper update:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9433 fps, incoming 4.00694 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.852 fps, incoming 3.98286 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.WHJ2RT/receiver-frame.ppm
Fixture passed.
MediaMTX log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.WHJ2RT/mediamtx.log
FFmpeg log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.WHJ2RT/ffmpeg.log
Receiver snapshot: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.WHJ2RT/receiver-frame.ppm
```

Fresh final local rerun after CTest released UDP discovery port `47821`:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9225 fps, incoming 4.00407 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8229 fps, incoming 3.97885 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.i8usEd/receiver-frame.ppm
Fixture passed.
```

Cleanup:

```text
The fixture helper stopped FFmpeg and MediaMTX during cleanup and preserved temporary logs because `KEEP_PHONECAM_FIXTURE_LOGS=1` was set for this evidence run.
```

The fixture and CTest discovery tests must be run serially because both bind UDP discovery port `47821`. A parallel verification run failed with `Failed to bind UDP discovery port 47821`; the CTest discovery cases use `RESOURCE_LOCK phonecam_udp_discovery`, and rerunning the fixture after CTest completed passed with the fresh output above.

The helper was also run inside the Codex sandbox first and failed cleanly before receiver startup:

```text
MediaMTX exited before the fixture could run.
ERR listen tcp :8555: bind: operation not permitted
```

An earlier TCP+UDP MediaMTX config also failed in the sandbox at `listen udp :8000: bind: operation not permitted`. The fixture now uses MediaMTX `rtspTransports: [tcp]` and FFmpeg `-rtsp_transport tcp`, which removes the unnecessary UDP RTP/RTCP listeners for this receiver test. The same helper passed after allowing the local RTSP bind outside the sandbox. This is a local sandbox limitation, not an application failure.

During this run, the Android emulator owned `127.0.0.1:8554`, which caused FFmpeg to connect to qemu instead of MediaMTX and fail with `Could not write header ... Invalid data found when processing input`. The fixture helper now defaults to host port `8555` to avoid colliding with the Android app's `8554` RTSP port while emulator QA is running.

## Current Resume Audit

Fresh resumed audit on 2026-05-23 after recording the Galaxy Z Fold 5 feedback:

```text
git status --short
```

The tree is still the large uncommitted Android sender plus Windows receiver MVP rewrite. `DiscoveryBeaconProtocol.kt` is not half-applied: Android callers and JVM tests pass with the required six-digit `pairingCode` argument, and the Windows receiver still accepts optional pairing-code discovery.

Mac-safe local verification without adb/Gradle first passed syntax/static/build checks, then failed at sandboxed receiver CTest because the discovery tests could not bind UDP `47821`:

```text
RUN_ANDROID_BUILD=0 RUN_MAC_APP_PACKAGE=0 RUN_RTSP_FIXTURE=0 scripts/local_verification.sh
Output: /private/tmp/phonecam-local-verification-20260523-042203
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Receiver build
FAIL: Receiver CTest
Failed to bind UDP discovery port 47821.
```

`lsof -nP -iUDP:47821` showed no local port owner. The same CTest suite passed outside the Codex sandbox, confirming this was a local sandbox server-socket limitation rather than a receiver regression:

```text
ctest --test-dir /private/tmp/phonecam-windows-receiver-build -C Release --output-on-failure
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.27 sec
```

Fresh Android build/JVM-test helper result:

```text
scripts/build_android_debug.sh
BUILD SUCCESSFUL in 319ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh static/syntax/whitespace checks:

```text
ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

bash -n scripts/build_android_debug.sh scripts/smoke_receiver_fixture.sh scripts/mac_receiver_dev_smoke.sh scripts/mac_receiver_fixture_smoke.sh scripts/package_mac_receiver_app.sh scripts/android_device_smoke.sh scripts/android_rtsp_receiver_smoke.sh scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/local_verification.sh
passed

git diff --check
passed with the existing android/gradlew.bat CRLF warning only
```

Fresh synthetic receiver fixture after the resumed audit:

```text
scripts/smoke_receiver_fixture.sh
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.8131 fps, incoming 3.97749 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.imi4h1/receiver-frame.ppm
Fixture passed.
```

Fresh package-branding and cleanup-path guard after the Softcam metadata content check and elevated `-UnregisterOnly` check:

```text
ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "workflow yaml ok"'
workflow yaml ok

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

bash -n scripts/build_android_debug.sh scripts/smoke_receiver_fixture.sh scripts/mac_receiver_dev_smoke.sh scripts/mac_receiver_fixture_smoke.sh scripts/package_mac_receiver_app.sh scripts/android_device_smoke.sh scripts/android_rtsp_receiver_smoke.sh scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/local_verification.sh
passed

git diff --check
passed with the existing android/gradlew.bat CRLF warning only
```

Fresh pair-code collector audit and local rerun after resuming this work:

```text
ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "workflow yaml ok"'
workflow yaml ok

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

bash -n scripts/android_wifi_receiver_smoke.sh scripts/package_mac_receiver_app.sh scripts/android_device_smoke.sh scripts/mac_receiver_dev_smoke.sh scripts/build_android_debug.sh scripts/mac_receiver_fixture_smoke.sh scripts/smoke_receiver_fixture.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/android_rtsp_receiver_smoke.sh scripts/local_verification.sh
passed

git diff --check
passed with the existing android/gradlew.bat CRLF warning only
```

The current collector already contains `Get-AndroidMatrixPairingCode` and rejects a mistyped `-PairCode` before Windows preflight or DirectShow registration:

```text
PairCode $PairCode does not match Android matrix pairing code $androidMatrixPairingCode.
```

Fresh build/decode verification from the same pass:

```text
scripts/build_android_debug.sh
BUILD SUCCESSFUL in 330ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk

cmake --build /private/tmp/phonecam-windows-receiver-build --config Release
[100%] Built target phonecam-receiver

ctest --test-dir /private/tmp/phonecam-windows-receiver-build -C Release --output-on-failure
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.38 sec

scripts/smoke_receiver_fixture.sh
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.8317 fps, incoming 3.98006 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.Vkird4/receiver-frame.ppm
Fixture passed.
```

One attempted fixture run in this pass was invalid because it ran in parallel with CTest and both processes use UDP discovery port `47821`; rerunning the fixture by itself produced the passing result above.

Fresh follow-up on the Windows package README guard:

```text
desktop/windows/scripts/Package-PhoneCamWindows.ps1
  package README now states that -PairCode is checked against the stable six-digit pairing code in the Android matrix before Windows preflight or DirectShow registration starts.

scripts/check_windows_static_contracts.rb
  now fails if the generated Windows package README stops documenting that pair-code preflight.
```

Fresh full local verification harness run:

```text
scripts/local_verification.sh
Generated: 2026-05-23T04:44:20+03:00
Output: /private/tmp/phonecam-local-verification-20260523-044420

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-044420/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

The macOS dev app package from this run was written under `/private/tmp/phonecam-local-verification-20260523-044420/mac-app/PhoneCam Receiver.app` and passed the executable bundle sanity check. This proves the macOS preview/dev wrapper remains buildable; it still does not prove Windows DirectShow or OBS/browser enumeration.

Fresh DirectShow snapshot-review evidence hardening:

```text
desktop/windows/scripts/Test-PhoneCamWindowsRuntime.ps1
  generated manual-app-evidence-template.json now includes directShowFrameMatchesExpectedAndroidStream and directShowFrameReviewNote.
  -ValidateManualEvidence requires directShowFrameMatchesExpectedAndroidStream=true and a non-empty directShowFrameReviewNote.

scripts/validate_mvp_evidence.rb
  final MVP validation now rejects Windows manual evidence unless the DirectShow snapshot review is explicitly confirmed.

scripts/check_windows_static_contracts.rb
  fixture coverage now rejects manual evidence with directShowFrameMatchesExpectedAndroidStream=false and an empty review note.

desktop/windows/scripts/Package-PhoneCamWindows.ps1
  generated README-WINDOWS.txt now tells the Windows operator to inspect the DirectShow frame snapshot and fill the review fields before OBS/browser evidence validation.
```

Fresh full local verification harness run after that hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T04:51:17+03:00
Output: /private/tmp/phonecam-local-verification-20260523-045117

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-045117/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh collector operator-instruction update:

```text
desktop/windows/scripts/Collect-PhoneCamWindowsEvidence.ps1
  after runtime evidence capture, the printed finalize instruction now tells the Windows operator to inspect the DirectShow snapshot, set directShowFrameMatchesExpectedAndroidStream/directShowFrameReviewNote, and add screenshotPath files before running -FinalizeOnly.

scripts/check_windows_static_contracts.rb
  now requires the collector script itself to mention directShowFrameMatchesExpectedAndroidStream and directShowFrameReviewNote.
```

Fresh full local verification harness run after the collector instruction update:

```text
scripts/local_verification.sh
Generated: 2026-05-23T04:53:23+03:00
Output: /private/tmp/phonecam-local-verification-20260523-045323

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-045323/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Windows evidence skip-guard hardening:

```text
desktop/windows/scripts/Collect-PhoneCamWindowsEvidence.ps1
  now rejects -SkipPreflight in the final evidence collector.

desktop/windows/scripts/Test-PhoneCamWindowsRuntime.ps1
  now rejects -KeepReceiverRunning -SkipCapture so OBS/browser evidence cannot be tied to a run without FFmpeg DirectShow capture and directshow-frame.bmp.

scripts/check_windows_static_contracts.rb
  now guards both of those failure paths.
```

Fresh full local verification harness run after that skip-guard hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T04:58:38+03:00
Output: /private/tmp/phonecam-local-verification-20260523-045838

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Receiver CTest detail:
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.32 sec

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-045838/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh serial RTSP fixture rerun after that skip-guard hardening:

```text
scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 41.8033 fps, incoming 5.72558 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.LFtu8b/receiver-frame.ppm
Fixture passed.
```

Fresh full local verification harness run after pair-code normalization hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:03:46+03:00
Output: /private/tmp/phonecam-local-verification-20260523-050346

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Receiver CTest detail:
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.61 sec

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-050346/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh full local verification harness run after manual RTSP matrix preflight hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:08:28+03:00
Output: /private/tmp/phonecam-local-verification-20260523-050828

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Receiver CTest detail:
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.31 sec

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-050828/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh full local verification harness run after portable bundle manifest hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:12:34+03:00
Output: /private/tmp/phonecam-local-verification-20260523-051234

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Receiver CTest detail:
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.33 sec

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-051234/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh full local verification harness run after bundle source-input fingerprint hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:16:14+03:00
Output: /private/tmp/phonecam-local-verification-20260523-051614

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Receiver CTest detail:
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.32 sec

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-051614/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh post-audit local verification refresh:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:19:47+03:00
Output: /private/tmp/phonecam-local-verification-20260523-051947

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-051947/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after the local harness:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.8967 fps, incoming 3.98903 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.1WbKGF/receiver-frame.ppm
Fixture passed.
```

Fresh evidence-bundle handoff hardening:

- `scripts/bundle_mvp_evidence.rb` now writes a root `README.txt` into `PhoneCam-MVP-Evidence`, records that README path in `bundle-manifest.json`, and records whether the bundle was created with validation skipped.
- The root README tells the reviewer to run the bundled validation command from the bundle folder, lists the relative Android/Windows evidence paths, lists the bundled validator path, and records the source input SHA-256 fingerprints.
- `scripts/check_windows_static_contracts.rb` now verifies the README, root-relative validation command, bundled validator reference, source fingerprint section, and non-skipped validation status for the complete synthetic fixture bundle.
- `README.md`, `docs/testing.md`, and the Windows package README generator in `desktop/windows/scripts/Package-PhoneCamWindows.ps1` now document the bundle README and validation-skipped metadata.

Fresh full local verification harness run after evidence-bundle README hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:23:24+03:00
Output: /private/tmp/phonecam-local-verification-20260523-052324

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-052324/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after evidence-bundle README hardening:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.734 fps, incoming 3.96658 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.eBXeaS/receiver-frame.ppm
Fixture passed.
```

Fresh Windows collector prerequisite hardening:

- `desktop/windows/scripts/Collect-PhoneCamWindowsEvidence.ps1` now resolves the `-Ruby` command before Android preflight, Windows runtime work, or final bundling, and reports a direct install/pass-`-Ruby` error when Ruby is missing.
- The collector uses the resolved Ruby executable for Android matrix preflight, final MVP validation, and evidence bundling.
- If a non-default `-Ruby` path is supplied, the collector includes that argument in the printed `-FinalizeOnly` follow-up command.
- `README.md`, `docs/testing.md`, `desktop/windows/README.md`, and the generated Windows package README now document Ruby as a final evidence prerequisite alongside elevated PowerShell and an LGPL-clean FFmpeg CLI.
- `scripts/check_windows_static_contracts.rb` now guards the Ruby prerequisite documentation and collector command resolution.

Fresh full local verification harness run after collector Ruby-prerequisite hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:28:15+03:00
Output: /private/tmp/phonecam-local-verification-20260523-052815

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-052815/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after collector Ruby-prerequisite hardening:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.7982 fps, incoming 3.97543 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.ckCV2l/receiver-frame.ppm
Fixture passed.
```

Fresh Windows package README-generation hardening:

- `desktop/windows/scripts/Package-PhoneCamWindows.ps1` now builds `README-WINDOWS.txt` from a literal PowerShell here-string template with explicit placeholders for the FFmpeg note/path.
- This preserves Markdown code-span backticks and PowerShell line-continuation backticks in the packaged runbook instead of letting PowerShell's expandable-string parser treat them as escapes.
- `scripts/check_windows_static_contracts.rb` now guards the literal template and placeholder replacement.

Fresh full local verification harness run after package README-generation hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:31:19+03:00
Output: /private/tmp/phonecam-local-verification-20260523-053119

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-053119/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after package README-generation hardening:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.8452 fps, incoming 3.98192 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.IhX5nP/receiver-frame.ppm
Fixture passed.
```

Fresh Android calibration persistence hardening:

- `RtspMainActivity` now saves selected profile changes immediately instead of relying only on lifecycle pause/back events.
- `RtspMainActivity` now persists separate back-camera and front-camera output rotation corrections using normalized degree values.
- The `Rotate Left` / `Rotate Right` actions save the current camera's correction immediately, so a foldable/manual calibration survives app restarts.
- `AndroidConfigurationContractTest` now guards the persisted profile path and the persisted per-camera rotation preference keys.
- `README.md`, `android/README.md`, and `docs/testing.md` now state that profile and per-camera Rotate corrections are saved.

Fresh Android build/JVM test run after calibration persistence:

```text
scripts/build_android_debug.sh
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk

TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T02:34:00.771Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T02:34:00.787Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T02:34:00.788Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T02:34:00.792Z
```

Fresh full local verification harness run after calibration persistence:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:34:24+03:00
Output: /private/tmp/phonecam-local-verification-20260523-053424

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-053424/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after calibration persistence:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.8144 fps, incoming 3.97767 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.MoEIxd/receiver-frame.ppm
Fixture passed.
```

Fresh Android Stop camera-session release hardening:

- `RtspMainActivity.stopStreaming()` now stops streaming, releases any active hidden preview, releases the RootEncoder/RTSP camera session, recreates a fresh `RtspServerStream`, reapplies the bitrate adapter, resets prepared/preview/zoom/facing state, and refreshes the RTSP URL before returning to the connection screen.
- This prevents a stopped sender from keeping a prepared camera preview session alive behind the connection page, which made manual retesting and phone sleep behavior harder to reason about.
- `AndroidConfigurationContractTest` now guards that `Stop` calls `releaseCameraSessionForStop()`, releases and recreates the stream object, resets `isPrepared`/`previewFrameSeen`, and returns the camera-facing state to back-camera default.
- `README.md`, `android/README.md`, and `docs/testing.md` now document that `Stop` releases the camera session instead of leaving a hidden preview prepared.

Fresh Android build/JVM test run after Stop camera-session release:

```text
scripts/build_android_debug.sh
BUILD SUCCESSFUL in 327ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk

TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T02:36:57.373Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T02:36:57.388Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T02:36:57.389Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T02:36:57.392Z
```

Fresh full local verification harness run after Stop camera-session release:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:38:52+03:00
Output: /private/tmp/phonecam-local-verification-20260523-053852

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-053852/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after Stop camera-session release:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.7955 fps, incoming 3.97506 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.Xg6os9/receiver-frame.ppm
Fixture passed.
```

Fresh final evidence validator hardening:

- `scripts/validate_mvp_evidence.rb` now checks every recorded Windows RTSP URL field, including `effectiveRtspUrl`, `selectedRtspUrl`, `openedRtspUrl`, and `rtspUrl`, and rejects runtime or manual evidence when those fields point at different endpoints.
- `scripts/validate_mvp_evidence.rb` now requires real Windows runtime evidence to include `openedRtspUrl` parsed from receiver stdout, and requires auto-discovery evidence to include `selectedRtspUrl` parsed from receiver stdout.
- The final validator now also requires Windows manual OBS/browser evidence to use the same `sourceMode` as the runtime DirectShow capture.
- `scripts/check_windows_static_contracts.rb` now has fixture cases that reject inconsistent runtime RTSP fields, missing runtime `openedRtspUrl`, missing auto-discovery `selectedRtspUrl`, inconsistent manual RTSP fields, and manual source-mode mismatch, while still accepting the complete positive fixture.
- This avoids a bad final bundle where a Windows artifact claims the physical Android matrix URL but the receiver selected or opened a different RTSP source.

Fresh validator/static checks after RTSP field-consistency hardening:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

git diff --check
warning: in the working copy of 'android/gradlew.bat', CRLF will be replaced by LF the next time Git touches it
```

Fresh full local verification harness run after RTSP field-consistency hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:45:13+03:00
Output: /private/tmp/phonecam-local-verification-20260523-054513

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-054513/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after RTSP field-consistency hardening:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.8126 fps, incoming 3.97742 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.L1MIx4/receiver-frame.ppm
Fixture passed.
```

Fresh selected/opened Windows runtime RTSP evidence hardening:

- `scripts/validate_mvp_evidence.rb` now requires `openedRtspUrl` for real Windows runtime evidence, proving the receiver stdout recorded the actual RTSP URL opened by the receiver.
- For `sourceMode: "auto-discovered Android RTSP"`, it also requires `selectedRtspUrl`, proving the receiver selected a discovery beacon before opening RTSP.
- `desktop/windows/scripts/Test-PhoneCamWindowsRuntime.ps1` now runs the same selected/opened RTSP evidence check before it can write passed runtime evidence, so a Windows run fails immediately if receiver stdout does not prove the opened stream or auto-discovered selected stream.
- `scripts/check_windows_static_contracts.rb` now rejects missing-opened and missing-selected runtime fixture evidence.
- `README.md`, `docs/testing.md`, and the generated Windows package README text now document these selected/opened RTSP requirements.

Fresh validator/static checks after selected/opened RTSP hardening:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

git diff --check
warning: in the working copy of 'android/gradlew.bat', CRLF will be replaced by LF the next time Git touches it
```

Fresh full local verification harness run after selected/opened RTSP hardening:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:50:08+03:00
Output: /private/tmp/phonecam-local-verification-20260523-055008

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-055008/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after selected/opened RTSP hardening:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Receiver summary: 60 frames, avg 28.9166 fps, incoming 3.99177 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.heckpZ/receiver-frame.ppm
Fixture passed.
```

Fresh Windows runtime-script selected/opened RTSP enforcement:

- `desktop/windows/scripts/Test-PhoneCamWindowsRuntime.ps1` now has `Assert-ReceiverRtspEvidence`, which fails real RTSP runs before writing passed runtime evidence if receiver stdout lacks `openedRtspUrl`, if auto-discovery lacks `selectedRtspUrl`, if any recorded RTSP URL is invalid, or if selected/opened/supplied URL fields point to different endpoints.
- `scripts/check_windows_static_contracts.rb` now guards `Get-CanonicalRtspEndpoint`, `Assert-ReceiverRtspEvidence`, and the runtime-script failure messages so this enforcement remains packaged with the Windows verifier.
- PowerShell Core is not installed on this Mac, so the PowerShell script change is static-contract verified here and still requires a real Windows execution pass for runtime proof.

Fresh validator/static checks after runtime-script selected/opened RTSP enforcement:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

git diff --check
warning: in the working copy of 'android/gradlew.bat', CRLF will be replaced by LF the next time Git touches it
```

Fresh full local verification harness run after runtime-script selected/opened RTSP enforcement:

```text
scripts/local_verification.sh
Generated: 2026-05-23T05:53:06+03:00
Output: /private/tmp/phonecam-local-verification-20260523-055306

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
SKIP: Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-055306/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh synthetic RTSP fixture refresh after runtime-script selected/opened RTSP enforcement:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Discovery complete: 1 PhoneCam device(s) found.
Using discovered stream FPS: 60
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9274 fps, incoming 4.00474 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.926 fps, incoming 3.99308 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.aTV60P/receiver-frame.ppm
Fixture passed.
```

Fresh fixed-landscape streaming lock and orientation evidence contract:

- `RtspMainActivity` now requests `ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE` for the streaming page instead of sensor-landscape. This is meant to avoid mid-session landscape/reverse-landscape flips on foldable/tabletop postures while keeping `Rotate Left` / `Rotate Right` as the explicit output correction controls.
- Physical Android orientation evidence is now versioned as `orientationEvidenceVersion: 4` and must include `orientationLockMode: "fixed-landscape"` for both direct stream/back-camera and front-camera orientation evidence.
- `scripts/validate_mvp_evidence.rb` rejects Android matrix evidence without the fixed-landscape lock metadata, and `scripts/check_windows_static_contracts.rb` includes a negative fixture for that failure mode.
- The Windows package README generated by `desktop/windows/scripts/Package-PhoneCamWindows.ps1` now tells Windows operators that Android matrix preflight requires version-4 fixed-landscape evidence before DirectShow registration/capture starts.

Fresh full local verification harness run after fixed-landscape streaming lock:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T06:05:39+03:00
Output: /private/tmp/phonecam-local-verification-20260523-060539

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-060539/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fixture details from that harness:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9584 fps, incoming 4.00904 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.7975 fps, incoming 3.97534 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.GA48hZ/receiver-frame.ppm
Fixture passed.
```

This audit refreshes Mac-buildable evidence only. It still does not prove physical Android orientation, Windows DirectShow registration/capture, OBS enumeration, browser camera-picker enumeration, or real Android-to-Windows virtual-camera behavior.

Fresh emulator QA and local verification refresh after the fixed-landscape evidence contract:

- Android Studio is installed on this Mac, and `~/Library/Android/sdk/emulator/emulator -list-avds` now reports `Pixel_9_Pro_XL`.
- There was no attached physical phone in `adb devices`; the available target was the emulator `emulator-5554`.
- Emulator evidence is scoped to install, launch, UI, local preview, front/back switch state, rotate control wiring, and emulator RTSP decode through adb port forwarding. It does not satisfy the physical Android Wi-Fi/orientation matrix or real phone camera-quality gate.
- A first non-escalated `scripts/local_verification.sh` run failed when Gradle could not create its local file-lock socket inside the sandbox (`java.net.SocketException: Operation not permitted`). The same harness passed after rerunning with permission for local sockets.

Fresh Android debug build:

```text
scripts/build_android_debug.sh
BUILD SUCCESSFUL in 373ms
45 actionable tasks: 1 executed, 44 up-to-date
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh forced Android JVM tests:

```text
cd android && ./gradlew :app:testDebugUnitTest --rerun-tasks
BUILD SUCCESSFUL in 5s
28 actionable tasks: 28 executed

TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:14:12.152Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:14:12.168Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:14:12.169Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:14:12.173Z
```

Fresh emulator app smoke:

```text
ANDROID_SERIAL=emulator-5554 scripts/android_device_smoke.sh
Smoke evidence: /private/tmp/phonecam-android-smoke-20260523-061147

PASS: Start Camera Server visible
PASS: Efficient/Balanced/Motion controls visible
PASS: six-digit pairing code visible
PASS: Start Camera Server reached streaming screen
PASS: output rotation status visible
PASS: TextureView preview reported live frames
PASS: Rotate changes output rotation from 0 to 90 degrees
PASS: Switch changes status to front camera
PASS: no PhoneCam crash marker in logcat
PASS: no stream configuration failure marker in logcat
```

Visual artifacts from that emulator smoke:

```text
/private/tmp/phonecam-android-smoke-20260523-061147/screenshot-after-start-compact.png
/private/tmp/phonecam-android-smoke-20260523-061147/screenshot-after-switch.png
```

Fresh emulator RTSP receiver smoke over adb forwarding:

```text
ANDROID_SERIAL=emulator-5554 RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/android_rtsp_receiver_smoke.sh
Android RTSP receiver smoke evidence: /private/tmp/phonecam-android-rtsp-receiver-20260523-061225

PASS: Android RTSP server reached streaming screen
PASS: receiver decoded 30 frames from Android RTSP stream
PASS: no PhoneCam crash marker in logcat
PASS: no stream configuration failure marker in logcat
```

Receiver stdout from the emulator RTSP smoke:

```text
Opening rtsp://127.0.0.1:8556/ with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8556, path=/
Headless/null sink active: 960x540 @ 30 fps
Receiver summary: 30 frames, avg 27.0372 fps, incoming 0.307301 Mbps, decode errors 0
```

Fresh full local verification harness run:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T06:13:06+03:00
Output: /private/tmp/phonecam-local-verification-20260523-061306

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-061306/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fixture details from that harness:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.7954 fps, incoming 3.98647 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8186 fps, incoming 3.97825 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.Dddrjo/receiver-frame.ppm
Fixture passed.
```

Fresh Android test-evidence hardening:

- `scripts/build_android_debug.sh` now supports `FORCE_ANDROID_TESTS=1`. In that mode it runs `:app:testDebugUnitTest --rerun-tasks` before `:app:assembleDebug`, so local verification evidence is backed by freshly generated JVM test XMLs instead of Gradle up-to-date reports.
- The Android build helper now prints a compact summary for every `app/build/test-results/testDebugUnitTest/TEST-*.xml` file: test count, failures, errors, skipped, and timestamp.
- `scripts/local_verification.sh` now invokes the Android helper as `env FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh`.
- `scripts/check_windows_static_contracts.rb` now guards the fresh-test mode and XML-summary behavior.
- `README.md`, `android/README.md`, and `docs/testing.md` document the fresh-test mode.

Repeated Gradle sandbox error review:

- The restricted local sandbox repeatedly failed Gradle startup with `Could not create service of type FileLockContentionHandler` and `java.net.SocketException: Operation not permitted`.
- Checked likely fixes before continuing: Gradle daemon settings, `--no-daemon`, file-system watching via `--no-watch-fs`, isolated `GRADLE_USER_HOME`, cached distribution availability, and stale daemon/cache concerns. Gradle's own docs note that daemon communication uses a local socket and that `GRADLE_USER_HOME` controls caches/distributions; the daemon/watch flags did not remove this sandbox socket requirement here.
- A direct non-escalated retry with `--no-daemon --no-watch-fs -Dorg.gradle.daemon=false` still failed with the same FileLockContentionHandler socket error against the cached Gradle home.
- The efficient local fix remains running Gradle commands outside the restricted sandbox while keeping `GRADLE_USER_HOME` and `java.io.tmpdir` under `/private/tmp`.

Fresh forced Android build/test helper run after XML-summary hardening:

```text
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh
BUILD SUCCESSFUL in 1s
28 actionable tasks: 28 executed
BUILD SUCCESSFUL in 315ms
39 actionable tasks: 1 executed, 38 up-to-date

TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:20:17.617Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:20:17.632Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:20:17.633Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:20:17.637Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh full local verification harness run after forcing fresh JVM-test evidence:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T06:20:36+03:00
Output: /private/tmp/phonecam-local-verification-20260523-062036

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-062036/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Android XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:20:40.810Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:20:40.825Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:20:40.826Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:20:40.830Z
```

Fixture details from that harness:

```text
Listening for PhoneCam discovery beacons on UDP 47821 for 2 seconds with pair code 123456...
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9073 fps, incoming 4.00196 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.853 fps, incoming 3.983 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.VuKWb5/receiver-frame.ppm
Fixture passed.
```

## Android Matrix Handoff Bundle

The evidence bundler now supports an Android-only handoff mode:

```bash
ruby scripts/bundle_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --android-only \
  --output-dir /path/to/PhoneCam-Android-Matrix-Handoff
```

This mode validates the physical Android matrix with `validate_mvp_evidence.rb --android-only`, copies the matrix folder, rewrites JSON artifact paths to portable relative paths, copies the validator under `tools/`, and writes `README.txt` plus `bundle-manifest.json` with `"androidOnly": true`. It intentionally does not claim Windows DirectShow, OBS, or browser evidence. The Windows operator should copy the whole handoff folder and pass its bundled `android/matrix-evidence.json` to `Collect-PhoneCamWindowsEvidence.ps1`.

Fresh verification after adding the Android-only bundle path:

```text
ruby -c scripts/bundle_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "workflow yaml ok"'
workflow yaml ok

bash -n scripts/build_android_debug.sh scripts/local_verification.sh scripts/smoke_receiver_fixture.sh scripts/mac_receiver_dev_smoke.sh scripts/mac_receiver_fixture_smoke.sh scripts/package_mac_receiver_app.sh scripts/android_device_smoke.sh scripts/android_rtsp_receiver_smoke.sh scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

The static contract now builds a complete synthetic Android-only bundle, verifies the manifest has no absolute host paths, verifies `README.txt` documents Windows handoff rather than MVP completion, checks that the copied `android/matrix-evidence.json` no longer contains the source temp directory, and re-runs the bundled validator in Android-only mode.

Fresh full local verification harness after the same change:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T06:30:08+03:00
Output: /private/tmp/phonecam-local-verification-20260523-063008

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-063008/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:30:13.311Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:30:13.325Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:30:13.326Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:30:13.330Z
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9426 fps, incoming 4.00685 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8598 fps, incoming 3.98393 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.ZZleJr/receiver-frame.ppm
Fixture passed.
```

Additional physical-observation note from the Galaxy Z Fold 5 review: the phone was opened about 90 degrees in fold mode, effectively landscape. The sender screen did not visibly show a livestream preview to the user; it showed Swap, one other control, and debug/status text. Receiver snapshots from that session showed the front camera rotated 90 degrees to the right, and the back camera was upside down in one image but correct in another. Therefore that old physical matrix remains useful for Wi-Fi decode/discovery/bandwidth evidence only; it is not accepted orientation evidence.

## Android Sender Preview Clarity Follow-up

The Android streaming screen now has an explicit `PREVIEW STARTING` / `PREVIEW LIVE` badge above a shorter compact strip that shows only preview state, camera, output rotation, and pairing code. The RTSP URL, profile summary, connection state, live bitrate, discovery state, and foldable camera diagnostics remain in the `Info` diagnostics panel for evidence collection. This addresses the Galaxy Z Fold review where the sender screen read as buttons plus debug text rather than an obvious local livestream preview.

Fresh Android build and JVM-test evidence after this UI change:

```text
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh
BUILD SUCCESSFUL in 1s
28 actionable tasks: 28 executed
BUILD SUCCESSFUL in 314ms
39 actionable tasks: 1 executed, 38 up-to-date

TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:36:21.937Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:36:21.951Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:36:21.952Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:36:21.956Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

The configuration contract now requires `previewBadgeText`, the `PREVIEW STARTING` default, the `PREVIEW LIVE` code path, explicit `Rotate Left` / `Rotate Right` controls, and the compact status strip capped to two lines. This is still source/build evidence only; the next physical run must visually confirm that the SurfaceView behind the badge is actually showing the live phone camera.

Fresh full local verification harness after the same UI change:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T06:36:16+03:00
Output: /private/tmp/phonecam-local-verification-20260523-063616

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-063616/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9625 fps, incoming 4.00961 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8181 fps, incoming 3.97818 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.APTuA1/receiver-frame.ppm
Fixture passed.
```

## Windows Collector Preflight-only Mode

`desktop/windows/scripts/Collect-PhoneCamWindowsEvidence.ps1` now supports `-PreflightOnly`. This lets the Windows operator validate the Android matrix, pair code or manual RTSP URL, receiver path, FFmpeg, Softcam DLL/installer, Ruby/PowerShell resolution, and elevation state without changing firewall state, attempting DirectShow capture, starting OBS/browser checks, or creating a final bundle.

Example:

```powershell
.\desktop\windows\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
  -PreflightOnly `
  -AndroidMatrix PATH\TO\matrix-evidence.json `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -PairCode PHONE_CODE
```

The package README now shows that preflight-only collector command before the real capture command. Static contracts verify that `-PreflightOnly` cannot be combined with `-FinalizeOnly`, that it exits after Windows runtime preflight, and that it exits before firewall setup or `Windows Android-to-DirectShow runtime evidence`.

Fresh verification after adding collector preflight-only mode:

```text
ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "workflow yaml ok"'
workflow yaml ok

bash -n scripts/build_android_debug.sh scripts/local_verification.sh scripts/smoke_receiver_fixture.sh scripts/mac_receiver_dev_smoke.sh scripts/mac_receiver_fixture_smoke.sh scripts/package_mac_receiver_app.sh scripts/android_device_smoke.sh scripts/android_rtsp_receiver_smoke.sh scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh
```

Fresh full local verification harness after the same change:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T06:40:51+03:00
Output: /private/tmp/phonecam-local-verification-20260523-064051

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-064051/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:40:56.828Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:40:56.844Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:40:56.845Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:40:56.849Z
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9048 fps, incoming 4.00162 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8814 fps, incoming 3.98692 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.3iJY1A/receiver-frame.ppm
Fixture passed.
```

## Windows Manual Evidence Screenshot Integrity

The final MVP validator and Windows manual-evidence validator now require OBS and browser/camera-app proof to be separate app screenshots. They reject reused `directshow-frame.bmp` snapshots and reject a single file reused for both OBS and browser/camera-app evidence. This keeps the DirectShow frame artifact as a lower-level virtual-camera capture while requiring separate application-level enumeration proof.

Fast checks after this hardening:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

PowerShell syntax parsing was not run on this macOS host because `pwsh` is not installed.

Fresh full local verification harness after the screenshot-integrity hardening:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T06:49:29+03:00
Output: /private/tmp/phonecam-local-verification-20260523-064929

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-064929/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

The first sandboxed harness attempt reached the Android step and failed because Gradle could not create its file-lock contention socket (`java.net.SocketException: Operation not permitted`). The same command passed outside the sandbox.

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:49:34.870Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:49:34.885Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:49:34.885Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:49:34.889Z
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.8349 fps, incoming 3.99194 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8723 fps, incoming 3.98566 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.LYBUZF/receiver-frame.ppm
Fixture passed.
```

## Android Front-Camera Orientation Artifact Fix

The physical Wi-Fi smoke script now uses the same `android-orientation-*` prefix for every front-camera orientation artifact it captures and validates. Before this fix, `collect_orientation_artifacts "$OUT_DIR/android-orientation"` wrote `android-orientation-accelerometer-rotation.txt` and `android-orientation-user-rotation.txt`, but later checks and JSON output referenced `android-accelerometer-rotation.txt` and `android-user-rotation.txt`. A real front-camera orientation run could therefore fail or emit broken artifact paths even after collecting the expected Android rotation settings.

Focused checks after the fix:

```text
bash -n scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/local_verification.sh

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh full local verification harness after the artifact-prefix fix:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T06:55:05+03:00
Output: /private/tmp/phonecam-local-verification-20260523-065505

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-065505/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:55:10.930Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:55:10.945Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:55:10.946Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T03:55:10.950Z
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.8607 fps, incoming 3.99551 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8069 fps, incoming 3.97664 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.MyfW60/receiver-frame.ppm
Fixture passed.
```

## Android Orientation Calibration Mode

The physical Wi-Fi smoke helper now supports `ORIENTATION_CALIBRATION=1`. This mode starts the Android RTSP server, records Wi-Fi state, then captures receiver snapshots at each 0/90/180/270 output rotation for the back camera and, when `VERIFY_FRONT_CAMERA=1`, the front camera. It writes `orientation-calibration.json`, `orientation-calibration-summary.txt`, per-rotation UI XML/screenshots, sender orientation dumps, receiver logs, and decoded PPM snapshots. The JSON is explicitly marked `finalMvpEvidence: false` with a `doesNotProve` list, because calibration only helps choose `STREAM_ROTATE_TAPS` and `FRONT_CAMERA_ROTATE_TAPS`; it does not replace the final accepted physical matrix.

No Android phone was attached during this local run:

```text
~/Library/Android/sdk/platform-tools/adb devices
List of devices attached
```

Focused checks after adding calibration mode:

```text
bash -n scripts/build_android_debug.sh scripts/smoke_receiver_fixture.sh scripts/mac_receiver_dev_smoke.sh scripts/mac_receiver_fixture_smoke.sh scripts/package_mac_receiver_app.sh scripts/android_device_smoke.sh scripts/android_rtsp_receiver_smoke.sh scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/local_verification.sh

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh full local verification harness after adding calibration mode:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T07:00:52+03:00
Output: /private/tmp/phonecam-local-verification-20260523-070051

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-070051/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:00:57.186Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:00:57.201Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:00:57.202Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:00:57.206Z
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.8798 fps, incoming 3.99815 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.912 fps, incoming 3.99114 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.Y6Lktn/receiver-frame.ppm
Fixture passed.
```

## Final Evidence Gate Hardening

The physical Wi-Fi smoke helper now marks final-mode `wifi-evidence.json` output as `finalMvpEvidence: true`. Exploratory Android evidence stays non-final: `ORIENTATION_CALIBRATION=1` writes `finalMvpEvidence: false`, and `ALLOW_UNVERIFIED_ORIENTATION=1` now marks both single-profile and matrix evidence as non-final. The final MVP validator rejects Android matrix evidence when the matrix root or any profile evidence is non-final, even if the surrounding matrix path is otherwise well formed. The Android-only preflight path used by the Windows collector now has explicit negative coverage for the same non-final matrix case.

Focused checks after the final/exploratory evidence split:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

git diff --check
warning: in the working copy of 'android/gradlew.bat', CRLF will be replaced by LF the next time Git touches it
```

Fresh full local verification harness after this hardening:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T07:19:23+03:00
Output: /private/tmp/phonecam-local-verification-20260523-071923

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-071923/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:19:29.249Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:19:29.264Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:19:29.265Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:19:29.268Z
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9273 fps, incoming 4.00473 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8067 fps, incoming 3.97661 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.6SV0jG/receiver-frame.ppm
Fixture passed.
```

## SurfaceView And RootEncoder Orientation Follow-up

The Galaxy Z Fold 5 review showed two live-device problems: the sender screen did not read as an obvious livestream preview, and the receiver snapshots were not consistently upright in fold-landscape posture. The Android sender now uses a `SurfaceView` preview instead of `TextureView`, starts preview through RootEncoder's `startPreview(surfaceView)` path, enables RootEncoder `autoHandleOrientation`, passes `CameraHelper.getCameraOrientation(this)` into `setOrientation(...)`, and waits for a RootEncoder `takePhoto(...)` preview-frame probe before showing `PREVIEW LIVE`. The app still records Camera2 sensor orientation, display rotation, RootEncoder rotation, and preview window size in `Camera diagnostics`, but those values are now diagnostics rather than app-owned rotation math. Per-camera output `Rotate` remains the acceptance correction mechanism.

Focused checks after the SurfaceView/RootEncoder patch:

```text
ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

bash -n scripts/android_device_smoke.sh scripts/android_wifi_receiver_smoke.sh

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

scripts/build_android_debug.sh
BUILD SUCCESSFUL in 1s
45 actionable tasks: 9 executed, 36 up-to-date
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:32:16.729Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:32:16.748Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:32:16.749Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:32:16.754Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

The first sandboxed full local verification attempt failed at Gradle with `java.net.SocketException: Operation not permitted` while creating the Gradle file-lock contention handler. This is the known Codex sandbox socket restriction, not an app failure. The same harness passed outside the sandbox:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T07:32:28+03:00
Output: /private/tmp/phonecam-local-verification-20260523-073228

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-073228/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:32:34.320Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:32:34.335Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:32:34.336Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:32:34.340Z
```

Fresh receiver CTest from that harness:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.25 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.26 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.26 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.26 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.26 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.05 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.35 sec
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9296 fps, incoming 4.00505 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8626 fps, incoming 3.98433 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.AVtzpt/receiver-frame.ppm
Fixture passed.
```

## Preview Evidence Gate Follow-up

The final Android evidence validator now rejects a physical Wi-Fi run unless each profile's structured `wifi-evidence.json` records `previewLive: true`. This directly covers the Galaxy Z Fold 5 feedback where the sender screen did not show an obvious livestream preview even though receiver-side decode artifacts existed. `scripts/check_windows_static_contracts.rb` now includes a negative fixture for `previewLive: false`, so the final MVP gate cannot silently accept a run where the SurfaceView preview never reached `Preview: live`.

Follow-up hardening: `scripts/android_wifi_receiver_smoke.sh` now also fails the physical Wi-Fi capture itself when `Preview: live` is absent. That means bad sender-preview evidence is rejected at collection time, before the Android profile matrix or final MVP validator sees it.

Second follow-up hardening: `scripts/android_device_smoke.sh` now exits nonzero when critical app smoke checks fail, including missing live preview, unchanged Rotate output, failed front-camera switch, crash markers, or stream-configuration failure markers. The physical profile matrix summary now also includes each profile's `previewLive` value next to the observed pairing code and RTSP URL, so Android handoff evidence makes the live-preview state visible without opening every per-profile `wifi-evidence.json`.

Windows evidence hardening: the final Ruby validator and PowerShell manual-evidence validator now require OBS and browser/camera-app screenshot artifacts to have PNG, JPEG, or BMP signatures. This prevents a non-empty text placeholder from satisfying the manual app enumeration evidence requirement.

Focused checks after the preview-evidence gate:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

bash -n scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/android_device_smoke.sh

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh full local verification:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T07:38:36+03:00
Output: /private/tmp/phonecam-local-verification-20260523-073836

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-073836/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:38:42.399Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:38:42.415Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:38:42.415Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:38:42.419Z
```

Fresh receiver CTest from that harness:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.26 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.26 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.26 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.26 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.24 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.03 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.32 sec
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 59 frames, avg 29.0282 fps, incoming 4.01287 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8554 fps, incoming 3.98333 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.qWHia3/receiver-frame.ppm
Fixture passed.
```

`git diff --check` passed in the harness with the existing warning that `android/gradlew.bat` uses CRLF and would be rewritten by Git if touched.

Fresh full local verification after making the physical Wi-Fi helper fail when `Preview: live` is absent:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T07:43:18+03:00
Output: /private/tmp/phonecam-local-verification-20260523-074318

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-074318/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:43:23.639Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:43:23.654Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:43:23.655Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:43:23.658Z
```

Fresh receiver CTest from that harness:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.26 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.26 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.26 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.26 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.26 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.05 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.36 sec
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 59 frames, avg 28.945 fps, incoming 4.00137 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.9286 fps, incoming 3.99343 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.kZmtQK/receiver-frame.ppm
Fixture passed.
```

Fresh full local verification after making the lighter device smoke fail on critical warnings and adding `previewLive` to the matrix profile summary:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T07:47:09+03:00
Output: /private/tmp/phonecam-local-verification-20260523-074709

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-074709/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:47:15.317Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:47:15.332Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:47:15.332Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:47:15.336Z
```

Fresh receiver CTest from that harness:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.24 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.25 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.25 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.26 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.26 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.05 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.32 sec
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.9754 fps, incoming 4.0114 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.7817 fps, incoming 3.97315 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.kA9NkC/receiver-frame.ppm
Fixture passed.
```

Fresh full local verification after requiring image-like OBS/browser screenshot artifacts:

```text
RUN_RTSP_FIXTURE=1 MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/local_verification.sh
Generated: 2026-05-23T07:53:57+03:00
Output: /private/tmp/phonecam-local-verification-20260523-075357

PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check

Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-075357/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android JVM test XML summaries from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:54:03.115Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:54:03.130Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:54:03.131Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T04:54:03.135Z
```

Fresh receiver CTest from that harness:

```text
1/6 Test #1: phonecam-receiver-self-test ............................   Passed    0.23 sec
2/6 Test #2: phonecam-receiver-discovery-self-test ..................   Passed    2.23 sec
3/6 Test #3: phonecam-receiver-pair-code-discovery-self-test ........   Passed    2.25 sec
4/6 Test #4: phonecam-receiver-pair-code-mismatch-self-test .........   Passed    2.25 sec
5/6 Test #5: phonecam-receiver-auto-discovery-selection-self-test ...   Passed    2.25 sec
6/6 Test #6: phonecam-receiver-rtsp-open-failure ....................   Passed    0.05 sec
100% tests passed, 0 tests failed out of 6
Total Test time (real) =   9.27 sec
```

Fresh RTSP fixture details from that harness:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Auto-discovery self-test selected: rtsp://127.0.0.1:8555/phonecam-test
Opening rtsp://127.0.0.1:8555/phonecam-test with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8555, path=/phonecam-test
Headless/null sink active: 1280x720 @ 60 fps
Decoded 58 frames, avg 28.8541 fps, incoming 3.9946 Mbps, decode errors 0
Receiver summary: 60 frames, avg 28.8076 fps, incoming 3.97673 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.9zPr1z/receiver-frame.ppm
Fixture passed.
```

Fresh Mac receiver fixture and dev-app packaging check after the Z Fold 5 follow-up notes:

```text
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver KEEP_PHONECAM_FIXTURE_LOGS=1 scripts/mac_receiver_fixture_smoke.sh

First sandbox run failed at localhost bind:
ERR listen tcp :8565: bind: operation not permitted

Approved rerun passed:
Mac receiver dev evidence: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.Myp449/mac-evidence/mac-receiver-evidence.json
Opening rtsp://127.0.0.1:8565/phonecam-mac-dev with RTSP-over-TCP
Receiver target: host=127.0.0.1, port=8565, path=/phonecam-mac-dev
Headless/null sink active: 1280x720 @ 30 fps
Receiver summary: 30 frames, avg 27.8394 fps, incoming 3.92417 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.Myp449/mac-evidence/receiver-frame.ppm
Mac receiver fixture passed.
MediaMTX log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.Myp449/mediamtx.log
FFmpeg log: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-mac-helper-fixture.Myp449/ffmpeg.log
```

Structured Mac evidence summary:

```text
status: passed
generatedAt: 2026-05-23T04:58:56Z
sourceMode: direct-rtsp
macDevOnly: true
requestedFrames: 30
openedRtspUrl: rtsp://127.0.0.1:8565/phonecam-mac-dev
sinkResolution: 1280x720
sinkFps: 30.0
decode.frames: 30
decode.avgFps: 27.8394
decode.incomingMbps: 3.92417
decode.decodeErrors: 0
artifacts.snapshotPresent: true
doesNotProve: Windows DirectShow registration; PhoneCam Virtual Camera enumeration; OBS/browser camera picker rendering; Windows firewall or LAN behavior
```

Fresh macOS dev app package check:

```text
RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver OUTPUT_DIR=/private/tmp/phonecam-mac-app-20260523-0758 scripts/package_mac_receiver_app.sh
Mac receiver app: /private/tmp/phonecam-mac-app-20260523-0758/PhoneCam Receiver.app
This app is Mac development evidence only; it does not prove Windows DirectShow/OBS enumeration.

test -x /private/tmp/phonecam-mac-app-20260523-0758/PhoneCam\ Receiver.app/Contents/MacOS/phonecam-receiver
exit status: 0
```

This proves the shared native RTSP decode path and the macOS development wrapper still work on this Mac. It does not prove the Android sender's physical orientation behavior, the sender SurfaceView visual quality on the Galaxy Z Fold 5, Windows Softcam registration, Windows DirectShow frame capture, or OBS/browser enumeration.

## Absolute Rotation Target Follow-up

The physical Android Wi-Fi smoke and profile-matrix helpers now accept absolute output-rotation targets:

```text
STREAM_OUTPUT_ROTATION_DEGREES=0|90|180|270
FRONT_CAMERA_OUTPUT_ROTATION_DEGREES=0|90|180|270
```

This is intended for the Galaxy Z Fold 5 follow-up. The exploratory calibration run captures snapshots for each visible output rotation; the final acceptance run can now request the chosen upright output degree directly instead of relying on `STREAM_ROTATE_TAPS` or `FRONT_CAMERA_ROTATE_TAPS` from whatever rotation value happened to be persisted at app startup. After the explicit left/right UI patch, the helper chooses the shortest `Rotate Left` or `Rotate Right` path to the target and records the request mode, requested target degrees, applied direction/taps, final UI output rotation, screenshots, and diagnostics in `wifi-evidence.json`.

The older tap-count controls remain available for debugging:

```text
STREAM_ROTATE_TAPS=0..3
FRONT_CAMERA_ROTATE_TAPS=0..3
```

The helper rejects ambiguous input when both an absolute target and a tap count are supplied for the same camera. This is script-level evidence hardening only; it still needs a fresh physical Android run before orientation can be marked accepted.

Fresh focused checks for this change:

```text
bash -n scripts/build_android_debug.sh scripts/smoke_receiver_fixture.sh scripts/mac_receiver_dev_smoke.sh scripts/mac_receiver_fixture_smoke.sh scripts/package_mac_receiver_app.sh scripts/local_verification.sh scripts/android_device_smoke.sh scripts/android_rtsp_receiver_smoke.sh scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh
exit status: 0

ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

git diff --check
exit status: 0 with the known android/gradlew.bat CRLF warning
```

Fresh negative input checks that stop before adb work:

```text
STREAM_OUTPUT_ROTATION_DEGREES=45 scripts/android_wifi_receiver_smoke.sh
STREAM_OUTPUT_ROTATION_DEGREES must be 0, 90, 180, or 270.

STREAM_OUTPUT_ROTATION_DEGREES=90 STREAM_ROTATE_TAPS=1 scripts/android_wifi_receiver_smoke.sh
Use STREAM_OUTPUT_ROTATION_DEGREES or STREAM_ROTATE_TAPS, not both.

FRONT_CAMERA_OUTPUT_ROTATION_DEGREES=45 scripts/android_wifi_profile_matrix_smoke.sh
FRONT_CAMERA_OUTPUT_ROTATION_DEGREES must be 0, 90, 180, or 270.
```

## Explicit Rotate Left/Right Follow-up

The Android sender now exposes separate `Rotate Left` and `Rotate Right` controls on the streaming screen. `Rotate Left` applies `-90` degrees to the current camera's persisted output correction; `Rotate Right` applies `+90` degrees and keeps the existing `rotateStreamBtn` id so the smoke helpers can still drive clockwise rotation for calibration. The bottom control bar now uses weighted buttons across the screen so `Switch`, `Rotate Left`, `Rotate Right`, and `Stop` fit in a landscape foldable/phone viewport instead of relying on a wrap-content row.

This specifically addresses the Galaxy Z Fold 5 feedback where the front-camera output appeared rotated 90 degrees right. A human tester can now tap `Rotate Left` once for that case instead of cycling three times through a one-way rotate control. This is still source/build evidence only until the physical fold-mode run is repeated.

Fresh Android build and JVM test evidence:

```text
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh

First sandbox run failed before Gradle startup with:
java.net.SocketException: Operation not permitted

Approved rerun passed:
BUILD SUCCESSFUL
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:09:17.838Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:09:17.854Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:09:17.855Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:09:17.859Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh focused checks:

```text
bash -n scripts/android_device_smoke.sh scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh
exit status: 0

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

git diff --check
exit status: 0 with the known android/gradlew.bat CRLF warning
```

## Fresh Shortest-Path Rotation Plan Verification

After adding separate left/right rotation controls, the physical Wi-Fi smoke helper was hardened so absolute target degrees choose the shortest path: for example `0 -> 270` uses one `Rotate Left` tap instead of three `Rotate Right` taps. The self-test is intentionally placed before adb/APK/receiver checks so it can run while no phone is attached.

Fresh no-device checks:

```text
ROTATION_PLAN_SELF_TEST=1 scripts/android_wifi_receiver_smoke.sh
rotation plan self-test passed

bash -n scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/android_device_smoke.sh
exit status: 0

bash -n scripts/*.sh
exit status: 0

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

ruby -e 'require "yaml"; YAML.safe_load(File.read(".github/workflows/build.yml"), aliases: true); puts "workflow yaml ok"'
workflow yaml ok

git diff --check
exit status: 0 with the known android/gradlew.bat CRLF warning
```

The CI static-contract job and `scripts/local_verification.sh` now both run the rotation planning self-test, so shortest-path left/right rotation planning is guarded by the normal no-device verification path.

Fresh Android build and JVM test evidence:

```text
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh

First sandbox run failed before Gradle startup with:
java.net.SocketException: Operation not permitted

Approved rerun passed:
BUILD SUCCESSFUL
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:17:30.899Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:17:30.914Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:17:30.915Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:17:30.919Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh receiver build, CTest, and RTSP fixture evidence:

```text
cmake --build /private/tmp/phonecam-windows-receiver-build --config Release
[100%] Built target phonecam-receiver

ctest --test-dir /private/tmp/phonecam-windows-receiver-build -C Release --output-on-failure
100% tests passed, 0 tests failed out of 6
Total Test time (real) = 9.32 sec

MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver scripts/smoke_receiver_fixture.sh
Discovered Synthetic Android at rtsp://127.0.0.1:8555/phonecam-test (1280x720 @ 60 fps, 2.8 Mbps, sender 127.0.0.1, pair 123456)
Receiver summary: 60 frames, avg 28.8479 fps, incoming 3.98229 Mbps, decode errors 0
Fixture passed.
```

Fresh local verification harness evidence after wiring the rotation self-test into CI/local verification:

```text
RUN_ANDROID_BUILD=0 RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

First sandboxed run failed in receiver CTest discovery cases:
Failed to bind UDP discovery port 47821.

Approved rerun outside the sandbox passed:
Generated: 2026-05-23T08:22:46+03:00
Output: /private/tmp/phonecam-local-verification-20260523-082246
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
SKIP: Android debug build and fresh JVM tests disabled with RUN_ANDROID_BUILD=0
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-082246/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

## Rotation Evidence Gate Hardening

The final MVP evidence validator now rejects Android orientation evidence unless the physical Wi-Fi `wifi-evidence.json` records the explicit correction direction (`left` or `right`) and normalized output rotation degrees (`0`, `90`, `180`, or `270`). For absolute target mode, the validator also requires the requested target degrees to be normalized and to match the resulting output rotation for both direct/back and front-camera evidence. This prevents a stale, ambiguous, or internally inconsistent pre-left/right rotation artifact from satisfying the final Android matrix gate.

Fresh focused checks:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

bash -n scripts/*.sh
exit status: 0

ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "workflow yaml ok"'
workflow yaml ok
```

The static contract fixture now confirms the final validator accepts complete Android/Windows fixture evidence and rejects Android matrix evidence that omits `streamRotationDirection`/`streamOrientation.rotationDirection`, uses invalid stream output rotation degrees, or records absolute rotation targets that do not match the resulting stream/front-camera output rotation.

Fresh follow-up checks for requested-target/output consistency:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

bash -n scripts/*.sh
exit status: 0
```

Fresh local verification harness evidence:

```text
RUN_ANDROID_BUILD=0 RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T08:29:13+03:00
Output: /private/tmp/phonecam-local-verification-20260523-082913
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
SKIP: Android debug build and fresh JVM tests disabled with RUN_ANDROID_BUILD=0
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-082913/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh local verification harness evidence after requested-target/output consistency hardening:

```text
RUN_ANDROID_BUILD=0 RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T08:32:44+03:00
Output: /private/tmp/phonecam-local-verification-20260523-083244
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
SKIP: Android debug build and fresh JVM tests disabled with RUN_ANDROID_BUILD=0
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-083244/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Fresh Android build and JVM test evidence:

```text
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh

Approved rerun passed:
BUILD SUCCESSFUL
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:29:52.091Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:29:52.106Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:29:52.107Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:29:52.111Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

## Windows Handoff Rotation Contract Refresh

The generated Windows package README and checked-in Windows README now explicitly carry the same Android orientation contract enforced by `scripts/validate_mvp_evidence.rb`: physical-phone evidence must include recorded `Rotate Left`/`Rotate Right` direction, rotation request mode, normalized 0/90/180/270 output-rotation degrees, requested absolute target degrees when used, target/output consistency, posture, diagnostics, version-4 per-camera output rotation metadata, and fixed-landscape lock metadata before Windows DirectShow evidence can be collected.

Fresh focused checks:

```text
ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

bash -n scripts/*.sh
exit status: 0

ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "workflow yaml ok"'
workflow yaml ok

git diff --check
exit status: 0 with the known android/gradlew.bat CRLF warning

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh local verification harness evidence after the Windows handoff rotation-contract refresh:

```text
RUN_ANDROID_BUILD=0 RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T08:39:12+03:00
Output: /private/tmp/phonecam-local-verification-20260523-083912
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
SKIP: Android debug build and fresh JVM tests disabled with RUN_ANDROID_BUILD=0
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-083912/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

## Android Preview Watchdog Follow-up

The Android sender now treats the SurfaceView preview-frame probe as an ongoing liveness signal rather than a one-shot check. If RootEncoder's `takePhoto(...)` preview probe does not return within `2500ms`, the UI switches from `PREVIEW STARTING` to `PREVIEW CHECKING`, the status line reports `Preview: not confirmed`, and the app retries the probe every `1000ms` until a real preview frame is observed. The status remains `not confirmed` during retry attempts after the first timeout, so physical QA does not confuse a retrying probe with confirmed live preview. This is meant to make the next Galaxy Z Fold 5 run easier to interpret: a visible `PREVIEW LIVE` badge still means the local sender preview was confirmed, while `PREVIEW CHECKING` is explicit evidence that the sender surface was not yet proven live.

Fresh Android build and JVM test evidence:

```text
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh

Approved rerun passed:
BUILD SUCCESSFUL
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:44:03.287Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:44:03.302Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:44:03.303Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:44:03.307Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh rerun after keeping the retrying preview-probe state visibly `not confirmed` until a real preview frame is observed:

```text
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh

Approved rerun passed:
BUILD SUCCESSFUL
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:47:17.303Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:47:17.320Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:47:17.321Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:47:17.326Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh full local verification harness evidence after the preview-state ordering follow-up:

```text
RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T08:48:21+03:00
Output: /private/tmp/phonecam-local-verification-20260523-084821
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-084821/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Android JVM test timestamps from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:48:27.294Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:48:27.309Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:48:27.310Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:48:27.314Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh focused checks:

```text
ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

bash -n scripts/*.sh
exit status: 0

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok

git diff --check
exit status: 0 with the known android/gradlew.bat CRLF warning
```

Fresh local verification harness evidence after the preview watchdog patch:

```text
RUN_ANDROID_BUILD=0 RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T08:44:26+03:00
Output: /private/tmp/phonecam-local-verification-20260523-084426
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
SKIP: Android debug build and fresh JVM tests disabled with RUN_ANDROID_BUILD=0
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-084426/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

## Android Sender Visual Evidence Gate Follow-up

The final MVP validator now treats Android sender screenshots as real visual artifacts, not just path strings. Each physical Android profile must include the compact pre-diagnostics streaming screenshot, the diagnostics-expanded streaming screenshot, rotation screenshot, and front-camera switch/rotation screenshots as non-empty PNG/JPEG/BMP image files. This tightens the next Galaxy Z Fold 5 evidence run around the previous user-observed issue where the sender screen did not visibly show an obvious livestream.

Fresh focused checks after tightening Android screenshot validation:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

bash -n scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/build_android_debug.sh scripts/local_verification.sh
exit status: 0

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh Android build/JVM test evidence after the Android screenshot validation gate:

```text
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh

Initial sandboxed attempt failed before build start:
Gradle could not create FileLockContentionHandler because java.net.SocketException: Operation not permitted.

Approved rerun outside the sandbox passed:
BUILD SUCCESSFUL
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:55:50.791Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:55:50.807Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:55:50.808Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T05:55:50.812Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Fresh full local verification harness evidence after the Android sender visual evidence gate:

```text
RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T08:56:08+03:00
Output: /private/tmp/phonecam-local-verification-20260523-085608
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-085608/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

## Android Compact Preview UI Gate Follow-up

The final MVP validator now cross-checks the compact pre-diagnostics Android UI dump itself. In addition to `previewLive: true` and valid screenshot image files, each physical Android profile must now have a compact sender UI dump containing `PREVIEW LIVE`, and the diagnostics-expanded streaming UI dump must contain `Preview: live`. This is a direct guard for the Galaxy Z Fold feedback where the sender screen did not make the live preview obvious before diagnostics were opened.

Fresh focused checks after requiring compact `PREVIEW LIVE` UI text:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

bash -n scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/build_android_debug.sh scripts/local_verification.sh
exit status: 0

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh full local verification harness evidence after the compact preview UI gate:

```text
RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T09:00:32+03:00
Output: /private/tmp/phonecam-local-verification-20260523-090032
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-090032/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Android JVM test timestamps from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:00:38.818Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:00:38.833Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:00:38.834Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:00:38.838Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

## Windows Manual Screenshot Content Gate Follow-up

The final MVP validator and Windows manual-evidence validator now hash OBS/browser screenshot files and the saved DirectShow frame snapshot. The completed Windows evidence must use separate OBS and browser/camera-app screenshot files with different image content, and neither app screenshot may duplicate the saved `directshow-frame.bmp` content. This prevents a final evidence bundle from passing with copied screenshots under different filenames.

Fresh focused checks after content-hash screenshot validation:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

bash -n scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/build_android_debug.sh scripts/local_verification.sh
exit status: 0

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh full local verification harness evidence after the Windows screenshot-content gate:

```text
RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T09:06:24+03:00
Output: /private/tmp/phonecam-local-verification-20260523-090624
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-090624/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Android JVM test timestamps from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:06:30.637Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:06:30.652Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:06:30.653Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:06:30.657Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

## Windows DirectShow Snapshot Image Gate Follow-up

The final MVP validator and Windows runtime helper now require the saved DirectShow frame snapshot to be a readable PNG, JPEG, or BMP image artifact, not only a non-empty file. The runtime helper fails immediately if FFmpeg writes a snapshot file that does not have a supported image signature, and the final MVP validator rejects runtime evidence whose `capture.snapshot` is text or another non-image file.

Fresh focused checks after requiring DirectShow snapshot image evidence:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

bash -n scripts/android_wifi_receiver_smoke.sh scripts/android_wifi_profile_matrix_smoke.sh scripts/build_android_debug.sh scripts/local_verification.sh
exit status: 0

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh full local verification harness evidence after the DirectShow snapshot image gate:

```text
RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T09:11:15+03:00
Output: /private/tmp/phonecam-local-verification-20260523-091115
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-091115/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Android JVM test timestamps from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:11:22.085Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:11:22.100Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:11:22.101Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:11:22.107Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

## Android Receiver Snapshot Image Gate Follow-up

The final MVP validator now requires Android direct LAN, pair-code discovery, and front-camera decoded receiver snapshots to be actual image artifacts. The helper writes PPM snapshots today, and the validator accepts PPM, PNG, JPEG, or BMP signatures while rejecting text or other non-image files. This closes the Android side of the same evidence gap already closed for the Windows DirectShow snapshot: a final evidence bundle cannot pass with a non-empty but bogus receiver-frame file.

Fresh focused checks after requiring Android receiver snapshot image evidence:

```text
ruby -c scripts/validate_mvp_evidence.rb
Syntax OK

ruby -c scripts/check_windows_static_contracts.rb
Syntax OK

ruby scripts/check_windows_static_contracts.rb
windows static contracts ok
```

Fresh full local verification harness evidence after the Android receiver snapshot image gate:

```text
RUN_RTSP_FIXTURE=1 scripts/local_verification.sh

Approved run outside the sandbox passed:
Generated: 2026-05-23T09:20:04+03:00
Output: /private/tmp/phonecam-local-verification-20260523-092004
PASS: Ruby syntax check validate_mvp_evidence
PASS: Ruby syntax check bundle_mvp_evidence
PASS: Ruby syntax check static contracts
PASS: Workflow YAML parse
PASS: Shell syntax check
PASS: Android rotation plan self-test
SKIP: PowerShell syntax check unavailable: pwsh not found
PASS: Windows/static evidence contracts
PASS: Android debug build and fresh JVM tests
PASS: Receiver build
PASS: Receiver CTest
PASS: macOS dev app package
PASS: macOS dev app bundle sanity
PASS: Synthetic RTSP receiver fixture
PASS: Git diff whitespace check
Local verification passed.
Summary: /private/tmp/phonecam-local-verification-20260523-092004/summary.txt
Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration.
```

Android JVM test timestamps from that harness:

```text
TEST-com.phonecam.AndroidConfigurationContractTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:20:11.455Z
TEST-com.phonecam.CameraOrientationMathTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:20:11.470Z
TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml: tests=4 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:20:11.471Z
TEST-com.phonecam.StreamProfileTest.xml: tests=3 failures=0 errors=0 skipped=0 timestamp=2026-05-23T06:20:11.475Z
APK: /Users/alpyalay/Documents/GitHub/PhoneCamRedux/android/app/build/outputs/apk/debug/app-debug.apk
```

Synthetic RTSP fixture evidence from the same harness:

```text
Receiver summary: 60 frames, avg 28.7244 fps, incoming 3.96525 Mbps, decode errors 0
Snapshot written: /var/folders/jn/0l78_s69583gnmp32y1gn0j00000gn/T//phonecam-fixture.OYx8R3/receiver-frame.ppm
Fixture passed.
```

## Still Required On Windows

- Build the receiver with a Windows LGPL FFmpeg distribution.
- Build the PhoneCam-branded Softcam fork from `desktop/windows/scripts/Prepare-PhoneCamSoftcam.ps1`.
- Let GitHub Actions or a Windows host run the new Softcam-linked receiver build job.
- Register `PhoneCam Virtual Camera` on a Windows host.
- If auto-discovery fails while manual RTSP works, run `desktop/windows/scripts/Install-PhoneCamFirewallRules.ps1` from an elevated PowerShell and retry discovery.
- Run `desktop/windows/scripts/Test-PhoneCamWindowsRuntime.ps1` with `-AutoDiscover -PairCode PHONE_CODE -KeepReceiverRunning` or `-RtspUrl rtsp://PHONE_IP:8554/ -KeepReceiverRunning` to register Softcam, feed a real Android RTSP stream into `PhoneCam Virtual Camera`, enumerate it through FFmpeg DirectShow, capture frames plus `directshow-frame.bmp` from the virtual camera, then keep the same stream live for OBS/browser camera-picker evidence.
- Confirm `PhoneCam Virtual Camera` appears in OBS and at least one browser/camera app.
- Fill and validate the generated `manual-app-evidence-template.json` with `Test-PhoneCamWindowsRuntime.ps1 -ValidateManualEvidence ... -RuntimeEvidence ...`, keeping the generated `receiverProcessId` and template path tied to the same live receiver.
- Confirm `Test-PhoneCamWindowsRuntime.ps1 -SoftcamRoot C:\deps\phonecam-softcam -UnregisterOnly` removes the camera cleanly after OBS/browser evidence is captured.
- Run `ruby scripts/validate_mvp_evidence.rb --android-matrix MATRIX_JSON --windows-runtime RUNTIME_JSON --windows-manual MANUAL_JSON` after both Android and Windows evidence sets are captured.

## Still Required With Physical Android Hardware

- Re-run the physical Android Wi-Fi profile matrix after installing the current APK. Include `STREAM_DEVICE_POSTURE` and `FRONT_CAMERA_DEVICE_POSTURE`, inspect the receiver snapshots/live output, set `STREAM_OUTPUT_ROTATION_DEGREES` for the direct/back pass and `FRONT_CAMERA_OUTPUT_ROTATION_DEGREES` for the front pass if either output needs correction, and set `STREAM_ORIENTATION_STATUS=passed` plus `FRONT_CAMERA_ORIENTATION_STATUS=passed` only when direct/back and front output are upright in landscape. Rotate corrections are intentionally per-camera; use absolute output-rotation targets from calibration instead of assuming a tap count from a previous persisted starting state.
- During that rerun, explicitly confirm the sender screen shows a live local SurfaceView preview behind the compact status strip, and use `Info` only when capturing diagnostics. The previous Galaxy Z Fold 5 run did not make the preview visually obvious to the user.
- The old matrix at `/private/tmp/phonecam-android-wifi-profile-matrix-20260523-003143` remains useful for Wi-Fi decode/discovery/bandwidth evidence, but it is no longer an orientation acceptance artifact.
- Additional Android follow-up: longer latency/frame-drop/thermal soak, more physical phone models, more LAN/router topologies, and real Android-to-Windows Wi-Fi behavior once a Windows host is available.
