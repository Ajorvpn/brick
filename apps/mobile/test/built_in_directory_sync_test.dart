// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/servers/data/services/built_in_directory_sync_service.dart';
import 'package:mobile/features/servers/domain/built_in_feed_config.dart';
import 'package:mobile/features/servers/presentation/providers/built_in_directory_sync_provider.dart';
import 'package:mobile/features/servers/presentation/screens/servers_screen.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import 'localization_test_harness.dart';

/// Real-shaped lines from the live `Ajorvpn/brick-sub-collector` feed: the
/// `#` fragment is the only place country metadata travels.
const String _germany =
    'vless://11111111-2222-3333-4444-555555555555@de.example.com:443'
    '?security=reality#🇩🇪 Germany 01 | VLESS';
const String _netherlands =
    'trojan://secretpass@nl.example.com:443'
    '#🇳🇱 Amsterdam';
const String _unitedStates =
    'ss://YWVzLTI1Ni1nY206c2VjcmV0cHc=@us.example.com:8388'
    '#🇺🇸 New York';

/// A mixed feed: three supported protocols, one unparseable URI line and one
/// line that is not a URI at all.
String _mixedFeed() => <String>[
  _germany,
  'this line is not a configuration',
  _netherlands,
  'unsupported://nope',
  _unitedStates,
].join('\n');

final Uri _primary = Uri.parse('https://primary.example/directory.txt');
final Uri _mirror = Uri.parse('https://mirror.example/directory.txt');

BuiltInFeedFetcher _body(String body, {List<Uri>? calls}) {
  return (uri) async {
    calls?.add(uri);
    return Ok<String, ConfigParseError>(body);
  };
}

BuiltInFeedFetcher _offline({List<Uri>? calls}) {
  return (uri) async {
    calls?.add(uri);
    return const Err<String, ConfigParseError>(
      NetworkFailureError('the request could not be completed'),
    );
  };
}

BuiltInDirectorySyncService _service({
  required FakeServerProfileRepository repository,
  required AppPreferencesRepository preferences,
  required BuiltInFeedFetcher fetcher,
  List<Uri>? feedUrls,
  DateTime Function()? clock,
  Duration? feedTimeout,
}) {
  return BuiltInDirectorySyncService(
    loadRepository: () async => repository,
    preferences: preferences,
    fetcher: fetcher,
    feedUrls: feedUrls ?? <Uri>[_primary],
    feedTimeout: feedTimeout ?? kBuiltInFeedTimeout,
    clock: clock ?? () => DateTime.utc(2026, 11, 23, 10),
  );
}

