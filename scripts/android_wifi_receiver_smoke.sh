#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
APK="${APK:-$ROOT_DIR/android/app/build/outputs/apk/debug/app-debug.apk}"
PACKAGE="${PACKAGE:-com.phonecam}"
RECEIVER_BIN="${RECEIVER_BIN:-/private/tmp/phonecam-windows-receiver-build/phonecam-receiver}"
OUT_DIR="${OUT_DIR:-/private/tmp/phonecam-android-wifi-receiver-$(date +%Y%m%d-%H%M%S)}"
FRAMES="${FRAMES:-60}"
DISCOVER_SECONDS="${DISCOVER_SECONDS:-8}"
REQUIRE_DISCOVERY="${REQUIRE_DISCOVERY:-0}"
ALLOW_EMULATOR="${ALLOW_EMULATOR:-0}"
KEEP_PHONECAM_RUNNING="${KEEP_PHONECAM_RUNNING:-0}"
VERIFY_FRONT_CAMERA="${VERIFY_FRONT_CAMERA:-1}"
PROFILE_LABEL="${PROFILE_LABEL:-Efficient}"
STREAM_ROTATE_TAPS="${STREAM_ROTATE_TAPS:-0}"
FRONT_CAMERA_ROTATE_TAPS="${FRONT_CAMERA_ROTATE_TAPS:-0}"
STREAM_OUTPUT_ROTATION_DEGREES="${STREAM_OUTPUT_ROTATION_DEGREES:-}"
FRONT_CAMERA_OUTPUT_ROTATION_DEGREES="${FRONT_CAMERA_OUTPUT_ROTATION_DEGREES:-}"
ORIENTATION_CALIBRATION="${ORIENTATION_CALIBRATION:-0}"
CALIBRATION_FRAMES="${CALIBRATION_FRAMES:-20}"
ROTATION_PLAN_SELF_TEST="${ROTATION_PLAN_SELF_TEST:-0}"
ALLOW_UNVERIFIED_ORIENTATION="${ALLOW_UNVERIFIED_ORIENTATION:-0}"
STREAM_ORIENTATION_STATUS="${STREAM_ORIENTATION_STATUS:-not-verified}"
STREAM_ORIENTATION_NOTES="${STREAM_ORIENTATION_NOTES:-}"
STREAM_DEVICE_POSTURE="${STREAM_DEVICE_POSTURE:-}"
FRONT_CAMERA_ORIENTATION_STATUS="${FRONT_CAMERA_ORIENTATION_STATUS:-not-verified}"
FRONT_CAMERA_ORIENTATION_NOTES="${FRONT_CAMERA_ORIENTATION_NOTES:-}"
FRONT_CAMERA_DEVICE_POSTURE="${FRONT_CAMERA_DEVICE_POSTURE:-}"
ORIENTATION_EVIDENCE_VERSION=4
ROTATION_CONTROL_MODE="per-camera-output"
ORIENTATION_LOCK_MODE="fixed-landscape"
stream_rotate_taps_applied="$STREAM_ROTATE_TAPS"
front_camera_rotate_taps_applied="$FRONT_CAMERA_ROTATE_TAPS"
stream_rotation_request_mode="tap-count"
front_rotation_request_mode="tap-count"
stream_rotation_direction_applied="right"
front_camera_rotation_direction_applied="right"

if [[ ! "$STREAM_ROTATE_TAPS" =~ ^[0-3]$ ]]; then
  echo "STREAM_ROTATE_TAPS must be 0, 1, 2, or 3." >&2
  exit 2
fi

if [[ ! "$FRONT_CAMERA_ROTATE_TAPS" =~ ^[0-3]$ ]]; then
  echo "FRONT_CAMERA_ROTATE_TAPS must be 0, 1, 2, or 3." >&2
  exit 2
fi

if [[ -n "$STREAM_OUTPUT_ROTATION_DEGREES" && ! "$STREAM_OUTPUT_ROTATION_DEGREES" =~ ^(0|90|180|270)$ ]]; then
  echo "STREAM_OUTPUT_ROTATION_DEGREES must be 0, 90, 180, or 270." >&2
  exit 2
fi

if [[ -n "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES" && ! "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES" =~ ^(0|90|180|270)$ ]]; then
  echo "FRONT_CAMERA_OUTPUT_ROTATION_DEGREES must be 0, 90, 180, or 270." >&2
  exit 2
fi

if [[ -n "$STREAM_OUTPUT_ROTATION_DEGREES" && "$STREAM_ROTATE_TAPS" != "0" ]]; then
  echo "Use STREAM_OUTPUT_ROTATION_DEGREES or STREAM_ROTATE_TAPS, not both." >&2
  exit 2
fi

if [[ -n "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES" && "$FRONT_CAMERA_ROTATE_TAPS" != "0" ]]; then
  echo "Use FRONT_CAMERA_OUTPUT_ROTATION_DEGREES or FRONT_CAMERA_ROTATE_TAPS, not both." >&2
  exit 2
fi

if [[ "$ORIENTATION_CALIBRATION" != "0" && "$ORIENTATION_CALIBRATION" != "1" ]]; then
  echo "ORIENTATION_CALIBRATION must be 0 or 1." >&2
  exit 2
fi

if [[ "$ROTATION_PLAN_SELF_TEST" != "0" && "$ROTATION_PLAN_SELF_TEST" != "1" ]]; then
  echo "ROTATION_PLAN_SELF_TEST must be 0 or 1." >&2
  exit 2
fi

if [[ ! "$CALIBRATION_FRAMES" =~ ^[1-9][0-9]*$ ]]; then
  echo "CALIBRATION_FRAMES must be a positive integer." >&2
  exit 2
fi

if [[ "$ALLOW_UNVERIFIED_ORIENTATION" != "0" && "$ALLOW_UNVERIFIED_ORIENTATION" != "1" ]]; then
  echo "ALLOW_UNVERIFIED_ORIENTATION must be 0 or 1." >&2
  exit 2
fi

STREAM_ORIENTATION_STATUS="$(tr '[:upper:]' '[:lower:]' <<<"$STREAM_ORIENTATION_STATUS")"
case "$STREAM_ORIENTATION_STATUS" in
  passed|failed|not-verified) ;;
  *)
    echo "STREAM_ORIENTATION_STATUS must be passed, failed, or not-verified." >&2
    exit 2
    ;;
esac

FRONT_CAMERA_ORIENTATION_STATUS="$(tr '[:upper:]' '[:lower:]' <<<"$FRONT_CAMERA_ORIENTATION_STATUS")"
case "$FRONT_CAMERA_ORIENTATION_STATUS" in
  passed|failed|not-verified) ;;
  *)
    echo "FRONT_CAMERA_ORIENTATION_STATUS must be passed, failed, or not-verified." >&2
    exit 2
    ;;
esac

if [[ "$ALLOW_UNVERIFIED_ORIENTATION" != "1" && "$ORIENTATION_CALIBRATION" != "1" && "$ROTATION_PLAN_SELF_TEST" != "1" ]]; then
  missing_orientation_inputs=()
  if [[ "$STREAM_ORIENTATION_STATUS" != "passed" ]]; then
    missing_orientation_inputs+=("STREAM_ORIENTATION_STATUS=passed")
  fi
  if [[ -z "$STREAM_ORIENTATION_NOTES" ]]; then
    missing_orientation_inputs+=("STREAM_ORIENTATION_NOTES")
  fi
  if [[ -z "$STREAM_DEVICE_POSTURE" ]]; then
    missing_orientation_inputs+=("STREAM_DEVICE_POSTURE")
  fi
  if [[ "$VERIFY_FRONT_CAMERA" == "1" ]]; then
    if [[ "$FRONT_CAMERA_ORIENTATION_STATUS" != "passed" ]]; then
      missing_orientation_inputs+=("FRONT_CAMERA_ORIENTATION_STATUS=passed")
    fi
    if [[ -z "$FRONT_CAMERA_ORIENTATION_NOTES" ]]; then
      missing_orientation_inputs+=("FRONT_CAMERA_ORIENTATION_NOTES")
    fi
    if [[ -z "$FRONT_CAMERA_DEVICE_POSTURE" ]]; then
      missing_orientation_inputs+=("FRONT_CAMERA_DEVICE_POSTURE")
    fi
  fi

  if [[ "${#missing_orientation_inputs[@]}" -gt 0 ]]; then
    echo "Physical orientation acceptance inputs are required before running the final Android Wi-Fi smoke." >&2
    printf 'Missing: %s\n' "${missing_orientation_inputs[*]}" >&2
    echo "Inspect the physical receiver output first, then set the status fields to passed only when the stream is landscape-correct." >&2
    echo "For exploratory collection only, set ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1; that evidence will not satisfy final MVP validation." >&2
    exit 2
  fi
fi

run_rotation_plan_self_test() {
  local failures=0
  local current
  local target
  local expected
  local actual
  local clockwise_taps

  while read -r current target expected; do
    [[ -n "$current" ]] || continue

    if [[ ! "$current" =~ ^(0|90|180|270)$ || ! "$target" =~ ^(0|90|180|270)$ ]]; then
      actual="<error>"
    else
      clockwise_taps=$(( ((target - current + 360) % 360) / 90 ))
      if [[ "$clockwise_taps" -le 2 ]]; then
        actual="right $clockwise_taps"
      else
        actual="left $((4 - clockwise_taps))"
      fi
    fi

    if [[ "$actual" != "$expected" ]]; then
      echo "FAIL: rotation plan $current->$target expected '$expected' but got '$actual'" >&2
      failures=$((failures + 1))
    fi
  done <<'CASES'
0 0 right 0
0 90 right 1
0 180 right 2
0 270 left 1
90 0 left 1
90 270 right 2
180 90 left 1
270 0 right 1
270 180 left 1
CASES

  if [[ "$failures" -gt 0 ]]; then
    return 2
  fi

  echo "rotation plan self-test passed"
}

if [[ "$ROTATION_PLAN_SELF_TEST" == "1" ]]; then
  run_rotation_plan_self_test
  exit $?
