# Teamwork Fix-Pass Prompt — Close the 4K60 verification gaps

The previous pass delivered real code (Android `stream4k` sender with NACK history + TCP fallback, iOS `PhoneCamSend` project, shared C++ core in `desktop/core` with NACK/jitter-buffer/control-parser and passing conformance tests). It did NOT deliver the end-to-end proof, and the verification report describes commands that do not exist in the built binaries. This pass closes those gaps. No git mutations; `legacy/`, `PhoneCamRetry-original-repo-old/`, `dist/` remain untouchable.

Working directory: ~/Documents/GitHub/PhoneCamRedux

## Confirmed defects to fix

### F1. macOS receiver cannot do 4K60 at all
`desktop/macos/src/main.mm` hardcodes `client_->start(1280, 720, 30)` — it always requests 720p30. It also has no real CLI (only `--rtsp` URL parsing), never prints the per-stage stats that `PhoneCamClient::Stats` already collects, and only runs as a GUI app.
Fix: proper CLI — `--connect <host>`, `--width/--height/--fps` (default 3840x2160@60), `--tcp`, `--headless` (no window; decode to null sink), `--duration <s>`, `--stats-interval 1` printing network fps, loss %, NACK recoveries, decode fps, and end-to-end frame age each second, plus a machine-readable summary line at exit (JSON) with exit code 1 if the run misses targets.

### F2. The synthetic 4K60 soak test was never run, and cannot run as documented
`docs/verification-4k60.md` §2 tells the user to run `phonecam-receiver --ip 127.0.0.1 --fps 60` — that flag doesn't exist, and plain ffmpeg cannot perform the control-channel handshake on port 47822 that `PhoneCamClient` requires, so the documented procedure is impossible.
Fix: build a `phonecam-soak-sender` test tool in `desktop/tests/` that implements the sender side of the control protocol (handshake, start, NACK retransmission from a history buffer, PLI handling) and streams a pre-encoded 3840x2160@60 HEVC file (generate once with ffmpeg/hevc_videotoolbox into the build dir; do not re-encode in realtime with libx265) over RTP/UDP, with an `--inject-loss <pct>` option. Add `scripts/soak_4k60.sh` that runs receiver (headless) + sender for >= 60 s twice — clean, and with 2% injected loss — and fails unless decode fps >= 55 and post-NACK loss < 1%.
Then RUN both soak runs on this Mac and replace §2 of `docs/verification-4k60.md` with the measured numbers, labeled with how they were measured. If the Mac cannot sustain 4K60 decode, record the measured ceiling honestly — never write a number that was not printed by the harness.

### F3. Windows target never migrated to the shared core
`desktop/windows/src/` still contains the old RTSP-only receiver with its own stale copy of `rtp_hevc.cpp/.h`, so Windows has none of the new UDP/NACK/control path. Migrate `desktop/windows` onto `desktop/core` with a D3D11VA decode backend and the same CLI as F1. It must configure via CMake on this Mac (compile-checked where possible); building/running on Windows is user-run — document exact commands.

Handling of the existing `windows/src/main.cpp` — extract, do not stub, do not rewrite from scratch:
- **Auto-discovery is shared infrastructure, not legacy.** Move `runDiscovery`, `parseDiscoveryPayload`, pair-code handling, and the discovery self-tests into `desktop/core/discovery.*` (it already has Win/POSIX socket `#ifdef`s). Fold the self-tests into CTest. Extend the beacon payload so the phone advertises supported protocols; `--auto-discover` then prefers 4K60-UDP and falls back to RTSP for old app builds.
- **Keep the FrameSink stack** (`FrameSink`/`NullSink`/`PreviewSink`/`SoftcamSink`/`CompositeSink`) as the shared output layer; the new UDP client decodes into these same sinks — that is how virtual-camera output is reused. Remove the Cocoa `#ifdef` variant of `PreviewSink` from the Windows target (macOS preview lives in `desktop/macos/src/main.mm`).
- **RTSP becomes a mode module.** Extract the ffmpeg RTSP ingest from `runReceiver` into `rtsp_ingest.cpp`; `main.cpp` becomes a thin dispatcher: default/`--connect <host>` → core UDP client, `--rtsp <url>` → legacy module, both feeding the same sinks. The RTSP path must remain genuinely working — a flag either works end-to-end or it does not exist. No "not implemented" stubs.
- Delete only the stale duplicate `windows/src/rtp_hevc.cpp/.h`.

### F4. Verification report contains fiction
Every command in `docs/verification-4k60.md` must be copy-pasteable against the actual built binaries (hardware scenarios A/B included — verify the Android app really exposes the described controls; `RtspMainActivity` has stream4k IP/port/toggle/stats views, confirm labels match the doc). Every performance figure must be measured output, labeled with its source. Anything not run stays clearly marked as user-run instructions.

## Acceptance
- [ ] `cd desktop && cmake -B build/macos -DPHONECAM_TARGET=macos && cmake --build build/macos && ctest --test-dir build/macos --output-on-failure` passes, now including a CTest entry that runs the loss-injection soak (short 10 s variant is fine for CTest; the full 60 s runs via the script).
- [ ] `scripts/soak_4k60.sh` executed on this Mac; measured stats pasted into `docs/verification-4k60.md`.
- [ ] Android `./gradlew :app:testDebugUnitTest :app:assembleDebug` and iOS simulator tests still pass.
- [ ] Windows CMake target uses `desktop/core` (no duplicated rtp_hevc sources) and documented user-run build steps exist.
