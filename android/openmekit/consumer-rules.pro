# Consumer ProGuard rules for openmekit
# These rules are applied to any app that depends on this library.

# Keep BouncyCastle — required at runtime for Ed25519 signing and X25519 ECDH
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Keep DataStore generated classes
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { *; }
