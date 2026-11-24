// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/add_subscription_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/connection/presentation/screens/qr_scan_screen.dart';
import 'package:mobile/features/logs/presentation/screens/logs_screen.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:mobile/features/settings/presentation/screens/settings_screen.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  File findEnJson() {
    final direct = File('assets/translations/en.json');
    if (direct.existsSync()) return direct;
    final fromRoot = File('apps/mobile/assets/translations/en.json');
    if (fromRoot.existsSync()) return fromRoot;
    return direct;
  }

  File findFaJson() {
    final direct = File('assets/translations/fa.json');
    if (direct.existsSync()) return direct;
    final fromRoot = File('apps/mobile/assets/translations/fa.json');
    if (fromRoot.existsSync()) return fromRoot;
    return direct;
  }

  group('en.json asset', () {
    test('is valid JSON with the expected top-level keys', () {
      final file = findEnJson();
      expect(file.existsSync(), isTrue);

      final parsed = parseTranslationsJson(file.readAsStringSync());
      expect(
        parsed.keys,
        containsAll(<String>['app_title', 'home', 'settings']),
      );
    });

    test('exactly matches the in-memory map used by widget tests', () {
      // Guards against the test harness drifting from the real asset: the
      // harness duplicates this JSON so tests stay hermetic, and this test
      // is what proves the duplicate is still faithful.
      final file = findEnJson();
      final fromAsset = parseTranslationsJson(file.readAsStringSync());
      expect(fromAsset, equals(testEnglishTranslations()));
    });
  });

  group('.tr() lookup in widgets', () {
    testWidgets('HomeScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const HomeScreen()),
        overrides: repositoryOverride(),
      );

      // HomeScreen renders the brand-bar title, the guided empty state and the
      // orb hints; it does NOT render `home.label` ('Home') anywhere.
      expect(find.text('Brick VPN'), findsOneWidget);
      expect(find.text('No saved servers yet'), findsOneWidget);
      expect(find.text('Browse Servers'), findsOneWidget);
      expect(find.text('Choose server'), findsOneWidget);
      expect(
        find.text(
          'Pick a location from the Servers tab to start a secure '
          'tunnel.',
        ),
        findsOneWidget,
      );
      // The raw lookup key must never be displayed to a user.
      expect(find.text('connection.add_server'), findsNothing);
      expect(find.text('connection.add_subscription'), findsNothing);
      expect(find.text('home.title'), findsNothing);
      expect(find.text('home.browse_servers'), findsNothing);
      expect(find.text('home.choose_server_subtitle'), findsNothing);
      expect(find.text('home.select_server_hint'), findsNothing);
    });

    testWidgets('ServersScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const ServersScreen()),
        overrides: repositoryOverride(),
      );

      expect(find.byType(ServersScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('servers_update_button')),
        findsOneWidget,
      );
      expect(find.text('Servers'), findsOneWidget);
      // Header pill + empty-state CTA both render the same localized label
      expect(find.text('Update Servers'), findsNWidgets(2));
      expect(find.text('No servers added yet'), findsOneWidget);
      expect(find.text('servers.title'), findsNothing);
      expect(find.text('servers.update_servers'), findsNothing);
      expect(find.text('servers.empty_title'), findsNothing);
      expect(find.text('servers.empty_subtitle'), findsNothing);
    });

    testWidgets('LogsScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const LogsScreen()),
      );

      expect(find.widgetWithText(AppBar, 'Logs'), findsOneWidget);
      expect(find.text('logs.title'), findsNothing);
      expect(find.text('No log entries yet'), findsOneWidget);
      expect(find.text('settings.no_logs'), findsNothing);
    });

    testWidgets('SettingsScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const SettingsScreen()),
      );

      expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
      expect(find.text('Back to Home'), findsOneWidget);
      expect(find.text('settings.back_to_home'), findsNothing);
    });

    testWidgets('AddServerScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const AddServerScreen()),
        overrides: repositoryOverride(),
      );

      expect(find.widgetWithText(AppBar, 'Add Server'), findsOneWidget);
      expect(find.text('Server URI'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
      expect(find.text('add_server.title'), findsNothing);
      expect(find.text('add_server.uri_label'), findsNothing);
      expect(find.text('add_server.save'), findsNothing);
      expect(find.text('add_server.scan_qr'), findsNothing);
    });

    testWidgets('QrScanScreen renders translated strings in granted state', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(
          home: QrScanScreen(
            scannerBuilder: (context, onDetect) => const SizedBox(),
          ),
        ),
        overrides: repositoryOverride(),
      );

      expect(find.widgetWithText(AppBar, 'Scan QR Code'), findsOneWidget);
      expect(
        find.text('Point your camera at a server QR code'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('qr_scan.title'), findsNothing);
      expect(find.text('qr_scan.instruction'), findsNothing);
      expect(find.text('qr_scan.cancel'), findsNothing);
    });

    testWidgets('QrScanScreen renders translated strings in denied state', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(
          home: QrScanScreen(
            scannerBuilder: (context, onDetect) => const SizedBox(),
          ),
        ),
        overrides: repositoryOverride(
          null,
          const FakeCameraPermissionService(
            status: CameraPermissionStatus.denied,
          ),
        ),
      );

      expect(
        find.text('Camera permission is required to scan QR codes.'),
        findsOneWidget,
      );
      expect(find.text('Grant Permission'), findsOneWidget);
      expect(find.text('qr_scan.permission_denied'), findsNothing);
      expect(find.text('qr_scan.request_permission'), findsNothing);
    });

    testWidgets(
      'QrScanScreen renders translated strings in permanentlyDenied state',
      (tester) async {
        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(
            home: QrScanScreen(
              scannerBuilder: (context, onDetect) => const SizedBox(),
            ),
          ),
          overrides: repositoryOverride(
            null,
            const FakeCameraPermissionService(
              status: CameraPermissionStatus.permanentlyDenied,
            ),
          ),
        );

        expect(
          find.text(
            'Camera permission is permanently denied. Please enable it in '
            'system settings.',
          ),
          findsOneWidget,
        );
        expect(find.text('Open Settings'), findsOneWidget);
        expect(
          find.text('qr_scan.permission_permanently_denied'),
          findsNothing,
        );
        expect(find.text('qr_scan.open_settings'), findsNothing);
      },
    );

    testWidgets('AddSubscriptionScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const AddSubscriptionScreen()),
        overrides: repositoryOverride(),
      );

      expect(find.widgetWithText(AppBar, 'Add Subscription'), findsOneWidget);
      expect(find.text('Subscription URL'), findsOneWidget);
      expect(find.text('Subscription Name (optional)'), findsOneWidget);
      expect(find.text('Import Subscription'), findsOneWidget);
      expect(find.text('add_subscription.title'), findsNothing);
      expect(find.text('add_subscription.import_button'), findsNothing);
    });

    testWidgets("a different locale (fa) resolves to that locale's value", (
      tester,
    ) async {
      // Proves `.tr()` performs a real lookup rather than returning the key:
      // the loader serves the shipped Persian bundle for a different code.
      final loader = TestAssetLoader(
        translations: {
          'en': testEnglishTranslations(),
          'fa': parseTranslationsJson(findFaJson().readAsStringSync()),
        },
      );

      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const HomeScreen()),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('fa'),
      );

      expect(find.text('Brick VPN'), findsOneWidget);
      expect(find.text('هنوز سروری ذخیره نشده است'), findsOneWidget);
      expect(find.text('مرور سرورها'), findsOneWidget);
      expect(find.text('انتخاب سرور'), findsOneWidget);
      // `home.label` is translated but HomeScreen never renders it, so the
      // Persian value must be absent — this pins the assertion to the keys the
      // screen actually uses.
      expect(find.text('خانه'), findsNothing);
      // The raw lookup key must never surface in another locale either.
      expect(find.text('home.title'), findsNothing);
      expect(find.text('home.browse_servers'), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(HomeScreen))),
        TextDirection.rtl,
        reason: 'Persian must render right-to-left',
      );

      // AddServerScreen renders Persian chrome plus an LTR URI island.
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const AddServerScreen()),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('fa'),
      );

      expect(find.widgetWithText(AppBar, 'افزودن سرور'), findsOneWidget);
      expect(find.text('URI سرور'), findsOneWidget);
      expect(find.text('ذخیره'), findsOneWidget);
      expect(find.text('اسکن کد QR'), findsOneWidget);
      expect(find.text('Add Server'), findsNothing);
      expect(find.text('add_server.title'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('add_server_uri_field')),
            )
            .textDirection,
        TextDirection.ltr,
        reason: 'A server URI must stay LTR inside an RTL UI',
      );

      // QrScanScreen also renders Persian via .tr().
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(
          home: QrScanScreen(
            scannerBuilder: (context, onDetect) => const SizedBox(),
          ),
        ),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('fa'),
      );

      expect(find.widgetWithText(AppBar, 'اسکن کد QR'), findsOneWidget);
      expect(find.text('دوربین را به سمت کد QR سرور بگیرید'), findsOneWidget);
      expect(find.text('لغو'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsNothing);
      expect(find.text('qr_scan.title'), findsNothing);

      // AddSubscriptionScreen renders Persian and keeps its URL field LTR.
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const AddSubscriptionScreen()),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('fa'),
      );

      expect(find.widgetWithText(AppBar, 'افزودن اشتراک'), findsOneWidget);
      expect(find.text('نشانی اشتراک'), findsOneWidget);
      expect(find.text('نام اشتراک (اختیاری)'), findsOneWidget);
      expect(find.text('وارد کردن اشتراک'), findsOneWidget);
      expect(find.text('Add Subscription'), findsNothing);
      expect(find.text('add_subscription.title'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('add_subscription_url_field')),
            )
            .textDirection,
        TextDirection.ltr,
        reason: 'A subscription URL must stay LTR inside an RTL UI',
      );

      // ServersScreen also renders Persian via .tr().
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const ServersScreen()),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('fa'),
      );

      expect(find.byType(ServersScreen), findsOneWidget);
      // ServersScreen renders its title in a custom header, not an AppBar.
      expect(find.text('سرورها'), findsOneWidget);
      expect(find.text('هنوز سروری اضافه نشده است'), findsOneWidget);
      expect(find.text('به‌روزرسانی سرورها'), findsNWidgets(2));
      expect(find.text('Servers'), findsNothing);
      expect(find.text('servers.title'), findsNothing);
      expect(find.text('servers.empty_title'), findsNothing);
    });
  });
}
