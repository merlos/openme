# openme app ProGuard rules

# Keep BouncyCastle — required at runtime for Ed25519 + X25519
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Keep ZXing
-keep class com.google.zxing.** { *; }
-keep class com.journeyapps.** { *; }

# Keep Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
