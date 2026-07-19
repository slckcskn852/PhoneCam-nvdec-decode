# Testing

For the latest local command evidence from this rebuild, see [verification-report.md](verification-report.md).

## Android Build

```bash
cd android
./gradlew :app:testDebugUnitTest :app:assembleDebug --console=plain
```

Codex/local helper:

```bash
scripts/build_android_debug.sh
```

That helper sets `GRADLE_USER_HOME` and `java.io.tmpdir` under `/private/tmp`, which avoids the local sandbox's Gradle file-lock/socket restrictions. Set `FORCE_ANDROID_TESTS=1` to force `:app:testDebugUnitTest --rerun-tasks` first and print the regenerated JVM test XML summaries; `scripts/local_verification.sh` uses that mode so its Android evidence is not backed by stale up-to-date test reports.

The current JVM unit tests verify the Android UDP discovery beacon payload format, stream profile bitrate budget, launcher manifest, low-bandwidth profile selector UI, source-level camera/orientation safeguards, and removal of the old raw TCP streamer from the active source set:

```text
android/app/build/test-results/testDebugUnitTest/TEST-com.phonecam.DiscoveryBeaconProtocolTest.xml
android/app/build/test-results/testDebugUnitTest/TEST-com.phonecam.StreamProfileTest.xml
android/app/build/test-results/testDebugUnitTest/TEST-com.phonecam.AndroidConfigurationContractTest.xml
```

## Android Emulator QA

Use the Test Android Apps workflow:

```bash
adb devices
./gradlew :app:installDebug --console=plain --quiet
adb -s <serial> shell cmd package resolve-activity --brief com.phonecam
adb -s <serial> shell am start -n com.phonecam/.RtspMainActivity
adb -s <serial> exec-out uiautomator dump /dev/tty > /tmp/phonecam-ui.xml
adb -s <serial> exec-out screencap -p > /tmp/phonecam-home.png
adb -s <serial> logcat -d > /tmp/phonecam-logcat.txt
```

Repo helper for the same launch/UI/logcat evidence path:

```bash
scripts/android_device_smoke.sh
```

The helper installs the debug APK, grants camera permission when possible, launches the resolved activity, taps `Start Camera Server`, checks the streaming UI for `Preview: live`, taps `Rotate`, taps `Switch`, captures launch/post-start/post-switch UI XML, screenshots, logcat files, force-stops the app after evidence capture, and writes a `summary.txt` under `/private/tmp/phonecam-android-smoke-*`. It exits nonzero when critical smoke checks fail, including missing live preview, unchanged output rotation, failed front-camera switch, crash markers, or stream-configuration failure markers.

It also taps the `Rotate` control once on the streaming screen and checks that the `Output rotation` value changes in the UI. This is a wiring smoke test for the rotation control only; physical receiver output still decides whether an orientation is acceptable.

The sender's `Stop` path releases the RTSP/camera preview session and recreates a fresh stream object for the next start. That keeps repeated physical orientation passes from inheriting a hidden prepared preview after returning to the connection screen.

Android sender to native receiver smoke test:

```bash
scripts/android_rtsp_receiver_smoke.sh
```

This starts the Android app in an emulator or attached device, taps `Start Camera Server`, forwards host TCP port `8556` to device RTSP port `8554` with adb, then runs the native receiver against `rtsp://127.0.0.1:8556/`. It proves the Android RTSP server can feed the receiver decode path on the local development host. It still does not prove physical Wi-Fi traversal or Windows DirectShow output.

## Mac Receiver Dev Smoke

Use this on macOS to exercise the same native receiver binary against either a live PhoneCam RTSP URL or LAN auto-discovery:

```bash
RTSP_URL=rtsp://PHONE_IP:8554/ \
  RECEIVER_BIN=/path/to/phonecam-receiver \
  scripts/mac_receiver_dev_smoke.sh
```

or:

```bash
PAIR_CODE=123456 \
  RECEIVER_BIN=/path/to/phonecam-receiver \
  scripts/mac_receiver_dev_smoke.sh
```

The helper builds the receiver with `PHONECAM_WITH_SOFTCAM=OFF` when `RECEIVER_BIN` is not supplied, runs it with `--no-preview --no-softcam`, requires a decoded frame snapshot, and writes `mac-receiver-evidence.json`, stdout/stderr logs, the exact receiver command, and `receiver-frame.ppm` under `/tmp/phonecam-mac-receiver-dev-*`.

A local synthetic fixture can publish an RTSP test stream through MediaMTX and validate the Mac helper without a phone:

```bash
MEDIAMTX_BIN=/private/tmp/phonecam-mediamtx/mediamtx \
  RECEIVER_BIN=/private/tmp/phonecam-windows-receiver-build/phonecam-receiver \
  scripts/mac_receiver_fixture_smoke.sh
```

The fixture configures MediaMTX and FFmpeg for RTSP-over-TCP only. This avoids MediaMTX's UDP RTP/RTCP listeners while matching the receiver's RTSP-over-TCP decode path.

