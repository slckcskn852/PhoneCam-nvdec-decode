import Foundation

public protocol StreamControllerListener: AnyObject {
    func streamControllerDidUpdateStatus(_ controller: StreamController, status: String)
}

public class StreamController: ControlClientDelegate, CaptureEncoderDelegate {
    public weak var listener: StreamControllerListener?
    
    private let controlClient = ControlClient()
    private var encoder: CaptureEncoder?
    private var sender: UdpStreamSender?
    private let packetizer = RtpSwiftPacketizer()
    
    private var activeLadder: Ladder?
    private var targetIp: String = "127.0.0.1"
    private var targetPort: UInt16 = 5004
    
    public init() {
        controlClient.delegate = self
    }
    
    public func startControl() {
        controlClient.start()
        listener?.streamControllerDidUpdateStatus(self, status: "Control channel listening")
    }
    
    public func stopControl() {
        controlClient.stop()
        stopStreaming()
        listener?.streamControllerDidUpdateStatus(self, status: "Control channel stopped")
    }
    
    public func isStreaming() -> Bool {
        return encoder != nil
    }
    
    // MARK: - ControlClientDelegate
    
    public func controlClientDidReceiveStart(_ client: ControlClient, ladder: Ladder) {
        let destinationIp = "127.0.0.1"
        let destinationPort: UInt16 = 5004
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
        if controlClient.isTcpConnected {
            let packets = packetizer.packetize(accessUnit: data, ptsUs: ptsUs)
            for packet in packets {
                controlClient.sendTcpMedia(packet: packet)
            }
        } else {
            sender?.onAccessUnit(annexB: data, ptsUs: ptsUs)
        }
    }
    
    public func captureEncoderDidError(_ encoder: CaptureEncoder, message: String) {
        listener?.streamControllerDidUpdateStatus(self, status: "Encoder error: \(message)")
    }
    
    // MARK: - Private Methods
    
    private func startStreaming(ladder: Ladder, targetIp: String, targetPort: UInt16) {
        self.targetIp = targetIp
        self.targetPort = targetPort
        activeLadder = ladder
        
        let captureEncoder = CaptureEncoder(delegate: self)
        captureEncoder.configure(width: ladder.width, height: ladder.height, fps: ladder.fps, bitrateBps: ladder.bitrateBps)
        self.encoder = captureEncoder
        
        if !controlClient.isTcpConnected {
            let udpSender = UdpStreamSender(targetIp: targetIp, targetPort: targetPort, packetizer: packetizer) { [weak self] stats in
                guard let self = self else { return }
                self.listener?.streamControllerDidUpdateStatus(
                    self,
                    status: "UDP \(ladder.width)x\(ladder.height)@\(ladder.fps): \(stats.fps) fps, \(String(format: "%.1f", stats.mbps)) Mbps, \(stats.packetsSent) pkts"
                )
            }
            self.sender = udpSender
            udpSender.start()
        }
        
        captureEncoder.start()
        listener?.streamControllerDidUpdateStatus(self, status: "Streaming started: \(ladder.summary)")
    }
    
    private func stopStreaming() {
        encoder?.stop()
        encoder = nil
        sender?.stop()
        sender = nil
        activeLadder = nil
        listener?.streamControllerDidUpdateStatus(self, status: "Streaming stopped")
    }
}
