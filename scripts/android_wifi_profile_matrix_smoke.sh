#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ROOT="${OUT_ROOT:-/private/tmp/phonecam-android-wifi-profile-matrix-$(date +%Y%m%d-%H%M%S)}"
PROFILES="${PROFILES:-Efficient Balanced Motion}"
VERIFY_FRONT_CAMERA="${VERIFY_FRONT_CAMERA:-1}"
REQUIRE_DISCOVERY="${REQUIRE_DISCOVERY:-1}"
CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-0}"
STREAM_ROTATE_TAPS="${STREAM_ROTATE_TAPS:-0}"
FRONT_CAMERA_ROTATE_TAPS="${FRONT_CAMERA_ROTATE_TAPS:-0}"
STREAM_OUTPUT_ROTATION_DEGREES="${STREAM_OUTPUT_ROTATION_DEGREES:-}"
FRONT_CAMERA_OUTPUT_ROTATION_DEGREES="${FRONT_CAMERA_OUTPUT_ROTATION_DEGREES:-}"
ALLOW_UNVERIFIED_ORIENTATION="${ALLOW_UNVERIFIED_ORIENTATION:-0}"
STREAM_ORIENTATION_STATUS="${STREAM_ORIENTATION_STATUS:-not-verified}"
STREAM_ORIENTATION_NOTES="${STREAM_ORIENTATION_NOTES:-}"
STREAM_DEVICE_POSTURE="${STREAM_DEVICE_POSTURE:-}"
FRONT_CAMERA_ORIENTATION_STATUS="${FRONT_CAMERA_ORIENTATION_STATUS:-not-verified}"
FRONT_CAMERA_ORIENTATION_NOTES="${FRONT_CAMERA_ORIENTATION_NOTES:-}"
FRONT_CAMERA_DEVICE_POSTURE="${FRONT_CAMERA_DEVICE_POSTURE:-}"

mkdir -p "$OUT_ROOT"

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

if [[ "$ALLOW_UNVERIFIED_ORIENTATION" != "1" ]]; then
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
    echo "Physical orientation acceptance inputs are required before running the final Android Wi-Fi matrix." >&2
    printf 'Missing: %s\n' "${missing_orientation_inputs[*]}" >&2
    echo "Inspect the physical receiver output first, then set the status fields to passed only when the stream is landscape-correct." >&2
    echo "For exploratory collection only, set ALLOW_UNVERIFIED_ORIENTATION=1 CONTINUE_ON_FAILURE=1; that evidence will not satisfy final MVP validation." >&2
    exit 2
  fi
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

json_string_or_null() {
  local value="$1"
  if [[ -n "$value" ]]; then
    printf '"%s"' "$(json_escape "$value")"
  else
    printf 'null'
  fi
}

json_bool_or_null() {
  case "$1" in
    true|false) printf '%s' "$1" ;;
    *) printf 'null' ;;
  esac
}

json_field_from_file() {
  local json_file="$1"
  local field="$2"
  [[ -f "$json_file" ]] || return 0
  sed -nE "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$json_file" | head -n 1
}

json_bool_field_from_file() {
  local json_file="$1"
  local field="$2"
  [[ -f "$json_file" ]] || return 0
  sed -nE "s/.*\"$field\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" "$json_file" | head -n 1
}

