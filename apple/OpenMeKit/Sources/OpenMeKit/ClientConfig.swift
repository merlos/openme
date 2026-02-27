import Foundation

// Swift value types mirroring the YAML schema of ~/.openme/config.yaml.
// Parsing is done manually to avoid a third-party YAML dependency; the
// config format is simple enough for a lightweight line-based parser.

/// A single named client profile that holds everything needed to knock a server.
///
/// Profiles are persisted in `config.yaml` under the `profiles:` key and are
/// produced by `openme add` on the server. Each profile contains the server
/// connection details and the client's Ed25519 signing key pair.
///
/// - Important: The ``privateKey`` field contains a raw Ed25519 seed and must
///   be handled with care. ``ProfileStore`` writes the backing file with
///   `0600` permissions and never logs key material.
public struct Profile: Codable, Identifiable, Equatable {
    /// Stable identifier — equals ``name``.
    public var id: String { name }
    /// Key used in the `profiles:` YAML map and displayed in the UI.
    public var name: String

    /// Hostname or IP address of the openme server.
    public var serverHost: String
    /// UDP port the server listens on for SPA knock packets (default `7777`).
    public var serverUDPPort: UInt16
    /// Base64-encoded Curve25519 public key of the server.
    /// Used for the ECDH key agreement step of the knock protocol.
    public var serverPubKey: String
    /// Base64-encoded Ed25519 private key (32-byte seed, or 64-byte seed+public).
    /// - Warning: Treat this value as a secret. Never log or transmit it.
    public var privateKey: String
    /// Base64-encoded Ed25519 public key corresponding to ``privateKey``.
    public var publicKey: String
    /// Optional shell command executed after a successful knock (macOS only).
    /// Leave empty to skip. Example: `"open ssh://myserver.example.com"`.
    public var postKnock: String

    /// Creates a new profile.
    ///
    /// - Parameters:
    ///   - name: Unique profile identifier used as the YAML map key.
    ///   - serverHost: Hostname or IP of the openme server.
    ///   - serverUDPPort: UDP port the server listens on. Defaults to `7777`.
    ///   - serverPubKey: Base64-encoded Curve25519 public key of the server.
    ///   - privateKey: Base64-encoded Ed25519 private key of this client.
    ///   - publicKey: Base64-encoded Ed25519 public key of this client.
    ///   - postKnock: Optional shell command to run after a successful knock.
    public init(
        name: String,
        serverHost: String = "",
        serverUDPPort: UInt16 = 7777,
        serverPubKey: String = "",
        privateKey: String = "",
        publicKey: String = "",
        postKnock: String = ""
    ) {
        self.name = name
        self.serverHost = serverHost
        self.serverUDPPort = serverUDPPort
        self.serverPubKey = serverPubKey
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.postKnock = postKnock
    }
}

/// Lightweight profile summary used in list views and menus.
///
/// `ProfileEntry` deliberately omits key material so it can be safely passed to
/// UI layers that have no need for the Ed25519 private key. Full details are
/// available via ``ProfileStore/profile(named:)``.
public struct ProfileEntry: Identifiable {
    /// Stable identifier — equals ``name``.
    public var id: String { name }
    /// Profile name as stored in `config.yaml`.
    public let name: String
    /// Hostname or IP address of the openme server.
    public let serverHost: String
    /// UDP port the server listens on for knock packets.
    public let serverUDPPort: UInt16

    /// Creates a lightweight profile entry.
    ///
    /// - Parameters:
    ///   - name: Profile name.
    ///   - serverHost: Hostname or IP of the server.
    ///   - serverUDPPort: UDP port of the server.
    public init(name: String, serverHost: String, serverUDPPort: UInt16) {
        self.name = name
        self.serverHost = serverHost
        self.serverUDPPort = serverUDPPort
    }
}

// MARK: - YAML parsing

/// Parses and serialises the `config.yaml` client configuration file.
///
/// The parser is a lightweight, line-based YAML reader that handles the
/// specific subset of YAML produced by `openme add`. It supports both the
/// 2-space indentation of go-yaml v2 and the 4-space indentation of go-yaml v3.
///
/// Expected YAML schema:
/// ```yaml
/// profiles:
///   <name>:
///     server_host: "..."
///     server_udp_port: 7777
///     server_pubkey: "..."
///     private_key: "..."
///     public_key:  "..."
///     post_knock:  "..."
/// ```
///
/// For the full config format reference see the
/// [Client Configuration](https://openme.merlos.org/docs/configuration/client.html) docs.
public enum ClientConfigParser {

