// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:config_parser/config_parser.dart';
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
import 'package:mobile/core/providers/subscription_fetcher_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:mobile/features/connection/domain/usecases/build_server_profile.dart';
import 'package:mobile/features/connection/presentation/providers/camera_permission_provider.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

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
    : _translations = translations ?? {'en': testEnglishTranslations()};

  final Map<String, Map<String, dynamic>> _translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final key = locale.languageCode;
    final data = _translations[key] ?? _translations['en'];
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
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// Every profile passed to [start], in call order.
  final List<ServerProfile> startCalls = <ServerProfile>[];

  /// How many times [stop] was called.
  int stopCalls = 0;

  /// How many times [prepare] was called.
  int prepareCalls = 0;

  /// The last state pushed via [emit].
  ConnectionState lastState = const Disconnected();

  @override
  Stream<ConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<TrafficStats> get trafficStats => _statsController.stream;

  @override
  Stream<String> get logEvents => _logController.stream;

  /// Pushes [log] to every listener of [logEvents].
  void emitLog(String log) => _logController.add(log);

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

  /// Consent is always already held in tests: this fake exists to drive UI
  /// state transitions deterministically, and there is no Android consent
  /// dialog to model. Recorded like `stopCalls` so a test can assert the
  /// widget layer actually asked for consent before starting.
  @override
  Future<VpnCommandResult> prepare() async {
    prepareCalls++;
    return const VpnCommandAccepted();
  }

  /// Releases both controllers.
  Future<void> dispose() async {
    await _stateController.close();
    await _statsController.close();
  }
}

/// A valid VLESS URI. The UUID and host are fake; only the shape matters.
// TEMP-ARTIFACT: Hardcoded test URI from P3-T15 scaffolding.
// Phase 5 will introduce dynamic server profiles.
const String validVlessUri =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443#My%20Server';

/// A valid Shadowsocks URI (userinfo form).
const String validShadowsocksUri =
    'ss://YWVzLTI1Ni1nY206c2VjcmV0cHc=@example.com:8388#SS%20Node';

/// A valid Trojan URI.
const String validTrojanUri =
    'trojan://mypassword@example.com:443#Trojan%20Node';

/// In-memory saved server record used by test doubles.
class SavedServerRecord {
  const SavedServerRecord({
    required this.id,
    required this.sourceUri,
    required this.addedAt,
  });

  final String id;
  final String sourceUri;
  final DateTime addedAt;
}

/// An in-memory data source for tests.
///
/// Used so persistence behaviour is asserted without a platform channel, and so
/// a "restart" can be simulated by building a second repository over the same
/// backing list.
class FakeServerProfileDataSource {
  /// Creates a data source seeded with [initial].
  FakeServerProfileDataSource([List<SavedServerRecord>? initial])
    : records = <SavedServerRecord>[...?initial],
      savedProfiles = <ServerProfile>[],
      subscriptions = <SubscriptionMetadata>[];

  /// The records currently held. Survives a "restart" by being shared.
  final List<SavedServerRecord> records;

  /// In-memory server profiles saved via repository.
  final List<ServerProfile> savedProfiles;

  /// In-memory subscriptions saved via repository.
  final List<SubscriptionMetadata> subscriptions;
}

/// A test-only in-memory [ServerProfileRepository] implementation for widget
/// tests, allowing simulated app restarts via shared
/// [FakeServerProfileDataSource].
class FakeServerProfileRepository implements ServerProfileRepository {
  FakeServerProfileRepository(FakeServerProfileDataSource dataSource)
    : _dataSource = dataSource;

  final FakeServerProfileDataSource _dataSource;
  static const BuildServerProfile _buildProfile = BuildServerProfile();

