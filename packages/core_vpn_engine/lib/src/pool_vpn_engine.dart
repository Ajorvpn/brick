// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';

import 'vpn_command_result.dart';
import 'vpn_engine.dart';

/// Optional capability interface for [VpnEngine] implementations that can
/// start a native failover pool (e.g. a sing-box `urltest` outbound group)
/// over multiple ordered candidate profiles.
///
/// Defined as a separate `interface class` rather than adding a method onto
/// [VpnEngine] so existing engine implementations and test doubles do not need
/// breaking changes. Callers check `engine is PoolVpnEngine` and fall back to
/// [VpnEngine.start] otherwise.
abstract interface class PoolVpnEngine implements VpnEngine {
  /// Starts the VPN tunnel using [primary] as the primary/metadata profile
  /// and [candidates] as an ordered failover pool (typically including
  /// [primary] first).
  ///
  /// When fewer than two valid candidates are available, implementations
  /// should transparently fall back to single-outbound [start] semantics.
  Future<VpnCommandResult> startPool(
    ServerProfile primary,
    List<ServerProfile> candidates,
  );
}
