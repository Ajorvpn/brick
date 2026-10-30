// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mobile/core/network/network_status.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_status_provider.g.dart';

/// Data source contract abstracting the underlying network connectivity probe.
///
/// Ensures the domain and presentation layers are completely isolated from
/// third-party connectivity plugins and platform channels.
abstract interface class ConnectivitySource {
  /// Stream of raw connectivity change emissions.
  Stream<List<ConnectivityResult>> get onConnectivityChanged;

  /// Retrieves the current snapshot of active network interfaces.
  Future<List<ConnectivityResult>> checkConnectivity();
}

/// Production implementation of [ConnectivitySource] backed by
/// `connectivity_plus`.
class RealConnectivitySource implements ConnectivitySource {
  /// Creates a connectivity source wrapping [connectivity] (defaults to
  /// singleton).
  RealConnectivitySource([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() =>
      _connectivity.checkConnectivity();
}

/// Maps a list of [ConnectivityResult] values to a high-level [NetworkStatus].
///
/// In `connectivity_plus` v6+, multiple active interfaces can be reported.
/// If the list is empty or contains ONLY [ConnectivityResult.none], the device
/// is considered [NetworkStatus.offline]. If any interface is connected (e.g.
/// Wi-Fi, mobile, ethernet, VPN), the device is [NetworkStatus.online].
NetworkStatus mapConnectivity(List<ConnectivityResult> results) {
  if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
    return NetworkStatus.offline;
  }
  return NetworkStatus.online;
}

/// Provider exposing the [ConnectivitySource] abstraction.
///
/// Can be overridden in tests with a fake implementation to avoid invoking
/// native platform channels.
@Riverpod(keepAlive: true)
ConnectivitySource connectivitySource(Ref ref) {
  return RealConnectivitySource();
}

/// Exposes the app-wide network reachability stream.
///
/// This provider is OBSERVABILITY ONLY (per P4-T4). It must not be wired into
/// any reactive reconnect logic, which is strictly deferred to Phase 7.
@Riverpod(keepAlive: true)
Stream<NetworkStatus> networkStatus(Ref ref) async* {
  final source = ref.watch(connectivitySourceProvider);

  // 1. Initial snapshot probe
  final initial = await source.checkConnectivity();
  var current = mapConnectivity(initial);
  yield current;

  // 2. Stream subsequent connectivity change events with deduplication
  await for (final results in source.onConnectivityChanged) {
    final next = mapConnectivity(results);
    if (next != current) {
      current = next;
      yield current;
    }
  }
}
