// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Disconnecting,
        Error,
        InvalidConfig,
        PermissionDenied,
        ServerProfile;
import 'package:core_vpn_engine/core_vpn_engine.dart'
    show
        VpnCommandAccepted,
        VpnCommandRejectedInvalidConfig,
        VpnCommandRejectedPermissionDenied,
        VpnEngine;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart'
    show SavedServerProfile;
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';

/// Represents the discrete lifecycle states of the automatic reconnection
/// coordinator.
@immutable
sealed class AutoReconnectState {
  const AutoReconnectState();
}

/// Auto-reconnect is idle. No reconnection attempt is scheduled or running.
@immutable
final class AutoReconnectIdle extends AutoReconnectState {
  const AutoReconnectIdle();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AutoReconnectIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The device is currently offline. Reconnect attempts are paused until
/// connectivity is restored.
@immutable
final class AutoReconnectWaitingForNetwork extends AutoReconnectState {
  const AutoReconnectWaitingForNetwork({required this.attempt});

  /// The current attempt index that will be executed once network returns.
  final int attempt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoReconnectWaitingForNetwork && other.attempt == attempt;

  @override
  int get hashCode => Object.hash(runtimeType, attempt);
}

/// The coordinator is waiting on an exponential backoff timer before the next
/// attempt.
@immutable
final class AutoReconnectBackoff extends AutoReconnectState {
  const AutoReconnectBackoff({
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
  });

  /// The 1-based attempt index about to be executed.
  final int attempt;

  /// The maximum allowed retry attempts before giving up.
  final int maxAttempts;

  /// The duration of the current backoff delay.
  final Duration delay;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoReconnectBackoff &&
          other.attempt == attempt &&
          other.maxAttempts == maxAttempts &&
          other.delay == delay;

  @override
  int get hashCode => Object.hash(runtimeType, attempt, maxAttempts, delay);
}

/// A reconnection attempt is actively executing (dispatching to engine).
@immutable
final class AutoReconnectInFlight extends AutoReconnectState {
  const AutoReconnectInFlight({
    required this.attempt,
    required this.maxAttempts,
  });

  /// The 1-based attempt index currently in flight.
  final int attempt;

  /// The maximum allowed retry attempts.
  final int maxAttempts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoReconnectInFlight &&
          other.attempt == attempt &&
          other.maxAttempts == maxAttempts;

  @override
  int get hashCode => Object.hash(runtimeType, attempt, maxAttempts);
}

/// The maximum retry budget was exhausted without establishing a connection.
@immutable
final class AutoReconnectExhausted extends AutoReconnectState {
  const AutoReconnectExhausted({required this.totalAttempts});

  /// Total number of failed attempts made.
  final int totalAttempts;

  /// Alias for [totalAttempts].
  int get attemptsTaken => totalAttempts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoReconnectExhausted && other.totalAttempts == totalAttempts;