fi

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g' <<<"$1" | tr -d '\n'
}

json_bool() {
  if [[ "$1" == "1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

receiver_frames() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  sed -nE 's/.*Receiver summary: ([0-9]+) frames.*/\1/p' "$log_file" | tail -n 1
}

receiver_resolution() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  sed -nE 's/.*Headless\/null sink active: ([0-9]+x[0-9]+) @.*/\1/p' "$log_file" | tail -n 1
}

receiver_avg_fps() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  sed -nE 's/.*Receiver summary: [0-9]+ frames, avg ([0-9]+(\.[0-9]+)?) fps,.*/\1/p' "$log_file" | tail -n 1
}

receiver_incoming_mbps() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  sed -nE 's/.*Receiver summary: [0-9]+ frames, avg [0-9.]+ fps, incoming ([0-9]+(\.[0-9]+)?) Mbps,.*/\1/p' "$log_file" | tail -n 1
}

receiver_decode_errors() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  sed -nE 's/.*Receiver summary: [0-9]+ frames, avg [0-9.]+ fps, incoming [0-9.]+ Mbps, decode errors ([0-9]+).*/\1/p' "$log_file" | tail -n 1
}

receiver_selected_rtsp_url() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  sed -nE 's/^Auto-discovery selected: (rtsp:\/\/[^[:space:]]+).*/\1/p; s/^Auto-discovery self-test selected: (rtsp:\/\/[^[:space:]]+).*/\1/p' "$log_file" | tail -n 1
}

receiver_opened_rtsp_url() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 0
  sed -nE 's/^Opening (rtsp:\/\/[^[:space:]]+) with RTSP-over-TCP.*/\1/p' "$log_file" | tail -n 1
}

extract_rtsp_host_from_url() {
  local url="$1"
  sed -nE 's#^rtsp://([^/:]+).*#\1#p' <<<"$url"
}

first_matching_line() {
  local file="$1"
  local pattern="$2"
  [[ -f "$file" ]] || return 0
  grep -Eim 1 "$pattern" "$file" 2>/dev/null | tr -d '\r' || true
}

file_text_no_newlines() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  tr -d '\r\n' <"$file"
}

collect_network_artifacts() {
  "$ADB" -s "$serial" shell cmd wifi status >"$OUT_DIR/android-wifi-status.txt" 2>&1 || true
  "$ADB" -s "$serial" shell dumpsys wifi >"$OUT_DIR/android-wifi-dumpsys.txt" 2>&1 || true
  "$ADB" -s "$serial" shell ip route >"$OUT_DIR/android-ip-route.txt" 2>&1 || true
  "$ADB" -s "$serial" shell ip addr >"$OUT_DIR/android-ip-addr.txt" 2>&1 || true
  "$ADB" -s "$serial" shell getprop >"$OUT_DIR/android-getprop.txt" 2>&1 || true
}

collect_orientation_artifacts() {
  local prefix="${1:-$OUT_DIR/android-orientation}"
  "$ADB" -s "$serial" shell dumpsys input >"$prefix-input.txt" 2>&1 || true
  "$ADB" -s "$serial" shell dumpsys window >"$prefix-window.txt" 2>&1 || true
  "$ADB" -s "$serial" shell dumpsys display >"$prefix-display.txt" 2>&1 || true
  "$ADB" -s "$serial" shell settings get system accelerometer_rotation >"$prefix-accelerometer-rotation.txt" 2>&1 || true
  "$ADB" -s "$serial" shell settings get system user_rotation >"$prefix-user-rotation.txt" 2>&1 || true
}

json_number_or_null() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf 'null'
  fi
}

json_decimal_or_null() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "$value"
  else
    printf 'null'
  fi
}

is_decimal() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

decimal_positive() {
  is_decimal "$1" && awk -v value="$1" 'BEGIN { exit !(value + 0 > 0) }'
}

decimal_lte() {
  is_decimal "$1" && is_decimal "$2" && awk -v value="$1" -v limit="$2" 'BEGIN { exit !(value + 0 <= limit + 0) }'
}

