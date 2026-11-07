// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Disconnecting,
        Error;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';

/// Tracks active connection session duration via a 1 Hz timer.
///
/// Automatically synchronizes with the engine's authoritative
/// [connectionStateProvider]:
/// - Starts a 1-second periodic timer upon transition to [Connected].
/// - Idempotent against consecutive [Connected] emissions (e.g. lifecycle
///   resumes), maintaining session continuity without resetting mid-session.
/// - Cancels timer and resets duration to [Duration.zero] on any exit from
///   [Connected] (e.g. [Disconnecting], [Disconnected], [Connecting], [Error]).
/// - Cancels timer when disposed.
class SessionDurationNotifier extends Notifier<Duration> {
  Timer? _timer;

  @override
  Duration build() {
    ref.onDispose(() {
      _timer?.cancel();
    });

    ref.listen<AsyncValue<ConnectionState>>(connectionStateProvider, (
      previous,
      next,
    ) {
      final prevConn = previous?.value;
      final nextConn = next.value;

      if (prevConn is Connected && nextConn is Connected) {
        // Idempotent Connected emission (e.g. lifecycle resume resync):
        // do not reset timer mid-session!
        return;
      }

      if (nextConn is Connected) {
        state = Duration.zero;
        _startTimer();
      } else {
        _stopTimer();
      }
    });

    final initialConn =
        ref.read(connectionStateProvider).value ??
        ref.read(initialConnectionStateProvider);
    if (initialConn is Connected) {
      _startTimer();
    }

    return Duration.zero;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state + const Duration(seconds: 1);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    state = Duration.zero;
  }
}

/// Reactive provider exposing the current session elapsed duration.
final sessionDurationProvider =
    NotifierProvider<SessionDurationNotifier, Duration>(
      SessionDurationNotifier.new,
    );
