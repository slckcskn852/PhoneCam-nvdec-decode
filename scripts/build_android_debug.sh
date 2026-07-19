#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GRADLE_HOME="${GRADLE_USER_HOME:-/private/tmp/phonecam-gradle-home}"
JAVA_TMP_DIR="${JAVA_TMPDIR:-/private/tmp/phonecam-gradle-tmp}"
FORCE_TEST_RERUN="${FORCE_ANDROID_TESTS:-0}"

mkdir -p "$GRADLE_HOME" "$JAVA_TMP_DIR"

cd "$ROOT_DIR/android"
if [[ "$FORCE_TEST_RERUN" == "1" ]]; then
  GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew "-Djava.io.tmpdir=$JAVA_TMP_DIR" :app:testDebugUnitTest --rerun-tasks --console=plain
  GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew "-Djava.io.tmpdir=$JAVA_TMP_DIR" :app:assembleDebug --console=plain
else
  GRADLE_USER_HOME="$GRADLE_HOME" ./gradlew "-Djava.io.tmpdir=$JAVA_TMP_DIR" :app:testDebugUnitTest :app:assembleDebug --console=plain
fi

for result in app/build/test-results/testDebugUnitTest/TEST-*.xml; do
  [[ -f "$result" ]] || continue
  tests="$(sed -nE 's/.*<testsuite[^>]*tests="([^"]*)".*/\1/p' "$result" | head -n 1)"
  failures="$(sed -nE 's/.*<testsuite[^>]*failures="([^"]*)".*/\1/p' "$result" | head -n 1)"
  errors="$(sed -nE 's/.*<testsuite[^>]*errors="([^"]*)".*/\1/p' "$result" | head -n 1)"
  skipped="$(sed -nE 's/.*<testsuite[^>]*skipped="([^"]*)".*/\1/p' "$result" | head -n 1)"
  timestamp="$(sed -nE 's/.*<testsuite[^>]*timestamp="([^"]*)".*/\1/p' "$result" | head -n 1)"
  if [[ -n "$tests" && -n "$failures" && -n "$errors" && -n "$skipped" && -n "$timestamp" ]]; then
    echo "$(basename "$result"): tests=$tests failures=$failures errors=$errors skipped=$skipped timestamp=$timestamp"
  fi
done

echo "APK: $ROOT_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