write_wifi_evidence_json() {
  local evidence_file="$OUT_DIR/wifi-evidence.json"
  local generated_at
  local direct_frames
  local direct_resolution
  local direct_avg_fps
  local direct_incoming_mbps
  local direct_decode_errors
  local direct_opened_url
  local discovery_frames
  local discovery_resolution
  local discovery_avg_fps
  local discovery_incoming_mbps
  local discovery_decode_errors
  local discovery_selected_url
  local discovery_opened_url
  local front_frames
  local front_resolution
  local front_avg_fps
  local front_incoming_mbps
  local front_decode_errors
  local front_opened_url
  local front_orientation_summary
  local front_display_summary
  local front_input_summary
  local front_accelerometer_rotation
  local front_user_rotation
  local stream_orientation_summary
  local stream_display_summary
  local stream_input_summary
  local stream_accelerometer_rotation
  local stream_user_rotation
  local stream_camera_diagnostics
  local stream_rotation_degrees
  local front_rotation_degrees
  local front_camera_diagnostics
  local preview_state
  local preview_live=0
  local rtsp_host_text
  local wifi_status_summary
  local wifi_dumpsys_summary
  local ip_route_summary
  local wifi_evidence_captured=0
  local direct_passed=0
  local discovery_passed=0
  local front_status_passed=0
  local front_decode_passed=0
  local stream_orientation_evidence_captured=0
  local stream_orientation_passed=0
  local front_orientation_evidence_captured=0
  local front_orientation_passed=0
  local crash_free=0
  local config_failure_free=0
  local overall_passed=0
  local final_mvp_evidence=1

  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  direct_frames="$(receiver_frames "$OUT_DIR/receiver-direct.stdout.log")"
  direct_resolution="$(receiver_resolution "$OUT_DIR/receiver-direct.stdout.log")"
  direct_avg_fps="$(receiver_avg_fps "$OUT_DIR/receiver-direct.stdout.log")"
  direct_incoming_mbps="$(receiver_incoming_mbps "$OUT_DIR/receiver-direct.stdout.log")"
  direct_decode_errors="$(receiver_decode_errors "$OUT_DIR/receiver-direct.stdout.log")"
  direct_opened_url="$(receiver_opened_rtsp_url "$OUT_DIR/receiver-direct.stdout.log")"
  discovery_frames="$(receiver_frames "$OUT_DIR/receiver-discovery.stdout.log")"
  discovery_resolution="$(receiver_resolution "$OUT_DIR/receiver-discovery.stdout.log")"
  discovery_avg_fps="$(receiver_avg_fps "$OUT_DIR/receiver-discovery.stdout.log")"
  discovery_incoming_mbps="$(receiver_incoming_mbps "$OUT_DIR/receiver-discovery.stdout.log")"
  discovery_decode_errors="$(receiver_decode_errors "$OUT_DIR/receiver-discovery.stdout.log")"
  discovery_selected_url="$(receiver_selected_rtsp_url "$OUT_DIR/receiver-discovery.stdout.log")"
  discovery_opened_url="$(receiver_opened_rtsp_url "$OUT_DIR/receiver-discovery.stdout.log")"
  front_frames="$(receiver_frames "$OUT_DIR/receiver-front-direct.stdout.log")"
  front_resolution="$(receiver_resolution "$OUT_DIR/receiver-front-direct.stdout.log")"
  front_avg_fps="$(receiver_avg_fps "$OUT_DIR/receiver-front-direct.stdout.log")"
  front_incoming_mbps="$(receiver_incoming_mbps "$OUT_DIR/receiver-front-direct.stdout.log")"
  front_decode_errors="$(receiver_decode_errors "$OUT_DIR/receiver-front-direct.stdout.log")"
  front_opened_url="$(receiver_opened_rtsp_url "$OUT_DIR/receiver-front-direct.stdout.log")"
  front_orientation_summary="$(first_matching_line "$OUT_DIR/android-orientation-window.txt" "mCurrentRotation|mRotation|orientation|requestedOrientation|DisplayRotation|userRotation")"
  front_display_summary="$(first_matching_line "$OUT_DIR/android-orientation-display.txt" "mCurrentOrientation|mRotation|rotation|DisplayViewport")"
  front_input_summary="$(first_matching_line "$OUT_DIR/android-orientation-input.txt" "SurfaceOrientation|orientation|rotation")"
  front_accelerometer_rotation="$(file_text_no_newlines "$OUT_DIR/android-orientation-accelerometer-rotation.txt")"
  front_user_rotation="$(file_text_no_newlines "$OUT_DIR/android-orientation-user-rotation.txt")"
  stream_orientation_summary="$(first_matching_line "$OUT_DIR/android-stream-orientation-window.txt" "mCurrentRotation|mRotation|orientation|requestedOrientation|DisplayRotation|userRotation")"
  stream_display_summary="$(first_matching_line "$OUT_DIR/android-stream-orientation-display.txt" "mCurrentOrientation|mRotation|rotation|DisplayViewport")"
  stream_input_summary="$(first_matching_line "$OUT_DIR/android-stream-orientation-input.txt" "SurfaceOrientation|orientation|rotation")"
  stream_accelerometer_rotation="$(file_text_no_newlines "$OUT_DIR/android-stream-orientation-accelerometer-rotation.txt")"
  stream_user_rotation="$(file_text_no_newlines "$OUT_DIR/android-stream-orientation-user-rotation.txt")"
  stream_camera_diagnostics="$(camera_diagnostics_from_ui "$OUT_DIR/ui-after-start.xml")"
  if [[ "$stream_rotate_taps_applied" -gt 0 ]]; then
    stream_rotation_degrees="$(rotation_degrees_from_ui "$OUT_DIR/ui-stream-rotate-$stream_rotate_taps_applied.xml")"
    stream_camera_diagnostics="$(camera_diagnostics_from_ui "$OUT_DIR/ui-stream-rotate-$stream_rotate_taps_applied.xml")"
  else
    stream_rotation_degrees="$(rotation_degrees_from_ui "$OUT_DIR/ui-after-start.xml")"
  fi
  if [[ "$front_camera_rotate_taps_applied" -gt 0 ]]; then
    front_rotation_degrees="$(rotation_degrees_from_ui "$OUT_DIR/ui-front-rotate-$front_camera_rotate_taps_applied.xml")"
    front_camera_diagnostics="$(camera_diagnostics_from_ui "$OUT_DIR/ui-front-rotate-$front_camera_rotate_taps_applied.xml")"
  else
    front_rotation_degrees="$(rotation_degrees_from_ui "$OUT_DIR/ui-after-switch.xml")"
    front_camera_diagnostics="$(camera_diagnostics_from_ui "$OUT_DIR/ui-after-switch.xml")"
  fi
  preview_state="$(preview_state_from_ui "$OUT_DIR/ui-after-start.xml")"
  if [[ "$preview_state" == "live" ]]; then
    preview_live=1
  fi
  rtsp_host_text="$(extract_rtsp_host_from_url "$rtsp_url")"
  wifi_status_summary="$(first_matching_line "$OUT_DIR/android-wifi-status.txt" "Wi-Fi|Wifi|wifi|SSID|BSSID|link speed|frequency|Connected")"
  wifi_dumpsys_summary="$(first_matching_line "$OUT_DIR/android-wifi-dumpsys.txt" "Wi-Fi|Wifi|wifi|SSID|BSSID|mWifi|wlan|link speed|frequency")"
  ip_route_summary="$(first_matching_line "$OUT_DIR/android-ip-route.txt" "wlan|wifi|default")"

  if [[ "$direct_status" -eq 0 &&
        "$direct_frames" == "$FRAMES" &&
        "$direct_resolution" == "$profile_resolution_text" &&
        "$direct_decode_errors" == "0" ]] &&
      decimal_positive "$direct_avg_fps" &&
      decimal_lte "$direct_incoming_mbps" "$profile_max_incoming_mbps_text"; then
    direct_passed=1
  fi
  if [[ "$discovery_status" -eq 0 &&
        "$discovery_frames" == "$FRAMES" &&
        "$discovery_resolution" == "$profile_resolution_text" &&
        "$discovery_decode_errors" == "0" ]] &&
      decimal_positive "$discovery_avg_fps" &&
      decimal_lte "$discovery_incoming_mbps" "$profile_max_incoming_mbps_text"; then
    discovery_passed=1
  fi
  if [[ "$front_status" -eq 0 ]]; then
    front_status_passed=1
  fi
  if [[ "$front_decode_status" -eq 0 &&
        "$front_frames" == "$FRAMES" &&
        "$front_resolution" == "$profile_resolution_text" &&
        "$front_decode_errors" == "0" ]] &&
      decimal_positive "$front_avg_fps" &&
      decimal_lte "$front_incoming_mbps" "$profile_max_incoming_mbps_text"; then
    front_decode_passed=1
  fi
  if [[ -s "$OUT_DIR/android-stream-orientation-input.txt" &&
        -s "$OUT_DIR/android-stream-orientation-window.txt" &&
        -s "$OUT_DIR/android-stream-orientation-display.txt" &&
        -s "$OUT_DIR/android-stream-orientation-accelerometer-rotation.txt" &&
        -s "$OUT_DIR/android-stream-orientation-user-rotation.txt" ]]; then
    stream_orientation_evidence_captured=1
  fi
  if [[ "$STREAM_ORIENTATION_STATUS" == "passed" &&
        "$stream_orientation_evidence_captured" == "1" &&
        -n "$STREAM_ORIENTATION_NOTES" &&
        -n "$STREAM_DEVICE_POSTURE" ]]; then
    stream_orientation_passed=1
  fi
  if [[ -s "$OUT_DIR/android-orientation-input.txt" &&
        -s "$OUT_DIR/android-orientation-window.txt" &&
        -s "$OUT_DIR/android-orientation-display.txt" &&
        -s "$OUT_DIR/android-orientation-accelerometer-rotation.txt" &&
        -s "$OUT_DIR/android-orientation-user-rotation.txt" ]]; then
    front_orientation_evidence_captured=1
  fi
  if [[ "$FRONT_CAMERA_ORIENTATION_STATUS" == "passed" &&
        "$front_orientation_evidence_captured" == "1" &&
        -n "$FRONT_CAMERA_ORIENTATION_NOTES" &&
        -n "$FRONT_CAMERA_DEVICE_POSTURE" ]]; then
    front_orientation_passed=1
  fi
  if ! logs_match "FATAL EXCEPTION|AndroidRuntime.*com\.phonecam|com\.phonecam.*AndroidRuntime"; then
    crash_free=1
  fi
  if ! logs_match "AudioEncoder not prepared|Video configuration failed|Video-only audio stub failed|Camera switch failed"; then
    config_failure_free=1
  fi
  if grep -Eiq "Wi-Fi|Wifi|wifi|SSID|BSSID|mWifi|wlan|link speed|frequency" \
      "$OUT_DIR/android-wifi-status.txt" \
      "$OUT_DIR/android-wifi-dumpsys.txt" \
      "$OUT_DIR/android-ip-route.txt" \
      "$OUT_DIR/android-ip-addr.txt" 2>/dev/null; then
    wifi_evidence_captured=1
  fi
  if [[ "$direct_passed" == "1" && "$preview_live" == "1" && "$crash_free" == "1" && "$config_failure_free" == "1" ]]; then
    if [[ "$stream_orientation_passed" == "1" ]]; then
      if [[ "$VERIFY_FRONT_CAMERA" != "1" || ( "$front_status_passed" == "1" && "$front_decode_passed" == "1" && "$front_orientation_passed" == "1" ) ]]; then
        if [[ "$REQUIRE_DISCOVERY" != "1" || "$discovery_passed" == "1" ]]; then
          overall_passed=1
        fi
      fi
    fi
  fi
  if [[ "$ALLOW_UNVERIFIED_ORIENTATION" == "1" ]]; then
    final_mvp_evidence=0
  fi

  {
    printf '{\n'
    printf '  "status": "%s",\n' "$([[ "$overall_passed" == "1" ]] && echo "passed" || echo "failed")"
    printf '  "finalMvpEvidence": %s,\n' "$(json_bool "$final_mvp_evidence")"
    printf '  "generatedAt": "%s",\n' "$generated_at"
    printf '  "evidenceDir": "%s",\n' "$(json_escape "$OUT_DIR")"
    printf '  "androidSerial": "%s",\n' "$(json_escape "$serial")"
    printf '  "apk": "%s",\n' "$(json_escape "$APK")"
    printf '  "activity": "%s",\n' "$(json_escape "$activity")"
    printf '  "receiver": "%s",\n' "$(json_escape "$RECEIVER_BIN")"
    printf '  "profile": "%s",\n' "$(json_escape "$PROFILE_LABEL")"
    printf '  "expectedProfileSummary": "%s",\n' "$(json_escape "$profile_summary_text")"
    printf '  "expectedResolution": "%s",\n' "$(json_escape "$profile_resolution_text")"
    printf '  "expectedBitrateMbps": %s,\n' "$(json_decimal_or_null "$profile_bitrate_mbps_text")"
    printf '  "maxAllowedIncomingMbps": %s,\n' "$(json_decimal_or_null "$profile_max_incoming_mbps_text")"
    printf '  "framesRequested": %s,\n' "$FRAMES"
    printf '  "rtspUrl": "%s",\n' "$(json_escape "$rtsp_url")"
    printf '  "pairingCode": "%s",\n' "$(json_escape "$pairing_code")"
    printf '  "previewState": "%s",\n' "$(json_escape "$preview_state")"
    printf '  "previewLive": %s,\n' "$(json_bool "$preview_live")"
    printf '  "streamRotationRequestMode": "%s",\n' "$stream_rotation_request_mode"
    if [[ -n "$STREAM_OUTPUT_ROTATION_DEGREES" ]]; then
      printf '  "streamRequestedOutputRotationDegrees": %s,\n' "$STREAM_OUTPUT_ROTATION_DEGREES"
    else
      printf '  "streamRequestedOutputRotationDegrees": null,\n'
    fi
    printf '  "streamRotationDirection": "%s",\n' "$stream_rotation_direction_applied"
    printf '  "streamRotateTaps": %s,\n' "$stream_rotate_taps_applied"
    printf '  "streamRotationDegrees": %s,\n' "$(json_number_or_null "$stream_rotation_degrees")"
    printf '  "streamOrientation": {\n'
    printf '    "orientationEvidenceVersion": %s,\n' "$ORIENTATION_EVIDENCE_VERSION"
    printf '    "rotationControlMode": "%s",\n' "$ROTATION_CONTROL_MODE"
    printf '    "orientationLockMode": "%s",\n' "$ORIENTATION_LOCK_MODE"
    printf '    "orientationStatus": "%s",\n' "$(json_escape "$STREAM_ORIENTATION_STATUS")"
    printf '    "orientationEvidenceCaptured": %s,\n' "$(json_bool "$stream_orientation_evidence_captured")"
    printf '    "rotationRequestMode": "%s",\n' "$stream_rotation_request_mode"
    if [[ -n "$STREAM_OUTPUT_ROTATION_DEGREES" ]]; then
      printf '    "requestedOutputRotationDegrees": %s,\n' "$STREAM_OUTPUT_ROTATION_DEGREES"
    else
      printf '    "requestedOutputRotationDegrees": null,\n'
    fi
    printf '    "rotationDirection": "%s",\n' "$stream_rotation_direction_applied"
    printf '    "rotateTaps": %s,\n' "$stream_rotate_taps_applied"
    printf '    "outputRotationDegrees": %s,\n' "$(json_number_or_null "$stream_rotation_degrees")"
    printf '    "orientationNotes": "%s",\n' "$(json_escape "$STREAM_ORIENTATION_NOTES")"
    printf '    "devicePosture": "%s",\n' "$(json_escape "$STREAM_DEVICE_POSTURE")"
    printf '    "cameraDiagnostics": "%s",\n' "$(json_escape "$stream_camera_diagnostics")"
    printf '    "orientationSummary": "%s",\n' "$(json_escape "$stream_orientation_summary")"
    printf '    "displaySummary": "%s",\n' "$(json_escape "$stream_display_summary")"
    printf '    "inputSummary": "%s",\n' "$(json_escape "$stream_input_summary")"
    printf '    "accelerometerRotation": "%s",\n' "$(json_escape "$stream_accelerometer_rotation")"
    printf '    "userRotation": "%s",\n' "$(json_escape "$stream_user_rotation")"
    printf '    "orientationArtifacts": {\n'
    printf '      "input": "%s",\n' "$(json_escape "$OUT_DIR/android-stream-orientation-input.txt")"
    printf '      "window": "%s",\n' "$(json_escape "$OUT_DIR/android-stream-orientation-window.txt")"
    printf '      "display": "%s",\n' "$(json_escape "$OUT_DIR/android-stream-orientation-display.txt")"
    printf '      "accelerometerRotation": "%s",\n' "$(json_escape "$OUT_DIR/android-stream-orientation-accelerometer-rotation.txt")"
    printf '      "userRotation": "%s"\n' "$(json_escape "$OUT_DIR/android-stream-orientation-user-rotation.txt")"
    printf '    }\n'
    printf '  },\n'
    printf '  "requireDiscovery": %s,\n' "$(json_bool "$REQUIRE_DISCOVERY")"
    printf '  "verifyFrontCamera": %s,\n' "$(json_bool "$VERIFY_FRONT_CAMERA")"
    printf '  "network": {\n'
    printf '    "wifiEvidenceCaptured": %s,\n' "$(json_bool "$wifi_evidence_captured")"
    printf '    "rtspHost": "%s",\n' "$(json_escape "$rtsp_host_text")"
    printf '    "wifiStatusSummary": "%s",\n' "$(json_escape "$wifi_status_summary")"
    printf '    "wifiDumpsysSummary": "%s",\n' "$(json_escape "$wifi_dumpsys_summary")"
    printf '    "ipRouteSummary": "%s",\n' "$(json_escape "$ip_route_summary")"
    printf '    "artifacts": {\n'
    printf '      "wifiStatus": "%s",\n' "$(json_escape "$OUT_DIR/android-wifi-status.txt")"
    printf '      "wifiDumpsys": "%s",\n' "$(json_escape "$OUT_DIR/android-wifi-dumpsys.txt")"
    printf '      "ipRoute": "%s",\n' "$(json_escape "$OUT_DIR/android-ip-route.txt")"
    printf '      "ipAddr": "%s",\n' "$(json_escape "$OUT_DIR/android-ip-addr.txt")"
    printf '      "getprop": "%s"\n' "$(json_escape "$OUT_DIR/android-getprop.txt")"
    printf '    }\n'
    printf '  },\n'
    printf '  "directDecode": {\n'
    printf '    "status": "%s",\n' "$([[ "$direct_passed" == "1" ]] && echo "passed" || echo "failed")"
    printf '    "exitStatus": %s,\n' "$direct_status"
    printf '    "frames": %s,\n' "$(json_number_or_null "$direct_frames")"
    printf '    "resolution": "%s",\n' "$(json_escape "$direct_resolution")"
    printf '    "avgFps": %s,\n' "$(json_decimal_or_null "$direct_avg_fps")"
    printf '    "incomingMbps": %s,\n' "$(json_decimal_or_null "$direct_incoming_mbps")"
    printf '    "decodeErrors": %s,\n' "$(json_number_or_null "$direct_decode_errors")"
    printf '    "openedRtspUrl": "%s",\n' "$(json_escape "$direct_opened_url")"
    printf '    "stdout": "%s",\n' "$(json_escape "$OUT_DIR/receiver-direct.stdout.log")"
    printf '    "stderr": "%s",\n' "$(json_escape "$OUT_DIR/receiver-direct.stderr.log")"
    printf '    "snapshot": "%s"\n' "$(json_escape "$OUT_DIR/receiver-direct-frame.ppm")"
    printf '  },\n'
    printf '  "pairCodeDiscoveryDecode": {\n'
    printf '    "status": "%s",\n' "$([[ "$discovery_passed" == "1" ]] && echo "passed" || echo "failed")"
    printf '    "exitStatus": %s,\n' "$discovery_status"
    printf '    "pairingCode": "%s",\n' "$(json_escape "$pairing_code")"
    printf '    "frames": %s,\n' "$(json_number_or_null "$discovery_frames")"
    printf '    "resolution": "%s",\n' "$(json_escape "$discovery_resolution")"
    printf '    "avgFps": %s,\n' "$(json_decimal_or_null "$discovery_avg_fps")"
    printf '    "incomingMbps": %s,\n' "$(json_decimal_or_null "$discovery_incoming_mbps")"
    printf '    "decodeErrors": %s,\n' "$(json_number_or_null "$discovery_decode_errors")"
    printf '    "selectedRtspUrl": "%s",\n' "$(json_escape "$discovery_selected_url")"
    printf '    "openedRtspUrl": "%s",\n' "$(json_escape "$discovery_opened_url")"
    printf '    "stdout": "%s",\n' "$(json_escape "$OUT_DIR/receiver-discovery.stdout.log")"
    printf '    "stderr": "%s",\n' "$(json_escape "$OUT_DIR/receiver-discovery.stderr.log")"
    printf '    "snapshot": "%s"\n' "$(json_escape "$OUT_DIR/receiver-discovery-frame.ppm")"
    printf '  },\n'
    printf '  "frontCamera": {\n'
    printf '    "verified": %s,\n' "$(json_bool "$VERIFY_FRONT_CAMERA")"
    printf '    "switchStatus": "%s",\n' "$([[ "$front_status_passed" == "1" ]] && echo "passed" || echo "failed")"
    printf '    "decodeStatus": "%s",\n' "$([[ "$front_decode_passed" == "1" ]] && echo "passed" || echo "failed")"
    printf '    "switchExitStatus": %s,\n' "$front_status"
    printf '    "decodeExitStatus": %s,\n' "$front_decode_status"
    printf '    "frames": %s,\n' "$(json_number_or_null "$front_frames")"
    printf '    "resolution": "%s",\n' "$(json_escape "$front_resolution")"
    printf '    "avgFps": %s,\n' "$(json_decimal_or_null "$front_avg_fps")"
    printf '    "incomingMbps": %s,\n' "$(json_decimal_or_null "$front_incoming_mbps")"
    printf '    "decodeErrors": %s,\n' "$(json_number_or_null "$front_decode_errors")"
    printf '    "openedRtspUrl": "%s",\n' "$(json_escape "$front_opened_url")"
    printf '    "orientationEvidenceVersion": %s,\n' "$ORIENTATION_EVIDENCE_VERSION"
    printf '    "rotationControlMode": "%s",\n' "$ROTATION_CONTROL_MODE"
    printf '    "orientationLockMode": "%s",\n' "$ORIENTATION_LOCK_MODE"
    printf '    "orientationStatus": "%s",\n' "$(json_escape "$FRONT_CAMERA_ORIENTATION_STATUS")"
    printf '    "orientationEvidenceCaptured": %s,\n' "$(json_bool "$front_orientation_evidence_captured")"
    printf '    "rotationRequestMode": "%s",\n' "$front_rotation_request_mode"
    if [[ -n "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES" ]]; then
      printf '    "requestedOutputRotationDegrees": %s,\n' "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES"
    else
      printf '    "requestedOutputRotationDegrees": null,\n'
    fi
    printf '    "rotationDirection": "%s",\n' "$front_camera_rotation_direction_applied"
    printf '    "rotateTaps": %s,\n' "$front_camera_rotate_taps_applied"
    printf '    "outputRotationDegrees": %s,\n' "$(json_number_or_null "$front_rotation_degrees")"
    printf '    "orientationNotes": "%s",\n' "$(json_escape "$FRONT_CAMERA_ORIENTATION_NOTES")"
    printf '    "devicePosture": "%s",\n' "$(json_escape "$FRONT_CAMERA_DEVICE_POSTURE")"
    printf '    "cameraDiagnostics": "%s",\n' "$(json_escape "$front_camera_diagnostics")"
    printf '    "orientationSummary": "%s",\n' "$(json_escape "$front_orientation_summary")"
    printf '    "displaySummary": "%s",\n' "$(json_escape "$front_display_summary")"
    printf '    "inputSummary": "%s",\n' "$(json_escape "$front_input_summary")"
    printf '    "accelerometerRotation": "%s",\n' "$(json_escape "$front_accelerometer_rotation")"
    printf '    "userRotation": "%s",\n' "$(json_escape "$front_user_rotation")"
    printf '    "orientationArtifacts": {\n'
    printf '      "input": "%s",\n' "$(json_escape "$OUT_DIR/android-orientation-input.txt")"
    printf '      "window": "%s",\n' "$(json_escape "$OUT_DIR/android-orientation-window.txt")"
    printf '      "display": "%s",\n' "$(json_escape "$OUT_DIR/android-orientation-display.txt")"
    printf '      "accelerometerRotation": "%s",\n' "$(json_escape "$OUT_DIR/android-orientation-accelerometer-rotation.txt")"
    printf '      "userRotation": "%s"\n' "$(json_escape "$OUT_DIR/android-orientation-user-rotation.txt")"
    printf '    },\n'
    printf '    "artifacts": {\n'
    printf '      "switchUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-after-switch.xml")"
    printf '      "switchScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-after-switch.png")"
    printf '      "finalSwitchUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-after-switch-final.xml")"
    printf '      "finalSwitchScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-after-switch-final.png")"
    if [[ "$front_camera_rotate_taps_applied" -gt 0 ]]; then
      printf '      "rotationUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-front-rotate-$front_camera_rotate_taps_applied.xml")"
      printf '      "rotationScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-front-rotate-$front_camera_rotate_taps_applied.png")"
    else
      printf '      "rotationUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-after-switch-final.xml")"
      printf '      "rotationScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-after-switch-final.png")"
    fi
    printf '      "receiverStdout": "%s",\n' "$(json_escape "$OUT_DIR/receiver-front-direct.stdout.log")"
    printf '      "receiverStderr": "%s",\n' "$(json_escape "$OUT_DIR/receiver-front-direct.stderr.log")"
    printf '      "receiverSnapshot": "%s",\n' "$(json_escape "$OUT_DIR/receiver-front-frame.ppm")"
    printf '      "logcatAfterSwitch": "%s",\n' "$(json_escape "$OUT_DIR/logcat-after-switch.txt")"
    printf '      "logcatAfterFrontReceiver": "%s"\n' "$(json_escape "$OUT_DIR/logcat-after-front-receiver.txt")"
    printf '    }\n'
    printf '  },\n'
    printf '  "logcat": {\n'
    printf '    "crashFree": %s,\n' "$(json_bool "$crash_free")"
    printf '    "streamConfigFailureFree": %s\n' "$(json_bool "$config_failure_free")"
    printf '  },\n'
    printf '  "artifacts": {\n'
    printf '    "summary": "%s",\n' "$(json_escape "$OUT_DIR/summary.txt")"
    printf '    "initialUi": "%s",\n' "$(json_escape "$OUT_DIR/ui.xml")"
    printf '    "initialScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot.png")"
    printf '    "profileUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-profile-$profile_slug_text.xml")"
    printf '    "profileScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-profile-$profile_slug_text.png")"
    printf '    "streamingCompactUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-after-start-compact.xml")"
    printf '    "streamingCompactScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-after-start-compact.png")"
    printf '    "streamingUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-after-start.xml")"
    printf '    "streamingScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-after-start.png")"
    if [[ "$stream_rotate_taps_applied" -gt 0 ]]; then
      printf '    "streamRotationUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-stream-rotate-$stream_rotate_taps_applied.xml")"
      printf '    "streamRotationScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-stream-rotate-$stream_rotate_taps_applied.png")"
    else
      printf '    "streamRotationUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-after-start.xml")"
      printf '    "streamRotationScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-after-start.png")"
    fi
    printf '    "logcatAfterStart": "%s"\n' "$(json_escape "$OUT_DIR/logcat-after-start.txt")"
    printf '  }\n'
    printf '}\n'
  } >"$evidence_file"

  echo "Physical Android Wi-Fi JSON evidence: $evidence_file"
}

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
  if [[ "$ALLOW_EMULATOR" == "1" ]]; then
    serial="$("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
  else
    serial="$("$ADB" devices | awk 'NR > 1 && $2 == "device" && $1 !~ /^emulator-/ { print $1; exit }')"
  fi
