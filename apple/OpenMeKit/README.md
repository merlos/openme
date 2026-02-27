# OpenMeKit

**OpenMeKit** is the shared Swift library that implements the [openme](../../README.md) Single Packet Authentication (SPA) protocol for Apple platforms. It is consumed by the iOS app, the macOS menu-bar app, and the watchOS companion — so all cryptographic and networking logic lives in one place, tested once.

---

## What it does

A single knock is a **165-byte UDP datagram** that is computationally indistinguishable from random noise to anyone without the server's Curve25519 private key:

```
 0       1      33      45                   101                   165
 ┌───────┬──────┬───────┬─────────────────────┬─────────────────────┐
 │version│ephem │ nonce │     ciphertext      │    ed25519_sig      │
 │ 1 B   │32 B  │12 B   │     56 B            │     64 B            │
 └───────┴──────┴───────┴─────────────────────┴─────────────────────┘
 ◄─────────────── signed portion (101 B) ──────────────────────────►
```

`KnockService` carries out the full client-side sequence on every knock:

1. Generate an ephemeral Curve25519 key pair.
2. Derive a shared secret with the server's static Curve25519 public key (ECDH).
3. Expand the secret with HKDF-SHA256 into a ChaCha20-Poly1305 key.
4. Encrypt the payload (target ports, timestamp, 128-bit random nonce).
5. Sign the first 101 bytes with the client's Ed25519 private key.
6. Dispatch the datagram over UDP — no response expected.

`KnockManager` wraps `KnockService` for SwiftUI apps, adding profile resolution, `@Published` state, and **continuous knock** mode (re-sends every 20 s so firewall rules stay alive during long sessions).

---

## Supported platforms

| Platform | Minimum OS |
|----------|-----------|
| macOS    | 14 (Sonoma) |
| iOS      | 17 |
| watchOS  | via openme-watch (uses WatchConnectivity) |

---

## Adding OpenMeKit to your Swift project

### Swift Package Manager (local path)

```swift
// Package.swift
dependencies: [
    .package(path: "../OpenMeKit"),   // adjust relative path as needed
],
targets: [
    .target(name: "MyApp", dependencies: ["OpenMeKit"]),
]
```

### Xcode

**File → Add Package Dependencies…** → choose the local `apple/OpenMeKit` folder, or add the repository URL and select a version tag once published to GitHub.

---

## Quick-start

```swift
import OpenMeKit

// 1. Load profiles from ~/.openme/config.yaml
let store = ProfileStore()
try store.load()

// 2. Create the manager (must be @MainActor / on main thread)
let manager = KnockManager()
manager.store = store

// 3. Single knock
manager.knock(profile: "home") { result in
    switch result {
    case .success:          print("Knock sent")
    case .failure(let msg): print("Error: \(msg)")
    }
}

// 4. Keep rules alive for a long session
manager.startContinuousKnock(profile: "home")
// … later …
manager.stopContinuousKnock()
```

---

## Documentation

| Resource | URL |
|----------|-----|
| **OpenMeKit API reference** (DocC, HTML) | [openme.merlos.org/docs/openmekit](https://openme.merlos.org/docs/openmekit) |
| Protocol specification | [openme.merlos.org/docs/protocol](https://openme.merlos.org/docs/protocol) |
| Cryptography | [openme.merlos.org/docs/protocol/cryptography.html](https://openme.merlos.org/docs/protocol/cryptography.html) |
| Packet format | [openme.merlos.org/docs/protocol/packet-format.html](https://openme.merlos.org/docs/protocol/packet-format.html) |
| Security model | [openme.merlos.org/docs/security](https://openme.merlos.org/docs/security) |

---

## Building the API reference locally

Requires Xcode 15 + or the Swift toolchain (`swift` in `$PATH`).

```bash
cd apple/OpenMeKit
swift package \
  --allow-writing-to-directory ./openmekit-docs \
  generate-documentation \
  --target OpenMeKit \
  --output-path ./openmekit-docs \
  --transform-for-static-hosting \
  --hosting-base-path /docs/openmekit
open ./openmekit-docs/index.html
```

The `--transform-for-static-hosting` flag produces self-contained HTML that works without a DocC server, matching the GitHub Pages deployment.

---

## License

MIT — see [LICENSE](../../LICENSE).
