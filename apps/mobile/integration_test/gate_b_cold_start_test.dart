// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart' as domain;
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/connection/presentation/widgets/server_tile.dart';
import 'package:mobile/main.dart' as app;
import 'package:vpn_engine_android/vpn_engine_android.dart';

import 'chaos_test_harness.dart';

void main() {
  final binding = initChaosTestHarness();

  testWidgets(
    'P3-T16 Gate B: Cold-start state recovery and native truth synchronization',
    (tester) async {
      // Launch the real application on the physical device.
      await app.main();
      await tester.pumpAndSettle();

      // Ensure the home screen is mounted.
      expect(find.byType(HomeScreen), findsOneWidget);

      // --- Setup: Add dummy VLESS server via UI if not already present ---
      var serverTileFinder = find.byType(ServerTile);
      if (serverTileFinder.evaluate().isEmpty) {
        final addServerButton = find.text('Add Server');
        expect(addServerButton, findsOneWidget);
        await tester.tap(addServerButton);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), dummyVlessUri);
        await tester.tap(find.text('Parse'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        serverTileFinder = find.byType(ServerTile);
      }

      expect(serverTileFinder, findsWidgets);
      final targetTile = serverTileFinder.first;

      final connectButton = find.descendant(
        of: targetTile,
        matching: find.text('Connect'),
      );
      expect(connectButton, findsOneWidget);

      // --- Phase A: Start VPN and wait for Connected ---
      await tester.tap(connectButton);
      await tester.pump();
      final initialConnectedBadge = await waitForBadgeText(
        tester,
        (text) => text == 'Connected',
      );
      expect(initialConnectedBadge, equals('Connected'));

      // Confirm native state machine is in Running state.
      final initialNativeState = await getNativeVpnState();
      expect(initialNativeState, equals(VpnNativeState.running));

      // --- Phase B: Simulate App Backgrounding & State Provider Reset ---
      // 1. Simulate backgrounding and resuming lifecycle transitions.
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // 2. Query initial state fetcher (simulating cold restart probe).
      final coldProbedEngine = AndroidVpnEngine();
      final probedState = await coldProbedEngine.getStatus();
      expect(
        probedState,
        isA<domain.Connected>(),
        reason: 'Direct cold getStatus() probe must return Connected',
      );

      // 3. Reset the connectionStateProvider to force it to re-query the native
      // layer (simulating cold UI reconnection to live native VPN tunnel).
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .invalidate(connectionStateProvider);
      await tester.pump();

      // --- Phase C: Assert UI resolves to Connected & Clean Teardown ---
      // 4. Assert: UI instantly resolves back to 'Connected' based purely on
      // native truth (VpnEngine Invariant 1).
      final recoveredBadge = await waitForBadgeText(
        tester,
        (text) => text == 'Connected',
      );
      expect(recoveredBadge, equals('Connected'));

      // Confirm native state remains Running.
      final midNative = await getNativeVpnState();
      expect(midNative, equals(VpnNativeState.running));

      // 5. Verify the recovered UI can control and stop the tunnel.
      final freshTileFinder = find.byType(ServerTile);
      expect(freshTileFinder, findsWidgets);
      final disconnectButton = find.descendant(
        of: freshTileFinder.first,
        matching: find.text('Disconnect'),
      );
      expect(disconnectButton, findsOneWidget);

      await tester.tap(disconnectButton);
      await tester.pump();
      final disconnectedBadge = await waitForBadgeText(
        tester,
        (text) => text == 'Disconnected',
      );
      expect(disconnectedBadge, equals('Disconnected'));

      final finalNativeState = await getNativeVpnState();
      expect(
        finalNativeState == VpnNativeState.idle ||
            finalNativeState == VpnNativeState.stopped,
        isTrue,
        reason:
            'Native state must be idle or stopped, but was $finalNativeState',
      );
    },
  );
}
