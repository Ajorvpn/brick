# Brick VPN — Native Android Harness (Phase 3, Gate A)

A **standalone** Android application project used to prove the native
`VpnService` + `libbox` lifecycle in isolation, before any Flutter is involved.

Gate A exists because the legacy prototype's failure was in native
bridge/lifecycle engineering, not in the core concept. Proving that layer alone
keeps native bugs from being confused with Dart/platform-channel bugs later
(`AI_ROLES/ARCHITECTURE.md`, Section 3.5).

## Flutter independence (this is the point)

This project has **no** Flutter plugin, no `includeBuild` of the Flutter SDK, and
no dependency on `apps/mobile`. If you find a `dev.flutter.*` plugin here, Gate A
isolation has been broken.

## Pinned versions

| Component | Version | Source |
|---|---|---|
| Android Gradle Plugin | `9.1.0` | matches `apps/mobile` |
| Gradle | `9.3.1` | matches `apps/mobile` |
| Kotlin | provided by AGP 9.x built-in support | see note below |
| `compileSdk` / `targetSdk` | `36` | Android SDK Platform 36 (pre-installed) |
| `minSdk` | `21` | P3-T2 decision — see Known constraints |
| NDK | `26.1.10909125` (r26b) | `AI_ROLES/TOOLCHAIN_VERSIONS.md` (P3-T1) |
| JDK | 17 | `JAVA_HOME` |

**AGP 9.x note:** applying `org.jetbrains.kotlin.android` is now an *error* —
AGP 9.0 has built-in Kotlin support. The plugin is deliberately absent from both
build files. See <https://kotl.in/gradle/agp-built-in-kotlin>.

## Prerequisites

- JDK 17 on `PATH` / `JAVA_HOME`
- Android SDK with **Platform 36** installed, discoverable via
  `ANDROID_HOME`/`ANDROID_SDK_ROOT` **or** a `local.properties` file
- NDK `26.1.10909125` if a native (`.so`) build is added later

`local.properties` is gitignored. Create it if needed:

```bash
echo "sdk.dir=$ANDROID_HOME" > local.properties
```

## Build (CLI only — no IDE required)

```bash
cd native/android
./gradlew assembleDebug
```

Output APK:

```
app/build/outputs/apk/debug/app-debug.apk
```

Windows: `gradlew.bat assembleDebug`.

## Run on a device or emulator

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n dev.brickvpn.native.harness/dev.brickvpn.harness.MainActivity
```

The app shows a single label: **"Brick VPN Native Harness"**. It requests **no
permissions**, performs no network I/O, and registers no VPN service.

## Known constraints

- **`minSdk 21` is inherited, not validated.** P3-T1 logged "min API 21" as an
  explicitly *unverified* item. Flutter's own floor is 24. This harness builds
  and installs at 21, but the eventual Flutter app cannot necessarily do so —
  revisit before Gate B.
- **`namespace` is `dev.brickvpn.harness`, not `dev.brickvpn.native.harness`.**
  `native` is a Java keyword, so AGP rejects it as a package segment. The
  *applicationId* — the app's real unique identity — **is**
  `dev.brickvpn.native.harness` as specified, and is unaffected.
- **No VPN, no libbox, no channels.** `BIND_VPN_SERVICE` is deliberately
  absent. The `VpnService` is a later Gate A task; platform channels are Gate B.
- **Nothing has run on a device yet.** This project has only been proven to
  *build*. `adb devices` is empty in the current environment.

## Not yet implemented here

- libbox AAR / Go 1.20 `gomobile` build (P3-T3)
- 16 KB page-alignment verification of a real `libbox.so` (P3-T3)
- `VpnService` lifecycle (P3-T6)
- Pigeon platform channels (Gate B)
