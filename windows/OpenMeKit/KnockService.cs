using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using Org.BouncyCastle.Crypto.Agreement;
using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;

namespace OpenMeKit;

/// <summary>
/// Pure .NET implementation of the openme SPA knock protocol.
/// </summary>
/// <remarks>
/// <para>
/// <c>KnockService</c> handles the complete client-side knock sequence:
/// ephemeral X25519 ECDH → HKDF-SHA256 key derivation → ChaCha20-Poly1305
/// encryption → Ed25519 signature → UDP datagram dispatch.
/// </para>
///
/// <para><b>Wire format</b> — every knock is a fixed-size <b>165-byte</b> UDP datagram:</para>
/// <code>
///  0       1      33      45                  101                  165
///  ┌───────┬──────┬───────┬────────────────────┬────────────────────┐
///  │version│ephem │ nonce │     ciphertext     │    ed25519_sig     │
///  │  1 B  │ 32 B │  12 B │       56 B         │       64 B         │
///  └───────┴──────┴───────┴────────────────────┴────────────────────┘
///  ◄──────────────── signed portion (101 B) ───────────────────────►
/// </code>
/// <para>
/// Plaintext (40 bytes): 8-byte nanosecond Unix timestamp (big-endian) |
/// 16-byte random nonce | 16-byte target IPv6 (zeros = use source IP).
/// </para>
/// </remarks>
public static class KnockService
{
    /// <summary>SPA protocol version byte embedded in every packet.</summary>
    public const byte ProtocolVersion = 1;

    /// <summary>Total size of a knock packet in bytes.</summary>
    public const int PacketSize = 165;

    /// <summary>Number of bytes covered by the Ed25519 signature (PacketSize − 64).</summary>
    public const int SignedPortionSize = 101;

    private static readonly byte[] HkdfInfo = Encoding.UTF8.GetBytes("openme-v1-chacha20poly1305");

    // ── Public API ────────────────────────────────────────────────────────────

    /// <summary>
    /// Sends a single SPA knock packet to the server asynchronously.
    /// </summary>
    /// <remarks>
    /// A successful return means the OS accepted the datagram for transmission; it does
    /// <b>not</b> confirm the server received it or that a firewall rule was opened.
    /// </remarks>
    /// <param name="serverHost">Hostname or IP address string of the openme server.</param>
    /// <param name="serverPort">UDP port the server is listening on (usually <c>54154</c>).</param>
    /// <param name="serverPubKeyBase64">Base64-encoded 32-byte Curve25519 public key of the server.</param>
    /// <param name="clientPrivKeyBase64">
    /// Base64-encoded Ed25519 private key of this client.
    /// Accepts both 32-byte (seed) and 64-byte (seed + public key) encodings.
    /// </param>
    /// <param name="cancellationToken">Optional cancellation token.</param>
    /// <exception cref="KnockException">Thrown for any key, packet-building, or send error.</exception>
    public static async Task KnockAsync(
        string serverHost,
        ushort serverPort,
        string serverPubKeyBase64,
        string clientPrivKeyBase64,
        CancellationToken cancellationToken = default)
    {
        var packet = BuildPacket(serverPubKeyBase64, clientPrivKeyBase64);

        using var udp = new UdpClient();
        try
        {
            await udp.SendAsync(new ReadOnlyMemory<byte>(packet), new System.Net.IPEndPoint(
                    // Resolve hostname or parse IP
                    (await System.Net.Dns.GetHostAddressesAsync(serverHost, cancellationToken))[0],
                    serverPort),
                cancellationToken);
        }
        catch (KnockException) { throw; }
        catch (Exception ex)
        {
            throw new KnockException(KnockErrorKind.SendFailed,
                $"UDP send to {serverHost}:{serverPort} failed: {ex.Message}", ex);
        }
    }

    /// <summary>
    /// Builds the 165-byte SPA packet. Exposed publicly for unit testing.
    /// </summary>
    /// <param name="serverPubKeyBase64">Base64-encoded 32-byte Curve25519 server public key.</param>
    /// <param name="clientPrivKeyBase64">Base64-encoded Ed25519 private key (32 or 64 bytes).</param>
    /// <returns>165-byte packet ready for UDP transmission.</returns>
    /// <exception cref="KnockException">Thrown for invalid key or construction failures.</exception>
    public static byte[] BuildPacket(string serverPubKeyBase64, string clientPrivKeyBase64)
    {
        // --- Decode server public key (must be 32 bytes / X25519)
        byte[] serverPubKeyBytes;
        try   { serverPubKeyBytes = Convert.FromBase64String(serverPubKeyBase64); }
        catch { throw new KnockException(KnockErrorKind.InvalidServerKey, "Server public key is not valid base64."); }
        if (serverPubKeyBytes.Length != 32)
            throw new KnockException(KnockErrorKind.InvalidServerKey,
                $"Server public key must be 32 bytes, got {serverPubKeyBytes.Length}.");

        // --- Decode client private key (Ed25519 seed = first 32 bytes)
        byte[] clientPrivKeyBytes;
        try   { clientPrivKeyBytes = Convert.FromBase64String(clientPrivKeyBase64); }
        catch { throw new KnockException(KnockErrorKind.InvalidClientKey, "Client private key is not valid base64."); }

        var seed = clientPrivKeyBytes.Length switch
        {
            64 => clientPrivKeyBytes[..32],
            32 => clientPrivKeyBytes,
            _  => throw new KnockException(KnockErrorKind.InvalidClientKey,
                      $"Client private key must be 32 or 64 bytes, got {clientPrivKeyBytes.Length}.")
        };

        try   { return BuildPacketInternal(serverPubKeyBytes, seed); }
        catch (KnockException) { throw; }
        catch (Exception ex)
        {
            throw new KnockException(KnockErrorKind.PacketBuildFailed,
                $"Packet construction failed: {ex.Message}", ex);
        }
    }

