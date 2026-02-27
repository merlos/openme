import CryptoKit
import Foundation
import Network

/// Pure-Swift implementation of the openme SPA knock protocol.
///
/// `KnockService` handles the complete client-side knock sequence:
/// ephemeral ECDH key agreement → HKDF key derivation → ChaCha20-Poly1305
/// encryption → Ed25519 signature → UDP datagram dispatch. It requires no
/// server response and leaves no persistent network state.
///
/// ## Wire format
///
/// Every knock is a fixed-size **165-byte** UDP datagram:
///
/// ```
///  0       1      33      45                   101                   165
///  ┌───────┬──────┬───────┬─────────────────────┬─────────────────────┐
///  │version│ephem │ nonce │     ciphertext      │    ed25519_sig      │
///  │ 1 B   │32 B  │12 B   │     56 B            │     64 B            │
///  └───────┴──────┴───────┴─────────────────────┴─────────────────────┘
///  ◄─────────────── signed portion (101 B) ──────────────────────────►
/// ```
///
/// For the canonical specification see:
/// - [Packet Format](https://openme.merlos.org/docs/protocol/packet-format.html)
/// - [Cryptography](https://openme.merlos.org/docs/protocol/cryptography.html)
/// - [Handshake](https://openme.merlos.org/docs/protocol/handshake.html)
public enum KnockService {

    // MARK: - Constants

    public static let protocolVersion: UInt8 = 1
    public static let packetSize       = 165
    public static let signedPortionSize = packetSize - 64  // 101

    private static let hkdfInfo = "openme-v1-chacha20poly1305".data(using: .utf8)!

    // MARK: - Public API

    /// Sends a single SPA knock packet to the server asynchronously.
    ///
    /// The packet is dispatched over UDP using `Network.framework`. A `.success`
    /// result only confirms the OS accepted the datagram for transmission — it
    /// does **not** confirm the server received it or that a firewall rule was
    /// opened. Use a TCP health-port check to verify the rule is active.
    ///
    /// This method returns immediately; `completion` is called on the **main queue**.
    ///
    /// - Parameters:
    ///   - serverHost: Hostname or IP address string of the openme server.
    ///   - serverPort: UDP port the server is listening on (usually `7777`).
    ///   - serverPubKeyBase64: Base64-encoded 32-byte Curve25519 public key of the server.
    ///   - clientPrivKeyBase64: Base64-encoded Ed25519 private key of this client.
    ///     Accepts both 32-byte (seed) and 64-byte (seed + public key) encodings.
    ///   - completion: Closure invoked on the main queue with `.success` or
    ///     `.failure(`<``KnockServiceError``>`)` once the datagram is sent or an
    ///     error occurs.
    public static func knock(
        serverHost: String,
        serverPort: UInt16,
        serverPubKeyBase64: String,
        clientPrivKeyBase64: String,
        completion: @escaping (Result<Void, KnockServiceError>) -> Void
    ) {
        // Decode keys
        guard let serverPubKeyData = Data(base64Encoded: serverPubKeyBase64),
              serverPubKeyData.count == 32 else {
            completion(.failure(KnockServiceError.invalidServerKey)); return
        }
        guard let clientPrivKeyData = Data(base64Encoded: clientPrivKeyBase64) else {
            completion(.failure(KnockServiceError.invalidClientKey)); return
        }

        let serverPubKey: Curve25519.KeyAgreement.PublicKey
        do {
            serverPubKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverPubKeyData)
        } catch {
            completion(.failure(KnockServiceError.invalidServerKey)); return
        }

        let signingKey: Curve25519.Signing.PrivateKey
        do {
            // Ed25519 private keys may be stored as 64 bytes (seed+pub) or 32 bytes (seed only).
            let seed = clientPrivKeyData.count == 64 ? clientPrivKeyData.prefix(32) : clientPrivKeyData
            signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        } catch {
            completion(.failure(KnockServiceError.invalidClientKey)); return
        }

        // Build packet
        let packet: Data
        do {
            packet = try buildPacket(serverPubKey: serverPubKey, signingKey: signingKey)
        } catch {
            completion(.failure(KnockServiceError.packetBuildFailed(error.localizedDescription))); return
        }

        // Send via NWConnection (UDP)
        let host = NWEndpoint.Host(serverHost)
        let port = NWEndpoint.Port(rawValue: serverPort)!
        let connection = NWConnection(host: host, port: port, using: .udp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: packet, completion: .contentProcessed { sendError in
                    connection.cancel()
                    DispatchQueue.main.async {
                        if let e = sendError {
                            completion(.failure(KnockServiceError.sendFailed(e.localizedDescription)))
                        } else {
                            completion(.success(()))
                        }
                    }
                })
            case .failed(let error):
                connection.cancel()
                DispatchQueue.main.async {
                    completion(.failure(KnockServiceError.sendFailed(error.localizedDescription)))
                }
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    // MARK: - Packet Construction

