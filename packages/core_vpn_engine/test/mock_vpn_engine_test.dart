// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:test/test.dart';

/// Polls [condition] until it holds, failing the test if it does not hold
/// within five seconds. Polling (rather than fixed sleeps) keeps the suite
/// fast on quick machines and flake-resistant on slow CI runners.
Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within 5 seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Builds a minimal valid profile for command tests. Its contents never
/// matter to the mock (which retains no profile by design); only the
/// container type does.
ServerProfile buildProfile() => ServerProfile(
  id: 'p-1',
  name: 'Mock test server',
  config: VlessOutbound(
    server: 'v.example',
    serverPort: 443,
    uuid: '00000000-0000-0000-0000-000000000001',
  ),
  addedAt: DateTime.utc(2026, 9, 21),
);

/// Builds a fast engine for tests; real usage would keep the demo-scale
/// defaults. Tick sizes are small and exact so increment assertions stay
/// readable (`n * txBytesPerTick`).
MockVpnEngine buildEngine({
  Duration connectDelay = const Duration(milliseconds: 30),
  Duration disconnectDelay = const Duration(milliseconds: 30),
  Duration statsInterval = const Duration(milliseconds: 10),
  int txBytesPerTick = 1024,
  int rxBytesPerTick = 4096,
}) => MockVpnEngine(
  connectDelay: connectDelay,
  disconnectDelay: disconnectDelay,
  statsInterval: statsInterval,
  txBytesPerTick: txBytesPerTick,
  rxBytesPerTick: rxBytesPerTick,
);

