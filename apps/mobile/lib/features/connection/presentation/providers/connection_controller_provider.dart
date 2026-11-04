// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Error,
        ServerProfile;
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection_controller_provider.g.dart';

/// Dispatches connect/disconnect intents to the engine.
///
/// This notifier holds **no** connection state of its own. It exists purely
/// to turn a button press into an engine command, and it deliberately does
/// not publish a "connecting"/"connected" value: the UI reads that from
/// `connectionStateProvider`, which is the authoritative stream
/// (`VpnEngine` Invariant 1). If this class also tracked state, the two
/// sources could disagree and the UI would have to pick a winner — the exact
/// design failure that produced the legacy prototype's false "Connected".
///
/// The in-flight guard is the one piece of state kept here, and it guards
/// against a *duplicate command*, not against describing the tunnel: it stops
/// a second tap while the first command is still being dispatched. It is not
/// rendered as connection state.
@riverpod
class ConnectionController extends _$ConnectionController {
  /// Guards against re-dispatching while a command is in flight.
  bool _busy = false;

  /// Tracks the ID of the server currently connecting or connected.
  String? _activeConnectingServerId;

  /// No initial state: this notifier exists only to dispatch commands.
  ///
  /// The exposed state is a never-awaited `AsyncValue<void>` placeholder. It
  /// carries no connection information, which is the point — if this
  /// notifier held a real value, the UI could read it *instead of* the
  /// authoritative stream and recreate the legacy false-"Connected" bug.
  @override
  FutureOr<void> build() {
    ref.keepAlive();
    ref.listen<AsyncValue<ConnectionState>>(connectionStateProvider, (
      previous,
      next,
    ) {
      final state = next.value;
      if (state is Disconnected || state is Error) {
        _activeConnectingServerId = null;
      }
    });
  }

  /// Whether a command is currently being dispatched.
  bool get isBusy => _busy;

  /// The ID of the server currently connecting or connected, if any.
  String? get activeConnectingServerId => _activeConnectingServerId;

  /// Requests a tunnel start for [profile].
  ///
  /// The returned `Future` completes with the [VpnCommandResult] from the
  /// engine (or a rejection if busy / no profile). Callers must not treat its
  /// completion as a connection; watch `connectionStateProvider` instead.
  ///
  /// If another server is currently connected or connecting, cleanly stops it
  /// first before preparing and starting [profile].
  Future<VpnCommandResult> connect(ServerProfile? profile) async {
    if (profile == null) {
      return const VpnCommandFailed();
    }
    if (_busy) {
      return const VpnCommandRejectedBusy();
    }
    _busy = true;
    try {
      final engine = ref.read(vpnEngineProvider);
      final repoFuture = ref.read(serverProfileRepositoryProvider.future);
      final currentState = ref.read(connectionStateProvider).value;
      if (currentState is Connected || currentState is Connecting) {
        if (_activeConnectingServerId != profile.id) {
          await engine.stop();
        }
      }

      final prepareResult = await engine.prepare();
      if (prepareResult is! VpnCommandAccepted) {
        _activeConnectingServerId = null;
        return prepareResult;
      }

      final startResult = await engine.start(profile);
      if (startResult is! VpnCommandAccepted) {
        _activeConnectingServerId = null;
        return startResult;
      }

      _activeConnectingServerId = profile.id;

      try {
        final repo = await repoFuture;
        await repo.save(profile.copyWith(lastUsedAt: DateTime.now().toUtc()));
        if (ref.mounted) {
          ref.invalidate(savedServersProvider);
        }
      } on Object {
        // Graceful fallback: storage failure must not disrupt active tunnel.
      }

      return startResult;
    } finally {
      _busy = false;
    }
  }

  /// Requests a tunnel stop.
  ///
  /// Same acceptance semantics as [connect]: completion means the stop was
  /// accepted, not that the tunnel is down. See `connectionStateProvider`.
  Future<VpnCommandResult> disconnect() async {
    if (_busy) {
      return const VpnCommandRejectedBusy();
    }
    _busy = true;
    try {
      final engine = ref.read(vpnEngineProvider);
      final result = await engine.stop();
      _activeConnectingServerId = null;
      return result;
    } finally {
      _busy = false;
    }
  }
}
