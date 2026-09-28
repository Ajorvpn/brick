plugins {
    id("com.android.application")
    // NOTE: AGP 9.0+ provides built-in Kotlin support. Applying
    // `org.jetbrains.kotlin.android` here is now an ERROR
    // ("plugin is no longer required ... since AGP 9.0"), so it is
    // deliberately absent. See https://kotl.in/gradle/agp-built-in-kotlin
}

android {
    // Application ID for the Gate A native harness. Deliberately distinct
    // from the Flutter app's ID so both can be installed side by side.
    // NOTE: the *namespace* (Java package) cannot contain the segment
    // "native" — `native` is a Java keyword, and AGP rejects the build with
    // "Namespace ... is not a valid Java package name as 'native' is a
    // Java keyword". The applicationId below is a plain unique string and is
    // unaffected, so the app's identity is exactly as specified.
    namespace = "dev.brickvpn.harness"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.brickvpn.native.harness"
        // P3-T2 decision: minSdk 21 per the human's explicit direction.
        // NOTE: `packages/config_parser` and Flutter itself do not support 21;
        // see native/android/README.md "Known constraints".
        minSdk = 21
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0-gateA"
    }

    // Pinned by P3-T1 (AI_ROLES/TOOLCHAIN_VERSIONS.md): NDK r26b.
    ndkVersion = "26.1.10909125"

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

dependencies {
    // Intentionally minimal. No Flutter, no libbox, no Pigeon at Gate A.
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
}
