# vpn_engine_android — Flutter Android platform plugin (Phase 3, P3-T11)

Wraps the **proven Gate A** native VPN engine (`BrickVpnService` + `libbox`) as a
Flutter Android platform plugin. The Kotlin sources here were migrated
**verbatim** from the former standalone `native/android/` harness — they are
byte-identical, which is why the test counts still match the old baseline
exactly.

## What P3-T11 did and did not do

| Did | Did **not** |
|---|---|
| Repackaged the engine as a federated-plugin-shaped package | Define any platform channel |
| Migrated sources, manifests, resources, and all tests verbatim | Wire any Dart engine implementation (P3-T14) |
| Moved `build_libbox_aar.sh` here | Touch the provider override (P3-T15) |
| Added a structural, channel-free `VpnEngineAndroidPlugin` | Change any engine behaviour |

`VpnEngineAndroidPlugin` deliberately opens **no** channel and defines **no**
protocol. Choosing a channel API shape here would preempt P3-T12, so the plugin
is registered structurally only.

### Why the Dart and native package names differ

`name: vpn_engine_android` (Dart) but `package: dev.brickvpn.harness` (native).
The Kotlin kept its original package so the migration stayed a pure move. `native`
is a Java keyword, so AGP rejects it as a package segment — that is also why the
old harness used this namespace (see Constraints).

## Building the `libbox.aar` (required first)

`android/libs/libbox.aar` is a **gitignored build artifact** (~55 MB). A fresh
clone must build it before Gradle will compile.

```bash
bash packages/vpn_engine_android/scripts/build_libbox_aar.sh
```

The script pins and asserts every input, then **verifies** the output. P3-T11
changed only its output path: the AAR now lands in `android/libs/` (a library
module) rather than `app/libs/` (an application module).

| Pin | Value |
|---|---|
| sing-box | tag `v1.10.7` (commit `253b41936ecd6ae17948d49d9c510d7100830927`) |
| Go | 1.21.x — asserted at runtime; the script **fails** on any other minor |
| gomobile | `github.com/sagernet/gomobile` v0.1.4 — asserted from the binary's build info |
| gobind | same module/version as gomobile |
| NDK | r26b (`26.1.10909125`) |
| Build tags | `with_utls` — **required**; see below |
| Android API | 21 |

Prerequisites: Go **1.21.x** on `PATH`; `gomobile` **and** `gobind` in
`$HOME/go/bin`, both from `github.com/sagernet/gomobile@v0.1.4`:

```bash
go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.4
go install github.com/sagernet/gomobile/cmd/gobind@v0.1.4
```

**Do not use `gomobile init`** — it installs `gobind@latest`, which breaks the pin.

### `GOTOOLCHAIN=local` — mandatory

Go 1.21+ silently downloads and switches to a **newer** toolchain when a module's
`go` directive demands it, changing the compiled `.so` with no source change.
`GOTOOLCHAIN=local` makes the build either use the pinned Go or fail loudly.

### `with_utls` — mandatory

`-tags with_utls` is not optional. Without it, `common/tls/utls_stub.go` compiles
in and its `NewRealityClient` returns an unconditional error, so **every**
Reality (VLESS/XRay) outbound fails at parse time. Verified on the built AAR: the
stub error string is absent and `github.com/sagernet/utls` symbols are present.

### 16 KB page alignment

The script exports `CGO_LDFLAGS="-Wl,-z,max-page-size=16384"` and verifies the
result rather than assuming it. Every `LOAD` segment must show `0x4000`. NDK
r26b does **not** default to 16 KB (r27+ does), so the flag is load-bearing.

> **Naming gotcha:** a gomobile AAR ships `jni/<abi>/**libgojni.so**`, not
> `libbox.so`. Grepping the wrong name matches nothing and silently passes for
> the wrong reason.

## Running the tests

```bash
cd packages/vpn_engine_android/android
./gradlew testDebugUnitTest          # 36 JVM tests
./gradlew connectedAndroidTest       # 13 instrumented tests (needs a device)
```

### Instrumented tests need VPN consent first

`BrickVpnServiceTest` and `LibboxEngineTest` start a real `VpnService`. On a
device that has never approved a VPN app, every test fails until consent is
granted. Installing the APK **resets** the `ACTIVATE_VPN` appop, so grant it
*after* installing and *before* running:

```bash
adb install -r build/outputs/apk/debug/*.apk
adb shell appops set dev.brickvpn.native.harness ACTIVATE_VPN allow
adb shell am instrument -w dev.brickvpn.native.harness.test/androidx.test.runner.AndroidJUnitRunner
```

`testApplicationId` is pinned to `dev.brickvpn.native.harness` to preserve the
established VPN appop/device workflow from the harness era.

## Pinned versions

| Component | Version |
|---|---|
| Android Gradle Plugin | `9.1.0` |
| Gradle | `9.3.1` |
| Kotlin | AGP 9.x built-in support (do **not** apply `kotlin.android`) |
| `compileSdk` / `targetSdk` | `36` |
| `minSdk` | `24` (see Constraints) |
| Flutter embedding | `compileOnly` |

## Constraints

- **`minSdk 24` is a P3-T11 change from 21.** Flutter's own floor is 24, and the
  AAR is consumed by a Flutter app. The harness previously inherited 21, which
  was never validated against Flutter.
- **`namespace` is `dev.brickvpn.harness`.** `native` is a Java keyword, so AGP
  rejects it as a package segment. The *applicationId* /
  `testApplicationId` **is** `dev.brickvpn.native.harness` and is unaffected.
- **AGP 9.x has built-in Kotlin.** Applying
  `org.jetbrains.kotlin.android` is now an *error*. The plugin is deliberately
  absent. See <https://kotl.in/gradle/agp-built-in-kotlin>.
- **JUnit 4 is kept deliberately.** AGP 9 can silently run a JUnit 5 platform
  with zero discovered tests and report green. These tests are JUnit 4 so the
  counts are real: **36**, matching the old harness baseline exactly.
- **Flutter embedding is `compileOnly`.** This keeps the plugin buildable and
  testable standalone, exactly as the harness was, without dragging the Flutter
  SDK into the Gradle unit-test classpath.

## Not yet implemented here

- Pigeon platform channels and the Flutter bridge (P3-T12)
- The `AndroidVpnEngine` Dart implementation (P3-T14) and its provider override
  (P3-T15)
