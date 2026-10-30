// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show Connected, Disconnected, Error, PlatformError;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

/// The label currently shown in the connection state badge.
String _badgeText(WidgetTester tester) {
  final label = tester
      .widget<Chip>(
        find.byKey(const ValueKey<String>('connection_state_badge')),
      )
      .label;
  return (label as Text).data!;
}

/// Simulates the app transitioning into the background / paused state,
/// respecting Flutter's lifecycle state machine:
/// `resumed -> inactive -> hidden -> paused`.
void _simulateAppPaused(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

/// Simulates the app returning to the foreground / resumed state,
/// respecting Flutter's lifecycle state machine:
/// `paused -> hidden -> inactive -> resumed`.
void _simulateAppResumed(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  setUpAll(initTestLocalization);

  group('AppLifecycleListener & Native State Resync (P4-T1)', () {
    testWidgets(
      'silent native disconnect while paused is reconciled immediately on '
      'resume',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        // 1. Initial state is Connected.
        engine.emit(const Connected());

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        expect(_badgeText(tester), 'Connected');

        // 2. Simulate OS suspending the app (going to background/paused).
        _simulateAppPaused(tester);
        await tester.pump();

        // 3. Silently drop the native VPN while suspended (no stream event
        // emitted because the EventChannel was suspended/missed).
        engine.lastState = const Disconnected();

        // The badge must still show Connected while paused (VM was suspended).
        expect(_badgeText(tester), 'Connected');

        // 4. Simulate app returning to foreground (resumed).
        _simulateAppResumed(tester);

        // Allow microtasks and stream events from getStatus() to resolve.
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        // 5. Assert badge instantly updated to Disconnected without user input.
        expect(_badgeText(tester), 'Disconnected');
      },
    );

    testWidgets(
      'silent native connect while paused is reconciled immediately on resume',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        // 1. Initial state is Disconnected.
        engine.emit(const Disconnected());

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        expect(_badgeText(tester), 'Disconnected');

        // 2. Simulate app going to background.
        _simulateAppPaused(tester);
        await tester.pump();

        // 3. Native VPN connects in background without Dart event stream.
        engine.lastState = const Connected();

        // 4. Simulate app returning to foreground.
        _simulateAppResumed(tester);

        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        // 5. Assert badge reconciled to Connected.
        expect(_badgeText(tester), 'Connected');
      },
    );

    testWidgets(
      'cold start probes getStatus immediately and shows Connected if tunnel '
      'was running',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        // Native engine is already running before Flutter VM started.
        engine.lastState = const Connected();

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        expect(_badgeText(tester), 'Connected');
      },
    );

    testWidgets(
      'silent native error while paused is reconciled to connection error upon '
      'resume',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        engine.emit(const Connected());

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
          dataSource: dataSource,
        );

        expect(_badgeText(tester), 'Connected');

        _simulateAppPaused(tester);
        await tester.pump();

        // Native engine encountered an error while app was suspended
        engine.lastState = const Error(PlatformError('Tunnel killed by OS'));

        _simulateAppResumed(tester);

        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        // Should render localized connection error
        expect(_badgeText(tester), 'Connection error');
      },
    );

    testWidgets(
      'observer initialized at app root (MyApp) reconciles native state on '
      'resume',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        engine.emit(const Connected());

        // Pump full MyApp root
        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );

        expect(_badgeText(tester), 'Connected');

        _simulateAppPaused(tester);
        await tester.pump();

        engine.lastState = const Disconnected();

        _simulateAppResumed(tester);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(_badgeText(tester), 'Disconnected');
      },
    );
  });
}
