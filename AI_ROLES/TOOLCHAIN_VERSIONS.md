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
| Go | **1.20** (minimum matching the sing-box v1.10.7 `go.mod` directive) | 2026-09-28 | Pinned (P3-T1). Must be built with `GOTOOLCHAIN=local`. See "Go toolchain auto-resolution". |
| gomobile | **`github.com/sagernet/gomobile` v0.1.4** (fork of `golang.org/x/mobile`) | 2026-09-28 | Pinned (P3-T1). v0.1.4 is the exact version sing-box v1.10.7 requires. BSD-3-Clause. |
| Android NDK | **r26b** — HUMAN-DECIDED, not primary-source verified | 2026-09-28 | Pinned (P3-T1) on human direction. See "Unverified" below. |
| Android Gradle Plugin | Not yet pinned - deferred to a later Phase 3 task | 2026-09-16 | No project-level pin is recorded. Out of P3-T1 scope. |
| Kotlin | Not yet pinned - deferred to a later Phase 3 task | 2026-09-16 | No native Kotlin implementation exists yet. Out of P3-T1 scope. |
| sing-box | **v1.10.7** (v1.10.x series) | 2026-09-28 | Pinned (P3-T1). Chosen to match the schema the Phase 2 serializers already emit. See "sing-box version policy". |

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

## Phase 3 Pins — Evidence and Rationale (P3-T1, recorded 2026-09-28)

Every value below was checked against a primary source on 2026-09-28. Where a
claim could **not** be confirmed, it is marked UNVERIFIED and repeated in the
"Unverified items" section rather than presented as fact.

### sing-box version policy

**Pinned: `v1.10.7`** (the v1.10.x series).

This is a deliberate compatibility choice, not a recency choice. Verified on
2026-09-28, the current upstream releases are **v1.14.2** (stable) and
**1.15.0-alpha.9** (pre-release). v1.10.x is therefore *not* the newest
release. It is pinned anyway because:

- `packages/config_parser`'s Sing-Box serializer was written and verified
  against the **1.10/1.11** outbound schema in P2-T3. Pinning 1.10.x keeps the
  emitted JSON valid with no rework.
- sing-box **deprecated the WireGuard *outbound* in 1.11.0 and removes it in
  1.13.0**. The Phase 2 WireGuard/AmneziaWG serialization is only meaningful
  against a 1.10–1.12 line. (That work is a known Phase 2 limitation: real
  runtime AmneziaWG is unsupported by sing-box regardless of version.)

**Consequence the human must own:** pinning v1.10.x means shipping a roughly
1.5-year-old dependency. It is a security-relevant decision and is recorded
here so it is revisited deliberately, not by accident.

### Platform interface shape (verified)

In v1.10.7 the mobile bridge lives at:

- import path `github.com/sagernet/sing-box/experimental/libbox`
- Go package name **`libbox`** (confirmed: `package libbox`)
- the interface type is **`libbox.PlatformInterface`**

**Correction to an earlier assumption:** the `io.nekohasekai.libbox.*` package
path is **not** used by v1.10.7. That path belongs to the pre-1.10
`io.nekohasekai/sing-box` module era. v1.10.7 declares
`module github.com/sagernet/sing-box`. Any design note or code that imports
`io.nekohasekai.libbox` is wrong for this pin and must be corrected.

### Go version (verified)

sing-box **v1.10.7**'s `go.mod` declares **`go 1.20`**. That is the minimum
language/toolchain version for that module, so **Go 1.20** is the pin.

A prior working note suggested Go 1.23.x on the grounds that it "matches
sing-box go.mod". **That was incorrect** and has been corrected here:

| sing-box | `go` directive in `go.mod` |
|---|---|
| v1.10.7 | `go 1.20` |
| v1.14.2 (current stable) | `go 1.25.5` |

Neither declares 1.23.x. Building with a much newer Go than the module asks for
is permitted by the `go` directive but increases the risk of the QUIC breakage
described below, which is one more reason to stay close to 1.20.

### gomobile (verified)

**`github.com/sagernet/gomobile` v0.1.4** — a public fork of
`golang.org/x/mobile` ("forked from golang/mobile"), BSD-3-Clause, 1,159
commits. v0.1.4 is the version required by sing-box v1.10.7's `go.mod`, so the
pin is inherited from sing-box rather than chosen independently.

For reference, sing-box v1.14.2 requires `sagernet/gomobile v0.1.12` — if the
sing-box pin is ever moved forward, this row must move with it.

### 16 KB page-size alignment

Google requires 16 KB page-size support for native libraries on newer Android
devices. From the Android Developers page (updated 2026-09-16): an app whose
`.so` files have a **LOAD segment alignment of 4 KB** is run in "16 KB backcompat
mode" and shows a warning; apps that are genuinely 16 KB aligned do not.

Build flag:

```
CGO_LDFLAGS="-Wl,-z,max-page-size=16384"
```

Verification on the built artifact:

```
readelf -l jni/arm64-v8a/libbox.so | grep -A 1 LOAD
```

The `Align` column of each `LOAD` segment must read **`0x4000`** (16384). Any
`0x1000` (4096) means the library is not 16 KB aligned.

> **UNVERIFIED.** I confirmed the 4 KB-LOAD-segment/backcompat behaviour and the
> existence of the 16 KB requirement from the Android Developers page, but I
> could **not** extract from it a primary-source confirmation that
> `-Wl,-z,max-page-size=16384` is the currently-recommended flag for a
> gomobile/CGO build, nor an official statement of which NDK versions emit
> 16 KB-aligned output natively. Treat both the flag and the r26b choice as
> **human-directed, pending confirmation**. See "Unverified items".

