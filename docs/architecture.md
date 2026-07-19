# Architecture

## Direction

PhoneCamRedux is designed for low-latency, high-fidelity 4K60 HEVC video streaming. The production transport pathway leverages a stateful RTP/UDP custom control and media protocol optimized for local Wi-Fi networks. It also provides a multiplexed TCP cable fallback for wired USB connections, and a legacy RTSP-over-TCP pathway for compatibility.

## Pipeline

### Wireless Production Path (UDP)
```text
Android (Camera2/MediaCodec HEVC) / iOS (AVFoundation/VideoToolbox HEVC)
  |--- RTP Media (UDP Port 5004) -------> Receiver RTP Ingestion (RTP/HEVC) -> Jitter Buffer -> Decoder (FFmpeg)
  |--- Control Channel (UDP Port 47822) <-> JSON Control Handshake, NACK, PLI, ABR Updates
  |--- Discovery Beacon (UDP Port 47821) -> Receiver Discovery Auto-Connect
```

### Wired Fallback Path (USB TCP Multiplex)
```text
Android / iOS
  |--- ADB / usbmuxd Port Forwarding (Port 47822)
  |--- Single Multiplexed TCP Stream
         |--- Channel 0x01: JSON Control
         |--- Channel 0x02: Media RTP Packets
                 -----> Receiver Ingestion (No Jitter Buffer / Lossless) -> Decoder (FFmpeg)
```

### Legacy Fallback Path (RTSP)
```text
Android / iOS
  |--- RTSP Server (TCP Port 8554) ------> Receiver (FFmpeg RTSP client)
```

---

## Media and Control Protocol Details

### 1. UDP Control & Media Pathways
- **Media Pathway (UDP Port 5004):** Raw H.265 (HEVC) NAL units are packetized into RTP packets according to **RFC 7798** and sent over UDP. Packets exceeding the MTU (1400 bytes) are split into Fragmentation Units (FU-A packets, type `49`).
- **Control Pathway (UDP Port 47822):** A bidirectional UDP channel using JSON-formatted frames. It handles:
  - **Capability Handshake:** `ping` / `pong` exchange negotiating video resolution profiles and frame rates.
  - **Session Management:** `connect` / `connect_ack`, `start`, and `stop` requests.
  - **Retransmission Requests (NACK):** When the receiver detects missing sequence numbers, it sends a JSON `nack` containing a list of missing sequences. The sender resends them from its 256-packet history ring buffer.
  - **Keyframe Requests (PLI):** When recovery fails, the receiver requests a keyframe using a JSON `pli` packet, triggering an immediate IDR keyframe generation at the sender encoder.

### 2. TCP CableFallback Multiplexing
When streaming over USB (via `adb forward` or `usbmuxd`), UDP is replaced by a single TCP connection on port `47822` to avoid packet loss. Control and media streams are multiplexed using a 6-byte header:
- **Byte 0 (Channel ID):** `0x01` for Control (JSON), `0x02` for Media (RTP packet).
- **Byte 1 (Reserved):** Set to `0x00`.
- **Bytes 2-5 (Length):** 32-bit big-endian integer representing the payload size.
Because TCP is lossless, NACK and retransmissions are disabled, and the receiver's jitter buffer target is reduced to `0 ms` to achieve minimum latency.

### 3. Stateful ABR (Adaptive Bitrate) Adjustments
To maintain a stable 4K60 stream over fluctuating Wi-Fi connections, the sender dynamically adapts its bitrate and resolution based on feedback sent by the receiver every 500 ms:
- **Bitrate Decrements:** If the reported `loss_fraction > 0.02` (2%), the sender decreases the encoder bitrate by **10%**. If the bitrate floor is reached, it steps down the resolution ladder (e.g., 4K60 -> 4K30 -> 1080p60).
- **Bitrate Increments:** If `loss_fraction < 0.005` (0.5%) and network jitter remains $< 10$ ms over a **5-second window**, the sender increases the encoder bitrate by **10%** (up to the maximum profile cap).

### 4. Playout Jitter Buffer
On the receiver, incoming RTP/UDP packets are queued in a jitter buffer before being sent to the decoder:
- **Default Delay:** `50 ms` target delay to smooth out network jitter and allow time for NACK retransmission cycles.
- **Jitter Tracking:** Calculated continuously using RFC 3550 standard algorithms to schedule timely NACKs.
- **TCP Mode:** Bypassed (target set to `0 ms`) to minimize latency on wired paths.

---

## macOS CoreMedia I/O (CMIO) Camera Extension Layout

To expose the virtual camera natively on macOS (replacing legacy deprecated DirectShow/Quartz virtual cameras), PhoneCamRedux implements Apple's modern CoreMedia I/O (CMIO) System/Camera Extension API.

### Component Structure
1. **Host App (`PhoneCam Receiver`):** A standard macOS app that manages the media ingestion, control connection, and user interface.
2. **Camera Extension (`com.phonecam.redux.Extension`):** Runs as a sandboxed system-level daemon, communicating with the host app via IPC (using XPC or Mach ports).
3. **Stream Pipeline:**
   - Host app receives and decodes HEVC frames into `CVPixelBuffer` objects.
   - Decoded buffers are sent via XPC to the CMIO Extension.
   - The Extension wraps buffers in `CMSampleBuffer` and outputs them to macOS applications via the CoreMedia I/O subsystem.

### macOS Build and Code Signing Instructions

CMIO Camera Extensions require strict code signing and provisioning to be loaded by the macOS system.

#### 1. Building the Receiver & Extension
Using CMake to generate build configurations:
```bash
cmake -S . -B build/macos -G Xcode
cmake --build build/macos --config Release
```

#### 2. Code Signing for Local Development
If you do not have an Apple Developer Account with Camera Extension entitlements, you must sign ad-hoc for local development:
```bash
# Ad-hoc sign the helper executable
codesign --force --sign - --entitlements desktop/macos/ents.plist build/macos/Release/phonecam-receiver

# Ad-hoc sign the Camera Extension bundle
codesign --force --sign - --entitlements desktop/macos/extension.plist build/macos/Release/PhoneCam\ Receiver.app/Contents/Library/SystemExtensions/com.phonecam.redux.Extension.systemextension
```
*Note: To run ad-hoc signed system extensions on macOS, you may need to disable System Integrity Protection (SIP) or enable developer mode on your machine (`systemextensionsctl developer on`).*

#### 3. Code Signing for Distribution
For production deployment, you must sign using an Apple Developer ID Application certificate and provision the extension with the `com.apple.developer.system-extension.install` and `com.apple.security.personal-information.camera` entitlements:
```bash
codesign --force --options runtime --sign "Developer ID Application: Your Name (TEAMID)" \
  --entitlements desktop/macos/extension.plist \
  build/macos/Release/PhoneCam\ Receiver.app/Contents/Library/SystemExtensions/com.phonecam.redux.Extension.systemextension
```

---

## Android Implementation

- **Launcher:** `android/app/src/main/java/com/phonecam/MainActivity.kt`
- **Media Engine:** Leverages standard `MediaCodec` H.265/HEVC hardware encoder combined with custom RTP packetizers.
- **Orientation Control:** Fixed landscape orientation lock. Front/back camera switching retains correct sensor orientation. Tap-to-rotate provides 90-degree adjustments persisting per-camera.

## Windows Implementation

- **DirectShow softcam filter:** Softcam driver registered as `PhoneCam Virtual Camera`.
- **Media Pipeline:** FFmpeg HEVC decoding to `AV_PIX_FMT_BGR24` matching DirectShow's native memory layout.

