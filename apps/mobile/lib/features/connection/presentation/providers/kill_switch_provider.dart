// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Error,
        InvalidConfig,
        PermissionDenied,
        ServerProfile;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';

/// Platform bridge for managing native OS/VpnService kill switch lockdown.
abstract interface class KillSwitchPlatformBridge {
  /// Tells the native platform to engage or release fail-closed lockdown
  /// blocking.
  Future<void> setLockdownBlocking({required bool active});
}

/// Production implementation of [KillSwitchPlatformBridge] invoking
/// `dev.brickvpn.harness/kill_switch` via [MethodChannel].
class MethodChannelKillSwitchPlatformBridge
    implements KillSwitchPlatformBridge {
  const MethodChannelKillSwitchPlatformBridge([
    this._channel = const MethodChannel('dev.brickvpn.harness/kill_switch'),
  ]);

  final MethodChannel _channel;

  @override
  Future<void> setLockdownBlocking({required bool active}) async {
    try {
      await _channel.invokeMethod<void>(
        'setLockdownBlocking',
        <String, dynamic>{'active': active},
      );
    } on MissingPluginException {
      // Gracefully absorbed on platforms/tests without native plugin
    } on PlatformException {
      // Absorbed safely
    }
  }
}

/// Fake implementation of [KillSwitchPlatformBridge] for hermetic testing.
class FakeKillSwitchPlatformBridge implements KillSwitchPlatformBridge {
  final List<bool> blockingHistory = <bool>[];

  /// Whether native lockdown is currently active based on the last call.
  bool get isCurrentlyBlocking =>
      blockingHistory.isNotEmpty && blockingHistory.last;

  @override
  Future<void> setLockdownBlocking({required bool active}) async {
    blockingHistory.add(active);
  }
}

/// Platform bridge provider for [KillSwitchPlatformBridge]. Can be
/// overridden in tests.
final killSwitchPlatformBridgeProvider = Provider<KillSwitchPlatformBridge>((
  ref,
) {
  return const MethodChannelKillSwitchPlatformBridge();
});

/// Represents the discrete lifecycle states of the application kill switch.
@immutable
sealed class KillSwitchState {
  const KillSwitchState();
}

/// Kill switch is inactive.
///
/// Occurs when kill switch is disabled by preference, when the app boots
/// before any tunnel is started, or after the user cleanly disconnects.
/// Traffic outside the VPN is permitted by the OS.
@immutable
final class KillSwitchInactive extends KillSwitchState {
  const KillSwitchInactive();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KillSwitchInactive;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Kill switch is armed and protecting traffic.
///
/// Occurs when kill switch is enabled and the user-intended VPN tunnel is
/// actively [Connected] (or establishing an initial connection).
@immutable
final class KillSwitchArmed extends KillSwitchState {
  const KillSwitchArmed();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KillSwitchArmed;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Kill switch is actively blocking unprotected internet traffic.
///
/// Triggers when the tunnel drops unexpectedly mid-session, during any
/// auto-reconnect backoff/waiting window, or after retry exhaustion, until
/// the user reconnects, unblocks, or disables the kill switch toggle.
@immutable
final class KillSwitchBlocking extends KillSwitchState {
  const KillSwitchBlocking({required this.reason});

  /// Diagnostic identifier explaining why blocking was engaged.
  final String reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KillSwitchBlocking && other.reason == reason);

  @override
  int get hashCode => Object.hash(runtimeType, reason);
}

/// Coordinates kill switch state transitions and leak-protection invariants.
///
/// SAFETY INVARIANTS:
/// 1. Preference Gating: When [killSwitchEnabledProvider] is `false`, the
///    state is strictly [KillSwitchInactive] and never blocks.
/// 2. User Intent: Clean user-initiated disconnects transition directly to
///    [KillSwitchInactive] without ever entering [KillSwitchBlocking].
/// 3. Risk Window Coverage: Any unexpected connection drop, network flapping,
///    auto-reconnect backoff window, or post-retry exhaustion engages
///    [KillSwitchBlocking] to prevent unprotected traffic leaks.
/// 4. Reconnect Restoration: When the tunnel successfully reconnects,
///    the state automatically transitions back to [KillSwitchArmed].
class KillSwitchNotifier extends Notifier<KillSwitchState> {
  bool _userSessionActive = false;

  /// Whether a user session is actively intended.
  bool get isUserSessionActive => _userSessionActive;

