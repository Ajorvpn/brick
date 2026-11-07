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
import 'package:mobile/core/providers/app_preferences_provider.dart';
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
      final prevConn =
          previous?.value ??
          (previous?.isLoading == true
              ? ref.read(initialConnectionStateProvider)
              : null);
      final nextConn = next.value;

      if (prevConn is Connected && nextConn is Connected) {
        // Idempotent Connected emission (e.g. lifecycle resume resync or
        // initial microtask settling): do not reset timer mid-session!
        return;
      }

      final prefs = ref.read(appPreferencesRepositoryProvider);
      if (nextConn is Connected) {
        final now = DateTime.now().toUtc();
        if (prevConn != null && prevConn is! Connected) {
          // Brand-new connection handshake just completed in this session:
          // ALWAYS start fresh from zero.
          unawaited(prefs.setActiveSessionStartedAt(now));
          state = Duration.zero;
        } else {
          // Initial stream resolution re-attaching to an already-Connected
          // background session: restore elapsed time from persistent storage.
          final existingStart = prefs.getActiveSessionStartedAt();
          if (existingStart == null) {
            unawaited(prefs.setActiveSessionStartedAt(now));
            state = Duration.zero;
          } else {
            final elapsed = now.difference(existingStart);
            state = elapsed.isNegative ? Duration.zero : elapsed;
          }
        }
        _startTimer();
      } else {
        unawaited(prefs.setActiveSessionStartedAt(null));
        _stopTimer();
      }
    });

    final initialConn =
        ref.read(connectionStateProvider).value ??
        ref.read(initialConnectionStateProvider);
    var initialDuration = Duration.zero;
    final prefs = ref.read(appPreferencesRepositoryProvider);
    if (initialConn is Connected) {
      final startedAt = prefs.getActiveSessionStartedAt();
      if (startedAt != null) {
        final elapsed = DateTime.now().toUtc().difference(startedAt);
        initialDuration = elapsed.isNegative ? Duration.zero : elapsed;
      } else {
        unawaited(prefs.setActiveSessionStartedAt(DateTime.now().toUtc()));
      }
      _startTimer();
    } else if (initialConn != null) {
      // Clean up any stale persisted timestamp if previous session was killed
      // while UI was dead.
      unawaited(prefs.setActiveSessionStartedAt(null));
    }

    return initialDuration;
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
