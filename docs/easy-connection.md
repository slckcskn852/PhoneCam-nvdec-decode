# Connect your phone to your computer

1. Open `phonecam-receiver.exe` on Windows. Leave the connection window open. If Windows asks, allow access on your **Private** home network. The **Allow home network** button runs the bundled firewall helper after Windows administrator approval.
2. Open PhoneCam on Android or iOS. Tap **Find my computer**, then select the computer name. Allow camera and local-network access when asked.
3. Choose **PhoneCam Virtual Camera** in your calling or recording app if the Windows virtual-camera component is installed. Keep PhoneCam in the foreground on your phone.

The receiver chooses 1080p60 when supported, then 1080p30, then another exposed mode. Camera/encoder capability checks still apply. For a specific mode, start the receiver with `--listen --width 1920 --height 1080 --fps 240` (or another supported combination).

If the computer does not appear, enter the **PC code** shown in the receiver, or its IPv4 address. A custom listener port can be entered as `192.168.1.42:47824`. PC codes represent addresses and catch common typing mistakes; they are not passwords. Codes change if the computer's address changes. With multiple network adapters, try the code beside the computer's home-network address. Use this unencrypted transport on a trusted network.

The app retries a lost connection while it remains open. **Stop connection**, backgrounding the phone app, or closing the PC preview stops the current session. Reopening the receiver lets an already reconnecting phone connect again. No account or router port forwarding is required on a reachable home LAN.

## Home-network arrangements

| Arrangement | How to connect |
| --- | --- |
| Same Wi-Fi/router; PC on Ethernet | Find my computer should list the receiver when discovery and the connection are allowed. |
| Different Wi-Fi names, mesh nodes, or a second router in access-point/bridge mode | Discovery works when these devices share the same LAN and multicast is permitted. Otherwise try the PC code. |
| Phone behind a second router, PC on the upstream home LAN | Enter the upstream PC's code/address. The phone initiates TCP toward the PC, so this often works without inbound forwarding on the phone's router. Routing/firewall policy must allow it. |
| PC behind a second NAT router, phone upstream; separate isolated subnets | Put both devices on the same main network, use access-point/bridge mode, or configure a route as appropriate for your equipment. A code cannot create reachability. |
| Guest Wi-Fi, AP/client isolation, VPN blocking LAN traffic | Switch to the main home network or allow local traffic in the network/VPN configuration. Discovery and manual connections can both be blocked. |

Bonjour/mDNS normally stays on the local link; routed networks may need manual addressing. See [Apple's Bonjour FAQ](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/NetServices/Articles/faq.html). Windows uses the built-in [DNS service registration API](https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsserviceregister); Android uses [Network Service Discovery](https://developer.android.com/reference/android/net/nsd/NsdManager). There is no internet relay or automatic router reconfiguration.

## Latency behavior

The easy connection uses native TCP with Nagle disabled and no intentional receiver playout delay. TCP can still accumulate delay under loss or a slow link. iOS batches a complete encoded access unit into one network send, with the existing 4 MiB queued-byte limit. Android also sends complete access units through its bounded sender queue.

For advanced UDP, the receiver starts with a 10 ms playout delay instead of the previous 50 ms. It updates the delay every 500 ms, grows quickly for jitter/loss, and shrinks gradually to a 5 ms floor (50 ms maximum). `--jitter-ms N` selects a fixed delay instead. The change removes 40 ms of initial configured buffering; it is not a measured 40 ms reduction in camera-to-screen latency.

Compressed queues reject old backlog when new frames arrive (80 ms default age limit; longer fixed playout settings retain their requested delay), retain byte/frame limits, and wait for an IDR after damage or overflow so missing reference frames do not create persistent corruption. Decoded output still keeps the newest pending frame. For lowest practical delay, use a stable Wi-Fi link and Ethernet for the PC where available; higher frame rates and resolution still depend on the hardware and consuming app.

## Advanced compatibility

The old phone-listener workflows remain under **Advanced connection options** in the mobile apps. Enable receiver access for direct `tcp://PHONE_IP:47822` or `udp://PHONE_IP:5004` commands. Android's RTSP server, six-digit phone selector, quality profiles, and orientation controls remain in that panel. These six-digit selectors are separate from the new PC address codes.

The default PC listener uses TCP 47823. The firewall helper installs app-scoped Private-profile rules for this port, Bonjour UDP 5353, and existing native/RTSP paths. For custom ports, configure the corresponding firewall rule yourself. The Windows GUI and firewall/DNS-SD APIs require a physical Windows check; local macOS builds validate shared code, not Windows firewall behavior.
