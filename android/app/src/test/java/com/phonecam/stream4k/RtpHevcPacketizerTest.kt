package com.phonecam.stream4k

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RtpHevcPacketizerTest {

    @Test
    fun splitAnnexBHandlesThreeByteStartCodes() {
        val a = nal(32, 6)
        val b = nal(19, 8)
        val buffer = byteArrayOf(0, 0, 1) + a + byteArrayOf(0, 0, 1) + b

        val nals = RtpHevcPacketizer.splitAnnexB(buffer)

        assertEquals(2, nals.size)
        assertArrayEquals(a, nals[0])
        assertArrayEquals(b, nals[1])
    }

    @Test
    fun splitAnnexBHandlesFourByteStartCodesAndTrailingZeros() {
        val a = nal(33, 6)
        val b = nal(19, 9)
        val buffer = byteArrayOf(0, 0, 0, 1) + a + byteArrayOf(0, 0, 0, 1) + b + byteArrayOf(0, 0, 0)

        val nals = RtpHevcPacketizer.splitAnnexB(buffer)

        assertEquals(2, nals.size)
        assertArrayEquals(a, nals[0])
        assertArrayEquals(b, nals[1])
    }

    @Test
    fun splitAnnexBTreatsMissingStartCodeAsSingleNal() {
        val buffer = byteArrayOf(0x26, 0x01, 0x11, 0x22, 0, 0)

        val nals = RtpHevcPacketizer.splitAnnexB(buffer)

        assertEquals(1, nals.size)
        assertArrayEquals(byteArrayOf(0x26, 0x01, 0x11, 0x22), nals[0])
    }

    @Test
    fun splitAnnexBReturnsEmptyForEmptyAndStartCodeOnlyInput() {
        assertTrue(RtpHevcPacketizer.splitAnnexB(ByteArray(0)).isEmpty())
        assertTrue(RtpHevcPacketizer.splitAnnexB(byteArrayOf(0, 0, 1)).isEmpty())
        assertTrue(RtpHevcPacketizer.splitAnnexB(byteArrayOf(0, 0, 0, 0)).isEmpty())
    }

    @Test
    fun smallNalProducesSingleNalUnitPacket() {
        val packetizer = RtpHevcPacketizer()
        val nal = nal(19, 10)

        val packets = packetizer.packetize(annexB(nal), ptsUs = 0L)

        assertEquals(1, packets.size)
        val packet = packets[0]
        assertEquals(RtpHevcPacketizer.RTP_HEADER_SIZE + nal.size, packet.size)
        assertEquals(0x80.toByte(), packet[0]) // V=2
        assertEquals(RtpHevcPacketizer.PAYLOAD_TYPE, packet[1].toInt() and 0x7F)
        assertTrue(packet[1].toInt() and 0x80 != 0) // marker on last packet of AU
        assertEquals(0x1F, packet[2].toInt() and 0xFF) // initial sequence number
        assertEquals(0x00, packet[3].toInt() and 0xFF)
        assertEquals(0x50, packet[8].toInt() and 0xFF) // SSRC 0x50434B36
        assertEquals(0x43, packet[9].toInt() and 0xFF)
        assertEquals(0x4B, packet[10].toInt() and 0xFF)
        assertEquals(0x36, packet[11].toInt() and 0xFF)
        assertArrayEquals(nal, packet.copyOfRange(RtpHevcPacketizer.RTP_HEADER_SIZE, packet.size))
    }

    @Test
    fun largeNalIsFragmentedIntoFuPackets() {
        val packetizer = RtpHevcPacketizer(mtu = 1400)
        val nal = nal(19, 5_000)

        val packets = packetizer.packetize(annexB(nal), ptsUs = 0L)

        // 4998 payload bytes / 1385 max chunk = 4 FU packets.
        assertEquals(4, packets.size)
        packets.forEach { packet ->
            assertTrue("packet <= mtu", packet.size <= 1400)
            // FU indicator: F/NRI kept, type replaced by 49.
            val fuIndicatorType = (packet[12].toInt() shr 1) and 0x3F
            assertEquals(RtpHevcPacketizer.NAL_TYPE_FU, fuIndicatorType)
            assertEquals(nal[1], packet[13])
        }
        // S bit on first, E bit on last, neither in the middle.
        assertEquals(0x80 or 19, packets[0][14].toInt() and 0xFF)
        assertEquals(19, packets[1][14].toInt() and 0xFF)
        assertEquals(19, packets[2][14].toInt() and 0xFF)
        assertEquals(0x40 or 19, packets[3][14].toInt() and 0xFF)
        // Reassembled FU payloads equal the original NAL payload.
        val reassembled = packets.fold(ByteArray(0)) { acc, packet ->
            acc + packet.copyOfRange(RtpHevcPacketizer.RTP_HEADER_SIZE + 3, packet.size)
        }
        assertArrayEquals(nal.copyOfRange(2, nal.size), reassembled)
    }

    @Test
    fun markerBitIsSetOnlyOnLastPacketOfAccessUnit() {
        val packetizer = RtpHevcPacketizer()
        val au = annexB(nal(32, 8), nal(33, 8), nal(19, 9000))

        val packets = packetizer.packetize(au, ptsUs = 0L)

        assertTrue(packets.size > 3) // two singles + several FUs
        packets.dropLast(1).forEach { packet ->
            assertEquals(0, packet[1].toInt() and 0x80)
        }
        assertTrue(packets.last()[1].toInt() and 0x80 != 0)
    }

    @Test
    fun timestampConvertsMicrosecondsTo90kHzClock() {
        val packetizer = RtpHevcPacketizer()

        val packets = packetizer.packetize(annexB(nal(19, 10)), ptsUs = 1_000_000L)

        val packet = packets[0]
        val timestamp = ((packet[4].toInt() and 0xFF) shl 24) or
            ((packet[5].toInt() and 0xFF) shl 16) or
            ((packet[6].toInt() and 0xFF) shl 8) or
            (packet[7].toInt() and 0xFF)
        assertEquals(90_000, timestamp)
    }

    @Test
    fun sequenceNumberAdvancesAndWrapsAt65536() {
        val packetizer = RtpHevcPacketizer(initialSequenceNumber = 65_535)

        val packets = packetizer.packetize(annexB(nal(1, 6), nal(1, 6)), ptsUs = 0L)

        assertEquals(2, packets.size)
        assertEquals(0xFF, packets[0][2].toInt() and 0xFF)
        assertEquals(0xFF, packets[0][3].toInt() and 0xFF)
        assertEquals(0x00, packets[1][2].toInt() and 0xFF)
        assertEquals(0x00, packets[1][3].toInt() and 0xFF)
    }

    @Test
    fun audNalsAreDropped() {
        val packetizer = RtpHevcPacketizer()
        val slice = nal(19, 10)

        val packets = packetizer.packetize(annexB(nal(RtpHevcPacketizer.NAL_TYPE_AUD, 4), slice), ptsUs = 0L)

        assertEquals(1, packets.size)
        assertArrayEquals(slice, packets[0].copyOfRange(RtpHevcPacketizer.RTP_HEADER_SIZE, packets[0].size))
        assertTrue(packetizer.packetize(annexB(nal(RtpHevcPacketizer.NAL_TYPE_AUD, 4)), ptsUs = 0L).isEmpty())
    }

    @Test
    fun vpsSpsPpsPassThroughInOrder() {
        val packetizer = RtpHevcPacketizer()
        val vps = nal(32, 8)
        val sps = nal(33, 8)
        val pps = nal(34, 8)
        val slice = nal(19, 12)

        val packets = packetizer.packetize(annexB(vps, sps, pps, slice), ptsUs = 0L)

        assertEquals(4, packets.size)
        val expected = listOf(vps, sps, pps, slice)
        packets.forEachIndexed { index, packet ->
            assertArrayEquals(
                expected[index],
                packet.copyOfRange(RtpHevcPacketizer.RTP_HEADER_SIZE, packet.size)
            )
        }
        assertFalse(packets[0][1].toInt() and 0x80 != 0)
        assertFalse(packets[1][1].toInt() and 0x80 != 0)
        assertFalse(packets[2][1].toInt() and 0x80 != 0)
        assertTrue(packets[3][1].toInt() and 0x80 != 0)
    }

    @Test
    fun testPacketHistory() {
        val packetizer = RtpHevcPacketizer()
        val nal = nal(19, 10)
        val packets = packetizer.packetize(annexB(nal), ptsUs = 0L)
        val firstSeq = ((packets[0][2].toInt() and 0xFF) shl 8) or (packets[0][3].toInt() and 0xFF)
        val retrieved = packetizer.getPacket(firstSeq)
        assertTrue(retrieved != null)
        assertArrayEquals(packets[0], retrieved)
    }

    private fun hexToBytes(hex: String): ByteArray {
        val s = hex.trim().replace("\\s".toRegex(), "")
        val len = s.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(s[i], 16) shl 4) + Character.digit(s[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }

    private fun readHexFile(path: String): ByteArray {
        var currentDir: java.io.File? = java.io.File(".").absoluteFile
        while (currentDir != null) {
            val targetFile = java.io.File(currentDir, path)
            if (targetFile.exists()) {
                return hexToBytes(targetFile.readText())
            }
            currentDir = currentDir.parentFile
        }
        throw java.io.FileNotFoundException("File not found: $path in any parent directories of ${java.io.File(".").absolutePath}")
    }

    @Test
    fun testR1ConformanceSingleNal() {
        val bytes = readHexFile("docs/protocol-vectors/rtp_single_nal.hex")
        assertTrue(bytes.size >= 12)
        assertEquals(0x80.toByte(), bytes[0]) // V=2
        assertEquals(96, bytes[1].toInt() and 0x7F) // PT=96
        assertEquals(0, bytes[1].toInt() and 0x80) // Marker bit should be 0
        
        // Sequence number: 0x1f00
        val seq = ((bytes[2].toInt() and 0xFF) shl 8) or (bytes[3].toInt() and 0xFF)
        assertEquals(0x1F00, seq)
        
        // Timestamp: 0x0004e200
        val ts = ((bytes[4].toLong() and 0xFF) shl 24) or
                 ((bytes[5].toLong() and 0xFF) shl 16) or
                 ((bytes[6].toLong() and 0xFF) shl 8) or
                 (bytes[7].toLong() and 0xFF)
        assertEquals(320000L, ts)
        
        // SSRC: 0x50434b36
        val ssrc = ((bytes[8].toLong() and 0xFF) shl 24) or
                   ((bytes[9].toLong() and 0xFF) shl 16) or
                   ((bytes[10].toLong() and 0xFF) shl 8) or
                   (bytes[11].toLong() and 0xFF)
        assertEquals(0x50434B36L, ssrc)
        
        // HEVC NAL Unit Header: 0x4001
        val nalHeader0 = bytes[12].toInt() and 0xFF
        val nalHeader1 = bytes[13].toInt() and 0xFF
        assertEquals(32, (nalHeader0 shr 1) and 0x3F) // VPS type
        assertEquals(1, nalHeader1) // Temporal ID plus 1
    }

    @Test
    fun testR1ConformanceFuStart() {
        val bytes = readHexFile("docs/protocol-vectors/rtp_fu_start.hex")
        assertTrue(bytes.size >= 15)
        assertEquals(0x80.toByte(), bytes[0]) // V=2
        assertEquals(96, bytes[1].toInt() and 0x7F)
        assertEquals(0, bytes[1].toInt() and 0x80) // Marker = 0
        
        val seq = ((bytes[2].toInt() and 0xFF) shl 8) or (bytes[3].toInt() and 0xFF)
        assertEquals(0x1F01, seq)
        
        // FU indicator: 0x6201
        val fuInd0 = bytes[12].toInt() and 0xFF
        val fuInd1 = bytes[13].toInt() and 0xFF
        assertEquals(49, (fuInd0 shr 1) and 0x3F) // FU NAL type
        assertEquals(1, fuInd1)
        
        // FU header: 0x93
        val fuHdr = bytes[14].toInt() and 0xFF
        assertTrue(fuHdr and 0x80 != 0) // Start bit set
        assertFalse(fuHdr and 0x40 != 0) // End bit not set
        assertEquals(19, fuHdr and 0x3F) // original NAL unit type 19 (IDR slice)
    }

    @Test
    fun testR1ConformanceFuEnd() {
        val bytes = readHexFile("docs/protocol-vectors/rtp_fu_end.hex")
        assertTrue(bytes.size >= 15)
        assertEquals(0x80.toByte(), bytes[0]) // V=2
        assertEquals(96, bytes[1].toInt() and 0x7F)
        assertTrue(bytes[1].toInt() and 0x80 != 0) // Marker = 1
        
        val seq = ((bytes[2].toInt() and 0xFF) shl 8) or (bytes[3].toInt() and 0xFF)
        assertEquals(0x1F02, seq)
        
        // FU indicator: 0x6201
        val fuInd0 = bytes[12].toInt() and 0xFF
        val fuInd1 = bytes[13].toInt() and 0xFF
        assertEquals(49, (fuInd0 shr 1) and 0x3F) // FU NAL type
        assertEquals(1, fuInd1)
        
        // FU header: 0x53
        val fuHdr = bytes[14].toInt() and 0xFF
        assertFalse(fuHdr and 0x80 != 0) // Start bit not set
        assertTrue(fuHdr and 0x40 != 0) // End bit set
        assertEquals(19, fuHdr and 0x3F) // original NAL unit type 19
    }

    /** Builds a HEVC NAL unit (2-byte header + patterned payload, no zeros at the end). */
    private fun nal(type: Int, size: Int): ByteArray {
        val bytes = ByteArray(size)
        bytes[0] = (type shl 1).toByte()
        bytes[1] = 0x01
        for (i in 2 until size) {
            bytes[i] = (i * 31 and 0xFF).toByte()
        }
        bytes[size - 1] = 0x7F
        return bytes
    }

    private fun annexB(vararg nals: ByteArray): ByteArray {
        return nals.fold(ByteArray(0)) { acc, nal -> acc + byteArrayOf(0, 0, 1) + nal }
    }
    @org.junit.Test
    fun invalidNackSequencesAreIgnored() {
        val packetizer = RtpHevcPacketizer()
        org.junit.Assert.assertNull(packetizer.getPacket(-1))
        org.junit.Assert.assertNull(packetizer.getPacket(65536))
    }

    @org.junit.Test(expected = IllegalArgumentException::class)
    fun impossibleMtuIsRejectedInsteadOfLoopingForever() {
        RtpHevcPacketizer(mtu = 15)
    }

    @org.junit.Test
    fun allFragmentHistoryContainsFinalPayloadAndMarker() {
        val packetizer = RtpHevcPacketizer()
        val au = ByteArray(9000) { 7 }.also {
            it[0] = 0; it[1] = 0; it[2] = 1; it[3] = 0x26; it[4] = 1
        }
        val packets = packetizer.packetize(au, 1_000_000)
        org.junit.Assert.assertTrue(packets.size > 1)
        for (packet in packets) {
            val seq = ((packet[2].toInt() and 255) shl 8) or (packet[3].toInt() and 255)
            org.junit.Assert.assertArrayEquals(packet, packetizer.getPacket(seq))
        }
    }

}
