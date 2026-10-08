# PROJECT_STATE.md — Current Snapshot

> **PROCESS RULE (non-negotiable):** This file MUST be updated by the coding
> agent at the end of every task, without exception, reflecting true,
> verified state — not aspirational state. AI chat context does not persist
> across sessions; this file does. It is the authoritative persistent memory
> of the project across sessions. If this file is stale, it must be corrected
> before any new task begins, not silently worked around.

> **PROCESS RULE (as of 2026-09-17 — non-negotiable):** AI coding agents are
> PERMANENTLY PROHIBITED from running any git write command (`add`, `commit`,
> `push`, `branch`, or any other state-changing git operation). Agents may
> only edit files; a human always executes git commands manually. This rule
> was established after an agent made three unauthorized (though low-risk,
> docs-only, factually accurate) commits during a Phase 0 closeout task
> without stopping to ask first.

> This file reflects the CURRENT state of the project only. It is not a
> history log (task-by-task history lives in Git commit history and each
> task's final report). Every AI agent must read this file first, before
> `ARCHITECTURE.md` or `ROADMAP.md`, to get immediate situational awareness.

**Last updated**: 2026-09-28 — P3-T1 toolchain research recorded + P3-T2 native Android harness scaffolded (build verified)
**Updated by**: Coding agent, during the P3-T2 native-module-scaffolding task; build output, APK contents and Dart test counts all re-derived from live runs in that task

---

## 1. Current Phase

**Phase 3 — Android VPN Engine: Gate A IN PROGRESS.** P3-T1 (toolchain
research) is delivered and `TOOLCHAIN_VERSIONS.md` is pinned. P3-T2 scaffolded
`native/android/` as a standalone, CLI-buildable Android Gradle project and **proven
`./gradlew assembleDebug`**, producing a real 3.2 MB debug APK; **as of P3-T11 that project
has been migrated to the Flutter plugin package `packages/vpn_engine_android/` and deleted.**
The Phase 2 parser layer
this phase consumes remains delivered and verified (8 protocol families, subscription decoder,
smart content router, Sing-Box serializer + inverse reader). Phase 2 is still not formally
closed: P2-T12 and P2-T9's AC verification remain open, and `P3-T1` declares
`Depends On: P2-T12`.

**P3-T2 build environment, all verified live on 2026-09-28:** JDK 17.0.20.1; Android SDK at
`~/Android/Sdk`; NDK **`26.1.10909125` (r26b)** present — matches the P3-T1 pin; AGP 9.1.0;
Gradle 9.3.1; `compileSdk`/`targetSdk` **36** (Platform 36 pre-installed); `minSdk` 21.
Two facts worth remembering: **AGP 9.x has built-in Kotlin support**, so applying
`org.jetbrains.kotlin.android` is now a hard build error; and **`native` is a Java keyword**,
so the Gradle `namespace` is `dev.brickvpn.harness` while the `applicationId` remains
`dev.brickvpn.native.harness` exactly as specified.

**Not yet proven (P3-T2, 2026-09-28; SUPERSEDED 2026-09-30 by P3-T6):** the APK had never been
installed or launched — `adb devices -l` was empty and `flutter emulators` reported
"No emulators available".

**P3-T6 UPDATE (2026-09-30) — a real device is now attached and was used.** `adb devices -l`
reports **`RZ8M53WPMPF`** (Samsung **SM-A205F**, Android 10 / **API 29**, usb `3-2`,
`state: device`). `./gradlew connectedAndroidTest` was run against it and passed **4/4**.
This closes the "no device available" blocker recorded in P3-T1/P3-T2. Note the device is
**API 29**, so the API 34+ foreground-service rules are not exercised on this hardware; the
`specialUse` declaration is forward-looking for `targetSdk 36` but unverified at runtime here.
`flutter emulators` remains empty — the device is USB-attached, not an AVD.

**P3-T5 (2026-09-27) — READY FOR HUMAN REVIEW, state machine implemented and tested.** A
STOP-AND-ASK was raised because the task brief, the ROADMAP, and `ARCHITECTURE.md` §3.1.1
specified **three different state vocabularies**; the human chose Option 1, making the ROADMAP's
**8-state** list authoritative and dropping the brief's `Reconnecting` (it has no legal incoming
edge in the normative graph, so it would have been an untestable dead state).

Delivered in `packages/vpn_engine_android/android/src/main/kotlin/dev/brickvpn/harness/vpn/`
(as of P3-T11; originally `native/android/app/src/main/java/dev/brickvpn/harness/vpn/`):
- `VpnState.kt` — 8 states as a **sealed class** (`Error` carries `reason`), plus the legal
  transition table. Mapping to `core_domain`'s 5 `ConnectionState` variants: `Idle`/`Stopped` →
  `Disconnected`, `Preparing`/`Starting` → `Connecting`, `Running` → `Connected`, `Stopping` →
  `Disconnecting`, `Error` → `Error`, `Revoked` → `Error(PermissionDenied)`.
- `VpnStateMachine.kt` — **pure Kotlin, zero `android.*` imports** (grep-verified), so it is
  host-JVM testable. Session tokens per `start()`; stale callbacks refused; the 5 Dart
  `VpnCommandResult` values returned synchronously while final state flows only through
  `StateFlow<VpnState>`; a 5000 ms watchdog.
- `VpnStateMachineTest.kt` — **36 tests, 0 failures, 0 errors, 0.44 s**, using
  `kotlinx-coroutines-test` virtual time (no emulator, no Robolectric, no `connectedAndroidTest`).

**Two real bugs found and fixed during the task, both worth remembering:**

1. **JVM class-initialization order (the serious one).** `LEGAL` was a
   `Map<VpnState, Set<VpnState>>` built in `VpnState`'s companion object. Because
   `VpnStateMachine`'s field initializer touches `VpnState.Idle` first, `VpnState$Idle.<clinit>`
   ran *before* `VpnState$Companion.<clinit>`, so the companion captured the still-uninitialized
   `Idle` and `Revoked` singletons as **`null`**: `Idle.canTransitionTo(Preparing)` silently
   returned **false**, and `onRevoke()` was refused. The map is now keyed by `const String` ids, so
   no lookup can depend on object init order. A dedicated regression test pins this.
2. **Watchdog re-arm on repeated `stop()`.** Naively re-arming the 5000 ms stop watchdog on every
   `stop()` call would let a polling caller keep a stuck teardown alive forever. `stop()` while
   `Stopping` is now a true no-op, proven by a test that calls it 5× and still converges.

**Deliberate design decision worth flagging:** the **stop watchdog forces `Stopped`, not `Error`**.
§3.1.1 forbids `Stopping -> Error` *precisely so* the watchdog can reach a legal resting state, so
forcing `Error` would violate the normative graph to satisfy a timeout. The **start** watchdog does
go to `Error("Watchdog timeout after 5000ms")`, which is legal.

**Test infrastructure was created from scratch:** before this task `app/src/test` did not exist and
`app/build.gradle.kts` declared **no** test dependencies, so `testDebugUnitTest` reported
`NO-SOURCE` and "passed" without running a single test. JUnit 4.13.2, `kotlinx-coroutines-core`
and `kotlinx-coroutines-test` were added. A green `testDebugUnitTest` was previously meaningless.

**P3-T7 (2026-10-02) — READY FOR HUMAN REVIEW, real libbox runs on a real device; AC1 explicitly OUTSTANDING.**
The P3-T6 fake engine is replaced by `LibboxTunnelEngine`, which drives a genuine sing-box v1.10.7
`BoxService`; `LibboxPlatformInterface` implements all **18** `PlatformInterface` methods (fresh
`javap` this task — zero drift from the P3-T4 table); `BrickVpnApplication` performs the process-wide
`Libbox.setup()`. Verified on `RZ8M53WPMPF` (SM-A205F, **API 29**): `connectedAndroidTest` →
**11/11, 0 failures**; host-JVM `testDebugUnitTest` → **36/36**. logcat proves real libbox execution:
`Libbox.setup ok` ×1, `libbox service started` ×11, `libbox service closed` ×11,
`openTun: lending` ×11, `TUN descriptor closed` ×12.

- **AC1 is NOT met.** The Gate A config's only outbound is `block`, which discards traffic, so there
  is no real tunnel and the device's effective outbound IP cannot change. AC1's manual before/after
  IP verification **awaits a human-provided test server / public endpoint**. This is a scoped,
  deliberate deferral — not "done", and it must not be reported as done.

### P3-T7 AC1 verification attempt (2026-10-03) — AC1 still NOT met; TWO NEW BLOCKERS found

A real verification attempt was made with a human-provided VLESS/Reality/gRPC public server and a
throwaway local Shadowsocks server. **AC1 remains unmet.** Two architectural blockers were found
that make the current build unable to carry real traffic at all, independent of any test server:

- **NEW OPEN ITEM A — the pinned libbox AAR is built WITHOUT `-tags with_utls`, so Reality is
  impossible.** In sing-box v1.10.7 `common/tls/utls_stub.go` (build tag `!with_utls`) makes
  `NewRealityClient` return an unconditional error, and `common/tls/client.go` calls it for every
  Reality outbound. The shipped `libgojni.so` demonstrably contains the stub (its embedded source
  path string and both stub error strings are present in the binary). Consequence: **any Reality
  endpoint — arguably the most common VLESS/XRay transport in the wild — cannot be used with the
  currently pinned AAR.** The AAR must be rebuilt with uTLS (and, if Reality-only parity is wanted,
  verified for other excluded tags). This is a dependency-level decision, not a task-level fix.
