package org.merlos.openmekit

import android.util.Log
import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.generators.X25519KeyPairGenerator
import org.bouncycastle.crypto.params.X25519KeyGenerationParameters
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

private const val TAG = "KnockService"

/**
 * Pure-Kotlin implementation of the openme SPA (Single Packet Authentication) knock protocol.
 *
 * [KnockService] handles the complete client-side knock sequence:
 * ephemeral X25519 ECDH key agreement → HKDF-SHA256 key derivation →
 * ChaCha20-Poly1305 encryption → Ed25519 signature → UDP datagram dispatch.
 * It requires no server response and leaves no persistent network state.
 *
 * ## Wire format
 *
 * Every knock is a fixed-size **165-byte** UDP datagram:
 *
 * ```
 *  0       1      33      45                   101                   165
 *  ┌───────┬──────┬───────┬─────────────────────┬─────────────────────┐
 *  │version│ephem │ nonce │     ciphertext      │    ed25519_sig      │
 *  │ 1 B   │32 B  │12 B   │     56 B            │     64 B            │
 *  └───────┴──────┴───────┴─────────────────────┴─────────────────────┘
 *  ◄─────────────── signed portion (101 B) ──────────────────────────►
 * ```
 *
 * ## Crypto stack
 * | Step | Algorithm | Notes |
 * |------|-----------|-------|
 * | Key agreement | X25519 (Curve25519 ECDH) | Ephemeral key per knock |
 * | KDF | HKDF-SHA256 | info = `"openme-v1-chacha20poly1305"` |
 * | Encryption | ChaCha20-Poly1305 | 12-byte random nonce |
 * | Signature | Ed25519 | Over signed portion (101 B) |
 *
 * For the canonical specification see:
 * - [Packet Format](https://openme.merlos.org/docs/protocol/packet-format.html)
 * - [Cryptography](https://openme.merlos.org/docs/protocol/cryptography.html)
 */
object KnockService {

    // ─── Constants ──────────────────────────────────────────────────────────────

    /** Current protocol version byte. */
    const val PROTOCOL_VERSION: Byte = 1

    /** Total wire size of a SPA knock packet, in bytes. */
    const val PACKET_SIZE = 165

    /** Number of bytes covered by the Ed25519 signature. */
    const val SIGNED_PORTION_SIZE = PACKET_SIZE - 64  // 101

    private val HKDF_INFO = "openme-v1-chacha20poly1305".toByteArray(Charsets.UTF_8)

    // ─── Public API ─────────────────────────────────────────────────────────────

    /**
     * Sends a single SPA knock packet to the server.
     *
     * This is a **blocking** call and should be invoked from a background thread or
     * a coroutine with [kotlinx.coroutines.Dispatchers.IO].
     *
     * A successful return only confirms the OS dispatched the UDP datagram — it does
     * **not** guarantee the server received it or that a firewall rule was opened.
     * Use a TCP health-port check to verify the rule is active.
     *
     * @param serverHost Hostname or IP address string of the openme server.
     * @param serverPort UDP port the server is listening on (usually `54154`).
     * @param serverPubKeyBase64 Base64-encoded 32-byte X25519 public key of the server.
     * @param clientPrivKeyBase64 Base64-encoded Ed25519 private key of this client.
     *   Accepts both 32-byte (seed only) and 64-byte (seed + public key) encodings.
     * @throws KnockError if key decoding, packet construction, or UDP send fails.
     */
    @Throws(KnockError::class)
    fun knock(
        serverHost: String,
        serverPort: Int,
        serverPubKeyBase64: String,
        clientPrivKeyBase64: String,
    ) {
        val serverPubKeyBytes = decodeBase64(serverPubKeyBase64)
            ?: throw KnockError.InvalidServerKey
        if (serverPubKeyBytes.size != 32) throw KnockError.InvalidServerKey

        val clientPrivKeyBytes = decodeBase64(clientPrivKeyBase64)
            ?: throw KnockError.InvalidClientKey

        // Ed25519 keys may be stored as 64 bytes (seed+pub) or 32 bytes (seed only).
        val seed = if (clientPrivKeyBytes.size == 64) clientPrivKeyBytes.copyOf(32)
                   else clientPrivKeyBytes
        if (seed.size != 32) throw KnockError.InvalidClientKey

        val serverPubKey = X25519PublicKeyParameters(serverPubKeyBytes, 0)
        val signingKey = Ed25519PrivateKeyParameters(seed, 0)

        val packet = try {
            buildPacket(serverPubKey, signingKey)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to build knock packet", e)
            throw KnockError.PacketBuildFailed(e.message ?: "unknown error")
        }

        sendUdp(serverHost, serverPort, packet)
    }