fi

if [[ -z "$serial" ]]; then
  echo "No attached physical Android device found." >&2
  echo "Attach a phone with USB debugging or wireless debugging, then rerun this script." >&2
  "$ADB" devices >&2 || true
  exit 2
fi

if [[ "$serial" == emulator-* && "$ALLOW_EMULATOR" != "1" ]]; then
  echo "Refusing to use emulator target $serial for Wi-Fi validation." >&2
  echo "This helper is for physical Android Wi-Fi evidence. Set ALLOW_EMULATOR=1 only for script debugging." >&2
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

tap_rotate_right_control() {
  local xml_file="$1"
  tap_resource_id "$xml_file" "$PACKAGE:id/rotateStreamBtn" ||
    tap_text "$xml_file" "Rotate Right" ||
    tap_text "$xml_file" "Rotate Back" ||
    tap_text "$xml_file" "Rotate Front" ||
    tap_text "$xml_file" "Rotate"
}

tap_rotate_left_control() {
  local xml_file="$1"
  tap_resource_id "$xml_file" "$PACKAGE:id/rotateCounterClockwiseBtn" ||
    tap_text "$xml_file" "Rotate Left"
}

tap_rotate_control() {
  tap_rotate_right_control "$1"
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

rotate_taps_to_target() {
  local current="$1"
  local target="$2"

  if [[ ! "$current" =~ ^(0|90|180|270)$ ]]; then
    echo "Current output rotation is missing or invalid: ${current:-<missing>}" >&2
    return 2
  fi
  if [[ ! "$target" =~ ^(0|90|180|270)$ ]]; then
    echo "Target output rotation is invalid: ${target:-<missing>}" >&2
    return 2
  fi

  echo $(( ((target - current + 360) % 360) / 90 ))
}

rotation_plan_to_target() {
  local current="$1"
  local target="$2"
  local clockwise_taps

  clockwise_taps="$(rotate_taps_to_target "$current" "$target")" || return $?
  if [[ "$clockwise_taps" -le 2 ]]; then
    echo "right $clockwise_taps"
  else
    echo "left $((4 - clockwise_taps))"
  fi
}

preview_state_from_ui() {
  local xml_file="$1"
  [[ -f "$xml_file" ]] || return 0
  sed -nE 's/.*Preview: ([^"&< ]+).*/\1/p' "$xml_file" | tail -n 1
}

camera_diagnostics_from_ui() {
  local xml_file="$1"
  [[ -f "$xml_file" ]] || return 0
  sed -nE 's/.*Camera diagnostics: ([^&"]*).*/\1/p' "$xml_file" | tail -n 1
}

apply_rotate_taps() {
  local count="$1"
  local phase="$2"
  local current_xml="$3"
  local direction="${4:-right}"
  local before_rotation
  local after_rotation
  local tap_index
  local rotate_label="right"

  [[ "$count" -gt 0 ]] || return 0

  case "$direction" in
    right|clockwise) rotate_label="right" ;;
    left|counterclockwise) rotate_label="left" ;;
    *)
      echo "Unknown rotate direction during $phase: $direction" >&2
      return 2
      ;;
  esac

  for tap_index in $(seq 1 "$count"); do
    before_rotation="$(rotation_degrees_from_ui "$current_xml")"
    if [[ "$rotate_label" == "left" ]]; then
      tap_rotate_left_control "$current_xml"
    else
      tap_rotate_right_control "$current_xml"
    fi || {
      echo "Rotate $rotate_label button could not be tapped during $phase rotation tap $tap_index." >&2
      return 2
    }
    sleep 1
    current_xml="$OUT_DIR/ui-$phase-rotate-$tap_index.xml"
    "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$current_xml" || true
    "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-$phase-rotate-$tap_index.png" || true
    after_rotation="$(rotation_degrees_from_ui "$current_xml")"

    if [[ -n "$before_rotation" && -n "$after_rotation" && "$before_rotation" == "$after_rotation" ]]; then
      if [[ "$rotate_label" == "left" ]]; then
        tap_rotate_left_control "$current_xml"
      else
        tap_rotate_right_control "$current_xml"
      fi || {
        echo "Rotate $rotate_label retry could not be tapped during $phase rotation tap $tap_index." >&2
        return 2
      }
      sleep 1
      "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$current_xml" || true
      "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-$phase-rotate-$tap_index.png" || true
      after_rotation="$(rotation_degrees_from_ui "$current_xml")"
    fi

    if [[ -n "$before_rotation" && -n "$after_rotation" && "$before_rotation" == "$after_rotation" ]]; then
      echo "Rotate did not change output rotation during $phase rotation tap $tap_index." >&2
      return 2
    fi
  done
}