  @override
  Future<List<SavedServer>> loadServers() async {
    final result = <SavedServer>[];
    for (final record in _dataSource.records) {
      final parsed = _buildProfile(
        uri: record.sourceUri,
        id: record.id,
        addedAt: record.addedAt,
      );
      switch (parsed) {
        case Ok(:final value):
          result.add(SavedServerProfile(value));
        case Err(:final error):
          result.add(SavedServerBroken(id: record.id, reason: error.message));
      }
    }
    for (final profile in _dataSource.savedProfiles) {
      result.add(SavedServerProfile(profile));
    }
    return result;
  }

  @override
  Future<void> addServer(String sourceUri) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    _dataSource.records.add(
      SavedServerRecord(id: id, sourceUri: sourceUri, addedAt: DateTime.now()),
    );
  }

  @override
  Future<void> removeServer(String id) async {
    _dataSource.records.removeWhere((r) => r.id == id);
    _dataSource.savedProfiles.removeWhere((p) => p.id == id);
  }

  @override
  Future<List<ServerProfile>> getAll() async {
    final servers = await loadServers();
    return servers
        .whereType<SavedServerProfile>()
        .map((s) => s.profile)
        .toList(growable: false);
  }

  @override
  Future<ServerProfile?> getById(String id) async {
    final all = await getAll();
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> save(ServerProfile profile) async {
    _dataSource.records.removeWhere((r) => r.id == profile.id);
    _dataSource.savedProfiles.removeWhere((p) => p.id == profile.id);
    _dataSource.savedProfiles.add(profile);
  }

  @override
  Future<void> delete(String id) => removeServer(id);

  @override
  Future<List<SubscriptionMetadata>> getAllSubscriptions() async =>
      List.unmodifiable(_dataSource.subscriptions);

  @override
  Future<SubscriptionMetadata?> getSubscriptionById(String id) async {
    for (final s in _dataSource.subscriptions) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Future<void> saveSubscription(SubscriptionMetadata subscription) async {
    _dataSource.subscriptions.removeWhere((s) => s.id == subscription.id);
    _dataSource.subscriptions.add(subscription);
  }

  @override
  Future<void> saveSubscriptionWithProfiles(
    SubscriptionMetadata subscription,
    List<ServerProfile> profiles,
  ) async {
    _dataSource.subscriptions.removeWhere((s) => s.id == subscription.id);
    _dataSource.subscriptions.add(subscription);
    for (final profile in profiles) {
      _dataSource.records.removeWhere((r) => r.id == profile.id);
      _dataSource.savedProfiles.removeWhere((p) => p.id == profile.id);
      _dataSource.savedProfiles.add(profile);
    }
  }

  @override
  Future<void> replaceSubscriptionProfiles(
    SubscriptionMetadata subscription,
    List<ServerProfile> newProfiles,
  ) async {
    final oldSub = await getSubscriptionById(subscription.id);
    final oldAssociated = oldSub?.associatedServerIds ?? const <String>[];

    _dataSource.subscriptions.removeWhere((s) => s.id == subscription.id);
    _dataSource.subscriptions.add(subscription);

    _dataSource.savedProfiles.removeWhere(
      (p) =>
          p.subscriptionId == subscription.id || oldAssociated.contains(p.id),
    );
    _dataSource.records.removeWhere((r) => oldAssociated.contains(r.id));

    _dataSource.savedProfiles.addAll(newProfiles);
  }

  @override
  Future<void> deleteSubscription(String id) async {
    _dataSource.subscriptions.removeWhere((s) => s.id == id);
  }

  @override
  Future<void> deleteSubscriptionCascade(String subscriptionId) async {
    final oldSub = await getSubscriptionById(subscriptionId);
    final oldAssociated = oldSub?.associatedServerIds ?? const <String>[];

    _dataSource.subscriptions.removeWhere((s) => s.id == subscriptionId);
    _dataSource.savedProfiles.removeWhere(
      (p) => p.subscriptionId == subscriptionId || oldAssociated.contains(p.id),
    );
    _dataSource.records.removeWhere((r) => oldAssociated.contains(r.id));
  }
}

/// A controllable [CameraPermissionService] fake for widget tests.
class FakeCameraPermissionService implements CameraPermissionService {
  /// Creates a fake camera permission service.
  const FakeCameraPermissionService({
    this.status = CameraPermissionStatus.granted,
    this.openSettingsResult = true,
  });

  /// The status returned by [checkStatus] and [requestPermission].
  final CameraPermissionStatus status;

  /// The value returned by [openSettings].
  final bool openSettingsResult;

  @override
  Future<CameraPermissionStatus> checkStatus() async => status;

  @override
  Future<CameraPermissionStatus> requestPermission() async => status;

  @override
  Future<bool> openSettings() async => openSettingsResult;
}

/// Builds a [ServerProfileRepository] over [dataSource].
ServerProfileRepository buildRepository(
  FakeServerProfileDataSource dataSource,
) => FakeServerProfileRepository(dataSource);

/// Riverpod overrides that resolve the saved-server list from [dataSource]
/// and camera permission from [cameraPermissionService].
///
/// Returns `List<Object>` (not `List<Override>`) because the harness cannot
/// name `Override` — see [localizedApp].
List<Object> repositoryOverride([
  FakeServerProfileDataSource? dataSource,
  CameraPermissionService? cameraPermissionService,
]) => [
  serverProfileRepositoryProvider.overrideWith(
    (ref) async => buildRepository(dataSource ?? FakeServerProfileDataSource()),
  ),
  cameraPermissionServiceProvider.overrideWithValue(
    cameraPermissionService ?? const FakeCameraPermissionService(),
  ),
];

/// Pumps [app] with a `ProviderScope` that overrides the engine, the
/// profile repository, and camera permissions, plus the real localization.
Future<void> pumpConnectionApp(
  WidgetTester tester,
  Widget app, {
  required FakeVpnEngine engine,
  FakeServerProfileDataSource? dataSource,
  CameraPermissionService? cameraPermissionService,
  QrScannerBuilder? scannerBuilder,
  SubscriptionFetcher? subscriptionFetcher,
  ServerProfileRepository? repository,
}) async {
  await tester.pumpWidget(
    localizedApp(
      overrides: [
        vpnEngineProvider.overrideWithValue(engine),
        serverProfileRepositoryProvider.overrideWith(
          (ref) async =>
              repository ??
              buildRepository(dataSource ?? FakeServerProfileDataSource()),
        ),
        cameraPermissionServiceProvider.overrideWithValue(
          cameraPermissionService ?? const FakeCameraPermissionService(),
        ),
        qrScannerBuilderProvider.overrideWithValue(scannerBuilder),
        if (subscriptionFetcher != null)
          subscriptionFetcherProvider.overrideWithValue(subscriptionFetcher),
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
  FakeServerProfileDataSource? dataSource,
  CameraPermissionService? cameraPermissionService,
  QrScannerBuilder? scannerBuilder,
  SubscriptionFetcher? subscriptionFetcher,
}) async {
  await pumpConnectionApp(
    tester,
    localizedMaterialApp(home: app),
    engine: engine,
    dataSource: dataSource,
    cameraPermissionService: cameraPermissionService,
    scannerBuilder: scannerBuilder,
    subscriptionFetcher: subscriptionFetcher,
  );
}

/// The translations that [TestAssetLoader] serves, for drift assertions.
Map<String, dynamic> testEnglishTranslations() => const {
  'app_title': 'Brick VPN',
  'navigation': {
    'home': 'Home',
    'servers': 'Servers',
    'logs': 'Logs',
    'settings': 'Settings',
  },
  'servers': {
    'title': 'Servers',
    'placeholder': 'Server list will appear here',
    'empty_title': 'No servers added yet',
    'empty_subtitle':
        'Add a server link, scan a QR code, or import a subscription to '
        'get started.',
    'standalone_section': 'Standalone Servers',
    'subscription_section': 'Subscription Servers',
    'standalone_badge': 'Standalone',
    'subscription_badge': 'Subscription',
    'edit': 'Edit',
    'duplicate': 'Duplicate',
    'refresh_subscription': 'Refresh Subscription',
    'delete_subscription': 'Delete Subscription',
    'delete_server_title': 'Delete Server',
    'delete_server_message': 'Are you sure you want to delete this server?',
    'delete_subscription_title': 'Delete Subscription',
    'delete_subscription_message':
        'Are you sure you want to delete this subscription and all its '
        'servers?',
    'confirm_delete': 'Delete',
    'cancel': 'Cancel',
    'save': 'Save',
    'edit_server_title': 'Edit Server',
    'server_name': 'Server Name',
    'replacement_uri': 'Replacement URI (optional)',
    'replacement_uri_hint': 'Paste replacement configuration link',
    'copy_suffix': '{name} (Copy)',
    'name_required': 'Server name cannot be empty',
    'storage_error': 'Failed to save server changes to local storage',
    'read_only_error':
        'Subscription servers are read-only. Duplicate as standalone to edit.',
  },
  'home': {
    'title': 'Brick VPN',
    'label': 'Home',
    'go_to_settings': 'Go to Settings',
  },
  'settings': {
    'title': 'Settings',
    'label': 'Settings',
    'back_to_home': 'Back to Home',
    'language': 'Language',
    'theme': 'Theme',
    'theme_system': 'System',
    'theme_light': 'Light',
    'theme_dark': 'Dark',
    'lang_en': 'English',
    'lang_de': 'Deutsch',
    'live_logs': 'Live Logs',
    'live_logs_subtitle': 'Real-time diagnostic logs',
    'no_logs': 'No log entries yet',
  },
  'connection': {
    'add_server': 'Add Server',
    'add_subscription': 'Add Subscription',
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
  'error': {
    'generic': 'An unexpected error occurred',
    'vpn_permission_denied': 'VPN permission was denied by the system',
    'invalid_config': 'The server configuration is invalid',
    'platform_error': 'VPN engine encountered an internal error',
    'unknown': 'An unknown connection error occurred',
    'server_busy': 'A VPN operation is already in progress',
  },
  'add_server': {
    'title': 'Add Server',
    'uri_label': 'Server URI',
    'paste_hint': 'Paste server configuration link (vless://, vmess://, etc.)',
    'paste_from_clipboard': 'Paste from clipboard',
    'save': 'Save',
    'scan_qr': 'Scan QR Code',
    'error_is_subscription':
        'This is a subscription URL. Please use the Add Subscription flow.',
    'uri_required': 'Enter a server URI first',
  },
  'qr_scan': {
    'title': 'Scan QR Code',
    'instruction': 'Point your camera at a server QR code',
    'cancel': 'Cancel',
    'permission_denied': 'Camera permission is required to scan QR codes.',
    'permission_permanently_denied':
        'Camera permission is permanently denied. Please enable it in '
        'system settings.',
    'request_permission': 'Grant Permission',
    'open_settings': 'Open Settings',
  },
  'add_subscription': {
    'title': 'Add Subscription',
    'url_label': 'Subscription URL',
    'url_hint': 'https://example.com/subscription',
    'name_label': 'Subscription Name (optional)',
    'name_hint': 'My Subscription',
    'import_button': 'Import Subscription',
    'url_required': 'Enter a subscription URL first',
    'success_message': 'Successfully imported {count} servers',
    'partial_success_message':
        'Imported {count} servers ({skipped} invalid entries skipped)',
    'no_valid_servers': 'No valid server configurations found in subscription',
    'invalid_url': 'Please enter a valid HTTPS subscription URL',
    'paste_from_clipboard': 'Paste from clipboard',
    'storage_error': 'Failed to save subscription to local storage',
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
    supportedLocales: const <Locale>[Locale('en'), Locale('de')],
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
