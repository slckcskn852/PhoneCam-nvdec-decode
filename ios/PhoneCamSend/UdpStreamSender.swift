import Foundation
import Network

public class UdpStreamSender {
    public struct Stats {
        public let framesSent: Int64
        public let packetsSent: Int64
        public let bytesSent: Int64
        public let droppedFrames: Int64
        public let fps: Int
        public let mbps: Double
    }
    private struct AccessUnit { let data: Data; let pts: Int64 }
    private let targetIp: String
    private let targetPort: UInt16
    private let packetizer: RtpSwiftPacketizer
    private let onStats: ((Stats) -> Void)?
    private let onKeyFrameNeeded: (() -> Void)?
    private let lock = NSLock()
    private let streamQueue = DispatchQueue(label: "com.phonecam.stream4k.udpsender")
    private var connection: NWConnection?
    private var queue: [AccessUnit] = []
    private var running = false
    private var awaitingKeyFrame = false
    private var sending = false
    private var ready = false
    private var generation = 0
    private var retransmissionsInFlight = 0
    private var framesSent: Int64 = 0, packetsSent: Int64 = 0, bytesSent: Int64 = 0, droppedFrames: Int64 = 0
    private var lastReport = ProcessInfo.processInfo.systemUptime
    private var reportFrames: Int64 = 0, reportBytes: Int64 = 0

    public init(targetIp: String, targetPort: UInt16, packetizer: RtpSwiftPacketizer,
                onKeyFrameNeeded: (() -> Void)? = nil, onStats: ((Stats) -> Void)? = nil) {
        self.targetIp = targetIp; self.targetPort = targetPort; self.packetizer = packetizer
        self.onKeyFrameNeeded = onKeyFrameNeeded; self.onStats = onStats
    }
    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard !running, let port = NWEndpoint.Port(rawValue: targetPort) else { return }
        running = true
        generation += 1
        let token = generation
        let connection = NWConnection(host: NWEndpoint.Host(targetIp), port: port, using: .udp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.lock.lock()
            guard self.generation == token else { self.lock.unlock(); return }
            if case .ready = state { self.ready = true }
            if case .failed = state { self.running = false; self.queue.removeAll() }
            self.lock.unlock()
            self.drainNext()
        }
        connection.start(queue: streamQueue)
    }
    public func stop() {
        lock.lock()
        running = false; ready = false; sending = false; generation += 1
        let old = connection; connection = nil; queue.removeAll()
        lock.unlock()
        old?.cancel()
    }
    public func onAccessUnit(annexB: Data, ptsUs: Int64, isKeyFrame: Bool = true) {
        lock.lock()
        guard running else { lock.unlock(); return }
        if annexB.count > 8 * 1024 * 1024 || queue.count >= 4 {
            droppedFrames += Int64(queue.count + 1); queue.removeAll(); awaitingKeyFrame = true
            lock.unlock(); onKeyFrameNeeded?(); return
        }
        if awaitingKeyFrame && !isKeyFrame { droppedFrames += 1; lock.unlock(); return }
        if isKeyFrame { awaitingKeyFrame = false }
        queue.append(AccessUnit(data: annexB, pts: ptsUs))
        lock.unlock()
        streamQueue.async { [weak self] in self?.drainNext() }
    }
    private func drainNext() {
        lock.lock()
        guard running, ready, !sending, !queue.isEmpty, let connection = connection else { lock.unlock(); return }
        sending = true
        let unit = queue.removeFirst(), token = generation
        lock.unlock()
        let packets = packetizer.packetize(accessUnit: unit.data, ptsUs: unit.pts)
        sendBatch(packets, offset: 0, connection: connection, token: token)
    }
    // At most 64 Network.framework datagrams are outstanding for the active AU.
    // A completion releases the next batch; the OS queue cannot grow with stream duration.
    private func sendBatch(_ packets: [Data], offset: Int, connection: NWConnection, token: Int) {
        lock.lock()
        guard running && generation == token else { lock.unlock(); return }
        if offset == packets.count {
            framesSent += 1; sending = false
            reportIfDueLocked()
            lock.unlock(); drainNext(); return
        }
        lock.unlock()
        let end = min(offset + 64, packets.count)
        var remaining = end - offset
        var failed = false
        connection.batch {
            for index in offset..<end {
                let packet = packets[index]
                connection.send(content: packet, completion: .contentProcessed { [weak self] error in
                    guard let self = self else { return }
                    // Completions execute on streamQueue, so remaining/failed are serialized.
                    if error != nil { failed = true }
                    self.lock.lock()
                    if self.generation == token && error == nil {
                        self.packetsSent += 1; self.bytesSent += Int64(packet.count)
                    }
                    self.lock.unlock()
                    remaining -= 1
                    if remaining == 0 {
                        if failed {
                            self.lock.lock()
                            if self.generation == token { self.sending = false; self.awaitingKeyFrame = true; self.droppedFrames += Int64(self.queue.count + 1); self.queue.removeAll() }
                            self.lock.unlock()
                            self.onKeyFrameNeeded?()
                            self.drainNext()
                        } else { self.sendBatch(packets, offset: end, connection: connection, token: token) }
                    }
                })
            }
        }
    }
    public func retransmitPacket(seq: Int) {
        guard let packet = packetizer.getPacket(seq: seq) else { return }
        lock.lock()
        guard running, ready, retransmissionsInFlight < 64, let connection = connection else { lock.unlock(); return }
        retransmissionsInFlight += 1
        lock.unlock()
        connection.send(content: packet, completion: .contentProcessed { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock(); self.retransmissionsInFlight -= 1; self.lock.unlock()
        })
    }
    private func reportIfDueLocked() {
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now - lastReport
        guard elapsed >= 1 else { return }
        let stats = Stats(framesSent: framesSent, packetsSent: packetsSent, bytesSent: bytesSent, droppedFrames: droppedFrames,
                          fps: Int(Double(framesSent - reportFrames) / elapsed), mbps: Double(bytesSent - reportBytes) * 8 / elapsed / 1_000_000)
        reportFrames = framesSent; reportBytes = bytesSent; lastReport = now
        DispatchQueue.main.async { [weak self] in self?.onStats?(stats) }
    }
}
