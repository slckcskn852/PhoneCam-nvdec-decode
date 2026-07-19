import XCTest
@testable import PhoneCamSend

final class PhoneCamSendTests: XCTestCase {

    private func nal(type: Int, size: Int) -> Data {
        var bytes = Data(repeating: 0, count: size)
        bytes[0] = UInt8((type << 1) & 0xFF)
        bytes[1] = 0x01
        for i in 2..<size {
            bytes[i] = UInt8((i * 31) & 0xFF)
        }
        bytes[size - 1] = 0x7F
        return bytes
    }

    private func annexB(_ nals: Data...) -> Data {
        var data = Data()
        for nal in nals {
            data.append(contentsOf: [0, 0, 1])
            data.append(nal)
        }
        return data
    }

    func testSplitAnnexBHandlesThreeByteStartCodes() {
        let a = nal(type: 32, size: 6)
        let b = nal(type: 19, size: 8)
        let buffer = Data([0, 0, 1]) + a + Data([0, 0, 1]) + b

        let nals = RtpSwiftPacketizer.splitAnnexB(data: buffer)

        XCTAssertEqual(nals.count, 2)
        XCTAssertEqual(nals[0], a)
        XCTAssertEqual(nals[1], b)
    }

    func testSplitAnnexBHandlesFourByteStartCodesAndTrailingZeros() {
        let a = nal(type: 33, size: 6)
        let b = nal(type: 19, size: 9)
        let buffer = Data([0, 0, 0, 1]) + a + Data([0, 0, 0, 1]) + b + Data([0, 0, 0])

        let nals = RtpSwiftPacketizer.splitAnnexB(data: buffer)

        XCTAssertEqual(nals.count, 2)
        XCTAssertEqual(nals[0], a)
        XCTAssertEqual(nals[1], b)
    }

    func testSplitAnnexBTreatsMissingStartCodeAsSingleNal() {
        let buffer = Data([0x26, 0x01, 0x11, 0x22, 0, 0])

        let nals = RtpSwiftPacketizer.splitAnnexB(data: buffer)

        XCTAssertEqual(nals.count, 1)
        XCTAssertEqual(nals[0], Data([0x26, 0x01, 0x11, 0x22]))
    }

    func testSplitAnnexBReturnsEmptyForEmptyAndStartCodeOnlyInput() {
        XCTAssertTrue(RtpSwiftPacketizer.splitAnnexB(data: Data()).isEmpty)
        XCTAssertTrue(RtpSwiftPacketizer.splitAnnexB(data: Data([0, 0, 1])).isEmpty)
        XCTAssertTrue(RtpSwiftPacketizer.splitAnnexB(data: Data([0, 0, 0, 0])).isEmpty)
    }

    func testSmallNalProducesSingleNalUnitPacket() {
        let packetizer = RtpSwiftPacketizer()
        let slice = nal(type: 19, size: 10)

        let packets = packetizer.packetize(accessUnit: annexB(slice), ptsUs: 0)

        XCTAssertEqual(packets.count, 1)
        let packet = packets[0]
        XCTAssertEqual(packet.count, RtpSwiftPacketizer.rtpHeaderSize + slice.count)
        XCTAssertEqual(packet[0], 0x80)
        XCTAssertEqual(packet[1] & 0x7F, RtpSwiftPacketizer.payloadType)
        XCTAssertTrue((packet[1] & 0x80) != 0) // marker bit set
        XCTAssertEqual(packet[2], 0x1F) // initial sequence number 0x1F00
        XCTAssertEqual(packet[3], 0x00)
        XCTAssertEqual(packet[8], 0x50) // SSRC 0x50434B36
        XCTAssertEqual(packet[9], 0x43)
        XCTAssertEqual(packet[10], 0x4B)
        XCTAssertEqual(packet[11], 0x36)
        XCTAssertEqual(packet.subdata(in: RtpSwiftPacketizer.rtpHeaderSize..<packet.count), slice)
    }

