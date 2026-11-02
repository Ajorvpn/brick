// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart' show ServerProfile;
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

class _FailingServerProfileRepository extends FakeServerProfileRepository {
  _FailingServerProfileRepository(super.dataSource);

  @override
  Future<void> save(ServerProfile profile) async {
    throw const FileSystemException(
      'Disk write error',
      '/secret-storage-path/profiles.json',
    );
  }
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

      expect(
        find.byKey(const ValueKey<String>('confirm_delete_dialog')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm_delete_confirm')),
      );
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

        expect(
          find.byKey(const ValueKey<String>('confirm_delete_dialog')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_delete_confirm')),
        );
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

    testWidgets(
      'delete confirmation dialog: cancel keeps server, confirm deletes it',
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

        // Add 1 standalone server
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

        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();
        expect(find.text('Standalone1'), findsOneWidget);

        final serverId = dataSource.records.first.id;
        final deleteKey = ValueKey<String>('server_delete_$serverId');

        // 1. Tap delete button -> dialog appears
        await tester.tap(find.byKey(deleteKey));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('confirm_delete_dialog')),
          findsOneWidget,
        );
        expect(find.text('Delete Server'), findsOneWidget);

        // 2. Tap cancel -> dialog disappears, server still exists
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_delete_cancel')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('confirm_delete_dialog')),
          findsNothing,
        );
        expect(find.text('Standalone1'), findsOneWidget);

        // 3. Tap delete again -> dialog appears
        await tester.tap(find.byKey(deleteKey));
        await tester.pumpAndSettle();

