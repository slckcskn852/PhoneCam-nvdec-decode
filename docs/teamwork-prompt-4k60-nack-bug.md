# Teamwork Bug-Fix Prompt — Lossy-channel collapse after ~30 s + gamed soak duration

The previous pass reported the F2 soak as PASSED (55.6 fps, 0.00% post-NACK loss). That result came from a `--duration 10` run. An independent full-length run of `scripts/soak_4k60.sh` (default 60 s) on this Mac produced:

- Clean channel, 60 s: PASS — 59.4 avg decode fps, 0.00% loss. The 4K60 decode path is genuinely good.
- 2% injected loss, 60 s: **FAIL** — avg decode fps 19.6, post-NACK loss 1.30%, receiver exit code 1.

Per-second stats from `desktop/build/macos/receiver_soak_loss_2.0.log` show the shape: the stream is healthy for ~30 s (58–62 fps, loss ~0.01%), then collapses hard (net fps ~25, decode fps 0–2, loss climbing monotonically) and never recovers. This is a state-accumulation / wraparound bug, not a throughput limit. No git mutations; `legacy/`, `PhoneCamRetry-original-repo-old/`, `dist/` untouchable.

## F5. Diagnose and fix the collapse in the loss-recovery path

Leads to investigate (verify, don't assume):
1. **RTP sequence wraparound.** At ~3,260 packets/s the 16-bit sequence wraps every ~20 s; the collapse onset (~30–40 s) is consistent with a mishandled wrap in the extended-sequence / gap-detection logic in `desktop/core/rtp_hevc.cpp` (`ext > nextReleaseSeq_` path) or in the sender's retransmission history lookup. Add a unit test that streams >  2×65536 synthetic packets with loss across multiple wraps.
2. **NACK storm / unbounded re-request growth.** The NACK counter grows ~3.3k/s even while healthy and ~20k/s during collapse (175k+ by t=50 s). With 2% loss, permanently-lost sequences below the stall point may be re-NACKed every 15 ms forever, flooding the sender and choking the receive loop. Give up on a sequence after a bounded number of retries / age, advance `nextReleaseSeq_` past it, and rely on the PLI keyframe-request path to resync.
3. **The `nack_recoveries` stat is meaningless.** `phonecam_client.cpp` computes `packetsReceived - framesEmitted`, which reports ~191k "recoveries" on a ZERO-loss run. Count actual recoveries: packets that arrived via retransmission after being NACKed. Fix the stat and the fields derived from it.

## Acceptance — no shortcuts this time
- [ ] `bash scripts/soak_4k60.sh` (default 60 s duration, unmodified) passes BOTH runs. Reported numbers in `docs/verification-4k60.md` must come from a full-length run; state the duration next to every figure. A 10 s run does not satisfy a ≥ 60 s criterion.
- [ ] New CTest covering multi-wrap sequence handling under loss passes.
- [ ] Rewrite the Measured Loopback Performance section of `docs/verification-4k60.md` with the new full-length results; remove the invalid 10 s figures and the bogus nack_recoveries values.
- [ ] Android/iOS/desktop builds and existing tests still pass (touching core NACK logic affects the Android sender's history buffer semantics too — if the retry/give-up policy changes the protocol, update `docs/protocol-4k60.md` and both sender implementations in the same pass).
