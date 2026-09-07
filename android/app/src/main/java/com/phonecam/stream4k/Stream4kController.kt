package com.phonecam.stream4k

import android.content.Context
import android.media.MediaCodec
import android.util.Log
import android.view.Surface
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.charset.StandardCharsets

/**
 * Orchestrates probe -> encoder -> camera -> sender for the 4K60 UDP path and
 * answers the PHONECAM4K text control protocol on UDP port 47822.
 *
 * Lifecycle-safe: [stop] is idempotent and the controller survives repeated
 * start/stop cycles. All heavy resources (camera, codec, sockets) are
 * released in [stop] / [release].
 */
open class Stream4kController(context: Context) {
    interface Listener {
        /** Human-readable state line for the UI. Called on arbitrary threads. */
        fun onStatus(message: String)
    }

    var listener: Listener? = null
    @Volatile private var foreground = false

    @Synchronized
    fun setForeground(active: Boolean) {
        foreground = active
        if (!active) stop()
    }

    private val appContext = context.applicationContext
    private val rtpPacketizer = RtpHevcPacketizer()
    @Volatile internal var probe: DeviceCapabilitiesSource = AndroidCapabilityProbe(appContext)

    @Volatile private var persistentSurface: Surface? = null
    @Volatile var encoder: HevcEncoder? = null
        internal set
    @Volatile private var camera: Camera2Pipeline? = null
    @Volatile private var sender: UdpStreamSender? = null
    @Volatile var activeLadder: Ladder? = null
        internal set
    @Volatile var negotiatedLadder: Ladder? = null
        internal set
    @Volatile var consecutiveGoodReports = 0
        internal set
    @Volatile private var controlRunning = false
    @Volatile private var controlGeneration = 0L
    private var controlThread: Thread? = null
    private var controlSocket: DatagramSocket? = null
    @Volatile var lastPeerAddress: InetAddress? = null
        private set
    @Volatile var lastPeerPort: Int? = null
        private set
    @Volatile var currentBitrate = 0
        internal set
    @Volatile private var lastMessageTime = 0L
    @Volatile private var keepaliveThread: Thread? = null
    private var tcpServerSocket: java.net.ServerSocket? = null
    @Volatile private var tcpClientSocket: java.net.Socket? = null
    @Volatile private var tcpSender: TcpStreamSender? = null
    private var tcpControlThread: Thread? = null

    fun availableLadders(): List<Ladder> = probe.availableLadders()
    fun probeLadder(): Ladder? = availableLadders().firstOrNull()

    fun capabilityReport(): String {
        val p = probe
        return if (p is AndroidCapabilityProbe) {
            p.report()
        } else {
            "Fake Capabilities"
        }
    }

    @Synchronized
    open fun start(ladder: Ladder, targetIp: String, targetPort: Int): Boolean {
        if (!foreground || appContext.checkSelfPermission(android.Manifest.permission.CAMERA) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED) return false
        stopStreaming()
        return try {
            val surface = MediaCodec.createPersistentInputSurface()
            persistentSurface = surface
            val hevcEncoder = HevcEncoder()
            encoder = hevcEncoder
            val activeTcpSender = tcpSender
            val udpSender = if (activeTcpSender == null) {
                UdpStreamSender(
                    targetIp = targetIp,
                    targetPort = targetPort,
                    packetizer = rtpPacketizer,
                    onKeyFrameNeeded = { hevcEncoder.requestKeyFrame() },
                    onStats = { stats ->
                        listener?.onStatus(
                            "4K UDP ${ladder.width}x${ladder.height}@${ladder.fps}: " +
                                "${stats.fps} fps, ${String.format(java.util.Locale.US, "%.1f", stats.mbps)} Mbps, " +
                                "${stats.packetsSent} pkts, ${stats.droppedFrames} dropped"
                        )
                    }
                )
            } else null
            sender = udpSender

            hevcEncoder.callback = object : HevcEncoder.Callback {
                private val packetizer = rtpPacketizer

                override fun onAccessUnit(annexB: ByteArray, ptsUs: Long, isKeyFrame: Boolean) {
                    if (activeTcpSender != null) {
                        val packets = packetizer.packetize(annexB, ptsUs)
                        activeTcpSender.sendAccessUnit(packets)
                    } else {
                        udpSender?.onAccessUnit(annexB, ptsUs, isKeyFrame)
                    }
                }

                override fun onError(message: String) {
                    Log.e(TAG, message)
                    listener?.onStatus("4K encoder error: $message")
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        synchronized(this@Stream4kController) { if (encoder === hevcEncoder) stopStreaming() }
                    }
                }
            }
            hevcEncoder.configure(
                width = ladder.width,
                height = ladder.height,
                bitrateBps = ladder.bitrateBps,
                fps = ladder.fps,
                persistentInputSurface = surface,
                encoderName = ladder.encoderName
            )
            val cameraPipeline = Camera2Pipeline(appContext)
            cameraPipeline.stateCallback = object : Camera2Pipeline.StateCallback {
                override fun onStreamingStarted() {
                    listener?.onStatus("4K camera streaming: ${ladder.summary}")
                }

                override fun onStreamingStopped() {
                    listener?.onStatus("4K camera stopped")
                }

                override fun onError(message: String) {
                    listener?.onStatus("4K camera error: $message")
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        synchronized(this@Stream4kController) { if (camera === cameraPipeline) stopStreaming() }
                    }
                }
            }