To exercise the local macOS preview window as a development app, add `PREVIEW=1`:

```bash
PREVIEW=1 RTSP_URL=rtsp://PHONE_IP:8554/ \
  RECEIVER_BIN=/path/to/phonecam-receiver \
  scripts/mac_receiver_dev_smoke.sh
```

The preview path uses the receiver's Cocoa sink on Apple hosts and still writes the decoded PPM snapshot plus structured evidence. Keep `PREVIEW=0` for unattended CI-style smoke runs.

To create a double-clickable local development app around the same receiver binary:

```bash
scripts/package_mac_receiver_app.sh
```

This builds the receiver with `PHONECAM_WITH_SOFTCAM=OFF` when `RECEIVER_BIN` is not supplied, then writes `dist/PhoneCam-Mac/PhoneCam Receiver.app`. The app's default startup waits for a PhoneCam Android discovery beacon and opens the Cocoa preview sink. The bundle includes a README that states it is Mac development evidence only and does not prove Windows DirectShow registration or OBS/browser camera enumeration.

This is useful for shared RTSP decode and UDP discovery diagnostics on macOS. It intentionally records `macDevOnly: true` and a `doesNotProve` list because it cannot prove Windows DirectShow registration, `PhoneCam Virtual Camera` enumeration, OBS/browser camera rendering, or Windows firewall behavior.

Physical Android Wi-Fi sender to native receiver smoke test:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_receiver_smoke.sh
```

This helper is intentionally stricter than the adb-forwarded smoke:

- It refuses `emulator-*` targets unless `ALLOW_EMULATOR=1` is explicitly set for script debugging.
- When `ANDROID_SERIAL` is not set, it selects the first non-emulator adb target so a running emulator does not mask an attached phone.
- It extracts the concrete LAN RTSP URL and six-digit pairing code from the Android UI.
- It captures Android Wi-Fi/network state with `cmd wifi status`, `dumpsys wifi`, `ip route`, `ip addr`, and `getprop`, then records summaries and artifact paths in `wifi-evidence.json`.
- It records `avgFps`, `incomingMbps`, and `decodeErrors` from each receiver run, plus the selected profile's expected bitrate and allowed incoming-Mbps ceiling.
- It asks the receiver to write decoded PPM frame snapshots for direct LAN, pair-code discovery, and front-camera decode runs.
- It fails if the receiver cannot decode the requested frame count from the direct LAN RTSP URL, reports decode errors, or exceeds the profile bandwidth ceiling.
- It also tries `--auto-discover --pair-code` and records that result separately. The final MVP evidence gate requires this pair-code discovery decode to pass for each profile, so use firewall/router fixes rather than treating discovery failure as acceptable final evidence.
- It taps `Switch`, verifies the UI reaches `Camera: Front`, and runs a second direct LAN decode after the front-camera switch.
- It records whether the sender UI reached `Preview: live`, which means RootEncoder returned a preview-frame probe through the SurfaceView path. If the probe times out, the app switches to `PREVIEW CHECKING` / `Preview: not confirmed` and retries instead of silently accepting an unconfirmed preview surface. The physical Wi-Fi helper exits nonzero when the sender never reports live preview, and the final MVP validator rejects physical Android evidence when `previewLive` is missing or false. The sender defaults to a `PREVIEW LIVE` badge plus compact camera/pairing/rotation strip and keeps the full diagnostics panel behind the `Info` button so the live preview remains visually inspectable on foldable landscape screens. This is local sender evidence only; receiver snapshots still decide output correctness.
- It taps `Info` before the diagnostic UI dump and records the sender UI's `Camera diagnostics` line for direct/back and front-camera evidence. That line includes camera id, Camera2 sensor orientation, display rotation, RootEncoder device rotation, and preview window size, which is required context for foldable devices such as the Galaxy Z Fold in half-open landscape use.
- It can target absolute output rotation with `STREAM_OUTPUT_ROTATION_DEGREES=0|90|180|270` before direct decode and `FRONT_CAMERA_OUTPUT_ROTATION_DEGREES=0|90|180|270` after the front-camera switch. The helper reads the current UI `Output rotation`, chooses the shortest `Rotate Left` or `Rotate Right` path, and records the request mode, target degrees, applied direction/taps, resulting degrees, and rotation UI/screenshot artifacts in `wifi-evidence.json`. Legacy `STREAM_ROTATE_TAPS=0..3` and `FRONT_CAMERA_ROTATE_TAPS=0..3` are still available for direct tap-count debugging.
- `ROTATION_PLAN_SELF_TEST=1 scripts/android_wifi_receiver_smoke.sh` verifies that shortest-path rotation planning without touching adb, the APK, or the receiver binary.
- It has an exploratory `ORIENTATION_CALIBRATION=1` mode for foldable/manual calibration. That mode starts the phone stream, captures receiver snapshots at each 0/90/180/270 output rotation for the back camera and, when `VERIFY_FRONT_CAMERA=1`, the front camera, then writes `orientation-calibration.json` and `orientation-calibration-summary.txt`. Calibration evidence is marked non-final and does not satisfy the final MVP gate; inspect its snapshots to choose the accepted `STREAM_OUTPUT_ROTATION_DEGREES` and `FRONT_CAMERA_OUTPUT_ROTATION_DEGREES` values for the later matrix run.
- It captures Android display/window/input rotation artifacts for the direct stream before decode and again after the front-camera switch. The helper only counts direct stream/back-camera orientation as accepted when `STREAM_ORIENTATION_STATUS=passed`, `STREAM_ORIENTATION_NOTES`, and `STREAM_DEVICE_POSTURE` are set after inspecting the physical receiver output and decoded direct snapshot.
- It only counts front-camera orientation as accepted when `FRONT_CAMERA_ORIENTATION_STATUS=passed`, `FRONT_CAMERA_ORIENTATION_NOTES`, and `FRONT_CAMERA_DEVICE_POSTURE` are set after inspecting the physical receiver output and decoded front-camera snapshot.
- In acceptance mode, it fails before installing or launching the app unless the required orientation acceptance fields are supplied. This is intentional so a real phone session is not spent on evidence that cannot pass the final gate.
- It writes UI XML, compact pre-diagnostics sender screenshots, diagnostics-expanded screenshots, logcat, network artifacts, orientation artifacts, direct receiver logs, discovery receiver logs, decoded receiver frame snapshots, front-camera receiver logs, `summary.txt`, and structured `wifi-evidence.json` under `/private/tmp/phonecam-android-wifi-receiver-*`. The final gate requires these captured UI/logcat/snapshot artifacts, including a compact sender UI dump that contains `PREVIEW LIVE`, valid PNG/JPEG/BMP Android screenshots, the compact streaming screenshot, the front-camera switch screenshot, and valid PPM/PNG/JPEG/BMP decoded receiver frames, so the JSON cannot stand in for missing or bogus visual evidence.

Useful options:

```bash
ORIENTATION_CALIBRATION=1 CALIBRATION_FRAMES=20 \
  RECEIVER_BIN=/path/to/phonecam-receiver \
  scripts/android_wifi_receiver_smoke.sh
