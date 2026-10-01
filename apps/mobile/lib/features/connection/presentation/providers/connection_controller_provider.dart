// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart' show ServerProfile;
import 'package:mobile/core/providers/vpn_engine_provider.dart';
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

  /// No initial state: this notifier exists only to dispatch commands.
  ///
  /// The exposed state is a never-awaited `AsyncValue<void>` placeholder. It
  /// carries no connection information, which is the point — if this
  /// notifier held a real value, the UI could read it *instead of* the
  /// authoritative stream and recreate the legacy false-"Connected" bug.
  @override
  FutureOr<void> build() {}

  /// Whether a command is currently being dispatched.
  bool get isBusy => _busy;

  /// Requests a tunnel start for [profile].
  ///
  /// The returned `Future` completes when the command has been *accepted*,
  /// which is NOT the same as being connected. Callers must not treat its
  /// completion as a connection; watch `connectionStateProvider` instead.
  ///
  /// A no-op when a command is already in flight, or when [profile] is
  /// null. Returns whether a command was actually dispatched.
  Future<bool> connect(ServerProfile? profile) async {
    if (profile == null || _busy) {
      return false;
    }
    _busy = true;
    try {
      await ref.read(vpnEngineProvider).start(profile);
      return true;
    } finally {
      _busy = false;
    }
  }

  /// Requests a tunnel stop.
  ///
  /// Same acceptance semantics as [connect]: completion means the stop was
  /// accepted, not that the tunnel is down. See `connectionStateProvider`.
  Future<bool> disconnect() async {
    if (_busy) {
      return false;
    }
    _busy = true;
    try {
      await ref.read(vpnEngineProvider).stop();
      return true;
    } finally {
      _busy = false;
    }
  }
}
