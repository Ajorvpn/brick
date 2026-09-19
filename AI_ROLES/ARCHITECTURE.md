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
treated as a P0 bug, never as acceptable behavior.
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
(This table is appended to, never rewritten, as new major decisions are
made throughout the project.)