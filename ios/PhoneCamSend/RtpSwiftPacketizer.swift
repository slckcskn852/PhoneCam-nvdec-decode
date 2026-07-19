import Foundation

public class RtpSwiftPacketizer {
    public static let defaultMtu = 1400
    public static let defaultSsrc: UInt32 = 0x50434B36
    public static let payloadType: UInt8 = 96
    public static let rtpHeaderSize = 12
    public static let hevcNalHeaderSize = 2
    public static let nalTypeAud = 35
    public static let nalTypeFu = 49
    private static let fuHeaderTotal = 3
    private static let fuStartBit: UInt8 = 0x80
    private static let fuEndBit: UInt8 = 0x40
    private static let rtpClockHz: Int64 = 90_000

    public private(set) var sequenceNumber: UInt16
    public let mtu: Int
    public let ssrc: UInt32
    private var history = [Data?](repeating: nil, count: 256)

    public init(mtu: Int = defaultMtu, ssrc: UInt32 = defaultSsrc, initialSequenceNumber: UInt16 = 0x1F00) {
        self.mtu = mtu
        self.ssrc = ssrc
        self.sequenceNumber = initialSequenceNumber
    }

    public func getPacket(seq: Int) -> Data? {
        guard let packet = history[seq % 256] else { return nil }
        let packetSeq = (Int(packet[2]) << 8) | Int(packet[3])
        return packetSeq == seq ? packet : nil
    }

    public func packetize(accessUnit: Data, ptsUs: Int64) -> [Data] {
        let timestamp = UInt32((ptsUs * Self.rtpClockHz / 1_000_000) & 0xFFFFFFFF)
        let nals = Self.splitAnnexB(data: accessUnit).filter { nal in
            nal.count >= Self.hevcNalHeaderSize && Self.nalType(nal: nal) != Self.nalTypeAud
        }
        if nals.isEmpty { return [] }

        var packets = [Data]()
        for nal in nals {
            if Self.rtpHeaderSize + nal.count <= mtu {
                packets.append(buildSingleNalPacket(nal: nal, timestamp: timestamp))
            } else {
                packets.append(contentsOf: buildFuPackets(nal: nal, timestamp: timestamp))
            }
        }

        if !packets.isEmpty {
            var last = packets[packets.count - 1]
            last[1] |= 0x80 // Set Marker (M) bit to 1
            packets[packets.count - 1] = last
            
            let lastSeq = (sequenceNumber &- 1) & 0xFFFF
            history[Int(lastSeq) % 256] = last
        }

        return packets
    }

    private func buildSingleNalPacket(nal: Data, timestamp: UInt32) -> Data {
        var packet = Data(repeating: 0, count: Self.rtpHeaderSize + nal.count)
        writeRtpHeader(packet: &packet, timestamp: timestamp)
        packet.replaceSubrange(Self.rtpHeaderSize..<packet.count, with: nal)
        return packet
    }

    private func buildFuPackets(nal: Data, timestamp: UInt32) -> [Data] {
        let type = UInt8(Self.nalType(nal: nal))
        let fuIndicator0 = (nal[0] & 0x81) | (UInt8(Self.nalTypeFu) << 1)
        let fuIndicator1 = nal[1]
        let maxChunk = mtu - Self.rtpHeaderSize - Self.fuHeaderTotal
        let payloadSize = nal.count - Self.hevcNalHeaderSize
        var packets = [Data]()
        var offset = Self.hevcNalHeaderSize
        var sent = 0
        while sent < payloadSize {
            let chunkSize = min(maxChunk, payloadSize - sent)
            var packet = Data(repeating: 0, count: Self.rtpHeaderSize + Self.fuHeaderTotal + chunkSize)
            writeRtpHeader(packet: &packet, timestamp: timestamp)
            packet[Self.rtpHeaderSize] = fuIndicator0
            packet[Self.rtpHeaderSize + 1] = fuIndicator1
            var fuHeader = type
            if sent == 0 {
                fuHeader |= Self.fuStartBit
            }
            if sent + chunkSize == payloadSize {
                fuHeader |= Self.fuEndBit
            }
            packet[Self.rtpHeaderSize + 2] = fuHeader
            packet.replaceSubrange((Self.rtpHeaderSize + Self.fuHeaderTotal)..<packet.count, with: nal.subdata(in: offset..<(offset + chunkSize)))
            packets.append(packet)
            offset += chunkSize
            sent += chunkSize
        }
        return packets
    }

    private func writeRtpHeader(packet: inout Data, timestamp: UInt32) {
        packet[0] = 0x80 // V=2, P=0, X=0, CC=0
        packet[1] = Self.payloadType // M=0 (modified later for last packet)
        packet[2] = UInt8((sequenceNumber >> 8) & 0xFF)
        packet[3] = UInt8(sequenceNumber & 0xFF)
        
        history[Int(sequenceNumber) % 256] = packet
        sequenceNumber = sequenceNumber &+ 1
        
        packet[4] = UInt8((timestamp >> 24) & 0xFF)
        packet[5] = UInt8((timestamp >> 16) & 0xFF)
        packet[6] = UInt8((timestamp >> 8) & 0xFF)
        packet[7] = UInt8(timestamp & 0xFF)
        
        packet[8] = UInt8((ssrc >> 24) & 0xFF)
        packet[9] = UInt8((ssrc >> 16) & 0xFF)
        packet[10] = UInt8((ssrc >> 8) & 0xFF)
        packet[11] = UInt8(ssrc & 0xFF)
    }

    public static func nalType(nal: Data) -> Int {
        if nal.isEmpty { return -1 }
        return Int((nal[0] >> 1) & 0x3F)
    }

    public static func splitAnnexB(data: Data) -> [Data] {
        var nals = [Data]()
        var nalStart = -1
        var i = 0
        let count = data.count
        while i + 2 < count {
            if data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1 {
                if nalStart >= 0 {
                    addTrimmed(nals: &nals, data: data, start: nalStart, end: i)
                }
                i += 3
                nalStart = i
            } else {
                i += 1
            }
        }
        if nalStart >= 0 {
            addTrimmed(nals: &nals, data: data, start: nalStart, end: count)
        } else if !data.isEmpty {
            addTrimmed(nals: &nals, data: data, start: 0, end: count)
        }
        return nals
    }

    private static func addTrimmed(nals: inout [Data], data: Data, start: Int, end: Int) {
        var trimmedEnd = end
        while trimmedEnd > start && data[trimmedEnd - 1] == 0 {
            trimmedEnd -= 1
        }
        if trimmedEnd > start {
            nals.append(data.subdata(in: start..<trimmedEnd))
        }
    }
}