```

After inspecting the calibration receiver snapshots, run the acceptance path with the chosen absolute output rotations. This is preferred over tap counts because the Android app persists separate back/front correction values between launches:

```bash
FRAMES=120 DISCOVER_SECONDS=10 REQUIRE_DISCOVERY=1 \
STREAM_OUTPUT_ROTATION_DEGREES=0 FRONT_CAMERA_OUTPUT_ROTATION_DEGREES=270 \
STREAM_ORIENTATION_STATUS=passed \
  STREAM_ORIENTATION_NOTES="direct/back receiver snapshot and live output stayed landscape-correct" \
  STREAM_DEVICE_POSTURE="phone physically landscape on tabletop" \
FRONT_CAMERA_ORIENTATION_STATUS=passed \
  FRONT_CAMERA_ORIENTATION_NOTES="front receiver snapshot and live output stayed landscape-correct after switching and rotating" \
  FRONT_CAMERA_DEVICE_POSTURE="phone physically landscape on tabletop" \
  RECEIVER_BIN=/path/to/phonecam-receiver \
  scripts/android_wifi_receiver_smoke.sh
```

Use `REQUIRE_DISCOVERY=1` when debugging the helper interactively and you want it to exit immediately on discovery failure. Final MVP validation requires the recorded pair-code discovery decode regardless of that single-run helper flag.
Leave `VERIFY_FRONT_CAMERA=1` for acceptance evidence; setting it to `0` is only useful while debugging setup issues before front-camera validation.
Leave `STREAM_ORIENTATION_STATUS` at `not-verified` until a human has inspected the physical direct/back-camera receiver output after any requested output rotation target or rotation taps. Set it to `passed` only for the acceptance run where the output is landscape-correct, include a short `STREAM_ORIENTATION_NOTES` value describing what was inspected, and record the physical posture in `STREAM_DEVICE_POSTURE`.
Leave `FRONT_CAMERA_ORIENTATION_STATUS` at `not-verified` until a human has inspected the physical front-camera receiver output after any requested output rotation target or rotation taps. Set it to `passed` only for the acceptance run where the output is landscape-correct, include a short `FRONT_CAMERA_ORIENTATION_NOTES` value describing what was inspected, and record the physical posture in `FRONT_CAMERA_DEVICE_POSTURE`.
For exploratory collection before the orientation fix is trusted, use `ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1`. That mode can capture logs, snapshots, and decode metrics, but the resulting evidence is intentionally non-final and will not satisfy `scripts/validate_mvp_evidence.rb`.

Full physical profile matrix:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_profile_matrix_smoke.sh
```