- **NEW OPEN ITEM B — outbound socket protection is present but permanently disabled, so a widened
  route would loop.** The protect-equivalent *does* exist and is already implemented as one of our 18
  `PlatformInterface` methods: `autoDetectInterfaceControl(fd)` (verified against pinned source —
  `Router.AutoDetectInterfaceFunc()` in `route/router.go` invokes it for **every** outbound socket;
  the reference app `sing-box-for-android` implements it as `protect(fd)`). But it is gated behind
  **both** `usePlatformAutoDetectInterfaceControl() = true` **and** `route.auto_detect_interface =
  true` in the config JSON. Ours currently returns `false` and the config omits the flag, so libbox
  falls back to interface-based binding. **Any real tunnelling is therefore impossible by current
  design**, and simply widening the route to `0.0.0.0/0` would route libbox's own connection to the
  server back into the TUN. Wiring `VpnService.protect(fd)` is a genuine prerequisite for shipping a
  usable VPN and deserves its own task, not a silent flip.
- **Positive result worth keeping:** with a **narrow** route (only the probe target's ranges, not
  `0.0.0.0/0`) and Shadowsocks — which needs no uTLS — the real engine **did** carry device traffic.
  Server-side proof: the throwaway Shadowsocks server logged inbound connections whose **only**
  source was the test device's LAN address, while the device stayed reachable over ADB throughout.
  So the TUN → libbox → outbound → remote-server path is real and works; what is missing is a
  transport the pinned AAR supports plus a full-route/protect pairing.
- **Environmental note:** the test device's clock is ~66 minutes behind the dev machine, which makes
  Shadowsocks 2022-cipher timestamp validation fail (`bad timestamp`). That is a device/NTP problem,
  not a tunnel defect, but it will mask payload-level verification until corrected.

**Net:** AC1 stays OUTSTANDING, now blocked on NEW OPEN ITEMS A and B rather than merely "awaiting
a test server". A test server is no longer the critical path; the pinned AAR's build tags and the
protect wiring are.
### P3-T7 Part 2 (2026-10-03) — NEW OPEN ITEMS A and B are FIXED; AC1 still NOT met (needs a credential)

Part 2 closed both architectural blockers above. **AC1 remains OUTSTANDING** — not because of
any remaining defect in our code, but because the retest could not be performed: the
human-provided VLESS/Reality credential was shredded at the end of the previous session per the
task's own teardown rule and was not re-supplied, so the "device IP actually changes to the
server's network" measurement could not be repeated. Nothing below claims otherwise.

- **NEW OPEN ITEM A — CLOSED. The AAR now carries uTLS.** `scripts/build_libbox_aar.sh` now
  passes `-tags with_utls` to `gomobile bind`, justified in-script from the pinned source rather
  than from memory: `Makefile:3` lists `with_utls` in sing-box's own official `TAGS_GO120`;
  `common/tls/reality_client.go:1` is `//go:build with_utls`; and `common/tls/utls_stub.go:1`
  is the `!with_utls` complement whose `NewRealityClient` raised the error that blocked us.
  Verified three ways:
  1. **Binary:** the new `libgojni.so` contains **zero** occurrences of `utls_stub.go` or the
     stub's error string, and now contains real uTLS internals (`uApplyPatch`,
     `uconn.Extensions`, ClientHello fingerprints) — the same `strings` probe that originally
     diagnosed the fault.
  2. **Host binary:** rebuilt `sing-box` with `-tags with_utls`; the identical Reality config
     that previously failed with `parse outbound[0]: uTLS, which is required by reality client
     is not included in this build` now parses cleanly.
  3. **On device:** the instrumented suite runs against the new AAR with **zero** occurrences of
     that error in logcat.
  The AAR still passes the script's 16 KB alignment assertion and is larger than before
  (53 MB vs 50 MB), consistent with uTLS being linked in. `with_reality_server` was
  deliberately NOT enabled: it is for running a Reality inbound, and we are a client.
- **NEW OPEN ITEM B — CLOSED. Socket protection is wired and proven live.**
  `LibboxPlatformInterface.usePlatformAutoDetectInterfaceControl()` now returns `true`,
  `autoDetectInterfaceControl(fd)` calls the real `VpnService.protect(fd)` (wired through a
  `socketProtector` lambda supplied by `BrickVpnService`), and the config carries
  `route.auto_detect_interface: true` — all three halves of the two-part gate. Verified by a new
  instrumented test asserting the callback **actually fires during a real dial** (not merely
  that the method exists), and separately on-device under a temporary `0.0.0.0/0` route:
  `protect()` was invoked, the suite still passed, and the device stayed reachable over ADB —
  i.e. **no routing loop**, which is precisely what the pairing prevents.
- **Tests:** `connectedAndroidTest` → **13/13** (was 11; two new permanent tests below).
  `testDebugUnitTest` → **36/36**.
- **Two new permanent tests** (deliberate non-doc repo changes, per this task):
  `outboundSocketProtectionIsInvokedDuringARealDial` guards the two-part protect gate against
  regression, and `deadPeerStillWalksTheFullLifecycleAndTearsDownCleanly` is a hermetic
  known-dead-peer test proving a valid config with an unreachable server still reaches `Running`
  and still tears down to `Stopped` — the guard against a "connected" state hiding a broken
  tunnel. The latter had to run through the real service rather than `start(tunFd = -1)`,
  because libbox configures the TUN during `BoxService.start()`, so a *valid* config needs a
  genuine descriptor.
- **Route decision left to the human, as instructed.** The `0.0.0.0/0` widening used for
  testing was **reverted**; `BrickVpnService` still ships the restricted `10.111.222.0/24`
  Gate A route. Whether a shipping VPN should capture `0.0.0.0/0` permanently is a product
  decision, not a harness default — and it must never ship without the protect wiring.
- **Build-script side change:** client submodules (`clients/android`, `clients/apple`) are now
  opt-in via `FETCH_CLIENT_SUBMODULES=1` rather than unconditional. They are not imported by
  `experimental/libbox`, and fetching them wasted ~20 minutes and failed twice with
  `RPC failed; curl 56` before this task.

**Net:** AC1's remaining dependency is a **human-provided test credential**, not a defect. The
two blockers that previously made it structurally unreachable are fixed and locked in by tests.

- **Three real bugs found on the device that code review had not caught:**
  1. **`Libbox.setup()` was never called.** Without it sing-box's `sWorkingPath` is `""`, so it
     resolved `cache.db` against the process CWD (`/`, read-only) and *every* `BoxService.start()`
     failed with `proxyerror: pre-start cache file: open cache.db: read-only file system`.
  2. **`android.permission.INTERNET` was missing.** libbox opens real sockets immediately; every
     `socket()` returned `EACCES`, surfacing as `initialize inbound/tun[tun-in]: listen tcp4
     10.111.222.1:0: socket: permission denied`. P3-T6 never needed it because `FakeTunnelEngine`
     touched no network — **a fake engine masked a genuine platform requirement.**
  3. **A TUN descriptor leak in the start/stop race.** When a stop arrived while `establish()` was in
     flight, a one-shot `AtomicBoolean` "already closed" flag was consumed while `tunPfd` was still
     `null`, so the descriptor the racing start then acquired could never be released. Replaced with
     an `AtomicReference` claim on the descriptor itself; `runStartSequence` now also releases a
     descriptor whose session was superseded. The final logcat measurably balances: 11 sessions +
     1 superseded release = **12** descriptor closes.
- **P3-T6's descriptor rule was re-verified, not assumed:** `noDescriptorLeakAcrossStartStop` passes
  with the real engine, `detachFd()` is still never called, and libbox's own wrapper `dup()`s the fd
  (primary source: `experimental/libbox/service.go:OpenTun`).
- **AC5 answered with primary-source evidence:** the v1.10.7 18-method interface contains **no DNS
  `lookup()`/resolver callback at all**, so the legacy `Semaphore`/thread-pool deadlock class is
  structurally absent from this pin rather than merely avoided.

**P3-T11 (2026-10-05) — READY FOR HUMAN REVIEW. The engine is now a Flutter Android platform
plugin at `packages/vpn_engine_android/`; the obsolete `native/android/` project is DELETED.**
Migration was a **pure move**: all 9 Kotlin files (7 main + 2 androidTest), both
`AndroidManifest.xml` files, and the JVM test class were verified **byte-identical** (`cmp`) to
their former `native/android/` originals before deletion, so no behavioural regression is
possible from the repackaging. `scripts/build_libbox_aar.sh` moved with them (output path
changed to `android/libs/libbox.aar`, since a library module has no `app/`); `README.md` and
`REFERENCE_ARCHITECTURE_STUDY.md` moved too.

- **Test counts preserved exactly: 36/36 JVM, 0 failures, 0 errors; 13/13 instrumented, 0
  failures** — asserted numerically from the JUnit XML, not from Gradle's exit code. This
  matters because AGP 9 can run a JUnit 5 platform that discovers zero tests and still report
  green; these tests stay JUnit 4 precisely so the count is meaningful.
- **Rebuilt AAR verified by measurement, not hash:** sing-box v1.10.7 with `with_utls`;
  `PlatformInterface` has exactly **18** methods via `javap`; `utls_stub.go` and its
  "uTLS, which is required by reality client is not included in this build" error string are
  **absent**; real `github.com/sagernet/utls` symbols (922 refs) and
  `sing-box/common/tls.NewRealityClient` are **present**; arm64-v8a `LOAD` segments are
  **0x4000** (16 KB) aligned.
