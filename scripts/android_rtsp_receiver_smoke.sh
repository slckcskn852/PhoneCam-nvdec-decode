#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
APK="${APK:-$ROOT_DIR/android/app/build/outputs/apk/debug/app-debug.apk}"
PACKAGE="${PACKAGE:-com.phonecam}"
RECEIVER_BIN="${RECEIVER_BIN:-/private/tmp/phonecam-windows-receiver-build/phonecam-receiver}"
OUT_DIR="${OUT_DIR:-/private/tmp/phonecam-android-rtsp-receiver-$(date +%Y%m%d-%H%M%S)}"
HOST_RTSP_PORT="${HOST_RTSP_PORT:-8556}"
DEVICE_RTSP_PORT="${DEVICE_RTSP_PORT:-8554}"
FRAMES="${FRAMES:-30}"

if [[ ! -x "$ADB" ]]; then
  echo "adb not found or not executable: $ADB" >&2
  exit 2
fi

if [[ ! -f "$APK" ]]; then
  echo "APK not found: $APK" >&2
  echo "Build it first with scripts/build_android_debug.sh." >&2
  exit 2
fi

if [[ ! -x "$RECEIVER_BIN" ]]; then
  echo "Receiver binary not found or not executable: $RECEIVER_BIN" >&2
  echo "Set RECEIVER_BIN or build desktop/windows first." >&2
  exit 2
fi

serial="${ANDROID_SERIAL:-}"
if [[ -z "$serial" ]]; then
  serial="$("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
fi

if [[ -z "$serial" ]]; then
  echo "No attached Android device or running emulator found." >&2
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

cleanup() {
  "$ADB" -s "$serial" forward --remove "tcp:$HOST_RTSP_PORT" >/dev/null 2>&1 || true
  "$ADB" -s "$serial" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"

echo "Using Android target: $serial"
echo "Writing evidence to: $OUT_DIR"

"$ADB" -s "$serial" install -r "$APK" >"$OUT_DIR/install.txt"
"$ADB" -s "$serial" shell pm grant "$PACKAGE" android.permission.CAMERA >/dev/null 2>&1 || true
"$ADB" -s "$serial" logcat -c
"$ADB" -s "$serial" forward --remove "tcp:$HOST_RTSP_PORT" >/dev/null 2>&1 || true
"$ADB" -s "$serial" forward "tcp:$HOST_RTSP_PORT" "tcp:$DEVICE_RTSP_PORT" >"$OUT_DIR/adb-forward.txt"

"$ADB" -s "$serial" shell cmd package resolve-activity --brief "$PACKAGE" >"$OUT_DIR/resolve-activity.txt"
activity="$(tail -n 1 "$OUT_DIR/resolve-activity.txt" | tr -d '\r')"
if [[ -z "$activity" || "$activity" == "No activity found" ]]; then
  echo "Unable to resolve launch activity for $PACKAGE." >&2
  cat "$OUT_DIR/resolve-activity.txt" >&2
  exit 2
fi

"$ADB" -s "$serial" shell am start -n "$activity" --ez phonecam_advanced true >"$OUT_DIR/launch.txt"
sleep 3
"$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui.xml" || true
"$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot.png" || true

if ! tap_text "$OUT_DIR/ui.xml" "Start Camera Server"; then
  echo "Start Camera Server could not be tapped." >&2
  exit 2
fi

sleep 7
"$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-start.xml" || true
"$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-start.png" || true
"$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-start.txt"

rtsp_url="rtsp://127.0.0.1:$HOST_RTSP_PORT/"
receiver_status=0
"$RECEIVER_BIN" --rtsp "$rtsp_url" --frames "$FRAMES" --no-preview --no-softcam >"$OUT_DIR/receiver.stdout.log" 2>"$OUT_DIR/receiver.stderr.log" || receiver_status=$?
"$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-receiver.txt"

{
  echo "Android target: $serial"
  echo "APK: $APK"
  echo "Activity: $activity"
  echo "Receiver: $RECEIVER_BIN"
  echo "Forwarded RTSP URL: $rtsp_url"
  echo
  if grep -q "Discovery beacon active" "$OUT_DIR/ui-after-start.xml"; then
    echo "PASS: Android RTSP server reached streaming screen"
  else
    echo "WARN: Android streaming status not found"
  fi
  if [[ "$receiver_status" -eq 0 ]] && grep -q "Receiver summary: $FRAMES frames" "$OUT_DIR/receiver.stdout.log"; then
    echo "PASS: receiver decoded $FRAMES frames from Android RTSP stream"
  else
    echo "WARN: receiver failed or decoded an unexpected frame count"
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

if [[ "$receiver_status" -ne 0 ]]; then
  echo "Receiver failed with exit code $receiver_status. Logs: $OUT_DIR" >&2
  exit "$receiver_status"
fi

echo "Android RTSP receiver smoke evidence: $OUT_DIR"
