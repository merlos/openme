# openme — macOS

> Native macOS menu bar client — knock your server from the menu bar.

## Stack

- **Language:** Swift 5.10
- **UI:** SwiftUI (menu bar app, no Dock icon)
- **Crypto:** CryptoKit (Curve25519 ECDH, ChaCha20-Poly1305, Ed25519, HKDF-SHA256)
- **Networking:** Network.framework (UDP via `NWConnection`)
- **Distribution:** Direct DMG / Mac App Store
- **Minimum macOS:** 13.0 (Ventura)
- **App Sandbox:** Yes — no Go binary, no subprocesses

## Features

- Menu bar icon with per-profile knock actions
- Continuous knock mode (re-knocks every 20 s to keep the port open)
- Native Swift SPA knock — no bundled CLI, fully sandboxed
- Profile manager sheet — add, delete and inspect profiles
- Import profile from YAML — paste the block printed by `openme add` or drag a `.yaml` file
- macOS Shortcuts support (`openme connect <profile>` via App Intents)
- Config stored in the sandbox container (`~/Library/Application Support/openme/`)

## Development Setup

### Prerequisites

- Xcode 15+
- macOS 13+

No Go toolchain is needed — the knock protocol is implemented natively in Swift.

### Building

1. Open `openme-client.xcodeproj` in Xcode
2. Select the **openme-client** scheme
3. Press **⌘R**

The app appears as a lock-shield icon in the menu bar.

### Project structure

| Path | Description |
|------|-------------|
| `openme_clientApp.swift` | `@main` App with `MenuBarExtra` + `Window` scenes |
| `Networking/KnockService.swift` | Native SPA knock — packet build + UDP send |
| `KnockManager.swift` | ObservableObject managing single + continuous knocks |
| `Models/ClientConfig.swift` | Profile, ProfileEntry, YAML parser/serializer |
| `Models/ProfileStore.swift` | ObservableObject that loads/saves config |
| `Views/MenuBarMenuView.swift` | The menu shown when clicking the status item |
| `Views/ProfileManagerView.swift` | Profile list + detail editor |
| `Views/ImportProfileView.swift` | Paste/drag YAML to import profiles |
| `Intents/KnockIntent.swift` | Shortcuts / App Intents support |

### Running

Select the target in Xcode and press **⌘R**. The app appears as a lock icon in the menu bar. The CLI binary must be present in the bundle resources; run the build step above first.