- **`VpnEngineAndroidPlugin` opens no channel and defines no protocol**, by design. Picking a
  channel shape here would preempt P3-T12. The Dart engine (P3-T14) and provider override
  (P3-T15) are likewise not wired; `apps/mobile` carries a path dependency and nothing imports
  it yet.
- **Melos dual-list rule:** added to the workspace and to `test:flutter`'s `ignore`, and
  deliberately **NOT** added to `test:dart`'s `scope`. It is a Flutter package with no
  `test/` directory; scoping it into plain `dart test` would route it into an incompatible
  runner. `melos bootstrap` → 7 packages; `melos run analyze --no-select` → SUCCESS across all
  7; `dart format --set-exit-if-changed .` → 0 changed.

- **Two wiring bugs found and fixed during this task, both silent:** the plugin's `pubspec.yaml`
  needs `resolution: workspace` (every existing member declares it, and bootstrap hard-fails
  without it), and this repo's YAML is **2-space** indented — a 4-space edit nested
  `vpn_engine_android` under `shared_utils` in `apps/mobile/pubspec.yaml`, which `melos`
  rejected with a confusing "Unrecognized keys: [sdk, git, path, hosted]" parse error.
- **`.gitignore` footgun carried over deliberately:** the root's blanket `*.jar` rule would
  have excluded `android/gradle/wrapper/gradle-wrapper.jar`, so `./gradlew` would fail on every
  fresh clone. The plugin `.gitignore` re-includes it, as `native/android/.gitignore` did.
- **NOT re-verified this session: the 13 instrumented tests.** They passed 13/13 earlier in this
  session, but the final post-deletion pass could not re-run them because `RZ8M53WPMPF`
  disconnected (`adb devices` empty; no system image is installed, so there is no emulator
  fallback). The instrumented APK **does** build (`assembleDebugAndroidTest` → SUCCESS) and the
  test sources are byte-identical, so this is an environment gap, not a known defect — but
  treat the post-deletion 13/13 as **not independently re-confirmed** until a device is
  reattached. Order matters when redoing it: install first, then
  `adb shell appops set dev.brickvpn.native.harness ACTIVATE_VPN allow`, then instrument.

**P3-T6 (2026-09-30) — READY FOR HUMAN REVIEW, VpnService skeleton proven on a real device.**
`BrickVpnService` implements the Android lifecycle against the P3-T5 `VpnStateMachine`, with
**no libbox call of any kind** (engine is `FakeTunnelEngine`, a fixed-delay sleep) — the
P3-T6/P3-T7 separation was preserved as `ROADMAP.md` requires. Delivered in
`native/android/app/src/main/java/dev/brickvpn/harness/vpn/`: `TunnelEngine.kt` (interface +
fake) and `BrickVpnService.kt`; instrumented tests in `app/src/androidTest/.../BrickVpnServiceTest.kt`.

- **Real-device proof:** `RZ8M53WPMPF` (Samsung SM-A205F, **API 29**). `./gradlew connectedAndroidTest`
  → **4/4 passed, BUILD SUCCESSFUL**; the P3-T5 host-JVM suite still **36/36**.
- logcat proves the real chain: `service created → onStartCommand: start → TUN descriptor
  acquired (fd=64) → state -> Starting → state -> Running`, then `ACTION_STOP → Stopping →
  onDestroy → TUN descriptor closed`.
- **Descriptor discipline:** `establish()` is retained in Kotlin and closed exactly once via an
  `AtomicBoolean` guard, on a `cleanupScope` that **outlives `onDestroy`** so a teardown-time
  cancel cannot skip the close. `detachFd()` is never called. No fd leak across 3 cycles
  (asserted against `/proc/self/fd`).

**One real bug found and fixed, worth remembering:** the `ACTION_STOP` branch of
`onStartCommand` did **not** call `startForeground()`. The instrumentation process was killed
mid-suite with `android.app.RemoteServiceException: Context.startForegroundService() did not
then call Service.startForeground()`. `startForegroundSafely()` is now hoisted to the top of
`onStartCommand` for **every** action, and the tests use `startService()` (not
`startForegroundService()`) for the stop command, since a teardown must not re-promote to
foreground. High confidence — the exception names the contract verbatim.

**Known gap carried forward:** the device is **API 29**, so the Android 14+ foreground-service
rules are *not* exercised. The manifest declares `specialUse` (correct for `targetSdk 36`) but
that path is unverified at runtime on this hardware. **P3-T7's test-config question is now
partially answered and remains OPEN.** The non-traffic half is done (see the P3-T7 entry above):
the harness runs real libbox against a hardcoded `block` outbound, so no server was needed to
verify lifecycle and teardown. What is still open is **exactly ROADMAP P3-T7 AC1** — a real
outbound plus a manually verified change in the device's effective outbound IP — which **awaits a
human-provided test server or public endpoint**. Do not read this as resolved.

**P3-T4 (2026-09-27) — READY FOR HUMAN REVIEW, study written.** The STOP-AND-ASK was
**answered by the human: sing-box v1.10.7 is retained** (to preserve the Phase 2
WireGuard/AmneziaWG schema), so the study was written scoped to the pinned API.
`native/android/REFERENCE_ARCHITECTURE_STUDY.md` now exists (~18 KB) and covers all six
domains. Decisions recorded there:

- **TUN FD ownership:** `establish()` -> retain the `ParcelFileDescriptor` in the Kotlin
  controller -> pass `pfd.fd` to libbox. **`detachFd()` is never called.** Confirmed in both
  references (`hiddify` has zero `detachFd` hits under `android/app/src/main`). This directly
  addresses the legacy TUN-leak failure in `ARCHITECTURE.md` §3.5.
- **Thin service:** `VpnService` is a lifecycle shell; logic lives in a separate, unit-testable
  controller. Both references do this (`VPNService.kt:28-46` in each).
- **Single process:** neither reference declares `android:process`; `.bg.` is a package segment,
  not a process. Gate A stays single-process.
- **JNI:** the exact **18-method** `io.nekohasekai.libbox.libbox.PlatformInterface` was extracted
  from our own AAR via `javap` and tabulated. Newer upstream methods (`checkPlatformShell`,
  `usePlatformAutoRedirect`, `usePlatformBridge`, …) are explicitly marked unavailable.
  Note `InterfaceUpdateListener.updateDefaultInterface(String,int)` takes **2** args here vs
  **4** upstream — porting the reference call verbatim would not compile.
