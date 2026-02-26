import CryptoKit
import Foundation
import Network

/// Pure-Swift implementation of the openme SPA knock protocol.
///
/// Wire format (165 bytes):
///   [version(1)] [ephemeral_pubkey(32)] [nonce(12)] [ciphertext+tag(56)] [ed25519_sig(64)]
///
/// Ciphertext decrypts to (40 bytes):
///   [timestamp(8)] [random_nonce(16)] [target_ip(16)]
public enum KnockService {

    // MARK: - Constants

    public static let protocolVersion: UInt8 = 1
    public static let packetSize       = 165
    public static let signedPortionSize = packetSize - 64  // 101

    private static let hkdfInfo = "openme-v1-chacha20poly1305".data(using: .utf8)!

    // MARK: - Public API

    /// Sends a single SPA knock packet to the server.
    ///
    /// - Parameters:
    ///   - serverHost: hostname or IP of the server
    ///   - serverPort: UDP port to send the knock to
    ///   - serverPubKeyBase64: server's static Curve25519 public key (base64)
    ///   - clientPrivKeyBase64: client's Ed25519 private key (base64, 64-byte seed+pub or 32-byte seed)
    ///   - completion: called on the main queue with the result
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

    /// Builds a 165-byte SPA knock packet.
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

public enum KnockServiceError: LocalizedError {
    case invalidServerKey
    case invalidClientKey
    case packetBuildFailed(String)
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
