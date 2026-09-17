# PROJECT_STATE.md — Current Snapshot

> **PROCESS RULE (non-negotiable):** This file MUST be updated by the coding
> agent at the end of every task, without exception, reflecting true,
> verified state — not aspirational state. AI chat context does not persist
> across sessions; this file does. It is the authoritative persistent memory
> of the project across sessions. If this file is stale, it must be corrected
> before any new task begins, not silently worked around.

> This file reflects the CURRENT state of the project only. It is not a
> history log (task-by-task history lives in Git commit history and each
> task's final report). Every AI agent must read this file first, before
> `ARCHITECTURE.md` or `ROADMAP.md`, to get immediate situational awareness.

**Last updated**: 2026-09-17, P0-T4 verification + PROJECT_STATE full rewrite
**Updated by**: Coding agent, with authenticated `gh` API evidence

---

## 1. Current Phase

**Phase 0 — Project Foundation & Governance Setup (near closeout).**

No application code, no domain logic, no native code, and no UI have been
written yet. All Phase 0 tasks (P0-T1 through P0-T12) are implemented, in
review, or pending human actions. P0-T12 (Phase 0 closeout DoD pass) has NOT
been started and must not be attempted until the human reviews P0-T10/P0-T11
and resolves the P0-T4 branch-protection item.

---

## 2. Phase 0 Task Status (quoted from `AI_ROLES/ROADMAP.md`)

The following one-line summaries reflect the actual `**Status:**` lines
currently in `AI_ROLES/ROADMAP.md`. Where ROADMAP.md and observed reality
disagree, it is flagged here rather than silently resolved.

- **P0-T1**: `Completed ✅` — Git repository and baseline scaffold commit
  finalized (commits `d056b07`, `c1821c0`). Note: the working tree is
  currently NOT clean (multiple uncommitted changes awaiting human-authorized
  commit; see Section 6) — this does not contradict the completed scaffold
  baseline but must be resolved before closeout.
- **P0-T2**: `Completed ✅` — GPL v3 `LICENSE` added in commit `57db473`.
- **P0-T3**: `Completed ✅` — all AI_ROLES governance files committed.
- **P0-T4**: `In Progress` — secret scanning, push protection, Dependabot
  alerts, and automated security fixes verified PASS via authenticated
  `gh` API; `.github/dependabot.yml` created locally (uncommitted);
  branch protection on `master` still NOT configured — human action
  required; blocks P0-T12, not other Phase 0 work.
- **P0-T5**: `Completed ✅` — baseline CI workflow passing (runs
  `35094137659`, `35094469907`).
- **P0-T6**: `Completed ✅` — six-package Melos workspace verified
  (bootstrap/analyze/test all pass).
- **P0-T7**: `Completed ✅` — native/ README scaffolding finalized in commit
  `d626064` (human-reviewed).
- **P0-T8**: `Ready for Human Review` — `AI_ROLES/TOOLCHAIN_VERSIONS.md`
  created and verified.
- **P0-T9**: `Completed ✅` — Memory MCP write/read round-trip verified.
- **P0-T10**: `Ready for Human Review` — base dependency wiring for
  `apps/mobile` done and verified; awaiting human review.
- **P0-T11**: `Ready for Human Review` — root `README.md` authored; build
  instructions verified on a real Android device (SM A205F,
  `RZ8M53WPMPF`); awaiting human review.
- **P0-T12**: `Not Started` — Phase 0 closeout DoD pass. Explicitly out of
  scope until T10/T11 review and P0-T4 branch protection are resolved.

---

## 3. What Exists Right Now (Verified)

- Git repository at `~/Documents/Code/brick-vpn` (GitHub: `Ajorvpn/brick`,
  default branch `master`).
- Melos monorepo, six packages: root workspace `pubspec.yaml` (Dart Native
  Workspace, sole source of truth; `melos.yaml` removed), `apps/mobile`
  (Flutter 3.47.4 scaffold with base dependencies wired per P0-T10), and
  `packages/{core_domain, core_vpn_engine, config_parser, ui_theme,
  shared_utils}`.
- `.github/workflows/ci.yml` — passing CI (P0-T5, runs `35094137659`,
  `35094469907`).
- `.github/dependabot.yml` — created 2026-09-17 (P0-T4), 8 entries: 7× `pub`
  (one per pubspec.yaml directory) + 1× `github-actions`; PyYAML-validated;
  NOT yet committed/pushed.
- `LICENSE` (GPL v3), root `README.md` (P0-T11, uncommitted),
  `AI_ROLES/TOOLCHAIN_VERSIONS.md` (P0-T8).
- `native/{android,ios,desktop}/README.md` scaffolding (P0-T7).
- Android debug build verified end-to-end on device SM A205F
  (`RZ8M53WPMPF`): `flutter run` built `app-debug.apk`, installed, and
  launched (Impeller/Vulkan, Dart VM Service up) — with
  `apps/mobile/android/build.gradle.kts` left as the untouched Flutter
  template original.
- GitHub repo security settings (verified 2026-09-17 via authenticated
  `gh` API): secret scanning enabled, push protection enabled, Dependabot
  alerts enabled, automated security fixes enabled.

## 4. What Does NOT Exist Yet

- Any real domain/VPN/UI code — no VpnService, no libbox/sing-box
  integration, no feature screens (by design; that is Phases 1–11).
- Branch protection on `master` (human UI action pending; verified absent
  via `GET /branches/master/protection` → `404 Branch not protected`).
- `.github/dependabot.yml` on the remote (created locally; not pushed).
- No public-facing security policy page (deferred per SECURITY.md).
- No license/CLA decision beyond GPL v3 direction (open question).

## 5. Environment Notes (Verified on This Machine)

- OS: Ubuntu 24.04.5 LTS
- Flutter: 3.47.4 (stable channel); Dart SDK: 3.13.3; Melos: 8.7.0;
  Git: 2.43.0 — authoritative matrix in
  [`AI_ROLES/TOOLCHAIN_VERSIONS.md`](TOOLCHAIN_VERSIONS.md). AGP/Kotlin/Go/
  NDK/sing-box pins deliberately deferred to Phase 3.
- **Local Gradle init-script footgun (must stay disabled):**
  `/home/e60/.gradle/init.d/iran-mirrors.gradle.disabled` — a machine-wide
  Gradle init script that injects extra Maven repositories. When active, it
  breaks the Flutter Android plugin loader with
  `Build was configured to prefer settings repositories over project
  repositories but repository 'maven' was added by settings file
  'settings.gradle.kts'`. It MUST remain renamed with `.disabled`; the fix
  is NEVER to delete the `allprojects` repositories block from
  `apps/mobile/android/build.gradle.kts`. Documented in the root README
  Troubleshooting section.
- `gh` CLI authenticated as `Ajorvpn` (keyring, `repo` scope) — enables
  authenticated GitHub API verification.
- Multiple `adb` binaries warning (low priority, unresolved).
- Linux desktop toolchain not installed (intentionally deferred until the
  Desktop phase).
- At least one physical Android device (SM A205F) available for testing.

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

### Melos 8.7.0 workspace/config contract (dated 2026-09-15)

This was fully re-verified after the stale `melos.yaml` file was removed:
Melos 8.7.0 does not read `melos.yaml` for workspace/package discovery or
`melos run` scripts at all. The only configuration entry point it uses is
the root `pubspec.yaml`, where `workspace:` defines package discovery and
`melos:` contains the script/config block. The earlier `melos.yaml` file was
therefore dead configuration in this version and had been duplicating
settings that were already in `pubspec.yaml`.

The repo now uses a single, unambiguous source of truth: root
`pubspec.yaml` for both workspace discovery and Melos configuration.
See the Phase 0 P0-T5 evidence trail in `AI_ROLES/ROADMAP.md` for the
verified command outputs and package-source proof.

---

## 6. Working Tree State (uncommitted, awaiting human authorization)

As of 2026-09-17, the working tree contains intentional, uncommitted changes
(agents are prohibited from committing without explicit human approval):

- `AI_ROLES/ROADMAP.md` — P0-T4/T7/T10/T11 status updates.
- `AI_ROLES/TOOLCHAIN_VERSIONS.md` — resolved Dart package versions (P0-T10).
- `apps/mobile/pubspec.yaml`, `apps/mobile/analysis_options.yaml`,
  `pubspec.lock` — base dependency wiring (P0-T10).
- `apps/mobile/macos/Flutter/GeneratedPluginRegistrant.swift` — incidental
  Flutter tooling regeneration during dependency work.
- `README.md` (untracked) — root README (P0-T11).
- `.github/dependabot.yml` (untracked) — new (P0-T4).

The human must review and authorize commits for these before P0-T12.

---

## 7. Open Questions / Pending Human Decisions

1. **Branch protection on `master`** (P0-T4): not yet configured on GitHub;
   requires manual UI action (require PR + required status check + no
   force-push + no deletions), then agent re-verification.
2. **P0-T10 review**: human to review dependency-wiring deliverables and
   mark `Completed`.
3. **P0-T11 review**: human to review root `README.md` and mark `Completed`.
4. **P0-T8 review**: still `Ready for Human Review` from an earlier session.
5. **Commit authorization**: multiple working-tree changes (Section 6) need
   explicit human go-ahead to commit (and then push, including
   `.github/dependabot.yml`).
6. License/CLA wording finalization (GPL v3 direction agreed).
7. Memory MCP: verified 2026-09-16 with a real write/read round-trip; may be
   used as a low-sensitivity convenience cache, with graceful fallback to
   `PROJECT_STATE.md`/`ARCHITECTURE.md`/`ROADMAP.md`; governance files remain
   the source of truth on any conflict.

## 8. Immediate Next Steps (In Order)

1. Human: apply branch protection on `master` (GitHub UI), then agent
   re-verifies via `gh api repos/Ajorvpn/brick/branches/master/protection`.
2. Human: review P0-T10 and P0-T11 deliverables (full raw content supplied in
   the 2026-09-17 session report); on approval, mark `Completed`, unblocking
   P0-T12.
3. Human: authorize commits of the working-tree changes (including
   `.github/dependabot.yml` and `README.md`).
4. Agent (after 1–3): run P0-T12 — Phase 0 closeout DoD pass.
