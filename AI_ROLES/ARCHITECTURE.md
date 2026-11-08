# ARCHITECTURE.md — Brick VPN Technical Architecture

> **Status**: Living document. This file is the single source of truth for 
> *why* technical decisions were made. Every AI Agent working on this 
> codebase MUST read this file before writing any code. If a decision here 
> seems wrong for a new situation, STOP and ask the human maintainer before 
> deviating — do not silently override architecture decisions.

---

## 0. Context: Why This Document Exists

This project is a ground-up rewrite of a previous VPN client attempt 
(codename: the "legacy prototype") that was abandoned due to accumulated 
technical debt and architectural mistakes — not because the core idea was 
wrong. The root causes of that failure, verified through static analysis, 
were:

1. A native bridge layer (JS ↔ Kotlin ↔ Go core) that was written without 
   rigorous error handling, leading to silent failures (e.g., stats 
   pipeline failing silently, VPN service failing to stop cleanly).
2. No separation between "VPN connection lifecycle" and "traffic 
   statistics reporting" — bugs in one bled into the other.
3. No formal state machine for VPN lifecycle (connect/disconnect races, 
   orphaned TUN interfaces, blocking calls on the main thread during 
   teardown).
4. Insufficiently tested platform integration code, treated as an 
   afterthought rather than the most critical layer of the system.

**Every architectural decision in this document is deliberately designed 
to prevent a repeat of these specific failure modes.** Where relevant, 
this document explicitly calls out which lesson from the legacy prototype 
informed a decision.

---

## 1. High-Level Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| UI Framework | **Flutter** (Dart) | Single codebase compiles to native ARM/x64 across mobile, desktop. No JS bridge overhead. Proven at scale for this exact use case (Hiddify uses the same stack + sing-box in production with millions of users). |
| VPN Core | **sing-box** (via `libbox`, Go) | Industry-proven multi-protocol proxy core (VLESS, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, REALITY). Actively maintained, used by multiple production VPN clients. We integrate it, we do NOT reimplement proxy protocols ourselves. |
| Monorepo Tooling | **Melos** (on top of Dart Native Workspaces, Dart SDK ≥3.6) | Official/standard tool for Dart/Flutter monorepos. Turborepo (JS ecosystem) is not applicable here since the project is Dart-first. |
| State Management | **Riverpod** (with `riverpod_generator`, `Notifier`/`AsyncNotifier`) | Compile-time safety, low boilerplate, excellent testability. Chosen over Bloc for solo-developer + AI-agent-assisted velocity without sacrificing architectural rigor. |
| Navigation | **go_router** | Official Flutter team package, declarative routing, deep-link ready. |
| Linting | **very_good_analysis** | Stricter ruleset than default `flutter_lints`, industry-respected (Very Good Ventures). |
| Localization | **easy_localization** | Structured i18n from day one (Persian + English), even though UI polish comes later. |
| Logging (dev-only) | **logger** | Structured local logging for development/debugging. Explicitly NOT wired to any remote telemetry service. |
| Telemetry/Analytics | **None** (by design) | This is a censorship-circumvention / privacy tool. No Google Analytics, no Firebase, no default crash reporting to third parties. If crash reporting is ever added, it must be self-hosted or privacy-first, and opt-in only. |
| CI/CD | **GitHub Actions** | Lint + type-check + test + build matrix run on every push/PR from the first task onward — not bolted on later. |
| License | **GPL v3** | Ensures derivative/commercial forks must remain open source, protecting the project from being silently absorbed into closed-source commercial products. |

---

## 2. Monorepo Structure
brick-vpn/
├── apps/
│ └── mobile/ # Main Flutter app (targets Android first;
│ # later Windows/macOS/Linux/iOS build
│ # targets are added to this SAME app,
│ # per Flutter's multi-platform model —
│ # this is NOT a separate app per platform)
├── packages/
│ ├── core_domain/ # Pure Dart: Entities, Use Cases,
│ │ # Repository interfaces. Zero Flutter
│ │ # dependency. Fully unit-testable in
│ │ # isolation.
│ ├── core_vpn_engine/ # The VPN abstraction layer (see Section 3)
│ ├── config_parser/ # Pure Dart parser: vless://, vmess://,
│ │ # trojan://, ss://, hysteria2://, tuic://
│ │ # subscription URLs → sing-box JSON config.
│ │ # Zero UI dependency, heavily unit-tested.
│ ├── ui_theme/ # Shared design tokens (colors, typography,
│ │ # spacing) — NOT full components yet.
│ └── shared_utils/ # Cross-cutting utilities: logger wrapper,
│ # error types, result/either types.
├── native/
│ ├── android/ # Kotlin native module source
│ │ # (VpnService, libbox JNI bridge)
│ ├── ios/ # Swift native module source (future phase)
│ └── desktop/ # Go source for brick_vpn_daemon
│ # (standalone privileged daemon binary,
│ # embeds sing-box directly — future phase,
│ # see Section 3.6)
├── AI_ROLES/ # This governance folder
├── melos.yaml
├── pubspec.yaml # Workspace root (Dart Native Workspace)
└── README.md

text


### 2.1 Critical Setup Note — Dart Native Workspaces (Learned the Hard Way)

Melos ≥8.x is built on top of Dart's **native pub workspace** feature 
(Dart SDK ≥3.6). This has two non-obvious requirements that MUST be 
followed for every new package added to this monorepo, or Melos will 
silently report `0 packages bootstrapped` / `No packages were found`:

