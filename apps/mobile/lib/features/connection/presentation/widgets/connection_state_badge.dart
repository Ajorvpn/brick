// SPDX-License-Identifier: GPL-3.0-or-later

// Flutter's own `ConnectionState` (from `package:flutter/src/widgets/async.dart`)
// collides by name with the domain type; hide Flutter's so the exhaustive
// switch below stays exhaustive over `core_domain`'s five variants.
import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Disconnecting,
        Error;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';

/// Shows the current tunnel state.
///
/// **This widget is the enforcement point for `VpnEngine` Invariant 1.** Its
/// only input is `connectionStateProvider`, i.e. the engine's authoritative
/// `connectionState` stream. It never reads the result of a `start()`/`stop()`
/// command and never infers state from a button press. Before the engine
/// emits anything the badge reads "Disconnected", which is the honest
/// default: an un-emitted stream means no transition has been reported, not
/// that a connection is pending.
///
/// `Error` is deliberately rendered as one generic badge rather than
/// branching on `ConnectionErrorReason`. The reason enum exists so callers
/// *can* branch exhaustively; at this stage the app has no recovery action to
/// offer per reason, so surfacing raw native detail would be noise.
class ConnectionStateBadge extends ConsumerWidget {
  /// Creates the badge.
  const ConnectionStateBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionStateProvider);

    return state.when(
      // Nothing emitted yet: no transition reported, so nothing is connected.
      loading: () => _Badge(label: 'connection.state_disconnected'.tr()),
      error: (error, stackTrace) =>
          _Badge(label: 'connection.state_error'.tr()),
      data: (value) => _Badge(label: _labelFor(value)),
    );
  }

  /// Maps a sealed [ConnectionState] to its localized label.
  ///
  /// Exhaustive over the sealed hierarchy, so adding a variant upstream
  /// becomes a compile-time error here rather than a silent blank badge.
  String _labelFor(ConnectionState value) {
    return switch (value) {
      Disconnected() => 'connection.state_disconnected'.tr(),
      Connecting() => 'connection.state_connecting'.tr(),
      Connected() => 'connection.state_connected'.tr(),
      Disconnecting() => 'connection.state_disconnecting'.tr(),
      Error() => 'connection.state_error'.tr(),
    };
  }
}

/// The badge's visual chrome, kept private so the public widget surface stays
/// one class.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      // The key lets widget tests assert which state is shown without
      // depending on the localized copy.
      key: const ValueKey<String>('connection_state_badge'),
    );
  }
}
