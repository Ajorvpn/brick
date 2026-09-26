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
  Duration stopWatchdogTimeout = MockVpnEngine.defaultStopWatchdogTimeout,
  int txBytesPerTick = 1024,
  int rxBytesPerTick = 4096,
}) => MockVpnEngine(
  connectDelay: connectDelay,
  disconnectDelay: disconnectDelay,
  statsInterval: statsInterval,
  stopWatchdogTimeout: stopWatchdogTimeout,
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

    test('stop while Disconnected is an idempotent no-op that emits '
        'nothing', () async {
      final engine = buildEngine();
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      // Idempotent by design: an already-stopped engine has nothing to
      // tear down, so the command is accepted rather than rejected.
      expect(await engine.stop(), const VpnCommandAccepted());
      expect(await engine.getStatus(), const Disconnected());

      // Longer than disconnectDelay: a wrongly scheduled teardown would
      // have fired by now.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(states, isEmpty);
    });

    test('repeated stop while Disconnecting is accepted and has no additional '
        'effect', () async {
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

      // Every repeated stop is accepted, but none of them may spawn a
      // second teardown routine or invalidate the first one's token.
      expect(await engine.stop(), const VpnCommandAccepted());
      expect(await engine.stop(), const VpnCommandAccepted());
      expect(await engine.stop(), const VpnCommandAccepted());

      // The engine still settles exactly once.
      await waitFor(() => states.contains(const Disconnected()));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(states.whereType<Disconnecting>().length, 1);
      expect(states.whereType<Disconnected>().length, 1);
    });

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

  group('session tokens (ARCHITECTURE.md 3.5)', () {
    test(
      'a superseded start callback cannot resurrect a stopped session',
      () async {
        // The engine is stopped and restarted while the FIRST connect
        // timer is still pending. The stale callback must be discarded.
        final engine = buildEngine(
          connectDelay: const Duration(milliseconds: 120),
          disconnectDelay: const Duration(milliseconds: 10),
        );
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Connecting()));

        // Accepted stop supersedes the in-flight attempt...
        expect(await engine.stop(), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Disconnected()));

        // ...and a brand-new attempt is started before the stale connect
        // timer would have fired.
        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Connected()));

        // Wait past the superseded connectDelay.
        await Future<void>.delayed(const Duration(milliseconds: 150));

        // Exactly one Connecting, one Connected, one clean teardown: the
        // stale callback produced nothing and no duplicate connection.
        expect(states.whereType<Connecting>().length, 2);
        expect(states.whereType<Connected>().length, 1);
        expect(states, [
          const Connecting(),
          const Disconnecting(),
          const Disconnected(),
          const Connecting(),
          const Connected(),
        ]);
      },
    );

    test(
      'rapid start -> stop -> start never yields an illegal transition',
      () async {
        final engine = buildEngine(
          connectDelay: const Duration(milliseconds: 40),
          disconnectDelay: const Duration(milliseconds: 40),
        );
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);

        // No awaits between the commands: this is the tightest possible
        // interleaving of accept/reject paths.
        //
        // Expected acceptance: only the first `start` is accepted (the
        // engine is Disconnected). `stop` is then accepted and moves the
        // engine to Disconnecting, so the second `start` is correctly
        // rejected busy, the second `stop` is an idempotent no-op, and
        // the third `start` is rejected busy too. The engine therefore
        // settles on Disconnected without ever reaching Connected — and
        // critically, without any illegal transition or phantom Connected.
        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        expect(await engine.stop(), const VpnCommandAccepted());
        expect(
          await engine.start(buildProfile()),
          const VpnCommandRejectedBusy(),
        );
        expect(await engine.stop(), const VpnCommandAccepted());
        expect(
          await engine.start(buildProfile()),
          const VpnCommandRejectedBusy(),
        );

        // The teardown completes, and the abandoned connect attempt never
        // surfaces a phantom Connected.
        await waitFor(() => states.contains(const Disconnected()));
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(states.whereType<Connected>(), isEmpty);
        expect(states.whereType<Connecting>().length, 1);
        expect(states, [
          const Connecting(),
          const Disconnecting(),
          const Disconnected(),
        ]);
        expect(await engine.getStatus(), const Disconnected());
      },
    );
  });

  group('stop watchdog (ARCHITECTURE.md 3.5, 5000ms hard timeout)', () {
    test('the mandated default really is 5000ms', () {
      expect(
        MockVpnEngine.defaultStopWatchdogTimeout,
        const Duration(milliseconds: 5000),
      );
      expect(
        MockVpnEngine().stopWatchdogTimeout,
        const Duration(milliseconds: 5000),
      );
    });

    test('forces Disconnected when teardown overruns the watchdog', () async {
      // Teardown would take far longer than the watchdog allows.
      final engine = buildEngine(
        disconnectDelay: const Duration(milliseconds: 400),
        stopWatchdogTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connected()));

      expect(await engine.stop(), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Disconnected()));

      // The watchdog, not the slow teardown, completed this.
      expect(
        states.whereType<Disconnecting>().length,
        1,
        reason: 'a stuck Disconnecting is a P0 bug',
      );

      // The still-pending slow completion must not fire a second
      // Disconnected afterwards.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(states.whereType<Disconnected>().length, 1);
      expect(await engine.getStatus(), const Disconnected());
    });

    test('a graceful teardown cancels the watchdog', () async {
      // Teardown finishes well inside the watchdog window.
      final engine = buildEngine(
        disconnectDelay: const Duration(milliseconds: 20),
        stopWatchdogTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(engine.dispose);
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);
      addTearDown(sub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connected()));
      expect(await engine.stop(), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Disconnected()));

      // Wait past the watchdog window: a watchdog that was NOT cancelled
      // would try to force a second transition here.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(states, [
        const Connecting(),
        const Connected(),
        const Disconnecting(),
        const Disconnected(),
      ]);
    });
  });

  group('failure simulation hooks', () {
    test(
      'simulateConnectionFailure settles on Error and stops the attempt',
      () async {
        final engine = buildEngine(
          connectDelay: const Duration(milliseconds: 150),
        );
        addTearDown(engine.dispose);
        final states = <ConnectionState>[];
        final stats = <TrafficStats>[];
        final stateSub = engine.connectionState.listen(states.add);
        final statsSub = engine.trafficStats.listen(stats.add);
        addTearDown(stateSub.cancel);
        addTearDown(statsSub.cancel);

        expect(await engine.start(buildProfile()), const VpnCommandAccepted());
        await waitFor(() => states.contains(const Connecting()));

        engine.simulateConnectionFailure();

        // Legal from Connecting; the injected reason is carried in the
        // Error payload, not matched on its detail text. The stream is
        // asynchronous, so the emission must be awaited, not assumed.
        await waitFor(() => states.whereType<Error>().isNotEmpty);
        final last = states.last;
        expect(last, isA<Error>());
        expect((last as Error).reason, isA<PlatformError>());
        expect(await engine.getStatus(), isA<Error>());

        // The cancelled completion must not overwrite the failure.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(states.whereType<Connected>(), isEmpty);
        expect(stats, isEmpty);
      },
    );

    test(
      'simulateUnexpectedDisconnect settles on Error and stops stats',
      () async {
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

        engine.simulateUnexpectedDisconnect();

        // Awaited delivery: the hook is synchronous, the stream is not.
        await waitFor(() => states.whereType<Error>().isNotEmpty);
        final last = states.last;
        expect(last, isA<Error>());
        expect((last as Error).reason, isA<PlatformError>());

        // The statistics pipeline is halted: a dead tunnel reports no
        // more throughput.
        final statsAtFailure = stats.length;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(stats.length, statsAtFailure);
      },
    );

    test('both hooks reject an invalid state with a StateError', () async {
      final engine = buildEngine();
      addTearDown(engine.dispose);

      // From Disconnected both hooks are invalid.
      expect(engine.simulateConnectionFailure, throwsStateError);
      expect(engine.simulateUnexpectedDisconnect, throwsStateError);

      // From Connected, only simulateConnectionFailure is invalid.
      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      while (await engine.getStatus() != const Connected()) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(engine.simulateConnectionFailure, throwsStateError);

      // The engine is undamaged by the rejected calls.
      expect(await engine.getStatus(), const Connected());
    });

    test('both hooks throw after dispose', () async {
      final engine = buildEngine();
      await engine.dispose();
      expect(engine.simulateConnectionFailure, throwsStateError);
      expect(engine.simulateUnexpectedDisconnect, throwsStateError);
    });
  });

  group('concurrency and resource safety', () {
    test('100 interleaved commands across many engines never corrupt '
        'state', () async {
      const engineCount = 10;
      const commandsPerEngine = 10;
      final engines = List.generate(
        engineCount,
        (_) => buildEngine(
          connectDelay: const Duration(milliseconds: 2),
          disconnectDelay: const Duration(milliseconds: 2),
          statsInterval: const Duration(milliseconds: 2),
        ),
      );
      addTearDown(() async {
        for (final engine in engines) {
          await engine.dispose();
        }
      });

      // Every observed transition must be a legal one; any illegal
      // transition would have thrown a StateError from _transitionTo and
      // failed the test.
      const legal = <Type, Set<Type>>{
        Disconnected: {Connecting},
        Connecting: {Connected, Error, Disconnecting},
        Connected: {Disconnecting, Error},
        Disconnecting: {Disconnected},
        Error: {Connecting, Disconnecting},
      };

      for (final engine in engines) {
        final states = <ConnectionState>[];
        final sub = engine.connectionState.listen(states.add);
        addTearDown(sub.cancel);
        // Drain async errors so a stray failure surfaces as a test error
        // rather than an unhandled zone error.
        engine.trafficStats.listen((_) {}, onError: (_) {});

        for (var i = 0; i < commandsPerEngine; i++) {
          switch (i % 4) {
            case 0:
              await engine.start(buildProfile());
            case 1:
              await engine.stop();
            case 2:
              // Both hooks are state-dependent by design; a StateError
              // here is the contract working, not a failure.
              try {
                engine.simulateConnectionFailure();
              } on StateError {
                // Expected: not in Connecting.
              }
            case 3:
              try {
                engine.simulateUnexpectedDisconnect();
              } on StateError {
                // Expected: not in Connected.
              }
          }
          // Yield so timers interleave between commands.
          await Future<void>.delayed(const Duration(milliseconds: 3));
        }

        // The engine always rests in a state it can legitimately reach.
        expect(await engine.getStatus(), isA<ConnectionState>());

        for (var i = 1; i < states.length; i++) {
          final allowed = legal[states[i - 1].runtimeType];
          expect(
            allowed,
            contains(states[i].runtimeType),
            reason:
                'illegal transition ${states[i - 1].runtimeType} -> '
                '${states[i].runtimeType}',
          );
        }
      }
    });

    test('100+ engines can be created, run, and disposed with no leaked '
        'callbacks', () async {
      const iterations = 100;
      for (var i = 0; i < iterations; i++) {
        final engine = buildEngine(
          connectDelay: const Duration(milliseconds: 1),
          disconnectDelay: const Duration(milliseconds: 1),
          statsInterval: const Duration(milliseconds: 1),
        );
        final states = <ConnectionState>[];
        final stats = <TrafficStats>[];
        final stateSub = engine.connectionState.listen(states.add);
        final statsSub = engine.trafficStats.listen(stats.add);

        await engine.start(buildProfile());
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await engine.stop();
        await Future<void>.delayed(const Duration(milliseconds: 3));

        await engine.dispose();
        await stateSub.cancel();
        await statsSub.cancel();

        // Nothing may fire after release.
        final statesAtDispose = states.length;
        final statsAtDispose = stats.length;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        expect(states.length, statesAtDispose);
        expect(stats.length, statsAtDispose);

        // The engine is genuinely finished with.
        await expectLater(engine.start(buildProfile()), throwsStateError);
      }
    });

    test('dispose during an in-flight connect emits nothing further', () async {
      final engine = buildEngine(
        connectDelay: const Duration(milliseconds: 200),
      );
      final states = <ConnectionState>[];
      final sub = engine.connectionState.listen(states.add);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => states.contains(const Connecting()));

      await engine.dispose();
      final statesAtDispose = states.length;

      // Well past the pending connectDelay: no late Connected, and no
      // exception escaping a released engine.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(states.length, statesAtDispose);
      await sub.cancel();
    });

    test('per-session counters reset on the next start', () async {
      final engine = buildEngine(
        statsInterval: const Duration(milliseconds: 10),
        txBytesPerTick: 1000,
        rxBytesPerTick: 2000,
      );
      addTearDown(engine.dispose);
      final stats = <TrafficStats>[];
      final sub = engine.trafficStats.listen(stats.add);
      addTearDown(sub.cancel);

      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => stats.length >= 3);
      expect(stats.first.txBytes, 1000);
      expect(stats.last.txBytes, greaterThan(1000));

      expect(await engine.stop(), const VpnCommandAccepted());
      while (await engine.getStatus() != const Disconnected()) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // The second session must not inherit the first session's totals.
      stats.clear();
      expect(await engine.start(buildProfile()), const VpnCommandAccepted());
      await waitFor(() => stats.isNotEmpty);
      expect(stats.first.txBytes, 1000);
      expect(stats.first.rxBytes, 2000);
    });
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
