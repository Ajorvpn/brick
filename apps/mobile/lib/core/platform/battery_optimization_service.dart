// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Platform bridge contract for querying and requesting battery optimization
/// exemption on Android.
abstract interface class BatteryOptimizationService {
  /// Checks whether the application is currently exempted from OS battery
  /// optimization (Doze mode, background restrictions).
  Future<bool> isIgnoringBatteryOptimizations();

  /// Prompts the user or requests exclusion from OS battery optimization via
  /// Android system settings dialog.
  ///
  /// Returns `true` if the platform intent was successfully dispatched.
  Future<bool> requestIgnoreBatteryOptimizations();
}

/// Production implementation of [BatteryOptimizationService] communicating over
/// the `dev.brickvpn.harness/battery_optimization` MethodChannel.
class MethodChannelBatteryOptimizationService
    implements BatteryOptimizationService {
  const MethodChannelBatteryOptimizationService([
    this._channel = const MethodChannel(
      'dev.brickvpn.harness/battery_optimization',
    ),
  ]);

  final MethodChannel _channel;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// In-memory fake implementation of [BatteryOptimizationService] for hermetic
/// testing.
class FakeBatteryOptimizationService implements BatteryOptimizationService {
  FakeBatteryOptimizationService({
    this.isIgnoring = false,
    this.autoGrantOnRequest = true,
  });

  /// Whether battery optimization is currently ignored.
  bool isIgnoring;

  /// Whether [requestIgnoreBatteryOptimizations] automatically grants
  /// exemption (mutates [isIgnoring] to true) or leaves it unchanged.
  final bool autoGrantOnRequest;

  /// Recorded number of times [requestIgnoreBatteryOptimizations] was called.
  int requestCalls = 0;

  /// Recorded number of times [isIgnoringBatteryOptimizations] was called.
  int checkCalls = 0;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    checkCalls++;
    return isIgnoring;
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    requestCalls++;
    if (autoGrantOnRequest) {
      isIgnoring = true;
    }
    return true;
  }
}

/// Provider for the platform [BatteryOptimizationService]. Can be overridden
/// in tests.
final batteryOptimizationServiceProvider = Provider<BatteryOptimizationService>(
  (ref) => const MethodChannelBatteryOptimizationService(),
);

/// Coordinates reactive state for battery optimization exemption.
class BatteryOptimizationIgnoredNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final service = ref.watch(batteryOptimizationServiceProvider);

    // Re-check exemption whenever user returns to the app from the OS
    // battery optimization settings dialog.
    final listener = AppLifecycleListener(onResume: () => unawaited(refresh()));
    ref.onDispose(listener.dispose);

    return await service.isIgnoringBatteryOptimizations();
  }

  /// Re-queries the native platform to refresh exemption status.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(batteryOptimizationServiceProvider);
      return await service.isIgnoringBatteryOptimizations();
    });
  }

  /// Requests battery optimization exemption from the OS and updates state.
  Future<bool> requestExemption() async {
    final service = ref.read(batteryOptimizationServiceProvider);
    final launched = await service.requestIgnoreBatteryOptimizations();
    if (launched) {
      final current = await service.isIgnoringBatteryOptimizations();
      state = AsyncValue.data(current);
      return current;
    }
    return false;
  }
}

/// Reactive provider exposing whether the app is exempt from battery limits.
final batteryOptimizationIgnoredProvider =
    AsyncNotifierProvider<BatteryOptimizationIgnoredNotifier, bool>(
      BatteryOptimizationIgnoredNotifier.new,
    );
