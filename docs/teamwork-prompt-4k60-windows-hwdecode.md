# Teamwork Prompt — Windows 4K60 hardware decode + port the Windows-session patches

Real-hardware verification (Samsung Z Fold 5, Android 14 → Windows 11 x64, WiFi 6, sender 192.168.1.220 / receiver 192.168.1.125) proved the system works end-to-end — stream, control channel, and the branded softcam virtual camera all functioned — but exposed two defects:

1. The Windows launcher (`desktop/windows/src/main.cpp`) hardcoded `client.start(1280, 720, ...)` and defaulted `--fps` to 30 — the same hardcode class already fixed once on macOS. It was patched during the Windows test session (added `--width`/`--height` flags; made `applyDiscoveredDevice` adopt the beacon-advertised resolution/fps).
2. With the patch, real 4K60 decode averaged **18.94 fps** — the Windows receiver uses software HEVC decode plus `sws_scale` YUV→BGR on the CPU. The D3D11VA backend previously claimed as delivered was never implemented.

IMPORTANT: the session patches and the new verification §4 exist only in the Windows PC's checkout. If they have not been pushed to the repo yet, treat re-applying them (identical semantics) as part of this pass — check `git log`/diff first, do not assume.

No git history rewrites; `legacy/`, `PhoneCamRetry-original-repo-old/`, `dist/` untouchable.

## F6. Windows hardware decode pipeline

- Decode: FFmpeg D3D11VA hwaccel (`av_hwdevice_ctx_create(AV_HWDEVICE_TYPE_D3D11VA)`), decoder outputs `AV_PIX_FMT_D3D11` textures. NVDEC may be added as an optional path, D3D11VA is the requirement (vendor-neutral). Software decode remains as an explicit fallback with a loud log warning, never a silent default.
- Color conversion on GPU: use the D3D11 VideoProcessor (or a trivial compute/pixel shader) for NV12→BGRA. `sws_scale` at 4K60 is the proven bottleneck — it must be off the hot path.
- Preview: render the converted texture straight to a swapchain — zero CPU readback.
- Softcam sink: the DirectShow filter needs CPU-side BGR frames, so a staging-texture readback is unavoidable there. Measure its cost at 4K60; if the readback+push can't hold 55+ fps, add a `--softcam-scale` option (GPU-downscale to 1080p for the virtual camera while preview stays 4K) and record measured numbers for both configurations. No silent quality reduction.
- CLI cleanup: the Windows launcher currently reuses `--rtsp <url>` to feed the new UDP client — rename the primary flag to `--connect <host>` (matching macOS), keep `--rtsp` for the genuine legacy RTSP mode only.

## Acceptance — measured on real hardware or explicitly user-run

- [ ] Windows CMake target builds with D3D11VA (configure-checked on macOS; compile/run steps documented for the Windows PC).
- [ ] Synthetic soak on the Windows PC (phonecam-soak-sender loopback, 60 s, clean + 2% loss) using hardware decode: >= 55 fps decode. Provide the exact commands; results recorded only when actually run.
- [ ] Real-device retest procedure for the Z Fold 5 over WiFi: expect >= 55 fps at 4K60 with hardware decode; record measured decode fps, network Mbps, loss %, NACK recoveries, and any ABR ladder steps in `docs/verification-4k60.md` §4 (append, do not overwrite the software-decode baseline — it is the comparison point).
- [ ] The Windows-session patches (`--width`/`--height`, discovery-driven resolution/fps) are present in the repo (ported or verified already pushed).
- [ ] macOS build, CTest, soak, Android and iOS tests still pass (no regressions from shared-core changes).
- [ ] Every number in documentation is measured and labeled with its source machine and method. Numbers that were not measured do not appear.
