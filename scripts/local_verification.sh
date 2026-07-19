#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-/private/tmp/phonecam-local-verification-$STAMP}"
RECEIVER_BUILD_DIR="${RECEIVER_BUILD_DIR:-/private/tmp/phonecam-windows-receiver-build}"
RUN_ANDROID_BUILD="${RUN_ANDROID_BUILD:-1}"
RUN_RTSP_FIXTURE="${RUN_RTSP_FIXTURE:-0}"
RUN_MAC_APP_PACKAGE="${RUN_MAC_APP_PACKAGE:-1}"
RUN_POWERSHELL_SYNTAX="${RUN_POWERSHELL_SYNTAX:-auto}"
MEDIAMTX_BIN="${MEDIAMTX_BIN:-/private/tmp/phonecam-mediamtx/mediamtx}"
RECEIVER_BIN="${RECEIVER_BIN:-$RECEIVER_BUILD_DIR/phonecam-receiver}"

mkdir -p "$OUTPUT_DIR"
SUMMARY="$OUTPUT_DIR/summary.txt"
: > "$SUMMARY"

log() {
  printf '%s\n' "$*" | tee -a "$SUMMARY"
}

safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

run_step() {
  local name="$1"
  shift
  local log_name
  log_name="$(safe_name "$name").log"
  local log_path="$OUTPUT_DIR/$log_name"

  log ""
  log "== $name =="
  log "$*"
  if "$@" >"$log_path" 2>&1; then
    log "PASS: $name"
    log "Log: $log_path"
  else
    local status=$?
    log "FAIL: $name (exit $status)"
    log "Log: $log_path"
    tail -n 80 "$log_path" | tee -a "$SUMMARY" >&2 || true
    exit "$status"
  fi
}

skip_step() {
  log ""
  log "SKIP: $1"
}

cd "$ROOT_DIR"

log "PhoneCamRedux local verification"
log "Generated: $(date -Iseconds)"
log "Output: $OUTPUT_DIR"
log "Host: $(uname -a)"
log ""
log "This local verification intentionally does not run adb, physical Android Wi-Fi evidence, Windows DirectShow registration, or OBS/browser camera enumeration."

run_step "Workflow YAML parse" ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build.yml"); puts "workflow yaml ok"'
run_step "Shell syntax check" bash -n \
  scripts/build_android_debug.sh \
  scripts/smoke_receiver_fixture.sh \
  scripts/mac_receiver_dev_smoke.sh \
  scripts/mac_receiver_fixture_smoke.sh \
  scripts/package_mac_receiver_app.sh \
  scripts/android_device_smoke.sh \
  scripts/android_rtsp_receiver_smoke.sh \
  scripts/android_wifi_receiver_smoke.sh \
  scripts/android_wifi_profile_matrix_smoke.sh \
  scripts/local_verification.sh
run_step "Android rotation plan self-test" env ROTATION_PLAN_SELF_TEST=1 scripts/android_wifi_receiver_smoke.sh
if command -v pwsh >/dev/null 2>&1; then
  run_step "PowerShell syntax check" pwsh -NoProfile -Command \
    '$scripts = Get-ChildItem -Path desktop/windows/scripts -Filter *.ps1; foreach ($script in $scripts) { $tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -gt 0) { foreach ($errorItem in $errors) { Write-Error "$($script.FullName): $($errorItem.Message)" }; throw "PowerShell syntax check failed for $($script.FullName)" } }; "PowerShell syntax ok"'
elif [[ "$RUN_POWERSHELL_SYNTAX" == "1" ]]; then
  log ""
  log "FAIL: PowerShell syntax check requested with RUN_POWERSHELL_SYNTAX=1, but pwsh is not installed."
  exit 2
else
  skip_step "PowerShell syntax check unavailable: pwsh not found"
fi

if [[ "$RUN_ANDROID_BUILD" == "1" ]]; then
  run_step "Android debug build and fresh JVM tests" env FORCE_ANDROID_TESTS=1 scripts/build_android_debug.sh
else
  skip_step "Android debug build and fresh JVM tests disabled with RUN_ANDROID_BUILD=0"
fi

if [[ -f "$RECEIVER_BUILD_DIR/CMakeCache.txt" ]]; then
  run_step "Receiver build" cmake --build "$RECEIVER_BUILD_DIR" --config Release
  run_step "Receiver CTest" ctest --test-dir "$RECEIVER_BUILD_DIR" -C Release --output-on-failure
else
  skip_step "Receiver build directory missing: $RECEIVER_BUILD_DIR"
fi

if [[ "$(uname -s)" == "Darwin" && "$RUN_MAC_APP_PACKAGE" == "1" && -x "$RECEIVER_BIN" ]]; then
  run_step "macOS dev app package" env RECEIVER_BIN="$RECEIVER_BIN" OUTPUT_DIR="$OUTPUT_DIR/mac-app" scripts/package_mac_receiver_app.sh
  run_step "macOS dev app bundle sanity" test -x "$OUTPUT_DIR/mac-app/PhoneCam Receiver.app/Contents/MacOS/phonecam-receiver"
else
  skip_step "macOS dev app package unavailable or disabled"
fi

if [[ "$RUN_RTSP_FIXTURE" == "1" ]]; then
  if [[ -x "$MEDIAMTX_BIN" && -x "$RECEIVER_BIN" ]]; then
    run_step "Synthetic RTSP receiver fixture" env MEDIAMTX_BIN="$MEDIAMTX_BIN" RECEIVER_BIN="$RECEIVER_BIN" scripts/smoke_receiver_fixture.sh
  else
    skip_step "Synthetic RTSP fixture requested but MEDIAMTX_BIN or RECEIVER_BIN is missing"
  fi
else
  skip_step "Synthetic RTSP fixture disabled by default; set RUN_RTSP_FIXTURE=1 to run it"
fi

run_step "Git diff whitespace check" git diff --check

log ""
log "Local verification passed."
log "Summary: $SUMMARY"
log "Remaining external evidence: fresh physical Android orientation matrix, real Windows DirectShow registration/capture, and OBS/browser enumeration."
