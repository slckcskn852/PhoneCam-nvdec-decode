#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/private/tmp/phonecam-mac-receiver-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist/PhoneCam-Mac}"
APP_NAME="${APP_NAME:-PhoneCam Receiver}"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
RECEIVER_BIN="${RECEIVER_BIN:-}"
FFMPEG_ROOT="${FFMPEG_ROOT:-}"

resolve_ffmpeg_root() {
  if [[ -n "$FFMPEG_ROOT" ]]; then
    printf '%s\n' "$FFMPEG_ROOT"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    local ffmpeg_prefix
    ffmpeg_prefix="$(brew --prefix ffmpeg 2>/dev/null || true)"
    if [[ -n "$ffmpeg_prefix" && -d "$ffmpeg_prefix/include" ]]; then
      printf '%s\n' "$ffmpeg_prefix"
      return
    fi
  fi

  for candidate in /opt/homebrew /usr/local; do
    if [[ -f "$candidate/include/libavformat/avformat.h" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  echo "FFmpeg headers/libs not found. Set FFMPEG_ROOT=/path/to/ffmpeg prefix." >&2
  exit 2
}

if [[ -z "$RECEIVER_BIN" ]]; then
  FFMPEG_ROOT="$(resolve_ffmpeg_root)"
  cmake -S "$ROOT_DIR/desktop/windows" -B "$BUILD_DIR" \
    -DFFMPEG_ROOT="$FFMPEG_ROOT" \
    -DPHONECAM_WITH_SOFTCAM=OFF
  cmake --build "$BUILD_DIR" --config Release
  RECEIVER_BIN="$BUILD_DIR/phonecam-receiver"
fi

if [[ ! -x "$RECEIVER_BIN" ]]; then
  echo "Receiver binary not found or not executable: $RECEIVER_BIN" >&2
  exit 2
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$RECEIVER_BIN" "$APP_DIR/Contents/MacOS/phonecam-receiver"
chmod +x "$APP_DIR/Contents/MacOS/phonecam-receiver"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>PhoneCam Receiver</string>
  <key>CFBundleExecutable</key>
  <string>phonecam-receiver</string>
  <key>CFBundleIdentifier</key>
  <string>com.phonecam.receiver.dev</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PhoneCam Receiver</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cat > "$APP_DIR/Contents/Resources/README.txt" <<'README'
PhoneCam Receiver.app is a macOS development preview wrapper around the native receiver.

Opening the app runs the receiver with its default behavior: wait briefly for an Android PhoneCam LAN discovery beacon, then show the Cocoa preview window for the decoded RTSP stream.

This app is not the Windows MVP virtual webcam backend. It does not register a DirectShow camera, does not prove OBS/browser webcam enumeration on Windows, and does not replace the Windows Softcam evidence workflow.
README

echo "Mac receiver app: $APP_DIR"
echo "This app is Mac development evidence only; it does not prove Windows DirectShow/OBS enumeration."
