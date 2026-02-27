# openme Android

Android app + client library for the [openme](https://github.com/merlos/openme) Single Packet Authentication (SPA) protocol.

## Project structure

```
android/
├── openmekit/          ← Kotlin library — protocol, crypto, profile storage
│   └── src/main/kotlin/org/merlos/openmekit/
│       ├── Profile.kt              data classes
│       ├── ClientConfigParser.kt   YAML + QR JSON import
│       ├── KnockService.kt         SPA packet builder + UDP sender
│       ├── KnockManager.kt         coroutine-friendly façade
│       └── ProfileStore.kt         DataStore-backed persistence
└── app/                ← Android Jetpack Compose app (Material 3)
    └── src/main/kotlin/org/merlos/openme/
        ├── MainActivity.kt
        └── ui/
            ├── ProfileViewModel.kt
            └── screens/
                ├── ProfileListScreen.kt    list + swipe-to-knock / swipe-to-delete
                ├── ProfileDetailScreen.kt  edit fields + Knock button
                └── ImportProfileScreen.kt  YAML paste + QR scan tabs
```

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Android Studio | Ladybug (2024.2) |
| JDK | 17 |
| Gradle | 8.9 (wrapper generated below) |

## Setup

```bash
# 1. Change to the android directory
cd android

# 2. Initialise the Gradle wrapper (requires Gradle installed globally)
gradle wrapper --gradle-version 8.9

# 3. Build debug APK
./gradlew app:assembleDebug

# 4. Install on connected device / emulator
./gradlew app:installDebug
```

## Run tests

```bash
./gradlew openmekit:test
```

## Generate API documentation

The library uses [Dokka](https://kotlinlang.org/docs/dokka-introduction.html) to produce KDoc HTML output:

```bash
./gradlew openmekit:dokkaHtml
# Output: ../docs/android-sdk/openmekit/
```

The generated docs are consumed by the Quarto documentation site at `docs/android-sdk/index.qmd`.

## Minimum SDK

Android 10 (API 29). Ed25519 and X25519 use BouncyCastle (`bcprov-jdk15to18`) to support all
API 29+ devices. ChaCha20-Poly1305 and HKDF-SHA256 use the standard `javax.crypto` APIs
available from API 29.

## See also

- [Android SDK documentation](../docs/android-sdk/index.qmd)
- [Protocol specification](../docs/protocol/index.qmd)
## QR Onboarding

```
Server                              Phone
  │  sudo openme add alice --qr        │
  │──────── scan QR ───────────────────>│ app imports profile
  │                                     │ keys stored in Keystore
  │<──── ready to knock ───────────────>│
```

## Development Setup

_Instructions will be added when development begins._