    func testLargeNalIsFragmentedIntoFuPackets() {
        let packetizer = RtpSwiftPacketizer(mtu: 1400)
        let slice = nal(type: 19, size: 5000)

        let packets = packetizer.packetize(accessUnit: annexB(slice), ptsUs: 0)

        XCTAssertEqual(packets.count, 4)
        for packet in packets {
            XCTAssertTrue(packet.count <= 1400)
            let fuIndicatorType = (packet[12] >> 1) & 0x3F
            XCTAssertEqual(Int(fuIndicatorType), RtpSwiftPacketizer.nalTypeFu)
            XCTAssertEqual(packet[13], slice[1])
        }
        
        XCTAssertEqual(packets[0][14], 0x80 | 19)
        XCTAssertEqual(packets[1][14], 19)
        XCTAssertEqual(packets[2][14], 19)
        XCTAssertEqual(packets[3][14], 0x40 | 19)

        var reassembled = Data()
        for packet in packets {
            reassembled.append(packet.subdata(in: (RtpSwiftPacketizer.rtpHeaderSize + 3)..<packet.count))
        }
        XCTAssertEqual(slice.subdata(in: 2..<slice.count), reassembled)
    }

    func testMarkerBitIsSetOnlyOnLastPacketOfAccessUnit() {
        let packetizer = RtpSwiftPacketizer()
        let au = annexB(nal(type: 32, size: 8), nal(type: 33, size: 8), nal(type: 19, size: 9000))

        let packets = packetizer.packetize(accessUnit: au, ptsUs: 0)

        XCTAssertTrue(packets.count > 3)
        for i in 0..<(packets.count - 1) {
            XCTAssertEqual(packets[i][1] & 0x80, 0)
        }
        XCTAssertTrue((packets.last![1] & 0x80) != 0)
    }

    func testTimestampConvertsMicrosecondsTo90kHzClock() {
        let packetizer = RtpSwiftPacketizer()

        let packets = packetizer.packetize(accessUnit: annexB(nal(type: 19, size: 10)), ptsUs: 1_000_000)

        XCTAssertEqual(packets.count, 1)
        let packet = packets[0]
        let timestamp = (UInt32(packet[4]) << 24) |
                        (UInt32(packet[5]) << 16) |
                        (UInt32(packet[6]) << 8) |
                        UInt32(packet[7])
        XCTAssertEqual(timestamp, 90000)
    }

    func testSequenceNumberAdvancesAndWrapsAt65536() {
        let packetizer = RtpSwiftPacketizer(initialSequenceNumber: 65535)

        let packets = packetizer.packetize(accessUnit: annexB(nal(type: 1, size: 6), nal(type: 1, size: 6)), ptsUs: 0)

        XCTAssertEqual(packets.count, 2)
        XCTAssertEqual(packets[0][2], 0xFF)
        XCTAssertEqual(packets[0][3], 0xFF)
        XCTAssertEqual(packets[1][2], 0x00)
        XCTAssertEqual(packets[1][3], 0x00)
    }