profile_slug() {
  tr '[:upper:]' '[:lower:]' <<<"$1"
}

profile_summary() {
  case "$1" in
    Efficient) echo "Efficient: 960x540 @ 30 fps, 1.2 Mbps" ;;
    Balanced) echo "Balanced: 1280x720 @ 30 fps, 1.8 Mbps" ;;
    Motion) echo "Motion: 1280x720 @ 60 fps, 2.8 Mbps" ;;
    *)
      echo "Unknown PROFILE_LABEL: $1" >&2
      echo "Expected Efficient, Balanced, or Motion." >&2
      exit 2
      ;;
  esac
}

profile_resolution() {
  case "$1" in
    Efficient) echo "960x540" ;;
    Balanced|Motion) echo "1280x720" ;;
    *)
      echo "Unknown PROFILE_LABEL: $1" >&2
      exit 2
      ;;
  esac
}

profile_bitrate_mbps() {
  case "$1" in
    Efficient) echo "1.2" ;;
    Balanced) echo "1.8" ;;
    Motion) echo "2.8" ;;
    *)
      echo "Unknown PROFILE_LABEL: $1" >&2
      exit 2
      ;;
  esac
}

profile_max_incoming_mbps() {
  case "$1" in
    Efficient) echo "2.0" ;;
    Balanced) echo "3.0" ;;
    Motion) echo "4.5" ;;
    *)
      echo "Unknown PROFILE_LABEL: $1" >&2
      exit 2
      ;;
  esac
}

extract_pairing_code() {
  local xml_file="$1"
  local node
  node="$(node_by_resource_id "$xml_file" "$PACKAGE:id/pairingCodeText")"
  sed -nE 's/.*text="([0-9]{6})".*/\1/p' <<<"$node"
}

extract_rtsp_url() {
  local xml_file="$1"
  grep -Eo 'rtsp://[^"&<[:space:]]+' "$xml_file" | head -n 1 || true
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

receiver_run_meets_profile_metrics() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 1
  grep -q "Headless/null sink active: $profile_resolution_text" "$log_file" &&
    grep -q "Receiver summary: $FRAMES frames" "$log_file" &&
    [[ "$(receiver_decode_errors "$log_file")" == "0" ]] &&
    decimal_positive "$(receiver_avg_fps "$log_file")" &&
    decimal_lte "$(receiver_incoming_mbps "$log_file")" "$profile_max_incoming_mbps_text"
}

calibration_json_entry_count=0

