// P3-T11: the Flutter plugin's own Android library module.
//
// Two notes on why this file has more in it than the stock
// `flutter create --template=plugin` output (which is only
// `rootProject.name = ...`):
//
// 1. `pluginManagement.repositories` is required to build this module
//    STANDALONE (unit tests, and the AAR verification path). When the plugin
//    is consumed by apps/mobile, Flutter's `dev.flutter.flutter-plugin-loader`
//    supplies the build wiring and the *consuming app's* settings file wins —
//    so this block is inert in that path.
// 2. The `dev.flutter.flutter-plugin-loader` itself is deliberately NOT applied
//    here: it is the consuming app's responsibility, and adding it to a library
//    module that is also built standalone would tie unit-test builds to a
//    configured Flutter SDK.
// AGP 9 does not publish a plugin-marker artifact for `com.android.library`
// (or `com.android.application`), so an ordinary
// `plugins { id("com.android.library") version "9.1.0" }` lookup fails with:
//
//   could not resolve plugin artifact
//   'com.android.library:com.android.library.gradle.plugin:9.1.0'
//
// Mapping the plugin id onto AGP's real coordinates here makes the lookup
// resolve without any marker artifact. (Measured alternatives that do NOT work
// on AGP 9.1.0: `buildscript { classpath(...) }` + `apply(plugin = ...)` —
// which also breaks Kotlin DSL type-safe accessors, yielding 25
// "Unresolved reference 'implementation'" errors — and declaring the version in
// a `plugins {}` block in this settings file.)
//
// When the plugin is consumed by apps/mobile, Flutter's plugin loader supplies
// the build wiring and the consuming app's settings file takes precedence.
pluginManagement {
    repositories {
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
    resolutionStrategy {
        eachPlugin {
            if (requested.id.id == "com.android.library") {
                useModule("com.android.tools.build:gradle:${requested.version}")
            }
        }
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        google()
        mavenCentral()
    }
}

rootProject.name = "vpn_engine_android"