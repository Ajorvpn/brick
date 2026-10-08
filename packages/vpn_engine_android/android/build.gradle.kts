// P3-T11 — Flutter Android platform plugin library module.
//
// Proven recipe (measured, 5 attempts; full log in PROJECT_STATE.md section 5):
// AGP 9 publishes NO plugin-marker artifact for `com.android.library`, so a
// plain `plugins { id("com.android.library") version "9.1.0" }` fails with
// "could not resolve plugin artifact
//  'com.android.library:com.android.library.gradle.plugin:9.1.0'".
// The fix is the `resolutionStrategy` in settings.gradle.kts mapping the plugin
// id onto AGP's real coordinates.
//
// Kotlin: AGP 9.x provides built-in Kotlin, so `org.jetbrains.kotlin.android`
// is deliberately NOT applied and the migrated Gate A sources compile as-is.
// The stock `flutter create --template=plugin` template does NOT build
// standalone against our AGP 9.1.0 pin — it relies on the consuming app's
// settings file to supply AGP, and its `java.srcDirs(...)` call is
// deprecated-as-error under 9.1.0. AGP 9 already includes `src/main/kotlin`
// and `src/test/kotlin` by default, so no srcDirs override is needed.
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
    }
}

plugins {
    // Declared here (not via `apply(plugin = ...)`) because Kotlin DSL
    // type-safe accessors — `implementation(...)`, `testImplementation(...)`,
    // `android { }` — are only generated for plugins applied via `plugins {}`.
    id("com.android.library") version "9.1.0"
}

group = "dev.brickvpn.vpn_engine_android"
version = "1.0-SNAPSHOT"

android {
    // Namespace stays `dev.brickvpn.harness` so every migrated Kotlin file's
    // existing `package` declaration remains correct — renaming packages would
    // mean touching code, which this task's zero-behavior-change rule forbids.
    namespace = "dev.brickvpn.harness"
    compileSdk = 36

    defaultConfig {
        // P3-T11 (human-confirmed): raised from 21 to 24. Flutter's
        // platform-plugin mechanism has a hard floor of 24, so 21 is not a
        // viable alternative for AC #3. Recorded as an override of P3-T2's
        // minSdk-21 decision in PROJECT_STATE.md. The API-29 test device does
        // not exercise this boundary, so the test suites cannot detect it.
        minSdk = 24

        // P3-T11: AGP defaults a library's instrumentation test app to
        // `<namespace>.test` (= `dev.brickvpn.harness.test`). The Gate A
        // instrumented tests drive a real VpnService, so the test app needs the
        // `ACTIVATE_VPN` appop granted — and more importantly the human's
        // established device workflow is bound to `dev.brickvpn.native.harness`
        // (adb install, `appops set … ACTIVATE_VPN allow`, run scripts).
        //
        // Pinning `testApplicationId` to that same id keeps every existing
        // command working unchanged. Without this the suite fails 10/13 with
        // "establish() returned null", because the grant above does not apply
        // to `dev.brickvpn.harness.test`.
        testApplicationId = "dev.brickvpn.native.harness"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Same dependency set as the former Gate A application module, minus what
    // only an application needs.
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

    // P3-T3 / P3-T7 Part 2: the sing-box v1.10.7 libbox AAR (built with
    // `-tags with_utls`). Gitignored; a fresh clone MUST run
    // scripts/build_libbox_aar.sh before this module compiles. No graceful
    // fallback on purpose — a missing AAR must fail loudly at build time.
    implementation(files("libs/libbox.aar"))

    // P3-T11: Flutter embedding, `compileOnly` (never `implementation`) so the
    // plugin class compiles without forcing a Flutter runtime onto a native
    // consumer. This replaced excluding the file from the source set, which is
    // not expressible in the AGP 9 Kotlin DSL. Engine revision is pinned to
    // Flutter 3.47.4's (flutter doctor: "Engine revision 06a2e2a110").
    compileOnly("io.flutter:flutter_embedding_debug:1.0.0-06a2e2a110089dff50fe635cffd2a61e1b24fbcd")

    // Host-JVM unit tests — JUnit 4, deliberately. The stock Flutter template
    // ships `useJUnitPlatform()` + JUnit 5; adopting that would make Gradle
    // discover ZERO JUnit-4 tests and still report BUILD SUCCESSFUL, which is a
    // silent false green. The suite must keep running all 36 tests.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")

    // P3-T6/P3-T7: instrumented tests, re-run on the real device.
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}