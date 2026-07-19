#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECEIVER_BIN="${RECEIVER_BIN:-/private/tmp/phonecam-windows-receiver-build/phonecam-receiver}"
MEDIAMTX_BIN="${MEDIAMTX_BIN:-mediamtx}"
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
FRAMES="${FRAMES:-60}"
RTSP_PORT="${RTSP_PORT:-8555}"
RTSP_URL="${RTSP_URL:-rtsp://127.0.0.1:${RTSP_PORT}/phonecam-test}"
PAIR_CODE="${PAIR_CODE-123456}"

if [[ "$MEDIAMTX_BIN" == "mediamtx" ]] && ! command -v "$MEDIAMTX_BIN" >/dev/null 2>&1 && [[ -x /private/tmp/phonecam-mediamtx/mediamtx ]]; then
  MEDIAMTX_BIN="/private/tmp/phonecam-mediamtx/mediamtx"
fi

if [[ ! "$RTSP_PORT" =~ ^[0-9]+$ ]]; then
  echo "RTSP_PORT must be numeric: $RTSP_PORT" >&2
  exit 2
fi

if [[ ! -x "$RECEIVER_BIN" ]]; then
  echo "Receiver binary not found or not executable: $RECEIVER_BIN" >&2
  echo "Set RECEIVER_BIN or build desktop/windows first." >&2
  exit 2
fi

if ! command -v "$MEDIAMTX_BIN" >/dev/null 2>&1 && [[ ! -x "$MEDIAMTX_BIN" ]]; then
  echo "MediaMTX not found: $MEDIAMTX_BIN" >&2
  echo "Set MEDIAMTX_BIN to the mediamtx executable." >&2
  exit 2
fi

if ! command -v "$FFMPEG_BIN" >/dev/null 2>&1 && [[ ! -x "$FFMPEG_BIN" ]]; then
  echo "FFmpeg not found: $FFMPEG_BIN" >&2
  echo "Set FFMPEG_BIN to the ffmpeg executable." >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phonecam-fixture.XXXXXX")"
CONFIG_FILE="$TMP_DIR/mediamtx.yml"
MEDIAMTX_LOG="$TMP_DIR/mediamtx.log"
FFMPEG_LOG="$TMP_DIR/ffmpeg.log"
SNAPSHOT_FILE="$TMP_DIR/receiver-frame.ppm"

cat > "$CONFIG_FILE" <<YAML
logLevel: info
logDestinations: [stdout]
readTimeout: 10s
writeTimeout: 10s
rtsp: true
rtspTransports: [tcp]
rtspAddress: :$RTSP_PORT
rtmp: false
hls: false
webrtc: false
srt: false
paths:
  all:
YAML

mediamtx_pid=""
ffmpeg_pid=""

cleanup() {
  local status=$?
  if [[ -n "$ffmpeg_pid" ]] && kill -0 "$ffmpeg_pid" >/dev/null 2>&1; then
    kill "$ffmpeg_pid" >/dev/null 2>&1 || true
    wait "$ffmpeg_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$mediamtx_pid" ]] && kill -0 "$mediamtx_pid" >/dev/null 2>&1; then
    kill "$mediamtx_pid" >/dev/null 2>&1 || true
    wait "$mediamtx_pid" >/dev/null 2>&1 || true
  fi
  if [[ "$status" -eq 0 && "${KEEP_PHONECAM_FIXTURE_LOGS:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  else
    echo "Fixture logs preserved in: $TMP_DIR" >&2
  fi
}
trap cleanup EXIT

ensure_running() {
  local pid="$1"
  local name="$2"
  local log_file="$3"

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "$name exited before the fixture could run." >&2
    echo "Log: $log_file" >&2
    sed -n '1,220p' "$log_file" >&2 || true
    exit 2
  fi
}

"$MEDIAMTX_BIN" "$CONFIG_FILE" >"$MEDIAMTX_LOG" 2>&1 &
mediamtx_pid="$!"
sleep 1
ensure_running "$mediamtx_pid" "MediaMTX" "$MEDIAMTX_LOG"

"$FFMPEG_BIN" -hide_banner -loglevel info -re \
  -f lavfi -i testsrc2=size=1280x720:rate=30 \
  -f lavfi -i anullsrc=channel_layout=mono:sample_rate=48000 \
  -pix_fmt yuv420p -c:v libx264 -preset veryfast -tune zerolatency \
  -g 30 -b:v 4M -c:a aac -b:a 96k -rtsp_transport tcp -f rtsp "$RTSP_URL" >"$FFMPEG_LOG" 2>&1 &
ffmpeg_pid="$!"
sleep 2
ensure_running "$ffmpeg_pid" "FFmpeg RTSP publisher" "$FFMPEG_LOG"

receiver_args=(--auto-discover-self-test "$RTSP_URL" --frames "$FRAMES" --snapshot "$SNAPSHOT_FILE" --no-preview --no-softcam)
if [[ -n "$PAIR_CODE" ]]; then
  receiver_args+=(--pair-code "$PAIR_CODE")
fi

"$RECEIVER_BIN" "${receiver_args[@]}"
if [[ ! -s "$SNAPSHOT_FILE" ]]; then
  echo "Receiver fixture did not write a decoded frame snapshot: $SNAPSHOT_FILE" >&2
  exit 2
fi

echo "Fixture passed."
if [[ "${KEEP_PHONECAM_FIXTURE_LOGS:-0}" == "1" ]]; then
  echo "MediaMTX log: $MEDIAMTX_LOG"
  echo "FFmpeg log: $FFMPEG_LOG"
  echo "Receiver snapshot: $SNAPSHOT_FILE"
else
  echo "Temporary fixture logs will be removed. Set KEEP_PHONECAM_FIXTURE_LOGS=1 to preserve them."
fi
