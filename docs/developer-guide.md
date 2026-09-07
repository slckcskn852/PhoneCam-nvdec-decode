# Developer build and verification guide

Run commands in this guide from the repository root. For the main setup and current feature overview, see the [README](../README.md).

PhoneCamRedux streams Android or iOS camera video to a desktop receiver. Windows virtual-camera output uses PhoneCam-branded DirectShow Softcam. macOS has a working receiver/decode path; its CMIO camera extension is still a skeleton.

The native HEVC path targets 4K60 and 1080p120/240 when the phone camera, encoder, network, Windows GPU and consuming app support the mode. These are hardware validation targets, not verified universal performance claims. See [release readiness and validation](release-readiness.md) before distributing or advertising them.

## Easy home-network setup

1. Open `phonecam-receiver.exe` on your Windows computer and allow Private-network access.
2. Open PhoneCam on your phone, tap **Find my computer**, and choose the computer name.
3. Allow camera/local-network access. Select **PhoneCam Virtual Camera** in your calling app when the virtual-camera component is installed.

If discovery does not cross a second home router, enter the PC code shown on the receiver. The phone opens the connection toward the PC and retries while the app stays open. Automatic mode prefers 1080p60, then 1080p30. Isolated guest networks still require a reachable network. See [setup, router arrangements, and latency behavior](easy-connection.md).

## Streaming paths

- Native HEVC: RTP/UDP media on `5004`, control on `47822`, adaptive jitter buffering (starts at 10 ms, range 5–50 ms; fixed override available), a 2048-packet retransmission history and bandwidth adaptation.
- Easy connection: phone-initiated native TCP to the PC on `47823`, Bonjour computer discovery, PC address codes, and foreground reconnect.
- Wired/native TCP: length-prefixed control/media on `47822`, with zero added playout delay by default. ADB/usbmux port forwarding is a development setup; TCP can still incur queueing and head-of-line delay.
- Android RTSP fallback: H.264/RTSP on `8554`, with the existing preview, pairing-code discovery and orientation controls.
- Windows: optional D3D11VA decoding, reusable BGR buffers, bounded latest-frame output and patched Softcam timing through 240 FPS. GPU readback and BGR copies remain.
- Receiver access is an explicit foreground opt-in on mobile. The LAN protocol is unencrypted and discovery codes are selectors, not authentication. Use a trusted LAN during development.

For advanced native UDP mode, expand **Advanced connection options** and enable receiver access on your phone, then run:

```powershell
phonecam-receiver.exe --rtsp udp://PHONE_IP:5004 --width 3840 --height 2160 --fps 60
phonecam-receiver.exe --rtsp udp://PHONE_IP:5004 --width 1920 --height 1080 --fps 240 --jitter-ms 20
```

Unavailable camera/encoder combinations are rejected; lower exposed modes remain available. The native Android mode feeds only the encoder surface to preserve constrained high-speed compatibility. The RTSP orientation evidence below does not certify the native path.

## Build Instructions

### Android Sender Build
```bash
cd android
./gradlew :app:testDebugUnitTest :app:assembleDebug --console=plain
```
Or use the local helper script:
```bash
scripts/build_android_debug.sh
```

### iOS Sender Build
To compile the iOS app target and run unit tests on the simulator:
```bash
# Build device target
xcodebuild -project ios/PhoneCamSend.xcodeproj -scheme PhoneCamSend -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO

# Run simulator unit tests
xcodebuild test -project ios/PhoneCamSend.xcodeproj -scheme PhoneCamSend -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID'
```

For fresh unit-test XML timestamps in verification runs, use:

```bash
FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh
```

APK:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

## Android RTSP fallback usage

Expand **Advanced connection options** for this legacy workflow.

1. Install and open the Android app.
2. Grant camera permission.
3. Choose Efficient, Balanced, or Motion.
4. Note the six-digit pairing code if more than one phone may be on the LAN.
5. Tap `Start Camera Server`.
6. If the receiver output is sideways or upside down, tap `Rotate Left` or `Rotate Right` until the current camera's webcam output is upright.
7. Use receiver auto-discovery or the shown URL, typically:

```text
rtsp://PHONE_IP:8554/
```

