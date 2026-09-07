# PhoneCam patch notes

## September 8, 2026 — Home Network Update

**Focus:** connect with fewer steps, reduce accumulated video delay, and strengthen the high-FPS pipeline. This is a source update; hardware performance and signed release distribution remain separate acceptance gates.

### New features

- **Computer discovery:** Android NSD and iOS Bonjour list running PC receivers by name. Browsing is tied to foreground UI activity.
- **PC connection window:** default Windows startup waits for a phone and displays local addresses, short PC codes, copy controls, and connection help.
- **Phone-to-PC TCP:** phones open the native connection on port 47823, identify the protocol before control negotiation, and use the existing framed control/media stream.
- **Manual connection fallback:** checksummed PC address codes and host/IP inputs, with optional custom ports. Shared test vectors keep all three parsers compatible.
- **Automatic format negotiation:** easy mode prefers exposed 1080p60, then 1080p30, then another supported mode. Explicit desktop dimensions/FPS still request specific modes.
- **Foreground reconnect:** Android and iOS retry lost computer connections; stop controls and background transitions cancel connection attempts and release the camera.
- **Home-network firewall helper:** the Windows UI can launch the bundled app-scoped Private-profile rule installer with administrator approval. The helper retains legacy RTSP/discovery rules and adds native TCP/media and Bonjour ports.
- **Simple mobile controls:** legacy receiver access, native UDP settings, and Android RTSP profiles remain available in Advanced options. Existing RTSP QA helpers can open that panel directly.
- **Session visibility:** camera permission is requested before streaming; Android keeps the screen awake, and iOS disables auto-lock while receiver access or a connection is active.

### Performance tuning

- **Adaptive UDP playout:** initial delay reduced from 50 ms to 10 ms; feedback adjusts it within 5–50 ms. Increases react promptly, decreases are gradual, and fixed `--jitter-ms` overrides remain available.
- **TCP latency:** disabled Nagle on native connections and kept default TCP playout at zero. Both mobile senders batch complete access units instead of scheduling each RTP fragment independently.
- **Bounded backlog:** compressed queues enforce frame/byte limits and reject stale backlog on insertion. Longer fixed playout settings retain the requested delay. Output replaces the pending decoded frame with the newest one.
- **Decoder efficiency:** added optional Windows D3D11VA HEVC decode, reusable FFmpeg buffers/conversion state, and a software fallback. Kept virtual-camera output dimensions stable across source adaptation.
- **Softcam frame pacing:** replaced millisecond-rounded timing with frame-indexed 100 ns timestamps through 240 FPS; reused high-resolution wait resources and skipped redundant large-buffer clears.
- **macOS decode/preview:** reused VideoToolbox sessions when parameter sets stay unchanged and bounded retained preview buffers.

### Stability fixes

- Always join native client threads after EOF; make stop idempotent and bound socket polling/connect waits.
- Serialize TCP records, handle partial writes, disable oversized records, and validate negotiated dimensions/FPS.
- Bound JSON message size/depth and unsafe numeric fields before control processing.
- Cap HEVC access units/fragments and NACK work; identify incomplete access units instead of decoding damaged references.
- Request an IDR after damage or queue overflow and withhold dependent frames until recovery.
- Preserve RTP sequence/timestamp behavior through wrap and sender adaptation.
- Use RAII ownership for FFmpeg decoding and protect Softcam send/delete races with shared ownership and synchronization.
- Reuse stable PhoneCam-specific shared-memory names and harden Softcam media-format/sample-size checks.
- Restore actual RTSP H.264/HEVC demuxing and local-file decode instead of treating RTSP URLs as native HEVC endpoints.

### Android changes

- Match requested modes against camera IDs, encoder support, frame-duration limits, and advertised fixed FPS ranges.
- Use public Camera2 constrained high-speed sessions for qualifying 120/240 FPS modes, with the encoder surface configuration those sessions require.
- Select a supported camera/encoder pair instead of assuming a device model supports every advertised marketing mode.
- Bound UDP/TCP queues and retransmission history; request a keyframe or disconnect on overload instead of building an unbounded delay.
- Release partially configured codecs and surfaces; guard stale camera/control callbacks across stop and restart.
- Update target SDK to 36, use foreground consent, handle system insets/back navigation, and keep release output unsigned until proper release signing is supplied.

### iOS changes

- Fix retransmission history retaining incomplete packet data.
- Set capture frame duration to the requested FPS, check exposed formats, disable frame reordering, and use the hardware-encoder requirement where available.
- Drain encoding callbacks safely before teardown and bound malformed NAL parsing.
- Use the negotiated receiver destination, serialize control state, bound pending network bytes, and ignore callbacks from replaced sessions.
- Add Bonjour service declarations and local-network usage text; keep discovery, connections, and camera use tied to the app lifecycle.

### Developer and release tools

- Add bounded-memory stress, hostile-record handling, reverse-handshake, automatic negotiation, reconnect, PC-code, and IDR recovery regressions.
- Add a real HEVC fixture smoke test for the complete phone-initiated receiver path.
- Add a Windows high-FPS soak harness with mode/FPS, memory/handle, decode, and Softcam evidence gates.
- Add Windows Softcam concurrent lifecycle checks and native ASan/UBSan CI, plus iOS simulator CI.
- Pin the Softcam source revision and apply the PhoneCam timing/lifecycle patch reproducibly.
- Add a Windows release packager requiring runtime DLLs, valid release signatures, license notices, matching FFmpeg source/build material, and a SHA-256 manifest. Development packages can explicitly skip signature enforcement.
- Add `--dependency-info` and `--release-check`; reject detected GPL/nonfree FFmpeg builds for the intended release path.
- Document router arrangements, proprietary-distribution obligations, hardware acceptance criteria, and current platform limitations.

### Verified locally

- **57 Android tests** passed and the debug APK builds.
- **18 iOS simulator tests** passed; the unsigned device build succeeds.
- **5 native receiver checks** and **3 ASan/UBSan suites** passed.
- Phone-initiated TCP delivered **10 real HEVC frames with zero decode errors** in a deliberately paced connection smoke test.
- The receiver appeared in a live **Bonjour browse on macOS**.

### Integration status

This feature branch extends the Softcam-based `295ff13` checkout. Newer upstream `main` adds a Media Foundation pipeline and overlapping mobile/transport work. Those changes are preserved on `main`; this branch needs a separate integration review before merge.

### Still on the test bench

- Physical Windows DNS-SD/firewall behavior, D3D11VA/Softcam integration, and OBS/browser/calling-app compatibility.
- Sustained real-device 4K60 and 1080p120/240, including Samsung capability differences and consumer frame-rate limits.
- Measured camera-to-screen latency under real exposure, encoder, network-loss, and display conditions.
- Authenticated/encrypted transport, production signing, final store assets/privacy work, and the macOS CMIO virtual-camera extension.

The public camera APIs determine available Samsung modes; this update does not unlock modes hidden by device firmware. PC codes do not bypass guest isolation or NAT, and the lower configured buffer is not an end-to-end latency benchmark.
