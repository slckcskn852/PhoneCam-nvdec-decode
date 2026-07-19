#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/private/tmp/phonecam-mac-receiver-build}"
FFMPEG_ROOT="${FFMPEG_ROOT:-/opt/homebrew}"
BUILD_RECEIVER="${BUILD_RECEIVER:-1}"
RECEIVER_BIN="${RECEIVER_BIN:-}"
RTSP_URL="${RTSP_URL:-}"
PAIR_CODE="${PAIR_CODE:-}"
DISCOVER_SECONDS="${DISCOVER_SECONDS:-8}"
FRAMES="${FRAMES:-60}"
PREVIEW="${PREVIEW:-0}"
OUT_DIR="${OUT_DIR:-${TMPDIR:-/tmp}/phonecam-mac-receiver-dev-$(date +%Y%m%d-%H%M%S)}"

if [[ -z "$RECEIVER_BIN" ]]; then
  RECEIVER_BIN="$BUILD_DIR/phonecam-receiver"
fi

if [[ ! "$FRAMES" =~ ^[0-9]+$ ]] || [[ "$FRAMES" -lt 1 ]]; then
  echo "FRAMES must be a positive integer: $FRAMES" >&2
  exit 2
fi

if [[ ! "$DISCOVER_SECONDS" =~ ^[0-9]+$ ]] || [[ "$DISCOVER_SECONDS" -lt 1 ]]; then
  echo "DISCOVER_SECONDS must be a positive integer: $DISCOVER_SECONDS" >&2
  exit 2
fi

if [[ -n "$PAIR_CODE" && ! "$PAIR_CODE" =~ ^[0-9]{6}$ ]]; then
  echo "PAIR_CODE must contain six digits: $PAIR_CODE" >&2
  exit 2
fi

if [[ "$PREVIEW" != "0" && "$PREVIEW" != "1" ]]; then
  echo "PREVIEW must be 0 or 1: $PREVIEW" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"

if [[ ! -x "$RECEIVER_BIN" ]]; then
  if [[ "$BUILD_RECEIVER" != "1" ]]; then
    echo "Receiver binary not found or not executable: $RECEIVER_BIN" >&2
    echo "Set RECEIVER_BIN or run with BUILD_RECEIVER=1." >&2
    exit 2
  fi

  cmake -S "$ROOT_DIR/desktop/windows" -B "$BUILD_DIR" \
    -DFFMPEG_ROOT="$FFMPEG_ROOT" \
    -DPHONECAM_WITH_SOFTCAM=OFF
  cmake --build "$BUILD_DIR" --config Release
fi

if [[ ! -x "$RECEIVER_BIN" ]]; then
  echo "Receiver binary not found or not executable after build: $RECEIVER_BIN" >&2
  exit 2
fi

source_mode="auto-discover"
receiver_args=()
if [[ -n "$RTSP_URL" ]]; then
  source_mode="direct-rtsp"
  receiver_args+=(--rtsp "$RTSP_URL")
else
  receiver_args+=(--auto-discover --discover-seconds "$DISCOVER_SECONDS")
  if [[ -n "$PAIR_CODE" ]]; then
    receiver_args+=(--pair-code "$PAIR_CODE")
  fi
fi

SNAPSHOT_FILE="$OUT_DIR/receiver-frame.ppm"
STDOUT_LOG="$OUT_DIR/receiver.stdout.log"
STDERR_LOG="$OUT_DIR/receiver.stderr.log"
COMMAND_LOG="$OUT_DIR/receiver-command.txt"
EVIDENCE_JSON="$OUT_DIR/mac-receiver-evidence.json"

receiver_args+=(--frames "$FRAMES" --snapshot "$SNAPSHOT_FILE" --no-softcam)
if [[ "$PREVIEW" != "1" ]]; then
  receiver_args+=(--no-preview)
fi

{
  printf '%q ' "$RECEIVER_BIN" "${receiver_args[@]}"
  echo
} >"$COMMAND_LOG"

receiver_status=0
"$RECEIVER_BIN" "${receiver_args[@]}" >"$STDOUT_LOG" 2>"$STDERR_LOG" || receiver_status=$?

if [[ "$receiver_status" -eq 0 && ! -s "$SNAPSHOT_FILE" ]]; then
  echo "Receiver exited successfully but did not write a decoded frame snapshot: $SNAPSHOT_FILE" >&2
  receiver_status=2
