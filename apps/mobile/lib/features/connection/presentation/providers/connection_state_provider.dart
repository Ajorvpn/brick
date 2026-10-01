// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection_state_provider.g.dart';

/// Exposes the engine's authoritative [VpnEngine.connectionState] stream.
///
/// This is the **only** source the UI is allowed to render connection state
/// from. `VpnEngine` Invariant 1 (`vpn_engine.dart`) states that `start()`
/// and `stop()` report only whether a command was *accepted*, and that the
/// real lifecycle transition arrives exclusively on this stream; the
/// legacy prototype coupled the two and displayed "Connected" over a dead
/// tunnel, which is the exact bug `connection/presentation/README.md`
/// forbids repeating.
///
/// Reading `vpnEngineProvider` here (rather than accepting the engine as a
/// parameter) keeps this provider working under a plain
/// `overrideWithValue` in tests while still resolving the real keepAlive
/// engine in the app.
@riverpod
Stream<ConnectionState> connectionState(Ref ref) {
  return ref.watch(vpnEngineProvider).connectionState;
}

/// Exposes the engine's [VpnEngine.trafficStats] stream.
///
/// Separate from [connectionState] on purpose: `VpnEngine` Invariant 2
/// declares them independent failure domains, and funnelling both through a
/// single provider would reintroduce the coupling the invariant exists to
/// prevent. A stats-pipeline failure therefore cannot disturb the connection
/// badge.
@riverpod
Stream<TrafficStats> trafficStats(Ref ref) {
  return ref.watch(vpnEngineProvider).trafficStats;
}