1. The root `pubspec.yaml` MUST explicitly list every package path under 
   a `workspace:` field:
   ```yaml
   workspace:
     - apps/mobile
     - packages/core_domain
     - packages/core_vpn_engine
     # ... every package, listed explicitly
Every individual package's own pubspec.yaml MUST include:
YAML

resolution: workspace
Action for AI Agents: Whenever you create a new package under
apps/ or packages/, you MUST update the root pubspec.yaml's
workspace: list AND add resolution: workspace to the new package's
pubspec.yaml as part of the same task. Forgetting this is the single
most common setup error in this repo — verify with melos list after
adding any package.

3. The VPN Engine Abstraction Layer (Most Critical Architectural Decision)
This is the layer that caused the legacy prototype to fail. It receives
the highest engineering scrutiny in this project.

3.1 Design Principle
The rest of the app (UI, state management, business logic) must NEVER
know or care whether it's running on Android (Platform Channel), iOS
(Platform Channel), or Desktop (privileged daemon + local IPC). It only
interacts with an abstract Dart interface. This is a direct application
of the Dependency Inversion Principle and is what makes the domain layer
testable without a real device/VPN connection.

3.1.1 Legal State Transition Graph (normative)
The `VpnEngine` lifecycle is a finite state machine over the sealed
`ConnectionState` hierarchy (`packages/core_domain/lib/src/
connection_state.dart`). The graph below is NORMATIVE: every engine
implementation, native or mock, must permit exactly these transitions and
must reject everything else. An illegal transition is a programmer error
and must be surfaced (the mock throws `StateError`; a native engine must
log and refuse, per Section 3.5) - never silently coerced into a
plausible-looking state. Silently "fixing" an impossible transition is
precisely what produced the legacy prototype's "Connected over a dead
tunnel" bug.

From | To | Meaning
Disconnected | Connecting | User-requested connect accepted; attempt begins.
Connecting | Connected | Attempt succeeded; tunnel is up and traffic may flow.
Connecting | Error | Attempt failed; the tunnel was never established.
Connecting | Disconnecting | User stopped the attempt before it settled.
Connected | Disconnecting | User-requested teardown begins.
Connected | Error | The tunnel died without being asked to (unexpected disconnect). **Added 2026-09-26 (P1-T5).** A live tunnel can fail spontaneously, so `Error` must be reachable from `Connected`; otherwise an unexpected drop could only be reported as a clean teardown, losing the failure reason and misrepresenting the tunnel's state.
Disconnecting | Disconnected | Teardown completed. The ONLY legal exit from `Disconnecting` (enforced by the stop watchdog - see Section 3.5).
Error | Connecting | Explicit retry.
Error | Disconnecting | User dismissed/cleared the failure.

Deliberately NOT legal, and each for a reason:
- `Connected -> Connecting` without an intervening `Disconnecting` /
  `Disconnected`. A second attempt must never be layered over a live
  tunnel; this is the legacy prototype's core bug class (Section 0).
- `Disconnecting -> Error` and `Disconnecting -> Connecting`. Once a
  teardown has been announced the machine must converge on
  `Disconnected`; this is what lets the 5000 ms stop watchdog
  (Section 3.5) force a stuck teardown to a legal resting state instead
  of needing an escape hatch.
- `Disconnected -> Error`, `Disconnected -> Disconnecting`. Nothing has
  been attempted, so there is no failure to report and nothing to tear
  down.

Session tokens (Section 3.5) and the 5000 ms stop watchdog (Section 3.5)
are the two mechanisms that keep this graph honest under concurrency: the
first prevents a superseded attempt's late callback from applying a
transition that is legal in the abstract but wrong for the current
session; the second guarantees `Disconnecting` can never be terminal.

3.1.2 Native Android Harness State Vocabulary (8-state)
The native Android engine (`packages/vpn_engine_android`, Gate A) does NOT reuse the five
Dart `ConnectionState` variants directly. P3-T5 implemented an 8-state
vocabulary in `VpnState.kt`, a sealed class whose only legal transitions are:

    Idle       -> Preparing, Revoked
    Preparing  -> Starting, Stopping, Error, Revoked
    Starting   -> Running, Stopping, Error, Revoked
    Running    -> Stopping, Error, Revoked
    Stopping   -> Stopped, Revoked
    Stopped    -> Preparing, Idle, Revoked
    Error(r)   -> Preparing, Stopping, Revoked
    Revoked    -> Idle

Every other pair is refused. An illegal transition is a programmer error that
the native engine logs and refuses (never coerces, never throws across the
boundary); the refusal is recorded in `lastRejection`.

Mapping onto the normative Section 3.1.1 graph:

| Native `VpnState` | Dart `ConnectionState` | Note |
|---|---|---|
| `Idle`                | `Disconnected` | nothing attempted yet |
| `Preparing`           | `Connecting`   | config validation / TUN setup |
| `Starting`            | `Connecting`   | engine start in flight |
| `Running`             | `Connected`    | tunnel up |
| `Stopping`            | `Disconnecting`| teardown announced |
| `Stopped`             | `Disconnected` | teardown completed cleanly |
| `Error(reason)`       | `Error(reason)`| 1:1 |
| `Revoked`             | `Error(PermissionDenied)` | no Dart equivalent |

Why the native side needs a finer vocabulary: it must distinguish "never
attempted" (`Idle`) from "finished cleanly" (`Stopped`) — a distinction Dart's
single `Disconnected` deliberately collapses — and it must distinguish "still
validating config" (`Preparing`) from "engine is starting" (`Starting`), because
a stop request must cancel cleanly in both. `Revoked` has no Dart counterpart
because VPN permission revocation is an Android-specific concept: the OS can
withdraw the VPN slot from under a running tunnel, and that must not be
reported as an ordinary teardown.

The 8-state graph is a strict refinement of Section 3.1.1 — no edge exists here
that is illegal there. Two consequences worth stating: `Running -> Error` is
legal (an unexpected drop must not be laundered into a clean teardown), and
`Stopping -> Error` is NOT legal, which is precisely what lets the 5000 ms stop
watchdog force a stuck teardown to `Stopped` as a legal resting state.

3.2 The Abstraction
text

packages/core_vpn_engine/
├── lib/
│   ├── core_vpn_engine.dart              # Public exports
│   └── src/
│       ├── vpn_engine.dart               # Abstract interface (the contract)
│       ├── vpn_connection_state.dart     # Sealed class: Disconnected,
│       │                                 # Connecting, Connected, Disconnecting,
│       │                                 # Reconnecting, Error(reason) — explicit
│       │                                 # state machine, no ambiguous states.
│       ├── vpn_traffic_stats.dart        # Value object: upload/download
│       │                                 # bytes, connection duration.
│       ├── platform/
│       │   ├── android/
│       │   │   └── android_vpn_engine.dart   # Implements VpnEngine via
│       │   │                                 # Pigeon-generated typed
│       │   │                                 # channels (see 3.5)
│       │   ├── ios/                          # (future) Implements VpnEngine
│       │   │                                 # via Platform Channel
│       │   └── desktop/                      # (future) Implements VpnEngine
│       │                                     # via local IPC to
│       │                                     # `brick_vpn_daemon` (see 3.6)
│       └── vpn_engine_factory.dart       # Returns the correct platform
│                                          # implementation at runtime
│                                          # (Platform.isAndroid, etc.)
3.3 Key Interface Contract (conceptual — final Dart syntax defined at
implementation time)

The VpnEngine abstract interface exposes:

Future<void> connect(VpnConfig config)
Future<void> disconnect()
Stream<VpnConnectionState> get connectionState
Stream<VpnTrafficStats> get trafficStats
Future<VpnConnectionState> getCurrentState()
Explicit separation lesson applied: connectionState and
trafficStats are TWO SEPARATE streams with independent failure domains.
A failure in the stats pipeline must NEVER be able to affect or block the
connection state pipeline, and vice versa. This directly addresses the
legacy prototype's Problem 1 (stats silently failing) and its coupling
with Problem 2 (connection issues).

Note: This interface is expected to be amended during Phase 3
(see P3-T12 in ROADMAP.md) to add an explicit prepare()-style
permission-consent command, mirroring Android's VpnService.prepare()
flow, which was not present in the original interface design above.

3.4 Platform Implementation Strategy
Platform	Mechanism	Notes
Android	Platform Channel (Pigeon-generated MethodChannel + EventChannel equivalents) → Kotlin → VpnService → libbox AAR	OS-mandated: only a VpnService can create a TUN interface. No way around this.
iOS (future)	Platform Channel → Swift → NetworkExtension (NEPacketTunnelProvider) → libbox XCFramework	OS-mandated equivalent of Android's VpnService.
Desktop (Phase 12+)	Separate privileged daemon process (brick_vpn_daemon, a standalone Go binary embedding the sing-box core directly — no gomobile/cgo bridge needed since no JNI is involved on desktop) ↔ local IPC (Unix domain socket on Linux/macOS, named pipe on Windows; loopback-only, token-authenticated) ↔ unprivileged Flutter GUI process	The GUI process never links against the VPN core directly and never requires elevated privileges itself. Control-plane commands and stats/log streaming use sing-box's built-in Clash API (REST/WS over localhost) wherever it covers the need, avoiding a custom IPC protocol for those concerns. This pattern matches production precedent (WireGuard, Tailscale, Mullvad, Hiddify's hiddify-core) and provides privilege separation and crash isolation between the GUI and the TUN-owning process. In-process dart:ffi directly wrapping sing-box is explicitly rejected as the primary desktop architecture — see Section 3.6 and the Decision Log.
3.5 Native Layer Engineering Standards (Android — Phase 3 focus)
Because the legacy prototype's Kotlin native module was the primary
source of failure, the following are non-negotiable requirements for
the native Android implementation:

Explicit state machine: The VPN service lifecycle must be modeled
as an explicit finite state machine (not implicit booleans/flags).
Invalid transitions must be rejected and logged, not silently ignored.
No blocking calls on the main thread, ever — especially during
onDestroy()/teardown. All blocking libbox calls (disconnect(),
close()) must run on a dedicated background dispatcher, with
explicit timeouts.
Guaranteed TUN cleanup: Every code path that opens a TUN file
descriptor must have a corresponding guaranteed cleanup path (using
Kotlin's try/finally or equivalent), including error/exception paths.
The legacy prototype leaked TUN interfaces when startOrReloadService
failed after openTun succeeded — this must be structurally
impossible in the new implementation.
ACTION_STOP explicit handshake: Stopping the VPN must use an
explicit intent action + stopSelf() pattern, never a bare
context.stopService() call from outside the service.
Retain the ParcelFileDescriptor handle: The Java/Kotlin side
must always retain a handle capable of force-closing the TUN
interface, even if the Go/libbox side becomes unresponsive.
No callback re-entrancy deadlocks: Native callbacks from libbox
(e.g., a Go-side serviceStop() callback) must never directly call
back into a function that could be waiting on the same lock/thread
that triggered it in the first place.

Outbound socket protection is MANDATORY for any real tunnel, and it
is gated, not automatic. In pinned sing-box v1.10.7, libbox reaches the
host for per-socket protection through
`PlatformInterface.autoDetectInterfaceControl(fd)`; the reference
Android client implements that method as `VpnService.protect(fd)`. It
fires only when BOTH conditions hold: (a) the platform interface
returns true from `usePlatformAutoDetectInterfaceControl()`, and (b)
the config sets `route.auto_detect_interface = true`. If either is
missing, libbox silently falls back to interface-based socket binding.
Once the TUN claims `0.0.0.0/0` without protection being active,
libbox's own connection to the proxy server is routed back into the TUN
it created — a self-inflicted routing loop. Protection and full-route
capture are therefore a matched pair and must be enabled together; a
wide route with protection disabled is a bug, not a tuning choice.
(Verified 2026-10-03 against pinned source. Since P3-T7 Part 2 the harness
wires all three halves — `usePlatformAutoDetectInterfaceControl() = true`,
`VpnService.protect(fd)` in `autoDetectInterfaceControl`, and
`route.auto_detect_interface = true` in the config — and an instrumented
test asserts the callback actually fires on a real dial. The Gate A route
stays restricted, which remains safe regardless.)

The pinned libbox AAR's build tags define its transport ceiling.
sing-box gates several protocols behind build tags, and the shipping
AAR was built without `with_utls`. Because sing-box v1.10.7 routes
every Reality outbound through `NewRealityClient`, which is a stub
without that tag, **Reality cannot function at all** with this AAR.
Protocol support must therefore be asserted against the AAR's actual
build tags rather than assumed from the library's advertised protocol
list; a supported protocol in upstream docs is not necessarily
available in our binary.

As of P3-T7 Part 2 (2026-10-03) the shipping AAR **does** carry
`with_utls`: `scripts/build_libbox_aar.sh` passes it explicitly, with
the justification sourced from the pinned tree rather than assumed.
This is the standing model for build-tag decisions — the tag set is
part of the dependency contract and must be re-verified whenever the
AAR is rebuilt, because a tag silently missing produces a binary that
compiles, installs, and only fails at connection time.
Session tokens are mandatory on every start()/stop() command.
Every command carries a session token identifying the lifecycle
attempt it belongs to; callbacks or events tagged with a stale/
superseded token must be discarded silently at the point of receipt
(though still logged for diagnostics) and must never be applied to
the current state — this directly prevents the kind of state-race
bugs (e.g., a "stopping" state being overwritten by a late callback
from a previous session) that affected the legacy prototype.
Stop watchdog with a hard timeout: Any transition into a
STOPPING state must be guarded by a watchdog with a hard 5000ms
timeout. If libbox teardown has not completed within that window,
the watchdog must forcibly close the retained ParcelFileDescriptor
and force the state machine into STOPPED/ERROR regardless of
libbox's own reported status. A stuck STOPPING state is always
treated as a P0 bug, never as acceptable behavior. This guarantee is
bounded by an upstream, process-level risk: sing-box v1.10.7's
BoxService.Close() calls os.Exit(1) internally on its own
C.FatalStopTimeout, so a hung libbox close can terminate the entire
app process before this watchdog can act — it is therefore not a
full substitute for process-level supervision (see
PROJECT_STATE.md "Known deviations").
Type-safe generated channels only: All platform-channel commands
must use Pigeon-generated type-safe interfaces, never hand-written
MethodChannel string-keyed method names or raw argument maps.
High-frequency streams (connection state, traffic stats, logs) must
use EventChannel (or a typed equivalent generated/wrapped for type
safety) rather than repeated method-channel polling.
Command acceptance is separate from final state: start() and
stop() calls must return quickly with one of a fixed set of
acceptance results — accepted, rejectedBusy,
rejectedInvalidConfig, rejectedPermissionDenied, or failed —
describing only whether the command was accepted for processing.
The actual resulting connected/stopped transition must be
communicated exclusively via the state stream, and must never be
inferred or assumed from a command's return value.
3.6 Desktop Engine Architecture (Planned, Phase 12+)
Status: Planning placeholder. This section documents the current
best-informed target architecture for desktop support, based on
synthesis of production VPN client precedent available at the time of
writing. It is explicitly flagged for re-verification against the
actual state of the sing-box/Go/desktop-OS ecosystem when Phase 12 is
actually started (see ROADMAP.md task P12-T1) — do not treat any
specific claim below as guaranteed to still be current at
implementation time.

3.6.1 Rationale
Desktop operating systems do not impose the same "only a privileged
OS-mediated service can own a TUN interface" restriction that Android's
VpnService and iOS's NEPacketTunnelProvider enforce. This means a
desktop implementation could technically call into sing-box directly
from within the Flutter GUI process via dart:ffi. This was considered
and explicitly rejected as the primary architecture, for three reasons:

Privilege separation. Creating a TUN interface and routing system
traffic requires elevated/administrator privileges on every desktop
OS. Running the entire GUI process with elevated privileges (which
in-process FFI would effectively require) unnecessarily expands the
attack surface of a large, complex, frequently-updated UI codebase
to root/admin level. A small, minimal, auditable privileged daemon
process is a much smaller and more defensible trust boundary.
Crash isolation. A crash or hang in the Flutter GUI process (UI
rendering bugs, plugin issues, memory issues) must never be able to
take down an active VPN tunnel, and vice versa — a daemon crash
should be independently recoverable without necessarily killing the
user's open GUI session. In-process FFI couples these two failure
domains together permanently.
Lifecycle independence. A privileged background daemon can
continue running (maintaining the VPN connection) independently of
whether the GUI is open, closed, or restarted — mirroring the
Android foreground-service model's "VPN survives GUI process death"
property, which this project already depends on and tests for
(see ROADMAP.md Phase 7).
This matches directly-observed production precedent: WireGuard, Tailscale,
Mullvad, OpenVPN, and Hiddify's own hiddify-core (which this project's
research explicitly reviewed) all run their VPN-core/TUN-owning logic as
a separate privileged daemon or service process, communicating with an
unprivileged GUI client over local IPC — never as an in-process library
call from the GUI itself.

3.6.2 Target Architecture
text

┌─────────────────────────┐         local IPC          ┌──────────────────────────┐
│   Flutter Desktop GUI     │  (Unix socket / named pipe, │   brick_vpn_daemon         │
│   (unprivileged process)  │◄────loopback-only, token───►│   (privileged process,     │
│                            │        authenticated)        │    embeds sing-box core)   │
│  - core_vpn_engine's       │                              │                            │
│    desktop VpnEngine impl  │   Control plane / stats /    │  - Owns TUN interface      │
│    talks over IPC          │   logs: sing-box's Clash     │    (Wintun / utun /        │
│  - Never elevated          │   API (REST/WS, localhost)   │    /dev/net/tun)           │
│  - Never links VPN core    │   wherever it covers the     │  - Runs as OS service/     │
│    directly                │   need; custom daemon        │    launchd job/helper      │
└─────────────────────────┘   commands only where needed  └──────────────┬───────────┘
                                                                          │
                                                                          ▼
                                                            TUN device / system routing
3.6.3 Per-OS Notes
OS	TUN mechanism	Privilege/service model	Notes
Windows	Wintun	Windows Service	Daemon installed/managed as a Windows Service for privilege and lifecycle management independent of any logged-in user session.
macOS	utun	launchd-managed privileged helper	A launchd-managed privileged helper process is used initially. NetworkExtension/System Extension is deliberately deferred and should be reconsidered specifically if/when Mac App Store distribution is pursued, since NetworkExtension is generally the App-Store-mandated mechanism for macOS VPN apps, whereas the launchd helper + utun approach is appropriate for direct/notarized distribution outside the App Store.
Linux	/dev/net/tun + CAP_NET_ADMIN	systemd service, or a polkit-authorized helper	Either a systemd service (for systemd-based distributions, the large majority of modern Linux desktops) or a polkit-authorized helper/capability-based approach may be used, to be decided with documented rationale at implementation time given Linux's more heterogeneous privilege-management landscape.
3.6.4 Control Plane
Wherever possible, control-plane operations (start/stop/status queries),
traffic statistics, and log streaming should use sing-box's own built-in
Clash API (REST/WS interface over localhost), rather than inventing a
fully custom IPC protocol for concerns sing-box already exposes natively.
A custom protocol layer over the authenticated local IPC channel
(Section 3.4) is used only for what the Clash API does not cover — e.g.,
daemon lifecycle management itself (start/stop/install the daemon
process) and privilege-elevation coordination during first-run setup.

3.6.5 Explicit Rejection of In-Process FFI as Primary Architecture
dart:ffi remains a permissible tool in this project only for
isolated, non-privileged utility functions where it offers a clear,
narrow benefit. It must never be used as the mechanism by which the
GUI process owns or directly controls the VPN/TUN lifecycle on desktop.
See the Decision Log entry below for the formal record of this decision.

4. Clean Architecture — Feature Structure
Within apps/mobile/lib/features/<feature_name>/, every feature follows
the same three-layer structure:

text

features/traffic_stats/
├── data/            # Repository implementations, data sources
│                     # (e.g., wraps core_vpn_engine's trafficStats stream)
├── domain/           # Feature-specific entities/use cases NOT shared
│                     # across the app (shared ones live in core_domain)
└── presentation/     # Screens, widgets, Riverpod providers/notifiers
Rule for AI Agents: When implementing a new feature, always mirror
this exact structure. Do not put business logic in presentation/. Do
not put Flutter/widget imports in domain/.

5. Security Architecture (Summary — full detail in SECURITY.md)
Key architectural implications relevant to this document:

No plaintext storage of server configs or credentials anywhere —
uses platform-native secure storage (Android Keystore-backed encrypted
storage, equivalent mechanisms per platform later).
No default logging of sensitive data (server IPs, user configs)
even in dev-mode logger output — sensitive fields must be
redacted at the logging utility level in shared_utils.
Config parser (packages/config_parser) is a pure, sandboxed
function with no side effects, network calls, or file I/O — this
makes it trivially fuzz-testable and reduces attack surface from
malicious subscription URLs/configs.
6. Explicitly Deferred Decisions (Not Yet Made — Do Not Assume)
The following are intentionally NOT decided yet and must not be
architected around prematurely:

Exact per-OS desktop daemon/IPC implementation details (Windows
Wintun service specifics, macOS launchd helper installation
mechanism, Linux systemd-vs-polkit choice) — Section 3.6 documents
only the current best-informed target architecture and is
explicitly flagged for re-verification at Phase 12 start; do not
treat it as final implementation detail.
iOS NetworkExtension implementation details (Phase 13) — also
explicitly gated behind a feasibility assessment before any
implementation commitment (see ROADMAP.md P13-T1).
Subscription/Premium backend architecture (Phase 14) — deliberately
kept out of the current monorepo's dependency graph so the free/open
client never structurally depends on a commercial backend, and itself
gated behind a feasibility assessment (see ROADMAP.md P14-T1).
Final UI/UX design system specifics (Phase 11) — ui_theme package
currently holds only placeholder tokens.
7. Decision Log
Date/Phase	Decision	Alternatives Considered	Rationale
Phase 0	Flutter over React Native	React Native + Expo (used in legacy prototype)	Fewer abstraction layers to native code, official desktop support, proven identical architecture in Hiddify at scale.
Phase 0	Melos over Turborepo	Turborepo (used in legacy prototype)	Turborepo is JS/TS-oriented; not applicable to a Dart-first codebase.
Phase 0	Riverpod over Bloc	Bloc, Provider, GetX	Lower boilerplate, strong compile-time safety, good fit for solo/AI-assisted development velocity.
Phase 0	GPL v3 license	MIT, Apache 2.0, AGPL v3	Prevents closed-source commercial forks while remaining less restrictive than AGPL for the eventual separate premium backend.
Phase 0	No default telemetry/analytics	Firebase Analytics, Google Analytics	Product is a censorship-circumvention/privacy tool; any default data collection is a trust and security liability.
Pre-Phase 3 (peer-review synthesis)	Desktop VPN core runs as a separate privileged daemon process + local IPC, not in-process Dart FFI	In-process dart:ffi directly wrapping sing-box as a c-shared library, called from the GUI process	Matches production precedent (WireGuard, Tailscale, Mullvad, and Hiddify's own hiddify-core all use a privileged daemon/service + unprivileged GUI + local IPC pattern); provides privilege separation (GUI never needs elevation), crash isolation (GUI and VPN-core failures are independent), and lifecycle independence (VPN can outlive GUI process, consistent with the Android foreground-service model already adopted). Status: Confirmed, pending Phase 12 detailed design and ecosystem re-verification — see Section 3.6.
Phase 5 (P5-T1)	Local Persistent Storage for Server Profiles & Subscriptions via Versioned Atomic JSON-File Store	Isar, Hive (v2/v3), Drift/sqlite3, raw SharedPreferences	Zero third-party database or native binary dependencies; ServerProfile and sealed OutboundConfig hierarchy already serialize to canonical sing-box-compatible JSON with `schema_version: 1` (`toJson()`) and deserialize via `readSingBoxOutboundJson()`; in-memory cache gives sub-millisecond reads while atomic write-then-rename (`.tmp` -> final file) guarantees resilience against crashes/corruption; preserves a clean seam for Phase 8 encryption (encrypting sensitive fields or the serialized payload via Android Keystore / iOS Keychain).
Phase 5 (P5-T3)	QR Code Scanner & Permission Handling via mobile_scanner & permission_handler	qr_code_scanner, zxing2, camera + google_mlkit_barcode_scanning	mobile_scanner uses modern CameraX on Android and AVFoundation on iOS, actively maintained with Flutter 3 / Dart 3 workspace support; permission_handler provides precise 3-state runtime permission checks (granted, denied, permanentlyDenied) and direct system settings redirection; both wrapped behind testable abstractions for 100% hermetic widget tests.
Phase 5 (P5-T6)	Full-Replace Diffing Policy on Subscription Refresh	Diff-by-tag/endpoint, merge heuristics	Subscription feeds lack stable identifiers across refreshes (URLs, remarks, and ports rotate); diff heuristics risk orphan servers or silent drift. Full-replace atomically swaps child profiles on >=1 valid config and preserves existing profiles untouched on failure.
Phase 5 (P5-T7)	Active Server Selection Persistence via AppPreferencesRepository with Auto-Fallback Policy	Dedicated active_server storage file, complex favorites graph	Per SECURITY.md Section 3, activeServerId is an opaque identifier with None/Low sensitivity safe for SharedPreferences (key: brick.preferences.active_server_id). A reactive activeServerProvider resolves the active profile against the valid server list, falling back to the first valid profile when unselected or when the active profile is deleted (or null when empty), avoiding dangling ID references or crashes.
Phase 5 (P5-T8)	Real Connect/Disconnect Flow with Stream-Truth State, lastUsedAt Stamping & Clean Mid-Connection Switch	Optimistic UI state, in-place re-start without stopping previous tunnel	Enforces VpnEngine Invariant 1 (UI connection state renders exclusively from the connectionState stream, never from optimistic controller booleans). Primary toggle on active server card provides intuitive 1-tap connect/disconnect. Stamping lastUsedAt into ServerProfileRepository on accepted start dispatch records usage history without disrupting active tunnels on storage errors. Clean mid-connection switching calls engine.stop() before prepare() and start(newProfile), preventing VpnCommandRejectedBusy collisions. Surfaces all command rejections (permission denied, invalid config, busy, platform error) via ErrorMapper and AppFeedback.
(This table is appended to, never rewritten, as new major decisions are
made throughout the project.)

### 7.2 P5-T3 QR Scanner & Camera Permission Architecture

#### Package Evaluation Summary
- **`qr_code_scanner`**: Deprecated, relies on obsolete Android Camera 1 / Camera 2 APIs without CameraX support, unmaintained since 2022.
- **`zxing2` / manual camera pipelines**: Requires heavy manual frame piping and native image conversions; unnecessary maintenance surface.
- **`mobile_scanner` (Chosen)**: Official standard for modern Flutter barcode/QR scanning. Utilizes Android CameraX and ML Kit, with active maintenance, zero legacy native bridge dependencies, and clean lifecycle support.
- **`permission_handler` (Chosen)**: Standard cross-platform permission abstraction providing explicit distinction between `granted`, `denied` (retryable), and `permanentlyDenied` (requiring `openAppSettings()`).

#### Architectural Principles & Concurrency Control
1. **Single-Scan Debounce Lock**: Scanners produce continuous camera frames. On first valid non-empty scan event, a synchronous boolean flag (`_isProcessing = true`) engages before any async parsing or persistence to prevent duplicate server profile creation.
2. **Hermetic Testability**: Hardware camera dependencies and permission checks are fully isolated behind `CameraPermissionService` (injected via Riverpod) and an optional `scannerBuilder` on `QrScanScreen`. Automated widget tests exercise all 3 permission states and simulated QR inputs in milliseconds without physical device camera access.
3. **Zero Leaks**: Scanned raw payloads are treated as untrusted secrets per `SECURITY.md` and are never logged or reflected in UI error messages.

### 7.1 P5-T1 Storage Architecture & Schema Specification

#### Storage Engine Evaluation Summary
- **Isar:** Abandoned/stalled maintenance on modern Dart 3, requires complex native binaries and heavy codegen.
- **Hive:** Hive v2 is unmaintained; Hive v3/CE still stabilizing; lacks clean migration primitives.
- **Drift / SQLite3:** Heavy relational engine with SQLite C-bindings and boilerplate; unjustified for VPN client datasets (<500 profiles, <500 KB payload) that are naturally document/tree-structured.
- **Versioned Atomic JSON-File Store (Chosen):** Pure Dart logic using `dart:io` and `path_provider` application documents/support directory. Atomic write (`File.writeAsString` to temp file + `rename`) guarantees ACID-like durability against sudden process termination. In-memory cache ensures zero disk reads on normal UI queries.

#### P1-T3 Serialization Resolution
The P1-T3 design question is resolved in favor of the **fully-typed sealed class hierarchy** already in `core_domain`:
- Storage serializes `ServerProfile` instances via `toJson()` which includes the polymorphic `OutboundConfig.toJson()` (carrying the `'type'` discriminator matching the protocol scheme).
- Deserialization executes `readSingBoxOutboundJson` from `config_parser` to reconstitute the concrete `OutboundConfig` (`VlessOutbound`, `TrojanOutbound`, `ShadowsocksOutbound`, etc.).
- A storage envelope wraps all records with a top-level `"schema_version": 1`.

#### Top-Level Storage Envelope Schema
```json
{
  "schema_version": 1,
  "updated_at": "2026-10-31T02:00:00.000Z",
  "server_profiles": [
    {
      "id": "uuid-or-id",
      "name": "My Server",
      "config": {
        "type": "vless",
        "server": "example.com",
        "server_port": 443,
        ...
      },
      "added_at": "2026-10-31T02:00:00.000Z",
      "last_used_at": null,
      "subscription_id": null,
      "schema_version": 1
    }
  ],
  "subscriptions": [
    {
      "id": "sub-id",
      "url": "https://example.com/sub",
      "name": "Primary Subscription",
      "last_refreshed_at": "2026-10-31T02:00:00.000Z",
      "associated_server_ids": ["uuid-or-id"],
      "schema_version": 1
    }
  ],
  "broken_servers": {
    "broken-id": "Error reason message"
  }
}
```

#### SubscriptionMetadata Schema Specification
- `id`: Non-empty `String` identifier (UUID or unique local id).
- `url`: `String` (HTTP/HTTPS subscription endpoint). Sensitive; no `toString()` leak per `SECURITY.md`.
- `name`: `String` user-facing display label.
- `lastRefreshedAt`: Nullable `DateTime` timestamp of last successful update.
- `associatedServerIds`: Immutable `List<String>` tracking which server profiles belong to this subscription for sync/cleanup.
- `userInfo`: Optional `SubscriptionUserInfo` (upload, download, total, expire).
- `schemaVersion`: Integer schema version (currently `1`).

### 7.3 P5-T6 Server Management & Subscription Refresh Architecture

#### Full-Replace Subscription Refresh Diffing Policy
- **Background & Problem:** Subscription feeds (HTTP/HTTPS payloads containing Base64 or multi-line sing-box configs) rarely contain immutable cross-fetch server IDs. Remarks and IP endpoints can change between updates. Complex heuristic diffing (e.g. matching by host:port or fuzzy remark) introduces high risk of stale zombies, duplicated nodes, or phantom configuration mutations.
- **Diffing Policy:**
  - When manual refresh is triggered on a subscription, the endpoint is fetched and parsed via `SubscriptionFetcher`.
  - **Success Path:** If the fetch succeeds and produces at least 1 valid server configuration, all existing `ServerProfile`s associated with `subscription.id` are atomically deleted and replaced with the newly parsed profiles. `SubscriptionMetadata` is updated with the new `associatedServerIds`, new `lastRefreshedAt`, and latest `SubscriptionUserInfo` in a **single atomic disk write** (`replaceSubscriptionProfiles`).
  - **Failure / Zero-Valid Path:** If the network request fails or the payload yields 0 valid servers, the existing stored server profiles are **preserved completely untouched**, preventing transient network drops from wiping a user's working servers. A user-facing error message is surfaced via `AppFeedback.showError`.

### 7.4 P5-T8 Real Connect/Disconnect Flow Architecture

#### Stream-Driven Truth (VpnEngine Invariant 1)
- The primary Connect/Disconnect toggle button on `home_active_server_card` (`home_connect_toggle_button`) and the live status badge render their state exclusively from the `connectionStateProvider` stream (`Disconnected`, `Connecting`, `Connected`, `Disconnecting`, `Error`).
- Optimistic UI state transitions are strictly prohibited: tapping Connect awaits command acceptance from `VpnEngine.prepare()` and `VpnEngine.start(profile)`. If accepted, UI state remains untouched until the native engine stream emits an actual state transition.

#### Mid-Connection Server Switch Policy
- When the VPN tunnel is in `Connected` or `Connecting` state and the user requests connection to a different server profile (either by selecting a new active server or tapping Connect on another profile), `ConnectionController.connect` cleanly halts the active session via `await engine.stop()` before dispatching `engine.prepare()` and `engine.start(newProfile)`.
- This eliminates `VpnCommandRejectedBusy` race conditions and guarantees seamless switching between nodes without forcing the user to manually disconnect first.

#### lastUsedAt Timestamp Stamping & Fault Tolerance
- Upon successful dispatch of `engine.start(profile)` returning `VpnCommandAccepted`, `ConnectionController` asynchronously persists an updated profile with `lastUsedAt: DateTime.now().toUtc()` to `ServerProfileRepository` and invalidates `savedServersProvider`.
- Storage operations are wrapped in an isolated exception guard so that potential local storage failures or disk write delays never interrupt or terminate an established, healthy VPN tunnel.

## 8. Phase 6 — Traffic Stats & Live Logs Architecture

### 8.1 P6-T1 Traffic Stats Data Plumbing & Rate Calculation Architecture

#### Native Android Stats Plumbing & Audit (`packages/vpn_engine_android`)
- **Native Implementation Class:** `dev.brickvpn.harness.VpnEngineAndroidPlugin.PluginTrafficStatsEventsStreamHandler` in `packages/vpn_engine_android/android/src/main/kotlin/dev/brickvpn/harness/VpnEngineAndroidPlugin.kt`.
- **Pigeon Event Channel:** Registered under typed channel `dev.flutter.pigeon.vpn_engine_android.VpnEngineEventChannels.trafficStatsEvents` via `TrafficStatsEventsStreamHandler.register(messenger, trafficHandler)`.
- **Collection Mechanism & Polling Frequency:**
  - When the native `VpnStateMachine` enters `VpnState.Running`, `startPollingIfRunning(machine)` launches a Kotlin coroutine in plugin lifecycle `scope`.
  - While `isActive && machine.currentState is VpnState.Running`, it polls at a fixed 1 Hz interval (`delay(1000L)`).
  - Collects cumulative bytes via a two-tier strategy:
    1. First reads kernel network statistics `/sys/class/net/tun0/statistics/rx_bytes` and `/sys/class/net/tun0/statistics/tx_bytes`.
    2. Falls back to Android OS runtime statistics `android.net.TrafficStats.getUidRxBytes(Process.myUid())` and `android.net.TrafficStats.getUidTxBytes(Process.myUid())`.
  - Emits typed `TrafficStatsEvent(txBytes = tx, rxBytes = rx, epochMillis = System.currentTimeMillis())` directly through `sink.success(...)`.
  - Cancels immediately on tunnel termination (`onCancel` / `onServiceDestroyed`).
- **Structural Absence of Legacy Swallowed-Error Bug:**
  - The legacy prototype failed because it polled an external TCP `CommandClient` where socket connection failures were silently downgraded to warnings and masked by JavaScript-side state gates.
  - In Brick VPN, stats are collected in-process directly from the Linux kernel virtual network interface and Android OS process accounting. There is no external TCP socket or IPC daemon that can fail to connect or be swallowed.
- **Dart Platform Adapter:**
  - `AndroidVpnEngine` (`packages/vpn_engine_android/lib/src/android_vpn_engine.dart`) maps `TrafficStatsEvent` to domain `TrafficStats(txBytes, rxBytes, timestamp)` while enforcing Invariant 2 (stream errors on stats are absorbed cleanly without bubbling to connection state).

#### SessionTrafficMetrics State Model
- Immutable value entity (`apps/mobile/lib/features/connection/domain/entities/session_traffic_metrics.dart`) annotated with `@immutable` from `package:meta/meta.dart`, tracking:
  - `txBytes`: cumulative session upload bytes.
  - `rxBytes`: cumulative session download bytes.
  - `txBytesPerSec`: real-time upload speed in bytes per second.
  - `rxBytesPerSec`: real-time download speed in bytes per second.
  - `lastUpdated`: timestamp of latest snapshot calculation.
- Strictly adheres to `SECURITY.md` Section 4 by omitting `toString()` to prevent connection telemetry from leaking into system logs.

#### Delta Rate Calculation Invariants
- Enforced by `SessionTrafficMetricsCalculator` (`apps/mobile/lib/features/connection/domain/usecases/session_traffic_metrics_calculator.dart`):
  1. *First tick of a session:* instantaneous speeds `txBytesPerSec` and `rxBytesPerSec` are clamped to `0.0`, eliminating false initial speed spikes if the native counter begins with accumulated bytes.
  2. *Subsequent ticks:* throughput rates are computed as `(deltaBytes * 1000.0) / deltaMs`.
  3. *Zero-duration & clock-skew protection:* if `deltaMs <= 0` (duplicate timestamp or clock skew), rate is clamped to `0.0` (guaranteeing zero division prevention).
  4. *Counter-reset protection:* if `deltaBytes < 0`, rate is clamped to `0.0`.
  5. *Strict zero-NaN/Infinity guarantee:* output rates are guaranteed non-negative, finite numbers.

#### Lifecycle Synchronization & Session Reset
- `sessionTrafficMetricsProvider` (`apps/mobile/lib/features/connection/presentation/providers/session_traffic_metrics_provider.dart`) synchronizes with `connectionStateProvider`:
  - Subscribes to `engine.trafficStats` in `build()`.
  - Ignores duplicate `Connected` -> `Connected` transitions (e.g. app lifecycle resume health-checks) so the baseline is never wiped out mid-session.
  - When transitioning from non-`Connected` to `Connected`: resets `_calculator` baseline and zeros state for a clean session.
  - When transitioning to `Disconnected`, `Connecting` (new session starting), or `Error`, resets `_calculator` baseline and zeros state (`SessionTrafficMetrics.zero`) to prevent stale data bleeding across sessions.
  - When transitioning to `Disconnecting`, clamps rates to `0.0` while preserving session-cumulative byte totals until `Disconnected`.

#### Failure Domain Isolation (VpnEngine Invariant 2)
- The traffic stats pipeline is strictly decoupled from the connection state pipeline:
  - Any error on `engine.trafficStats` stream is caught and absorbed gracefully (rates clamped to `0.0`, cumulative bytes retained).
  - Stream errors on stats never crash the UI, never disrupt `sessionTrafficMetricsProvider`, and never affect `connectionStateProvider`.

#### Formatting Utilities (TrafficFormatter)
- Zero-dependency binary IEC unit formatter (1024 basis) in `apps/mobile/lib/features/connection/domain/formatters/traffic_formatter.dart`:
  - `formatBytes(bytes)` -> `0 B`, `1.5 KiB`, `2.0 MiB`, `1.2 GiB`.
  - `formatSpeed(bytesPerSec)` -> `0 B/s`, `512 B/s`, `12.4 KiB/s`, `3.5 MiB/s`.
  - Defensively clamps negative values, `NaN`, and `Infinity` to safe zero representations.
  - Replaces ad-hoc string formatting in `ThroughputReadout`, preserving 100% test compatibility.

### 8.2 P6-T2 Traffic Stats UI Display & Fine-Grained `.select()` Rebuild Isolation

#### Rebuild Isolation Architecture
- The native stats engine ticks at 1 Hz during an active VPN session. Naively watching `sessionTrafficMetricsProvider` or `trafficStatsProvider` at the screen or card level would trigger continuous high-frequency widget rebuilds, causing UI jank and battery drain.
- `ThroughputReadout` (`apps/mobile/lib/features/connection/presentation/widgets/throughput_readout.dart`) enforces strict rebuild isolation:
  1. Neither `HomeScreen` nor `ThroughputReadout` watches the full metrics state.
  2. `ThroughputReadout` watches only `sessionTrafficMetricsProvider.select((m) => m.hasError)` to render `'connection.traffic_unavailable'` on stream faults (Invariant 2).
  3. `_CumulativeTotalsText` watches `sessionTrafficMetricsProvider.select((m) => (TrafficFormatter.formatBytes(m.txBytes), TrafficFormatter.formatBytes(m.rxBytes)))`.
  4. `_InstantaneousSpeedText` watches `sessionTrafficMetricsProvider.select((m) => (TrafficFormatter.formatSpeed(m.txBytesPerSec), TrafficFormatter.formatSpeed(m.rxBytesPerSec)))`.
  5. Selecting the **formatted string tuple** leverages Dart record equality: if raw byte counters change by an amount that does not alter the displayed text (e.g. `1.0 MiB` -> `1.0 MiB`), Riverpod short-circuits and prevents even the leaf `Text` widget from rebuilding.
  6. Verified by automated widget test in `traffic_stats_plumbing_test.dart` confirming zero parent or sibling widget rebuilds across continuous traffic ticks.

### 8.3 P6-T3 Live Log Capture, Structured `LogEntry` & Bounded Ring Buffer Architecture

#### Native Android Log Stream Plumbing & Audit (`packages/vpn_engine_android`)
- **Native Log Source:** sing-box/libbox Go engine invokes `PlatformInterface.writeLog(log: String)` in `packages/vpn_engine_android/android/src/main/kotlin/dev/brickvpn/harness/vpn/LibboxPlatformInterface.kt`.
- **Global Consumer Forwarding:** `LibboxPlatformInterface.writeLog` writes to Android logcat (`Log.i("LibboxPlatformInterface", "libbox: $log")`) and routes each raw string through `onLogReceived(log)`. `LibboxTunnelEngine.globalLogConsumer` receives this callback.
- **Platform EventChannel Registration:** In `dev.brickvpn.harness.VpnEngineAndroidPlugin.onAttachedToEngine`, an `EventChannel` named `dev.brickvpn.harness/log_events` is registered with `PluginLogEventsStreamHandler`. `LibboxTunnelEngine.globalLogConsumer` dispatches each line directly to `logHandler.onLog(log)` (`sink?.success(log)`).
- **Dart Ingestion:** `AndroidVpnEngine.logEvents` maps `EventChannel('dev.brickvpn.harness/log_events').receiveBroadcastStream()` to `Stream<String>`.

#### Structured `LogEntry` & `LogLevel` Domain Model
- `LogEntry` (`apps/mobile/lib/core/logging/log_entry.dart`) is an immutable, structured representation keeping log fields distinct:
  - `timestamp: DateTime` (parsed UTC timestamp or fallback timestamp).
  - `level: LogLevel` enum (`trace`, `debug`, `info`, `warning`, `error`, `fatal`).
  - `message: String` (clean message payload stripped of timestamp, level, and source prefixes).
  - `source: String?` (subsystem or component tag, e.g. `'router'`, `'tun'`, `'dns'`).
  - `raw: String` (original unparsed string preserved for debugging and text display).
- **Deterministic Parser (`LogEntry.parseEngineLine`):**
  - Transparently parses structured JSON lines (sing-box JSON format: `{"time":..., "level":..., "msg":..., "tag":...}`).
  - Parses sing-box standard lines with timezone offsets (e.g. `+0000 2026-11-05 12:00:00 INFO [inbound] starting`).
  - Parses standard bracketed or level-word log formats (`[WARN] ...`, `ERROR: ...`, `level=info`).
  - Safely falls back to `LogLevel.info` and fallback timestamp for plain text lines.

#### Bounded In-Memory Ring Buffer (`LogBuffer`)
- **Memory Bounding & O(1) Eviction:** `LogBuffer` (`apps/mobile/lib/core/logging/log_buffer.dart`) wraps a `ListQueue<LogEntry>` with a strict capacity bound (default `300` entries per P6-T3 architecture, synchronized with `LogManager.maxBufferSize`). When the queue reaches capacity, `removeFirst()` evicts the oldest entry in $O(1)$ time, guaranteeing that long-running VPN sessions cannot cause unbounded memory growth or OOM crashes.
- **Stress-Tested Bounding:** Verified by automated stress test emitting 5,000 log lines into a capacity-300 buffer, retaining exactly the newest 300 entries (`#4701` through `#5000`) in strict chronological sequence (and custom capacity buffers like 500 retaining `#4501` through `#5000`).

