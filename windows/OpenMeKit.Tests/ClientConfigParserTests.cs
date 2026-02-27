using OpenMeKit;
using Xunit;

namespace OpenMeKit.Tests;

/// <summary>Unit tests for <see cref="ClientConfigParser"/>.</summary>
public sealed class ClientConfigParserTests
{
    private const string SampleYaml = """
        profiles:
            alice:
                server_host: server.example.com
                server_udp_port: 54154
                server_pubkey: abc123=
                private_key: priv123=
                public_key: pub123=
                post_knock: start ssh://server.example.com
            bob:
                server_host: 10.0.0.1
                server_udp_port: 9000
                server_pubkey: xyz=
                private_key: privbob=
                public_key: pubbob=
        """;

    // ── ParseYaml ──

    [Fact]
    public void ParseYaml_TwoProfilesReturned()
    {
        var profiles = ClientConfigParser.ParseYaml(SampleYaml);
        Assert.Equal(2, profiles.Count);
    }

    [Fact]
    public void ParseYaml_AliceFieldsCorrect()
    {
        var profiles = ClientConfigParser.ParseYaml(SampleYaml);
        var alice = profiles["alice"];
        Assert.Equal("alice",                alice.Name);
        Assert.Equal("server.example.com",   alice.ServerHost);
        Assert.Equal((ushort)54154,           alice.ServerUdpPort);
        Assert.Equal("abc123=",              alice.ServerPubKey);
        Assert.Equal("priv123=",             alice.PrivateKey);
        Assert.Equal("pub123=",              alice.PublicKey);
        Assert.Equal("start ssh://server.example.com", alice.PostKnock);
    }

    [Fact]
    public void ParseYaml_BobPortOverride()
    {
        var profiles = ClientConfigParser.ParseYaml(SampleYaml);
        Assert.Equal((ushort)9000, profiles["bob"].ServerUdpPort);
    }

    [Fact]
    public void ParseYaml_EmptyStringThrows()
    {
        var ex = Assert.Throws<ClientConfigException>(() =>
            ClientConfigParser.ParseYaml(""));
        Assert.Equal(ClientConfigError.NoProfilesFound, ex.Kind);
    }

    [Fact]
    public void ParseYaml_NoProfilesSectionThrows()
    {
        var ex = Assert.Throws<ClientConfigException>(() =>
            ClientConfigParser.ParseYaml("key: value\nother: thing\n"));
        Assert.Equal(ClientConfigError.NoProfilesFound, ex.Kind);
    }

    // ── ParseQrPayload ──

    private const string SampleQr = """
        {"profile":"home","host":"home.example.com","udp_port":54154,
         "server_pubkey":"srvKey=","client_privkey":"cliPriv=","client_pubkey":"cliPub="}
        """;

    [Fact]
    public void ParseQrPayload_FieldsCorrect()
    {
        var p = ClientConfigParser.ParseQrPayload(SampleQr);
        Assert.Equal("home",             p.Name);
        Assert.Equal("home.example.com", p.ServerHost);
        Assert.Equal((ushort)54154,      p.ServerUdpPort);
        Assert.Equal("srvKey=",          p.ServerPubKey);
        Assert.Equal("cliPriv=",         p.PrivateKey);
        Assert.Equal("cliPub=",          p.PublicKey);
    }

    [Fact]
    public void ParseQrPayload_MissingRequiredFieldThrows()
    {
        var ex = Assert.Throws<ClientConfigException>(() =>
            ClientConfigParser.ParseQrPayload("""{"host":"x.com"}"""));
        Assert.Equal(ClientConfigError.InvalidQrPayload, ex.Kind);
    }

    // ── YAML round-trip ──

    [Fact]
    public void ToYaml_RoundTrip()
    {
        var original = ClientConfigParser.ParseYaml(SampleYaml);
        var yaml     = ClientConfigParser.ToYaml(original.Values);
        var reparsed = ClientConfigParser.ParseYaml(yaml);

        Assert.Equal(original.Count, reparsed.Count);
        foreach (var (name, p) in original)
        {
            Assert.True(reparsed.ContainsKey(name));
            var r = reparsed[name];
            Assert.Equal(p.ServerHost,    r.ServerHost);
            Assert.Equal(p.ServerUdpPort, r.ServerUdpPort);
            Assert.Equal(p.ServerPubKey,  r.ServerPubKey);
            Assert.Equal(p.PrivateKey,    r.PrivateKey);
            Assert.Equal(p.PublicKey,     r.PublicKey);
        }
    }
}
