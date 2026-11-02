// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/screens/add_subscription_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

/// Fake implementation of [SubscriptionTransport] for deterministic tests.
class FakeSubscriptionTransport implements SubscriptionTransport {
  FakeSubscriptionTransport({this.handler});

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

class _FailingStorageRepository extends FakeServerProfileRepository {
  _FailingStorageRepository(super.dataSource);

  @override
  Future<void> saveSubscriptionWithProfiles(
    SubscriptionMetadata subscription,
    List<ServerProfile> profiles,
  ) async {
    throw const FileSystemException('Disk write failure / secret-db-path');
  }
}

TransportResponse _okResponse(
  String body, {
  Map<String, String> headers = const {},
}) {
  return TransportResponse(
    statusCode: HttpStatus.ok,
    headers: headers,
    body: Stream.value(utf8.encode(body)),
  );
}

const String _uuid = '11111111-2222-3333-4444-555555555555';
const String _vless1 =
    'vless://$_uuid@node1.example.com:443?security=none#Node1';
const String _vless2 =
    'vless://$_uuid@node2.example.com:443?security=none#Node2';
const String _vless3 =
    'vless://$_uuid@node3.example.com:443?security=none#Node3';

void main() {
  setUpAll(initTestLocalization);

  group('AddSubscriptionScreen — P5-T4 Subscription URL Import', () {
    testWidgets('full success: imports 3 valid servers and pops route', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      final fetcher = SubscriptionFetcher(
        transport: FakeSubscriptionTransport(
          handler: (uri, headers) async {
            return _okResponse('$_vless1\n$_vless2\n$_vless3');
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

      expect(dataSource.subscriptions, isEmpty);
      expect(dataSource.savedProfiles, isEmpty);

      // Navigate from Home to Add Subscription
      await tester.tap(
        find.byKey(const ValueKey<String>('home_add_subscription_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddSubscriptionScreen), findsOneWidget);

      // Enter subscription details
      await tester.enterText(
        find.byKey(const ValueKey<String>('add_subscription_url_field')),
        'https://sub.example.com/servers',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('add_subscription_name_field')),
        'Pro Fast VPN',
      );

      // Tap Import
      await tester.tap(
        find.byKey(const ValueKey<String>('add_subscription_import_button')),
      );
      await tester.pumpAndSettle();

      // UI verified: popped to HomeScreen with success SnackBar
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AddSubscriptionScreen), findsNothing);
      expect(find.text('Successfully imported 3 servers'), findsOneWidget);

      // Persistence verified: 1 metadata and 3 server profiles
      expect(dataSource.subscriptions, hasLength(1));
      final sub = dataSource.subscriptions.single;
      expect(sub.name, equals('Pro Fast VPN'));
      expect(sub.url, equals('https://sub.example.com/servers'));
      expect(sub.associatedServerIds, hasLength(3));

      expect(dataSource.savedProfiles, hasLength(3));
      final expectedEndpoints = [
        'node1.example.com:443',
        'node2.example.com:443',
        'node3.example.com:443',
      ];
      for (var i = 0; i < dataSource.savedProfiles.length; i++) {
        final profile = dataSource.savedProfiles[i];
        expect(profile.subscriptionId, equals(sub.id));
        expect(profile.name, equals('Pro Fast VPN - ${expectedEndpoints[i]}'));
        expect(sub.associatedServerIds, contains(profile.id));
      }
    });

    testWidgets('partial success: saves 2 valid servers and pops route', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      final fetcher = SubscriptionFetcher(
        transport: FakeSubscriptionTransport(
          handler: (uri, headers) async {
            return _okResponse(
              '$_vless1\n$_vless2\ninvalid-scheme://foo:bar/bad\n',
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

      await tester.tap(
        find.byKey(const ValueKey<String>('home_add_subscription_button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('add_subscription_url_field')),
        'https://sub.example.com/partial',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_subscription_import_button')),
      );
      await tester.pumpAndSettle();

      // Verified partial success: 2 imported, 1 skipped, SnackBar indicates
      // partial success, route popped.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AddSubscriptionScreen), findsNothing);
      expect(
        find.text('Imported 2 servers (1 invalid entries skipped)'),
        findsOneWidget,
      );

      expect(dataSource.subscriptions, hasLength(1));
      expect(dataSource.savedProfiles, hasLength(2));
      expect(dataSource.subscriptions.single.associatedServerIds, hasLength(2));
      expect(
        dataSource.savedProfiles[0].name,
        equals('sub.example.com - node1.example.com:443'),
      );
      expect(
        dataSource.savedProfiles[1].name,
        equals('sub.example.com - node2.example.com:443'),
      );
    });

    testWidgets('failure: network error shows SnackBar and stays on screen', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      final fetcher = SubscriptionFetcher(
        transport: FakeSubscriptionTransport(
          handler: (uri, headers) async {
            throw const SocketException('Connection refused');
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

      await tester.tap(
        find.byKey(const ValueKey<String>('home_add_subscription_button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('add_subscription_url_field')),
        'https://offline.example.com/feed',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_subscription_import_button')),
      );
      await tester.pumpAndSettle();

      // Screen stays open, SnackBar rendered, no persistence
      expect(find.byType(AddSubscriptionScreen), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(dataSource.subscriptions, isEmpty);
      expect(dataSource.savedProfiles, isEmpty);
    });

    testWidgets(
      'failure: zero valid servers shows localized error and stays on screen',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        final fetcher = SubscriptionFetcher(
          transport: FakeSubscriptionTransport(
            handler: (uri, headers) async {
              return _okResponse(
                'unsupported://bad1.example.com:443\n'
                'unsupported://bad2.example.com:443\n',
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

        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_subscription_button')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_url_field')),
          'https://sub.example.com/empty',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_subscription_import_button')),
        );
        await tester.pumpAndSettle();

        // Localized no_valid_servers error displayed
        expect(find.byType(AddSubscriptionScreen), findsOneWidget);
        expect(
          find.text('No valid server configurations found in subscription'),
          findsAtLeast(1),
        );
        expect(dataSource.subscriptions, isEmpty);
        expect(dataSource.savedProfiles, isEmpty);
      },
    );

    testWidgets('security: failed fetch never leaks sensitive tokens in UI', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      const secretToken = 'SECRET_TOKEN_XYZ_987654321';
      final fetcher = SubscriptionFetcher(
        transport: FakeSubscriptionTransport(
          handler: (uri, headers) async {
            return TransportResponse(
              statusCode: HttpStatus.forbidden,
              headers: const {},
              body: Stream.value(utf8.encode('Forbidden')),
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

      await tester.tap(
        find.byKey(const ValueKey<String>('home_add_subscription_button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('add_subscription_url_field')),
        'https://api.example.com/sub/v1?token=$secretToken',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_subscription_import_button')),
      );
      await tester.pumpAndSettle();

      // Zero-secrets assertion: SnackBar and all Text widgets must not contain
      // the secret token or sensitive query params
      expect(find.byType(SnackBar), findsOneWidget);
      final snackBarFinder = find.byType(SnackBar);
      final snackBarTexts = tester
          .widgetList<Text>(
            find.descendant(of: snackBarFinder, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? '')
          .toList();

      for (final text in snackBarTexts) {
        expect(text, isNot(contains(secretToken)));
        expect(text, isNot(contains('token=')));
      }
    });

    testWidgets('validation: empty URL shows localized error', (tester) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('home_add_subscription_button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('add_subscription_import_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter a subscription URL first'), findsAtLeast(1));
      expect(find.byType(AddSubscriptionScreen), findsOneWidget);
      expect(dataSource.subscriptions, isEmpty);
    });

    testWidgets('validation: invalid URL scheme shows localized error', (
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

      await tester.tap(
        find.byKey(const ValueKey<String>('home_add_subscription_button')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('add_subscription_url_field')),
        'ftp://example.com/subscription',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_subscription_import_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter a valid HTTPS subscription URL'),
        findsAtLeast(1),
      );
      expect(find.byType(AddSubscriptionScreen), findsOneWidget);
      expect(dataSource.subscriptions, isEmpty);
    });

    testWidgets('clipboard paste affordance updates URL text field', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.getData') {
            return const <String, dynamic>{
              'text': 'https://sub.example.com/pasted',
            };
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('home_add_subscription_button')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('add_subscription_paste_button')),
      );
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('add_subscription_url_field')),
      );
      expect(textField.controller?.text, 'https://sub.example.com/pasted');
    });

    testWidgets(
      'failure: storage exception shows safe localized error without leaks',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        final fetcher = SubscriptionFetcher(
          transport: FakeSubscriptionTransport(
            handler: (uri, headers) async {
              return _okResponse(_vless1);
            },
          ),
        );

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          subscriptionFetcher: fetcher,
          repository: _FailingStorageRepository(dataSource),
        );

        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_subscription_button')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('add_subscription_url_field')),
          'https://sub.example.com/storage-fail',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_subscription_import_button')),
        );
        await tester.pumpAndSettle();

        // Stays on screen, shows safe localized error, does NOT leak exception
        expect(find.byType(AddSubscriptionScreen), findsOneWidget);
        expect(
          find.text('Failed to save subscription to local storage'),
          findsAtLeast(1),
        );
        expect(find.textContaining('FileSystemException'), findsNothing);
        expect(find.textContaining('secret-db-path'), findsNothing);
      },
    );
  });
}
