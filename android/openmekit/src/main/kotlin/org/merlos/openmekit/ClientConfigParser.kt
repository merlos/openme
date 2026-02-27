package org.merlos.openmekit

import org.json.JSONObject

/**
 * Parses and serialises the openme client configuration format.
 *
 * Supports two input formats:
 * - **YAML** — the `config.yaml` file produced by `openme add` on the server.
 * - **JSON** — the QR code payload produced by `openme qr`.
 *
 * The YAML parser is a lightweight, line-based reader that handles the specific subset of YAML
 * produced by `openme add`. It auto-detects indent width (2-space / 4-space) and works with
 * both go-yaml v2 and go-yaml v3 output.
 *
 * ### Expected YAML schema
 * ```yaml
 * profiles:
 *   <name>:
 *     server_host: "..."
 *     server_udp_port: 54154
 *     server_pubkey: "..."
 *     private_key: "..."
 *     public_key: "..."
 *     post_knock: "..."
 * ```
 *
 * ### QR JSON schema
 * ```json
 * {
 *   "profile": "my-server",
 *   "host": "203.0.113.1",
 *   "udp_port": 54154,
 *   "server_pubkey": "<base64>",
 *   "client_privkey": "<base64>",
 *   "client_pubkey": "<base64>"
 * }
 * ```
 *
 * For the full config format reference see the
 * [Client Configuration](https://openme.merlos.org/docs/configuration/client.html) docs.
 */
object ClientConfigParser {

    // ─── YAML ───────────────────────────────────────────────────────────────────

    /**
     * Parses a `config.yaml` YAML string into a map of [Profile] values keyed by name.
     *
     * The parser auto-detects indent width and handles both 2-space (go-yaml v2) and
     * 4-space (go-yaml v3) indentation. Malformed or incomplete profiles are silently
     * skipped so a partially-valid config still loads the good entries.
     *
     * @param yaml Full contents of a `config.yaml` file.
     * @return Map of profile name → [Profile]. Empty if no valid profiles are found.
     * @throws ParserError.NoProfilesFound if the YAML contains no `profiles:` section
     *   or every profile fails validation.
     */
    @Throws(ParserError::class)
    fun parseYaml(yaml: String): Map<String, Profile> {
        val profiles = mutableMapOf<String, Profile>()
        val rawLines = yaml.lines()

        var inProfiles = false
        var currentName: String? = null
        var currentDict = mutableMapOf<String, String>()
        var profileIndent: Int? = null
        var kvIndent: Int? = null

        fun leadingSpaces(s: String): Int {
            var count = 0
            for (ch in s) {
                when (ch) {
                    ' ' -> count++
                    '\t' -> count += 4
                    else -> break
                }
            }
            return count
        }

        fun parseValue(raw: String): String {
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) return ""
            val quoteChars = setOf('"', '\'')
            if (trimmed.first() in quoteChars) {
                val openQuote = trimmed.first()
                val rest = trimmed.drop(1)
                val closeIdx = rest.indexOf(openQuote)
                if (closeIdx >= 0) return rest.substring(0, closeIdx)
            }
            // Unquoted: strip inline comment
            val commentIdx = trimmed.indexOf(" #")
            return if (commentIdx >= 0) trimmed.substring(0, commentIdx).trim() else trimmed
        }

        fun commitProfile(name: String, dict: Map<String, String>) {
            val host = dict["server_host"] ?: return
            val port = dict["server_udp_port"]?.toIntOrNull() ?: 54154
            val serverPub = dict["server_pubkey"]?.takeIf { it.isNotBlank() } ?: return
            val privKey = dict["private_key"]?.takeIf { it.isNotBlank() } ?: return
            val pubKey = dict["public_key"] ?: ""
            val postKnock = dict["post_knock"] ?: ""
            profiles[name] = Profile(
                name = name,
                serverHost = host,
                serverUDPPort = port,
                serverPubKey = serverPub,
                privateKey = privKey,
                publicKey = pubKey,
                postKnock = postKnock,
            )
        }

