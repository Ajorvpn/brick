// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Initializes easy_localization's device-locale storage for a test file.
///
/// `EasyLocalization` reads a persisted locale during `initState`. Without
/// this the controller throws
/// `LateInitializationError: Field '_deviceLocale' has not been
/// initialized.` Call from a `setUpAll` in any test that pumps an
/// `EasyLocalization` widget; it is the test-side equivalent of
/// `await EasyLocalization.ensureInitialized()` in `main()`.
Future<void> initTestLocalization() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `ensureInitialized()` reads the persisted locale through
  // `shared_preferences`, whose platform channel has no implementation in
  // `flutter test`; without this mock it throws
  // `MissingPluginException(No implementation found for method getAll ...)`.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await EasyLocalization.ensureInitialized();
}

/// In-memory [AssetLoader] backed by literal maps.
///
/// The production loader reads `assets/translations/*.json` through
/// `rootBundle`, which is not populated inside `flutter test`. Using an
/// in-memory loader keeps widget tests hermetic (no filesystem, no asset
/// bundle) while still exercising the real `.tr()` lookup path.
///
/// The English map below is a deliberate, minimal duplicate of
/// `assets/translations/en.json`. A dedicated test asserts the two agree,
/// so this cannot silently drift from the real asset.
class TestAssetLoader extends AssetLoader {
  TestAssetLoader({Map<String, Map<String, dynamic>>? translations})
    : _translations =
          translations ??
          const {
            'en': {
              'app_title': 'Brick VPN',
              'home': {
                'title': 'Brick VPN',
                'label': 'Home',
                'go_to_settings': 'Go to Settings',
              },
              'settings': {
                'title': 'Settings',
                'label': 'Settings',
                'back_to_home': 'Back to Home',
              },
            },
          };

  final Map<String, Map<String, dynamic>> _translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final key = locale.languageCode;
    final data = _translations[key];
    if (data == null) {
      throw FlutterError('No test translations for locale "$key".');
    }
    return data;
  }
}

/// The translations that [TestAssetLoader] serves, for drift assertions.
Map<String, dynamic> testEnglishTranslations() => const {
  'app_title': 'Brick VPN',
  'home': {
    'title': 'Brick VPN',
    'label': 'Home',
    'go_to_settings': 'Go to Settings',
  },
  'settings': {
    'title': 'Settings',
    'label': 'Settings',
    'back_to_home': 'Back to Home',
  },
};

/// Parses the given JSON string into the nested map shape that
/// easy_localization expects.
Map<String, dynamic> parseTranslationsJson(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

/// Wraps the given child widget in the same localization + provider stack
/// that the app's entrypoint builds, so widget tests exercise the real
/// `.tr()` lookup path.
///
/// Mirrors the real entrypoint exactly: EasyLocalization ABOVE ProviderScope.
/// A bare [MaterialApp] that registers easy_localization's delegates.
///
/// Mirrors `MyApp`'s `MaterialApp.router` wiring. Screens pumped through
/// this must still register the delegates, exactly as the real app does.
Widget localizedMaterialApp({Widget? home}) {
  return Builder(
    builder: (context) => MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      home: home,
    ),
  );
}

Widget localizedApp({required Widget child, AssetLoader? assetLoader}) {
  return EasyLocalization(
    supportedLocales: const <Locale>[Locale('en')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    saveLocale: false,
    assetLoader: assetLoader ?? TestAssetLoader(),
    child: ProviderScope(child: child),
  );
}

/// Pumps [app] inside [localizedApp] and settles the localization load.
Future<void> pumpLocalizedApp(
  WidgetTester tester,
  Widget app, {
  AssetLoader? assetLoader,
}) async {
  await tester.pumpWidget(localizedApp(child: app, assetLoader: assetLoader));

  // `EasyLocalization` resolves translations through an async asset load
  // that starts only when the localization delegate first loads. A single
  // `pumpAndSettle` is NOT enough: it can complete before the loader's
  // Future resolves, leaving `.tr()` to fall back to returning the raw key
  // (logged by easy_localization as "Localization key [...] not found").
  // Yield to the real event loop, then pump frames until the text settles.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}