The streaming overlay keeps a `PREVIEW LIVE` badge and a compact camera/pairing/rotation strip visible while leaving the SurfaceView preview exposed. If the preview-frame probe stalls, the badge switches to `PREVIEW CHECKING`, the status line says `Preview: not confirmed`, and the app retries the probe until a real preview frame is observed. Tap `Info` to open the full diagnostics panel with RTSP URL, front/back camera, RootEncoder input rotation, output rotation, receiver connection state, live bitrate, discovery status, and foldable camera diagnostics; tap `Hide` to return to the cleaner preview. The selected profile and Rotate correction are saved. The Rotate button is camera-specific, so a back-camera correction does not carry over to the front camera after `Switch`. `Stop` releases the camera session instead of leaving a hidden preview prepared behind the connection screen.

Device or emulator smoke QA helper:

```bash
scripts/android_device_smoke.sh
```

Android RTSP sender to native receiver smoke helper:

```bash
scripts/android_rtsp_receiver_smoke.sh
```

This uses adb port forwarding to connect the local receiver to the Android RTSP server. It is useful emulator/device evidence for the sender and decoder path, but it is not a substitute for physical Wi-Fi validation.

Physical Android Wi-Fi sender to native receiver smoke helper:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_receiver_smoke.sh
```

This selects a non-emulator adb target by default, refuses emulator targets unless explicitly allowed, extracts the phone's LAN RTSP URL and pairing code from the Android UI, captures Android Wi-Fi/network state, decodes frames from the direct LAN URL, records receiver FPS/bitrate/decode-error metrics, tries pair-code auto-discovery, then switches to the front camera and decodes again. Prefer `STREAM_OUTPUT_ROTATION_DEGREES=0|90|180|270` and `FRONT_CAMERA_OUTPUT_ROTATION_DEGREES=0|90|180|270` after a calibration pass; the helper reads the current UI `Output rotation`, chooses the shortest `Rotate Left` or `Rotate Right` path to the target, and records the actual applied direction and tap count. The older `STREAM_ROTATE_TAPS=0..3` and `FRONT_CAMERA_ROTATE_TAPS=0..3` controls are still available for direct tap-count debugging. The JSON records the request mode, requested target degrees, applied direction/taps, resulting UI `Output rotation` degrees, whether the local SurfaceView reached `Preview: live`, and the Android sender's `Camera diagnostics` line. It also captures decoded receiver frame snapshots, Android UI XML, compact pre-diagnostics sender screenshots, diagnostics-expanded screenshots, display/window/input rotation artifacts, and logcat files for direct/back and front-camera passes. It writes `summary.txt`, receiver/logcat/network/orientation/UI/screenshot/snapshot artifacts, and structured `wifi-evidence.json` under `/private/tmp/phonecam-android-wifi-receiver-*`. The helper exits nonzero if the sender never reaches `Preview: live`. Final MVP validation requires `previewLive: true`, a compact sender UI dump containing `PREVIEW LIVE`, pair-code discovery decode evidence, valid PPM/PNG/JPEG/BMP decoded frame snapshots, Wi-Fi network evidence, zero decode errors, profile-bounded incoming Mbps, captured Android UI artifacts, valid PNG/JPEG/BMP Android sender screenshots, output rotation degrees, `STREAM_DEVICE_POSTURE`, `FRONT_CAMERA_DEVICE_POSTURE`, sender camera diagnostics, and manually confirmed physical direct/back plus front-camera orientation with notes to pass, not just manual RTSP fallback. By default the helper now fails before touching the phone unless those orientation acceptance fields are already supplied; set `ALLOW_UNVERIFIED_ORIENTATION=1` only for exploratory capture, which will still fail final MVP validation.

For the Galaxy Z Fold orientation issue, run a calibration pass before final evidence:

```bash
ORIENTATION_CALIBRATION=1 CALIBRATION_FRAMES=20 \
  RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_receiver_smoke.sh
```

That writes `orientation-calibration.json`, `orientation-calibration-summary.txt`, UI/screenshot artifacts, and receiver snapshots for each 0/90/180/270 output rotation for the back camera and, when enabled, the front camera. It is deliberately marked non-final; inspect those snapshots, choose the upright output rotation degrees, then rerun the full profile matrix with `STREAM_OUTPUT_ROTATION_DEGREES` and `FRONT_CAMERA_OUTPUT_ROTATION_DEGREES`. This avoids relying on persisted starting rotation state from an earlier run.

The lighter `scripts/android_device_smoke.sh` also checks for `Preview: live`, taps `Rotate` once, and verifies that the UI `Output rotation` value changes. It now exits nonzero if the app fails to reach the streaming screen, the local preview never reports live, Rotate does not change the output rotation, Switch does not reach front-camera status, or logcat contains crash/stream-configuration markers. That proves the preview/status/control wiring; it does not prove physical camera orientation.

Full physical profile matrix helper:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_profile_matrix_smoke.sh
```