write_matrix_evidence_json() {
  local evidence_file="$OUT_ROOT/matrix-evidence.json"
  local generated_at
  local profile
  local slug
  local profile_dir
  local exit_status
  local status
  local evidence_json
  local pairing_code
  local rtsp_url
  local preview_live
  local final_mvp_evidence=1
  local first=1

  if [[ "$ALLOW_UNVERIFIED_ORIENTATION" == "1" ]]; then
    final_mvp_evidence=0
  fi

  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    printf '{\n'
    printf '  "status": "%s",\n' "$([[ "$matrix_status" -eq 0 ]] && echo "passed" || echo "failed")"
    printf '  "finalMvpEvidence": %s,\n' "$(json_bool "$final_mvp_evidence")"
    printf '  "generatedAt": "%s",\n' "$generated_at"
    printf '  "outRoot": "%s",\n' "$(json_escape "$OUT_ROOT")"
    printf '  "profilesRequested": "%s",\n' "$(json_escape "$PROFILES")"
    printf '  "verifyFrontCamera": %s,\n' "$(json_bool "$VERIFY_FRONT_CAMERA")"
    printf '  "requireDiscovery": %s,\n' "$(json_bool "$REQUIRE_DISCOVERY")"
    printf '  "continueOnFailure": %s,\n' "$(json_bool "$CONTINUE_ON_FAILURE")"
    printf '  "allowUnverifiedOrientation": %s,\n' "$(json_bool "$ALLOW_UNVERIFIED_ORIENTATION")"
    if [[ -n "$STREAM_OUTPUT_ROTATION_DEGREES" ]]; then
      printf '  "streamOutputRotationDegrees": %s,\n' "$STREAM_OUTPUT_ROTATION_DEGREES"
    else
      printf '  "streamOutputRotationDegrees": null,\n'
    fi
    printf '  "streamRotateTaps": %s,\n' "$STREAM_ROTATE_TAPS"
    if [[ -n "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES" ]]; then
      printf '  "frontCameraOutputRotationDegrees": %s,\n' "$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES"
    else
      printf '  "frontCameraOutputRotationDegrees": null,\n'
    fi
    printf '  "frontCameraRotateTaps": %s,\n' "$FRONT_CAMERA_ROTATE_TAPS"
    printf '  "matrixExitStatus": %s,\n' "$matrix_status"
    printf '  "summary": "%s",\n' "$(json_escape "$OUT_ROOT/summary.txt")"
    printf '  "profiles": [\n'
    for profile in "${profile_list[@]}"; do
      slug="$(tr '[:upper:]' '[:lower:]' <<<"$profile")"
      profile_dir="$OUT_ROOT/$slug"
      evidence_json="$profile_dir/wifi-evidence.json"
      pairing_code="$(json_field_from_file "$evidence_json" "pairingCode")"
      rtsp_url="$(json_field_from_file "$evidence_json" "rtspUrl")"
      preview_live="$(json_bool_field_from_file "$evidence_json" "previewLive")"
      exit_status=""
      status="missing"
      if [[ -f "$profile_dir/skipped.txt" ]]; then
        status="skipped"
      elif [[ -f "$profile_dir/exit-status.txt" ]]; then
        exit_status="$(cat "$profile_dir/exit-status.txt")"
        if [[ "$exit_status" == "0" ]]; then
          status="passed"
        else
          status="failed"
        fi
      fi

      if [[ "$first" == "0" ]]; then
        printf ',\n'
      fi
      first=0
      printf '    {\n'
      printf '      "profile": "%s",\n' "$(json_escape "$profile")"
      printf '      "status": "%s",\n' "$status"
      if [[ -n "$exit_status" ]]; then
      printf '      "exitStatus": %s,\n' "$exit_status"
      else
        printf '      "exitStatus": null,\n'
      fi
      printf '      "evidenceDir": "%s",\n' "$(json_escape "$profile_dir")"
      printf '      "evidenceJson": "%s",\n' "$(json_escape "$evidence_json")"
      printf '      "pairingCode": %s,\n' "$(json_string_or_null "$pairing_code")"
      printf '      "rtspUrl": %s,\n' "$(json_string_or_null "$rtsp_url")"
      printf '      "previewLive": %s,\n' "$(json_bool_or_null "$preview_live")"
      printf '      "runLog": "%s",\n' "$(json_escape "$profile_dir/run.log")"
      printf '      "summary": "%s",\n' "$(json_escape "$profile_dir/summary.txt")"
      printf '      "skipped": "%s"\n' "$(json_escape "$profile_dir/skipped.txt")"
      printf '    }'
    done
    printf '\n  ]\n'
    printf '}\n'
  } >"$evidence_file"

  echo "Physical Android Wi-Fi profile matrix JSON evidence: $evidence_file"
}

read -r -a profile_list <<<"$PROFILES"
if [[ "${#profile_list[@]}" -eq 0 ]]; then
  echo "No profiles requested. Set PROFILES='Efficient Balanced Motion'." >&2
  exit 2
fi

echo "Writing profile matrix evidence to: $OUT_ROOT"

