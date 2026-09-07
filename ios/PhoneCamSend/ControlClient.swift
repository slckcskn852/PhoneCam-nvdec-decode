import Foundation
import Network

public struct Ladder: Codable, Equatable {
    public let width: Int
    public let height: Int
    public let fps: Int
    public let bitrateBps: Int
    public let name: String
    
    public init(width: Int, height: Int, fps: Int, bitrateBps: Int, name: String) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateBps = bitrateBps
        self.name = name
    }
    
    public var summary: String {
        return "\(width)x\(height)@\(fps) \(bitrateBps / 1_000_000)Mbps"
    }
}

public protocol ControlClientDelegate: AnyObject {
    func controlClientDidReceiveStart(_ client: ControlClient, ladder: Ladder)
    func controlClientDidReceiveStop(_ client: ControlClient)
    func controlClientDidReceiveNack(_ client: ControlClient, seqs: [Int])
    func controlClientDidReceivePli(_ client: ControlClient)
    func controlClientDidChangeBitrate(_ client: ControlClient, bitrateBps: Int)
    func controlClientDidChangeLadder(_ client: ControlClient, newLadder: Ladder)
}

public class ControlClient {
    public static let controlPort: UInt16 = 47822
    
    public weak var delegate: ControlClientDelegate?
    
    public private(set) var negotiatedLadder: Ladder?
    public private(set) var activeLadder: Ladder?
    public private(set) var currentBitrate: Int = 0
    public private(set) var consecutiveGoodReports: Int = 0
    
    private var udpListener: NWListener?
    private var tcpListener: NWListener?
    private var tcpConnection: NWConnection?
    
    private let queue = DispatchQueue(label: "com.phonecam.stream4k.control")
    private let queueKey = DispatchSpecificKey<Bool>()
    private let sendLock = NSLock()
    private var tcpBytesInFlight = 0
    private var tcpOverloaded = false
    private var udpConnection: NWConnection?
    private var running = false
    private var receiverEndpoint: NWEndpoint?
    private var connectionGeneration = 0
    public var onConnectionStatus: ((String) -> Void)?
    private var lastMessageTime: Date = Date()
    private var keepaliveTimer: DispatchSourceTimer?
    
    public static let candidateLadders: [Ladder] = [
        Ladder(width: 3840, height: 2160, fps: 60, bitrateBps: 35_000_000, name: "4K60 HEVC"),
        Ladder(width: 3840, height: 2160, fps: 30, bitrateBps: 25_000_000, name: "4K30 HEVC fallback"),
        Ladder(width: 1920, height: 1080, fps: 240, bitrateBps: 45_000_000, name: "1080p240 HEVC"),
        Ladder(width: 1920, height: 1080, fps: 120, bitrateBps: 28_000_000, name: "1080p120 HEVC"),
        Ladder(width: 1920, height: 1080, fps: 60, bitrateBps: 12_000_000, name: "1080p60 HEVC fallback"),
        Ladder(width: 1920, height: 1080, fps: 30, bitrateBps: 8_000_000, name: "1080p30 HEVC fallback")
    ]
    
    public private(set) var availableLadders: [Ladder] = []
    public private(set) var mediaHost: String?
    public private(set) var mediaPort: UInt16 = 5004

    public init() { queue.setSpecific(key: queueKey, value: true) }

    private func onQueue<T>(_ action: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true { return action() }
        return queue.sync(execute: action)
    }
    
    public func start() { onQueue { startOnQueue() } }
    private func startOnQueue() {
        guard !running else { return }
        running = true
        availableLadders = CaptureEncoder.availableLadders()
        
        lastMessageTime = Date()
        startUdpListener()
        startTcpListener()
        startKeepaliveMonitor()
    }
    
    public func connect(to endpoint: NWEndpoint) { onQueue {
        stopOnQueue()
        running = true
        availableLadders = CaptureEncoder.availableLadders()
        receiverEndpoint = endpoint
        startKeepaliveMonitor()
        connectReceiverOnQueue()
    } }

