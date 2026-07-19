# Teamwork Project Prompt — PhoneCam 4K60 Remake

Rebuild PhoneCamRedux into a phone-as-webcam system capable of 4K60 HEVC end-to-end over WiFi (primary use case), with a USB-cable fallback, targeting Android and iOS senders and Windows and macOS receivers. Performance-first native architecture: Kotlin/Camera2/MediaCodec on Android, Swift/AVFoundation/VideoToolbox on iOS, C++ with hardware decode on desktop. Streaming cores stay strictly decoupled from UI, but a minimal functional control UI IS in scope (the original app's fatal flaw was having none).

Working directory: ~/Documents/GitHub/PhoneCamRedux
Integrity mode: development

## Context — read before writing any code

- `PhoneCamRetry-original-repo-old/` is the reference known-good implementation: Android sends MJPEG over TCP through `adb forward` to a Python receiver (`knowngood.py`) that outputs to an OBS virtual camera. It is 1080p60, USB-only, UI-less — but it WORKS. Treat its latency and reliability as the bar to beat. READ-ONLY; never modify it.
- A previous agent pass left a partial, UNCOMMITTED implementation in the working tree: `android/app/src/main/java/com/phonecam/stream4k/` (Camera2Pipeline, HevcEncoder, RtpHevcPacketizer, UdpStreamSender, CapabilityProbe, Stream4kController) and `desktop/windows/src/` (main.cpp, rtp_hevc.cpp/.h, CMakeLists, vcpkg.json). Do NOT assume this code works and do NOT rewrite it from scratch reflexively. First audit it against the protocol spec (R1), keep what's correct, fix or replace what isn't, and record the audit verdict in `docs/verification-4k60.md`.
- The existing RTSP path (`RtspMainActivity.kt`, `activity_rtsp.xml`, discovery via `DiscoveryBeaconProtocol.kt`) must keep working as the legacy/compatibility mode.
- `legacy/`, `PhoneCamRetry-original-repo-old/`, `dist/`, and the UnityCapture licensing posture are untouchable. No git mutations of any kind (no commit/push/reset/branch).
- This host is a Mac. Anything that can only be verified on Windows or on physical phones must be delivered as exact, copy-pasteable commands for the user plus automated tests that run on macOS/CI where possible.

## Phase 0 — Protocol contract (blocks all platform work)

### R1. Wire protocol specification + conformance vectors
Write `docs/protocol-4k60.md` as the single source of truth ALL platform teams implement against:
- Media transport: RTP/UDP carrying HEVC per RFC 7798 (FU and single-NAL modes, marker bits, sequence rollover, 90 kHz timestamps).
- Reliability layer for real WiFi — this is mandatory, not optional: receiver-driven NACK retransmission with a bounded sender history buffer, receiver jitter buffer with configurable target (default ≤ 50 ms), and a keyframe-request (PLI-equivalent) control message for unrecoverable loss.
- Control channel on UDP port 47822: versioned JSON handshake (capabilities exchange: max resolution/fps ladder, codec, transport), start/stop, bitrate adaptation feedback (receiver reports loss/jitter, sender adapts bitrate and, only when needed, steps down the ladder 4K60 → 4K30 → 1080p60), keepalive/timeout.
- Discovery: reuse the existing beacon protocol for peer addressing; document it in the same file.
- Cable fallback framing: the identical elementary stream and control messages over a single TCP connection (length-prefixed frames) so the transport swaps without touching encoder/decoder code.
- Ship language-neutral conformance test vectors (hex fixtures for packetization/depacketization edge cases: FU split/reassembly, seq rollover, NACK, handshake) under `docs/protocol-vectors/`, consumed by both Android unit tests and desktop CTest.

## Platform workstreams (parallel after R1)

### R2. Android 4K60 sender core
Audit and complete `com.phonecam.stream4k` to full R1 conformance: Camera2 + MediaCodec HEVC (capability-probed; use the probe to gate the offered ladder), packetizer + NACK history + control channel, adaptive bitrate. Add the TCP cable transport (same stream over `adb forward tcp`). Keep the core free of any Activity/UI imports. Unit-test packetizer and control state machine against the R1 vectors. Scope: `android/app`.

### R3. Desktop receiver — shared core, two targets
Restructure `desktop/` into a shared C++ receiver core (depacketizer, jitter buffer, NACK generator, control client, stats) with platform decode/output backends:
- `desktop/windows`: D3D11VA/NVDEC decode, output to the existing softcam/virtual-camera path. Keep current CMake/vcpkg/CTest working.
- `desktop/macos`: VideoToolbox decode. Virtual camera on macOS requires a signed CMIO Camera Extension — implement the extension target and document the signing steps for the user, but acceptance for this pass is a live low-latency preview window plus clean frame-callback API the extension consumes. NEVER stub the extension with fake success paths.
- Both targets support UDP (primary) and TCP-cable ingest, print per-stage stats (network fps, loss %, NACK recoveries, decode fps, end-to-end frame age), and pass the R1 conformance vectors in CTest.

### R4. iOS sender
New `ios/` SwiftPM/Xcode project: AVFoundation capture + VideoToolbox HEVC encode + the same R1 packetizer/control implementation in Swift, core decoupled from UI, minimal start/stop UI. Acceptance for this pass: `xcodebuild build CODE_SIGNING_ALLOWED=NO` succeeds for a device target, protocol unit tests pass against the R1 vectors via `xcodebuild test` on a simulator (capture paths behind a protocol so protocol logic tests don't need a camera). Real-device streaming is user-run; provide exact steps. USB (usbmuxd) cable mode for iOS may be documented as future work — do not fake it.

### R5. Minimal control UI wiring
Android: extend the existing activity with mode selection (4K60 UDP / RTSP legacy / USB cable), resolution-fps ladder picker gated by the capability probe, connection status, and live measured fps/Mbps. Desktop targets: CLI flags + on-screen/console stats are sufficient. No visual polish, no cross-platform UI framework this pass.

## Phase 2 — Validation & documentation

### R6. End-to-end validation
- Synthetic: receiver must sustain ≥ 55 fps (target 60) depacketize+decode of an ffmpeg-generated 3840x2160@60 HEVC RTP/UDP localhost stream for ≥ 60 s with < 1% post-NACK loss, and demonstrate NACK recovery under artificially injected loss (e.g. 2% drop), printing per-stage stats.
- Hardware: ATTEMPT real validation. If a phone is reachable via adb: install, stream 4K60 over WiFi to the mac receiver, and separately verify the TCP cable path via `adb forward`; record measured fps/Mbps/loss/latency. If no hardware is reachable, output exact step-by-step user-run commands instead. NEVER report a number that was not measured; every figure in `docs/verification-4k60.md` must state how it was measured. If real hardware can't hold 4K60, record the measured ceiling and the ladder step actually sustained.

### R7. Documentation
Update `README.md`, `docs/architecture.md`, `docs/requirements.md`: 4K60 UDP is the production path, RTSP is legacy fallback, USB cable is the wired fallback for both. Document the Windows build (user-run), macOS build, iOS build+deploy, and the CMIO extension signing steps. Remove stale references to quarantined `legacy/` paths.

## Acceptance criteria — verification commands (run on this Mac)

- [ ] `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug` exits 0.
- [ ] `cd desktop && cmake -B build/macos -DFFMPEG_ROOT="$(brew --prefix ffmpeg)" -DPHONECAM_TARGET=macos && cmake --build build/macos && ctest --test-dir build/macos --output-on-failure` all exit 0 (adjust flags to the final CMake layout, but macOS build+CTest must run locally).
- [ ] `xcodebuild -project ios/... build CODE_SIGNING_ALLOWED=NO` (device target) and simulator protocol tests exit 0.
- [ ] Synthetic 4K60 soak (R6) passes with printed per-stage stats, including the injected-loss NACK recovery run.
- [ ] Windows: exact user-run build/test commands documented; CMake for the Windows target configured but not required to build on this host.
- [ ] `docs/protocol-4k60.md`, `docs/protocol-vectors/`, and `docs/verification-4k60.md` exist; every number in the verification doc is labeled with its measurement method.
- [ ] Legacy RTSP mode still builds and its entry points are untouched-or-working.

## Hard constraints

- No git mutations. No changes under `legacy/`, `PhoneCamRetry-original-repo-old/`, or `dist/`. UnityCapture licensing posture unchanged.
- No fabricated benchmarks, no stubbed "success" paths standing in for hardware features, no silent scope cuts — anything cut or deferred must be listed in `docs/verification-4k60.md`.
- Protocol doc (R1) merges before platform teams write transport code; platform teams treat it as the contract and propose spec changes by editing the doc, not by diverging.