  @override
  int get hashCode => Object.hash(runtimeType, totalAttempts);
}

/// Extension providing convenience queries on [AutoReconnectState].
extension AutoReconnectStateX on AutoReconnectState {
  /// Whether auto-reconnect is currently active (waiting, backing off, or
  /// in-flight).
  bool get isReconnecting =>
      this is AutoReconnectWaitingForNetwork ||
      this is AutoReconnectBackoff ||
      this is AutoReconnectInFlight;
}

/// Policy configuring exponential backoff and retry limits for auto-reconnect.
class AutoReconnectPolicy {
  const AutoReconnectPolicy({
    this.maxRetries = 5,
    this.initialBackoff = const Duration(seconds: 1),
    this.backoffMultiplier = 2,
    this.maxBackoff = const Duration(seconds: 30),
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  /// Maximum reconnection attempts before stopping.
  final int maxRetries;

  /// Delay for the first retry attempt.
  final Duration initialBackoff;

  /// Multiplier applied on each subsequent retry attempt.
  final int backoffMultiplier;

  /// Maximum ceiling cap for backoff delay.
  final Duration maxBackoff;

  /// Debounce interval to coalesce rapid network transition events.
  final Duration debounceDuration;

  /// Calculates the backoff delay for a 1-based [attempt] number.
  Duration backoffForAttempt(int attempt) {
    if (attempt <= 1) return initialBackoff;
    var delayMs = initialBackoff.inMilliseconds;
    for (var i = 1; i < attempt; i++) {
      delayMs = (delayMs * backoffMultiplier).clamp(
        0,
        maxBackoff.inMilliseconds,
      );
    }
    return Duration(milliseconds: delayMs);
  }
}

/// Provider exposing the [AutoReconnectPolicy]. Can be overridden in tests.
final autoReconnectPolicyProvider = Provider<AutoReconnectPolicy>((ref) {
  return const AutoReconnectPolicy();
});

/// Coordinates automatic tunnel reconnection on unexpected disconnects and
/// network changes.
///
/// SAFETY INVARIANTS:
/// 1. User Intent: Only reconnects when an active user session is intended
///    ([_userSessionActive] == true). If disconnected cleanly by user or
///    on app boot, network changes NEVER trigger an unsolicited connection.
/// 2. Idempotent & Single-Flight: Coalesces rapid network flapping via debounce
///    and guards against overlapping concurrent connection dispatches.
/// 3. Bounded Backoff: Retries follow exponential backoff capped at
///    [AutoReconnectPolicy.maxBackoff], stopping after
///    [AutoReconnectPolicy.maxRetries].
/// 4. Cancellation: User can cancel/disconnect at any time, immediately
///    stopping all timers and returning to clean idle.
class AutoReconnectNotifier extends Notifier<AutoReconnectState> {
  bool _userSessionActive = false;
  ServerProfile? _activeProfile;
  int _currentAttempt = 0;
  Timer? _backoffTimer;
  Timer? _debounceTimer;
  List<ConnectivityResult> _lastConnectivity = const <ConnectivityResult>[];

  /// The last PHYSICAL bearer set observed, remembered across emissions that
  /// carry no physical transport at all.
  ///
  /// Android can report `[vpn]` (or `[none]`) in the moment Wi-Fi drops while
  /// our tunnel is still up. Deriving "previous bearer" from the last raw
  /// emission would then compare the next `[mobile, vpn]` against nothing and
  /// silently miss the Wi-Fi -> Cellular handoff, so the bearer is kept until a
  /// real one replaces it.
  Set<ConnectivityResult> _lastPhysicalTransports =
      const <ConnectivityResult>{};
  bool _connectivityInitialized = false;
  bool _isExecuting = false;
  bool _isStoppingForReconnect = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Whether there is currently an active user-intended session.
  bool get isUserSessionActive => _userSessionActive;

  /// The active profile targeted for reconnection.
  ServerProfile? get activeProfile => _activeProfile;

  /// The current retry attempt index.
  int get currentAttempt => _currentAttempt;

  @override
  AutoReconnectState build() {
    ref.onDispose(() {
      _cancelTimers();
      unawaited(_connectivitySub?.cancel());
    });

    final connSource = ref.watch(connectivitySourceProvider);
    unawaited(
      connSource.checkConnectivity().then((initial) {
        _lastConnectivity = List<ConnectivityResult>.unmodifiable(initial);
        _rememberPhysicalTransports(initial);
        _connectivityInitialized = true;
      }),
    );
    _connectivitySub = connSource.onConnectivityChanged.listen(
      _handleConnectivityEvent,
    );

    // 1. Listen to connection state transitions from the engine
    ref.listen<AsyncValue<ConnectionState>>(connectionStateProvider, (
      previous,
      next,
    ) {
      final conn = next.value;
      if (conn is Connected) {
        if (!_userSessionActive) {
          _userSessionActive = true;
          _activeProfile ??= ref.read(activeServerProvider)?.profile;
        }
        final wasReconnecting = state.isReconnecting;
        _cancelTimers();
        _currentAttempt = 0;
        state = const AutoReconnectIdle();
        if (wasReconnecting) {
          _logDiagnostic('Auto-reconnect succeeded. Tunnel re-established.');
        }
      } else if (conn is Connecting) {
        if (!_userSessionActive) {
          _userSessionActive = true;
          _activeProfile ??= ref.read(activeServerProvider)?.profile;
        }
      } else if (conn is Error) {
        if (_isExecuting || _isStoppingForReconnect) {
          return;
        }
        if (conn.reason is InvalidConfig || conn.reason is PermissionDenied) {
          _userSessionActive = false;
          _activeProfile = null;
          _cancelTimers();
          state = const AutoReconnectIdle();
          _logDiagnostic(
            'Non-recoverable error (${conn.reason.runtimeType}). '
            'Auto-reconnect cancelled.',
          );
          return;
        }
        if (_userSessionActive) {
          if (state is AutoReconnectInFlight) {
            state = const AutoReconnectIdle();
          }
          // Unexpected drop while user session is active!
          _handleUnexpectedDrop();
        }
      } else if (conn is Disconnected) {
        if (_isExecuting || _isStoppingForReconnect) {
          return;
        }
        if (_userSessionActive) {
          if (state is AutoReconnectInFlight) {
            state = const AutoReconnectIdle();
          }
          // Unexpected drop while user session is active!
          _handleUnexpectedDrop();
        }
      }
    });

    final initialConn =
        ref.read(connectionStateProvider).value ??
        ref.read(initialConnectionStateProvider);
    if (initialConn is Connected || initialConn is Connecting) {
      _userSessionActive = true;
      _activeProfile ??= ref.read(activeServerProvider)?.profile;
    }

    ref.listen<SavedServerProfile?>(activeServerProvider, (previous, next) {
      if (_userSessionActive && next != null) {
        _activeProfile ??= next.profile;
      }
    });

    return const AutoReconnectIdle();
  }

  /// Extracts only the underlying PHYSICAL transports from a
  /// `connectivity_plus` emission.
  ///
  /// `ConnectivityResult.none` carries no transport and
  /// `ConnectivityResult.vpn` is our own tunnel rather than a physical link,
  /// so both are dropped. What remains is the real bearer set (wi-fi, mobile,
  /// ethernet, bluetooth, ...), which is the only thing a "handoff" can mean.
  static Set<ConnectivityResult> _physicalTransports(
    List<ConnectivityResult> results,
  ) {
    return <ConnectivityResult>{
      for (final result in results)
        if (result != ConnectivityResult.none &&
            result != ConnectivityResult.vpn)
          result,
    };
  }

  /// Whether [results] describes a device with NO usable physical bearer.
  ///
  /// `[ConnectivityResult.vpn]` alone means our own tunnel exists while the
  /// underlying link is gone, so it is offline for reconnect purposes: counting
  /// it as online burned the whole retry budget against a dead uplink.
  static bool _isEffectivelyOffline(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every(
          (result) =>
              result == ConnectivityResult.none ||
              result == ConnectivityResult.vpn,
        );
  }

  /// Remembers [results]' physical bearers, ignoring emissions without any.
  void _rememberPhysicalTransports(List<ConnectivityResult> results) {
    final physical = _physicalTransports(results);
    if (physical.isEmpty) return;
    _lastPhysicalTransports = Set<ConnectivityResult>.unmodifiable(physical);
  }

  void _handleUnexpectedDrop() {
    final prefs = ref.read(appPreferencesRepositoryProvider);
    if (!prefs.isAutoReconnectEnabled()) {
      _logDiagnostic(
        'Drop detected, but auto-reconnect is disabled in settings.',
      );
      return;
    }

    final isOffline =
        _connectivityInitialized && _isEffectivelyOffline(_lastConnectivity);
    if (isOffline) {
      state = AutoReconnectWaitingForNetwork(attempt: _currentAttempt);
      _logDiagnostic('Tunnel dropped while offline. Waiting for network.');
      return;
    }

    _scheduleReconnect();
  }

  void _handleConnectivityEvent(List<ConnectivityResult> results) {
    final policy = ref.read(autoReconnectPolicyProvider);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(policy.debounceDuration, () {
      _processDebouncedConnectivity(results);
    });
  }

  void _processDebouncedConnectivity(List<ConnectivityResult> results) {
    _connectivityInitialized = true;
    _lastConnectivity = List<ConnectivityResult>.unmodifiable(results);

    if (!_userSessionActive) {
      _rememberPhysicalTransports(results);
      return;
    }

    final prevPhysical = _lastPhysicalTransports;
    final nextPhysical = _physicalTransports(results);
    // Remember the bearer only when this emission actually HAS one: an
    // intermediate `[vpn]` / `[none]` must never erase Wi-Fi, or the following
    // Wi-Fi -> Cellular handoff would compare against an empty set and be
    // missed entirely.
    if (nextPhysical.isNotEmpty && !setEquals(prevPhysical, nextPhysical)) {
      _lastPhysicalTransports = Set<ConnectivityResult>.unmodifiable(
        nextPhysical,
      );
    }

    if (_isEffectivelyOffline(results)) {
      _backoffTimer?.cancel();
      _backoffTimer = null;
      state = AutoReconnectWaitingForNetwork(attempt: _currentAttempt);
      return;
    }

    // Check if network interface changed while connected.
    //
    // Only PHYSICAL transports count. `connectivity_plus` v6+ surfaces
    // Android's own VPN interface as `ConnectivityResult.vpn`, so bringing
    // OUR tunnel up turns `[wifi]` into `[wifi, vpn]`. Comparing raw result
    // lists therefore manufactured a "handoff" on every tunnel start and made
    // the app stop its own tunnel ~350 ms after `state -> Running`, forever.
    final connState = ref.read(connectionStateProvider).value;
    final interfaceChanged =
        prevPhysical.isNotEmpty &&
        nextPhysical.isNotEmpty &&
        !setEquals(prevPhysical, nextPhysical);

    // Device returned online from offline.
    if (state is AutoReconnectWaitingForNetwork) {
      if (connState is! Connected) {
        _scheduleReconnect();
        return;
      }
      if (!interfaceChanged) {
        // Same bearer came back and the tunnel never went down: nothing to do.
        state = const AutoReconnectIdle();
        return;
      }
      // A different physical bearer returned while the tunnel survived, so the
      // handoff restart below must run (a plain `_scheduleReconnect()` would
      // bail out precisely because the tunnel is still `Connected`).
    }

    if (connState is Connected && interfaceChanged) {
      // The handoff restart is an automatic tunnel restart, so it obeys the
      // same user preference as every other automatic restart: an explicit
      // disable in Settings must never be overridden by a network event.
      final prefs = ref.read(appPreferencesRepositoryProvider);
      if (!prefs.isAutoReconnectEnabled()) {
        _logDiagnostic(
          'Physical interface handoff detected, but auto-reconnect is '
          'disabled in settings. Leaving tunnel untouched.',
        );
        return;
      }
      _logDiagnostic(
        'Interface handoff detected while connected. Restarting tunnel.',
      );
      // Stop old stale tunnel to trigger clean reconnection
      final engine = ref.read(vpnEngineProvider);
      unawaited(engine.stop());
      return;
    }

    if (connState is Disconnected || connState is Error) {
      _scheduleReconnect();
    }
  }

  /// Called when the user explicitly initiates a connection from the UI.
  void onUserInitiatedConnect(ServerProfile profile) {
    _userSessionActive = true;
    _activeProfile = profile;
    _currentAttempt = 0;
    _cancelTimers();
    state = const AutoReconnectIdle();
    unawaited(
      ref.read(connectivitySourceProvider).checkConnectivity().then((initial) {
        _lastConnectivity = List<ConnectivityResult>.unmodifiable(initial);
        _rememberPhysicalTransports(initial);
      }),
    );
  }

  /// Called when the user explicitly cancels or disconnects from the UI.
  void onUserInitiatedDisconnect() {
    final wasReconnecting = state.isReconnecting;
    _userSessionActive = false;
    _activeProfile = null;
    _lastPhysicalTransports = const <ConnectivityResult>{};
    _currentAttempt = 0;
    _cancelTimers();
    state = const AutoReconnectIdle();
    if (wasReconnecting) {
      _logDiagnostic('Auto-reconnect cancelled by user.');
    }
  }

  /// Schedules a reconnection attempt following the exponential backoff policy.
  void scheduleReconnect() => _scheduleReconnect();

  void _scheduleReconnect() {
    if (!_userSessionActive) return;

    final prefs = ref.read(appPreferencesRepositoryProvider);
    if (!prefs.isAutoReconnectEnabled()) {
      _logDiagnostic('Auto-reconnect is disabled by user preference.');
      return;
    }

    final currentConn = ref.read(connectionStateProvider).value;
    if (currentConn is Connected) {
      return;
    }

    if (_backoffTimer != null && state is AutoReconnectBackoff) {
      return;
    }

    if (_isExecuting ||
        _isStoppingForReconnect ||
        state is AutoReconnectInFlight) {
      return;
    }

    final isOffline =
        _connectivityInitialized && _isEffectivelyOffline(_lastConnectivity);
    if (isOffline) {
      state = AutoReconnectWaitingForNetwork(attempt: _currentAttempt);
      return;
    }

    final policy = ref.read(autoReconnectPolicyProvider);

    if (_currentAttempt >= policy.maxRetries) {
      _userSessionActive = false;
      _cancelTimers();
      state = AutoReconnectExhausted(totalAttempts: _currentAttempt);
      _logDiagnostic(
        'Auto-reconnect budget exhausted after $_currentAttempt attempts.',
      );
      return;
    }

    _currentAttempt++;
    final delay = policy.backoffForAttempt(_currentAttempt);
    state = AutoReconnectBackoff(
      attempt: _currentAttempt,
      maxAttempts: policy.maxRetries,
      delay: delay,
    );
    _logDiagnostic(
      'Scheduling reconnect attempt $_currentAttempt/${policy.maxRetries} in ${delay.inSeconds}s',
    );

    _backoffTimer?.cancel();
    _backoffTimer = Timer(delay, () {
      _backoffTimer = null;
      unawaited(_executeReconnect());
    });
  }

  Future<void> _executeReconnect() async {
    if (!_userSessionActive) return;
    if (_isExecuting) return;
    _isExecuting = true;

    final policy = ref.read(autoReconnectPolicyProvider);
    state = AutoReconnectInFlight(
      attempt: _currentAttempt,
      maxAttempts: policy.maxRetries,
    );
    _logDiagnostic(
      'Executing reconnect attempt $_currentAttempt/${policy.maxRetries}',
    );

    try {
      final engine = ref.read(vpnEngineProvider);
      final profile = _activeProfile ?? ref.read(activeServerProvider)?.profile;

      if (profile == null) {
        _logDiagnostic('No active server profile available to reconnect.');
        _userSessionActive = false;
        state = const AutoReconnectIdle();
        return;
      }

      final currentState = ref.read(connectionStateProvider).value;
      if (currentState is! Disconnected) {
        _isStoppingForReconnect = true;
        try {
          await engine.stop();
          // `stop()` is accepted as soon as native enters Stopping. Starting a
          // new session before native reaches Stopped races the teardown
          // (the service may be destroyed under the new start).
          await _waitUntilStopped(engine);
        } finally {
          _isStoppingForReconnect = false;
        }
      }

      final prepareResult = await engine.prepare();
      if (prepareResult is! VpnCommandAccepted) {
        if (prepareResult is VpnCommandRejectedPermissionDenied ||
            prepareResult is VpnCommandRejectedInvalidConfig) {
          _userSessionActive = false;
          _activeProfile = null;
          _cancelTimers();
          state = const AutoReconnectIdle();
          _logDiagnostic(
            'Non-recoverable prepare rejection (${prepareResult.runtimeType}). '
            'Auto-reconnect cancelled.',
          );
          return;
        }
        _logDiagnostic(
          'Engine prepare rejected: ${prepareResult.runtimeType}. '
          'Scheduling retry.',
        );
        _isExecuting = false;
        state = const AutoReconnectIdle();
        _scheduleReconnect();
        return;
      }

      final startResult = await engine.start(profile);
      if (startResult is! VpnCommandAccepted) {
        if (startResult is VpnCommandRejectedPermissionDenied ||
            startResult is VpnCommandRejectedInvalidConfig) {
          _userSessionActive = false;
          _activeProfile = null;
          _cancelTimers();
          state = const AutoReconnectIdle();
          _logDiagnostic(
            'Non-recoverable start rejection (${startResult.runtimeType}). '
            'Auto-reconnect cancelled.',
          );
          return;
        }
        _logDiagnostic(
          'Engine start rejected: ${startResult.runtimeType}. '
          'Scheduling retry.',
        );
        _isExecuting = false;
        state = const AutoReconnectIdle();
        _scheduleReconnect();
        return;
      }

      _logDiagnostic('Reconnect tunnel start command accepted.');
    } on Object catch (e) {
      _logDiagnostic(
        'Unexpected exception during reconnect dispatch: ${e.runtimeType}',
      );
      _isExecuting = false;
      state = const AutoReconnectIdle();
      _scheduleReconnect();
    } finally {
      _isExecuting = false;
    }
  }

  /// Awaits the engine's terminal stopped state, bounded.
  ///
  /// Returns immediately when the engine is already [Disconnected] / [Error],
  /// and also when it has not published an in-flight teardown ([Disconnecting])
  /// - in that case there is no observable stop to await, and blocking on a
  /// silent engine would wedge the reconnect path.
  Future<void> _waitUntilStopped(VpnEngine engine) async {
    final current =
        ref.read(connectionStateProvider).value ??
        ref.read(initialConnectionStateProvider);
    if (current is Disconnected || current is Error) return;
    // Only a published teardown ([Disconnecting]) is awaitable; see the same
    // guard in ConnectionController._waitUntilStopped.
    if (current is! Disconnecting) return;
    try {
      await engine.connectionState
          .firstWhere((state) => state is Disconnected || state is Error)
          .timeout(const Duration(seconds: 3));
    } on Object {
      // Bounded: a slow or silent teardown must never wedge the switch.
    }
  }

  void _cancelTimers() {
    _backoffTimer?.cancel();
    _backoffTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _logDiagnostic(String message) {
    try {
      ref.read(logManagerProvider.notifier).recordDiagnostic(message);
    } on Object {
      // Gracefully absorb if LogManager is unavailable in isolated unit tests
    }
  }
}

/// Reactive provider exposing the current [AutoReconnectState].
final autoReconnectProvider =
    NotifierProvider<AutoReconnectNotifier, AutoReconnectState>(
      AutoReconnectNotifier.new,
    );