    // ── Internal packet construction ──────────────────────────────────────────

    private static byte[] BuildPacketInternal(byte[] serverPubKeyBytes, byte[] seed)
    {
        var rng = new SecureRandom();

        // 1. Ephemeral X25519 key pair
        var ephemeralGen = new X25519KeyPairGenerator();
        ephemeralGen.Init(new X25519KeyGenerationParameters(rng));
        var ephemeralKp   = ephemeralGen.GenerateKeyPair();
        var ephemeralPriv = (X25519PrivateKeyParameters)ephemeralKp.Private;
        var ephemeralPub  = (X25519PublicKeyParameters)ephemeralKp.Public;
        var ephemeralPubBytes = ephemeralPub.GetEncoded(); // 32 bytes

        // 2. ECDH: ephemeral private × server public → 32-byte shared secret
        var serverPubParams = new X25519PublicKeyParameters(serverPubKeyBytes);
        var agreement = new X25519Agreement();
        agreement.Init(ephemeralPriv);
        var sharedSecret = new byte[agreement.AgreementSize]; // 32
        agreement.CalculateAgreement(serverPubParams, sharedSecret, 0);

        // 3. HKDF-SHA256: sharedSecret → 32-byte ChaCha20-Poly1305 key
        var chachaKey = HKDF.DeriveKey(HashAlgorithmName.SHA256,
            ikm:          sharedSecret,
            outputLength: 32,
            salt:         ReadOnlySpan<byte>.Empty,
            info:         HkdfInfo);

        // 4. 12-byte ChaCha20 nonce (random)
        var nonce = new byte[12];
        rng.NextBytes(nonce);

        // 5. Plaintext: 40 bytes
        //    [0..7]  = nanosecond Unix timestamp, big-endian int64
        //    [8..23] = 16-byte random padding
        //    [24..39]= 16-byte target IP (zeros → use packet source IP)
        var plaintext = new byte[40];
        long nanos = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1_000_000L;
        for (int i = 0; i < 8; i++)
            plaintext[7 - i] = (byte)(nanos >> (8 * i));

        var randomPad = new byte[16];
        rng.NextBytes(randomPad);
        randomPad.CopyTo(plaintext, 8);
        // bytes 24-39 remain zero (target IP = source IP)

        // 6. ChaCha20-Poly1305 encrypt → ciphertext (40 B) + tag (16 B) = 56 B
        var ciphertext = new byte[40];
        var tag        = new byte[16];
        using var chacha = new ChaCha20Poly1305(chachaKey);
        chacha.Encrypt(nonce, plaintext, ciphertext, tag);

        var ciphertextWithTag = new byte[56];
        ciphertext.CopyTo(ciphertextWithTag, 0);
        tag.CopyTo(ciphertextWithTag, 40);

        // 7. Assemble signed portion (101 bytes):
        //    version(1) | ephem_pubkey(32) | nonce(12) | ciphertext+tag(56)
        var signedPortion = new byte[SignedPortionSize];
        signedPortion[0] = ProtocolVersion;
        ephemeralPubBytes.CopyTo(signedPortion, 1);   // 1..32
        nonce.CopyTo(signedPortion, 33);               // 33..44
        ciphertextWithTag.CopyTo(signedPortion, 45);   // 45..100

        // 8. Ed25519 sign over bytes [0..100]
        var signingKeyParams = new Ed25519PrivateKeyParameters(seed);
        var signer = new Ed25519Signer();
        signer.Init(true, signingKeyParams);
        signer.BlockUpdate(signedPortion, 0, signedPortion.Length);
        var signature = signer.GenerateSignature(); // 64 bytes

        // 9. Final 165-byte packet = signedPortion(101) | signature(64)
        var packet = new byte[PacketSize];
        signedPortion.CopyTo(packet, 0);
        signature.CopyTo(packet, SignedPortionSize);

        return packet;
    }
}

// ── Error types ───────────────────────────────────────────────────────────────

/// <summary>Error categories for <see cref="KnockException"/>.</summary>
public enum KnockErrorKind
{
    /// <summary>The server public key could not be decoded or has the wrong length.</summary>
    InvalidServerKey,
    /// <summary>The client private key could not be decoded or has the wrong length.</summary>
    InvalidClientKey,
    /// <summary>Packet construction failed (ECDH, HKDF, AEAD, or signing error).</summary>
    PacketBuildFailed,
    /// <summary>The UDP datagram could not be dispatched.</summary>
    SendFailed,
}

/// <summary>Exception thrown by <see cref="KnockService"/>.</summary>
public sealed class KnockException(KnockErrorKind kind, string message, Exception? inner = null)
    : Exception(message, inner)
{
    /// <summary>The specific category of knock failure.</summary>
    public KnockErrorKind Kind { get; } = kind;
}
