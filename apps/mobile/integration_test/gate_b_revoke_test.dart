// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/connection/presentation/widgets/server_tile.dart';
import 'package:mobile/main.dart';
import 'package:vpn_engine_android/vpn_engine_android.dart';

import 'chaos_test_harness.dart';

void main() {
  initChaosTestHarness();

  testWidgets('P3-T16 Gate B: System permission revoke graceful handling', (
    tester,
  ) async {
    WidgetsFlutterBinding.ensureInitialized();
    await EasyLocalization.ensureInitialized();

    // Controller allowing simulated system events (e.g. adb shell appops
    // set ACTIVATE_VPN deny) while forwarding real native bridge events.
    final stateEventController = StreamController<VpnStateEvent>.broadcast();
    final nativeSub = stateEvents().listen(
      stateEventController.add,
      onError: stateEventController.addError,
    );

    final engine = AndroidVpnEngine(
      stateEventsStream: stateEventController.stream,
    );

    runApp(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: ProviderScope(
          overrides: [
            if (Platform.isAndroid)
              vpnEngineProvider.overrideWith((ref) => engine),
          ],
          child: const MyApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

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

    // --- 1. Connect the VPN via the UI ---
    await tester.tap(connectButton);
    await tester.pump();
    final connectedBadge = await waitForBadgeText(
      tester,
      (text) => text == 'Connected',
    );
    expect(connectedBadge, equals('Connected'));

    // --- 2. Invoke revoke event simulating system permission revoke ---
    // (simulates: adb shell appops set dev.brickvpn.mobile ACTIVATE_VPN deny)
    stateEventController.add(VpnStateEvent(state: VpnNativeState.revoked));
    await tester.pump();

    // --- 3. Assert UI transitions to Disconnected or Error without crash ---
    final revokedBadge = await waitForBadgeText(
      tester,
      (text) =>
          text == 'Connection error' ||
          text == 'Error' ||
          text == 'Disconnected',
    );
    expect(
      revokedBadge == 'Connection error' ||
          revokedBadge == 'Error' ||
          revokedBadge == 'Disconnected',
      isTrue,
      reason:
          'UI must transition to Error or Disconnected, got "$revokedBadge"',
    );

    // Verify app remains responsive (no ANR or fatal crash in Dart VM).
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(connectionBadgeKey), findsOneWidget);

    // Cleanup
    await engine.stop();
    await nativeSub.cancel();
    await stateEventController.close();
  });
}