void main() {
  group('lifecycle happy path', () {
    test('initial state is Disconnected', () async {
      final engine = buildEngine();
      addTearDown(engine.dispose);
      expect(await engine.getStatus(), const Disconnected());
    });

    test(
      'start is accepted and emits Connecting then Connected in order',
      () async {
        final engine = buildEngine();
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.length >= 2);
        expect(states, [const Connecting(), const Connected()]);
      },
    );

    test('traffic stats tick and increment while connected', () async {
      final engine = buildEngine(txBytesPerTick: 1024, rxBytesPerTick: 4096);
      addTearDown(engine.dispose);
      final stats = <TrafficStats>[];
      final sub = engine.trafficStats.listen(stats.add);
      addTearDown(sub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => stats.length >= 3);

      expect(stats[0].txBytes, 1024);
      expect(stats[1].txBytes, 2048);
      expect(stats[2].txBytes, 3072);
      expect(stats[1].rxBytes - stats[0].rxBytes, 4096);
      expect(stats[1].timestamp.isBefore(stats[2].timestamp), isTrue);
    });

    test('stop is accepted, emits Disconnecting then Disconnected, and '
        'stats stop ticking', () async {
      final engine = buildEngine();
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final stats = <TrafficStats>[];
      final stateSub = engine.connectionState.listen(states.add);
      final statsSub = engine.trafficStats.listen(stats.add);
      addTearDown(stateSub.cancel);
      addTearDown(statsSub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connected()));
      await waitFor(() => stats.isNotEmpty);

      expect(await engine.stop(), const VpnCommandAccepted());
      await waitFor(() => states.length >= 4);
      expect(states, [
        const Connecting(),
        const Connected(),
        const Disconnecting(),
        const Disconnected(),
      ]);

      final statsAtDisconnect = stats.length;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(stats.length, statsAtDisconnect);
    });
  });

  group('busy semantics', () {
    test(
      'start while Connecting is rejected busy and the attempt completes',
      () async {
        final engine = buildEngine(
          connectDelay: const Duration(milliseconds: 120),
        );
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.isNotEmpty);
        expect(states, [const Connecting()]);

        expect(
          await engine.start(buildProfile()),
          const VpnCommandRejectedBusy(),
        );

        await waitFor(() => states.length >= 2);
        expect(states.whereType<Connecting>().length, 1);
        expect(states.last, const Connected());
      },
    );

    test(
      'start while Connected is rejected busy without a new Connecting',
      () async {
        final engine = buildEngine();
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Connected()));

        expect(
          await engine.start(buildProfile()),
          const VpnCommandRejectedBusy(),
        );
        expect(await engine.getStatus(), const Connected());

        // Invariant from the P1-T5 acceptance criteria: the machine must
        // never surface Connected -> Connecting without a teardown phase.
        expect(states.whereType<Connecting>().length, 1);
        expect(states.last, const Connected());
      },
    );

    test(
      'stop while Disconnected is rejected busy and emits nothing',
      () async {
        final engine = buildEngine();
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        expect(await engine.stop(), const VpnCommandRejectedBusy());
        expect(await engine.getStatus(), const Disconnected());

        // Longer than disconnectDelay: a wrongly scheduled teardown would
        // have fired by now.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(states, isEmpty);
      },
    );

    test(
      'repeated stop while Disconnecting has no additional effect',
      () async {
        final engine = buildEngine(
          disconnectDelay: const Duration(milliseconds: 120),
        );
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Connected()));

        expect(await engine.stop(), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Disconnecting()));
        expect(await engine.stop(), const VpnCommandRejectedBusy());
        expect(await engine.stop(), const VpnCommandRejectedBusy());

        await waitFor(() => states.contains(const Disconnected()));
        expect(states.whereType<Disconnecting>().length, 1);
        expect(states.whereType<Disconnected>().length, 1);
      },
    );

    test('stop during Connecting cancels the pending attempt', () async {
      final engine = buildEngine(
        connectDelay: const Duration(milliseconds: 200),
      );
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connecting()));

      expect(await engine.stop(), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Disconnected()));

      // Wait past the cancelled connectDelay: a phantom Connected from the
      // abandoned attempt must never surface.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(states.whereType<Connected>(), isEmpty);
      expect(states, [
        const Connecting(),
        const Disconnecting(),
        const Disconnected(),
      ]);
    });
  });

  group('simulated start rejections', () {
    test('simulatePermissionDenied rejects without any state change', () async {
      final engine = buildEngine()..simulatePermissionDenied = true;
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      expect(
        await engine.start(buildProfile()),
        const VpnCommandRejectedPermissionDenied(),
      );
      expect(await engine.getStatus(), const Disconnected());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(states, isEmpty);

      // Clearing the hook must leave the engine fully usable.
      engine.simulatePermissionDenied = false;
      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connected()));
    });

    test('simulateInvalidConfig rejects without any state change', () async {
      final engine = buildEngine()..simulateInvalidConfig = true;
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      expect(
        await engine.start(buildProfile()),
        const VpnCommandRejectedInvalidConfig(),
      );
      expect(await engine.getStatus(), const Disconnected());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(states, isEmpty);

      engine.simulateInvalidConfig = false;
      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connected()));
    });

    test('simulateStartupFailure fails without any state change', () async {
      final engine = buildEngine()..simulateStartupFailure = true;
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandFailed());
      expect(await engine.getStatus(), const Disconnected());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(states, isEmpty);

      engine.simulateStartupFailure = false;
      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connected()));
    });
  });

  group('simulated connection error', () {
    test(
      'settles on Error(reason) instead of Connected and ticks no stats',
      () async {
        const reason = PlatformError('simulated native failure');
        final engine = buildEngine()..simulatedConnectionError = reason;
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final stats = <TrafficStats>[];
        final stateSub = engine.connectionState.listen(states.add);
        final statsSub = engine.trafficStats.listen(stats.add);
        addTearDown(stateSub.cancel);
        addTearDown(statsSub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.length >= 2);
        expect(states, [const Connecting(), const Error(reason)]);

        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(stats, isEmpty);
      },
    );

    test('stop from Error clears the failure through Disconnecting', () async {
      final engine = buildEngine()
        ..simulatedConnectionError = const InvalidConfig();
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Error(InvalidConfig())));
      expect(await engine.stop(), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Disconnected()));
      expect(states, [
        const Connecting(),
        const Error(InvalidConfig()),
        const Disconnecting(),
        const Disconnected(),
      ]);
    });

    test(
      'a retry after Error starts a fresh attempt once the hook is cleared',
      () async {
        final engine = buildEngine()
          ..simulatedConnectionError = const Unknown();
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Error(Unknown())));

        engine.simulatedConnectionError = null;
        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Connected()));
        expect(states, [
          const Connecting(),
          const Error(Unknown()),
          const Connecting(),
          const Connected(),
        ]);
      },
    );
  });

  group('independent failure domains', () {
    test(
      'a stats-pipeline failure never affects the connection state',
      () async {
        final engine = buildEngine()..simulateStatsFailure = true;
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final stateErrors = <Object>[];
        final statsErrors = <Object>[];
        final stateSub = engine.connectionState.listen(
          states.add,
          onError: stateErrors.add,
        );
        final statsSub = engine.trafficStats.listen(
          (_) {},
          onError: statsErrors.add,
        );
        addTearDown(stateSub.cancel);
        addTearDown(statsSub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => statsErrors.isNotEmpty);

        // The statistics pipeline is visibly broken...
        expect(statsErrors.first, isA<StateError>());
        // ...while the connection pipeline is completely unaffected.
        expect(await engine.getStatus(), const Connected());
        await waitFor(() => states.contains(const Connected()));
        expect(stateErrors, isEmpty);

        // The engine stays fully operable: teardown still completes.
        expect(await engine.stop(), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Disconnected()));
        expect(stateErrors, isEmpty);
      },
    );
  });

  group('disposal', () {
    test('dispose cancels timers, closes both streams, is idempotent, and '
        'rejects later commands', () async {
      final engine = buildEngine();
      final states = <ConnectionState>[];
      final stats = <TrafficStats>[];
      final stateSub = engine.connectionState.listen(states.add);
      final statsSub = engine.trafficStats.listen(stats.add);
      addTearDown(stateSub.cancel);
      addTearDown(statsSub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connected()));
      await waitFor(() => stats.isNotEmpty);

      await engine.dispose();
      await engine.dispose(); // Idempotent: the second call is a no-op.

      // Closed broadcast streams deliver `done` to late subscribers, which
      // proves both controllers were really closed rather than merely
      // silent.
      var stateClosed = false;
      var statsClosed = false;
      final stateProbe = engine.connectionState.listen(
        (_) {},
        onDone: () => stateClosed = true,
      );
      final statsProbe = engine.trafficStats.listen(
        (_) {},
        onDone: () => statsClosed = true,
      );
      addTearDown(stateProbe.cancel);
      addTearDown(statsProbe.cancel);
      await waitFor(() => stateClosed && statsClosed);

      // No timer may fire after disposal.
      final statesAtDispose = states.length;
      final statsAtDispose = stats.length;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(states.length, statesAtDispose);
      expect(stats.length, statsAtDispose);

      // A disposed engine refuses work loudly instead of lying.
      await expectLater(engine.start(buildProfile()), throwsStateError);
      await expectLater(engine.stop(), throwsStateError);
      await expectLater(engine.getStatus(), throwsStateError);
    });
  });
}