        // 4. Tap confirm -> server deleted -> empty state
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_delete_confirm')),
        );
        await tester.pumpAndSettle();
        expect(find.text('No servers added yet'), findsOneWidget);
        expect(find.text('Standalone1'), findsNothing);
      },
    );

    testWidgets(
      'edit standalone server: updates name & URI reactively; validates URI '
      'error without closing; subscription servers lack edit button',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        final fetcher = SubscriptionFetcher(
          transport: _FakeSubscriptionTransport(
            handler: (uri, headers) async {
              return TransportResponse(
                statusCode: HttpStatus.ok,
                headers: const {},
                body: Stream.value(utf8.encode(_subVless1)),
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

        // Add 1 standalone server
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

        // Add 1 subscription
        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_subscription_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_url_field')),
          'https://sub.example.com/feed',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_name_field')),
          'SubGroup',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_subscription_import_button')),
        );
        await tester.pumpAndSettle();

        // Go to Servers screen
        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        final standaloneId = dataSource.records.first.id;
        final subServerId = dataSource.savedProfiles.first.id;

        // 1. Verify subscription server does NOT have an edit button
        expect(
          find.byKey(ValueKey<String>('server_edit_$subServerId')),
          findsNothing,
        );

        // 2. Standalone server DOES have an edit button
        final editButton = find.byKey(
          ValueKey<String>('server_edit_$standaloneId'),
        );
        expect(editButton, findsOneWidget);

        // 3. Tap Edit button -> Edit dialog opens
        await tester.tap(editButton);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('edit_server_dialog')),
          findsOneWidget,
        );
        expect(find.text('Edit Server'), findsOneWidget);

        // 4. Test validation: enter empty name -> error, dialog remains open
        await tester.enterText(
          find.byKey(const ValueKey<String>('edit_server_name_field')),
          '   ',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('edit_server_save')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('edit_server_dialog')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('edit_server_dialog')),
            matching: find.text('Server name cannot be empty'),
          ),
          findsOneWidget,
        );

        // 5. Test validation: enter invalid replacement URI -> error shown
        await tester.enterText(
          find.byKey(const ValueKey<String>('edit_server_name_field')),
          'Renamed Standalone',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('edit_server_uri_field')),
          'badprotocol://invalid-uri',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('edit_server_save')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('edit_server_dialog')),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsOneWidget);

        // Dismiss SnackBar
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(seconds: 5));

        // 6. Test success: enter valid replacement URI (Trojan) & valid name
        const replacementTrojan =
            'trojan://newpassword@newtrojan.example.com:443#Renamed Standalone';
        await tester.enterText(
          find.byKey(const ValueKey<String>('edit_server_uri_field')),
          replacementTrojan,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('edit_server_save')),
        );
        await tester.pumpAndSettle();

        // Dialog should be dismissed
        expect(
          find.byKey(const ValueKey<String>('edit_server_dialog')),
          findsNothing,
        );

        // Tile reactively reflects updated name and new protocol
        expect(find.text('Renamed Standalone'), findsOneWidget);
        expect(find.text('TROJAN'), findsOneWidget);
        expect(find.text('newtrojan.example.com:443'), findsOneWidget);
      },
    );

    testWidgets(
      'duplicate server: creates independent standalone copy for both '
      'standalone and subscription servers',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        final fetcher = SubscriptionFetcher(
          transport: _FakeSubscriptionTransport(
            handler: (uri, headers) async {
              return TransportResponse(
                statusCode: HttpStatus.ok,
                headers: const {},
                body: Stream.value(utf8.encode(_subVless1)),
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

        // Import 1 subscription
        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_subscription_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_url_field')),
          'https://sub.example.com/feed',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_name_field')),
          'SubGroup',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_subscription_import_button')),
        );
        await tester.pumpAndSettle();

        // Switch to Servers screen
        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        expect(find.text('Standalone Servers'), findsNothing);
        expect(find.text('SubGroup'), findsAtLeast(1));

        final subServerId = dataSource.savedProfiles.first.id;

        // Duplicate subscription server
        final duplicateButton = find.byKey(
          ValueKey<String>('server_duplicate_$subServerId'),
        );
        expect(duplicateButton, findsOneWidget);
        await tester.tap(duplicateButton);
        await tester.pumpAndSettle();

        // Standalone section now exists with the duplicate server!
        expect(find.text('Standalone Servers'), findsOneWidget);
        expect(
          find.text('SubGroup - sub1.example.com:443 (Copy)'),
          findsOneWidget,
        );
        // Original subscription server still exists in its group
        expect(find.text('SubGroup - sub1.example.com:443'), findsOneWidget);
      },
    );

    testWidgets(
      'subscription refresh: updates servers on success; preserves existing '
      'servers on fetch error',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        var simulateNetworkError = false;
        var fetchedPayload = _subVless1;

        final fetcher = SubscriptionFetcher(
          transport: _FakeSubscriptionTransport(
            handler: (uri, headers) async {
              if (simulateNetworkError) {
                throw const SocketException('Connection refused');
              }
              return TransportResponse(
                statusCode: HttpStatus.ok,
                headers: const {},
                body: Stream.value(utf8.encode(fetchedPayload)),
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

        // Import subscription initially with _subVless1
        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_subscription_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_url_field')),
          'https://sub.example.com/feed',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_name_field')),
          'Plan Alpha',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_subscription_import_button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        final subId = dataSource.subscriptions.first.id;
        final refreshKey = ValueKey<String>('subscription_refresh_$subId');
        expect(find.byKey(refreshKey), findsOneWidget);
        expect(find.text('Plan Alpha - sub1.example.com:443'), findsOneWidget);

        // 1. Simulate network failure during refresh
        simulateNetworkError = true;
        await tester.tap(find.byKey(refreshKey));
        await tester.pumpAndSettle();

        // Error feedback displayed and existing server preserved untouched!
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Plan Alpha - sub1.example.com:443'), findsOneWidget);

        // Dismiss SnackBar
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(seconds: 5));

        // 2. Simulate successful refresh with new server list (_subVless2)
        simulateNetworkError = false;
        fetchedPayload = _subVless2;

        await tester.tap(find.byKey(refreshKey));
        await tester.pumpAndSettle();

        // Success SnackBar displayed
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Successfully imported 1 servers'), findsOneWidget);

        // Old server sub1 replaced by new server sub2!
        expect(find.text('Plan Alpha - sub1.example.com:443'), findsNothing);
        expect(find.text('Plan Alpha - sub2.example.com:443'), findsOneWidget);
      },
    );

    testWidgets(
      'delete subscription cascade: removes subscription header and all child '
      'servers',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

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

        // Import subscription with 2 servers
        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_subscription_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_url_field')),
          'https://sub.example.com/feed',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_name_field')),
          'Cascade Plan',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_subscription_import_button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        expect(find.text('Cascade Plan'), findsAtLeast(1));
        expect(
          find.text('Cascade Plan - sub1.example.com:443'),
          findsOneWidget,
        );
        expect(
          find.text('Cascade Plan - sub2.example.com:443'),
          findsOneWidget,
        );

        final subId = dataSource.subscriptions.first.id;
        final deleteSubKey = ValueKey<String>('subscription_delete_$subId');

        // Tap Delete Subscription button -> confirmation dialog appears
        await tester.tap(find.byKey(deleteSubKey));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('confirm_delete_dialog')),
          findsOneWidget,
        );
        expect(find.text('Delete Subscription'), findsOneWidget);

        // Confirm deletion
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_delete_confirm')),
        );
        await tester.pumpAndSettle();

        // Subscription and all associated servers removed -> empty state
        expect(find.text('No servers added yet'), findsOneWidget);
        expect(find.text('Cascade Plan'), findsNothing);
        expect(find.text('Cascade Plan - sub1.example.com:443'), findsNothing);
        expect(find.text('Cascade Plan - sub2.example.com:443'), findsNothing);
      },
    );

    testWidgets(
      'rapid duplicate calls generate unique standalone server IDs via '
      'monotonic sequence without collision',
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

        // Add 1 standalone server
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

        // Switch to Servers screen
        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        final originalId = dataSource.records.first.id;
        final duplicateButton = find.byKey(
          ValueKey<String>('server_duplicate_$originalId'),
        );
        expect(duplicateButton, findsOneWidget);

        // Duplicate twice rapidly
        await tester.tap(duplicateButton);
        await tester.pumpAndSettle();
        await tester.tap(duplicateButton);
        await tester.pumpAndSettle();

        // Expect 2 saved duplicated profiles in dataSource.savedProfiles
        expect(dataSource.savedProfiles.length, equals(2));
        final ids = <String>{
          originalId,
          ...dataSource.savedProfiles.map((p) => p.id),
        };
        // All 3 IDs must be unique
        expect(ids.length, equals(3));
        expect(
          dataSource.savedProfiles[0].id,
          isNot(equals(dataSource.savedProfiles[1].id)),
        );
        expect(find.text('Standalone1 (Copy)'), findsNWidgets(2));
      },
    );

    testWidgets(
      'repository FileSystemException is redacted to generic storage error '
      'and never leaks raw paths or exception details to UI',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        final failingRepo = _FailingServerProfileRepository(dataSource);
        addTearDown(engine.dispose);

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          repository: failingRepo,
        );

        // Add 1 standalone server
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

        // Switch to Servers screen
        await tester.tap(find.byIcon(Icons.dns));
        await tester.pumpAndSettle();

        final serverId = dataSource.records.first.id;

        // Open Edit Dialog
        await tester.tap(find.byKey(ValueKey<String>('server_edit_$serverId')));
        await tester.pumpAndSettle();

        // Change name and attempt to save (triggers repo.save which throws)
        await tester.enterText(
          find.byKey(const ValueKey<String>('edit_server_name_field')),
          'RenamedServer',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('edit_server_save')),
        );
        await tester.pumpAndSettle();

        // Redacted localized storage error message must be shown
        expect(
          find.text('Failed to save server changes to local storage'),
          findsAtLeast(1),
        );

        // Security assertion: Never leak exception class, OS error, or paths
        expect(find.textContaining('FileSystemException'), findsNothing);
        expect(find.textContaining('secret-storage-path'), findsNothing);
        expect(find.textContaining('Disk write error'), findsNothing);
      },
    );
  });
}
