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

**Last updated**: 2026-09-17 — Phase 0 closeout (P0-T4 finalize, P0-T12 closeout gate)
**Updated by**: Coding agent, with raw command output and authenticated `gh` API evidence

---

## 1. Current Phase

**Phase 0 — Project Foundation & Governance Setup: FUNCTIONALLY COMPLETE, pending final human sign-off.**

The Phase 0 closeout gate (P0-T12) has been exercised and passed: a fresh
clone of `origin/master` bootstraps, formats, analyzes, and tests cleanly
with zero manual intervention, and CI is green on the pushed commit. No task
has been marked `Completed` by an agent; the remaining items are human
reviews and final sign-off. No application code, no domain logic, no native
code, and no UI have been written yet — those begin in Phase 1 (P1-T1).

---

## 2. Phase 0 Task Status (quoted from `AI_ROLES/ROADMAP.md`)

Status tokens below are quoted verbatim from the corresponding
`**Status:**` line in `AI_ROLES/ROADMAP.md` (line numbers cited so a reader
can reconcile). Full status prose lives in `ROADMAP.md` only — it is not
duplicated here, to avoid the two files silently drifting apart.

- **P0-T1** (`ROADMAP.md:93`): `Completed ✅` — "Git repository and baseline
  scaffold commit" finalized; commits `d056b07` and `c1821c0` present.
- **P0-T2** (`ROADMAP.md:125`): `Completed ✅` — GPL v3 `LICENSE` added in
  commit `57db473`, byte-verified against the official GPL v3 text.
- **P0-T3** (`ROADMAP.md:157`): `Completed ✅` — all `AI_ROLES` governance
  files committed and cross-verified.
- **P0-T4** (`ROADMAP.md:189`): `Ready for Human Review` — all six required
  items verified via authenticated `gh` API on 2026-09-17: secret scanning
  `enabled`; push protection `enabled`; Dependabot vulnerability alerts HTTP
  `204`; Dependabot automated security fixes `{"enabled": true, "paused":
  false}`; `.github/dependabot.yml` created and committed; branch protection
  on `master` returns HTTP `200` with `allow_force_pushes.enabled: false` and
  `allow_deletions.enabled: false`.
- **P0-T5** (`ROADMAP.md:222`): `Completed ✅` — baseline CI workflow
  (format, analyze, test) verified by real GitHub Actions runs.
- **P0-T6** (`ROADMAP.md:258`): `Completed ✅` — six-package Melos workspace
  verified (`melos list`, `bootstrap`, `analyze`, `test` all pass).
- **P0-T7** (`ROADMAP.md:298`): `Completed ✅` — `native/android`,
  `native/ios`, `native/desktop` README scaffolding; finalized in commit
  `d626064`.
- **P0-T8** (`ROADMAP.md:326`): `Ready for Human Review` —
  `AI_ROLES/TOOLCHAIN_VERSIONS.md` created with freshly verified Flutter
  3.47.4 / Dart 3.13.3 / Melos 8.7.0 / Git 2.43.0 values and the
  version-upgrade policy.
- **P0-T9** (`ROADMAP.md:368`): `Completed ✅` — Memory MCP write/read
  round-trip verified with a fresh second server invocation.
- **P0-T10** (`ROADMAP.md:402`): `Ready for Human Review` — base dependency
  wiring for `apps/mobile` done and verified, `very_good_analysis` active
  with documented template-only exceptions, resolved Dart versions recorded
  in `TOOLCHAIN_VERSIONS.md`.
- **P0-T11** (`ROADMAP.md:436`): `Ready for Human Review` — root `README.md`
  authored; the literal `flutter run` instruction was verified on the real
  Android device `SM A205F` (`RZ8M53WPMPF`).
- **P0-T12** (`ROADMAP.md:467`): `Ready for Human Review` — closeout gate
  validated on 2026-09-17: fresh clone at `c506ebb` bootstraps/formats/
  analyzes/tests with zero manual intervention, and CI run `35169690649`
  completes `success` on `master`.

**Discrepancies flagged, not silently resolved:**

1. `P0-T12`'s acceptance criterion still literally reads "CI is green on the
   `main` branch", while the repository's actual default branch is `master`.
   CI is green on `master`; that checkbox is deliberately left unchecked
   pending a human decision. (The same stale `main` wording in P0-T5 was the
   source of the CI trigger mismatch fixed on 2026-09-17.)

---

## 3. What Exists Right Now (Verified)

