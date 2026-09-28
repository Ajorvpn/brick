// Brick VPN — native Android harness (Phase 3, Gate A).
//
// This project is deliberately STANDALONE: it has no Flutter plugin, no
// includeBuild of the Flutter SDK, and no dependency on apps/mobile. Gate A
// must prove the native VpnService lifecycle in isolation, so any Flutter
// coupling here would defeat the purpose of the gate.
pluginManagement {
    repositories {
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
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "brickvpn-native-harness"
include(":app")