This runs the physical Wi-Fi helper once per profile: Efficient, Balanced, and Motion by default. Each run verifies the selected profile summary, decodes frames from the direct LAN RTSP URL at the expected resolution, requires pair-code auto-discovery decode, records receiver FPS/bitrate/decode-error metrics and decoded frame snapshots, requires accepted direct stream/back-camera orientation evidence with sender camera diagnostics, and writes a per-profile evidence folder with `wifi-evidence.json`, UI dumps, screenshots, logcat, snapshots, orientation artifacts, and receiver logs, plus top-level `summary.txt` and `matrix-evidence.json` files under `/private/tmp/phonecam-android-wifi-profile-matrix-*`. The matrix JSON also summarizes each profile's observed pairing code, RTSP URL, `previewLive` value, and `allowUnverifiedOrientation` value when its `wifi-evidence.json` exists. The final profile also runs the front-camera switch/decode/orientation check when `VERIFY_FRONT_CAMERA=1`.
The matrix sets `REQUIRE_DISCOVERY=1` by default so a passed matrix cannot hide a discovery failure. `REQUIRE_DISCOVERY=0` is only for script debugging and cannot satisfy the final MVP evidence gate. In acceptance mode, the matrix fails before starting any per-profile phone run unless direct/back orientation status, notes, and posture are supplied, plus front-camera orientation status, notes, and posture when `VERIFY_FRONT_CAMERA=1`. The matrix exits nonzero when any profile or required discovery decode fails, but still writes per-profile `run.log`, `exit-status.txt`, skipped-profile notes, and the top-level summary after a started run. Set `ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1` only when collecting as much partial hardware evidence as possible before the orientation issue is fixed; that exploratory evidence remains invalid for final MVP validation.

The physical evidence at `/private/tmp/phonecam-android-wifi-profile-matrix-20260523-003143` still proves real Wi-Fi RTSP decode and pair-code discovery, but its orientation acceptance is invalidated by later human review on a Galaxy Z Fold 5 opened about 90 degrees. Re-run the matrix after the SurfaceView preview, RootEncoder orientation, live-preview, foldable camera-diagnostics, and per-camera Rotate patches are installed, and re-run it whenever Android sender behavior, camera switching/orientation logic, discovery payloads, or receiver decode validation changes.

If `adb devices` returns no attached devices and `emulator -list-avds` returns no AVD names, create or attach an Android target first. Do not mark emulator QA as fresh evidence from build-only tests.

Verify:

- App launches.
- Camera permission request appears or the app reaches the RTSP control screen.
- `Start Camera Server` is visible.
- Efficient, Balanced, and Motion profile controls render.
- Pairing code renders.
- Streaming status preserves URL, active profile, camera facing, connection state, live bitrate, and discovery state.
- Streaming status shows `Preview: live` after the local SurfaceView path returns a RootEncoder preview-frame probe.
- Starting the camera server does not crash when no receiver is connected.
- The native receiver can decode frames from the Android RTSP sender through `adb forward` when an emulator/device is available.
- Logcat has no PhoneCam fatal crash marker, `AudioEncoder not prepared`, camera-switch failure, or video/audio configuration failure from `com.phonecam`.

Physical-device checks for Selcuk's feedback:

- Verify Efficient starts at `960x540 @ 30 fps`, around `1.2 Mbps`.
- Verify Balanced starts at `1280x720 @ 30 fps`, around `1.8 Mbps`.
- Verify Motion starts at `1280x720 @ 60 fps`, around `2.8 Mbps`.
- Verify front/back camera switching works while streaming.
- Verify output orientation remains landscape-correct after switching cameras and rotating the phone.

Emulators may prove app launch, permissions, UI, encoder startup, and RTSP server startup. They still do not prove real phone Wi-Fi camera quality, thermal behavior, or hardware encoder behavior. Use a physical Android phone for final Android RTSP validation, and use a Windows host for final DirectShow/OBS/browser validation.

## Physical Android RTSP Test

1. Install `app-debug.apk` on a phone.
2. Connect phone and receiver host to the same Wi-Fi network.
3. Prefer the scripted Wi-Fi smoke when adb is available:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_receiver_smoke.sh
```

4. On Windows, or when testing manually, start the camera server and try receiver auto-discovery:

```powershell
phonecam-receiver.exe
phonecam-receiver.exe --discover --discover-seconds 5
phonecam-receiver.exe --auto-discover --discover-seconds 5 --fps 60
phonecam-receiver.exe --auto-discover --pair-code PHONE_CODE --discover-seconds 5 --fps 60
```

No-argument startup waits up to 15 seconds for a discovery beacon and connects to the first discovered phone. If `--fps` is not provided, the receiver uses the stream FPS advertised by the phone's discovery beacon.

5. If discovery is blocked by the router or firewall, open the shown URL manually:

```powershell
phonecam-receiver.exe --rtsp rtsp://PHONE_IP:8554/ --fps 60
```

A direct FFmpeg sanity check is also useful:

```powershell
ffplay -rtsp_transport tcp rtsp://PHONE_IP:8554/
```

On Windows private networks, discovery may need an explicit firewall rule for the receiver's UDP listener:

```powershell
.\desktop\windows\scripts\Install-PhoneCamFirewallRules.ps1 `
  -Receiver .\build\windows-receiver\Release\phonecam-receiver.exe
```

