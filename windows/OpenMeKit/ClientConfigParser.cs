using System.Text.RegularExpressions;

namespace OpenMeKit;

/// <summary>
/// Parses and serialises the <c>~/.openme/config.yaml</c> client configuration file.
/// </summary>
/// <remarks>
/// The parser is a lightweight, line-based YAML reader that handles the specific subset
/// of YAML produced by <c>openme add</c>. It supports both the 2-space indentation of
/// go-yaml v2 and the 4-space indentation of go-yaml v3, as well as the QR-code JSON
/// payload format used by the mobile apps.
///
/// Expected YAML schema:
/// <code>
/// profiles:
///   &lt;name&gt;:
///     server_host: "..."
///     server_udp_port: 54154
///     server_pubkey: "..."
///     private_key: "..."
///     public_key:  "..."
///     post_knock:  "..."
/// </code>
/// </remarks>
public static class ClientConfigParser
{
    // ── YAML parsing ──────────────────────────────────────────────────────────

    /// <summary>
    /// Parses a <c>config.yaml</c> string into a dictionary of <see cref="Profile"/> objects
    /// keyed by profile name.
    /// </summary>
    /// <param name="yaml">Content of a config.yaml produced by <c>openme add</c>.</param>
    /// <returns>Dictionary mapping profile name → <see cref="Profile"/>.</returns>
    /// <exception cref="ClientConfigException">Thrown when no profiles can be found.</exception>
    public static Dictionary<string, Profile> ParseYaml(string yaml)
    {
        var profiles = new Dictionary<string, Profile>(StringComparer.Ordinal);
        var lines = yaml.ReplaceLineEndings("\n").Split('\n');

        // Detect indentation level (2 or 4 spaces) from the first profile-name line
        // that appears directly under "profiles:".
        int indent = 0;
        bool inProfiles = false;

        foreach (var raw in lines)
        {
            if (raw.TrimStart().StartsWith("profiles:", StringComparison.Ordinal))
            {
                inProfiles = true;
                continue;
            }
            if (!inProfiles) continue;

            // First non-empty line after "profiles:" is a profile name at indent N.
            var trimmed = raw.TrimEnd();
            if (trimmed.Length == 0) continue;

            int spaces = trimmed.Length - trimmed.TrimStart().Length;
            if (spaces > 0) { indent = spaces; break; }
        }

        if (indent == 0) indent = 2; // fallback

        Profile? current = null;
        inProfiles = false;

        foreach (var raw in lines)
        {
            var line = raw.TrimEnd();
            if (line.TrimStart().StartsWith("profiles:", StringComparison.Ordinal))
            {
                inProfiles = true;
                continue;
            }
            if (!inProfiles) continue;
            if (line.Trim().Length == 0) continue;

            int depth = (line.Length - line.TrimStart().Length) / indent;

            if (depth == 1)
            {
                // Profile name line: "  alice:"
                if (current != null && !string.IsNullOrEmpty(current.Name))
                    profiles[current.Name] = current;

                var name = line.Trim().TrimEnd(':');
                current = new Profile { Name = name };
                continue;
            }

            if (depth == 2 && current != null)
            {
                var (key, value) = SplitKeyValue(line.Trim());
                switch (key)
                {
                    case "server_host":     current.ServerHost    = value; break;
                    case "server_udp_port": current.ServerUdpPort = ushort.TryParse(value, out var p) ? p : (ushort)54154; break;
                    case "server_pubkey":   current.ServerPubKey  = value; break;
                    case "private_key":     current.PrivateKey    = value; break;
                    case "public_key":      current.PublicKey     = value; break;
                    case "post_knock":      current.PostKnock     = value; break;
                }
            }
        }

        if (current != null && !string.IsNullOrEmpty(current.Name))
            profiles[current.Name] = current;

        if (profiles.Count == 0)
            throw new ClientConfigException(ClientConfigError.NoProfilesFound,
                "No profiles found in the YAML. Make sure the text starts with 'profiles:'.");

        return profiles;
    }

