# PhoneCam release and performance readiness

Audit date: 2026-09-07; final validation continued on 2026-09-08. This report records implemented improvements and the tests possible on the available Mac. It does **not** certify Windows hardware throughput, zero leaks, Samsung compatibility across models, or store approval.

## Implemented

| Area | Change and intended benefit |
| --- | --- |
| Windows decoding | RAII for FFmpeg codec/packet/frame/scaler resources, padded input, correct EAGAIN/drain behavior, EOF flush, D3D11VA when available, explicit software fallback. RTSP H.264/HEVC demux works separately from native HEVC. |
| Windows output | Reusable producer/pending/consumer buffers; only the latest pending frame is retained. Preview is capped at 30 FPS; Softcam gets stream-rate output. Output dimensions stay fixed through bandwidth adaptation. Snapshot copied once. |
| Softcam patch | Pinned upstream revision; 100 ns sample timestamps derived from frame index, fixing integer-millisecond timing (240 FPS previously became 250). Reused per-thread waitable timer, no redundant full-frame clear, checked sample sizes/formats, isolated shared-memory names, concurrent send/delete ownership. |
| Desktop core | Playout capped at 32 frames and 32 MiB; AU/FU capped at 8 MiB; bounded retransmission work; damaged AUs request keyframes. EOF always joins threads. TCP records/partial writes validated and serialized; connection timeout 3 s; idle receive timeout in receiver. Timestamp wrap handled incrementally. |
| Android | Public camera/HEVC-encoder capability intersection; exact camera ID and encoder retained per mode. Encoder-only constrained high-speed sessions for exposed 120/240 modes. No assumption that 60 FPS requires a constrained session. Bounded send queues, persistent RTP sequence across adaptation, lifecycle generation checks and resource cleanup. API 36, modern Back dispatch and system-bar insets. |
| iOS | Correct retransmission packet copies, bounded network queues/history, hardware HEVC preference, exact requested capture frame duration, encoder drain before callback-owner teardown, synchronized sender snapshots, real negotiated receiver address, camera/local-network descriptions and foreground opt-in. |
| macOS | Decode session reused when parameter sets are unchanged; callbacks drained before invalidation. Preview retains its image buffer and allows only one pending UI update. CMIO extension remains a skeleton. |
| Distribution | Release build no longer uses Android debug signing. Windows package gate rejects GPL/nonfree/non-shared FFmpeg configurations and requires license/source/build inputs plus signatures unless explicitly making a development package. |

These limits cover individual queues, not total process memory. A single 4K BGR24 image is 24,883,200 bytes. Three reusable output buffers alone require about 71.2 MiB, before decoder surfaces, playout, Softcam shared memory and an optional snapshot. One BGR pass is about 1.49 GB/s at 4K60 and at 1080p240; readback/conversion/consumer copies can multiply that traffic. D3D11VA is not a zero-copy virtual-camera implementation.

## Samsung: supported high-speed path and limits

The implementation checks all publicly enumerated camera IDs, fixed AE ranges/output frame durations, constrained high-speed sizes/ranges and HEVC encoder size/rate support. A mode is advertised only when camera and encoder agree. Hardware codec capability metadata is a prerequisite, not a sustained thermal performance guarantee.

