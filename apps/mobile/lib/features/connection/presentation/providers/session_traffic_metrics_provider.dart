// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Disconnecting,
        Error,
        TrafficStats;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/session_traffic_metrics.dart';
import 'package:mobile/features/connection/domain/usecases/session_traffic_metrics_calculator.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';

/// Provides real-time [SessionTrafficMetrics] for the active VPN session.
///
/// Automatically synchronizes with [connectionStateProvider]:
/// - When connected, listens to the engine's traffic stats stream and computes
///   real-time delta throughput and cumulative session bytes.
/// - When transitioning to [Disconnected], [Connecting], or [Error], resets
///   metrics to [SessionTrafficMetrics.zero] and clears the baseline snapshot
///   so stale data never bleeds across sessions.
/// - Adheres to VpnEngine Invariant 2 (Failure Domain Isolation): stats stream
///   errors are absorbed gracefully and never crash the UI or corrupt
///   [connectionStateProvider].
class SessionTrafficMetricsNotifier extends Notifier<SessionTrafficMetrics> {
  final SessionTrafficMetricsCalculator _calculator =
      SessionTrafficMetricsCalculator();
  StreamSubscription<TrafficStats>? _statsSub;

  @override
  SessionTrafficMetrics build() {
    ref.onDispose(() {
      unawaited(_statsSub?.cancel());
    });

    final engine = ref.read(vpnEngineProvider);
    _statsSub = engine.trafficStats.listen(
      (stats) {
        state = _calculator.process(stats);
      },
      onError: (Object error, StackTrace stack) {
        // VpnEngine Invariant 2: Failure domain isolation.
        // Stream errors on traffic stats are absorbed gracefully without
        // disturbing connection state or throwing unhandled exceptions.
        state = state.copyWith(
          txBytesPerSec: 0,
          rxBytesPerSec: 0,
          hasError: true,
        );
      },
    );

    ref.listen<AsyncValue<ConnectionState>>(connectionStateProvider, (
      previous,
      next,
    ) {
      final prevConn = previous?.value;
      final nextConn = next.value;

      if (prevConn is Connected && nextConn is Connected) {
        // Idempotent Connected emission (e.g. lifecycle resume resync):
        // do NOT reset calculator baseline mid-session!
        return;
      }

      if (nextConn is Connected) {
        // Fresh transition into Connected from another state
        _calculator.reset();
        state = SessionTrafficMetrics.zero;
      } else if (nextConn is Disconnected ||
          nextConn is Connecting ||
          nextConn is Error) {
        _calculator.reset();
        state = SessionTrafficMetrics.zero;
      } else if (nextConn is Disconnecting) {
        // Transitioning to Disconnecting: clamp rates to 0 while preserving
        // session-cumulative totals
        state = state.copyWith(txBytesPerSec: 0, rxBytesPerSec: 0);
      }
    });

    return SessionTrafficMetrics.zero;
  }
}

/// Reactive provider exposing the active session's traffic metrics.
final sessionTrafficMetricsProvider =
    NotifierProvider<SessionTrafficMetricsNotifier, SessionTrafficMetrics>(
      SessionTrafficMetricsNotifier.new,
    );