        for (rawLine in rawLines) {
            // Skip blank, comment, and document-marker lines
            val stripped = rawLine.trimEnd()
            if (stripped.isBlank()) continue
            val trimmed = stripped.trim()
            if (trimmed.startsWith("#") || trimmed == "---" || trimmed == "..." || trimmed.startsWith("%")) continue

            val indent = leadingSpaces(stripped)

            // Looking for the root `profiles:` key (must be at indent 0)
            if (!inProfiles) {
                if (indent == 0 && trimmed == "profiles:") {
                    inProfiles = true
                }
                continue
            }

            // We are inside the profiles: block
            val colonIdx = trimmed.indexOf(':')
            if (colonIdx < 0) continue
            val key = trimmed.substring(0, colonIdx).trim()
            val valueRaw = trimmed.substring(colonIdx + 1)

            when {
                // Profile-name line — deduce profileIndent on first encounter
                profileIndent == null || indent == profileIndent -> {
                    // Save previous profile
                    currentName?.let { commitProfile(it, currentDict) }
                    profileIndent = indent
                    currentName = key
                    currentDict = mutableMapOf()
                    kvIndent = null
                }
                // Key-value line — deduce kvIndent on first encounter
                kvIndent == null || indent == kvIndent -> {
                    kvIndent = indent
                    currentDict[key] = parseValue(valueRaw)
                }
                // Deeper nesting or unexpected indent — ignore
            }
        }

        currentName?.let { commitProfile(it, currentDict) }

        if (profiles.isEmpty()) throw ParserError.NoProfilesFound
        return profiles
    }

    /**
     * Serialises a map of profiles to a `config.yaml` string compatible with
     * the openme CLI (go-yaml v3, 4-space indent).
     *
     * @param profiles Map of profile name → [Profile].
     * @return YAML string ready to be written to `config.yaml`.
     */
    fun toYaml(profiles: Map<String, Profile>): String {
        val sb = StringBuilder("profiles:\n")
        for ((_, p) in profiles) {
            sb.append("    ${p.name}:\n")
            sb.append("        server_host: \"${p.serverHost}\"\n")
            sb.append("        server_udp_port: ${p.serverUDPPort}\n")
            sb.append("        server_pubkey: \"${p.serverPubKey}\"\n")
            sb.append("        private_key: \"${p.privateKey}\"\n")
            sb.append("        public_key: \"${p.publicKey}\"\n")
            sb.append("        post_knock: \"${p.postKnock}\"\n")
        }
        return sb.toString()
    }

    // ─── QR JSON ────────────────────────────────────────────────────────────────

    /**
     * Parses the JSON payload from an openme QR code into a [Profile].
     *
     * QR codes are generated by `openme qr <profile-name>` on the server.
     * They encode a JSON object — **not** the YAML config format.
     *
     * Expected JSON fields:
     * - `"profile"` — profile name
     * - `"host"` — server hostname or IP
     * - `"udp_port"` — server UDP port
     * - `"server_pubkey"` — Base64-encoded server Curve25519 public key
     * - `"client_privkey"` — Base64-encoded client Ed25519 private key
     * - `"client_pubkey"` — Base64-encoded client Ed25519 public key
     *
     * @param json Raw JSON string decoded from a QR code.
     * @return A fully populated [Profile].
     * @throws ParserError.InvalidQRPayload if required fields are missing or the
     *   string is not valid JSON.
     */
    @Throws(ParserError::class)
    fun parseQRPayload(json: String): Profile {
        return try {
            val obj = JSONObject(json)
            val name = obj.optString("profile").takeIf { it.isNotBlank() }
                ?: throw ParserError.InvalidQRPayload
            val host = obj.optString("host").takeIf { it.isNotBlank() }
                ?: throw ParserError.InvalidQRPayload
            val port = obj.optInt("udp_port", 54154)
            val serverPub = obj.optString("server_pubkey").takeIf { it.isNotBlank() }
                ?: throw ParserError.InvalidQRPayload
            val privKey = obj.optString("client_privkey").takeIf { it.isNotBlank() } ?: ""
            val pubKey = obj.optString("client_pubkey") ?: ""
            Profile(
                name = name,
                serverHost = host,
                serverUDPPort = port,
                serverPubKey = serverPub,
                privateKey = privKey,
                publicKey = pubKey,
            )
        } catch (e: ParserError) {
            throw e
        } catch (e: Exception) {
            throw ParserError.InvalidQRPayload
        }
    }
}

/**
 * Errors thrown by [ClientConfigParser].
 */
sealed class ParserError : Exception() {
    /** The YAML contains no `profiles:` section or every profile fails validation. */
    object NoProfilesFound : ParserError() {
        override val message = "No valid profiles found in the configuration."
        private fun readResolve(): Any = NoProfilesFound
    }

    /** The QR JSON payload is missing required fields or is not valid JSON. */
    object InvalidQRPayload : ParserError() {
        override val message = "Invalid QR payload: required fields are missing or the JSON is malformed."
        private fun readResolve(): Any = InvalidQRPayload
    }
}