- **Panic safety is an open gap, not solved:** neither reference traps Go panics at the JNI
  boundary (sing-box-for-android's `triggerNativeCrash()` is debug-only). Mitigation is the
  session-token + stop-watchdog contract already in `MockVpnEngine`, not exception handling.

Sources `8e42c63` and `276a7ef` were studied for architecture only; **zero GPL code was copied**.
Hiddify is GPLv3 §7-with-additional-terms, recorded in `TOOLCHAIN_VERSIONS.md`.


**P3-T3 (2026-09-28) — libbox AAR built.** `native/android/scripts/build_libbox_aar.sh`
reproducibly builds `app/libs/libbox.aar` (48 MB, gitignored) from sing-box **v1.10.7**
(commit `253b41936ecd6ae17948d49d9c510d7100830927`) using Go **1.21.13**, gomobile/gobind
**v0.1.4** and NDK **r26b**. All 4 ABIs are produced; arm64 `LOAD` segments verified at
`0x4000` (16 KB aligned) both in the AAR and in the final APK. The AAR is linked into the
harness and `MainActivity` calls `Libbox.version()`.

**P3-T1 pin CORRECTED — Go 1.20 -> 1.21.x** (human-approved). sing-box v1.10.7's `go.mod`
declares `go 1.20`, but that *understates* the real requirement:
`experimental/libbox/command_connections.go:6` imports the stdlib `slices` package, which only
entered GOROOT in Go 1.21, so `gomobile bind` cannot compile the libbox package with Go 1.20.
The lesson generalises: **a `go` directive is a floor, not a build recipe** — verify what the
package actually imports, not only what go.mod declares.

Two further facts recorded in `TOOLCHAIN_VERSIONS.md` / `native/android/README.md`:
(a) a gomobile AAR ships `jni/<abi>/libgojni.so`, **not** `libbox.so`; and (b) the generated
class is `io.nekohasekai.libbox.libbox.Libbox` (javapkg + Go package name), not
`io.nekohasekai.libbox.Libbox`.

**Still unproven:** `Libbox.version()` is compiled and packaged but has **never executed** —
JNI linkage is proven at build time only, not at runtime. That needs a device.

**Phase 2 is substantially complete but NOT 100% complete, and was not closed by the agent.** A
closeout audit was performed on 2026-09-27 and is recorded in `ROADMAP.md`. Outstanding:
- ~~**P2-T10 (subscription URL fetch)**~~ — **delivered 2026-09-27.** `SubscriptionFetcher` in
  `packages/config_parser/lib/src/subscription/subscription_fetcher.dart`: HTTPS-only (re-checked
  on every redirect hop), 5-hop redirect cap, 10s whole-fetch deadline, 5 MB cap applied
  incrementally with immediate stream cancellation, injectable `SubscriptionTransport` for
  offline tests, and six new secret-safe `ConfigParseError` variants. Verified against a real
  server streaming 200 MB (aborted at 2 MiB in ~0.4 s). Certificate pinning remains deferred.
- ~~**P2-T11 (adversarial/fuzz pass)**~~ — **delivered 2026-09-27, and it found two real
  bugs.** `test/fuzz_adversarial_test.dart` (104 tests) pushes a curated corpus plus 5 000
  seeded random inputs through all 15 public entry points, asserting that nothing throws and
  no canary leaks. **Both bugs were unhandled `FormatException` crashes reachable from a single
  pasted link:** (1) seven duplicated `_percentDecode` helpers caught only `ArgumentError`, so
  `trojan://%C3%28@host:443` crashed six parsers; (2) nine unguarded `Uri.queryParameters` sites
  crashed seven more, since `queryParameters` calls `decodeQueryComponent`. Both fixed at the
  single shared source. Full write-up in `packages/config_parser/SECURITY_NOTES.md`, which also
  records residual limitations honestly.
- **P2-T9** — implemented and tested, but its acceptance criteria have not been human-verified
  one-by-one; checkboxes left unticked on purpose.
- **P2-T12** — this audit was performed; the full DoD checklist walk is outstanding.

**The gate:** `P3-T1` declares `Depends On: P2-T12`, so Phase 3 is formally gated until a human
closes P2-T12. Gate A is a native-only Kotlin harness with zero Flutter involvement and does not
use subscription fetching, so P2-T10 does not block it; P2-T11 is the more relevant risk to
schedule early, because Phase 3 will feed real untrusted config into this parser. Phase 3 is
officially titled "Android VPN Engine", not "Core Engine & Platform Integration".

Phase 0 (Project Foundation & Governance Setup) and Phase 1 (Architecture Skeleton, P1-T1..P1-T11)
are complete. Phase 1 built, and is verified by re-running the suites against the live repository:
`Result<T, E>` (P1-T1), the core domain types (P1-T2), the polymorphic `OutboundConfig` hierarchy
with `ServerProfile` (P1-T3), the `VpnEngine` contract with sealed `VpnCommandResult` (P1-T4),
the hardened `MockVpnEngine` reference implementation (P1-T5), the feature-first folder convention
(P1-T6), the Riverpod DI wiring (P1-T7), the `go_router` skeleton (P1-T8), the logging skeleton with
a redaction stub (P1-T9), and the `easy_localization` wiring (P1-T10). P1-T11 is this closeout audit.

**Phase 2 built the pure-Dart `config_parser` package** (`packages/config_parser`, routed through
`dart test`): the `ConfigParseError` taxonomy plus bounded defensive decoders (P2-T1), six protocol
parsers — VLESS, VMess, Trojan, Shadowsocks (both SIP002 and legacy forms, with cipher validation
against sing-box's verified 18-value list), Hysteria2 (`hy2://` and `hysteria2://`) and TUIC (P2-T2
through P2-T7, which in practice shipped as a smaller number of larger commits — see §6 Known
Deviations), the unified `parseUri` scheme dispatcher (P2-T8), the Sing-Box 1.10+ JSON serializer, and
the subscription decoder / `Subscription-Userinfo` parser with fault-tolerant bulk parsing. Field
names and accepted values were verified against the live sing-box documentation rather than
training data.

Two further capabilities were added after the original P2 plan was written, and are recorded in
`ROADMAP.md` as **P2-T13** and **P2-T14** (deliberately *not* renumbered onto P2-T6/P2-T7, which
are the Hysteria2 and TUIC entries and retain their own acceptance criteria):
- **WireGuard / AmneziaWG** — `ProtocolType.wireguard` / `.amneziawg`, the `WireGuardOutbound` and
  `AmneziaWgOutbound` domain types, `wireguard://` / `wg://` / `amneziawg://` / `awg://` URI parsers
  and Sing-Box JSON mapping. Requires `core_domain` to be unfrozen, and it must be **re-frozen**
  after this work.
- **Smart content router** — `parseConfigContent` detects and routes pasted input (deep link →
  single URI → raw JSON → subscription) and returns a uniform `SmartParseResult`, with
  `readSingBoxOutboundJson` as the inverse of the Sing-Box serializer.

Both are uncommitted and awaiting human review. Open items carried into review: the sing-box
WireGuard outbound is deprecated (removed in 1.13.0); sing-box has no AmneziaWG schema so the nine
obfuscation parameters cannot be serialized for runtime use; `AmneziaWgOutbound` still lacks
`==`/`hashCode` covering those parameters; the AWG numeric ranges are not yet cited to an
authoritative source; and `brick://` has no Android intent-filter registered yet.

**Closeout measurements (all figures re-run at the stated audit time):**
- **575 tests pass monorepo-wide (551 pure-Dart + 24 Flutter), re-run 2026-09-28** during the
  CI-restoration/governance-sweep task, which replayed the full `.github/workflows/ci.yml`
  step sequence locally (bootstrap → format → analyze → test; all four SUCCESS). Pure-Dart:
  `shared_utils` 15, `core_domain` 123, `core_vpn_engine` 43, `config_parser` 370. Flutter:
  `mobile` 23, `ui_theme` 1. The `core_domain` and `config_parser` increases over the previous
  556 figure come from this task: 16 new AmneziaWG equality tests and 3 new serializer
  lock-in tests.
  (Supersedes 556/532, 554/530, "175 tests / 152 pure-Dart", "258 pure-Dart", the
  "346 tests / `core_domain` 94 / `config_parser` 170" figure, and the
  "417 / `config_parser` 228" figure; all were stale.)
- **Pure Dart isolation verified 2026-09-27:** 0 `package:flutter/` and 0 `dart:ui` imports in
  `shared_utils`, `core_domain`, `core_vpn_engine` and `config_parser`; 0 references to
  `core_vpn_engine` in `config_parser`'s `pubspec.yaml` or barrel.
- **Redaction:** 0 `toString()` overrides on any config or domain type (so no accidental default
  dump of a secret-bearing object), and a canary-based sweep across 19 hostile inputs confirms no
  parser error message echoes input secrets. See §6 for the one leak this audit found and fixed.
- `flutter analyze .` — 0 errors, 0 warnings, 0 lints across all 6 packages.
- `dart format --set-exit-if-changed` — was NOT clean before this task (this is what turned CI red); a formatting-only fix is applied in the current task and re-verified as 0 changed, but the committed baseline on `master` is still unformatted until the human pushes.
- **Pure-Dart isolation re-verified:** 0 `package:flutter/*` and 0 `dart:ui` imports in
  `shared_utils`, `core_domain`, and `core_vpn_engine`; all three run under plain `dart test`.

**This phase is not "zero technical debt."** Known open items are listed in §6. The most
consequential: the device-run acceptance criteria for P1-T7/T8/T10/T11 were never executed
(no Android device was available), and `redact()` is a documented no-op stub until Phase 8.

## 2. Active Task Status — Phase 2 delivery + Phase 3 readiness (quoted from `AI_ROLES/ROADMAP.md`)

Status tokens below are quoted verbatim from the corresponding `**Status:**` line in `AI_ROLES/ROADMAP.md`.

- **P1-T1** (`ROADMAP.md:564`): `Completed ✅` — Hand-written `Result<T, E>` implemented in `packages/shared_utils` with 10 standalone unit tests passing. Pushed and merged to master.
- **P1-T2** (`ROADMAP.md:599`): `Completed ✅` — `ConnectionState` (sealed, 5 variants) and `TrafficStats` (immutable value type) implemented in `packages/core_domain` with 13 standalone unit tests passing. `ConnectionErrorReason` implemented as a sealed class (chosen over enum to carry `PlatformError`'s String payload). Package migrated to pure Dart. Pushed and merged to master at commit `e6f9874`.
- **P1-T3** (`ROADMAP.md:642`): `Completed ✅` — Implemented the sealed `OutboundConfig` hierarchy (TCP-based family: VLESS/VMess/Trojan; QUIC-based family: Hysteria2/TUIC with mandatory non-nullable TLS and `zeroRttHandshake` defaulting to false; standalone Shadowsocks), 7 shared composition types, the `ProtocolType` enum, and the `ServerProfile` container. 76 new unit tests (89 total passing), including the `extraParams` null-defaults tripwire and exhaustive-switch checks. Package remains pure Dart. Pushed and merged to master at commit `9e748e2`.
- **P1-T4** (`ROADMAP.md:679`): `Completed ✅` — Implemented `abstract interface class VpnEngine` (connectionState/trafficStats streams with independent failure domains, `start(ServerProfile)`/`stop()`/`getStatus()` with acceptance-separate-from-state semantics) and sealed `VpnCommandResult` (5 stateless variants with `'type'` discriminators). Package migrated to pure Dart (`core_domain` workspace dep) and added to both Melos lists in the same change set. 13 tests passing, including exhaustive-switch and stream-isolation checks. Pushed and merged to master at commit `249617f`.
- **P1-T5** (`ROADMAP.md:721`): `Completed ✅` — `MockVpnEngine` reference implementation (541 lines) fully implemented: simulated lifecycle, configurable rejections, independent failure domains, session tokens, a 5000 ms stop watchdog, and idempotent `stop()`/`dispose()`. 30 `mock_vpn_engine_test.dart` tests (43 total in the package, up from 13 at P1-T4). 147 pure-Dart tests pass monorepo-wide (10 shared_utils + 94 core_domain + 43 core_vpn_engine). `flutter analyze` clean across all 6 packages. The state-machine graph gained a `Connected -> Error` edge to support `simulateUnexpectedDisconnect()` (see ARCHITECTURE.md Section 3.1). **These changes are uncommitted and awaiting human review/commit** (the earlier `45b7c85` commit's non-conventional message is a permanent accepted deviation — see §6).
- **P1-T6** (`ROADMAP.md:759`): `Not Started` — Feature-first folder structure convention + reference feature skeleton (this is the next planned task; work has not yet begun in the file).

---

## 3. What Exists Right Now (Verified)

### Code & Architecture Skeleton
- **`packages/vpn_engine_android/` (Flutter Android platform plugin, verified):** Created in
  P3-T11. Wraps the proven Gate A native VPN engine (`BrickVpnService` + `LibboxTunnelEngine` +
  real libbox `BoxService`) as a Flutter Android platform plugin, replacing the deleted
  `native/android/` standalone harness. Kotlin sources, both manifests, and all tests were
  migrated **byte-identically**, so behaviour is unchanged by construction. Verified:
  **36/36** JVM tests and **13/13** instrumented tests (13/13 not re-confirmed post-deletion —
  device unavailable; see the P3-T11 entry in §1). `PlatformInterface` implements all **18**
  libbox methods. Ships a structural, channel-free `VpnEngineAndroidPlugin`; the platform
  channel is P3-T12, the Dart engine P3-T14. `minSdk` 24, `compileSdk`/`targetSdk` 36, AGP 9.1.0,
  Gradle 9.3.1, built-in Kotlin. Builds its own `libbox.aar` via
  `scripts/build_libbox_aar.sh` (sing-box v1.10.7, `with_utls`, 16 KB aligned).
- **`packages/shared_utils/` (Pure Dart, verified):** Retroactively corrected P0-T6's scaffolding by removing all Flutter SDK transitives. Contains a hand-written, sealed `Result<T, E>` primitive with `Ok` and `Err` final subclasses (value-equality with `identical` fast path, intentionally no `toString` override so sensitive error payloads are not printed by default, `map`/`mapErr` transforms, and exhaustive `fold`/pattern-matching). Tested with 10 standalone unit tests running under `dart test`.
- **`packages/core_domain/` (Pure Dart, verified):** Contains the complete polymorphic `OutboundConfig` hierarchy — sealed `TcpBasedOutbound` family (VLESS, VMess, Trojan), sealed `QuicBasedOutbound` family (Hysteria2, TUIC — mandatory non-nullable TLS, `zeroRttHandshake` defaulting to false), and standalone `ShadowsocksOutbound` — plus 7 shared composition types (`TlsSettings`, `TransportSettings` with 4 transports, `QuicSettings`, `MultiplexSettings`, and the REALITY/uTLS/fragment blocks), the `ProtocolType` enum (6 values with canonical URI schemes), and the `ServerProfile` container with `copyWith`. Ships alongside sealed `ConnectionState` (5 variants), sealed `ConnectionErrorReason` (4 variants), and immutable `TrafficStats`. All value types are const-constructible with `identical`-fast-path equality, implement discriminated snake_case `toJson()`, and intentionally have no `toString` override (SECURITY.md). Tested with 89 standalone unit tests running under `dart test`.

**API-shape change (2026-09-25):** `TlsSettings`, `WebSocketTransport`, `HttpTransport`, `HttpUpgradeTransport`, and `Hysteria2Outbound` are **no longer `const`-constructible**. The first four now defensively copy their `List`/`Map` fields into unmodifiable views at construction (so a caller mutating a collection afterwards can no longer change a "value type" that may sit in a `Set`/`Map` with a shifting `hashCode`); `Hysteria2Outbound` gained an unconditional constructor-time `ArgumentError` when `obfsType`/`obfsPassword` are set inconsistently. Both are runtime operations a const constructor cannot express. All other domain value types remain `const`-constructible.
- **`packages/core_vpn_engine/` (Pure Dart, verified):** Migrated from Flutter scaffold to pure Dart in P1-T4. Exposes the `abstract interface class VpnEngine` contract (authoritative `connectionState` stream, independent `trafficStats` stream, acceptance-separate-from-state `start(ServerProfile)`/`stop()`/`getStatus()`) and sealed `VpnCommandResult` (5 stateless variants: Accepted, RejectedBusy, RejectedInvalidConfig, RejectedPermissionDenied, Failed — const, value-equal, discriminated `toJson()`, no `toString`). P1-T5 added the in-memory `MockVpnEngine` reference implementation (541 lines): simulated lifecycle (`Disconnected` → `Connecting` → `Connected` → `Disconnecting` → `Disconnected`) with injectable delays, a periodic `TrafficStats` ticker, configurable rejection/failure hooks, an exhaustively-checked legal-transition graph that throws `StateError` on impossible sequences, structurally independent stats/connection pipelines, and an idempotent `dispose()`. Tested with **43 standalone unit tests** under `dart test` (13 from P1-T4 + 30 in `mock_vpn_engine_test.dart`), including exhaustive-switch, stream-isolation, session-token race, stop-watchdog, 100-interleaved-command stress, and 100-engine resource-leak checks. **P1-T5 hardening (2026-09-26)** further added: a monotonic **session token** so superseded async callbacks can never transition the engine; a hard **5000 ms stop watchdog** (`MockVpnEngine.defaultStopWatchdogTimeout`, overridable only so tests can drive the mechanism without a 5-second wait) that force-completes a stuck teardown; fully **idempotent `stop()`** (always accepted); per-session counter reset relocated into `start()`; hardened disposal ordering (`_disposed` set before controllers close, all four timers cancelled); and `simulateConnectionFailure()` / `simulateUnexpectedDisconnect()` failure hooks. The legal-transition graph now permits **`Connected` -> `Error`** so an established tunnel can fail without being asked to (previously only `Connecting` could reach `Error`), which is what `simulateUnexpectedDisconnect()` exercises.
- **`apps/mobile` (Flutter, wired, pure-Dart deps declared):** Dependencies resolved and pinned (`flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`, `build_runner`, `go_router`, `easy_localization`, `logger`, `very_good_analysis`), plus the workspace siblings `core_domain`, `core_vpn_engine`, and `shared_utils` declared explicitly. Built out during P1-T6..P1-T10:
  * `lib/core/providers/` — `@Riverpod(keepAlive: true)` providers: `vpnEngineProvider` (bound to `MockVpnEngine`, with `ref.onDispose`), `appRouterProvider` (`GoRouter`), `appLoggerProvider` (`AppLogger`). All `.g.dart` files are generated by `build_runner` and **are committed** (not gitignored).
  * `lib/core/logging/app_logger.dart` — the single supported logging entry point; routes every message through `redact()` and silences itself entirely in release builds (`Level.off`).
  * `lib/core/router/app_router.dart` — the route table (`/` Home, `/settings` Settings).
  * `lib/features/` — the feature-first convention: `README.md` plus the `connection` and `settings` reference features, each with `data/`, `domain/`, `presentation/`. Screens use `.tr()` exclusively.
  * `assets/translations/en.json` — the localization asset, registered under `flutter: assets:`.
  * `test/localization_test_harness.dart` — reproduces the real `EasyLocalization` + `ProviderScope` stack (in-memory `AssetLoader`) so widget tests exercise the actual `.tr()` lookup path.
  * 23 Flutter tests pass. The app has **not** yet been run on a device (see §6).
- **Melos Workspace (6 packages):** Configured via root `pubspec.yaml` list and individual package `resolution: workspace` settings.
- **Deterministic Test Routing (Refactored):** Root `pubspec.yaml` Melos `test` script was refactored into a composite script that dispatches tests to:
  * `test:dart` (`melos exec -- dart test`): routes pure-Dart packages (`shared_utils`, `core_domain`, `core_vpn_engine`) via an allowlist (`scope:`). Currently 3 packages allowlisted — shared_utils (15 tests), core_domain (94 tests), and core_vpn_engine (43 tests, including the P1-T4 `VpnEngine`/`VpnCommandResult` suite and the P1-T5 `MockVpnEngine` suite); more will be added as Phase 2 (`config_parser`) migrates to pure Dart. **Monorepo total as of the P1-T11 closeout: 152 passing pure-Dart tests** (15 + 94 + 43), plus **23 Flutter tests** in `apps/mobile` = **175 total**.
  * `test:flutter` (`melos exec -- flutter test`): routes Flutter-dependent packages via a denylist (`ignore:`).
  * This ensures pure-Dart packages are tested natively with plain `dart test` (5.8s real time) rather than relying on undocumented Flutter fallback behavior (13.8s real time).

### Repository & CI
- **Git HEAD sync:** Local `master` HEAD is verified equal to live `origin/master` at every audit cycle. Exact hash is NOT recorded here to avoid the self-referential staleness inherent in "the document naming its own commit's hash before that commit exists". Use `git rev-parse HEAD` for the current value.
- **CI Status: RED on `master` (as of 2026-09-28).** The four most recent *push*-event runs (`503bbd1`, `29860a1`, `1bb7972`, `117c0f8`) all failed on the single job **"Check formatting"**; "Analyze workspace" and "Test workspace" were skipped, so no analyzer or test failure is involved. Root cause: two `core_domain` test files were committed unformatted and several `config_parser` parser files were edited unformatted, so `melos run format --no-select` exits non-zero. **A local formatting fix is prepared (see the current task) but is NOT yet on CI and is NOT verified green until the human commits and pushes.** Re-check with `gh run list --branch master --event push` after pushing.
- **Branch Protection:** Active on remote `master` via GitHub UI (no force-push, no deletion).
- **Vulnerability Scanners:** GitHub secret scanning, push protection, and Dependabot are active.
- **Tracked logs:** Phase 0 closeout report is committed and tracked in `AI_ROLES/logs/phase-0-closeout-2026-09-17.md`.

---

## 4. What Does NOT Exist Yet

- ~~`MockVpnEngine` reference implementation (`core_vpn_engine` — P1-T5)~~ — **now exists** (see §3). UI feature wiring and native integration are still ahead.
- **Real redaction logic** (P1-T9 stub, Phase 8 work). The `redact()` helper
  lives in `packages/shared_utils/lib/src/redaction.dart` and is currently a
  documented pass-through stub returning its input unchanged. `AppLogger`
  (`apps/mobile/lib/core/logging/app_logger.dart`) already routes every log
  message through it, so Phase 8 only has to implement the masking rules — no
  call-site changes required. Until then, NO sensitive value is actually
  redacted at runtime; see SECURITY.md Section 4.
- Android native integration (`VpnService`, `libbox` JNI bridge) — deferred to Phase 3.
- **Secure storage for saved server profiles — NOT yet done; release blocker.**
  Saved servers are currently persisted in **plain `SharedPreferences`**
  (`apps/mobile/lib/core/providers/server_profile_repository_provider.dart` binds
  `SharedPreferencesServerProfileDataSource`). The stored value is the
  **full source URI, which embeds the server credential** (e.g. a VLESS UUID or
  a Trojan password), so on a rooted or imaged device that data is readable in
  cleartext. Per SECURITY.md §3, server config is High-sensitivity data and plain
  `SharedPreferences` is not acceptable at release.
  **Required before Phase 11 / release:** replace the data source with a
  `flutter_secure_storage`-backed (Keystore / Keychain) implementation of
  `ServerProfileLocalDataSource`, keeping the repository and every provider
  unchanged so only the composition root moves. The `TODO(Ajorvpn)` in
  `server_profile_repository_provider.dart` tracks this; it is a **deferred
  security task, not a stylistic one** — do not treat the green test suite as
  evidence this is closed.
  Accepted for now because the alternative is shipping no persistence at all;
  it must not survive to release.
- Clean Linux desktop toolchain (missing locally: clang, cmake, ninja, pkg-config; deferred to Phase 12).

---

## 5. Environment & Toolchain Notes

- **Verified toolchain pins:** Flutter 3.47.4 stable, Dart 3.13.3, Melos 8.7.0, Git 2.43.0. Do not change any pinned version as a side effect of another task.
- **Local Gradle init-script footgun (must stay disabled):** `/home/e60/.gradle/init.d/iran-mirrors.gradle.disabled` must remain disabled to prevent settings-repository conflicts in Android Gradle builds.
- **Disk pressure — standing gate item:** Disk `/` fluctuates as build/tool caches accumulate. As measured on 2026-09-25, `/` is at **86% (14 GB free)**, which is **below** the project's documented ~92% danger threshold. A manual cache cleanup was performed by the human maintainer between the 2026-09-22 forensic audit (which recorded 95% / 4.9 GB free — above the danger line) and this entry; this agent did not run the purge itself. Safe repo-local recipe if needed: `rm -rf apps/mobile/build packages/*/build .dart_tool apps/mobile/.dart_tool packages/*/.dart_tool` then `melos bootstrap`. Note the largest consumers on this machine are outside the repo (`~/.gradle` and `~/Android`, measured at 8.4 GB and 8.8 GB respectively on 2026-09-22), so the repo-local recipe alone is not sufficient. Watch this: once disk crosses ~92%, Flutter/Dart/Melos tools can silently fail with exit 255 and empty output. If a tool fails with exit 255 and produces empty output, run **the exit-255 diagnosis below first** before assuming disk pressure.
- **Exit-255 empty-output diagnosis (before assuming disk failure):** The snap-installed Flutter, Dart, and pub-global Melos shims silently fail with exit code 255 and zero-byte output when stdout is redirected to a regular file (e.g., `flutter --version > /tmp/x.log`). The identical command succeeds when piped (e.g., `flutter --version | cat`) or when written directly to a terminal. If you observe exit 255 with empty output from any of these tools, ALWAYS retry the command piped through `cat` or `tee` before concluding disk pressure or environment breakage. This misdiagnosis has happened at least once in project history; capturing it here to prevent recurrence.
- **AGP 9.1.0: how to apply `com.android.library` from a module's `plugins {}` block (recipe, measured 2026-10-03 during P3-T11).** Reusable for P3-T12–P3-T15 and any future Android library/plugin module here. **To apply AGP 9.1.0's `com.android.library` to a module via `plugins{}`, add a `pluginManagement.resolutionStrategy` mapping `id("com.android.library")` to `com.android.tools.build:gradle:9.1.0` in `settings.gradle.kts` — the plugin marker artifact AGP 9 publishes doesn't resolve otherwise.** Built-in Kotlin (no `org.jetbrains.kotlin.android`) works under this setup; the stock `flutter create --template=plugin` output does **NOT** build standalone against our AGP 9.1.0 pin — it relies on the consuming app's settings file for AGP, and its `java.srcDirs(...)` call is deprecated-as-error under 9.1.0.

  The five attempts below were each run as a real build, not reasoned about; the error strings are verbatim.

  | # | Approach | Outcome |
  |---|---|---|
  | 1 | `plugins { id("com.android.library") version "9.1.0" }` in the module | ✗ `could not resolve plugin artifact 'com.android.library:com.android.library.gradle.plugin:9.1.0'` — AGP 9 publishes no plugin-marker for this id |
  | 2 | bare `plugins { id("com.android.library") }` + module-local `buildscript { classpath(...) }` | ✗ `plugin dependency must include a version number for this source` — Gradle evaluates a script's `plugins {}` **before** that same script's `buildscript {}` |
  | 3 | same, version declared in a `plugins {}` block in `settings.gradle.kts` | ✗ same marker-resolution failure as (1) |
  | 4 | `buildscript { classpath(...) }` + `apply(plugin = "com.android.library")` | ✗ plugin applies, but **25** × `Unresolved reference 'implementation'` — `apply()` generates no Kotlin DSL type-safe accessors |
  | **5** | **`plugins { id("com.android.library") version "9.1.0" }` + `pluginManagement.resolutionStrategy { eachPlugin { … useModule("com.android.tools.build:gradle:${requested.version}") } }` in `settings.gradle.kts`** | ✓ **AGP applies, accessors generated, Kotlin compiles** |

  Two further AGP-9 traps found in the same session, both of which the stock Flutter template walks into:
  - `java.srcDirs("src/main/kotlin")` is deprecated and fails the build (`'fun srcDirs(...)' is deprecated. Use \`directories\` mutable set instead`) — and `directories` exposes no `setFrom` in this DSL version. **No `srcDirs` override is needed at all**: AGP 9 includes `src/main/kotlin` and `src/test/kotlin` by default.
  - A module cannot exclude a single source file from its own Kotlin compile via `exclude(...)`/`java.exclude(...)` in `sourceSets` — both resolve to Gradle's `Configuration.exclude` and fail with `Unresolved reference … receiver type mismatch`.
- **`minSdk` is now 24, overriding P3-T2's `minSdk 21` (human-confirmed, 2026-10-03).** Reason: Flutter's platform-plugin mechanism has a **hard floor of 24**, so remaining at 21 is **not a viable alternative** for ROADMAP P3-T11 AC #3 (the plugin must be resolvable by `apps/mobile`). This is an **external constraint forcing the change, not a preference**, and it supersedes the P3-T2 decision recorded at ROADMAP line ~1801 (`minSdk 21 is a human decision and remains an explicitly-unverified P3-T1 open item`). **The test device (SM-A205F, API 29) is unaffected either way, so our device test suite cannot detect this boundary — do not assume the 36/13 instrumented + host-JVM runs cover it.** Any future device-claim about supported API levels must be verified separately or stated as untested.

---

## 6. Open Questions / Pending Human Decisions

### RESOLVED (human decision, 2026-09-29) — sing-box version: staying on v1.10.7

**Decision: Brick VPN stays on sing-box v1.10.7. The pin does not move.**
Evidence base: the read-only evidence report of 2026-09-28 (no build attempted).

Rationale:

- **The interface cost is essentially zero for our scope.** v1.14.2 adds 14
  `PlatformInterface` methods; **10 of the 14 are Tailscale-SSH and bridge
  surface** (`OpenShellSession`, `LookupUser`, `LookupSFTPServer`,
  `ReadSystemSSHHostKey`, `CheckPlatformShell`, `UsePlatformShell`,
  `TailscaleHostname`, `CancelNotification`, `UsePlatformBridge`,
  `CreateBridge`), which this product does not implement. The remaining 4
  (`StartNeighborMonitor`, `CloseNeighborMonitor`, `RegisterMyInterface`,
  `LocalDNSTransport`) are opt-in L2-neighbour and DNS-transport facilities,
  also unused. **None of the 14 is required for the 6+2-protocol TUN MVP** —
  every one has a benign stub default in
  `experimental/libbox/config.go`.
  *(Correction: an earlier draft of this entry said all 14 were Tailscale/bridge.
  That was wrong — 10 of 14. The conclusion is unchanged, since none of the 14
  is needed either way.)*
- **Upgrading is not cheap.** `go.mod` at v1.14.2 requires **Go 1.25.5** against
  our **1.21.x** pin, and `build_libbox_aar.sh` hard-fails on mismatch; the
  `gomobile v0.1.4` pin was chosen because it is the version v1.10.7 requires
  and would need re-validating.
- **It breaks WireGuard/AmneziaWG.** The WireGuard *outbound* no longer exists
  at >= 1.13 (only `endpoint.go` remains), while
  `singbox_serializer.dart` still emits a WireGuard **outbound**. Moving the
  pin would therefore make that output invalid at runtime
  (`config_parser/README.md`).
- **Migration risk is low but real.** 5 methods are removed, and
  `FindConnectionOwner` changed return type `(int32, error)` ->
  `(*ConnectionOwner, error)` while keeping its name — a silent-breakage hazard
  for anything written against the 18-method table.

**Revisit only if** Tailscale-like features or a WireGuard-endpoint rewrite
become actual roadmap items. The v1.10.x pin is otherwise a standing,
deliberate choice — it is four minor series behind upstream and is **not**
expected to move. Note that v1.10.7 receives no upstream fixes from here on;
that is an accepted consequence of the decision, not an oversight.

### Phase 2 closeout audit — open items and known limits (2026-09-27)

Found by the closeout audit. Each is stated with its evidence so it can be verified, not re-derived.

1. **`config_parser` is no longer a pure, I/O-free package (P2-T10).** The `SubscriptionFetcher`
   adds one `dart:io` import. The package still has zero `package:flutter/` and zero `dart:ui`
   imports and still runs under plain `dart test`, but it is **no longer web-compatible** and no
   longer "pure and deterministic (no I/O)" as the README previously claimed. The fetcher is
   confined to a single file so the parsers stay pure, and the transport is an injectable
   interface, so moving it to a dedicated package later is a clean change. **A reviewer may
   reasonably overrule the placement decision and split it out.** Related: TLS **certificate
   pinning is still deferred** and should be added to the `SECURITY.md` hardening backlog.

2. **Security defect found and FIXED during this audit — echoed untrusted identifiers.**
   `UnsupportedSchemeError`, `UnsupportedProtocolError` and `UnsupportedCipherError` stored a
   caller-supplied token and reproduced it verbatim in `message`. The doc comments assumed the
   token was "a short, non-sensitive token", but nothing enforced that: a payload such as
   `{"type":"<credential>","server":...}` produced `Unsupported protocol: <credential>`, putting a
   secret into a log-bound string (`SECURITY.md` §4 forbids credentials in logs). Fixed by routing
   all three through `sanitiseEchoedIdentifier`, which passes only short, identifier-shaped values
   (`[a-z0-9-]`, <= 32 chars) and otherwise reports a shape mismatch. Covered by
   `packages/config_parser/test/error_redaction_test.dart`. **The underlying assumption — that a
   token field is safe to echo — should be re-checked anywhere else it is made.**

3. **`AmneziaWgOutbound` does not override `==`/`hashCode` — DEFERRED.**
   It inherits identity semantics from `WireGuardOutbound`, so two instances differing *only* in
   obfuscation parameters (`jc`, `jmin`, `jmax`, `s1`, `s2`, `h1`–`h4`) compare equal. This is a
   real correctness bug for any future deduplication or profile-diffing logic. It was **not** fixed
   because the fix requires adding fields or an override to `packages/core_domain`, which is
   strictly frozen. Needs a deliberate unfreeze.

4. **Sing-Box WireGuard outbound is deprecated; an endpoint migration is planned.**
   sing-box deprecated the WireGuard *outbound* in 1.11.0 and documents removal in 1.13.0
   ("Migrate WireGuard outbound to endpoint"). The JSON emitted here is correct for the 1.10/1.11
   schema this client targets. When the client moves to sing-box >= 1.13, WireGuard must be
   modelled as an `endpoint`, not an outbound — a `core_domain` shape change, so it needs its own
   task and an unfreeze.

5. **sing-box has no AmneziaWG schema — runtime AmneziaWG is not supported.**
   None of the nine obfuscation parameters exist in sing-box's WireGuard schema and it rejects
   unknown top-level keys. They are parsed, range-validated and preserved on the domain object
   (`toJson()` namespaces them under `amneziawg_obfuscation`) but are **not** emitted for runtime
   use, because doing so yields a config sing-box refuses to load. Real AWG support needs a patched
   sing-box or a different outbound construct. The `amneziawg://` / `awg://` URI scheme is also
   this project's own invention — no stable AWG link convention exists.

6. **AWG numeric ranges are uncited.** The `jc`/`jmin`/`jmax`/`s1`/`s2`/`h1`–`h4` bounds were
   implemented without a cited live AmneziaWG source during this work. They need checking against
   authoritative AmneziaWG documentation before being relied on.

7. **WireGuard private-key transport had to be handled defensively.** A base64 key contains
   `+`, `/` and `=`, any of which corrupts a URI's authority component, so a raw key in the
   userinfo position makes the link unparseable. The parsers accept either a percent-encoded
   userinfo or a `private_key` query parameter (query wins). Real-world clients are inconsistent
   here, so both forms are supported deliberately.

8. **`brick://` deep links are not registered with the OS.** `parseConfigContent` implements and
   tests the `brick://import?url=...` / `?config=...` contract, but
   `apps/mobile/android/app/src/main/AndroidManifest.xml` has no intent-filter for the scheme, so
   Android will not route such a link into the app. It is reachable from clipboard / in-app paste
   only until that Android wiring is added.

9. **Smart-router multi-entry detection is newline-based.** A body of several URIs joined by any
   separator other than a newline is routed as a single URI and fails with a syntax error instead
   of being split. Base64 bodies (no `://` at all) are handled correctly by falling through to the
   subscription decoder.

10. **The Sing-Box serializer's AmneziaWG handling is order-dependent.** `tryBuild` sets
   `'type': config.protocol.name` (which is `amneziawg` for an AWG outbound) and then
   `out.addAll(map)`, where the WireGuard branch supplies `'type': 'wireguard'`, which overwrites
   it. The result is correct, but the correctness depends on that overwrite order. There is a test
   pinning `json['type'] == 'wireguard'`; a future refactor that reorders these lines would
   silently emit `"type": "amneziawg"`, which sing-box would reject.

### Phase 1 closeout — open items (2026-09-26)

These are the specific reasons Phase 1 is **not** declared 100% closed. Each is stated with the
evidence that established it, so the next agent can verify rather than re-derive.

1. **The app has never been run on a real Android device or emulator.** This leaves four
   acceptance-criteria boxes unchecked (P1-T7, P1-T8, P1-T10, P1-T11). Evidence:
   `flutter devices` lists only Linux and Chrome; `adb devices -l` is empty; `lsusb` shows no
   Android/Samsung USB device; `flutter emulators` reports no emulators available. Additionally,
   `assembleDebug` cannot complete in this environment because the `io.flutter:*_debug` engine
   artifacts are neither cached nor downloadable — `storage.googleapis.com` is unreachable
   (curl times out) while `github.com` and `pub.dev` both return HTTP 200. **Until a human runs the
   > **P3-T6 UPDATE (2026-09-30) — partly superseded.** The *evidence above* is no longer true:
   > a real Android device is now attached (`RZ8M53WPMPF`, Samsung SM-A205F, API 29) and
   > `./gradlew connectedAndroidTest` passed 4/4 on it. What this item still blocks is the
   > **Flutter app** (`apps/mobile`), not the native harness: the `storage.googleapis.com`
   > engine-artifact problem above is unrelated to the device and remains unresolved, so
   > P1-T7/T8/T10/T11 (all Flutter-side) are still genuinely open. Only the native Gate A
   > harness has now been proven on hardware.
   app on a device, the routing, localization, and Riverpod wiring are proven only by widget tests,
   never on a real target.**
2. **RETIRED — the earlier "`melos run <script>` hangs" reports were a FALSE POSITIVE.**
   Re-verified 2026-09-27: a full, non-detached `melos run test --no-select` completes
   successfully in well under 3 minutes, with both steps reporting `SUCCESS`
   (`test:dart` → `SUCCESS`, `test:flutter` → `SUCCESS`, final line `SUCCESS`, exit 0).
   `melos run analyze --no-select` and `melos run format --no-select` likewise complete.
   The original "12+ minute hang" observation was an artifact of launching Melos detached
   (`nohup`/`setsid`) and polling: the child process was reaped when the tool call returned, so an
   empty log was misread as a hang. There is no environmental Melos problem. Per-package
   commands remain useful for isolating a failure, but the canonical `DEFINITION_OF_DONE.md`
   Section 3 check (`melos run format|analyze|test`) is fully satisfiable and is now satisfied.
3. **CI has not validated any of the P1-T5..P1-T11 work**, because it is all still uncommitted. The
   P1-T11 criterion "CI is green on master" is left unchecked for that reason, not because a red run
   was observed.
4. **`redact()` is a no-op stub** (see §4). `SECURITY.md` Section 4's redaction requirement is
   structurally in place — `AppLogger` routes every message through it — but nothing is actually
   masked at runtime. Deliberately deferred to Phase 8, and recorded so it is not forgotten.
5. **Governance drift found during the closeout, not fixed here:** `ARCHITECTURE.md` Section 3.2
   still lists a `Reconnecting` `ConnectionState` variant that was never implemented. Separately, the
   "N1–N10" invariant labels referenced in several task briefs do not exist anywhere in `AI_ROLES/`
   (Section 3.5's ten unnumbered bullets are the real source). Both are documentation-only and were
   left alone rather than silently rewritten.


6. **Dependabot PR #1:** An automated PR to update GitHub Actions remains open and requires a human decision (merge/close).
7. **Dependabot pub failures:** 6 automated dependency updates failed on Dependabot's dynamic run on 2026-09-17 (`apps/mobile`, `core_domain`, `core_vpn_engine`, `config_parser`, `shared_utils`, `ui_theme`) due to monorepo package resolution errors. Non-blocking for local development, but worth noting for automation health.
8. **Pre-P1-T3 competitive research completed (informational, no decision pending):** Four independent AI agents surveyed sing-box protocol documentation, Hiddify implementation, and Iranian VPN user community reports (2025-2026 blackouts). Three agents converged on the same protocol config architecture: a base `sealed OutboundConfig` with family sealed sub-classes (`TcpBasedOutbound`, `QuicBasedOutbound`, standalone `ShadowsocksOutbound`) plus shared composition types (`TlsSettings`, `TransportSettings`, `QuicSettings`, `MultiplexSettings`, `RealitySettings`). Findings including field surveys, competitive gaps, and Iranian censorship-blackout scenarios (dnstt fallback, TLS Fragment, Chrome QUIC parroting) are documented in `AI_ROLES/COMPETITIVE_RESEARCH.md` (see AI_ROLES/COMPETITIVE_RESEARCH.md). This research informed P1-T3's architecture choices before implementation began.

### Known deviations (accepted, not to be fixed)

0. **(2026-09-28) P3-T1 pinned Go 1.20 from `go.mod` alone; P3-T3 corrected it to
   1.21.x.** Evidence trail, recorded rather than amended:
   P3-T1 commit `c6ab7cc` changed exactly one file (`AI_ROLES/TOOLCHAIN_VERSIONS.md`,
   +193/-22) and ran **no build at all**, so the pin rested entirely on reading the
   `go` directive in sing-box v1.10.7's `go.mod` (`go 1.20`). P3-T3's first
   `gomobile bind` then failed with
   `command_connections.go:6:2: package slices is not in GOROOT`, because
   `experimental/libbox/command_connections.go:6` imports the stdlib `slices`
   package, which only entered GOROOT in Go 1.21. Corrected to Go 1.21.13
   (sha256-verified download, human-approved) and re-proven by a clean
   end-to-end rebuild producing a 48 MB `libbox.aar` with arm64 LOAD segments
   at `0x4000`. **Lesson, carried forward: a `go` directive is a floor, not a
   build recipe — a pin that was never exercised is a hypothesis.** See
   `TOOLCHAIN_VERSIONS.md` §"Go version (verified by build)".
1. **P1-T5 commit `45b7c85` violated conventional-commit format** (its whole multi-line body was committed as the subject line, so the subject begins `- In-memory VpnEngine…` instead of `feat:`/`docs:`). Because it is already pushed to `origin/master` and branch protection forbids force-push, and because rewriting published history is permanently prohibited for agents, this is accepted as a permanent historical deviation and **must not be amended**. All subsequent commits should use a conventional subject.
2. **Commit `586908c` bundles P1-T6 and P1-T7's output under a subject labelled only
   "(P1-T8)"** — `git log --oneline -- apps/mobile/lib/features/README.md` and
   `-- apps/mobile/lib/core/providers/vpn_engine_provider.dart` both resolve to that single
   commit, so no dedicated commit exists for T6 or T7 individually. Accepted as historical and
   **not to be split retroactively** (that would require a history rewrite, which is permanently
   prohibited for agents).
3. **Commit `2a1bb4c` ("Add SECURITY.md to define security architecture and
   policies for Brick VPN") does not follow conventional-commit format** — the subject
   begins with a capitalised imperative and no `type:` prefix. It is also the commit that
   introduced the ROADMAP, and therefore the commit that every `Not Started` status line
   from Phase 2 onward still traces back to. Accepted as historical, for the same reason
   as `45b7c85` and `f1245e9`. Recorded here so the count of non-conventional subjects is
   complete rather than silently understated.

4. **Commit `f1245e9` ("updating and fixing CODING_STANDARDS") does not follow
   conventional-commit format**, violating the rule established after `45b7c85`. It touches only
   `AI_ROLES/CODING_STANDARDS.md`. Accepted as historical for the same reason as above. All
   subsequent commits must use a conventional subject.
5. **`AppLogger.e()`'s `error` and `stackTrace` parameters bypass `redact()`.** Only the
   `message` parameter is redacted (structurally, via the single `_emit` chokepoint). An `Object`
   passed as `error` is attached to the log unredacted. Currently harmless because no domain
   type has a `toString` override, so accidental interpolation cannot emit a credential — but it
   is a real seam. **Open item for whoever implements real redaction in Phase 8**: route `error`
   through `redact` too, or document the exclusion as accepted.

6. **`packages/shared_utils/lib/src/result.dart` equality is stricter than payload-only comparison.** `Ok`/`Err` check `other.runtimeType == runtimeType`, so `Ok<int,String>(1)` is not equal to `Ok<num,Object>(1)`. This was deliberately **NOT** changed: simply dropping the `runtimeType` check would make equality **asymmetric** under Dart's covariant generics (one direction true, the other false), violating the `==` contract — a worse defect than being over-strict but symmetric. Documented as an accepted limitation, not a bug to fix.

7. **(2026-10-02) RISK — sing-box v1.10.7's `BoxService.Close()` calls `os.Exit(1)` on a
   `C.FatalStopTimeout` internally** (confirmed in pinned source during P3-T7). This means a hung
   libbox close can kill the entire app process, and our own 5000ms stop watchdog
   (`VpnStateMachine`) cannot intervene — it operates at the Kotlin level, above a process-kill.
   No mitigation exists yet; revisit during Phase 7 stability work (process-level supervision /
   restart strategy). Evidence: `experimental/libbox/service.go`, `func (s *BoxService) Close()`,
   pinned commit `253b41936ecd6ae17948d49d9c510d7100830927` —
   `select { case <-done: return err; case <-time.After(C.FatalStopTimeout): os.Exit(1) }`.

---

### Status provenance under human review (2026-09-28)

A governance integrity sweep (CI-restoration task, Part 1) ran `git blame` over the Status
line of every Phase 0–2 task in `ROADMAP.md` to establish *who wrote each `Completed`*. The
result is a provenance table held in that task's report. Its headline findings, stated here
without changing any ROADMAP status:

- **Phase 0 (P0-T1..T12):** all twelve trace to separate `docs:`-only commits, several of
  them explicitly titled "… after human review". This is the *correct* provenance pattern.
- **Phase 1 (P1-T1..T5):** statuses were written by separate `docs:` commits
  (`5120833`, `6b63ec6`, `300839c`, `896b060`) — correct pattern — **except P1-T5**, whose
  Status line was last written by `a0c2f8e`, the **same commit that added the
  `MockVpnEngine` code**. That is a probable agent self-mark (Class B).
- **Phase 2 (P2-T1..T8, T13, T14, T10, T11):** every `Completed` Status line was written by
  the **same commit that also changed `packages/` code**, i.e. an agent self-marked each task
  complete in the commit that implemented it (Class B). P2-T11's Status is additionally
  **uncommitted working-tree text** written by an agent (Class C). None of the Phase 2
  `Completed` statuses came from a later human sign-off commit.
- A task prompt had also instructed an agent to mark P2-T11 "Completed", which conflicts with
  `DEFINITION_OF_DONE.md` §1 ("An AI agent MUST NOT mark a task as `Completed` by itself").

**No ROADMAP Status was changed in response to these findings.** The human decides whether to
downgrade any of them to "Ready for Human Review — sign-off pending". This block exists so the
decision is made from evidence rather than from a doc that merely asserts the outcome.

### `core_domain` freeze exceptions A1 + A2 (2026-09-28), and re-freeze

The `core_domain` freeze was **temporarily lifted for exactly two, human-authorized changes**
and is **RE-FROZEN** immediately afterwards:

- **A1 — formatting-only:** `packages/core_domain/test/protocol_type_test.dart` and
  `packages/core_domain/test/wireguard_outbound_test.dart` (the two files that had been
  committed unformatted, turning CI red).
- **A2 — the AmneziaWgOutbound equality fix:** `packages/core_domain/lib/src/outbound_config.dart`
  (adds `==`/`hashCode` overrides covering the nine AWG parameters) plus the new
  `packages/core_domain/test/amneziawg_equality_test.dart`.

No other file under `packages/core_domain/` was modified. Nothing else in the frozen package
required change; if something does in future, it needs its own explicit authorization.

---

## 7. Immediate Next Steps (In Order)

1. Human: **restore CI on `master`.** `master` is currently RED — the last four push runs
   failed on the "Check formatting" job (see §3). A formatting-only fix is prepared and
   verified locally (the full CI step sequence now passes end to end), but it is **not on CI
   until the human commits and pushes**. Suggested commit split: (1) `style:` formatting,
   (2) `fix(core_domain):` AmneziaWg equality, (3) `test:` serializer lock-in,
   (4) `docs:` PROJECT_STATE sync. After pushing, re-check with
   `gh run list --branch master --event push`.
   Also uncommitted: the whole P2-T6..P2-T11 body of work (17 files total in the working
   tree, of which 13 are modified and 3 are new, plus this task's edits) — none of it has
   been seen by CI yet.
2. Human: run the app on a real Android device/emulator. Still the highest-value outstanding
   verification action: it closes the four unchecked device-run acceptance criteria from P1-T7/T8/T10
   and is the only way to confirm routing, localization, and Riverpod wiring on a real target.
   (`assembleDebug` additionally needs `storage.googleapis.com` reachable to resolve the
   `io.flutter:*_debug` engine artifacts.)
3. Human: confirm CI is green on `master` once the above is committed.
4. Agent (P2-T9): reconcile the ROADMAP’s subscription-content-parser scope against what already
   shipped (decoder, `Subscription-Userinfo`, fault-tolerant bulk parser are implemented) before
   writing new code — the remaining scope is likely smaller than the task text implies.