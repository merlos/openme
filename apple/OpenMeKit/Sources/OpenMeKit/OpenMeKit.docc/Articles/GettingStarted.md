# Getting Started with OpenMeKit

Integrate OpenMeKit into your Apple-platform app and perform your first knock in four steps.

## Overview

OpenMeKit is distributed as a local Swift Package. Once added to your Xcode
project it exposes a high-level ``KnockManager`` for typical UI use and a
lower-level ``KnockService`` for programmatic or extension use.

> **Prerequisites** — You need a running openme server and a client config
> file (`config.yaml`) produced by `openme add`. See the
> [Client Setup](https://openme.merlos.org/docs/getting-started/client-setup.html)
> guide and [Adding Clients](https://openme.merlos.org/docs/getting-started/adding-clients.html)
> for setup instructions.

## Step 1 — Add the Package

In Xcode open **File › Add Package Dependencies…** and choose the local
`apple/OpenMeKit` folder, or add it in `Package.swift`:

```swift
.package(path: "../OpenMeKit")
```

Then add `OpenMeKit` to the target's **Frameworks, Libraries, and Embedded Content**.

## Step 2 — Load Profiles

``ProfileStore`` reads `~/.openme/config.yaml` (macOS / watchOS) or the shared
App Group container (iOS + widget) automatically.

```swift
import OpenMeKit

@StateObject private var store = ProfileStore()
```

On iOS, both the app and its widget share the same file through the
`group.org.merlos.openme` App Group, so a profile saved in the app is
immediately available to the widget without any extra work.

## Step 3 — Send a Knock

### Using KnockManager (recommended for UI)

```swift
import OpenMeKit

@StateObject private var manager = KnockManager()

// in your view's onAppear / init
manager.store = store

// Single knock
manager.knock(profile: "home") { result in
    switch result {
    case .success:
        print("Knocked successfully")
    case .failure(let message):
        print("Knock failed: \(message)")
    }
}

// Continuous knock (re-sends every 20 s while connection is open)
manager.startContinuousKnock(profile: "home")
// ...later:
manager.stopContinuousKnock()
```

### Using KnockService directly (extensions, background tasks)

```swift
import OpenMeKit

KnockService.knock(
    serverHost: "myserver.example.com",
    serverPort: 54154,
    serverPubKeyBase64: "<base64 server pubkey>",
    clientPrivKeyBase64: "<base64 client privkey>"
) { result in
    switch result {
    case .success:
        print("Packet sent")
    case .failure(let error):
        print(error.localizedDescription)
    }
}
```

> **Note** — `KnockService.knock` is a fire-and-forget UDP send. A
> `.success` result means the packet was dispatched by the OS; it does not
> confirm the server received it or opened a firewall rule. Use
> `openme status` (TCP health check) to verify the rule is active.

## Step 4 — Manage Profiles

```swift
// Load the full Profile (including private key) for advanced use
if let p = store.profile(named: "home") {
    print(p.serverHost, p.serverUDPPort)
}

// Persist a new or edited profile
let p = Profile(
    name: "office",
    serverHost: "office.example.com",
    serverUDPPort: 54154,
    serverPubKey: "...",
    privateKey: "...",
    publicKey: "..."
)
try store.update(p)

// Remove a profile
try store.delete(name: "old-profile")
```

## Security considerations

Private keys are stored in `config.yaml` with `0600` file permissions.
On iOS watchOS the file lives inside the sandboxed App Group container.
OpenMeKit never logs or prints private key material.

For a full discussion of the threat model see
[Security](https://openme.merlos.org/docs/security/index.html) and
[Key Management](https://openme.merlos.org/docs/security/key-management.html).