            persistentSurface = surface
            encoder = hevcEncoder
            sender = udpSender
            camera = cameraPipeline
            activeLadder = ladder
            currentBitrate = ladder.bitrateBps
            consecutiveGoodReports = 0
            lastMessageTime = System.currentTimeMillis()

            udpSender?.start()
            hevcEncoder.start()
            cameraPipeline.open(ladder, surface)
            startKeepaliveMonitor()
            Log.i(TAG, "4K start -> $targetIp:$targetPort ${ladder.summary} (TCP=${activeTcpSender != null})")
            true
        } catch (e: Exception) {
            Log.e(TAG, "4K start failed", e)
            listener?.onStatus("4K start failed: ${e.message}")
            stopStreaming()
            false
        }
    }

    /** Full stop: streaming resources plus the control listener. */
    @Synchronized
    fun stop() {
        stopStreaming()
        stopControlListener()
    }

    /** Idempotent streaming-only stop; the control listener keeps running. */
    @Synchronized
    fun stopStreaming() {
        stopKeepaliveMonitor()
        camera?.close()
        camera = null
        try {
            encoder?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Encoder release failed", e)
        }
        encoder = null
        sender?.stop()
        sender = null
        try {
            persistentSurface?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Persistent surface release failed", e)
        }
        persistentSurface = null
        activeLadder = null
        consecutiveGoodReports = 0
    }

    fun isStreaming(): Boolean = encoder != null

    @Synchronized
    private fun startKeepaliveMonitor() {
        stopKeepaliveMonitor()
        lastMessageTime = System.currentTimeMillis()
        keepaliveThread = Thread({
            while (isStreaming()) {
                try {
                    Thread.sleep(1000)
                } catch (e: InterruptedException) {
                    break
                }
                if (System.currentTimeMillis() - lastMessageTime > 5000) {
                    Log.w(TAG, "ABR/Keepalive: Timeout. No control messages received from peer in 5s. Stopping stream.")
                    listener?.onStatus("4K UDP stopped: client timeout")
                    stopStreaming()
                    break
                }
            }
        }, "PhoneCamKeepaliveMonitor").apply {
            isDaemon = true
            start()
        }
    }

    @Synchronized
    private fun stopKeepaliveMonitor() {
        keepaliveThread?.interrupt()
        keepaliveThread = null
    }

    // ------------------------------------------------------------------
    // UDP control protocol on port 47822
    // ------------------------------------------------------------------

    @Synchronized
    fun startControlListener() {
        if (!foreground) return
        if (controlRunning) return
        try {
            // Bind before publishing worker threads so stop cannot miss a late socket.
            val udp = DatagramSocket(CONTROL_PORT)
            controlSocket = udp
            val tcp = java.net.ServerSocket(CONTROL_PORT)
            tcpServerSocket = tcp
            controlRunning = true
            val token = ++controlGeneration
            controlThread = Thread({ controlLoop(udp, token) }, "PhoneCam4kControl").apply { isDaemon = true; start() }
            tcpControlThread = Thread({ tcpControlLoop(tcp, token) }, "PhoneCam4kTcpControl").apply { isDaemon = true; start() }
        } catch (e: Exception) {
            stopControlListener()
            listener?.onStatus("Receiver access failed: ${e.message}")
        }
    }

    @Synchronized
    fun stopControlListener() {
        controlRunning = false
        controlGeneration++
        try {
            controlSocket?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Control socket close failed", e)
        }
        controlSocket = null
        try {
            tcpServerSocket?.close()
        } catch (e: Exception) {
            Log.w(TAG, "TCP ServerSocket close failed", e)
        }
        tcpServerSocket = null
        try {
            tcpClientSocket?.close()
        } catch (e: Exception) {
            Log.w(TAG, "TCP client socket close failed", e)
        }
        tcpClientSocket = null
        tcpSender?.stop()
        tcpSender = null
        controlThread = null
        tcpControlThread?.interrupt()
        tcpControlThread = null
    }

    fun connectToReceiver(host: String, port: Int = 47823) {
        if (port !in 1..65535 || host.isBlank()) return
        synchronized(this) {
            if (!foreground) return
            stop()
            controlRunning = true
            val token = ++controlGeneration
            tcpControlThread = Thread({
                var retry = 0
                while (controlRunning && controlGeneration == token) {
                    val client = java.net.Socket()
                    synchronized(this) {
                        if (!controlRunning || controlGeneration != token) { client.close(); return@Thread }
                        tcpClientSocket = client
                    }
                    try {
                        listener?.onStatus(if (retry == 0) "Connecting to computer…" else "Connection lost. Reconnecting…")
                        client.connect(java.net.InetSocketAddress(host, port), 3000)
                        client.tcpNoDelay = true
                        client.getOutputStream().write("PHONECAM/2\n".toByteArray(StandardCharsets.US_ASCII))
                        handleTcpClient(client, token)
                    } catch (_: Exception) {
                        if (controlRunning && controlGeneration == token)
                            listener?.onStatus("Computer unreachable. Keep the receiver open, allow its home-network access, or check the PC code.")
                    } finally { try { client.close() } catch (_: Exception) {} }
                    retry++
                    if (!controlRunning || controlGeneration != token) break
                    try { Thread.sleep((retry.coerceAtMost(3) * 1000).toLong()) } catch (_: InterruptedException) { break }
                }
            }, "PhoneCamComputerConnection").apply { isDaemon = true; start() }
        }
    }

    private fun tcpControlLoop(serverSocket: java.net.ServerSocket, token: Long) {
        while (controlRunning && controlGeneration == token) {
            val client = try { serverSocket.accept() } catch (_: java.io.IOException) { break }
            handleTcpClient(client, token)
        }
    }

    private fun handleTcpClient(client: java.net.Socket, token: Long) {
        val outSender = try { synchronized(this) {
                if (!controlRunning || controlGeneration != token || isStreaming()) {
                    client.close()
                    null
                } else {
                    tcpClientSocket = client
                    lastPeerAddress = client.inetAddress
                    lastPeerPort = client.port
                    TcpStreamSender(client) { stats ->
                        listener?.onStatus("TCP: ${stats.fps} fps, ${String.format(java.util.Locale.US, "%.1f", stats.mbps)} Mbps, ${stats.packetsSent} pkts")
                    }.also { tcpSender = it; it.start() }
                }
            } } catch (e: Exception) {
                try { client.close() } catch (_: Exception) {}
                null
            } ?: return
            try {
                val input = java.io.DataInputStream(client.getInputStream())
                while (controlRunning && controlGeneration == token) {
                    val channel = input.readByte()
                    val reserved = input.readByte()
                    val length = input.readInt()
                    require(channel == 1.toByte() && reserved == 0.toByte() && length in 1..65535) { "Invalid control record" }
                    val payload = ByteArray(length)
                    input.readFully(payload)
                    
                    if (channel == 1.toByte()) {
                        val text = String(payload, StandardCharsets.UTF_8).trim()
                        val reply = synchronized(this) {
                            if (controlRunning && controlGeneration == token) handleControlCommand(text, client.inetAddress, client.port) else null
                        }
                        if (reply != null) {
                            val replyBytes = reply.toByteArray(StandardCharsets.UTF_8)
                            outSender.sendFrame(1.toByte(), replyBytes)
                        }
                    }
                }
            } catch (e: Exception) {
                if (controlRunning) Log.w(TAG, "TCP client error: ${e.message}")
            } finally {
                synchronized(this) {
                    if (controlGeneration == token && tcpClientSocket === client) {
                        stopStreaming()
                        tcpSender = null
                        tcpClientSocket = null
                    }
                }
                outSender.stop()
                try { client.close() } catch (e: Exception) {}
            }
    }

    private fun controlLoop(socket: DatagramSocket, token: Long) {
        val buffer = ByteArray(65535)
        while (controlRunning && controlGeneration == token) {
            val packet = DatagramPacket(buffer, buffer.size)
            try {
                socket.receive(packet)
            } catch (e: Exception) {
                if (controlRunning) Log.w(TAG, "Control receive failed", e)
                break
            }
            val text = String(packet.data, packet.offset, packet.length, StandardCharsets.UTF_8).trim()
            val reply = synchronized(this) {
                if (controlRunning && controlGeneration == token && tcpSender == null) handleControlCommand(text, packet.address, packet.port) else null
            }
            if (reply != null) {
                try {
                    val payload = reply.toByteArray(StandardCharsets.UTF_8)
                    socket.send(DatagramPacket(payload, payload.size, packet.address, packet.port))
                } catch (e: Exception) {
                    Log.w(TAG, "Control reply failed", e)
                }
            }
        }
    }

    /**
     * Parses one JSON control command and applies it. Returns the JSON reply text or
     * null when no reply is due.
     */
    internal fun handleControlCommand(text: String, peerAddress: InetAddress, peerPort: Int): String? {
        val map = try {
            JsonHelper.parse(text)
        } catch (e: Exception) {
            return null
        }
        val type = map["type"] as? String ?: return null
        if (isStreaming() && lastPeerAddress != null && peerAddress != lastPeerAddress) return null
        
        lastMessageTime = System.currentTimeMillis()
        
        return when (type) {
            "ping" -> {
                val builder = StringBuilder()
                builder.append("{\"version\":\"1.0\",\"type\":\"pong\",\"device_name\":\"Android Phone\",\"capabilities\":{\"ladder\":[")
                builder.append(availableLadders().joinToString(",") {
                    "{\"width\":${it.width},\"height\":${it.height},\"fps\":${it.fps},\"bitrate\":${it.bitrateBps}}"
                })
                builder.append("]},\"state\":\"${if (isStreaming()) "streaming" else "idle"}\"}")
                builder.toString()
            }
            "connect" -> {
                val sel = map["selected_ladder"] as? Map<*, *>
                val w = (sel?.get("width") as? Number)?.toInt() ?: 1920
                val h = (sel?.get("height") as? Number)?.toInt() ?: 1080
                val fps = (sel?.get("fps") as? Number)?.toInt() ?: 60
                val streamPort = (map["stream_port"] as? Number)?.toInt() ?: 5004
                
                val resolved = if (w == 0 && h == 0 && fps == 0) {
                    val modes = availableLadders()
                    modes.firstOrNull { it.width == 1920 && it.height == 1080 && it.fps == 60 }
                        ?: modes.firstOrNull { it.width == 1920 && it.height == 1080 && it.fps == 30 }
                        ?: modes.firstOrNull()
                } else resolveRequestedLadder(w, h, fps, 0)
                if (resolved == null || (streamPort !in 1..65535 && map["transport"] != "tcp")) {
                    "{\"version\":\"1.0\",\"type\":\"connect_ack\",\"status\":\"error\",\"reason\":\"unsupported_ladder\"}"
                } else {
                    lastPeerAddress = peerAddress
                    lastPeerPort = streamPort
                    activeLadder = resolved
                    negotiatedLadder = resolved
                    "{\"version\":\"1.0\",\"type\":\"connect_ack\",\"status\":\"success\",\"selected_ladder\":{\"width\":${resolved.width},\"height\":${resolved.height},\"fps\":${resolved.fps},\"bitrate\":${resolved.bitrateBps}}}"
                }
            }
            "start" -> {
                val ladder = activeLadder ?: return "{\"version\":\"1.0\",\"type\":\"start_ack\",\"status\":\"error\",\"reason\":\"connect_required\"}"
                val ip = lastPeerAddress?.hostAddress ?: peerAddress.hostAddress
                val port = lastPeerPort ?: 5004
                val ok = start(ladder, ip, port)
                if (ok) {
                    "{\"version\":\"1.0\",\"type\":\"start_ack\",\"status\":\"success\"}"
                } else {
                    "{\"version\":\"1.0\",\"type\":\"start_ack\",\"status\":\"error\"}"
                }
            }
            "stop" -> {
                stopStreaming()
                "{\"version\":\"1.0\",\"type\":\"stop_ack\",\"status\":\"success\"}"
            }
            "nack" -> {
                val seqs = map["seqs"] as? List<*>
                if (seqs != null) {
                    for (seqObj in seqs) {
                        val seq = (seqObj as? Number)?.toInt()
                        if (seq != null) {
                            sender?.retransmitPacket(seq)
                        }
                    }
                }
                null
            }
            "pli" -> {
                encoder?.requestKeyFrame()
                null
            }
            "feedback" -> {
                val lossFractionObj = map["loss_fraction"] as? Number
                val lossFraction = lossFractionObj?.toDouble() ?: 0.0
                val jitterMsObj = map["jitter_ms"] as? Number
                val jitterMs = jitterMsObj?.toDouble() ?: 0.0
                handleBitrateAdaptation(lossFraction, jitterMs)
                null
            }
            else -> null
        }
    }

    internal fun handleBitrateAdaptation(lossFraction: Double, jitterMs: Double) {
        val ladder = activeLadder ?: return
        val enc = encoder ?: return
        if (lossFraction > 0.02) {
            consecutiveGoodReports = 0
            val minBitrate = ladder.bitrateBps / 2
            if (currentBitrate > minBitrate) {
                currentBitrate = (currentBitrate * 0.9).toInt().coerceAtLeast(minBitrate)
                enc.setBitrate(currentBitrate)
                Log.i(TAG, "ABR: loss $lossFraction > 2%, decreasing bitrate to $currentBitrate Bps")
            } else {
                val nextLadder = getNextLowerLadder(ladder)
                if (nextLadder != null) {
                    Log.i(TAG, "ABR: loss $lossFraction at floor, stepping down ladder to ${nextLadder.summary}")
                    val ip = lastPeerAddress?.hostAddress ?: "127.0.0.1"
                    val port = lastPeerPort ?: 5004
                    Thread {
                        start(nextLadder, ip, port)
                    }.start()
                }
            }
        } else if (lossFraction < 0.005 && jitterMs < 10.0) {
            consecutiveGoodReports++
            if (consecutiveGoodReports >= 10) {
                consecutiveGoodReports = 0
                if (currentBitrate >= ladder.bitrateBps) {
                    val negotiated = negotiatedLadder
                    if (negotiated != null && isLadderLowerThan(ladder, negotiated)) {
                        val nextLadder = getNextHigherLadder(ladder)
                        if (nextLadder != null && !isLadderLowerThan(negotiated, nextLadder)) {
                            Log.i(TAG, "ABR: 10 consecutive good reports, stepping up ladder to ${nextLadder.summary}")
                            val ip = lastPeerAddress?.hostAddress ?: "127.0.0.1"
                            val port = lastPeerPort ?: 5004
                            Thread {
                                start(nextLadder, ip, port)
                            }.start()
                        }
                    }
                } else {
                    currentBitrate = (currentBitrate * 1.10).toInt().coerceAtMost(ladder.bitrateBps)
                    enc.setBitrate(currentBitrate)
                    Log.i(TAG, "ABR: 10 consecutive good reports, increasing bitrate to $currentBitrate Bps")
                }
            }
        } else {
            consecutiveGoodReports = 0
        }
    }

    internal fun getNextLowerLadder(current: Ladder): Ladder? {
        return availableLadders().filter { isLadderLowerThan(it, current) && it.bitrateBps < current.bitrateBps &&
            (negotiatedLadder == null || it.fps <= negotiatedLadder!!.fps) }
            .maxWithOrNull(compareBy<Ladder> { it.width }.thenBy { it.height }.thenBy { it.fps })
    }

    internal fun getNextHigherLadder(current: Ladder): Ladder? {
        val limit = negotiatedLadder
        return availableLadders().filter {
            isLadderLowerThan(current, it) && it.bitrateBps > current.bitrateBps &&
                (limit == null || (!isLadderLowerThan(limit, it) && it.fps <= limit.fps))
        }.minWithOrNull(compareBy<Ladder> { it.width }.thenBy { it.height }.thenBy { it.fps })
    }

    internal fun isLadderLowerThan(a: Ladder, b: Ladder): Boolean {
        if (a.width < b.width) return true
        if (a.width == b.width && a.height < b.height) return true
        if (a.width == b.width && a.height == b.height && a.fps < b.fps) return true
        return false
    }

    private fun resolveRequestedLadder(width: Int, height: Int, fps: Int, bitrateBps: Int): Ladder? {
        if (width !in 1..3840 || height !in 1..2160 || fps !in 1..240) return null
        val modes = availableLadders()
        return modes.firstOrNull { it.width == width && it.height == height && it.fps == fps }
            ?: modes.firstOrNull { it.width <= width && it.height <= height && it.fps <= fps }
    }

    companion object {
        private const val TAG = "Stream4kController"
        const val CONTROL_PORT = 47822
        const val CONTROL_MAGIC = "PHONECAM4K"
        const val DEFAULT_STREAM_PORT = 5004
        private const val DEFAULT_FALLBACK_BITRATE = 12_000_000
    }
}
