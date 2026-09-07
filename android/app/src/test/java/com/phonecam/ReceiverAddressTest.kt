package com.phonecam
import org.junit.Assert.*
import org.junit.Test
class ReceiverAddressTest {
    @Test fun sharedPcCodeVectors() {
        for ((code, ip) in listOf("PC-R2M0-2AGG" to "192.168.1.42", "PC-1800-01F7" to "10.0.0.5", "PC-NG80-G2A2" to "172.16.8.9")) {
            assertEquals(ReceiverAddress.Target(ip), ReceiverAddress.parse(code))
        }
        assertEquals(ReceiverAddress.Target("192.168.1.42"), ReceiverAddress.parse(" pc-r2m0-2agg "))
        assertNull(ReceiverAddress.parse("PC-R2M0-2AGH"))
    }
    @Test fun manualAddressAndPort() {
        assertEquals(ReceiverAddress.Target("pc.local", 12345), ReceiverAddress.parse("pc.local:12345"))
        assertNull(ReceiverAddress.parse("10.0.0.5:0"))
        assertNull(ReceiverAddress.parse("10.0.0.5:65536"))
        assertNull(ReceiverAddress.parse("https://pc.local"))
        assertNull(ReceiverAddress.parse(""))
    }
}
