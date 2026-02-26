import Foundation

// Swift value types mirroring the YAML schema of ~/.openme/config.yaml.
// Parsing is done manually to avoid a third-party YAML dependency; the
// config format is simple enough for a lightweight line-based parser.

/// A single named client profile.
public struct Profile: Codable, Identifiable, Equatable {
    public var id: String { name }
    public var name: String           // key in the profiles map

    public var serverHost: String
    public var serverUDPPort: UInt16
    public var serverPubKey: String
    public var privateKey: String
    public var publicKey: String
    public var postKnock: String

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

/// Lightweight entry used by the menu (avoids exposing private keys unnecessarily).
public struct ProfileEntry: Identifiable {
    public var id: String { name }
    public let name: String
    public let serverHost: String
    public let serverUDPPort: UInt16
}

// MARK: - YAML parsing

/// Parses the client config YAML into a dictionary of `Profile` values.
///
/// The format produced by `openme add` is:
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
public enum ClientConfigParser {

    public static func parse(yaml: String) throws -> [String: Profile] {
        var profiles: [String: Profile] = [:]

        // Collect all lines, strip trailing whitespace.
        let lines = yaml.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .init(charactersIn: " \t\r")) }

        var inProfiles = false
        var currentName: String?
        var currentDict: [String: String] = [:]

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

        for line in lines {
            if line.hasPrefix("#") || line.isEmpty { continue }

            let indent = yaml.components(separatedBy: .newlines)
                .first(where: { $0.contains(line) })
                .map { $0.prefix(while: { $0 == " " }).count } ?? 0

            if line == "profiles:" {
                inProfiles = true
                continue
            }

            guard inProfiles else { continue }

            // Profile name — 2-space indent, ends with ":"
            if indent == 2 && line.hasSuffix(":") && !line.contains(" ") {
                flushCurrent()
                currentName = String(line.dropLast())
                currentDict = [:]
                continue
            }

            // Key-value pair — 4-space indent
            if indent == 4, let colonIdx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIdx])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                currentDict[key] = value
            }
        }
        flushCurrent()

        if profiles.isEmpty {
            throw ParserError.noProfilesFound
        }
        return profiles
    }

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

    public enum ParserError: LocalizedError {
        case noProfilesFound
        public var errorDescription: String? { "No profiles found in the YAML. Make sure the content starts with 'profiles:'." }
    }
}