Run from an elevated PowerShell. The helper adds inbound UDP `47821` and outbound TCP `8554` rules scoped to the receiver executable. Remove them with `-Remove`.

## Windows Receiver Build

```powershell
cmake -S desktop/windows -B build/windows-receiver `
  -DFFMPEG_ROOT=C:\deps\ffmpeg `
  -DSOFTCAM_ROOT=C:\deps\softcam `
  -DPHONECAM_WITH_SOFTCAM=ON

cmake --build build/windows-receiver --config Release
```

Verify:

- Preview window renders frames.
- Startup output shows the RTSP target host, port, and path.
- Runtime output shows frame count, average FPS, incoming Mbps, and decode errors.
- Preview window title shows target, connection state, resolution, FPS, incoming Mbps, frame count, and decode errors.
- Softcam virtual camera appears in OBS or a browser camera test.
- Stopping the receiver releases the virtual camera.
- Softcam unregister path works.

Generated-frame receiver sink test:

```powershell
phonecam-receiver.exe --self-test --frames 240 --fps 60
```

With Softcam linked, this validates the virtual-camera frame path without requiring a phone or RTSP stream.

Headless generated-frame test for CI:

```powershell
phonecam-receiver.exe --self-test --frames 5 --fps 30 --no-preview --no-softcam
```

This proves the receiver binary starts and can run its frame-sink loop without requiring an interactive Windows desktop. It does not prove DirectShow registration.

Discovery parser/socket self-test:

```powershell
phonecam-receiver.exe --discovery-self-test
```

Expected output includes:

```text
Discovered Synthetic Android at rtsp://127.0.0.1:8554/
Discovery self-test passed.
```

This proves the receiver can bind the discovery port, parse a PhoneCam beacon, and select the advertised RTSP URL. It does not prove real Wi-Fi broadcast traversal; that still requires a physical phone and Windows host on the same LAN.

Pair-code discovery parser/socket self-test:

```powershell
phonecam-receiver.exe --discovery-self-test --pair-code 123456
```

Auto-discovery selection metadata self-test:

```powershell
phonecam-receiver.exe --auto-discovery-selection-self-test
```

This verifies that the auto-discovery path applies the selected beacon URL and advertised FPS before opening RTSP. It catches regressions where a 60 fps phone profile would still create a 30 fps preview/Softcam sink.

CTest wrapper for the receiver self-test and discovery self-test:

```powershell
ctest --test-dir build/windows-receiver -C Release --output-on-failure
```

This suite covers generated-frame delivery, discovery beacon parsing/socket binding, pair-code filtering, auto-discovery metadata selection, and the unavailable-RTSP failure diagnostic. In Codex's default sandbox, the discovery CTest can fail at UDP bind time. Run CTest outside the sandbox or through an approved local command when testing discovery binding.

Auto-discovery plus RTSP decode fixture:

```bash
mediamtx mediamtx.yml
ffmpeg -re -f lavfi -i testsrc2=size=1280x720:rate=30 \
  -f lavfi -i anullsrc=channel_layout=mono:sample_rate=48000 -pix_fmt yuv420p \
  -c:v libx264 -preset veryfast -tune zerolatency -g 30 -b:v 4M \
  -c:a aac -b:a 96k -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8555/phonecam-test
phonecam-receiver --auto-discover-self-test rtsp://127.0.0.1:8555/phonecam-test \
  --pair-code 123456 --frames 60 --snapshot receiver-frame.ppm --no-preview --no-softcam
```

This tests discovery selection and the receiver's RTSP decode path together without requiring a physical phone, and writes a decoded PPM frame snapshot.

Repo helper for this fixture:

```bash
MEDIAMTX_BIN=/path/to/mediamtx RECEIVER_BIN=/path/to/phonecam-receiver \
  scripts/smoke_receiver_fixture.sh
```

The helper defaults to RTSP port `8555` and pair-code filter `123456` so it can run while an Android emulator or phone path is using the app's normal `8554` RTSP port. It also forces MediaMTX and FFmpeg to RTSP-over-TCP so the fixture does not need MediaMTX UDP RTP/RTCP listeners. In Codex's sandbox this helper can still fail before receiver startup with `listen tcp ... bind: operation not permitted`. Run it outside the sandbox, or allow the local RTSP bind when prompted.

Run this helper separately from receiver CTest. Both the fixture and the discovery CTests bind UDP port `47821`, so running them in parallel can produce `Failed to bind UDP discovery port 47821`.

Windows PowerShell helper:

```powershell
.\desktop\windows\scripts\Test-PhoneCamReceiverFixture.ps1 `
  -Receiver .\build\windows-receiver\Release\phonecam-receiver.exe `
  -MediaMtx C:\deps\mediamtx\mediamtx.exe `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe
```

RTSP fixture test without a phone:

```bash
mediamtx mediamtx.yml
ffmpeg -re -f lavfi -i testsrc2=size=1280x720:rate=30 \
  -f lavfi -i anullsrc=channel_layout=mono:sample_rate=48000 -pix_fmt yuv420p \
  -c:v libx264 -preset veryfast -tune zerolatency -g 30 -b:v 4M \
  -c:a aac -b:a 96k -rtsp_transport tcp -f rtsp rtsp://127.0.0.1:8555/phonecam-test
phonecam-receiver --rtsp rtsp://127.0.0.1:8555/phonecam-test --fps 30 --frames 60 --no-preview --no-softcam
```

Expected receiver output includes a preview sink line and a summary such as:

```text
Headless/null sink active: 1280x720 @ 30 fps
Receiver summary: 60 frames, avg 28-30 fps, incoming ~4 Mbps, decode errors 0
```

## Known Host Limitations

On macOS, Android build and emulator UI checks can run. Windows DirectShow registration and camera visibility cannot be verified without a Windows host.

## GitHub Actions

The workflow in `.github/workflows/build.yml` builds:

- Static packaging contracts on Ubuntu.
- Android debug APK on Ubuntu.
- Windows receiver on `windows-latest` with vcpkg FFmpeg and `PHONECAM_WITH_SOFTCAM=OFF`.
- PhoneCam-branded Softcam on `windows-latest`, then the receiver with `PHONECAM_WITH_SOFTCAM=ON` and `PHONECAM_REQUIRE_SOFTCAM=ON`, followed by the same receiver CTest suite before packaging.

The Android job runs JVM unit tests before building the debug APK. The preview-only Windows job runs the receiver CTest suite, covering the headless frame self-test and discovery self-test. The Softcam-linked Windows job proves the DirectShow sender backend compiles and links against a branded Softcam build, then runs the receiver CTest suite with that backend linked before packaging. It intentionally does not register a DirectShow camera because GitHub-hosted runners are not a reliable target for interactive camera-app enumeration.

The Windows vcpkg manifest disables FFmpeg default features and enables only `avcodec`, `avformat`, and `swscale`. Keep GPL/nonfree FFmpeg features out of the CI/package manifest unless the distribution license posture is intentionally changed. The `static-contracts` job runs `scripts/check_windows_static_contracts.rb` to enforce the manifest, workflow, and package-copy expectations.

The Softcam-linked Windows job also runs `desktop/windows/scripts/Package-PhoneCamWindows.ps1`, checks the package manifest/readme contents, and uploads `phonecam-windows-mvp-package`, which contains the receiver, Softcam DLL/installer, FFmpeg/vcpkg runtime DLLs when discoverable, the Windows evidence collector, firewall/runtime verification scripts, and docs. The packager verifies the Softcam source or `PHONECAM-SOFTCAM-BUILD.txt` before copying the DLL, then includes `docs\SOFTCAM-BUILD.txt` so the artifact records the expected `PhoneCam Virtual Camera` filter name and CLSID. The package can omit `bin\ffmpeg.exe` when built from the minimal vcpkg manifest; in that case, pass an installed LGPL-clean FFmpeg CLI executable to the runtime verification script.

## Windows DirectShow Runtime Verification

On a real Windows host, prefer the collector wrapper for the final Android-to-Windows evidence pass:

Prerequisites: elevated PowerShell, a built PhoneCam-branded Softcam root, an LGPL-clean `ffmpeg.exe` for DirectShow enumeration/capture, and Ruby available as `ruby` on PATH. If Ruby is not on PATH, pass `-Ruby C:\path\to\ruby.exe` to `Collect-PhoneCamWindowsEvidence.ps1`; the collector resolves it before Android preflight, Windows runtime work, or final bundling.

```powershell
.\desktop\windows\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
  -PreflightOnly `
  -AndroidMatrix PATH\TO\matrix-evidence.json `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -PairCode PHONE_CODE
```

Use this collector preflight before the real capture session. It validates the Android matrix, pair code or manual RTSP URL, receiver, FFmpeg, Softcam DLL/installer, Ruby/PowerShell resolution, and elevation state, and writes `windows-preflight-summary.txt` plus `windows-preflight-evidence.json` without firewall changes, DirectShow capture, OBS/browser checks, or final bundling.

```powershell
.\desktop\windows\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
  -AndroidMatrix PATH\TO\matrix-evidence.json `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -PairCode PHONE_CODE `
  -InstallFirewallRules
```

It first runs the Android matrix evidence preflight:

```bash
ruby scripts/validate_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --android-only
```

That preflight must pass before Windows runtime work starts, including `-FinalizeOnly`. It refuses stale Android matrices that still prove Wi-Fi decode/discovery but lack the current rotation-control, live-preview, direct stream/back-camera orientation, front-camera orientation, output-rotation, physical-posture, and camera-diagnostics evidence required after the Galaxy Z Fold review.

Before moving the Android matrix to Windows, create a portable Android-only handoff bundle:

```bash
ruby scripts/bundle_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --android-only \
  --output-dir /path/to/PhoneCam-Android-Matrix-Handoff
```