### Reference source availability (verified 2026-09-28)

| Project | Availability | License |
|---|---|---|
| `hiddify/hiddify-app` | Public, 32.9k stars, has `android/` | **"Hiddify Extended GNU GPL v3"** — see below |
| `SagerNet/sing-box` | Public, 38.4k stars | GPL-3.0-or-later |

**Hiddify's license is not plain GPL-3.0.** Its `LICENSE.md` is the
"Hiddify Extended GNU General Public License v3": GPLv3 plus GPLv3 §7
additional conditions. The ones that matter here:

1. **Source Code Availability** — reuse requires publishing a maintained GitHub
   fork of the Hiddify repository.
2. **NonCommercial Use Only** — no commercial use without prior written consent.
3. **Naming and Interface Restrictions** — may not ship with a Hiddify-like
   name or a closely-resembling UI.
4. **Attribution** and **ShareAlike**.

**Recommendation: read-only study, no code reuse.** Conditions 1 and 3 in
particular make fork-and-reuse a poor fit for a differently-named product.
Brick VPN is itself GPLv3, so the base license is compatible; it is the §7
additions that are restrictive. This has not been reviewed by a lawyer and
should not be treated as legal advice.

---

## Known Toolchain Footguns

### Go toolchain auto-resolution (re-confirmed as a control, NOT as a proven bug)

Set **`GOTOOLCHAIN=local`** for every Go build so the toolchain can never be
swapped or downloaded automatically. This is a build-hygiene control and is
**adopted as a hard requirement**, independent of whether the QUIC failure below
is still reproducible.

- **Still relevant, as policy: yes.** Silent toolchain selection is a real
  reproducibility hazard: it can change the AAR/`.so` output with no source
  change at all. Pinning explicitly is cheap and correct.
- **Still relevant, as a documented incident: NOT CONFIRMED.** The specific
  claim that an auto-selected Go version *breaks QUIC outbounds* (Hysteria2 /
  TUIC) traces to peer review and has **not** been reproduced or sourced from
  an upstream issue as of 2026-09-28. Treat it as a hypothesis that justifies
  the control, not as an established fact. If the human can produce the
  upstream reference, this note should cite it.

### sing-box interface path history (corrected, and now load-bearing)

Three different names appear in older notes. Verified state as of 2026-09-28:

| sing-box | module path | libbox package | platform interface type |
|---|---|---|---|
| v1.10.7 (**our pin**) | `github.com/sagernet/sing-box` | `experimental/libbox`, `package libbox` | `libbox.PlatformInterface` |
| pre-1.10 era | `io.nekohasekai/sing-box` | `libbox` | `io.nekohasekai.libbox.PlatformInterface` |
| 1.11+ / 1.13 era | `github.com/sagernet/sing-box` | `experimental/libbox` | moved toward `adapter.PlatformInterface` |

**Actionable:** any note or code referencing `io.nekohasekai.libbox.*` is
**wrong for our v1.10.7 pin** — that was the pre-1.10 module path. If the
sing-box pin moves to 1.13+, `adapter.PlatformInterface` becomes correct and
this becomes a genuine migration task with its own acceptance criteria; it is
**not** a routine dependency bump.

## Deferred Phase 3 Pins

**Pinned in P3-T1 (2026-09-28):** Go 1.20, `github.com/sagernet/gomobile`
v0.1.4, Android NDK r26b (human-directed, unverified), sing-box v1.10.7.

**Still deferred to a later Phase 3 task:** Android Gradle Plugin and Kotlin.
Neither was in P3-T1's scope and neither is needed until the native Android
module is actually scaffolded (P3-T2 onwards).

## Unverified items (P3-T1) — read before trusting these pins

Per the P3-T1 acceptance criteria, these are recorded rather than papered
over. Each needs a human check or a source I could not reach:

1. **Android NDK r26b is human-directed, not verified.** No primary source was
   found stating that r26b is the correct NDK for Go 1.20 +
   `sagernet/gomobile` on arm64-v8a/x86_64. r27b was also mentioned as an
   alternative and was not ruled out. Confirm before the AAR build task.
2. **`-Wl,-z,max-page-size=16384` is not primary-source confirmed** for a
   gomobile/CGO build. The flag is recorded on human instruction. The *check*
   (`readelf -l … | grep -A 1 LOAD` expecting `0x4000`) is standard and sound.
3. **Whether `sagernet/gomobile` carries 16 KB-ELF or Cgo-symbol patches could
   not be confirmed** — the fork's README documents neither. The 16 KB
   alignment is more likely a build-flag concern than a fork feature.
4. **The Go/QUIC breakage incident is unsourced.** See the footgun note above:
   the control is adopted, the specific bug is not evidenced.
5. **Minimum SDK / API level was not verified.** "min API 21" was asserted in
   an earlier note but no source was checked; Go 1.20 and modern Android NDK
   toolchains have their own floor.
6. **`SagerNet/sing-box-for-android` license was not independently checked**
   (assumed GPL-3.0-or-later).
7. **Nothing has been built.** P3-T1 is a research task; no AAR, no
   `libbox.so`, and no `readelf` verification has actually been performed,
   because no native toolchain is installed on this machine yet. Every 16 KB
   claim above is therefore a specification for a future build, not an
   observed result.
