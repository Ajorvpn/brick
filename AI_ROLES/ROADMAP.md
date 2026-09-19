# Brick VPN — ROADMAP.md

> **Governance document.** Read `AGENTS.md`, `ARCHITECTURE.md`, this file, `CODING_STANDARDS.md`,
> `SECURITY.md`, and `DEFINITION_OF_DONE.md` in that order before working on any task.

## Purpose

This is the authoritative, granular task breakdown for Brick VPN, from an empty monorepo
scaffold to a stable, usable Android MVP, and beyond toward desktop, iOS, and a premium
system. It exists so that any single task can be handed to an AI coding agent in isolation,
with zero ambiguity about scope, dependencies, or what "done" means.

## How This Document Is Used

1. The project owner selects the next task whose `Status` is `Not Started` and whose
   `Depends On` list is fully `Completed`.
2. The task is discussed/refined with the planning assistant if anything is unclear.
3. The planning assistant produces an engineered English prompt derived from that task's
   Objective / Scope / Acceptance Criteria.
4. The prompt is handed to a coding agent (Cursor, Claude Code, Copilot, etc.).
5. The agent follows the standard workflow defined in `AGENTS.md`
   (Understand → Research → Design → Implement → Self-Test → Self-Review as Debugger → Report).
6. The agent updates task status per the vocabulary in `DEFINITION_OF_DONE.md`. An agent may
   only propose `Ready for Human Review` — never self-mark `Completed`.
7. The human reviews, marks `Completed`, and updates `PROJECT_STATE.md`.
8. Move to the next task. This is a strictly sequential, domino-style process unless a task's
   Notes explicitly allow parallelization.

## Status Legend

- `Not Started`
- `In Progress`
- `Blocked` — must include a one-line reason and what unblocks it
- `Ready for Human Review`
- `Completed`

## Task Template

Every task in this document has the following fields:

- **ID** — `P<phase>-T<number>`, e.g. `P0-T3`.
- **Title**
- **Status**
- **Depends On** — list of task IDs, or `—` if none.
- **Objective** — one paragraph, plain statement of what must exist when this task is done.
- **Scope** — explicit `Included` and `Excluded` file/package paths and behaviors. If it's not
  listed as included, the agent must not touch it without stopping to ask first.
- **Acceptance Criteria** — a checklist. All boxes must be true before the task can be marked
  `Ready for Human Review`.
- **Notes for Agent** — context, known gotchas, explicit permission boundaries, and pointers to
  relevant `AI_ROLES/` sections.

## Granularity Note

Phases 0–3 (governance, architecture skeleton, config parser, Android VPN engine) are the
near-term, highest-risk work and are broken down here at maximum granularity. Phases 4 onward
are sketched at a coarser granularity for now and **will be expanded to full task-level detail
when the project actually reaches them**, per the living-document practice already established
for `PROJECT_STATE.md`. Do not treat later-phase task descriptions as final or fully specified —
they must be re-verified against the state of the ecosystem (sing-box, Flutter, platform
policies) at the time they are actually started, per the project's no-guessing rule.

## Phase Overview

| Phase | Name | One-line description |
|---|---|---|
| 0 | Project Governance & Repo Scaffolding | Repo, CI, tooling, governance docs finalized |
| 1 | Architecture Skeleton | Domain layer, DI, feature-first structure, no real features yet |
| 2 | Config Parser Engine | Pure-Dart, independently testable parsing of vless/vmess/trojan/ss/hysteria2/tuic/subscriptions |
| 3 | Android VPN Engine | Native-only lifecycle gate → Platform Channel/Pigeon gate. Highest-risk phase. |
| 4 | State Management + App Skeleton | Riverpod wiring, go_router, bare navigation, no final UI |
| 5 | Core MVP Features | Add server, connect/disconnect, server list, QR scan |
| 6 | Traffic Stats & Live Logs | Deliberately separated from Phase 3 per legacy lesson learned |
| 7 | Stability & Lifecycle Hardening | Auto-reconnect, kill switch, DNS correctness, chaos tests |
| 8 | Security Hardening | Secure storage, log redaction, update integrity |
| 9 | Testing & QA | Unit, integration, manual test protocol |
| 10 | Android MVP Release Prep | Signing, AAB/APK, GitHub Release, Play Store declaration |
| — | **Stable, usable Android MVP exists at this point** | |
| 11 | Full UI/UX Design & Implementation | |
| 12 | Desktop Support | Daemon + IPC architecture. Windows → macOS → Linux |
| 13 | iOS Support | Uncertain/possible later |
| 14 | Premium/Subscription System | Future, architecturally decoupled from the free client |

---

## Phase 0 — Project Governance & Repo Scaffolding

**Phase Goal:** the repository is safe, reproducible, and fully documented for AI-assisted
development before any real feature code is written.

### P0-T1 — Finalize Git repository and baseline scaffold commit

**Status:** Completed ✅ — reverified on 2026-09-16 that `git status --short` is empty, commits `d056b07` and `c1821c0` are present in history, and `.freebuff/` is excluded by `.gitignore` line 18.
**Depends On:** —

**Objective:** Ensure the existing monorepo scaffold (`apps/mobile`, `packages/`, `native/`,
`AI_ROLES/`, `melos.yaml`, root `pubspec.yaml`) is committed to Git as a clean, working baseline,
with a correct `.gitignore` for a Flutter + Melos + native (Kotlin/Go) monorepo.

**Scope:**
- Included: root `.gitignore`, verifying `git status` is clean after commit, one commit (or a
  small reviewed set of commits) representing the current scaffold state.
- Excluded: any new feature code, any changes to `AI_ROLES/*` content, any dependency changes.

**Acceptance Criteria:**
- [x] `.gitignore` excludes: `.dart_tool/`, `build/`, `*.iml`, `.idea/` (if not already project-wide),
      `pubspec_overrides.yaml` (Melos-generated), `.mcp-memory/`, `.freebuff/`, Android `local.properties`,
      Android/Gradle build outputs, any `*.aar`/`*.jar` unless explicitly meant to be checked in,
      and any keystore/signing files (`*.jks`, `*.keystore`, `key.properties`).
- [x] `git status` shows a clean working tree after the commit.
- [x] `git log` shows a coherent, readable commit history (squash/amend if the prior scaffold
      history is messy — confirm with human before rewriting history if already pushed anywhere).
- [x] No secrets, credentials, or machine-specific absolute paths are committed.

**Notes for Agent:**
- This is a housekeeping task. If `git log` already looks clean, verify and report rather than
  rewriting history unnecessarily.
- Stop and ask if any file looks like it might contain a secret or an absolute path specific to
  the developer's machine.

---

### P0-T2 — Add GPL v3 LICENSE file and root license headers policy

**Status:** Completed ✅ — verified in commit `57db473` that root `LICENSE` is byte-identical to the official GNU GPL v3 text downloaded from `https://www.gnu.org/licenses/gpl-3.0.txt` (674 lines, 35149 bytes, SHA-256 `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`), that `CODING_STANDARDS.md` explicitly requires SPDX `GPL-3.0-or-later` headers for new source files from Phase 1 onward, and that no unrelated files were changed.
**Depends On:** P0-T1

**Objective:** Add the official GNU GPL v3 license text as `LICENSE` at the repo root, and define
(in `CODING_STANDARDS.md`, as an addendum if not already present) the policy for whether/how
per-file license headers are used across the monorepo.

**Scope:**
- Included: `/LICENSE` (full, unmodified GPL v3 text), a short "License" section added to the
  (not-yet-written) root `README.md` placeholder note, a decision recorded on file-header policy.
- Excluded: any changes to `AI_ROLES/*` files' own content beyond the header-policy addendum,
  no license headers retroactively added to files yet (that's a mechanical follow-up only if the
  human decides headers are required).

**Acceptance Criteria:**
- [x] `/LICENSE` contains the exact, official, unmodified GPL v3.0 text.
- [x] A short note exists (in `CODING_STANDARDS.md` or a new `LICENSE_POLICY.md` inside
      `AI_ROLES/` if the human prefers) stating whether per-file SPDX headers
      (`SPDX-License-Identifier: GPL-3.0-or-later`) are required for new source files going
      forward. Default recommendation: yes, require SPDX header comment in every new source
      file from Phase 1 onward.
- [x] Decision is explicit, not left ambiguous.

**Notes for Agent:**
- Do not paraphrase or shorten the GPL v3 text — use the canonical text from gnu.org verbatim.
- If unsure whether SPDX headers should be mandatory, present the tradeoff to the human rather
  than deciding silently (this is a "stop and ask" case per `AGENTS.md`).

---

### P0-T3 — Commit and cross-verify all AI_ROLES governance files

**Status:** Completed ✅
**Depends On:** P0-T1

**Objective:** Ensure all eight `AI_ROLES/` files (`AGENTS.md`, `ARCHITECTURE.md`, `ROADMAP.md`,
`PROJECT_STATE.md`, `CODING_STANDARDS.md`, `SECURITY.md`, `DEFINITION_OF_DONE.md`,
`MCP_MEMORY_GUIDE.md`) are present, committed, and internally consistent — no contradictory
statements, no broken cross-references, no leftover placeholder text.

**Scope:**
- Included: read-only cross-verification pass across all `AI_ROLES/*.md` files; fixing purely
  mechanical issues (broken relative links, obvious typos, inconsistent terminology e.g. task
  status vocabulary must match exactly between `ROADMAP.md` and `DEFINITION_OF_DONE.md`).
- Excluded: any substantive rewriting of policy/architecture content — if a real contradiction
  in *substance* (not just wording) is found, stop and report it rather than resolving it
  unilaterally.

**Acceptance Criteria:**
- [x] All 8 files exist under `AI_ROLES/` and are committed.
- [x] Status vocabulary (`Not Started`/`In Progress`/`Blocked`/`Ready for Human Review`/
      `Completed`) is used identically across `ROADMAP.md` and `DEFINITION_OF_DONE.md`.
- [x] All internal relative links (if any) resolve correctly.
- [x] A short report is produced listing: files checked, any mechanical fixes made, any
      substantive inconsistencies found (even if not fixed).

**Notes for Agent:**
- This task is explicitly a verification/QA pass, not a rewrite. Bias toward reporting issues
  over silently "fixing" anything that looks like a judgment call.

---

### P0-T4 — GitHub repository setup: branch protection, Dependabot, secret scanning

**Status:** Completed ✅ — all six required items verified on 2026-09-17 via authenticated `gh` API (account `Ajorvpn`): (1) secret scanning ✅ `enabled`; (2) secret scanning push protection ✅ `enabled`; (3) Dependabot vulnerability alerts ✅ HTTP `204` (enabled); (4) Dependabot automated security fixes ✅ `{"enabled": true, "paused": false}`; (5) `.github/dependabot.yml` ✅ created and committed — seven `pub` entries, one per directory containing a `pubspec.yaml`, plus a `github-actions` entry for `.github/workflows/`, validated with PyYAML and grounded in the official Dependabot documentation (`pub` is a supported community-maintained ecosystem; Dependabot checks manifest files only in the specified directory, so monorepos need one entry per manifest directory); (6) branch protection on the default branch `master` ✅ verified via API (`GET /branches/master/protection` returns HTTP `200`, `allow_force_pushes.enabled: false`, `allow_deletions.enabled: false`). The configured protection is the deliberate, documented, lenient solo-development tier: pull-request-required and status-check-required protection are intentionally NOT enabled at this stage (single maintainer, no external contributors yet). This is a documented decision, not an oversight, and it must be revisited and tightened before the project gains outside contributors or goes fully public.

