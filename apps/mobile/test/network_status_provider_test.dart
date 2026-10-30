// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/network_status.dart';
import 'package:mobile/core/network/network_status_provider.dart';

/// Fake implementation of [ConnectivitySource] for hermetic testing.
class FakeConnectivitySource implements ConnectivitySource {
  FakeConnectivitySource({this.initial = const [ConnectivityResult.wifi]})
    : _controller = StreamController<List<ConnectivityResult>>.broadcast();

  final List<ConnectivityResult> initial;
  final StreamController<List<ConnectivityResult>> _controller;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() => Future.value(initial);

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void emit(List<ConnectivityResult> results) => _controller.add(results);

  Future<void> dispose() => _controller.close();
}

void main() {
  group('mapConnectivity — unit tests', () {
    test('maps empty or none-only results to NetworkStatus.offline', () {
      expect(mapConnectivity([]), equals(NetworkStatus.offline));
      expect(
        mapConnectivity([ConnectivityResult.none]),
        equals(NetworkStatus.offline),
      );
      expect(
        mapConnectivity([ConnectivityResult.none, ConnectivityResult.none]),
        equals(NetworkStatus.offline),
      );
    });

    test('maps any active interface to NetworkStatus.online', () {
      expect(
        mapConnectivity([ConnectivityResult.wifi]),
        equals(NetworkStatus.online),
      );
      expect(
        mapConnectivity([ConnectivityResult.mobile]),
        equals(NetworkStatus.online),
      );
      expect(
        mapConnectivity([ConnectivityResult.ethernet]),
        equals(NetworkStatus.online),
      );
      expect(
        mapConnectivity([ConnectivityResult.vpn]),
        equals(NetworkStatus.online),
      );
      expect(
        mapConnectivity([ConnectivityResult.other]),
        equals(NetworkStatus.online),
      );
      expect(
        mapConnectivity([ConnectivityResult.none, ConnectivityResult.wifi]),
        equals(NetworkStatus.online),
      );
    });
  });

  group('networkStatusProvider — stream tests', () {
    test('yields initial status from checkConnectivity', () async {
      final fake = FakeConnectivitySource();
      final container = ProviderContainer(
        overrides: [connectivitySourceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final completer = Completer<NetworkStatus>();
      final sub = container.listen<AsyncValue<NetworkStatus>>(
        networkStatusProvider,
        (previous, next) {
          next.whenData((status) {
            if (!completer.isCompleted) completer.complete(status);
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      expect(await completer.future, equals(NetworkStatus.online));
    });

    test('yields offline if initial checkConnectivity is none', () async {
      final fake = FakeConnectivitySource(
        initial: const [ConnectivityResult.none],
      );
      final container = ProviderContainer(
        overrides: [connectivitySourceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final completer = Completer<NetworkStatus>();
      final sub = container.listen<AsyncValue<NetworkStatus>>(
        networkStatusProvider,
        (previous, next) {
          next.whenData((status) {
            if (!completer.isCompleted) completer.complete(status);
          });
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      expect(await completer.future, equals(NetworkStatus.offline));
    });

    test('translates stream transitions from wifi to none and back', () async {
      final fake = FakeConnectivitySource();
      final container = ProviderContainer(
        overrides: [connectivitySourceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      addTearDown(fake.dispose);

      final emissions = <NetworkStatus>[];
      final sub = container.listen<AsyncValue<NetworkStatus>>(
        networkStatusProvider,
        (previous, next) {
          next.whenData(emissions.add);
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Wait for initial probe emission
      await Future<void>.delayed(Duration.zero);
      expect(emissions, equals([NetworkStatus.online]));

      // Simulate transition to offline
      fake.emit(const [ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(emissions, equals([NetworkStatus.online, NetworkStatus.offline]));

      // Simulate transition to mobile data
      fake.emit(const [ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      expect(
        emissions,
        equals([
          NetworkStatus.online,
          NetworkStatus.offline,
          NetworkStatus.online,
        ]),
      );

      // Duplicate emission is deduplicated by distinct()
      fake.emit(const [ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      expect(
        emissions,
        equals([
          NetworkStatus.online,
          NetworkStatus.offline,
          NetworkStatus.online,
        ]),
      );
    });
  });
}
