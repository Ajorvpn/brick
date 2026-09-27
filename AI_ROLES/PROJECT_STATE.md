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

**Last updated**: 2026-09-26 — Phase 1 progress (P1-T5 hardened and verified, staged for human commit; 147 pure-Dart tests green)
**Updated by**: Coding agent, after P1-T5 hardening + governance sync; all counts re-verified against live test/analyzer runs

---

## 1. Current Phase

**Phase 2 — Config & Protocol Parsers: P2-T1 through P2-T8 are implemented and verified. P2-T5's
final piece (Shadowsocks cipher validation) landed with the most recent work. Phase 2 is NOT
closed — P2-T9..P2-T12 remain, and §6 records the open items.**

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

**Closeout measurements (2026-09-26, all re-run at audit time):**
- **346 tests pass monorepo-wide (322 pure-Dart + 24 Flutter).** Pure-Dart: `shared_utils` 15,
  `core_domain` 94, `core_vpn_engine` 43, `config_parser` 170. Flutter: `mobile` 23, `ui_theme` 1.
  (Supersedes the earlier "175 tests / 152 pure-Dart" Phase-1 closeout figure and the "258
  pure-Dart" figure quoted in Phase-2 handoffs; both were stale.)
- `flutter analyze .` — 0 errors, 0 warnings, 0 lints across all 6 packages.
- `dart format --set-exit-if-changed` — 0 changed files across all 6 packages.
- **Pure-Dart isolation re-verified:** 0 `package:flutter/*` and 0 `dart:ui` imports in
  `shared_utils`, `core_domain`, and `core_vpn_engine`; all three run under plain `dart test`.

**This phase is not "zero technical debt."** Known open items are listed in §6. The most
consequential: the device-run acceptance criteria for P1-T7/T8/T10/T11 were never executed
(no Android device was available), and `redact()` is a documented no-op stub until Phase 8.

## 2. Active Phase 1 Task Status (quoted from `AI_ROLES/ROADMAP.md`)

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
- **CI Status:** GitHub Actions CI is green on the current `master` HEAD. Historical runs are visible via `gh run list --branch master`. Any red run must be investigated before the next task begins.
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
- Clean Linux desktop toolchain (missing locally: clang, cmake, ninja, pkg-config; deferred to Phase 12).

---

## 5. Environment & Toolchain Notes

- **Verified toolchain pins:** Flutter 3.47.4 stable, Dart 3.13.3, Melos 8.7.0, Git 2.43.0. Do not change any pinned version as a side effect of another task.
- **Local Gradle init-script footgun (must stay disabled):** `/home/e60/.gradle/init.d/iran-mirrors.gradle.disabled` must remain disabled to prevent settings-repository conflicts in Android Gradle builds.
- **Disk pressure — standing gate item:** Disk `/` fluctuates as build/tool caches accumulate. As measured on 2026-09-25, `/` is at **86% (14 GB free)**, which is **below** the project's documented ~92% danger threshold. A manual cache cleanup was performed by the human maintainer between the 2026-09-22 forensic audit (which recorded 95% / 4.9 GB free — above the danger line) and this entry; this agent did not run the purge itself. Safe repo-local recipe if needed: `rm -rf apps/mobile/build packages/*/build .dart_tool apps/mobile/.dart_tool packages/*/.dart_tool` then `melos bootstrap`. Note the largest consumers on this machine are outside the repo (`~/.gradle` and `~/Android`, measured at 8.4 GB and 8.8 GB respectively on 2026-09-22), so the repo-local recipe alone is not sufficient. Watch this: once disk crosses ~92%, Flutter/Dart/Melos tools can silently fail with exit 255 and empty output. If a tool fails with exit 255 and produces empty output, run **the exit-255 diagnosis below first** before assuming disk pressure.
- **Exit-255 empty-output diagnosis (before assuming disk failure):** The snap-installed Flutter, Dart, and pub-global Melos shims silently fail with exit code 255 and zero-byte output when stdout is redirected to a regular file (e.g., `flutter --version > /tmp/x.log`). The identical command succeeds when piped (e.g., `flutter --version | cat`) or when written directly to a terminal. If you observe exit 255 with empty output from any of these tools, ALWAYS retry the command piped through `cat` or `tee` before concluding disk pressure or environment breakage. This misdiagnosis has happened at least once in project history; capturing it here to prevent recurrence.

---

## 6. Open Questions / Pending Human Decisions

### Phase 1 closeout — open items (2026-09-26)

These are the specific reasons Phase 1 is **not** declared 100% closed. Each is stated with the
evidence that established it, so the next agent can verify rather than re-derive.

6. **The app has never been run on a real Android device or emulator.** This leaves four
   acceptance-criteria boxes unchecked (P1-T7, P1-T8, P1-T10, P1-T11). Evidence:
   `flutter devices` lists only Linux and Chrome; `adb devices -l` is empty; `lsusb` shows no
   Android/Samsung USB device; `flutter emulators` reports no emulators available. Additionally,
   `assembleDebug` cannot complete in this environment because the `io.flutter:*_debug` engine
   artifacts are neither cached nor downloadable — `storage.googleapis.com` is unreachable
   (curl times out) while `github.com` and `pub.dev` both return HTTP 200. **Until a human runs the
   app on a device, the routing, localization, and Riverpod wiring are proven only by widget tests,
   never on a real target.**
7. **RETIRED — the earlier "`melos run <script>` hangs" reports were a FALSE POSITIVE.**
   Re-verified 2026-09-27: a full, non-detached `melos run test --no-select` completes
   successfully in well under 3 minutes, with both steps reporting `SUCCESS`
   (`test:dart` → `SUCCESS`, `test:flutter` → `SUCCESS`, final line `SUCCESS`, exit 0).
   `melos run analyze --no-select` and `melos run format --no-select` likewise complete.
   The original "12+ minute hang" observation was an artifact of launching Melos detached
   (`nohup`/`setsid`) and polling: the child process was reaped when the tool call returned, so an
   empty log was misread as a hang. There is no environmental Melos problem. Per-package
   commands remain useful for isolating a failure, but the canonical `DEFINITION_OF_DONE.md`
   Section 3 check (`melos run format|analyze|test`) is fully satisfiable and is now satisfied.
8. **CI has not validated any of the P1-T5..P1-T11 work**, because it is all still uncommitted. The
   P1-T11 criterion "CI is green on master" is left unchecked for that reason, not because a red run
   was observed.
9. **`redact()` is a no-op stub** (see §4). `SECURITY.md` Section 4's redaction requirement is
   structurally in place — `AppLogger` routes every message through it — but nothing is actually
   masked at runtime. Deliberately deferred to Phase 8, and recorded so it is not forgotten.
10. **Governance drift found during the closeout, not fixed here:** `ARCHITECTURE.md` Section 3.2
   still lists a `Reconnecting` `ConnectionState` variant that was never implemented. Separately, the
   "N1–N10" invariant labels referenced in several task briefs do not exist anywhere in `AI_ROLES/`
   (Section 3.5's ten unnumbered bullets are the real source). Both are documentation-only and were
   left alone rather than silently rewritten.


1. **Dependabot PR #1:** An automated PR to update GitHub Actions remains open and requires a human decision (merge/close).
2. **Dependabot pub failures:** 6 automated dependency updates failed on Dependabot's dynamic run on 2026-09-17 (`apps/mobile`, `core_domain`, `core_vpn_engine`, `config_parser`, `shared_utils`, `ui_theme`) due to monorepo package resolution errors. Non-blocking for local development, but worth noting for automation health.
3. **Pre-P1-T3 competitive research completed (informational, no decision pending):** Four independent AI agents surveyed sing-box protocol documentation, Hiddify implementation, and Iranian VPN user community reports (2025-2026 blackouts). Three agents converged on the same protocol config architecture: a base `sealed OutboundConfig` with family sealed sub-classes (`TcpBasedOutbound`, `QuicBasedOutbound`, standalone `ShadowsocksOutbound`) plus shared composition types (`TlsSettings`, `TransportSettings`, `QuicSettings`, `MultiplexSettings`, `RealitySettings`). Findings including field surveys, competitive gaps, and Iranian censorship-blackout scenarios (dnstt fallback, TLS Fragment, Chrome QUIC parroting) are documented in `AI_ROLES/COMPETITIVE_RESEARCH.md` (see AI_ROLES/COMPETITIVE_RESEARCH.md). This research informed P1-T3's architecture choices before implementation began.

### Known deviations (accepted, not to be fixed)

4. **P1-T5 commit `45b7c85` violated conventional-commit format** (its whole multi-line body was committed as the subject line, so the subject begins `- In-memory VpnEngine…` instead of `feat:`/`docs:`). Because it is already pushed to `origin/master` and branch protection forbids force-push, and because rewriting published history is permanently prohibited for agents, this is accepted as a permanent historical deviation and **must not be amended**. All subsequent commits should use a conventional subject.
6. **Commit `586908c` bundles P1-T6 and P1-T7's output under a subject labelled only
   "(P1-T8)"** — `git log --oneline -- apps/mobile/lib/features/README.md` and
   `-- apps/mobile/lib/core/providers/vpn_engine_provider.dart` both resolve to that single
   commit, so no dedicated commit exists for T6 or T7 individually. Accepted as historical and
   **not to be split retroactively** (that would require a history rewrite, which is permanently
   prohibited for agents).
7. **Commit `f1245e9` ("updating and fixing CODING_STANDARDS") does not follow
   conventional-commit format**, violating the rule established after `45b7c85`. It touches only
   `AI_ROLES/CODING_STANDARDS.md`. Accepted as historical for the same reason as above. All
   subsequent commits must use a conventional subject.
8. **`AppLogger.e()`'s `error` and `stackTrace` parameters bypass `redact()`.** Only the
   `message` parameter is redacted (structurally, via the single `_emit` chokepoint). An `Object`
   passed as `error` is attached to the log unredacted. Currently harmless because no domain
   type has a `toString` override, so accidental interpolation cannot emit a credential — but it
   is a real seam. **Open item for whoever implements real redaction in Phase 8**: route `error`
   through `redact` too, or document the exclusion as accepted.

5. **`packages/shared_utils/lib/src/result.dart` equality is stricter than payload-only comparison.** `Ok`/`Err` check `other.runtimeType == runtimeType`, so `Ok<int,String>(1)` is not equal to `Ok<num,Object>(1)`. This was deliberately **NOT** changed: simply dropping the `runtimeType` check would make equality **asymmetric** under Dart's covariant generics (one direction true, the other false), violating the `==` contract — a worse defect than being over-strict but symmetric. Documented as an accepted limitation, not a bug to fix.

---

## 7. Immediate Next Steps (In Order)

1. Human: review and commit the Phase 2 work as ONE clean commit — P2-T5 (Hysteria2/TUIC parsers,
   Sing-Box serializer support for them, the `parseUri` router wiring) plus this task’s cipher
   validation, duplicate-line removal, and governance sync. 9 files are currently uncommitted and
   have never been seen by CI.
2. Human: run the app on a real Android device/emulator. Still the highest-value outstanding
   verification action: it closes the four unchecked device-run acceptance criteria from P1-T7/T8/T10
   and is the only way to confirm routing, localization, and Riverpod wiring on a real target.
   (`assembleDebug` additionally needs `storage.googleapis.com` reachable to resolve the
   `io.flutter:*_debug` engine artifacts.)
3. Human: confirm CI is green on `master` once the above is committed.
4. Agent (P2-T9): reconcile the ROADMAP’s subscription-content-parser scope against what already
   shipped (decoder, `Subscription-Userinfo`, fault-tolerant bulk parser are implemented) before
   writing new code — the remaining scope is likely smaller than the task text implies.