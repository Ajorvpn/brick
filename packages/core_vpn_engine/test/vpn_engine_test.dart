// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:test/test.dart';

/// Minimal fake proving the `VpnEngine` contract is implementable without
/// Flutter, a device, or native code — the property P1-T5's MockVpnEngine
/// will build on. Each stream is backed by its OWN controller, structurally
/// enforcing the independent-failure-domains invariant.
class _FakeVpnEngine implements VpnEngine {
  _FakeVpnEngine(this.initialState);

  final ConnectionState initialState;
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _statsController = StreamController<TrafficStats>.broadcast();

  /// Pushes a stats snapshot through the stats pipeline only.
  void emitStats(TrafficStats stats) {
    _statsController.add(stats);
  }

  /// Pushes a state transition through the state pipeline only.
  void emitState(ConnectionState state) {
    _stateController.add(state);
  }

  void dispose() {
    unawaited(_stateController.close());
    unawaited(_statsController.close());
  }

  @override
  Stream<ConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<TrafficStats> get trafficStats => _statsController.stream;

  @override
  Future<VpnCommandResult> start(ServerProfile profile) async {
    return const VpnCommandAccepted();
  }

  @override
  Future<VpnCommandResult> stop() async => const VpnCommandAccepted();

  @override
  Future<ConnectionState> getStatus() async => initialState;
}

ServerProfile buildProfile() => ServerProfile(
  id: 'p-1',
  name: 'Test server',
  config: VlessOutbound(server: 'v.example', serverPort: 443, uuid: 'u'),
  addedAt: DateTime.utc(2026, 9, 21),
);

void main() {
  group('interface contract shape', () {
    test('a plain Dart class can implement the full contract', () {
      final engine = _FakeVpnEngine(const Disconnected());
      expect(engine, isA<VpnEngine>());
    });

    test(
      'start accepts a ServerProfile and returns Future<VpnCommandResult>',
      () async {
        final engine = _FakeVpnEngine(const Disconnected());
        addTearDown(engine.dispose);
        final result = await engine.start(buildProfile());
        expect(result, isA<VpnCommandAccepted>());
      },
    );

    test('stop returns Future<VpnCommandResult>', () async {
      final engine = _FakeVpnEngine(const Connected());
      addTearDown(engine.dispose);
      expect(await engine.stop(), isA<VpnCommandAccepted>());
    });

    test('getStatus returns the current state snapshot', () async {
      final engine = _FakeVpnEngine(const Connected());
      addTearDown(engine.dispose);
      expect(await engine.getStatus(), const Connected());
    });

    test('command acceptance does not imply a state transition '
        '(Invariant 1)', () async {
      final engine = _FakeVpnEngine(const Disconnected());
      addTearDown(engine.dispose);
      final result = await engine.start(buildProfile());
      expect(result, isA<VpnCommandAccepted>());
      // The state snapshot is untouched by the accepted command: only the
      // connectionState stream may carry transitions.
      expect(await engine.getStatus(), const Disconnected());
    });
  });

  group('independent failure domains (Invariant 2)', () {
    test('stats emissions never reach the connectionState stream', () async {
      final engine = _FakeVpnEngine(const Disconnected());
      addTearDown(engine.dispose);

      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      // Subscribe to the stats stream BEFORE emitting: broadcast streams
      // drop events with no listener, so ordering matters here.
      final statsDone = engine.trafficStats.first;

      engine.emitStats(
        TrafficStats(txBytes: 1, rxBytes: 2, timestamp: DateTime.utc(2026)),
      );
      final stats = await statsDone;
      expect(stats.txBytes, 1);
      // Give the state pipeline a scheduling beat; it must stay silent.
      await Future<void>.delayed(Duration.zero);
      expect(states, isEmpty);
      await sub.cancel();
    });

    test('state emissions never reach the trafficStats stream', () async {
      final engine = _FakeVpnEngine(const Disconnected());
      addTearDown(engine.dispose);

      final stats = <TrafficStats>[];
      final sub = engine.trafficStats.listen(stats.add);
      // Same subscribe-before-emit ordering as above.
      final stateDone = engine.connectionState.first;

      engine.emitState(const Connecting());
      final state = await stateDone;
      expect(state, const Connecting());
      await Future<void>.delayed(Duration.zero);
      expect(stats, isEmpty);
      await sub.cancel();
    });
  });
}
