# openmekit ProGuard rules

# Keep BouncyCastle — required at runtime for Ed25519 signing and X25519 ECDH
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Keep DataStore
-keep class androidx.datastore.** { *; }
