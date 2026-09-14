# PROJECT_STATE.md — Current Snapshot

> This file reflects the CURRENT state of the project only. It is not a
> history log (task-by-task history, if needed, lives in Git commit
> history and each task's final report — not here). Every AI agent must
> read this file first, before `ARCHITECTURE.md` or `ROADMAP.md`, to get
> immediate situational awareness. This file must be updated at the end
> of every task, per `DEFINITION_OF_DONE.md` Section 7.

**Last updated**: Phase 0, initial repository scaffolding
**Updated by**: Human maintainer + planning session (no coding agent task executed yet)

---

## 1. Current Phase

**Phase 0 — Project Foundation & Governance Setup**

We are still inside Phase 0. No application code, no domain logic, no
native code, and no UI has been written yet. Everything so far is
repository scaffolding and governance documentation.

---

## 2. What Exists Right Now (Verified, Working)

- Git repository initialized at `~/Documents/Code/brick-vpn`.
- Melos-based monorepo scaffolded and verified working:
  - Root `pubspec.yaml` uses Dart Native Workspace (`workspace:` field).
  - `melos.yaml` configured with `analyze`, `format`, `test` scripts.
  - `apps/mobile` — a fresh, untouched `flutter create` default app
    (org: `dev.brickvpn`), confirmed bootstrapped successfully via
    `melos bootstrap` (`1 packages bootstrapped`).
  - `melos list` correctly shows `mobile` as a recognized workspace package.
- Folder structure created (mostly empty, placeholders only):
brick-vpn/
├── apps/mobile/ # default Flutter scaffold, unmodified
├── packages/ # empty — no packages created yet
├── native/
│ ├── android/ # empty
│ ├── ios/ # empty
│ └── desktop/ # empty
├── AI_ROLES/
│ └── logs/ # empty
├── melos.yaml
├── pubspec.yaml
└── .gitignore

text

- `AI_ROLES/` governance documents completed so far:
- [x] `ARCHITECTURE.md`
- [x] `AGENTS.md`
- [x] `CODING_STANDARDS.md`
- [x] `DEFINITION_OF_DONE.md`
- [x] `SECURITY.md`
- [x] `MCP_MEMORY_GUIDE.md`
- [x] `PROJECT_STATE.md` (this file)
- [ ] `ROADMAP.md` — **not yet written, next immediate step**

---

## 3. Environment Notes (Verified on This Machine)

- OS: Ubuntu 24.04.4 LTS
- Flutter: 3.47.4 (stable channel)
- Dart SDK: 3.13.3
- Melos: 8.7.0 (installed via `dart pub global activate melos`)
- `flutter doctor` status:
- [x] Flutter toolchain OK
- [x] Android toolchain OK (Android SDK 36.1.0) — ⚠️ warning: multiple
  `adb` binaries detected (`~/Android/Sdk/platform-tools/adb` and
  `/usr/lib/android-sdk/platform-tools/adb`). Not yet resolved. Low
  priority — revisit if device connection issues occur.
- [x] Chrome (web) OK — web is not a target platform for this project,
  noted only because `flutter doctor` reports it.
- [ ] Linux desktop toolchain — **not installed** (`clang++`, `CMake`,
  `ninja`, `pkg-config` missing). Intentionally deferred; only required
  starting at the Desktop phase (Phase 12), not before.
- [x] Connected device — at least one physical Android device (or
  equivalent) detected as available for testing.

### Known Environment Gotcha (Documented in `ARCHITECTURE.md` Section 2.1)

Melos 8.x requires **both**:
1. A `workspace:` field in the root `pubspec.yaml` explicitly listing
 every package path.
2. `resolution: workspace` inside every individual package's own
 `pubspec.yaml`.

Omitting either causes `melos list` / `melos bootstrap` to silently report
`0 packages bootstrapped` with no clear error. This was already hit once
and resolved during initial scaffolding — any new package added to this
repo must follow this pattern from the start.

---

## 4. What Does NOT Exist Yet (Do Not Assume)

- No `packages/core_domain`, `packages/core_vpn_engine`,
`packages/config_parser`, `packages/ui_theme`, or
`packages/shared_utils` have been created yet — these are all still
just directories/decisions in `ARCHITECTURE.md`, not real code.
- No native Android/Kotlin code exists yet (`native/android` is empty).
- No Riverpod, go_router, very_good_analysis, easy_localization, or any
other planned dependency has been added to `apps/mobile/pubspec.yaml`
yet — it is still the unmodified default Flutter template.
- No CI/CD (GitHub Actions) workflow exists yet.
- No `libbox` AAR or sing-box integration exists yet.
- Memory MCP has **not** been installed, configured, or verified yet
(see `MCP_MEMORY_GUIDE.md` Section 5 — the verification task is still
pending and tracked as an upcoming Phase 0 task).
- No license file, README content, or public-facing documentation has
been written yet.
- No UI/UX design work has started (intentionally deferred to Phase 11
per `ARCHITECTURE.md`).

---

## 5. Immediate Next Steps (In Order)

1. Write `AI_ROLES/ROADMAP.md` — the full phase-by-phase, task-by-task
 plan (Phase 0 through Phase 10 in fine detail; Phases 11–14 at a
 higher level, to be expanded when reached).
2. Begin executing Phase 0 remaining tasks from the roadmap, expected to
 include (exact list to be finalized in `ROADMAP.md`):
 - Memory MCP installation + verification task.
 - GitHub repository creation, initial push, branch protection,
   Dependabot/secret-scanning enablement (per `SECURITY.md` Section 11).
 - Base dependency setup in `apps/mobile/pubspec.yaml` (Riverpod,
   go_router, very_good_analysis, easy_localization, logger).
 - GitHub Actions CI workflow (lint + analyze + test on push/PR).
 - `packages/` skeletons created with correct workspace configuration.

---

## 6. Open Questions / Pending Human Decisions

- Final decision on open-source license file wording/CLA (if any) —
GPL v3 direction agreed, exact `LICENSE` file not yet added.
- Whether Memory MCP is actually usable in the specific coding
agent/tool the maintainer will use for implementation — unverified
(see Section 4 above).
- No blocking technical decisions pending at this time.