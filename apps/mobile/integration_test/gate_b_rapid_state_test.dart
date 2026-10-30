// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/connection/presentation/widgets/server_tile.dart';
import 'package:mobile/main.dart' as app;
import 'package:vpn_engine_android/vpn_engine_android.dart';

import 'chaos_test_harness.dart';

void main() {
  initChaosTestHarness();

  testWidgets(
    'P3-T16 Gate B: Staggered spam chaos and live traffic throughput test',
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
      final disconnectButton = find.descendant(
        of: targetTile,
        matching: find.text('Disconnect'),
      );
      expect(connectButton, findsOneWidget);
      expect(disconnectButton, findsOneWidget);

      // --- Chaos: Staggered spam delays hitting native mid-transition ---
      // Real wall-clock delays (200ms, 500ms, 1000ms) ensure taps arrive
      // during native Starting / Stopping states to exercise RejectedBusy.
      final delays = <Duration>[
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 300),
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 400),
        const Duration(milliseconds: 700),
      ];

      for (final delay in delays) {
        await tester.tap(connectButton);
        await tester.pump();
        await Future<void>.delayed(delay);
        await tester.pump();

        await tester.tap(disconnectButton);
        await tester.pump();
        await Future<void>.delayed(delay);
        await tester.pump();
      }

      // Allow any in-flight transitions from the spam barrage to settle.
      await waitForBadgeText(
        tester,
        (text) => text != 'Connecting' && text != 'Disconnecting',
        timeout: const Duration(seconds: 20),
        pollInterval: const Duration(milliseconds: 200),
      );

      // --- Long Connect Phase: Establish connection & verify traffic ---
      // 1. Tap Connect and wait for Connected state.
      await tester.tap(connectButton);
      final connectedBadge = await waitForBadgeText(
        tester,
        (text) => text == 'Connected',
      );
      expect(connectedBadge, equals('Connected'));

      // 2. Wait 8 real wall-clock seconds for traffic stats updates.
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        await tester.pump();
      }

      // 3. Assert ConnectionStateBadge is still Connected.
      expect(getBadgeText(tester), equals('Connected'));

      // 4. Assert ThroughputReadout shows real non-zero bytes (B/KiB/etc.).
      final throughput = getThroughputText(tester);
      final formattedRegex = RegExp(
        r'^\d+(\.\d+)?\s*(B|KiB|MiB|GiB|TiB)\s+up\s+/\s+'
        r'\d+(\.\d+)?\s*(B|KiB|MiB|GiB|TiB)\s+down$',
      );
      expect(
        formattedRegex.hasMatch(throughput),
        isTrue,
        reason:
            'ThroughputReadout must show non-zero rx/tx byte counts, '
            'but was "$throughput"',
      );
      expect(throughput, isNot(contains('No traffic data')));
      expect(throughput, isNot(contains('Traffic data unavailable')));

      // 5. Tap Disconnect and assert it settles back to Disconnected.
      await tester.tap(disconnectButton);
      final disconnectedBadge = await waitForBadgeText(
        tester,
        (text) => text == 'Disconnected',
      );
      expect(disconnectedBadge, equals('Disconnected'));

      // Verify native state agrees with UI state.
      final finalNative = await getNativeVpnState();
      expect(
        finalNative == VpnNativeState.idle ||
            finalNative == VpnNativeState.stopped,
        isTrue,
        reason: 'Native state must be idle or stopped, but was $finalNative',
      );

      // 6. Ensure app remains responsive (no ANR or platform deadlock).
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(connectionBadgeKey), findsOneWidget);
    },
  );
}
