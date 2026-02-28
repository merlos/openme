import XCTest
import CryptoKit
@testable import OpenMeKit

/// Unit tests for ``KnockService`` packet construction and key validation.
///
/// These tests exercise the pure packet-building path (no UDP transmission).
/// They validate the wire-format invariants described at
/// https://openme.merlos.org/docs/protocol/packet-format.html
final class KnockServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// A freshly generated server key pair used across tests.
    private let serverPriv = Curve25519.KeyAgreement.PrivateKey()
    private var serverPub:  Curve25519.KeyAgreement.PublicKey { serverPriv.publicKey }

    /// A freshly generated client signing key used across tests.
    private let signingKey = Curve25519.Signing.PrivateKey()

    // MARK: - Packet size

    func testPacketIsExactly165Bytes() throws {
        let packet = try KnockService.buildPacket(serverPubKey: serverPub, signingKey: signingKey)
        XCTAssertEqual(packet.count, KnockService.packetSize,
                       "buildPacket must return exactly \(KnockService.packetSize) bytes")
    }

    // MARK: - Protocol version

    func testFirstByteIsProtocolVersion() throws {
        let packet = try KnockService.buildPacket(serverPubKey: serverPub, signingKey: signingKey)
        XCTAssertEqual(packet[0], KnockService.protocolVersion,
                       "First byte must be protocol version \(KnockService.protocolVersion)")
    }

    // MARK: - Ephemeral randomness

    func testTwoKnocksProduceDifferentPackets() throws {
        let p1 = try KnockService.buildPacket(serverPubKey: serverPub, signingKey: signingKey)
        let p2 = try KnockService.buildPacket(serverPubKey: serverPub, signingKey: signingKey)
        XCTAssertNotEqual(p1, p2,
                          "Each knock must embed a fresh ephemeral key and random nonce")
    }

    func testEphemeralPublicKeyDiffersPerKnock() throws {
        let p1 = try KnockService.buildPacket(serverPubKey: serverPub, signingKey: signingKey)
        let p2 = try KnockService.buildPacket(serverPubKey: serverPub, signingKey: signingKey)
        // Bytes 1-32 (inclusive) are the ephemeral Curve25519 public key
        XCTAssertNotEqual(p1[1..<33], p2[1..<33],
                          "Ephemeral public key (bytes 1-32) must be fresh per knock")
    }

    // MARK: - Field layout

    func testSignedPortionIs101Bytes() {
        XCTAssertEqual(KnockService.signedPortionSize, 101)
    }

    func testPacketSizeConstant() {
        XCTAssertEqual(KnockService.packetSize, 165)
    }

    func testProtocolVersionConstant() {
        XCTAssertEqual(KnockService.protocolVersion, 1)
    }

    // MARK: - Key validation (via knock API)

    func testInvalidBase64ServerKeyFails() {
        let expectation = expectation(description: "invalid server key fails")
        KnockService.knock(
            serverHost: "127.0.0.1",
            serverPort: 54154,
            serverPubKeyBase64: "not-base64!!!",
            clientPrivKeyBase64: Data(signingKey.rawRepresentation).base64EncodedString()
        ) { result in
            if case .failure(let err) = result, case .invalidServerKey = err {
                // expected
            } else {
                XCTFail("Expected invalidServerKey error, got \(result)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testWrongLengthServerKeyFails() {
        let expectation = expectation(description: "wrong-length server key fails")
        let shortKey = Data(repeating: 0, count: 16).base64EncodedString()   // 16 B, not 32
        KnockService.knock(
            serverHost: "127.0.0.1",
            serverPort: 54154,
            serverPubKeyBase64: shortKey,
            clientPrivKeyBase64: Data(signingKey.rawRepresentation).base64EncodedString()
        ) { result in
            if case .failure(let err) = result, case .invalidServerKey = err {
                // expected
            } else {
                XCTFail("Expected invalidServerKey error, got \(result)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testInvalidBase64ClientKeyFails() {
        let expectation = expectation(description: "invalid client key fails")
        KnockService.knock(
            serverHost: "127.0.0.1",
            serverPort: 54154,
            serverPubKeyBase64: Data(serverPub.rawRepresentation).base64EncodedString(),
            clientPrivKeyBase64: "!!not-base64!!"
        ) { result in
            if case .failure(let err) = result, case .invalidClientKey = err {
                // expected
            } else {
                XCTFail("Expected invalidClientKey error, got \(result)")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // MARK: - Packet constant check via build (smoke test)

    func testBuildPacketProducesNonZeroBytes() throws {
        let packet = try KnockService.buildPacket(serverPubKey: serverPub, signingKey: signingKey)
        // The signed portion (bytes 0-100) must not be all zeros.
        let signedPortion = packet[0..<KnockService.signedPortionSize]
        let allZero = signedPortion.allSatisfy { $0 == 0 }
        XCTAssertFalse(allZero, "Signed portion must not be all zeros")
    }
}
