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

      expect(find.text('Brick VPN'), findsOneWidget);
      // HomeScreen renders the AppBar title and the empty-state message. It
      // does NOT render `home.label` ('Home') anywhere, so asserting on that
      // string would only ever pass by coincidence.
      expect(find.text('No saved servers yet'), findsOneWidget);
      expect(find.text('Add Server'), findsOneWidget);
      expect(find.text('Add Subscription'), findsOneWidget);
      // The raw lookup key must never be displayed to a user.
      expect(find.text('connection.add_server'), findsNothing);
      expect(find.text('connection.add_subscription'), findsNothing);
      expect(find.text('home.title'), findsNothing);
    });

    testWidgets('ServersScreen renders translated strings, not keys', (
      tester,
    ) async {
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const ServersScreen()),
        overrides: repositoryOverride(),
      );

      expect(find.widgetWithText(AppBar, 'Servers'), findsOneWidget);
      expect(find.text('No servers added yet'), findsOneWidget);
      expect(find.text('Add Server'), findsOneWidget);
      expect(find.text('Add Subscription'), findsOneWidget);
      expect(find.text('servers.title'), findsNothing);
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

      expect(find.widgetWithText(AppBar, 'Live Logs'), findsOneWidget);
      expect(find.text('settings.live_logs'), findsNothing);
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

    testWidgets("a different locale resolves to that locale's value", (
      tester,
    ) async {
      // Proves `.tr()` performs a real lookup rather than returning the key:
      // the loader serves different text for a different language code.
      final loader = TestAssetLoader(
        translations: {
          'en': testEnglishTranslations(),
          'de': {
            'app_title': 'Ziegel VPN',
            'home': {'title': 'Ziegel VPN', 'label': 'Startseite'},
            'servers': {
              'title': 'Server',
              'placeholder': 'Serverliste wird hier angezeigt',
              'empty_title': 'Noch keine Server hinzugefügt',
              'empty_subtitle':
                  'Fügen Sie einen Server-Link hinzu, scannen Sie einen '
                  'QR-Code oder importieren Sie ein Abonnement, um zu '
                  'beginnen.',
              'standalone_section': 'Eigenständige Server',
              'subscription_section': 'Abonnement-Server',
              'standalone_badge': 'Eigenständig',
              'subscription_badge': 'Abonnement',
            },
            'settings': {
              'title': 'Einstellungen',
              'label': 'Einstellungen',
              'back_to_home': 'Zurück zur Startseite',
            },
            'connection': {
              'add_server': 'Server hinzufügen',
              'add_subscription': 'Abonnement hinzufügen',
              'no_servers': 'Noch keine Server gespeichert',
              'state_disconnected': 'Getrennt',
              'traffic_none': 'Keine Verkehrsdaten',
            },
            'add_server': {
              'title': 'Server hinzufügen',
              'uri_label': 'Server-URI',
              'paste_hint': 'Server-Link einfügen',
              'paste_from_clipboard': 'Aus Zwischenablage einfügen',
              'save': 'Speichern',
              'scan_qr': 'QR-Code scannen',
              'error_is_subscription':
                  'Dies ist eine Abonnement-URL. Bitte verwenden Sie den '
                  'Ablauf Abonnement hinzufügen.',
              'uri_required': 'Geben Sie zuerst eine Server-URI ein',
            },
            'qr_scan': {
              'title': 'QR-Code scannen',
              'instruction': 'Richten Sie die Kamera auf einen Server-QR-Code',
              'cancel': 'Abbrechen',
              'permission_denied':
                  'Kameraberechtigung ist zum Scannen von QR-Codes '
                  'erforderlich.',
              'permission_permanently_denied':
                  'Kameraberechtigung ist dauerhaft verweigert. Bitte in den '
                  'Systemeinstellungen aktivieren.',
              'request_permission': 'Berechtigung erteilen',
              'open_settings': 'Einstellungen öffnen',
            },
            'add_subscription': {
              'title': 'Abonnement hinzufügen',
              'url_label': 'Abonnement-URL',
              'url_hint': 'https://example.com/subscription',
              'name_label': 'Abonnementname (optional)',
              'name_hint': 'Mein Abonnement',
              'import_button': 'Abonnement importieren',
              'url_required': 'Geben Sie zuerst eine Abonnement-URL ein',
              'success_message': '{count} Server erfolgreich importiert',
              'partial_success_message':
                  '{count} Server importiert '
                  '({skipped} ungültige Einträge übersprungen)',
              'no_valid_servers':
                  'Keine gültigen Serverkonfigurationen im Abonnement '
                  'gefunden',
              'invalid_url':
                  'Bitte geben Sie eine gültige HTTPS-Abonnement-URL ein',
              'paste_from_clipboard': 'Aus Zwischenablage einfügen',
              'storage_error':
                  'Abonnement konnte nicht lokal gespeichert werden',
            },
          },
        },
      );

      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const HomeScreen()),
        assetLoader: loader,
        // HomeScreen is a ConsumerWidget: without a ProviderScope (and a
        // repository override) it throws while building, so the whole test
        // fails on a StateError rather than on a translation mismatch.
        overrides: repositoryOverride(),
        startLocale: const Locale('de'),
      );

      expect(find.text('Ziegel VPN'), findsOneWidget);
      expect(find.text('Server hinzufügen'), findsOneWidget);
      expect(find.text('Abonnement hinzufügen'), findsOneWidget);
      // `home.label` is translated but HomeScreen never renders it, so the
      // German value must be absent — this pins the assertion to the keys the
      // screen actually uses.
      expect(find.text('Startseite'), findsNothing);
      // The raw lookup key must never surface in another locale either.
      expect(find.text('home.title'), findsNothing);

      // Verify AddServerScreen also renders German translations via .tr().
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const AddServerScreen()),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('de'),
      );

      expect(find.widgetWithText(AppBar, 'Server hinzufügen'), findsOneWidget);
      expect(find.text('Server-URI'), findsOneWidget);
      expect(find.text('Speichern'), findsOneWidget);
      expect(find.text('QR-Code scannen'), findsOneWidget);
      expect(find.text('Add Server'), findsNothing);
      expect(find.text('add_server.title'), findsNothing);

      // Verify QrScanScreen also renders German translations via .tr().
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(
          home: QrScanScreen(
            scannerBuilder: (context, onDetect) => const SizedBox(),
          ),
        ),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('de'),
      );

      expect(find.widgetWithText(AppBar, 'QR-Code scannen'), findsOneWidget);
      expect(
        find.text('Richten Sie die Kamera auf einen Server-QR-Code'),
        findsOneWidget,
      );
      expect(find.text('Abbrechen'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsNothing);
      expect(find.text('qr_scan.title'), findsNothing);

      // Verify AddSubscriptionScreen also renders German translations
      // via .tr().
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const AddSubscriptionScreen()),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('de'),
      );

      expect(
        find.widgetWithText(AppBar, 'Abonnement hinzufügen'),
        findsOneWidget,
      );
      expect(find.text('Abonnement-URL'), findsOneWidget);
      expect(find.text('Abonnementname (optional)'), findsOneWidget);
      expect(find.text('Abonnement importieren'), findsOneWidget);
      expect(find.text('Add Subscription'), findsNothing);
      expect(find.text('add_subscription.title'), findsNothing);

      // Verify ServersScreen also renders German translations via .tr().
      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const ServersScreen()),
        assetLoader: loader,
        overrides: repositoryOverride(),
        startLocale: const Locale('de'),
      );

      expect(find.widgetWithText(AppBar, 'Server'), findsOneWidget);
      expect(find.text('Noch keine Server hinzugefügt'), findsOneWidget);
      expect(find.text('Server hinzufügen'), findsOneWidget);
      expect(find.text('Abonnement hinzufügen'), findsOneWidget);
      expect(find.text('Servers'), findsNothing);
      expect(find.text('servers.title'), findsNothing);
      expect(find.text('servers.empty_title'), findsNothing);
    });
  });
}