  @override
  KillSwitchState build() {
    final enabled = ref.watch(killSwitchEnabledProvider);

    // If disabled in settings, immediately disengage and reset
    if (!enabled) {
      if (_userSessionActive) {
        unawaited(
          ref
              .read(killSwitchPlatformBridgeProvider)
              .setLockdownBlocking(active: false),
        );
      }
      _userSessionActive = false;
      return const KillSwitchInactive();
    }

    // 1. Listen to engine connection state transitions
    ref.listen<AsyncValue<ConnectionState>>(connectionStateProvider, (
      previous,
      next,
    ) {
      if (!ref.read(killSwitchEnabledProvider)) {
        return;
      }

      final conn = next.value;
      if (conn is Connected) {
        _userSessionActive = true;
        if (state is! KillSwitchArmed) {
          final wasBlocking = state is KillSwitchBlocking;
          state = const KillSwitchArmed();
          if (wasBlocking) {
            unawaited(
              ref
                  .read(killSwitchPlatformBridgeProvider)
                  .setLockdownBlocking(active: false),
            );
          }
          _logDiagnostic('KillSwitch armed.');
        }
      } else if (conn is Connecting) {
        if (_userSessionActive && state is! KillSwitchArmed) {
          state = const KillSwitchArmed();
          _logDiagnostic('KillSwitch armed.');
        }
      } else if (conn is Error) {
        if (conn.reason is InvalidConfig || conn.reason is PermissionDenied) {
          // Non-recoverable config/permission rejections
          _userSessionActive = false;
          final wasBlocking = state is KillSwitchBlocking;
          if (state is! KillSwitchInactive) {
            state = const KillSwitchInactive();
            _logDiagnostic('KillSwitch disengaged.');
          }
          if (wasBlocking) {
            unawaited(
              ref
                  .read(killSwitchPlatformBridgeProvider)
                  .setLockdownBlocking(active: false),
            );
          }
          return;
        }

        if (_userSessionActive) {
          _engageBlocking('unexpected_error');
        }
      } else if (conn is Disconnected) {
        if (_userSessionActive) {
          _engageBlocking('unexpected_disconnect');
        }
      }
    });

    // 2. Listen to auto-reconnect state transitions
    ref.listen<AutoReconnectState>(autoReconnectProvider, (previous, next) {
      if (!ref.read(killSwitchEnabledProvider)) {
        return;
      }

      if (next is AutoReconnectWaitingForNetwork ||
          next is AutoReconnectBackoff ||
          next is AutoReconnectInFlight) {
        if (_userSessionActive) {
          _engageBlocking('auto_reconnect_window');
        }
      } else if (next is AutoReconnectExhausted) {
        // Post-retry exhaustion: keep blocking until user unblocks or disables
        _engageBlocking('auto_reconnect_exhausted');
      }
    });

    // Defect D5 fix: verify current connection/auto-reconnect state on build
    final autoReconnect = ref.read(autoReconnectProvider);
    final isSessionActive = ref
        .read(autoReconnectProvider.notifier)
        .isUserSessionActive;
    final currentConn =
        ref.read(connectionStateProvider).value ??
        ref.read(initialConnectionStateProvider);

    if (currentConn is Connected ||
        (currentConn is Connecting && isSessionActive)) {
      _userSessionActive = true;
      _logDiagnostic('KillSwitch armed.');
      return const KillSwitchArmed();
    }

    if (autoReconnect.isReconnecting ||
        autoReconnect is AutoReconnectExhausted ||
        (isSessionActive &&
            (currentConn is Error || currentConn is Disconnected))) {
      _userSessionActive = true;
      unawaited(
        ref
            .read(killSwitchPlatformBridgeProvider)
            .setLockdownBlocking(active: true),
      );
      _logDiagnostic('KillSwitch actively blocking unprotected traffic.');
      return const KillSwitchBlocking(reason: 'enabled_during_drop');
    }

    return const KillSwitchInactive();
  }

  /// Engages [KillSwitchBlocking] if not already blocking.
  void _engageBlocking(String reason) {
    if (state is! KillSwitchBlocking) {
      state = KillSwitchBlocking(reason: reason);
      unawaited(
        ref
            .read(killSwitchPlatformBridgeProvider)
            .setLockdownBlocking(active: true),
      );
      _logDiagnostic('KillSwitch actively blocking unprotected traffic.');
    }
  }

  /// Called when the user initiates a connection.
  void onUserInitiatedConnect(ServerProfile profile) {
    _userSessionActive = true;
    if (ref.read(killSwitchEnabledProvider)) {
      final wasBlocking = state is KillSwitchBlocking;
      state = const KillSwitchArmed();
      if (wasBlocking) {
        unawaited(
          ref
              .read(killSwitchPlatformBridgeProvider)
              .setLockdownBlocking(active: false),
        );
      }
      _logDiagnostic('KillSwitch armed.');
    }
  }

  /// Called when the user initiates a disconnect or taps the unblock action.
  void onUserInitiatedDisconnect() {
    _userSessionActive = false;
    final wasBlocking = state is KillSwitchBlocking;
    if (state is! KillSwitchInactive) {
      state = const KillSwitchInactive();
      _logDiagnostic('KillSwitch disengaged.');
    }
    if (wasBlocking) {
      unawaited(
        ref
            .read(killSwitchPlatformBridgeProvider)
            .setLockdownBlocking(active: false),
      );
    }
  }

  /// Explicitly disengages kill switch protection.
  void disengage() {
    onUserInitiatedDisconnect();
  }

  void _logDiagnostic(String message) {
    try {
      ref.read(logManagerProvider.notifier).recordDiagnostic(message);
    } on Object {
      // Gracefully absorb if LogManager is unavailable in isolated unit tests
    }
  }
}

/// Reactive provider exposing the current [KillSwitchState].
final killSwitchProvider =
    NotifierProvider<KillSwitchNotifier, KillSwitchState>(
      KillSwitchNotifier.new,
    );
