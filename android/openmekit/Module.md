# Module OpenMeKit Android

**OpenMeKit** is the official Android client library for the [openme](https://github.com/merlos/openme)
Single Packet Authentication (SPA) protocol.

## Overview

OpenMeKit handles the full knock lifecycle on Android:

1. **Profile management** — [ProfileStore] persists named profiles (server address, crypto keys)
   using Jetpack DataStore Preferences.
2. **Import** — [ClientConfigParser] parses both the `config.yaml` YAML format (produced by
   `openme add` on the server) and the JSON format embedded in QR codes (produced by `openme qr`).
3. **Knock** — [KnockService] builds and dispatches the 165-byte SPA UDP datagram using
   ephemeral X25519 ECDH + HKDF-SHA256 + ChaCha20-Poly1305 + Ed25519 signing.
4. **Manager** — [KnockManager] ties everything together for use from ViewModels.

## Protocol summary

Every knock is exactly **165 bytes** over UDP:

```
 0       1      33      45                   101                   165
 ┌───────┬──────┬───────┬─────────────────────┬─────────────────────┐
 │version│ephem │ nonce │     ciphertext      │    ed25519_sig      │
 │ 1 B   │32 B  │12 B   │     56 B            │     64 B            │
 └───────┴──────┴───────┴─────────────────────┴─────────────────────┘
 ◄─────────────── signed portion (101 B) ──────────────────────────►
```

See the [full protocol specification](https://openme.merlos.org/docs/protocol/packet-format.html).

## Quick start

```kotlin
// 1. Import a profile from YAML
val profiles = ClientConfigParser.parseYaml(yamlString)
val store = ProfileStore(context)
store.saveAll(profiles)

// 2. Knock from a ViewModel
viewModelScope.launch {
    val result = KnockManager(context).knock("my-server")
    when (result) {
        is KnockResult.Success -> showToast("Knocked!")
        is KnockResult.Failure -> showError(result.error.message)
    }
}
```

## Package

The library lives under the `org.merlos.openmekit` package.
