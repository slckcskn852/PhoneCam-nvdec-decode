# PhoneCam 4K60 HEVC Streaming Protocol Specification

This document defines the wire protocol for high-performance, low-latency 4K60 HEVC streaming over WiFi and USB cable connections between PhoneCam senders (Android/iOS) and receivers (Windows/macOS).

---

## 1. Media Transport (UDP)

For WiFi streaming, video data is packetized into RTP packets and sent over UDP to the receiver's media port (default: `5004`).

### RTP Packet Format
RTP packets carry HEVC (H.265) payloads according to **RFC 7798**.
- **Payload Type (PT):** `96` (Dynamic HEVC payload type).
- **Marker (M) Bit:** Set to `1` on the last RTP packet of a video access unit (frame); set to `0` otherwise.
- **Timestamp:** 90 kHz clock. Sequence number rollover and timestamp calculations must align with standard RTP.
- **Sequence Number:** 16-bit sequence number, incrementing by 1 for each packet sent.

### HEVC Packetization Modes
- **Single NAL Unit Mode:** If a NAL unit fits entirely within the MTU (default MTU = 1400 bytes, including 12-byte RTP header), it is sent as-is.
- **Fragmentation Unit (FU) Mode:** If a NAL unit exceeds the MTU, it is split into multiple FU packets (Type `49`).
  - **FU Indicator (2 bytes):**
    - Byte 0: `(NAL_Type_FU << 1)` with `F` and `nuh_layer_id` bits copied from the original NAL header.
    - Byte 1: `nuh_temporal_id_plus1` from the original NAL header.
  - **FU Header (1 byte):**
    - Bit 7 (S): Start bit (1 on the first fragment, 0 otherwise).
    - Bit 6 (E): End bit (1 on the last fragment, 0 otherwise).
    - Bits 0-5: Original `nal_unit_type`.
  - **Payload:** Raw NAL unit payload fragment.

---

## 2. Control Channel (UDP Port 47822)

The control channel handles handshakes, state control, keepalives, and reliability feedback (NACK, PLI, ABR). All control packets are JSON payloads.

### JSON Handshake Flow

#### 1. Capability Discovery (PING/PONG)
The client sends a `ping` to discover or check the status of the sender.
- **Client -> Server `PING`**:
  ```json
  {
    "version": "1.0",
    "type": "ping"
  }
  ```
- **Server -> Client `PONG`**:
  ```json
  {
    "version": "1.0",
    "type": "pong",
    "device_name": "Android Phone",
    "capabilities": {
      "ladder": [
        {"width": 3840, "height": 2160, "fps": 60, "bitrate": 35000000},
        {"width": 3840, "height": 2160, "fps": 30, "bitrate": 25000000},
        {"width": 1920, "height": 1080, "fps": 60, "bitrate": 12000000}
      ]
    },
    "state": "idle" // or "streaming"
  }
  ```

#### 2. Session Init (CONNECT)
The client requests to start a session with a specific resolution and frame rate.
- **Client -> Server `connect`**:
  ```json
  {
    "version": "1.0",
    "type": "connect",
    "selected_ladder": {"width": 3840, "height": 2160, "fps": 60},
    "transport": "udp",
    "stream_port": 5004
  }
  ```
- **Server -> Client `connect_ack`**:
  ```json
  {
    "version": "1.0",
    "type": "connect_ack",
    "status": "success", // or "error"
    "selected_ladder": {"width": 3840, "height": 2160, "fps": 60, "bitrate": 35000000}
  }
  ```

#### 3. Stream Control (START/STOP)
- **Client -> Server `start`**:
  ```json
  {
    "version": "1.0",
    "type": "start"
  }
  ```
- **Client -> Server `stop`**:
  ```json
  {
    "version": "1.0",
    "type": "stop"
  }
  ```

---

## 3. Reliability Layer