**Manual GitHub UI steps the human performed (note recorded here, in this Status field, per ROADMAP.md's own convention — no separate log file was created):**
1. Branch protection on `master`: branch name pattern `master`; force pushes **not allowed**; branch deletions **not allowed**; pull-request-required and status-check-required intentionally **left disabled** (deliberate solo-development choice, see above).
2. Secret scanning: **enabled** (Settings → Code security → Secret scanning).
3. Secret scanning push protection: **enabled** (Protection settings within Secret scanning).
4. Dependabot alerts: **enabled** (Code security → Dependabot alerts).
5. Dependabot security updates (automated security fixes): **enabled** (Code security → Dependabot security updates).
6. `.github/dependabot.yml` created by the agent, committed in `e6914b4`, and pushed.

Each of items 1–6 was independently re-verified by the agent over the authenticated GitHub API on 2026-09-17 (raw evidence in this task's final report and in `PROJECT_STATE.md`).
**Depends On:** P0-T1

**Objective:** Configure the GitHub repository's built-in security and workflow features so the
project has baseline supply-chain hygiene from day one, per `SECURITY.md`.

**Scope:**
- Included: `.github/dependabot.yml` (covering pub/Dart, GitHub Actions, and — once they exist —
  Gradle/Go ecosystems, with a conservative update schedule, e.g. weekly, grouped where sensible),
  enabling GitHub secret scanning and push protection (repo settings, documented in a short note
  since this may require manual UI steps the agent cannot perform), a basic branch protection
  rule description for `master` (require PR, require status checks once CI exists — CI itself is
  P0-T5) documented for the human to apply manually if the agent lacks GitHub admin API access.
  Clarification (2026-09-17): the human deliberately chose a lighter protection tier for the
  solo-development phase — no pull-request requirement and no required status check were enabled;
  force-pushes and branch deletions were disabled instead. The "require PR, require status checks"
  wording above describes this task's original aspiration, not what was actually configured, and it
  is to be revisited and tightened before the project gains contributors.
- Excluded: actual CI workflow content (that's P0-T5), any Gradle/Go dependency files that don't
  exist yet (add placeholders/comments noting they'll be added when those ecosystems appear).

**Acceptance Criteria:**
- [x] `.github/dependabot.yml` exists and validates (correct YAML, correct package-ecosystem
      values for `pub` and `github-actions` at minimum).

      Evidence: created and committed in `e6914b4`; validated with PyYAML (`VALID YAML — 8
      entries`); 7× `pub` entries (one per directory containing a `pubspec.yaml`) plus 1×
      `github-actions` entry. Live proof that GitHub honors it: Dependabot opened PR #1
      (`github-actions` bump) within minutes of the push.
- [x] A short `AI_ROLES/logs/` note or PR description lists the manual GitHub UI steps the human
      must still perform (secret scanning toggle, push protection toggle, branch protection rule)
      if the agent's access doesn't allow configuring them directly.

      Satisfied by the enumerated manual-steps note in this task's **Status** field above (items
      1–6), which documents each GitHub UI action the human performed and how it was re-verified.
      ROADMAP.md's own convention permits recording such a note in the Status prose rather than
      creating a separate log file; no `AI_ROLES/logs/` file was created.
- [x] No workflow file is created here that would fail simply because CI doesn't exist yet.

      Evidence: this task created no workflow file. The only workflow, `.github/workflows/ci.yml`,
      belongs to P0-T5 and has since run green 7 times on `master`.

**Notes for Agent:**
- If you have no ability to configure repository settings via API/CLI in this environment, do not
  guess — produce the exact list of manual steps for the human instead, per the "stop and ask /
  don't guess" rule.

---

### P0-T5 — Baseline CI workflow (format, analyze, test)

**Status:** Completed ✅ — verified that commits `bea3eea` and `5fddb07` exist, the current `.github/workflows/ci.yml` pins Flutter 3.47.4 and Melos 8.7.0, uses non-interactive `--no-select` execution, and GitHub Actions runs `35094137659` and `35094469907` both remain `completed` with `success` conclusions.
**Depends On:** P0-T3

**Objective:** Add a GitHub Actions workflow that runs on every push and pull request, executing
the Melos scripts already defined (`melos run format`, `melos run analyze`, `melos run test`)
against the monorepo, using pinned tool versions.

**Scope:**
- Included: `.github/workflows/ci.yml`, pinning exact Flutter version (3.47.4 or whatever is
  current and verified at task time — confirm, do not assume it hasn't changed), pinning Dart SDK
  implicitly via the Flutter version, using `subosito/flutter-action` (or verified current
  equivalent) with caching enabled.
- Excluded: any native Android/Go build steps (that belongs to Phase 3), any release/signing
  workflow (Phase 10).

**Acceptance Criteria:**
- [x] Workflow triggers on `push` to `master` (not `main`, which no longer exists) and on all
      `pull_request` events.
- [x] Workflow installs the pinned Flutter version, runs `melos bootstrap`, then `melos run
      format`, `melos run analyze`, `melos run test`, failing the job on any non-zero exit.
- [x] Workflow uses dependency/build caching to keep run time reasonable.
- [x] A test run (triggered by an actual PR or push) is shown to pass or fail correctly — i.e.
  verified working, not just written and assumed correct. GitHub Actions run 35094137659
  completed successfully for commit `bea3eea8af76c0b222da20ea4d6002d43e8a86c3`.
- [x] Pinned versions are recorded in a comment in the workflow file, with a note to update them
      only via a dedicated task, not silently.

**Notes for Agent:**
- Verify the current recommended Flutter-setup GitHub Action and its exact usage syntax rather
  than relying on possibly-stale training knowledge — this is exactly the kind of external,
  fast-moving fact the no-guessing rule exists for.
- Do not add native/Go steps even if tempted "for completeness" — strictly out of scope here.

---

### P0-T6 — Melos workspace hygiene verification and package skeletons

**Status:** Completed ✅ — fresh verification on 2026-09-16 showed `config_parser`, `core_domain`, `core_vpn_engine`, `mobile`, `shared_utils`, and `ui_theme` in `melos list`; `melos bootstrap` reported `6 packages bootstrapped`; `melos run analyze --no-select` and `melos run test --no-select` both completed successfully across all six packages.
**Depends On:** P0-T1

**Objective:** Create empty, correctly-wired Dart package skeletons for the five planned
`packages/` (`core_domain`, `core_vpn_engine`, `config_parser`, `ui_theme`, `shared_utils`),
each following the exact Melos/Dart-Native-Workspace pattern already discovered and documented
(root `pubspec.yaml` `workspace:` list + each package's own `resolution: workspace`), so `melos
list` and `melos bootstrap` correctly recognize all packages.

**Scope:**
- Included: `packages/core_domain/`, `packages/core_vpn_engine/`, `packages/config_parser/`,
  `packages/ui_theme/`, `packages/shared_utils/` — each a minimal valid Dart package (`pubspec.yaml`
  with `resolution: workspace`, `lib/<package_name>.dart` placeholder export file, `test/` folder
  with one trivial passing test), root `pubspec.yaml` `workspace:` list updated to include all
  five new paths alongside `apps/mobile`.
- Excluded: any real domain classes, VPN engine interfaces, or parser logic — those belong to
  Phase 1/2/3. These are empty, buildable, testable skeletons only.

**Acceptance Criteria:**
- [x] `melos list` shows all 6 packages (`mobile` + the 5 new ones).
- [x] `melos bootstrap` reports all 6 packages bootstrapped successfully, with zero errors.
- [x] `melos run analyze` and `melos run test` both pass across the whole workspace.
- [x] Each new package's `pubspec.yaml` has `resolution: workspace` placed correctly (right after
      `publish_to: none`, matching the exact pattern already verified for `apps/mobile`).
- [x] The CI workflow from P0-T5 is re-run and still passes with the new packages present.

      Evidence: the workflow now exists (P0-T5) and has run green 7 times on `master`, including
      runs after the five new packages and the P0-T10 dependency wiring landed — e.g.
      `35170446158` (`9151a40`), `35170349543` (`60305ed`), `35170180363` (`b8ef4ce`),
      `35169690649` (`c506ebb`), each `conclusion: success`.

**Notes for Agent:**
- This exact Melos/workspace pitfall has already been hit once during initial scaffolding (see
  `PROJECT_STATE.md`) — follow the documented two-step pattern precisely; do not rediscover the
  bug from scratch.
- Package names should be Dart-valid, e.g. `core_domain`, `core_vpn_engine`, `config_parser`,
  `ui_theme`, `shared_utils` — confirm exact naming with the human if anything looks ambiguous
  (e.g. whether `shared_utils` should be `common` instead) before creating files.

---

### P0-T7 — Native module directory scaffolding (Android, iOS, Desktop placeholders)

**Status:** Completed ✅ — created `native/android/README.md`, `native/ios/README.md`, and `native/desktop/README.md` with scoped purpose, future phase, and architecture references. Fresh verification found all three README files and no native build tooling files. Finalized in commit `d626064`.
**Depends On:** P0-T1

**Objective:** Establish the `native/android/`, `native/ios/`, and `native/desktop/` directory
structure with minimal placeholder content and clear README notes describing what will live
there and when (per phase), without creating any real native build configuration yet (that is
Phase 3's job for Android).

**Scope:**
- Included: `native/android/README.md`, `native/ios/README.md`, `native/desktop/README.md`, each
  stating: purpose of the directory, which Phase will populate it, and a link back to the
  relevant `ARCHITECTURE.md` section (Section 3 / 3.5 for Android, Section 3.6 for Desktop).
- Excluded: any actual Gradle files, Xcode project files, Go source files, or build scripts.

**Acceptance Criteria:**
- [x] All three README files exist with accurate, non-placeholder-sounding content (real
      sentences, not "TODO").
- [x] Each README correctly references the relevant `ARCHITECTURE.md` section by name/number.
- [x] No native build tooling files are accidentally created.

**Notes for Agent:**
- Keep this deliberately minimal — the goal is a self-documenting empty scaffold, not a head
  start on Phase 3 native work.

---

### P0-T8 — Toolchain version pinning matrix document

**Status:** Completed ✅ — created `AI_ROLES/TOOLCHAIN_VERSIONS.md` on 2026-09-16 with freshly verified Flutter 3.47.4, Dart 3.13.3, Melos 8.7.0, and Git 2.43.0 values; Go and gomobile were confirmed not installed, while Go/NDK/gomobile/AGP/Kotlin/sing-box pins are explicitly deferred to Phase 3. The required version-upgrade policy and both toolchain footguns are documented, and `PROJECT_STATE.md` references the matrix.
**Depends On:** —

**Objective:** Create a single authoritative document (`AI_ROLES/TOOLCHAIN_VERSIONS.md`) listing
every pinned version relevant to reproducible builds: Flutter, Dart SDK, Melos, and — as
placeholders to be filled in when Phase 3 actually starts — Go, `gomobile`/`golang.org/x/mobile`,
Android NDK, Android Gradle Plugin, Kotlin, and the exact pinned sing-box commit/tag. Establish
the rule that any change to a pinned version is its own dedicated task with full lifecycle
re-testing, never a silent/incidental bump.

**Scope:**
- Included: `AI_ROLES/TOOLCHAIN_VERSIONS.md` with a version table, a "how to update" policy
  section, and explicit call-outs for two known footguns already surfaced during peer review:
  (a) never rely on Go's `go.mod`-based auto toolchain resolution in CI — pin the Go version
  explicitly, because auto-resolution has been reported to silently break QUIC-based outbounds
  (relevant to Hysteria2/TUIC support) in Android AAR builds; (b) treat any sing-box major-version
  bump (e.g. the 1.13 `platform.Interface` → `adapter.PlatformInterface` break) as a dedicated
  migration task with its own acceptance criteria, never a routine dependency update.
- Excluded: actually installing/pinning Go/NDK/gomobile/sing-box yet — those fields are marked
  `TBD — set in Phase 3` for now. This task only pins what's already installed and verified
  (Flutter 3.47.4, Dart 3.13.3, Melos 8.7.0 — reverify these are still what's actually installed
  at task time before writing them down).

**Acceptance Criteria:**
- [x] `AI_ROLES/TOOLCHAIN_VERSIONS.md` exists with a complete table (even if some rows are `TBD`).
- [x] The Go-toolchain-auto-resolution footgun and the sing-box-1.13-interface-break footgun are
      both documented explicitly, in the agent's own words, not copy-pasted verbatim from any
      external source.
- [x] A clear policy statement exists: "Upgrading any pinned version listed here requires its own
      roadmap task with explicit lifecycle re-testing acceptance criteria; it is never bundled
      into an unrelated task."
- [x] `PROJECT_STATE.md` is updated to reference this new file's existence.

**Notes for Agent:**
- Verify current installed versions (`flutter --version`, `dart --version`, `melos --version`)
  rather than trusting any previously-recorded number, since time may have passed.
- Do not install or attempt to pin Go/NDK/gomobile in this task — that's explicitly deferred.

---

### P0-T9 — Memory MCP verification task

**Status:** Completed ✅ — verified on 2026-09-16 with two separate server invocations using `@modelcontextprotocol/server-memory` version `0.6.3`: the first created entity `Brick_VPN_MCP_Verification_2026_09_16` with its observation in `.mcp-memory/memory.json`, and the fresh second invocation retrieved the same entity and observation intact. The memory path is ignored by `.gitignore`; PROJECT_STATE records the result, graceful fallback, and governance-file ownership-of-truth rules.
**Depends On:** —

**Objective:** Verify, per `MCP_MEMORY_GUIDE.md`, whether the Memory MCP server
(`@modelcontextprotocol/server-memory`) is actually usable in the agent's real tool environment:
store a low-sensitivity test fact in one session, start a fresh session, and confirm the fact is
retrievable. Record the outcome (works / doesn't work / partially works) so future tasks know
whether to rely on it.

**Scope:**
- Included: following the exact setup described in `MCP_MEMORY_GUIDE.md` (npx-based reference
  server, `MEMORY_FILE_PATH` pointing to `.mcp-memory/memory.json`, gitignored), storing one
  clearly-labeled test fact (e.g. "Brick VPN MCP verification marker: <timestamp>"), then in a
  genuinely new session, attempting retrieval.
- Excluded: storing any real project data, any Roadmap/architecture content, anything above
  "None" sensitivity per `SECURITY.md`'s data classification table.

**Acceptance Criteria:**
- [x] A clear pass/fail/partial result is recorded in `PROJECT_STATE.md`'s open questions section
      (replacing the current "unverified" note).
- [x] If it works: a short "how to use it going forward" note is added, confirming the
      graceful-degradation and ownership-of-truth rules from `MCP_MEMORY_GUIDE.md` still apply.
- [x] N/A — feature worked, condition did not apply. (If it doesn't work: this is explicitly not
      a blocker — record it and move on, per the "never block on it" rule.)
- [x] `.mcp-memory/` is confirmed present in `.gitignore`.

**Notes for Agent:**
- This task's entire point is an honest, verified answer — "I couldn't test this because X" is an
  acceptable and useful outcome; do not fabricate a successful test.

---

### P0-T10 — Base dependency wiring for `apps/mobile`

**Status:** Completed ✅ — verified on 2026-09-16 that the six-package workspace bootstraps successfully with the approved mobile dependencies, very_good_analysis is active with documented exceptions limited to the untouched Flutter template, a temporary `@riverpod` example caused `dart run build_runner build` in `apps/mobile` to process one input and write two outputs, the temporary source and generated files were then removed, the full workspace analysis and tests pass afterward, and exact resolved Dart package versions are recorded in `AI_ROLES/TOOLCHAIN_VERSIONS.md`.
**Depends On:** P0-T6

**Objective:** Add the already-approved core dependencies to `apps/mobile/pubspec.yaml`
(`flutter_riverpod`, `riverpod_generator` + `riverpod_annotation`, `go_router`,
`easy_localization`, `logger`, `very_good_analysis` as a dev
dependency wired into `analysis_options.yaml`, `build_runner` for code generation) with zero
feature code — just confirming the dependency graph resolves and code generation runs.

**Scope:**
- Included: `apps/mobile/pubspec.yaml` dependency additions, `apps/mobile/analysis_options.yaml`
  configured to use `very_good_analysis`, a trivial `build_runner build` dry run to confirm
  code-gen tooling works (e.g. one throwaway `@riverpod` annotated function, removed or kept as a
  documented example — confirm preference with human), root workspace re-bootstrap.
- Excluded: any real providers/routes/screens — this is dependency plumbing only.

**Acceptance Criteria:**
- [x] `melos bootstrap` succeeds with all new dependencies resolved, no version conflicts.
- [x] `melos run analyze` passes with `very_good_analysis` rules active (any necessary,
      justified lint exceptions are documented inline with a comment explaining why).
- [x] `dart run build_runner build --delete-conflicting-outputs` succeeds in `apps/mobile`.
- [x] `melos run test` still passes.
- [x] Exact resolved versions of each new dependency are noted in `TOOLCHAIN_VERSIONS.md` or a
      linked note (Dart package versions specifically, distinct from the native toolchain table).

**Notes for Agent:**
- Use the latest stable versions compatible with the pinned Flutter/Dart SDK — verify compatibility
  rather than assuming latest-is-always-fine, since `very_good_analysis` and `riverpod_generator`
  major versions can have breaking rule/API changes.

---

### P0-T11 — Root README.md authoring

**Status:** Completed ✅ — the literal `cd apps/mobile && flutter run` instruction was re-executed against the connected Android device `SM A205F` (`RZ8M53WPMPF`): Gradle assembled `app-debug.apk` successfully, the APK was installed, and the app launched (Impeller/Vulkan rendering, Dart VM Service up). The earlier Gradle settings-repository conflict was caused solely by a machine-wide init script under `~/.gradle/init.d/`, not by any repository file; `apps/mobile/android/build.gradle.kts` remains the untouched Flutter template original (with its `allprojects` repositories block). The README now documents a Troubleshooting note for that local init-script footgun.
**Depends On:** P0-T2, P0-T6

**Objective:** Write a root `README.md` that gives any visitor (contributor, curious user,
future-you) an accurate picture of what Brick VPN is, its current state, how to build it, and
where to find the governance docs — without overselling features that don't exist yet.

**Scope:**
- Included: `/README.md` — project description, current status ("early development, no working
  VPN functionality yet" stated honestly), supported protocols (planned, not yet implemented —
  stated as such), build/setup instructions (Flutter version, `melos bootstrap`, how to run
  `apps/mobile`), link to `LICENSE`, link to `AI_ROLES/` for contributors, no telemetry statement,
  contribution/issue-reporting pointer.
- Excluded: marketing language, screenshots/UI descriptions (none exist), any claims about
  security guarantees that aren't yet implemented or verified.

**Acceptance Criteria:**
- [x] README accurately reflects actual current project state (cross-check against
      `PROJECT_STATE.md` before writing).
- [x] Build instructions are verified to actually work by following them literally.
- [x] No unverified or aspirational security/feature claims are stated as fact.
- [x] License section correctly states GPL v3 and links to `/LICENSE`.

**Notes for Agent:**
- Honesty over polish here — this is infrastructure documentation, not marketing copy. If in
  doubt about whether a claim is accurate, state it as "planned" rather than as done.

---

### P0-T12 — Phase 0 closeout and Definition-of-Done pass

**Status:** Completed ✅ — the Phase 0 closeout gate was validated on 2026-09-17: a fresh clone of `origin/master` at commit `c506ebb` ran `melos bootstrap` (6 packages bootstrapped), `melos run format --no-select`, `melos run analyze --no-select`, and `melos run test --no-select` with zero manual intervention and zero failures, and GitHub Actions CI run `35169690649` (event `push`, `headSha` `c506ebb`) completed with conclusion `success` on `master` after the workflow trigger was corrected from the stale `main` value to the repository's actual default branch `master`. Note: this task's acceptance criterion originally read "CI is green on the `main` branch"; that was unsatisfiable because `main` no longer exists, so it was reworded to reference the repository's actual default branch `master` and is now checked, citing CI run `35170446158` on commit `9151a40` (conclusion `success`).
**Depends On:** P0-T1 through P0-T11

**Objective:** Perform a full closeout review of Phase 0: confirm every task above is genuinely
`Completed`, run the complete DoD checklist from `DEFINITION_OF_DONE.md` against the repository
as a whole, and update `PROJECT_STATE.md` to reflect that Phase 0 is finished and Phase 1 is
about to begin.

**Scope:**
- Included: full repository verification pass (CI green, `melos bootstrap`/`analyze`/`test` all
  passing from a clean clone), `PROJECT_STATE.md` rewritten to reflect the new baseline (what
  exists now, what still doesn't, immediate next steps pointing at Phase 1's first task).
- Excluded: starting any Phase 1 work.

**Acceptance Criteria:**
- [x] Fresh clone of the repo, from scratch, followed by `melos bootstrap`, `melos run analyze`,
      `melos run format`, `melos run test` — all succeed with zero manual intervention.

      Evidence: fresh clone of `origin/master` at `c506ebb` into `/tmp/brick-vpn-verify` on
      2026-09-17 — `melos bootstrap` → `6 packages bootstrapped`; `melos run format --no-select`
      → SUCCESS; `melos run analyze --no-select` → SUCCESS; `melos run test --no-select` →
      SUCCESS. Zero manual intervention, zero failures.
- [x] CI is green on the `master` branch (the repository's actual default branch; `main` does not
      exist).

      Evidence: `gh api repos/Ajorvpn/brick --jq '.default_branch'` → `master`, and `main` is
      absent from `gh api repos/Ajorvpn/brick/branches` (it was deleted 2026-09-16T12:55:24Z,
      before this task). Latest run on the tip: run `35170446158` (`headSha` `9151a40`, event
      `push`) → `conclusion: success`. Note: the criterion's original wording said "`main`",
      which was unsatisfiable as written because that branch no longer exists; reworded here to
      `master` per human instruction.
- [x] `PROJECT_STATE.md` is fully rewritten to reflect end-of-Phase-0 state (not a diff/patch —
      a coherent current snapshot, per its own documented format).

      Evidence: rewritten in commits `c506ebb` and `b8ef4ce` as a coherent full snapshot (sections
      1–10: current phase, per-task status, what exists, what does not exist, environment notes,
      repository sync state, resolved blockers, open questions, next steps, closing note) — not a
      diff or patch.
- [x] A closeout report is produced following the exact template in `DEFINITION_OF_DONE.md`
      (Task Status / Summary / Files Changed / Verification Performed / Self-Review / Known
      Limitations / Human Action Required).

      Evidence: the 2026-09-17 Phase 0 closeout report was delivered in this task's final report
      using that exact template, with raw command output attached for every claim.

**Notes for Agent:**
- This is a gate, not a formality — if a fresh clone doesn't build cleanly, Phase 0 is not
  actually done, regardless of what individual task statuses say.

---

## Phase 1 — Architecture Skeleton

**Phase Goal:** establish the core abstractions, domain types, dependency-injection wiring, and
feature-first folder conventions that every later phase builds on — with zero real features,
zero real VPN logic, and zero final UI. Everything here must be provable with unit tests alone.

**Cross-cutting note for all Phase 1 tasks:** nothing in this phase touches native code, platform
channels, or `packages/config_parser` parsing logic. Those are Phase 3 and Phase 2 respectively.
Phase 1 exists purely to make Phase 2+ possible to build cleanly.

---

### P1-T1 — Result-type error handling primitive

**Status:** Not Started
**Depends On:** P0-T12

**Objective:** Implement the shared `Result<T, E>`-style type (per `CODING_STANDARDS.md`'s
"no exceptions for expected failures" rule) in `packages/shared_utils`, used everywhere an
operation can fail in an expected, recoverable way (parsing errors, VPN command rejections,
storage failures) as opposed to Dart `Exception`s, which remain reserved for truly unexpected
programmer errors.

**Scope:**
- Included: `packages/shared_utils/lib/src/result.dart` (or equivalent), exporting a sealed
  `Result<T, E>` type with `Ok<T, E>` / `Err<T, E>` variants, convenience methods (`map`, `fold`,
  `isOk`/`isErr`, or equivalent — pick a small, idiomatic surface, do not over-engineer), full
  unit test coverage of the type itself.
- Excluded: any domain-specific error types yet (those come with the entities that need them in
  later tasks/phases) — this task only builds the generic mechanism.

**Acceptance Criteria:**
- [ ] `Result<T, E>` is a sealed class (or equivalent exhaustive pattern) so `switch` statements
      on it are exhaustiveness-checked by the analyzer.
- [ ] Unit tests cover: constructing `Ok`/`Err`, `map`, `fold`, equality/hashCode behavior.
- [ ] `melos run analyze` and `melos run test` pass.
- [ ] A short doc comment on the type explains when to use `Result` vs. when a Dart `Exception`
      is still appropriate (per `CODING_STANDARDS.md`), so future agents don't have to re-derive
      the rule.

**Notes for Agent:**
- Do not adopt a third-party functional-programming package (e.g. `fpdart`, `dartz`) for this
  unless explicitly discussed with the human first — the intent is a small, purpose-built type
  the whole team (human + agents) fully understands, not a general FP library surface.

---

### P1-T2 — Core domain entities: connection state and traffic stats

**Status:** Not Started
**Depends On:** P1-T1

**Objective:** Define the two central domain types referenced throughout `ARCHITECTURE.md`
Section 3 — `ConnectionState` (sealed class: `Disconnected` / `Connecting` / `Connected` /
`Disconnecting` / `Error`) and `TrafficStats` (immutable value object: bytes up, bytes down,
timestamp) — in `packages/core_domain`, as pure Dart with zero Flutter dependency.

**Scope:**
- Included: `packages/core_domain/lib/src/connection_state.dart`,
  `packages/core_domain/lib/src/traffic_stats.dart`, barrel export in
  `packages/core_domain/lib/core_domain.dart`, unit tests for both types (equality, exhaustive
  pattern matching, immutability).
- Excluded: the `VpnEngine` interface itself (that's `packages/core_vpn_engine`, next task) and
  any server/profile model (also this phase, but a separate task below).

**Acceptance Criteria:**
- [ ] `ConnectionState` is a sealed class with exactly the five variants listed above; `Error`
      carries a structured reason (not a bare `String message` — use a small enum or sealed
      reason type so calling code can branch on failure category, per the legacy lesson that
      vague error states caused undebuggable behavior).
- [ ] `TrafficStats` is immutable (`const` constructor where possible), value-equal (`==`/
      `hashCode` implemented or generated), and has no mutable public fields.
- [ ] Both types have zero imports from `package:flutter/*` — verified by attempting to run their
      tests with plain `dart test`, not `flutter test`, to prove the package is pure Dart.
- [ ] Unit tests cover equality, exhaustiveness (a `switch` with no `default` compiles and is
      analyzer-clean), and construction of every variant.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- This directly encodes the "two explicitly separate streams... must never share a failure
  domain" rule from `ARCHITECTURE.md` Section 3 — `ConnectionState.Error` and any future
  `TrafficStats`-side failure handling must remain structurally independent. If tempted to merge
  them into one combined "engine status" type, stop and re-read that section first.
- If genuinely unsure what fields `Error`'s reason type needs at this stage, keep it minimal
  (e.g. `permissionDenied`, `invalidConfig`, `platformError(String detail)`, `unknown`) and note
  in the report that it may need extension once Phase 3 native error taxonomy is defined.

---

### P1-T3 — Core domain entity: server profile model

**Status:** Not Started
**Depends On:** P1-T1

**Objective:** Define the `ServerProfile` domain entity in `packages/core_domain` — the
in-memory representation of a single configured server (protocol type, host, port, credentials/
keys, remark/name, and a reference to which protocol-specific config it wraps), independent of
how it was parsed (that's Phase 2's job) or how it's stored (that's Phase 8's secure-storage job).

**Scope:**
- Included: `packages/core_domain/lib/src/server_profile.dart`, a `ProtocolType` enum (`vless`,
  `vmess`, `trojan`, `shadowsocks`, `hysteria2`, `tuic`), unit tests, barrel export update.
- Excluded: any parsing logic, any storage/persistence logic, any UI-facing formatting.

**Acceptance Criteria:**
- [ ] `ServerProfile` is immutable, value-equal, and contains only generic fields that apply
      across all six protocols plus a protocol-specific `Map<String, dynamic>` or sealed
      per-protocol config payload (decide and justify the choice in the task report — this is a
      real design decision, not a formality, and should be informed by what Phase 2's parser
      will actually need to produce).
- [ ] `ProtocolType` enum has exactly the six required values, named consistently with how
      they'll appear in subscription URLs/config parsing later.
- [ ] Zero Flutter dependency, verified the same way as P1-T2.
- [ ] Unit tests cover construction, equality, and (if a sealed per-protocol payload is chosen)
      exhaustive pattern matching.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- If genuinely torn between a generic `Map`-based payload vs. a fully-typed sealed class per
  protocol, this is exactly the kind of ambiguous architectural fork the no-guessing rule exists
  for — present both options with tradeoffs and stop for a human decision rather than picking
  silently. A reasonable default recommendation to offer: typed sealed per-protocol config
  classes, since that gives Phase 2 compile-time safety, but confirm before implementing.

---

### P1-T4 — VpnEngine abstract interface and supporting command/result types

**Status:** Not Started
**Depends On:** P1-T2

**Objective:** Implement the abstract `VpnEngine` interface in `packages/core_vpn_engine`,
exactly matching the design finalized in `ARCHITECTURE.md` Section 3 and 3.5 (as patched):
separate `connectionState` and `trafficStats` streams, `start`/`stop` methods returning an
immediate command-acceptance result (`accepted` / `rejectedBusy` / `rejectedInvalidConfig` /
`rejectedPermissionDenied` / `failed`) distinct from the asynchronously-streamed final state, and
a `getStatus()` query method.

**Scope:**
- Included: `packages/core_vpn_engine/lib/src/vpn_engine.dart` (abstract interface),
  `packages/core_vpn_engine/lib/src/vpn_command_result.dart` (sealed result type), depends on
  `packages/core_domain` for `ConnectionState`/`TrafficStats`/`ServerProfile`, barrel export.
- Excluded: any concrete implementation (Android platform-channel implementation is Phase 3;
  the in-memory mock implementation is the next task, P1-T5).

**Acceptance Criteria:**
- [ ] `VpnEngine` is an abstract interface (`abstract interface class` or equivalent) exposing:
      `Stream<ConnectionState> get connectionState`, `Stream<TrafficStats> get trafficStats`,
      `Future<VpnCommandResult> start(ServerProfile profile)`,
      `Future<VpnCommandResult> stop()`, `Future<ConnectionState> getStatus()`.
- [ ] `VpnCommandResult` is a sealed class with exactly the five variants listed above (matching
      `ARCHITECTURE.md` Section 3.5 patch verbatim).
- [ ] No platform-channel, dart:ffi, or any concrete I/O code exists in this package — it is a
      pure contract package, dependency-free apart from `core_domain`.
- [ ] Doc comments on every public member explain the accepted-vs-final-state distinction clearly
      enough that a future agent implementing a concrete engine cannot misread it.
- [ ] `melos run analyze` and `melos run test` pass (tests here can only cover the sealed type
      shape itself, since there's no implementation yet).

**Notes for Agent:**
- This is one of the most important files in the whole project — the legacy failure was rooted
  in exactly this kind of contract being ambiguous. Take extra care that the interface makes
  incorrect usage hard: e.g. there should be no way for calling code to treat `accepted` as
  "connected."

---

### P1-T5 — MockVpnEngine reference implementation

**Status:** Not Started
**Depends On:** P1-T4

**Objective:** Implement `MockVpnEngine implements VpnEngine` in `packages/core_vpn_engine`, a
fully in-memory, no-native-dependency implementation that simulates realistic state transitions
with artificial delays, so that Phase 4/5 app-skeleton and UI work can proceed and be fully
tested before the real Phase 3 Android engine exists.

**Scope:**
- Included: `packages/core_vpn_engine/lib/src/mock_vpn_engine.dart`, configurable simulated
  latency and configurable simulated failure modes (e.g. a constructor flag to simulate
  `rejectedInvalidConfig` or a mid-connection `Error` state, for testing error-handling UI later),
  full unit tests of its own state-machine correctness (no illegal transitions, e.g. it must be
  impossible for it to go `Connected` → `Connecting` without passing through `Disconnecting`/
  `Disconnected` first, mirroring the real invariant the Android engine must also respect).
- Excluded: anything resembling real network I/O — this must remain a pure, fast, deterministic
  test double.

**Acceptance Criteria:**
- [ ] `MockVpnEngine` implements every member of `VpnEngine` per P1-T4's contract exactly.
- [ ] Unit tests prove: calling `start` while already `Connecting`/`Connected` returns
      `rejectedBusy` and does not corrupt internal state; `stop` is idempotent; simulated failure
      modes produce the correct `ConnectionState.Error` variant with correct reason.
- [ ] State transition sequence is enforced internally (illegal transitions either throw a clear
      programmer-error exception in debug builds or are structurally impossible — document which
      approach was chosen and why).
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- Treat this mock's internal state machine with the same rigor as the real Android one will
  eventually need — this is a good low-risk place to prove out the state-machine logic and
  invariants before they matter for real (with real TUN interfaces and real user impact) in
  Phase 3.

---

### P1-T6 — Feature-first folder structure convention + reference feature skeleton

**Status:** Not Started
**Depends On:** P0-T10, P1-T4

**Objective:** Establish, inside `apps/mobile/lib`, the concrete feature-first Clean
Architecture folder convention referenced in `ARCHITECTURE.md` (strict `data` / `domain` /
`presentation` layering per feature), by creating one fully-structured but functionally-empty
reference feature — `connection` — that later Phase 4/5 tasks will fill in with real logic.

**Scope:**
- Included: `apps/mobile/lib/features/connection/data/` (empty, with a `.gitkeep` or a short
  README explaining what belongs here — repository implementations, data sources),
  `apps/mobile/lib/features/connection/domain/` (empty, with README — entities re-exported or
  feature-specific use-case classes), `apps/mobile/lib/features/connection/presentation/` (empty,
  with README — widgets, Riverpod providers/notifiers, screens), a top-level
  `apps/mobile/lib/features/README.md` documenting the convention itself (what goes in each
  layer, the rule that `presentation` never imports `data` directly, only through `domain`).
- Excluded: any actual widget, provider, or repository code — this task only builds the skeleton
  and the documented convention, to be filled in starting Phase 4.

**Acceptance Criteria:**
- [ ] The three-layer folder structure exists under `features/connection/` with clear README
      content in each (not just empty folders with no explanation).
- [ ] `features/README.md` states the layering rule explicitly and unambiguously, including the
      "presentation never imports data directly" rule, and gives a one-line rationale (testability,
      replaceability of data sources without touching UI).
- [ ] `melos run analyze` still passes (no code was added that could fail analysis, but confirm
      nothing broke).
- [ ] A brief addendum is added to `CODING_STANDARDS.md` (or confirmed already present — check
      first, don't duplicate) pointing to this concrete example as the canonical reference
      structure for all future features.

**Notes for Agent:**
- Do not create additional example features beyond `connection` in this task — one clean,
  well-documented reference is deliberately sufficient; more would be premature scope creep.

---

### P1-T7 — Riverpod dependency-injection wiring skeleton

**Status:** Not Started
**Depends On:** P1-T5, P1-T6

**Objective:** Wire up the root Riverpod `ProviderScope` in `apps/mobile`'s `main.dart`, and
create the core provider(s) that expose a `VpnEngine` instance to the rest of the app — using
`MockVpnEngine` as the bound implementation for now — following the code-generation-only
Riverpod convention from `CODING_STANDARDS.md`.

**Scope:**
- Included: `apps/mobile/lib/main.dart` updated to wrap the app in `ProviderScope`,
  `apps/mobile/lib/core/providers/vpn_engine_provider.dart` (or equivalent location matching the
  agreed folder convention) exposing the `VpnEngine` via a `@riverpod` provider currently bound to
  `MockVpnEngine`, with a clear, single, documented seam where Phase 3's real Android
  implementation will later be substituted (e.g. via provider override, not a hardcoded
  conditional).
- Excluded: any UI code consuming the provider yet (that starts in Phase 4/5); no real engine
  implementation.

**Acceptance Criteria:**
- [ ] App builds and runs (on the connected Android device/emulator) showing the current default
      Flutter scaffold (no real UI yet), with `ProviderScope` active and no runtime provider
      errors.
- [ ] The `VpnEngine` provider is code-generated (`@riverpod`), not a hand-written
      `Provider((ref) => ...)`.
- [ ] A doc comment at the provider definition explicitly states: "This is bound to
      `MockVpnEngine` until Phase 3; do not implement real platform-channel logic here — override
      this provider's implementation at the composition root when Phase 3 is ready."
- [ ] `dart run build_runner build --delete-conflicting-outputs` succeeds.
- [ ] `melos run analyze` and `melos run test` pass; app runs without crashing.

**Notes for Agent:**
- This task is the first point where `apps/mobile` actually depends on `core_vpn_engine` and
  `core_domain` — confirm the pubspec dependency wiring resolves cleanly via Melos before writing
  provider code.

---

### P1-T8 — go_router skeleton with placeholder routes

**Status:** Not Started
**Depends On:** P1-T7

**Objective:** Wire up `go_router` in `apps/mobile` with two placeholder routes — `/` (Home) and
`/settings` (Settings) — each rendering a minimal, clearly-labeled placeholder screen (plain
`Scaffold` with a text label), so that later phases have real navigation infrastructure to build
features into without needing to design routing from scratch.

**Scope:**
- Included: `apps/mobile/lib/core/router/app_router.dart` (or agreed location), two placeholder
  screen widgets under `features/connection/presentation/` (Home) and a new minimal
  `features/settings/presentation/` skeleton (Settings) — note: `settings` as a feature folder is
  created here only to the extent needed for this placeholder screen; its full data/domain layers
  per the P1-T6 convention can be added later when Settings gets real functionality.
- Excluded: any real settings content, any deep-linking configuration, any route guards.

**Acceptance Criteria:**
- [ ] App launches directly into the Home placeholder route.
- [ ] Navigating to `/settings` (via a simple button on Home, for manual verification only) shows
      the Settings placeholder and back-navigation works correctly.
- [ ] Router is defined using `go_router`'s recommended current API (verify current
      recommended patterns — e.g. `GoRouter.routingConfig` vs. constructor-based route lists —
      rather than assuming a possibly-outdated pattern from training data).
- [ ] `melos run analyze` and `melos run test` pass; manual run confirms navigation works on
      device/emulator.

**Notes for Agent:**
- Keep both placeholder screens intentionally ugly/minimal — any time spent on visual polish here
  is out of scope until Phase 11.

---

### P1-T9 — Logging skeleton (logger) with redaction hook stub

**Status:** Not Started
**Depends On:** P0-T10

**Objective:** Wire up the chosen logging library (`logger`, confirmed dev-tooling choice) in
`apps/mobile`, active only in debug/profile builds by default, with a stubbed-out redaction
function that later phases (Phase 3 native logs, Phase 8 security hardening) will extend to
actually redact sensitive fields (server credentials, keys) per `SECURITY.md`'s logging/redaction
policy.

**Scope:**
- Included: `apps/mobile/lib/core/logging/app_logger.dart` (or equivalent), the `logger` package initialized
  and accessible via a simple provider or singleton (justify the choice), a `redact(String input)`
  stub function (can be a no-op returning input unchanged for now, but must be clearly marked
  `// TODO(security): implement real redaction — see SECURITY.md logging policy` and referenced
  from a Phase 8 task placeholder), confirmation that logging is disabled/no-op in release builds
  by default (or gated behind an explicit debug flag).
- Excluded: any actual sensitive-data logging yet (nothing sensitive exists in the app at this
  phase anyway), any log-export/diagnostic-bundle feature (later phase).

**Acceptance Criteria:**
- [ ] Logger is initialized once at app startup, accessible from anywhere via a documented,
      consistent access pattern (not ad-hoc logger instances scattered around).
- [ ] Release-mode builds do not emit logs (verified by checking build-mode conditionals, e.g.
      `kReleaseMode`), consistent with the no-telemetry, privacy-first stance.
- [ ] The redaction stub function exists, is clearly marked as incomplete, and is referenced by
      name in a note added to `PROJECT_STATE.md`'s "what does NOT exist yet" or open-questions
      section so it isn't forgotten by Phase 8.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- Do not attempt to implement real redaction logic now — there's nothing sensitive to redact yet,
  and doing it prematurely without the full picture (Phase 3 native log formats, Phase 2 config
  contents) risks a redaction scheme that doesn't actually cover the real sensitive fields later.

---

### P1-T10 — easy_localization skeleton wiring

**Status:** Not Started
**Depends On:** P1-T8

**Objective:** Wire up `easy_localization` in `apps/mobile` with a single locale (`en`) and a
minimal translation file covering only the strings already used by the Phase 1 placeholder
screens, establishing the convention for how all future user-facing strings must be added (no
hardcoded strings in widgets from this point forward).

**Scope:**
- Included: `apps/mobile/assets/translations/en.json` (or agreed path/format), `easy_localization`
  initialization in `main.dart`, updating the two placeholder screens from P1-T8 to use
  `.tr()`-style lookups instead of hardcoded strings, a short rule added to `CODING_STANDARDS.md`
  (or confirmed already present) forbidding hardcoded user-facing strings from this point on.
- Excluded: any additional locales beyond `en` — multi-language support is out of current MVP
  scope unless the human decides otherwise later.

**Acceptance Criteria:**
- [ ] App runs with all placeholder-screen text sourced from `en.json`, not hardcoded.
- [ ] Adding a new translation key and using it in a widget is demonstrated to work end-to-end
      (part of the task's own verification, using one of the existing placeholder strings).
- [ ] `melos run analyze` and `melos run test` pass; manual run confirms text renders correctly.
- [ ] The "no hardcoded user-facing strings" rule is explicitly stated in `CODING_STANDARDS.md`.

**Notes for Agent:**
- Verify current `easy_localization` setup steps against its current published documentation —
  asset loading/codegen setup for this package has changed across versions historically.

---

### P1-T11 — Phase 1 closeout and Definition-of-Done pass

**Status:** Not Started
**Depends On:** P1-T1 through P1-T10

**Objective:** Perform a full closeout review of Phase 1: confirm every task above is genuinely
`Completed`, run the full DoD checklist against the repository, verify the app runs end-to-end on
a real device/emulator showing placeholder navigation wired to the mock VPN engine, and update
`PROJECT_STATE.md` to reflect that Phase 1 is finished and Phase 2 is about to begin.

**Scope:**
- Included: full repository verification pass (fresh clone → `melos bootstrap` → `analyze` →
  `format` → `test` → manual app run), `PROJECT_STATE.md` rewritten to reflect the new baseline.
- Excluded: starting any Phase 2 work.

**Acceptance Criteria:**
- [ ] Fresh clone builds and passes all Melos scripts with zero manual intervention.
- [ ] App launches on a real Android device/emulator, shows Home placeholder, navigates to
      Settings placeholder and back, all text sourced from localization, no crashes, no analyzer
      warnings.
- [ ] `core_domain` and `core_vpn_engine` packages remain provably pure-Dart (no Flutter
      dependency) — re-verify, don't just trust earlier tasks' claims.
- [ ] CI is green on `master` (the repository's actual default branch).
- [ ] `PROJECT_STATE.md` fully rewritten as a coherent current snapshot.
- [ ] Closeout report follows the exact `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
- Pay particular attention to re-verifying the "pure Dart, no Flutter dependency" property of
  `core_domain`/`core_vpn_engine` — this is a load-bearing architectural invariant for future
  desktop/FFI work and is cheap to silently violate by accident (e.g. an errant import) without
  tooling catching it unless explicitly checked.

---

## Phase 2 — Config Parser Engine

**Phase Goal:** a pure-Dart, fully independently-testable library (`packages/config_parser`)
that turns raw text (a single URI, a subscription blob, or pasted text containing one) into
validated `ServerProfile` domain entities — with zero UI, zero network I/O side effects beyond
the explicit subscription-fetch task, and zero dependency on `core_vpn_engine` or Flutter.

**Cross-cutting security constraint for the entire phase (per `SECURITY.md`):** every parser
function in this package must be a pure function with no side effects, must defensively handle
malformed/adversarial input without throwing uncaught exceptions or hanging, must enforce bounded
resource usage (max input length, max nesting depth, max list size), and must never evaluate,
`eval`, or dynamically execute any part of the input. Treat every input to this package as
untrusted, including subscription content from a server the user explicitly added — a malicious
or compromised subscription source is an explicit item in `SECURITY.md`'s threat model.

**Format-research caveat (applies to every parsing task below):** VLESS/VMess/Trojan/Shadowsocks/
Hysteria2/TUIC URI formats are **community conventions, not formal RFCs**, and have drifted/been
extended over time across different client implementations (e.g. differing query-parameter names
for the same concept). Do not rely purely on possibly-stale training knowledge of these formats —
each parsing task below includes an explicit research/verification step against current sing-box
documentation and/or multiple real-world example URIs before writing the parser, per the
no-guessing rule.

---

### P2-T1 — Shared parsing error taxonomy and defensive-parsing utilities

**Status:** Not Started
**Depends On:** P1-T3, P1-T11

**Objective:** Before any protocol-specific parser is written, establish the shared error type
(`ConfigParseError`, a sealed class covering categories like `malformedUri`, `unsupportedScheme`,
`missingRequiredField`, `invalidFieldValue`, `inputTooLarge`, `unknown`) and a small set of shared
defensive-parsing helper functions (safe base64 decode with size limits, safe URI parsing with
length limits, bounded JSON parsing) that every protocol parser in this phase will reuse, so
input-size/malformed-input handling is consistent and centralized rather than reimplemented per
protocol.

**Scope:**
- Included: `packages/config_parser/lib/src/errors/config_parse_error.dart`,
  `packages/config_parser/lib/src/utils/safe_decoding.dart` (or equivalent), constants for
  maximum allowed input lengths (e.g. max single-URI length, max subscription blob size — pick
  concrete, justified numbers and document the reasoning), unit tests for every helper covering
  both valid and adversarial inputs (oversized input, deeply nested/malformed base64, non-UTF8
  bytes, empty input, null bytes).
- Excluded: any protocol-specific parsing logic (VLESS, VMess, etc. — those are separate tasks
  below and must depend on this task's output).

**Acceptance Criteria:**
- [ ] `ConfigParseError` is a sealed class using `Result<ServerProfile, ConfigParseError>` (from
      `packages/shared_utils`, P1-T1) as the return type convention for every parser function
      going forward — no parser function in this package may throw for expected/malformed input.
- [ ] Defensive helpers reject oversized input safely (return `Err`, not an exception, not a
      hang, not unbounded memory growth) — proven by a unit test that feeds multi-megabyte
      adversarial input and asserts the function returns quickly with a size-limit error.
- [ ] Base64 decoding helper handles both standard and URL-safe base64, with and without padding
      (a real-world compatibility need for VMess/subscription content), and rejects invalid
      base64 gracefully.
- [ ] Zero Flutter dependency; zero use of `dart:mirrors`, `dart:isolate`-based code execution, or
      any form of dynamic code evaluation.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- Pick concrete max-length constants now (e.g. 8 KB for a single server URI, a documented larger
  bound for subscription blobs — justify the numbers based on realistic legitimate use, not
  arbitrarily) — this is a real security decision the human should be able to review, so state
  the reasoning clearly in the task report even though it doesn't need a live discussion first.

---

### P2-T2 — VLESS URI parser

**Status:** Not Started
**Depends On:** P2-T1

**Objective:** Research the current VLESS URI format (as consumed by sing-box specifically —
verify against sing-box's own documentation/config schema rather than a generic community
gist, since sing-box is the actual runtime target) and implement
`parseVlessUri(String uri) -> Result<ServerProfile, ConfigParseError>` in
`packages/config_parser`, mapping every field sing-box's VLESS outbound config accepts (UUID,
address, port, encryption, flow, network/transport type, TLS/Reality settings, SNI, etc.) into
the typed per-protocol config payload established in `packages/core_domain` (P1-T3).

**Scope:**
- Included: `packages/config_parser/lib/src/parsers/vless_parser.dart`, unit tests using a
  curated set of real-world example VLESS URIs (plain TCP, WebSocket, gRPC, Reality/XTLS variants
  if sing-box supports them — verify current support), a short markdown note in
  `packages/config_parser/README.md` (create if absent) documenting the exact URI shape this
  parser targets and its source of truth.
- Excluded: VMess/Trojan/etc. parsers (separate tasks); subscription-level parsing (separate
  task); any UI for adding a server manually (later phase).

**Acceptance Criteria:**
- [ ] Parser correctly extracts every field sing-box's VLESS outbound schema requires or
      optionally accepts, verified against current sing-box documentation (cite what was checked
      in the task report).
- [ ] Malformed/incomplete VLESS URIs (missing UUID, invalid port, unknown transport type) return
      a specific, correctly-categorized `ConfigParseError`, never throw.
- [ ] Unit tests include at least 5 distinct real-world-shaped example URIs covering different
      transport/TLS combinations, plus at least 5 deliberately malformed inputs.
- [ ] Output `ServerProfile` round-trips correctly (i.e., re-serializing it back into a config
      sing-box would accept, if a serializer exists yet — if not yet built, at minimum verify all
      required fields are present and correctly typed).
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- If sing-box's actual accepted VLESS parameter set differs meaningfully from what training data
  suggests, trust the verified current documentation and flag the discrepancy in the report
  rather than silently reconciling it — this is exactly the kind of drifted/undocumented-format
  situation the phase-level caveat above warns about.

---

### P2-T3 — VMess URI parser

**Status:** Not Started
**Depends On:** P2-T1

**Objective:** Research and implement `parseVmessUri(String uri) -> Result<ServerProfile,
ConfigParseError>`, handling the base64-encoded-JSON VMess URI convention (`vmess://<base64
JSON>`), verified against sing-box's current VMess outbound config schema.

**Scope:**
- Included: `packages/config_parser/lib/src/parsers/vmess_parser.dart`, reuse of the safe
  base64/JSON decoding helpers from P2-T1, unit tests with real-world-shaped example URIs and
  malformed inputs (invalid base64, valid base64 but invalid/incomplete JSON, JSON with
  unexpected types in a field), README note documenting the exact JSON shape targeted.
- Excluded: other protocol parsers; subscription-level parsing.

**Acceptance Criteria:**
- [ ] Parser correctly handles the base64-JSON structure, including known field-naming
      inconsistencies across VMess client implementations if discovered during research (document
      which variants are supported and which are explicitly not, rather than silently guessing).
- [ ] Bounded JSON parsing from P2-T1 is reused, not reimplemented.
- [ ] Malformed input (bad base64, malformed JSON, missing required fields, oversized JSON) all
      return correctly-categorized `Err` results, never throw or hang.
- [ ] Unit tests include at least 5 valid example URIs and at least 5 malformed/adversarial ones.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- VMess URI JSON field naming has historically had inconsistent short-key conventions across
  different client authors (e.g. abbreviated field names). Verify against sing-box's actual
  expected input rather than assuming a single "standard" — if sing-box only accepts one specific
  shape, document that constraint clearly so users understand which exported VMess links will and
  won't work.

---

### P2-T4 — Trojan URI parser

**Status:** Not Started
**Depends On:** P2-T1

**Objective:** Research and implement `parseTrojanUri(String uri) -> Result<ServerProfile,
ConfigParseError>` for the `trojan://` URI convention, verified against sing-box's current Trojan
outbound config schema.

**Scope:**
- Included: `packages/config_parser/lib/src/parsers/trojan_parser.dart`, unit tests, README note.
- Excluded: other protocol parsers; subscription-level parsing.

**Acceptance Criteria:**
- [ ] Parser correctly extracts password, host, port, and TLS/transport-related query parameters
      per sing-box's current Trojan schema.
- [ ] Malformed input returns correctly-categorized `Err` results.
- [ ] Unit tests include at least 5 valid example URIs (covering plain and WebSocket-transport
      variants if sing-box supports them) and at least 5 malformed inputs.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- Trojan URIs are comparatively simple relative to VLESS/VMess; resist the urge to add
  speculative field support beyond what sing-box's schema actually documents.

---

### P2-T5 — Shadowsocks (SIP002) URI parser

**Status:** Not Started
**Depends On:** P2-T1

**Objective:** Research and implement `parseShadowsocksUri(String uri) -> Result<ServerProfile,
ConfigParseError>` for the `ss://` URI convention (SIP002 standard, with awareness of the older
legacy fully-base64 `ss://` format some clients still export), verified against sing-box's
current Shadowsocks outbound schema and supported cipher list.

**Scope:**
- Included: `packages/config_parser/lib/src/parsers/shadowsocks_parser.dart`, handling both the
  SIP002 format (`ss://base64(method:password)@host:port`) and the legacy fully-base64-encoded
  format, unit tests, README note documenting which cipher methods sing-box currently supports
  (reject unsupported ciphers with a specific `ConfigParseError`, not a generic failure).
- Excluded: other protocol parsers; subscription-level parsing.

**Acceptance Criteria:**
- [ ] Both SIP002 and legacy formats are correctly detected and parsed.
- [ ] An unsupported/unknown cipher method produces a specific, user-actionable
      `ConfigParseError` variant (e.g. `unsupportedCipher`), distinct from generic malformed-input
      errors.
- [ ] Unit tests cover both formats with at least 3 valid examples each, plus malformed inputs
      (invalid cipher, invalid base64, missing port).
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- Verify sing-box's actual currently-supported Shadowsocks cipher list rather than assuming the
  full historical Shadowsocks cipher set is supported — sing-box may have deprecated some.

---

### P2-T6 — Hysteria2 URI parser

**Status:** Not Started
**Depends On:** P2-T1

**Objective:** Research and implement `parseHysteria2Uri(String uri) -> Result<ServerProfile,
ConfigParseError>` for the `hysteria2://` (or `hy2://`) URI convention, verified against
sing-box's current Hysteria2 outbound config schema, including its QUIC/TLS-specific parameters
(obfuscation, ports, bandwidth hints if part of the URI convention).

**Scope:**
- Included: `packages/config_parser/lib/src/parsers/hysteria2_parser.dart`, unit tests, README
  note. Explicitly cross-check the Go-toolchain footgun noted in `TOOLCHAIN_VERSIONS.md`
  (P0-T8) — this protocol is QUIC-based, so the parser's correctness matters even more given that
  known Android-build risk downstream.
- Excluded: other protocol parsers; subscription-level parsing; anything related to the actual
  QUIC connection/runtime behavior (that's Phase 3's concern, this task is parsing only).

**Acceptance Criteria:**
- [ ] Parser correctly handles both `hysteria2://` and `hy2://` scheme variants if sing-box/the
      ecosystem treats them as equivalent (verify, don't assume).
- [ ] Malformed input returns correctly-categorized `Err` results.
- [ ] Unit tests include at least 5 valid example URIs and at least 5 malformed inputs.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- This is one of the two protocols explicitly named in the project's core goals (alongside TUIC)
  as newer/less standardized than VLESS/VMess/Trojan/SS — expect more format variance across
  real-world example URIs found during research, and document what's supported vs. not.

---

### P2-T7 — TUIC URI parser

**Status:** Not Started
**Depends On:** P2-T1

**Objective:** Research and implement `parseTuicUri(String uri) -> Result<ServerProfile,
ConfigParseError>` for the `tuic://` URI convention, verified against sing-box's current TUIC
outbound config schema (UUID+password authentication, congestion-control options, etc.).

**Scope:**
- Included: `packages/config_parser/lib/src/parsers/tuic_parser.dart`, unit tests, README note.
- Excluded: other protocol parsers; subscription-level parsing.

**Acceptance Criteria:**
- [ ] Parser correctly extracts UUID, password, host, port, and TUIC-specific query parameters
      per sing-box's current schema.
- [ ] Malformed input returns correctly-categorized `Err` results.
- [ ] Unit tests include at least 5 valid example URIs and at least 5 malformed inputs.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- Same caveat as Hysteria2 regarding format variance — verify against sing-box specifically.

---

### P2-T8 — Unified scheme-dispatch entry point

**Status:** Not Started
**Depends On:** P2-T2, P2-T3, P2-T4, P2-T5, P2-T6, P2-T7

**Objective:** Implement a single public entry point,
`parseServerUri(String rawInput) -> Result<ServerProfile, ConfigParseError>`, in
`packages/config_parser`, that trims/normalizes input, detects the URI scheme, and dispatches to
the correct protocol-specific parser from the six tasks above — this becomes the one function the
rest of the app (UI "add server" flow, subscription parser) actually calls.

**Scope:**
- Included: `packages/config_parser/lib/src/parse_server_uri.dart` (public API, exported from the
  package's main barrel file), unit tests covering dispatch correctness for all six schemes plus
  an `unsupportedScheme` error for anything else, and graceful handling of surrounding whitespace/
  newlines/accidental extra text a user might paste alongside a URI.
- Excluded: subscription-blob-level parsing (multiple URIs at once — next task).

**Acceptance Criteria:**
- [ ] `parseServerUri` correctly dispatches to each of the six protocol parsers based on scheme.
- [ ] Unknown/unsupported schemes return `ConfigParseError.unsupportedScheme`, not a crash or a
      silent no-op.
- [ ] Leading/trailing whitespace and newlines around a single pasted URI are handled gracefully.
- [ ] This is the **only** function outside the package's own internals that external code should
      need to call for single-URI parsing — confirm the package's barrel export reflects a clean,
      minimal public API surface (protocol-specific parsers can remain internal/unexported if
      appropriate, or exported for advanced use — decide and document which).
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- This is the package's primary public contract going forward — treat its signature and error
  semantics as something later phases (UI, subscription handling) will depend on directly.

---

### P2-T9 — Subscription content parser

**Status:** Not Started
**Depends On:** P2-T8

**Objective:** Implement parsing of subscription **content** (not fetching — fetching over the
network is explicitly a separate concern, see P2-T10) — i.e., given raw text that is either a
base64-encoded newline-separated list of server URIs, or a plain newline-separated list of server
URIs, produce a `List<Result<ServerProfile, ConfigParseError>>` (preserving per-line success/
failure so a subscription with 40 good entries and 2 malformed ones doesn't fail everything).

**Scope:**
- Included: `packages/config_parser/lib/src/parse_subscription_content.dart`, reuse of P2-T1's
  bounded base64/size-limit helpers (subscription blobs are a larger, still-bounded, size class —
  confirm/set the specific limit here explicitly), unit tests covering both base64-wrapped and
  plain-text subscription formats, mixed valid/invalid line handling, and adversarial input
  (extremely long single "line" with no newlines, binary garbage, empty content).
- Excluded: actual HTTP fetching of a subscription URL (P2-T10); any Clash-style YAML
  subscription format unless the human explicitly confirms it's in scope (flag as an open
  question rather than silently implementing or silently skipping it).

**Acceptance Criteria:**
- [ ] Correctly parses a base64-encoded blob into individual URIs, then each URI via
      `parseServerUri`, returning per-entry results.
- [ ] Correctly parses a plain (non-base64) newline-separated list the same way.
- [ ] A subscription with some malformed entries returns partial success — valid entries are not
      discarded because of unrelated malformed entries elsewhere in the same blob.
- [ ] Adversarial inputs (oversized blob, no valid newlines, non-UTF8 bytes) are rejected safely
      and quickly, never hang or crash the process.
- [ ] `melos run analyze` and `melos run test` pass.
- [ ] Open question about Clash-style YAML subscription support is explicitly raised in the task
      report if encountered, not silently resolved.

**Notes for Agent:**
- Stop and ask the human before adding YAML/Clash-format subscription support — it's a
  meaningfully larger scope addition (new dependency, new format surface, new attack surface for
  untrusted YAML parsing) than plain-list/base64 subscriptions, and wasn't part of the originally
  scoped protocol list.

---

### P2-T10 — Subscription URL fetch (network boundary, explicitly isolated)

**Status:** Not Started
**Depends On:** P2-T9

**Objective:** Implement the network-fetching half of subscription support —
`fetchSubscriptionContent(Uri url) -> Result<String, ConfigParseError>` — as a clearly separated
concern from parsing (P2-T9), enforcing HTTPS-only, a request timeout, and a response-size cap,
per `SECURITY.md`'s network/DNS security and untrusted-input rules.

**Scope:**
- Included: a new, explicitly minimal networking capability — decide and document whether this
  belongs in `packages/config_parser` (kept pure otherwise) or a new small dedicated package/
  module boundary (e.g. `packages/config_parser`'s `data`-adjacent layer, or directly in
  `apps/mobile`'s `data` layer for the `connection`/a new `subscriptions` feature per the P1-T6
  convention) — present the tradeoff and pick one, documented clearly, since this is the first
  task in the project that performs real network I/O.
- Excluded: any UI for adding/managing subscriptions (later phase); TLS certificate pinning
  (explicitly deferred, note it as a future `SECURITY.md` hardening item if not already listed).

**Acceptance Criteria:**
- [ ] HTTP (non-TLS) subscription URLs are rejected outright with a specific error — HTTPS only,
      no fallback, no user override, per `SECURITY.md`.
- [ ] A request timeout (e.g. 15 seconds — justify the number) and a maximum response body size
      (justify the number, consistent with P2-T9's subscription-size bound) are both enforced.
- [ ] TLS certificate validation is not weakened or disabled anywhere in the implementation
      (explicitly verify no `badCertificateCallback`-style override exists).
- [ ] Fetched content is passed through P2-T9's parser, not parsed ad-hoc inline.
- [ ] Unit/integration tests cover: successful fetch of a mocked HTTPS endpoint, timeout
      behavior, oversized-response rejection, and HTTP-scheme rejection (using a mock HTTP client,
      not live network calls, so tests remain deterministic and offline-runnable).
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- This task is the first place real network I/O and therefore real remote-attacker-controlled
  input enters the app — treat every acceptance criterion above as a security requirement, not a
  nice-to-have, and re-read `SECURITY.md`'s relevant sections before implementing.

---

### P2-T11 — Adversarial/fuzz-style test pass across the whole package

**Status:** Not Started
**Depends On:** P2-T2 through P2-T10

**Objective:** Perform a dedicated adversarial-input test-hardening pass across every parser in
`packages/config_parser`, beyond the malformed-input cases already written per-parser, explicitly
looking for: unbounded loops, unbounded memory allocation, stack overflow from deeply nested/
recursive input, and any code path that could throw an unhandled exception instead of returning
`Err`.

**Scope:**
- Included: additional test files (or an extension of existing ones) specifically targeting
  cross-cutting adversarial patterns (extremely long strings with no delimiters, deeply nested
  percent-encoding, malformed UTF-8/UTF-16 surrogate pairs, null bytes mid-string, control
  characters), applied across all six protocol parsers plus the subscription parser; any bugs
  found are fixed within this package.
- Excluded: any changes outside `packages/config_parser`.

**Acceptance Criteria:**
- [ ] For every parser, at least one deliberately pathological input is tested and confirmed to
      return a fast, bounded `Err` result rather than hanging, crashing, or consuming excessive
      memory (define and use a concrete test timeout, e.g. asserting the test completes within a
      short wall-clock bound, as a proxy for "no pathological slowdown").
- [ ] Any bug discovered during this pass is fixed, with a regression test added.
- [ ] A short written summary of what adversarial categories were tested is added to
      `packages/config_parser/README.md` or a `SECURITY_NOTES.md` within the package.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- This task exists precisely because `config_parser` handles untrusted input per `SECURITY.md` —
  treat it with genuine adversarial-mindset rigor, not as a formality. If you find yourself
  unable to construct a meaningfully pathological test case for a given parser, say so explicitly
  in the report rather than padding the task with trivial tests.

---

### P2-T12 — Phase 2 closeout and Definition-of-Done pass

**Status:** Not Started
**Depends On:** P2-T1 through P2-T11

**Objective:** Perform a full closeout review of Phase 2: confirm every task above is genuinely
`Completed`, confirm `packages/config_parser` remains pure Dart with zero Flutter/UI dependency
and zero dependency on `core_vpn_engine`, and update `PROJECT_STATE.md` to reflect that Phase 2
is finished and Phase 3 (the highest-risk phase) is about to begin.

**Scope:**
- Included: full repository verification pass, a consolidated `packages/config_parser/README.md`
  documenting the full public API (`parseServerUri`, `parseSubscriptionContent`,
  `fetchSubscriptionContent`) and every supported protocol with a link to its source-of-truth
  documentation used during research, `PROJECT_STATE.md` rewritten to reflect the new baseline.
- Excluded: starting any Phase 3 work.

**Acceptance Criteria:**
- [ ] Fresh clone builds and passes all Melos scripts with zero manual intervention.
- [ ] `packages/config_parser` has zero `package:flutter/*` imports and zero dependency on
      `packages/core_vpn_engine`, verified explicitly (not just assumed from earlier tasks).
- [ ] All six protocol parsers plus subscription content parsing plus subscription fetching are
      demonstrated working via the test suite, with a documented, non-trivial adversarial test
      pass per P2-T11.
- [ ] CI is green on `master` (the repository's actual default branch).
- [ ] `PROJECT_STATE.md` fully rewritten as a coherent current snapshot, explicitly flagging that
      Phase 3 (Android VPN Engine) is the next and highest-risk phase, and that its two-gate
      structure (native-only lifecycle gate, then Platform-Channel/Flutter integration gate) must
      be followed strictly per `ARCHITECTURE.md`.
- [ ] Closeout report follows the exact `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
- Before closing this phase, double-check that no protocol parser silently diverges from what
  sing-box actually accepts at runtime — since Phase 3 will be the first point real sing-box
  config validation happens, any parser inaccuracies discovered there will be more expensive to
  trace back. If time allows, cross-referencing a couple of parsed outputs against sing-box's
  documented JSON config schema (even without running sing-box itself yet) is valuable, though
  not a hard blocking requirement for this closeout.

---

## Phase 3 — Android VPN Engine

**Phase Goal:** a Kotlin `VpnService` implementation, driving sing-box's `libbox` Go core, proven
correct and resilient under real lifecycle stress — **before** it is ever wired to Flutter. This
is the highest-risk phase in the project and directly targets the root cause of the legacy
project's failure (native bridge/lifecycle engineering, not the core concept).

**Structure:** this phase is split into two sequential gates, per the finalized `ARCHITECTURE.md`
decision:

- **Gate A (this chunk):** a native-only lifecycle harness — a minimal Kotlin Android module and
  debug activity/instrumented test suite, with **zero Flutter involvement** — used to prove the
  `VpnService` + `libbox` state machine is correct in isolation.
- **Gate B (next chunk):** wiring the proven native engine to Flutter via Pigeon-generated
  Platform Channels, then re-running equivalent lifecycle stress tests through the full stack.

**Non-negotiable rule for this entire phase:** Gate B may not begin until every acceptance
criterion in Gate A is met and the Gate A closeout task is `Completed`. This ordering exists
specifically to isolate native lifecycle bugs from Dart/platform-channel bugs, per peer-review
findings — do not shortcut it even if it looks slower.

---

### Gate A — Native-Only Android VPN Lifecycle Harness

---

### P3-T1 — Research pass: sing-box/libbox current integration state

**Status:** Not Started
**Depends On:** P2-T12

**Objective:** Before writing any code, produce a written research report (not yet committed as
project documentation — a working note for the human and next tasks) verifying, as of the actual
current date, the following facts against live/current sources (sing-box repo, its release notes,
official docs, and Hiddify's public Android source if license-compatible to reference):

1. The current stable sing-box release/tag recommended for mobile integration, and its exact
   mobile platform-interface shape (confirm whether the `adapter.PlatformInterface` migration
   noted in peer review is present in the version being targeted, or has moved further since).
2. The current recommended `gomobile`/`golang.org/x/mobile` version and fork (verify whether
   sing-box's own pinned fork, as referenced in peer review, is still the right one to use).
3. The current recommended Go version to pin in CI, explicitly re-confirming the
   go.mod-auto-resolution QUIC-breakage footgun is still relevant and what Go version avoids it.
4. Current Android NDK version compatible with that Go/gomobile combination.
5. Whether 16KB page-size-aligned `.so` output requires any special gomobile/NDK build flags with
   the versions selected, and how to verify alignment on a built `.so` file.
6. Confirmation of whether Hiddify's Android `VpnService` source is publicly available and under
   a license compatible with reference study (and, separately, whether any direct code reuse —
   as opposed to reading for understanding — would be desirable and license-compatible; default
   assumption is read-only reference, not reuse, unless the human decides otherwise).

**Scope:**
- Included: a research report only — no code, no files under `native/android/` yet beyond
  updating `AI_ROLES/TOOLCHAIN_VERSIONS.md`'s `TBD` rows (P0-T8) with the now-confirmed values.
- Excluded: any actual AAR build attempt (next task); any Kotlin code.

**Acceptance Criteria:**
- [ ] `TOOLCHAIN_VERSIONS.md`'s previously-`TBD` rows (Go, gomobile, NDK, sing-box commit/tag) are
      filled in with specific, verified values and a one-line justification each.
- [ ] The two known footguns (Go auto-resolution/QUIC breakage, sing-box `platform.Interface` →
      `adapter.PlatformInterface` migration) are explicitly re-confirmed as still-relevant or
      noted as superseded, with the current situation described accurately.
- [ ] The 16KB page-size alignment requirement's current build-flag/verification method is
      documented.
- [ ] The report explicitly states what could **not** be verified with confidence, if anything,
      rather than filling gaps with assumptions.

**Notes for Agent:**
- This is a pure research task by design — resist the urge to jump ahead into implementation.
  Every fact recorded here becomes load-bearing for the rest of Phase 3, so accuracy matters more
  than speed.
- If live web/documentation access isn't available in the coding-agent environment, say so
  explicitly and report back to the human with specific questions to verify manually, rather than
  proceeding on unverified assumptions — this is exactly the no-guessing rule in its purest form.

---

### P3-T2 — Native Android module scaffolding (`native/android`)

**Status:** Not Started
**Depends On:** P3-T1

**Objective:** Set up `native/android/` as a standalone, buildable Android Gradle project
(application module, not yet a Flutter plugin), pinned to the versions confirmed in P3-T1
(NDK, AGP, Kotlin, target/compile/min SDK versions — verify current reasonable min-SDK choice
given `VpnService` requirements and realistic device support goals, don't assume).

**Scope:**
- Included: `native/android/` populated with a minimal Gradle Android application project
  (`build.gradle.kts`/`settings.gradle.kts`, standard module layout), Gradle wrapper checked in,
  Kotlin configured, no VPN logic yet — just a project that builds and installs a blank "Hello"
  activity on a device/emulator.
- Excluded: any libbox/AAR integration (next task); any VpnService code.

**Acceptance Criteria:**
- [ ] `native/android/` builds successfully via Gradle CLI (`./gradlew assembleDebug`) with zero
      manual IDE-only steps.
- [ ] The built debug APK installs and launches on the connected physical device/emulator (per
      `PROJECT_STATE.md`'s noted environment), showing a minimal placeholder screen.
- [ ] All pinned versions match exactly what P3-T1 recorded in `TOOLCHAIN_VERSIONS.md`.
- [ ] If the Iran-network Gradle-mirror issue (documented in `PROJECT_STATE.md`'s errors/lessons)
      recurs, it is resolved the same documented way (`maven.aliyun.com` mirror) and the
      resolution is re-confirmed still necessary/correct, not blindly copied without checking.
- [ ] A short `native/android/README.md` replaces the Phase-0 placeholder with real build/run
      instructions.

**Notes for Agent:**
- Keep this module fully independent of `apps/mobile` for now — no Flutter embedding, no
  `flutter create -t plugin` scaffolding yet. That happens in Gate B.

---

### P3-T3 — Build sing-box `libbox` AAR from pinned source

**Status:** Not Started
**Depends On:** P3-T2

**Objective:** Produce a reproducible build script that compiles the pinned sing-box commit/tag's
`libbox` package into an Android AAR via `gomobile bind`, using the pinned Go/gomobile/NDK
versions from P3-T1, and integrate the resulting AAR into `native/android/`'s debug build so a
trivial libbox API call (e.g. reading the core version string) can be verified from the
placeholder activity.

**Scope:**
- Included: a build script (e.g. `native/android/scripts/build_libbox_aar.sh` or equivalent,
  language/tooling choice justified in the report), the script's output AAR placed in a
  `.gitignore`d location (per P0-T1's `.gitignore` rule) with a documented manual-download/build
  step noted in the README (mirroring the legacy project's known "libbox.aar gitignored" reality,
  but now with a reproducible build script instead of an undocumented manual step), one Kotlin
  call into libbox proving linkage works (e.g. logging the core version).
- Excluded: any VpnService/TUN logic — this task only proves the AAR builds and links correctly.

**Acceptance Criteria:**
- [ ] The build script runs successfully end-to-end from a clean environment (document exact
      prerequisites: Go version installed, NDK path, etc.) and produces a valid AAR.
- [ ] The AAR is explicitly pinned to a specific sing-box git commit/tag recorded in the script
      itself and cross-referenced with `TOOLCHAIN_VERSIONS.md`.
- [ ] The placeholder Android app successfully calls into libbox and displays/logs the core
      version string, proving the JNI/gomobile bridge links correctly at runtime (no
      `UnsatisfiedLinkError`).
- [ ] The AAR's `.so` output is verified for 16KB page-size alignment per the method documented
      in P3-T1 (do not skip this — it is a hard Play Store requirement already in effect, not a
      future concern).
- [ ] `native/android/README.md` documents exactly how to (re)run the build script, including the
      Go-version-pinning safeguard (explicitly not relying on `go.mod` auto-resolution).
- [ ] The build script itself, or CI (if wired up here — optional at this stage, can be deferred
      to a later task if native Android CI is a separate concern), is noted as a candidate for
      future CI automation even if not yet automated in this task.

**Notes for Agent:**
- This task is likely to surface real, unpredictable friction (this is exactly the kind of step
  that broke down previously due to environment-specific issues). Document every real obstacle
  hit and how it was resolved, in detail, in the task report — this record is valuable for anyone
  (human or future agent) who has to rebuild this AAR later after a sing-box version bump.
- Do not silently work around a build failure by downgrading/upgrading a pinned version without
  flagging it — if a pinned version combination from P3-T1 turns out not to actually work
  together, stop and report back rather than silently picking different versions.

---

### P3-T4 — Study reference implementation(s) and record design notes

**Status:** Not Started
**Depends On:** P3-T1

**Objective:** Study Hiddify's public Android `VpnService`/libbox integration source (if publicly
available and license-compatible for reference-only study, per P3-T1's findings) and/or any other
credible open-source sing-box-based Android VPN client, specifically to extract lifecycle design
patterns — not to copy code — and produce a short design-notes document informing the state
machine to be built in the next tasks.

**Scope:**
- Included: a design-notes document (e.g. `native/android/docs/LIFECYCLE_DESIGN_NOTES.md`)
  summarizing: how the reference implementation handles TUN fd ownership/cleanup, how it
  structures its state machine, how it handles `onRevoke()`, how it avoids main-thread blocking,
  and any patterns explicitly worth adopting or explicitly worth avoiding (e.g. if the reference
  implementation has a known bug class, note it so Brick VPN doesn't inherit it).
- Excluded: copying any actual source code verbatim into Brick VPN's repository — this task is
  read-and-summarize only, respecting license obligations.

**Acceptance Criteria:**
- [ ] The design-notes document exists and is specific (not generic platitudes) — it should read
      as "here is concretely how a real production implementation solves problem X," for at least
      the following problems: TUN fd lifecycle, stop/teardown sequencing, revoke handling,
      threading model, and callback-after-teardown prevention.
- [ ] Any code excerpts quoted for illustration (if any, kept minimal) are clearly attributed with
      source and license, per GPL v3/attribution obligations.
- [ ] The document explicitly informs (with direct references) the state machine design in the
      next task (P3-T5), rather than existing as a disconnected research artifact.

**Notes for Agent:**
- If Hiddify's Android source turns out not to be easily accessible or not license-compatible for
  even read-only study, say so and fall back to whatever credible reference material can be
  verified (sing-box's own official example/reference Android integration code, if it exists, or
  documented architecture write-ups) — do not fabricate familiarity with source you have not
  actually verified access to.

---

### P3-T5 — VPN state machine design and implementation (pure Kotlin, no libbox/TUN yet)

**Status:** Not Started
**Depends On:** P3-T4

**Objective:** Implement the core state machine — `VpnStateMachine` — as a standalone, unit-
testable Kotlin class with **no libbox or Android `VpnService` dependency yet**, enforcing every
lifecycle rule established in `ARCHITECTURE.md` Section 3.5: explicit states (`Idle`, `Preparing`,
`Starting`, `Running`, `Stopping`, `Stopped`, `Error`, `Revoked`), session tokens on every
start/stop, idempotent start/stop, a 5-second stop watchdog, and rejection of illegal transitions
with the correct `accepted`/`rejectedBusy`/etc. semantics mirroring the Dart `VpnCommandResult`
contract from P1-T4.

**Scope:**
- Included: `native/android/app/src/main/kotlin/.../vpn/VpnStateMachine.kt` (or the module path
  appropriate once this becomes a shared library module — decide structure and justify),
  corresponding JVM unit tests (`native/android/app/src/test/kotlin/.../VpnStateMachineTest.kt`)
  using a real test framework (JUnit + kotlinx-coroutines-test for any async/timeout behavior),
  no Android instrumentation dependency yet (pure JVM unit tests, fast, no emulator required).
- Excluded: any real libbox call, any real TUN/VpnService interaction — this state machine must be
  fully provable in isolation first, exactly mirroring how `MockVpnEngine` (P1-T5) was proven in
  isolation on the Dart side.

**Acceptance Criteria:**
- [ ] States match exactly: `Idle`, `Preparing`, `Starting`, `Running`, `Stopping`, `Stopped`,
      `Error(reason)`, `Revoked` — implemented as a sealed class/interface, not raw enums with
      loosely-associated data, so illegal states are structurally harder to represent.
- [ ] Every `start`/`stop` command carries a session token; a stale-token callback/event fed into
      the state machine is provably ignored (unit test proves this explicitly).
- [ ] `start` while `Starting`/`Running` returns `rejectedBusy` without corrupting state.
- [ ] `stop` while `Stopping` is idempotent (calling it multiple times has no additional effect
      beyond the first).
- [ ] `stop` while `Starting` cancels the in-progress start and transitions cleanly, not into an
      inconsistent hybrid state.
- [ ] A simulated stop that "hangs" (test double never signals completion) is proven, via a
      coroutine-based test with virtual/fake time, to trigger the 5-second watchdog and forcibly
      transition to `Stopped`/`Error` regardless.
- [ ] Command-acceptance results (`accepted`/`rejectedBusy`/`rejectedInvalidConfig`/
      `rejectedPermissionDenied`/`failed`) are returned synchronously/immediately from
      `start`/`stop`, while final-state transitions are only ever emitted via a separate
      state-flow (`StateFlow`/`SharedFlow` or equivalent) — mirroring the Dart contract's
      accepted-vs-final-state separation exactly.
- [ ] All work is unit-testable on the JVM without an Android emulator (verified by actually
      running `./gradlew test`, not `connectedAndroidTest`).
- [ ] `melos`/Gradle equivalents pass; specifically `./gradlew :native-android-module:test`
      (path TBD based on actual module structure) is green.

**Notes for Agent:**
- This is the single most important file in the native codebase. Treat it with the rigor of
  something that will be read, audited, and possibly ported (conceptually) to iOS's
  `PacketTunnelProvider` lifecycle later — keep libbox/TUN/Android-framework specifics entirely
  out of this class; it should only know about abstract "start/stop the underlying engine"
  callbacks it invokes on a to-be-defined interface, not concrete libbox types.
- If any lifecycle rule from `ARCHITECTURE.md` Section 3.5 seems ambiguous or insufficiently
  specific to implement without guessing (e.g. exact watchdog duration, exact behavior on
  double-stop), stop and ask rather than picking silently — these are exactly the kind of
  decisions that caused the legacy project's undebuggable bugs.

---

### P3-T6 — VpnService skeleton wired to the state machine (no libbox yet)

**Status:** Not Started
**Depends On:** P3-T5, P3-T2

**Objective:** Implement a minimal Android `VpnService` subclass that wires real Android
lifecycle events (`onStartCommand`, `onDestroy`, `onRevoke`, foreground-service notification,
`VpnService.Builder`/`establish()`) to the `VpnStateMachine` from P3-T5, **without yet calling
into libbox at all** — using a fake/no-op "engine" (e.g. one that just waits a fixed delay to
simulate connecting) so the Android-framework-integration layer can be proven correct in
isolation from libbox-specific complexity.

**Scope:**
- Included: `BrickVpnService.kt` (or similarly named) extending `android.net.VpnService`, correct
  foreground-service notification setup (with whatever notification-permission handling the
  target Android API levels require, per P3-T1's research), a fake/stub "tunnel engine" interface
  implementation for this task only, explicit `ACTION_STOP` broadcast/intent handling +
  `stopSelf()` (never a bare `stopService()`, per the non-negotiable rule), retained
  `ParcelFileDescriptor` handle management (acquire via `establish()`, guaranteed close via
  try/finally on every code path).
- Excluded: any real libbox call (next task); any Flutter/platform-channel code.

**Acceptance Criteria:**
- [ ] Service correctly starts in the foreground with a valid, correctly-typed notification
      (confirm the correct foreground-service type declaration for VPN, per current Android
      requirements verified in P3-T1/at task time).
- [ ] `onRevoke()` is implemented and correctly triggers a clean stop through the state machine
      (not a separate, parallel teardown path).
- [ ] Explicit `ACTION_STOP` intent + `stopSelf()` handshake is implemented; no code path calls
      the deprecated/unsafe bare `stopService()` pattern documented as a legacy bug.
- [ ] The `ParcelFileDescriptor` obtained from `establish()` is guaranteed closed exactly once on
      every exit path (normal stop, error, revoke, service destroyed) — proven via targeted
      instrumented tests (see next bullet) and/or careful manual code review documented in the
      report.
- [ ] No blocking calls occur on the main thread anywhere in this class, including in
      `onDestroy()` — all state-machine interaction happens via coroutines on an appropriate
      dispatcher, verified by code review and, where feasible, a StrictMode-based check during
      manual testing.
- [ ] Android instrumented tests (`connectedAndroidTest`, requiring the device/emulator) prove:
      service starts and reaches `Running` (fake engine) state, `ACTION_STOP` cleanly stops it,
      `onRevoke()` cleanly stops it, and no `ParcelFileDescriptor` leak is observed (verified via
      `adb shell` fd inspection on the running process, as documented in the legacy project's own
      debugging notes).
- [ ] `./gradlew connectedAndroidTest` passes on the real connected device noted in
      `PROJECT_STATE.md`.

**Notes for Agent:**
- This task deliberately defers libbox entirely so that any bug found here is unambiguously an
  Android-framework/lifecycle bug, not a libbox integration bug — preserve this separation
  strictly; do not "just wire in libbox while I'm here" even if it seems convenient.

---

### P3-T7 — libbox integration: real tunnel engine wired into VpnService

**Status:** Not Started
**Depends On:** P3-T6, P3-T3

**Objective:** Replace the fake/stub tunnel engine from P3-T6 with a real implementation that
initializes libbox with a valid sing-box configuration (a hardcoded, known-good test config for
now — real user-supplied configs come from Phase 2's parser output later in Gate B), implements
whatever `PlatformInterface`/`adapter.PlatformInterface` (per P3-T1's confirmed current shape)
libbox requires from the host app, and correctly passes the TUN file descriptor from
`VpnService.Builder.establish()` into libbox.

**Scope:**
- Included: `LibboxTunnelEngine.kt` (or similarly named) implementing whatever engine interface
  `VpnStateMachine`/`VpnService` expects (defined in P3-T5/T6), correct libbox lifecycle calls
  (start/stop/close) dispatched off the main thread, correct handling of libbox callbacks
  (ensuring stale-session callbacks are discarded per the state machine's session-token rule),
  one hardcoded, known-valid sing-box test config (e.g. pointing at a test/self-hosted server the
  human provides, or a well-known public test endpoint if appropriate — confirm with human) used
  purely for lifecycle testing purposes.
- Excluded: any dynamic/user-supplied config loading (Gate B); any UI for config selection.

**Acceptance Criteria:**
- [ ] libbox successfully establishes a real tunnel using the hardcoded test config, verified by
      an actual change in the device's effective outbound IP (e.g. via a manual `curl
      ifconfig.me`-equivalent check before/after connecting, documented in the report) — this is
      the first point in the entire project where real network traffic actually flows through
      sing-box, and it must be explicitly, manually verified, not assumed from code review alone.
- [ ] libbox callbacks (state changes, errors) are correctly routed into `VpnStateMachine`,
      respecting session tokens (a stale callback from a previous session must be provably
      ignored, per P3-T5's contract).
- [ ] No libbox call (start, stop, config apply) blocks the main thread.
- [ ] The `ParcelFileDescriptor` handling rule from P3-T6 still holds with the real libbox engine
      in place — re-verified, not assumed to still work unchanged.
- [ ] The DNS-bootstrap-deadlock class of bug from the legacy project (`Semaphore`/thread-pool
      blocking in a custom `lookup()` implementation) is either not reintroduced (if the current
      libbox/adapter interface no longer requires a custom blocking DNS implementation) or, if it
      is still required, is implemented with explicit, tested interruptibility/timeout handling —
      confirm which situation applies based on P3-T1's research and document the decision.
- [ ] Any remote rule-set/geoip/geosite downloads libbox may attempt are either disabled for this
      test config or explicitly verified not to block startup indefinitely (the legacy project's
      "blocking Iran-side raw.githubusercontent.com fetch" bug must not be reintroduced silently).
- [ ] Instrumented tests re-run from P3-T6 (start/stop/revoke) all still pass with the real engine.
- [ ] `melos`/Gradle test commands pass; manual real-traffic verification is documented with
      concrete before/after evidence in the task report.

**Notes for Agent:**
- This task is the direct spiritual successor to the exact bugs that killed the legacy project
  (stats always zero due to swallowed connection failures, "connected" but no real traffic due to
  DNS/geoip blocking, catch-path leaks). Re-read the legacy failure analysis in
  `PROJECT_STATE.md`'s "Errors & Dead Ends" section before starting, and treat every one of those
  root causes as an explicit test case to actively try to reproduce and prove absent, not just
  something to passively avoid.
- Do not silently swallow any libbox error as a mere log warning — every failure path must
  propagate into `VpnStateMachine.Error` with a specific reason, per the legacy lesson about
  silently-swallowed `CommandClient` connection failures.

---

### P3-T8 — Traffic stats and log stream wiring (kept structurally separate from connection state)

**Status:** Not Started
**Depends On:** P3-T7

**Objective:** Implement real traffic statistics polling/streaming from libbox (bytes up/down)
and a bounded, redacted log ring buffer, exposed from `BrickVpnService` as two structurally
separate data flows from `VpnStateMachine`'s connection-state flow — directly enforcing the
architectural rule that connection state and traffic stats must never share a failure domain
(the legacy project's core stats bug was exactly this coupling).

**Scope:**
- Included: a `TrafficStatsPublisher` (or similarly named) component polling/subscribing to
  libbox's stats interface (verify current recommended mechanism — e.g. sing-box's `CommandClient`
  stats API, per P3-T1/T4 research) independently of connection-state handling, such that a stats-
  connection failure cannot cause or be caused by a connection-state failure and vice versa; a
  bounded, redacted `LogRingBuffer` capturing recent native-layer log lines (no secrets — apply
  the redaction principle from `SECURITY.md` even at this early stage, using placeholder rules if
  the real redaction scheme isn't finalized yet, per P1-T9's stub).
- Excluded: any UI display of stats/logs (Gate B minimum, real UI later); log export/diagnostic
  bundle feature (later phase).

**Acceptance Criteria:**
- [ ] Traffic stats update at a reasonable interval (e.g. ~1Hz — justify the exact number) while
      connected, using real byte counts observed to increase during actual data transfer in
      manual testing (not hardcoded/simulated values).
- [ ] Traffic stats reporting is proven, via a specific test/manual scenario, to keep working
      correctly even if artificially forced to hit an internal error once (and recover), without
      affecting the connection-state flow, and conversely a simulated connection-state error does
      not silently zero out or corrupt the stats flow — directly reproducing and disproving the
      legacy bug class.
- [ ] Log ring buffer is bounded in size (define and justify a concrete max entry count/byte
      size) and does not grow unbounded during a long-running connection.
- [ ] No raw config secrets (UUIDs, passwords, keys) appear in any captured log line — verified by
      manual inspection of captured logs during a test connection using the hardcoded test config
      from P3-T7.
- [ ] `melos`/Gradle test commands pass; manual verification documented with evidence (e.g.
      observed stats values during a real download).

**Notes for Agent:**
- This task exists specifically because "traffic stats always showed 0 bytes" was one of the
  three named root failures of the legacy project. Do not consider this task done until you have
  concretely, manually observed non-zero, increasing byte counts during a real test connection —
  code review alone is not sufficient evidence here.

---

### P3-T9 — Chaos/stress test suite (the Gate A hard gate)

**Status:** Not Started
**Depends On:** P3-T8

**Objective:** Implement and execute the full lifecycle chaos-test protocol against the native-
only harness, covering every scenario identified across the peer-review responses and the legacy
failure analysis, as both automated instrumented tests (where feasible) and a documented manual
test script (where true device-level chaos, like force-stop or reboot, can't be fully automated
without additional tooling).

**Scope:**
- Included: an automated instrumented test suite covering repeated start/stop cycling, and a
  manual test protocol document (`native/android/docs/CHAOS_TEST_PROTOCOL.md`) covering the
  scenarios below, executed by hand on the real connected device, with results recorded.
- Excluded: any Flutter-side testing (Gate B).

**Acceptance Criteria — all must pass, each with recorded evidence:**
- [ ] Start/stop cycled 100 times sequentially via automated instrumented test — zero crashes,
      zero stuck `Stopping` states, zero leaked `ParcelFileDescriptor`s (verified via `adb shell`
      fd count inspection before/after the run).
- [ ] Start/stop cycled 20 times with the device screen turned off during each cycle (manual).
- [ ] Start/stop cycled 20 times with the app/service backgrounded (manual).
- [ ] Start/stop cycled with Wi-Fi ↔ mobile-data network switching occurring mid-connection
      (manual) — connection either cleanly recovers or cleanly errors, never silently corrupts
      state.
- [ ] Calling `start` while already `Starting` does not corrupt state (`rejectedBusy` returned,
      original start proceeds normally) — automated.
- [ ] Calling `stop` while `Starting` cleanly cancels and cleans up — automated.
- [ ] Calling `stop` repeatedly while already `Stopping` is idempotent — automated.
- [ ] Force-stopping the app via Android system settings while the VPN is running, then
      reopening it, results in no zombie service, no leaked TUN interface, and correct state
      reporting on reopen (manual).
- [ ] Device reboot while VPN was running results in the VPN correctly stopped (not restarted
      unexpectedly without explicit always-on configuration) and no persistent broken state
      (manual).
- [ ] Simulated/forced libbox teardown hang (e.g. via a debug hook) is proven to trigger the
      5-second stop watchdog and force-complete cleanup — automated (extends the P3-T5 unit-level
      proof to the full real-engine integration level).
- [ ] `onRevoke()` (triggered via Android VPN settings, disabling the VPN externally) results in
      clean stop, correct state, and no restart loop (manual).
- [ ] Providing a deliberately invalid config to `start()` results in rejection before any TUN
      interface is created, with a specific `Error` reason, never a partial/half-started state
      (automated or manual, whichever is more practical to construct).

**Notes for Agent:**
- **This task is the actual Gate A pass/fail checkpoint for the entire project's core risk.** If
  any scenario above fails, fix the root cause in the relevant earlier task's files (P3-T5/T6/T7/
  T8) and re-run the **entire** suite from scratch — do not consider a partial re-run sufficient,
  since fixes can introduce regressions in previously-passing scenarios.
- Record results honestly, including intermittent/flaky failures — a scenario that "usually
  passes" is not a passing scenario for a VPN lifecycle; investigate and fix flakiness rather than
  reporting it as a pass.

---

### P3-T10 — Gate A closeout and Definition-of-Done pass

**Status:** Not Started
**Depends On:** P3-T1 through P3-T9

**Objective:** Formally close out Gate A: confirm every task above is genuinely `Completed`,
confirm the full chaos-test suite (P3-T9) passes with no outstanding known issues, and update
`PROJECT_STATE.md` to reflect that the native Android VPN lifecycle is proven and Gate B
(Flutter/Platform-Channel integration) is ready to begin.

**Scope:**
- Included: full verification pass of `native/android/` from a clean checkout (fresh AAR build
  via P3-T3's script, fresh Gradle build, full test suite run), a written Gate A summary report,
  `PROJECT_STATE.md` update.
- Excluded: any Gate B work.

**Acceptance Criteria:**
- [ ] Fresh checkout + fresh libbox AAR build + `./gradlew build` + full unit/instrumented test
      suite all succeed with zero manual workarounds beyond what's documented in
      `native/android/README.md`.
- [ ] The full P3-T9 chaos-test suite passes in a final, clean run (not relying on results from
      earlier iterative debugging runs).
- [ ] A Gate A summary report explicitly maps each of the legacy project's named root-cause bugs
      (traffic stats always zero, connected-but-no-traffic, VPN wouldn't stop reliably, and their
      sub-causes listed in `PROJECT_STATE.md`) to the specific test/scenario in this phase that
      now proves it does not reproduce — a direct, explicit traceability list, not a vague
      assurance.
- [ ] `PROJECT_STATE.md` is fully rewritten to reflect end-of-Gate-A state, explicitly stating
      Gate B is next and must not skip re-testing equivalent scenarios through the full Flutter
      stack.
- [ ] Closeout report follows the exact `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
- Do not proceed to Gate B tasks under any circumstances until this closeout is genuinely
  `Completed` and reviewed by the human — this is the single most important sequencing gate in
  the entire roadmap.

---

### Gate B — Flutter / Platform-Channel Integration

**Precondition for this entire gate:** P3-T10 (Gate A closeout) must be `Completed`. Every task
below assumes the native Kotlin `VpnStateMachine` + `BrickVpnService` + libbox integration is
already proven correct in isolation. The purpose of Gate B is to wire that proven engine to
Flutter **without introducing new lifecycle bugs at the bridge layer**, and to prove that with
its own dedicated chaos-test pass — never assuming Gate A's proof automatically transfers.

---

### P3-T11 — Convert native Android module into a Flutter platform plugin

**Status:** Not Started
**Depends On:** P3-T10

**Objective:** Restructure `native/android/` (or create a new properly-structured Flutter federated
plugin package, e.g. `packages/vpn_engine_android`) so the proven `BrickVpnService` and its Gradle/
libbox build pipeline become a Flutter Android platform plugin, installable into `apps/mobile` via
the standard Flutter plugin mechanism, with zero behavioral changes to the already-proven native
code beyond what's structurally required for plugin packaging.

**Scope:**
- Included: a new Flutter plugin package (decide exact name/location and justify — e.g.
  `packages/vpn_engine_android`, following the Melos workspace pattern from P0-T6), migration of
  the Gate A Kotlin sources into the plugin's `android/` directory, migration of the libbox AAR
  build script and its `.gitignore` entry, updated `native/android/README.md` (or its replacement)
  reflecting the new structure, confirmation that the plugin's own Gradle build still passes the
  same unit tests migrated from Gate A unchanged.
- Excluded: any actual Dart-side platform channel code yet (next task); no behavioral changes to
  `VpnStateMachine`, `BrickVpnService`, or the libbox integration logic itself — this is a
  structural/packaging migration only.

**Acceptance Criteria:**
- [ ] All Gate A unit tests (`VpnStateMachineTest` etc.) pass unchanged after migration into the
      new plugin structure — proving the migration introduced no logic changes.
- [ ] All Gate A instrumented tests pass unchanged after migration (re-run on the real device).
- [ ] The plugin correctly registers with Flutter's plugin system (verified by adding it as a
      path dependency to `apps/mobile` and confirming `melos bootstrap` resolves it, even before
      any Dart code calls into it).
- [ ] The libbox AAR build script continues to work from its new location, producing an
      identical AAR to before the migration (same sing-box commit pinned, same output).
- [ ] `melos run analyze` and `melos run test` pass across the whole workspace; native Gradle
      tests also pass via their own command.

**Notes for Agent:**
- Resist any temptation to "improve" or refactor the native lifecycle code while moving it — if
  you notice something worth improving, note it in the report as a follow-up suggestion rather
  than changing proven, chaos-tested code as a side effect of a structural migration.

---

### P3-T12 — Pigeon schema definition for VPN commands

**Status:** Not Started
**Depends On:** P3-T11, P1-T4

**Objective:** Define the Pigeon schema (per the finalized `ARCHITECTURE.md` Section 3.5 rule
requiring type-safe generated channels, not hand-written `MethodChannel` strings) covering every
command and data type needed to bridge Dart's `VpnEngine` contract (P1-T4) to the native
`VpnStateMachine`/`BrickVpnService`: `start(ServerProfile)`, `stop()`, `getStatus()`, plus the
data classes for connection state, command results, and any permission-request signaling Android
`VpnService` requires (the user-consent intent flow).

**Scope:**
- Included: a Pigeon schema file (e.g. `packages/vpn_engine_android/pigeons/vpn_api.dart`),
  generated Dart and Kotlin bindings via the Pigeon tool, wired into the plugin's build process
  (documented how/when codegen is run — manually invoked command vs. build-time hook, decide and
  justify), exact mapping of every `VpnCommandResult`/`ConnectionState` variant from
  `core_domain`/`core_vpn_engine` into Pigeon-compatible types.
- Excluded: the actual Kotlin-side implementation of the generated interface (next task); the
  actual Dart-side `VpnEngine` implementation (task after that).

**Acceptance Criteria:**
- [ ] Pigeon schema compiles and generates both Dart and Kotlin code without errors.
- [ ] Every method/type needed by the `VpnEngine` interface (P1-T4) has a corresponding, faithful
      Pigeon representation — no information loss or semantic drift (e.g. the accepted-vs-final-
      state distinction must survive the translation exactly).
- [ ] The Android permission-consent flow (the system dialog `VpnService` requires before first
      use, via `VpnService.prepare()`) is explicitly represented in the schema as a distinct
      command/result (e.g. a `prepare()` call returning whether consent is already granted or an
      intent needs to be launched) — this was not fully modeled in P1-T4's initial interface and
      must be added/reconciled now; if this requires revisiting `packages/core_vpn_engine`'s
      `VpnEngine` interface itself, do so and document the change clearly.
- [ ] Generated code is committed or the codegen step is wired into the build process consistently
      (decide once, document, follow project-wide convention already used for Riverpod codegen).
- [ ] `melos run analyze` passes on generated Dart code (with any necessary, documented
      analyzer-exception patterns for generated files, per common Pigeon/codegen conventions).

**Notes for Agent:**
- The permission-consent flow is a real gap between the original P1-T4 design (written before
  Android-specific realities were fully in view) and what Android actually requires. This is
  exactly the kind of discovery that should trigger a documented interface revision, not a
  workaround bolted on only at the platform layer — the abstraction should stay honest about
  platform realities per `ARCHITECTURE.md`'s own caution against over-generic abstractions.

---

### P3-T13 — Kotlin-side Pigeon API implementation

**Status:** Not Started
**Depends On:** P3-T12

**Objective:** Implement the generated Pigeon host-API interface on the Kotlin side, delegating
every call directly to the already-proven `VpnStateMachine`/`BrickVpnService` from Gate A with
**no new lifecycle logic introduced at this layer** — this class should be a thin, faithful
adapter, not a place where new state-handling decisions get made.

**Scope:**
- Included: `PigeonVpnApiImpl.kt` (or similarly named), wiring `prepare()`/`start()`/`stop()`/
  `getStatus()` Pigeon calls to the state machine's existing public methods, wiring the state
  machine's `StateFlow`/`SharedFlow` output to Pigeon's event-streaming mechanism (Pigeon's
  event channel support, or a manually wired `EventChannel` if Pigeon's current version doesn't
  cover streaming as cleanly — verify current Pigeon capabilities rather than assuming).
- Excluded: any new business logic, any new state transitions not already defined in
  `VpnStateMachine`.

**Acceptance Criteria:**
- [ ] Every Pigeon-defined method has a correct, thin implementation with no additional lifecycle
      logic beyond argument translation and delegation.
- [ ] Confirmed via code review (documented explicitly in the report) that this class introduces
      zero new blocking calls, zero new threading decisions beyond what the state machine already
      dictates, and zero new state.
- [ ] State/event streaming correctly delivers every `VpnStateMachine` transition to the Dart side
      in order, with no drops (verified in the next task's integration tests, referenced here as a
      forward dependency).
- [ ] `./gradlew build` and existing native tests still pass.

**Notes for Agent:**
- If you find yourself writing anything that looks like a decision ("what should happen if X") at
  this layer, stop — that decision either already exists in `VpnStateMachine` (find and use it) or
  is a genuine gap that should be fixed in `VpnStateMachine` directly (Gate A's file), not patched
  around here. This layer's entire value is in having *no* independent judgment.

---

### P3-T14 — Dart-side `AndroidVpnEngine` implementation

**Status:** Not Started
**Depends On:** P3-T13, P1-T4

**Objective:** Implement `AndroidVpnEngine implements VpnEngine` in
`packages/vpn_engine_android` (Dart side), wrapping the generated Pigeon client API, translating
between Pigeon-generated types and the `core_domain`/`core_vpn_engine` types, with unit tests
using a mocked Pigeon client (no real platform channel/device required for these particular
tests — that's what instrumented/integration tests are for, next task).

**Scope:**
- Included: `packages/vpn_engine_android/lib/src/android_vpn_engine.dart`, unit tests with a
  mocked/faked Pigeon host API, correct mapping of every Pigeon type to/from
  `ConnectionState`/`TrafficStats`/`VpnCommandResult`/`ServerProfile`.
- Excluded: any real device testing (next task); any UI wiring (task after that).

**Acceptance Criteria:**
- [ ] `AndroidVpnEngine` correctly implements every member of the `VpnEngine` interface from
      P1-T4 (as possibly amended by P3-T12's permission-flow discovery).
- [ ] Unit tests, using a mocked Pigeon client, prove correct type translation in both directions
      and correct stream forwarding (state and stats streams from the mock produce correctly
      mapped Dart-side values).
- [ ] Error/edge cases are handled without throwing: a malformed or unexpected value arriving
      from the native side (simulated in the mock) results in a well-formed `Err`/`Error` state,
      never an uncaught exception propagating to UI code.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- Keep this class as thin and mechanical as its Kotlin-side counterpart from P3-T13 — the same
  "no independent judgment" principle applies symmetrically on both sides of the bridge.

---

### P3-T15 — Wire `AndroidVpnEngine` into the app via Riverpod provider override

**Status:** Not Started
**Depends On:** P3-T14, P1-T7

**Objective:** Replace `MockVpnEngine` with the real `AndroidVpnEngine` as the bound
implementation behind the `VpnEngine` provider established in P1-T7, on the real Android platform
target, while keeping `MockVpnEngine` available for tests/other platforms via the documented
override seam.

**Scope:**
- Included: updating `apps/mobile`'s provider composition root (per P1-T7's documented seam) to
  bind `AndroidVpnEngine` on Android, updating the placeholder Home screen (from P1-T8) minimally
  to expose real connect/disconnect buttons and a text display of the live connection state and
  traffic stats streams (still visually minimal/placeholder per the project's deferred-UI
  principle — functional, not polished).
- Excluded: any real UI polish; any server-profile-selection UI (Phase 5) — use the same hardcoded
  test config approach from P3-T7/Gate A for now, exposed via a simple hardcoded
  `ServerProfile` for manual testing purposes only.

**Acceptance Criteria:**
- [ ] Running `apps/mobile` on the real connected Android device shows a functional (not
      polished) screen with a connect button, a disconnect button, live connection-state text,
      and live traffic-stats text.
- [ ] Tapping connect triggers the real Android `VpnService.prepare()` consent dialog on first
      use (if not already granted), and correctly proceeds after consent.
- [ ] Connecting via this real Flutter UI produces a real, verified change in outbound IP
      (same manual verification method as P3-T7, now proven through the full stack) — this is the
      first true end-to-end proof that Flutter → Pigeon → Kotlin → libbox → real network traffic
      works.
- [ ] Disconnecting cleanly returns to `Disconnected` state in the UI, with the native service
      fully torn down (re-verified via the same `adb`-based fd/process checks used in Gate A).
- [ ] `melos run analyze` and `melos run test` pass; manual end-to-end verification is documented
      with evidence in the task report.

**Notes for Agent:**
- This is the first moment the entire promise of the project — "a working VPN connect/disconnect
  through a real Flutter UI" — becomes concretely true. Treat the manual verification step with
  real rigor and document it thoroughly; this is a genuine milestone, not a routine task.

---

### P3-T16 — Full-stack chaos/stress test suite (the Gate B hard gate)

**Status:** Not Started
**Depends On:** P3-T15

**Objective:** Re-execute the **entire** chaos-test protocol from P3-T9, this time driving every
scenario through the real Flutter UI/Dart `VpnEngine` layer instead of the native-only harness,
explicitly checking for a new class of bugs that can only exist at the bridge/UI layer: Dart-side
state desync from native truth, Flutter engine restart handling, app-process-death recovery from
the Dart side's perspective, and platform-channel-specific deadlocks or dropped events.

**Scope:**
- Included: an automated integration test suite (Flutter integration_test package, running on the
  real device) covering repeatable scenarios, and an extension of
  `native/android/docs/CHAOS_TEST_PROTOCOL.md` (or its new location post-P3-T11 migration) with a
  "Full-Stack (Gate B)" section covering the additional Flutter-specific scenarios below.
- Excluded: nothing — this must be a genuinely complete re-run, not an abbreviated subset.

**Acceptance Criteria — all must pass, each with recorded evidence:**
- [ ] All applicable P3-T9 scenarios (100x start/stop, screen-off, backgrounded, network
      switching, busy/idempotency rejections, force-stop recovery, reboot recovery, watchdog
      trigger, revoke handling, invalid config rejection) are re-verified passing when driven
      through the Flutter UI, not just the native harness.
- [ ] Flutter UI state is proven to always match true native state after: app force-stop and
      reopen while VPN running, Flutter engine restart (if simulable) while VPN running, and app
      cold-start with VPN already running from a previous session.
- [ ] No platform-channel deadlock is observed across any of the above scenarios (verified by
      the app remaining responsive/no ANR during and after each scenario).
- [ ] Traffic stats and log streams (P3-T8) continue to flow correctly to the Dart UI throughout
      stress scenarios, with the same failure-domain-independence property re-verified at the
      full-stack level (a stats hiccup must not affect displayed connection state and vice versa).
- [ ] Command-acceptance vs. final-state semantics (P1-T4/P3-T12's core contract) are proven
      correct under stress — e.g. rapid repeated taps on connect/disconnect in the real UI never
      produce a UI state inconsistent with reality, even transiently in a way that misleads the
      user (directly targeting the legacy "icon shows connected but no traffic" class of bug, now
      at the UI-truthfulness level specifically).

**Notes for Agent:**
- Exactly as with P3-T9, this is a genuine pass/fail gate, not a formality. If anything fails,
  root-cause it precisely — determine whether the bug lives in the native layer (meaning Gate A's
  proof was somehow incomplete and must be revisited), the bridge layer (P3-T12/13/14), or the
  Dart/UI layer (P3-T15), fix it at its true source, and re-run the entire suite again.
- Report explicitly and honestly which layer any discovered bug lived in — this information is
  valuable for understanding whether the two-gate strategy actually achieved its intended
  isolation benefit, which is itself worth recording for future project retrospectives.

---

### P3-T17 — Phase 3 closeout and Definition-of-Done pass

**Status:** Not Started
**Depends On:** P3-T1 through P3-T16

**Objective:** Perform the full closeout review of Phase 3 in its entirety (both gates): confirm
every task is genuinely `Completed`, confirm the full-stack chaos suite passes cleanly, and update
`PROJECT_STATE.md` to reflect that Brick VPN has a working, hardened, real Android VPN
connect/disconnect/stats pipeline — the single hardest technical milestone in the whole project.

**Scope:**
- Included: full repository verification pass (fresh clone → AAR build → `melos bootstrap` →
  `analyze`/`format`/`test` → native Gradle build/tests → full chaos suite final run), a written
  Phase 3 summary explicitly re-confirming the legacy-bug traceability list from P3-T10 still
  holds true at the full-stack level, `PROJECT_STATE.md` rewritten to reflect the new baseline.
- Excluded: starting any Phase 4 work.

**Acceptance Criteria:**
- [ ] Fresh clone, from scratch, builds the libbox AAR, builds `apps/mobile`, and passes every
      automated test (Dart + Kotlin, unit + instrumented + integration) with zero manual
      workarounds beyond documented setup steps.
- [ ] The full Gate B chaos suite (P3-T16) passes in a final clean run.
- [ ] The legacy-bug traceability list is re-confirmed valid at the full-stack level (not just
      Gate A's native-only level) — explicitly re-stated in this closeout report.
- [ ] CI reflects whatever native build steps are feasible to automate at this point (if full
      on-device instrumented/chaos testing can't run in CI, document exactly what CI does cover —
      e.g. Kotlin unit tests, Dart unit tests, AAR build reproducibility — and what still requires
      manual on-device verification going forward).
- [ ] `PROJECT_STATE.md` fully rewritten as a coherent current snapshot, explicitly noting that
      the highest-risk phase of the project is complete and Phase 4 (state management + app
      skeleton around real features) is next.
- [ ] Closeout report follows the exact `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
- This closeout deserves unusual care in how it's written — it is the definitive record proving
  (or not) that the root cause of the legacy project's failure has actually been solved this time.
  If there is any lingering doubt, flaky behavior, or untested edge case, state it plainly rather
  than presenting an artificially clean picture.

---

## Phase 4 — State Management & App Skeleton

**Phase Goal:** build the app-wide plumbing every real feature in Phase 5+ will rely on — proper
navigation shell, app-lifecycle-aware state resync, non-secret local persistence, a consistent
error-presentation pattern, connectivity awareness, and a minimal theming skeleton — without yet
building any actual feature (server list, add-server, QR scan). Riverpod DI (P1-T7) and basic
`go_router` (P1-T8) already exist from Phase 1; this phase extends them into a real app shell now
that a real `AndroidVpnEngine` (Phase 3) exists behind the `VpnEngine` provider.

---

### P4-T1 — App lifecycle observer: resync VPN state on resume

**Status:** Not Started
**Depends On:** P3-T17

**Objective:** Implement an app-lifecycle observer that, whenever the Flutter app returns to the
foreground (resume from background, cold start), explicitly calls `VpnEngine.getStatus()` and
reconciles any Riverpod-held UI state with the authoritative native answer — directly enforcing
the "native layer is the single source of truth, Dart never invents state" principle from
`ARCHITECTURE.md` for the one moment (app resume) where Dart-side state is most likely to have
gone stale while the UI wasn't listening.

**Scope:**
- Included: an `AppLifecycleObserver` (using `WidgetsBindingObserver` or Flutter's current
  recommended lifecycle-listening API — verify current best practice) wired at the app root,
  a Riverpod provider/notifier holding the "confirmed-by-native" connection state that the rest
  of the UI reads from (rather than reading raw stream events directly in ways that could show a
  stale last-known value before resync completes), unit tests for the resync notifier's logic
  using a mocked `VpnEngine`.
- Excluded: any UI screen changes beyond what's needed to observe this behavior in the existing
  minimal Home screen from P3-T15.

**Acceptance Criteria:**
- [ ] On cold start, before any user interaction, the UI queries and displays the true native VPN
      state (e.g. if the VPN was left running from a previous session, the UI reflects "Connected"
      immediately, not a default "Disconnected" that later flips).
- [ ] On resume from background, the same resync occurs, verified manually by: connecting,
      backgrounding the app, waiting, foregrounding again, and confirming the UI never shows a
      stale/incorrect state even transiently in an observable way.
- [ ] Unit tests cover the resync notifier's logic against a mocked `VpnEngine` returning various
      states, including simulating a resync call that itself fails (should not crash the app or
      leave the UI in an ambiguous state — falls back to a clear "Error"/"Unknown" indicator with
      a retry affordance rather than silently guessing).
- [ ] `melos run analyze` and `melos run test` pass; manual resume-resync scenario documented.

**Notes for Agent:**
- This directly targets a subtler variant of the legacy "JS overwrote native stopping state" bug
  class — the fix here is architectural (resync-on-resume as a first-class, tested behavior), not
  a one-off patch.

---

### P4-T2 — Non-secret local persistence skeleton

**Status:** Not Started
**Depends On:** P1-T11

**Objective:** Establish the mechanism for persisting non-secret app preferences (e.g. selected
theme mode, selected locale, "has completed first-run consent" flag) locally on-device, explicitly
scoped to `None`/`Low`-sensitivity data per `SECURITY.md`'s data classification table — real
server configs/credentials are explicitly **not** part of this task and must wait for Phase 8's
secure-storage design.

**Scope:**
- Included: research and selection of a concrete local key-value persistence package (verify
  current recommended options compatible with the project's minimal-dependency philosophy —
  e.g. `shared_preferences` or an equivalent current standard; justify the choice), a thin
  `AppPreferencesRepository` abstraction in `apps/mobile`'s appropriate feature/core layer
  (following the P1-T6 data/domain/presentation convention), unit tests using a fake/in-memory
  implementation of the repository interface.
- Excluded: anything related to `ServerProfile` storage or any credential/secret storage — a
  loud, explicit comment/doc note must mark this repository as "non-secret preferences only,"
  cross-referencing `SECURITY.md`, to prevent future misuse as a dumping ground for sensitive data.

**Acceptance Criteria:**
- [ ] `AppPreferencesRepository` (or similarly named) interface exists with a concrete
      implementation backed by the chosen persistence package, plus a fake implementation for
      tests.
- [ ] A doc comment on the interface explicitly states the sensitivity boundary and points to
      `SECURITY.md`'s data classification table.
- [ ] At least one real preference (e.g. theme mode) round-trips correctly: set it, restart the
      app, confirm it persisted.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- If genuinely unsure whether a given piece of data belongs here or must wait for Phase 8's
  secure storage, stop and ask rather than guessing — this boundary is a real security control,
  not a stylistic preference.

---

### P4-T3 — Global error / feedback presentation pattern

**Status:** Not Started
**Depends On:** P1-T10

**Objective:** Establish one consistent, app-wide pattern for surfacing errors and transient
feedback to the user (e.g. a `Result`-aware helper that maps `Err`/failure states from any
feature into a consistent snackbar/banner presentation), so that every future feature (Phase 5
onward) has a single, already-decided way to show failures instead of each feature inventing its
own error UI ad hoc.

**Scope:**
- Included: a small `AppFeedback`/`ErrorPresenter` utility (exact naming/location decided and
  justified) usable from any Riverpod notifier/widget to show a localized (via `easy_localization`,
  P1-T10), non-technical user-facing message, with an optional "details" affordance for more
  technical information (kept minimal here — not a full diagnostic viewer, that's later); a
  documented convention added to `CODING_STANDARDS.md` (or confirmed present) for how
  feature-level `Result.Err`/domain error types should be mapped to user-facing messages
  (e.g. a required `toUserMessage()`-style mapping per error type, enforced by convention/lint
  where feasible).
- Excluded: any specific feature's actual error messages beyond what's needed to demonstrate the
  pattern (e.g. reusing the connect/disconnect flow from P3-T15 as the demonstration case).

**Acceptance Criteria:**
- [ ] A working, demonstrated example exists: forcing a connect failure (e.g. via
      `MockVpnEngine`'s configurable failure mode from P1-T5, used in a test, or a real device
      scenario) results in a consistent, localized, non-crashing user-facing message via the new
      pattern.
- [ ] The convention for mapping domain errors to user messages is documented clearly enough that
      a future agent implementing Phase 5's "add server" feature can follow it without
      re-deriving the pattern.
- [ ] `melos run analyze` and `melos run test` pass.

**Notes for Agent:**
- Keep this visually minimal (a plain `SnackBar` or equivalent is entirely sufficient) — the value
  of this task is the *consistency and reusability of the pattern*, not visual design, which is
  explicitly deferred to Phase 11.

---

### P4-T4 — Connectivity change awareness

**Status:** Not Started
**Depends On:** P4-T1

**Objective:** Add a basic, app-wide awareness of underlying network connectivity changes (Wi-Fi
↔ mobile data ↔ none), exposed as a Riverpod stream/provider, intended to inform (in later
phases) auto-reconnect logic (Phase 7) and user-facing status messaging — this task only
establishes the observability, not any reactive behavior yet.

**Scope:**
- Included: research and selection of a current, reliable Flutter connectivity-monitoring package
  (verify current recommended option — connectivity detection APIs and packages have shifted over
  time; do not assume a specific package name from possibly-stale training knowledge without
  checking), a `ConnectivityStatus` provider exposing current state, unit tests using a fake/mock
  connectivity source.
- Excluded: any actual reconnect logic (explicitly Phase 7's job) — this task is observation-only.

**Acceptance Criteria:**
- [ ] `ConnectivityStatus` provider correctly reflects real connectivity changes, verified
      manually by toggling Wi-Fi/airplane mode on the test device and observing the provider's
      value change accordingly (can be observed via a temporary debug log or the existing minimal
      Home screen).
- [ ] Unit tests cover the provider's logic against a faked connectivity stream.
- [ ] `melos run analyze` and `melos run test` pass; manual verification documented.

**Notes for Agent:**
- Do not wire this into `VpnEngine` or attempt any auto-reconnect behavior here — that's
  explicitly out of scope until Phase 7, where it can be designed with the full picture of
  lifecycle hardening in view.

---

### P4-T5 — Real navigation shell (bottom navigation + route structure)

**Status:** Not Started
**Depends On:** P1-T8, P1-T6

**Objective:** Replace the minimal two-route `go_router` skeleton from P1-T8 with the real
top-level navigation shell the MVP will use: a bottom-navigation (or equivalent — confirm
preference, default assumption is bottom navigation for a mobile-first app) structure with four
placeholder destinations — Home/Connection, Servers, Logs, Settings — each backed by a properly
structured feature folder per the P1-T6 convention, still visually minimal/placeholder, but now
representing the app's real information architecture for Phase 5+ to build into.

**Scope:**
- Included: `features/servers/presentation/` and `features/logs/presentation/` skeletons created
  (mirroring `features/connection` and `features/settings` already established), a
  `StatefulShellRoute` (or current `go_router`-recommended nested-navigation pattern — verify
  current API) providing bottom navigation across the four destinations, each destination showing
  a clearly labeled placeholder screen for now.
- Excluded: any real content on the Servers or Logs screens (Phase 5/6 respectively) — placeholders
  only, following the same "intentionally minimal" principle as earlier placeholder screens.

**Acceptance Criteria:**
- [ ] All four destinations are reachable via bottom navigation, each preserving its own
      navigation state independently if the user navigates deeper within one tab (verify current
      `go_router` nested-navigation/state-preservation behavior works as expected — don't assume).
- [ ] The existing functional Home screen content (connect/disconnect buttons, live state/stats
      display from P3-T15) is preserved and now lives correctly within this new shell.
- [ ] `melos run analyze` and `melos run test` pass; manual navigation verified on device.

**Notes for Agent:**
- Verify current `go_router` documentation for nested/shell-route patterns rather than assuming a
  specific API shape from training data, since this part of `go_router`'s API has evolved across
  versions.

---

### P4-T6 — Minimal theming skeleton (light/dark, no visual design work)

**Status:** Not Started
**Depends On:** P4-T2, P4-T5

**Objective:** Establish a minimal `ThemeData`/`ColorScheme` setup supporting light and dark mode,
driven by the theme-mode preference persisted via P4-T2, using Flutter/Material defaults rather
than any custom visual design — the explicit goal is to have the *mechanism* (theme switching,
persistence, system-mode-following) working correctly now, so Phase 11 can focus purely on
visual design later without re-plumbing this infrastructure.

**Scope:**
- Included: a basic light/dark `ThemeData` pair (Material defaults, no custom color palette/
  branding), a theme-mode selector wired into the (currently placeholder) Settings screen, correct
  persistence and restoration of the chosen mode across app restarts via P4-T2's repository.
- Excluded: any custom color palette, typography, branding, or icon work — explicitly deferred to
  Phase 11.

**Acceptance Criteria:**
- [ ] User can switch between light/dark/system theme mode from the Settings placeholder screen,
      and the change is immediately reflected app-wide.
- [ ] The chosen mode persists across app restarts.
- [ ] "System" mode correctly follows the OS-level light/dark setting (verified manually by
      toggling the device's system theme).
- [ ] `melos run analyze` and `melos run test` pass; manual verification documented.

**Notes for Agent:**
- Do not spend any effort on visual polish, custom fonts, or branding here — if you find yourself
  making a design decision beyond "which of Flutter's default theme mechanisms to wire up," you've
  gone out of scope for this task.

---

### P4-T7 — App startup sequencing

**Status:** Not Started
**Depends On:** P4-T1, P4-T2, P4-T6

**Objective:** Define and implement an explicit, ordered app-startup sequence (initialize
localization → initialize preferences repository → initialize theme → initialize Riverpod
provider container → perform the P4-T1 initial VPN-state resync → render the navigation shell),
replacing whatever implicit/ad-hoc ordering currently exists in `main.dart`, so startup behavior
is deterministic and easy to reason about (and extend later, e.g. with a real splash screen in
Phase 11).

**Scope:**
- Included: a restructured `apps/mobile/lib/main.dart` (and a small `AppStartup`/`AppBootstrap`
  helper if that improves clarity — decide and justify) making the startup sequence explicit and
  linear, with basic error handling if any startup step fails (e.g. preferences read failure)
  such that the app degrades gracefully (sensible defaults) rather than crashing on launch.
- Excluded: any actual splash-screen visual design (Phase 11); any native-side startup changes.

**Acceptance Criteria:**
- [ ] Startup sequence is explicit and linear in code, documented with a comment listing the
      exact order and why it matters (e.g. "preferences must load before theme is applied").
- [ ] A simulated failure in any one startup step (e.g. forcing the preferences repository to
      throw, in a test) results in graceful degradation (app still launches, using safe defaults,
      with an appropriate error surfaced via P4-T3's pattern if user-relevant) rather than a crash.
- [ ] `melos run analyze` and `melos run test` pass; manual cold-start verified on device.

**Notes for Agent:**
- Keep this focused on *sequencing correctness and resilience*, not on adding new startup-time
  features — no new functionality should be introduced here beyond re-ordering/hardening what
  already exists from earlier Phase 4 tasks.

---

### P4-T8 — Phase 4 closeout and Definition-of-Done pass

**Status:** Not Started
**Depends On:** P4-T1 through P4-T7

**Objective:** Perform a full closeout review of Phase 4: confirm every task above is genuinely
`Completed`, confirm the app has a coherent, navigable, lifecycle-aware skeleton with a real
(functional, connected) VPN engine underneath, and update `PROJECT_STATE.md` to reflect that
Phase 5 (Core MVP Features) is ready to begin.

**Scope:**
- Included: full repository verification pass (fresh clone → all Melos scripts → manual full
  app walkthrough on device: cold start, navigate all four tabs, toggle theme, connect/disconnect
  VPN, background/foreground the app), `PROJECT_STATE.md` rewritten to reflect the new baseline.
- Excluded: starting any Phase 5 work.

**Acceptance Criteria:**
- [ ] Fresh clone builds and passes all Melos scripts and native tests with zero manual
      intervention beyond documented setup.
- [ ] A full manual walkthrough of the app (as described above) is performed and documented with
      no crashes, no state-desync glitches, and no analyzer warnings.
- [ ] CI is green on `master` (the repository's actual default branch).
- [ ] `PROJECT_STATE.md` fully rewritten as a coherent current snapshot, explicitly noting Phase 5
      is next and will build real functionality (add server, server list, QR scan,
      connect/disconnect using real user-supplied configs) on top of this now-stable skeleton.
- [ ] Closeout report follows the exact `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
- This is a good moment to sanity-check that the hardcoded test `ServerProfile` from P3-T15 is
  clearly marked/isolated (e.g. behind a debug-only code path or clearly-labeled temporary
  constant) so Phase 5's real "add server" feature has an obvious, unambiguous place to plug in
  without fighting leftover test scaffolding.

---


## Phase 5 — Core MVP Features

**Phase Goal:** Replace all Phase 3/4 hardcoded/test data with real, user-supplied server configurations. By the end of this phase, a user can add a server (by pasting a link or scanning a QR code), optionally import a subscription, see their servers in a real list, pick one as active, and actually connect/disconnect through it — the first true end-to-end usable feature slice of Brick VPN.

**Granularity Note (reaffirmed):** Per the Granularity Note in the document header, Phase 5 tasks are written at a coarser grain than Phases 0–3. Each task below is still fully templated and independently actionable, but some tasks intentionally bundle related sub-steps that a future re-pass may choose to split further once this phase is actually reached. Do not treat the current task count as final — expand if the assigned coding agent or the human reviewer finds a task too large to complete and review as one atomic unit.

---

### P5-T1 — Local Persistent Storage for Server Profiles

**Status:** Not Started
**Depends On:** P1-T3, P4-T8

**Objective:**
Implement a real, persistent storage backend for `ServerProfile` records (and any subscription metadata) behind the repository interface defined in `packages/core_domain` (P1-T3), replacing the in-memory/hardcoded test data used throughout Phases 3–4.

**Scope:**
- Included:
  - Research and select a local storage solution appropriate for Flutter (candidates to evaluate on their actual current merits — do not assume based on popularity alone: Isar, Hive, Drift/sqlite3, or a simpler JSON-file-based store). Document the comparison and the decision with rationale in a short ADR-style note (can live in `ARCHITECTURE.md` Decision Log or a dedicated note referenced from it).
  - Confirm/finalize the open design question from P1-T3 regarding whether per-protocol config payloads are stored as a generic `Map<String, dynamic>` or as a fully-typed sealed class hierarchy, and make sure the chosen storage layer can (de)serialize whichever representation was actually implemented in `core_domain`. If P1-T3 left this ambiguous or was implemented inconsistently, resolve/align it as part of this task and flag the resolution clearly in the completion report.
  - Implement the concrete repository class(es) fulfilling the repository interface(s) already defined in `core_domain`, backed by the chosen storage engine.
  - Support CRUD operations: create, read (single + list), update, delete for `ServerProfile` entities.
  - Support a minimal subscription metadata record (subscription URL, last-refreshed timestamp, associated server profile IDs) sufficient for P5-T4/T6 to build on. The exact schema is this task's responsibility to define, since no prior task has defined it.
  - Wire the concrete repository into the app's dependency-injection/Riverpod provider graph (per P4-T2's provider architecture), replacing whatever placeholder/in-memory repository was used in Phase 4.
  - Data migration is out of scope for correctness right now (no real users exist yet), but the schema should be defined with a version field or equivalent so that future migrations (Phase 8+) are not a rewrite.
- Excluded:
  - Encryption-at-rest of sensitive fields (passwords, UUIDs, private keys) — deferred to Phase 8 (Security Hardening). This task must still avoid trivially defeating future encryption efforts (e.g., don't bake in assumptions that make encrypting a single field impossible later), but no encryption work is required now.
  - Cloud sync / backup of any kind — explicitly out of scope, not currently planned for this project at all.
  - UI for any of this — pure data-layer work.

**Acceptance Criteria:**
- [ ] Storage engine selection is documented with rationale (performance/reactivity/maintenance-burden trade-offs actually considered, not assumed).
- [ ] Concrete repository implementation exists, fulfills the `core_domain` interface, and compiles with no type-checking errors.
- [ ] CRUD operations are covered by automated tests using a real (not mocked) instance of the storage engine, run against temporary/in-memory storage locations so tests don't pollute developer machines.
- [ ] Subscription metadata schema is defined and documented (even briefly) in code comments or a short markdown note.
- [ ] Provider graph is updated so the rest of the app now reads/writes through the real repository, and the Phase 4 in-memory/hardcoded implementation is deleted (not left dangling as dead code).
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Check the actual state of `core_domain`'s `ServerProfile` model before starting — its exact shape was left open in P1-T3 and may have been resolved in a way not anticipated by this roadmap text. If you find the model under-specified or inconsistent with what subscription-derived servers (Phase 2's parser output) actually produce, stop and ask rather than force-fitting one representation onto the other. Do not silently pick a storage engine because it's what you've seen most often in unrelated projects — verify current (as of when you actually do this task) community consensus, maintenance status, and Flutter-null-safety/latest-Dart-SDK compatibility of whichever engine you propose.

---

### P5-T2 — Add Server: Manual URI/Link Paste

**Status:** Not Started
**Depends On:** P5-T1, P2-T3 through P2-T8 (protocol parsers), P2-T11 (parser facade/validation output)

**Objective:**
Implement the first real "Add Server" entry path: a screen/flow where the user pastes a single server configuration link (e.g., `vmess://`, `vless://`, `trojan://`, `ss://`, etc., per whatever protocols Phase 2 actually implemented) and the app parses it via the Phase 2 config parser engine, shows a confirmation/preview, and persists it via P5-T1's repository.

**Scope:**
- Included:
  - A minimal input screen (plain text field + paste-from-clipboard convenience button + submit action). Visual design remains deliberately minimal per the Phase 11 deferral — functional clarity only.
  - Wiring the pasted string through the Phase 2 parser facade, handling success and failure paths.
  - On successful parse: show a brief, plain preview of key fields (protocol type, address, remark/name if present) and let the user confirm before saving, or save directly if that's the simpler correct UX call — the agent should make and document this small UX call, not treat it as an open design question requiring a human round-trip.
  - On parse failure: surface the specific error reason returned by the Phase 2 parser (not a generic "invalid link" message), consistent with Phase 2's error-handling design.
  - Duplicate detection is a nice-to-have, not required, for this task — if trivial to add given the repository's query capabilities, include it; otherwise leave a `// TODO` and do not block completion on it.
- Excluded:
  - QR scanning (P5-T3).
  - Subscription URLs (P5-T4) — a subscription URL pasted into this single-server field should be detected and rejected with a clear message pointing the user at the subscription import flow, not silently mis-parsed as a single server.
  - Editing an existing server (P5-T6).

**Acceptance Criteria:**
- [ ] User can paste a valid link for at least one protocol supported by Phase 2 and see it appear, persisted, in the repository.
- [ ] Invalid/malformed input produces a clear, specific, non-crashing error message surfaced from the parser's actual failure reason.
- [ ] A subscription-URL-shaped input is detected and rejected with guidance rather than mis-handled.
- [ ] Manual test performed and described for at least two different protocol types actually implemented in Phase 2.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This is the first place where Phase 2's parser output meets a real UI and real persistence — treat any mismatch you discover between what the parser produces and what `core_domain`/the repository expects as a signal to stop and reconcile, not to paper over with ad-hoc conversion glue scattered through UI code. All input here is untrusted (pasted by the user, possibly copied from an untrusted source) — treat it per `SECURITY.md` handling expectations already established in Phase 2, even though this task itself is UI-layer.

---

### P5-T3 — Add Server: QR Code Scan

**Status:** Not Started
**Depends On:** P5-T2

**Objective:**
Add a QR-code-scanning entry path that feeds the same parse-and-save pipeline built in P5-T2, including the Android camera permission flow.

**Scope:**
- Included:
  - Research and select a current, maintained QR-scanning Flutter package (verify actual maintenance status and current Android/Flutter-version compatibility — do not assume a package that was popular during training-data cutoff is still the right choice).
  - Camera permission request flow (grant/deny/permanently-denied states all handled distinctly, with clear user-facing messaging for each — reuse or extend whatever permission-handling pattern already exists from P3-T12's VPN-permission `prepare()` work if applicable, for consistency).
  - Scanning a QR code containing a single server link and routing the decoded string through the exact same parser pipeline used in P5-T2 (no duplicated parsing logic).
  - Basic scan-screen affordances (camera preview, cancel button) — minimal styling only.
- Excluded:
  - Scanning a QR code that encodes a full subscription (if such a format exists/matters, defer to P5-T4's judgment or a future task — do not scope-creep this task).
  - Batch/multi-QR scanning.

**Acceptance Criteria:**
- [ ] Camera permission is correctly requested, and all three states (granted, denied, permanently denied → redirected to system settings) are handled without crashing.
- [ ] A real QR code encoding a valid server link, scanned on a physical Android device or emulator with a virtual camera feed, results in a correctly parsed and saved server.
- [ ] An invalid/unsupported QR code produces the same clear error path as P5-T2's invalid-link case, not a separate inconsistent error UX.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Verify current camera-permission best practice for the Android API levels this project targets (per P0-T8/P3-T3's pinned target/minSdk) — permission handling has shifted across Android versions and across Flutter permission packages; don't assume older guidance still applies without checking.

---

### P5-T4 — Add Server: Subscription URL Import

**Status:** Not Started
**Depends On:** P5-T1, P2-T9, P2-T10 (subscription fetch/parse from Phase 2)

**Objective:**
Implement a flow for importing multiple servers at once from a subscription URL, using the fetch-and-parse logic already built in Phase 2, and persisting the resulting set of servers along with subscription metadata for later refresh.

**Scope:**
- Included:
  - An input flow for the user to paste/enter a subscription URL (mirrors P5-T2's input pattern where reasonable, for UX consistency).
  - Invoking Phase 2's subscription fetch logic (P2-T9/T10), which already treats the fetched content as untrusted per `SECURITY.md`.
  - On successful fetch+parse: persist the subscription metadata record (from P5-T1) and all resulting `ServerProfile` entries, tagging each with the subscription it came from so P5-T6's refresh/removal logic can manage them as a group.
  - Clear handling of partial failure (subscription reachable but contains some malformed entries among valid ones) — decide and document whether partial success (import the valid ones, report the invalid ones) or all-or-nothing is the correct behavior; partial success is the recommended default unless the agent finds a concrete reason otherwise.
  - Network-failure and timeout handling with clear user-facing messaging (distinct from parse-failure messaging).
- Excluded:
  - Automatic/background periodic refresh of subscriptions — manual refresh only, wired in P5-T6.
  - Subscription format auto-detection beyond whatever Phase 2 already implemented (e.g., if Phase 2 only handles Base64 and/or a specific YAML dialect, do not expand format support here without flagging it as a scope question first).

**Acceptance Criteria:**
- [ ] A valid subscription URL (real or realistic test fixture) results in correctly imported, persisted servers correctly tagged with their source subscription.
- [ ] Partial-failure behavior is implemented and documented per whichever policy (partial-success vs. all-or-nothing) was decided.
- [ ] Network failure, timeout, and empty-subscription cases are all handled without crashing, with distinct, clear messaging.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task is a thin orchestration/UI layer over already-built Phase 2 logic — if you find yourself needing to add real parsing logic here rather than in `packages/config_parser`, stop and reconsider whether this belongs in Phase 2 instead, to avoid splitting parsing logic across layers.

---

### P5-T5 — Server List Screen (Real Data)

**Status:** Not Started
**Depends On:** P5-T1, P4-T8

**Objective:**
Replace the Phase 3/4 hardcoded test `ServerProfile` and its placeholder list UI with a real server list screen backed by the repository from P5-T1, reactively updating as servers are added, edited, or removed.

**Scope:**
- Included:
  - A list screen showing all persisted servers (name/remark, protocol type, and whichever minimal identifying fields are useful — visual design remains minimal per Phase 11 deferral).
  - Reactive updates via the Riverpod provider graph (per P4-T2) — adding a server elsewhere in the app must cause this list to update without manual refresh.
  - An empty state (no servers yet) with a clear call-to-action pointing at the add-server flows (P5-T2/T3/T4).
  - Visual/structural distinction (even if minimal, e.g. a small subtitle or grouping) between standalone servers and subscription-sourced servers, since P5-T6 will need per-subscription actions.
  - Explicit removal of the Phase 3/4 hardcoded test `ServerProfile` from all code paths reachable in normal app operation (per the forward-pointer already noted in P4-T8) — it may remain only as isolated test fixture data used strictly within automated tests, never in production/runtime code paths.
- Excluded:
  - Sorting/filtering/search — nice-to-have, not required for MVP; add only if trivial, otherwise leave as a documented future improvement.
  - Drag-to-reorder or any advanced list interaction.

**Acceptance Criteria:**
- [ ] Server list reflects real repository state and updates reactively when data changes elsewhere in the app.
- [ ] Empty state is implemented and reachable (verified by clearing all servers and observing it).
- [ ] The Phase 3/4 hardcoded test `ServerProfile` no longer appears anywhere in a normal (non-test) run of the app; a grep/search confirms it is confined to test code only.
- [ ] Subscription-sourced vs. standalone servers are visually distinguishable in some minimal way.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This is the task that finally retires the Phase 3 test scaffolding from the runtime app — treat its complete removal from production code paths as a hard requirement, not a nice-to-have, since leaving it in risks silent confusion in later phases (e.g., someone accidentally connecting to test data instead of a real server).

---

### P5-T6 — Server Management: Edit, Delete, Duplicate, Refresh Subscription

**Status:** Not Started
**Depends On:** P5-T5, P5-T4

**Objective:**
Implement the remaining CRUD-adjacent user actions on servers: editing a standalone server's fields, deleting a server (standalone or subscription-sourced), duplicating a server, and manually refreshing a subscription (re-fetch, diff against existing entries, add/update/remove as appropriate).

**Scope:**
- Included:
  - Edit flow for standalone (non-subscription) servers — reuse P5-T2's input/validation pattern where the edited fields require re-parsing/re-validation (e.g., if editing raw fields rather than just a display name).
  - Delete flow with a confirmation step (destructive action), for both standalone and subscription-sourced servers, with appropriate warnings if deleting a subscription's "parent" record also removes all its child servers.
  - Duplicate flow (copy a server's config into a new standalone entry, e.g. useful for a user who wants to tweak a subscription-derived server without losing the original on next refresh).
  - Manual subscription refresh action: re-run P5-T4's fetch/parse logic for an existing subscription, and implement a clear, documented diffing policy (e.g., replace all previously-associated servers with the newly fetched set; or diff by some stable identifier if one exists — the agent must decide and document which, given what's actually available in the parsed data).
- Excluded:
  - Editing a subscription-sourced server's raw connection fields directly (since a refresh would overwrite it) — if editing is desired for such a server, it should go through "duplicate to standalone" first. Document this constraint clearly to the user in the UI copy.
  - Bulk operations (multi-select delete, etc.).

**Acceptance Criteria:**
- [ ] Editing a standalone server persists changes correctly and re-validates edited fields.
- [ ] Deleting a server (both kinds) works correctly, including the subscription-parent-deletes-children case, with a confirmation step that cannot be bypassed accidentally.
- [ ] Duplicating a server produces a correct, independent standalone copy.
- [ ] Manual subscription refresh correctly updates the associated server set per the documented diffing policy, verified with a test subscription that changes between two fetches.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
The diffing policy for subscription refresh is an explicit open design point — do not guess silently. Pick the simplest correct policy (full-replace is likely simplest and safest given no stable cross-fetch identifier may exist in most subscription formats), document why, and flag it in your completion report as a decision the human should be aware of, even though it doesn't rise to the level of needing a mid-task pause.

---

### P5-T7 — Active Server Selection

**Status:** Not Started
**Depends On:** P5-T5

**Objective:**
Introduce the concept of a single "active" (currently selected, about-to-connect-or-connected) server, distinct from the full list, with persistence across app restarts.

**Scope:**
- Included:
  - A way for the user to mark one server as active from the list screen (e.g., tap-to-select, with clear visual indication of which one is currently active).
  - Persisting the active server selection (its identifier) across app restarts — this may live in the same storage engine as P5-T1 or a simpler key-value store; the agent should choose the simplest correct approach.
  - Exposing the active server through the Riverpod provider graph so the connect/disconnect flow (P5-T8) and any future status displays (Phase 6) can consume it reactively.
  - Handling the case where the currently-active server is deleted (P5-T6) — the app must not crash or reference a dangling ID; fall back to "no active server selected" state cleanly.
- Excluded:
  - Any notion of multiple simultaneously "favorited" servers, tags, or grouping beyond the single active-selection concept — explicitly out of scope for MVP.

**Acceptance Criteria:**
- [ ] User can select an active server from the list, with clear visual indication.
- [ ] Active selection persists across a full app restart.
- [ ] Deleting the active server results in a clean "no active server" state, verified by an explicit test/manual check, with no crash or stale reference.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Keep this deliberately simple — a single nullable "active server ID" concept is sufficient for MVP. Resist the temptation to build a more general selection/favorites system now; that can be revisited post-MVP if actually needed.

---

### P5-T8 — Real Connect/Disconnect Flow

**Status:** Not Started
**Depends On:** P5-T7, P3-T17 (Gate B complete), P3-T12 (VpnEngine `prepare()` amendment)

**Objective:**
Wire the app's connect/disconnect UI actions (built against hardcoded test data in Phase 3/4) to the real active server selected in P5-T7, completing the first true end-to-end MVP user journey: add a real server → select it as active → connect → verify real traffic flows → disconnect.

**Scope:**
- Included:
  - Removing all remaining references to the Phase 3 hardcoded test `ServerProfile` from the connect/disconnect code path specifically (complementing P5-T5's removal from the list-display path — this task ensures the *engine invocation* path is also clean).
  - Passing the real active server's config through to `VpnEngine.start()` (per the P1-T4 interface, as amended in P3-T12 to include the `prepare()`-style permission flow) exactly as it was exercised with test data in Phase 3, now with real user-supplied data.
  - Ensuring the full state-stream-driven UI update pattern established in Phase 3/4 (session tokens, `accepted`/`rejectedBusy`/`rejectedInvalidConfig`/`rejectedPermissionDenied`/`failed` command responses, state stream as sole source of truth for connected/disconnected/error display) is preserved and correctly reflects real-world outcomes, not just the test scenarios it was originally validated against.
  - Handling `rejectedInvalidConfig` gracefully — if a persisted server's config somehow fails engine-side validation despite passing Phase 2's parser (e.g., a field the parser accepts but the native engine rejects), surface a clear error rather than a silent failure, and treat this discrepancy as worth flagging to the human even if not blocking.
  - Handling "no active server selected" gracefully in the connect UI (e.g., connect button disabled or redirects to server selection) — this state did not exist in Phase 3/4's hardcoded-server world and must now be designed.
  - Manual end-to-end verification: add at least one real server (via a real, working config the developer has access to), connect, confirm actual non-zero increasing traffic (reusing the verification method established in P3-T8), and disconnect cleanly.
- Excluded:
  - Traffic stats *display* in the UI — that remains Phase 6's responsibility. This task only needs to confirm traffic flows at a verification/debugging level (e.g., via logs or the same method used in P3-T8), not build user-facing stats UI.
  - Auto-reconnect, kill switch, or any resilience features — Phase 7.

**Acceptance Criteria:**
- [ ] Connect/disconnect UI actions operate against the real active server, not any hardcoded test data, verified by grep/code-review confirming no production code path still references Phase 3 test fixtures.
- [ ] "No active server selected" state is handled cleanly in the UI with no crash.
- [ ] `rejectedInvalidConfig` and other rejection reasons are surfaced to the user distinctly and clearly, not collapsed into one generic error.
- [ ] A real, working server config, added through the app's normal add-server flow, was used to manually verify actual non-zero increasing traffic during a connected session, and this verification is described in the completion report with enough detail to be trusted (not just "it worked").
- [ ] Disconnect reliably returns the app to a clean disconnected state after the above test, with no stuck `STOPPING` state (reusing the watchdog guarantee from Section 3.5/P3-T5).
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This is the task where Brick VPN becomes, for the first time, an actually-usable VPN client end to end. Do not treat this as "just wiring" — the legacy prototype's worst failures (traffic always showing 0, VPN appearing connected with no real traffic, VPN not stopping reliably) were exactly this kind of integration seam. Re-read the Errors & Dead Ends context for those failure modes before starting, and design your manual verification specifically to rule each of them out again now that real (not test) configs are involved. If anything about the real-world behavior differs from what Phase 3's test-data verification showed, stop and investigate rather than assuming the Phase 3 work already covers this.

---

### P5-T9 — Phase 5 Closeout and Definition-of-Done Pass

**Status:** Not Started
**Depends On:** P5-T1 through P5-T8

**Objective:**
Perform a full closeout pass on Phase 5: verify the entire add-server → select-active → connect/disconnect journey works from a fresh clone, produce the standard DoD report, and update `PROJECT_STATE.md` to reflect the new baseline before Phase 6 begins.

**Scope:**
- Included:
  - Fresh-clone build and manual run-through of the complete Phase 5 user journey: add a server via manual paste, add a server via QR scan, add a subscription, edit/delete/duplicate a server, refresh a subscription, select an active server, connect, verify real traffic, disconnect.
  - Confirming no Phase 3/4 test scaffolding remains reachable from any production code path (final check, complementing P5-T5's and P5-T8's individual removals).
  - Full `DEFINITION_OF_DONE.md`-template report covering all of Phase 5's tasks collectively.
  - Rewriting `PROJECT_STATE.md` to reflect: Phase 5 complete, real server management and real connect/disconnect now exist, next phase is Phase 6 (Traffic Stats & Live Logs), and any open follow-up items noted during Phase 5 (e.g., the `rejectedInvalidConfig` discrepancy flag from P5-T8, if it occurred).
- Excluded:
  - Any new feature work — this is a verification/closeout task only.

**Acceptance Criteria:**
- [ ] Fresh-clone full journey verified and described step-by-step in the report.
- [ ] No test scaffolding reachable from production code paths (explicit confirmation, not assumption).
- [ ] DoD report produced using the exact template from `DEFINITION_OF_DONE.md`.
- [ ] `PROJECT_STATE.md` rewritten and accurate as of end of Phase 5.
- [ ] Explicit statement of what Phase 6 will need from Phase 5 (i.e., the active-server and connect/disconnect plumbing Phase 6's stats/logs UI will hook into).

**Notes for Agent:**
As with every phase closeout, do not mark this `Completed` yourself — propose `Ready for Human Review` and wait. Use this pass to genuinely stress the fresh-clone experience as a new contributor would, not just re-run what you already know works.

---

## Phase 6 — Traffic Stats & Live Logs

**Phase Goal:** Give the user real, trustworthy visibility into what the VPN connection is actually doing — live upload/download traffic statistics and a live log viewer — sourced directly from the native engine, not derived from guesses or client-side estimation. This phase is deliberately separated from Phase 3 (per the legacy-prototype lesson where traffic stats silently always showed 0 bytes due to a swallowed connection failure) so that stats/logs plumbing gets focused, dedicated verification rather than being bolted onto the already-high-risk VPN lifecycle work.

**Granularity Note (reaffirmed):** Written at the same coarser-but-fully-templated grain as Phase 5, expandable later.

---

### P6-T1 — Traffic Stats Data Plumbing (Native → Domain)

**Status:** Not Started
**Depends On:** P3-T17, P5-T8

**Objective:**
Implement reliable, real-time traffic statistics reporting from the native Android VPN engine, through the Pigeon-generated typed channels established in Phase 3, into the Dart domain layer — with explicit, deliberate attention to avoiding the exact root cause of the legacy prototype's "traffic always 0 bytes" failure.

**Scope:**
- Included:
  - Re-verify, at time of execution, the current correct mechanism for reading traffic statistics from the sing-box/libbox version actually pinned in this project (candidates to check: a `CommandClient`/status-query API, the Clash API's traffic endpoint if exposed on Android too, or a direct stats accessor on the libbox session object). Do not assume the legacy prototype's approach (`CommandClient` polling) is still the correct or best mechanism — verify current guidance and pick deliberately.
  - If a `CommandClient`-style connection is used, implement explicit, non-swallowed error handling for connection failures — the legacy prototype's root-cause bug was silently downgrading connection failures to warnings and only polling when JS-side state was already `'connected'`. This exact failure pattern must be explicitly designed against and called out in the completion report as verified absent.
  - Native-side collection of traffic stats (bytes uploaded, bytes downloaded, and current instantaneous speed if directly available; otherwise compute speed client-side from a byte-count delta over a known time interval — document which approach was used and why).
  - A typed EventChannel-equivalent stream (per Section 3.5's Pigeon/typed-channel rule) delivering stats updates to Dart at a reasonable, bounded frequency (define and document the interval — e.g., 1 second — balancing responsiveness against overhead).
  - A domain-layer `TrafficStats` model (bytes up, bytes down, timestamp, optionally instantaneous speed) in `packages/core_domain`, and the corresponding provider(s) in the app layer to expose it reactively.
  - Explicit verification that the stats stream's failure domain is independent of the connection-state stream's failure domain — i.e., a stats-subscription hiccup must not corrupt or freeze the connection-state display, and vice versa (this directly generalizes P3-T8's original test to real, non-test usage).
- Excluded:
  - Any UI rendering of stats (P6-T2).
  - Historical/persisted stats across sessions or app restarts.
  - Per-app or per-destination traffic breakdown — out of scope entirely for this project's current ambitions.

**Acceptance Criteria:**
- [ ] The current-correct native stats-reporting mechanism is identified, verified against actual current sing-box/libbox documentation or source (not assumed from prior knowledge), and documented in the report.
- [ ] Connection failures in whatever stats-fetch mechanism is used are explicitly surfaced (logged as errors, not silently downgraded to warnings) and reported up through a well-defined error path — explicitly confirmed to not reproduce the legacy prototype's swallowed-failure bug.
- [ ] During a real connected session with real traffic (reusing a working config), non-zero, correctly increasing byte counts are observed end-to-end through the Dart-side stream, and this observation is described in the report with enough detail (actual numbers, method of verification) to be trusted.
- [ ] Stats stream and connection-state stream are demonstrated to be failure-domain-independent (e.g., by a deliberate fault-injection test analogous to P3-T8's, adapted for this real pipeline).
- [ ] Automated tests cover the domain-layer `TrafficStats` model and the Dart-side stream-handling logic, with the platform-channel boundary faked/mocked.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task exists specifically because of a real, previously-shipped bug — re-read the "Errors & Dead Ends" context on the legacy prototype's traffic-stats failure before starting. Do not treat this as routine plumbing; the exact failure mode (stats mechanism silently failing to connect, error downgraded to a warning, fallback logic gated on a state condition that masked the whole problem) must be a named, explicitly-checked-for risk in your own verification approach, not something you assume can't happen again because "the architecture is better now."

---

### P6-T2 — Traffic Stats UI Display

**Status:** Not Started
**Depends On:** P6-T1

**Objective:**
Display the real-time traffic statistics produced by P6-T1 in a minimal, functional UI element visible while connected.

**Scope:**
- Included:
  - Display of current upload/download speed and session-cumulative upload/download totals, updating live while connected.
  - Reset of session-cumulative totals at the start of each new connection (not carried over from a previous session).
  - Sensible human-readable formatting (B/KB/MB/GB, /s for speed) — implement or use a well-vetted formatting utility rather than ad-hoc string math prone to off-by-factor-of-1024-vs-1000 bugs.
  - Deliberately minimal visual design per the Phase 11 UI/UX deferral — plain text/labels are entirely sufficient, no charts or graphics required.
- Excluded:
  - Any charting, graphing, or historical visualization — explicitly deferred to be considered (if ever) as part of Phase 11's design pass, not guaranteed to be built at all.
  - Per-app or per-connection breakdown displays.

**Acceptance Criteria:**
- [ ] Speed and cumulative totals update visibly and correctly during a real connected session.
- [ ] Totals reset correctly on each new connection.
- [ ] Byte-formatting utility is correct and covered by a unit test (including boundary values like exactly 1024 bytes, 1 MB, etc.).
- [ ] UI update frequency does not cause visible jank or excessive widget rebuilds — verified by the agent checking that only the relevant stats widget(s) rebuild on each stream tick, not the entire screen (use Riverpod's fine-grained `select`/watch patterns as established in P4-T2's provider architecture).
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Because the stats stream may tick frequently, pay explicit attention to rebuild scope — this is a good, low-risk place to demonstrate correct fine-grained Riverpod usage per the architecture already established in Phase 4, rather than naively watching the whole stats object from a high-level widget.

---

### P6-T3 — Live Log Capture From Native Engine

**Status:** Not Started
**Depends On:** P3-T17

**Objective:**
Capture the native sing-box/libbox engine's internal log output and stream it to the Dart layer in near-real time via a typed channel, with a bounded in-memory buffer, for use by the log viewer (P6-T4).

**Scope:**
- Included:
  - Verify the current correct API for hooking into libbox's logging output (a `Logger` interface, log-file tailing, or a dedicated log-streaming API — check what the pinned sing-box/libbox version actually exposes rather than assuming).
  - Forward each log entry to Dart with at minimum: timestamp, level/severity, and message text, via a typed EventChannel-equivalent stream per Section 3.5's rules.
  - Implement a bounded in-memory ring buffer (native or Dart side — agent's choice, document which) so that long-running connections do not cause unbounded memory growth; define and document the buffer size/eviction policy.
  - Rate-limit or batch log delivery if the native engine can produce logs faster than the UI can reasonably consume them, to avoid flooding the platform channel or the UI thread.
- Excluded:
  - Full log redaction (sensitive-data scrubbing) — this is explicitly deferred to Phase 8 (Security Hardening) per the project's established phase plan. However, this task must not make Phase 8's job harder: keep log entries as structured data (not pre-flattened into opaque strings) wherever feasible, so that a future redaction pass in Phase 8 can inspect and filter fields rather than needing to regex arbitrary text.
  - Persisting logs to disk across app restarts — in-memory only for this phase.

**Acceptance Criteria:**
- [ ] Native log output is verified to be actually captured and correctly forwarded to Dart during a real connected session (spot-checked against known expected log lines, e.g., a connection-start or DNS-resolution log entry).
- [ ] In-memory ring buffer correctly bounds memory growth during an extended test run (e.g., an artificially high-log-volume scenario), verified and described in the report.
- [ ] Log entries arrive as structured data (level, timestamp, message as distinct fields), not a single opaque blob string, confirmed in the report.
- [ ] Report explicitly flags, as a known limitation, that log entries may currently contain sensitive information (server addresses, possibly credentials depending on log verbosity) and that full redaction is deferred to Phase 8 — this flag must also be carried into the Phase 6 closeout's `PROJECT_STATE.md` update (P6-T7).
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Do not attempt to build a full redaction system now — that is explicitly Phase 8's job and doing it prematurely/inconsistently here risks conflicting with Phase 8's eventual design. Your only obligation regarding sensitive data in this task is to (a) not make the problem structurally harder to fix later, and (b) clearly document the gap so it isn't forgotten. If you notice the native engine logging something egregiously sensitive in cleartext (e.g., a raw password) at a log level that would be visible even in default/non-verbose mode, flag this prominently in your report as a candidate for the human to consider suppressing at the source (e.g., lowering that specific log's verbosity) even before Phase 8 — but do not silently implement ad-hoc filtering yourself without flagging it.

---

### P6-T4 — Live Log Viewer Screen

**Status:** Not Started
**Depends On:** P6-T3

**Objective:**
Build a minimal, functional screen displaying the live log stream from P6-T3, with basic usability affordances (auto-scroll, level-based visual distinction, clear buffer).

**Scope:**
- Included:
  - A scrollable list view rendering log entries as they arrive, newest at the bottom (or top — agent's choice, but must be consistent and documented).
  - Auto-scroll-to-latest behavior that automatically pauses when the user manually scrolls up to read older entries, and a clear affordance to resume auto-scroll (e.g., a "jump to latest" button).
  - Minimal visual distinction between log levels (e.g., a colored left-border, tag, or icon per level) — deliberately simple, no elaborate theming, per Phase 11 deferral.
  - A "clear buffer" action that empties the currently displayed/stored log buffer.
- Excluded:
  - Text search or filtering by level/keyword — nice-to-have, not required; add only if trivial, otherwise document as a future improvement.
  - Export/copy functionality (P6-T5).
  - Persistence of logs across app restarts (consistent with P6-T3's in-memory-only scope).

**Acceptance Criteria:**
- [ ] Log entries render live and correctly as they arrive during a real connected session.
- [ ] Auto-scroll and its pause/resume behavior work correctly and are manually verified.
- [ ] Log level visual distinction is present and correct for at least the levels the native engine actually emits.
- [ ] Clear-buffer action works correctly and is reflected both in the UI and in the underlying buffer from P6-T3.
- [ ] Rendering performance remains acceptable with a large buffer (test with the buffer near its configured maximum size) — use a virtualized/lazy list widget, not a naively rebuilt full list, if buffer sizes make this a concern.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Keep this screen genuinely minimal — it is a debugging/transparency tool for this phase, not a polished feature; Phase 11 may later redesign its visual presentation entirely, but the functional behavior (correctness of what's displayed) established here should carry forward.

---

### P6-T5 — Log Export / Copy

**Status:** Not Started
**Depends On:** P6-T4

**Objective:**
Allow the user to copy or export the currently buffered logs, for troubleshooting and bug-report purposes, with an explicit, honest warning about potential sensitive content given that full redaction is not yet implemented (Phase 8).

**Scope:**
- Included:
  - A "copy to clipboard" action for the currently buffered log contents (or the currently visible portion — agent's choice, document which, "entire buffer" is the recommended default).
  - Optionally, a "share/export as file" action using the platform's native share sheet, if implementable without disproportionate effort — if it turns out to be non-trivial, it is acceptable to ship copy-to-clipboard only and document the export-as-file action as a documented future improvement.
  - A mandatory, clear, non-dismissible-by-accident warning shown before export/copy, stating that logs may contain server addresses or other connection details and that the user should review before sharing publicly — this is a cheap, immediate safeguard pending Phase 8's full redaction system, not a replacement for it.
- Excluded:
  - Any automatic upload, telemetry, or remote log submission of any kind — this would directly violate the project's established no-telemetry policy and is absolutely out of scope, now and always, unless a future explicit, opt-in, user-initiated "send to developer" feature is deliberately designed and approved as its own task.

**Acceptance Criteria:**
- [ ] Copy-to-clipboard action works correctly and is manually verified to produce the actual current buffer contents.
- [ ] The sensitive-content warning is shown before every export/copy action and clearly worded.
- [ ] If file-export was implemented, it is verified to work via the platform share sheet on a real device/emulator; if not implemented, this is explicitly and honestly stated in the report rather than left ambiguous.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task is a deliberate, minimal stopgap for a real security gap (unredacted logs) that will not be fully closed until Phase 8. Treat the warning dialog as a genuine, non-optional safeguard, not UI decoration — do not ship this task without it.

---

### P6-T6 — Connection Session Info Panel

**Status:** Not Started
**Depends On:** P5-T8, P6-T2

**Objective:**
Consolidate glanceable session information — connection duration, active server name/protocol, and current engine state — into one minimal info panel, sitting alongside the traffic stats display from P6-T2.

**Scope:**
- Included:
  - A live-ticking connection-duration timer, starting from the moment the engine's state stream reports a successful connected transition, and stopping/resetting on disconnect.
  - Display of the currently active server's name/remark and protocol type (sourced from P5-T7's active-server selection).
  - Display of the current engine state (e.g., connecting/connected/disconnecting/disconnected/error) using the existing state stream as the sole source of truth, consistent with the architecture rule established in Section 3.5 (state stream, never inferred from command return values).
  - Deliberately minimal layout — this can be a simple panel or card, no custom illustration/branding.
- Excluded:
  - Any diagnostics beyond what is already available from existing streams (e.g., no new native-side data collection should be needed for this task — if it turns out something is missing, flag it rather than building new native plumbing under this task's scope).

**Acceptance Criteria:**
- [ ] Duration timer starts and stops correctly and accurately across at least one full connect/disconnect cycle, manually verified.
- [ ] Active server name/protocol displayed correctly and updates if the active server selection changes between sessions.
- [ ] Engine state displayed matches the actual state stream at all times, including during error states, verified by deliberately inducing at least one error condition (e.g., an invalid config or airplane-mode network loss) and observing correct display.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
If you find that displaying accurate state or duration requires new data not currently exposed by the existing state stream, stop and flag this as a gap rather than adding ad-hoc new native plumbing under this task — that would blur this task's scope with P6-T1/P3's established boundaries.

---

### P6-T7 — Phase 6 Closeout and Definition-of-Done Pass

**Status:** Not Started
**Depends On:** P6-T1 through P6-T6

**Objective:**
Perform a full closeout pass on Phase 6: verify the complete stats-and-logs experience works correctly from a fresh clone across a real connected session, produce the standard DoD report, and update `PROJECT_STATE.md` to reflect the new baseline — explicitly carrying forward the known log-redaction gap into Phase 8's eventual scope.

**Scope:**
- Included:
  - Fresh-clone build and manual run-through: connect to a real server, observe live traffic stats and live logs simultaneously, verify the session info panel, disconnect, and confirm stats/logs behave correctly across a second connect/disconnect cycle (not just the first).
  - Full `DEFINITION_OF_DONE.md`-template report covering all of Phase 6's tasks collectively.
  - Rewriting `PROJECT_STATE.md` to reflect: Phase 6 complete, live stats and logs now exist, the log-redaction gap is an explicitly tracked known limitation pointing at Phase 8, and the next phase is Phase 7 (Stability & Lifecycle Hardening).
- Excluded:
  - Any new feature work — verification/closeout only.

**Acceptance Criteria:**
- [ ] Fresh-clone full journey (connect → observe stats/logs → disconnect → reconnect → observe again) verified and described step-by-step in the report.
- [ ] DoD report produced using the exact template from `DEFINITION_OF_DONE.md`.
- [ ] `PROJECT_STATE.md` rewritten, accurate as of end of Phase 6, and explicitly carries forward the log-redaction known-limitation flag into Phase 8's scope description.
- [ ] Explicit statement of what Phase 7 will need from Phase 6 (i.e., that stats/logs/session-info plumbing exists and should continue functioning correctly through the reconnect/kill-switch/chaos scenarios Phase 7 will introduce).

**Notes for Agent:**
As with every phase closeout, do not mark this `Completed` yourself — propose `Ready for Human Review` and wait. Pay particular attention to verifying the *second* connect/disconnect cycle in this pass, not just the first — several of the legacy prototype's worst bugs (stuck STOPPING state, `initializedOnce` guard breaking subsequent starts) only manifested on repeated use, not first use.

---


## Phase 7 — Stability & Lifecycle Hardening

**Phase Goal:** Move Brick VPN from "works when everything goes right" to "behaves correctly and predictably when things go wrong" — network changes, app process death, device sleep/doze, and outright chaos/fault injection. This phase exists specifically to systematically re-prove, under real-world adverse conditions, that the legacy prototype's worst failure modes (unreliable stop, DNS bootstrap deadlocks, silent stats/connection desync) cannot recur, and to add genuinely new resilience features (auto-reconnect, kill switch) that the legacy prototype never had at all.

**Granularity Note (reaffirmed):** Written at the same coarser-but-fully-templated grain as Phases 5–6, expandable later.

---

### P7-T1 — Auto-Reconnect on Network Change

**Status:** Not Started
**Depends On:** P5-T8, P6-T6

**Objective:**
Implement automatic reconnection of the active VPN session when the underlying network connectivity changes (e.g., Wi-Fi to mobile data handoff, brief connectivity loss and recovery), instead of leaving the connection silently dead or requiring manual user intervention.

**Scope:**
- Included:
  - Verify the current correct Android mechanism for detecting network changes relevant to an active `VpnService` (e.g., `ConnectivityManager.NetworkCallback`, `underlyingNetworks` API) — check current guidance rather than assuming older APIs are still preferred, consistent with the project's no-guessing policy.
  - A defined reconnection policy: detect network change/loss → attempt to re-establish the tunnel using the same active server config → surface intermediate state (e.g., a `reconnecting` state, which may require a small, explicitly-justified amendment to the state machine/enum established in Phase 3, per Section 3.5's state-stream rules) → resolve to `connected` or `error` after a bounded number of retry attempts with backoff.
  - Explicit definition of retry count/backoff timing, documented in code and in the report — do not leave this as an unbounded or magic-number decision without justification.
  - A user-visible indication of the `reconnecting` state, minimal styling per Phase 11 deferral, surfaced through the session info panel (P6-T6).
  - A way for the user to cancel/disable auto-reconnect and manually disconnect at any point during the reconnecting sequence, without getting stuck.
- Excluded:
  - Any change to the underlying server config or protocol during reconnection (e.g., automatic failover to a different server) — this is explicitly out of scope; auto-reconnect targets the *same* server only. Multi-server failover, if ever desired, would be a distinct future feature requiring its own design.
  - Reconnection behavior when the app process itself has been killed (covered separately in P7-T6).

**Acceptance Criteria:**
- [ ] Toggling airplane mode on/off (or switching Wi-Fi/mobile data) during an active connection triggers a correct `reconnecting` → `connected` cycle, manually verified and described with specifics (timing observed, number of retries needed) in the report.
- [ ] A prolonged network outage (e.g., airplane mode left on beyond the retry budget) results in a clean, correctly-surfaced `error`/`disconnected` state, not an infinite or stuck `reconnecting` state.
- [ ] User can cancel/disconnect at any point during reconnection and the app returns to a clean disconnected state, reusing the stop-watchdog guarantee from Section 3.5.
- [ ] Any state-machine amendment (e.g., new `reconnecting` state) is clearly documented and cross-referenced back to the original Phase 1/3 state definitions so the two don't drift out of sync.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Network-change handling combined with VPN tunnels is a notoriously fiddly area on Android (interactions with `underlyingNetworks`, DNS re-resolution, and the OS's own network-transition behavior) — verify current best practice explicitly rather than relying on older Stack Overflow-era patterns. If you hit a genuinely ambiguous platform behavior (e.g., inconsistent behavior across Android versions/OEMs) that can't be resolved through research alone, stop and describe the ambiguity rather than picking one behavior and hoping it generalizes.

---

### P7-T2 — Kill Switch

**Status:** Not Started
**Depends On:** P7-T1

**Objective:**
Implement an optional, user-toggleable "kill switch" that blocks all network traffic outside the VPN tunnel whenever the VPN is supposed to be active but is not currently connected (e.g., during a failed reconnect, an unexpected drop, or before the user manually reconnects) — preventing traffic leaks, which matter significantly given this project's censorship-circumvention/privacy context.

**Scope:**
- Included:
  - Verify the current correct Android mechanism for implementing a kill switch (candidates: `VpnService.Builder`'s `setBlocking`/always-on VPN APIs, `android:supportsAlwaysOn` manifest attribute, `setMeteredNetwork`/route-based blocking, or blocking via routing all traffic through the tun interface with no fallback route) — confirm current guidance rather than assuming a specific mechanism from prior knowledge.
  - A user-facing toggle (default: off, to avoid surprising users who haven't opted in) to enable/disable the kill switch, persisted per P5-T1's storage layer or a simple settings store (whichever already exists at this point — reuse rather than introduce a new storage mechanism).
  - Correct behavior across the actual risk windows: app start before VPN connects, an unexpected connection drop mid-session, and the reconnect-attempt window from P7-T1.
  - Clear user-facing messaging when the kill switch is actively blocking traffic (so the user understands why, e.g., other apps have no internet) rather than it appearing as a silent, confusing outage.
- Excluded:
  - Android's built-in system-level "Always-on VPN + Block connections without VPN" OS setting is a separate, OS-managed feature the user can already enable in system settings independent of this app — this task is about an app-level kill switch that works even without the user enabling that OS feature, but should not conflict with or duplicate it if the user has both enabled. Document the interaction/precedence if both are active.

**Acceptance Criteria:**
- [ ] With the kill switch enabled, forcibly killing/crashing the VPN connection (e.g., via a debug-only forced-disconnect trigger, or physically disabling network) results in verified, complete network blockage for other apps until the VPN reconnects or the user disables the kill switch — verified concretely (e.g., attempting to load a webpage in another app during the blocked window and confirming failure).
- [ ] With the kill switch disabled, the same scenario results in normal (non-VPN, potentially leaking) traffic, confirming the toggle actually has effect and isn't a no-op.
- [ ] The kill switch does not falsely trigger/block during normal, successful connect/disconnect user-initiated flows — only during unexpected/unwanted disconnection while the VPN is meant to be active.
- [ ] Interaction with Android's OS-level "Block connections without VPN" setting (if the user separately enables it) is documented and does not produce contradictory or broken behavior.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This feature has real user-safety implications in this project's stated censorship/privacy context — do not ship a kill switch that appears to work in the happy path but silently fails to actually block traffic in the exact scenario it exists for (unexpected disconnection). Design your verification specifically around inducing that scenario, not just toggling the setting and eyeballing UI state.

---

### P7-T3 — DNS Correctness and Leak Prevention Hardening

**Status:** Not Started
**Depends On:** P3-T7, P5-T8

**Objective:**
Systematically re-verify and harden DNS handling end-to-end, explicitly re-checking for the DNS bootstrap deadlock risk identified in the legacy prototype (blocking geoip/geosite downloads, non-interruptible thread-pool/semaphore patterns) and adding DNS-leak prevention so that DNS queries are not inadvertently sent outside the tunnel.

**Scope:**
- Included:
  - Re-verify, against the actual pinned sing-box/libbox version, the current-correct DNS bootstrap and rule-set (geoip/geosite) loading behavior — specifically confirming whether blocking network calls to external hosts (e.g., raw.githubusercontent.com or wherever rule-sets are currently fetched from) occur during startup, and whether they can hang or deadlock startup under poor/no connectivity. This directly re-examines the exact root cause suspected (never fully confirmed) in the legacy prototype's "connected but no real traffic" failure.
  - If rule-sets are fetched remotely at runtime, implement or verify a bounded timeout and graceful degradation (e.g., proceed without rule-set-based routing rather than hanging indefinitely) so that poor connectivity during startup cannot produce an indefinitely stuck `connecting` state.
  - Explicit DNS-leak testing: verify that while connected, all DNS queries are actually routed through the tunnel and not leaking to the device's original/underlying DNS servers.
  - IP-based SNI handling re-check: the legacy prototype noted "IP-based SNI issues" as a suspected contributing factor — re-verify current correct handling of SNI when connecting to IP-address-based endpoints, if relevant to the protocols this project supports.
- Excluded:
  - Any new DNS-related *feature* (e.g., custom DNS server configuration by the user, DNS-over-HTTPS toggle) — this task is about correctness/hardening of existing behavior, not new user-facing DNS configuration options, which would be a separate future feature if ever prioritized.

**Acceptance Criteria:**
- [ ] Rule-set/geoip loading behavior under simulated poor/no connectivity (e.g., blocking the relevant hosts via a firewall rule or airplane-mode-during-startup test) is verified to degrade gracefully (bounded timeout, clear error/fallback) rather than hang indefinitely, with the test methodology described in the report.
- [ ] DNS-leak test performed and passed using a concrete, describable method (e.g., a DNS-leak-test endpoint or manual `nslookup`/packet-capture-based verification while connected) — actual evidence, not assumption.
- [ ] SNI handling for IP-based endpoints (if applicable to supported protocols) is verified correct.
- [ ] Any startup-blocking behavior discovered and fixed is clearly described, including how it relates (or doesn't) to the legacy prototype's original suspected root cause.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task directly targets a previously *suspected but never conclusively confirmed* root cause from the legacy prototype. Approach it as a genuine investigation, not a checklist formality — if you find the actual current sing-box/libbox behavior differs materially from what was suspected in the legacy prototype (e.g., rule-sets are bundled offline now, or fetched differently, or already timeout-bounded), say so clearly and explain what you found, rather than forcing a fix for a problem that may no longer exist in the current version.

---

### P7-T4 — Foreground Service Resilience (Process Death, Doze, Battery Optimization)

**Status:** Not Started
**Depends On:** P3-T17, P7-T1

**Objective:**
Harden the Android foreground VPN service against OS-level process management (Doze mode, battery optimization, low-memory process death) so the VPN connection survives realistic real-world device conditions rather than only clean, foreground, plugged-in testing conditions.

**Scope:**
- Included:
  - Verify current correct foreground-service-type declaration and any additional manifest/runtime requirements for a long-running VPN foreground service on the Android API levels this project targets (this may overlap with, but should specifically re-check for currency, whatever was established in Phase 3's initial service setup).
  - Verify and, if needed, implement guidance/prompting for the user to exclude Brick VPN from aggressive battery optimization (OEM-specific behavior on some devices, e.g., certain manufacturers' custom battery managers, is a known real-world pain point for background/VPN apps) — implement at least the standard Android `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` flow; document OEM-specific quirks as a known limitation if full coverage isn't feasible.
  - Test and document behavior under Doze mode (simulated via `adb shell dumpsys deviceidle`) to confirm the VPN connection and its foreground service survive Doze transitions correctly.
  - Test and document behavior under simulated low-memory conditions (e.g., `adb shell am kill` on the app process while the foreground service should keep it alive, or artificially inducing memory pressure) to confirm the VPN service either survives correctly or, if the OS legitimately kills it, the app's state on next launch correctly reflects "disconnected" rather than a stale "connected" display.
- Excluded:
  - Guaranteeing survival against a user manually force-stopping the app via Android system settings — this is an explicit, intentional user action the OS is designed to honor, and no app can or should try to circumvent it. Document this as an accepted, expected limitation, not a bug to fix.

**Acceptance Criteria:**
- [ ] Battery-optimization-exclusion prompt flow is implemented and manually verified to work (user is correctly taken to the relevant system dialog/settings).
- [ ] VPN connection is manually verified to survive a Doze-mode transition, with the test method (`dumpsys deviceidle` commands used) described in the report.
- [ ] App behavior after an OS-forced process kill is verified to correctly reflect actual state on next launch (no stale "connected" UI shown when the underlying service/tunnel is actually gone) — this directly matters for user trust and for avoiding a false sense of security.
- [ ] Known, undocumented-by-Google OEM-specific battery-management quirks (if encountered during testing on available test devices) are documented as known limitations rather than silently ignored.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Real-device testing matters more here than in almost any other task so far — emulator behavior for Doze/battery-optimization/process-death scenarios can differ meaningfully from real OEM devices. Use real hardware if at all available, and explicitly state in your report whether your testing was emulator-only or included real devices, and if the latter, which make/model/Android version.

---

### P7-T5 — Chaos Test Suite: Legacy Failure Mode Regression Set

**Status:** Not Started
**Depends On:** P7-T1, P7-T2, P7-T3, P7-T4

**Objective:**
Consolidate a dedicated, repeatable "chaos test suite" — automated where feasible, manually scripted where not — that deliberately reproduces every specific failure mode documented from the legacy prototype's collapse, explicitly proving each one is now handled correctly by the current architecture. This is the project's formal reckoning with its own documented history of failure.

**Scope:**
- Included:
  - Enumerate, as discrete test cases, every specific legacy failure mode documented in this project's historical record, at minimum:
    1. Traffic stats always reporting 0 bytes due to a silently-swallowed stats-connection failure.
    2. VPN reporting "connected" state while no real traffic actually flows.
    3. DNS/rule-set bootstrap hang blocking startup indefinitely.
    4. VPN failing to stop reliably due to a blocking disconnect call on the main thread.
    5. VPN failing to stop reliably due to fire-and-forget error-swallowing daemon threads.
    6. VPN failing to restart after a stop due to a `close()`-then-`initializedOnce`-guard bug.
    7. Service `onBind` returning null causing binding failures.
    8. Using `stopService()` instead of the correct `ACTION_STOP` + `stopSelf()` pattern.
    9. UI state race conditions overwriting a "stopping" state incorrectly.
    10. Orphaned coroutines/threads surviving past their owning session's lifecycle.
    11. Re-entrant stop-call deadlock risk.
    12. `detachFd()` called without a properly retained `ParcelFileDescriptor`, leaking or breaking the tunnel.
  - For each item, either point to the specific existing test (from Phase 3's P3-T9/T16 chaos tests, if it already covers this exact scenario) or write a new dedicated test/manual-verification script if not already covered, explicitly re-run against the *current, fully integrated* app (not just the Gate A native harness in isolation) — since Phase 5/6/7 have added substantial new code since Phase 3's original chaos testing.
  - Produce a single consolidated chaos-test report/checklist mapping each legacy failure mode to its current test, its current pass/fail status, and the evidence for that status.
- Excluded:
  - Inventing entirely new failure scenarios unrelated to the documented legacy history — this task is specifically a regression/reckoning exercise against known past failures, not general new fault-injection testing (which may be worth doing but is not this task's purpose).

**Acceptance Criteria:**
- [ ] All twelve (or however many are actually documented in the project's historical record at execution time) legacy failure modes are individually enumerated, tested against the current full app, and shown to pass, with concrete evidence for each (not a blanket "seems fine").
- [ ] The consolidated chaos-test checklist/report is committed to the repository (e.g., under `docs/` or wherever test artifacts live) as a durable, re-runnable reference, not just described in the completion report and then lost.
- [ ] Any legacy failure mode that is found to still reproduce, even partially, is treated as a release-blocking bug, fixed before this task can be proposed as `Ready for Human Review`, and explicitly called out in the report as "found and fixed" rather than glossed over.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task is, in a real sense, the project settling its own accounts with its predecessor. Take it seriously and literally — go back through the project's documented history of the legacy prototype's failures (available in prior session context/documentation) and make sure nothing on that list is skipped or hand-waved. If you're not fully certain whether a given legacy issue is genuinely fixed by the current architecture versus merely "probably fine because the architecture is different now," treat that uncertainty itself as a reason to write an explicit test rather than assume.

---

### P7-T6 — VPN State Persistence Across App Process Restart

**Status:** Not Started
**Depends On:** P7-T4

**Objective:**
Ensure that if the Brick VPN app's Flutter/UI process is killed and relaunched while the native VPN service is still legitimately running in the background (a normal, supported Android pattern for foreground services), the app correctly re-attaches to and reflects the actual live state of the ongoing connection, rather than showing an incorrect default/disconnected state or, worse, allowing the user to start a conflicting second session.

**Scope:**
- Included:
  - Verify the current correct pattern for a Flutter app to query/re-attach to an already-running Android foreground service's state on app (re)launch (e.g., a synchronous state query on the Pigeon-generated interface performed during app startup, before the UI settles on an initial connection-state display).
  - Ensure the app-startup sequence (whatever was established in Phase 4's app skeleton/routing) correctly incorporates this state re-attachment as an early step, so the user never sees a flash of incorrect "disconnected" state before the real state loads.
  - Verify correct behavior for the traffic-stats and log streams (P6-T1/T3) reconnecting/resuming correctly after this kind of app-process restart, not just the connection-state stream.
  - Prevent the possibility of a duplicate/conflicting session start attempt if the app doesn't realize a session is already active (this connects to and should reuse whatever session-token/busy-rejection logic already exists per Section 3.5's `rejectedBusy` command-response rule).
- Excluded:
  - True device reboot handling (i.e., whether the VPN should attempt to auto-start after a full device reboot) — this is a distinct, separate feature (often called "connect on boot") that has not yet been scoped anywhere in this roadmap; if desired, it should be proposed as a new, explicitly separate future task rather than folded silently into this one.

**Acceptance Criteria:**
- [ ] Killing and relaunching the Flutter app process (via `adb shell am kill` or Android's own recent-apps swipe-to-close, while the VPN service continues running) results in the relaunched app correctly displaying the actual live connected state, active server, and resuming stats/logs, verified manually with specifics described in the report.
- [ ] No flash of incorrect state is visible during the app's startup/re-attachment sequence, or if unavoidable due to a brief async gap, it is a neutral "loading/checking state" rather than a misleading "disconnected" flash.
- [ ] Attempting to start a new connection from the relaunched app while a session is already active correctly results in a `rejectedBusy` (or equivalent) response, not a duplicate/conflicting session.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This scenario (UI process death independent of the long-lived foreground service) is a completely normal, frequent occurrence on Android and must be treated as a first-class supported case, not an edge case — many real users will experience this simply by the OS reclaiming the Flutter engine's memory while the VPN keeps running in the background.

---

### P7-T7 — Phase 7 Closeout and Definition-of-Done Pass

**Status:** Not Started
**Depends On:** P7-T1 through P7-T6

**Objective:**
Perform a full closeout pass on Phase 7: verify the complete resilience feature set (auto-reconnect, kill switch, DNS hardening, foreground-service resilience, chaos-test regression suite, process-restart re-attachment) works correctly together from a fresh clone, produce the standard DoD report, and update `PROJECT_STATE.md` to reflect the new baseline before Phase 8 begins.

**Scope:**
- Included:
  - Fresh-clone build and a combined real-world stress run: connect, induce a network change (auto-reconnect), induce an unexpected drop with kill switch enabled, kill and relaunch the app process mid-session, and re-run the full chaos-test checklist from P7-T5 one final time against this fully integrated state.
  - Full `DEFINITION_OF_DONE.md`-template report covering all of Phase 7's tasks collectively.
  - Rewriting `PROJECT_STATE.md` to reflect: Phase 7 complete, the app is now resilient to network changes/process death/common failure modes, the full legacy-failure-mode chaos checklist passes, and the next phase is Phase 8 (Security Hardening) — explicitly carrying forward the known log-redaction gap (from P6-T7) as Phase 8's primary open item.
- Excluded:
  - Any new feature work — verification/closeout only.

**Acceptance Criteria:**
- [ ] Fresh-clone combined stress run completed and described step-by-step in the report, covering all resilience features working together, not just individually.
- [ ] Final re-run of the P7-T5 chaos checklist confirmed passing against the fully integrated Phase 7 state.
- [ ] DoD report produced using the exact template from `DEFINITION_OF_DONE.md`.
- [ ] `PROJECT_STATE.md` rewritten, accurate as of end of Phase 7, explicitly listing the carried-forward log-redaction gap as Phase 8's primary open item.
- [ ] Explicit statement of what Phase 8 will need from Phase 7 (i.e., stable connection lifecycle and logging plumbing to build secure-storage and redaction on top of, without needing to revisit lifecycle correctness itself).

**Notes for Agent:**
As with every phase closeout, do not mark this `Completed` yourself — propose `Ready for Human Review` and wait. This closeout is unusually important given this phase's explicit purpose of settling the project's historical failure record — be thorough and honest in the report, including calling out anything that took longer or proved harder than expected, since that information has real value for how the human plans the remaining phases.

---

## Phase 8 — Security Hardening

**Phase Goal:** Systematically close the security gaps that were deliberately deferred throughout Phases 1–7 — most notably the log-redaction gap explicitly flagged in Phase 6/7's closeouts — and add the baseline security posture expected of a censorship-circumvention-relevant VPN client: encrypted local storage for sensitive fields, redacted logging, secure update/integrity verification, and a general security self-review of everything shipped so far.

**Granularity Note (reaffirmed):** Written at the same coarser-but-fully-templated grain as Phases 5–7, expandable later.

---

### P8-T1 — Secure Storage for Sensitive Server Fields

**Status:** Not Started
**Depends On:** P5-T1

**Objective:**
Encrypt sensitive fields within persisted `ServerProfile` records (passwords, UUIDs, private keys, pre-shared keys — whichever fields are actually sensitive given the protocols this project supports) at rest, closing the gap explicitly deferred in P5-T1.

**Scope:**
- Included:
  - Verify the current correct, maintained secure-storage mechanism for Flutter/Android (candidates: `flutter_secure_storage` backed by Android Keystore, or field-level encryption layered on top of the P5-T1 storage engine using a key held in Android Keystore) — confirm current maintenance status and correctness rather than assuming a specific package is still the right choice.
  - Identify, per supported protocol (from Phase 2's parser output), exactly which fields are sensitive and require encryption (e.g., VMess UUID, Trojan password, Shadowsocks password, VLESS UUID/private keys) versus which fields are non-sensitive and can remain in plaintext for query/display efficiency (e.g., server address, remark/name, protocol type).
  - Implement field-level (not whole-record) encryption so that non-sensitive fields remain queryable/displayable without a decryption round-trip, while sensitive fields are only decrypted when actually needed (e.g., at connect time when passed to the native engine).
  - Migrate any already-persisted sensitive data (from real-world usage during Phases 5–7 development/testing) to the new encrypted format, or, if no real migration path is feasible/needed at this pre-release stage, document that existing dev/test data will simply be cleared and note this clearly as acceptable since no real users exist yet.
  - Ensure decrypted sensitive values are handled carefully in memory (not lingering longer than needed, not accidentally logged — this connects directly to P8-T2's redaction work) once passed to the native engine invocation path.
- Excluded:
  - Full-disk encryption or OS-level device security — out of scope, relies on the underlying OS/device security model.
  - Biometric/passcode app-lock feature — a distinct, separate potential future feature not currently scoped anywhere in this roadmap; if desired later, it should be proposed as its own task.

**Acceptance Criteria:**
- [ ] Chosen secure-storage mechanism is verified current/maintained and documented with rationale.
- [ ] Sensitive vs. non-sensitive field classification is explicitly documented per supported protocol.
- [ ] Sensitive fields are verified, by direct inspection of the actual on-disk storage (e.g., pulling the app's data directory via `adb` and inspecting the raw file/database contents), to be genuinely encrypted/unreadable in plaintext.
- [ ] Non-sensitive fields remain efficiently queryable without requiring decryption, verified by confirming the server-list screen (P5-T5) still performs acceptably.
- [ ] End-to-end connect flow (P5-T8) still works correctly with the now-encrypted sensitive fields, verified with a real connection test.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Verify your chosen mechanism's actual current behavior on the Android API levels this project targets — Android Keystore behavior has had version-specific quirks historically (e.g., certain API levels' StrongBox availability, key invalidation on biometric enrollment changes). Do not assume a package's documentation is fully current; test the actual behavior on a real or accurately configured emulator device.

---

### P8-T2 — Log Redaction

**Status:** Not Started
**Depends On:** P6-T3, P8-T1

**Objective:**
Implement systematic redaction of sensitive information from the live log stream and any log buffer (established in Phase 6), closing the gap explicitly and repeatedly flagged since P6-T3/T7.

**Scope:**
- Included:
  - Define, in code and documentation, the concrete set of redaction rules: which fields/patterns must never appear in logs in plaintext (server addresses potentially, credentials/UUIDs/passwords definitely, and any other field identified as sensitive in P8-T1's classification).
  - Because P6-T3 was explicitly required to keep log entries as structured data (not pre-flattened opaque strings), implement redaction at the structured-field level where possible (e.g., a known "password" field is always redacted before display/export, regardless of surrounding message text) rather than relying solely on fragile regex-over-freetext matching.
  - For log content that originates from the native engine as unstructured free text (where structured redaction isn't possible), implement a best-effort pattern-based redaction pass (e.g., regex matching for common credential-shaped substrings) and explicitly document its known limitations (regex-based redaction can never be 100% guaranteed complete).
  - Apply redaction consistently across all three surfaces established in Phase 6: the live log viewer (P6-T4), the copy/export function (P6-T5), and any future log persistence.
  - Provide a clearly-labeled, off-by-default "verbose/debug mode" toggle (if a genuine debugging need exists for unredacted logs during development) that keeps redaction on by default for normal users and only exposes unredacted logs behind an explicit, clearly-scary-worded opt-in intended for advanced troubleshooting — document clearly if this toggle is or isn't implemented, don't build it speculatively if not clearly needed.
- Excluded:
  - Redacting data the app doesn't control at all (e.g., if a future telemetry/crash-reporting system were ever added — which it currently is not, per the no-telemetry policy — that would need its own redaction review at that time).

**Acceptance Criteria:**
- [ ] Concrete redaction rule set is documented (which fields/patterns, and why).
- [ ] Structured-field redaction is verified working for all fields classified as sensitive in P8-T1, confirmed by deliberately triggering log output containing such fields and inspecting the actual displayed/exported result.
- [ ] Best-effort free-text redaction (if implemented) is tested against realistic sample log lines and its known limitations are honestly documented.
- [ ] Redaction is verified consistent across the log viewer, copy/export function, and any buffer inspection point — no surface leaks what another surface redacts.
- [ ] The P6-T5 sensitive-content warning dialog is re-evaluated now that redaction exists — either retained (if residual risk still justifies it) or removed/updated, with the decision documented.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Be honest and precise in your report about the actual completeness of redaction — do not claim "all sensitive data is now redacted" if what was actually built is a best-effort regex pass with known gaps. This is exactly the kind of overclaiming the project's Definition-of-Done process (self-review as an independent debugger) exists to catch; genuinely try to break your own redaction logic before reporting it as done.

---

### P8-T3 — Input Validation and Untrusted-Data Security Review (Full Pass)

**Status:** Not Started
**Depends On:** P2-T3 through P2-T11, P5-T2, P5-T3, P5-T4

**Objective:**
Perform a dedicated, project-wide security review of every code path that handles untrusted external input — pasted links, QR-scanned content, subscription-fetched content, and any other externally-sourced data — verifying that the security-conscious handling required since Phase 2 was actually implemented correctly and consistently everywhere it applies, not just in the original parser package.

**Scope:**
- Included:
  - Re-audit every Phase 2 protocol parser and the Phase 2 subscription-fetch logic specifically for: proper bounds checking on untrusted string lengths, safe handling of malformed/malicious Base64 or URI-encoded content, resistance to trivial denial-of-service via pathological input (e.g., extremely long strings, deeply nested or repetitive structures if the format allows them), and safe handling of unexpected/unknown fields (ignored, not crashed on).
  - Re-audit the Phase 5 add-server flows (manual paste, QR scan, subscription import) to confirm the UI layer doesn't bypass or weaken the parser's validation (e.g., no ad-hoc string manipulation before handing input to the parser that could defeat its safety checks).
  - Verify subscription-fetch network behavior (P2-T9/T10) against basic network-security expectations: TLS certificate validation is not disabled/bypassed anywhere, redirects are handled safely (no unbounded redirect chains), and response size is bounded to prevent memory-exhaustion from a malicious/compromised subscription source.
  - Produce a written security review report (can live under `docs/security/` or referenced from `SECURITY.md`) listing what was checked, what was found, and what (if anything) was fixed as a result.
- Excluded:
  - Formal penetration testing or third-party security audit — out of scope for a solo/AI-assisted project at this stage; this is a rigorous internal self-review, not a substitute for professional audit, and the report should say so honestly.

**Acceptance Criteria:**
- [ ] Every Phase 2 parser is re-audited against the checklist above, with findings documented per-parser.
- [ ] At least one deliberate adversarial-input test per parser (e.g., a fuzzed/malformed/oversized input) is performed and its outcome (safe rejection vs. crash vs. unexpected behavior) is documented; any crash or unsafe behavior found is fixed before this task can be proposed as `Ready for Human Review`.
- [ ] Subscription-fetch network behavior is verified against the TLS/redirect/size-bounding checklist above, with evidence.
- [ ] A written security review report is committed to the repository.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template, in addition to (not instead of) the dedicated security review report.

**Notes for Agent:**
Approach this task adversarially — actively try to construct inputs designed to break the parsers and fetch logic (absurdly long strings, malformed encoding, unexpected nesting, a subscription server that returns gigabytes of data or an infinite redirect loop) rather than only confirming happy-path and previously-known error cases still work. This is the project's dedicated opportunity to find what wasn't caught during Phase 2's original, necessarily-more-implementation-focused development.

---

### P8-T4 — App Update Integrity Verification

**Status:** Not Started
**Depends On:** P0-T8

**Objective:**
Ensure users can verify the authenticity and integrity of Brick VPN releases/updates obtained outside an app store (e.g., direct APK download from GitHub Releases), given this project's GitHub-Actions-based CI/release process and its relevance to censorship-circumvention-tool trust precedent (Signal/Tor Browser/F-Droid style reproducible-build and signature-verification norms).

**Scope:**
- Included:
  - Verify/establish that release APKs produced by CI are signed with a consistent, properly-secured signing key (this may substantially overlap with signing work more fully scoped in Phase 10 — if so, this task should focus specifically on the *verification/transparency* side: publishing checksums, documenting the expected signing certificate fingerprint, and/or exploring reproducible-build verification, while deferring the actual release-signing pipeline mechanics to Phase 10 if not yet built).
  - Publish SHA-256 (or currently-recommended equivalent) checksums alongside each GitHub Release artifact, and document, in the repository (e.g., `README.md` or a dedicated `docs/verifying-releases.md`), how a user can independently verify a downloaded APK's checksum and/or signing certificate fingerprint.
  - Investigate and document (even if full implementation is deferred to Phase 10 or later) the feasibility of reproducible builds for this specific project's toolchain (Flutter + Go/gomobile), given the reproducible-builds precedent noted from Signal/Tor Browser/F-Droid — an honest "not yet fully reproducible, here's what would be needed" documentation is an acceptable outcome if full reproducibility isn't achievable at this stage.
- Excluded:
  - Building a full auto-update-with-signature-verification mechanism inside the app itself — out of scope; users are expected to obtain updates via GitHub Releases or an app store (Phase 10), which have their own respective integrity guarantees (Play Store's own signing verification, or manual checksum verification for direct APK).

**Acceptance Criteria:**
- [ ] Release signing key existence/security is verified or explicitly flagged as not-yet-established (cross-referencing Phase 10 if that's where full signing work belongs).
- [ ] Checksum publication is implemented in the CI release pipeline (from P0-T8) and verified by producing at least one real tagged test release and confirming the checksum file is correctly generated and matches the artifact.
- [ ] User-facing verification documentation is written and committed.
- [ ] Reproducible-build feasibility investigation is documented honestly, whatever the conclusion.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Do not overstate what's achieved here — if full reproducible builds aren't realistically achievable at this point in the project's maturity, say so plainly and document the gap as a future improvement rather than implying a stronger guarantee than actually exists. Trust-related documentation for a censorship-circumvention tool must be scrupulously honest, since overclaiming security properties is arguably worse than not claiming them at all.

---

### P8-T5 — Dependency and Supply-Chain Security Pass

**Status:** Not Started
**Depends On:** P0-T8

**Objective:**
Perform a review of the project's dependency supply chain (Dart/Flutter pub packages, Go modules, Android/Gradle dependencies) for known vulnerabilities, unmaintained packages, and excessive/unnecessary permission or capability footprint, and establish an ongoing lightweight process for catching future issues.

**Scope:**
- Included:
  - Run current, appropriate dependency-vulnerability scanning tools for each part of the stack (verify what's actually current/appropriate — e.g., `dart pub outdated`/`pub audit`-equivalent tooling if it exists, Go's `govulncheck`, Gradle dependency vulnerability plugins, and/or GitHub's own Dependabot if not already enabled) — do not assume a specific tool's continued existence/relevance without checking.
  - Review the full dependency tree (not just direct dependencies) for anything clearly abandoned/unmaintained, and document/flag (not necessarily immediately replace, if replacement is disruptive) any findings.
  - Review Android manifest permissions declared by the app and confirm each one is actually necessary and justified (no leftover permissions from scaffolding/templates that aren't actually used).
  - Set up GitHub Dependabot (or equivalent, verified-current tool) for ongoing automated dependency-update PRs, if not already configured as part of P0-T8's CI setup.
- Excluded:
  - Manually auditing the full source code of every dependency — infeasible at this scale; this task relies on tooling and metadata (known CVEs, maintenance status) rather than full source review of third-party code.

**Acceptance Criteria:**
- [ ] Vulnerability scan results for each part of the stack are documented, and any found high/critical severity issues are addressed (updated/patched/mitigated) before this task can be proposed as `Ready for Human Review`.
- [ ] Unmaintained-dependency findings are documented with a risk assessment (low/medium/high concern) even if not immediately actioned.
- [ ] Android manifest permissions are confirmed minimal-and-justified, with any unused/unnecessary permissions removed.
- [ ] Dependabot (or equivalent) is confirmed active and correctly configured for this repository.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This is exactly the kind of task where current, verified information matters more than general knowledge — tooling in this space (vulnerability scanners, Dependabot configuration syntax, `govulncheck` usage) changes over time; confirm current usage patterns rather than relying on possibly-outdated familiarity.

---

### P8-T6 — Phase 8 Closeout and Definition-of-Done Pass

**Status:** Not Started
**Depends On:** P8-T1 through P8-T5

**Objective:**
Perform a full closeout pass on Phase 8: verify the complete security-hardening feature set (secure storage, log redaction, input-validation review, update-integrity verification, dependency supply-chain review) is correctly integrated, produce the standard DoD report, and update `PROJECT_STATE.md` to reflect the new baseline before Phase 9 begins.

**Scope:**
- Included:
  - Fresh-clone build and a combined verification pass: confirm sensitive fields are encrypted at rest, confirm logs are redacted end-to-end during a real connected session, spot-check at least one adversarial input from P8-T3's testing still behaves safely, confirm release checksum publication works, confirm dependency scanning is active.
  - Full `DEFINITION_OF_DONE.md`-template report covering all of Phase 8's tasks collectively.
  - Rewriting `PROJECT_STATE.md` to reflect: Phase 8 complete, the app now has a documented baseline security posture, all previously-tracked security gaps (log redaction, secure storage) are closed or their residual limitations honestly documented, and the next phase is Phase 9 (Testing & QA).
- Excluded:
  - Any new feature or security work beyond verifying and consolidating what P8-T1 through P8-T5 already built.

**Acceptance Criteria:**
- [ ] Fresh-clone combined verification pass completed and described step-by-step in the report.
- [ ] DoD report produced using the exact template from `DEFINITION_OF_DONE.md`.
- [ ] `PROJECT_STATE.md` rewritten, accurate as of end of Phase 8, with all previously-tracked security gaps explicitly resolved or their remaining limitations clearly stated (not silently dropped from tracking).
- [ ] Explicit statement of what Phase 9 will need from Phase 8 (i.e., a security-hardened, resilient app ready for systematic test-suite buildout and manual QA protocol design).

**Notes for Agent:**
As with every phase closeout, do not mark this `Completed` yourself — propose `Ready for Human Review` and wait. Given this phase's subject matter, hold yourself to an especially high honesty bar in the report: clearly distinguish between "verified secure," "best-effort mitigation with known limitations," and "not yet addressed, flagged for future work" for each item, rather than presenting a uniformly reassuring summary.

---

## Phase 9 — Testing & QA

**Phase Goal:** Consolidate and systematize testing across the entire project — unit, integration, and manual QA — into a coherent, repeatable process, closing gaps left by the necessarily task-scoped, incremental testing performed throughout Phases 0–8. This phase exists to catch cross-cutting issues that only become visible when the whole system is tested as a whole, and to produce a durable manual test protocol the human can run before any future release.

**Granularity Note (reaffirmed):** Written at the same coarser-but-fully-templated grain as Phases 5–8, expandable later.

---

### P9-T1 — Unit Test Coverage Audit and Gap-Filling

**Status:** Not Started
**Depends On:** P8-T6

**Objective:**
Audit unit test coverage across all packages (`core_domain`, `config_parser`, state-management/provider logic, utility code) built throughout Phases 1–8, identify meaningful coverage gaps (not just raw percentage, but untested critical logic), and fill the gaps that matter.

**Scope:**
- Included:
  - Run coverage tooling (`flutter test --coverage` / `dart test --coverage` and Go's equivalent for any Go-side unit-testable logic) across all packages, and review the actual coverage report, not just a summary percentage.
  - Distinguish genuinely important untested logic (parsing edge cases, state-machine transition logic, repository CRUD edge cases, redaction rules) from low-value untested code (trivial getters, generated code, UI boilerplate) — prioritize filling gaps in the former, explicitly do not chase 100% coverage as a vanity metric.
  - Write missing unit tests for identified high-value gaps.
  - Document the final coverage state (tool used, percentage achieved, and — more importantly — a qualitative statement of what critical logic is now covered) in a short report.
- Excluded:
  - Native Android instrumented/on-device unit tests beyond what Phase 3 already established — this task focuses on Dart/Go unit-testable logic; Android-specific on-device testing is covered by P9-T2's integration scope and Phase 3's existing chaos-test harness.

**Acceptance Criteria:**
- [ ] Coverage report generated and reviewed for all applicable packages.
- [ ] A documented list of identified high-value gaps and which were filled (with justification for any deliberately left unfilled).
- [ ] All newly written tests pass in CI.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Resist the temptation to treat this task as "raise the coverage number." A parser's malformed-input rejection path or a state machine's rare transition is worth far more test attention than a trivial data-class getter — use judgment, and document that judgment in the report so the human can sanity-check your prioritization.

---

### P9-T2 — Integration Test Suite: Cross-Feature Journeys

**Status:** Not Started
**Depends On:** P9-T1, P7-T7

**Objective:**
Build an automated (or, where full automation isn't feasible on Android VPN infrastructure, rigorously scripted semi-manual) integration test suite covering complete cross-feature user journeys that span multiple phases' work together, which no single phase's own tests were responsible for covering end-to-end.

**Scope:**
- Included:
  - Verify current best practice for Flutter integration testing on Android, especially given the VpnService/foreground-service/native-engine involvement (e.g., `integration_test` package, `patrol`, or another current tool — check maintenance status and suitability for VPN-permission-requiring flows before choosing, since VPN permission dialogs and foreground services can be awkward for standard integration-test tooling).
  - Define and implement at least the following cross-feature journeys as integration tests or, if genuinely infeasible to automate given VPN-specific OS interaction constraints, as precisely scripted manual test procedures documented in a way a human (or future agent) can execute repeatably:
    1. Fresh install → add server (manual paste) → connect → observe stats/logs → disconnect → app restart → state correctly re-attaches.
    2. Add subscription → refresh subscription → delete a subscription-sourced server's parent → verify children removed → connect to a remaining standalone server.
    3. Enable kill switch → induce unexpected disconnect → verify traffic blocked → reconnect → verify traffic resumes and kill switch releases correctly.
    4. Network change mid-connection (auto-reconnect) combined with live stats/log observation continuing correctly through the reconnect.
  - Document, for any journey that could not be fully automated, exactly why (specific tooling/OS limitation encountered), so this isn't mistaken for laziness by a future reviewer.
- Excluded:
  - Re-testing anything already fully covered by Phase 7's chaos-test suite (P7-T5) in isolation — this task is specifically about *cross-feature* journeys spanning multiple phases' features together, not re-running single-feature tests.

**Acceptance Criteria:**
- [ ] All four (or more, if the agent identifies additional valuable cross-feature journeys) journeys are implemented as automated tests, or documented as precise, repeatable manual scripts with clear justification for non-automation.
- [ ] Automated journeys pass reliably (run at least three times to check for flakiness; document any flaky behavior found and its resolution or known-limitation status).
- [ ] Manual scripts (if any) are committed to the repository in a clearly discoverable location (e.g., `docs/testing/manual-integration-scripts.md`).
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
VPN-permission dialogs and foreground-service lifecycle are known pain points for Android integration-test tooling — verify current, real capability of whatever tool you choose against these specific constraints before committing to full automation; a well-documented manual script is a more honest deliverable than a flaky or fake automated test that doesn't actually exercise what it claims to.

---

### P9-T3 — Manual QA Test Protocol Document

**Status:** Not Started
**Depends On:** P9-T2

**Objective:**
Produce a comprehensive, durable manual QA test protocol document — a checklist a human (the project owner, or eventually a contributor) can run through before any release, covering functional correctness, resilience, and security-relevant behavior across the entire app, consolidating and cross-referencing everything validated piecemeal throughout Phases 0–9.

**Scope:**
- Included:
  - A single, well-organized document (e.g., `docs/testing/manual-qa-protocol.md`) structured by feature area (server management, connect/disconnect, stats/logs, resilience/kill-switch, security-relevant behaviors) with clear step-by-step procedures and expected outcomes for each.
  - Explicit cross-references back to the specific tasks/tests each protocol section originates from (e.g., "see P7-T5 chaos checklist for full legacy-regression detail") rather than duplicating full detail redundantly.
  - A recommended minimum device/OS-version test matrix (e.g., minimum supported Android version, a recent Android version, at least one non-Google-Pixel OEM device if available) reflecting real-world diversity, given the OEM-specific quirks already noted in P7-T4.
  - A clear statement of protocol scope: this document is for pre-release manual verification, distinct from (and complementary to) the automated test suites from P9-T1/T2.
- Excluded:
  - Automating this protocol — by definition this is the manual/human-judgment layer; if a step becomes fully automatable it should graduate into P9-T2's suite instead, with a note left behind pointing there.

**Acceptance Criteria:**
- [ ] Document is committed to the repository, well-organized, and covers all major feature areas built through Phase 9.
- [ ] Cross-references to originating tasks/tests are present and accurate.
- [ ] Document was actually test-driven at least once by the agent (i.e., the agent ran through their own written protocol at least once end-to-end to confirm it's actually followable and produces the expected outcomes) before being proposed as complete.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Write this for a future reader who has much less context than you currently have (possibly the human themself in six months, or a future contributor) — be explicit about setup steps, expected exact outcomes, and what "pass" vs. "fail" looks like for each item, rather than assuming shared context.

---

### P9-T4 — Phase 9 Closeout and Definition-of-Done Pass

**Status:** Not Started
**Depends On:** P9-T1 through P9-T3

**Objective:**
Perform a full closeout pass on Phase 9: confirm the full automated test suite (unit + integration) passes cleanly from a fresh clone, confirm the manual QA protocol is complete and usable, produce the standard DoD report, and update `PROJECT_STATE.md` to reflect that the project is now ready to enter Phase 10 (Android MVP Release Prep).

**Scope:**
- Included:
  - Fresh-clone full automated test suite run (unit + integration) with a clean pass, and a fresh-clone run-through of at least a representative subset of the manual QA protocol.
  - Full `DEFINITION_OF_DONE.md`-template report covering all of Phase 9's tasks collectively.
  - Rewriting `PROJECT_STATE.md` to reflect: Phase 9 complete, the project has a comprehensive automated + manual test posture, and the next phase is Phase 10 (Android MVP Release Prep) — the final phase before a real, stable, usable Android MVP exists.
- Excluded:
  - Any new test-writing beyond fixing anything broken discovered during this closeout pass.

**Acceptance Criteria:**
- [ ] Fresh-clone full automated test suite passes cleanly, confirmed and described in the report.
- [ ] Representative manual QA protocol subset run-through completed and described.
- [ ] DoD report produced using the exact template from `DEFINITION_OF_DONE.md`.
- [ ] `PROJECT_STATE.md` rewritten, accurate as of end of Phase 9, explicitly noting the project is now feature-complete and hardened for MVP release prep.
- [ ] Explicit statement of what Phase 10 will need from Phase 9 (a fully tested, stable app ready for signing/packaging/release-process work, with no known functional or resilience regressions outstanding).

**Notes for Agent:**
As with every phase closeout, do not mark this `Completed` yourself — propose `Ready for Human Review` and wait. This closeout marks the threshold just before Android MVP release prep — take particular care that nothing is quietly broken or flaky, since Phase 10 will assume the app underneath the release packaging is solid.

---

## Phase 10 — Android MVP Release Prep

**Phase Goal:** Take the fully built, tested, and hardened app from Phase 9 and turn it into an actually distributable Android MVP — signed, packaged correctly for both direct-APK and Play Store distribution, compliant with Play Store's VPN-specific policy requirements, and released. Completion of this phase marks the milestone stated in the project's Key Results: **a stable, usable Android MVP exists.**

**Granularity Note (reaffirmed):** Written at the same coarser-but-fully-templated grain as Phases 5–9, expandable later. This phase also formally picks up several concerns explicitly flagged earlier in the project as "future concerns, not yet ticketed" — ProGuard/R8 gomobile keep rules, AAB/ABI-split distribution, and Play Store's VPN-specific declaration requirements — and gives each its own task now that the project has reached the phase where they actually matter.

---

### P10-T1 — Release Signing Key Setup and CI Signing Pipeline

**Status:** Not Started
**Depends On:** P0-T8, P8-T4

**Objective:**
Establish a real, securely-managed release signing key for Android, and wire automated, reproducible release signing into the CI pipeline established in P0-T8, building directly on the checksum-publication and integrity-verification groundwork from P8-T4.

**Scope:**
- Included:
  - Generate a proper release signing keystore following current official Android guidance (key algorithm, validity period, keystore format — verify current recommendations rather than assuming older guidance still applies).
  - Establish a secure key-storage and CI-secret-injection process (e.g., GitHub Actions encrypted secrets) so the private key material is never committed to the repository and is only accessible to the release-build CI job.
  - Wire the signing step into the CI pipeline so that tagged release builds are automatically signed, producing a properly signed AAB and/or APK as CI artifacts.
  - Document the signing certificate's fingerprint (SHA-256) publicly (e.g., in the repository or release notes) so users and, later, Play Store can cross-verify it — this directly complements and completes the checksum/fingerprint documentation groundwork started in P8-T4.
  - Document, clearly and for the human's own future reference (not just the agent's), the exact key-backup/recovery procedure and the severe consequences of key loss (inability to publish updates to the same Play Store listing, or users being unable to verify update authenticity for direct APKs) — this is a human-owned operational risk, not something the agent can mitigate technically beyond documenting it clearly.
- Excluded:
  - Play App Signing (Google-managed signing key) enrollment decision — that is a Play-Store-specific choice belonging to P10-T7; this task only needs to produce a correctly signed, verifiable release artifact regardless of which final signing arrangement Play Store submission ultimately uses.

**Acceptance Criteria:**
- [ ] Release keystore generated following current official guidance, with generation parameters documented.
- [ ] CI pipeline produces a correctly signed release build from a test tag, verified by inspecting the artifact's signature (e.g., via `apksigner verify`) and confirming it matches the documented fingerprint.
- [ ] Private key material confirmed absent from the repository history (explicit check, not assumption).
- [ ] Key-backup/recovery procedure and its risks are clearly documented for the human.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This is one of the few tasks in the entire project where a mistake (leaking the signing key, or losing it with no backup) has effectively irreversible real-world consequences for the human's ability to maintain this project long-term. Be unusually careful and explicit here — if anything about secret handling in the current CI setup seems even slightly uncertain, stop and confirm with the human before proceeding, rather than proceeding on a best-guess basis.

---

### P10-T2 — ProGuard/R8 Release Hardening and Gomobile Bridge Keep Rules

**Status:** Not Started
**Depends On:** P3-T17

**Objective:**
Correctly configure ProGuard/R8 rules for release builds so that minification/obfuscation does not break the gomobile-generated Java/Kotlin bridge classes — directly resolving the previously-flagged-but-unticketed risk that release builds could crash with `NoClassDefFoundError` due to missing keep rules for `go.Seq`/`go.*` and related gomobile bridge classes.

**Scope:**
- Included:
  - Verify the current correct set of ProGuard/R8 keep rules needed for whatever gomobile/libbox AAR integration approach was actually implemented in Phase 3 (rules may differ depending on the exact gomobile version and binding generation approach used — do not assume a generic rule set found in unrelated projects applies unmodified).
  - Add the verified keep rules to the app's `proguard-rules.pro` (or equivalent R8 configuration).
  - Build a genuine release-mode (minified, obfuscated) build and perform a real, full connect/disconnect/traffic-stats/logs verification pass against it — not just a debug-mode build — to concretely prove the bridge survives minification. This is the specific, concrete test the legacy-flagged risk demands.
  - Check for and add any other keep rules needed for other parts of the stack that might also be affected by minification (e.g., any reflection-based JSON serialization in Dart-generated platform channel code, if applicable, or other native-library-adjacent classes).
- Excluded:
  - General app-wide ProGuard/R8 optimization tuning beyond what's needed for correctness — this task is about not breaking the app, not about advanced size/performance optimization, which could be a separate future task if ever prioritized.

**Acceptance Criteria:**
- [ ] Correct, verified keep rules are added and documented with rationale (referencing what would break without them).
- [ ] A real release-mode (minified) build is produced and manually tested end-to-end (connect, real traffic verification, stats, logs, disconnect) with zero `NoClassDefFoundError` or related crashes, and this test is described concretely in the report.
- [ ] Any other minification-sensitive areas found are documented and addressed.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task exists specifically because this exact failure mode (release-only crash due to missing gomobile keep rules) is a well-documented, real risk pattern in gomobile-based Android projects — do not treat this as routine boilerplate copy-pasting; genuinely build and test a release-mode artifact, since debug-mode testing (which disables minification) would not catch this class of bug at all.

---

### P10-T3 — AAB Build and ABI-Split Configuration for Dual Distribution

**Status:** Not Started
**Depends On:** P10-T1, P10-T2

**Objective:**
Configure the build system to correctly produce both an Android App Bundle (AAB) for Play Store distribution and appropriately ABI-split (or universal, if deliberately chosen) APKs for direct/GitHub-Release distribution, resolving the previously-flagged-but-unticketed AAB/ABI-split distribution requirement.

**Scope:**
- Included:
  - Verify current Play Store requirements regarding AAB submission and Play Feature Delivery/App Bundle ABI splitting (Play Store has required AAB for new apps for some time; confirm current specifics rather than assuming outdated requirements).
  - Configure Gradle to produce a correct AAB including all ABIs the project supports (confirm which native ABIs are actually built by the gomobile/libbox AAR from Phase 3 — likely `arm64-v8a` and `armeabi-v7a` at minimum, verify if `x86`/`x86_64` are also produced/needed for emulator-based testing distribution).
  - Configure a separate direct-APK build path for GitHub Releases: decide and document whether to ship a universal APK (larger, simpler for users) or per-ABI split APKs (smaller, requires the user to pick correctly) — a universal APK is the recommended default for a non-technical-user-facing direct-download channel, unless the agent finds a strong concrete reason otherwise.
  - Verify both artifact types build correctly through the CI signing pipeline from P10-T1.
- Excluded:
  - Dynamic feature modules / Play Feature Delivery beyond basic ABI splitting — no dynamic feature delivery is currently planned or needed for this project's scope.

**Acceptance Criteria:**
- [ ] AAB build correctly configured and verified to build successfully with all required ABIs included, confirmed via bundle inspection (e.g., `bundletool`).
- [ ] Direct-distribution APK build path configured and decision (universal vs. split) documented with rationale.
- [ ] Both artifact types successfully produced through the signed CI pipeline from a test tag.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Verify actual current Play Store AAB/ABI policy specifics before implementing — Play Store's exact requirements and defaults around bundle configuration have evolved over time; confirm rather than assume based on general familiarity.

---

### P10-T4 — Play Store VPN Policy Compliance Pass

**Status:** Not Started
**Depends On:** P10-T3, P8-T6

**Objective:**
Ensure Brick VPN's Play Store listing and app behavior fully comply with Google Play's VPN-service-specific policy requirements, resolving the previously-flagged-but-unticketed concerns around the separate VpnService declaration form, mandatory encryption of all device-to-endpoint traffic, and the prohibition on manipulating ads.

**Scope:**
- Included:
  - Verify current Google Play policy requirements specific to apps using `VpnService` (this has historically included: a separate policy declaration form distinct from the general Data Safety section, a requirement that all traffic between the device and the remote VPN endpoint be encrypted, and an explicit prohibition on VPN apps manipulating or injecting ads into user traffic) — confirm current exact requirements rather than relying on the possibly-outdated summary already noted in prior project context.
  - Complete/prepare the actual Play Console VPN declaration form content (even if actual submission happens in P10-T7, the content/answers should be drafted and reviewed here).
  - Confirm and document that Brick VPN's actual behavior genuinely satisfies each requirement (e.g., confirm no ad-related code exists anywhere in the app — consistent with the project's no-telemetry, no-ads posture already established from the very beginning of the project).
  - Prepare the general Play Store Data Safety section content, reflecting what data (if any) the app actually collects — which, per the project's no-telemetry policy, should be minimal to none, making this section straightforward but still requiring accurate, honest completion.
- Excluded:
  - The actual Play Console submission/publishing action itself — that belongs to P10-T7; this task is about compliance research, content preparation, and behavioral verification.

**Acceptance Criteria:**
- [ ] Current Play Store VPN-specific policy requirements are verified and documented (with source references where possible).
- [ ] Draft VPN declaration form content and Data Safety section content are prepared and committed (e.g., under `docs/release/`) for the human's review before actual submission.
- [ ] App behavior is confirmed, by code review, to have no ad-related functionality of any kind.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Play policy specifics and enforcement patterns shift over time and carry real consequences (listing rejection or removal) if misjudged — verify current requirements carefully and flag any ambiguity to the human rather than guessing at compliant answers for a legal/policy-adjacent form.

---

### P10-T5 — Minimal Release Store Listing Assets

**Status:** Not Started
**Depends On:** P10-T4

**Objective:**
Produce the minimum viable set of Play Store listing assets (app icon, feature graphic, screenshots, short/full description) needed for submission, explicitly consistent with the project's deliberate deferral of full UI/UX polish to Phase 11 — these assets should be honest, functional, and unpolished-but-presentable, not a preview of Phase 11's eventual design work.

**Scope:**
- Included:
  - A basic, clean app icon (does not need custom branding/illustration work per the Phase 11 deferral — a simple, legible, reasonably professional icon is sufficient; if the human wants to supply a real design asset at this point instead of an agent-generated placeholder, that should be accommodated).
  - Screenshots of the app's actual current minimal UI (honest representation, not aspirational mockups) sufficient to satisfy Play Console's minimum screenshot count/dimension requirements (verify current requirements).
  - Short and full store-listing description text, written honestly about the app's current actual feature set and its open-source/GPLv3 nature.
  - A minimal privacy policy document (Play Store requires a privacy policy URL for apps handling network permissions/VPN) — given the no-telemetry policy, this should be a short, honest document stating what data is and (mostly) is not collected, hosted wherever the project's other documentation lives (e.g., GitHub Pages or within the repository linked appropriately).
- Excluded:
  - Any deep visual design work, custom illustration, or marketing-grade asset production — explicitly deferred to Phase 11's dedicated UI/UX pass; assets produced here may be entirely superseded later.

**Acceptance Criteria:**
- [ ] All required Play Console asset slots (icon, feature graphic, screenshots, descriptions) are filled with real, honest, minimally-acceptable content meeting Play Console's current technical requirements (dimensions, formats).
- [ ] Privacy policy document is written, published/hosted, and its URL is valid and accessible.
- [ ] All listing text accurately describes actual current app functionality (no aspirational or Phase-11-anticipating claims).
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Resist any temptation to over-invest in polish here — per the project's explicit Phase 11 deferral, "good enough and honest" is the correct bar for this task, not "impressive." Flag to the human, rather than deciding unilaterally, if you believe a particular asset genuinely needs human/designer input beyond what you can reasonably produce (e.g., the app icon, if the human has design preferences).

---

### P10-T6 — GitHub Release Publication (Direct-Distribution Channel)

**Status:** Not Started
**Depends On:** P10-T3, P8-T4

**Objective:**
Publish the first real, tagged GitHub Release of Brick VPN, providing the direct-APK-download distribution channel independent of Play Store, complete with release notes, signed artifacts, and checksums, fully exercising the CI/signing/checksum pipeline built in P0-T8, P10-T1, and P8-T4 end to end for the first time with real release intent (not just a test tag).

**Scope:**
- Included:
  - Tag and trigger a real release build through the CI pipeline, producing the signed direct-distribution APK (per P10-T3's decision) and its checksum/fingerprint documentation (per P8-T4/P10-T1).
  - Write genuine, accurate release notes describing the current feature set, known limitations (explicitly including anything carried forward from earlier phase closeouts that remains a documented open item), and installation instructions (including guidance on enabling "install from unknown sources," since this is a direct APK not from Play Store).
  - Verify the published release artifact by downloading it fresh (not reusing a local build) and performing an install-and-smoke-test on a real or accurately configured device.
  - Update the repository's `README.md` (or equivalent) to point to this release as the current recommended direct-download option.
- Excluded:
  - Play Store publication — that is P10-T7, a separate, distinct distribution channel with its own process and timeline.

**Acceptance Criteria:**
- [ ] A real, tagged GitHub Release is published with correctly signed artifact(s) and checksum documentation.
- [ ] Release notes are accurate, honest, and include known limitations.
- [ ] Fresh download-and-install smoke test performed and confirmed working, described in the report.
- [ ] `README.md` updated to reference the release.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This is the first time the project's release pipeline is exercised for real, not as a test — treat any friction or unexpected behavior encountered here as valuable signal about the pipeline's actual readiness, and document it honestly even if it required manual workarounds, so the human knows whether the automated pipeline is genuinely trustworthy or still needs attention.

---

### P10-T7 — Play Store Submission (Closed/Internal Testing Track)

**Status:** Not Started
**Depends On:** P10-T4, P10-T5, P10-T6

**Objective:**
Submit Brick VPN to Google Play Console via a closed or internal testing track (not immediately public production release), completing the actual submission action prepared for in P10-T4/T5, and establish the review-and-iterate loop with Play Console's review process before any consideration of full public release.

**Scope:**
- Included:
  - Actual Play Console app creation and submission using the AAB (P10-T3), compliance content (P10-T4), and listing assets (P10-T5) prepared in prior tasks.
  - Decision on Play App Signing enrollment (Google-managed signing) vs. self-managed signing, made with the human's explicit input given the long-term operational implications noted in P10-T1.
  - Submission to a closed or internal testing track first (not open/production) — this is a deliberate, conservative choice appropriate for a first-ever submission of a censorship-circumvention-relevant VPN app, allowing time to respond to any Play review questions or rejections without public-facing consequences.
  - Documentation of the actual review outcome (approved / rejected with reasons / questions from Google) and, if issues arise, a clear plan for addressing them — this task's completion may reasonably be "submitted and awaiting review" rather than "approved," since Play review timelines are outside this project's control; that is an acceptable outcome to report honestly.
  - A brief, honest note in the report/documentation regarding Google's MASA (Mobile App Security Assessment) "Verified" badge program — explicitly confirming this remains a long-term/out-of-scope goal for now (per its 10k-install/250-review/90-day threshold), not something to pursue at initial submission.
- Excluded:
  - Promoting to a public/production Play Store listing — that is a distinct, separate future decision the human should make deliberately once testing-track results and review outcomes are known, not something this task should do automatically.

**Acceptance Criteria:**
- [ ] Play Console listing created and submitted to a closed/internal testing track with all required content from P10-T4/T5.
- [ ] Signing arrangement (Play App Signing vs. self-managed) decision made explicitly with human input and documented.
- [ ] Actual submission outcome (or current pending status) is documented honestly in the report.
- [ ] MASA badge program is explicitly noted as out-of-scope for now, with its threshold requirements documented for future reference.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task's success should not be defined as "achieved full public Play Store approval" — Play review can take time and may involve back-and-forth outside this project's control. A well-executed, honestly-documented submission to a testing track, with a clear plan for handling review feedback, is a complete and successful outcome for this task. Do not attempt to rush or artificially force a production release to claim a cleaner-sounding completion.

---

### P10-T8 — Phase 10 Closeout: Android MVP Milestone

**Status:** Not Started
**Depends On:** P10-T1 through P10-T7

**Objective:**
Perform the final closeout pass for Phase 10 and, with it, for the entire Android MVP effort spanning Phases 0–10 — confirming the project has genuinely reached the milestone explicitly stated in the roadmap's Key Results: a stable, usable Android MVP exists, distributed via both GitHub Releases and (at least) a Play Store testing track.

**Scope:**
- Included:
  - A final, holistic fresh-clone-to-release verification: build from scratch, confirm the signed release pipeline works, confirm the GitHub Release is live and installable, confirm the Play Console submission status, and re-run a representative subset of the Phase 9 manual QA protocol against the actual released artifact (not just a local dev build) as a final sanity check that nothing was altered by the release-packaging process itself (minification, signing, etc.).
  - A comprehensive `DEFINITION_OF_DONE.md`-template report covering all of Phase 10's tasks collectively.
  - A significant rewrite of `PROJECT_STATE.md` marking this as a true milestone: the Android MVP is complete and released; summarizing, at a high level, everything built across Phases 0–10; explicitly listing all known limitations and deferred items carried forward (log-redaction residual limitations, OEM battery-optimization quirks, reproducible-build gaps, MASA badge deferral, Play Store review status); and clearly stating that the next phase, Phase 11 (Full UI/UX Design & Implementation), begins a new arc focused on polish and expansion (desktop, iOS, premium) rather than core functionality.
  - A brief retrospective note (can be part of the same `PROJECT_STATE.md` update or a separate short document) reflecting on how this rebuild compares to the legacy prototype's collapse — since this milestone represents the point where the legacy prototype's original ambitions have now actually been achieved, correctly, with full documentation and testing.
- Excluded:
  - Any new feature work.

**Acceptance Criteria:**
- [ ] Final holistic verification (fresh clone through to released, installed artifact) performed and described in full.
- [ ] Representative manual QA protocol subset re-run specifically against the actual release artifact (not a dev build) and confirmed passing.
- [ ] DoD report produced using the exact template from `DEFINITION_OF_DONE.md`.
- [ ] `PROJECT_STATE.md` rewritten to mark the Android MVP milestone explicitly, with a full summary of known limitations carried forward.
- [ ] Retrospective note comparing this achieved milestone to the legacy prototype's history is written.
- [ ] Explicit statement confirming Phase 11 (UI/UX) is next, and that all prior phases' functional/resilience/security work is considered a stable foundation not expected to need revisiting for that phase's purposes.

**Notes for Agent:**
This is the most significant closeout in the roadmap so far — it marks the actual achievement of what the legacy prototype set out to do and failed at. Take real care and pride in this report; it should read as a genuine, credible account of a working, tested, released product, not a rote checklist completion. As with every phase closeout, do not mark this `Completed` yourself — propose `Ready for Human Review` and wait; this particular sign-off is one the human will likely want to review especially carefully.

---

## Phase 11 — Full UI/UX Design & Implementation

**Phase Goal:** This phase marks a deliberate shift in the project's arc: with the Android MVP (Phases 0–10) functionally complete, stable, tested, and released, Phase 11 replaces every deliberately-minimal placeholder screen and interaction built throughout Phases 3–10 with a genuinely designed, polished, cohesive user experience — a real visual identity, real interaction design, accessibility consideration, and localization-ready UI — without touching or regressing any of the underlying functional/resilience/security work already achieved.

**Granularity Note (reaffirmed):** Written at the same coarser-but-fully-templated grain as Phases 5–10, expandable later. This phase is unusual in that it is primarily a *design* effort as much as an engineering one — several tasks below explicitly call for design-decision documentation (mood boards, style guides, component libraries) alongside code, and several explicitly invite deeper human involvement/preference than earlier, more mechanically-specified phases.

---

### P11-T1 — Design System Foundation: Visual Identity and Style Guide

**Status:** Not Started
**Depends On:** P10-T8

**Objective:**
Establish Brick VPN's actual visual identity — color palette, typography, spacing/sizing scale, iconography style, light/dark theme definitions — and document it as a concrete, reusable style guide, replacing the "no custom color palette/branding" placeholder state explicitly carried since Phase 4.

**Scope:**
- Included:
  - Propose a color palette (including a proper light theme and dark theme, both genuinely designed, not just an inverted default) appropriate for a privacy/security-focused tool — research current conventions in this specific app category (VPN/privacy tools) for tone/color psychology cues (e.g., trust, calm, security) without slavishly copying any single competitor's branding.
  - Define a typography scale (font family selection — verify licensing is compatible with GPL v3 distribution — and a consistent heading/body/label size hierarchy).
  - Define a spacing/sizing scale (e.g., a consistent 4px/8px-based system) to be used across all screens going forward, replacing ad-hoc spacing values used during minimal-UI phases.
  - Define an iconography approach (a consistent icon set/library — verify current licensing compatibility, or commit to a custom icon approach if preferred).
  - Implement this as an actual Flutter `ThemeData` (or equivalent theming mechanism appropriate to whatever widget/design approach — Material 3 vs. a more custom design language — is chosen; this choice itself should be made deliberately and documented, not defaulted to without consideration).
  - Present the proposed visual identity to the human for feedback/approval before implementing it across all screens (this is one of the few points in the roadmap where the agent should expect and plan for a design-review round-trip with the human, given how subjective and consequential this decision is).
  - Document the finalized design system in a durable reference (e.g., `docs/design/style-guide.md` and/or a Storybook-equivalent widget catalog screen within the app itself, if the agent judges that valuable).
- Excluded:
  - Applying the new design system to every individual screen — that is the responsibility of subsequent tasks (P11-T2 onward); this task establishes the foundation only.
  - Custom app icon/launcher icon design — handled in P11-T2 alongside the broader screen-by-screen pass, since it's more of an asset-production task than a system-definition task.

**Acceptance Criteria:**
- [ ] Color palette (light + dark), typography scale, spacing scale, and iconography approach are all proposed, documented, and presented to the human for explicit approval before proceeding further.
- [ ] Font licensing is verified compatible with GPL v3 / open-source distribution.
- [ ] Icon set licensing (if a third-party set is chosen) is verified compatible.
- [ ] A working `ThemeData` (or equivalent) implementation exists and is demonstrably switchable between light/dark modes.
- [ ] Design system is documented durably in the repository.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template, and explicitly notes that human design approval was sought and obtained before this task is considered ready for review.

**Notes for Agent:**
This task is explicitly more subjective than almost anything earlier in the roadmap — do not unilaterally lock in major visual identity decisions (primary brand color, overall aesthetic direction) without presenting options and getting real human sign-off first, since this is exactly the kind of decision where the human's personal taste and product vision legitimately overrides an agent's default aesthetic judgment. Present a small number of well-reasoned options rather than either a single unexplained choice or an overwhelming number of alternatives.

---

### P11-T2 — Screen-by-Screen Redesign Pass: Core Navigation and Server Management

**Status:** Not Started
**Depends On:** P11-T1

**Objective:**
Apply the design system from P11-T1 to replace all deliberately-minimal placeholder UI built in Phases 4–5 for the app's core navigation shell and server-management screens (server list, add-server flows, server detail/edit), including the app's launcher icon and splash screen, explicitly closing the placeholder gaps noted since P4-T6/P4-T7.

**Scope:**
- Included:
  - Redesign of the app's core navigation shell (whatever structure — bottom nav, drawer, etc. — was established in P4-T5, now revisited with real design intent rather than "visually minimal" placeholder framing).
  - Redesign of the server list screen (P5-T5), including empty state, subscription-vs-standalone visual distinction, and active-server indication (P5-T7).
  - Redesign of all add-server flows: manual paste (P5-T2), QR scan (P5-T3), subscription import (P5-T4) — including genuine visual/interaction polish of camera-permission states and error messaging, not just restyled versions of the original minimal implementations.
  - Redesign of server edit/delete/duplicate/refresh interactions (P5-T6).
  - Real app launcher icon and splash screen design, replacing the "no splash-screen visual design" placeholder explicitly noted in P4-T7.
  - Basic responsive/adaptive layout consideration for different Android screen sizes (phones of varying sizes at minimum; tablet support is not required but should not be actively broken).
- Excluded:
  - Connect/disconnect screen and traffic-stats/logs UI — handled separately in P11-T3, since that screen carries the most state-driven complexity and deserves focused attention.
  - Settings/preferences screens — handled in P11-T4.

**Acceptance Criteria:**
- [ ] All listed screens/flows are visually and interactively redesigned per the P11-T1 design system, verified by manual walkthrough and screenshots included in the report.
- [ ] No functional regression versus the pre-redesign behavior — every acceptance criterion from the original Phase 5 tasks for these flows still holds true after the redesign (re-verified explicitly, not assumed).
- [ ] Real launcher icon and splash screen are implemented and visible on a real/emulated device.
- [ ] Basic responsiveness verified across at least two different screen sizes/densities.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This is a redesign, not a rewrite — the underlying state management, repository wiring, and validation logic from Phase 5 must remain functionally intact. Treat every original Phase 5 acceptance criterion as a regression-test checklist you must re-confirm after your visual/structural changes, since UI restructuring is a common source of accidentally broken event wiring or lost edge-case handling.

---

### P11-T3 — Screen-by-Screen Redesign Pass: Connection, Stats, and Logs

**Status:** Not Started
**Depends On:** P11-T2

**Objective:**
Apply the design system to the app's most state-driven and highest-visibility screens: the main connect/disconnect screen, the traffic-stats display, the session info panel, and the live log viewer — turning the functionally-correct-but-deliberately-plain implementations from Phases 5–7 into the app's actual primary user-facing experience.

**Scope:**
- Included:
  - Redesign of the primary connect/disconnect screen/button, including clear, well-designed visual states for every value in the connection state machine (disconnected, connecting, connected, reconnecting, disconnecting, error) — this is likely the single most important screen in the entire app and deserves particular design care.
  - Redesign of the traffic-stats display (P6-T2) and session info panel (P6-T6), potentially including simple data visualization (e.g., a basic live speed graph) if the agent judges it valuable and feasible — explicitly optional, not required, given this was explicitly deferred as a "maybe" in P6-T2's original scope.
  - Redesign of the live log viewer (P6-T4) and its export/copy interaction (P6-T5), preserving all existing safety affordances (the sensitive-content warning, auto-scroll behavior) while improving visual presentation.
  - Redesign of kill-switch and auto-reconnect-related UI surfaces introduced in Phase 7 (P7-T1/T2), ensuring their states remain exactly as clear and unambiguous as their original minimal implementations required, now with better visual execution.
- Excluded:
  - Any change to the underlying state machine, stream architecture, or redaction logic — this task is strictly visual/interaction-layer.

**Acceptance Criteria:**
- [ ] Every connection state has a distinct, clear, well-designed visual representation, verified by manually walking through all states (including inducing an error state and a reconnecting state) and confirming each is visually unambiguous.
- [ ] No functional regression versus pre-redesign behavior for stats accuracy, log correctness/redaction, kill-switch behavior, or auto-reconnect behavior — explicitly re-verified against the relevant original Phase 6/7 acceptance criteria.
- [ ] If a live graph/visualization was added, it is verified to not introduce meaningful performance overhead (reusing the fine-grained-rebuild verification approach from P6-T2).
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This screen is the emotional core of the app's user experience — a user watches this screen more than any other. Prioritize clarity and trustworthiness of the connection-state display above visual cleverness; an ambiguous or overly-animated state transition that makes a user unsure whether they're actually protected would be a serious regression in a privacy-focused tool, regardless of how polished it looks.

---

### P11-T4 — Settings, Preferences, and Onboarding Screens

**Status:** Not Started
**Depends On:** P11-T1

**Objective:**
Design and implement a proper settings/preferences screen consolidating all the scattered toggles and preferences introduced piecemeal throughout Phases 7–8 (kill switch toggle, auto-reconnect behavior if configurable, battery-optimization prompt access, log-verbosity toggle if implemented, theme selection from P11-T1), plus a first-run onboarding flow introducing new users to the app.

**Scope:**
- Included:
  - A dedicated settings screen consolidating: kill-switch enable/disable (P7-T2), any auto-reconnect configuration exposed (P7-T1), battery-optimization exclusion request re-access (P7-T4), verbose/debug log mode toggle if implemented (P8-T2), theme selection (light/dark/system, per P11-T1), app version/about info, and links to the privacy policy (P10-T5) and open-source license/attribution (GPL v3 requires appropriate notices — verify correct attribution practice).
  - A first-run onboarding flow (shown only on first launch) briefly introducing the app's purpose and guiding the user through initial VPN permission grant (P3-T12's `prepare()` flow) and, optionally, adding their first server — designed to reduce first-use confusion, especially given this app's likely audience includes less technically sophisticated users in censorship-affected regions.
  - Language/localization selection UI if multiple languages are supported at this point (cross-check against whatever `easy_localization` setup exists from earlier phases — verify current actual language coverage rather than assuming).
- Excluded:
  - Building out actual translations for new languages beyond whatever already exists — that is a content/localization task, not a UI-design task, and should be scoped separately if the human wants to expand language support.
  - Advanced account/profile features — not applicable, this project has no user-account system at this stage.

**Acceptance Criteria:**
- [ ] Settings screen consolidates all listed preferences correctly, with each toggle/action verified to actually affect the corresponding underlying behavior (not just visually present).
- [ ] Onboarding flow is verified to appear only on first launch, correctly guides through VPN permission grant, and does not reappear on subsequent launches.
- [ ] GPL v3 attribution/license notices are correctly included and verified accurate.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Given this project's stated real-world context (censorship-affected regions, potentially less technically sophisticated users), design the onboarding flow with genuine empathy for a first-time user who may be anxious or unfamiliar with VPN concepts — clear, reassuring, jargon-light language is more valuable here than clever design flourishes.

---

### P11-T5 — Accessibility Pass

**Status:** Not Started
**Depends On:** P11-T2, P11-T3, P11-T4

**Objective:**
Perform a dedicated accessibility review and remediation pass across the entire redesigned app, ensuring basic compliance with mobile accessibility standards (screen reader support, sufficient color contrast, adequate touch target sizes, text scaling support).

**Scope:**
- Included:
  - Verify current Android/Flutter accessibility guidelines and testing tools (e.g., Flutter's accessibility inspector/`flutter_test`'s semantics testing utilities, Android's Accessibility Scanner) — confirm current recommended tooling rather than assuming.
  - Screen-reader (TalkBack) walkthrough of all major screens/flows, ensuring all interactive elements have meaningful semantic labels and logical focus/reading order.
  - Color contrast verification for both light and dark themes against WCAG AA (or currently-recommended equivalent) contrast ratios, for all text/interactive-element color combinations defined in P11-T1's style guide.
  - Touch target size verification (minimum recommended tap target dimensions) across all interactive elements.
  - Text-scaling support verification (testing the app's layouts at larger system font-size settings to confirm no critical UI breaks/overlaps/truncates unreadably).
- Excluded:
  - Full WCAG AAA compliance or specialized accessibility features beyond standard mobile app expectations (e.g., no requirement for a fully custom high-contrast mode beyond the standard light/dark themes, unless the human specifically wants this as a future enhancement).

**Acceptance Criteria:**
- [ ] TalkBack walkthrough completed for all major screens, with any found issues (missing labels, illogical focus order) fixed.
- [ ] Color contrast verified and passing for all text/UI-element combinations in both themes, with any failing combinations adjusted in the style guide and propagated back through the app.
- [ ] Touch target sizes verified adequate across the app.
- [ ] Text-scaling tested at at least one significantly larger-than-default system font size, with any critical breakage fixed.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Accessibility is not optional polish — for a tool whose purpose is providing access to information/communication in restrictive environments, ensuring it is genuinely usable by people with visual or motor impairments is directly aligned with the project's underlying values. Treat found issues as real bugs, not nice-to-haves.

---

### P11-T6 — Micro-interactions, Animation, and Perceived-Performance Polish

**Status:** Not Started
**Depends On:** P11-T3

**Objective:**
Add tasteful, purposeful animation and micro-interaction polish (state transitions, loading states, button feedback) to elevate the app's perceived quality and responsiveness, without introducing the kind of ambiguous-state-during-animation risk explicitly warned against in P11-T3.

**Scope:**
- Included:
  - Smooth, purposeful transitions for connection-state changes (e.g., a well-designed transition for connecting→connected) that enhance rather than obscure clarity of current state.
  - Loading/skeleton states for any screen with async data loading (server list while repository loads, subscription refresh in progress) replacing any raw spinner-only or blank-screen placeholder states from earlier phases.
  - Button/interactive-element press feedback consistent with the design system's overall feel.
  - Page-transition animations for navigation between screens, if the chosen navigation framework (`go_router`, per earlier decisions) supports this cleanly — verify current `go_router` capability/idioms for custom transitions rather than assuming.
- Excluded:
  - Any animation that delays or obscures critical state information (e.g., a lengthy animation that delays showing an error state) — per P11-T3's explicit priority, clarity and trustworthiness always take precedence over animation polish; any conflict between the two must be resolved in favor of clarity.

**Acceptance Criteria:**
- [ ] All listed animation/polish areas are implemented and manually verified to feel smooth (no jank, verified via Flutter's performance overlay/profiling tools) on a real or accurately representative device.
- [ ] No animation is found to delay or obscure critical state information beyond a brief, reasonable duration (agent should define and justify what "reasonable" means, e.g., under 300ms for critical-state-related transitions).
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
When in doubt, favor restraint — a slightly-less-impressive but perfectly clear and fast interface is strictly better for this project's purposes than a beautiful but slightly-ambiguous or slightly-laggy one. If you're not sure whether a given animation helps or hurts clarity, err toward cutting it or making it faster.

---

### P11-T7 — Phase 11 Closeout and Definition-of-Done Pass

**Status:** Not Started
**Depends On:** P11-T1 through P11-T6

**Objective:**
Perform a full closeout pass on Phase 11: confirm the entire app has been coherently redesigned with no functional regressions anywhere, re-run the full Phase 9 manual QA protocol against the redesigned app, produce the standard DoD report, and update `PROJECT_STATE.md` to reflect the new, fully-polished baseline before Phase 12 (Desktop Support) begins.

**Scope:**
- Included:
  - Fresh-clone build and a full re-run of the entire Phase 9 manual QA protocol (P9-T3) against the now fully-redesigned app, confirming zero functional regressions introduced by the UI/UX overhaul.
  - A final holistic visual/UX walkthrough confirming design-system consistency (P11-T1) is genuinely applied across every screen, with no leftover "minimal placeholder" styling accidentally missed anywhere in the app.
  - Full `DEFINITION_OF_DONE.md`-template report covering all of Phase 11's tasks collectively.
  - Rewriting `PROJECT_STATE.md` to reflect: Phase 11 complete, the app now has a complete, polished, accessible UI/UX; explicitly confirming all prior functional/resilience/security guarantees from Phases 0–10 remain intact; and stating that the next phase, Phase 12 (Desktop Support), begins a new platform-expansion arc building on the daemon+IPC architecture defined in `ARCHITECTURE.md` Section 3.6.
- Excluded:
  - Any new design or feature work beyond fixing regressions/inconsistencies found during this closeout pass.

**Acceptance Criteria:**
- [ ] Full Phase 9 manual QA protocol re-run against the redesigned app with zero functional regressions found (or all found regressions fixed before proposing this task as ready for review).
- [ ] Design-system consistency confirmed across every screen via holistic walkthrough, with screenshots/evidence included in the report.
- [ ] DoD report produced using the exact template from `DEFINITION_OF_DONE.md`.
- [ ] `PROJECT_STATE.md` rewritten, accurate as of end of Phase 11, explicitly confirming the Android app is now both functionally complete and visually polished, and setting up Phase 12's desktop-expansion context.
- [ ] Explicit statement of what Phase 12 will need from Phase 11 (i.e., a stable, polished Android reference implementation whose UI/UX patterns — though not its Android-specific platform-channel plumbing — should inform desktop's own GUI design for consistency).

**Notes for Agent:**
As with every phase closeout, do not mark this `Completed` yourself — propose `Ready for Human Review` and wait. This closeout is a natural point for the human to spend real time actually using the app as a genuine end user would, since it's the first point in the roadmap where the app is meant to feel finished rather than merely functional — encourage this in your report by making the fresh-install experience as easy as possible to trigger for review purposes.

---

## Phase 12 — Desktop Support

**Phase Goal:** Extend Brick VPN to Windows, macOS, and Linux (in that priority order, per the project's stated priorities), built on the daemon+IPC architecture already decided and documented in `ARCHITECTURE.md` Section 3.6 — a privileged local daemon (`brick_vpn_daemon`, Go binary embedding sing-box directly) communicating with an unprivileged Flutter desktop GUI over authenticated local IPC, explicitly rejecting in-process `dart:ffi` as the primary architecture. Section 3.6 was explicitly marked as a planning placeholder to be re-verified against the ecosystem's actual state once this phase is reached — this phase's first task does exactly that.

**Granularity Note (reaffirmed):** Written at the same coarser-but-fully-templated grain as Phases 5–11. Given this phase's genuinely large scope (three separate operating systems, each with distinct privilege/service models), tasks are organized by sub-arc (shared daemon core → Windows → macOS → Linux → cross-platform integration/closeout) rather than at Phase 0–3's maximum granularity; expect this phase to be revisited and expanded task-by-task as each OS sub-arc is actually reached, exactly as the living-document caveat allows.

---

### P12-T1 — Re-Verification of Section 3.6 Architecture Against Current Ecosystem State

**Status:** Not Started
**Depends On:** P11-T7

**Objective:**
Before writing any desktop code, formally re-verify every assumption embedded in `ARCHITECTURE.md` Section 3.6 against the actual current state of the relevant ecosystems (sing-box/libbox desktop capabilities, Go cross-compilation tooling, Wintun/utun/TUN driver landscape, and current production-VPN-client precedent), since this section was explicitly written as a planning placeholder pending re-verification.

**Scope:**
- Included:
  - Re-verify that sing-box's core library can be embedded directly into a standalone Go binary (no gomobile/cgo/JNI layer needed) for desktop targets, and confirm current recommended approach for doing so (module import, build tags, etc.).
  - Re-verify sing-box's current Clash API surface (REST/WS endpoints) for control-plane, stats, and log streaming, confirming it still covers this project's needs (start/stop/status/traffic-stats/logs) or identifying gaps requiring a custom IPC protocol layer on top.
  - Re-verify current Wintun (Windows), utun (macOS), and `/dev/net/tun` (Linux) driver/API status and licensing for each target OS.
  - Re-check current production precedent (WireGuard, Tailscale, Mullvad, Hiddify) for anything that has materially changed since the original architecture decision, and confirm the daemon+IPC pattern remains the correct choice (expected outcome: confirmation, not reversal, but this must be genuinely checked, not rubber-stamped).
  - Produce a short addendum to `ARCHITECTURE.md` Section 3.6 documenting what was re-verified, what (if anything) changed from the original placeholder text, and updating its status from "planning placeholder" to "verified as of Phase 12 start."
- Excluded:
  - Any actual implementation — this task is research/verification and documentation only.

**Acceptance Criteria:**
- [ ] Every specific technical claim embedded in Section 3.6 is individually re-checked against current sources, with findings documented.
- [ ] Any discrepancy between the original placeholder assumptions and current reality is clearly flagged, and if it materially affects the architecture, escalated to the human before proceeding rather than silently patched.
- [ ] `ARCHITECTURE.md` Section 3.6 is updated to reflect verified status, with a clear changelog note of what was confirmed vs. revised.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task exists precisely because the original architecture decision was made without live internet access and was explicitly flagged for exactly this kind of re-verification. Do not treat this as a formality — if the ecosystem has shifted (e.g., a newer sing-box release changes the Clash API, or a better-supported alternative to Wintun has emerged), surface it clearly rather than building three OS's worth of desktop work on a stale assumption.

---

### P12-T2 — `brick_vpn_daemon` Core Skeleton and Build Pipeline

**Status:** Not Started
**Depends On:** P12-T1

**Objective:**
Create the `brick_vpn_daemon` Go binary skeleton — a standalone, cross-compilable daemon embedding sing-box, exposing its control plane over local IPC — along with its own dedicated build/CI pipeline, independent of the Android AAR build pipeline from Phase 3.

**Scope:**
- Included:
  - New Go module/package (e.g., `apps/brick_vpn_daemon` or wherever the monorepo structure from P0/P1 dictates) with sing-box embedded per P12-T1's verified integration approach.
  - Minimal viable daemon lifecycle: start, accept one IPC connection, respond to a trivial "ping"/"version" command, stop cleanly — this task proves the skeleton works before any real VPN logic is wired in.
  - Cross-compilation build pipeline (Go's native cross-compilation, `GOOS`/`GOARCH` targeting Windows/macOS/Linux) added to the project's CI (extending P0-T8's pipeline, not replacing it), pinning the exact same verified Go toolchain version already established for the Android build (per P0-T8/P3-T1's toolchain-pinning philosophy) to avoid the QUIC/Hysteria2/TUIC toolchain-drift risk already documented for Android.
  - Basic daemon logging (to stdout/file, platform-appropriate location) sufficient for early development debugging — full structured logging parity with the Android side's log-streaming system is a later task (P12-T11).
- Excluded:
  - Actual TUN/VPN lifecycle logic — that is OS-specific and handled in P12-T4 (Windows), P12-T7 (macOS), P12-T9 (Linux).
  - IPC protocol design details beyond the trivial ping/version proof — full protocol design is P12-T3.

**Acceptance Criteria:**
- [ ] `brick_vpn_daemon` builds successfully for Windows, macOS, and Linux targets via cross-compilation.
- [ ] A trivial IPC round-trip (ping/version command) works correctly on at least one development OS, with cross-OS verification tracked as a follow-up in subsequent per-OS tasks if not immediately testable on all three.
- [ ] CI pipeline produces build artifacts for all three OS targets from a single trigger.
- [ ] Go toolchain version is explicitly pinned and matches (or is deliberately, documented-ly different from, with justification) the version pinned for Android.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Keep this skeleton genuinely minimal — its only job is proving the daemon can be built, cross-compiled, and can accept one IPC round-trip. Resist adding real VPN logic prematurely; that belongs in the OS-specific tasks where it can be properly scoped and tested against that OS's actual privilege/service model.

---

### P12-T3 — IPC Protocol Design and Authentication

**Status:** Not Started
**Depends On:** P12-T2

**Objective:**
Design and implement the local IPC protocol connecting the unprivileged Flutter desktop GUI to the privileged `brick_vpn_daemon`, per Section 3.6's specification (Unix domain socket on Linux/macOS, named pipe on Windows, loopback-only, token-authenticated), preferring sing-box's built-in Clash API for control-plane/stats/logs wherever it sufficiently covers this project's needs, with a custom protocol layer only for what the Clash API doesn't cover (e.g., daemon lifecycle management itself, privilege-elevation coordination).

**Scope:**
- Included:
  - Concrete transport implementation for each OS (Unix domain socket for Linux/macOS, named pipe for Windows) with correct, current-verified permission/security settings (socket file permissions, named pipe security descriptors) so that only the intended local user/process can connect.
  - Token-based authentication scheme: daemon generates a random token at startup, writes it to a location only the legitimate local user can read (verify current best practice for this per OS), and the GUI must present this token on connection before any privileged command is accepted.
  - Protocol surface definition: which commands go through sing-box's native Clash API directly (if the GUI can talk to it directly once authenticated) versus which require a custom daemon-level command (e.g., "start VPN with this config," "stop," "get daemon status," "shutdown daemon") — document this split clearly, since it affects both the daemon and GUI implementation.
  - Error handling and reconnection logic for the IPC channel itself (distinct from VPN connection state) — e.g., what happens if the daemon crashes or restarts while the GUI is running; this connects to P12-T12's later crash-recovery hardening but this task must at least define the basic reconnect-attempt behavior.
- Excluded:
  - Remote/network-based access to the daemon of any kind — the IPC channel must be strictly loopback-only, never exposed on any network interface, under any circumstances.

**Acceptance Criteria:**
- [ ] IPC transport implemented and verified working with correct restrictive permissions on at least one development OS (with per-OS verification tracked in the corresponding OS-specific tasks).
- [ ] Token authentication verified to actually reject unauthenticated/incorrectly-authenticated connection attempts (tested with a deliberate wrong-token connection attempt).
- [ ] Protocol command surface (native Clash API vs. custom daemon commands) is documented clearly.
- [ ] Basic IPC-channel-level reconnection behavior (GUI detects daemon disconnect, attempts reconnect) is implemented and manually verified.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Security matters as much here as anywhere else in the project — an unauthenticated or network-exposed local IPC channel controlling a privileged VPN daemon would be a serious local-privilege-escalation-adjacent vulnerability. Verify current OS-specific best practices for securing local sockets/pipes rather than assuming a naive implementation is sufficient, and treat any uncertainty about a given OS's exact security model as a reason to stop and research further rather than guess.

---

### P12-T4 — Windows: Daemon as Windows Service with Wintun

**Status:** Not Started
**Depends On:** P12-T3

**Objective:**
Implement the Windows-specific portion of `brick_vpn_daemon`: TUN interface management via Wintun, running as a Windows Service (for privilege and lifecycle management independent of any logged-in user session), with correct installation/elevation flow.

**Scope:**
- Included:
  - Wintun integration for TUN interface creation/management on Windows, per P12-T1's re-verified integration approach.
  - Windows Service registration/lifecycle (install, start, stop, uninstall) so the daemon runs with appropriate privilege and survives independent of the GUI process, consistent with Section 3.6's architecture.
  - UAC elevation flow for the initial service installation step (which requires administrator privileges), designed to be as unobtrusive as reasonably possible for the end user (e.g., a one-time elevation prompt during first-run setup, not a recurring one).
  - Full local VPN lifecycle correctness on Windows: connect, disconnect, and the same session-token/stop-watchdog discipline established for Android in Section 3.5, adapted appropriately for this daemon context (the exact mechanism differs from Android's JNI bridge, but the *principles* — no stuck stopping state, no silently swallowed errors — must carry over).
- Excluded:
  - GUI-side implementation (P12-T5) — this task is daemon/service-layer only.
  - Installer/packaging polish (P12-T6).

**Acceptance Criteria:**
- [ ] Wintun-based TUN interface creation/teardown verified working on a real Windows machine or VM.
- [ ] Windows Service installs, starts, stops, and uninstalls correctly, with the elevation flow tested and confirmed to only prompt when actually necessary.
- [ ] A full connect → real traffic verification (reusing the same non-zero-increasing-byte-count verification standard established in Android's P3-T8/P5-T8) → disconnect cycle is manually verified and described concretely in the report.
- [ ] Stop reliability is explicitly tested (repeated connect/disconnect cycles, at least 5 in a row) with zero stuck states, directly mirroring the Android chaos-test discipline from P7-T5.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Apply the same skepticism and rigor to Windows service lifecycle correctness that Phase 3 applied to Android's VpnService lifecycle — Windows services have their own set of subtle failure modes (service control manager timeouts, improper shutdown handling) that deserve the same "don't guess, verify, and chaos-test repeated cycles" discipline that caught the legacy prototype's Android-side bugs.

---

### P12-T5 — Windows: Flutter Desktop GUI Integration

**Status:** Not Started
**Depends On:** P12-T4, P11-T7

**Objective:**
Build the Windows Flutter desktop GUI shell, wired to `brick_vpn_daemon` over the IPC protocol from P12-T3, reusing the design system and UX patterns established in Phase 11 for visual/interaction consistency with the Android app, while adapting layout appropriately for a desktop window paradigm.

**Scope:**
- Included:
  - Flutter desktop (Windows target) app skeleton, reusing `packages/core_domain` and other shared packages from the monorepo (per P0/P1's architecture) wherever platform-agnostic logic allows reuse, rather than duplicating logic already built for mobile.
  - An IPC-based `VpnEngine` implementation (fulfilling the same abstract interface from P1-T4, amended per P3-T12) that talks to `brick_vpn_daemon` instead of a native Android bridge — this is the concrete proof that the `VpnEngine` abstraction from Phase 1 was correctly designed for exactly this kind of multi-backend reuse.
  - Desktop-appropriate window/layout adaptation of Phase 11's screens (server list, connect screen, stats/logs, settings) — resizable window, appropriate desktop navigation paradigm (may differ from mobile's bottom-nav/drawer pattern; agent should choose and document a sensible desktop-appropriate navigation structure consistent with the Phase 11 design system's visual language).
  - System tray integration (minimize-to-tray, quick connect/disconnect from tray icon) as a desktop-appropriate convenience feature not applicable to mobile.
  - Handling of the first-run daemon-installation/elevation flow (from P12-T4) within the GUI's onboarding experience, extending the onboarding concept from P11-T4 appropriately for desktop's distinct privileged-component-installation need.
- Excluded:
  - macOS/Linux GUI work — separate tasks (P12-T8, P12-T10).

**Acceptance Criteria:**
- [ ] Windows Flutter GUI builds and runs, correctly communicating with `brick_vpn_daemon` over IPC for the full connect/disconnect/stats/logs feature set already proven on Android.
- [ ] Shared package reuse (`core_domain` etc.) is confirmed and documented — specifically noting what fraction of Android's business logic was reused unchanged versus what needed adaptation, as a concrete validation of the Phase 1 architecture's cross-platform design goal.
- [ ] System tray integration works correctly (minimize, restore, quick actions).
- [ ] First-run daemon installation/elevation flow is integrated into onboarding and tested on a clean Windows environment (no prior daemon installation).
- [ ] A full real-world manual test (add real server, connect, verify traffic, disconnect) is performed on the actual Windows GUI+daemon combination, mirroring the rigor of Android's P5-T8.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Pay close attention to how much of the existing Dart codebase you're able to reuse versus rewrite — significant unexpected rewriting needed here would be a signal that Phase 1's abstraction boundaries (`VpnEngine` interface, `core_domain` package structure) weren't as clean as intended, and worth flagging honestly to the human even though it's too late to redo that work retroactively.

---

### P12-T6 — Windows: Installer, Auto-Update, and Release Packaging

**Status:** Not Started
**Depends On:** P12-T5

**Objective:**
Produce a proper, distributable Windows installer for Brick VPN (bundling both the GUI and the daemon, with correct daemon-service installation as part of setup), plus a release/distribution pipeline analogous to Android's GitHub Release channel from Phase 10.

**Scope:**
- Included:
  - Verify current best-practice Windows installer tooling for Flutter desktop apps (e.g., MSIX, Inno Setup, WiX, or another currently-appropriate option) and select one with documented rationale.
  - Installer must correctly install both the GUI application and register/install the `brick_vpn_daemon` Windows Service, handling the UAC elevation requirement cleanly during setup rather than at first GUI launch (improving on P12-T4/T5's initial elevation-at-first-run approach, if setup-time elevation proves a better UX — agent's judgment, documented).
  - Code-signing consideration for the Windows installer/executable (unsigned Windows executables trigger SmartScreen warnings that would seriously undermine trust for a security tool) — investigate current code-signing certificate options/costs and present findings to the human, since this may involve a real financial cost decision outside the agent's authority to make unilaterally.
  - CI pipeline extension to produce and publish the Windows installer as part of the project's GitHub Release process (extending P10-T6's release pipeline to include this new artifact type).
  - Checksum publication for the Windows installer, consistent with the integrity-verification practice established in P8-T4/P10-T1.
- Excluded:
  - Windows Store (Microsoft Store) distribution — not currently planned; direct-download distribution via GitHub Releases is the initial target, consistent with the project's Android direct-APK precedent.

**Acceptance Criteria:**
- [ ] Installer tooling choice documented with rationale.
- [ ] Installer correctly installs GUI and daemon service on a clean Windows test environment, verified end-to-end.
- [ ] Code-signing options and costs are researched and presented to the human as a decision point, with a clear interim recommendation (e.g., ship unsigned initially with a documented SmartScreen-bypass instruction for users, versus delaying release for signing) — the agent should not unilaterally commit project funds or make this trade-off without human input.
- [ ] Installer artifact is produced through CI and published via GitHub Releases with checksum documentation.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Code-signing cost is a real financial decision — flag it clearly to the human rather than assuming either "pay for it" or "ship unsigned" unilaterally. If shipping unsigned initially, be explicit in release notes and documentation about the SmartScreen warning users should expect and how to safely proceed, since an unexplained scary OS warning could otherwise undermine trust in exactly the way this project cannot afford given its target audience.

---

### P12-T7 — macOS: Daemon as Privileged Helper with utun

**Status:** Not Started
**Depends On:** P12-T3

**Objective:**
Implement the macOS-specific portion of `brick_vpn_daemon`: TUN interface management via `utun`, running as a `launchd`-managed privileged helper process, per Section 3.6's macOS notes, with NetworkExtension/System Extension explicitly deferred unless App Store distribution is later pursued.

**Scope:**
- Included:
  - `utun` interface integration for TUN management on macOS, per P12-T1's re-verified approach.
  - `launchd`-managed privileged helper installation (a standard macOS pattern for privilege-separated helper tools, e.g., via `SMJobBless` or its currently-recommended successor API — verify current Apple-recommended approach, since this API surface has shifted over recent macOS versions and older patterns may be deprecated).
  - Correct handling of macOS's privilege-escalation UX for helper tool installation (a system authentication prompt, analogous to Windows' UAC flow), designed for a clean first-run experience.
  - Full local VPN lifecycle correctness on macOS mirroring the same rigor as P12-T4: session-token discipline, stop-watchdog equivalent, repeated connect/disconnect chaos-testing.
  - Explicit documentation of the NetworkExtension/System Extension deferral decision and what would need to change if/when Mac App Store distribution is ever pursued (NetworkExtension is generally required for App-Store-distributed macOS VPN apps; the `launchd` helper + utun approach is appropriate for direct/notarized distribution outside the App Store, consistent with this project's GitHub-Release-first distribution model).
- Excluded:
  - GUI-side implementation (P12-T8).
  - Notarization/packaging polish (P12-T8).

**Acceptance Criteria:**
- [ ] `utun`-based TUN interface creation/teardown verified working on a real Mac or accurately configured VM.
- [ ] `launchd`-managed privileged helper installs, runs, and is correctly invoked by the daemon/GUI, using the current Apple-recommended installation API (verified, not assumed from older documentation).
- [ ] A full connect → real traffic verification → disconnect cycle is manually verified and described concretely in the report.
- [ ] Repeated connect/disconnect chaos-testing (at least 5 cycles) shows zero stuck states.
- [ ] NetworkExtension deferral rationale and future-reconsideration conditions are clearly documented.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Apple's privileged-helper-tool APIs have a documented history of API deprecation and migration (older `SMJobBless`-based patterns have been superseded on recent macOS versions) — verify the actual current-recommended approach for whatever macOS version range this project decides to support, rather than implementing a pattern that may already be legacy by the time this task is executed.

---

### P12-T8 — macOS: GUI Integration, Notarization, and Release Packaging

**Status:** Not Started
**Depends On:** P12-T7, P11-T7

**Objective:**
Build the macOS Flutter desktop GUI (mirroring P12-T5's Windows approach and reusing the same shared packages), and produce a properly notarized, distributable macOS application bundle/installer.

**Scope:**
- Included:
  - Flutter desktop (macOS target) GUI skeleton and IPC-based `VpnEngine` implementation, reusing shared packages, mirroring P12-T5's structure and design-system consistency.
  - macOS-appropriate UX adaptations (menu bar integration, macOS-native window chrome/behavior conventions) analogous to Windows' system tray integration.
  - Apple code-signing and notarization pipeline (required for smooth distribution outside the Mac App Store — unnotarized apps trigger Gatekeeper warnings similar in spirit to Windows SmartScreen) — this requires an active Apple Developer Program membership, which, like Windows code-signing, involves a real cost decision that must be presented to the human rather than assumed.
  - CI pipeline extension to build, sign, notarize, and publish the macOS app via GitHub Releases, with checksum documentation.
- Excluded:
  - Mac App Store submission — not currently planned, consistent with the NetworkExtension deferral decision in P12-T7.

**Acceptance Criteria:**
- [ ] macOS GUI builds and runs, correctly communicating with the daemon for the full feature set already proven on Android/Windows.
- [ ] Apple Developer Program membership cost/decision is clearly presented to the human before proceeding with signing/notarization work that depends on it.
- [ ] Notarization pipeline (once the above is resolved) is verified to produce a Gatekeeper-clean app, tested on a clean macOS environment.
- [ ] A full real-world manual test (add real server, connect, verify traffic, disconnect) is performed on the actual macOS GUI+daemon combination.
- [ ] Release artifact published via GitHub Releases with checksum documentation.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
As with Windows code-signing, do not assume the human wants to incur the Apple Developer Program cost without asking — present the trade-off (notarized vs. unnotarized-with-clear-Gatekeeper-bypass-instructions) clearly and let the human decide, consistent with how P12-T6 handled the analogous Windows decision.

---

### P12-T9 — Linux: Daemon as systemd Service / Polkit-Authorized Helper with `/dev/net/tun`

**Status:** Not Started
**Depends On:** P12-T3

**Objective:**
Implement the Linux-specific portion of `brick_vpn_daemon`: TUN interface management via `/dev/net/tun` with `CAP_NET_ADMIN`, and a privilege-management approach appropriate to Linux's more heterogeneous ecosystem (a systemd service for distributions using systemd, with a polkit-authorized-helper fallback/alternative considered for broader compatibility), per Section 3.6's Linux notes.

**Scope:**
- Included:
  - `/dev/net/tun` + `CAP_NET_ADMIN` integration for TUN management on Linux, per P12-T1's re-verified approach.
  - systemd service unit definition for running the daemon with appropriate privilege on systemd-based distributions (the large majority of modern Linux desktop distributions).
  - Investigation of a polkit-authorized-helper alternative (or a capability-based approach avoiding a persistent root daemon entirely, e.g., using file capabilities on the daemon binary itself) for cases where a full systemd service feels heavier than necessary or for non-systemd distributions — the agent should research current common practice among comparable Linux VPN clients and make a documented, reasoned choice rather than assuming systemd-only support is sufficient without acknowledging the trade-off.
  - Full local VPN lifecycle correctness mirroring P12-T4/T7's rigor.
- Excluded:
  - Support for exotic/niche distributions beyond mainstream systemd-based and, if pursued, common non-systemd alternatives — a reasonable, documented scope boundary should be set (e.g., "tested on Ubuntu, Fedora, and Debian; other distributions likely work but are untested") rather than an unbounded compatibility promise.

**Acceptance Criteria:**
- [ ] TUN interface creation/teardown verified working on at least two different mainstream Linux distributions (e.g., Ubuntu and Fedora, to catch systemd-version/dependency differences).
- [ ] Chosen privilege-management approach (systemd service, polkit helper, or capability-based) is documented with rationale, including its trade-offs versus alternatives considered.
- [ ] A full connect → real traffic verification → disconnect cycle is manually verified and described concretely in the report on each tested distribution.
- [ ] Repeated connect/disconnect chaos-testing (at least 5 cycles) shows zero stuck states.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Linux desktop environments are meaningfully more heterogeneous than Windows or macOS — be explicit and honest about the actual tested scope (which distributions, which desktop environments if GUI-relevant) rather than implying universal Linux support. If you find the privilege-management landscape genuinely fragmented enough that a single approach can't reasonably cover "most" mainstream distributions, flag this to the human as a real scope/priority decision rather than picking one arbitrarily and hoping it generalizes.

---

### P12-T10 — Linux: GUI Integration and Release Packaging

**Status:** Not Started
**Depends On:** P12-T9, P11-T7

**Objective:**
Build the Linux Flutter desktop GUI (mirroring P12-T5/T8's approach), and produce distributable Linux packages appropriate to the privilege-management approach chosen in P12-T9.

**Scope:**
- Included:
  - Flutter desktop (Linux target) GUI skeleton and IPC-based `VpnEngine` implementation, reusing shared packages, mirroring the Windows/macOS structure and design-system consistency.
  - Linux-appropriate UX adaptations (system tray via whichever cross-desktop-environment approach is currently reasonable to support — verify current state of Linux system tray support fragmentation across desktop environments and document the actual supported scope).
  - Package format selection appropriate to the chosen privilege-management approach and target distributions (candidates: `.deb`, `.rpm`, AppImage, Flatpak — verify current relative merits and pick one or more with documented rationale, considering how each format interacts with the systemd-service/polkit-helper/capability approach from P12-T9).
  - CI pipeline extension to build and publish the chosen Linux package format(s) via GitHub Releases, with checksum documentation.
- Excluded:
  - Official distribution-repository submission (e.g., getting into Debian's official repos, or a Flathub submission) — that is a longer-term, separate community-process effort outside this task's scope; GitHub-Release-hosted packages are the initial target, consistent with other platforms.

**Acceptance Criteria:**
- [ ] Linux GUI builds and runs, correctly communicating with the daemon for the full feature set already proven on other platforms, on the same distributions tested in P12-T9.
- [ ] Package format choice documented with rationale, including how it correctly bundles/coordinates with the chosen daemon privilege-management approach.
- [ ] A full real-world manual test (add real server, connect, verify traffic, disconnect) is performed on each tested distribution's packaged build (not just a raw dev build).
- [ ] Release artifact(s) published via GitHub Releases with checksum documentation.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Test the actual packaged artifact, not just a locally-run dev build — packaging issues (missing dependencies, incorrect service-file installation paths, permission issues) are a common source of "works on my machine but not for users" bugs, and the whole point of this task is producing something a real Linux user can actually install and run correctly.

---

### P12-T11 — Cross-Platform Desktop Feature Parity and Consistency Pass

**Status:** Not Started
**Depends On:** P12-T5, P12-T8, P12-T10

**Objective:**
Verify and reconcile feature parity across all three desktop platforms and against the Android reference implementation, ensuring stats, logs, kill switch, auto-reconnect, and all other Phase 5–9 features work consistently and correctly on every desktop OS, not just on whichever OS happened to be developed/tested first.

**Scope:**
- Included:
  - Systematic feature-by-feature comparison across Windows, macOS, Linux, and Android: server management, connect/disconnect, traffic stats, live logs (including redaction from Phase 8), kill switch, auto-reconnect, settings/preferences.
  - Reconciliation of any feature-parity gaps found — either implement the missing piece on the lagging platform(s) or explicitly, deliberately document a platform-specific limitation with clear reasoning (e.g., if a specific OS-level capability genuinely doesn't have a clean equivalent).
  - Cross-platform re-run of the relevant portions of the Phase 9 manual QA protocol (P9-T3), adapted for desktop where mobile-specific steps (e.g., camera QR scanning, if not supported on desktop — decide and document whether QR scanning is in-scope for desktop at all, given most desktops lack a convenient camera-scanning workflow; a "paste from clipboard" or "import from file" alternative may be the appropriate desktop equivalent) don't directly apply.
  - Log-redaction parity check (from Phase 8) specifically re-verified on the desktop daemon's log output, since the daemon is an entirely new log-emitting component not covered by Phase 8's original Android-focused redaction work.
- Excluded:
  - Any new feature not already present on Android — this task is about parity and consistency, not adding net-new functionality beyond what's needed to adapt mobile-specific interactions (like QR scanning) to a sensible desktop equivalent.

**Acceptance Criteria:**
- [ ] Feature-by-feature parity matrix (platform × feature) is produced and committed to the repository, with every gap either closed or explicitly justified as a documented platform limitation.
- [ ] Desktop-adapted manual QA protocol subset is run and passes on all three desktop platforms.
- [ ] Log redaction (per Phase 8's rules) is verified applied correctly to `brick_vpn_daemon`'s own log output, not just the previously-covered Android log stream.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
This task exists because platform-by-platform development naturally risks feature drift — the goal is a genuinely equivalent experience across all four supported platforms (three desktop + Android) modulo well-justified, clearly-documented platform-specific differences, not an accidentally-inconsistent patchwork.

---

### P12-T12 — Desktop Daemon Crash Recovery and GUI Resilience

**Status:** Not Started
**Depends On:** P12-T11

**Objective:**
Harden the desktop architecture against daemon crashes and GUI-process restarts, applying the same resilience rigor Phase 7 applied to Android's foreground-service lifecycle, adapted for the desktop daemon+IPC model's distinct failure modes.

**Scope:**
- Included:
  - Daemon crash detection and automatic restart (via the OS's service-management facility — Windows Service recovery options, `launchd` `KeepAlive`, systemd `Restart=`) with correct behavior when the daemon restarts mid-VPN-session (does the tunnel drop and need reconnection, or can it survive a daemon restart? — investigate what's actually achievable given each OS's TUN-ownership model, and document the actual behavior honestly rather than assuming seamless recovery is possible).
  - GUI-side detection of daemon disconnect/restart (building on P12-T3's basic reconnection logic) with correct, clear user-facing messaging distinguishing "daemon temporarily unavailable, reconnecting" from "VPN disconnected."
  - Prevention of orphaned TUN interfaces or zombie daemon processes across repeated crash/restart cycles — explicit chaos-testing analogous to Android's P7-T5 legacy-regression suite, but targeting desktop-specific risks (e.g., a killed daemon leaving a dangling `utun`/`Wintun` interface that blocks a subsequent daemon start).
  - A consolidated desktop chaos-test checklist analogous to P7-T5's Android checklist, documenting each desktop-specific failure mode tested and its outcome.
- Excluded:
  - Full feature-parity with Android's kill-switch/auto-reconnect network-change handling — those features were already verified for parity in P12-T11; this task is specifically about daemon-process-level (not network-level) resilience.

**Acceptance Criteria:**
- [ ] Daemon crash (simulated via forced kill) results in correct OS-level automatic restart on all three desktop platforms, verified concretely.
- [ ] GUI correctly detects and clearly communicates daemon unavailability/reconnection to the user, distinct from VPN-level disconnection messaging.
- [ ] Repeated forced daemon crash/restart cycles (at least 5) produce zero orphaned TUN interfaces or zombie processes, verified via OS-level process/interface inspection after each cycle.
- [ ] Desktop chaos-test checklist is committed to the repository as a durable, re-runnable reference, mirroring P7-T5's approach.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template.

**Notes for Agent:**
Treat this task with the same seriousness the project gave Android's chaos-testing in Phase 7 — the desktop daemon+IPC architecture is new, unproven-in-this-project territory, and deserves its own dedicated adversarial verification rather than an assumption that "it's simpler than Android so it's probably fine."

---

### P12-T13 — Phase 12 Closeout and Definition-of-Done Pass

**Status:** Not Started
**Depends On:** P12-T1 through P12-T12

**Objective:**
Perform a full closeout pass on Phase 12: confirm Brick VPN is now a genuinely functional, tested, released cross-platform application across Android, Windows, macOS, and Linux, produce the standard DoD report, and update `PROJECT_STATE.md` to reflect this major milestone before Phase 13 (iOS Support) begins.

**Scope:**
- Included:
  - Fresh-clone build and full manual verification pass across all three desktop platforms plus a regression check on Android to confirm nothing in the monorepo's shared packages was inadvertently broken by desktop-driven changes.
  - Full `DEFINITION_OF_DONE.md`-template report covering all of Phase 12's tasks collectively.
  - Rewriting `PROJECT_STATE.md` to reflect: Phase 12 complete, Brick VPN now supports Android, Windows, macOS, and Linux; summarizing the daemon+IPC architecture's real-world validation outcome; explicitly listing all platform-specific known limitations (unsigned-binary warnings if code-signing wasn't pursued, distribution-compatibility scope boundaries on Linux, NetworkExtension deferral on macOS); and stating that Phase 13 (iOS Support) is next, explicitly flagged in the original roadmap as "uncertain/possible later" and requiring its own feasibility assessment before full commitment.
- Excluded:
  - Any new feature work.

**Acceptance Criteria:**
- [ ] Fresh-clone full verification pass across all four platforms (three desktop + Android regression check) completed and described in the report.
- [ ] DoD report produced using the exact template from `DEFINITION_OF_DONE.md`.
- [ ] `PROJECT_STATE.md` rewritten, accurate as of end of Phase 12, with all platform-specific known limitations clearly listed.
- [ ] Explicit statement flagging Phase 13's uncertain status and recommending a feasibility-assessment-first approach rather than assuming full commitment.

**Notes for Agent:**
As with every phase closeout, do not mark this `Completed` yourself — propose `Ready for Human Review` and wait. This closeout represents the project's expansion from a single-platform mobile app to a genuine cross-platform tool — take care to present an honest, complete picture of platform-specific trade-offs and limitations rather than a uniformly polished summary, since the human's decisions about code-signing costs, Linux distribution scope, and whether to pursue Phase 13 at all will depend on this report's accuracy.

---

## Phase 13 — iOS Support

**Phase Goal:** Assess and, if the feasibility assessment supports proceeding, implement iOS support for Brick VPN. This phase is explicitly flagged throughout this roadmap as "uncertain/possible later" — unlike every prior phase, Phase 13's very first task is a genuine go/no-go feasibility and cost/benefit assessment, not an assumed commitment to build. iOS's fundamentally different VPN architecture (mandatory NetworkExtension/Packet Tunnel Provider App Extension model, no equivalent to Android's flexible VpnService or desktop's privileged-daemon pattern), Apple Developer Program cost, App Store review policy specific to VPN apps, and this project's censorship-circumvention context (which has historically drawn extra App Store scrutiny for VPN tools) all warrant a deliberate, human-informed decision before any implementation work begins.

**Granularity Note (reaffirmed):** Written at the same coarser-but-fully-templated grain as Phases 5–12. Given the explicit uncertainty of whether this phase proceeds at all, only the feasibility-assessment task (P13-T1) and a high-level skeleton of subsequent tasks are provided here; the subsequent tasks are intentionally left at a lighter level of detail than other phases and marked as **contingent** — to be properly expanded, re-verified, and re-scoped only after P13-T1's assessment concludes with a human decision to proceed.

---

### P13-T1 — iOS Feasibility Assessment and Go/No-Go Decision

**Status:** Not Started
**Depends On:** P12-T13

**Objective:**
Produce a rigorous, honest feasibility assessment of iOS support for Brick VPN, covering technical architecture requirements, Apple Developer Program and distribution costs, App Store review risk specific to VPN/censorship-circumvention apps, and required engineering effort — culminating in a clear recommendation to the human, who makes the final go/no-go decision. No implementation work of any kind occurs in this task.

**Scope:**
- Included:
  - Research and document iOS's mandatory VPN architecture: the NetworkExtension framework's Packet Tunnel Provider App Extension model — confirm current requirements (this is fundamentally different from Android's `VpnService` or the desktop daemon+IPC pattern; verify current Apple documentation rather than relying on general familiarity, since NetworkExtension APIs and entitlement requirements have evolved).
  - Confirm whether sing-box/libbox has current, maintained iOS/NetworkExtension integration support (check the upstream project's actual current state — some sing-box-based projects, including tools referenced earlier in this project's research such as Hiddify, do ship iOS versions, which is a positive feasibility signal worth verifying directly rather than assuming).
  - Document required Apple Developer Program enrollment (annual cost, verified at current rates) and the specific NetworkExtension entitlement request process (Apple requires a special entitlement request/approval for the Packet Tunnel Provider entitlement, which is not automatically granted — verify current process and typical approval timeline/requirements).
  - Research current App Store Review Guidelines as they specifically apply to VPN apps (Guideline 5.x historically covers this), and specifically research any documented pattern of extra scrutiny, rejection, or removal of VPN/censorship-circumvention-relevant apps from the App Store in various jurisdictions — this is directly relevant given this project's stated Iran-censorship context, and the assessment must be honest about this risk, not optimistic.
  - Estimate engineering effort required, given the architectural divergence from Android/desktop (a Packet Tunnel Provider extension is a distinct, sandboxed process with its own lifecycle model, memory constraints, and IPC-to-host-app pattern — quite different from anything built in Phases 3 or 12), including how much of `packages/core_domain` and other shared Dart logic could realistically be reused versus what would need entirely new platform-specific implementation.
  - Produce a written assessment document (e.g., `docs/planning/ios-feasibility-assessment.md`) covering all of the above, ending with a clear, honest recommendation (proceed / proceed with caveats / do not proceed at this time) and explicit reasoning, but leaving the actual decision to the human.
- Excluded:
  - Any actual iOS project scaffolding, code, or Apple Developer Program enrollment action — this task is pure research and documentation, explicitly gated before any commitment of time or money.

**Acceptance Criteria:**
- [ ] NetworkExtension/Packet Tunnel Provider architecture requirements are researched and documented against current Apple documentation.
- [ ] sing-box/libbox's current iOS support status is directly verified (not assumed) and documented, including reference to any existing sing-box-based iOS apps as feasibility evidence.
- [ ] Apple Developer Program costs and the NetworkExtension entitlement approval process are documented with current, verified figures/requirements.
- [ ] App Store review risk specific to VPN/censorship-circumvention apps is researched and documented honestly, including any known historical precedent of rejections or removals relevant to this category.
- [ ] Engineering effort estimate is produced, with explicit reasoning about shared-code reuse potential versus new platform-specific work required.
- [ ] A clear, honest recommendation is documented, and the assessment is explicitly presented to the human as a decision point, not a fait accompli.
- [ ] Report follows the `DEFINITION_OF_DONE.md` template, in addition to the dedicated assessment document.

**Notes for Agent:**
This task's integrity depends entirely on honesty — do not shade the assessment toward a predetermined "yes, let's build it" conclusion out of a desire to keep the project moving forward, nor toward an overly pessimistic "no" out of risk-aversion. Present the real trade-offs (cost, App Store risk given this project's specific censorship-circumvention purpose, engineering effort, and realistic user-reach benefit of iOS support) as clearly and neutrally as possible, and let the human — who bears the actual financial and reputational risk of this decision — decide. If you cannot find reliable current information on any specific point (e.g., current NetworkExtension entitlement approval timelines, which Apple does not always document precisely), say so explicitly rather than presenting an estimate as more certain than it is.

---

### P13-T2 through P13-TN — Contingent iOS Implementation Tasks (To Be Scoped Upon Go Decision)

**Status:** Not Started (contingent — entire remainder of this phase is blocked pending P13-T1's outcome)
**Depends On:** P13-T1 (explicit human "go" decision required, not merely task completion)

**Objective:**
This placeholder represents the full iOS implementation arc, deliberately left unexpanded until P13-T1 concludes with an explicit human decision to proceed. If and when that decision is made, this section must be properly re-scoped into full, individually-templated tasks — following the same rigor as Phases 0–12 — before any implementation work begins, consistent with this roadmap's living-document principle.

**Scope (anticipated structure, subject to full re-scoping):**
- Included (anticipated, not yet committed):
  - iOS Packet Tunnel Provider App Extension implementation, embedding sing-box/libbox per whatever integration pattern P13-T1's research identifies as current best practice.
  - Host app + extension IPC (iOS's own App Group/Darwin notification or similar mechanism for host-app-to-extension communication, replacing the Android JNI/Pigeon pattern and the desktop daemon/IPC pattern with iOS's own distinct model).
  - Reuse of `packages/core_domain` and other shared Dart/Flutter packages wherever the host app (as opposed to the low-level extension, which per NetworkExtension convention runs as a separate lightweight process typically implemented in Swift, not Dart) can leverage them.
  - VPN permission/consent flow adapted for iOS's own system-level VPN configuration approval dialog (distinct from Android's `VpnService.prepare()` and requiring its own dedicated design, likely requiring an amendment to the `VpnEngine` interface analogous to what P3-T12 did for Android).
  - Full feature parity pass against Android/desktop (server management, connect/disconnect, stats, logs with redaction, kill switch if technically feasible within NetworkExtension's constraints, auto-reconnect) — noting explicitly that some features may not be technically achievable within iOS's sandboxed extension model, which is exactly the kind of constraint P13-T1's research should have flagged in advance.
  - Apple Developer Program enrollment, entitlement request/approval process execution, App Store submission (or, as with Android's initial approach, a TestFlight closed-testing phase first).
  - iOS-specific UI/UX adaptation of the Phase 11 design system to iOS's human interface conventions (which differ meaningfully from Android's Material-influenced conventions) — this may itself warrant being treated as a design task analogous to P11-T1, not merely a mechanical port.
- Excluded:
  - Nothing can be definitively excluded yet — full scope depends on P13-T1's findings.

**Acceptance Criteria:**
- [ ] This entire task group remains `Not Started` and unexpanded unless and until the human explicitly reviews P13-T1's assessment and decides to proceed.
- [ ] Upon a "go" decision, this section is rewritten as a full set of properly granular, individually-templated tasks (following the exact Task Template established in this document's header) before any implementation task is started — i.e., this placeholder itself must never be treated as an actionable task to "complete"; it is scaffolding for a future planning pass.

**Notes for Agent:**
Do not attempt to implement anything under this placeholder as written — it exists only to reserve the phase's place in the roadmap's structure and to make explicit that real planning work is still required here. If a human asks you to "just start on Phase 13," and P13-T1 has not been completed and explicitly approved with a "go" decision, treat that as exactly the kind of ambiguous/out-of-process situation this project's governance model requires you to stop and question rather than proceed on.

---

### P13-TN — Phase 13 Closeout (Contingent)

**Status:** Not Started (contingent on P13-T1's outcome and the full re-scoped task list's completion, if pursued)
**Depends On:** All tasks in the re-scoped Phase 13 task list, if the phase is pursued

**Objective:**
If Phase 13 is pursued and completed, perform the standard phase closeout: fresh-clone verification across iOS alongside a regression check on all previously-supported platforms, full DoD report, and `PROJECT_STATE.md` update reflecting either (a) full five-platform support (Android, Windows, macOS, Linux, iOS) if pursued and completed, or (b) an explicit, documented decision that iOS support was assessed and deliberately not pursued, with clear reasoning preserved for future reference in case circumstances change.

**Scope:**
- Included:
  - Whichever closeout is actually applicable given P13-T1's outcome — this task's concrete content cannot be finalized until that outcome is known.
- Excluded:
  - N/A pending outcome.

**Acceptance Criteria:**
- [ ] `PROJECT_STATE.md` accurately reflects Phase 13's actual outcome (built-and-shipped, or deliberately-not-pursued-with-documented-reasoning), so that no future reader is left wondering whether iOS support was ever considered.
- [ ] If pursued and completed, all standard closeout rigor from prior phase closeouts (fresh-clone verification, cross-platform regression check, DoD report) applies in full.
- [ ] If not pursued, the assessment document from P13-T1 remains preserved and referenced as the durable record of that decision, available for reconsideration in the future without needing to redo the research from scratch.

**Notes for Agent:**
Whichever outcome occurs, ensure the project's documentation tells a clear, honest story about iOS — either "we built it, here's how it works and what its limitations are" or "we deliberately chose not to, here's exactly why, and here's what would need to be true for that decision to be revisited." An undocumented, ambiguous non-decision would be a worse outcome than either clear alternative.

---

## Phase 14 — Premium/Subscription System

**Status: Not yet authored.** Per the Granularity Note, detailed tasks for this phase will be
written when the project actually approaches it (after Phase 11–13), and are gated behind an
explicit human go/no-go decision, mirroring Phase 13's structure (a single P14-T1 feasibility/
architecture-decoupling assessment task, followed by contingent unscoped tasks). This phase must
never degrade the free-tier client, per the standing project constraint.

## Document Closing Notes

### Living-Document Principle (Reaffirmed)

This roadmap is not a fixed, one-time specification — it is a living document, exactly as stated in the Granularity Note at the top of this document. Phases 0 through 3 were written at maximum granularity because they cover the highest-risk, most architecturally foundational, and most failure-prone work in the entire project (config parsing of untrusted input, and the Android VPN lifecycle that directly caused the collapse of the legacy prototype). Phases 4 through 14 were deliberately written at a coarser grain, on the explicit understanding that:

- Each phase's task breakdown, as currently written, represents a reasonable best-effort plan given what is knowable *before* that phase is actually reached — not a guarantee that no task will need to be split, merged, reordered, or revised once real engineering work begins.
- Before starting work on any phase from Phase 4 onward, the human and the assistant should jointly revisit that phase's task list, confirm it still makes sense given everything learned in prior phases, and expand/adjust granularity as needed — particularly for Phase 12 (Desktop Support), which was already written with an explicit acknowledgment that per-OS sub-arcs will likely need further breakdown once actually started, and Phases 13–14 (iOS, Premium), which are explicitly feasibility-gated and largely unscoped pending their respective go/no-go decisions.
- No task in this document should ever be treated as binding beyond what current knowledge, at the time it is actually started, supports. If reality diverges from what was planned here, the roadmap must be updated to reflect reality — not silently ignored, and not treated as an obstacle to doing the right thing.
- This document must be kept in sync with `PROJECT_STATE.md` at all times. Every phase-closeout task in this roadmap explicitly requires a `PROJECT_STATE.md` rewrite; if at any point the two documents disagree about what has actually been completed, `PROJECT_STATE.md` (which reflects verified, human-reviewed reality) takes precedence, and this roadmap should be corrected to match it, not the other way around.

### Working Process Going Forward

With `ROADMAP.md` now fully drafted from Phase 0 through Phase 14, the project's actual working process, task by task, is as follows:

1. **Task selection.** The human selects the next task with `Status: Not Started` whose `Depends On` tasks are all marked `Completed`. Tasks must be worked strictly in dependency order — no task should be started out of sequence, even if it looks tempting or easy, since the domino-style dependency structure exists specifically to prevent compounding, hard-to-diagnose integration failures of exactly the kind that destroyed the legacy prototype.
2. **Discussion and refinement.** The human and the assistant discuss the selected task together — clarifying scope, resolving any open design questions flagged in that task's Notes for Agent, and confirming the task is genuinely ready to be handed off (i.e., its dependencies are not just marked complete on paper, but the human is confident the underlying work is actually sound).
3. **Prompt engineering.** The assistant produces a single, self-contained, engineering-grade English prompt for that specific task, incorporating the task's Objective, Scope, Acceptance Criteria, and Notes for Agent from this roadmap, along with any additional context or clarifications surfaced during discussion in step 2.
4. **Handoff to a coding agent.** The human provides this prompt to a coding agent (human or AI), who executes the task following the seven-step workflow defined in `AGENTS.md`.
5. **Agent self-review and reporting.** The coding agent performs its own Definition-of-Done pass per `DEFINITION_OF_DONE.md` — type-checking, testing, and a final self-review conducted as an independent debugger — and produces a structured report using the exact template defined there (Task Status / Summary / Files Changed / Verification Performed / Self-Review / Known Limitations / Human Action Required). The agent proposes the task as `Ready for Human Review`; it never marks its own work `Completed`.
6. **Human review.** The human reviews the agent's report and the actual resulting work, and either marks the task `Completed` (unblocking its dependents), sends it back with feedback if it falls short, or escalates back to a discussion round (step 2) if something unexpected or ambiguous was uncovered during the work.
7. **Repeat.** The cycle returns to step 1 for the next eligible task.

This cycle continues task-by-task through Phase 10, at which point a stable, usable, tested, and released **Android MVP** exists — the project's first major real-world milestone. The cycle then continues through Phase 11 (UI/UX polish), Phase 12 (Desktop support), and the feasibility-gated Phases 13 (iOS) and 14 (Premium), each following the exact same process.

### Phase Task-Count Summary

The following table is provided purely as a navigational aid for quickly locating a phase's task range within this document. It is not authoritative — the actual task list within each phase section of this document is the source of truth, and this table should be updated if any phase's task count changes during a future re-scoping pass.

| Phase | Title | Task Range | Task Count | Granularity |
|---|---|---|---|---|
| 0 | Project Governance & Repo Scaffolding | P0-T1 – P0-T12 | 12 | Maximum |
| 1 | Architecture Skeleton | P1-T1 – P1-T11 | 11 | Maximum |
| 2 | Config Parser Engine | P2-T1 – P2-T12 | 12 | Maximum |
| 3 | Android VPN Engine (Gate A + Gate B) | P3-T1 – P3-T17 | 17 | Maximum |
| 4 | State Management & App Skeleton | P4-T1 – P4-T8 | 8 | Coarser |
| 5 | Core MVP Features | P5-T1 – P5-T9 | 9 | Coarser |
| 6 | Traffic Stats & Live Logs | P6-T1 – P6-T7 | 7 | Coarser |
| 7 | Stability & Lifecycle Hardening | P7-T1 – P7-T7 | 7 | Coarser |
| 8 | Security Hardening | P8-T1 – P8-T6 | 6 | Coarser |
| 9 | Testing & QA | P9-T1 – P9-T4 | 4 | Coarser |
| 10 | Android MVP Release Prep | P10-T1 – P10-T8 | 8 | Coarser |
| — | **Android MVP milestone reached (Phases 0–10 complete)** | | | |
| 11 | Full UI/UX Design & Implementation | P11-T1 – P11-T7 | 7 | Coarser |
| 12 | Desktop Support (Windows/macOS/Linux) | P12-T1 – P12-T13 | 13 | Coarser, sub-arc-organized |
| 13 | iOS Support | P13-T1 – P13-TN | 1 assessment task + contingent placeholder | Feasibility-gated |
| 14 | Premium/Subscription System | P14-T1 – P14-TN | 1 assessment task + contingent placeholder | Feasibility-gated |

**Total scoped tasks as of this document's initial completion: 121** (12 + 11 + 12 + 17 + 8 + 9 + 7 + 7 + 6 + 4 + 8 + 7 + 13 + 2 + 2), with Phases 13 and 14 each currently represented by only their gating assessment task and a placeholder pending a human go/no-go decision — the true final task count for those two phases will only be known once (and if) they are re-scoped following their respective feasibility assessments.

### Closing Statement

This document represents the complete, currently-known engineering plan for Brick VPN, from an empty repository through a fully-featured, secure, tested, cross-platform, GPL v3 open-source VPN client — built by a solo developer working in close, disciplined partnership with AI coding agents, under the governance framework established in `AI_ROLES/`, `ARCHITECTURE.md`, `AGENTS.md`, `DEFINITION_OF_DONE.md`, and `SECURITY.md`. It was written with explicit, deliberate attention to the real, documented failures of this project's legacy prototype, so that every major risk which sank that earlier attempt has a corresponding, named safeguard somewhere in this plan.

`ROADMAP.md` is now considered complete and ready for active use as of this closing section. Development may now proceed task-by-task, beginning with the next eligible `Not Started` task, per the working process described above.

---