#### Burst Coalescing & Stream Fault Resilience
- **Microtask Burst Coalescing:** High-frequency bursts (e.g. 1,000 log lines emitted in a tight loop during handshake or routing table setup) are enqueued synchronously into `LogBuffer`, while UI state notification is scheduled via `scheduleMicrotask`. Multiple log arrivals within the same event-loop turn trigger exactly one consolidated UI state emission, preventing UI thread saturation and eliminating dropped frames.
- **Single Subscription & Stream Error Resilience:** `LogManager` (`apps/mobile/lib/core/logging/log_manager.dart`) is the single subscriber to `engine.logEvents`. Stream errors on `engine.logEvents` are captured and absorbed by `onError(..., cancelOnError: false)` without crashing the app, without terminating the subscription, and without disturbing the VPN connection.
- **Buffer Clearance (`clear()`):** `LogManager.clear()` atomically flushes both the string buffer and structured ring buffer, truncates `brick_vpn_live.log`, and immediately notifies listeners.

#### Mandatory Phase 8 Log Redaction Known Limitation Flag
- **KNOWN LIMITATION (DEFERRED TO PHASE 8):** In Phase 6, live log output captured from the native engine arrives without sensitive data scrubbing. Engine logs may contain sensitive information, including server hostnames/IP addresses, port numbers, routing destinations, or authentication credentials depending on log verbosity. Full structured-field redaction and free-text masking are explicitly deferred to **Phase 8 (P8-T2 — Log Redaction)** per the project roadmap.
- Keeping log entries as structured `LogEntry` records in P6-T3 directly enables Phase 8 to inspect and redact sensitive fields (e.g. redacting known credential fields) cleanly without relying exclusively on fragile regular expressions over free text.