    /// Constructs a 165-byte SPA knock packet ready to be sent over UDP.
    ///
    /// This lower-level method is public for unit testing and advanced use cases
    /// (e.g. pre-building a packet for a watch complication). Most callers should
    /// use ``knock(serverHost:serverPort:serverPubKeyBase64:clientPrivKeyBase64:completion:)``
    /// instead.
    ///
    /// Construction steps:
    /// 1. Generate an ephemeral Curve25519 keypair.
    /// 2. ECDH with the server's static public key → shared secret.
    /// 3. HKDF-SHA256 (info: `"openme-v1-chacha20poly1305"`) → 32-byte symmetric key.
    /// 4. Build 40-byte plaintext: `timestamp‖random_nonce‖target_ip`.
    /// 5. Seal with ChaCha20-Poly1305 → 56-byte ciphertext+tag.
    /// 6. Assemble unsigned portion (101 bytes): `version‖ephem_pub‖nonce‖ciphertext`.
    /// 7. Sign the 101-byte portion with the Ed25519 client key → 64-byte signature.
    /// 8. Append signature → 165-byte final packet.
    ///
    /// - Parameters:
    ///   - serverPubKey: Server's static Curve25519 public key for ECDH.
    ///   - signingKey: Client's Ed25519 private key used to sign the packet.
    ///   - targetIP: 16-byte IPv6-mapped target IP. Pass `nil` or 16 zero-bytes
    ///     to tell the server to use the packet's source IP.
    ///   - timestamp: Timestamp embedded in the plaintext. Defaults to `Date()`.
    ///     The server rejects packets outside a configurable replay window
    ///     (default ±60 s). See
    ///     [Replay Protection](https://openme.merlos.org/docs/protocol/replay-protection.html).
    /// - Returns: A 165-byte `Data` value ready to be transmitted.
    /// - Throws: `CryptoKit` errors if ECDH, HKDF, AEAD sealing, or Ed25519
    ///   signing fails; ``KnockServiceError/packetBuildFailed(_:)`` wraps these
    ///   at the ``knock(serverHost:serverPort:serverPubKeyBase64:clientPrivKeyBase64:completion:)`` level.
    public static func buildPacket(
        serverPubKey: Curve25519.KeyAgreement.PublicKey,
        signingKey: Curve25519.Signing.PrivateKey,
        targetIP: Data? = nil,
        timestamp: Date = Date()
    ) throws -> Data {

        // 1. Ephemeral Curve25519 keypair
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()

        // 2. ECDH → HKDF → symmetric key
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: serverPubKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: hkdfInfo,
            outputByteCount: 32
        )

        // 3. Build plaintext (40 bytes)
        var plaintext = Data(capacity: 40)

        // Timestamp: int64 big-endian nanoseconds since epoch
        let nanos = Int64(timestamp.timeIntervalSince1970 * 1_000_000_000)
        var nanosBE = nanos.bigEndian
        plaintext.append(Data(bytes: &nanosBE, count: 8))

        // Random nonce: 16 bytes
        var randomNonce = Data(count: 16)
        _ = randomNonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        plaintext.append(randomNonce)

        // Target IP: 16 bytes (IPv6-mapped). All-zero → "use my source IP"
        if let ip = targetIP, ip.count == 16 {
            plaintext.append(ip)
        } else {
            plaintext.append(Data(count: 16))
        }

        // 4. Encrypt (ChaCha20-Poly1305)
        let nonce = ChaChaPoly.Nonce()
        let sealedBox = try ChaChaPoly.seal(plaintext, using: symmetricKey, nonce: nonce)

        // 5. Assemble packet (unsigned portion = 101 bytes)
        var packet = Data(capacity: packetSize)
        packet.append(protocolVersion)                                      // 1 B
        packet.append(ephemeral.publicKey.rawRepresentation)                // 32 B
        packet.append(contentsOf: nonce.withUnsafeBytes { Array($0) })      // 12 B
        packet.append(sealedBox.ciphertext + sealedBox.tag)                 // 56 B (40 + 16)

        assert(packet.count == signedPortionSize, "Signed portion must be 101 bytes")

        // 6. Ed25519 signature over bytes [0..<101]
        let signature = try signingKey.signature(for: packet)
        packet.append(signature)

        assert(packet.count == packetSize, "Packet must be 165 bytes")
        return packet
    }
}

// MARK: - Error type

/// Errors thrown or returned by ``KnockService``.
public enum KnockServiceError: LocalizedError {
    /// The server public key string is not valid base64 or is not exactly 32 bytes.
    case invalidServerKey
    /// The client private key string is not valid base64 or cannot be used as an Ed25519 seed.
    case invalidClientKey
    /// Packet construction failed (ECDH, HKDF, AEAD, or signing error).
    /// The associated value contains the underlying error description.
    case packetBuildFailed(String)
    /// The UDP datagram could not be dispatched.
    /// The associated value contains the `NWError` description.
    case sendFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerKey:     return "Invalid server public key"
        case .invalidClientKey:     return "Invalid client private key"
        case .packetBuildFailed(let msg): return "Failed to build packet: \(msg)"
        case .sendFailed(let msg):  return "Failed to send knock: \(msg)"
        }
    }
}
