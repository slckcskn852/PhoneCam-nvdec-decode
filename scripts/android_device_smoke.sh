#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
APK="${APK:-$ROOT_DIR/android/app/build/outputs/apk/debug/app-debug.apk}"
PACKAGE="${PACKAGE:-com.phonecam}"
OUT_DIR="${OUT_DIR:-/private/tmp/phonecam-android-smoke-$(date +%Y%m%d-%H%M%S)}"

if [[ ! -x "$ADB" ]]; then
  echo "adb not found or not executable: $ADB" >&2
  exit 2
fi

if [[ ! -f "$APK" ]]; then
  echo "APK not found: $APK" >&2
  echo "Build it first with scripts/build_android_debug.sh." >&2
  exit 2
fi

serial="${ANDROID_SERIAL:-}"
if [[ -z "$serial" ]]; then
  serial="$("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
fi

if [[ -z "$serial" ]]; then
  echo "No attached Android device or running emulator found." >&2
  echo "Attach a phone or create/start an AVD, then rerun this script." >&2
  "$ADB" devices >&2 || true
  exit 2
fi

node_lines() {
  tr '<' '\n' < "$1"
}

node_by_text() {
  local xml_file="$1"
  local text="$2"
  node_lines "$xml_file" | grep -F "text=\"$text\"" | head -n 1 || true
}

node_by_resource_id() {
  local xml_file="$1"
  local resource_id="$2"
  node_lines "$xml_file" | grep -F "resource-id=\"$resource_id\"" | head -n 1 || true
}

node_center() {
  local node="$1"
  local bounds
  bounds="$(sed -E 's/.*bounds="\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]".*/\1 \2 \3 \4/' <<<"$node")"
  if [[ "$bounds" == "$node" ]]; then
    return 1
  fi
  awk '{ printf "%d %d\n", ($1 + $3) / 2, ($2 + $4) / 2 }' <<<"$bounds"
}

tap_text() {
  local xml_file="$1"
  local text="$2"
  local node
  local center
  node="$(node_by_text "$xml_file" "$text")"
  if [[ -z "$node" ]]; then
    return 1
  fi
  center="$(node_center "$node")"
  if [[ -z "$center" ]]; then
    return 1
  fi
  "$ADB" -s "$serial" shell input tap $center
}

tap_resource_id() {
  local xml_file="$1"
  local resource_id="$2"
  local node
  local center
  node="$(node_by_resource_id "$xml_file" "$resource_id")"
  if [[ -z "$node" ]]; then
    return 1
  fi
  center="$(node_center "$node")"
  if [[ -z "$center" ]]; then
    return 1
  fi
  "$ADB" -s "$serial" shell input tap $center
}

tap_rotate_control() {
  local xml_file="$1"
  tap_resource_id "$xml_file" "$PACKAGE:id/rotateStreamBtn" ||
    tap_text "$xml_file" "Rotate Right" ||
    tap_text "$xml_file" "Rotate Left" ||
    tap_text "$xml_file" "Rotate Back" ||
    tap_text "$xml_file" "Rotate Front" ||
    tap_text "$xml_file" "Rotate"
}

tap_diagnostics_control() {
  local xml_file="$1"
  tap_resource_id "$xml_file" "$PACKAGE:id/diagnosticsToggleBtn" || tap_text "$xml_file" "Info"
}

rotation_degrees_from_ui() {
  local xml_file="$1"
  [[ -f "$xml_file" ]] || return 0
  sed -nE 's/.*Output rotation: ([0-9]+) deg.*/\1/p' "$xml_file" | tail -n 1
}