    func testAudNalsAreDropped() {
        let packetizer = RtpSwiftPacketizer()
        let slice = nal(type: 19, size: 10)

        let packets = packetizer.packetize(accessUnit: annexB(nal(type: RtpSwiftPacketizer.nalTypeAud, size: 4), slice), ptsUs: 0)

        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].subdata(in: RtpSwiftPacketizer.rtpHeaderSize..<packets[0].count), slice)
        XCTAssertTrue(packetizer.packetize(accessUnit: annexB(nal(type: RtpSwiftPacketizer.nalTypeAud, size: 4)), ptsUs: 0).isEmpty)
    }

    func testVpsSpsPpsPassThroughInOrder() {
        let packetizer = RtpSwiftPacketizer()
        let vps = nal(type: 32, size: 8)
        let sps = nal(type: 33, size: 8)
        let pps = nal(type: 34, size: 8)
        let slice = nal(type: 19, size: 12)

        let packets = packetizer.packetize(accessUnit: annexB(vps, sps, pps, slice), ptsUs: 0)

        XCTAssertEqual(packets.count, 4)
        let expected = [vps, sps, pps, slice]
        for i in 0..<4 {
            XCTAssertEqual(expected[i], packets[i].subdata(in: RtpSwiftPacketizer.rtpHeaderSize..<packets[i].count))
        }
        XCTAssertFalse((packets[0][1] & 0x80) != 0)
        XCTAssertFalse((packets[1][1] & 0x80) != 0)
        XCTAssertFalse((packets[2][1] & 0x80) != 0)
        XCTAssertTrue((packets[3][1] & 0x80) != 0)
    }

    func testPacketHistory() {
        let packetizer = RtpSwiftPacketizer()
        let slice = nal(type: 19, size: 10)
        let packets = packetizer.packetize(accessUnit: annexB(slice), ptsUs: 0)
        let firstSeq = (Int(packets[0][2]) << 8) | Int(packets[0][3])
        let retrieved = packetizer.getPacket(seq: firstSeq)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(packets[0], retrieved)
    }

    private func hexToBytes(_ hex: String) -> Data {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        hex = hex.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }

    private func readHexFile(_ path: String) throws -> Data {
        let thisFile = URL(fileURLWithPath: #file)
        let projectRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fileUrl = projectRoot.appendingPathComponent(path)
        let content = try String(contentsOf: fileUrl, encoding: .utf8)
        return hexToBytes(content)
    }

    func testR1ConformanceSingleNal() throws {
        let bytes = try readHexFile("docs/protocol-vectors/rtp_single_nal.hex")
        XCTAssertTrue(bytes.count >= 12)
        XCTAssertEqual(bytes[0], 0x80) // V=2
        XCTAssertEqual(bytes[1] & 0x7F, 96) // PT=96
        XCTAssertEqual(bytes[1] & 0x80, 0) // Marker bit should be 0
        
        let seq = (Int(bytes[2]) << 8) | Int(bytes[3])
        XCTAssertEqual(seq, 0x1F00)
        
        let ts = (UInt64(bytes[4]) << 24) |
                 (UInt64(bytes[5]) << 16) |
                 (UInt64(bytes[6]) << 8) |
                 UInt64(bytes[7])
        XCTAssertEqual(ts, 320000)
        
        let ssrc = (UInt64(bytes[8]) << 24) |
                   (UInt64(bytes[9]) << 16) |
                   (UInt64(bytes[10]) << 8) |
                   UInt64(bytes[11])
        XCTAssertEqual(ssrc, 0x50434B36)
        
        let nalHeader0 = bytes[12]
        let nalHeader1 = bytes[13]
        XCTAssertEqual(Int((nalHeader0 >> 1) & 0x3F), 32) // VPS type
        XCTAssertEqual(nalHeader1, 1) // Temporal ID plus 1
    }

    func testR1ConformanceFuStart() throws {
        let bytes = try readHexFile("docs/protocol-vectors/rtp_fu_start.hex")
        XCTAssertTrue(bytes.count >= 15)
        XCTAssertEqual(bytes[0], 0x80) // V=2
        XCTAssertEqual(bytes[1] & 0x7F, 96)
        XCTAssertEqual(bytes[1] & 0x80, 0) // Marker = 0
        
        let seq = (Int(bytes[2]) << 8) | Int(bytes[3])
        XCTAssertEqual(seq, 0x1F01)
        
        let fuInd0 = bytes[12]
        let fuInd1 = bytes[13]
        XCTAssertEqual(Int((fuInd0 >> 1) & 0x3F), 49) // FU NAL type
        XCTAssertEqual(fuInd1, 1)
        
        let fuHdr = bytes[14]
        XCTAssertTrue((fuHdr & 0x80) != 0) // Start bit set
        XCTAssertFalse((fuHdr & 0x40) != 0) // End bit not set
        XCTAssertEqual(fuHdr & 0x3F, 19) // original NAL unit type 19
    }

    func testR1ConformanceFuEnd() throws {
        let bytes = try readHexFile("docs/protocol-vectors/rtp_fu_end.hex")
        XCTAssertTrue(bytes.count >= 15)
        XCTAssertEqual(bytes[0], 0x80) // V=2
        XCTAssertEqual(bytes[1] & 0x7F, 96)
        XCTAssertTrue((bytes[1] & 0x80) != 0) // Marker = 1
        
        let seq = (Int(bytes[2]) << 8) | Int(bytes[3])
        XCTAssertEqual(seq, 0x1F02)
        
        let fuInd0 = bytes[12]
        let fuInd1 = bytes[13]
        XCTAssertEqual(Int((fuInd0 >> 1) & 0x3F), 49) // FU NAL type
        XCTAssertEqual(fuInd1, 1)
        
        let fuHdr = bytes[14]
        XCTAssertFalse((fuHdr & 0x80) != 0) // Start bit not set
        XCTAssertTrue((fuHdr & 0x40) != 0) // End bit set
        XCTAssertEqual(fuHdr & 0x3F, 19) // original NAL unit type 19
    }
}