- Git repository at `~/Documents/Code/brick-vpn`, GitHub `Ajorvpn/brick`,
  default branch `master`. All Phase 0 work is committed and pushed; local
  and remote `master` both point at commit `c506ebb`.
- Melos monorepo with six packages, verified by `melos bootstrap` reporting
  `6 packages bootstrapped`: root workspace `pubspec.yaml` (Dart Native
  Workspace + Melos config, sole source of truth), `apps/mobile`, and
  `packages/{core_domain, core_vpn_engine, config_parser, ui_theme,
  shared_utils}`.
- Root `README.md` — honest early-stage status, Android-focused run
  instructions, and a Troubleshooting section for the local Gradle init-script
  footgun. No CI badge; no unverified iOS/desktop claims.
- Root `LICENSE` (GPL v3, verbatim official text) plus the SPDX header policy
  in `CODING_STANDARDS.md` for new source files from Phase 1 onward.
- `.github/workflows/ci.yml` — CI pinning Flutter 3.47.4 and Melos 8.7.0,
  non-interactive (`--no-select`), triggered on `push` to `master` (corrected
  2026-09-17) and on all `pull_request` events.
- `.github/dependabot.yml` — 8 entries: 7× `pub` (one per directory
  containing a `pubspec.yaml`: `/`, `/apps/mobile`, and the five
  `packages/*`) plus 1× `github-actions` for `.github/workflows/`.
- `AI_ROLES/` governance set: `AGENTS.md`, `ARCHITECTURE.md`,
  `CODING_STANDARDS.md`, `SECURITY.md`, `DEFINITION_OF_DONE.md`,
  `TOOLCHAIN_VERSIONS.md`, `ROADMAP.md`, `PROJECT_STATE.md`,
  `MCP_MEMORY_GUIDE.md`, `AI_ROLES/ARCHITECTURE.md`.
- `native/{android,ios,desktop}/README.md` placeholders (no native build
  tooling yet; that starts in Phase 3).
- `apps/mobile` Flutter scaffold with base dependencies wired: `riverpod`,
  `riverpod_annotation`, `riverpod_generator`, `build_runner`, `go_router`,
  `easy_localization`, `logger`, `very_good_analysis`. Resolved versions are
  recorded in `AI_ROLES/TOOLCHAIN_VERSIONS.md`.
- GitHub security configuration (verified via authenticated API): secret
  scanning, push protection, Dependabot alerts, Dependabot automated security
  fixes, and a lenient branch-protection rule on `master` (no force-push, no
  deletion) all active.
