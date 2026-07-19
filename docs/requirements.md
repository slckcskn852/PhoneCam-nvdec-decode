# Requirements

## Product Goal

Use an Android or iOS phone as a high-performance Windows or macOS virtual webcam over local network (Wi-Fi or USB connection).

## Primary Use Case

- Local area network (LAN) or direct USB connection.
- Wi-Fi 6 or strong 5 GHz Wi-Fi preferred for wireless; USB connection for zero-interference wired fallback.
- Receiver runs on Windows (DirectShow virtual camera) or macOS (Camera Extension) and exposes a virtual webcam.

## Media & Transport Requirements

### 1. High-Performance 4K60 UDP path (Production)
- **Video Format:** 4K60 HEVC (H.265) streaming with low-latency hardware encoding/decoding.
- **Protocol:** RTP over UDP (default port `5004`) based on RFC 7798.
- **ABR (Adaptive Bitrate):** Dynamic bitrate adjustment based on receiver feedback (loss fraction and jitter). Downscales profile or lowers bitrate when loss exceeds threshold; steps up when network is stable.
- **NACK Queues:** Retransmission mechanism for recovering dropped packets over lossy wireless connections.
- **Jitter Buffer:** Playout smoothing with configurable delay (default `50 ms`) on the receiver.

### 2. Legacy RTSP-over-TCP Fallback
- **Protocol:** RTSP server on the phone (port `8554`).
- **Use Case:** Legacy fallback for compatibility or when UDP control/media traffic is blocked.

### 3. USB Cable Wired Fallback
- **Protocol:** Single multiplexed TCP stream over USB (using ADB port forwarding for Android, `usbmuxd` for iOS) on port `47822`.
- **Multiplexing:** Length-prefixed framing to separate Control (`0x01`) and Media (`0x02`) channels.
- **Optimizations:** Jitter buffer target set to `0 ms` (minimum latency) since TCP is lossless; NACK and retransmissions disabled.

## Platform Requirements

### Senders (Android & iOS)
- **Android:** Android 7.0+ with Camera2 API and hardware MediaCodec HEVC encoder.
- **iOS:** iOS 15+ with AVFoundation and VideoToolbox HEVC hardware encoder.
- **Orientation:** Lock to fixed landscape for streaming. Handle front/back camera orientation swaps seamlessly.
- **Discovery:** Broadcast UDP beacons on port `47821` every 1 second, containing device name, streaming URL, parameters, and a six-digit pairing code.

### Receivers (Windows & macOS)
- **Windows:** Windows 10/11 DirectShow Softcam virtual camera. Direct preview via Win32.
- **macOS:** macOS 12+ CMIO (CoreMedia I/O) camera extension layout. Native preview.
- **Auto-Discovery:** Listen on port `47821` to auto-detect senders on LAN, filter by pairing code, and auto-negotiate FPS.

## Non-Goals For This MVP
- Remote internet streaming over WAN.
- TURN/WebRTC NAT traversal.
- Audio forwarding.
- OBS source code reuse (must maintain MIT-compatible licensing).

## Future Work
- SRT transport mode for pro-video environments.
- Signed installer packaging pipeline for both platforms.
- Android thermal auto-downgrade integration.
- QR pairing UI built on top of the pairing-code flow.

