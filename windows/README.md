# openme — Windows

> System-tray SPA client for Windows x64 and arm64 · **Status: Active**

## Overview

Two components live in this directory:

| Directory | Type | Description |
|---|---|---|
| `OpenMeKit/` | .NET class library | Protocol, profile storage, profile parsing |
| `openme-windows/` | WPF application | System-tray / notification-area app |
| `OpenMeKit.Tests/` | xUnit test project | Unit tests for the library |

---

## Requirements

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) (includes WPF runtimes)
- Windows 10 version 1903+ or Windows 11
- Architecture: `x64` or `arm64`

---

## Quick Start

```powershell
# From the windows/ directory
cd windows

# Restore dependencies
dotnet restore

# Run tests
dotnet test

# Run the app (requires .NET 8 Windows runtime)
dotnet run --project openme-windows

# Publish self-contained for x64
dotnet publish openme-windows -c Release -r win-x64 --self-contained

# Publish self-contained for arm64 (Surface Pro X, Snapdragon laptops)
dotnet publish openme-windows -c Release -r win-arm64 --self-contained
```

Published output lands in `openme-windows/bin/Release/net8.0-windows/<rid>/publish/`.

---

## OpenMeKit Library

`OpenMeKit` is a platform-agnostic .NET standard library (targets `net8.0`) with no
Windows-specific dependencies. It can be used in any .NET project.

### Key types

| Type | Description |
|---|---|
| `Profile` | Profile data (server host/port/pubkey, client keys, post-knock command) |
| `ProfileEntry` | Lightweight summary without key material (safe for UI lists) |
| `KnockService` | Builds and sends the 165-byte SPA UDP packet |
| `KnockManager` | High-level async API; single and continuous-knock modes |
| `ProfileStore` | JSON-backed persistence in `%APPDATA%\openme\profiles.json` |
| `ClientConfigParser` | Parses YAML (`openme add` output) and QR-code JSON payloads |

### Usage example

```csharp
using OpenMeKit;

var store   = new ProfileStore();
var manager = new KnockManager(store);
manager.OnKnockCompleted += (_, outcome) =>
    Console.WriteLine(outcome.Result == KnockResult.Success
        ? $"Knocked {outcome.ProfileName}"
        : $"Failed: {outcome.ErrorMessage}");

// Import a profile from YAML produced by `openme add`
store.ImportYaml(File.ReadAllText("config.yaml"));

// Single knock
await manager.KnockAsync("home");

// Keep the firewall rule alive during an extended session
manager.StartContinuousKnock("home");
// ... later
manager.StopContinuousKnock();
```

### Crypto stack

| Operation | .NET API |
|---|---|
| Ephemeral ECDH | `X25519KeyPairGenerator` (BouncyCastle) |
| HKDF-SHA256 | `System.Security.Cryptography.HKDF` (.NET 5+) |
| ChaCha20-Poly1305 | `System.Security.Cryptography.ChaCha20Poly1305` (.NET 6+) |
| Ed25519 signing | `Ed25519Signer` (BouncyCastle) |
| UDP dispatch | `System.Net.Sockets.UdpClient` |

---

## openme-windows App

The WPF application runs entirely in the Windows **notification area** (system tray):

- **Tray icon** — double-click to open Profile Manager
- **Context menu** — per-profile Knock and Continuous Knock actions, plus
  Manage Profiles, Import Profile, Website, Docs, Quit
- **Profile Manager window** — master–detail list editor with inline Knock
  and Continuous Knock buttons; private key is masked with a show/hide toggle
- **Import Profile window** — paste YAML or drag-and-drop a `.yaml` file;
  parse preview shows profile names before import
- **Balloon notifications** — knock result (success / failure) shown via OS toast

### Project structure

```
openme-windows/
  App.xaml / App.xaml.cs         — entry point, tray icon, context menu
  app.manifest                   — DPI awareness, Windows 10/11 compat
  Themes/Generic.xaml            — shared Fluent-inspired styles
  ViewModels/
    ProfileManagerViewModel.cs
    ImportProfileViewModel.cs
  Views/
    ProfileManagerWindow.xaml    — master-detail editor
    ImportProfileWindow.xaml     — YAML / file drop importer
  Resources/
    openme.ico                   — (add your own; optional but recommended)
```

### Adding a tray icon

Place a 256×256 (multi-size) `.ico` file at `openme-windows/Resources/openme.ico`.
The `.csproj` includes it as a `Resource`; the app loads it automatically.
If the file is absent the system default application icon is used.

---

## Running Tests

```powershell
dotnet test OpenMeKit.Tests
```

Tests cover:
- Packet is exactly 165 bytes with correct version byte
- Two consecutive packets differ in their ephemeral key
- Invalid / short keys throw `KnockException` with the correct `Kind`
- YAML round-trip: parse → serialise → re-parse produces identical profiles
- QR payload parsing and missing-field error handling

---

## Architecture Compatibility

| Target | Runtime ID | Notes |
|-------|------------|-------|
| Intel/AMD 64-bit | `win-x64` | Windows 10/11, Server 2019+ |
| ARM 64-bit | `win-arm64` | Windows 11 on Snapdragon / Surface Pro X |

WPF arm64 support was added in .NET 6 and is fully supported on .NET 8.

---

## See Also

- [openme CLI](../cli/README.md) — Go server and command-line client
- [iOS / macOS apps](../apple/) — SwiftUI clients
- [Android app](../android/README.md) — Jetpack Compose client


_Instructions will be added when development begins._
