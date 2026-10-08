// SPDX-License-Identifier: GPL-3.0-or-later

/// Brick VPN's native Android VPN engine, packaged as a Flutter platform
/// plugin (P3-T11), with its type-safe bridge (P3-T12).
///
/// ## What this package exposes today
///
///  - **P3-T11** — the proven Gate A native engine (`BrickVpnService`,
///    `VpnStateMachine`, `LibboxTunnelEngine` + real libbox) as an installable
///    Flutter Android platform plugin.
///  - **P3-T12** — the Pigeon-generated, type-safe bridge declared in
///    `pigeons/vpn_api.dart`: a `VpnEngineHostApi` client for `prepare`,
///    `start`, `stop` and `getStatus`, plus two structurally independent
///    `EventChannel` streams (`stateEvents`, `trafficStatsEvents`).
///
/// ## What is deliberately still absent
///
///  - The **Kotlin host-side implementation** of that API is **P3-T13**.
///    Nothing here registers a host handler yet, so calling the client before
///    P3-T13 will surface as a `PlatformException` — that is expected.
///  - `AndroidVpnEngine implements VpnEngine` (the `core_vpn_engine`
///    contract) is **P3-T14**, as is the Riverpod binding in **P3-T15**.
///
/// ## Why this is generated rather than hand-written
///
/// `ARCHITECTURE.md` Section 3.5 requires Pigeon-generated type-safe channels
/// and forbids hand-written `MethodChannel` string keys or raw argument maps.
/// Regenerate with:
///
/// ```sh
/// cd packages/vpn_engine_android && dart run pigeon --input pigeons/vpn_api.dart
/// ```
///
/// The generated `.g.dart`/`.g.kt` are committed (matching this repo's
/// Riverpod codegen convention) and must not be edited by hand.
library;

export 'src/vpn_engine_api.g.dart';