This runs Efficient, Balanced, and Motion in separate app launches, verifies each profile summary, decodes each profile over direct LAN RTSP, requires pair-code auto-discovery decode for each profile by default, records receiver FPS/bitrate/decode-error metrics and decoded PPM frame snapshots, and runs the front-camera switch/decode/orientation check on the final profile. It writes top-level `summary.txt` and `matrix-evidence.json` files under `/private/tmp/phonecam-android-wifi-profile-matrix-*`, plus per-profile evidence folders with `wifi-evidence.json`. The matrix JSON summarizes each profile's observed pairing code, RTSP URL, live-preview status, and whether unverified orientation collection was explicitly allowed.

Mac receiver dev helper:

```bash
RTSP_URL=rtsp://PHONE_IP:8554/ RECEIVER_BIN=/path/to/phonecam-receiver \
  scripts/mac_receiver_dev_smoke.sh
```

When `RTSP_URL` is omitted, the helper uses `--auto-discover` and can filter with `PAIR_CODE=123456`. It writes stdout/stderr logs, `receiver-frame.ppm`, and `mac-receiver-evidence.json`. This is shared transport/decode/discovery evidence only; it explicitly does not prove Windows DirectShow registration or OBS/browser camera enumeration.

For a local synthetic Mac check without a phone, run:

```bash
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx \
  RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver \
  scripts/mac_receiver_fixture_smoke.sh
```

On Apple hosts, the receiver also has a Cocoa preview sink. Add `PREVIEW=1` to the Mac helper to exercise the local preview window while still keeping the evidence marked as Mac-dev-only.

You can also package the preview-capable receiver as a local development app:

```bash
scripts/package_mac_receiver_app.sh
```

The app bundle is written to `dist/PhoneCam-Mac/PhoneCam Receiver.app`. Opening it waits briefly for an Android PhoneCam discovery beacon and then shows the Cocoa preview for the decoded stream. This is a Mac development aid only; it does not register a Windows camera, does not prove DirectShow, and does not replace the Windows Softcam/OBS evidence path.

### Windows Receiver Build

