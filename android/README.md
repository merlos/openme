# openme — Android App

> Android client · **Status: Planned**

## Planned Stack

- **Language:** Kotlin
- **UI:** Jetpack Compose
- **Min SDK:** Android 10 (API 29)
- **Distribution:** Google Play / F-Droid / APK

## Planned Features

- Profile manager
- Home screen widget and shortcut for one-tap knock
- QR code scanner for server config import
- On-device Ed25519 key generation (private key stays on device)
- Biometric authentication before knock
- Tasker / Automation integration

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
