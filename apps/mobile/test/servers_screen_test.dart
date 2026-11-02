// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/add_subscription_screen.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

class _FakeSubscriptionTransport implements SubscriptionTransport {
  _FakeSubscriptionTransport({this.handler});

  Future<TransportResponse> Function(Uri uri, Map<String, String> headers)?
  handler;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async {
    if (handler != null) {
      return await handler!(uri, headers);
    }
    return TransportResponse(
      statusCode: HttpStatus.ok,
      headers: const {},
      body: Stream.value(utf8.encode('')),
    );
  }

  @override
  void close() {}
}

const String _uuid = '11111111-2222-3333-4444-555555555555';
const String _standaloneVless =
    'vless://$_uuid@standalone.example.com:443?security=none#Standalone1';
const String _subVless1 =
    'vless://$_uuid@sub1.example.com:443?security=none#SubNode1';
const String _subVless2 =
    'vless://$_uuid@sub2.example.com:443?security=none#SubNode2';

void main() {
  setUpAll(initTestLocalization);

  group('ServersScreen — P5-T5 Server List Screen (Real Data)', () {
    testWidgets('empty state renders and CTA buttons navigate cleanly', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );

      // Switch to Servers tab (bottom navigation bar)
      await tester.tap(find.byIcon(Icons.dns));
      await tester.pumpAndSettle();

      expect(find.byType(ServersScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Servers'), findsOneWidget);

      // Verify empty state text and icons
      expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
      expect(find.text('No servers added yet'), findsOneWidget);
      expect(
        find.text(
          'Add a server link, scan a QR code, or import a subscription '
          'to get started.',
        ),
        findsOneWidget,
      );

      // Verify CTA: Add Server button navigates to /add-server
      expect(
        find.byKey(const ValueKey<String>('servers_empty_add_server_button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('servers_empty_add_server_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddServerScreen), findsOneWidget);

      // Pop back to ServersScreen
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ServersScreen), findsOneWidget);

      // Verify CTA: Add Subscription button navigates to /add-subscription
      expect(
        find.byKey(
          const ValueKey<String>('servers_empty_add_subscription_button'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey<String>('servers_empty_add_subscription_button'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddSubscriptionScreen), findsOneWidget);
    });

    testWidgets('AppBar actions navigate to add server and add subscription', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );

      await tester.tap(find.byIcon(Icons.dns));
      await tester.pumpAndSettle();

      // Tap AppBar Add Server action
      await tester.tap(
        find.byKey(const ValueKey<String>('servers_add_server_action')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddServerScreen), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      // Tap AppBar Add Subscription action
      await tester.tap(
        find.byKey(const ValueKey<String>('servers_add_subscription_action')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddSubscriptionScreen), findsOneWidget);
    });

    testWidgets(
      'reactive update: adding manual server updates ServersScreen dynamically',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );

        // Switch to Servers tab
        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();
        expect(find.text('No servers added yet'), findsOneWidget);

        // Tap Add Server action from AppBar
        await tester.tap(
          find.byKey(const ValueKey<String>('servers_add_server_action')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AddServerScreen), findsOneWidget);

        // Paste VLESS URI and tap Save
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          _standaloneVless,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        // Popped back to ServersScreen — must reactively display the new server
        expect(find.byType(ServersScreen), findsOneWidget);
        expect(find.text('No servers added yet'), findsNothing);
        expect(find.text('Standalone Servers'), findsOneWidget);
        expect(find.text('Standalone1'), findsOneWidget);
        expect(find.text('VLESS'), findsOneWidget);
        expect(find.text('standalone.example.com:443'), findsOneWidget);
        expect(find.text('Standalone'), findsOneWidget);
      },
    );

    testWidgets(
      'grouping & security: standalone vs subscription distinction without '
      'URL leaks',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        const secretToken = 'SECRET_TOKEN_SUPER_CONFIDENTIAL_12345';
        const secretSubUrl = 'https://sub.provider.com/feed?token=$secretToken';

        final fetcher = SubscriptionFetcher(
          transport: _FakeSubscriptionTransport(
            handler: (uri, headers) async {
              return TransportResponse(
                statusCode: HttpStatus.ok,
                headers: const {},
                body: Stream.value(utf8.encode('$_subVless1\n$_subVless2')),
              );
            },
          ),
        );

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          subscriptionFetcher: fetcher,
        );

        // Add 1 standalone server first
        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_server_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          _standaloneVless,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        // Import 1 subscription with 2 servers
        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_subscription_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_url_field')),
          secretSubUrl,
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_name_field')),
          'Pro Nodes Plan',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_subscription_import_button')),
        );
        await tester.pumpAndSettle();

        // Switch to Servers tab
        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        expect(find.byType(ServersScreen), findsOneWidget);

        // 1. Standalone section verification
        expect(find.text('Standalone Servers'), findsOneWidget);
        expect(find.text('Standalone1'), findsOneWidget);
        expect(find.text('Standalone'), findsOneWidget);

        // 2. Subscription section verification
        expect(find.text('Pro Nodes Plan'), findsAtLeast(1));
        expect(
          find.text('Pro Nodes Plan - sub1.example.com:443'),
          findsOneWidget,
        );
        expect(
          find.text('Pro Nodes Plan - sub2.example.com:443'),
          findsOneWidget,
        );

        // 3. Zero-secret leak guarantee: secret token and URL never rendered
        expect(find.textContaining(secretToken), findsNothing);
        expect(find.textContaining('sub.provider.com'), findsNothing);
      },
    );

    testWidgets('removing all servers reactively returns to empty state', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );

      // Add a server
      await tester.tap(
        find.byKey(const ValueKey<String>('home_add_server_button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('add_server_uri_field')),
        _standaloneVless,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_save_button')),
      );
      await tester.pumpAndSettle();

      // Go to Servers screen
      await tester.tap(find.byIcon(Icons.dns));
      await tester.pumpAndSettle();
      expect(find.text('Standalone1'), findsOneWidget);

      // Find and tap the remove button on the server tile
      final serverId = dataSource.records.first.id;
      final deleteKey = ValueKey<String>('server_delete_$serverId');
      expect(find.byKey(deleteKey), findsOneWidget);

      await tester.tap(find.byKey(deleteKey));
      await tester.pumpAndSettle();

      // Reactively transitions to Empty State
      expect(find.text('No servers added yet'), findsOneWidget);
      expect(find.text('Standalone1'), findsNothing);
    });

    testWidgets(
      'broken server entry renders safely without URI leak and can be removed',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        // Seed a broken unparseable record containing sensitive text
        const sensitiveBadUri =
            'unsupported-proto://secret_user:secret_pass@host:1234';
        dataSource.records.add(
          SavedServerRecord(
            id: 'broken_entry_1',
            sourceUri: sensitiveBadUri,
            addedAt: DateTime.utc(2026, 11, 2),
          ),
        );

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );

        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        // Broken tile rendered safely with safe title
        expect(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('server_broken_tile_broken_entry_1'),
            ),
            matching: find.text('Unreadable server'),
          ),
          findsOneWidget,
        );

        // Security check: sensitive text inside the broken URI is NOT displayed
        expect(find.textContaining('secret_user'), findsNothing);
        expect(find.textContaining('secret_pass'), findsNothing);

        // Remove the broken entry
        final deleteButton = find.byKey(
          const ValueKey<String>('server_delete_broken_entry_1'),
        );
        expect(deleteButton, findsOneWidget);
        await tester.tap(deleteButton);
        await tester.pumpAndSettle();

        // Removed cleanly -> Empty state
        expect(find.text('No servers added yet'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey<String>('server_broken_tile_broken_entry_1'),
          ),
          findsNothing,
        );
      },
    );
  });
}
