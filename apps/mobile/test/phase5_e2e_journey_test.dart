// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart'
    show Connected, Disconnected, TrafficStats;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/add_subscription_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/servers/presentation/providers/server_management_controller.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

class _FakeSubscriptionTransport implements SubscriptionTransport {
  _FakeSubscriptionTransport({required this.bodyProvider});

  final String Function() bodyProvider;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async {
    return TransportResponse(
      statusCode: HttpStatus.ok,
      headers: const {},
      body: Stream.value(utf8.encode(bodyProvider())),
    );
  }

  @override
  void close() {}
}

const String _uuid1 = '11111111-2222-3333-4444-555555555555';
const String _uuid2 = '22222222-3333-4444-5555-666666666666';
const String _uuid3 = '33333333-4444-5555-6666-777777777777';
const String _uuid4 = '44444444-5555-6666-7777-888888888888';

const String _manualVlessUri =
    'vless://$_uuid1@node1.example.com:443?security=none#Germany%20Node%201';
const String _qrVlessUri =
    'vless://$_uuid2@node2.example.com:443?security=none#United%20Kingdom%20Node%202';
const String _subVlessUri1 =
    'vless://$_uuid3@sub1.example.com:443?security=none#Japan%20Node%201';
const String _subVlessUri2 =
    'vless://$_uuid4@sub2.example.com:443?security=none#Japan%20Node%202';
const String _subVlessUri2Refreshed =
    'vless://$_uuid4@sub2refreshed.example.com:443?security=none#Japan%20Node%203';