write_calibration_entry() {
  local evidence_file="$1"
  local phase="$2"
  local camera_label="$3"
  local index="$4"
  local rotation_degrees="$5"
  local camera_diagnostics="$6"
  local receiver_status="$7"
  local receiver_stdout="$8"
  local receiver_stderr="$9"
  local snapshot="${10}"
  local ui_xml="${11}"
  local screenshot="${12}"
  local orientation_prefix="${13}"

  if [[ "$calibration_json_entry_count" -gt 0 ]]; then
    printf ',\n' >>"$evidence_file"
  fi

  {
    printf '    {\n'
    printf '      "phase": "%s",\n' "$(json_escape "$phase")"
    printf '      "camera": "%s",\n' "$(json_escape "$camera_label")"
    printf '      "index": %s,\n' "$index"
    printf '      "outputRotationDegrees": %s,\n' "$(json_number_or_null "$rotation_degrees")"
    printf '      "cameraDiagnostics": "%s",\n' "$(json_escape "$camera_diagnostics")"
    printf '      "receiverExitStatus": %s,\n' "$receiver_status"
    printf '      "receiverFrames": %s,\n' "$(json_number_or_null "$(receiver_frames "$receiver_stdout")")"
    printf '      "receiverResolution": "%s",\n' "$(json_escape "$(receiver_resolution "$receiver_stdout")")"
    printf '      "receiverAvgFps": %s,\n' "$(json_decimal_or_null "$(receiver_avg_fps "$receiver_stdout")")"
    printf '      "receiverIncomingMbps": %s,\n' "$(json_decimal_or_null "$(receiver_incoming_mbps "$receiver_stdout")")"
    printf '      "receiverDecodeErrors": %s,\n' "$(json_number_or_null "$(receiver_decode_errors "$receiver_stdout")")"
    printf '      "artifacts": {\n'
    printf '        "ui": "%s",\n' "$(json_escape "$ui_xml")"
    printf '        "screenshot": "%s",\n' "$(json_escape "$screenshot")"
    printf '        "receiverStdout": "%s",\n' "$(json_escape "$receiver_stdout")"
    printf '        "receiverStderr": "%s",\n' "$(json_escape "$receiver_stderr")"
    printf '        "receiverSnapshot": "%s",\n' "$(json_escape "$snapshot")"
    printf '        "orientationInput": "%s",\n' "$(json_escape "$orientation_prefix-input.txt")"
    printf '        "orientationWindow": "%s",\n' "$(json_escape "$orientation_prefix-window.txt")"
    printf '        "orientationDisplay": "%s",\n' "$(json_escape "$orientation_prefix-display.txt")"
    printf '        "accelerometerRotation": "%s",\n' "$(json_escape "$orientation_prefix-accelerometer-rotation.txt")"
    printf '        "userRotation": "%s"\n' "$(json_escape "$orientation_prefix-user-rotation.txt")"
    printf '      }\n'
    printf '    }'
  } >>"$evidence_file"

  calibration_json_entry_count=$((calibration_json_entry_count + 1))
}

capture_calibration_phase() {
  local phase="$1"
  local camera_label="$2"
  local current_xml="$3"
  local evidence_file="$4"
  local summary_file="$5"
  local index
  local ui_xml
  local screenshot
  local rotation_degrees
  local camera_diagnostics
  local receiver_stdout
  local receiver_stderr
  local snapshot
  local orientation_prefix
  local receiver_status

  for index in 0 1 2 3; do
    ui_xml="$OUT_DIR/ui-calibration-$phase-$index.xml"
    screenshot="$OUT_DIR/screenshot-calibration-$phase-$index.png"
    "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$ui_xml" || true
    "$ADB" -s "$serial" exec-out screencap -p >"$screenshot" || true
    current_xml="$ui_xml"
    rotation_degrees="$(rotation_degrees_from_ui "$current_xml")"
    camera_diagnostics="$(camera_diagnostics_from_ui "$current_xml")"
    orientation_prefix="$OUT_DIR/android-calibration-$phase-$index-orientation"
    collect_orientation_artifacts "$orientation_prefix"

    receiver_stdout="$OUT_DIR/receiver-calibration-$phase-$index.stdout.log"
    receiver_stderr="$OUT_DIR/receiver-calibration-$phase-$index.stderr.log"
    snapshot="$OUT_DIR/receiver-calibration-$phase-$index.ppm"
    receiver_status=0
    "$RECEIVER_BIN" --rtsp "$rtsp_url" --frames "$CALIBRATION_FRAMES" --snapshot "$snapshot" --no-preview --no-softcam >"$receiver_stdout" 2>"$receiver_stderr" || receiver_status=$?
    "$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-calibration-$phase-$index.txt"

    {
      echo "$phase[$index]: outputRotation=${rotation_degrees:-unknown}, receiverStatus=$receiver_status, snapshot=$snapshot"
      echo "$phase[$index]: ui=$ui_xml"
      echo "$phase[$index]: diagnostics=${camera_diagnostics:-missing}"
    } >>"$summary_file"

    write_calibration_entry \
      "$evidence_file" \
      "$phase" \
      "$camera_label" \
      "$index" \
      "$rotation_degrees" \
      "$camera_diagnostics" \
      "$receiver_status" \
      "$receiver_stdout" \
      "$receiver_stderr" \
      "$snapshot" \
      "$ui_xml" \
      "$screenshot" \
      "$orientation_prefix"

    if [[ "$index" -lt 3 ]]; then
      if ! tap_rotate_control "$current_xml"; then
        echo "Rotate button could not be tapped during $phase calibration after index $index." >&2
        return 2
      fi
      sleep 1
    fi
  done

  if ! tap_rotate_control "$current_xml"; then
    echo "Rotate button could not restore $phase calibration to the starting rotation." >&2
    return 2
  fi
  sleep 1
  "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-calibration-$phase-restored.xml" || true
  "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-calibration-$phase-restored.png" || true
  echo "$phase: restored outputRotation=$(rotation_degrees_from_ui "$OUT_DIR/ui-calibration-$phase-restored.xml")" >>"$summary_file"
}

run_orientation_calibration() {
  local evidence_file="$OUT_DIR/orientation-calibration.json"
  local summary_file="$OUT_DIR/orientation-calibration-summary.txt"
  local front_xml="$OUT_DIR/ui-calibration-front-start.xml"
  local calibration_status=0

  calibration_json_entry_count=0
  {
    echo "PhoneCam physical orientation calibration"
    echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Android target: $serial"
    echo "Profile: $PROFILE_LABEL"
    echo "RTSP URL: $rtsp_url"
    echo "Pairing code: $pairing_code"
    echo "Calibration frames per rotation: $CALIBRATION_FRAMES"
    echo "This is exploratory calibration evidence and does not satisfy final MVP orientation acceptance."
    echo
  } >"$summary_file"

  {
    printf '{\n'
    printf '  "status": "calibration-only",\n'
    printf '  "generatedAt": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "evidenceDir": "%s",\n' "$(json_escape "$OUT_DIR")"
    printf '  "androidSerial": "%s",\n' "$(json_escape "$serial")"
    printf '  "profile": "%s",\n' "$(json_escape "$PROFILE_LABEL")"
    printf '  "rtspUrl": "%s",\n' "$(json_escape "$rtsp_url")"
    printf '  "pairingCode": "%s",\n' "$(json_escape "$pairing_code")"
    printf '  "calibrationFrames": %s,\n' "$CALIBRATION_FRAMES"
    printf '  "finalMvpEvidence": false,\n'
    printf '  "doesNotProve": [\n'
    printf '    "physical Android orientation acceptance",\n'
    printf '    "Windows DirectShow registration",\n'
    printf '    "OBS/browser camera enumeration"\n'
    printf '  ],\n'
    printf '  "usage": "Inspect receiverSnapshot artifacts for each camera and outputRotationDegrees, then rerun the final Wi-Fi matrix with STREAM_OUTPUT_ROTATION_DEGREES and FRONT_CAMERA_OUTPUT_ROTATION_DEGREES set to the chosen upright output rotations.",\n'
    printf '  "captures": [\n'
  } >"$evidence_file"

  capture_calibration_phase "back" "Back" "$OUT_DIR/ui-after-start.xml" "$evidence_file" "$summary_file" || calibration_status=$?

  if [[ "$VERIFY_FRONT_CAMERA" == "1" && "$calibration_status" -eq 0 ]]; then
    if tap_text "$OUT_DIR/ui-calibration-back-restored.xml" "Switch"; then
      sleep 2
      "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$front_xml" || true
      if ! grep -q "Camera: Front" "$front_xml"; then
        tap_text "$front_xml" "Switch" || calibration_status=2
      fi
      sleep 5
      "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$front_xml" || true
      "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-calibration-front-start.png" || true
      if grep -q "Camera: Front" "$front_xml"; then
        capture_calibration_phase "front" "Front" "$front_xml" "$evidence_file" "$summary_file" || calibration_status=$?
      else
        echo "Front calibration skipped: Switch did not reach front camera status." >>"$summary_file"
        calibration_status=2
      fi
    else
      echo "Front calibration skipped: Switch could not be tapped." >>"$summary_file"
      calibration_status=2
    fi
  fi

  {
    printf '\n'
    printf '  ],\n'
    printf '  "artifacts": {\n'
    printf '    "summary": "%s",\n' "$(json_escape "$summary_file")"
    printf '    "initialUi": "%s",\n' "$(json_escape "$OUT_DIR/ui-after-start.xml")"
    printf '    "initialScreenshot": "%s",\n' "$(json_escape "$OUT_DIR/screenshot-after-start.png")"
    printf '    "networkWifiStatus": "%s",\n' "$(json_escape "$OUT_DIR/android-wifi-status.txt")"
    printf '    "networkWifiDumpsys": "%s",\n' "$(json_escape "$OUT_DIR/android-wifi-dumpsys.txt")"
    printf '    "networkIpRoute": "%s"\n' "$(json_escape "$OUT_DIR/android-ip-route.txt")"
    printf '  }\n'
    printf '}\n'
  } >>"$evidence_file"

  {
    echo
    echo "Calibration JSON: $evidence_file"
    echo "Next final run: inspect snapshots, then set STREAM_OUTPUT_ROTATION_DEGREES and FRONT_CAMERA_OUTPUT_ROTATION_DEGREES for the accepted physical matrix."
  } >>"$summary_file"

  cat "$summary_file"
  return "$calibration_status"
}