**Requirements:**
- Visual Studio 2022 with Desktop development with C++.
- LGPL-clean dynamic FFmpeg build.
- [tshino/softcam](https://github.com/tshino/softcam) for DirectShow virtual camera output.

```powershell
cmake -S desktop/windows -B build/windows-receiver `
  -DFFMPEG_ROOT=C:\deps\ffmpeg `
  -DSOFTCAM_ROOT=C:\deps\softcam `
  -DPHONECAM_WITH_SOFTCAM=ON

cmake --build build/windows-receiver --config Release
```
Run the executable:
```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe
```

### macOS Receiver & Extension Build

**Requirements:**
- Xcode 13+ or Command Line Tools.
- FFmpeg libraries (available via `brew install ffmpeg`).

```bash
# Generate build configuration and compile
cmake -S . -B build/macos -G Xcode
cmake --build build/macos --config Release
```
For local testing, ad-hoc sign the built bundle:
```bash
codesign --force --sign - --entitlements desktop/macos/ents.plist build/macos/Release/phonecam-receiver
codesign --force --sign - --entitlements desktop/macos/extension.plist build/macos/Release/PhoneCam\ Receiver.app/Contents/Library/SystemExtensions/com.phonecam.redux.Extension.systemextension
```

Windows no-argument startup opens a connection window and waits for your phone. `--listen` selects the same behavior with additional options. `--auto-discover` explicitly selects legacy phone-beacon discovery. Manual RTSP URL fallback:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --rtsp rtsp://PHONE_IP:8554/ --fps 60
```

Auto-discover a running phone on the same LAN:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --auto-discover --discover-seconds 5 --fps 60
```

Filter discovery to the phone showing a specific pairing code:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --auto-discover --pair-code 123456 --discover-seconds 5 --fps 60
```

List discovered phones without connecting:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --discover --discover-seconds 5
```

If Softcam is linked and registered, select the registered Softcam/PhoneCam virtual camera in OBS, Zoom, Teams, Discord, or a browser camera test. The visible camera name is controlled by the registered Softcam filter build; the MVP sender does not rename the DirectShow device at runtime.

Headless CI/smoke-test mode:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --self-test --frames 5 --fps 30 --no-preview --no-softcam
```

Discovery smoke test:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --discovery-self-test
```

CTest wrapper for the receiver smoke tests:

```powershell
ctest --test-dir build/windows-receiver -C Release --output-on-failure
```

Auto-discovery plus local RTSP fixture:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe `
  --auto-discover-self-test rtsp://127.0.0.1:8555/phonecam-test `
  --pair-code 123456 --frames 60 --no-preview --no-softcam
```

Local helper for the same MediaMTX/FFmpeg receiver fixture:

```bash
MEDIAMTX_BIN=/path/to/mediamtx RECEIVER_BIN=/path/to/phonecam-receiver \
  scripts/smoke_receiver_fixture.sh
```

The helper uses host RTSP port `8555` and pair-code filter `123456` by default to avoid collisions with the Android app's normal `8554` port when an emulator is running.
It forces MediaMTX and FFmpeg to RTSP-over-TCP, matching the receiver path and avoiding MediaMTX's UDP RTP/RTCP listener ports during local fixture runs.

If auto-discovery does not find the phone on a Windows private LAN but the manual RTSP URL works, add scoped firewall rules for the receiver:

```powershell
.\desktop\windows\scripts\Install-PhoneCamFirewallRules.ps1 `
  -Receiver .\build\windows-receiver\Release\phonecam-receiver.exe
```

Windows helper for the same fixture:

```powershell
.\desktop\windows\scripts\Test-PhoneCamReceiverFixture.ps1 `
  -Receiver .\build\windows-receiver\Release\phonecam-receiver.exe `
  -MediaMtx C:\deps\mediamtx\mediamtx.exe `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe
```

Windows DirectShow runtime verification after building the Softcam-required receiver:

Prerequisites for the final Windows evidence pass: an elevated PowerShell session, an LGPL-clean `ffmpeg.exe` for DirectShow capture, and Ruby available as `ruby` on PATH. If Ruby is installed elsewhere, pass `-Ruby C:\path\to\ruby.exe` to `Collect-PhoneCamWindowsEvidence.ps1`; the collector uses it for the Android matrix preflight, final MVP validator, and evidence bundler.

```powershell
.\desktop\windows\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
  -PreflightOnly `
  -AndroidMatrix PATH\TO\matrix-evidence.json `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -PairCode PHONE_CODE
```

This preflight-only collector pass validates the Android matrix, pair code or manual RTSP URL, receiver path, FFmpeg, Softcam DLL/installer, Ruby/PowerShell resolution, and elevation state, then writes `windows-preflight-summary.txt` and `windows-preflight-evidence.json` without registering/capturing DirectShow, installing firewall rules, launching OBS/browser checks, or bundling final evidence.

```powershell
.\desktop\windows\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
  -AndroidMatrix PATH\TO\matrix-evidence.json `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -PairCode PHONE_CODE `
  -InstallFirewallRules
```

Use the collector for the real MVP run: it performs the preflight, optional private-LAN firewall setup, pair-code discovery, DirectShow capture, and keeps the receiver alive for OBS/browser evidence. When `-PairCode` is used, the collector normalizes the typed value to digits, requires exactly six digits, and compares it with the stable six-digit code recorded in the Android matrix before Windows preflight or DirectShow registration starts; a typo fails early. When manual `-RtspUrl` is used, the collector also checks that URL against the physical Android matrix before Windows preflight or DirectShow registration starts. The final collector refuses `-SkipPreflight`; use `Test-PhoneCamWindowsRuntime.ps1` directly for debug-only experiments. Use `-RtspUrl rtsp://PHONE_IP:8554/` instead of `-PairCode PHONE_CODE` only when UDP discovery is blocked. After filling the generated manual evidence template, run the same collector with `-FinalizeOnly -AndroidMatrix ... -RuntimeEvidence ... -ManualEvidence ...` to validate and bundle the final evidence.

The collector always validates the Android matrix first, before Windows preflight, DirectShow registration, or `-FinalizeOnly` bundling:

```bash
ruby scripts/validate_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --android-only
```

Use this locally before moving to Windows. It must pass with fresh physical Android evidence, including live-preview status, output-rotation artifacts, versioned direct/back and front orientation evidence, and device posture, so the Windows run cannot accidentally build final evidence on top of a stale Android matrix.

Before copying Android evidence to Windows, create an Android-only handoff bundle so the matrix and per-profile artifact paths are portable:

```bash
ruby scripts/bundle_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --android-only \
  --output-dir /path/to/PhoneCam-Android-Matrix-Handoff
```

Copy that whole folder to Windows and pass its bundled `android/matrix-evidence.json` path to `Collect-PhoneCamWindowsEvidence.ps1`. This bundle validates the physical Android matrix, rewrites JSON artifact references to relative paths, and does not claim Windows DirectShow or OBS/browser evidence.

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -Register `
  -PreflightOnly
```

This writes `windows-preflight-summary.txt` and `windows-preflight-evidence.json` without registering Softcam or capturing DirectShow frames. Use it first to catch missing receiver, FFmpeg, Softcam DLL/installer, or elevation prerequisites.

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -Register `
  -UnregisterAfter
```

That default path validates generated receiver frames through the registered DirectShow camera and writes `runtime-summary.txt` plus structured `runtime-evidence.json` under `%TEMP%\phonecam-windows-runtime-*`. For the actual Android-to-Windows path, start the Android camera server on the same LAN and run either pair-code auto-discovery:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -AutoDiscover `
  -PairCode PHONE_CODE `
  -DiscoverSeconds 10 `
  -Register `
  -KeepReceiverRunning
```

or manual RTSP fallback:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -RtspUrl rtsp://PHONE_IP:8554/ `
  -Register `
  -KeepReceiverRunning
```

`-KeepReceiverRunning` leaves the same receiver process live after FFmpeg DirectShow capture and writes `runtime-evidence.json`, `manual-app-enumeration-checklist.txt`, and `manual-app-evidence-template.json` next to `runtime-summary.txt`, so OBS or a browser camera test can select `PhoneCam Virtual Camera` while the Android stream is still feeding Softcam. It cannot be combined with `-SkipCapture`; OBS/browser evidence must be tied to a real FFmpeg DirectShow capture and saved `directshow-frame.bmp` artifact. The runtime helper now fails immediately when the FFmpeg capture log does not name the expected camera, reports fewer frames than requested, or cannot save a non-empty PNG/JPEG/BMP `directshow-frame.bmp` snapshot from the virtual camera. The runtime evidence records the receiver process id, selected/opened RTSP URL, non-empty runtime logs, DirectShow capture frame counts, capture logs naming the camera, the DirectShow snapshot log, the saved DirectShow frame snapshot, and the generated manual checklist/template paths; final MVP validation requires a real Android LAN URL, an `openedRtspUrl` parsed from receiver stdout, an auto-discovery `selectedRtspUrl` when `-PairCode` is used, complete runtime logs, captured frames that meet `requestedFrames`, a non-empty PNG/JPEG/BMP DirectShow snapshot, a non-empty generated checklist, and manual OBS/browser evidence from the generated template with the same `receiverProcessId`, not localhost, the emulator `10.0.2.*` network, or the `phone-ip` placeholder. The manual evidence template includes `runtimeArtifacts.directShowFrameSnapshot`, `directShowFrameMatchesExpectedAndroidStream`, and `directShowFrameReviewNote` so the operator must inspect the saved virtual-camera frame before completing OBS/browser checks. Save non-empty OBS and browser/camera-app screenshots beside the evidence file; they must be separate PNG, JPEG, or BMP app screenshots with different image content and must not reuse the DirectShow frame snapshot path or content. Fill the generated manual evidence template with versions, pass/fail values, DirectShow snapshot review values, and `screenshotPath` values, then set `status` to `passed` and validate it:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -ValidateManualEvidence PATH\TO\manual-app-evidence-template.json `
  -RuntimeEvidence PATH\TO\runtime-evidence.json
```

Stop the reported receiver process after those manual app checks, then cleanly unregister Softcam from an elevated PowerShell with:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -UnregisterOnly
```

For a branded DirectShow device, build the patched Softcam checkout with:

```powershell
powershell -ExecutionPolicy Bypass -File desktop\windows\scripts\Prepare-PhoneCamSoftcam.ps1 `
  -Destination C:\deps\phonecam-softcam
```

The preparation script writes `PHONECAM-SOFTCAM-BUILD.txt` with the resolved Softcam commit, `PhoneCam Virtual Camera` filter name, and PhoneCam CLSID. The Windows packager verifies that branding metadata or source patch before copying `softcam.dll`, then includes `docs\SOFTCAM-BUILD.txt` in the MVP package.

See [desktop/windows/SOFTCAM_BRANDING.md](../desktop/windows/SOFTCAM_BRANDING.md).

## Android RTSP fallback architecture

```text
Android phone
  Camera2/MediaCodec via RootEncoder
  RTSP server plugin
  RTSP-over-TCP on Wi-Fi LAN
        |
        v
Windows receiver
  FFmpeg RTSP demux + H.264 decode
  BGR24 frame conversion
  Win32 preview window with live diagnostics
  Softcam sender API
        |
        v
Windows camera apps
  OBS / Zoom / Teams / Discord / browser
```

## Third-Party License Notes

- RootEncoder and RTSP-Server are Apache-2.0.
- Softcam is MIT.
- FFmpeg must be distributed according to the exact build configuration. Use reviewed LGPL dynamic builds and preserve the library source, notices and relinking rights; see the release report.
- The Windows vcpkg manifest disables FFmpeg default features and enables only `avcodec`, `avformat`, and `swscale` for the CI/package path.
- OBS is GPLv2 and is only an interoperability target. Do not copy OBS code into this MIT app.
- `desktop/receiver` still contains the old Python/pyvirtualcam prototype. It is not the production path.

See [docs/third-party-notices.md](third-party-notices.md).

## Verification Status

See [docs/verification-report.md](verification-4k60.md) for exact commands, outputs, emulator artifacts, and remaining host-specific checks.

Safe local verification on this Mac:

```bash
scripts/local_verification.sh
```

This writes a timestamped summary and per-step logs under `/private/tmp/phonecam-local-verification-*`. It runs repository/static checks, the no-device Android rotation-plan self-test, Android debug build and JVM tests, the existing native receiver build/CTest when available, and the macOS dev app package check. It intentionally does not run adb, physical Android Wi-Fi evidence, Windows DirectShow registration, or OBS/browser camera enumeration. Set `RUN_RTSP_FIXTURE=1` to include the synthetic MediaMTX/FFmpeg receiver fixture when local RTSP bind approval is available.

After the physical Android profile matrix and Windows DirectShow/OBS/browser checks are captured, run the final evidence gate:

```bash
ruby scripts/validate_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --windows-runtime /path/to/runtime-evidence.json \
  --windows-manual /path/to/manual-app-evidence-template.json
```

That gate intentionally fails until physical Android Wi-Fi profile evidence, per-profile `wifi-evidence.json` files with non-emulator LAN RTSP URLs, Android Wi-Fi/network state, matching direct/discovery/front-camera decode URL evidence, valid PPM/PNG/JPEG/BMP decoded receiver frame snapshots, positive FPS and incoming-Mbps metrics within each profile ceiling, zero decode errors, a stable six-digit pairing code, captured Android UI/logcat artifacts, a compact sender UI dump containing `PREVIEW LIVE`, valid PNG/JPEG/BMP Android screenshots for the compact sender preview and diagnostics-expanded states, captured rotation artifacts plus `orientationEvidenceVersion >= 4`, `rotationControlMode: "per-camera-output"`, `orientationLockMode: "fixed-landscape"`, recorded `Rotate Left`/`Rotate Right` direction, 0/90/180/270 output rotation degrees that match any requested absolute target, `orientationStatus: "passed"`, orientation notes, device posture, and camera diagnostics for physical direct/back and front-camera checks, real DirectShow capture with non-empty runtime logs that contain the Android RTSP URL, DirectShow camera name, FFmpeg capture log camera name, sufficient FFmpeg capture frame count, a non-empty PNG/JPEG/BMP DirectShow frame snapshot, generated manual checklist/template artifacts, and completed OBS/browser manual evidence tied to the same camera name, source mode, RTSP URL, receiver process id, and generated manual template path are all present. OBS and browser/camera-app screenshots must be distinct PNG, JPEG, or BMP app screenshots, must have different image content from each other, and cannot reuse the saved DirectShow frame snapshot path or content. The Windows runtime RTSP URL must also match one of the physical Android matrix RTSP URLs, all recorded Windows `effectiveRtspUrl`/`selectedRtspUrl`/`openedRtspUrl` fields must refer to the same endpoint, `openedRtspUrl` must be recorded from receiver stdout for the real Windows run, and Windows auto-discovery evidence must record `selectedRtspUrl` plus use the same pairing code, so a successful Windows run cannot be combined with unrelated Android evidence. Current Android decode/discovery evidence is recorded in `docs/verification-report.md`, but fresh orientation evidence is required after the Z Fold review, fixed-landscape streaming lock, and per-camera rotation-control change; the remaining hard blocker is the Windows DirectShow/OBS/browser evidence set.

After the final gate passes, bundle the evidence into a portable folder:

```bash
ruby scripts/bundle_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --windows-runtime /path/to/runtime-evidence.json \
  --windows-manual /path/to/manual-app-evidence-template.json \
  --output-dir /path/to/PhoneCam-MVP-Evidence
```

The bundle contains copied logs/screenshots/snapshots, a bundled copy of `validate_mvp_evidence.rb` under `tools/`, a root `README.txt` that says to run validation from the bundle folder, and a `bundle-manifest.json` with relative evidence paths, source input SHA-256 fingerprints, validation-skipped status, and a validation command for the bundled copies.
The bundler runs `validate_mvp_evidence.rb` on the source evidence before copying and again on the rewritten bundled evidence, so preflight or otherwise incomplete evidence cannot be archived as a finished MVP bundle. `--skip-validation` exists only for diagnostics while investigating broken evidence paths.

Use `--android-only` only for the pre-Windows Android matrix handoff. The final MVP archive still requires `--windows-runtime` and `--windows-manual` after real DirectShow and OBS/browser evidence have been collected.

Verified on this Mac:

- Android debug build works with the repaired Gradle wrapper.
- Android JVM tests cover discovery beacons, stream profile budgets, profile-selector UI, launcher manifest, RootEncoder orientation handoff, camera/orientation safeguards, and removal of the old raw TCP source set.
- Fresh Android emulator evidence showed the APK installed and launched, pairing/profile UI rendered, `Start Camera Server` reached a video-only RTSP state, the front-camera switch updated status to `Camera: Front`, and logcat had no PhoneCam crash or stream configuration failure marker.
- Android emulator RTSP sender evidence showed the native receiver decoded 30 frames from the app through adb-forwarded RTSP at `960x540 @ 30 fps`, about `1.19 Mbps`, with zero decode errors.
- Windows receiver core builds on macOS against local FFmpeg in preview-only mode.
- Receiver self-test sends generated frames through the preview sink.
- Receiver decodes a synthetic H.264 RTSP-over-TCP stream published through MediaMTX.
- Receiver has a headless `--no-preview` self-test path for Windows CI.
- Receiver discovery parser/socket path passes synthetic UDP beacon, pair-code, mismatch, and auto-discovery FPS-selection self-tests.
- Receiver auto-discovery can select a synthetic pair-code beacon, adopt its advertised 60 fps stream metadata, and decode a local RTSP fixture when MediaMTX/FFmpeg are running.
- Mac receiver dev helper decodes a synthetic RTSP fixture, writes JSON evidence, and captures a decoded snapshot while explicitly marking the result as not Windows DirectShow evidence.
- A physical Android Wi-Fi profile matrix on phone `RFCW70YEQ1R` proved Efficient/Balanced/Motion direct LAN RTSP decode, pair-code discovery decode, front-camera switch/decode, and stable pairing code. Its orientation acceptance is now invalidated by human review on a Galaxy Z Fold 5 opened about 90 degrees: the front snapshot was rotated 90 degrees right and back-camera snapshots were inconsistent. The physical matrix helpers now fail early unless acceptance-mode orientation fields are supplied, or `ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1` is used for non-final exploratory collection. See `docs/verification-report.md`.

Not verified on this Mac:

- Fresh physical Android orientation evidence after the SurfaceView preview, RootEncoder orientation, fixed-landscape streaming lock, live-preview, and foldable camera-diagnostics patch.
- DirectShow Softcam registration.
- Camera visibility in OBS/Zoom/Teams.
- Android-to-Windows UDP discovery across an actual Wi-Fi LAN.
- Windows preview/Softcam runtime on an actual Windows host.
