package com.phonecam.stream4k

import android.util.Log
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.net.Socket
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** One writer owns the stream. Media is queued atomically by access unit. */
class TcpStreamSender(
    private val socket: Socket,
    private val onStats: ((UdpStreamSender.Stats) -> Unit)? = null
) {
    private data class Batch(val channel: Int, val packets: List<ByteArray>) {
        val bytes: Long = packets.sumOf { it.size.toLong() + 6 }
    }
    private val queue = ArrayBlockingQueue<Batch>(8)
    private val queuedBytes = AtomicLong()
    @Volatile private var running = false
    private var senderThread: Thread? = null
    private val outputStream = DataOutputStream(BufferedOutputStream(socket.getOutputStream(), 64 * 1024))

    fun start() {
        if (running) return
        socket.tcpNoDelay = true
        running = true
        senderThread = Thread({ sendLoop() }, "PhoneCamTcpSender").apply { isDaemon = true; start() }
    }

    fun stop() {
        running = false
        // Closing the socket unblocks a writer whose peer has stopped reading.
        try { socket.close() } catch (_: Exception) { }
        senderThread?.interrupt()
        senderThread?.takeIf { it !== Thread.currentThread() }?.join()
        senderThread = null
        queue.clear()
        queuedBytes.set(0)
    }

    fun sendFrame(channel: Byte, data: ByteArray) = enqueue(Batch(channel.toInt(), listOf(data)))
    fun sendAccessUnit(packets: List<ByteArray>) = enqueue(Batch(2, packets))

    private fun enqueue(batch: Batch) {
        if (!running || batch.packets.isEmpty()) return
        if (batch.packets.any { it.isEmpty() || it.size > 65535 } ||
            queuedBytes.addAndGet(batch.bytes) > MAX_QUEUED_BYTES || !queue.offer(batch)) {
            // Never discard an arbitrary RTP fragment or a control response. Once
            // reliable delivery cannot keep up, disconnect and renegotiate a lower mode.
            running = false
            try { socket.close() } catch (_: Exception) { }
        }
    }

    private fun sendLoop() {
        var start = System.nanoTime()
        var frames = 0L
        var packets = 0L
        var bytes = 0L
        var windowFrames = 0L
        var windowBytes = 0L
        try {
            while (running) {
                val batch = queue.poll(100, TimeUnit.MILLISECONDS) ?: continue
                queuedBytes.addAndGet(-batch.bytes)
                for (packet in batch.packets) {
                    outputStream.writeByte(batch.channel)
                    outputStream.writeByte(0)
                    outputStream.writeInt(packet.size)
                    outputStream.write(packet)
                    packets++
                    bytes += packet.size + 6
                    windowBytes += packet.size + 6
                }
                outputStream.flush()
                if (batch.channel == 2) { frames++; windowFrames++ }
                val elapsed = (System.nanoTime() - start) / 1_000_000L
                if (elapsed >= 1000) {
                    onStats?.invoke(UdpStreamSender.Stats(frames, packets, bytes, 0,
                        (windowFrames * 1000 / elapsed).toInt(), windowBytes * 8.0 / (elapsed * 1000)))
                    start = System.nanoTime(); windowFrames = 0; windowBytes = 0
                }
            }
        } catch (error: Exception) {
            if (running) Log.w(TAG, "TCP writer disconnected", error)
        } finally {
            running = false
            try { socket.close() } catch (_: Exception) { }
            queue.clear()
            queuedBytes.set(0)
        }
    }

    companion object {
        private const val TAG = "TcpStreamSender"
        private const val MAX_QUEUED_BYTES = 16 * 1024 * 1024L
    }
}
