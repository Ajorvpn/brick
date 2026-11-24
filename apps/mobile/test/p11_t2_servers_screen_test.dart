// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/presentation/providers/camera_permission_provider.dart';
import 'package:mobile/features/servers/presentation/providers/built_in_directory_sync_provider.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

const String _uuid = '11111111-2222-3333-4444-555555555555';

Map<String, dynamic> _loadTranslations(String lang) {
  var file = File('assets/translations/$lang.json');
  if (!file.existsSync()) {
    file = File('apps/mobile/assets/translations/$lang.json');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

final TestAssetLoader _assetLoader = TestAssetLoader(
  translations: {'en': _loadTranslations('en'), 'fa': _loadTranslations('fa')},
);

String _vlessUri({required String host, required String remark}) {
  return 'vless://$_uuid@$host:443?security=none#'
      '${Uri.encodeComponent(remark)}';
}

void _seedServer(
  FakeServerProfileDataSource dataSource, {
  required String id,
  required String remark,
  String host = 'example.com',
}) {
  dataSource.records.add(
    SavedServerRecord(
      id: id,
      sourceUri: _vlessUri(host: host, remark: remark),
      addedAt: DateTime.utc(2026, 11, 21),
    ),
  );
}

Widget _app(Widget child, ThemeMode themeMode) {
  return Builder(
    builder: (context) => MaterialApp(
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: child,
    ),
  );
}

Future<void> _pumpServersScreen(
  WidgetTester tester, {
  required FakeVpnEngine engine,
  required FakeServerProfileDataSource dataSource,
  ThemeMode themeMode = ThemeMode.dark,
}) async {
  final connectivity = FakeConnectivitySource();
  addTearDown(connectivity.dispose);

  await pumpLocalizedApp(
    tester,
    _app(const ServersScreen(), themeMode),
    assetLoader: _assetLoader,
    overrides: <Object>[
      vpnEngineProvider.overrideWithValue(engine),
      serverProfileRepositoryProvider.overrideWith(
        (ref) async => FakeServerProfileRepository(dataSource),
      ),
      cameraPermissionServiceProvider.overrideWithValue(
        const FakeCameraPermissionService(),
      ),
      connectivitySourceProvider.overrideWithValue(connectivity),
      // Hermetic: the directory sync never reaches the network in tests.
      builtInFeedFetcherProvider.overrideWithValue(offlineDirectoryFetcher),
    ],
  );
}

void _setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

FakeServerProfileDataSource _seedHierarchy() {
  final dataSource = FakeServerProfileDataSource();
  _seedServer(
    dataSource,
    id: 'de-frankfurt',
    remark: '🇩🇪 Germany · Frankfurt',
    host: 'frankfurt.example.com',
  );
  _seedServer(
    dataSource,
    id: 'de-berlin',
    remark: '🇩🇪 Germany · Berlin',
    host: 'berlin.example.com',
  );
  _seedServer(
    dataSource,
    id: 'de-country',
    remark: '🇩🇪 Germany',
    host: 'germany.example.com',
  );
  _seedServer(
    dataSource,
    id: 'us-ny',
    remark: '🇺🇸 United States · New York',
    host: 'ny.example.com',
  );
  _seedServer(
    dataSource,
    id: 'zz-node',
    remark: 'Mystery Node',
    host: 'mystery.example.com',
  );
  return dataSource;
}

void main() {
  setUpAll(initTestLocalization);

  testWidgets(
    '1. Empty state is play-compliant: no manual add actions, and Update '
    'Servers opens the disclosure sheet then shows the localized notice',
    (tester) async {
      _setSurface(tester, const Size(412, 915));
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);
      final dataSource = FakeServerProfileDataSource();

      await _pumpServersScreen(tester, engine: engine, dataSource: dataSource);

      expect(
        find.byKey(const ValueKey<String>('servers_empty_state')),
        findsOneWidget,
      );
      expect(find.text('No servers added yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('servers_empty_update_button')),
        findsOneWidget,
      );

      // Manual add affordances are intentionally absent on this screen.
      expect(
        find.byKey(const ValueKey<String>('servers_add_server_action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('servers_add_subscription_action')),
        findsNothing,
      );
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

      // No subscription feed exists -> Play-compliant disclosure sheet.
      await tester.tap(
        find.byKey(const ValueKey<String>('servers_update_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('update_servers_disclosure_sheet')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('update_servers_disclosure_accept')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('update_servers_disclosure_sheet')),
        findsNothing,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text(
          "Couldn't reach the server directory. Check your connection and "
          'try again.',
        ),
        findsWidgets,
      );
      expect(find.textContaining('servers.sync_'), findsNothing);
    },
  );

  testWidgets(
    '2. Hierarchical Country -> City/State -> Servers accordion with active '
    'spotlight, collapse/expand, and selection changes',
    (tester) async {
      _setSurface(tester, const Size(412, 1800));
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);
      final dataSource = _seedHierarchy();

      await _pumpServersScreen(tester, engine: engine, dataSource: dataSource);

      // Country accordion cards (small list -> all expanded by default).
      expect(
        find.byKey(const ValueKey<String>('country_group_DE')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_US')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_ZZ')),
        findsOneWidget,
      );

      // City / state sub-headers.
      expect(find.text('FRANKFURT'), findsOneWidget);
      expect(find.text('BERLIN'), findsOneWidget);
      expect(find.text('NEW YORK'), findsOneWidget);

      // Country-only servers have no fake 'Standard' sub-header.
      expect(find.text('STANDARD'), findsNothing);

      // 'Other Locations' label for ZZ.
      expect(find.text('Other Locations'), findsOneWidget);

      // Active spotlight for the auto-selected first server.
      expect(
        find.byKey(const ValueKey<String>('servers_active_spotlight')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('server_selected_de-frankfurt')),
        findsOneWidget,
      );

      // Collapse Germany -> its child tiles disappear.
      await tester.tap(find.byKey(const ValueKey<String>('country_header_DE')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('server_tile_de-berlin')),
        findsNothing,
      );

      // Expand Germany again -> child tiles come back.
      await tester.tap(find.byKey(const ValueKey<String>('country_header_DE')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('server_tile_de-berlin')),
        findsOneWidget,
      );

      // Selecting a different server moves the selection ring.
      await tester.tap(find.byKey(const ValueKey<String>('server_tile_us-ny')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('server_selected_us-ny')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('server_selected_de-frankfurt')),
        findsNothing,
      );
    },
  );

  testWidgets(
    '3. Instant search filters to matching country/city, shows no-match '
    'recovery state, and clear search restores the full list',
    (tester) async {
      _setSurface(tester, const Size(412, 1800));
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);
      final dataSource = _seedHierarchy();

      await _pumpServersScreen(tester, engine: engine, dataSource: dataSource);

      await tester.enterText(
        find.byKey(const ValueKey<String>('servers_search_field')),
        'Frankfurt',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('country_group_DE')),
        findsOneWidget,
      );
      expect(find.text('FRANKFURT'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('country_group_US')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_ZZ')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('servers_search_field')),
        'no_such_place_xyz',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('servers_no_matches_state')),
        findsOneWidget,
      );
      expect(find.text('No matching servers'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('servers_clear_search_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('servers_no_matches_state')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_DE')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_US')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_ZZ')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '4. Broken server recovery renders alongside valid countries, Update '
    'Servers meets 48dp, and typography stays 4-size/3-weight compliant',
    (tester) async {
      _setSurface(tester, const Size(412, 1800));
      final engine = FakeVpnEngine();
      addTearDown(engine.dispose);
      final dataSource = _seedHierarchy();
      dataSource.records.add(
        SavedServerRecord(
          id: 'broken-1',
          sourceUri: 'unsupported-proto://secret_user:secret_pass@host:1234',
          addedAt: DateTime.utc(2026, 11, 21),
        ),
      );

      await _pumpServersScreen(tester, engine: engine, dataSource: dataSource);

      expect(
        find.byKey(const ValueKey<String>('server_broken_tile_broken-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('server_delete_broken-1')),
        findsOneWidget,
      );
      expect(find.textContaining('secret_user'), findsNothing);
      expect(find.textContaining('secret_pass'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('country_group_DE')),
        findsOneWidget,
      );

      final updateButtonSize = tester.getSize(
        find.byKey(const ValueKey<String>('servers_update_button')),
      );
      expect(updateButtonSize.height, greaterThanOrEqualTo(48.0));

      final textWidgets = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(ServersScreen),
          matching: find.byType(Text),
        ),
      );
      expect(textWidgets, isNotEmpty);
      for (final text in textWidgets) {
        expect(
          text.style?.fontWeight,
          isNot(FontWeight.w600),
          reason: 'Disallowed FontWeight.w600 in Text("${text.data}")',
        );
        expect(
          text.style?.fontSize,
          isNot(13),
          reason: 'Disallowed fontSize 13 in Text("${text.data}")',
        );
      }
    },
  );

  testWidgets(
    '5. Responsive dark & light rendering at 360x640 and 412x915 with zero '
    'overflow and zero missing servers.* keys',
    (tester) async {
      for (final size in const <Size>[Size(360, 640), Size(412, 915)]) {
        for (final themeMode in const <ThemeMode>[
          ThemeMode.dark,
          ThemeMode.light,
        ]) {
          _setSurface(tester, size);
          final engine = FakeVpnEngine();
          addTearDown(engine.dispose);
          final dataSource = _seedHierarchy();

          await _pumpServersScreen(
            tester,
            engine: engine,
            dataSource: dataSource,
            themeMode: themeMode,
          );

          expect(
            tester.takeException(),
            isNull,
            reason:
                'Render exception at ${size.width.toInt()}x'
                '${size.height.toInt()} in $themeMode',
          );
          expect(
            find.byKey(const ValueKey<String>('servers_active_spotlight')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('country_group_DE')),
            findsOneWidget,
          );
          expect(find.textContaining('servers.'), findsNothing);
        }
      }
    },
  );
}
