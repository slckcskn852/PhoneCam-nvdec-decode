# Original User Request

## Initial Request — 2026-07-19T15:34:52Z

Rebuild PhoneCamRedux into a phone-as-webcam system capable of 4K60 HEVC end-to-end over WiFi (primary use case), with a USB-cable fallback, targeting Android and iOS senders and Windows and macOS receivers. Performance-first native architecture: Kotlin/Camera2/MediaCodec on Android, Swift/AVFoundation/VideoToolbox on iOS, C++ with hardware decode on desktop. Streaming cores stay strictly decoupled from UI, but a minimal functional control UI IS in scope (the original app's fatal flaw was having none).

Working directory: ~/Documents/GitHub/PhoneCamRedux
Integrity mode: development

## Requirements

### R1. Wire protocol specification + conformance vectors
Write/update `docs/protocol-4k60.md` as the single source of truth ALL platform teams implement against:
- Media transport: RTP/UDP carrying HEVC per RFC 7798 (FU and single-NAL modes, marker bits, sequence rollover, 90 kHz timestamps).
- Reliability layer: receiver-driven NACK retransmission with a bounded sender history buffer, receiver jitter buffer with configurable target (default ≤ 50 ms), and a keyframe-request (PLI-equivalent) control message for unrecoverable loss.
- Control channel on UDP port 47822: versioned JSON handshake (capabilities exchange: max resolution/fps ladder, codec, transport), start/stop, bitrate adaptation feedback (receiver reports loss/jitter, sender adapts bitrate and steps down resolution/fps ladder if needed), keepalive/timeout.
- Discovery: reuse the existing beacon protocol for peer addressing; document it.
- Cable fallback framing: identical elementary stream and control messages over a single TCP connection (length-prefixed frames) so the transport swaps without touching encoder/decoder code.
- Conformance test vectors: raw binary files containing the exact byte streams, paired with human-readable hexadecimal representations/metadata in JSON files under `docs/protocol-vectors/`, consumed by Android unit tests, iOS unit tests, and desktop CTest.

### R2. Android 4K60 sender core
Audit and complete `com.phonecam.stream4k` to full R1 conformance:
- Camera2 + MediaCodec HEVC (capability-probed; use the probe to gate the offered ladder).
- Packetizer + NACK history + control channel, adaptive bitrate.
- TCP cable transport (same stream over `adb forward tcp`).
- Decoupled core from any Activity/UI imports.
- Unit-test packetizer and control state machine against R1 vectors.

### R3. Desktop receiver — shared core, two targets
Shared C++ receiver core (depacketizer, jitter buffer, NACK generator, control client, stats) with platform decode/output backends:
- `desktop/windows`: D3D11VA/NVDEC decode, output to existing softcam/virtual-camera path. Keep current CMake/vcpkg/CTest working.
- `desktop/macos`: VideoToolbox decode. A separate CMake target representing a standard CoreMediaIO Camera Extension skeleton, with its code linking to the frame-callback API of the receiver core, and build/signing instructions in `docs/architecture.md`. Acceptance is a live low-latency preview window plus clean frame-callback API.
- Support both UDP (primary) and TCP-cable ingest, print per-stage stats (network fps, loss %, NACK recoveries, decode fps, end-to-end frame age), and pass R1 conformance vectors in CTest.

### R4. iOS sender
New `ios/` Xcode Project (`ios/PhoneCamSend.xcodeproj` + `ios/PhoneCamSend` subfolder):
- AVFoundation capture + VideoToolbox HEVC encode.
- R1 packetizer/control implementation in Swift, core decoupled from UI, minimal start/stop UI.
- USB (usbmuxd) mode is documented as future work (no placeholder code/transports implemented).
- Acceptance: `xcodebuild build CODE_SIGNING_ALLOWED=NO` succeeds for a device target, protocol unit tests pass against R1 vectors via `xcodebuild test` on a simulator.

### R5. Minimal control UI wiring
- Android: extend existing activity with mode selection, resolution-fps ladder picker, connection status, and live measured fps/Mbps.
- Desktop: CLI flags + on-screen/console stats.

### R6. End-to-end validation
- Synthetic: receiver must sustain ≥ 55 fps (target 60) depacketize+decode of an ffmpeg-generated 3840x2160@60 HEVC RTP/UDP localhost stream for ≥ 60 s with < 1% post-NACK loss, and demonstrate NACK recovery under artificially injected loss, printing per-stage stats.
- Hardware: Attempt real validation (WiFi and TCP cable). Record measured fps/Mbps/loss/latency in `docs/verification-4k60.md`. If no hardware, output step-by-step user-run commands.

### R7. Documentation
Update `README.md`, `docs/architecture.md`, `docs/requirements.md` to reflect 4K60 UDP production path, RTSP legacy fallback, and USB cable wired fallback.

## Acceptance Criteria

### Build & Unit Tests
- [ ] Android unit tests pass and debug APK assembles: `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug` exits 0.
- [ ] Desktop macOS builds and CTest passes: `cd desktop && cmake -B build/macos -DFFMPEG_ROOT="$(brew --prefix ffmpeg)" -DPHONECAM_TARGET=macos && cmake --build build/macos && ctest --test-dir build/macos --output-on-failure` exit 0.
- [ ] iOS target builds and simulator protocol tests pass: `xcodebuild -project ios/PhoneCamSend.xcodeproj -scheme PhoneCamSend -sdk iphonesimulator test CODE_SIGNING_ALLOWED=NO` and builds for device exit 0.
- [ ] Windows: CMake configured for Windows target; exact build/test commands documented.
- [ ] Legacy RTSP mode still builds and works.

### Protocol & Validation
- [ ] `docs/protocol-4k60.md`, `docs/protocol-vectors/` (raw binary + JSON metadata), and `docs/verification-4k60.md` exist.
- [ ] Synthetic 4K60 soak (R6) passes with printed per-stage stats (including injected loss run).