void main() {
  setUpAll(initTestLocalization);

  group('Phase 5 Complete End-to-End User Journey (P5-T1 — P5-T8)', () {
    testWidgets('executes the entire Phase 5 lifecycle in one seamless flow', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      final fakePrefs = FakeAppPreferencesRepository();
      addTearDown(engine.dispose);

      var currentSubPayload = '$_subVlessUri1\n$_subVlessUri2';
      final fetcher = SubscriptionFetcher(
        transport: _FakeSubscriptionTransport(
          bodyProvider: () => currentSubPayload,
        ),
      );

      // =====================================================================
      // STEP 1: Boot into empty state (P5-T1 / P5-T5)
      // =====================================================================
      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
        preferencesRepository: fakePrefs,
        subscriptionFetcher: fetcher,
        scannerBuilder: (context, onDetect) => ElevatedButton(
          key: const ValueKey<String>('test_qr_scanner_trigger'),
          onPressed: () => onDetect(_qrVlessUri),
          child: const Text('Simulate Scan'),
        ),
      );

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home_active_server_card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('home_connect_toggle_button')),
        findsNothing,
      );
      expect(find.text('No saved servers yet'), findsOneWidget);

      // Switch to Servers tab via bottom navigation bar
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
      await tester.pumpAndSettle();

      expect(find.byType(ServersScreen), findsOneWidget);
      expect(find.text('No servers added yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('servers_empty_state')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('servers_empty_update_button')),
        findsOneWidget,
      );

      // =====================================================================
      // STEP 2: Add a standalone server via manual URI paste (P5-T2)
      // =====================================================================
      unawaited(tester.element(find.byType(ServersScreen)).push('/add-server'));
      await tester.pumpAndSettle();

      expect(find.byType(AddServerScreen), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('add_server_uri_field')),
        _manualVlessUri,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_save_button')),
      );
      await tester.pumpAndSettle();

      // Popped back to ServersScreen (Smart Auto + Germany country card)
      expect(find.byType(ServersScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('server_location_auto')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_DE')),
        findsOneWidget,
      );
      expect(find.text('Germany'), findsOneWidget);

      // Switch to HomeScreen and verify default Smart Auto target
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_home')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('home_active_server_card')),
        findsOneWidget,
      );
      expect(find.text('Smart Auto'), findsOneWidget);
      expect(find.text('Best available server'), findsOneWidget);

      // =====================================================================
      // STEP 3: Add a second standalone server via QR scan (P5-T3)
      // =====================================================================
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
      await tester.pumpAndSettle();

      unawaited(tester.element(find.byType(ServersScreen)).push('/add-server'));
      await tester.pumpAndSettle();

      expect(find.byType(AddServerScreen), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_scan_qr_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('test_qr_scanner_trigger')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('test_qr_scanner_trigger')),
      );
      await tester.pumpAndSettle();

      // Returned to ServersScreen with Germany + United Kingdom country cards
      expect(find.byType(ServersScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('country_group_DE')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_GB')),
        findsOneWidget,
      );
      expect(find.text('United Kingdom'), findsOneWidget);

      // =====================================================================
      // STEP 4: Import subscription URL yielding servers (P5-T4, P5-T5)
      // =====================================================================
      unawaited(
        tester.element(find.byType(ServersScreen)).push('/add-subscription'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AddSubscriptionScreen), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('add_subscription_url_field')),
        'https://sub.example.com/api?token=super_secret_subscription_token',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('add_subscription_name_field')),
        'FastVPN Subscription',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_subscription_import_button')),
      );
      await tester.pumpAndSettle();

      // Popped back to ServersScreen
      expect(find.byType(ServersScreen), findsOneWidget);

      // Verify country grouping (manual DE, QR GB, subscription nodes ZZ)
      expect(
        find.byKey(const ValueKey<String>('country_group_ZZ')),
        findsOneWidget,
      );
      // Feed strip renders the subscription name cleanly once
      expect(find.text('FastVPN Subscription'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // header total count pill
      expect(find.text('2'), findsOneWidget); // feed count badge

      // Zero secret token/URL leakage in UI
      expect(
        find.textContaining('super_secret_subscription_token'),
        findsNothing,
      );
      expect(find.textContaining('https://sub.example.com'), findsNothing);

      // Allow the import success snackbar to expire before tile actions
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // =====================================================================
      // STEP 5: Controller CRUD + Subscription Refresh + Clean UI (P5-T6)
      // =====================================================================
      final allServers = await buildRepository(dataSource).getAll();
      final manualNode = allServers.firstWhere(
        (s) => s.name == 'Germany Node 1',
      );
      final qrNode = allServers.firstWhere(
        (s) => s.name == 'United Kingdom Node 2',
      );
      final subNode1 = allServers.firstWhere((s) => s.subscriptionId != null);
      final sub = (await buildRepository(
        dataSource,
      ).getAllSubscriptions()).single;

      final serversContainer = ProviderScope.containerOf(
        tester.element(find.byType(ServersScreen)),
      );
      final serverMgmt = serversContainer.read(
        serverManagementControllerProvider.notifier,
      );

      // 5a. Edit standalone server via controller without cluttering country UI
      await serverMgmt.editServer(
        existing: manualNode,
        newName: 'Germany Renamed 1',
      );
      await tester.pumpAndSettle();

      // 5b. Duplicate subscription server as standalone
      await serverMgmt.duplicateServer(subNode1);
      await tester.pumpAndSettle();

      final copyName = '${subNode1.name} (Copy)';
      expect(find.text('5'), findsOneWidget); // header total count pill
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('country_group_ZZ')),
          matching: find.text('3 servers'),
        ),
        findsOneWidget,
      );

      // 5c. Refresh subscription via UI with Full-Replace diffing policy
      currentSubPayload = '$_subVlessUri1\n$_subVlessUri2Refreshed';
      final refreshButton = find.byKey(
        ValueKey<String>('subscription_refresh_${sub.id}'),
      );
      await tester.ensureVisible(refreshButton);
      await tester.tap(refreshButton);
      await tester.pumpAndSettle();

      // Allow the refresh success snackbar to expire before deleting
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // 5d. Delete duplicated server via controller and verify count updates
      final updatedAll = await buildRepository(dataSource).getAll();
      final copyNode = updatedAll.firstWhere((s) => s.name == copyName);
      await serverMgmt.deleteServer(copyNode.id);
      await tester.pumpAndSettle();

      expect(find.text('4'), findsOneWidget); // header total count pill
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('country_group_ZZ')),
          matching: find.text('2 servers'),
        ),
        findsOneWidget,
      );

      // =====================================================================
      // STEP 6: Country location selection & persistence (P5-T7)
      // =====================================================================
      final ukHeader = find.byKey(const ValueKey<String>('country_header_GB'));
      await tester.ensureVisible(ukHeader);
      await tester.tap(ukHeader);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('country_selected_GB')),
        findsOneWidget,
      );
      expect(fakePrefs.getSelectedLocation(), equals('country:GB'));

      // =====================================================================
      // STEP 7: Connect toggle, traffic readout, lastUsedAt, disconnect (P5-T8)
      // =====================================================================
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_home')));
      await tester.pumpAndSettle();

      expect(find.text('United Kingdom'), findsOneWidget);
      expect(find.text('Auto-selected · 1 server'), findsOneWidget);

      final connectToggle = find.byKey(
        const ValueKey<String>('home_connect_toggle_button'),
      );
      expect(connectToggle, findsOneWidget);
      expect(
        find.descendant(of: connectToggle, matching: find.text('Connect')),
        findsOneWidget,
      );

      // Tap Connect toggle button
      await tester.tap(connectToggle);
      await tester.pump();

      expect(engine.prepareCalls, equals(1));
      expect(engine.startCalls, hasLength(1));
      expect(engine.startCalls.single.id, equals(qrNode.id));
      expect(engine.startCalls.single.name, equals('United Kingdom Node 2'));

      // Push Connected state from engine
      engine.emit(const Connected());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The orb hint switches to disconnect
      expect(
        find.descendant(of: connectToggle, matching: find.text('Disconnect')),
        findsOneWidget,
      );

      // Push live traffic stats and verify ThroughputReadout
      engine.emitStats(
        TrafficStats(
          txBytes: 1048576,
          rxBytes: 2097152,
          timestamp: DateTime.now().toUtc(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('1.0 MiB'), findsOneWidget);
      expect(find.textContaining('2.0 MiB'), findsOneWidget);

      // Tap Disconnect toggle button
      await tester.tap(connectToggle);
      await tester.pump();

      expect(engine.stopCalls, equals(1));

      // Push Disconnected state from engine
      engine.emit(const Disconnected());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.descendant(of: connectToggle, matching: find.text('Connect')),
        findsOneWidget,
      );

      // Verify lastUsedAt was stamped on United Kingdom Node 2
      final finalServers = await buildRepository(dataSource).getAll();
      final finalQrNode = finalServers.firstWhere((s) => s.id == qrNode.id);
      expect(finalQrNode.lastUsedAt, isNotNull);
    });
  });
}