- A live Dependabot pull request (#1, `github-actions` bump) — real proof the
  Dependabot configuration is being honored by GitHub.

---

## 4. What Does NOT Exist Yet

- Any real domain code, VPN engine, config parser logic, UI, state management
  wiring, or application feature behavior.
- Any Android native integration (`VpnService`, `libbox`, Kotlin bridge) or
  iOS/desktop native code.
- Any pinned Go / gomobile / NDK / AGP / Kotlin / sing-box versions (deferred
  to Phase 3; see `TOOLCHAIN_VERSIONS.md`).
- Pull-request-required and status-check-required branch protection on
  `master` — deliberately not enabled during the solo-development phase
  (documented decision, see P0-T4), to be tightened before outside
  contributors arrive or the project goes fully public.
- Any release, signing, or distribution pipeline (Phase 10).

---

## 5. Environment & Toolchain Notes

**Verified toolchain (see `AI_ROLES/TOOLCHAIN_VERSIONS.md` for the full
matrix and the version-upgrade policy):** Flutter 3.47.4, Dart 3.13.3,
Melos 8.7.0, Git 2.43.0. Do not change any pinned version as a side effect of
another task.

**Local Gradle init-script footgun (must stay disabled):**
`/home/e60/.gradle/init.d/iran-mirrors.gradle.disabled` is a *machine-wide*
Gradle init script on this developer machine that injects extra Maven
repositories into every Gradle build. If it is re-enabled (renamed back to
`.gradle`), Flutter's Android plugin loader fails with:

```text
Build was configured to prefer settings repositories over project
repositories but repository 'maven' was added by settings file
'settings.gradle.kts'
```

This was fully A/B-tested on 2026-09-17: with the init script disabled, the
unmodified Flutter template `apps/mobile/android/build.gradle.kts`
(including its `allprojects { repositories { google(); mavenCentral() } }`
block) builds and runs successfully on a real device. The earlier failure was
caused solely by the local init script, **not** by any file in this
repository. Never "fix" that error by deleting the `allprojects`
repositories block from the template.

**Dart Native Workspace pattern (both halves required):** package discovery
needs the `workspace:` list in the root `pubspec.yaml` **and**
`resolution: workspace` in each package's own `pubspec.yaml`. Omitting either
makes `melos list` / `melos bootstrap` silently report zero packages.

**Melos 8.7.0 configuration:** Melos 8.7.0 reads workspace discovery and
`melos run` scripts only from the root `pubspec.yaml` (`workspace:` +
`melos:` blocks). A separate `melos.yaml` was dead configuration in this
version and has been removed.

---

## 6. Repository Sync State

All Phase 0 work is **committed and pushed** — nothing is left pending in the
working tree except an untracked local scratch directory (`AI_ROLES/logs/`,
containing a personal prompt log) which is intentionally not part of the
project and is not committed.

Commit chain on `master` pushed 2026-09-17 (`d626064..c506ebb`):

- `e6914b4` — `chore: add dependabot configuration for pub and github-actions`
- `02e3979` — `ci: fix workflow trigger to match default branch (master)`
- `4d45523` — `feat: wire base mobile dependencies (riverpod, go_router, easy_localization, logger)`
- `eea4794` — `docs: add root README.md`
- `13ee527` — `docs: update Phase 0 governance status (P0-T4, P0-T7, P0-T10, P0-T11)`
- `c506ebb` — `docs: rewrite PROJECT_STATE.md as authoritative living snapshot`

**Fresh-clone closeout gate (P0-T12), verified 2026-09-17 at `c506ebb`:**
`git clone` → `melos bootstrap` (`6 packages bootstrapped`) →
`melos run format --no-select` (SUCCESS) → `melos run analyze --no-select`
(SUCCESS) → `melos run test --no-select` (SUCCESS). Zero manual
intervention, zero failures.

**CI:** GitHub Actions run `35169690649` (event `push`, `headSha` `c506ebb`)
completed with conclusion `success` on `master`.

---

## 7. Blockers Resolved Since the Previous Snapshot

1. **Branch protection on `master` (P0-T4)** — the human applied it via the
   GitHub UI; re-verified by the agent over authenticated API
   (`GET /branches/master/protection` → HTTP `200`,
   `allow_force_pushes.enabled: false`, `allow_deletions.enabled: false`).
   Chosen tier is deliberately lenient (no PR requirement, no required status
   check) for the solo-development phase; revisit before outside
   contributors or full public launch.
2. **Missing `.github/dependabot.yml`** — created, validated with PyYAML, and
   pushed; Dependabot immediately opened PR #1.
3. **CI trigger mismatch** — `.github/workflows/ci.yml` triggered `push` on
   the stale branch name `main`, so pushes to the real default branch
   `master` were never tested by CI. Corrected to `master`; CI now runs on
   push and is green.
4. **Uncommitted working tree (P0-T1 note)** — the outstanding Phase 0
   changes were committed and pushed with explicit human authorization;
   the tree is clean.
5. **README's "flutter run does not work" limitation** — removed. It was a
   local machine init-script artifact, not a repository defect; the exact
   literal instruction now works on a clean environment.

---

## 8. Open Questions / Pending Human Decisions

1. **P0-T4, P0-T8, P0-T10, P0-T11, P0-T12 review** — all five are
   `Ready for Human Review`; the human must review and mark `Completed`.
   Agents may not self-mark completion.
2. **P0-T12 acceptance criterion wording** — it says "CI is green on the
   `main` branch", but the default branch is `master`. Decide whether to
   reword the criterion or verify the stale `main` branch separately.
3. **Branch protection tier** — decide when to tighten beyond the current
   lenient tier (add PR requirement and required status check as the project
   approaches outside contributors or public launch).
4. **Dependabot PR #1** — a real PR now needs a human decision (merge or
   close) under the project's dependency policy.
5. **`AI_ROLES/logs/`** — untracked local scratch directory; decide whether
   it should be git-ignored, removed, or left alone.

---

## 9. Immediate Next Steps (In Order)

1. Human: review and approve P0-T4, P0-T8, P0-T10, P0-T11, P0-T12.
2. Human: decide the P0-T12 `main`-vs-`master` criterion wording and the fate
   of Dependabot PR #1 and `AI_ROLES/logs/`.
3. Agent, once approved: begin **Phase 1 — Architecture Skeleton, starting at
   P1-T1**. Read `AI_ROLES/ARCHITECTURE.md` and the Phase 1 section of
   `ROADMAP.md` before writing any code.

---

## 10. Closing Note

Phase 0 is functionally complete pending final human sign-off. Phase 1
(Architecture Skeleton) begins at P1-T1 next.
