plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.dokka)
}

android {
    namespace = "org.merlos.openmekit"
    compileSdk = 35

    defaultConfig {
        minSdk = 29

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // BouncyCastle — provides Ed25519 signing + X25519 ECDH for API 29-32
    // (API 33+ has native Ed25519 but we support down to 29)
    api(libs.bouncycastle.provider)

    // DataStore Preferences — profile persistence
    api(libs.androidx.datastore.preferences)

    // Core
    implementation(libs.androidx.core.ktx)

    // JSON deserialization for QR payloads
    api(libs.kotlinx.serialization.json)

    // Tests
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
}

// Dokka HTML output → docs/android-sdk/openmekit/
tasks.dokkaHtml {
    outputDirectory.set(rootProject.file("../docs/android-sdk/openmekit"))
    moduleName.set("OpenMeKit Android")
    moduleVersion.set("1.0.0")
    dokkaSourceSets {
        named("main") {
            displayName.set("OpenMeKit")
            includes.from("Module.md")
        }
    }
}
