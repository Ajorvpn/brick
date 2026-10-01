// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:core_domain/core_domain.dart'
    show ConnectionState, Disconnected, ServerProfile, TrafficStats;
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:easy_localization/easy_localization.dart';
// Flutter's own `ConnectionState` (from `package:flutter/src/widgets/async.dart`)
// collides by name with `core_domain`'s; hide Flutter's so the domain type is
// unambiguous throughout this harness.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/data/datasources/server_profile_local_data_source.dart';
import 'package:mobile/features/connection/data/repositories/local_server_profile_repository.dart';
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
              'connection': {
                'add_server': 'Add Server',
                'parse': 'Parse',
                'save': 'Save',
                'uri_label': 'Server URI',
                'uri_required': 'Enter a server URI first',
                'no_servers': 'No saved servers yet',
                'load_failed': 'Could not load saved servers',
                'connect': 'Connect',
                'disconnect': 'Disconnect',
                'remove': 'Remove',
                'broken_title': 'Unreadable server',
                'state_disconnected': 'Disconnected',
                'state_connecting': 'Connecting',
                'state_connected': 'Connected',
                'state_disconnecting': 'Disconnecting',
                'state_error': 'Connection error',
                'traffic': '{tx} up / {rx} down',
                'traffic_none': 'No traffic data',
                'traffic_unavailable': 'Traffic data unavailable',
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

/// A controllable [VpnEngine] fake for widget tests.
///
/// Deliberately **not** `MockVpnEngine`: that class simulates transitions on
/// internal timers, so a test would have to sleep for real time to observe
/// `Connecting`/`Connected`. This fake lets a test push an exact state
/// synchronously, so every assertion is deterministic and no test depends on
/// wall-clock timing.
///
/// It also records every `start`/`stop` call, which is how the "exactly once
/// per tap" acceptance criterion is verified.
class FakeVpnEngine implements VpnEngine {
  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();
  final StreamController<TrafficStats> _statsController =
      StreamController<TrafficStats>.broadcast();

  /// Every profile passed to [start], in call order.
  final List<ServerProfile> startCalls = <ServerProfile>[];

  /// How many times [stop] was called.
  int stopCalls = 0;

  /// The last state pushed via [emit].
  ConnectionState lastState = const Disconnected();

  @override
  Stream<ConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<TrafficStats> get trafficStats => _statsController.stream;

  /// Pushes [state] to every listener of [connectionState].
  void emit(ConnectionState state) {
    lastState = state;
    _stateController.add(state);
  }

  /// Pushes a traffic snapshot to every listener of [trafficStats].
  void emitStats(TrafficStats stats) => _statsController.add(stats);

  /// Pushes an error to [trafficStats] only, leaving [connectionState]
  /// untouched — the Invariant 2 "independent failure domains" contract.
  void emitStatsError(Object error) => _statsController.addError(error);

  @override
  Future<VpnCommandResult> start(ServerProfile profile) async {
    startCalls.add(profile);
    // Always "accepted": this fake is here to prove the UI does NOT treat
    // acceptance as connection, so it must hand back the accepting result
    // while emitting no transition at all.
    return const VpnCommandAccepted();
  }

  @override
  Future<VpnCommandResult> stop() async {
    stopCalls++;
    return const VpnCommandAccepted();
  }

  @override
  Future<ConnectionState> getStatus() async => lastState;

  /// Releases both controllers.
  Future<void> dispose() async {
    await _stateController.close();
    await _statsController.close();
  }
}

/// A valid VLESS URI. The UUID and host are fake; only the shape matters.
const String validVlessUri =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443#My%20Server';

/// A valid Shadowsocks URI (userinfo form).
const String validShadowsocksUri =
    'ss://YWVzLTI1Ni1nY206c2VjcmV0cHc=@example.com:8388#SS%20Node';

/// A valid Trojan URI.
const String validTrojanUri =
    'trojan://mypassword@example.com:443#Trojan%20Node';

/// An in-memory [ServerProfileLocalDataSource] for tests.
///
/// Used instead of `SharedPreferences` so persistence behaviour is asserted
/// without a platform channel, and so a "restart" can be simulated by
/// building a second repository over the same backing list.
class FakeServerProfileDataSource implements ServerProfileLocalDataSource {
  /// Creates a data source seeded with [initial].
  FakeServerProfileDataSource([List<SavedServerRecord>? initial])
    : records = <SavedServerRecord>[...?initial];

  /// The records currently held. Survives a "restart" by being shared.
  final List<SavedServerRecord> records;

  @override
  List<SavedServerRecord> readAll() => List<SavedServerRecord>.of(records);

  @override
  Future<void> writeAll(List<SavedServerRecord> next) async {
    records
      ..clear()
      ..addAll(next);
  }
}

/// Builds a [LocalServerProfileRepository] over [dataSource].
LocalServerProfileRepository buildRepository(
  ServerProfileLocalDataSource dataSource,
) => LocalServerProfileRepository(dataSource);

/// Riverpod overrides that resolve the saved-server list from [dataSource].
///
/// Returns `List<Object>` (not `List<Override>`) because the harness cannot
/// name `Override` — see [localizedApp].
List<Object> repositoryOverride([ServerProfileLocalDataSource? dataSource]) => [
  serverProfileRepositoryProvider.overrideWith(
    (ref) async => buildRepository(dataSource ?? FakeServerProfileDataSource()),
  ),
];

/// Pumps [app] with a `ProviderScope` that overrides the engine and the
/// profile repository, plus the real localization stack.
Future<void> pumpConnectionApp(
  WidgetTester tester,
  Widget app, {
  required FakeVpnEngine engine,
  ServerProfileLocalDataSource? dataSource,
}) async {
  await tester.pumpWidget(
    localizedApp(
      overrides: [
        vpnEngineProvider.overrideWithValue(engine),
        serverProfileRepositoryProvider.overrideWith(
          (ref) async =>
              buildRepository(dataSource ?? FakeServerProfileDataSource()),
        ),
      ],
      child: app,
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

/// Pumps [app] with the same overrides but no router, for widget-level tests.
Future<void> pumpConnectionMaterialApp(
  WidgetTester tester,
  Widget app, {
  required FakeVpnEngine engine,
  ServerProfileLocalDataSource? dataSource,
}) async {
  await pumpConnectionApp(
    tester,
    localizedMaterialApp(home: app),
    engine: engine,
    dataSource: dataSource,
  );
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
  'connection': {
    'add_server': 'Add Server',
    'parse': 'Parse',
    'save': 'Save',
    'uri_label': 'Server URI',
    'uri_required': 'Enter a server URI first',
    'no_servers': 'No saved servers yet',
    'load_failed': 'Could not load saved servers',
    'connect': 'Connect',
    'disconnect': 'Disconnect',
    'remove': 'Remove',
    'broken_title': 'Unreadable server',
    'state_disconnected': 'Disconnected',
    'state_connecting': 'Connecting',
    'state_connected': 'Connected',
    'state_disconnecting': 'Disconnecting',
    'state_error': 'Connection error',
    'traffic': '{tx} up / {rx} down',
    'traffic_none': 'No traffic data',
    'traffic_unavailable': 'Traffic data unavailable',
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

/// Wraps [child] in the same localization + provider stack the app's
/// entrypoint builds, with **exactly one** [ProviderScope].
///
/// [overrides] is threaded into that single scope rather than by nesting a
/// second `ProviderScope` around [child]. A nested scope silently drops the
/// outer scope's overrides for providers read below it in some Riverpod
/// versions, which previously made `serverProfileRepositoryProvider`
/// overrides appear to be ignored — the widget then ran the real
/// `SharedPreferences`-backed repository against empty mock prefs and
/// rendered an empty list instead of the seeded records.
Widget localizedApp({
  required Widget child,
  AssetLoader? assetLoader,
  // Riverpod's `Override` type is not exported by `flutter_riverpod`, and
  // adding `riverpod` as a direct dependency purely to name a test-helper
  // parameter type would be wrong. The override list is therefore built by
  // the caller and forwarded verbatim; `.cast()` adapts `List<Object>` to the
  // `List<Override>` the scope expects.
  List<Object>? overrides,
  Locale startLocale = const Locale('en'),
}) {
  return EasyLocalization(
    supportedLocales: startLocale.languageCode == 'en'
        ? const <Locale>[Locale('en')]
        : const <Locale>[Locale('en'), Locale('de')],
    path: 'assets/translations',
    startLocale: startLocale,
    fallbackLocale: const Locale('en'),
    saveLocale: false,
    assetLoader: assetLoader ?? TestAssetLoader(),
    child: ProviderScope(
      overrides: (overrides ?? const <Object>[]).cast(),
      child: child,
    ),
  );
}

/// Pumps [app] inside [localizedApp] and settles the localization load.
Future<void> pumpLocalizedApp(
  WidgetTester tester,
  Widget app, {
  AssetLoader? assetLoader,
  List<Object>? overrides,
  Locale startLocale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    localizedApp(
      child: app,
      assetLoader: assetLoader,
      overrides: overrides,
      startLocale: startLocale,
    ),
  );

  // `EasyLocalization` resolves translations through an async asset load
  // that starts only when the localization delegate first loads. A single
  // `pumpAndSettle` is NOT enough: it can complete before the loader's
  // Future resolves, leaving `.tr()` to fall back to returning the raw key
  // (logged by easy_localization as "Localization key [...] not found").
  // Yield to the real event loop, then pump frames until the text settles.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}