    /// Parses a `config.yaml` YAML string into a dictionary of profiles.
    ///
    /// The parser auto-detects the indentation width used by the YAML emitter
    /// so it works with both go-yaml v2 (2-space) and go-yaml v3 (4-space) output.
    ///
    /// - Parameter yaml: Full contents of the `config.yaml` file.
    /// - Returns: A dictionary mapping profile names to ``Profile`` values.
    /// - Throws: ``ParserError/noProfilesFound`` if the YAML contains no
    ///   `profiles:` section or all profiles fail to parse.
    public static func parse(yaml: String) throws -> [String: Profile] {
        var profiles: [String: Profile] = [:]

        // Work on raw lines so we can measure indentation before stripping.
        let rawLines = yaml.components(separatedBy: .newlines)

        var inProfiles = false
        var currentName: String?
        var currentDict: [String: String] = [:]
        // Detected once we see the first profile-name line.
        var profileIndent: Int? = nil
        var kvIndent:      Int? = nil

        /// Returns the leading-whitespace depth of a raw YAML line.
        /// Each space counts as 1; each tab is expanded to 4 spaces so that
        /// tab-indented YAML (typed manually or emitted by some editors) is
        /// handled the same way as space-indented YAML.
        func leadingSpaces(_ s: String) -> Int {
            var count = 0
            for ch in s {
                if ch == " "  { count += 1 }
                else if ch == "\t" { count += 4 }
                else { break }
            }
            return count
        }

        func flushCurrent() {
            guard let name = currentName else { return }
            profiles[name] = Profile(
                name: name,
                serverHost:    currentDict["server_host"] ?? "",
                serverUDPPort: UInt16(currentDict["server_udp_port"] ?? "7777") ?? 7777,
                serverPubKey:  currentDict["server_pubkey"] ?? "",
                privateKey:    currentDict["private_key"] ?? "",
                publicKey:     currentDict["public_key"] ?? "",
                postKnock:     currentDict["post_knock"] ?? ""
            )
        }

        for rawLine in rawLines {
            let indent = leadingSpaces(rawLine)
            let line   = rawLine.trimmingCharacters(in: .init(charactersIn: " \t\r"))

            if line.isEmpty || line.hasPrefix("#") { continue }

            if line == "profiles:" {
                inProfiles = true
                continue
            }

            guard inProfiles else { continue }

            // Detect profile-name indent from the first indented line after "profiles:".
            if profileIndent == nil && indent > 0 {
                profileIndent = indent
            }

            let pIndent = profileIndent ?? 2

            // Profile name: indented exactly one level, ends with ":", no spaces in name.
            if indent == pIndent && line.hasSuffix(":") && !line.dropLast().contains(" ") {
                flushCurrent()
                currentName = String(line.dropLast())
                currentDict = [:]
                // Learn key-value indent from the next deeper line.
                kvIndent = nil
                continue
            }

            // Key-value pair: deeper than profile indent.
            if indent > pIndent {
                // Learn kv indent on first encounter.
                if kvIndent == nil { kvIndent = indent }
                guard indent == kvIndent else { continue }

                if let colonIdx = line.firstIndex(of: ":") {
                    let key = String(line[line.startIndex..<colonIdx])
                        .trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIdx)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    currentDict[key] = value
                }
            }
        }
        flushCurrent()

        if profiles.isEmpty {
            throw ParserError.noProfilesFound
        }
        return profiles
    }

    /// Serialises a dictionary of profiles back to `config.yaml` YAML.
    ///
    /// Profiles are sorted alphabetically by name so the output is deterministic.
    /// The result uses 2-space indentation and quoted string values, and is
    /// compatible with the Go server's `openme add` format.
    ///
    /// - Parameter profiles: Dictionary of profile name → ``Profile`` to serialise.
    /// - Returns: A UTF-8 YAML string ready to be written to `config.yaml`.
    public static func serialize(profiles: [String: Profile]) -> String {
        var out = "profiles:\n"
        for (name, p) in profiles.sorted(by: { $0.key < $1.key }) {
            out += "  \(name):\n"
            out += "    server_host: \"\(p.serverHost)\"\n"
            out += "    server_udp_port: \(p.serverUDPPort)\n"
            out += "    server_pubkey: \"\(p.serverPubKey)\"\n"
            out += "    private_key: \"\(p.privateKey)\"\n"
            out += "    public_key: \"\(p.publicKey)\"\n"
            if !p.postKnock.isEmpty {
                out += "    post_knock: \"\(p.postKnock)\"\n"
            }
        }
        return out
    }

    /// Errors thrown by ``ClientConfigParser/parse(yaml:)``.
    public enum ParserError: LocalizedError {
        /// The YAML string contained no `profiles:` key or all entries were malformed.
        case noProfilesFound
        public var errorDescription: String? { "No profiles found in the YAML. Make sure the content starts with 'profiles:'." }
    }
}