fi

ROOT_DIR="$ROOT_DIR" \
OUT_DIR="$OUT_DIR" \
RECEIVER_BIN="$RECEIVER_BIN" \
SOURCE_MODE="$source_mode" \
RTSP_URL="$RTSP_URL" \
PAIR_CODE="$PAIR_CODE" \
DISCOVER_SECONDS="$DISCOVER_SECONDS" \
FRAMES="$FRAMES" \
PREVIEW="$PREVIEW" \
SNAPSHOT_FILE="$SNAPSHOT_FILE" \
STDOUT_LOG="$STDOUT_LOG" \
STDERR_LOG="$STDERR_LOG" \
COMMAND_LOG="$COMMAND_LOG" \
EVIDENCE_JSON="$EVIDENCE_JSON" \
RECEIVER_STATUS="$receiver_status" \
ruby <<'RUBY'
require "json"
require "time"

stdout_path = ENV.fetch("STDOUT_LOG")
stdout = File.exist?(stdout_path) ? File.read(stdout_path) : ""
stderr_path = ENV.fetch("STDERR_LOG")

summary_match = stdout.match(/Receiver summary: (\d+) frames, avg ([0-9.]+) fps, incoming ([0-9.]+) Mbps, decode errors (\d+)/)
opened_match = stdout.match(/Opening ([^\s]+) with RTSP-over-TCP/)
selected_match = stdout.match(/Auto-discovery selected: ([^\s]+)/)
sink_match = stdout.match(/Headless\/null sink active: ([0-9]+x[0-9]+) @ ([0-9.]+) fps/)

receiver_status = Integer(ENV.fetch("RECEIVER_STATUS"))
frames = summary_match ? Integer(summary_match[1]) : 0
decode_errors = summary_match ? Integer(summary_match[4]) : nil
snapshot_path = ENV.fetch("SNAPSHOT_FILE")
snapshot_present = File.exist?(snapshot_path) && File.size(snapshot_path).positive?

status = receiver_status.zero? && frames.positive? && decode_errors == 0 && snapshot_present ? "passed" : "failed"

evidence = {
  "status" => status,
  "generatedAt" => Time.now.utc.iso8601,
  "mode" => "mac-receiver-dev-smoke",
  "sourceMode" => ENV.fetch("SOURCE_MODE"),
  "macDevOnly" => true,
  "doesNotProve" => [
    "Windows DirectShow registration",
    "PhoneCam Virtual Camera enumeration",
    "OBS/browser camera picker rendering",
    "Windows firewall or LAN behavior"
  ],
  "outDir" => ENV.fetch("OUT_DIR"),
  "receiver" => ENV.fetch("RECEIVER_BIN"),
  "requestedFrames" => Integer(ENV.fetch("FRAMES")),
  "previewRequested" => ENV.fetch("PREVIEW") == "1",
  "rtspUrl" => ENV.fetch("RTSP_URL"),
  "pairingCode" => ENV.fetch("PAIR_CODE"),
  "discoverSeconds" => Integer(ENV.fetch("DISCOVER_SECONDS")),
  "exitStatus" => receiver_status,
  "selectedRtspUrl" => selected_match && selected_match[1],
  "openedRtspUrl" => opened_match && opened_match[1],
  "sinkResolution" => sink_match && sink_match[1],
  "sinkFps" => sink_match && Float(sink_match[2]),
  "decode" => {
    "frames" => frames,
    "avgFps" => summary_match && Float(summary_match[2]),
    "incomingMbps" => summary_match && Float(summary_match[3]),
    "decodeErrors" => decode_errors
  },
  "artifacts" => {
    "command" => ENV.fetch("COMMAND_LOG"),
    "stdout" => stdout_path,
    "stderr" => stderr_path,
    "snapshot" => snapshot_path,
    "snapshotPresent" => snapshot_present
  }
}

File.write(ENV.fetch("EVIDENCE_JSON"), JSON.pretty_generate(evidence))
RUBY

echo "Mac receiver dev evidence: $EVIDENCE_JSON"
sed -n '1,160p' "$STDOUT_LOG"

if [[ "$receiver_status" -ne 0 ]]; then
  echo "Receiver stderr: $STDERR_LOG" >&2
  sed -n '1,160p' "$STDERR_LOG" >&2 || true
  exit "$receiver_status"
fi
