<div align="center">

# PhoneCamRedux

**Turn your Android phone or iPhone into a camera for your computer.**

[![Build](https://github.com/KhazP/PhoneCamRedux/actions/workflows/build.yml/badge.svg)](https://github.com/KhazP/PhoneCamRedux/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[Get connected](#get-connected) · [Patch notes](#home-network-update--september-8-2026) · [Build](#build-from-source) · [Testing](#verification) · [Full changelog](CHANGELOG.md)

</div>

PhoneCam sends camera video over your home network to a native desktop receiver. On Windows, the PhoneCam-branded DirectShow component exposes **PhoneCam Virtual Camera** to compatible calling, recording, and streaming apps.

Native HEVC modes target **4K60** and **1080p120/240** where the phone camera, encoder, network, receiver, and consuming app support them. Hardware acceptance testing is still required; these are not guaranteed frame rates on every device. The macOS receiver can receive and decode video, while its CMIO virtual-camera extension remains unfinished.

## Get connected

1. **Open the PC receiver.** Launch `phonecam-receiver.exe`. Leave the connection window open and allow **Private-network** access when Windows asks.
2. **Find your computer.** Open PhoneCam on Android or iOS, tap **Find my computer**, and choose the computer name. Allow camera and local-network access.
3. **Use your camera.** With the Windows virtual-camera component installed, select **PhoneCam Virtual Camera** in your calling or recording app. Keep PhoneCam open on your phone.

**Computer missing?** Enter the **PC code** shown on the receiver, or its IP address. The phone initiates the connection and reconnects while the app stays open. **Stop connection** or backgrounding the app stops the camera and reconnect attempts.

The automatic connection prefers **1080p60**, then **1080p30**, then another mode exposed by the device. No account or USB cable is required. Build instructions are below; source changes do not constitute a signed installer release.

### Same home, different routers?

| Your setup | Connection path |
| --- | --- |
| Same Wi-Fi/router, including a PC on Ethernet | Use **Find my computer**. |
| Mesh Wi-Fi, different Wi-Fi names, or another router in access-point mode | Discovery works when devices share a LAN and multicast is allowed; otherwise use the PC code. |
| Phone behind a second router, PC on the upstream LAN | Try the PC code. Phone-initiated TCP often works when routing/firewall policy allows it. |
| Guest Wi-Fi, client isolation, or a PC behind a separate NAT router | Use the same main network or configure suitable routing. A code cannot bypass network isolation. |

The LAN protocol is currently unencrypted. PC codes contain an address and a typo checksum; they are **not passwords**. Use a trusted network. See the [connection guide](docs/easy-connection.md) for firewall help, custom ports, and router examples.

## Home Network Update · September 8, 2026

This update focuses on easier connections, less queued video, and more reliable high-frame-rate streaming. Full details are in the [patch notes](CHANGELOG.md).

### Added — easier setup

- **PC waiting screen:** launching the Windows receiver now shows the computer name, connection codes, copy button, and connection help.
- **Find my computer:** Android and iOS browse for nearby receivers using native Bonjour/DNS-SD support.
- **PC-code fallback:** enter a short address code or `IP:port` when discovery does not cross your network layout.
- **Phone-initiated connections:** native TCP connects from the phone to the PC, with foreground reconnect and explicit stop controls.
- **Windows network helper:** an app-scoped Private-network firewall setup button; Windows requests administrator approval before rules change.
- **Cleaner mobile setup:** advanced UDP/TCP and Android RTSP controls sit in an expandable panel.

### Tuned — latency and frame pacing

- **Adaptive UDP buffering:** starts at **10 ms**, adjusts between **5–50 ms**, grows quickly for jitter/loss, and shrinks gradually. `--jitter-ms` still selects a fixed delay.
- **Immediate TCP playout:** no deliberate receiver delay, Nagle disabled, and complete access-unit batching on both mobile senders.
- **Fresh-frame delivery:** bounded compressed queues, stale-backlog rejection, and one newest pending decoded frame keep slow stages from accumulating unlimited video.
- **Windows hardware decode:** optional **D3D11VA** HEVC decoding, reusable conversion/output buffers, and a software fallback.
- **High-FPS timing:** Softcam uses precise frame intervals through 240 FPS, reusable timer resources, and fewer redundant large-buffer clears.

Reducing the old 50 ms UDP default to 10 ms removes **40 ms of configured initial buffering**. This is not a measured 40 ms improvement in total camera-to-screen latency. TCP loss, camera exposure, encoding, GPU readback, and consumer buffering still matter.

### Fixed — stability and compatibility

- Clean shutdown after disconnects, malformed TCP records, and repeated stop calls; bounded network waits and serialized partial writes.
- Bounded RTP access units, fragments, retransmission work, and queues; request a keyframe after damaged or discarded reference frames.
- Safer Windows decoder ownership and Softcam concurrent send/delete behavior; corrected high-FPS timestamp rounding.
- Android mode selection intersects actual **camera and HEVC encoder capabilities**, including supported constrained high-speed camera sessions.
- iOS packet-history payloads, capture timing, encoder teardown, peer destinations, and stale connection callbacks.
- macOS VideoToolbox session reuse and bounded preview-buffer lifetime.
- A real H.264/HEVC **RTSP demux/decode fallback**, alongside the native HEVC paths.

### Added — release and QA tools

- Android target SDK 36, unsigned release configuration, foreground camera consent, and lifecycle cleanup.
- Windows high-FPS soak and Softcam lifecycle tests, shared native sanitizer checks, and Android/iOS regression jobs.
- A release packager that checks FFmpeg licensing configuration, required runtime files, signatures, notices, source/build documentation, and artifact hashes.

## Streaming modes

| Mode | Connection | Best fit |
| --- | --- | --- |
| **Easy connection** | Phone → PC, native HEVC/TCP on **47823** | Start here: discovery, codes, automatic format, reconnect. |
| **Advanced native UDP** | Control **47822**, RTP media **5004** | Manual low-latency tuning, retransmission, and bandwidth adaptation. |
| **Advanced native TCP** | PC → phone on **47822** | Manual LAN connections or developer port forwarding. |
| **Android RTSP** | H.264/RTSP on **8554** | Existing preview, quality profiles, rotation, and legacy phone discovery. |

Advanced direct connections require **Allow receiver access** in the mobile app's advanced panel. This lets a receiver on that network request camera streaming while the app remains open.

```powershell
# Wait for your phone and request a specific supported mode.
phonecam-receiver.exe --listen --width 3840 --height 2160 --fps 60
phonecam-receiver.exe --listen --width 1920 --height 1080 --fps 240

# Advanced UDP with a fixed 20 ms playout delay.
phonecam-receiver.exe --rtsp udp://PHONE_IP:5004 --width 1920 --height 1080 --fps 120 --jitter-ms 20

# Advanced TCP and Android RTSP fallback.
phonecam-receiver.exe --rtsp tcp://PHONE_IP:47822 --width 1920 --height 1080 --fps 60
phonecam-receiver.exe --rtsp rtsp://PHONE_IP:8554/ --fps 30
```

Run `phonecam-receiver.exe --help` for discovery, headless testing, snapshots, input-file decoding, and dependency checks. Android's older six-digit **phone selector** is separate from the new **PC address code**.

## Build from source

### Android

Requires JDK 17 and the Android SDK.

```bash
cd android
./gradlew :app:testDebugUnitTest :app:assembleDebug --console=plain
```

The APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`. The repository helper `scripts/build_android_debug.sh` runs the same build and reports test results.

### iOS

Requires Xcode and the iOS SDK. Signing is needed to install on a physical device or distribute through Apple.

```bash
xcodebuild -project ios/PhoneCamSend.xcodeproj -scheme PhoneCamSend \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project ios/PhoneCamSend.xcodeproj -scheme PhoneCamSend \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -parallel-testing-enabled NO test
```

### Windows receiver

Requires Visual Studio with C++ tools, CMake, and vcpkg. This development build disables virtual-camera output:

```powershell
cmake -S desktop/windows -B build/windows-receiver `
  -G "Visual Studio 17 2022" -A x64 `
  -DCMAKE_TOOLCHAIN_FILE="$env:VCPKG_INSTALLATION_ROOT/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows `
  -DPHONECAM_WITH_SOFTCAM=OFF
cmake --build build/windows-receiver --config Release
ctest --test-dir build/windows-receiver -C Release --output-on-failure
```

To enable **PhoneCam Virtual Camera**, build and register the branded Softcam component and configure `SOFTCAM_ROOT`. Follow the [Windows build and verification guide](docs/developer-guide.md#windows-receiver-build). The helper pins and patches the upstream Softcam revision reproducibly.

### macOS development receiver

```bash
brew install ffmpeg
cmake -S desktop/windows -B build/macos-receiver \
  -DFFMPEG_ROOT="$(brew --prefix ffmpeg)" -DPHONECAM_WITH_SOFTCAM=OFF
cmake --build build/macos-receiver
ctest --test-dir build/macos-receiver --output-on-failure
```

This builds the shared FFmpeg receiver for development. The separate native macOS path uses VideoToolbox; its CMIO extension is still a skeleton. Homebrew FFmpeg is a local testing dependency and is not automatically suitable for a proprietary release package.

## Verification

| Local check | Result for this update |
| --- | --- |
| Android JVM regressions | **57 passed**; debug APK built. |
| iOS simulator regressions | **18 passed**; unsigned device build succeeds. |
| Native receiver suite | **5 checks passed**, including reverse TCP, negotiation, reconnect, malformed input, and legacy conformance. |
| Address/undefined-behavior sanitizers | **3 suites passed** for native memory, network lifecycle, and conformance. |
| Real HEVC connection smoke test | **10 frames decoded, zero decode errors** through phone-initiated TCP; deliberately paced, not a throughput benchmark. |
| Bonjour advertisement | Receiver appeared in a live local macOS service browse. |

Physical **Windows driver/GPU/consumer tests**, real **Samsung/iPhone camera throughput**, varied **router/firewall arrangements**, and synchronized end-to-end latency measurements are still required. Software tests and macOS discovery do not establish Windows hardware performance.

### Upstream integration

This branch was developed against the Softcam checkout at `295ff13`. Newer upstream `main` contains a Media Foundation camera pipeline and other overlapping changes. This update is published separately to preserve that work; integration and renewed validation are required before merging. See [branch integration status](docs/release-readiness.md#branch-integration-status).

## Project map

| Area | Contents |
| --- | --- |
| [`android/`](android/) | Android camera sender, discovery, native HEVC, and RTSP fallback. |
| [`ios/`](ios/) | iOS camera sender, VideoToolbox encoding, discovery, and native transports. |
| [`desktop/core/`](desktop/core/) | Shared protocol, RTP, connection, and playout logic. |
| [`desktop/windows/`](desktop/windows/) | Receiver, D3D11VA, Softcam patch, firewall, packaging, and validation tools. |
| [`desktop/macos/`](desktop/macos/) | Native macOS receiver and unfinished CMIO extension. |
| [`docs/`](docs/) | Setup, architecture, protocol, evidence, and release notes. |

## License and distribution

PhoneCamRedux is **MIT licensed**. Dependencies retain their own terms. A proprietary distribution needs the appropriate notices and a compatible FFmpeg build, plus the required FFmpeg source/build information and relinking rights. The release checker rejects detected GPL/nonfree FFmpeg configurations; HEVC patent considerations are separate from copyright licensing.

See [third-party notices](docs/third-party-notices.md) and [release readiness](docs/release-readiness.md) for the audit and remaining signing, privacy, packaging, and store-submission work.

**More documentation:** [Full patch notes](CHANGELOG.md) · [Connection guide](docs/easy-connection.md) · [Developer/QA guide](docs/developer-guide.md) · [Architecture](docs/architecture.md) · [Native protocol](docs/protocol-4k60.md)