### NACK Retransmissions
To handle packet loss, the receiver tracks sequence numbers.
- When a gap in RTP sequence numbers is detected (e.g. received packet `N` when `N-1` was expected), the receiver starts a recovery timer for the missing packet(s).
- If a missing packet does not arrive within a short window (e.g. 10 ms), the receiver sends a `nack` control message.
- **NACK Message Format**:
  ```json
  {
    "version": "1.0",
    "type": "nack",
    "seqs": [8001, 8002]
  }
  ```
- **Sender History Buffer:** The sender must maintain a ring buffer of the last `256` transmitted RTP packets. Upon receiving a `nack`, it immediately resends the requested sequence numbers.

### Keyframe Requests (PLI)
If loss is unrecoverable (e.g. missing fragments of a keyframe after max NACK retries), the receiver requests a new keyframe.
- **PLI Message Format**:
  ```json
  {
    "version": "1.0",
    "type": "pli"
  }
  ```
- Upon receipt of a `pli` message, the sender forces the encoder to generate an IDR keyframe (using `PARAMETER_KEY_REQUEST_SYNC_FRAME` on Android or `VTCompressionSessionForceKeyFrame` on iOS).

### Jitter Buffer
The receiver must buffer packet data to smooth out network transit variations.
- **Configurable target delay:** Default `50 ms`.
- Jitter calculation follows RFC 3550:
  \[D(i, j) = (R_j - R_i) - (S_j - S_i)\]
  \[J(i) = J(i-1) + (|D(i-1, i)| - J(i-1))/16\]

### Bitrate Adaptation (ABR)
The receiver reports link quality metrics every `500 ms`.
- **ABR Feedback Message**:
  ```json
  {
    "version": "1.0",
    "type": "feedback",
    "loss_fraction": 0.015, // 1.5% loss since last report
    "jitter_ms": 4.5
  }
  ```
- **Sender Adaptation Logic:**
  - If `loss_fraction > 0.02` (2%), decrease encoder bitrate by 10%. If bitrate reaches the floor of the current resolution, step down the ladder (`4K60` -> `4K30` -> `1080p60`).
  - If `loss_fraction < 0.005` (0.5%) and `jitter_ms < 10.0` for 5 consecutive seconds, increase bitrate by 10% or step up the ladder if it was previously stepped down.

---

## 4. USB Cable Fallback (TCP multiplexing)

For wired connections, a single TCP connection is used for both control messages and media data.

### Connection
- The client connects via TCP to the server's control port `47822` (using `adb forward tcp:47822 tcp:47822` for Android, or `usbmuxd` for iOS).
- Once connected, both control and media messages are sent over this single TCP stream using length-prefixed frames.

### Multiplexed Frame Format
Every frame sent over the TCP socket must be prefixed by a 6-byte header:
```text
+-------------------+-------------------+---------------------------------------+
|  Channel (1 byte) | Reserved (1 byte) |         Length (4 bytes, BE)          |
+-------------------+-------------------+---------------------------------------+
|                                  Payload                                      |
+-------------------------------------------------------------------------------+
```
- **Channel:**
  - `0x01`: Control (JSON message)
  - `0x02`: Media (RTP packet, carrying HEVC slice)
- **Length:** 32-bit big-endian integer specifying the exact size of the payload following the header.

Since TCP is a lossless stream:
- No NACK packets are sent by the client.
- No packet history buffer or retransmissions are required from the sender.
- Jitter buffer target can be set to `0 ms` (minimum latency).

---

## 5. Discovery Protocol

Discovery uses the existing UDP beacon protocol.
- **Port:** `47821`
- **Sender Interval:** Broadcasts every `1` second.
- **Payload Format:** UTF-8 String, fields separated by `|`:
  `PHONECAM|1|<rtsp_url>|<width>|<height>|<fps>|<bitrate>|<device_name>|<pair_code>`
- **Example Payload:**
  `PHONECAM|1|rtsp://192.168.1.100:8554/live|3840|2160|60|35000000|Google Pixel|123456`