    // ─── Packet Construction ────────────────────────────────────────────────────

    /**
     * Constructs a 165-byte SPA knock packet ready to be sent over UDP.
     *
     * This lower-level method is public for unit testing and advanced use cases.
     * Most callers should use [knock] instead.
     *
     * Construction steps:
     * 1. Generate ephemeral X25519 key pair.
     * 2. X25519 ECDH with the server's static public key → 32-byte shared secret.
     * 3. HKDF-SHA256 (info: `"openme-v1-chacha20poly1305"`) → 32-byte symmetric key.
     * 4. Build 40-byte plaintext: `timestamp (8) ‖ random_nonce (16) ‖ target_ip (16)`.
     * 5. Seal with ChaCha20-Poly1305 → 56-byte ciphertext (40 + 16-byte tag).
     * 6. Assemble unsigned portion (101 B): `version ‖ ephem_pub ‖ nonce ‖ ciphertext`.
     * 7. Sign with Ed25519 client key → 64-byte signature.
     * 8. Append signature → 165-byte final packet.
     *
     * @param serverPubKey Server's static X25519 public key for ECDH.
     * @param signingKey Client's Ed25519 private key used to sign the packet.
     * @return A 165-byte [ByteArray] ready to be transmitted over UDP.
     */
    fun buildPacket(
        serverPubKey: X25519PublicKeyParameters,
        signingKey: Ed25519PrivateKeyParameters,
    ): ByteArray {
        val rng = SecureRandom()

        // 1. Ephemeral X25519 key pair
        val keyGen = X25519KeyPairGenerator()
        keyGen.init(X25519KeyGenerationParameters(rng))
        val ephemPair = keyGen.generateKeyPair()
        val ephemPriv = ephemPair.private as X25519PrivateKeyParameters
        val ephemPub  = ephemPair.public  as X25519PublicKeyParameters

        // 2. X25519 ECDH → 32-byte shared secret
        val agreement = X25519Agreement()
        agreement.init(ephemPriv)
        val sharedSecret = ByteArray(agreement.agreementSize)
        agreement.calculateAgreement(serverPubKey, sharedSecret, 0)

        // 3. HKDF-SHA256 → 32-byte symmetric key
        val symmetricKey = hkdfSha256(sharedSecret, salt = ByteArray(0), info = HKDF_INFO, outputLen = 32)

        // 4. Build 40-byte plaintext
        val plaintext = ByteBuffer.allocate(40)
        // Timestamp: int64 big-endian nanoseconds since epoch
        plaintext.order(ByteOrder.BIG_ENDIAN)
        plaintext.putLong(System.currentTimeMillis() * 1_000_000L)
        // Random nonce: 16 bytes
        val randomNonce = ByteArray(16).also { rng.nextBytes(it) }
        plaintext.put(randomNonce)
        // Target IP: 16 zero bytes = "use knock source IP"
        plaintext.put(ByteArray(16))
        val plaintextBytes = plaintext.array()

        // 5. ChaCha20-Poly1305 encryption
        val chachaKey = SecretKeySpec(symmetricKey, "ChaCha20")
        val nonce = ByteArray(12).also { rng.nextBytes(it) }
        val cipher = Cipher.getInstance("ChaCha20-Poly1305")
        cipher.init(Cipher.ENCRYPT_MODE, chachaKey, IvParameterSpec(nonce))
        val ciphertext = cipher.doFinal(plaintextBytes)  // 40 plaintext + 16 tag = 56 bytes

        // 6. Assemble signed portion (101 bytes)
        val packet = ByteBuffer.allocate(PACKET_SIZE)
        packet.put(PROTOCOL_VERSION)                  // 1 B  — version
        packet.put(ephemPub.encoded)                  // 32 B — ephemeral X25519 pub
        packet.put(nonce)                             // 12 B — ChaCha20 nonce
        packet.put(ciphertext)                        // 56 B — ciphertext + tag

        check(packet.position() == SIGNED_PORTION_SIZE) {
            "Signed portion must be $SIGNED_PORTION_SIZE bytes, got ${packet.position()}"
        }

        // 7. Ed25519 signature over first 101 bytes
        val unsignedBytes = packet.array().copyOf(SIGNED_PORTION_SIZE)
        val signer = Ed25519Signer()
        signer.init(true, signingKey)
        signer.update(unsignedBytes, 0, unsignedBytes.size)
        val signature = signer.generateSignature()   // 64 bytes

        // 8. Final packet
        packet.put(signature)                        // 64 B — Ed25519 signature

        check(packet.position() == PACKET_SIZE) {
            "Packet must be $PACKET_SIZE bytes, got ${packet.position()}"
        }
        return packet.array()
    }