void main() {
  setUpAll(initTestLocalization);

  group('Built-in directory payload parsing', () {
    test('parses a Base64-encoded feed and keeps the feed remarks', () async {
      final dataSource = FakeServerProfileDataSource();
      final repository = FakeServerProfileRepository(dataSource);
      final encoded = base64.encode(utf8.encode(_mixedFeed()));

      final result = await _service(
        repository: repository,
        preferences: FakeAppPreferencesRepository(),
        fetcher: _body(encoded),
      ).forceSync();

      expect(result, isA<DirectorySyncSuccess>());
      expect(result.serverCount, equals(3));

      final servers = await repository.getAll();
      expect(servers.length, equals(3));
      expect(
        servers.every(
          (server) => server.subscriptionId == kBuiltInDirectorySubscriptionId,
        ),
        isTrue,
      );
      expect(
        servers.any((server) => server.name.contains('Germany 01')),
        isTrue,
        reason: 'the #fragment must survive as the display name',
      );
    });

    test('parses a plain-text feed and skips malformed lines safely', () async {
      final repository = FakeServerProfileRepository(
        FakeServerProfileDataSource(),
      );

      final result = await _service(
        repository: repository,
        preferences: FakeAppPreferencesRepository(),
        fetcher: _body(_mixedFeed()),
      ).forceSync();

      expect(result, isA<DirectorySyncSuccess>());
      // One unsupported scheme plus one non-URI line: neither aborts the sync.
      expect((result as DirectorySyncSuccess).skippedLineCount, equals(1));

      final servers = await repository.getAll();
      expect(
        servers.map((server) => server.name).toList(),
        containsAll(<String>[
          '🇩🇪 Germany 01 | VLESS',
          '🇳🇱 Amsterdam',
          '🇺🇸 New York',
        ]),
      );
    });

    test(
      'a payload with zero usable servers is a failure, not a wipe',
      () async {
        final repository = FakeServerProfileRepository(
          FakeServerProfileDataSource(),
        );
        final preferences = FakeAppPreferencesRepository();

        // First a good sync, so there is a cache to protect.
        await _service(
          repository: repository,
          preferences: preferences,
          fetcher: _body(_mixedFeed()),
        ).forceSync();

        final result = await _service(
          repository: repository,
          preferences: preferences,
          fetcher: _body('unsupported://only-garbage'),
        ).forceSync();

        expect(result, isA<DirectorySyncFailure>());
        expect(result.serverCount, equals(3));
        expect((await repository.getAll()).length, equals(3));
      },
    );
  });

  group('Mirror failover', () {
    test('falls back to the mirror when the primary fails', () async {
      final calls = <Uri>[];
      final repository = FakeServerProfileRepository(
        FakeServerProfileDataSource(),
      );

      Future<Result<String, ConfigParseError>> fetcher(Uri uri) async {
        calls.add(uri);
        if (uri == _primary) {
          return const Err<String, ConfigParseError>(
            NetworkTimeoutError('directory fetch', kBuiltInFeedTimeout),
          );
        }
        return Ok<String, ConfigParseError>(_mixedFeed());
      }

      final result = await _service(
        repository: repository,
        preferences: FakeAppPreferencesRepository(),
        fetcher: fetcher,
        feedUrls: <Uri>[_primary, _mirror],
      ).forceSync();

      expect(result, isA<DirectorySyncSuccess>());
      expect(calls, equals(<Uri>[_primary, _mirror]));
      expect((await repository.getAll()).length, equals(3));
    });

    test('preserves the cached directory when every mirror fails', () async {
      final repository = FakeServerProfileRepository(
        FakeServerProfileDataSource(),
      );
      final preferences = FakeAppPreferencesRepository();

      await _service(
        repository: repository,
        preferences: preferences,
        fetcher: _body(_mixedFeed()),
      ).forceSync();
      final before = (await repository.getAll()).map((s) => s.id).toList();

      final result = await _service(
        repository: repository,
        preferences: preferences,
        fetcher: _offline(),
        feedUrls: <Uri>[_primary, _mirror],
      ).forceSync();

      expect(result, isA<DirectorySyncFailure>());
      expect(result.serverCount, equals(3));
      expect(
        (await repository.getAll()).map((s) => s.id).toList(),
        equals(before),
        reason: 'a total outage must never wipe the encrypted cache',
      );
    });
  });

  group('Throttle and single-flight', () {
    test(
      'syncIfNeeded skips a fresh cache and forceSync bypasses it',
      () async {
        final calls = <Uri>[];
        final repository = FakeServerProfileRepository(
          FakeServerProfileDataSource(),
        );
        final preferences = FakeAppPreferencesRepository();
        var now = DateTime.utc(2026, 11, 23, 10);
        final service = _service(
          repository: repository,
          preferences: preferences,
          fetcher: _body(_mixedFeed(), calls: calls),
          clock: () => now,
        );

        // Nothing cached yet -> the automatic pass must run.
        expect(await service.syncIfNeeded(), isA<DirectorySyncSuccess>());
        expect(calls.length, equals(1));
        expect(preferences.getLastDirectorySyncAt(), equals(now));

        // Five minutes later the cache is still fresh.
        now = now.add(const Duration(minutes: 5));
        expect(await service.syncIfNeeded(), isA<DirectorySyncSkipped>());
        expect(calls.length, equals(1));

        // A manual tap always refreshes.
        expect(await service.forceSync(), isA<DirectorySyncSuccess>());
        expect(calls.length, equals(2));

        // Past the window, the automatic pass runs again.
        now = now.add(kBuiltInDirectorySyncInterval);
        expect(await service.syncIfNeeded(), isA<DirectorySyncSuccess>());
        expect(calls.length, equals(3));
      },
    );

    test('concurrent callers share one network attempt', () async {
      final calls = <Uri>[];
      final repository = FakeServerProfileRepository(
        FakeServerProfileDataSource(),
      );
      final service = _service(
        repository: repository,
        preferences: FakeAppPreferencesRepository(),
        fetcher: _body(_mixedFeed(), calls: calls),
      );

      final results = await Future.wait(<Future<DirectorySyncResult>>[
        service.forceSync(),
        service.forceSync(),
        service.forceSync(),
      ]);

      expect(results.every((result) => result is DirectorySyncSuccess), isTrue);
      expect(calls.length, equals(1));
    });

    test('selects the first synced server when none was active', () async {
      final repository = FakeServerProfileRepository(
        FakeServerProfileDataSource(),
      );
      final preferences = FakeAppPreferencesRepository();

      await _service(
        repository: repository,
        preferences: preferences,
        fetcher: _body(_mixedFeed()),
      ).forceSync();

      expect(
        preferences.getActiveServerId(),
        equals('${kBuiltInDirectorySubscriptionId}_srv_1'),
      );
    });
  });

  group('Feed URL hardening', () {
    test('rejects non-HTTPS and SSRF-prone BRICK_SUB_URLS entries', () {
      final urls = resolveBuiltInFeedUrls(
        override: <String>[
          'http://insecure.example/sub.txt',
          'https://127.0.0.1/sub.txt',
          'https://[::1]/sub.txt',
          'https://169.254.169.254/latest/meta-data',
          'https://10.0.0.5/sub.txt',
          'https://cdn.example.com/sub.txt',
        ].join(','),
      );

      expect(
        urls.map((uri) => uri.toString()).toList(),
        equals(<String>['https://cdn.example.com/sub.txt']),
      );
    });

    test('falls back to the compiled-in mirrors when an override is unusable '
        'entirely', () {
      final urls = resolveBuiltInFeedUrls(override: 'http://insecure.example');

      expect(
        urls.map((uri) => uri.toString()).toList(),
        equals(kDefaultBuiltInFeedUrls),
      );
    });

    test('the compiled-in defaults are the verified live feed URLs', () {
      final urls = resolveBuiltInFeedUrls();

      expect(urls.length, equals(2));
      expect(
        urls.first.toString(),
        equals(
          'https://raw.githubusercontent.com/Ajorvpn/brick-sub-collector/'
          'sub/sub.txt',
        ),
      );
      expect(
        urls.last.toString(),
        equals(
          'https://cdn.jsdelivr.net/gh/Ajorvpn/brick-sub-collector@sub/'
          'sub.txt',
        ),
      );
    });

    test('literal private, CGNAT and multicast hosts are blocked', () {
      expect(isBlockedBuiltInFeedHost('192.168.1.10'), isTrue);
      expect(isBlockedBuiltInFeedHost('100.64.0.1'), isTrue);
      expect(isBlockedBuiltInFeedHost('224.0.0.1'), isTrue);
      expect(isBlockedBuiltInFeedHost('::ffff:127.0.0.1'), isTrue);
      expect(isBlockedBuiltInFeedHost('raw.githubusercontent.com'), isFalse);
    });
  });

  group('ServersScreen directory rendering', () {
    testWidgets('renders synced servers grouped by country and city', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dataSource = FakeServerProfileDataSource();
      final repository = FakeServerProfileRepository(dataSource);
      final preferences = FakeAppPreferencesRepository();
      await _service(
        repository: repository,
        preferences: preferences,
        fetcher: _body(_mixedFeed()),
      ).forceSync();

      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const ServersScreen()),
        overrides: <Object>[
          serverProfileRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          appPreferencesRepositoryProvider.overrideWithValue(preferences),
          builtInFeedFetcherProvider.overrideWithValue(offlineDirectoryFetcher),
        ],
      );

      expect(
        find.byKey(const ValueKey<String>('country_group_DE')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_NL')),
        findsOneWidget,
      );
      expect(find.text('Netherlands'), findsWidgets);
      expect(find.text('Germany'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offline with an empty list shows a calm retry notice', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = FakeServerProfileRepository(
        FakeServerProfileDataSource(),
      );

      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(home: const ServersScreen()),
        overrides: <Object>[
          serverProfileRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            FakeAppPreferencesRepository(),
          ),
          builtInFeedFetcherProvider.overrideWithValue(offlineDirectoryFetcher),
        ],
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('servers_empty_update_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('servers_empty_update_button')),
      );
      await tester.pumpAndSettle();

      // First manual sync -> Play-compliant disclosure, then a real attempt.
      expect(
        find.byKey(const ValueKey<String>('update_servers_disclosure_sheet')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('update_servers_disclosure_accept')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('servers_directory_sync_banner')),
        findsOneWidget,
      );
      expect(
        find.text(
          "Couldn't reach the server directory. Check your connection and "
          'try again.',
        ),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey<String>('servers_empty_state')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('F1-F3 and F5 regressions', () {
    test(
      'F1: a fresh sync selects the first synced server immediately',
      () async {
        final repository = FakeServerProfileRepository(
          FakeServerProfileDataSource(),
        );
        final preferences = FakeAppPreferencesRepository();
        final container = ProviderContainer(
          overrides: [
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            appPreferencesRepositoryProvider.overrideWithValue(preferences),
            builtInFeedFetcherProvider.overrideWithValue(_body(_mixedFeed())),
          ],
        );
        addTearDown(container.dispose);

        // Prime the notifier exactly as `HomeScreen` does on a fresh install.
        expect(container.read(activeServerIdProvider), isNull);

        final result = await container
            .read(builtInDirectorySyncControllerProvider)
            .forceSync();

        expect(result, isA<DirectorySyncSuccess>());
        expect(
          container.read(activeServerIdProvider),
          equals('${kBuiltInDirectorySubscriptionId}_srv_1'),
          reason: 'the persisted fallback must reach the in-memory notifier',
        );
      },
    );

    testWidgets(
      'F2: the official directory has no user refresh or delete controls',
      (tester) async {
        tester.view.physicalSize = const Size(412, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final repository = FakeServerProfileRepository(
          FakeServerProfileDataSource(),
        );
        final preferences = FakeAppPreferencesRepository();
        await _service(
          repository: repository,
          preferences: preferences,
          fetcher: _body(_mixedFeed()),
        ).forceSync();

        await pumpLocalizedApp(
          tester,
          localizedMaterialApp(home: const ServersScreen()),
          overrides: <Object>[
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
            appPreferencesRepositoryProvider.overrideWithValue(preferences),
            builtInFeedFetcherProvider.overrideWithValue(
              offlineDirectoryFetcher,
            ),
          ],
        );

        expect(
          find.byKey(
            const ValueKey<String>(
              'subscription_delete_brick_official_directory',
            ),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey<String>(
              'subscription_refresh_brick_official_directory',
            ),
          ),
          findsNothing,
        );
        // The synced servers are still browsable by country.
        expect(
          find.byKey(const ValueKey<String>('country_group_DE')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    test('F3: a hanging mirror is cut off and fails over', () async {
      final calls = <Uri>[];
      final hanging = Completer<Result<String, ConfigParseError>>();
      final repository = FakeServerProfileRepository(
        FakeServerProfileDataSource(),
      );

      Future<Result<String, ConfigParseError>> fetcher(Uri uri) {
        calls.add(uri);
        if (uri == _primary) return hanging.future;
        return Future<Result<String, ConfigParseError>>.value(
          Ok<String, ConfigParseError>(_mixedFeed()),
        );
      }

      final result = await _service(
        repository: repository,
        preferences: FakeAppPreferencesRepository(),
        fetcher: fetcher,
        feedUrls: <Uri>[_primary, _mirror],
        feedTimeout: const Duration(milliseconds: 50),
      ).forceSync();

      expect(result, isA<DirectorySyncSuccess>());
      expect(calls, equals(<Uri>[_primary, _mirror]));
      expect((await repository.getAll()).length, equals(3));
    });

    testWidgets('F5: Persian RTL render is overflow-free and fully localized', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final repository = FakeServerProfileRepository(
        FakeServerProfileDataSource(),
      );
      final preferences = FakeAppPreferencesRepository(
        initialDirectorySyncAccepted: true,
      );
      await _service(
        repository: repository,
        preferences: preferences,
        fetcher: _body(_mixedFeed()),
      ).forceSync();

      // A sync that never finishes keeps the status banner on screen while the
      // synced country groups are already rendered.
      final pending = Completer<Result<String, ConfigParseError>>();

      await pumpLocalizedApp(
        tester,
        localizedMaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: const ServersScreen(),
            ),
          ),
        ),
        startLocale: const Locale('fa'),
        assetLoader: TestAssetLoader(
          translations: <String, Map<String, dynamic>>{
            'en': testEnglishTranslations(),
            'fa': parseTranslationsJson(
              File('assets/translations/fa.json').readAsStringSync(),
            ),
          },
        ),
        overrides: <Object>[
          serverProfileRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          appPreferencesRepositoryProvider.overrideWithValue(preferences),
          builtInFeedFetcherProvider.overrideWithValue(
            (Uri uri) => pending.future,
          ),
        ],
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('servers_update_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final banner = find.byKey(
        const ValueKey<String>('servers_directory_sync_banner'),
      );
      expect(banner, findsOneWidget);
      expect(
        Directionality.of(tester.element(banner)),
        equals(TextDirection.rtl),
        reason: 'the banner must inherit the Persian text direction',
      );
      expect(
        find.byKey(const ValueKey<String>('country_group_DE')),
        findsOneWidget,
      );

      final rawKeys = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .where((value) => value.startsWith('servers.'))
          .toList(growable: false);
      expect(rawKeys, isEmpty, reason: 'no untranslated keys may render');
      expect(tester.takeException(), isNull);

      // Release the pending attempt so no timer outlives the test.
      pending.complete(
        const Err<String, ConfigParseError>(NetworkFailureError('offline')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
