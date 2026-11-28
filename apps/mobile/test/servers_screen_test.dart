// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart' show ServerProfile;
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

  @override
  Future<void> delete(String id) async {
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
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
      await tester.pumpAndSettle();

      expect(find.byType(ServersScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('servers_update_button')),
        findsOneWidget,
      );

      // Verify guided empty state
      expect(
        find.byKey(const ValueKey<String>('servers_empty_state')),
        findsOneWidget,
      );
      expect(find.text('No servers added yet'), findsOneWidget);
      expect(
        find.text(
          "Servers sync automatically from Brick VPN's official directory. "
          'Tap Update Servers to retry.',
        ),
        findsOneWidget,
      );

      // Manual add affordances are intentionally hidden (UX Refinement #3)
      expect(
        find.byKey(const ValueKey<String>('servers_empty_add_server_button')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('servers_empty_add_subscription_button'),
        ),
        findsNothing,
      );

      // Play-compliant disclosure flow from the empty-state Update Servers CTA
      expect(
        find.byKey(const ValueKey<String>('servers_empty_update_button')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('servers_empty_update_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('update_servers_disclosure_sheet')),
        findsOneWidget,
      );
      final cancelFinder = find.byKey(
        const ValueKey<String>('update_servers_disclosure_cancel'),
      );
      await tester.ensureVisible(cancelFinder);
      await tester.pumpAndSettle();
      await tester.tap(cancelFinder);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('update_servers_disclosure_sheet')),
        findsNothing,
        reason:
            'Tapping Cancel MUST dismiss the modal disclosure sheet cleanly',
      );

      // /add-server route remains reachable despite the hidden affordance
      unawaited(tester.element(find.byType(ServersScreen)).push('/add-server'));
      await tester.pumpAndSettle();
      expect(find.byType(AddServerScreen), findsOneWidget);

      // Pop back to ServersScreen
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ServersScreen), findsOneWidget);

      // /add-subscription route remains reachable as well
      unawaited(
        tester.element(find.byType(ServersScreen)).push('/add-subscription'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddSubscriptionScreen), findsOneWidget);
    });

    testWidgets(
      'preserved add-server and add-subscription routes are reachable',
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

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        // Manual add affordances stay hidden on ServersScreen
        expect(
          find.byKey(const ValueKey<String>('servers_add_server_action')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('servers_add_subscription_action')),
          findsNothing,
        );

        // Navigate to /add-server via the preserved route
        unawaited(
          tester.element(find.byType(ServersScreen)).push('/add-server'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AddServerScreen), findsOneWidget);

        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();

        // Navigate to /add-subscription via the preserved route
        unawaited(
          tester.element(find.byType(ServersScreen)).push('/add-subscription'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AddSubscriptionScreen), findsOneWidget);
      },
    );

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
        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();
        expect(find.text('No servers added yet'), findsOneWidget);

        // Navigate to /add-server via the preserved route
        unawaited(
          tester.element(find.byType(ServersScreen)).push('/add-server'),
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

        // Popped back to ServersScreen — reactively shows Smart Auto + country
        expect(find.byType(ServersScreen), findsOneWidget);
        expect(find.text('No servers added yet'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('server_location_auto')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('country_group_ZZ')),
          findsOneWidget,
        );
        expect(find.text('Other Locations'), findsOneWidget);
        expect(find.text('1 server'), findsAtLeast(1));
        expect(
          find.byKey(
            ValueKey<String>('server_tile_${dataSource.records.first.id}'),
          ),
          findsNothing,
        );
        expect(find.textContaining('standalone.example.com:443'), findsNothing);
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
        unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
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
        unawaited(
          tester.element(find.byType(HomeScreen)).push('/add-subscription'),
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
        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        expect(find.byType(ServersScreen), findsOneWidget);

        // 1. Country card aggregates standalone + subscription nodes without
        // exposing individual tiles or raw endpoints
        final zzGroup = find.byKey(const ValueKey<String>('country_group_ZZ'));
        expect(zzGroup, findsOneWidget);
        expect(
          find.descendant(of: zzGroup, matching: find.text('Other Locations')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: zzGroup, matching: find.text('3 servers')),
          findsOneWidget,
        );
        expect(find.text('Standalone1'), findsNothing);
        expect(find.textContaining('sub1.example.com:443'), findsNothing);

        // 2. Linked user subscription strip remains visible
        expect(find.text('Pro Nodes Plan'), findsAtLeast(1));

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
      unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
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
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('country_group_ZZ')),
        findsOneWidget,
      );

      // Delete the saved server via controller -> UI reacts cleanly
      final serverId = dataSource.records.first.id;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ServersScreen)),
      );
      await container
          .read(serverManagementControllerProvider.notifier)
          .deleteServer(serverId);
      await tester.pumpAndSettle();

      // Reactively transitions to Empty State
      expect(find.text('No servers added yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('country_group_ZZ')),
        findsNothing,
      );
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

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
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
      'delete confirmation dialog: cancel keeps entry, confirm deletes it',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        dataSource.records.add(
          SavedServerRecord(
            id: 'broken_entry_dialog_1',
            sourceUri: 'unsupported://bad@host:1234',
            addedAt: DateTime.utc(2026, 11, 2),
          ),
        );

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        const tileKey = ValueKey<String>(
          'server_broken_tile_broken_entry_dialog_1',
        );
        const deleteKey = ValueKey<String>(
          'server_delete_broken_entry_dialog_1',
        );
        expect(find.byKey(tileKey), findsOneWidget);

        // 1. Tap delete button -> dialog appears
        await tester.tap(find.byKey(deleteKey));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('confirm_delete_dialog')),
          findsOneWidget,
        );
        expect(find.text('Delete Server'), findsOneWidget);

        // 2. Tap cancel -> dialog disappears, broken entry still exists
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_delete_cancel')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('confirm_delete_dialog')),
          findsNothing,
        );
        expect(find.byKey(tileKey), findsOneWidget);

        // 3. Tap delete again -> dialog appears
        await tester.tap(find.byKey(deleteKey));
        await tester.pumpAndSettle();

        // 4. Tap confirm -> deleted -> empty state
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_delete_confirm')),
        );
        await tester.pumpAndSettle();
        expect(find.text('No servers added yet'), findsOneWidget);
        expect(find.byKey(tileKey), findsNothing);
      },
    );

    testWidgets('country-only cards omit per-node edit/duplicate clutter while controller '
        'mutations update counts reactively', (tester) async {
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
      unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
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
      unawaited(
        tester.element(find.byType(HomeScreen)).push('/add-subscription'),
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
      await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
      await tester.pumpAndSettle();
      // Let the import success snackbar expire
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final standaloneId = dataSource.records.first.id;
      final subServerId = dataSource.savedProfiles.first.id;

      // Per-node Edit/Duplicate buttons stay absent on Country-Only UI.
      expect(
        find.byKey(ValueKey<String>('server_edit_$subServerId')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey<String>('server_edit_$standaloneId')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey<String>('server_duplicate_$subServerId')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_ZZ')),
        findsOneWidget,
      );
      expect(find.text('2 servers'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ServersScreen)),
      );
      await container
          .read(serverManagementControllerProvider.notifier)
          .duplicateServer(dataSource.savedProfiles.first);
      await tester.pumpAndSettle();
      expect(find.text('3 servers'), findsOneWidget);
    });

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
        unawaited(
          tester.element(find.byType(HomeScreen)).push('/add-subscription'),
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

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        final subId = dataSource.subscriptions.first.id;
        final refreshKey = ValueKey<String>('subscription_refresh_$subId');
        expect(find.byKey(refreshKey), findsOneWidget);
        final zzGroup = find.byKey(const ValueKey<String>('country_group_ZZ'));
        expect(zzGroup, findsOneWidget);
        expect(
          find.descendant(of: zzGroup, matching: find.text('1 server')),
          findsOneWidget,
        );

        // 1. Simulate network failure during refresh
        simulateNetworkError = true;
        await tester.tap(find.byKey(refreshKey));
        await tester.pumpAndSettle();

        // Error feedback displayed and existing server count preserved!
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.descendant(of: zzGroup, matching: find.text('1 server')),
          findsOneWidget,
        );

        // Dismiss SnackBar
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(seconds: 5));

        // 2. Simulate successful refresh with new server list
        simulateNetworkError = false;
        fetchedPayload = '$_subVless1\n$_subVless2';

        await tester.tap(find.byKey(refreshKey));
        await tester.pumpAndSettle();

        // Success SnackBar displayed and country count updated cleanly
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Successfully imported 2 servers'), findsOneWidget);
        expect(
          find.descendant(of: zzGroup, matching: find.text('2 servers')),
          findsOneWidget,
        );
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
        unawaited(
          tester.element(find.byType(HomeScreen)).push('/add-subscription'),
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

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        expect(find.text('Cascade Plan'), findsAtLeast(1));
        expect(
          find.byKey(const ValueKey<String>('country_group_ZZ')),
          findsOneWidget,
        );
        expect(find.text('2 servers'), findsOneWidget);

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
        expect(
          find.byKey(const ValueKey<String>('country_group_ZZ')),
          findsNothing,
        );
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
        unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
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
        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        final originalId = dataSource.records.first.id;
        final repo = buildRepository(dataSource);
        final originalProfile = (await repo.getAll()).single;
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ServersScreen)),
        );
        final mgmt = container.read(
          serverManagementControllerProvider.notifier,
        );

        // Duplicate twice rapidly via controller
        await mgmt.duplicateServer(originalProfile);
        await mgmt.duplicateServer(originalProfile);
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
        expect(find.text('3 servers'), findsOneWidget);
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

        dataSource.records.add(
          SavedServerRecord(
            id: 'broken_redaction_1',
            sourceUri: 'unsupported://bad@host:1234',
            addedAt: DateTime.utc(2026, 11, 2),
          ),
        );

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          repository: failingRepo,
        );

        // Switch to Servers screen
        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        // Trigger repository FileSystemException via broken tile delete action
        await tester.tap(
          find.byKey(
            const ValueKey<String>('server_delete_broken_redaction_1'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_delete_confirm')),
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

    testWidgets(
      'default auto-fallback selection: marks Smart Auto active by default',
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

        unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          'vless://$_uuid@uk.example.com:443?security=none#United%20Kingdom%2001',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        // Without explicit selection, Smart Auto is active by default.
        expect(
          find.byKey(const ValueKey<String>('server_location_auto_selected')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('country_selected_GB')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'tapping a country card changes active selection and persists to prefs',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        final fakePrefs = FakeAppPreferencesRepository();
        addTearDown(engine.dispose);

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          preferencesRepository: fakePrefs,
        );

        unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          'vless://$_uuid@uk.example.com:443?security=none#United%20Kingdom%2001',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('country_header_GB')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('country_selected_GB')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('server_location_auto_selected')),
          findsNothing,
        );
        expect(fakePrefs.getSelectedLocation(), equals('country:GB'));
      },
    );

    testWidgets(
      'deleting all servers cleanly restores empty state without crash',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        final fakePrefs = FakeAppPreferencesRepository();
        addTearDown(engine.dispose);

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          preferencesRepository: fakePrefs,
        );

        unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          _standaloneVless,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('country_header_ZZ')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('country_selected_ZZ')),
          findsOneWidget,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ServersScreen)),
        );
        await container
            .read(serverManagementControllerProvider.notifier)
            .deleteServer(dataSource.records.first.id);
        await tester.pumpAndSettle();

        expect(find.text('No servers added yet'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsNothing);
      },
    );

    testWidgets(
      'end-to-end: selecting country in ServersScreen connects that country',
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

        // Add Germany + United Kingdom standalone servers
        unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          'vless://$_uuid@de.example.com:443?security=none#Germany%2001',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        unawaited(tester.element(find.byType(HomeScreen)).push('/add-server'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          'vless://$_uuid@uk.example.com:443?security=none#United%20Kingdom%2001',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        // Switch to Servers screen and select United Kingdom
        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_servers')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('country_header_GB')),
        );
        await tester.pumpAndSettle();

        // Switch to Home screen
        await tester.tap(find.byKey(const ValueKey<String>('nav_tab_home')));
        await tester.pumpAndSettle();

        expect(find.text('United Kingdom'), findsOneWidget);
        expect(find.text('Auto-selected · 1 server'), findsOneWidget);

        // Tap the dashboard orb
        await tester.tap(
          find.byKey(const ValueKey<String>('home_connect_toggle_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // Engine starts with the United Kingdom profile
        expect(engine.startCalls, hasLength(1));
        expect(engine.startCalls.single.name, equals('United Kingdom 01'));
      },
    );
  });
}
