package com.phonecam.stream4k

import android.util.Log
import java.io.DataOutputStream
import java.io.IOException
import java.net.Socket
import java.util.concurrent.ArrayBlockingQueue

class TcpStreamSender(
    private val socket: Socket,
    private val onStats: ((UdpStreamSender.Stats) -> Unit)? = null
) {
    private data class QueuedPacket(val channel: Byte, val data: ByteArray)

    private val queue = ArrayBlockingQueue<QueuedPacket>(QUEUE_CAPACITY)
    @Volatile private var running = false
    private var senderThread: Thread? = null
    private val outputStream = DataOutputStream(socket.getOutputStream())

    fun start() {
        if (running) return
        running = true
        queue.clear()
        senderThread = Thread({ sendLoop() }, "PhoneCamTcpSender").apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        running = false
        senderThread?.interrupt()
        senderThread = null
        try {
            socket.close()
        } catch (e: Exception) {
            // ignore
        }
        queue.clear()
    }

    /** Called on encoder or control thread. Never blocks. */
    fun sendFrame(channel: Byte, data: ByteArray) {
        if (!running) return
        if (!queue.offer(QueuedPacket(channel, data))) {
            queue.poll()
            queue.offer(QueuedPacket(channel, data))
        }
    }

    private fun sendLoop() {
        var windowStartMs = System.currentTimeMillis()
        var windowFrames = 0L
        var windowBytes = 0L
        var framesSent = 0L
        var packetsSent = 0L
        var bytesSent = 0L

        while (running) {
            val packet = try {
                queue.poll(100, java.util.concurrent.TimeUnit.MILLISECONDS)
            } catch (e: InterruptedException) {
                null
            } ?: continue

            try {
                // Header: Channel (1 byte), Reserved (1 byte), Length (4 bytes)
                outputStream.writeByte(packet.channel.toInt())
                outputStream.writeByte(0)
                outputStream.writeInt(packet.data.size)
                outputStream.write(packet.data)
                outputStream.flush()

                packetsSent++
                val size = 6 + packet.data.size
                bytesSent += size
                windowBytes += size
                if (packet.channel == 2.toByte()) {
                    val rtp = packet.data
                    if (rtp.size >= 12 && (rtp[1].toInt() and 0x80 != 0)) {
                        framesSent++
                        windowFrames++
                    }
                }
            } catch (e: IOException) {
                Log.e(TAG, "TCP send failed, closing connection", e)
                running = false
                break
            }

            val nowMs = System.currentTimeMillis()
            val elapsedMs = nowMs - windowStartMs
            if (elapsedMs >= 1_000) {
                val stats = UdpStreamSender.Stats(
                    framesSent = framesSent,
                    packetsSent = packetsSent,
                    bytesSent = bytesSent,
                    droppedFrames = 0,
                    fps = (windowFrames * 1_000 / elapsedMs).toInt(),
                    mbps = windowBytes * 8.0 * 1_000 / (elapsedMs * 1_000_000.0)
                )
                windowStartMs = nowMs
                windowFrames = 0
                windowBytes = 0
                try {
                    onStats?.invoke(stats)
                } catch (e: Exception) {
                    // ignore
                }
            }
        }
    }

    companion object {
        private const val TAG = "TcpStreamSender"
        private const val QUEUE_CAPACITY = 128
    }
}
