package org.merlos.openmekit

import org.bouncycastle.crypto.generators.Ed25519KeyPairGenerator
import org.bouncycastle.crypto.generators.X25519KeyPairGenerator
import org.bouncycastle.crypto.params.Ed25519KeyGenerationParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519KeyGenerationParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters
import org.junit.Assert.*
import org.junit.Test
import java.security.SecureRandom

/**
 * Unit tests for [KnockService] packet construction.
 *
 * These tests verify the packet size, version byte, and structural invariants without
 * performing actual UDP transmission.
 */
class KnockServiceTest {

    private val rng = SecureRandom()

    private fun generateServerKeyPair(): Pair<X25519PublicKeyParameters, org.bouncycastle.crypto.params.X25519PrivateKeyParameters> {
        val gen = X25519KeyPairGenerator()
        gen.init(X25519KeyGenerationParameters(rng))
        val pair = gen.generateKeyPair()
        return Pair(
            pair.public as X25519PublicKeyParameters,
            pair.private as org.bouncycastle.crypto.params.X25519PrivateKeyParameters,
        )
    }

    private fun generateClientSigningKey(): Ed25519PrivateKeyParameters {
        val gen = Ed25519KeyPairGenerator()
        gen.init(Ed25519KeyGenerationParameters(rng))
        return gen.generateKeyPair().private as Ed25519PrivateKeyParameters
    }

    @Test
    fun `packet is exactly 165 bytes`() {
        val (serverPub, _) = generateServerKeyPair()
        val clientSigning = generateClientSigningKey()

        val packet = KnockService.buildPacket(serverPub, clientSigning)

        assertEquals("Packet must be exactly 165 bytes", KnockService.PACKET_SIZE, packet.size)
    }

    @Test
    fun `packet starts with protocol version 1`() {
        val (serverPub, _) = generateServerKeyPair()
        val clientSigning = generateClientSigningKey()

        val packet = KnockService.buildPacket(serverPub, clientSigning)

        assertEquals("Version byte must be 1", KnockService.PROTOCOL_VERSION, packet[0])
    }

    @Test
    fun `each knock produces a different packet (ephemeral key)`() {
        val (serverPub, _) = generateServerKeyPair()
        val clientSigning = generateClientSigningKey()

        val p1 = KnockService.buildPacket(serverPub, clientSigning)
        val p2 = KnockService.buildPacket(serverPub, clientSigning)

        assertFalse(
            "Two knocks must differ due to ephemeral key and random nonce",
            p1.contentEquals(p2),
        )
    }

    @Test
    fun `YAML parser round-trips a simple config`() {
        val yaml = """
            profiles:
                my-server:
                    server_host: "10.0.0.1"
                    server_udp_port: 54154
                    server_pubkey: "abc123=="
                    private_key: "priv456=="
                    public_key: "pub789=="
                    post_knock: ""
        """.trimIndent()

        val profiles = ClientConfigParser.parseYaml(yaml)
        assertEquals(1, profiles.size)
        val p = profiles["my-server"]!!
        assertEquals("10.0.0.1", p.serverHost)
        assertEquals(54154, p.serverUDPPort)
        assertEquals("abc123==", p.serverPubKey)
        assertEquals("priv456==", p.privateKey)
    }

    @Test
    fun `QR parser handles valid JSON`() {
        val json = """{"profile":"vpn","host":"1.2.3.4","udp_port":54154,"server_pubkey":"srvpub==","client_privkey":"clipriv==","client_pubkey":"clipub=="}"""
        val p = ClientConfigParser.parseQRPayload(json)
        assertEquals("vpn", p.name)
        assertEquals("1.2.3.4", p.serverHost)
        assertEquals("srvpub==", p.serverPubKey)
        assertEquals("clipriv==", p.privateKey)
    }

    @Test(expected = ParserError.InvalidQRPayload::class)
    fun `QR parser throws on missing required fields`() {
        ClientConfigParser.parseQRPayload("""{"host":"1.2.3.4"}""")
    }

    @Test(expected = ParserError.NoProfilesFound::class)
    fun `YAML parser throws when no profiles section`() {
        ClientConfigParser.parseYaml("key: value\nother: stuff\n")
    }
}
