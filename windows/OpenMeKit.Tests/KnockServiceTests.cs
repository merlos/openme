using OpenMeKit;
using Xunit;

namespace OpenMeKit.Tests;

/// <summary>Unit tests for <see cref="KnockService"/> packet construction.</summary>
public sealed class KnockServiceTests
{
    // A pair of real test keys (ed25519 client + x25519 server) suitable for unit tests.
    // These are NOT used in production; they are committed only for test purposes.
    private const string TestServerPubKey  = "wfLHOBMHSXQT5YN0yCFW2y0TKhkXPrfMjklBkdGg5kM="; // 32 B X25519
    private const string TestClientPrivKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";   // 32 B Ed25519 seed (all-zeros test vector)

    [Fact]
    public void BuildPacket_ReturnsExact165Bytes()
    {
        var packet = KnockService.BuildPacket(TestServerPubKey, TestClientPrivKey);
        Assert.Equal(KnockService.PacketSize, packet.Length);
    }

    [Fact]
    public void BuildPacket_FirstByteIsProtocolVersion()
    {
        var packet = KnockService.BuildPacket(TestServerPubKey, TestClientPrivKey);
        Assert.Equal(KnockService.ProtocolVersion, packet[0]);
    }

    [Fact]
    public void BuildPacket_TwoCallsDifferInEphemeralKey()
    {
        // Ephemeral key (bytes 1-32) must be freshly generated each time.
        var p1 = KnockService.BuildPacket(TestServerPubKey, TestClientPrivKey);
        var p2 = KnockService.BuildPacket(TestServerPubKey, TestClientPrivKey);
        Assert.NotEqual(p1[1..33], p2[1..33]);
    }

    [Fact]
    public void BuildPacket_InvalidServerKeyThrows()
    {
        var ex = Assert.Throws<KnockException>(() =>
            KnockService.BuildPacket("not-base64!!", TestClientPrivKey));
        Assert.Equal(KnockErrorKind.InvalidServerKey, ex.Kind);
    }

    [Fact]
    public void BuildPacket_WrongLengthServerKeyThrows()
    {
        // 16 bytes → not 32
        var ex = Assert.Throws<KnockException>(() =>
            KnockService.BuildPacket(Convert.ToBase64String(new byte[16]), TestClientPrivKey));
        Assert.Equal(KnockErrorKind.InvalidServerKey, ex.Kind);
    }

    [Fact]
    public void BuildPacket_InvalidClientKeyThrows()
    {
        var ex = Assert.Throws<KnockException>(() =>
            KnockService.BuildPacket(TestServerPubKey, "!!!invalid!!!"));
        Assert.Equal(KnockErrorKind.InvalidClientKey, ex.Kind);
    }

    [Fact]
    public void BuildPacket_64ByteClientKeyAccepted()
    {
        // 64-byte key = seed(32) + pub(32); only the seed should be used.
        var seed = new byte[32];
        var pub  = new byte[32];
        var combined = Convert.ToBase64String([.. seed, .. pub]);

        var packet = KnockService.BuildPacket(TestServerPubKey, combined);
        Assert.Equal(KnockService.PacketSize, packet.Length);
    }
}
