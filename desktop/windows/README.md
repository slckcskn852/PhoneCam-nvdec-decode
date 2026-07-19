# PhoneCam Windows Receiver

This is the Windows-native MVP receiver for the Wi-Fi RTSP rebuild.

## What It Does

- Opens the Android phone RTSP URL with FFmpeg using RTSP-over-TCP.
- Decodes H.264 frames into BGR24.
- Shows a Win32 preview window.
- Sends frames to Softcam when `softcam.dll` is built, linked, and registered.
- Supports `--no-preview` for headless CI and smoke tests.
- Discovers running Android PhoneCam servers through UDP beacons on port `47821`.

The Softcam path is what makes the stream appear as a DirectShow virtual camera to apps such as OBS, Zoom, Teams, Discord, and browser camera pickers.

## Dependencies

- Visual Studio 2022 with Desktop development with C++.
- A dynamic LGPL FFmpeg build with `avformat`, `avcodec`, `avutil`, and `swscale`.
- Optional but recommended: [tshino/softcam](https://github.com/tshino/softcam), built as x64 Release.

Keep FFmpeg LGPL-clean for MIT-friendly distribution. Do not ship GPL or nonfree FFmpeg builds unless the distribution package clearly follows those licenses. The checked-in `vcpkg.json` disables FFmpeg default features and enables only `avcodec`, `avformat`, and `swscale` for the receiver CI/package path; do not add `gpl`, `nonfree`, `all-gpl`, `all-nonfree`, `x264`, or `x265` to the production manifest.

## Build

```powershell
cmake -S desktop/windows -B build/windows-receiver `
  -DFFMPEG_ROOT=C:\deps\ffmpeg `
  -DSOFTCAM_ROOT=C:\deps\softcam `
  -DPHONECAM_WITH_SOFTCAM=ON

cmake --build build/windows-receiver --config Release
```

Preview-only build:

```powershell
cmake -S desktop/windows -B build/windows-receiver `
  -DFFMPEG_ROOT=C:\deps\ffmpeg `
  -DPHONECAM_WITH_SOFTCAM=OFF

cmake --build build/windows-receiver --config Release
```

CI/vcpkg build:

```powershell
cmake -S desktop/windows -B build/windows-receiver `
  -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_INSTALLATION_ROOT/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows `
  -DPHONECAM_WITH_SOFTCAM=OFF

cmake --build build/windows-receiver --config Release
```

The checked-in GitHub Actions workflow uses this preview-only path. It proves the receiver compiles and its generated-frame sink path runs, but it does not prove DirectShow registration or camera visibility.

Softcam-required build:

```powershell
cmake -S desktop/windows -B build/windows-softcam-receiver `
  -DFFMPEG_ROOT=C:\deps\ffmpeg `
  -DSOFTCAM_ROOT=C:\deps\phonecam-softcam `
  -DPHONECAM_WITH_SOFTCAM=ON `
  -DPHONECAM_REQUIRE_SOFTCAM=ON

cmake --build build/windows-softcam-receiver --config Release
```

`PHONECAM_REQUIRE_SOFTCAM=ON` is intended for CI and release packaging. It fails CMake configuration if the Softcam headers/import library are not found, preventing accidental preview-only builds from being mistaken for virtual-camera builds.

## Run

Normal startup tries LAN pairing automatically. Start the Android app, tap `Start Camera Server`, then run:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe
```

The receiver waits up to 15 seconds for a PhoneCam discovery beacon and connects to the first discovered phone. It uses the FPS advertised in the beacon unless `--fps` is explicitly provided. If multiple phones are on the LAN, pass the six-digit Android pairing code:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --auto-discover --pair-code 123456
```

If discovery does not find the phone but the manual RTSP URL works, Windows Firewall may be blocking the UDP discovery listener. From an elevated PowerShell on a trusted private LAN, install scoped rules for this receiver binary:

```powershell
.\desktop\windows\scripts\Install-PhoneCamFirewallRules.ps1 `
  -Receiver .\build\windows-receiver\Release\phonecam-receiver.exe
```

Remove those rules with:

```powershell
.\desktop\windows\scripts\Install-PhoneCamFirewallRules.ps1 -Remove
```

Start the Android app, tap `Start Camera Server`, then use the shown RTSP URL:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --rtsp rtsp://PHONE_IP:8554/ --fps 60
```

Or let the receiver find the phone on the LAN:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --auto-discover --discover-seconds 5 --fps 60
```

Filter auto-discovery to a specific Android pairing code:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --auto-discover --pair-code 123456 --discover-seconds 5 --fps 60
```

Discovery-only mode:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --discover --discover-seconds 5
```

Pair-code discovery-only mode:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --discover --pair-code 123456 --discover-seconds 5
```

If Softcam is linked and installed, select the Softcam/PhoneCam device in OBS or another camera app.

Use `--frames N` to stop automatically after `N` decoded frames during integration tests:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --rtsp rtsp://PHONE_IP:8554/ --fps 60 --frames 120 --no-softcam
```

At startup the receiver logs the RTSP target host, port, and path. During playback it logs decoded frame count, average FPS, incoming bitrate, and decode error count. The Win32 preview window title mirrors the live target, connection state, resolution, FPS, incoming Mbps, frame count, and decode error count so the receiver remains diagnosable without watching the console.

Generated-frame sink test:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --self-test --frames 240 --fps 60
```

Headless generated-frame sink test:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --self-test --frames 5 --fps 30 --no-preview --no-softcam
```

Discovery parser/socket test:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --discovery-self-test
```

Pair-code discovery parser/socket test:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --discovery-self-test --pair-code 123456
```

Auto-discovery selection metadata test:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe --auto-discovery-selection-self-test
```

This verifies that receiver pairing adopts the discovered RTSP URL and advertised stream FPS before opening the RTSP connection.

Auto-discovery plus RTSP decode fixture, when a local RTSP stream is already published:

```powershell
.\build\windows-receiver\Release\phonecam-receiver.exe `
  --auto-discover-self-test rtsp://127.0.0.1:8555/phonecam-test `
  --pair-code 123456 --frames 60 --snapshot receiver-frame.ppm --no-preview --no-softcam
```

`--snapshot` writes the last decoded frame as a PPM image for evidence review. With Softcam linked, this sends generated BGR frames to the virtual camera without needing an Android phone.

## Softcam Install Notes

Build Softcam x64 Release first. Register the built `softcam.dll` with Softcam's installer example or batch files. Registration requires Administrator approval because it writes the DirectShow filter registration.

This repo does not vendor Softcam yet. The integration is source-compatible with Softcam's sender API:

```cpp
scCamera cam = scCreateCamera(width, height, fps);
scSendFrame(cam, bgrFrame);
scDeleteCamera(cam);
```

Keep the receiver conversion path as BGR24. Upstream Softcam's [sender sample](https://github.com/tshino/softcam/blob/main/examples/sender/sender.cpp) documents that its 24-bit frame buffer is BGR, not RGB, so `AV_PIX_FMT_BGR24` is intentional.

The visible camera name comes from the registered DirectShow filter, not from `phonecam-receiver.exe`. For the final branded device, build/register a PhoneCam-branded Softcam fork or installer so Windows exposes `PhoneCam Virtual Camera`.

This repo includes a preparation script for that fork:

```powershell
powershell -ExecutionPolicy Bypass -File desktop\windows\scripts\Prepare-PhoneCamSoftcam.ps1 `
  -Destination C:\deps\phonecam-softcam
```

See [SOFTCAM_BRANDING.md](SOFTCAM_BRANDING.md) for the exact upstream files and CLSID patch.

## Package

After building the Softcam-required receiver, create a redistributable folder and zip:

```powershell
.\desktop\windows\scripts\Package-PhoneCamWindows.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -FfmpegBinDir C:\deps\ffmpeg\bin `
  -OutputDir .\dist\PhoneCam-Windows
```

The package includes `phonecam-receiver.exe`, `softcam.dll`, `softcam_installer.exe`, FFmpeg/vcpkg runtime DLLs, Windows verification scripts, and bundled docs/notices. It also writes `docs\SOFTCAM-BUILD.txt` after verifying that the Softcam source or `PHONECAM-SOFTCAM-BUILD.txt` proves the `PhoneCam Virtual Camera` filter name and PhoneCam CLSID. Packaging fails instead of shipping an unbranded upstream Softcam by mistake. Use an LGPL-clean FFmpeg runtime for redistributable packages.

The package may not include `bin\ffmpeg.exe` when built from the minimal vcpkg manifest because the receiver only links FFmpeg libraries. `Test-PhoneCamWindowsRuntime.ps1` still needs an FFmpeg CLI executable to enumerate DirectShow devices and capture test frames, so pass an installed LGPL-clean `ffmpeg.exe` path if the package README reports that the CLI was not bundled.

## RTSP Test Fixture

MediaMTX is useful as a local RTSP server when a physical Android phone is not available. Publish a synthetic H.264 stream, then point the receiver at it:

```bash
mediamtx mediamtx.yml
ffmpeg -re -f lavfi -i testsrc2=size=1280x720:rate=30 \
  -f lavfi -i anullsrc=channel_layout=mono:sample_rate=48000 -pix_fmt yuv420p \
  -c:v libx264 -preset veryfast -tune zerolatency -g 30 -b:v 4M \
  -c:a aac -b:a 96k -f rtsp rtsp://127.0.0.1:8555/phonecam-test
phonecam-receiver --rtsp rtsp://127.0.0.1:8555/phonecam-test --fps 30 --frames 60 --no-preview --no-softcam
```

The repo helper `scripts/smoke_receiver_fixture.sh` creates this fixture with pair-code filtering, verifies a decoded frame snapshot, and defaults to host RTSP port `8555` to avoid emulator conflicts with the Android app's normal `8554` port.

Use an LGPL-clean FFmpeg build for distributable binaries. A local Homebrew FFmpeg with GPL codecs is acceptable for developer-only tests, but it is not the release dependency.

## Verification Checklist On Windows

For the real MVP evidence run, prefer the collector wrapper after the Android physical Wi-Fi matrix has been copied to the Windows host:

Prerequisites: elevated PowerShell, a built PhoneCam-branded Softcam root, an LGPL-clean `ffmpeg.exe` for DirectShow enumeration/capture, and Ruby available as `ruby` on PATH. If Ruby is installed elsewhere, pass `-Ruby C:\path\to\ruby.exe` to `Collect-PhoneCamWindowsEvidence.ps1`; the collector resolves it before Android preflight, Windows runtime work, or final evidence bundling.

```powershell
.\desktop\windows\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
  -PreflightOnly `
  -AndroidMatrix PATH\TO\matrix-evidence.json `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -PairCode PHONE_CODE
```

Run this preflight-only collector pass before the real evidence session. It validates the Android matrix, pair code or manual RTSP URL, receiver, FFmpeg, Softcam DLL/installer, Ruby/PowerShell resolution, and elevation state, then writes `windows-preflight-summary.txt` and `windows-preflight-evidence.json` without firewall changes, DirectShow capture, OBS/browser checks, or final bundling.

```powershell
.\desktop\windows\scripts\Collect-PhoneCamWindowsEvidence.ps1 `
  -AndroidMatrix PATH\TO\matrix-evidence.json `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -PairCode PHONE_CODE `
  -InstallFirewallRules
```

The collector runs preflight, optional firewall setup, Android pair-code discovery, DirectShow capture, and leaves the receiver alive for OBS/browser checks. When `-PairCode` is supplied, it is normalized to digits, required to contain exactly six digits, and checked against the stable six-digit pairing code in the Android matrix before Windows preflight or DirectShow registration starts. When manual `-RtspUrl` is supplied, it is also checked against the physical Android matrix before Windows preflight or DirectShow registration starts. The final collector refuses `-SkipPreflight`; use `Test-PhoneCamWindowsRuntime.ps1` directly for debug-only experiments. Use `-RtspUrl rtsp://PHONE_IP:8554/` instead of `-PairCode PHONE_CODE` only when UDP discovery is blocked. After filling the generated manual app evidence template, run `Collect-PhoneCamWindowsEvidence.ps1 -FinalizeOnly -AndroidMatrix ... -RuntimeEvidence ... -ManualEvidence ...` to validate the manual evidence, run the final MVP gate, and build the portable evidence bundle.

The collector first validates the Android matrix by running:

```powershell
ruby .\scripts\validate_mvp_evidence.rb `
  --android-matrix PATH\TO\matrix-evidence.json `
  --android-only
```

This check also runs for `-FinalizeOnly`. If the Android evidence is stale, incomplete, emulator-derived, or missing the current direct/back and front-camera orientation, posture, recorded `Rotate Left`/`Rotate Right` direction, rotation request mode, 0/90/180/270 output-rotation, target/output consistency for absolute rotation targets, and sender camera-diagnostics artifacts, the collector stops before Windows DirectShow capture or bundling. That keeps Windows evidence tied to a current physical Android run instead of the old Galaxy Z Fold matrix whose orientation acceptance was later invalidated.

When the Android matrix was collected on macOS, first create a portable handoff bundle and copy the whole folder to Windows:

```bash
ruby scripts/bundle_mvp_evidence.rb \
  --android-matrix /path/to/matrix-evidence.json \
  --android-only \
  --output-dir /path/to/PhoneCam-Android-Matrix-Handoff
```

Then pass `PhoneCam-Android-Matrix-Handoff\android\matrix-evidence.json` to `Collect-PhoneCamWindowsEvidence.ps1`. The handoff bundle rewrites per-profile artifact paths to relative paths and validates only the Android matrix; it does not replace Windows DirectShow, OBS, or browser evidence.

After building the Softcam-required receiver, run the runtime verification helper from an elevated PowerShell session:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -Register `
  -PreflightOnly
```

This preflight writes `windows-preflight-summary.txt` and `windows-preflight-evidence.json` without registering Softcam or capturing frames. It resolves the receiver, FFmpeg, Softcam DLL/installer, requested source mode, and administrator state so missing Windows prerequisites fail before the DirectShow run.

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -Register `
  -UnregisterAfter
```

The helper:

1. Registers the branded Softcam DLL with `softcam_installer.exe`, falling back to `regsvr32` only if the installer is not available.
2. Starts `phonecam-receiver.exe --self-test` with Softcam enabled by default, or starts the receiver from `-RtspUrl` / `-AutoDiscover` when validating a real Android stream.
3. Lists DirectShow devices with FFmpeg and checks for `PhoneCam Virtual Camera`.
4. Captures frames from `PhoneCam Virtual Camera` through FFmpeg and fails immediately if the capture log does not name that camera or reports fewer frames than requested.
5. Saves one DirectShow frame snapshot from `PhoneCam Virtual Camera` so the evidence contains an image artifact from the virtual device, not only a frame count.
6. Writes `runtime-summary.txt`, structured `runtime-evidence.json`, selected/opened RTSP URL details, receiver logs, FFmpeg device-list logs, capture logs, and the DirectShow snapshot log.
7. Stops the receiver and optionally unregisters Softcam.

For Android-to-Windows DirectShow verification, start the Android camera server on the same LAN and run either pair-code discovery:

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

or manual RTSP:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -Ffmpeg C:\deps\ffmpeg\bin\ffmpeg.exe `
  -RtspUrl rtsp://PHONE_IP:8554/ `
  -Register `
  -KeepReceiverRunning
```

`-KeepReceiverRunning` leaves the same receiver process live after FFmpeg DirectShow capture and writes `runtime-evidence.json`, `manual-app-enumeration-checklist.txt`, and `manual-app-evidence-template.json` beside `runtime-summary.txt`. It cannot be combined with `-SkipCapture`; OBS/browser evidence must be tied to a real FFmpeg DirectShow capture and saved `directshow-frame.bmp` artifact. The structured runtime evidence includes the receiver process id, selected/opened RTSP URL, non-empty runtime log paths, DirectShow capture frame counts, capture logs naming the expected camera, a saved PNG/JPEG/BMP DirectShow frame snapshot, and generated manual checklist/template paths, which final MVP validation treats as required Android LAN evidence. The generated manual template also carries `runtimeArtifacts.directShowFrameSnapshot`, `runtimeArtifacts.directShowSnapshotLog`, `runtimeArtifacts.directShowCaptureLog`, `directShowFrameMatchesExpectedAndroidStream`, and `directShowFrameReviewNote` for operator review, and the manual-evidence validator cross-checks those paths against `runtime-evidence.json` while requiring the operator to confirm the saved DirectShow snapshot matches the expected Android stream. Save non-empty OBS and browser/camera-app screenshots beside the evidence file; they must be separate PNG, JPEG, or BMP app screenshots with different image content and must not reuse the DirectShow frame snapshot path or content. Use the generated checklist and evidence template to record enumeration against the same live Android stream with matching `receiverProcessId`, DirectShow snapshot review values, and `screenshotPath` values, set `status` to `passed`, then validate the completed evidence file:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -ValidateManualEvidence PATH\TO\manual-app-evidence-template.json `
  -RuntimeEvidence PATH\TO\runtime-evidence.json
```

After validation, stop the reported receiver process and cleanly unregister Softcam from an elevated PowerShell with:

```powershell
.\desktop\windows\scripts\Test-PhoneCamWindowsRuntime.ps1 `
  -SoftcamRoot C:\deps\phonecam-softcam `
  -UnregisterOnly
```

After the physical Android matrix, Windows runtime, and manual OBS/browser evidence files are captured, run the repo-level final gate:

```powershell
ruby .\scripts\validate_mvp_evidence.rb `
  --android-matrix PATH\TO\matrix-evidence.json `
  --windows-runtime PATH\TO\runtime-evidence.json `
  --windows-manual PATH\TO\manual-app-evidence-template.json
```

The packaged Windows MVP includes `scripts\validate_mvp_evidence.rb`; run it from a shell with Ruby available.
The final gate also cross-checks the Windows runtime RTSP URL and auto-discovery pair code against the physical Android matrix evidence, requires Android receiver metrics with zero decode errors and profile-bounded incoming Mbps, requires captured rotation artifacts, recorded `Rotate Left`/`Rotate Right` direction, rotation request mode, 0/90/180/270 output-rotation degrees, requested absolute output-rotation target consistency, sender camera diagnostics, device posture, and `orientationStatus: "passed"` for the physical direct/back and front-camera checks, requires non-empty Windows runtime log files, verifies those logs contain the selected Android RTSP URL, DirectShow camera name, FFmpeg capture camera name, enough FFmpeg capture frames, and a saved PNG/JPEG/BMP DirectShow frame snapshot, rejects DirectShow captures that return fewer frames than `requestedFrames`, requires generated manual checklist/template artifacts, and requires the manual OBS/browser evidence to match the runtime receiver process id and generated manual evidence template path. OBS and browser/camera-app screenshots must be distinct PNG, JPEG, or BMP app screenshots, must have different image content from each other, and cannot reuse the saved DirectShow frame snapshot path or content. Capture the Android matrix and Windows DirectShow run against the same phone on the same LAN.

The evidence bundler validates the source evidence before copying and validates the rewritten bundled evidence afterward. Use `--skip-validation` only while debugging path issues; do not use it for the final MVP archive.

Manual end-to-end Windows checklist:

1. Build `phonecam-receiver.exe` with `PHONECAM_REQUIRE_SOFTCAM=ON`.
2. Build PhoneCam-branded Softcam.
3. Start the Android RTSP server on the same Wi-Fi network.
4. Run the Windows runtime verification helper above with `-AutoDiscover` or `-RtspUrl` and `-KeepReceiverRunning`.
5. Confirm OBS or a browser camera test can select and display `PhoneCam Virtual Camera` while that receiver process is still running.
6. Optionally run `phonecam-receiver.exe --auto-discover --pair-code PHONE_CODE --discover-seconds 5 --fps 60` separately to inspect the Win32 preview window.
7. Stop the receiver and unregister Softcam to verify clean removal.

When validating the Android Wi-Fi path from a Mac or Linux development host before moving to Windows, use:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_receiver_smoke.sh
```

That helper selects a non-emulator adb target by default, proves direct LAN RTSP decode from a physical Android phone, records FPS/bitrate/decode-error metrics, separately records whether pair-code discovery worked, then verifies decode after switching the phone to the front camera. It also records Android UI dumps, screenshots, logcat, rotation artifacts, `Rotate Left`/`Rotate Right` direction, rotation request mode, requested absolute output-rotation target when used, resulting 0/90/180/270 output-rotation degrees, and the sender `Camera diagnostics` line, and requires `STREAM_ORIENTATION_STATUS=passed`, `STREAM_ORIENTATION_NOTES`, `STREAM_DEVICE_POSTURE`, `FRONT_CAMERA_ORIENTATION_STATUS=passed`, `FRONT_CAMERA_ORIENTATION_NOTES`, and `FRONT_CAMERA_DEVICE_POSTURE` for an acceptance run after the physical receiver output has been inspected. The helper fails early when those acceptance fields are absent unless `ALLOW_UNVERIFIED_ORIENTATION=1` is set for exploratory, non-final collection. It does not prove DirectShow registration or OBS camera enumeration; those still require the Windows runtime verification steps above.

For full physical profile evidence before the Windows pass, run:

```bash
RECEIVER_BIN=/path/to/phonecam-receiver scripts/android_wifi_profile_matrix_smoke.sh
```

That matrix helper repeats the physical Wi-Fi decode/discovery check across Efficient, Balanced, and Motion, records profile-bounded incoming Mbps for each run, then keeps the front-camera decode/orientation check on the final profile.