has_pairing_code() {
  local xml_file="$1"
  local node
  node="$(node_by_resource_id "$xml_file" "$PACKAGE:id/pairingCodeText")"
  [[ "$node" =~ text=\"[0-9]{6}\" ]]
}

has_phonecam_crash_marker() {
  local log_file="$1"
  grep -Eq "FATAL EXCEPTION|AndroidRuntime.*com\.phonecam|com\.phonecam.*AndroidRuntime" "$log_file"
}

logs_match() {
  local pattern="$1"
  local log_file
  for log_file in "$OUT_DIR"/logcat*.txt; do
    [[ -f "$log_file" ]] || continue
    if grep -Eq "$pattern" "$log_file"; then
      return 0
    fi
  done
  return 1
}

mkdir -p "$OUT_DIR"

echo "Using Android target: $serial"
echo "Writing evidence to: $OUT_DIR"

"$ADB" -s "$serial" install -r "$APK" >"$OUT_DIR/install.txt"
"$ADB" -s "$serial" shell pm grant "$PACKAGE" android.permission.CAMERA >/dev/null 2>&1 || true
"$ADB" -s "$serial" logcat -c

"$ADB" -s "$serial" shell cmd package resolve-activity --brief "$PACKAGE" >"$OUT_DIR/resolve-activity.txt"
activity="$(tail -n 1 "$OUT_DIR/resolve-activity.txt" | tr -d '\r')"
if [[ -z "$activity" || "$activity" == "No activity found" ]]; then
  echo "Unable to resolve launch activity for $PACKAGE." >&2
  cat "$OUT_DIR/resolve-activity.txt" >&2
  exit 2
fi

"$ADB" -s "$serial" shell am start -n "$activity" >"$OUT_DIR/launch.txt"
sleep 3

"$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui.xml" || true
"$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot.png" || true
"$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat.txt"

start_tapped=0
switch_tapped=0
rotate_tapped=0
rotate_retry_tapped=0
rotation_before=""
rotation_after=""
if tap_text "$OUT_DIR/ui.xml" "Start Camera Server"; then
  start_tapped=1
  sleep 6
  "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-start-compact.xml" || true
  "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-start-compact.png" || true
  tap_diagnostics_control "$OUT_DIR/ui-after-start-compact.xml" || true
  sleep 1
  "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-start.xml" || true
  "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-start.png" || true
  "$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-start.txt"
  rotation_before="$(rotation_degrees_from_ui "$OUT_DIR/ui-after-start.xml")"

  if tap_rotate_control "$OUT_DIR/ui-after-start.xml"; then
    rotate_tapped=1
    sleep 2
    "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-rotate.xml" || true
    "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-rotate.png" || true
    "$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-rotate.txt"
    rotation_after="$(rotation_degrees_from_ui "$OUT_DIR/ui-after-rotate.xml")"

    if [[ -n "$rotation_before" && -n "$rotation_after" && "$rotation_before" == "$rotation_after" ]]; then
      if tap_rotate_control "$OUT_DIR/ui-after-rotate.xml"; then
        rotate_retry_tapped=1
        sleep 2
        "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-rotate-retry.xml" || true
        "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-rotate-retry.png" || true
        "$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-rotate-retry.txt"
        rotation_after="$(rotation_degrees_from_ui "$OUT_DIR/ui-after-rotate-retry.xml")"
      fi
    fi
  fi

  switch_xml="$OUT_DIR/ui-after-start.xml"
  if [[ "$rotate_tapped" -eq 1 && -f "$OUT_DIR/ui-after-rotate.xml" ]]; then
    switch_xml="$OUT_DIR/ui-after-rotate.xml"
  fi
  if [[ "$rotate_retry_tapped" -eq 1 && -f "$OUT_DIR/ui-after-rotate-retry.xml" ]]; then
    switch_xml="$OUT_DIR/ui-after-rotate-retry.xml"
  fi

  if tap_text "$switch_xml" "Switch"; then
    switch_tapped=1
    sleep 4
    "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-switch.xml" || true
    "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-switch.png" || true
    if ! grep -q "Camera: Front" "$OUT_DIR/ui-after-switch.xml"; then
      if tap_text "$OUT_DIR/ui-after-switch.xml" "Switch"; then
        sleep 4
        "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-switch.xml" || true
        "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-switch.png" || true
      fi
    fi
    "$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-switch.txt"
  fi
fi

"$ADB" -s "$serial" shell am force-stop "$PACKAGE" >"$OUT_DIR/force-stop.txt" 2>&1 || true

{
  echo "Android target: $serial"
  echo "APK: $APK"
  echo "Activity: $activity"
  echo
  if grep -q "Start Camera Server" "$OUT_DIR/ui.xml"; then
    echo "PASS: Start Camera Server visible"
  else
    echo "WARN: Start Camera Server not found in UI tree"
  fi
  if grep -q "Efficient" "$OUT_DIR/ui.xml" && grep -q "Balanced" "$OUT_DIR/ui.xml" && grep -q "Motion" "$OUT_DIR/ui.xml"; then
    echo "PASS: Efficient/Balanced/Motion controls visible"
  else
    echo "WARN: profile controls not all found in UI tree"
  fi
  if grep -q "Pairing Code" "$OUT_DIR/ui.xml" && has_pairing_code "$OUT_DIR/ui.xml"; then
    echo "PASS: six-digit pairing code visible"
  else
    echo "WARN: six-digit pairing code not found in UI tree"
  fi
  if [[ "$start_tapped" -eq 1 ]] && [[ -f "$OUT_DIR/ui-after-start.xml" ]] && grep -q "Discovery beacon active" "$OUT_DIR/ui-after-start.xml"; then
    echo "PASS: Start Camera Server reached streaming screen"
  elif [[ "$start_tapped" -eq 1 ]]; then
    echo "WARN: Start Camera Server tapped, but streaming status was not found"
  else
    echo "WARN: Start Camera Server could not be tapped"
  fi
  if [[ "$start_tapped" -eq 1 ]] && [[ -f "$OUT_DIR/ui-after-start.xml" ]] && grep -q "Output rotation:" "$OUT_DIR/ui-after-start.xml"; then
    echo "PASS: output rotation status visible"
  else
    echo "WARN: output rotation status not found"
  fi
  if [[ "$start_tapped" -eq 1 ]] && [[ -f "$OUT_DIR/ui-after-start.xml" ]] && grep -q "Preview: live" "$OUT_DIR/ui-after-start.xml"; then
    echo "PASS: SurfaceView preview reported live"
  elif [[ "$start_tapped" -eq 1 ]] && [[ -f "$OUT_DIR/ui-after-start.xml" ]] && grep -q "Preview:" "$OUT_DIR/ui-after-start.xml"; then
    echo "WARN: SurfaceView preview status was visible but did not report live"
  else
    echo "WARN: SurfaceView preview status not found"
  fi
  if [[ "$rotate_tapped" -eq 1 && -n "$rotation_before" && -n "$rotation_after" && "$rotation_before" != "$rotation_after" && "$rotate_retry_tapped" -eq 1 ]]; then
    echo "PASS: Rotate changes output rotation from $rotation_before to $rotation_after degrees after one retry"
  elif [[ "$rotate_tapped" -eq 1 && -n "$rotation_before" && -n "$rotation_after" && "$rotation_before" != "$rotation_after" ]]; then
    echo "PASS: Rotate changes output rotation from $rotation_before to $rotation_after degrees"
  elif [[ "$rotate_tapped" -eq 1 ]]; then
    echo "WARN: Rotate tapped, but output rotation change was not observed"
  else
    echo "WARN: Rotate button could not be tapped"
  fi
  if [[ "$switch_tapped" -eq 1 ]] && [[ -f "$OUT_DIR/ui-after-switch.xml" ]] && grep -q "Camera: Front" "$OUT_DIR/ui-after-switch.xml"; then
    echo "PASS: Switch changes status to front camera"
  elif [[ "$switch_tapped" -eq 1 ]]; then
    echo "WARN: Switch tapped, but front camera status was not found"
  else
    echo "WARN: Switch button could not be tapped"
  fi
  if logs_match "FATAL EXCEPTION|AndroidRuntime.*com\.phonecam|com\.phonecam.*AndroidRuntime"; then
    echo "WARN: PhoneCam crash marker appears in logcat"
  else
    echo "PASS: no PhoneCam crash marker in logcat"
  fi
  if logs_match "AudioEncoder not prepared|Video configuration failed|Video-only audio stub failed|Camera switch failed"; then
    echo "WARN: stream configuration failure marker appears in logcat"
  else
    echo "PASS: no stream configuration failure marker in logcat"
  fi
} | tee "$OUT_DIR/summary.txt"

smoke_status=0
if ! grep -q "Start Camera Server" "$OUT_DIR/ui.xml"; then
  echo "Android device smoke failed: Start Camera Server was not visible. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if ! grep -q "Efficient" "$OUT_DIR/ui.xml" ||
   ! grep -q "Balanced" "$OUT_DIR/ui.xml" ||
   ! grep -q "Motion" "$OUT_DIR/ui.xml"; then
  echo "Android device smoke failed: profile controls were not all visible. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if ! grep -q "Pairing Code" "$OUT_DIR/ui.xml" || ! has_pairing_code "$OUT_DIR/ui.xml"; then
  echo "Android device smoke failed: six-digit pairing code was not visible. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if [[ "$start_tapped" -ne 1 ]] ||
   [[ ! -f "$OUT_DIR/ui-after-start.xml" ]] ||
   ! grep -q "Discovery beacon active" "$OUT_DIR/ui-after-start.xml"; then
  echo "Android device smoke failed: Start Camera Server did not reach the streaming screen. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if [[ "$start_tapped" -ne 1 ]] ||
   [[ ! -f "$OUT_DIR/ui-after-start.xml" ]] ||
   ! grep -q "Output rotation:" "$OUT_DIR/ui-after-start.xml"; then
  echo "Android device smoke failed: output rotation status was not visible. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if [[ "$start_tapped" -ne 1 ]] ||
   [[ ! -f "$OUT_DIR/ui-after-start.xml" ]] ||
   ! grep -q "Preview: live" "$OUT_DIR/ui-after-start.xml"; then
  echo "Android device smoke failed: SurfaceView preview did not report live. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if [[ "$rotate_tapped" -ne 1 ||
      -z "$rotation_before" ||
      -z "$rotation_after" ||
      "$rotation_before" == "$rotation_after" ]]; then
  echo "Android device smoke failed: Rotate did not change output rotation. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if [[ "$switch_tapped" -ne 1 ]] ||
   [[ ! -f "$OUT_DIR/ui-after-switch.xml" ]] ||
   ! grep -q "Camera: Front" "$OUT_DIR/ui-after-switch.xml"; then
  echo "Android device smoke failed: Switch did not reach front camera status. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if logs_match "FATAL EXCEPTION|AndroidRuntime.*com\.phonecam|com\.phonecam.*AndroidRuntime"; then
  echo "Android device smoke failed: PhoneCam crash marker appears in logcat. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi
if logs_match "AudioEncoder not prepared|Video configuration failed|Video-only audio stub failed|Camera switch failed"; then
  echo "Android device smoke failed: stream configuration failure marker appears in logcat. Evidence: $OUT_DIR" >&2
  smoke_status=2
fi

echo "Smoke evidence: $OUT_DIR"
exit "$smoke_status"
