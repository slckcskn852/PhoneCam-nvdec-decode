package com.phonecam.stream4k

/**
 * RTP packetizer for HEVC (RFC 7798). Pure Kotlin, no Android imports, so it
 * runs in plain JVM unit tests.
 *
 * Input is one Annex-B access unit (NAL units prefixed with 00 00 01 or
 * 00 00 00 01 start codes). Output is a list of complete RTP packets with a
 * 12-byte header (PT=96, marker on the last packet of the access unit only).
 *
 * Stateful: the RTP sequence number advances across [packetize] calls.
 */
class RtpHevcPacketizer(
    private val mtu: Int = DEFAULT_MTU,
    private val ssrc: Int = DEFAULT_SSRC,
    initialSequenceNumber: Int = 0x1F00
) {
    private var sequenceNumber = initialSequenceNumber and 0xFFFF
    private val history = arrayOfNulls<ByteArray>(2048)

    init { require(mtu in 16..65507) { "MTU must hold an RTP/FU header and payload" } }

    @Synchronized
    fun getPacket(seq: Int): ByteArray? {
        if (seq !in 0..65535) return null
        val packet = history[seq % history.size] ?: return null
        val packetSeq = ((packet[2].toInt() and 0xFF) shl 8) or (packet[3].toInt() and 0xFF)
        return if (packetSeq == seq) packet else null
    }

    /**
     * Converts one Annex-B access unit into RTP packets. Returns an empty list
     * when the access unit carries no sendable NAL units (e.g. only AUDs).
     * Never throws on malformed input.
     */
    @Synchronized
    fun packetize(accessUnit: ByteArray, ptsUs: Long): List<ByteArray> {
        if (accessUnit.size > 8 * 1024 * 1024) return emptyList()
        val timestamp = ptsUs * RTP_CLOCK_HZ / 1_000_000L
        val nals = splitAnnexB(accessUnit).filter { nal ->
            nal.size >= HEVC_NAL_HEADER_SIZE && nalType(nal) != NAL_TYPE_AUD
        }
        if (nals.isEmpty()) return emptyList()

        val packets = mutableListOf<ByteArray>()
        for (nal in nals) {
            if (RTP_HEADER_SIZE + nal.size <= mtu) {
                packets.add(buildSingleNalPacket(nal, timestamp))
            } else {
                packets.addAll(buildFuPackets(nal, timestamp))
            }
        }
        // Marker bit goes only on the final packet of the access unit.
        val last = packets[packets.size - 1]
        last[1] = (last[1].toInt() or 0x80).toByte()
        return packets
    }

    private fun buildSingleNalPacket(nal: ByteArray, timestamp: Long): ByteArray {
        val packet = ByteArray(RTP_HEADER_SIZE + nal.size)
        writeRtpHeader(packet, timestamp)
        System.arraycopy(nal, 0, packet, RTP_HEADER_SIZE, nal.size)
        return packet
    }

    private fun buildFuPackets(nal: ByteArray, timestamp: Long): List<ByteArray> {
        val type = nalType(nal)
        val fuIndicator0 = (nal[0].toInt() and 0x81) or (NAL_TYPE_FU shl 1)
        val fuIndicator1 = nal[1].toInt()
        val maxChunk = mtu - RTP_HEADER_SIZE - FU_HEADER_TOTAL
        val payloadSize = nal.size - HEVC_NAL_HEADER_SIZE
        val packets = mutableListOf<ByteArray>()
        var offset = HEVC_NAL_HEADER_SIZE
        var sent = 0
        while (sent < payloadSize) {
            val chunkSize = minOf(maxChunk, payloadSize - sent)
            val packet = ByteArray(RTP_HEADER_SIZE + FU_HEADER_TOTAL + chunkSize)
            writeRtpHeader(packet, timestamp)
            packet[RTP_HEADER_SIZE] = fuIndicator0.toByte()
            packet[RTP_HEADER_SIZE + 1] = fuIndicator1.toByte()
            var fuHeader = type
            if (sent == 0) fuHeader = fuHeader or FU_START_BIT
            if (sent + chunkSize == payloadSize) fuHeader = fuHeader or FU_END_BIT
            packet[RTP_HEADER_SIZE + 2] = fuHeader.toByte()
            System.arraycopy(nal, offset, packet, RTP_HEADER_SIZE + FU_HEADER_TOTAL, chunkSize)
            packets.add(packet)
            offset += chunkSize
            sent += chunkSize
        }
        return packets
    }

    private fun writeRtpHeader(packet: ByteArray, timestamp: Long) {
        packet[0] = 0x80.toByte() // V=2, P=0, X=0, CC=0
        packet[1] = PAYLOAD_TYPE.toByte() // marker applied later on last packet
        packet[2] = (sequenceNumber shr 8).toByte()
        packet[3] = (sequenceNumber and 0xFF).toByte()
        history[sequenceNumber % history.size] = packet
        sequenceNumber = (sequenceNumber + 1) and 0xFFFF
        packet[4] = (timestamp shr 24).toByte()
        packet[5] = (timestamp shr 16).toByte()
        packet[6] = (timestamp shr 8).toByte()
        packet[7] = timestamp.toByte()
        packet[8] = (ssrc shr 24).toByte()
        packet[9] = (ssrc shr 16).toByte()
        packet[10] = (ssrc shr 8).toByte()
        packet[11] = ssrc.toByte()
    }

    companion object {
        const val DEFAULT_MTU = 1400
        const val DEFAULT_SSRC = 0x50434B36
        const val PAYLOAD_TYPE = 96
        const val RTP_HEADER_SIZE = 12
        const val HEVC_NAL_HEADER_SIZE = 2
        const val NAL_TYPE_AUD = 35
        const val NAL_TYPE_FU = 49
        private const val FU_HEADER_TOTAL = 3 // 2-byte payload header + 1-byte FU header
        private const val FU_START_BIT = 0x80
        private const val FU_END_BIT = 0x40
        private const val RTP_CLOCK_HZ = 90_000L

        fun nalType(nal: ByteArray): Int {
            return if (nal.isEmpty()) -1 else (nal[0].toInt() shr 1) and 0x3F
        }

        /**
         * Splits an Annex-B buffer into NAL units (start codes stripped,
         * trailing zero bytes trimmed). Buffers without any start code are
         * returned as a single NAL unit; empty NALs are dropped.
         */
        fun splitAnnexB(data: ByteArray): List<ByteArray> {
            val nals = mutableListOf<ByteArray>()
            var nalStart = -1
            var i = 0
            while (i + 2 < data.size) {
                if (data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 1.toByte()) {
                    if (nalStart >= 0) {
                        addTrimmed(nals, data, nalStart, i)
                    }
                    i += 3
                    nalStart = i
                } else {
                    i++
                }
            }
            if (nalStart >= 0) {
                addTrimmed(nals, data, nalStart, data.size)
            } else if (data.isNotEmpty()) {
                // No start code at all: treat the whole buffer as one NAL unit.
                addTrimmed(nals, data, 0, data.size)
            }
            return nals
        }

        private fun addTrimmed(nals: MutableList<ByteArray>, data: ByteArray, start: Int, end: Int) {
            var trimmedEnd = end
            while (trimmedEnd > start && data[trimmedEnd - 1] == 0.toByte()) {
                trimmedEnd--
            }
            if (trimmedEnd > start) {
                nals.add(data.copyOfRange(start, trimmedEnd))
            }
        }
    }
}
