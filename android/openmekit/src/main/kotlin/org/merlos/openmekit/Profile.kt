package org.merlos.openmekit

/**
 * A single named client profile holding everything needed to knock an openme server.
 *
 * Profiles are persisted in [ProfileStore] and are produced by `openme add` on the server,
 * then imported via YAML paste or QR code. Each profile contains the server connection details
 * and the client's Ed25519 signing key pair.
 *
 * ### Key handling
 * [privateKey] contains a raw Ed25519 seed encoded in Base64 and **must be treated as a secret**.
 * [ProfileStore] writes profiles to encrypted SharedPreferences and never logs key material.
 *
 * @property name Unique profile identifier — used as the YAML map key and displayed in the UI.
 * @property serverHost Hostname or IP address of the openme server.
 * @property serverUDPPort UDP port the server listens on for SPA knock packets (default `7777`).
 * @property serverPubKey Base64-encoded Curve25519 (X25519) public key of the server.
 *   Used for the ECDH key agreement step of the knock protocol.
 * @property privateKey Base64-encoded Ed25519 private key (32-byte seed, or 64-byte seed + public key).
 * @property publicKey Base64-encoded Ed25519 public key corresponding to [privateKey].
 * @property postKnock Optional shell command executed after a successful knock (Android only).
 *   Leave empty to skip.
 */
data class Profile(
    val name: String,
    val serverHost: String = "",
    val serverUDPPort: Int = 7777,
    val serverPubKey: String = "",
    val privateKey: String = "",
    val publicKey: String = "",
    val postKnock: String = "",
) {
    /** Stable identifier — equals [name]. */
    val id: String get() = name
}

/**
 * Lightweight profile summary used in list views.
 *
 * [ProfileEntry] deliberately omits key material so it can be safely passed to
 * UI layers that have no need for the Ed25519 private key. Full details are
 * available via [ProfileStore.profile].
 *
 * @property name Profile name as stored in the YAML config.
 * @property serverHost Hostname or IP address of the openme server.
 * @property serverUDPPort UDP port the server listens on for knock packets.
 */
data class ProfileEntry(
    val name: String,
    val serverHost: String,
    val serverUDPPort: Int,
) {
    /** Stable identifier — equals [name]. */
    val id: String get() = name
}