    private func connectReceiverOnQueue() {
        guard running, let endpoint = receiverEndpoint, tcpConnection == nil else { return }
        onConnectionStatus?("Connecting to computer… Keep the receiver open.")
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let connection = NWConnection(to: endpoint, using: NWParameters(tls: nil, tcp: tcp))
        handleTcpConnection(connection, reverse: true)
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak connection] in
            guard let self = self, let connection = connection, self.tcpConnection === connection else { return }
            if case .ready = connection.state { return }
            connection.cancel()
        }
    }

    public func stop() { onQueue { stopOnQueue() } }
    private func stopOnQueue() {
        running = false
        receiverEndpoint = nil
        connectionGeneration += 1
        udpConnection?.cancel()
        udpConnection = nil
        activeLadder = nil
        negotiatedLadder = nil
        
        udpListener?.cancel()
        udpListener = nil
        
        tcpListener?.cancel()
        tcpListener = nil
        
        tcpConnection?.cancel()
        tcpConnection = nil
        
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
    }
    
    // One enqueue and NWConnection send per access unit, preserving all RTP boundaries.
    public func sendTcpMedia(packets: [Data]) {
        guard !packets.isEmpty, packets.allSatisfy({ !$0.isEmpty && $0.count <= 65535 }) else { return }
        let bytes = packets.reduce(0) { $0 + $1.count + 6 }
        sendLock.lock()
        guard !tcpOverloaded else { sendLock.unlock(); return }
        if tcpBytesInFlight + bytes > 4 * 1024 * 1024 {
            tcpOverloaded = true
            sendLock.unlock()
            queue.async { [weak self] in self?.tcpConnection?.cancel() }
            return
        }
        tcpBytesInFlight += bytes
        sendLock.unlock()
        // Snapshot the session before enqueuing so old camera frames cannot enter a new session.
        let generation = onQueue { connectionGeneration }
        var frame = Data(capacity: bytes)
        for packet in packets {
            frame.append(contentsOf: [2, 0])
            var length = UInt32(packet.count).bigEndian
            withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
            frame.append(packet)
        }
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.running, self.connectionGeneration == generation, let connection = self.tcpConnection else {
                self.releaseSendBytes(bytes); return
            }
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                self?.releaseSendBytes(bytes)
                if error != nil { connection.cancel() }
            })
        }
    }
    private func releaseSendBytes(_ bytes: Int) {
        sendLock.lock(); tcpBytesInFlight -= bytes; sendLock.unlock()
    }
    public var isTcpConnected: Bool { onQueue { tcpConnection != nil } }
    public var destination: (String, UInt16)? { onQueue { mediaHost.map { ($0, mediaPort) } } }

    private func startUdpListener() {
        do {
            let listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: Self.controlPort)!)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleUdpConnection(connection)
            }
            listener.start(queue: queue)
            self.udpListener = listener
            print("ControlClient: UDP listener started on port \(Self.controlPort)")
        } catch {
            print("ControlClient: Failed to start UDP listener: \(error)")
        }
    }
    
    private func startTcpListener() {
        do {
            let tcp = NWProtocolTCP.Options()
            tcp.noDelay = true
            let listener = try NWListener(using: NWParameters(tls: nil, tcp: tcp), on: NWEndpoint.Port(rawValue: Self.controlPort)!)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleTcpConnection(connection)
            }
            listener.start(queue: queue)
            self.tcpListener = listener
            print("ControlClient: TCP listener started on port \(Self.controlPort)")
        } catch {
            print("ControlClient: Failed to start TCP listener: \(error)")
        }
    }
    
    private func handleUdpConnection(_ connection: NWConnection) {
        guard running, udpConnection == nil, tcpConnection == nil else { connection.cancel(); return }
        udpConnection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection, self.udpConnection === connection else { return }
            if case .failed = state { self.udpConnection = nil }
            if case .cancelled = state { self.udpConnection = nil }
        }
        connection.start(queue: queue)
        receiveUdpPacket(connection)
    }
    
    private func receiveUdpPacket(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] (content: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
            guard let self = self, self.running, self.udpConnection === connection else { return }
            if let data = content, !data.isEmpty {
                self.lastMessageTime = Date()
                if let response = self.processControlMessage(data, peer: connection.endpoint) {
                    connection.send(content: response, completion: .contentProcessed({ _ in }))
                }
            }
            if error == nil {
                self.receiveUdpPacket(connection)
            }
        }
    }
    
    private func handleTcpConnection(_ connection: NWConnection, reverse: Bool = false) {
        guard running, tcpConnection == nil, udpConnection == nil else { connection.cancel(); return }
        sendLock.lock(); tcpOverloaded = false; sendLock.unlock()
        connectionGeneration += 1
        tcpConnection = connection
        lastMessageTime = Date()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection, self.tcpConnection === connection else { return }
            switch state {
            case .ready:
                if reverse {
                    connection.send(content: Data("PHONECAM/2\n".utf8), completion: .contentProcessed { error in
                        if error != nil { connection.cancel() }
                        else { self.receiveTcpFrame(connection) }
                    })
                } else { self.receiveTcpFrame(connection) }
            case .failed, .cancelled:
                self.tcpConnection = nil
                self.activeLadder = nil
                self.connectionGeneration += 1
                let token = self.connectionGeneration
                DispatchQueue.main.async { self.delegate?.controlClientDidReceiveStop(self) }
                if self.running, self.receiverEndpoint != nil {
                    self.onConnectionStatus?("Connection lost. Reconnecting… Check the PC code and allow home-network access on the computer.")
                    self.queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                        guard let self = self, self.connectionGeneration == token else { return }
                        self.connectReceiverOnQueue()
                    }
                }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveTcpFrame(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 6, maximumLength: 6) { [weak self] (content: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
            guard let self = self, self.running, self.tcpConnection === connection, let header = content, header.count == 6 else {
                connection.cancel()
                return
            }
            
            let channel = header[0]
            let length = (UInt32(header[2]) << 24) |
                         (UInt32(header[3]) << 16) |
                         (UInt32(header[4]) << 8) |
                         UInt32(header[5])
            
            guard channel == 1, header[1] == 0, length > 0, length <= 65535 else {
                connection.cancel()
                return
            }
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { [weak self] (payload: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
                guard let self = self, self.running, self.tcpConnection === connection, let body = payload, body.count == Int(length) else {
                    connection.cancel()
                    return
                }
                
                self.lastMessageTime = Date()
                if channel == 0x01 { // Control
                    if let response = self.processControlMessage(body, peer: connection.endpoint) {
                        var respHeader = Data(count: 6)
                        respHeader[0] = 0x01
                        respHeader[1] = 0x00
                        let respLength = UInt32(response.count)
                        respHeader[2] = UInt8((respLength >> 24) & 0xFF)
                        respHeader[3] = UInt8((respLength >> 16) & 0xFF)
                        respHeader[4] = UInt8((respLength >> 8) & 0xFF)
                        respHeader[5] = UInt8(respLength & 0xFF)
                        
                        let frame = respHeader + response
                        connection.send(content: frame, completion: .contentProcessed({ _ in }))
                    }
                }
                
                if error == nil {
                    self.receiveTcpFrame(connection)
                }
            }
        }
    }
    
    private func processControlMessage(_ data: Data, peer: NWEndpoint) -> Data? {
        guard data.count <= 65535, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        
        var reply: [String: Any]? = nil
        
        switch type {
        case "ping":
            reply = [
                "version": "1.0",
                "type": "pong",
                "device_name": "iOS Phone",
                "capabilities": [
                    "ladder": availableLadders.map { [
                        "width": $0.width,
                        "height": $0.height,
                        "fps": $0.fps,
                        "bitrate": $0.bitrateBps
                    ] }
                ],
                "state": (activeLadder != nil) ? "streaming" : "idle"
            ]
            
        case "connect":
            if let selected = json["selected_ladder"] as? [String: Any],
               let w = selected["width"] as? Int,
               let h = selected["height"] as? Int,
               let fps = selected["fps"] as? Int {
                
                let requestedPort = json["stream_port"] as? Int ?? 5004
                let isTcp = (json["transport"] as? String) == "tcp"
                guard isTcp || (1...65535).contains(requestedPort) else { return nil }
                if case .hostPort(let host, _) = peer { mediaHost = "\(host)" }
                else if isTcp { mediaHost = "localhost" } // TCP uses the existing connection, not a UDP destination.
                else { return nil }
                mediaPort = isTcp ? 5004 : UInt16(requestedPort)
                let automatic = w == 0 && h == 0 && fps == 0
                let preferred = availableLadders.first { $0.width == 1920 && $0.height == 1080 && $0.fps == 60 }
                    ?? availableLadders.first { $0.width == 1920 && $0.height == 1080 && $0.fps == 30 }
                    ?? availableLadders.first
                if let matched = automatic ? preferred : availableLadders.first(where: { $0.width == w && $0.height == h && $0.fps == fps }) {
                    activeLadder = matched
                    negotiatedLadder = matched
                    currentBitrate = matched.bitrateBps
                    consecutiveGoodReports = 0
                    
                    reply = [
                        "version": "1.0",
                        "type": "connect_ack",
                        "status": "success",
                        "selected_ladder": [
                            "width": matched.width,
                            "height": matched.height,
                            "fps": matched.fps,
                            "bitrate": matched.bitrateBps
                        ]
                    ]
                } else {
                    reply = [
                        "version": "1.0",
                        "type": "connect_ack",
                        "status": "error",
                        "reason": "unsupported_ladder"
                    ]
                }
            }
            
        case "start":
            if let ladder = activeLadder {
                DispatchQueue.main.async {
                    self.delegate?.controlClientDidReceiveStart(self, ladder: ladder)
                }
                reply = [
                    "version": "1.0",
                    "type": "start_ack",
                    "status": "success"
                ]
            } else {
                reply = [
                    "version": "1.0",
                    "type": "start_ack",
                    "status": "error"
                ]
            }
            
        case "stop":
            activeLadder = nil
            DispatchQueue.main.async {
                self.delegate?.controlClientDidReceiveStop(self)
            }
            reply = [
                "version": "1.0",
                "type": "stop_ack",
                "status": "success"
            ]
            
        case "nack":
            if let seqs = json["seqs"] as? [Int] {
                DispatchQueue.main.async {
                    self.delegate?.controlClientDidReceiveNack(self, seqs: seqs)
                }
            }
            
        case "pli":
            DispatchQueue.main.async {
                self.delegate?.controlClientDidReceivePli(self)
            }
            
        case "feedback":
            if let lossFraction = json["loss_fraction"] as? Double,
               let jitterMs = json["jitter_ms"] as? Double {
                handleBitrateAdaptation(lossFraction: lossFraction, jitterMs: jitterMs)
            }
            
        default:
            break
        }
        
        if let reply = reply {
            return try? JSONSerialization.data(withJSONObject: reply)
        }
        return nil
    }
    
    private func handleBitrateAdaptation(lossFraction: Double, jitterMs: Double) {
        guard let ladder = activeLadder else { return }
        
        if lossFraction > 0.02 {
            consecutiveGoodReports = 0
            let minBitrate = ladder.bitrateBps / 2
            if currentBitrate > minBitrate {
                currentBitrate = max(Int(Double(currentBitrate) * 0.9), minBitrate)
                DispatchQueue.main.async {
                    self.delegate?.controlClientDidChangeBitrate(self, bitrateBps: self.currentBitrate)
                }
                print("ControlClient ABR: Decreased bitrate to \(currentBitrate) Bps")
            } else {
                if let nextLadder = getNextLowerLadder(current: ladder) {
                    print("ControlClient ABR: Stepping down ladder to \(nextLadder.summary)")
                    activeLadder = nextLadder
                    currentBitrate = nextLadder.bitrateBps
                    DispatchQueue.main.async {
                        self.delegate?.controlClientDidChangeLadder(self, newLadder: nextLadder)
                    }
                }
            }
        } else if lossFraction < 0.005 && jitterMs < 10.0 {
            consecutiveGoodReports += 1
            if consecutiveGoodReports >= 10 {
                consecutiveGoodReports = 0
                if currentBitrate >= ladder.bitrateBps {
                    if let negotiated = negotiatedLadder, isLadderLowerThan(ladder, negotiated) {
                        if let nextLadder = getNextHigherLadder(current: ladder) {
                            if !isLadderLowerThan(negotiated, nextLadder) {
                                print("ControlClient ABR: Stepping up ladder to \(nextLadder.summary)")
                                activeLadder = nextLadder
                                currentBitrate = nextLadder.bitrateBps
                                DispatchQueue.main.async {
                                    self.delegate?.controlClientDidChangeLadder(self, newLadder: nextLadder)
                                }
                            }
                        }
                    }
                } else {
                    currentBitrate = min(Int(Double(currentBitrate) * 1.1), ladder.bitrateBps)
                    DispatchQueue.main.async {
                        self.delegate?.controlClientDidChangeBitrate(self, bitrateBps: self.currentBitrate)
                    }
                    print("ControlClient ABR: Increased bitrate to \(currentBitrate) Bps")
                }
            }
        } else {
            consecutiveGoodReports = 0
        }
    }
    
    private func getNextLowerLadder(current: Ladder) -> Ladder? {
        if current.width == 3840 && current.height == 2160 && current.fps == 60 {
            return availableLadders.first(where: { $0.width == 3840 && $0.height == 2160 && $0.fps == 30 })
        } else if current.width == 3840 && current.height == 2160 && current.fps == 30 {
            return availableLadders.first(where: { $0.width == 1920 && $0.height == 1080 && $0.fps == 60 })
        }
        return nil
    }
    
    private func getNextHigherLadder(current: Ladder) -> Ladder? {
        if current.width == 1920 && current.height == 1080 && current.fps == 60 {
            return availableLadders.first(where: { $0.width == 3840 && $0.height == 2160 && $0.fps == 30 })
        } else if current.width == 3840 && current.height == 2160 && current.fps == 30 {
            return availableLadders.first(where: { $0.width == 3840 && $0.height == 2160 && $0.fps == 60 })
        }
        return nil
    }
    
    private func isLadderLowerThan(_ a: Ladder, _ b: Ladder) -> Bool {
        if a.width < b.width { return true }
        if a.width == b.width && a.height < b.height { return true }
        if a.width == b.width && a.height == b.height && a.fps < b.fps { return true }
        return false
    }
    
    private func startKeepaliveMonitor() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.activeLadder != nil && Date().timeIntervalSince(self.lastMessageTime) > 5.0 {
                self.tcpConnection?.cancel()
                self.udpConnection?.cancel()
                self.udpConnection = nil
                print("ControlClient: Keepalive timeout. Stopping stream.")
                self.activeLadder = nil
                DispatchQueue.main.async {
                    self.delegate?.controlClientDidReceiveStop(self)
                }
            }
        }
        self.keepaliveTimer = timer
        timer.resume()
    }
}
