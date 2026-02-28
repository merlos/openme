# openme Android

[![Android CI](https://github.com/merlos/openme/actions/workflows/android.yml/badge.svg)](https://github.com/merlos/openme/actions/workflows/android.yml)

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

## Build a release APK locally

### 1. Create a signing keystore (first time only)

```bash
keytool -genkeypair -v \
  -keystore app/release.keystore \
  -alias openme \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

Keep `release.keystore` **out of version control** — it is already listed in `.gitignore`.

### 2. Set signing credentials as environment variables

```bash
export KEYSTORE_PATH="$PWD/app/release.keystore"
export KEYSTORE_PASSWORD="your-store-password"
export KEY_ALIAS="openme"
export KEY_PASSWORD="your-key-password"
```

Or create a local `keystore.properties` file in `android/` (also `.gitignore`d):

```properties
storeFile=release.keystore
storePassword=your-store-password
keyAlias=openme
keyPassword=your-key-password
```

### 3. Build the signed release APK

```bash
cd android
./gradlew :app:assembleRelease \
  -Pandroid.injected.signing.store.file="$KEYSTORE_PATH" \
  -Pandroid.injected.signing.store.password="$KEYSTORE_PASSWORD" \
  -Pandroid.injected.signing.key.alias="$KEY_ALIAS" \
  -Pandroid.injected.signing.key.password="$KEY_PASSWORD"
```

Output: `app/build/outputs/apk/release/app-release.apk`

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

## CI — GitHub Actions setup

The workflow at [`.github/workflows/android.yml`](../.github/workflows/android.yml) runs on every push or PR that touches `android/**`.

| Job | What it does |
|-----|--------------|
| `test` | Runs openmekit JVM unit tests |
| `build` | Assembles the release AAR (`openmekit-release.aar`) |
| `apk` | Builds `openme-debug.apk`; builds signed `openme-release.apk` when signing secrets are present |

### Enabling signed release APK builds

Add the following four **repository secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|--------|-------|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded `.keystore` file (see below) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password (`storePassword`) |
| `ANDROID_KEY_ALIAS` | Key alias (e.g. `openme`) |
| `ANDROID_KEY_PASSWORD` | Key password (`keyPassword`) |

To encode the keystore:

```bash
# macOS — copies the base64 string to the clipboard
base64 -i app/release.keystore | pbcopy

# Linux
base64 app/release.keystore
```

Paste the output as the value of `ANDROID_KEYSTORE_BASE64`.

When `ANDROID_KEYSTORE_BASE64` is absent the release signing steps are skipped and only the debug APK is uploaded.

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