Copy the whole handoff folder to the Windows machine and pass its bundled `android/matrix-evidence.json` to `Collect-PhoneCamWindowsEvidence.ps1`. This keeps the per-profile screenshots, UI XML, logcat, receiver logs, decoded snapshots, and orientation artifacts reachable after the evidence leaves `/private/tmp`. It proves only the Android matrix; the final MVP bundle still needs Windows runtime and manual OBS/browser artifacts.

After the Android preflight, the collector checks any supplied `-PairCode` against the stable six-digit pairing code recorded in the Android matrix before starting Windows preflight or DirectShow registration. If manual `-RtspUrl` is supplied, it is also checked against the physical Android matrix before Windows preflight. It then runs Windows preflight, optional private-LAN firewall setup, pair-code auto-discovery, DirectShow capture, and keeps the receiver process alive for OBS/browser checks. Use `-RtspUrl rtsp://PHONE_IP:8554/` instead of `-PairCode PHONE_CODE` only when UDP discovery is blocked. After filling the generated manual evidence template, run `Collect-PhoneCamWindowsEvidence.ps1 -FinalizeOnly -AndroidMatrix ... -RuntimeEvidence ... -ManualEvidence ...` to validate manual evidence, run the final MVP gate, and bundle the evidence archive.

For lower-level checks after building the Softcam-required receiver, run:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -Register `
  -PreflightOnly
```

This preflight writes `windows-preflight-summary.txt` and `windows-preflight-evidence.json` without registering Softcam or capturing frames. It checks the receiver, FFmpeg, Softcam DLL/installer, intended source mode, and administrator state before the real DirectShow run.

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -Register `
  -UnregisterAfter
```

This requires an elevated PowerShell session because `-Register` writes DirectShow COM registration. It starts the receiver's generated-frame self-test, verifies `PhoneCam Virtual Camera` appears in FFmpeg's DirectShow device list, captures frames from that virtual camera, saves one DirectShow frame snapshot, and writes logs under `%TEMP%\phonecam-windows-runtime-*`.
The helper uses Softcam's `softcam_installer.exe` registration path when available, matching upstream Softcam's own registration scripts, and writes `runtime-summary.txt` plus structured `runtime-evidence.json` beside the receiver, DirectShow device-list, capture logs, snapshot log, and saved DirectShow snapshot. It fails the runtime run immediately if the FFmpeg capture log does not name the expected camera, reports fewer frames than `-CaptureFrames`, or cannot save a non-empty PNG/JPEG/BMP DirectShow frame snapshot.

To verify the real Android-to-Windows path instead of generated frames, start the Android camera server on the same LAN and use one of these source modes:

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

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -RtspUrl rtsp://PHONE_IP:8554/ `
  -Register `
  -KeepReceiverRunning
```

Use `-KeepReceiverRunning` for OBS/browser verification. The helper leaves the same receiver process live after FFmpeg DirectShow capture and writes `runtime-evidence.json`, `manual-app-enumeration-checklist.txt`, and `manual-app-evidence-template.json` beside `runtime-summary.txt`, including the process id, selected/opened RTSP URL, non-empty runtime log paths, DirectShow capture frame counts, capture logs naming the expected camera, a saved PNG/JPEG/BMP DirectShow frame snapshot, generated checklist/template paths, and the required OBS/browser checks. Final evidence requires `openedRtspUrl` from receiver stdout for the actual stream and `selectedRtspUrl` for auto-discovery runs. It cannot be combined with `-SkipCapture`; OBS/browser evidence must be tied to a real FFmpeg DirectShow capture and saved `directshow-frame.bmp` artifact. The generated manual template also includes `runtimeArtifacts.directShowFrameSnapshot`, `runtimeArtifacts.directShowSnapshotLog`, `runtimeArtifacts.directShowCaptureLog`, `directShowFrameMatchesExpectedAndroidStream`, and `directShowFrameReviewNote` so the operator must inspect the virtual-camera frame artifact before filling OBS/browser evidence, and validation cross-checks those paths against `runtime-evidence.json`. Save non-empty OBS and browser/camera-app screenshots beside the evidence file; they must be separate PNG, JPEG, or BMP app screenshots with different image content and must not reuse the DirectShow frame snapshot path or content. Fill the generated manual evidence template with versions, pass/fail values, `receiverProcessId`, DirectShow snapshot review values, and `screenshotPath` values, then set `status` to `passed` and validate it:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -ValidateManualEvidence PATH\TO\manual-app-evidence-template.json `
  -RuntimeEvidence PATH\TO\runtime-evidence.json
```

