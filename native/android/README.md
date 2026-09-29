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
| Go | 1.21.x (1.21.13) | `AI_ROLES/TOOLCHAIN_VERSIONS.md` (corrected in P3-T3) |
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

## Building `libbox.aar` (required before Gradle will compile)

`app/libs/libbox.aar` is a **build artifact** and is gitignored (48 MB). A fresh
clone must build it before `./gradlew assembleDebug` will work.

```bash
cd native/android
bash scripts/build_libbox_aar.sh
```

The script pins and asserts every input, then verifies the result:

| Pin | Value |
|---|---|
| sing-box | tag `v1.10.7` (commit `253b41936ecd6ae17948d49d9c510d7100830927`) |
| Go | 1.21.x — asserted at runtime; the script **fails** on any other minor |
| gomobile | `github.com/sagernet/gomobile` v0.1.4 — asserted from the binary's build info |
| gobind | same module/version as gomobile |
| NDK | r26b (`26.1.10909125`) |
| Android API | 21 |

### Prerequisites

- Go **1.21.x** on `PATH` via `$HOME/.local/go/bin`
- `gomobile` **and** `gobind` in `$HOME/go/bin`, both built from
  `github.com/sagernet/gomobile@v0.1.4`:
  ```bash
  go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.4
  go install github.com/sagernet/gomobile/cmd/gobind@v0.1.4
  ```
  **Do not use `gomobile init`** — it installs `gobind@latest`, which breaks the
  version pin and can pull a toolchain needing a newer Go.
- NDK r26b, `unzip`, `readelf`
- Network access to `github.com` and `proxy.golang.org`
- Disk: ~2 GB (module cache + 4-ABI build)

### `GOTOOLCHAIN=local` — why it is mandatory

Go 1.21+ will silently download and switch to a **newer** toolchain when a
module's `go` directive demands it. That changes the compiled `.so` with no
source change. `GOTOOLCHAIN=local` disables that: we either build with the
pinned Go or fail loudly. It is a reproducibility control, not hardening.

### 16 KB page alignment

The script exports `CGO_LDFLAGS="-Wl,-z,max-page-size=16384"` and then
**verifies the result** rather than assuming it:

```bash
unzip -q -o app/libs/libbox.aar jni/arm64-v8a/libgojni.so -d /tmp/libbox_check
readelf -l /tmp/libbox_check/jni/arm64-v8a/libgojni.so | grep -A 1 LOAD
```

Every `LOAD` segment must show `Align` = `0x4000`. NDK r26b does **not** default
to 16 KB (r27+ does), so the flag is load-bearing.

> **Naming gotcha:** a gomobile AAR ships `jni/<abi>/**libgojni.so**`, *not*
> `libbox.so`. A `grep` for the wrong name matches nothing and silently passes
> for the wrong reason; the script asserts the file exists before checking it.

### Generated Java API

The bind target is `io.nekohasekai.libbox`, and gomobile appends the Go package
name, so the generated class is **`io.nekohasekai.libbox.libbox.Libbox`** (note
the doubled `libbox`). `MainActivity` calls `Libbox.version()`, a `native`
method — that call is the JNI-linkage proof.

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
- **No VPN, no channels.** libbox *is* linked (P3-T3) and `Libbox.version()`
  is called, but `BIND_VPN_SERVICE` is deliberately absent: the `VpnService`
  is a later Gate A task, and platform channels are Gate B.
- **Nothing has run on a device yet.** The harness has been proven to *build*
  and the `.so` has been proven to be 16 KB aligned, but `adb devices` is empty,
  so `Libbox.version()` has never actually executed and an
  `UnsatisfiedLinkError` has not been ruled out on a real runtime.
- **Go is pinned at 1.21.x, not 1.20.** See the 16 KB / prerequisites sections
  above; the `go.mod` `go 1.20` directive understates the real requirement.

## Not yet implemented here

- `VpnService` lifecycle, TUN handling, ACTION_STOP handshake (P3-T6)
- Pigeon platform channels and the Flutter bridge (Gate B)
- Device/emulator verification of JNI linkage (needs hardware)
