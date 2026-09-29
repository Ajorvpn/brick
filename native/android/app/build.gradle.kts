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
    // Intentionally minimal. No Flutter, no Pigeon at Gate A.
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")

    // P3-T3: the sing-box v1.10.7 libbox AAR, built reproducibly by
    // scripts/build_libbox_aar.sh. It is gitignored, so a fresh clone MUST run
    // that script before this module will compile. No graceful fallback is
    // provided on purpose: a missing AAR should fail loudly at build time
    // rather than silently ship a harness that reports a fake version.
    implementation(files("libs/libbox.aar"))

    // P3-T5: `VpnStateMachine` is pure Kotlin (no Android framework imports) and
    // emits its state through a `StateFlow`, so coroutines are a genuine
    // `implementation` dependency of the module, not a test-only one.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

    // P3-T5: host-JVM unit tests. `testDebugUnitTest` needs no emulator and no
    // Robolectric, which is what lets the state machine be proven in isolation
    // (the native counterpart of how MockVpnEngine was proven in P1-T5).
    // NOTE: before this task `app/src/test` did not exist and NO test
    // dependencies were declared, so `testDebugUnitTest` reported NO-SOURCE
    // and "passed" without executing a single test.
    testImplementation("junit:junit:4.13.2")
    // Virtual time: the 5000 ms stop watchdog is exercised deterministically
    // via `advanceTimeBy` instead of actually sleeping five seconds.
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}
