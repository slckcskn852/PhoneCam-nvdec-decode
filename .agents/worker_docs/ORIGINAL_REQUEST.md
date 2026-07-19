## 2026-07-19T18:31:23Z
You are a Technical Writer worker. Your task is to update and create the documentation for PhoneCamRedux.

## Requirements
1. **Create `docs/verification-4k60.md`**:
   - Title: "PhoneCam 4K60 Rebuild Verification Report".
   - Include the Verification Results from the latest macOS and Android unit/conformance tests:
     - Android unit tests: 49 tests passed (including `RtpHevcPacketizerTest` and `Stream4kControllerTest` ABR logic).
     - Desktop macOS CTest: `conformance-tests` passed successfully.
     - iOS Simulator unit tests: 15 tests passed (`** TEST SUCCEEDED **`). iOS device target compiled successfully (`** BUILD SUCCEEDED **`).
   - Add step-by-step instructions for the **Synthetic Soak Test**:
     - How to run `ffmpeg` to stream 4K60 HEVC over UDP to localhost port 5004:
       `ffmpeg -re -f lavfi -i testsrc2=size=3840x2160:rate=60 -c:v libx265 -preset ultrafast -tune zerolatency -f rtp rtp://127.0.0.1:5004`
     - How to launch the receiver to ingest it:
       `./build/macos/phonecam-receiver --ip 127.0.0.1 --fps 60`
     - Document that it sustains >= 55 fps with < 1% loss.
   - Add step-by-step user-run commands for **Actual Hardware Verification**:
     - **WiFi UDP mode**: Select 4K60 UDP in the Android app, enter the Mac's IP address, start streaming, and run the receiver on Mac (`./phonecam-receiver --ip <android_ip> --fps 60`).
     - **USB TCP mode**: Connect the phone via USB. Run `adb forward tcp:47822 tcp:47822`. Start the stream in USB/TCP mode on the phone. Start the receiver in TCP mode: `./phonecam-receiver --ip 127.0.0.1 --tcp --fps 60`.
2. **Update `docs/requirements.md`**:
   - Update the requirements to reflect the 4K60 UDP production path, RTSP legacy fallback, and USB cable wired fallback.
3. **Update `docs/architecture.md`**:
   - Update the architecture design document to describe the UDP control and media pathways, TCP cableFallback multiplexing, ABR stateful adjustments (5-second window, 10% steps), playout Jitter Buffer (50ms delay), and macOS CMIO camera extension layout. Include macOS build and code signing instructions.
4. **Update `README.md`**:
   - Refresh the README to show the new multi-platform capabilities (Android, iOS, Windows, macOS), the UDP/TCP 4K60 protocol features (ABR, NACK, jitter buffer), and standard build commands for all platforms.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your working directory is `/Users/alpyalay/Documents/GitHub/PhoneCamRedux/.agents/worker_docs`.
Please write your handoff report to `/Users/alpyalay/Documents/GitHub/PhoneCamRedux/.agents/worker_docs/handoff.md` and send a message when done.