cleanup() {
  if [[ "$KEEP_PHONECAM_RUNNING" != "1" ]]; then
    "$ADB" -s "$serial" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"

echo "Using physical Android target: $serial"
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

"$ADB" -s "$serial" shell am start -n "$activity" --ez phonecam_advanced true >"$OUT_DIR/launch.txt"
sleep 3
"$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui.xml" || true
"$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot.png" || true
"$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat.txt"

pairing_code="$(extract_pairing_code "$OUT_DIR/ui.xml")"
initial_rtsp_url="$(extract_rtsp_url "$OUT_DIR/ui.xml")"
profile_summary_text="$(profile_summary "$PROFILE_LABEL")"
profile_resolution_text="$(profile_resolution "$PROFILE_LABEL")"
profile_bitrate_mbps_text="$(profile_bitrate_mbps "$PROFILE_LABEL")"
profile_max_incoming_mbps_text="$(profile_max_incoming_mbps "$PROFILE_LABEL")"
profile_slug_text="$(profile_slug "$PROFILE_LABEL")"

if [[ -z "$pairing_code" ]]; then
  echo "Could not extract six-digit pairing code from UI." >&2
  exit 2
fi

if [[ -z "$initial_rtsp_url" || "$initial_rtsp_url" == *phone-ip* ]]; then
  echo "Could not extract a concrete LAN RTSP URL from UI." >&2
  echo "Initial URL was: ${initial_rtsp_url:-<missing>}" >&2
  exit 2
fi

if [[ "$initial_rtsp_url" == rtsp://127.* || ( "$serial" == emulator-* && "$initial_rtsp_url" == rtsp://10.0.2.* ) ]]; then
  echo "RTSP URL looks like loopback/emulator NAT, not physical Wi-Fi: $initial_rtsp_url" >&2
  echo "Connect a physical phone to the same Wi-Fi LAN as the receiver host." >&2
  exit 2
fi

if ! tap_text "$OUT_DIR/ui.xml" "$PROFILE_LABEL"; then
  echo "Profile '$PROFILE_LABEL' could not be selected." >&2
  exit 2
fi

sleep 1
"$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-profile-$profile_slug_text.xml" || true
"$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-profile-$profile_slug_text.png" || true
if ! grep -q "$profile_summary_text" "$OUT_DIR/ui-profile-$profile_slug_text.xml"; then
  echo "Profile '$PROFILE_LABEL' summary was not visible after selection." >&2
  echo "Expected: $profile_summary_text" >&2
  exit 2
fi

if ! tap_text "$OUT_DIR/ui-profile-$profile_slug_text.xml" "Start Camera Server"; then
  echo "Start Camera Server could not be tapped." >&2
  exit 2
fi

sleep 7
"$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-start-compact.xml" || true
"$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-start-compact.png" || true
tap_diagnostics_control "$OUT_DIR/ui-after-start-compact.xml" || true
sleep 1
"$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-start.xml" || true
"$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-start.png" || true
"$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-start.txt"

rtsp_url="$(extract_rtsp_url "$OUT_DIR/ui-after-start.xml")"
if [[ -z "$rtsp_url" ]]; then
  rtsp_url="$initial_rtsp_url"
fi
collect_network_artifacts

if ! grep -q "$profile_summary_text" "$OUT_DIR/ui-after-start.xml"; then
  echo "Streaming UI did not show expected profile summary." >&2
  echo "Expected: $profile_summary_text" >&2
  exit 2
fi

if [[ "$ORIENTATION_CALIBRATION" == "1" ]]; then
  run_orientation_calibration
  exit $?
fi

if [[ -n "$STREAM_OUTPUT_ROTATION_DEGREES" ]]; then
  stream_rotation_request_mode="absolute-degrees"
  stream_current_rotation="$(rotation_degrees_from_ui "$OUT_DIR/ui-after-start.xml")"
  stream_rotation_plan="$(rotation_plan_to_target "$stream_current_rotation" "$STREAM_OUTPUT_ROTATION_DEGREES")" || {
    echo "Could not calculate stream rotation taps for target $STREAM_OUTPUT_ROTATION_DEGREES degrees. Logs: $OUT_DIR" >&2
    exit 2
  }
  stream_rotation_direction_applied="${stream_rotation_plan%% *}"
  stream_rotate_taps_applied="${stream_rotation_plan##* }"
  echo "Stream output rotation target: $STREAM_OUTPUT_ROTATION_DEGREES deg; current: ${stream_current_rotation:-unknown} deg; applying $stream_rotate_taps_applied $stream_rotation_direction_applied tap(s)."
fi

if ! apply_rotate_taps "$stream_rotate_taps_applied" "stream" "$OUT_DIR/ui-after-start.xml" "$stream_rotation_direction_applied"; then
  echo "Could not apply requested stream rotation taps. Logs: $OUT_DIR" >&2
  exit 2
fi
collect_orientation_artifacts "$OUT_DIR/android-stream-orientation"

direct_status=0
"$RECEIVER_BIN" --rtsp "$rtsp_url" --frames "$FRAMES" --snapshot "$OUT_DIR/receiver-direct-frame.ppm" --no-preview --no-softcam >"$OUT_DIR/receiver-direct.stdout.log" 2>"$OUT_DIR/receiver-direct.stderr.log" || direct_status=$?
"$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-direct-receiver.txt"

discovery_status=0
"$RECEIVER_BIN" --auto-discover --pair-code "$pairing_code" --discover-seconds "$DISCOVER_SECONDS" --frames "$FRAMES" --snapshot "$OUT_DIR/receiver-discovery-frame.ppm" --no-preview --no-softcam >"$OUT_DIR/receiver-discovery.stdout.log" 2>"$OUT_DIR/receiver-discovery.stderr.log" || discovery_status=$?
"$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-discovery-receiver.txt"

front_status=0
front_decode_status=0
if [[ "$VERIFY_FRONT_CAMERA" == "1" ]]; then
  if tap_text "$OUT_DIR/ui-after-start.xml" "Switch"; then
    sleep 2
    "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-switch-attempt.xml" || true
    if ! grep -q "Camera: Front" "$OUT_DIR/ui-after-switch-attempt.xml"; then
      # The app's blackout overlay can intercept the first tap after a long
      # receiver run. A second tap on the same visible switch then performs
      # the actual camera change.
      tap_text "$OUT_DIR/ui-after-switch-attempt.xml" "Switch" || front_status=2
    fi
    sleep 5
    "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-switch.xml" || true
    "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-switch.png" || true
    if [[ -n "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES" ]]; then
      front_rotation_request_mode="absolute-degrees"
      front_current_rotation="$(rotation_degrees_from_ui "$OUT_DIR/ui-after-switch.xml")"
      front_rotation_plan="$(rotation_plan_to_target "$front_current_rotation" "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES")" || {
        echo "Could not calculate front-camera rotation taps for target $FRONT_CAMERA_OUTPUT_ROTATION_DEGREES degrees. Logs: $OUT_DIR" >&2
        front_status=2
        front_rotation_plan="right 0"
      }
      front_camera_rotation_direction_applied="${front_rotation_plan%% *}"
      front_camera_rotate_taps_applied="${front_rotation_plan##* }"
      echo "Front output rotation target: $FRONT_CAMERA_OUTPUT_ROTATION_DEGREES deg; current: ${front_current_rotation:-unknown} deg; applying $front_camera_rotate_taps_applied $front_camera_rotation_direction_applied tap(s)."
    fi
    if ! apply_rotate_taps "$front_camera_rotate_taps_applied" "front" "$OUT_DIR/ui-after-switch.xml" "$front_camera_rotation_direction_applied"; then
      echo "Could not apply requested front-camera rotation taps. Logs: $OUT_DIR" >&2
      front_status=2
    fi
    "$ADB" -s "$serial" exec-out uiautomator dump /dev/tty >"$OUT_DIR/ui-after-switch-final.xml" || true
    "$ADB" -s "$serial" exec-out screencap -p >"$OUT_DIR/screenshot-after-switch-final.png" || true
    collect_orientation_artifacts "$OUT_DIR/android-orientation"
    "$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-switch.txt"
    if ! grep -q "Camera: Front" "$OUT_DIR/ui-after-switch-final.xml"; then
      front_status=2
    fi
    "$RECEIVER_BIN" --rtsp "$rtsp_url" --frames "$FRAMES" --snapshot "$OUT_DIR/receiver-front-frame.ppm" --no-preview --no-softcam >"$OUT_DIR/receiver-front-direct.stdout.log" 2>"$OUT_DIR/receiver-front-direct.stderr.log" || front_decode_status=$?
    "$ADB" -s "$serial" logcat -d >"$OUT_DIR/logcat-after-front-receiver.txt"
  else
    front_status=2
  fi
fi

{
  echo "Android target: $serial"
  echo "APK: $APK"
  echo "Activity: $activity"
  echo "Receiver: $RECEIVER_BIN"
  echo "LAN RTSP URL: $rtsp_url"
  echo "Pairing code: $pairing_code"
  echo "Profile: $PROFILE_LABEL"
  echo "Expected profile: $profile_summary_text"
  echo "Frames requested: $FRAMES"
  echo "Stream rotation request mode: $stream_rotation_request_mode"
  echo "Stream output rotation target: ${STREAM_OUTPUT_ROTATION_DEGREES:-<none>}"
  echo "Stream rotate direction applied: $stream_rotation_direction_applied"
  echo "Stream rotate taps applied before direct decode: $stream_rotate_taps_applied"
  echo "Stream orientation status: $STREAM_ORIENTATION_STATUS"
  echo "Stream orientation notes: ${STREAM_ORIENTATION_NOTES:-<empty>}"
  echo "Stream device posture: ${STREAM_DEVICE_POSTURE:-<empty>}"
  echo "Front camera verification: $VERIFY_FRONT_CAMERA"
  echo "Front camera rotation request mode: $front_rotation_request_mode"
  echo "Front camera output rotation target: ${FRONT_CAMERA_OUTPUT_ROTATION_DEGREES:-<none>}"
  echo "Front camera rotate direction applied: $front_camera_rotation_direction_applied"
  echo "Front camera rotate taps applied before front decode: $front_camera_rotate_taps_applied"
  echo "Front camera orientation status: $FRONT_CAMERA_ORIENTATION_STATUS"
  echo "Front camera orientation notes: ${FRONT_CAMERA_ORIENTATION_NOTES:-<empty>}"
  echo "Front camera device posture: ${FRONT_CAMERA_DEVICE_POSTURE:-<empty>}"
  echo "Network artifacts: $OUT_DIR/android-wifi-status.txt, $OUT_DIR/android-wifi-dumpsys.txt, $OUT_DIR/android-ip-route.txt"
  echo "Stream orientation artifacts: $OUT_DIR/android-stream-orientation-window.txt, $OUT_DIR/android-stream-orientation-display.txt, $OUT_DIR/android-stream-orientation-input.txt"
  echo "Front orientation artifacts: $OUT_DIR/android-orientation-window.txt, $OUT_DIR/android-orientation-display.txt, $OUT_DIR/android-orientation-input.txt"
  echo
  if grep -q "Discovery beacon active" "$OUT_DIR/ui-after-start.xml"; then
    echo "PASS: Android RTSP server reached streaming screen"
  else
    echo "WARN: Android streaming status not found"
  fi
  if grep -q "Preview: live" "$OUT_DIR/ui-after-start.xml"; then
    echo "PASS: SurfaceView preview reported live"
  elif grep -q "Preview:" "$OUT_DIR/ui-after-start.xml"; then
    echo "FAIL: SurfaceView preview status was visible but did not report live"
  else
    echo "FAIL: SurfaceView preview status not found"
  fi
  if [[ "$direct_status" -eq 0 ]] && receiver_run_meets_profile_metrics "$OUT_DIR/receiver-direct.stdout.log"; then
    echo "PASS: receiver decoded $FRAMES frames from physical Android LAN RTSP URL within $profile_max_incoming_mbps_text Mbps and with zero decode errors"
  else
    echo "FAIL: receiver failed direct LAN RTSP decode, decoded an unexpected frame count, exceeded bandwidth, or reported decode errors"
  fi
  if [[ "$STREAM_ORIENTATION_STATUS" == "passed" &&
        -s "$OUT_DIR/android-stream-orientation-window.txt" &&
        -s "$OUT_DIR/android-stream-orientation-display.txt" &&
        -s "$OUT_DIR/android-stream-orientation-input.txt" ]]; then
    echo "PASS: physical stream/back-camera orientation was manually verified and rotation artifacts were captured"
  else
    echo "FAIL: physical stream/back-camera orientation was not manually verified; inspect the receiver output and set STREAM_ORIENTATION_STATUS=passed only when it is landscape-correct"
  fi
  if [[ "$discovery_status" -eq 0 ]] && receiver_run_meets_profile_metrics "$OUT_DIR/receiver-discovery.stdout.log"; then
    echo "PASS: receiver auto-discovered pair code and decoded $FRAMES frames over LAN within $profile_max_incoming_mbps_text Mbps and with zero decode errors"
  else
    echo "WARN: receiver auto-discovery did not complete LAN decode within the metric requirements"
  fi
  if [[ "$VERIFY_FRONT_CAMERA" == "1" ]]; then
    if [[ "$front_status" -eq 0 ]]; then
      echo "PASS: Switch changes status to front camera"
    else
      echo "FAIL: Switch did not reach front camera status"
    fi
    if [[ "$front_decode_status" -eq 0 ]] &&
       receiver_run_meets_profile_metrics "$OUT_DIR/receiver-front-direct.stdout.log"; then
      echo "PASS: receiver decoded $FRAMES frames after physical front-camera switch within $profile_max_incoming_mbps_text Mbps and with zero decode errors"
    else
      echo "FAIL: receiver failed direct LAN RTSP decode after front-camera switch, exceeded bandwidth, or reported decode errors"
    fi
    if [[ "$FRONT_CAMERA_ORIENTATION_STATUS" == "passed" &&
          -s "$OUT_DIR/android-orientation-window.txt" &&
          -s "$OUT_DIR/android-orientation-display.txt" &&
          -s "$OUT_DIR/android-orientation-input.txt" ]]; then
      echo "PASS: physical front-camera orientation was manually verified and rotation artifacts were captured"
    else
      echo "FAIL: physical front-camera orientation was not manually verified; inspect the receiver output and set FRONT_CAMERA_ORIENTATION_STATUS=passed only when it is landscape-correct"
    fi
  else
    echo "SKIP: front camera switch/decode verification disabled"
  fi
  if logs_match "FATAL EXCEPTION|AndroidRuntime.*com\.phonecam|com\.phonecam.*AndroidRuntime"; then
    echo "FAIL: PhoneCam crash marker appears in logcat"
  else
    echo "PASS: no PhoneCam crash marker in logcat"
  fi
  if logs_match "AudioEncoder not prepared|Video configuration failed|Video-only audio stub failed|Camera switch failed"; then
    echo "FAIL: stream configuration failure marker appears in logcat"
  else
    echo "PASS: no stream configuration failure marker in logcat"
  fi
} | tee "$OUT_DIR/summary.txt"

write_wifi_evidence_json

if ! grep -q "Preview: live" "$OUT_DIR/ui-after-start.xml"; then
  echo "SurfaceView preview did not report live. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ "$direct_status" -ne 0 ]]; then
  echo "Direct LAN RTSP decode failed with exit code $direct_status. Logs: $OUT_DIR" >&2
  exit "$direct_status"
fi

if ! receiver_run_meets_profile_metrics "$OUT_DIR/receiver-direct.stdout.log"; then
  echo "Direct LAN RTSP decode did not meet frame, resolution, bitrate, or decode-error requirements. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ "$STREAM_ORIENTATION_STATUS" != "passed" ]]; then
  echo "Physical stream/back-camera orientation was not manually verified. Inspect the receiver output and rerun with STREAM_ORIENTATION_STATUS=passed only when it is correct. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ -z "$STREAM_ORIENTATION_NOTES" ]]; then
  echo "Physical stream/back-camera orientation notes are required. Set STREAM_ORIENTATION_NOTES after inspecting the receiver output and decoded direct snapshot. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ -z "$STREAM_DEVICE_POSTURE" ]]; then
  echo "Physical stream/back-camera device posture is required. Set STREAM_DEVICE_POSTURE to describe the phone posture during the accepted direct stream run. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ ! -s "$OUT_DIR/android-stream-orientation-window.txt" ||
      ! -s "$OUT_DIR/android-stream-orientation-display.txt" ||
      ! -s "$OUT_DIR/android-stream-orientation-input.txt" ||
      ! -s "$OUT_DIR/android-stream-orientation-accelerometer-rotation.txt" ||
      ! -s "$OUT_DIR/android-stream-orientation-user-rotation.txt" ]]; then
  echo "Physical stream/back-camera orientation artifacts were not captured. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ "$VERIFY_FRONT_CAMERA" == "1" && "$front_status" -ne 0 ]]; then
  echo "Physical front-camera switch did not reach front camera status. Logs: $OUT_DIR" >&2
  exit "$front_status"
fi

if [[ "$VERIFY_FRONT_CAMERA" == "1" && "$front_decode_status" -ne 0 ]]; then
  echo "Direct LAN RTSP decode after front-camera switch failed with exit code $front_decode_status. Logs: $OUT_DIR" >&2
  exit "$front_decode_status"
fi

if [[ "$VERIFY_FRONT_CAMERA" == "1" ]] && ! receiver_run_meets_profile_metrics "$OUT_DIR/receiver-front-direct.stdout.log"; then
  echo "Direct LAN RTSP decode after front-camera switch did not meet frame, resolution, bitrate, or decode-error requirements. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ "$VERIFY_FRONT_CAMERA" == "1" && "$FRONT_CAMERA_ORIENTATION_STATUS" != "passed" ]]; then
  echo "Physical front-camera orientation was not manually verified. Inspect the receiver output and rerun with FRONT_CAMERA_ORIENTATION_STATUS=passed only when it is correct. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ "$VERIFY_FRONT_CAMERA" == "1" && -z "$FRONT_CAMERA_ORIENTATION_NOTES" ]]; then
  echo "Physical front-camera orientation notes are required. Set FRONT_CAMERA_ORIENTATION_NOTES after inspecting the receiver output and decoded front-camera snapshot. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ "$VERIFY_FRONT_CAMERA" == "1" && -z "$FRONT_CAMERA_DEVICE_POSTURE" ]]; then
  echo "Physical front-camera device posture is required. Set FRONT_CAMERA_DEVICE_POSTURE to describe the phone posture during the accepted front-camera run. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ "$VERIFY_FRONT_CAMERA" == "1" &&
      ( ! -s "$OUT_DIR/android-orientation-window.txt" ||
        ! -s "$OUT_DIR/android-orientation-display.txt" ||
        ! -s "$OUT_DIR/android-orientation-input.txt" ||
        ! -s "$OUT_DIR/android-orientation-accelerometer-rotation.txt" ||
        ! -s "$OUT_DIR/android-orientation-user-rotation.txt" ) ]]; then
  echo "Physical front-camera orientation artifacts were not captured. Logs: $OUT_DIR" >&2
  exit 2
fi

if logs_match "FATAL EXCEPTION|AndroidRuntime.*com\.phonecam|com\.phonecam.*AndroidRuntime|AudioEncoder not prepared|Video configuration failed|Video-only audio stub failed|Camera switch failed"; then
  echo "Android logcat contains a fatal or stream configuration failure marker. Logs: $OUT_DIR" >&2
  exit 2
fi

if [[ "$REQUIRE_DISCOVERY" == "1" && "$discovery_status" -ne 0 ]]; then
  echo "LAN discovery was required but failed with exit code $discovery_status. Logs: $OUT_DIR" >&2
  exit "$discovery_status"
fi

if [[ "$REQUIRE_DISCOVERY" == "1" ]] && ! receiver_run_meets_profile_metrics "$OUT_DIR/receiver-discovery.stdout.log"; then
  echo "LAN discovery decode did not meet frame, resolution, bitrate, or decode-error requirements. Logs: $OUT_DIR" >&2
  exit 2
fi

echo "Physical Android Wi-Fi receiver smoke evidence: $OUT_DIR"
