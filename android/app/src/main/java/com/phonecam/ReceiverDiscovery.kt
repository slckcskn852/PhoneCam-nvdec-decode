package com.phonecam

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import java.net.Inet4Address
import java.util.ArrayDeque

/** Foreground-only DNS-SD discovery. Resolution is serialized for older Android versions. */
internal class ReceiverDiscovery(context: Context, private val onUpdate: (List<Computer>) -> Unit,
                                 private val onError: (String) -> Unit) {
    data class Computer(val name: String, val host: String, val port: Int)
    private val manager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val main = Handler(Looper.getMainLooper())
    private val computers = linkedMapOf<String, Computer>()
    private val pending = ArrayDeque<NsdServiceInfo>()
    private var listener: NsdManager.DiscoveryListener? = null
    private var generation = 0
    private var resolving = false
    private val visibleServices = mutableSetOf<String>()
    private val multicast = (context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager)
        ?.createMulticastLock("PhoneCam discovery")?.apply { setReferenceCounted(false) }
    fun start() {
        stop()
        try { multicast?.acquire() } catch (_: Exception) { /* NSD may work without the lock. */ }
        val token = generation
        val nsd = manager ?: return onError("Network discovery is unavailable. Enter the PC code instead.")
        listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, error: Int) { main.post { if (token == generation) onError("Could not search this network. Enter the PC code or allow local-network access.") } }
            override fun onStopDiscoveryFailed(type: String, error: Int) {}
            override fun onServiceFound(service: NsdServiceInfo) { main.post {
                if (token == generation && service.serviceType.contains("_phonecam._tcp") && pending.size < 32) {
                    visibleServices.add(service.serviceName)
                    pending.add(service); resolveNext(token)
                }
            } }
            override fun onServiceLost(service: NsdServiceInfo) { main.post {
                if (token == generation) { visibleServices.remove(service.serviceName); computers.remove(service.serviceName); onUpdate(computers.values.toList()) }
            } }
        }
        try { nsd.discoverServices("_phonecam._tcp.", NsdManager.PROTOCOL_DNS_SD, listener) }
        catch (_: Exception) { onError("Network discovery could not start. Enter the PC code instead.") }
    }
    @Suppress("DEPRECATION")
    private fun resolveNext(token: Int) {
        if (token != generation || resolving || pending.isEmpty()) return
        resolving = true
        val info = pending.removeFirst()
        try { manager?.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(service: NsdServiceInfo, error: Int) { main.post {
                if (token == generation) { resolving = false; resolveNext(token) }
            } }
            override fun onServiceResolved(service: NsdServiceInfo) { main.post {
                if (token != generation) return@post
                val host = service.host
                if (service.serviceName in visibleServices && host is Inet4Address && service.port in 1..65535 && computers.size < 32) {
                    computers[service.serviceName] = Computer(service.serviceName, host.hostAddress ?: "", service.port)
                    onUpdate(computers.values.sortedBy { it.name })
                }
                resolving = false; resolveNext(token)
            } }
        }) } catch (_: Exception) { resolving = false; resolveNext(token) }
    }
    fun stop() {
        generation++
        if (multicast?.isHeld == true) multicast.release()
        visibleServices.clear()
        listener?.let { try { manager?.stopServiceDiscovery(it) } catch (_: Exception) {} }
        listener = null; pending.clear(); computers.clear(); resolving = false
    }
}

internal object ReceiverAddress {
    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    const val DEFAULT_PORT = 47823
    data class Target(val host: String, val port: Int = DEFAULT_PORT)
    fun parse(input: String): Target? {
        val text = input.trim()
        if (text.length > 253) return null
        val normalized = text.uppercase(java.util.Locale.ROOT).filterNot { it == '-' || it.isWhitespace() }
        if (text.startsWith("PC-", ignoreCase = true) || (normalized.startsWith("PC") && normalized.length == 10 && !text.contains('.'))) {
            if (normalized.length != 10) return null
            var value = 0L
            for (c in normalized.drop(2)) {
                val digit = ALPHABET.indexOf(c)
                if (digit < 0) return null
                value = (value shl 5) or digit.toLong()
            }
            val ip = value ushr 8
            var crc = 0x5a
            for (shift in listOf(24, 16, 8, 0)) {
                crc = crc xor ((ip ushr shift).toInt() and 255)
                repeat(8) { crc = ((crc shl 1) xor if (crc and 128 != 0) 7 else 0) and 255 }
            }
            if (crc != (value and 255).toInt()) return null
            return Target(listOf(24,16,8,0).joinToString(".") { ((ip ushr it) and 255).toString() })
        }
        val parts = text.split(':')
        if (parts.size !in 1..2) return null
        val host = parts[0]
        if (host.isBlank() || !host.all { it.isLetterOrDigit() || it == '.' || it == '-' }) return null
        val port = if (parts.size == 2) parts[1].toIntOrNull() ?: return null else DEFAULT_PORT
        if (port !in 1..65535) return null
        return Target(host, port)
    }
}
