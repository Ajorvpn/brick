// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/servers/presentation/widgets/server_profile_tile.dart';
import 'package:mobile/features/servers/presentation/widgets/update_servers_disclosure_sheet.dart';
import 'package:ui_theme/ui_theme.dart';

import 'localization_test_harness.dart';

SavedServerProfile _makeServer({
  required String id,
  required String name,
  String server = 'example.com',
  int port = 443,
}) {
  return SavedServerProfile(
    ServerProfile(
      id: id,
      name: name,
      config: VlessOutbound(
        server: server,
        serverPort: port,
        uuid: '11111111-2222-3333-4444-555555555555',
        flow: 'xtls-rprx-vision',
        tls: TlsSettings(enabled: true),
      ),
      addedAt: DateTime.utc(2026, 11, 20),
    ),
  );
}

Map<String, dynamic> _loadTranslations(String lang) {
  var file = File('assets/translations/$lang.json');
  if (!file.existsSync()) {
    file = File('apps/mobile/assets/translations/$lang.json');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Widget _wrapWithMaterialApp({
  required Widget child,
  ThemeMode themeMode = ThemeMode.dark,
}) {
  return Builder(
    builder: (context) => MaterialApp(
      theme: BrickTheme.light(),
      darkTheme: BrickTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  setUpAll(initTestLocalization);

  final testAssetLoader = TestAssetLoader(
    translations: {
      'en': _loadTranslations('en'),
      'fa': _loadTranslations('fa'),
    },
  );

  group('ServerProfileTile', () {
    for (final themeMode in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets(
        '1. ServerProfileTile renders in $themeMode with BrickGlassCard, '
        'selection ring, BrickProtocolPill, and triggers actions '
        'without overflow',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          var selected = false;
          var edited = false;
          var duplicated = false;
          var deleted = false;

          final profile = _makeServer(
            id: 'srv-1',
            name: '🇩🇪 Germany · Frankfurt #1',
            server: 'de1.vpn.net',
          );

          await pumpLocalizedApp(
            tester,
            _wrapWithMaterialApp(
              themeMode: themeMode,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return ServerProfileTile(
                    server: profile,
                    sourceLabel: 'Standalone',
                    isSelected: selected,
                    onSelect: () => setState(() => selected = !selected),
                    onEdit: () => edited = true,
                    onDuplicate: () => duplicated = true,
                    onDelete: () => deleted = true,
                  );
                },
              ),
            ),
            assetLoader: testAssetLoader,
          );

          // Card renders
          expect(
            find.byKey(const ValueKey<String>('server_tile_srv-1')),
            findsOneWidget,
          );
          expect(find.byType(BrickGlassCard), findsOneWidget);
          expect(find.byType(BrickProtocolPill), findsOneWidget);
          expect(find.text('🇩🇪 Germany · Frankfurt #1'), findsOneWidget);
          expect(find.text('de1.vpn.net:443'), findsOneWidget);
          expect(find.text('Standalone'), findsOneWidget);

          // Initially unselected -> no selected dot
          expect(
            find.byKey(const ValueKey<String>('server_selected_srv-1')),
            findsNothing,
          );

          // Tap to select
          await tester.tap(
            find.byKey(const ValueKey<String>('server_tile_srv-1')),
          );
          await tester.pumpAndSettle();
          expect(selected, isTrue);
          expect(
            find.byKey(const ValueKey<String>('server_selected_srv-1')),
            findsOneWidget,
          );

          // Assert 48x48dp touch targets
          final editSize = tester.getSize(
            find.byKey(const ValueKey<String>('server_edit_srv-1')),
          );
          expect(editSize.width, greaterThanOrEqualTo(48.0));
          expect(editSize.height, greaterThanOrEqualTo(48.0));

          final dupSize = tester.getSize(
            find.byKey(const ValueKey<String>('server_duplicate_srv-1')),
          );
          expect(dupSize.width, greaterThanOrEqualTo(48.0));
          expect(dupSize.height, greaterThanOrEqualTo(48.0));

          final deleteSize = tester.getSize(
            find.byKey(const ValueKey<String>('server_delete_srv-1')),
          );
          expect(deleteSize.width, greaterThanOrEqualTo(48.0));
          expect(deleteSize.height, greaterThanOrEqualTo(48.0));

          // Tap Edit
          await tester.tap(
            find.byKey(const ValueKey<String>('server_edit_srv-1')),
          );
          await tester.pump();
          expect(edited, isTrue);

          // Tap Duplicate
          await tester.tap(
            find.byKey(const ValueKey<String>('server_duplicate_srv-1')),
          );
          await tester.pump();
          expect(duplicated, isTrue);

          // Tap Delete
          await tester.tap(
            find.byKey(const ValueKey<String>('server_delete_srv-1')),
          );
          await tester.pump();
          expect(deleted, isTrue);
        },
      );
    }
  });

  group('BrokenServerTile', () {
    testWidgets(
      '2. BrokenServerTile renders error state safely without credential leak '
      'and fires onDelete',
      (tester) async {
        var deleted = false;
        final broken = SavedServerBroken(
          id: 'broken-99',
          reason: 'Config syntax error at line 1',
        );

        await pumpLocalizedApp(
          tester,
          _wrapWithMaterialApp(
            child: BrokenServerTile(
              server: broken,
              onDelete: () => deleted = true,
            ),
          ),
          assetLoader: testAssetLoader,
        );

        expect(
          find.byKey(const ValueKey<String>('server_broken_tile_broken-99')),
          findsOneWidget,
        );
        expect(find.byType(BrickGlassCard), findsOneWidget);
        expect(find.text('Unreadable server'), findsOneWidget);
        expect(find.text('Config syntax error at line 1'), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

        final brokenDeleteSize = tester.getSize(
          find.byKey(const ValueKey<String>('server_delete_broken-99')),
        );
        expect(brokenDeleteSize.width, greaterThanOrEqualTo(48.0));
        expect(brokenDeleteSize.height, greaterThanOrEqualTo(48.0));

        // Tap Delete
        await tester.tap(
          find.byKey(const ValueKey<String>('server_delete_broken-99')),
        );
        await tester.pump();
        expect(deleted, isTrue);
      },
    );
  });

  group('UpdateServersDisclosureSheet', () {
    testWidgets('3. UpdateServersDisclosureSheet.show() returns true on accept '
        'and false on cancel', (tester) async {
      bool? result;

      await pumpLocalizedApp(
        tester,
        _wrapWithMaterialApp(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await UpdateServersDisclosureSheet.show(context);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
        assetLoader: testAssetLoader,
      );

      // Open sheet and tap accept
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('update_servers_disclosure_sheet')),
        findsOneWidget,
      );
      expect(find.text('Sync Server Directory'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('update_servers_disclosure_accept')),
      );
      await tester.pumpAndSettle();
      expect(result, isTrue);

      // Open sheet again and tap cancel
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('update_servers_disclosure_cancel')),
      );
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    for (final themeMode in [ThemeMode.dark, ThemeMode.light]) {
      for (final size in const [Size(360, 640), Size(412, 915)]) {
        testWidgets('4. UpdateServersDisclosureSheet renders cleanly at '
            '${size.width.toInt()}x${size.height.toInt()} in $themeMode', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await pumpLocalizedApp(
            tester,
            _wrapWithMaterialApp(
              themeMode: themeMode,
              child: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => UpdateServersDisclosureSheet.show(context),
                    child: const Text('Open'),
                  );
                },
              ),
            ),
            assetLoader: testAssetLoader,
          );

          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          expect(
            find.byKey(
              const ValueKey<String>('update_servers_disclosure_sheet'),
            ),
            findsOneWidget,
          );
          expect(find.text('Sync Server Directory'), findsOneWidget);
          expect(find.text('Continue & Sync'), findsOneWidget);
          expect(find.text('Not Now'), findsOneWidget);

          // Zero raw localization keys surfaced
          expect(find.text('servers.disclosure_title'), findsNothing);
          expect(find.text('servers.disclosure_body'), findsNothing);
          expect(find.text('servers.disclosure_accept'), findsNothing);
          expect(find.text('servers.disclosure_cancel'), findsNothing);

          // Clean dismiss
          final cancelFinder = find.byKey(
            const ValueKey<String>('update_servers_disclosure_cancel'),
          );
          await tester.ensureVisible(cancelFinder);
          await tester.pumpAndSettle();
          await tester.tap(cancelFinder);
          await tester.pumpAndSettle();
        });
      }
    }

    testWidgets('5. UpdateServersDisclosureSheet layout, WCAG onAccent, '
        'and typography guard', (tester) async {
      await pumpLocalizedApp(
        tester,
        _wrapWithMaterialApp(child: const UpdateServersDisclosureSheet()),
        assetLoader: testAssetLoader,
      );

      // Top widget is Align with alignment == Alignment.bottomCenter
      // and heightFactor == 1.0.
      final alignFinder = find.descendant(
        of: find.byType(UpdateServersDisclosureSheet),
        matching: find.byType(Align),
      );
      expect(alignFinder, findsAtLeastNWidgets(1));
      final align = tester.widget<Align>(alignFinder.first);
      expect(align.alignment, Alignment.bottomCenter);
      expect(align.heightFactor, 1.0);

      // update_servers_disclosure_accept FilledButton resolves foreground
      // color to BrickSemanticColors.dark.onAccent (NOT Colors.white).
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('update_servers_disclosure_accept')),
      );
      final resolvedForeground = button.style?.foregroundColor?.resolve(
        const <WidgetState>{},
      );
      expect(resolvedForeground, BrickSemanticColors.dark.onAccent);
      expect(resolvedForeground, isNot(Colors.white));

      // Zero Text widgets inside UpdateServersDisclosureSheet use
      // fontSize == 13 or fontWeight == FontWeight.w600.
      final textWidgets = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(UpdateServersDisclosureSheet),
          matching: find.byType(Text),
        ),
      );
      expect(textWidgets, isNotEmpty);
      for (final text in textWidgets) {
        expect(
          text.style?.fontSize,
          isNot(13),
          reason: 'Found disallowed fontSize 13 in Text("${text.data}")',
        );
        expect(
          text.style?.fontWeight,
          isNot(FontWeight.w600),
          reason: 'Found disallowed fontWeight w600 in Text("${text.data}")',
        );
      }
    });

    testWidgets(
      '6. en.json <-> fa.json recursive key parity and Locale("fa") render',
      (tester) async {
        Map<String, dynamic> loadMap(String relativePath) {
          var file = File(relativePath);
          if (!file.existsSync()) {
            file = File('apps/mobile/$relativePath');
          }
          final content = file.readAsStringSync();
          expect(
            content.endsWith('\n'),
            isTrue,
            reason: '$relativePath must end with trailing newline',
          );
          return jsonDecode(content) as Map<String, dynamic>;
        }

        Set<String> collectLeafKeys(
          Map<String, dynamic> map, [
          String prefix = '',
        ]) {
          final keys = <String>{};
          for (final entry in map.entries) {
            final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
            if (entry.value is Map<String, dynamic>) {
              keys.addAll(
                collectLeafKeys(entry.value as Map<String, dynamic>, key),
              );
            } else {
              keys.add(key);
              expect(
                entry.value.toString().trim().isNotEmpty,
                isTrue,
                reason: 'Key "$key" value must not be empty',
              );
            }
          }
          return keys;
        }

        final enMap = loadMap('assets/translations/en.json');
        final faMap = loadMap('assets/translations/fa.json');
        final enKeys = collectLeafKeys(enMap);
        final faKeys = collectLeafKeys(faMap);

        expect(faKeys, equals(enKeys));

        await pumpLocalizedApp(
          tester,
          _wrapWithMaterialApp(child: const UpdateServersDisclosureSheet()),
          startLocale: const Locale('fa'),
          assetLoader: testAssetLoader,
        );

        // Verify Persian translations render and zero raw servers.* keys
        // surfaced.
        expect(find.text('همگام‌سازی فهرست سرورها'), findsOneWidget);
        expect(find.text('ادامه و همگام‌سازی'), findsOneWidget);
        expect(find.text('اکنون نه'), findsOneWidget);
        expect(find.textContaining('servers.'), findsNothing);
      },
    );
  });
}
