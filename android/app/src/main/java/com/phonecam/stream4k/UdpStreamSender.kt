package com.phonecam.stream4k

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicLong

/**
 * Sends RTP-packetized HEVC access units to a fixed (ip, port) over UDP.
 *
 * Access units arrive on the encoder drain thread via [onAccessUnit] and are
 * handed to a sender thread through a bounded queue. When the queue is full
 * the oldest access unit is dropped (counted) — the encoder never blocks.
 */
class UdpStreamSender(
    private val targetIp: String,
    private val targetPort: Int,
    private val packetizer: RtpHevcPacketizer = RtpHevcPacketizer(),
    private val onStats: ((Stats) -> Unit)? = null
) {
    data class Stats(
        val framesSent: Long,
        val packetsSent: Long,
        val bytesSent: Long,
        val droppedFrames: Long,
        val fps: Int,
        val mbps: Double
    )

    private data class QueuedAccessUnit(val annexB: ByteArray, val ptsUs: Long)

    private val queue = ArrayBlockingQueue<QueuedAccessUnit>(QUEUE_CAPACITY_AUS)
    private val framesSent = AtomicLong()
    private val packetsSent = AtomicLong()
    private val bytesSent = AtomicLong()
    private val droppedFrames = AtomicLong()
    @Volatile private var running = false
    private var socket: DatagramSocket? = null
    private var senderThread: Thread? = null

    @Synchronized
    fun start() {
        if (running) return
        running = true
        queue.clear()
        framesSent.set(0)
        packetsSent.set(0)
        bytesSent.set(0)
        droppedFrames.set(0)
        senderThread = Thread({ sendLoop() }, "PhoneCam4kSender").apply {
            isDaemon = true
            start()
        }
    }

    /** Called on the encoder thread. Never blocks: drops the oldest AU when full. */
    fun onAccessUnit(annexB: ByteArray, ptsUs: Long, isKeyFrame: Boolean) {
        if (!running) return
        // Key frames are preceded by parameter sets; keep them as-is, the
        // packetizer drops AUD and passes VPS/SPS/PPS through.
        if (!queue.offer(QueuedAccessUnit(annexB, ptsUs))) {
            queue.poll()
            droppedFrames.incrementAndGet()
            queue.offer(QueuedAccessUnit(annexB, ptsUs))
        }
    }

    /** Retransmits a stored packet. Thread-safe, called from control thread. */
    fun retransmitPacket(seq: Int) {
        val packet = packetizer.getPacket(seq) ?: return
        val address = try {
            InetAddress.getByName(targetIp)
        } catch (e: Exception) {
            return
        }
        val datagramSocket = socket ?: return
        try {
            datagramSocket.send(DatagramPacket(packet, packet.size, address, targetPort))
        } catch (e: Exception) {
            Log.w(TAG, "NACK retransmit failed for seq $seq", e)
        }
    }

    @Synchronized
    fun stop() {
        running = false
        senderThread?.join(1_000)
        senderThread = null
        try {
            socket?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Socket close failed", e)
        }
        socket = null
        queue.clear()
    }

    private fun sendLoop() {
        val address = try {
            InetAddress.getByName(targetIp)
        } catch (e: Exception) {
            Log.e(TAG, "Bad target address $targetIp", e)
            running = false
            return
        }
        val datagramSocket = try {
            DatagramSocket()
        } catch (e: Exception) {
            Log.e(TAG, "Socket create failed", e)
            running = false
            return
        }
        socket = datagramSocket

        var windowStartMs = System.currentTimeMillis()
        var windowFrames = 0L
        var windowBytes = 0L

        while (running) {
            val unit = try {
                queue.poll(100, java.util.concurrent.TimeUnit.MILLISECONDS)
            } catch (e: InterruptedException) {
                null
            } ?: continue

            val packets = try {
                packetizer.packetize(unit.annexB, unit.ptsUs)
            } catch (e: Exception) {
                Log.w(TAG, "Packetize failed", e)
                continue
            }
            for (packet in packets) {
                try {
                    datagramSocket.send(DatagramPacket(packet, packet.size, address, targetPort))
                    packetsSent.incrementAndGet()
                    bytesSent.addAndGet(packet.size.toLong())
                    windowBytes += packet.size
                } catch (e: Exception) {
                    if (running) Log.w(TAG, "UDP send failed", e)
                }
            }
            if (packets.isNotEmpty()) {
                framesSent.incrementAndGet()
                windowFrames++
            }

            val nowMs = System.currentTimeMillis()
            val elapsedMs = nowMs - windowStartMs
            if (elapsedMs >= 1_000) {
                val stats = Stats(
                    framesSent = framesSent.get(),
                    packetsSent = packetsSent.get(),
                    bytesSent = bytesSent.get(),
                    droppedFrames = droppedFrames.get(),
                    fps = (windowFrames * 1_000 / elapsedMs).toInt(),
                    mbps = windowBytes * 8.0 * 1_000 / (elapsedMs * 1_000_000.0)
                )
                windowStartMs = nowMs
                windowFrames = 0
                windowBytes = 0
                try {
                    onStats?.invoke(stats)
                } catch (e: Exception) {
                    Log.w(TAG, "Stats callback failed", e)
                }
            }
        }
    }

    companion object {
        private const val TAG = "UdpStreamSender"
        private const val QUEUE_CAPACITY_AUS = 8
    }
}