For an exposed 1080p120/240 mode, it creates an encoder-surface-only constrained high-speed session and submits the required high-speed request list/burst. This avoids the unsupported output combinations that can make a capable phone appear limited. Android defines constrained high-speed sessions for rates of at least 120 FPS and restricts their surfaces and controls. Normal 4K60 uses the normal capture session when its fixed range is exposed. [Android high-speed session contract](https://developer.android.com/reference/android/hardware/camera2/CameraConstrainedHighSpeedCaptureSession).

No supported universal public-API override for a mode hidden by Samsung firmware was established. Do not infer third-party availability from the stock camera's slow-motion menu, a different model, or an old forum report. The implementable fallback is another exposed camera/size/rate, followed by firmware/model-specific testing. OEM partner access would require a separate agreement and documented SDK review; no private API, package impersonation or rooted-device dependency is included.

For each Samsung model/firmware: record model, SoC, Android/One UI build, camera ID, encoder name, fixed ranges and selected size; stream each exposed target for 30 minutes; verify real captured/decoded cadence, dropped frames, heat, exposure, orientation, camera switching and screen/background transitions. Missing 240 FPS must be shown as unsupported, not replaced by duplicated 60 FPS frames.

## Local validation

The committed regression suites cover bounded queues, timestamp wrap, oversized NAL/FU input, limited NACK work, TCP EOF/hostile record cleanup, camera/encoder intersections and packetization history. Local results:

| Check | Result |
| --- | --- |
| Android debug APK + JVM suite | 54 tests, zero failures/errors; compile/target SDK 36. |
| Android release bundle | `:app:bundleRelease` passed including release vital lint. ZIP integrity passed; no bundled `.so` files and no signing blocks. The AAB is unsigned. |
| iOS simulator suite | 17 tests, zero failures on the final source; iPhone 17 Pro simulator, iOS 27.0 beta environment. A stalled parallel rerun was interrupted; serial retry passed. Device unsigned build also passed earlier in this audit. |
| Release receiver CTest | 5/5 passed, including 30 TCP EOF/hostile-length cleanup cycles. |
| Core AddressSanitizer + UndefinedBehaviorSanitizer | 3/3 passed; no reported sanitizer violation. Native stress includes 100,000 bounded playout pushes. macOS ASan does not certify Linux LeakSanitizer or Windows private-memory behavior. |
| macOS VideoToolbox/Cocoa receiver | Compiled successfully with the preview ownership/session reuse changes. Physical camera rendering not exercised. |
| HEVC file decode | 30 frames at 3840×2160/60 metadata and 60 frames at 1920×1080/240 metadata decoded with zero errors. Short solid-color fixtures test decoding correctness only. |
| Local software throughput | Approximately 10.1 FPS for 4K and 44.5 FPS for 1080p on this Mac during the final fixture runs; swscale reported unaccelerated YUV420P→BGR24. These runs failed to demonstrate the requested real-time rates and are not Windows GPU measurements. |
| Proprietary release gate | Correctly rejected the installed GPL Homebrew FFmpeg with exit code 2. |
| Softcam patch applicability | Applied cleanly to upstream `e89a699ed9932c74f57afe4f396be89665967e00`; Windows compilation/runtime remains unverified locally. |

Release AAB: `android/app/build/outputs/bundle/release/app-release.aab` (5,360,288 bytes), SHA-256 `f0f4d8a90bed226ac1cd60b66dfe8a3728c2508f1ff376b3f987a9ff79b649c3`. Build log: `/tmp/phonecam-android-release-build.log`. Sign and validate through the distributor’s release process before upload.

Local logs were written under `/tmp/phonecam-*-final*.log` and the earlier iOS result bundle `/tmp/phonecam-ios-final-tests.xcresult`; the final serial pass is in `/tmp/phonecam-ios-serial-final.log`; these temporary paths are local evidence, not portable release artifacts. The commands below reproduce the checks.

```sh
cmake -S desktop/windows -B build/receiver -DCMAKE_BUILD_TYPE=Release \
  -DFFMPEG_ROOT=/path/to/ffmpeg -DPHONECAM_WITH_SOFTCAM=OFF
cmake --build build/receiver --parallel 4
ctest --test-dir build/receiver --output-on-failure

cmake -S desktop -B build/sanitizers -DPHONECAM_TARGET=core \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build build/sanitizers --parallel 4
ctest --test-dir build/sanitizers --output-on-failure

FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh
xcodebuild -project ios/PhoneCamSend.xcodeproj -scheme PhoneCamSend \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -parallel-testing-enabled NO test
```

CI now includes core ASan/UBSan, Android tests, iOS simulator tests and the Windows Softcam lifecycle executable. A local code/build pass does not mean those remote Windows jobs have run. The Softcam test runs 100 create/send/delete cycles with concurrent calls and checks process handles/private memory; Windows is required to execute it.

## Windows acceptance procedure

Build the pinned patched Softcam with `Prepare-PhoneCamSoftcam.ps1`, configure the receiver with `PHONECAM_REQUIRE_SOFTCAM=ON`, build Release and run CTest. Register the signed branded filter on the Windows test host using the existing runtime helper. The registration step requires elevation; the camera is a user-mode DirectShow filter, not a kernel driver.

Run each mode actually exposed by the phone, both native UDP and wired TCP. Example:

```powershell
.\desktop\windows\scripts\Test-PhoneCamHighFps.ps1 `
  -Receiver .\build\windows-softcam-receiver\Release\phonecam-receiver.exe `
  -Source udp://PHONE_IP:5004 -Mode 4k60 -Seconds 1800 `
  -OutputDirectory C:\evidence\4k60-udp
```

Use `1080p120` and `1080p240` for the other targets. The helper captures stdout/stderr and per-second private bytes, working set, handles and CPU time. It requires the exact negotiated resolution/rate, no lower-resolution source frames, at least 90% target output FPS, zero decode errors, sufficient frames, and bounded growth after 30 s warmup (64 MiB private bytes, 32 handles). These thresholds detect regressions; inspect the time series for a trend and repeat longer leak runs before release. `-NoSoftcam` isolates decoding and cannot count as virtual-camera evidence. `-SoftwareDecode` isolates the fallback.

Capture the registered camera in FFmpeg DirectShow/OBS at the same negotiated format while this run is active. Record consumer FPS, timestamps, duplicate/drop counts and visible source motion. Test 100 connect/disconnect cycles, receiver/app crashes, receiver restart, camera unplug/background, temporary network loss, permission revocation, 0/90/180/270 orientation and unsupported-mode rejection. Record Windows build, GPU/driver, CPU, network link and both binary hashes. Consumer apps may cap at 30/60 even when DirectShow advertises 120/240.

If readback/BGR copies prevent the target, the next architectural step is a separately tested NV12/GPU surface path with a real Media Foundation virtual camera/media source. Microsoft's API is available on Windows 11; it does not itself implement the source or solve frame ownership. [MFCreateVirtualCamera](https://learn.microsoft.com/en-us/windows/win32/api/mfvirtualcamera/nf-mfvirtualcamera-mfcreatevirtualcamera).

## Proprietary distribution and stores

The current MIT application/Softcam and Apache-2.0 Android dependencies permit a proprietary derivative subject to attribution and their license terms. Preserve upstream copyright notices. A reviewed dynamically linked LGPL FFmpeg build can be used while keeping application source private; the FFmpeg sources/modifications, licenses, build instructions and LGPL relinking/reverse-engineering rights still need to be supplied. GPL/nonfree builds and legacy pyvirtualcam are excluded from this package path. HEVC patent review is separate. [FFmpeg distribution checklist](https://www.ffmpeg.org/legal.html). See [third-party notices](third-party-notices.md) for dependency details.

`Package-PhoneCamWindows.ps1` requires the binary directory, Softcam installer/license, exact FFmpeg source archive and build instructions, a dependency-license directory, and a new output directory. It checks `--release-check`, required runtime DLLs and Authenticode signatures on the receiver/Softcam/installer. It produces a SHA-256 manifest. `-DevelopmentPackage` only bypasses signatures. It cannot verify archive correspondence or every transitive dependency's license; those remain release-owner checks. Do not ship the Homebrew FFmpeg used on this Mac or treat old MVP CI artifacts as a proprietary release package.

Google Play: compile/target SDK is now 36, meeting the stated August 31, 2026 new-app/update target requirement. Create a signed release AAB using the distributor's upload key and Play App Signing; choose owned application identity/versioning, complete Data safety/privacy policy and store assets, and run device/pre-launch testing. [Target API policy](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en). This audit's unsigned release AAB contains no `.so` libraries. Recheck the signed shipping AAB if dependencies change and verify 16 KB support for any added native libraries. [16 KB guidance](https://developer.android.com/guide/practices/page-sizes).

Apple: build uploads with iOS 26 SDK or later under the current April 28, 2026 requirement. [Apple SDK notice](https://developer.apple.com/news/?id=ueeok6yw). Camera and local-network purpose strings and foreground consent are implemented. Release still needs an owned bundle ID/team, distribution signing/provisioning, finished icons/launch/orientation/iPad metadata, an audit of required-reason API/privacy-manifest use and SDKs, truthful App Privacy answers/privacy policy, screenshots and a physical-device archive/TestFlight pass. Follow public APIs, permission/recording transparency and app completeness requirements. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

The native control/media protocol is currently unencrypted and does not authenticate receivers cryptographically. Foreground opt-in reduces accidental access but does not identify a trusted peer. Before a general consumer release, implement authenticated pairing and protected transport, or constrain distribution to a clearly disclosed trusted-network development use case. The six-digit discovery code is a selector, not a security boundary. macOS virtual-camera distribution additionally requires completing, signing and testing the CMIO extension; the existing skeleton must not be marketed as working camera output.

No store submissions, signing-key creation, Windows registration or public deployment were performed in this audit.

## September 8 connection and latency follow-up

The Windows receiver now waits for a phone by default, advertises a Bonjour computer service, and shows PC address codes plus a Private-network firewall helper. Android and iOS provide a computer picker, manual code/address entry, automatic 1080p60/30 negotiation, and foreground reconnect/stop. Legacy inbound phone access is in Advanced options. See [easy connection](easy-connection.md) for routed-network limits.

Native TCP disables Nagle and adds no deliberate playout delay; iOS sends one batch per access unit. Advanced UDP buffering starts at 10 ms and adapts within 5–50 ms rather than using a fixed 50 ms. Queued compressed frames have an 80 ms age limit on insertion and recover at an IDR after loss/overflow. These are implementation changes, not new measured end-to-end latency or hardware throughput claims.

Physical Windows DNS-SD, firewall approval, virtual-camera consumers, and real Android/iOS Wi-Fi/router combinations remain required acceptance tests. The unsigned artifacts from the earlier audit predate this follow-up; rebuild release packages before distribution.

Follow-up local validation: Android 57 tests passed and the final debug APK rebuilt; iOS 18 simulator tests passed and the final unsigned device build succeeded. All 5 native receiver checks and all 3 ASan/UBSan suites passed, including the fixed manual-delay retention regression. The reverse TCP fixture decoded 10 real HEVC frames without decode errors, and the receiver appeared in a live macOS Bonjour browse. No physical Windows or multi-router hardware result is claimed.

## Branch integration status

This update was implemented and tested from `295ff13` on the Softcam-based checkout. Fetching before publication found upstream `main` at `9ed0311`, with a newer Media Foundation virtual-camera implementation, additional sender/transport changes, packaging, and CMIO work. This update is published on `codex/home-network-latency-update` to preserve that upstream implementation. The results in this report apply to this branch; they do not validate a combination with the newer upstream code. Port and review these changes against the Media Foundation branch before merging to `main`.
