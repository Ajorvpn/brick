# Brick VPN Toolchain Versions

This file is the authoritative version matrix for reproducible development and
build work. Values marked as deferred are deliberately not pins and must be
verified when the relevant phase begins.

## Verified Matrix

| Tool or component | Version or state | Evidence date | Notes |
|---|---|---:|---|
| Flutter | 3.47.4 stable | 2026-09-16 | Installed and verified with `flutter --version`. |
| Dart SDK | 3.13.3 | 2026-09-16 | Installed through Flutter and verified with `dart --version`. |
| Melos | 8.7.0 | 2026-09-16 | Installed and verified with `melos --version`. |
| Git | 2.43.0 | 2026-09-16 | Installed and verified with `git --version`. |
| Go | Not installed; not yet pinned - deferred to Phase 3 | 2026-09-16 | Do not rely on automatic toolchain selection in CI. |
| gomobile / golang.org/x/mobile | Not installed; not yet pinned - deferred to Phase 3 | 2026-09-16 | Verify together with the Android AAR build design. |
| Android NDK | Not yet pinned - deferred to Phase 3 | 2026-09-16 | NDK directories are present locally, but no project pin is established. |
| Android Gradle Plugin | Not yet pinned - deferred to Phase 3 | 2026-09-16 | No project-level pin is recorded by this task. |
| Kotlin | Not yet pinned - deferred to Phase 3 | 2026-09-16 | No native Kotlin implementation exists yet. |
| sing-box commit or tag | Not yet pinned - deferred to Phase 3 | 2026-09-16 | No libbox or sing-box integration exists yet. |

## Resolved Dart Package Versions (P0-T10)

These versions were resolved in the workspace `pubspec.lock` after the mobile
dependency wiring on 2026-09-16.

| Package | Resolved version |
|---|---:|
| build_runner | 2.16.1 |
| easy_localization | 3.0.8 |
| flutter_riverpod | 3.4.3 |
| go_router | 18.0.1 |
| logger | 2.8.0 |
| riverpod_annotation | 4.0.7 |
| riverpod_generator | 4.0.9 |
| very_good_analysis | 11.0.0 |

## Update Policy

Upgrading any pinned version listed here requires its own roadmap task with
explicit lifecycle re-testing acceptance criteria; it is never bundled into an
unrelated task.

The task must verify the replacement version from an authoritative source,
update this matrix, rerun all affected validation, and document compatibility
risks before the version is adopted.

## Known Toolchain Footguns

### Go toolchain auto-resolution

CI must select an explicit Go version once Go is introduced. Do not rely on a
`go.mod` toolchain directive or automatic download to choose a version behind
the scenes. An unnoticed toolchain change can alter Android AAR output and may
break QUIC-based outbounds such as Hysteria2 or TUIC without an obvious source
change.

### sing-box 1.13 interface migration

A sing-box major-version upgrade is not a routine dependency bump. In
particular, the sing-box 1.13 API migration changes the platform interface from
`platform.Interface` to `adapter.PlatformInterface`. Treat that kind of change
as a dedicated migration task with its own acceptance criteria and lifecycle
validation, rather than silently updating a dependency.

## Deferred Phase 3 Pins

Go, gomobile, `golang.org/x/mobile`, the Android NDK, Android Gradle Plugin,
Kotlin, and the exact sing-box/libbox commit or tag remain intentionally
unselected. They must be researched and pinned in the dedicated Phase 3 work
before native VPN integration or Android AAR production begins.