Stop that process after app-level evidence is captured, then cleanly unregister Softcam from an elevated PowerShell with:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -UnregisterOnly
```

When `-CaptureWidth` and `-CaptureHeight` are omitted, FFmpeg DirectShow capture uses the camera's advertised/default format. Pass them explicitly only when the capture device requires a fixed size.

## Final MVP Evidence Gate

For a safe Mac-local regression pass that avoids adb and Windows-only claims:

```bash
scripts/local_verification.sh
```

The helper writes `summary.txt` plus per-step logs under `/private/tmp/phonecam-local-verification-*`. It runs Ruby syntax checks, workflow YAML parsing, shell syntax checks, optional `pwsh` PowerShell parser checks when PowerShell is installed, `scripts/check_windows_static_contracts.rb`, Android debug build/JVM tests, the existing native receiver build/CTest when the build directory exists, macOS dev app packaging when possible, and `git diff --check`. Set `RUN_RTSP_FIXTURE=1` to include the synthetic RTSP fixture. Set `RUN_POWERSHELL_SYNTAX=1` to require local `pwsh`; otherwise the helper records a skip when PowerShell is unavailable. This is local regression evidence only; physical Android orientation, Windows DirectShow registration/capture, and OBS/browser enumeration remain separate required evidence.

After physical Android Wi-Fi matrix evidence and Windows DirectShow/OBS/browser evidence are captured, validate the three required structured artifacts:

```bash
ruby scripts/validate_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --windows-runtime /path/to/runtime-evidence.json \
  --windows-manual /path/to/manual-app-evidence-template.json
```

This must fail if the Android matrix root is not marked `finalMvpEvidence: true`, was collected with `allowUnverifiedOrientation: true`, or any Android profile is missing, failed, lacks `wifi-evidence.json`, is not marked `finalMvpEvidence: true`, uses an emulator serial, lacks captured Wi-Fi/network state, uses localhost/emulator/placeholder RTSP URLs, decodes the wrong frame count or resolution, records direct LAN, pair-code discovery, or front-camera decode URLs that do not match the profile RTSP URL, lacks decoded receiver frame snapshots, records decoded receiver frame snapshots that are missing, empty, or not PPM/PNG/JPEG/BMP images, lacks positive FPS/bitrate metrics, reports decode errors, exceeds the profile incoming-Mbps ceiling, lacks captured UI/logcat artifacts, lacks a compact sender UI dump containing `PREVIEW LIVE`, lacks valid PNG/JPEG/BMP Android screenshot artifacts for the compact sender preview and diagnostics-expanded states, lacks a stable six-digit pairing code, lacks pair-code discovery decode evidence, lacks accepted direct stream/back-camera orientation evidence for every profile, lacks sender camera diagnostics for the direct/back and front-camera checks, lacks front-camera switch/decode evidence, lacks explicit `Rotate Left`/`Rotate Right` direction, lacks 0/90/180/270 output-rotation degrees, records an absolute rotation target that does not match the resulting output rotation, or lacks captured orientation artifacts plus `orientationEvidenceVersion >= 4`, `rotationControlMode: "per-camera-output"`, `orientationLockMode: "fixed-landscape"`, `orientationStatus: "passed"`, non-empty orientation notes, and a non-empty device posture for the physical front-camera check. It must also fail if the Windows runtime used generated self-test frames instead of Android RTSP, if the recorded Windows RTSP URL is localhost, the emulator `10.0.2.*` network, or the `phone-ip` placeholder, if the Windows runtime RTSP URL does not match one of the physical Android matrix RTSP URLs, if multiple recorded Windows runtime RTSP URL fields point to different endpoints, if the Windows runtime lacks `openedRtspUrl` from receiver stdout, if auto-discovery runtime evidence lacks `selectedRtspUrl`, if Windows auto-discovery uses a different pair code from the Android matrix, if DirectShow capture was skipped, if DirectShow capture returned fewer frames than `requestedFrames`, if required Windows runtime log files are missing or empty, if receiver stdout does not contain the selected Android RTSP URL, if the DirectShow device-list log does not contain the camera name, if the FFmpeg capture log does not contain the camera name or show at least `requestedFrames`, if the DirectShow snapshot log or saved DirectShow frame snapshot is missing, empty, or not a PNG/JPEG/BMP image, if the generated manual checklist/template artifacts are missing or do not match `--windows-manual`, if OBS/browser camera rendering evidence is incomplete, if OBS/browser screenshot files are missing, empty, not PNG/JPEG/BMP images, duplicated between apps, copied between apps, reused from the DirectShow frame snapshot path or content, or if the manual OBS/browser evidence is tied to a different camera name, source mode, RTSP URL, or receiver process id than the runtime DirectShow capture.

After the final gate passes, create a portable evidence bundle:

```bash
ruby scripts/bundle_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --windows-runtime /path/to/runtime-evidence.json \
  --windows-manual /path/to/manual-app-evidence-template.json \
  --output-dir /path/to/PhoneCam-MVP-Evidence
```

The bundler copies the evidence folders, rewrites JSON file references to portable relative paths, copies `validate_mvp_evidence.rb` under `tools/`, and writes a root `README.txt` plus `bundle-manifest.json` with relative evidence paths, source input SHA-256 fingerprints, validation-skipped status, and the validator command for the bundled copies. Re-run the bundled validation command from the bundle root before treating the archive as final evidence.
It validates the source evidence before copying and validates the bundled evidence after path rewriting. Use `--skip-validation` only when debugging evidence path issues; a release evidence bundle should be produced without that flag.
Use `--android-only` only for the Android matrix handoff before Windows evidence exists. A final MVP archive must be created without `--android-only` and without `--skip-validation`.