last_index=$(( ${#profile_list[@]} - 1 ))
matrix_status=0
stop_remaining=0
for index in "${!profile_list[@]}"; do
  profile="${profile_list[$index]}"
  slug="$(tr '[:upper:]' '[:lower:]' <<<"$profile")"
  profile_dir="$OUT_ROOT/$slug"
  mkdir -p "$profile_dir"

  if [[ "$stop_remaining" == "1" ]]; then
    echo "Skipping profile after earlier failure: $profile"
    echo "SKIP: not run after an earlier matrix failure" >"$profile_dir/skipped.txt"
    continue
  fi

  front_for_profile=0
  if [[ "$VERIFY_FRONT_CAMERA" == "1" && "$index" -eq "$last_index" ]]; then
    front_for_profile=1
  fi

  echo "Running physical Wi-Fi smoke for profile: $profile"
  set +e
  PROFILE_LABEL="$profile" \
    VERIFY_FRONT_CAMERA="$front_for_profile" \
    REQUIRE_DISCOVERY="$REQUIRE_DISCOVERY" \
    STREAM_ROTATE_TAPS="$STREAM_ROTATE_TAPS" \
    FRONT_CAMERA_ROTATE_TAPS="$FRONT_CAMERA_ROTATE_TAPS" \
    STREAM_OUTPUT_ROTATION_DEGREES="$STREAM_OUTPUT_ROTATION_DEGREES" \
    FRONT_CAMERA_OUTPUT_ROTATION_DEGREES="$FRONT_CAMERA_OUTPUT_ROTATION_DEGREES" \
    ALLOW_UNVERIFIED_ORIENTATION="$ALLOW_UNVERIFIED_ORIENTATION" \
    STREAM_ORIENTATION_STATUS="$STREAM_ORIENTATION_STATUS" \
    STREAM_ORIENTATION_NOTES="$STREAM_ORIENTATION_NOTES" \
    STREAM_DEVICE_POSTURE="$STREAM_DEVICE_POSTURE" \
    FRONT_CAMERA_ORIENTATION_STATUS="$FRONT_CAMERA_ORIENTATION_STATUS" \
    FRONT_CAMERA_ORIENTATION_NOTES="$FRONT_CAMERA_ORIENTATION_NOTES" \
    FRONT_CAMERA_DEVICE_POSTURE="$FRONT_CAMERA_DEVICE_POSTURE" \
    OUT_DIR="$profile_dir" \
    "$ROOT_DIR/scripts/android_wifi_receiver_smoke.sh" >"$profile_dir/run.log" 2>&1
  profile_status=$?
  set -e

  cat "$profile_dir/run.log"
  echo "$profile_status" >"$profile_dir/exit-status.txt"
  if [[ "$profile_status" -ne 0 ]]; then
    if [[ "$matrix_status" -eq 0 ]]; then
      matrix_status="$profile_status"
    fi
    if [[ "$CONTINUE_ON_FAILURE" != "1" ]]; then
      stop_remaining=1
    fi
  fi
done

{
  echo "Physical Android Wi-Fi profile matrix"
  echo "Profiles: $PROFILES"
  echo "Front camera verification on final profile: $VERIFY_FRONT_CAMERA"
  echo "Pair-code discovery required: $REQUIRE_DISCOVERY"
  echo "Continue on failure: $CONTINUE_ON_FAILURE"
  echo "Allow unverified orientation: $ALLOW_UNVERIFIED_ORIENTATION"
  echo "Stream output rotation target: ${STREAM_OUTPUT_ROTATION_DEGREES:-<none>}"
  echo "Stream rotate taps before direct decode: $STREAM_ROTATE_TAPS"
  echo "Stream orientation status: $STREAM_ORIENTATION_STATUS"
  echo "Stream orientation notes: ${STREAM_ORIENTATION_NOTES:-<empty>}"
  echo "Stream device posture: ${STREAM_DEVICE_POSTURE:-<empty>}"
  echo "Front camera output rotation target: ${FRONT_CAMERA_OUTPUT_ROTATION_DEGREES:-<none>}"
  echo "Front camera rotate taps before final front decode: $FRONT_CAMERA_ROTATE_TAPS"
  echo "Front camera orientation status: $FRONT_CAMERA_ORIENTATION_STATUS"
  echo "Front camera orientation notes: ${FRONT_CAMERA_ORIENTATION_NOTES:-<empty>}"
  echo "Front camera device posture: ${FRONT_CAMERA_DEVICE_POSTURE:-<empty>}"
  echo
  for profile in "${profile_list[@]}"; do
    slug="$(tr '[:upper:]' '[:lower:]' <<<"$profile")"
    profile_dir="$OUT_ROOT/$slug"
    echo "== $profile =="
    if [[ -f "$profile_dir/summary.txt" ]]; then
      cat "$profile_dir/summary.txt"
    elif [[ -f "$profile_dir/skipped.txt" ]]; then
      cat "$profile_dir/skipped.txt"
    elif [[ -f "$profile_dir/run.log" ]]; then
      cat "$profile_dir/run.log"
    else
      echo "missing summary"
    fi
    if [[ -f "$profile_dir/exit-status.txt" ]]; then
      echo "Exit status: $(cat "$profile_dir/exit-status.txt")"
    fi
    echo
  done
  echo "Matrix exit status: $matrix_status"
} | tee "$OUT_ROOT/summary.txt"

write_matrix_evidence_json

echo "Physical Android Wi-Fi profile matrix evidence: $OUT_ROOT"
exit "$matrix_status"
