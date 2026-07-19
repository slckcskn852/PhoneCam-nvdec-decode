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

    private val appContext = context.applicationContext
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

    fun probeLadder(): Ladder? {
        val p = probe
        return if (p is AndroidCapabilityProbe) {
            p.probe()
        } else {
            CapabilityProbe.chooseLadder(p.supportedCombos(), p.hasHevcEncoder(), p.normalSessionCombos())
        }
    }

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
        stopStreaming()
        return try {
            val surface = MediaCodec.createPersistentInputSurface()
            val hevcEncoder = HevcEncoder()
            val activeTcpSender = tcpSender
            val udpSender = if (activeTcpSender == null) {
                UdpStreamSender(
                    targetIp = targetIp,
                    targetPort = targetPort,
                    onStats = { stats ->
                        listener?.onStatus(
                            "4K UDP ${ladder.width}x${ladder.height}@${ladder.fps}: " +
                                "${stats.fps} fps, ${String.format(java.util.Locale.US, "%.1f", stats.mbps)} Mbps, " +
                                "${stats.packetsSent} pkts, ${stats.droppedFrames} dropped"
                        )
                    }
                )
            } else null

            hevcEncoder.callback = object : HevcEncoder.Callback {
                private val packetizer = RtpHevcPacketizer()

                override fun onAccessUnit(annexB: ByteArray, ptsUs: Long, isKeyFrame: Boolean) {
                    if (activeTcpSender != null) {
                        val packets = packetizer.packetize(annexB, ptsUs)
                        for (packet in packets) {
                            activeTcpSender.sendFrame(2.toByte(), packet)
                        }
                    } else {
                        udpSender?.onAccessUnit(annexB, ptsUs, isKeyFrame)
                    }
                }

                override fun onError(message: String) {
                    Log.e(TAG, message)
                    listener?.onStatus("4K encoder error: $message")
                }
            }
            hevcEncoder.configure(
                width = ladder.width,
                height = ladder.height,
                bitrateBps = ladder.bitrateBps,
                fps = ladder.fps,
                persistentInputSurface = surface
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
        if (controlRunning) return
        controlRunning = true
        controlThread = Thread({ controlLoop() }, "PhoneCam4kControl").apply {
            isDaemon = true
            start()
        }
        tcpControlThread = Thread({ tcpControlLoop() }, "PhoneCam4kTcpControl").apply {
            isDaemon = true
            start()
        }
    }

    @Synchronized
    fun stopControlListener() {
        controlRunning = false
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
        controlThread?.join(500)
        controlThread = null
        tcpControlThread?.join(500)
        tcpControlThread = null
    }

    private fun tcpControlLoop() {
        val serverSocket = try {
            java.net.ServerSocket(CONTROL_PORT)
        } catch (e: Exception) {
            Log.e(TAG, "TCP control listener bind failed on $CONTROL_PORT", e)
            return
        }
        tcpServerSocket = serverSocket
        while (controlRunning) {
            val client = try {
                serverSocket.accept()
            } catch (e: java.io.IOException) {
                break
            }
            tcpClientSocket = client
            try {
                val input = java.io.DataInputStream(client.getInputStream())
                val outSender = TcpStreamSender(client) { stats ->
                    listener?.onStatus(
                        "4K TCP ${activeLadder?.width}x${activeLadder?.height}: " +
                            "${stats.fps} fps, ${String.format(java.util.Locale.US, "%.1f", stats.mbps)} Mbps, " +
                            "${stats.packetsSent} pkts"
                    )
                }
                tcpSender = outSender
                outSender.start()
                
                lastPeerAddress = client.inetAddress
                lastPeerPort = client.port
                
                while (controlRunning) {
                    val channel = input.readByte()
                    val reserved = input.readByte()
                    val length = input.readInt()
                    val payload = ByteArray(length)
                    input.readFully(payload)
                    
                    if (channel == 1.toByte()) {
                        val text = String(payload, StandardCharsets.UTF_8).trim()
                        val reply = handleControlCommand(text, client.inetAddress, client.port)
                        if (reply != null) {
                            val replyBytes = reply.toByteArray(StandardCharsets.UTF_8)
                            outSender.sendFrame(1.toByte(), replyBytes)
                        }
                    }
                }
            } catch (e: Exception) {
                if (controlRunning) Log.w(TAG, "TCP client error: ${e.message}")
            } finally {
                tcpSender?.stop()
                tcpSender = null
                try { client.close() } catch (e: Exception) {}
                tcpClientSocket = null
            }
        }
    }

    private fun controlLoop() {
        val socket = try {
            DatagramSocket(CONTROL_PORT)
        } catch (e: Exception) {
            Log.e(TAG, "Control listener bind failed on $CONTROL_PORT", e)
            controlRunning = false
            return
        }
        controlSocket = socket
        val buffer = ByteArray(1024)
        while (controlRunning) {
            val packet = DatagramPacket(buffer, buffer.size)
            try {
                socket.receive(packet)
            } catch (e: Exception) {
                if (controlRunning) Log.w(TAG, "Control receive failed", e)
                break
            }
            lastPeerAddress = packet.address
            val text = String(packet.data, packet.offset, packet.length, StandardCharsets.UTF_8).trim()
            val reply = handleControlCommand(text, packet.address, packet.port)
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
        
        lastMessageTime = System.currentTimeMillis()
        
        return when (type) {
            "ping" -> {
                val ladder = probeLadder()
                val builder = StringBuilder()
                builder.append("{\"version\":\"1.0\",\"type\":\"pong\",\"device_name\":\"Android Phone\",\"capabilities\":{\"ladder\":[")
                builder.append("{\"width\":3840,\"height\":2160,\"fps\":60,\"bitrate\":35000000},")
                builder.append("{\"width\":3840,\"height\":2160,\"fps\":30,\"bitrate\":25000000},")
                builder.append("{\"width\":1920,\"height\":1080,\"fps\":60,\"bitrate\":12000000}")
                builder.append("]},\"state\":\"${if (isStreaming()) "streaming" else "idle"}\"}")
                builder.toString()
            }
            "connect" -> {
                val sel = map["selected_ladder"] as? Map<*, *>
                val w = (sel?.get("width") as? Number)?.toInt() ?: 1920
                val h = (sel?.get("height") as? Number)?.toInt() ?: 1080
                val fps = (sel?.get("fps") as? Number)?.toInt() ?: 60
                val streamPort = (map["stream_port"] as? Number)?.toInt() ?: 5004
                
                val resolved = resolveRequestedLadder(w, h, fps, 0)
                if (resolved == null) {
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
                val ladder = activeLadder ?: resolveRequestedLadder(1920, 1080, 60, 0)!!
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
        val combos = try { probe.supportedCombos() } catch (e: Exception) { emptySet() }
        val normalSession = try { probe.normalSessionCombos() } catch (e: Exception) { combos }
        
        if (current.width == 3840 && current.height == 2160 && current.fps == 60) {
            val c4k30 = Triple(3840, 2160, 30)
            if (c4k30 in combos) {
                return Ladder(3840, 2160, 30, c4k30 !in normalSession, 25_000_000, "4K30 HEVC fallback")
            }
            val c1080p60 = Triple(1920, 1080, 60)
            if (c1080p60 in combos) {
                return Ladder(1920, 1080, 60, c1080p60 !in normalSession, 12_000_000, "1080p60 HEVC fallback")
            }
        } else if (current.width == 3840 && current.height == 2160 && current.fps == 30) {
            val c1080p60 = Triple(1920, 1080, 60)
            if (c1080p60 in combos) {
                return Ladder(1920, 1080, 60, c1080p60 !in normalSession, 12_000_000, "1080p60 HEVC fallback")
            }
        }
        return null
    }

    internal fun getNextHigherLadder(current: Ladder): Ladder? {
        val combos = try { probe.supportedCombos() } catch (e: Exception) { emptySet() }
        val normalSession = try { probe.normalSessionCombos() } catch (e: Exception) { combos }
        
        if (current.width == 1920 && current.height == 1080 && current.fps == 60) {
            val c4k30 = Triple(3840, 2160, 30)
            if (c4k30 in combos) {
                return Ladder(3840, 2160, 30, c4k30 !in normalSession, 25_000_000, "4K30 HEVC fallback")
            }
            val c4k60 = Triple(3840, 2160, 60)
            if (c4k60 in combos) {
                return Ladder(3840, 2160, 60, c4k60 !in normalSession, 35_000_000, "4K60 HEVC")
            }
        } else if (current.width == 3840 && current.height == 2160 && current.fps == 30) {
            val c4k60 = Triple(3840, 2160, 60)
            if (c4k60 in combos) {
                return Ladder(3840, 2160, 60, c4k60 !in normalSession, 35_000_000, "4K60 HEVC")
            }
        }
        return null
    }

    internal fun isLadderLowerThan(a: Ladder, b: Ladder): Boolean {
        if (a.width < b.width) return true
        if (a.width == b.width && a.height < b.height) return true
        if (a.width == b.width && a.height == b.height && a.fps < b.fps) return true
        return false
    }

    private fun resolveRequestedLadder(width: Int, height: Int, fps: Int, bitrateBps: Int): Ladder? {
        val probed = probeLadder()
        if (probed != null && probed.width == width && probed.height == height && probed.fps == fps) {
            return probed
        }
        val combos = try {
            probe.supportedCombos()
        } catch (e: Exception) {
            emptySet()
        }
        if (Triple(width, height, fps) in combos) {
            val normalCombos = try {
                probe.normalSessionCombos()
            } catch (e: Exception) {
                combos
            }
            return Ladder(
                width = width,
                height = height,
                fps = fps,
                needsHighSpeedSession = Triple(width, height, fps) !in normalCombos,
                bitrateBps = if (bitrateBps > 0) bitrateBps else probed?.bitrateBps ?: DEFAULT_FALLBACK_BITRATE,
                reason = "Requested ${width}x$height@$fps"
            )
        }
        val clamped = probed?.takeIf {
            it.width <= width && it.height <= height && it.fps <= fps
        }
        if (clamped != null) {
            Log.i(TAG, "Control START clamped ${width}x$height@$fps -> ${clamped.summary}")
        }
        return clamped
    }

    companion object {
        private const val TAG = "Stream4kController"
        const val CONTROL_PORT = 47822
        const val CONTROL_MAGIC = "PHONECAM4K"
        const val DEFAULT_STREAM_PORT = 5004
        private const val DEFAULT_FALLBACK_BITRATE = 12_000_000
    }
}
