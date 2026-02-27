namespace OpenMeKit;

/// <summary>
/// A single named client profile holding everything needed to knock an openme server.
/// </summary>
/// <remarks>
/// Profiles are persisted in <c>%APPDATA%\openme\profiles.json</c> and can also be
/// imported from the YAML block emitted by <c>openme add</c> on the server.
/// </remarks>
public sealed class Profile
{
    /// <summary>Unique identifier — equals <see cref="Name"/>.</summary>
    public string Id => Name;

    /// <summary>Key used in the profiles store and displayed in the UI.</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>Hostname or IP address of the openme server.</summary>
    public string ServerHost { get; set; } = string.Empty;

    /// <summary>UDP port the server listens on for SPA knock packets (default <c>54154</c>).</summary>
    public ushort ServerUdpPort { get; set; } = 54154;

    /// <summary>Base64-encoded 32-byte Curve25519 public key of the server.</summary>
    public string ServerPubKey { get; set; } = string.Empty;

    /// <summary>
    /// Base64-encoded Ed25519 private key of this client.
    /// Accepts both 32-byte (seed) and 64-byte (seed + public key) encodings.
    /// </summary>
    /// <remarks>Treat as a secret. Never log or display without masking.</remarks>
    public string PrivateKey { get; set; } = string.Empty;

    /// <summary>Base64-encoded Ed25519 public key corresponding to <see cref="PrivateKey"/>.</summary>
    public string PublicKey { get; set; } = string.Empty;

    /// <summary>
    /// Optional shell command executed after a successful knock.
    /// Leave empty to skip. Example: <c>start ssh://myserver.example.com</c>.
    /// </summary>
    public string PostKnock { get; set; } = string.Empty;

    /// <summary>Creates a deep copy of this profile.</summary>
    public Profile Clone() => new()
    {
        Name         = Name,
        ServerHost   = ServerHost,
        ServerUdpPort = ServerUdpPort,
        ServerPubKey = ServerPubKey,
        PrivateKey   = PrivateKey,
        PublicKey    = PublicKey,
        PostKnock    = PostKnock,
    };
}

/// <summary>
/// Lightweight profile summary used in list views and menus.
/// Deliberately omits key material.
/// </summary>
public sealed class ProfileEntry
{
    /// <summary>Stable identifier — equals <see cref="Name"/>.</summary>
    public string Id => Name;

    /// <summary>Profile name as stored in the config.</summary>
    public string Name { get; }

    /// <summary>Hostname or IP address of the openme server.</summary>
    public string ServerHost { get; }

    /// <summary>UDP port the server listens on for knock packets.</summary>
    public ushort ServerUdpPort { get; }

    /// <summary>Creates a lightweight profile entry.</summary>
    public ProfileEntry(string name, string serverHost, ushort serverUdpPort)
    {
        Name          = name;
        ServerHost    = serverHost;
        ServerUdpPort = serverUdpPort;
    }

    /// <summary>Display string shown in list controls.</summary>
    public override string ToString() => $"{Name}  ({ServerHost}:{ServerUdpPort})";
}
