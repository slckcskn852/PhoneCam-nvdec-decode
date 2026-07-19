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

    private struct QueuedAccessUnit {
        let annexB: Data
        let ptsUs: Int64
    }

    private let targetIp: String
    private let targetPort: UInt16
    private let packetizer: RtpSwiftPacketizer
    private let onStats: ((Stats) -> Void)?

    private var connection: NWConnection?
    private var queue = [QueuedAccessUnit]()
    private let queueLimit = 8
    
    private var framesSent: Int64 = 0
    private var packetsSent: Int64 = 0
    private var bytesSent: Int64 = 0
    private var droppedFrames: Int64 = 0
    
    private var running = false
    private let lock = NSLock()
    private let streamQueue = DispatchQueue(label: "com.phonecam.stream4k.udpsender")
    private var timer: DispatchSourceTimer?

    public init(targetIp: String, targetPort: UInt16, packetizer: RtpSwiftPacketizer, onStats: ((Stats) -> Void)? = nil) {
        self.targetIp = targetIp
        self.targetPort = targetPort
        self.packetizer = packetizer
        self.onStats = onStats
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        if running { return }
        running = true
        
        queue.removeAll()
        framesSent = 0
        packetsSent = 0
        bytesSent = 0
        droppedFrames = 0
        
        let connection = NWConnection(host: NWEndpoint.Host(targetIp), port: NWEndpoint.Port(rawValue: targetPort)!, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                print("UdpStreamSender: Connection failed: \(error)")
            default:
                break
            }
        }
        connection.start(queue: streamQueue)
        self.connection = connection
        
        startLoop()
    }

    public func stop() {
        lock.lock()
        running = false
        connection?.cancel()
        connection = nil
        timer?.cancel()
        timer = nil
        queue.removeAll()
        lock.unlock()
    }

    public func onAccessUnit(annexB: Data, ptsUs: Int64) {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        
        if queue.count >= queueLimit {
            queue.removeFirst()
            droppedFrames += 1
        }
        queue.append(QueuedAccessUnit(annexB: annexB, ptsUs: ptsUs))
        lock.unlock()
    }

    public func retransmitPacket(seq: Int) {
        guard let packet = packetizer.getPacket(seq: seq) else { return }
        lock.lock()
        let activeConnection = connection
        lock.unlock()
        
        activeConnection?.send(content: packet, completion: .contentProcessed({ error in
            if let error = error {
                print("UdpStreamSender: Retransmit failed for seq \(seq): \(error)")
            } else {
                self.lock.lock()
                self.bytesSent += Int64(packet.count)
                self.lock.unlock()
            }
        }))
    }

    private func startLoop() {
        let timer = DispatchSource.makeTimerSource(queue: streamQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1))
        
        var windowStartMs = Date().timeIntervalSince1970 * 1000.0
        var windowFrames = 0
        var windowBytes: Int64 = 0
        
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            var unit: QueuedAccessUnit? = nil
            self.lock.lock()
            if self.running && !self.queue.isEmpty {
                unit = self.queue.removeFirst()
            }
            self.lock.unlock()
            
            if let unit = unit {
                let packets = self.packetizer.packetize(accessUnit: unit.annexB, ptsUs: unit.ptsUs)
                for packet in packets {
                    self.lock.lock()
                    let conn = self.connection
                    self.lock.unlock()
                    
                    conn?.send(content: packet, completion: .contentProcessed({ error in
                        if error == nil {
                            self.lock.lock()
                            self.packetsSent += 1
                            self.bytesSent += Int64(packet.count)
                            self.lock.unlock()
                        }
                    }))
                    windowBytes += Int64(packet.count)
                }
                if !packets.isEmpty {
                    self.lock.lock()
                    self.framesSent += 1
                    self.lock.unlock()
                    windowFrames += 1
                }
            }
            
            let nowMs = Date().timeIntervalSince1970 * 1000.0
            let elapsedMs = nowMs - windowStartMs
            if elapsedMs >= 1000.0 {
                self.lock.lock()
                let totalFrames = self.framesSent
                let totalPackets = self.packetsSent
                let totalBytes = self.bytesSent
                let totalDropped = self.droppedFrames
                self.lock.unlock()
                
                let stats = Stats(
                    framesSent: totalFrames,
                    packetsSent: totalPackets,
                    bytesSent: totalBytes,
                    droppedFrames: totalDropped,
                    fps: Int(Double(windowFrames) * 1000.0 / elapsedMs),
                    mbps: Double(windowBytes) * 8.0 * 1000.0 / (elapsedMs * 1000000.0)
                )
                
                windowStartMs = nowMs
                windowFrames = 0
                windowBytes = 0
                
                DispatchQueue.main.async {
                    self.onStats?(stats)
                }
            }
        }
        
        self.timer = timer
        timer.resume()
    }
}
