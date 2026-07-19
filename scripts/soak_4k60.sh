#!/bin/bash
# 4K60 Synthetic Soak Test Runner

DURATION=60
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --duration) DURATION="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Locate build binaries
RECEIVER_BIN=""
SENDER_BIN=""
BUILD_DIR=""
for dir in "$REPO_DIR/desktop/build/macos" "$REPO_DIR/desktop/build" "$REPO_DIR/build/macos" "$REPO_DIR/desktop/build/windows" "$REPO_DIR/build"; do
    if [ -f "$dir/phonecam-soak-sender" ]; then
        SENDER_BIN="$dir/phonecam-soak-sender"
        BUILD_DIR="$dir"
        if [ -f "$dir/macos/phonecam-receiver" ]; then
            RECEIVER_BIN="$dir/macos/phonecam-receiver"
        elif [ -f "$dir/phonecam-receiver" ]; then
            RECEIVER_BIN="$dir/phonecam-receiver"
        fi
        if [ -n "$RECEIVER_BIN" ]; then
            break
        fi
    fi
done

if [ -z "$RECEIVER_BIN" ] || [ -z "$SENDER_BIN" ]; then
    echo "Error: Binaries phonecam-receiver and phonecam-soak-sender not found in build directory!"
    exit 1
fi

HEVC_FILE="$BUILD_DIR/test_4k60.hevc"
if [ ! -f "$HEVC_FILE" ]; then
    echo "Generating pre-encoded 5-second 4K60 HEVC test pattern loop..."
    ffmpeg -f lavfi -i testsrc2=size=3840x2160:rate=60 -c:v hevc_videotoolbox -b:v 35M -t 5 -pix_fmt yuv420p -an "$HEVC_FILE" -y
fi

run_soak() {
    LOSS_PCT="$1"
    DESC="$2"
    
    echo "======================================================================"
    echo "Running Soak Test: $DESC (Duration: ${DURATION}s, Loss Injected: ${LOSS_PCT}%)"
    echo "======================================================================"
    
    RECEIVER_LOG="$BUILD_DIR/receiver_soak_loss_${LOSS_PCT}.log"
    rm -f "$RECEIVER_LOG"
    
    # Start soak sender
    echo "Starting Soak Sender..."
    SENDER_LOG="$BUILD_DIR/sender_soak_loss_${LOSS_PCT}.log"
    rm -f "$SENDER_LOG"
    "$SENDER_BIN" --file "$HEVC_FILE" --inject-loss "$LOSS_PCT" > "$SENDER_LOG" 2>&1 &
    SENDER_PID=$!
    
    # Wait for sender to start and bind its control socket
    echo "Waiting for sender control socket to bind..."
    for i in {1..50}; do
        if [ -f "$SENDER_LOG" ] && grep -q "Waiting for control connection" "$SENDER_LOG"; then
            break
        fi
        sleep 0.1
    done
    
    # Start receiver in headless mode
    echo "Starting Headless Receiver..."
    "$RECEIVER_BIN" --connect 127.0.0.1 --headless --duration "$DURATION" --stats-interval 1.0 > "$RECEIVER_LOG" 2>&1
    RC_RECEIVER=$?
    
    # Stop sender if it's still running
    kill $SENDER_PID 2>/dev/null
    wait $SENDER_PID 2>/dev/null
    
    echo "Receiver exited with code: $RC_RECEIVER"
    
    # Parse receiver logs for stats
    JSON_LINE=$(tail -n 5 "$RECEIVER_LOG" | grep '"duration_sec"')
    if [ -z "$JSON_LINE" ]; then
        echo "FAIL: No JSON summary found in receiver log!"
        echo "--- LOG BEGIN ---"
        cat "$RECEIVER_LOG"
        echo "--- LOG END ---"
        return 1
    fi
    
    echo "Receiver Summary: $JSON_LINE"
    
    DECODE_FPS=$(echo "$JSON_LINE" | sed -n 's/.*"avg_decode_fps": \([0-9.]*\).*/\1/p')
    LOSS_PCT_VAL=$(echo "$JSON_LINE" | sed -n 's/.*"loss_percent": \([0-9.]*\).*/\1/p')
    SUCCESS=$(echo "$JSON_LINE" | sed -n 's/.*"success": \([a-z]*\).*/\1/p')
    
    # Check targets: decode_fps >= 55.0 and post-NACK loss < 1%
    if (( $(echo "$DECODE_FPS < 55.0" | bc -l) )); then
        echo "FAIL: Average decode FPS ($DECODE_FPS) was less than 55.0!"
        return 1
    fi
    
    if (( $(echo "$LOSS_PCT_VAL >= 1.0" | bc -l) )); then
        echo "FAIL: Post-NACK loss percentage ($LOSS_PCT_VAL%) was >= 1.0%!"
        return 1
    fi
    
    if [ "$SUCCESS" != "true" ] || [ $RC_RECEIVER -ne 0 ]; then
        echo "FAIL: Receiver reported failure or exited with non-zero code!"
        return 1
    fi
    
    echo "PASS: $DESC targets met."
    return 0
}

# Run 1: Clean (0% loss)
run_soak 0.0 "Clean Channel"
RC_CLEAN=$?

# Run 2: Lossy (2% loss)
run_soak 2.0 "2% Injected Loss Channel"
RC_LOSSY=$?

if [ $RC_CLEAN -ne 0 ] || [ $RC_LOSSY -ne 0 ]; then
    echo "SOAK TESTS FAILED!"
    exit 1
fi

echo "ALL SOAK TESTS PASSED SUCCESSFULLY!"
exit 0
