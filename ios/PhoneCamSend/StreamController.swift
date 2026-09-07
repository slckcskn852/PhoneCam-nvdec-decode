import Foundation
import Network

public protocol StreamControllerListener: AnyObject {
    func streamControllerDidUpdateStatus(_ controller: StreamController, status: String)
}

public class StreamController: ControlClientDelegate, CaptureEncoderDelegate {
    public weak var listener: StreamControllerListener?
    
    private let controlClient = ControlClient()
    private let mediaLock = NSLock()
    private var controlEnabled = false
    private var encoder: CaptureEncoder?
    private var sender: UdpStreamSender?
    private let packetizer = RtpSwiftPacketizer()
    
    private var activeLadder: Ladder?
    private var targetIp: String = "127.0.0.1"
    private var targetPort: UInt16 = 5004
    
    public init() {
        controlClient.delegate = self
        controlClient.onConnectionStatus = { [weak self] status in
            guard let self = self else { return }
            DispatchQueue.main.async { self.listener?.streamControllerDidUpdateStatus(self, status: status) }
        }
    }
    
    public func connect(to endpoint: NWEndpoint) {
        stopControl()
        controlEnabled = true
        controlClient.connect(to: endpoint)
    }

    public func startControl() {
        controlEnabled = true
        controlClient.start()
        listener?.streamControllerDidUpdateStatus(self, status: "Control channel listening")
    }
    
    public func stopControl() {
        controlEnabled = false
        controlClient.stop()
        stopStreaming()
        listener?.streamControllerDidUpdateStatus(self, status: "Control channel stopped")
    }
    
    public func isStreaming() -> Bool {
        mediaLock.lock(); defer { mediaLock.unlock() }
        return encoder != nil
    }
    
    // MARK: - ControlClientDelegate
    
    public func controlClientDidReceiveStart(_ client: ControlClient, ladder: Ladder) {
        guard controlEnabled, let (destinationIp, destinationPort) = client.destination else { return }
        startStreaming(ladder: ladder, targetIp: destinationIp, targetPort: destinationPort)
    }
    
    public func controlClientDidReceiveStop(_ client: ControlClient) {
        stopStreaming()
    }
    
    public func controlClientDidReceiveNack(_ client: ControlClient, seqs: [Int]) {
        for seq in seqs {
            sender?.retransmitPacket(seq: seq)
        }
    }
    
    public func controlClientDidReceivePli(_ client: ControlClient) {
        encoder?.requestKeyFrame()
    }
    
    public func controlClientDidChangeBitrate(_ client: ControlClient, bitrateBps: Int) {
        encoder?.setBitrate(bitrateBps)
    }
    
    public func controlClientDidChangeLadder(_ client: ControlClient, newLadder: Ladder) {
        let ip = targetIp
        let port = targetPort
        stopStreaming()
        startStreaming(ladder: newLadder, targetIp: ip, targetPort: port)
    }
    
    // MARK: - CaptureEncoderDelegate
    
    public func captureEncoderDidOutputAccessUnit(_ encoder: CaptureEncoder, data: Data, ptsUs: Int64, isKeyFrame: Bool) {
        mediaLock.lock()
        let current = self.encoder === encoder
        let activeSender = sender
        mediaLock.unlock()
        guard current else { return }
        if controlClient.isTcpConnected {
            let packets = packetizer.packetize(accessUnit: data, ptsUs: ptsUs)
            controlClient.sendTcpMedia(packets: packets)
        } else {
            activeSender?.onAccessUnit(annexB: data, ptsUs: ptsUs, isKeyFrame: isKeyFrame)
        }
    }
    
    public func captureEncoderDidError(_ encoder: CaptureEncoder, message: String) {
        listener?.streamControllerDidUpdateStatus(self, status: "Encoder error: \(message)")
    }
    
    // MARK: - Private Methods
    
    private func startStreaming(ladder: Ladder, targetIp: String, targetPort: UInt16) {
        stopStreaming()
        self.targetIp = targetIp
        self.targetPort = targetPort
        activeLadder = ladder
        
        let captureEncoder = CaptureEncoder(delegate: self)
        captureEncoder.configure(width: ladder.width, height: ladder.height, fps: ladder.fps, bitrateBps: ladder.bitrateBps)
        mediaLock.lock()
        self.encoder = captureEncoder
        mediaLock.unlock()
        
        if !controlClient.isTcpConnected {
            let udpSender = UdpStreamSender(targetIp: targetIp, targetPort: targetPort, packetizer: packetizer, onKeyFrameNeeded: { [weak captureEncoder] in captureEncoder?.requestKeyFrame() }) { [weak self] stats in
                guard let self = self else { return }
                self.listener?.streamControllerDidUpdateStatus(
                    self,
                    status: "UDP \(ladder.width)x\(ladder.height)@\(ladder.fps): \(stats.fps) fps, \(String(format: "%.1f", stats.mbps)) Mbps, \(stats.packetsSent) pkts"
                )
            }
            mediaLock.lock()
            self.sender = udpSender
            mediaLock.unlock()
            udpSender.start()
        }
        
        captureEncoder.start()
        listener?.streamControllerDidUpdateStatus(self, status: "Streaming started: \(ladder.summary)")
    }
    
    private func stopStreaming() {
        mediaLock.lock()
        let oldEncoder = encoder
        let oldSender = sender
        encoder = nil
        sender = nil
        mediaLock.unlock()
        // Drain callbacks without holding the lock they use to snapshot media state.
        oldEncoder?.stop()
        oldSender?.stop()
        activeLadder = nil
        listener?.streamControllerDidUpdateStatus(self, status: "Streaming stopped")
    }
}