### 8.4 P6-T4 Live Log Viewer Screen Architecture

#### Screen Structure & Route Unification
- **Single Source of Truth:** `LiveLogsScreen` (`apps/mobile/lib/features/settings/presentation/screens/live_logs_screen.dart`) provides the canonical UI for inspecting real-time diagnostic engine logs.
- **Unified Navigation Routes:** Both `/settings/logs` (via `SettingsScreen`) and the bottom navigation `/logs` branch (`LogsScreen` at `apps/mobile/lib/features/logs/presentation/screens/logs_screen.dart`) delegate to `LiveLogsScreen`, guaranteeing identical viewer behavior and state synchronization across both entry points.
- **ConsumerStatefulWidget Lifecycle:** Manages a single `ScrollController` instance that is cleanly disposed in `dispose()` to prevent memory leaks.

#### Virtualized Lazy Rendering (`ListView.builder`)
- **Memory & Render Virtualization:** Driven by `ListView.builder` bound to `structuredLogEntriesProvider` (up to 300 entries in the bounded ring buffer).
- **Lazy Mounting:** Verified by automated widget test that when 300 entries are present, only visible viewport items are mounted; offscreen items (e.g., tile #0 at the top) are unmounted by Flutter's render viewport, eliminating jank and OOM risks during high-throughput logging.
- **Semantic Keys:**
  - Each list tile is tagged with `ValueKey<String>('log_entry_tile_$index')`.
  - Each log level badge is tagged with `ValueKey<String>('log_level_badge_${entry.level.name}_$index')`.

#### Level-Based Visual Differentiation
- **Distinct Visual Badges:** Every log entry renders a dedicated badge with uppercase level text (`INFO`, `WARN`, `ERROR`, `FATAL`, `DEBUG`, `TRACE`).
- **Semantic Color Palette:**
  - `LogLevel.fatal` & `LogLevel.error`: theme `colorScheme.error` with translucent error container background.
  - `LogLevel.warning`: high-contrast amber/orange (`Colors.orange.shade800`).
  - `LogLevel.info`: theme `colorScheme.primary`.
  - `LogLevel.debug` & `LogLevel.trace`: theme `colorScheme.outline` / muted secondary.
- **Structured Metadata Alignment:** Displays deterministic UTC timestamp (`HH:mm:ss`), optional component tag (`[source]`), and clean deduplicated message payload (`SelectableText(entry.message.isNotEmpty ? entry.message : entry.raw)`).

#### Auto-Scroll, Pause Detection & Manual Resume
- **Auto-Scroll Behavior:** Default state has `_autoScrollEnabled = true`. On initial build and whenever new entries arrive (monitored via `ref.listen(structuredLogEntriesProvider)`), `_scrollController.jumpTo(maxScrollExtent)` is invoked post-frame to keep the latest log line visible.
- **Scroll-Up Pause Detection:** A `NotificationListener<ScrollNotification>` inspects `metrics.maxScrollExtent - metrics.pixels`. When `distanceToBottom > 48.0` (indicating the user has scrolled up to inspect previous logs), `_autoScrollEnabled` is set to `false`.
- **"Jump to Latest" Affordance:** When auto-scroll is paused, an overlay `FloatingActionButton.extended` appears (`key: const ValueKey<String>('logs_jump_to_latest_button')`, localized `logs.jump_to_latest`).
- **Auto-Scroll Resume:** Tapping the jump button immediately jumps to `maxScrollExtent` and sets `_autoScrollEnabled = true`. Alternatively, scrolling down manually back to `distanceToBottom <= 12.0` automatically resumes auto-scroll and dismisses the jump button.

#### Atomic Clear Buffer Action
- **AppBar Action:** An `IconButton` (`key: const ValueKey<String>('logs_clear_button')`, localized tooltip `logs.clear_tooltip`) in `AppBar.actions` calls `ref.read(logManagerProvider.notifier).clear()`.
- **Instant Reactive Reset:** Atomically flushes both string and structured ring buffers, resets the live log file, and updates the screen to render the localized empty state (`settings.no_logs`: "No log entries yet").

### 8.5 P6-T5 Log Export / Copy Architecture & Privacy Safeguard

#### Copy-to-Clipboard Action & Disabled State
- **AppBar Integration:** An `IconButton` (`key: const ValueKey<String>('logs_copy_button')`, localized tooltip `logs.copy_tooltip`) sits in `LiveLogsScreen`'s `AppBar.actions`.
- **Empty Buffer Guard:** When `entries.isEmpty`, `onPressed` is set to `null` (disabling the action) to prevent accidental clipboard overwrites when no logs exist.

#### Mandatory Non-Dismissible-by-Accident Privacy Warning Dialog
- **Modal Security Gate:** Before any log data is written to the system clipboard, `_handleCopyLogs` displays an `AlertDialog` (`key: const ValueKey<String>('logs_privacy_warning_dialog')`).
- **Non-Dismissible Barrier (`barrierDismissible: false`):** Tapping outside the dialog or on the background barrier does not dismiss it, preventing users from bypassing or accidentally clearing the warning.
- **Clear Privacy Disclosure:** Warns the user explicitly that logs may contain sensitive connection details (server addresses, ports, or routing paths) and reminds them to review before public sharing pending full Phase 8 automated redaction (`P8-T2`).
- **User Actions:**
  - `TextButton` (`key: const ValueKey<String>('logs_copy_cancel_button')`, localized `logs.copy_cancel`): dismisses the modal with `false` and leaves the system clipboard completely untouched.
  - `FilledButton` (`key: const ValueKey<String>('logs_copy_confirm_button')`, localized `logs.copy_confirm`): dismisses the modal with `true` to initiate the copy sequence.

#### Formatted Export Payload & Feedback Notification
- **Deterministic Structured Formatting:** Each buffered entry is serialized into a newline-separated format:
  `${entry.timestamp.toUtc().toIso8601String()} [${entry.level.label}]${entry.source != null ? ' [${entry.source}]' : ''} ${entry.message.isNotEmpty ? entry.message : entry.raw}`.
- **Clipboard Delivery:** Written asynchronously to the OS clipboard via `Clipboard.setData(ClipboardData(text: payload))`.
- **User Feedback:** Displays a transient confirmation snackbar via `AppFeedback.showInfo(context, 'logs.copied_to_clipboard'.tr())`.

#### Documented File-Export Decision (P6-T5 Criterion 3)
- In accordance with P6-T5 Scope and Criterion 3, `P6-T5` ships Copy-to-Clipboard of the entire buffer as the primary, zero-extra-dependency export mechanism. Platform native share-sheet file export (via `share_plus`) is explicitly deferred and recorded as a documented future enhancement to avoid adding external binary dependencies before Phase 11.

### 8.6 P6-T6 Connection Session Info Panel & Duration Timer Architecture

#### Glanceable Session Consolidation
- **Location:** Mounted on `HomeScreen` directly beneath `ThroughputReadout` and above the active server card.
- **Card Container:** Rendered inside a `Card` (`key: const ValueKey<String>('session_info_panel')`) styled consistently with Material Design 3 surface tokens.
- **Sub-Component Architecture:** To guarantee strict rebuild isolation, `SessionInfoPanel` delegates rendering to three independent leaf `ConsumerWidget`s:
  1. `_ActiveServerText`: Renders the active server name and protocol type (`key: const ValueKey<String>('session_server_text')`), or fallback "None selected".
  2. `_SessionStatusText`: Renders the engine state from `connectionStateProvider` (`key: const ValueKey<String>('session_status_text')`).
  3. `_SessionDurationText`: Renders the formatted elapsed session duration (`key: const ValueKey<String>('session_duration_text')`).

#### Reactive Duration Tracking (`sessionDurationProvider`)
- **1 Hz Deterministic Ticking:** Driven by an in-memory `Timer.periodic(const Duration(seconds: 1), ...)` inside `SessionDurationNotifier`.
- **Authoritative Stream Synchronization:** Listens to `connectionStateProvider`:
  - When the engine transitions to `Connected`, duration resets to `Duration.zero` and starts the 1-second periodic timer.
  - Idempotent against consecutive `Connected` emissions (e.g. app lifecycle resume resyncs) so the running timer is never reset mid-session.
  - Cancels timer and resets duration to `Duration.zero` upon transitioning to `Disconnecting`, `Disconnected`, `Connecting`, or `Error`.
  - Disposes the timer cleanly in `ref.onDispose`.

#### Zero-Dependency Duration Formatting (`TrafficFormatter.formatDuration`)
- Formats standard `Duration` instances into `HH:MM:SS` notation (e.g., `00:00:00`, `01:05:30`).
- Defensive clamping: Clamps negative durations to `00:00:00`. Preserves hours >= 100 without truncation (e.g. `100:00:00`).

#### Rebuild Isolation
- `_SessionDurationText` watches `sessionDurationProvider.select(TrafficFormatter.formatDuration)`.
- 1 Hz timer ticks trigger rebuilds *only* on `_SessionDurationText`. Parent `SessionInfoPanel`, `HomeScreen`, and sibling widgets (`_ActiveServerText`, `_SessionStatusText`, `ConnectionStateBadge`, `ThroughputReadout`) remain completely untouched.

### 8.7 P6-T7 Phase 6 End-to-End User Journey & Two-Cycle Lifecycle Architecture

#### Continuous End-to-End Integration Test (`phase6_e2e_journey_test.dart`)
- **Real App Shell:** Tests the complete widget hierarchy (`MyApp` -> `AppShell` -> `HomeScreen` / `LogsScreen`) without mocking presentation-layer widgets or riverpod providers other than native engine platform channel interfaces (`FakeVpnEngine`).
- **Two Full Connect/Disconnect Cycles:** Proves that state resets, stream subscriptions, timers, and ring buffers survive repeated connection transitions without memory leaks, stale accumulator leakage, or state pollution.

#### Multi-Cycle Lifecycle & State Reset Guarantees
1. **Resting Baseline (Disconnected):**
   - `SessionInfoPanel` displays active server profile name/protocol, `Tunnel: Disconnected`, and `Duration: 00:00:00`.
   - `ThroughputReadout` displays zero cumulative bytes (`0 B up / 0 B down`) and zero transfer rates (`Speed: ↑ 0 B/s · ↓ 0 B/s`).
2. **First Connected Cycle (P6-T1 through P6-T6):**
   - Connect intent dispatches through `ConnectionController` to native engine.
   - Authoritative `Connected` event resets duration to `00:00:00` and starts 1 Hz periodic timer (advances cleanly to `00:00:04`).
   - First `TrafficStats` snapshot clamps rate to 0 B/s to eliminate false initial delta spikes; subsequent snapshots compute exact delta transfer speeds and cumulative totals.
   - Structured native logs arrive over `engine.logEvents` and stream into `LogManager`'s bounded ring buffer.
   - Navigating to the `Logs` tab renders structured log items with level badges (`[INFO]`, `[WARN]`, `[ERROR]`).
   - Copy action invokes non-dismissible privacy warning dialog (`barrierDismissible: false`); barrier taps are ignored; confirmation copies serialized logs to clipboard with user feedback; clear action resets buffer.
   - Disconnect transitions through `Disconnecting` -> `Disconnected`, stopping the duration timer and resetting session duration and speed readouts to zero.
3. **Second Connected Cycle (Baseline Invariant Verification):**
   - Reconnect transitions cleanly to `Connecting` -> `Connected`.
   - The first `TrafficStats` snapshot in Cycle 2 verifies the previous cycle's baseline is wiped: initial delta is clamped to 0 B/s, preventing false spikes across reconnect boundaries.
   - Second snapshot computes accurate delta speed.
   - Session duration timer starts fresh from `00:00:00` (advancing to `00:00:03`), proving no lingering timer tasks or stale offsets leak across sessions.
   - Emitting a fresh log entry verifies that previously cleared Cycle 1 entries do not reappear.
   - Final clean disconnect restores resting baseline.

## 9. Phase 7 — Stability & Lifecycle Hardening Architecture

### 9.1 P7-T1 Auto-Reconnect on Network Change & Drop Recovery Architecture

#### State Machine & State Hierarchy (`AutoReconnectState`)
The auto-reconnect coordinator (`AutoReconnectNotifier`, managed via `autoReconnectProvider`) enforces a deterministic state machine modeled with a sealed class hierarchy:
1. **`AutoReconnectIdle`:** Resting state. Reconnection logic is inactive (either disconnected or successfully connected).
2. **`AutoReconnectWaitingForNetwork`:** Device has completely lost physical network connectivity (`ConnectivityResult.none`). Reconnect backoff timer is paused until connectivity returns.
3. **`AutoReconnectBackoff` (`attempt`, `delay`, `targetProfile`):** Scheduled backoff delay before triggering reconnect. Displays retry countdown and attempt badge in `SessionInfoPanel`.
4. **`AutoReconnectInFlight` (`attempt`, `targetProfile`):** Active dispatch of tunnel teardown (`engine.stop()`) followed by connection initiation (`engine.start(profile)`).
5. **`AutoReconnectExhausted` (`attemptsTaken`, `targetProfile`):** Maximum retry limit (5 attempts) reached without establishing connection. Aborts auto-reconnect sequence, logs diagnostic error, and prompts user intervention.

#### User-Intent Invariant (`_userSessionActive`)
- **Strict User-Intent Tracking:** Auto-reconnect operates strictly within user-intended active sessions. When a user explicitly taps "Connect", `onUserInitiatedConnect(profile)` marks `_userSessionActive = true`. When the user explicitly taps "Disconnect", `onUserInitiatedDisconnect()` sets `_userSessionActive = false`.
- **Zero Spontaneous Connections:** Network transitions (Wi-Fi <-> Mobile, airplane mode toggle, interface up/down) occurring when `_userSessionActive == false` will **never** trigger tunnel initialization.
- **Immediate Cancellation:** If a user taps "Disconnect" at any point during backoff delay, network waiting, or in-flight reconnect, the sequence is cancelled immediately, all timers are disposed, and state reverts to `AutoReconnectIdle`.

#### Exponential Backoff Policy & Single-Flight Flap Debounce
- **Exponential Backoff (`AutoReconnectPolicy`):**
  - Base delay: `1.0s`
  - Multiplier: `2.0` (delays: 1s, 2s, 4s, 8s, 16s)
  - Maximum cap: `30.0s`
  - Maximum attempts: `5`
- **Flap Debounce (300ms):** Connectivity changes are guarded with a 300ms debounce timer. Rapid network flapping (e.g. Wi-Fi RSSI threshold bounces) does not trigger redundant reconnect cascades or concurrent dispatch storms.
- **Offline Pause / Resume:** When transitioning to `ConnectivityResult.none`, any pending backoff timer is cancelled and the coordinator enters `AutoReconnectWaitingForNetwork`. As soon as physical network returns (`wifi`, `mobile`, `ethernet`, or `vpn`), the backoff attempt is resumed.

#### Cross-Engine Invariants (Phase 1 & Phase 3 Integration)
- **Authoritative Stream Driven Truth (VpnEngine Invariant 1):** `connectionStateProvider` remains the single source of truth for tunnel status. `AutoReconnectNotifier` listens to engine transitions (`Disconnected`, `Error`) to detect unexpected drops while `_userSessionActive` is true.
- **Idempotent Teardown:** Prior to launching a new tunnel via `engine.start()`, `engine.stop()` is invoked and completed to ensure stale native socket resources, routing tables, and TUN file descriptors are completely released.
- **Stream Fault Resilience:** `VpnEngine` stream errors or unexpected disconnects invoke recovery handling without crashing the reactive provider container.

#### Diagnostic Logging & Metrics Synchronization
- **Diagnostic Logging (`LogManager.recordDiagnostic`):** Auto-reconnect lifecycle transitions (drop detected, reconnect scheduled, in-flight dispatch, cancellation, retry exhaustion) are logged into the Phase 6 ring buffer as sanitized UTC-stamped INFO/WARN/ERROR entries containing zero sensitive tokens, keys, or credentials.
- **Phase 6 Metrics Synchronization:** When a connection drops and enters auto-reconnect, `sessionDurationProvider` and `sessionTrafficMetricsProvider` reset to zero (`00:00:00` and `0 B/s`). When auto-reconnect successfully establishes the connection (`Connected`), duration and delta rate metrics begin anew, maintaining zero-accumulator leakage across reconnect cycles.

#### Android Native Network Callback & Underlying Network Handoff
- **Native Network Observation:** The Android platform monitors physical and virtual network availability via `ConnectivityManager.NetworkCallback` (`onAvailable`, `onLost`, `onCapabilitiesChanged`). On the Flutter side, this is consumed through `ConnectivitySource` (`connectivity_plus`), debounced at 300ms to eliminate transient flapping.
- **Underlying Network Hand-off in `VpnService`:** On Android, `VpnService.setUnderlyingNetworks(Network[])` allows the operating system to bind the TUN tunnel to an active Wi-Fi or cellular network interface. When transitioning between Wi-Fi and Cellular (or vice versa), the physical network route drops. To ensure that sing-box/libbox internal socket state machines do not hang or retain stale routes, `AutoReconnectNotifier` performs an active teardown (`engine.stop()`) followed by a clean rebuild (`engine.start()`), guaranteeing clean socket re-binding.

#### Re-Entrancy, Server Switching & Start Rejection Hardening (P7-T1 Remediation)
- **Re-Entrancy Guard (`_isStoppingForReconnect`):** In `_executeReconnect()`, invoking `await engine.stop()` triggers an asynchronous `Disconnecting -> Disconnected` sequence from the native engine. Guarding this invocation with `_isStoppingForReconnect = true` and checking `if (_isExecuting || _isStoppingForReconnect) return;` in the `connectionStateProvider` listener prevents the engine teardown event from triggering `_handleUnexpectedDrop()`, completely eliminating double increment of `_currentAttempt` and duplicate overlapping timer cascades.
- **Mid-Connection Server Switch (`D3`):** In `ConnectionController.connect(profile)`, when switching between servers while active, `onUserInitiatedDisconnect()` is dispatched to both `autoReconnectProvider` and `killSwitchProvider` *prior* to `await engine.stop()`. This ensures that tearing down the previous server is recognized as an intentional user action rather than an unexpected failure.
- **Start Rejection Clean Disarming (`D4`):** If `engine.prepare()` or `engine.start(profile)` returns a rejected outcome (`VpnCommandRejectedInvalidConfig`, `VpnCommandRejectedPermissionDenied`, or `VpnCommandFailed`), `onUserInitiatedDisconnect()` is immediately invoked on both coordinators, ensuring that `_userSessionActive` is cleanly cleared and neither coordinator is left stranded in an armed or retrying state.

#### State Machine Cross-Reference & Non-Recoverable Errors
`AutoReconnectState` operates at the presentation and session-orchestration level, sitting above the core and native state machines:

| `AutoReconnectState` | Phase 1 `core_domain.ConnectionState` | Phase 3 `VpnNativeState` | Behavior Description |
| :--- | :--- | :--- | :--- |
| `AutoReconnectIdle` | `Connected` / `Disconnected` | `running` / `idle` / `stopped` | Normal operating baseline; auto-reconnect is inactive. |
| `AutoReconnectWaitingForNetwork` | `Disconnected` / `Error` | `stopped` / `idle` / `error` | Physical network is absent (`ConnectivityResult.none`); retries on hold. |
| `AutoReconnectBackoff` | `Disconnected` / `Error` | `stopped` / `idle` / `error` | Backoff delay timer active (1s, 2s, 4s, 8s, 16s). |
| `AutoReconnectInFlight` | `Connecting` / `Disconnecting` | `stopping` -> `preparing` -> `starting` | Actively stopping stale tunnel and starting fresh tunnel. |
| `AutoReconnectExhausted` | `Disconnected` / `Error` | `stopped` / `error` | Retry budget (5 attempts) exhausted; surfaced clearly in UI. |

- **Non-Recoverable Error Guard:** `Error(InvalidConfig)` and `Error(PermissionDenied)` (and corresponding engine command rejections `VpnCommandRejectedInvalidConfig`, `VpnCommandRejectedPermissionDenied`) represent deterministic user or system configuration errors that cannot be healed by retrying. When encountered, `AutoReconnectNotifier` immediately clears `_userSessionActive`, cancels pending timers, and transitions to `AutoReconnectIdle`, preventing futile infinite retry loops. Transient errors (`PlatformError`, `UnexpectedDisconnect`, unexpected `Disconnected`) trigger backoff recovery.

### 9.2 P7-T2 Kill Switch Architecture & Leak-Protection Invariants

#### State Hierarchy & Architecture (`KillSwitchState`)
The application kill switch coordinator (`KillSwitchNotifier`, managed via `killSwitchProvider`) enforces a deterministic state machine modeled with a sealed class hierarchy:
1. **`KillSwitchInactive`:** Kill switch is idle/disengaged. Occurs when disabled in preferences, on initial app launch before a tunnel is started, or after a clean user-initiated disconnect. Internet traffic outside the VPN is not blocked by the application.
2. **`KillSwitchArmed`:** Kill switch is active and protecting traffic. Occurs when enabled in preferences AND the user-intended VPN tunnel is actively `Connected` (or establishing connection).
3. **`KillSwitchBlocking(reason)`:** Kill switch is actively blocking unprotected internet traffic to prevent IP/DNS leaks. Engages whenever the tunnel is down while a user session was intended.

#### Complete Risk Window Coverage
The kill switch explicitly covers three critical leak-risk windows:
1. **Unexpected Mid-Session Drops:** Engine emits `Error` (e.g. `PlatformError`, unexpected socket abort) or unexpected `Disconnected` while `_userSessionActive == true`.
2. **Auto-Reconnect Windows:** Spans the entire `P7-T1` recovery cycle, including `AutoReconnectWaitingForNetwork` (offline/airplane mode), `AutoReconnectBackoff` (exponential retry countdown), and `AutoReconnectInFlight` (tunnel teardown and rebuild).
3. **Post-Retry Exhaustion:** When auto-reconnect retry limits are reached (`AutoReconnectExhausted`), the kill switch remains in `KillSwitchBlocking` until the user takes explicit action (taps unblock/disconnect or disables the kill switch toggle), guaranteeing that traffic is never silently leaked after failed retries.

#### Critical Safety Invariant: Zero False Blocks on User Disconnect
- **Clean Disconnect Transitions:** When the user taps "Disconnect" (`ConnectionController.disconnect()`) or taps the banner unblock action (`kill_switch_unblock_button`), `KillSwitchNotifier.onUserInitiatedDisconnect()` is invoked *prior* to dispatching `engine.stop()`.
- **Immediate Disengagement:** This marks `_userSessionActive = false` and transitions the kill switch directly from `KillSwitchArmed` to `KillSwitchInactive`. When the engine subsequently emits `Disconnecting` and `Disconnected`, the kill switch recognizes the intentional stop and never enters `KillSwitchBlocking`.

#### UI Warning Banner & Unblock Affordance
- **High-Visibility Banner (`kill_switch_blocking_banner`):** Displayed prominently on `SessionInfoPanel` / `HomeScreen` during `KillSwitchBlocking`, featuring `Icons.shield_outlined`, localized title `"Kill Switch Active — Traffic Blocked"`, and explanatory body text.
- **Unblock Button (`kill_switch_unblock_button`):** Provides a direct affordance labelled `"Disconnect & Unblock"` that dispatches `ConnectionController.disconnect()`, immediately cancelling pending auto-reconnect timers, returning kill switch to `KillSwitchInactive`, and unblocking device traffic.

#### Native Android `VpnService` Routes, Fail-Closed Lockdown & OS Precedence
- **Native Fail-Closed OS Lockdown (`D1`):** In addition to the UI blocking banner, `kill_switch_provider.dart` integrates directly with the native layer via `KillSwitchPlatformBridge` invoking the `'dev.brickvpn.harness/kill_switch'` MethodChannel method `'setLockdownBlocking'`. When entering `KillSwitchBlocking` (during unexpected drops or auto-reconnect backoff), `BrickVpnService.setLockdown(true)` establishes a dedicated lockdown TUN descriptor with catch-all routes (`0.0.0.0/0` and `::/0`) and no forwarding loopback, completely blackholing non-VPN cleartext traffic at the OS kernel level. When the user disconnects or the tunnel recovers (`Connected`), `setLockdownBlocking(false)` releases the lockdown TUN descriptor.
- **In-Session Settings Toggle Reactivity (`D5`):** Enabling the Kill Switch toggle in `SettingsScreen` while a VPN session is already active immediately inspects the current engine and auto-reconnect state. If `Connected`, it transitions directly to `KillSwitchArmed`; if currently dropped or reconnecting, it transitions directly to `KillSwitchBlocking` and engages native OS lockdown blocking.
- **Android OS Always-On VPN Precedence:** Android OS provides an independent, kernel-enforced system setting: **"Always-on VPN"** with **"Block connections without VPN"** (Settings > Network & internet > VPN). When enabled at the OS level, the Linux kernel drops all non-TUN traffic globally, taking strict precedence over application-level states.

#### Sanitized Diagnostic Logging
All kill switch lifecycle transitions are stamped in UTC and recorded in `LogManager` using sanitized messages:
- Armed: `"KillSwitch armed."`
- Blocking: `"KillSwitch actively blocking unprotected traffic."`
- Disengaged: `"KillSwitch disengaged."`
Zero private keys, tokens, credentials, or raw platform exception traces are ever logged.

### 9.3 P7-T3 — DNS Correctness, Bootstrap Deadlock & IP-SNI Hardening Architecture

#### Zero Remote Rule-Set Downloads on Startup
In legacy prototypes, referencing remote `rule_set` URLs (such as `raw.githubusercontent.com` or external geoip/geosite databases) during tunnel initialization caused tunnel startup to freeze indefinitely under unstable, throttled, or censored network conditions. In Brick VPN, the sing-box runtime configuration generated by `PigeonVpnApiImpl.kt` contains **zero** remote `rule_set` entries or blocking external asset fetches. Tunnel startup is completely local, hermetic, and deterministic.

#### Circular DNS Bootstrap Deadlock Prevention
When an outbound proxy configuration uses a domain hostname (e.g. `node.example.com`), sing-box must resolve the IP address of `node.example.com` before the proxy connection can be initiated. If the DNS resolver is set to detour through the proxy itself, a circular deadlock occurs: the proxy cannot connect until the domain is resolved, and the domain cannot be resolved until the proxy is connected.
Brick VPN solves this with a dual-resolver architecture in sing-box:
1. **`dns-direct` (Bootstrap Resolver):** Configured with `"tag": "dns-direct"`, `"address": "1.1.1.1"`, and `"detour": "direct-out"`. A dedicated DNS rule (`"outbound": ["any"] -> "server": "dns-direct"`) routes all outbound server endpoint resolutions directly through the underlying network interface.
2. **`dns-remote` (Encrypted Tunnel Resolver):** Configured with `"tag": "dns-remote"`, `"address": "tcp://1.1.1.1"`, and `"detour": outboundTag` (with `"final": "dns-remote"`). All user and client DNS queries originating from the TUN interface are routed strictly through the encrypted proxy tunnel.

#### Strict TUN DNS Hijack & Leak Prevention
To eliminate DNS leakage across the device:
1. **TUN Inbound Hardening:** The TUN inbound descriptor sets `"auto_route": true` and `"strict_route": true`. `strict_route` forces the Android kernel routing tables to drop any traffic attempting to bypass the virtual interface.
2. **Port-53 Hijacking:** The route rules include `{"protocol": "dns", "action": "hijack-dns"}`. All UDP/TCP DNS queries on port 53 are captured into sing-box's internal DNS router, guaranteeing that third-party apps or hardcoded DNS addresses (e.g. `8.8.8.8`) cannot leak outside the encrypted VPN tunnel.

#### Bounded Startup Timeout
In `BrickVpnService.kt`, the tunnel initialization call `engine.start(pfd.fd, configJson)` is wrapped in a coroutine `withTimeout(15_000L)`. If a hostile network silently blackholes handshake packets without resetting the TCP connection, the startup sequence will abort after 15 seconds and transition cleanly to `VpnState.Error`, allowing `AutoReconnectNotifier` to initiate backoff rather than leaving the app hanging in `Starting` forever.

#### RFC 6066 IP-Literal SNI Hardening (`SingBoxOutboundSerializer`)
Per RFC 6066 Section 3, literal IPv4 and IPv6 addresses are not valid values for the TLS Server Name Indication (SNI) `HostName` extension. In legacy prototypes, setting `server_name` to a raw IP literal (e.g. `203.0.113.5` or `[2001:db8::1]`) caused libbox and the remote TLS server to reject the handshake.
In `packages/config_parser/lib/src/serializers/singbox_serializer.dart`, `SingBoxOutboundSerializer` enforces RFC 6066 compliance:
- Valid domain SNIs (e.g. `cdn.example.com`) are preserved in `tls.server_name`, even when the proxy server is an IP address.
- If `tls.serverName` is empty, null, or a raw IPv4/IPv6 literal (including bracketed IPv6 literals like `[::1]`), `server_name` is omitted entirely from the serialized JSON.
- Any IP-literal `server_name` values in `extraParams` are sanitized and omitted prior to emitting the `tls` block.

### 9.4 P7-T4 — Foreground Service Resilience (Process Death, Doze, Battery Optimization)

#### Manifest & Runtime Lifecycle Hardening
Brick VPN implements foreground service resilience adhering to Android 14+ (API 34) platform requirements and Linux kernel process management:
1. **Manifest Declarations:**
   - Declares `android.permission.FOREGROUND_SERVICE` and `android.permission.FOREGROUND_SERVICE_SPECIAL_USE` with subtype property `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE = "vpn"` in both `packages/vpn_engine_android` and `apps/mobile`.
   - Declares `android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` for battery exemption prompting.
   - `BrickVpnService` is declared with `android:foregroundServiceType="specialUse"` and `android:exported="false"`.
2. **Service Restart Resilience (`START_STICKY`):**
   - In `BrickVpnService.kt`, `onStartCommand` returns `START_STICKY` for `ACTION_START` and `ACTION_LOCKDOWN`, and `START_NOT_STICKY` for explicit user stop (`ACTION_STOP`).
   - If the Android low-memory killer (LMK) terminates the service process under extreme system memory pressure, the OS automatically recreates the service via a null-intent `onStartCommand` invocation.
   - Null-intent handling: If `isLockdownEnabled` is active, the service immediately re-establishes the fail-closed lockdown blackhole TUN (`0.0.0.0/0`, `::/0`) to guarantee zero leak gap. If the state machine is `Idle` or `Stopped`, the service invokes `stopSelf()` with `START_NOT_STICKY` to avoid leaked ghost processes.
3. **OS-Initiated Permission Revocation (`onRevoke`):**
   - When the user revokes VPN authorization in Android Settings or another VPN app is started, `onRevoke()` is triggered by the framework.
   - `onRevoke()` resets `isLockdownEnabled = false`, transitions `VpnStateMachine` via `onRevoke()`, stops the engine, closes the TUN descriptor on `cleanupScope`, and calls `stopSelf()`.
4. **Lockdown Survival Across Lifecycles (`P7-T1..P7-T3` Remediation D2):**
   - `onDestroy()` no longer wipes `isLockdownEnabled`. If the tunnel drops or encounters an error while lockdown is active, `BrickVpnService` remains running and engages `establishLockdownTun()`.
   - When Flutter dispatches `setLockdownBlocking(true)` while `current == null`, `BrickVpnService` is launched with `ACTION_LOCKDOWN` using `startForegroundService()`.

#### Battery Optimization Exemption Flow (`BatteryOptimizationService`)
Aggressive OEM battery managers frequently freeze or kill background network sockets during prolonged standby. Brick VPN provides guidance and direct OS integration:
1. **Platform Channel (`dev.brickvpn.harness/battery_optimization`):**
   - `isIgnoringBatteryOptimizations`: Queries `PowerManager.isIgnoringBatteryOptimizations(packageName)`.
   - `requestIgnoreBatteryOptimizations`: Dispatches `Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` with intent data `package:$packageName`. If the system dialog is blocked or unsupported, gracefully falls back to `Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`.
2. **Reactive UI (`SettingsScreen`):**
   - Integrates `settings_battery_optimization_tile` into `SettingsScreen`.
   - When restricted (`isIgnoring == false`), displays subtitle `"Optimized — tap to exclude from battery limits"`.
   - Tapping invokes `requestExemption()`, opening the system prompt; upon exemption, updates subtitle to `"Unrestricted (recommended for stable VPN)"`.

#### State Reconciliation on Process Kill & App Resume (Zero Stale State)
1. **Cold Boot Synchronization:**
   - In `AppBootstrap.init()`, reading `connectionStateProvider` queries native `VpnEngine.getStatus()` truth before the UI mounts, ensuring cold starts never display a stale `"Connected"` state.
2. **App Resume Probing (`AppLifecycleObserver`):**
   - `connectionStateProvider` mounts an `AppLifecycleListener`.
   - Whenever the Flutter app returns to the foreground (`AppLifecycleState.resumed`), `onResume()` queries `engine.getStatus()`.
   - If the OS killed the native service while backgrounded, `engine.getStatus()` returns `Disconnected()`. `connectionStateProvider` immediately emits `Disconnected()`, resetting `sessionDurationProvider` to `00:00:00` and updating `HomeScreen` and `SessionInfoPanel` immediately.

#### ADB Verification Methodology
1. **Simulating Doze Mode:**
   ```bash
   # Unplug battery simulation and force deep Doze
   adb shell dumpsys battery unplug
   adb shell dumpsys deviceidle force-idle
   # Verify device state is IDLE
   adb shell dumpsys deviceidle get deep
   # Step through maintenance windows
   adb shell dumpsys deviceidle step
   # Reset battery simulation
   adb shell dumpsys battery reset
   ```
2. **Simulating Low-Memory Process Kill:**
   ```bash
   # Kill the app process while VPN is active in background
   adb shell am kill dev.brickvpn.mobile
   # Verify foreground service remains active in dumpsys
   adb shell dumpsys activity services BrickVpnService
   ```

#### Documented Limitations & OEM Battery Manager Quirks
1. **Accepted Limitation — Manual Force Stop:**
   - If the user manually navigates to Android App Info and taps "Force Stop", the Linux kernel sends `SIGKILL` to all app processes and places the package into a stopped state (`FLAG_STOPPED`). The OS intentionally does not restart `START_STICKY` services until the user manually relaunches the app. This is an explicit, intentional OS security invariant that no app can or should circumvent.
2. **Documented OEM Background Battery Manager Quirks:**
   - **Xiaomi (MIUI / HyperOS):** Imposes an aggressive secondary process killer ("MIUI Battery Saver") and requires manual authorization in "Autostart" settings to permit background network operations. Documented for user manual adjustment.
   - **Samsung (OneUI):** Places background apps into "Sleeping apps" or "Deep sleeping apps" if not exempted via "Never sleeping apps" in Device Care settings.
   - **Huawei (EMUI / HarmonyOS):** Custom "App Launch" manager overrides standard Android battery settings; users must manually set App Launch to "Manage manually" (Auto-launch, Secondary launch, Run in background).
   - **OnePlus / OPPO (ColorOS / OxygenOS):** Aggressive memory cleaner kills background services during screen-off sleep cycles unless "Allow background activity" and "Lock app in Recents" are enabled.

### 9.5 P7-T5 — Chaos Test Suite & Legacy Failure Mode Matrix Architecture

#### Purpose & Architectural Reckoning
The legacy prototype failed in production due to unchecked concurrency races, optimistic UI assumptions, blocking calls on the main thread, fire-and-forget error swallowing, and uncoordinated OS lifecycle events. Phase 7 Task 5 establishes an automated regression test harness in `apps/mobile/test/legacy_chaos_regression_suite_test.dart` and a durable reference checklist in `AI_ROLES/LEGACY_CHAOS_REGRESSION_CHECKLIST.md` verifying the elimination of all twelve documented legacy collapse modes against the integrated Flutter application and native engine.

#### Core Architectural Invariants Verified
1. **Invariant 1 — Stream-Driven Truth (Failure Mode 2):** Command acceptance (`VpnCommandAccepted`) represents RPC acknowledgment only; the UI never infers connection state from command futures. State remains `Connecting` until native TUN events emit `Connected`.
2. **Invariant 2 — Independent Failure Domains (Failure Mode 1):** Telemetry stream errors (`trafficStats`) never perturb or tear down the active VPN tunnel (`connectionStateProvider`). The UI presents `Traffic data unavailable` and resumes cleanly upon receipt of fresh metrics.
3. **DNS Bootstrap Deadlock Prevention (Failure Mode 3):** Outbound serializers emit 0 remote `rule_set` dependencies; native routing delegates outbound endpoint resolution to `dns-direct` via `direct-out` while tunneling user traffic through `dns-remote`. Stalled startups abort with `PlatformError` within 15 seconds.
4. **Non-Blocking Lifecycle & Stop Watchdogs (Failure Mode 4):** Disconnect intents dispatch asynchronously without blocking the UI thread. A 5000ms watchdog forces `stopSelf()` teardown if native core termination stalls.
5. **Deterministic Error Propagation (Failure Mode 5):** Native daemon thread errors surface through `VpnStateMachine` to Pigeon as structured `Error(PlatformError(detail))` and are rendered to users via floating SnackBars.
6. **Repeatable Session Initialization (Failure Mode 6):** All engine components, controllers, and singleton registries cleanly reset state upon `close()`, supporting unlimited back-to-back connection cycles.
7. **IPC Resiliency & Controller Guard Recovery (Failure Mode 7):** IPC failures returning `VpnCommandFailed` or throwing `PlatformException` always unlock the in-flight command guard (`_busy = false` in `finally`), preventing permanent UI lockup.
8. **Intent-Driven Teardown & Kill Switch Coordination (Failure Mode 8):** Service stop is coordinated via `ACTION_STOP` intent and `stopSelf()`. `KillSwitchNotifier` differentiates deliberate user stop (`KillSwitchInactive`) from unexpected tunnel drop (`KillSwitchBlocking`).
9. **Monotonic Teardown Protection (Failure Mode 9):** Toggling into `Disconnecting` state disables connect buttons (`onPressed: null`), and late-arriving traffic packets are discarded without reverting state to `Connected`.
10. **Session Boundary Isolation (Failure Mode 10):** Riverpod auto-dispose and explicit session cancellation guarantees that duration timers and background coroutines from prior sessions never leak into subsequent sessions.
11. **Re-Entrancy Serialization & Busy Guard (Failure Mode 11):** Concurrent stop/start calls are serialized or safely rejected with `VpnCommandRejectedBusy`, eliminating thread deadlocks.
12. **TUN Descriptor Lifecycle Safety (Failure Mode 12):** Cancellation during `Connecting` aborts cleanly without leaking native file descriptors or leaving orphaned active session tokens.

### 9.6 P7-T6 — VPN State Persistence Across App Process Restart Architecture

#### Purpose & Problem Statement
When the Android OS evicts the Flutter UI process due to low memory (LMK / doze / user swipe in recents), the native foreground `BrickVpnService` continues running in its own lifecycle. Upon subsequent app launch, a naive architecture would default to `Disconnected`, flashing false disconnected states, resetting session stats, confusing the user, or even dispatching a duplicate `start()` command that tears down or restarts the live tunnel. P7-T6 establishes seamless state persistence and re-attachment across UI process death.

#### Architectural Components & Re-Attachment Flow
1. **Startup Pre-Warm & Probing Sequence:**
   - In `AppBootstrap.init()`, before the UI widget hierarchy mounts, the native engine is probed via `engine.getStatus()` with a 500ms safety timeout fallback to `Disconnected()`.
   - The probed status is provided to Riverpod's root container as `initialConnectionStateProvider.overrideWithValue(initialStatus)`.
   - When `connectionStateProvider` initializes, it immediately adopts the pre-warmed snapshot, preventing visual flickers.
2. **Neutral Loading State (Zero "Disconnected" Flash):**
   - In `ConnectionStateBadge` and `SessionInfoPanel`, when `connectionStateProvider` is in `AsyncLoading` (and neither stream data nor pre-warmed state is resolved), the UI renders a neutral localized `'connection.state_checking'.tr()` ("Checking..."), explicitly avoiding any optimistic or false "Disconnected" badge.
   - If pre-warmed state (`Connected`) is already present, the badge and panel render `Connected` on frame 0 with zero loading or disconnected flash.
3. **Active Session Re-Attachment:**
   - Upon observing `Connected`, `AutoReconnectNotifier` automatically re-arms by setting `_userSessionActive = true` and capturing `_activeProfile` from `activeServerProvider`.
   - `KillSwitchNotifier` detects the active tunnel on `build()` or `ref.listen` and transitions immediately to `KillSwitchArmed()`.
   - `ConnectionController` syncs `_activeConnectingServerId` with the active server.
   - `sessionDurationProvider` automatically resumes duration tracking for the active session.
   - `TrafficStats` and log events continue streaming into `LogManager` and telemetry providers.
4. **Duplicate-Session Guard:**
   - If user or UI triggers `controller.connect(profile)` for the already-connected server while in `Connected` or `Connecting`, `ConnectionController` returns `const VpnCommandRejectedBusy()` without dispatching redundant start or stop commands to native `VpnEngine`.
   - If a different server is selected, `ConnectionController` cleanly tears down the active tunnel before starting the new profile.

### 9.7 P7-T7 — Phase 7 End-to-End Combined Resilience Architecture & Phase 8 Handoff

#### Purpose & Scope
Phase 7 closeout reconciles all individual stability and lifecycle mechanisms into an unbroken, integrated real-world resilience architecture. Rather than asserting components in isolation, `P7-T7` verifies the synchronized interaction of auto-reconnect backoff, fail-closed kill switch lockdown, DNS bootstrap isolation, foreground service persistence, and UI process death re-attachment under continuous multi-stage stress (`apps/mobile/test/phase7_e2e_resilience_journey_test.dart`).

```
                    [ User Connect: Tokyo Node (Domain/SNI) ]
                                      │
                                      ▼
                        [ STAGE A: Active Connected ]
                     ├── KillSwitch: Armed (Native Open)
                     ├── AutoReconnect: Idle (Session Active)
                     ├── Live Duration Timer & Delta Throughput
                     └── Structured Live Engine Logs Streaming
                                      │
                         (Wi-Fi -> Cellular Handoff)
                                      ▼
                      [ STAGE B: Network Flap Recovery ]
                     ├── 350ms Flap Coalescing Debounce
                     ├── Engine Stop Dispatched
                     ├── KillSwitch: BLOCKING (Fail-Closed)
                     ├── AutoReconnect: Backoff (Attempt 1, 1s)
                     └── Reconnect Succeeded -> KillSwitch: Armed
                                      │
                      (Airplane Mode / Network Drop)
                                      ▼
                     [ STAGE C: Outage Hold & Recovery ]
                     ├── ConnectivityResult.none
                     ├── AutoReconnect: WaitingForNetwork
                     ├── KillSwitch: BLOCKING (Fail-Closed)
                     ├── Outage Hold: 0 Futile Connection Calls
                     └── Network Restored -> 1s Backoff -> Reconnected
                                      │
                      (UI Process Killed by System LMK)
                                      ▼
                   [ STAGE D: UI Process Death & Relaunch ]
                     ├── Native BrickVpnService Continues in Background
                     ├── AppBootstrap Pre-Warm (Zero Disconnected Flash)
                     ├── Active Session Re-Attached (Stats, Logs, Timer)
                     ├── Duplicate Connect Rejected with VpnCommandRejectedBusy
                     └── Clean Server Switch to Osaka Node (Stop -> Start)
                                      │
                         (Repeated Connection Failures)
                                      ▼
                    [ STAGE E: Retry Exhaustion & Unblock ]
                     ├── Exponential Retries: 1s, 2s, 4s, 8s, 16s (Cap: 5)
                     ├── AutoReconnect: Exhausted (TotalAttempts: 5)
                     ├── KillSwitch: BLOCKING (Continuous Leak Protection)
                     └── User Taps "Disconnect & Unblock" -> Clean Baseline
```

#### Multi-Stage Stress Flow Guarantee
1. **Stage A (Tokyo Node Connect & Plumbing Verification):**
   Initiates connection to a domain endpoint with TLS/SNI (`tokyo.example.com`). Asserts full activation: `Connected` state, `KillSwitchArmed`, duration timer ticking at 1 Hz, real-time byte counters and transfer speeds in `ThroughputReadout`, and structured log capture in `structuredLogEntriesProvider`.
2. **Stage B (Interface Handoff & Auto-Reconnect Recovery):**
   Simulates abrupt Wi-Fi to cellular transition. Network debounce (350ms) suppresses transient flapping, cleanly halts stale tunnel, and transitions `KillSwitch` into fail-closed `KillSwitchBlocking` (engaging OS/platform bridge lockdown) while `AutoReconnectNotifier` executes exponential backoff (attempt 1: 1s delay) before successfully re-establishing tunnel and disengaging lockdown.
3. **Stage C (Airplane Mode Outage Hold & Restoration):**
   Simulates complete network loss (`ConnectivityResult.none`) paired with engine drop. The system transitions into `AutoReconnectWaitingForNetwork` while holding `KillSwitchBlocking`. Bounded hold guarantees zero futile network calls during extended outages. Restoration of connectivity automatically resumes backoff and restores active tunnel and `KillSwitchArmed`.
4. **Stage D (Process Death Re-Attachment & Server Switching):**
   Simulates OS eviction of the Flutter engine (`pumpWidget(SizedBox.shrink())`) while native `BrickVpnService` remains connected in the background. On relaunch, `AppBootstrap.init()` pre-warms state from native engine status, eliminating visual flicker ("Checking...", never false "Disconnected"). Duplicate `connect()` for active server is safely rejected busy (`VpnCommandRejectedBusy`). Switching to Osaka Node cleanly executes monotonic teardown of Tokyo Node before initiating Osaka Node.
5. **Stage E (5-Attempt Retry Exhaustion & Clean Recovery):**
   Simulates unrecoverable remote server failure on Osaka Node. `AutoReconnectNotifier` attempts exponential retry ceiling (1s, 2s, 4s, 8s, 16s; max 5 attempts), transitioning to `AutoReconnectExhausted(totalAttempts: 5)`. The kill switch remains fail-closed in `KillSwitchBlocking` to prevent IP leakage. Tapping the warning banner's "Disconnect & Unblock" action cleanly disengages lockdown, resets auto-reconnect to `AutoReconnectIdle`, and restores clean `Disconnected` baseline.

#### Phase 8 Handoff Contract
Phase 7 completes the stabilization and hardening of the core client lifecycle, resolving all 12 historical prototype failure modes documented in `AI_ROLES/LEGACY_CHAOS_REGRESSION_CHECKLIST.md`.

What Phase 8 (Security Hardening) inherits from Phase 7:
- **Authoritative Lifecycle Truth (Invariant 1):** Phase 8 components (`P8-T1` secure storage, `P8-T2` log redaction) can rely unconditionally on `connectionStateProvider` and native engine status without building redundant lifecycle state trackers.
- **Hermetic Stream Boundaries (Invariant 2):** Live logging streams and traffic stats streams are completely decoupled from tunnel control. `LogManager` and `P8-T2` log redaction transformers can process log lines without risk of impacting VPN connection stability.
- **Stable Storage Contract:** `ServerProfileRepository` and `AppPreferencesRepository` provide unified interfaces for `P8-T1` to introduce AES-GCM / EncryptedSharedPreferences encryption for sensitive configuration fields (UUIDs, passwords, private keys, SNI headers) transparently.
- **Carried-Forward Open Item — Log Redaction:** Throughout Phases 6 and 7, live engine logs contain unredacted diagnostic strings. Field-level redaction and regex scrubbing are strictly designated as the primary objective of **Phase 8 (P8-T2 — Log Redaction)**.

---

## 10. Phase 8 — Security Hardening Architecture

### 10.1 P8-T1 — Secure Storage for Sensitive Server Fields Architecture

#### Purpose & Threat Model
In Phases 5–7, `FileServerProfileRepository` persisted `ServerProfile` and `SubscriptionMetadata` objects in plaintext JSON (`schema_version: 1`). While acceptable during early rapid prototyping, persisting raw credentials (UUIDs, private keys, passwords, obfuscation keys, subscription tokens) on non-volatile storage leaves sensitive material exposed to unprivileged file inspection, backup extraction, and forensic recovery.

`P8-T1` closes this gap by implementing **field-level authenticated encryption at rest** backed by hardware-protected Android Keystore AES-256-GCM, while maintaining plaintext metadata for sub-millisecond query and UI list rendering without decryption overhead.

#### Component Topology & Data Flow

```
[ UI / Presentation Layer ]
       │
       ▼
[ FileServerProfileRepository ] ──(schema_version: 2)──► [ server_profiles.json ]
       │                                                         │
       ├── Plaintext Metadata (id, name, protocol, server, port) ├── Plaintext
       │                                                         │
       └── Sensitive Fields (uuid, password, privateKey, etc.)   └── "enc:v1:<base64(IV + Ciphertext + Tag)>"
                   │
                   ▼
       [ SensitiveFieldCipher ]
       ├── AndroidKeystoreSensitiveFieldCipher ──(MethodChannel)──► AndroidKeyStore (AES-256-GCM)
       └── LocalAuthenticatedCipher / InMemory (HMAC-SHA256 Encrypt-then-MAC fallback)
```

#### Protocol Field Classification Matrix

| Protocol | Non-Sensitive Plaintext Fields | Sensitive Encrypted Fields (`enc:v1:...`) |
|---|---|---|
| **VLESS** | `id`, `name`, `protocol`, `server`, `server_port`, `flow`, `transport` | `uuid`, `tls.reality.public_key`, `tls.reality.short_id` |
| **VMess** | `id`, `name`, `protocol`, `server`, `server_port`, `alterId`, `security` | `uuid` |
| **Trojan** | `id`, `name`, `protocol`, `server`, `server_port`, `tls` | `password` |
| **Shadowsocks** | `id`, `name`, `protocol`, `server`, `server_port`, `method` | `password` |
| **Hysteria2** | `id`, `name`, `protocol`, `server`, `server_port`, `up_mbps`, `down_mbps`, `ports` | `password`, `obfs.password` |
| **TUIC** | `id`, `name`, `protocol`, `server`, `server_port`, `congestion_control` | `uuid`, `password` |
| **WireGuard** | `id`, `name`, `protocol`, `server`, `server_port`, `local_address` | `private_key`, `pre_shared_key`, `peer_public_key` |
| **AmneziaWG** | `id`, `name`, `protocol`, `server`, `server_port`, `jc`, `jmin`, `jmax`, `s1`, `s2`, `h1-h4` | `private_key`, `pre_shared_key`, `peer_public_key` |
| **Subscription** | `id`, `name`, `last_refreshed_at`, `associated_server_ids`, `user_info` | `url` (contains secret query tokens & UUIDs) |

#### Integrity & Migration Guarantees
1. **Zero Plaintext on Disk:** Every credential string across all 8 protocols and subscription URLs is encrypted before the atomic file rename.
2. **Deterministic Tamper Rejection (Fail-Closed):** Any single-bit modification of an `enc:v1:...` payload causes GCM/HMAC authentication to fail. Decryption throws `FormatException`, which `FileServerProfileRepository` catches safely, surfacing the compromised entry as `SavedServerBroken` without crashing or leaking secrets.
3. **Transparent v1 -> v2 Migration:** If `schema_version: 1` or plaintext records are loaded, the repository parses them, automatically writes back `schema_version: 2` with encrypted fields, and logs `"Migrated plaintext server profiles to encrypted storage v2"`.

#### Hardware Security & Android Keystore API Quirks
1. **Thread-Safety & Synchronization (`@Synchronized`):** `SecureStorageHelper` methods (`getOrCreateKey()`, `encrypt()`, `decrypt()`) are annotated with `@Synchronized` to prevent race conditions during concurrent MethodChannel invocations from multi-threaded isolate environments.
2. **Biometric Enrollment Resilience (`setUserAuthenticationRequired(false)`):** The master key generated via `KeyGenParameterSpec.Builder` explicitly configures `.setUserAuthenticationRequired(false)`. If omitted or set to true, any subsequent biometric enrollment change (e.g. user adds or removes a fingerprint) triggers a fatal `android.security.keystore.KeyPermanentlyInvalidatedException`, permanently destroying access to stored server profiles.
3. **StrongBox vs. TEE Fallback:** While StrongBox Keymaster offers dedicated hardware tamper-resistance on supported SoC chipsets (Pixel 3+), requesting StrongBox unconditionally causes `StrongBoxUnavailableException` on devices lacking dedicated hardware modules. Brick VPN targets standard hardware-backed AndroidKeyStore (TEE), ensuring universal hardware isolation across all supported Android versions without risking initialization failures.

### 10.2 Systematic Log Redaction Architecture (P8-T2)

#### Purpose & Threat Model
In Phases 6 and 7, native engine log events and diagnostic traces were ingested and displayed directly. Under sing-box and native Android VPN operation, log messages can inadvertently echo raw credentials (passwords, UUIDs, private keys, subscription tokens, obfuscation passwords), full connection URIs (carrying embedded credentials and server endpoints), and external peer IP addresses. Sharing or exporting these logs (e.g. for user troubleshooting or diagnostic support) creates severe confidentiality risks and de-anonymization vulnerabilities.

`P8-T2` establishes an **always-on, zero-bypass systematic redaction architecture** that sanitizes all incoming log lines at the earliest possible ingestion point before entries are stored in memory, rendered on screen, copied to the clipboard, or written to disk.

#### Component Topology & Ingestion Chokepoint

```
[ Native VpnEngine (logEvents Stream) ] ──► [ LogManager._handleLogEvent ]
                                                    │
                                                    ▼
                                      [ LogRedactor.redactRawLine ]
                                      ├── Known Profile Secrets (>= 4 chars) ──► "[REDACTED]"
                                      ├── Protocol & HTTP URIs (<scheme>://) ──► "<scheme>://[REDACTED]"
                                      ├── JSON Sensitive Keys ("password", etc) ──► '"key":"[REDACTED]"'
                                      ├── Free-Text Key-Value Patterns (key=val) ──► 'key=[REDACTED]'
                                      ├── RFC 4122 UUID Patterns ──► "[REDACTED_UUID]"
                                      └── External IPv4 / IPv6 Addresses ──► "[REDACTED_IP]"
                                                    │
                                                    ▼
                                            [ LogEntry.fromRaw ]
                                                    │
                      ┌─────────────────────────────┼─────────────────────────────┐
                      ▼                             ▼                             ▼
           [ Surface 1: Viewer ]         [ Surface 2: Clipboard ]        [ Surface 3: Temp Disk ]
       Bounded Ring Buffer (ListQueue)    Sanitized Copy Export          Single Rotating Log File
       (structuredLogEntriesProvider)   (logs_privacy_warning_dialog)    (brick_vpn_live.log)
```

#### Multi-Tiered Redaction Rules
1. **Dynamic Known Secrets:** Extracted at runtime from saved and active server profiles (`LogRedactor.extractSecretsFromProfile`) and subscriptions (`LogRedactor.extractSecretsFromSubscription`). Every secret string >= 4 characters (passwords, private keys, pre-shared keys, Reality public keys, short IDs, server hostnames/domains, subscription query tokens) is scrubbed to `[REDACTED]`.
2. **Share URIs & URLs:** Matches known VPN protocols (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, `hy2://`, `tuic://`, `wireguard://`, `wg://`) and web URIs (`http://`, `https://`). The entire sensitive authority and query string are replaced with `<scheme>://[REDACTED]`.
3. **Structured JSON Sensitive Keys:** Scrubs keys matching `password`, `private_key`, `public_key`, `pre_shared_key`, `obfs_password`, `short_id`, `uuid`, `server`, `url`, `auth`, `token`, `secret`, `key`, `headers`, `authorization` to `"$key":"[REDACTED]"` (or `"[REDACTED_HOST]"` for `server`).
4. **Free-Text Key-Value Patterns:** Matches common log assignment patterns (e.g. `password=...`, `token: ...`, `key = ...`) and scrubs values to `[REDACTED]`.
5. **RFC 4122 UUID Patterns:** Matches 8-4-4-4-12 hex UUID formats and scrubs them to `[REDACTED_UUID]`.
6. **External IP Sanitization with Diagnostic Address Preservation:** External IPv4 and IPv6 addresses are scrubbed to `[REDACTED_IP]`. However, essential local and diagnostic networking addresses are explicitly preserved intact:
   - Loopback: `127.0.0.1`, `::1`, `localhost`
   - Unspecified: `0.0.0.0`, `::`
   - Standard Subnet Masks: `255.255.255.0`, `255.255.255.255`
   - Brick VPN TUN Diagnostic Subnet: `10.111.222.0/24` (e.g. `10.111.222.1`)
   - ISO 8601 Timestamps: Timestamps (e.g. `2026-11-07T00:00:00Z` or `12:00:00`) are protected from IPv6 false-positive matching.

#### Invariant Guarantees
1. **Chokepoint Ingestion Guarantee:** Redaction executes immediately in `LogManager._handleLogEvent` before any insertion into in-memory ring buffers or disk file sinks. By construction, raw unredacted text never exists in the Live Viewer ring buffer, the Clipboard Export buffer, or the temp log file.
2. **Zero-Bypass / Always-On Design:** There is no configuration option, debug toggle, or user setting that disables log redaction. Security by default is absolute per `SECURITY.md`.
3. **Privacy Warning Dialog Confirmation:** Exporting logs to the system clipboard prompts a modal confirmation dialog (`logs_privacy_warning_dialog`) that reiterates that while credentials, URLs, and external IPs are automatically stripped, users should still exercise discretion before sharing logs publicly.

#### Architectural Limitations
- **Regex & Heuristic Boundary:** Redaction relies on deterministic regex matching and registration of known profile secrets. Unstructured free text containing high-entropy tokens or unconventional credential delimiters not matching the standard key patterns and not present in active profiles could theoretically bypass heuristic scrubbing. Registering profile and subscription secrets into `LogManager._knownSecrets` provides deterministic defense-in-depth against this limitation.

### 10.3 Input Validation and Untrusted-Data Security Architecture (P8-T3)

#### Purpose & Threat Vectors
Brick VPN processes externally-sourced, untrusted data across three ingress surfaces:
1. **Manual Link Pasting:** User clipboard paste in `AddServerScreen` (`vless://`, `trojan://`, `ss://`, etc.).
2. **Camera Optical Scanning:** Real-time barcode frames in `QrScanScreen`.
3. **Remote Subscription Document Retrieval:** Automated network ingestion in `SubscriptionFetcher` and `AddSubscriptionScreen`.

`P8-T3` implements a unified, defense-in-depth input validation architecture to eliminate buffer/memory exhaustion, remote code execution, SSRF, stack overflow recursion, transport downgrades, and credential reflection.

#### Component Topology & Security Controls

```
[ User Input / QR Frame / Subscription Feed ]
                      │
                      ▼
        [ Ingress Bounds Check ] ── (maxUriLength = 8 KiB / maxSubscriptionLength = 5 MiB)
                      │ (Fast O(1) Reject)
                      ▼
     [ Safe Parsing & Normalization ]
    ┌─────────────────┴─────────────────┐
    ▼                                   ▼
[ Protocol Parsers (1..8) ]    [ SubscriptionFetcher ]
- RFC 6066 SNI Sanitization    - Mandatory HTTPS Scheme
- Exact-Byte Base64 Decodes    - Redirect Downgrade Block
- Iterative Depth JSON (<=32)  - Incremental Byte-Cap Stream
- Discard Unknown Query Params - Whole-Fetch Deadline (10s)
    └─────────────────┬─────────────────┘
                      │
                      ▼
         [ Domain Error Mapping ]
     (Zero Secret / Host Echoing)
                      │
                      ▼
[ UI Presentation (ErrorMapper / Toast) ]
```

#### Invariant Guarantees
1. **Strict Bounds Enforcement:** Length limits are evaluated *prior* to parsing or allocation. Inputs exceeding `maxUriLength` (8 KiB) or `maxSubscriptionLength` (5 MiB) are rejected in O(1) time without recursive copying or string decoding.
2. **JSON Recursion Depth Bounding:** `safeJsonDecode` performs breadth-first depth checks capped at `maxJsonDepth = 32`, preventing stack overflow denial-of-service from adversarial nested payloads.
3. **Transport Security & Downgrade Prevention:** `SubscriptionFetcher` enforces HTTPS exclusively across initial URLs and all redirect hops. Cleartext HTTP and non-HTTP schemes are rejected immediately. Redirects from HTTPS to HTTP are terminated as security violations with `InsecureTransportError`.
4. **Incremental Memory-DoS Throttling:** Subscription streams are read chunk-by-chunk. If cumulative byte volume exceeds 5 MiB, the underlying `StreamSubscription` is cancelled immediately and the socket is drained, preventing memory exhaustion from endless streaming attacks.
5. **Zero Secret Echoing:** Presentation controllers (`AddServerController`, `AddSubscriptionController`) and `ErrorMapper` never reflect raw input strings, passwords, UUIDs, or tokens in user-visible error dialogs or SnackBar notifications.

#### Formal Reference
Comprehensive per-parser audit matrices and threat analysis are documented in `AI_ROLES/UNTRUSTED_INPUT_SECURITY_REVIEW.md` and verified by `apps/mobile/test/untrusted_input_security_review_test.dart`.

### 10.4 App Update Integrity & Release Verification Architecture (P8-T4)

#### Purpose & Threat Model
Brick VPN is designed for deployment in hostile censorship and surveillance environments where centralized app stores (Google Play, Apple App Store) may be blocked, restricted, or subject to geopolitical coercion. Consequently, users frequently obtain installation binaries via direct APK downloads from GitHub Releases, mirrors, or peer-to-peer distribution.

Without end-to-end cryptographic verification, direct binary distribution leaves users vulnerable to:
1. **Malicious Binary Tampering / Repackaging:** Attackers embedding spyware, telemetry, or compromised sing-box cores into modified APKs.
2. **Adversarial Network MITM:** In-flight packet injection or SSL-stripping during direct downloads from mirror sites.
3. **Distribution Infrastructure Compromise:** Tampering with hosted release assets or CDN edge caches.

`P8-T4` establishes an open, verifiable release integrity framework comprising deterministic checksum publication, user-facing verification protocols, and an honest technical evaluation of reproducible builds.

#### Release Integrity Architecture & Pipeline Mechanics

```
[ Developer / CI Pipeline (GitHub Actions) ]
                      │
                      ▼
        [ Tagged Release Trigger (v*) ]
                      │
                      ▼
          [ flutter build apk --release ]
                      │
                      ▼
[ scripts/generate_and_verify_checksums.sh ]
  ├── 1. Discovers Release Artifacts (*.apk, *.aab)
  ├── 2. Computes Cryptographic SHA-256 Hashes
  ├── 3. Normalizes Basenames & Sorts Deterministically
  ├── 4. Writes Canonical SHA256SUMS.txt
  └── 5. Self-Verifies (sha256sum -c SHA256SUMS.txt)
                      │
                      ▼
[ GitHub Releases / Artifact Storage ]
  ├── app-arm64-v8a-release.apk
  ├── app-armeabi-v7a-release.apk
  ├── app-x86_64-release.apk
  └── SHA256SUMS.txt
                      │
                      ▼
[ User / Downloader Verification Surface ]
  ├── Step 1: Checksum Match (sha256sum -c SHA256SUMS.txt)
  └── Step 2: Signature Inspection (apksigner verify --print-certs)
```

#### Android Signing Key Strategy & Governance (Phase 8 vs. Phase 10)
- **Current Development State (Phase 8):** In `apps/mobile/android/app/build.gradle.kts`, the `release` build type currently inherits debug signing keys:
  ```kotlin
  buildTypes {
      release {
          signingConfig = signingConfigs.getByName("debug")
      }
  }
  ```
- **Phase 10 Boundary:** Per `P8-T4` Scope 1 & Criterion 1, production release keystore generation, physical hardware token / offline air-gapped key custody, and GitHub Actions repository secrets provisioning (`ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) are explicitly scoped to **Phase 10 (Release Preparation)**.
- **Certificate Verification Structure:** User-facing documentation (`docs/verifying-releases.md`) establishes the standard verification workflow using `apksigner` and `keytool`, providing a defined placeholder for the production SHA-256 certificate fingerprint to be populated upon Phase 10 key generation.

#### Feasibility Investigation: Reproducible Builds
An honest evaluation of byte-for-byte reproducible builds was conducted across Brick VPN's composite toolchain:
1. **Flutter / Dart AOT Engine (`gen_snapshot`):** Compiles Dart code into `libapp.so`. Upstream Flutter builds embed build environment timestamps, absolute path symbols, and non-deterministic memory layouts unless specialized flags and hermetic containers are enforced.
2. **Go Engine (`libbox.aar` / gomobile):** Compiles sing-box core into native ELF binaries packaged within an Android Archive. Gomobile archives embed filesystem timestamps and host GOROOT metadata unless stripped with `-trimpath` and `SOURCE_DATE_EPOCH`.
3. **Android Gradle Plugin (AGP) / AAPT2 / D8:** Jar and APK ZIP packaging produces non-deterministic zip entry order and timestamps across different host OSes.

**Conclusion & Phase 10+ Roadmap:** Byte-for-byte reproducibility is not achievable out-of-the-box at Phase 8. Full reproducibility will be implemented in Phase 10+ by introducing:
- A hermetic, pinned Docker build container (`ubuntu:24.04` with pinned Flutter 3.47.4, Dart 3.13.3, Go 1.23, and Android NDK r27b).
- Git-commit-derived `SOURCE_DATE_EPOCH` and Go `-trimpath` compilation flags.
- Deterministic APK ZIP archive re-packing and timestamp zeroing prior to APK Signature Scheme v2/v3 signing.

### 10.5 Dependency & Supply-Chain Security Architecture (P8-T5)

#### Purpose & Threat Model
In privacy and anti-censorship software, third-party dependencies represent an existential supply-chain threat vector. Malicious upstream updates, compromised developer accounts, abandoned packages, or excessive permissions can lead to:
1. **Malicious Code Injection / Backdoors:** Compromising the cryptographic tunnel or exfiltrating user credentials.
2. **Permission Creep & Data Exfiltration:** Background location tracking, storage harvesting, or device identifier fingerprinting.
3. **Denial of Service:** Latent vulnerabilities or memory leaks in native engine components.

`P8-T5` establishes a hardened, multi-tier supply chain validation architecture:
1. **Zero-Advisory Dependency Baseline:** Continuous vulnerability scanning ensuring 0 critical/high CVEs across Dart, Gradle, and Go stacks.
2. **Strict Manifest Least-Privilege Enforcement:** Codified allowlist restricting Android permissions to strictly required features, with zero invasive permissions and non-exported service boundaries (`android:exported="false"`).
3. **Automated Dependabot Security Monitoring:** Weekly automated vulnerability and version PR updates across `pub`, `gradle`, and `github-actions` via `.github/dependabot.yml`.

#### Multi-Stack Inventory & Security Topology

```
[ Brick VPN Application Codebase ]
        │
        ├── 1. Dart/Flutter Stack ──► pub.dev (SHA-256 Verified, Zero Unpinned Git)
        │                             ├── Core Logic (flutter_riverpod, go_router)
        │                             └── Input Parsing (petitparser, yaml, crypto)
        │
        ├── 2. Native Android Stack ──► Google / Maven Central (AGP 9.1.0, JVM 17)
        │                               ├── AndroidManifest Least Privilege (8 permissions)
        │                               └── Non-Exported Service (BrickVpnService)
        │
        └── 3. Go Core Stack ────────► Hermetic libbox.aar (sing-box v1.10.7 with uTLS)
                                      └── 16 KiB Page-Aligned ELF Binaries (arm64, v7a, x86_64)
```

#### Automated Supply-Chain Verification
Automated test suite `apps/mobile/test/supply_chain_and_manifest_security_test.dart` enforces:
1. Strict AndroidManifest permission allowlist and invasive permission absence.
2. Dependabot version 2 weekly schedule across all three package ecosystems.
3. `pubspec.lock` registry provenance (`https://pub.dev`, local `path`, `sdk`) with zero unpinned git dependencies.
4. Deterministic checksum generator execution and tamper detection.

#### Formal Reference
The comprehensive dependency audit, vulnerability scan results, and permission justifications are documented in `AI_ROLES/DEPENDENCY_SUPPLY_CHAIN_AUDIT.md`.

### 10.6 Honest Security Posture Classification & Residual Risk Assessment

#### Security Posture Classification
In accordance with Brick VPN's core governance principles (no security theater, rigorous transparency, and honest threat modeling), the table below classifies the security controls implemented across Phase 8 into three explicit categories:

| Category | Security Control / Component | Implementation & Enforcement | Security Boundary & Assurance |
| :--- | :--- | :--- | :--- |
| **Category 1: Verified Secure** | **Storage Encryption at Rest (P8-T1)** | Field-level AES-256-GCM authenticated encryption schema v2 in `FileServerProfileRepository` backed by `SensitiveFieldCipher` abstraction (`AndroidKeystoreSensitiveFieldCipher` on Android via `SecureStorageHelper` in `VpnEngineAndroidPlugin.kt`, and `LocalAuthenticatedCipher` fallback for pure-Dart/unit tests). | Plaintext credentials (`uuid`, `password`, `private_key`, `pre_shared_key`, `peer_public_key`, `transport.headers`, `extra_params`, and subscription URLs) never hit persistent storage. Tampering triggers authentication tag failure (`AEADBadTagException`) and fails closed (`SavedServerBroken`). |
| | **Bounded Input Parsing (P8-T3)** | 8 URI protocol parsers with strict bounds (`maxUriInputLength = 8256`, `maxNameInputLength = 128`), regex/character set validation, and non-printable control/RTL Bidi character stripping (`BuildServerProfile.sanitizeRemark`). | O(1) input bounds prevent RegEx DoS and memory exhaustion. Clipboard pastes and keyboard entries strictly clamped. Malformed inputs fail safely with typed errors (`InputTooLargeError`, `InvalidUriFormatError`). |
| | **Systematic 3-Surface Log Scrubbing (P8-T2)** | Centralized redaction engine via `redact()` in `packages/shared_utils/lib/src/redaction.dart`, `LogRedactor` in `apps/mobile/lib/core/logging/log_redactor.dart`, `LogEntry.fromRaw`, and `LogManager._handleLogEvent`. | Guaranteed consistent redaction across all 3 user-facing and diagnostic surfaces: (1) Live Log Viewer UI, (2) Clipboard export dialog with privacy warning, and (3) persistent log files (`brick_vpn_live.log`). |
| | **Release Integrity & Checksum Verification (P8-T4)** | Android APK Signature Scheme v2/v3 signing, SHA-256 checksum generation (`SHA256SUMS.txt`), and automated tamper verification script (`scripts/generate_and_verify_checksums.sh`). | Cryptographic signature prevents APK modification or repacking. Debug artifacts (`*-debug.apk`, `*-debug.aab`) excluded from checksum baseline. Public fingerprint documented in `docs/verifying-releases.md`. |
| | **Supply Chain & Manifest Least Privilege (P8-T5)** | Hermetic native binaries, zero unpinned git dependencies, automated Dependabot weekly scanning, and minimal Android permission allowlist (8 justified permissions, zero invasive permissions). | Background services non-exported (`android:exported="false"`). Zero critical/high CVEs across Dart, Gradle, and Go stacks. |
| **Category 2: Best-Effort with Known Limitations** | **In-Memory Secret Retention** | Native engine `sing-box` (Go `libbox.aar`) requires decrypted credentials in memory to establish cryptographic tunnels. | An adversary with physical root/debugger access (`frida`, kernel memory dump) can inspect volatile RAM. Minimized by wiping strings where feasible, but runtime memory zeroing cannot be cryptographically guaranteed in managed runtimes (Go GC / Dart VM). |
| | **Host Test Mock Ciphers** | In JVM/desktop unit tests without Android Keystore, an in-memory/fallback AES-GCM cipher (`LocalAuthenticatedCipher` / `InMemorySensitiveFieldCipher`) is utilized. | Provides functional cryptographic parity in unit tests; hardware Keystore / StrongBox backed keys operate exclusively on real Android devices. |
| | **Free-Text Native Engine Log Redaction** | Sing-box core logs free-text strings that pass through regex pattern scrubbers. | Regex pattern matching handles common credential and address shapes, but cannot guarantee 100% detection of novel, non-standard, or obfuscated formats in free-text debug output. Advanced users warned via modal. |
| | **Subscription Server Integrity** | HTTPS TLS certificate validation, size bounds (`maxSubscriptionLength = 5 MiB`), redirect limit (`maxRedirects = 5`), and timeout (`defaultFetchTimeout = 10s`). | If an upstream subscription provider is compromised or issues malicious configuration payloads, the app safely parses or rejects them, but cannot verify if the remote server itself is trustworthy or logging user connections. |
| **Category 3: Deferred to Phase 10 / Production** | **Production Release Signing Key & Hardware/Offline Custody (P8-T4)** | Phase 8 builds use Android debug signing (`signingConfigs.getByName("debug")`) for reproducible development. | Generating the production release keystore, establishing secure offline/hardware key custody, configuring CI signing secrets, and replacing `[PENDING_PHASE10_PRODUCTION_KEY_FINGERPRINT]` in `docs/verifying-releases.md` are deferred to Phase 10. |
| | **Bit-for-Bit Reproducible Builds (P8-T4)** | Not yet bit-for-bit reproducible at Phase 8 due to `gomobile` AAR ZIP timestamps and host build paths. | Containerized hermetic build environment with `SOURCE_DATE_EPOCH`, `-trimpath`, deterministic APK ZIP timestamp normalization, and toolchain locking scoped to Phase 10+. |
| | **Transitive Cosmetic Dependency Lockfile Bump (P8-T5)** | `cupertino_ui` and `material_ui` transitive lockfile notices have 0 CVEs (`isCurrentAffectedByAdvisory: false`). | Cosmetic lockfile upgrades scheduled for Phase 10 release preparation to avoid mid-hardening dependency churn. |

#### Residual Risk & Threat Model Summary
1. **Device Compromise:** Physical compromise of an unencrypted, rooted device exposes runtime secrets in RAM. Users in extreme-threat environments should enable device full-disk encryption and avoid rooting.
2. **Censorship & Deep Packet Inspection (DPI):** Transport encryption protects payload content; however, metadata (IP endpoints, packet timing) remains subject to ISP/state censorship. Phase 12+ transport plugins (Shadowsocks, Reality) mitigate DPI detection.
3. **Malicious Upstream Subscriptions:** Input bounding and sanitization prevent client crashes and code execution from untrusted subscription feeds, but do not replace provider trust.







