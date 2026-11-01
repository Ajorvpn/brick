// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  group('AddServerScreen — P5-T2 Manual URI Paste & Direct Save', () {
    testWidgets('valid VLESS URI directly saves to repository and pops route', (
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

      expect(dataSource.records, isEmpty);

      // Navigate from Home to Add Server screen
      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();
      expect(find.byType(AddServerScreen), findsOneWidget);

      // Enter valid VLESS URI and tap Save
      await tester.enterText(
        find.byKey(const ValueKey<String>('add_server_uri_field')),
        validVlessUri,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_save_button')),
      );
      await tester.pumpAndSettle();

      // Verified: direct persistence without preview dialog, route popped
      expect(dataSource.records, hasLength(1));
      expect(dataSource.records.single.sourceUri, equals(validVlessUri));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AddServerScreen), findsNothing);
    });

    testWidgets(
      'valid Trojan URI directly saves to repository and pops route',
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

        expect(dataSource.records, isEmpty);

        // Navigate from Home to Add Server screen
        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();
        expect(find.byType(AddServerScreen), findsOneWidget);

        // Enter valid Trojan URI and tap Save
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          validTrojanUri,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        // Verified: direct persistence of second protocol, route popped
        expect(dataSource.records, hasLength(1));
        expect(dataSource.records.single.sourceUri, equals(validTrojanUri));
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(AddServerScreen), findsNothing);
      },
    );

    testWidgets(
      'invalid URI displays error SnackBar, inline error, and stays on screen',
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

        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();

        // Enter invalid URI
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          'not-a-valid-uri',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pump();

        // Verified: error presented via SnackBar, stays on AddServerScreen
        expect(find.byType(SnackBar), findsOneWidget);
        expect(dataSource.records, isEmpty);
        expect(find.byType(AddServerScreen), findsOneWidget);

        // Verify inline error text is also rendered on the TextField
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
        );
        expect(field.decoration?.errorText, isNotNull);
      },
    );

    testWidgets(
      'pasting an HTTPS subscription URL triggers subscription rejection',
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

        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();

        // Paste an HTTP subscription link
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          'https://example.com/api/v1/client/subscribe?token=secret123',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pump();

        // Verified: rejected with specific subscription guidance error
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.widgetWithText(
            SnackBar,
            'This is a subscription URL. Please use the Add Subscription flow.',
          ),
          findsOneWidget,
        );
        expect(dataSource.records, isEmpty);
        expect(find.byType(AddServerScreen), findsOneWidget);
      },
    );

    testWidgets(
      'pasting a multi-line subscription payload triggers rejection error',
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

        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();

        // Paste multiple server URIs (multi-line subscription payload)
        const multiLinePayload = '$validVlessUri\n$validTrojanUri';
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          multiLinePayload,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.widgetWithText(
            SnackBar,
            'This is a subscription URL. Please use the Add Subscription flow.',
          ),
          findsOneWidget,
        );
        expect(dataSource.records, isEmpty);
        expect(find.byType(AddServerScreen), findsOneWidget);
      },
    );

    testWidgets(
      'pasting a base64 subscription payload triggers rejection error',
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

        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();

        // Paste base64-encoded subscription payload
        final base64Payload = base64Encode(
          utf8.encode('$validVlessUri\n$validTrojanUri'),
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          base64Payload,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.widgetWithText(
            SnackBar,
            'This is a subscription URL. Please use the Add Subscription flow.',
          ),
          findsOneWidget,
        );
        expect(dataSource.records, isEmpty);
        expect(find.byType(AddServerScreen), findsOneWidget);
      },
    );

    testWidgets(
      'clipboard paste button populates TextField, clears errors, and saves',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        // Mock platform clipboard
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall methodCall) async {
            if (methodCall.method == 'Clipboard.getData') {
              return const <String, dynamic>{'text': validTrojanUri};
            }
            return null;
          },
        );

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
        );

        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();

        // First trigger an error with invalid text
        await tester.enterText(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
          'invalid',
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);

        // Tap paste icon button
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_paste_button')),
        );
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('add_server_uri_field')),
        );
        expect(field.controller?.text, equals(validTrojanUri));
        // Error must be cleared on paste
        expect(field.decoration?.errorText, isNull);

        // Tap Save
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_save_button')),
        );
        await tester.pumpAndSettle();

        expect(dataSource.records, hasLength(1));
        expect(dataSource.records.single.sourceUri, equals(validTrojanUri));
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(AddServerScreen), findsNothing);
      },
    );

    testWidgets('credentials in invalid URI are never leaked into error UI', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      const secretToken = 'hunter2_super_secret_token_value';
      const invalidUriWithSecret = 'invalid-scheme://$secretToken@example.com';

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );

      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('add_server_uri_field')),
        invalidUriWithSecret,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_save_button')),
      );
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);

      // Verify no rendered text widget (including SnackBar message) leaks the
      // secret
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data ?? '', isNot(contains(secretToken)));
      }
    });
  });
}
