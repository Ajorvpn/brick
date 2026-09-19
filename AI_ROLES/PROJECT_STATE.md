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

**Last updated**: 2026-09-19 — Phase 1 Transition (P1-T1 closeout, Melos script refactor)
**Updated by**: Coding agent, following a strict read-only audit verifying remote master state

---

## 1. Current Phase

**Phase 1 — Architecture Skeleton: IN PROGRESS (P1-T1 complete; P1-T2 is the next task to begin).**

Phase 0 (Project Foundation & Governance Setup) is 100% completed, committed, and signed off.
The project has successfully transitioned into Phase 1. The baseline primitive `Result<T, E>` (P1-T1) has been fully implemented, tested, and integrated. Melos test routing has been refactored to support pure-Dart and Flutter testing paths natively and deterministically.

---

## 2. Active Phase 1 Task Status (quoted from `AI_ROLES/ROADMAP.md`)

Status tokens below are quoted verbatim from the corresponding `**Status:**` line in `AI_ROLES/ROADMAP.md`.

- **P1-T1** (`ROADMAP.md:564`): `Completed ✅` — Hand-written `Result<T, E>` implemented in `packages/shared_utils` with 10 standalone unit tests passing. Pushed and merged to master.
- **P1-T2** (`ROADMAP.md:599`): `Not Started` — "Core domain entities: connection state and traffic stats" under packages/core_domain (this is the next planned task; work has not yet begun in the file).
- **P1-T3** (`ROADMAP.md:642`): `Not Started` — Server profile domain model.
- **P1-T4** (`ROADMAP.md:679`): `Not Started` — VpnEngine abstract interface and supporting command/result types.

---

## 3. What Exists Right Now (Verified)

### Code & Architecture Skeleton
- **`packages/shared_utils/` (Pure Dart, verified):** Retroactively corrected P0-T6's scaffolding by removing all Flutter SDK transitives. Contains a hand-written, sealed `Result<T, E>` primitive with `Ok` and `Err` final subclasses (value-equality with `identical` fast path, intentionally no `toString` override so sensitive error payloads are not printed by default, `map`/`mapErr` transforms, and exhaustive `fold`/pattern-matching). Tested with 10 standalone unit tests running under `dart test`.
- **`apps/mobile` (Flutter, wired):** Base dependencies resolved and pinned (`riverpod`, `riverpod_annotation`, `riverpod_generator`, `build_runner`, `go_router`, `easy_localization`, `logger`, `very_good_analysis`). Contains standard boilerplate tests.
- **Melos Workspace (6 packages):** Configured via root `pubspec.yaml` list and individual package `resolution: workspace` settings.
- **Deterministic Test Routing (Refactored):** Root `pubspec.yaml` Melos `test` script was refactored into a composite script that dispatches tests to:
  * `test:dart` (`melos exec -- dart test`): routes pure-Dart packages (`shared_utils`) via an allowlist (`scope:`).
  * `test:flutter` (`melos exec -- flutter test`): routes Flutter-dependent packages via a denylist (`ignore:`).
  * This ensures pure-Dart packages are tested natively with plain `dart test` (5.8s real time) rather than relying on undocumented Flutter fallback behavior (13.8s real time).

### Repository & CI
- **Git HEAD:** Match confirmed between local `master` and live remote `origin/master` at commit `f197932b438fa681f19fca3bce9b28c64f236e7a`.
- **CI Status:** GitHub Actions CI is green on `master` (runs `35461569805` and `35456305742` completed successfully).
- **Branch Protection:** Active on remote `master` via GitHub UI (no force-push, no deletion).
- **Vulnerability Scanners:** GitHub secret scanning, push protection, and Dependabot are active.
- **Tracked logs:** Phase 0 closeout report is committed and tracked in `AI_ROLES/logs/phase-0-closeout-2026-09-17.md`.

---

## 4. What Does NOT Exist Yet

- Real domain models for `core_domain` (`ConnectionState`, `TrafficStats`, `ServerProfile` — being built in P1-T2/P1-T3).
- `VpnEngine` contract interface (`core_vpn_engine` — P1-T4) or its mock implementation (`P1-T5`).
- Android native integration (`VpnService`, `libbox` JNI bridge) — deferred to Phase 3.
- Clean Linux desktop toolchain (missing locally: clang, cmake, ninja, pkg-config; deferred to Phase 12).

---

## 5. Environment & Toolchain Notes

- **Verified toolchain pins:** Flutter 3.47.4 stable, Dart 3.13.3, Melos 8.7.0, Git 2.43.0. Do not change any pinned version as a side effect of another task.
- **Local Gradle init-script footgun (must stay disabled):** `/home/e60/.gradle/init.d/iran-mirrors.gradle.disabled` must remain disabled to prevent settings-repository conflicts in Android Gradle builds.
- **Disk pressure warning:** Disk `/` is at 83% capacity (16 GB available). Caches are growing (`apps/mobile/build` is 1.1 GB). Keep an eye on disk capacity to prevent silent Flutter/Melos tool failures (exit 255) when crossing 92%.

---

## 6. Open Questions / Pending Human Decisions

1. **Dependabot PR #1:** An automated PR to update GitHub Actions remains open and requires a human decision (merge/close).
2. **Dependabot pub failures:** 6 automated dependency updates failed on Dependabot's dynamic run on 2026-09-17 (`apps/mobile`, `core_domain`, `core_vpn_engine`, `config_parser`, `shared_utils`, `ui_theme`) due to monorepo package resolution errors. Non-blocking for local development, but worth noting for automation health.

---

## 7. Immediate Next Steps (In Order)

1. Human: commit and push these governance updates.
2. Agent (P1-T2): Begin migrating `packages/core_domain` to pure Dart:
   - Remove `flutter` dependencies from its `pubspec.yaml` and add `test: ^1.31.1`.
   - Update its placeholder tests to import `package:test/test.dart` instead of `flutter_test`.
   - Add `core_domain` to root `pubspec.yaml`'s `test:dart` (`scope`) allowlist **and** `test:flutter` (`ignore`) denylist in the same commit.
   - Implement `ConnectionState`, `ConnectionErrorReason`, and `TrafficStats` as pure-Dart immutable models with comprehensive tests.