    // ── QR payload parsing ────────────────────────────────────────────────────

    /// <summary>
    /// Parses the JSON payload encoded in an openme QR code.
    /// </summary>
    /// <param name="json">
    /// JSON string with keys: <c>profile</c>, <c>host</c>, <c>udp_port</c>,
    /// <c>server_pubkey</c>, <c>client_privkey</c>, <c>client_pubkey</c>.
    /// </param>
    /// <returns>A populated <see cref="Profile"/>.</returns>
    /// <exception cref="ClientConfigException">Thrown when required fields are missing.</exception>
    public static Profile ParseQrPayload(string json)
    {
        // Lightweight JSON field extraction without a full JSON parser dependency.
        string? Get(string field)
        {
            // Matches: "field": "value"  or  "field":"value"
            var m = Regex.Match(json, $"\"{Regex.Escape(field)}\"\\s*:\\s*\"([^\"]*)\"");
            return m.Success ? m.Groups[1].Value : null;
        }
        string? GetInt(string field)
        {
            var m = Regex.Match(json, $"\"{Regex.Escape(field)}\"\\s*:\\s*(\\d+)");
            return m.Success ? m.Groups[1].Value : null;
        }

        var name   = Get("profile");
        var host   = Get("host");
        var port   = GetInt("udp_port");
        var sPub   = Get("server_pubkey");
        var cPriv  = Get("client_privkey");
        var cPub   = Get("client_pubkey");

        if (string.IsNullOrEmpty(name) || string.IsNullOrEmpty(host) ||
            string.IsNullOrEmpty(sPub)  || string.IsNullOrEmpty(cPriv))
            throw new ClientConfigException(ClientConfigError.InvalidQrPayload,
                "QR payload is missing required fields (profile, host, server_pubkey, client_privkey).");

        return new Profile
        {
            Name          = name,
            ServerHost    = host,
            ServerUdpPort = ushort.TryParse(port, out var p) ? p : (ushort)54154,
            ServerPubKey  = sPub,
            PrivateKey    = cPriv,
            PublicKey     = cPub ?? string.Empty,
        };
    }

    // ── YAML serialisation ────────────────────────────────────────────────────

    /// <summary>
    /// Serialises a collection of profiles to the <c>config.yaml</c> format compatible
    /// with the openme CLI.
    /// </summary>
    public static string ToYaml(IEnumerable<Profile> profiles)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("profiles:");
        foreach (var p in profiles)
        {
            sb.AppendLine($"    {p.Name}:");
            sb.AppendLine($"        server_host: {p.ServerHost}");
            sb.AppendLine($"        server_udp_port: {p.ServerUdpPort}");
            sb.AppendLine($"        server_pubkey: {p.ServerPubKey}");
            sb.AppendLine($"        private_key: {p.PrivateKey}");
            sb.AppendLine($"        public_key: {p.PublicKey}");
            if (!string.IsNullOrEmpty(p.PostKnock))
                sb.AppendLine($"        post_knock: {p.PostKnock}");
        }
        return sb.ToString();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static (string key, string value) SplitKeyValue(string line)
    {
        var idx = line.IndexOf(':', StringComparison.Ordinal);
        if (idx < 0) return (line, string.Empty);
        var key   = line[..idx].Trim();
        var value = line[(idx + 1)..].Trim().Trim('"');
        return (key, value);
    }
}

/// <summary>Error categories for <see cref="ClientConfigException"/>.</summary>
public enum ClientConfigError
{
    /// <summary>The YAML contained no <c>profiles:</c> section with entries.</summary>
    NoProfilesFound,
    /// <summary>The QR-code JSON payload was missing required fields or was malformed.</summary>
    InvalidQrPayload,
}

/// <summary>Exception thrown by <see cref="ClientConfigParser"/>.</summary>
public sealed class ClientConfigException(ClientConfigError kind, string message)
    : Exception(message)
{
    /// <summary>The specific parse error that occurred.</summary>
    public ClientConfigError Kind { get; } = kind;
}