    // ─── Internal helpers ───────────────────────────────────────────────────────

    private fun sendUdp(host: String, port: Int, data: ByteArray) {
        try {
            DatagramSocket().use { socket ->
                val address = InetAddress.getByName(host)
                val dp = DatagramPacket(data, data.size, address, port)
                socket.send(dp)
                Log.d(TAG, "Sent ${data.size}-byte SPA knock to $host:$port")
            }
        } catch (e: Exception) {
            Log.e(TAG, "UDP send failed", e)
            throw KnockError.SendFailed(e.message ?: "unknown error")
        }
    }

    /**
     * HKDF extract-and-expand (RFC 5869) using HMAC-SHA-256.
     *
     * @param ikm  Input key material (X25519 shared secret).
     * @param salt Optional salt; use empty byte array for no salt.
     * @param info Context info label.
     * @param outputLen Number of output bytes.
     */
    private fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, outputLen: Int): ByteArray {
        val effectiveSalt = salt.ifEmpty { ByteArray(32) }

        // Extract
        val extractMac = Mac.getInstance("HmacSHA256")
        extractMac.init(SecretKeySpec(effectiveSalt, "HmacSHA256"))
        val prk = extractMac.doFinal(ikm)

        // Expand
        val expandMac = Mac.getInstance("HmacSHA256")
        expandMac.init(SecretKeySpec(prk, "HmacSHA256"))

        val result = ByteArray(outputLen)
        var prev = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < outputLen) {
            expandMac.update(prev)
            expandMac.update(info)
            expandMac.update(counter.toByte())
            prev = expandMac.doFinal()
            val toCopy = minOf(prev.size, outputLen - offset)
            System.arraycopy(prev, 0, result, offset, toCopy)
            offset += toCopy
            counter++
        }
        return result
    }

    private fun decodeBase64(s: String): ByteArray? = try {
        Base64.getDecoder().decode(s)
    } catch (_: Exception) { null }
}

/**
 * Errors thrown by [KnockService].
 */
sealed class KnockError(message: String) : Exception(message) {
    /** The server public key is not valid Base64 or is not exactly 32 bytes. */
    object InvalidServerKey : KnockError("Invalid server public key: must be a 32-byte Base64-encoded X25519 key.")

    /** The client private key is not valid Base64 or cannot be used as an Ed25519 seed. */
    object InvalidClientKey : KnockError("Invalid client private key: must be a 32- or 64-byte Base64-encoded Ed25519 key.")

    /** Packet construction failed. The [cause] contains the underlying crypto error. */
    class PacketBuildFailed(detail: String) : KnockError("Failed to build knock packet: $detail")

    /** The UDP datagram could not be dispatched. */
    class SendFailed(detail: String) : KnockError("Failed to send knock: $detail")
}
