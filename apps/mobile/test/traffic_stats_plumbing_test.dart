// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/session_traffic_metrics.dart';
import 'package:mobile/features/connection/domain/formatters/traffic_formatter.dart';
import 'package:mobile/features/connection/domain/usecases/session_traffic_metrics_calculator.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/session_traffic_metrics_provider.dart';
import 'package:mobile/features/connection/presentation/widgets/throughput_readout.dart';

import 'localization_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestLocalization);

  group('TrafficFormatter', () {
    test('formatBytes formats binary IEC units deterministically', () {
      expect(TrafficFormatter.formatBytes(0), '0 B');
      expect(TrafficFormatter.formatBytes(-50), '0 B');
      expect(TrafficFormatter.formatBytes(512), '512 B');
      expect(TrafficFormatter.formatBytes(1023), '1023 B');
      expect(TrafficFormatter.formatBytes(1024), '1.0 KiB');
      expect(TrafficFormatter.formatBytes(1536), '1.5 KiB');
      expect(TrafficFormatter.formatBytes(2048), '2.0 KiB');
      expect(TrafficFormatter.formatBytes(1048576), '1.0 MiB');
      expect(TrafficFormatter.formatBytes(2097152), '2.0 MiB');
      expect(TrafficFormatter.formatBytes(1073741824), '1.0 GiB');
      expect(TrafficFormatter.formatBytes(1099511627776), '1.0 TiB');
    });

    test('formatSpeed formats transfer rates deterministically', () {
      expect(TrafficFormatter.formatSpeed(0), '0 B/s');
      expect(TrafficFormatter.formatSpeed(-100), '0 B/s');
      expect(TrafficFormatter.formatSpeed(double.nan), '0 B/s');
      expect(TrafficFormatter.formatSpeed(double.infinity), '0 B/s');
      expect(TrafficFormatter.formatSpeed(double.negativeInfinity), '0 B/s');
      expect(TrafficFormatter.formatSpeed(512), '512 B/s');
      expect(TrafficFormatter.formatSpeed(1024), '1.0 KiB/s');
      expect(TrafficFormatter.formatSpeed(12.4 * 1024), '12.4 KiB/s');
      expect(TrafficFormatter.formatSpeed(3.5 * 1024 * 1024), '3.5 MiB/s');
    });
  });

  group('SessionTrafficMetrics', () {
    test('zero baseline has default 0 values and null lastUpdated', () {
      const zero = SessionTrafficMetrics.zero;
      expect(zero.txBytes, 0);
      expect(zero.rxBytes, 0);
      expect(zero.txBytesPerSec, 0);
      expect(zero.rxBytesPerSec, 0);
      expect(zero.lastUpdated, isNull);
      expect(zero.hasError, isFalse);
    });

    test('value equality and copyWith work as expected', () {
      final now = DateTime.utc(2026, 11, 5, 12);
      const m1 = SessionTrafficMetrics(
        txBytes: 100,
        rxBytes: 200,
        txBytesPerSec: 50,
        rxBytesPerSec: 75,
      );
      const m2 = SessionTrafficMetrics(
        txBytes: 100,
        rxBytes: 200,
        txBytesPerSec: 50,
        rxBytesPerSec: 75,
      );
      expect(m1, equals(m2));
      expect(m1.hashCode, equals(m2.hashCode));

      final updated = m1.copyWith(txBytes: 300, lastUpdated: now);
      expect(updated.txBytes, 300);
      expect(updated.rxBytes, 200);
      expect(updated.txBytesPerSec, 50);
      expect(updated.lastUpdated, now);
      expect(updated.hasError, isFalse);

      final withError = m1.copyWith(hasError: true);
      expect(withError.hasError, isTrue);
      expect(m1 == withError, isFalse);
    });
  });

  group('SessionTrafficMetricsCalculator', () {
    late SessionTrafficMetricsCalculator calculator;

    setUp(() {
      calculator = SessionTrafficMetricsCalculator();
    });

    test('first snapshot reflects cumulative bytes but clamps speed to 0', () {
      final t0 = DateTime.utc(2026, 11, 5, 10);
      final metrics = calculator.process(
        TrafficStats(txBytes: 10240, rxBytes: 20480, timestamp: t0),
      );

      expect(metrics.txBytes, 10240);
      expect(metrics.rxBytes, 20480);
      expect(metrics.txBytesPerSec, 0);
      expect(metrics.rxBytesPerSec, 0);
      expect(metrics.lastUpdated, t0);
    });

    test('subsequent snapshot at 1s interval calculates exact speed', () {
      final t0 = DateTime.utc(2026, 11, 5, 10);
      final t1 = t0.add(const Duration(seconds: 1));

      calculator.process(
        TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
      );
      final metrics = calculator.process(
        TrafficStats(txBytes: 3000, rxBytes: 5000, timestamp: t1),
      );

      // deltaTx = 2000 bytes over 1000ms = 2000 B/s
      // deltaRx = 3000 bytes over 1000ms = 3000 B/s
      expect(metrics.txBytes, 3000);
      expect(metrics.rxBytes, 5000);
      expect(metrics.txBytesPerSec, 2000);
      expect(metrics.rxBytesPerSec, 3000);
    });

    test('subsequent snapshot at 500ms interval calculates exact speed', () {
      final t0 = DateTime.utc(2026, 11, 5, 10);
      final t1 = t0.add(const Duration(milliseconds: 500));

      calculator.process(
        TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
      );
      final metrics = calculator.process(
        TrafficStats(txBytes: 2000, rxBytes: 3000, timestamp: t1),
      );

      // deltaTx = 1000 bytes over 500ms = 2000 B/s
      // deltaRx = 1000 bytes over 500ms = 2000 B/s
      expect(metrics.txBytesPerSec, 2000);
      expect(metrics.rxBytesPerSec, 2000);
    });

    test('subsequent snapshot at 2s interval calculates exact speed', () {
      final t0 = DateTime.utc(2026, 11, 5, 10);
      final t1 = t0.add(const Duration(seconds: 2));

      calculator.process(
        TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
      );
      final metrics = calculator.process(
        TrafficStats(txBytes: 5000, rxBytes: 10000, timestamp: t1),
      );

      // deltaTx = 4000 bytes over 2000ms = 2000 B/s
      // deltaRx = 8000 bytes over 2000ms = 4000 B/s
      expect(metrics.txBytesPerSec, 2000);
      expect(metrics.rxBytesPerSec, 4000);
    });

    test(
      'duplicate timestamp (deltaMs == 0) clamps speed to 0 without NaN',
      () {
        final t0 = DateTime.utc(2026, 11, 5, 10);

        calculator.process(
          TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
        );
        final metrics = calculator.process(
          TrafficStats(txBytes: 2000, rxBytes: 3000, timestamp: t0),
        );

        expect(metrics.txBytesPerSec, 0);
        expect(metrics.rxBytesPerSec, 0);
        expect(metrics.txBytesPerSec.isNaN, isFalse);
        expect(metrics.rxBytesPerSec.isNaN, isFalse);
      },
    );

    test('clock skew backwards (deltaMs < 0) clamps speed to 0', () {
      final t0 = DateTime.utc(2026, 11, 5, 10, 1);
      final t1 = DateTime.utc(2026, 11, 5, 10);

      calculator.process(
        TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
      );
      final metrics = calculator.process(
        TrafficStats(txBytes: 2000, rxBytes: 3000, timestamp: t1),
      );

      expect(metrics.txBytesPerSec, 0);
      expect(metrics.rxBytesPerSec, 0);
    });

    test('counter reset (deltaBytes < 0) clamps speed to 0', () {
      final t0 = DateTime.utc(2026, 11, 5, 10);
      final t1 = t0.add(const Duration(seconds: 1));

      calculator.process(
        TrafficStats(txBytes: 5000, rxBytes: 5000, timestamp: t0),
      );
      final metrics = calculator.process(
        TrafficStats(txBytes: 100, rxBytes: 200, timestamp: t1),
      );

      expect(metrics.txBytes, 100);
      expect(metrics.rxBytes, 200);
      expect(metrics.txBytesPerSec, 0);
      expect(metrics.rxBytesPerSec, 0);
    });

    test('reset clears baseline so next tick clamps speed to 0', () {
      final t0 = DateTime.utc(2026, 11, 5, 10);
      final t1 = t0.add(const Duration(seconds: 1));

      calculator
        ..process(TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0))
        ..reset();

      final metrics = calculator.process(
        TrafficStats(txBytes: 5000, rxBytes: 6000, timestamp: t1),
      );

      expect(metrics.txBytes, 5000);
      expect(metrics.rxBytes, 6000);
      expect(metrics.txBytesPerSec, 0);
      expect(metrics.rxBytesPerSec, 0);
    });
  });

  group('sessionTrafficMetricsProvider', () {
    late FakeVpnEngine engine;
    late ProviderContainer container;

    setUp(() {
      engine = FakeVpnEngine();
      container = ProviderContainer(
        overrides: [vpnEngineProvider.overrideWithValue(engine)],
      )..listen(sessionTrafficMetricsProvider, (_, _) {});
    });

    tearDown(() async {
      container.dispose();
      await engine.dispose();
    });

    test('initial state is SessionTrafficMetrics.zero', () {
      final metrics = container.read(sessionTrafficMetricsProvider);
      expect(metrics, equals(SessionTrafficMetrics.zero));
    });

    test(
      'full session lifecycle: connect -> ticks -> disconnect -> reconnect',
      () async {
        // 1. Initially disconnected
        expect(
          container.read(sessionTrafficMetricsProvider),
          SessionTrafficMetrics.zero,
        );

        // 2. Transition to Connected
        engine.emit(const Connected());
        await pumpEventQueue();

        final t0 = DateTime.utc(2026, 11, 5, 10);
        final t1 = t0.add(const Duration(seconds: 1));
        final t2 = t1.add(const Duration(seconds: 1));

        // 3. First tick of session: speed is 0, cumulative bytes updated
        engine.emitStats(
          TrafficStats(txBytes: 1024, rxBytes: 2048, timestamp: t0),
        );
        await pumpEventQueue();

        var metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytes, 1024);
        expect(metrics.rxBytes, 2048);
        expect(metrics.txBytesPerSec, 0);
        expect(metrics.rxBytesPerSec, 0);

        // 4. Second tick 1s later: speed calculated
        engine.emitStats(
          TrafficStats(txBytes: 3072, rxBytes: 6144, timestamp: t1),
        );
        await pumpEventQueue();

        metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytes, 3072);
        expect(metrics.rxBytes, 6144);
        expect(metrics.txBytesPerSec, 2048);
        expect(metrics.rxBytesPerSec, 4096);

        // 5. Third tick 1s later: speed updated
        engine.emitStats(
          TrafficStats(txBytes: 4096, rxBytes: 8192, timestamp: t2),
        );
        await pumpEventQueue();

        metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytes, 4096);
        expect(metrics.rxBytes, 8192);
        expect(metrics.txBytesPerSec, 1024);
        expect(metrics.rxBytesPerSec, 2048);

        // 6. Transition to Disconnecting: rates clamped to 0, cumulative kept
        engine.emit(const Disconnecting());
        await pumpEventQueue();

        metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytes, 4096);
        expect(metrics.rxBytes, 8192);
        expect(metrics.txBytesPerSec, 0);
        expect(metrics.rxBytesPerSec, 0);

        // 7. Transition to Disconnected: metrics reset to zero
        engine.emit(const Disconnected());
        await pumpEventQueue();

        expect(
          container.read(sessionTrafficMetricsProvider),
          SessionTrafficMetrics.zero,
        );

        // 8. Reconnect in a second session: baseline must start fresh
        engine.emit(const Connected());
        await pumpEventQueue();

        final s2T0 = DateTime.utc(2026, 11, 5, 11);
        engine.emitStats(
          TrafficStats(txBytes: 500, rxBytes: 500, timestamp: s2T0),
        );
        await pumpEventQueue();

        metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytes, 500);
        expect(metrics.rxBytes, 500);
        expect(metrics.txBytesPerSec, 0);
        expect(metrics.rxBytesPerSec, 0);
      },
    );

    test('transition to Error or Connecting resets session metrics', () async {
      engine.emit(const Connected());
      await pumpEventQueue();

      final t0 = DateTime.utc(2026, 11, 5, 10);
      engine.emitStats(
        TrafficStats(txBytes: 1024, rxBytes: 2048, timestamp: t0),
      );
      await pumpEventQueue();
      expect(container.read(sessionTrafficMetricsProvider).txBytes, 1024);

      // Transition to Error
      engine.emit(const Error(InvalidConfig()));
      await pumpEventQueue();
      expect(
        container.read(sessionTrafficMetricsProvider),
        SessionTrafficMetrics.zero,
      );

      // Reconnect: Connecting resets baseline
      engine.emit(const Connecting());
      await pumpEventQueue();
      expect(
        container.read(sessionTrafficMetricsProvider),
        SessionTrafficMetrics.zero,
      );
    });

    test(
      'failure domain isolation: stats stream error does not crash provider',
      () async {
        engine.emit(const Connected());
        await pumpEventQueue();

        final t0 = DateTime.utc(2026, 11, 5, 10);
        final t1 = t0.add(const Duration(seconds: 1));

        engine.emitStats(
          TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
        );
        await pumpEventQueue();
        engine.emitStats(
          TrafficStats(txBytes: 2000, rxBytes: 4000, timestamp: t1),
        );
        await pumpEventQueue();

        var metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytesPerSec, 1000);
        expect(metrics.rxBytesPerSec, 2000);

        // Inject error into stats stream (Invariant 2)
        engine.emitStatsError(Exception('simulated stats hiccup'));
        await pumpEventQueue();

        // State absorbs error gracefully: rates clamped to 0, bytes retained
        metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytes, 2000);
        expect(metrics.rxBytes, 4000);
        expect(metrics.txBytesPerSec, 0);
        expect(metrics.rxBytesPerSec, 0);

        // Connection state remains completely unaffected
        final connState = container.read(connectionStateProvider).value;
        expect(connState, isA<Connected>());
      },
    );

    test(
      'idempotent Connected re-emission does not reset baseline mid-session',
      () async {
        engine.emit(const Connected());
        await pumpEventQueue();

        final t0 = DateTime.utc(2026, 11, 5, 10);
        final t1 = t0.add(const Duration(seconds: 1));
        final t2 = t1.add(const Duration(seconds: 1));

        engine.emitStats(
          TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
        );
        await pumpEventQueue();
        engine.emitStats(
          TrafficStats(txBytes: 2000, rxBytes: 4000, timestamp: t1),
        );
        await pumpEventQueue();

        var metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytesPerSec, 1000);
        expect(metrics.rxBytesPerSec, 2000);

        // Re-emit Connected (simulating AppLifecycleListener resume check)
        engine.emit(const Connected());
        await pumpEventQueue();

        // Third tick: delta should still be computed against t1, NOT reset to 0
        engine.emitStats(
          TrafficStats(txBytes: 3000, rxBytes: 6000, timestamp: t2),
        );
        await pumpEventQueue();

        metrics = container.read(sessionTrafficMetricsProvider);
        expect(metrics.txBytes, 3000);
        expect(metrics.rxBytes, 6000);
        expect(metrics.txBytesPerSec, 1000);
        expect(metrics.rxBytesPerSec, 2000);
      },
    );
  });

  group('ThroughputReadout UI & Rebuild Isolation (P6-T2)', () {
    testWidgets(
      'renders cumulative totals and speeds across full session lifecycle',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: ThroughputReadout()),
          engine: engine,
        );

        // Initial zero state: 0 B up / 0 B down, Speed: ↑ 0 B/s · ↓ 0 B/s
        expect(
          find.byKey(const ValueKey<String>('throughput_readout')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('throughput_speed_readout')),
          findsOneWidget,
        );
        expect(find.text('0 B up / 0 B down'), findsOneWidget);
        expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

        // Tunnel connects
        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Tick 1 at t0: 1000 tx, 2000 rx -> speed clamped to 0 on first tick
        final t0 = DateTime.utc(2026, 11, 5, 10);
        engine.emitStats(
          TrafficStats(txBytes: 1000, rxBytes: 2000, timestamp: t0),
        );
        await tester.pumpAndSettle();

        expect(find.text('1000 B up / 2.0 KiB down'), findsOneWidget);
        expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

        // Tick 2 at t0 + 1s: 2000 tx (+1000 B/s), 4000 rx (+2000 B/s)
        final t1 = t0.add(const Duration(seconds: 1));
        engine.emitStats(
          TrafficStats(txBytes: 2000, rxBytes: 4000, timestamp: t1),
        );
        await tester.pumpAndSettle();

        expect(find.text('2.0 KiB up / 3.9 KiB down'), findsOneWidget);
        expect(find.text('Speed: ↑ 1000 B/s · ↓ 2.0 KiB/s'), findsOneWidget);

        // Disconnecting state: speed clamped to 0, cumulative totals preserved
        engine.emit(const Disconnecting());
        await tester.pumpAndSettle();

        expect(find.text('2.0 KiB up / 3.9 KiB down'), findsOneWidget);
        expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

        // Disconnected state: both reset to 0
        engine.emit(const Disconnected());
        await tester.pumpAndSettle();

        expect(find.text('0 B up / 0 B down'), findsOneWidget);
        expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);

        // New Connecting session: ensures clean zero baseline
        engine.emit(const Connecting());
        await tester.pumpAndSettle();

        expect(find.text('0 B up / 0 B down'), findsOneWidget);
        expect(find.text('Speed: ↑ 0 B/s · ↓ 0 B/s'), findsOneWidget);
      },
    );

    testWidgets(
      'rebuild isolation: continuous traffic ticks update leaf widgets '
      'without rebuilding parent or sibling widgets',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        var parentBuildCount = 0;
        var siblingBuildCount = 0;

        await pumpConnectionMaterialApp(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              parentBuildCount++;
              return Scaffold(
                body: Column(
                  children: [
                    Builder(
                      builder: (context) {
                        siblingBuildCount++;
                        return const Text('Sibling Static Text');
                      },
                    ),
                    const ThroughputReadout(),
                  ],
                ),
              );
            },
          ),
          engine: engine,
        );

        expect(parentBuildCount, equals(1));
        expect(siblingBuildCount, equals(1));

        engine.emit(const Connected());
        await tester.pumpAndSettle();

        // Emit 5 consecutive traffic ticks
        var t = DateTime.utc(2026, 11, 5, 10);
        for (var i = 1; i <= 5; i++) {
          t = t.add(const Duration(seconds: 1));
          engine.emitStats(
            TrafficStats(txBytes: i * 1024, rxBytes: i * 2048, timestamp: t),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();

        // Throughput leaf widgets reflect latest values
        expect(find.text('5.0 KiB up / 10.0 KiB down'), findsOneWidget);
        expect(find.text('Speed: ↑ 1.0 KiB/s · ↓ 2.0 KiB/s'), findsOneWidget);

        // Parent and sibling widgets were NEVER rebuilt during the 5
        // traffic ticks! (Rebuild isolation criterion verified)
        expect(parentBuildCount, equals(1));
        expect(siblingBuildCount, equals(1));
      },
    );

    testWidgets(
      'leaf widget short-circuit: unchanged speed string does not rebuild '
      'speed leaf widget when cumulative totals change',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: ThroughputReadout()),
          engine: engine,
        );

        engine.emit(const Connected());
        await tester.pumpAndSettle();

        final t0 = DateTime.utc(2026, 11, 5, 10);
        // Tick 1 (speed clamped to 0)
        engine.emitStats(
          TrafficStats(txBytes: 1024, rxBytes: 2048, timestamp: t0),
        );
        await tester.pumpAndSettle();

        // Tick 2 (speed becomes 1.0 KiB/s and 2.0 KiB/s)
        final t1 = t0.add(const Duration(seconds: 1));
        engine.emitStats(
          TrafficStats(txBytes: 2048, rxBytes: 4096, timestamp: t1),
        );
        await tester.pumpAndSettle();

        expect(find.text('2.0 KiB up / 4.0 KiB down'), findsOneWidget);
        expect(find.text('Speed: ↑ 1.0 KiB/s · ↓ 2.0 KiB/s'), findsOneWidget);

        final speedWidgetAtTick2 = tester.widget<Text>(
          find.byKey(const ValueKey<String>('throughput_speed_readout')),
        );
        final totalsWidgetAtTick2 = tester.widget<Text>(
          find.byKey(const ValueKey<String>('throughput_readout')),
        );

        // Tick 3 (same delta -> speed remains 1.0 KiB/s and 2.0 KiB/s,
        // but cumulative totals change to 3.0 KiB and 6.0 KiB)
        final t2 = t1.add(const Duration(seconds: 1));
        engine.emitStats(
          TrafficStats(txBytes: 3072, rxBytes: 6144, timestamp: t2),
        );
        await tester.pumpAndSettle();

        expect(find.text('3.0 KiB up / 6.0 KiB down'), findsOneWidget);
        expect(find.text('Speed: ↑ 1.0 KiB/s · ↓ 2.0 KiB/s'), findsOneWidget);

        final speedWidgetAtTick3 = tester.widget<Text>(
          find.byKey(const ValueKey<String>('throughput_speed_readout')),
        );
        final totalsWidgetAtTick3 = tester.widget<Text>(
          find.byKey(const ValueKey<String>('throughput_readout')),
        );

        // Cumulative totals widget updated (different instance)
        expect(identical(totalsWidgetAtTick2, totalsWidgetAtTick3), isFalse);

        // Speed leaf widget did NOT rebuild (identical instance short-circuited
        // by Riverpod .select() record equality)
        expect(identical(speedWidgetAtTick2, speedWidgetAtTick3), isTrue);
      },
    );
  });
}
