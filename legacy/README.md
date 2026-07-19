# Legacy quarantine

Everything in this directory is **retired reference material**, not part of the
production path. It was moved here when the project pivoted to the 4K60 HEVC
UDP streaming core (see `docs/architecture.md`).

- `desktop-receiver-python/` — old Python prototype receivers (raw TCP H.264,
  WebRTC/aiortc, pyvirtualcam output). Protocols no longer served by the
  Android app. Retained for reference only; `pyvirtualcam` is GPLv2.
- `UnityCapture-master/` — vendored UnityCapture virtual webcam driver used by
  the Python prototype. The current Windows path uses tshino/softcam instead
  (see `desktop/windows/SOFTCAM_BRANDING.md`).
- `scripts-verification-empire/` — retired evidence-gate tooling
  (`validate_mvp_evidence.rb`, `bundle_mvp_evidence.rb`,
  `check_windows_static_contracts.rb`, and the PowerShell evidence
  collectors). These gated a 720p MVP evidence bundle and are no longer run.
- `docs/verification-report.md` — archived evidence report for the retired
  720p MVP.

Nothing here is built, shipped, or maintained. Do not add new references to
these paths from production code, CI, or docs.
