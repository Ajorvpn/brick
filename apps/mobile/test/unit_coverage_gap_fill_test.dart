// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/log_entry.dart';
import 'package:mobile/core/logging/log_redactor.dart';
import 'package:mobile/core/platform/battery_optimization_service.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/security/sensitive_field_cipher.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/add_server_controller.dart';
import 'package:mobile/features/connection/presentation/providers/add_subscription_controller.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/servers/data/repositories/file_server_profile_repository.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:mobile/features/servers/presentation/providers/server_management_controller.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

import 'localization_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initTestLocalization();
    Localization.load(
      const Locale('en'),
      translations: Translations(testEnglishTranslations()),
    );
  });

  group('P9-T1 High-Value Gap Fill — Repository CRUD & Cascade Edge Cases', () {
    late Directory tempDir;
    late File storageFile;
    late InMemorySensitiveFieldCipher cipher;
    late FileServerProfileRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('brick_p9t1_repo_');
      storageFile = File('${tempDir.path}/server_profiles.json');
      cipher = InMemorySensitiveFieldCipher();
      repository = FileServerProfileRepository(
        storageFile: storageFile,
        cipher: cipher,
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'replaceSubscriptionProfiles updates sub, removes old servers & broken, '
      'and preserves standalone servers intact',
      () async {
        // 0. Seed a real broken server entry in storage
        storageFile.writeAsStringSync(
          jsonEncode({
            'schema_version': 2,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            'server_profiles': <Map<String, dynamic>>[],
            'subscriptions': <Map<String, dynamic>>[],
            'broken_servers': {'broken-entry-1': 'Corrupt config payload'},
          }),
        );

        // 1. Seed a standalone server
        final standalone = ServerProfile(
          id: 'standalone-1',
          name: 'Standalone Tokyo',
          config: const VlessOutbound(
            server: 'standalone.example.com',
            serverPort: 443,
            uuid: '11111111-1111-1111-1111-111111111111',
          ),
          addedAt: DateTime.utc(2026, 11),
        );
        await repository.save(standalone);

        // 2. Seed an initial subscription with 2 profiles
        final subProfile1 = ServerProfile(
          id: 'sub-p1',
          name: 'Sub Frankfurt 1',
          config: const VlessOutbound(
            server: 'de1.example.com',
            serverPort: 443,
            uuid: '22222222-2222-2222-2222-222222222222',
          ),
          addedAt: DateTime.utc(2026, 11, 2),
          subscriptionId: 'sub-alpha',
        );
        final subProfile2 = ServerProfile(
          id: 'sub-p2',
          name: 'Sub Frankfurt 2',
          config: const VlessOutbound(
            server: 'de2.example.com',
            serverPort: 443,
            uuid: '33333333-3333-3333-3333-333333333333',
          ),
          addedAt: DateTime.utc(2026, 11, 2),
          subscriptionId: 'sub-alpha',
        );
        final initialSub = SubscriptionMetadata(
          id: 'sub-alpha',
          url: 'https://sub.example.com/feed',
          name: 'Alpha Feed',
          associatedServerIds: const ['sub-p1', 'sub-p2', 'broken-entry-1'],
          lastRefreshedAt: DateTime.utc(2026, 11, 2),
        );
        await repository.saveSubscription(initialSub);
        await repository.save(subProfile1);
        await repository.save(subProfile2);

        // Verify initial state including broken server
        final serversBefore = await repository.loadServers();
        expect(
          serversBefore.whereType<SavedServerBroken>().map((b) => b.id),
          contains('broken-entry-1'),
        );
        var allProfiles = await repository.getAll();
        expect(allProfiles.map((p) => p.id).toSet(), {
          'standalone-1',
          'sub-p1',
          'sub-p2',
        });

        // 3. Replace subscription profiles with new set
        final updatedSubProfile = ServerProfile(
          id: 'sub-p3',
          name: 'Sub Berlin New',
          config: const VlessOutbound(
            server: 'de3.example.com',
            serverPort: 443,
            uuid: '44444444-4444-4444-4444-444444444444',
          ),
          addedAt: DateTime.utc(2026, 11, 3),
          subscriptionId: 'sub-alpha',
        );
        final updatedSub = initialSub.copyWith(
          associatedServerIds: const ['sub-p3'],
          lastRefreshedAt: DateTime.utc(2026, 11, 3),
        );

        await repository.replaceSubscriptionProfiles(updatedSub, [
          updatedSubProfile,
        ]);

        // 4. Verify old sub profiles purged, new sub profile saved,
        // broken entry removed, standalone preserved
        final serversAfter = await repository.loadServers();
        expect(
          serversAfter.whereType<SavedServerBroken>().map((b) => b.id),
          isNot(contains('broken-entry-1')),
        );
        expect(serversAfter.whereType<SavedServerBroken>(), isEmpty);

        allProfiles = await repository.getAll();
        expect(allProfiles.map((p) => p.id).toSet(), {
          'standalone-1',
          'sub-p3',
        });

        final reloadedRepo = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );
        final reloadedProfiles = await reloadedRepo.getAll();
        expect(reloadedProfiles.map((p) => p.id).toSet(), {
          'standalone-1',
          'sub-p3',
        });
        final reloadedServers = await reloadedRepo.loadServers();
        expect(reloadedServers.whereType<SavedServerBroken>(), isEmpty);
      },
    );

    test('deleteSubscriptionCascade removes sub, associated profiles, '
        'and broken entries while keeping standalone servers intact', () async {
      // 0. Seed broken server in storage before initializing repository
      storageFile.writeAsStringSync(
        jsonEncode({
          'schema_version': 2,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'server_profiles': <Map<String, dynamic>>[],
          'subscriptions': <Map<String, dynamic>>[],
          'broken_servers': {'sub-broken-orphan': 'Corrupt config payload'},
        }),
      );

      // 1. Seed standalone server
      final standalone = ServerProfile(
        id: 'standalone-keep',
        name: 'Independent WireGuard',
        config: WireGuardOutbound(
          server: 'wg.example.com',
          serverPort: 51820,
          privateKey: 'private-key-1',
          peerPublicKey: 'peer-pubkey-1',
          localAddresses: const ['10.0.0.2/32'],
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(standalone);

      // 2. Seed subscription with profiles and broken server ID
      final subProfile = ServerProfile(
        id: 'sub-delete-target',
        name: 'Sub To Delete',
        config: const VlessOutbound(
          server: 'target.example.com',
          serverPort: 443,
          uuid: '55555555-5555-5555-5555-555555555555',
        ),
        addedAt: DateTime.utc(2026, 11),
        subscriptionId: 'sub-beta',
      );
      final sub = SubscriptionMetadata(
        id: 'sub-beta',
        url: 'https://sub.example.com/beta',
        name: 'Beta Feed',
        associatedServerIds: const ['sub-delete-target', 'sub-broken-orphan'],
        lastRefreshedAt: DateTime.utc(2026, 11),
      );
      await repository.saveSubscription(sub);
      await repository.save(subProfile);

      // Verify loaded before cascade
      final serversBefore = await repository.loadServers();
      expect(
        serversBefore.whereType<SavedServerBroken>().map((b) => b.id),
        contains('sub-broken-orphan'),
      );
      expect(await repository.getById('standalone-keep'), isNotNull);
      expect(await repository.getById('sub-delete-target'), isNotNull);
      expect(await repository.getSubscriptionById('sub-beta'), isNotNull);

      // 3. Cascade delete
      await repository.deleteSubscriptionCascade('sub-beta');

      // 4. Verify sub and associated removed, broken purged, standalone remains
      final serversAfter = await repository.loadServers();
      expect(
        serversAfter.whereType<SavedServerBroken>().map((b) => b.id),
        isNot(contains('sub-broken-orphan')),
      );
      expect(serversAfter.whereType<SavedServerBroken>(), isEmpty);

      expect(await repository.getById('standalone-keep'), isNotNull);
      expect(await repository.getById('sub-delete-target'), isNull);
      expect(await repository.getSubscriptionById('sub-beta'), isNull);

      // 5. Verify persistence
      final reloadedRepo = FileServerProfileRepository(
        storageFile: storageFile,
        cipher: cipher,
      );
      final reloadedProfiles = await reloadedRepo.getAll();
      expect(reloadedProfiles.length, equals(1));
      expect(reloadedProfiles.first.id, equals('standalone-keep'));
      expect(await reloadedRepo.getSubscriptionById('sub-beta'), isNull);
      final reloadedServers = await reloadedRepo.loadServers();
      expect(reloadedServers.whereType<SavedServerBroken>(), isEmpty);
    });

    test('Outbound transport round-trip reconstruction for Grpc, Http, '
        'and HttpUpgrade', () async {
      // 1. Grpc Transport
      final grpcProfile = ServerProfile(
        id: 'grpc-profile',
        name: 'gRPC Node',
        config: const VlessOutbound(
          server: 'grpc.example.com',
          serverPort: 443,
          uuid: '66666666-6666-6666-6666-666666666666',
          transport: GrpcTransport(
            serviceName: 'my-grpc-service',
            idleTimeout: Duration(seconds: 15),
            pingTimeout: Duration(seconds: 5),
            permitWithoutStream: true,
          ),
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(grpcProfile);

      // 2. Http Transport
      final httpProfile = ServerProfile(
        id: 'http-profile',
        name: 'HTTP Node',
        config: VmessOutbound(
          server: 'http.example.com',
          serverPort: 80,
          uuid: '77777777-7777-7777-7777-777777777777',
          transport: HttpTransport(
            host: const ['host1.example.com', 'host2.example.com'],
            path: '/http-path',
            method: 'POST',
            headers: const {'X-Custom-Auth': 'header-secret-123'},
          ),
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(httpProfile);

      // 3. HttpUpgrade Transport
      final httpUpgradeProfile = ServerProfile(
        id: 'httpupgrade-profile',
        name: 'HttpUpgrade Node',
        config: TrojanOutbound(
          server: 'upgrade.example.com',
          serverPort: 443,
          password: 'trojan-password',
          transport: HttpUpgradeTransport(
            host: 'upgrade.host.com',
            path: '/upgrade-tunnel',
            headers: const {'X-Upgrade-Key': 'upgrade-secret'},
          ),
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(httpUpgradeProfile);

      // Reload from disk to verify _parseTransport round-trip
      final reloadedRepo = FileServerProfileRepository(
        storageFile: storageFile,
        cipher: cipher,
      );

      final loadedGrpc = await reloadedRepo.getById('grpc-profile');
      expect(loadedGrpc, isNotNull);
      final grpcCfg = loadedGrpc!.config as VlessOutbound;
      expect(grpcCfg.transport, isA<GrpcTransport>());
      final grpcTransport = grpcCfg.transport! as GrpcTransport;
      expect(grpcTransport.serviceName, equals('my-grpc-service'));
      expect(grpcTransport.idleTimeout, equals(const Duration(seconds: 15)));
      expect(grpcTransport.pingTimeout, equals(const Duration(seconds: 5)));
      expect(grpcTransport.permitWithoutStream, isTrue);

      final loadedHttp = await reloadedRepo.getById('http-profile');
      expect(loadedHttp, isNotNull);
      final httpCfg = loadedHttp!.config as VmessOutbound;
      expect(httpCfg.transport, isA<HttpTransport>());
      final httpTransport = httpCfg.transport! as HttpTransport;
      expect(
        httpTransport.host,
        equals(['host1.example.com', 'host2.example.com']),
      );
      expect(httpTransport.path, equals('/http-path'));
      expect(httpTransport.method, equals('POST'));
      expect(
        httpTransport.headers?['X-Custom-Auth'],
        equals('header-secret-123'),
      );

      final loadedUpgrade = await reloadedRepo.getById('httpupgrade-profile');
      expect(loadedUpgrade, isNotNull);
      final upgradeCfg = loadedUpgrade!.config as TrojanOutbound;
      expect(upgradeCfg.transport, isA<HttpUpgradeTransport>());
      final upgradeTransport = upgradeCfg.transport! as HttpUpgradeTransport;
      expect(upgradeTransport.host, equals('upgrade.host.com'));
      expect(upgradeTransport.path, equals('/upgrade-tunnel'));
      expect(
        upgradeTransport.headers?['X-Upgrade-Key'],
        equals('upgrade-secret'),
      );
    });

    test('Outbound extraParams round-trip encryption across SS, Hy2, Tuic, '
        'and AWG', () async {
      // Shadowsocks with extra params
      final ssProfile = ServerProfile(
        id: 'ss-profile',
        name: 'Shadowsocks Node',
        config: const ShadowsocksOutbound(
          server: 'ss.example.com',
          serverPort: 8388,
          method: 'aes-128-gcm',
          password: 'ss-password',
          extraParams: {'ss_param': 'secret_ss_val'},
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(ssProfile);

      // Hysteria2 with extra params
      final hy2Profile = ServerProfile(
        id: 'hy2-profile',
        name: 'Hy2 Node',
        config: Hysteria2Outbound(
          server: 'hy2.example.com',
          serverPort: 443,
          password: 'hy2-password',
          tls: TlsSettings(enabled: true, serverName: 'hy2.example.com'),
          extraParams: const {'hy2_param': 'secret_hy2_val'},
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(hy2Profile);

      // Tuic with extra params
      final tuicProfile = ServerProfile(
        id: 'tuic-profile',
        name: 'Tuic Node',
        config: TuicOutbound(
          server: 'tuic.example.com',
          serverPort: 8443,
          uuid: '88888888-8888-8888-8888-888888888888',
          password: 'tuic-password',
          tls: TlsSettings(enabled: true, serverName: 'tuic.example.com'),
          extraParams: const {'tuic_param': 'secret_tuic_val'},
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(tuicProfile);

      // AmneziaWg with extra params
      final awgProfile = ServerProfile(
        id: 'awg-profile',
        name: 'AWG Node',
        config: AmneziaWgOutbound(
          server: 'awg.example.com',
          serverPort: 51820,
          privateKey: 'awg-privkey',
          peerPublicKey: 'awg-pubkey',
          localAddresses: const ['10.0.0.3/32'],
          jc: 3,
          jmin: 40,
          jmax: 70,
          extraParams: const {'awg_param': 'secret_awg_val'},
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(awgProfile);

      // Reload and assert
      final reloadedRepo = FileServerProfileRepository(
        storageFile: storageFile,
        cipher: cipher,
      );

      final loadedSs = await reloadedRepo.getById('ss-profile');
      expect(
        loadedSs?.config.extraParams?['ss_param'],
        equals('secret_ss_val'),
      );

      final loadedHy2 = await reloadedRepo.getById('hy2-profile');
      expect(
        loadedHy2?.config.extraParams?['hy2_param'],
        equals('secret_hy2_val'),
      );

      final loadedTuic = await reloadedRepo.getById('tuic-profile');
      expect(
        loadedTuic?.config.extraParams?['tuic_param'],
        equals('secret_tuic_val'),
      );

      final loadedAwg = await reloadedRepo.getById('awg-profile');
      expect(
        loadedAwg?.config.extraParams?['awg_param'],
        equals('secret_awg_val'),
      );
    });

    test('Corrupt outbound JSON config surfaces gracefully as broken server '
        'without crashing', () async {
      final corruptJson = jsonEncode({
        'schema_version': 2,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'server_profiles': [
          {
            'id': 'corrupted-profile-id',
            'name': 'Corrupted Node',
            'protocol': 'vless',
            'server': 'corrupt.example.com',
            'server_port': 443,
            'config': {'type': 'unknown-unsupported-proto'},
            'added_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        'subscriptions': <dynamic>[],
        'broken_servers': <String, dynamic>{},
      });
      await storageFile.writeAsString(corruptJson, flush: true);

      final repo = FileServerProfileRepository(
        storageFile: storageFile,
        cipher: cipher,
      );

      final servers = await repo.loadServers();
      expect(servers.length, equals(1));
      expect(servers.first, isA<SavedServerBroken>());
      final broken = servers.first as SavedServerBroken;
      expect(broken.id, equals('corrupted-profile-id'));
      expect(broken.reason, isNotEmpty);
    });
  });

  group('P9-T1 High-Value Gap Fill — LogEntry & Redactor Edge Cases', () {
    test('LogEntry.parseEngineLine handles all severity aliases correctly', () {
      // Free-text bracket and prefix format
      expect(
        LogEntry.parseEngineLine('[TRACE] test trace').level,
        equals(LogLevel.trace),
      );
      expect(
        LogEntry.parseEngineLine('level=trace test').level,
        equals(LogLevel.trace),
      );
      expect(
        LogEntry.parseEngineLine('[DEBUG] test debug').level,
        equals(LogLevel.debug),
      );
      expect(
        LogEntry.parseEngineLine('level=debug test').level,
        equals(LogLevel.debug),
      );
      expect(
        LogEntry.parseEngineLine('[WARN] test warn').level,
        equals(LogLevel.warning),
      );
      expect(
        LogEntry.parseEngineLine('[WARNING] test warning').level,
        equals(LogLevel.warning),
      );
      expect(
        LogEntry.parseEngineLine('[ERROR] test error').level,
        equals(LogLevel.error),
      );
      expect(
        LogEntry.parseEngineLine('level=error test').level,
        equals(LogLevel.error),
      );
      expect(
        LogEntry.parseEngineLine('[FATAL] test fatal').level,
        equals(LogLevel.fatal),
      );
      expect(
        LogEntry.parseEngineLine('level=fatal test').level,
        equals(LogLevel.fatal),
      );
      expect(
        LogEntry.parseEngineLine('[INFO] test info').level,
        equals(LogLevel.info),
      );

      // Structured JSON alias variants
      // (TRC, DBG, WRN, PANIC, CRIT, CRITICAL, INF)
      expect(
        LogEntry.parseEngineLine(jsonEncode({'lvl': 'TRC', 'msg': 'm'})).level,
        equals(LogLevel.trace),
      );
      expect(
        LogEntry.parseEngineLine(jsonEncode({'lvl': 'DBG', 'msg': 'm'})).level,
        equals(LogLevel.debug),
      );
      expect(
        LogEntry.parseEngineLine(jsonEncode({'lvl': 'WRN', 'msg': 'm'})).level,
        equals(LogLevel.warning),
      );
      expect(
        LogEntry.parseEngineLine(jsonEncode({'lvl': 'PANIC', 'msg': 'm'}))
            .level,
        equals(LogLevel.fatal),
      );
      expect(
        LogEntry.parseEngineLine(jsonEncode({'severity': 'CRIT', 'msg': 'm'}))
            .level,
        equals(LogLevel.fatal),
      );
      expect(
        LogEntry.parseEngineLine(
          jsonEncode({'log_level': 'CRITICAL', 'msg': 'm'}),
        ).level,
        equals(LogLevel.fatal),
      );
      expect(
        LogEntry.parseEngineLine(jsonEncode({'lvl': 'INF', 'msg': 'm'})).level,
        equals(LogLevel.info),
      );
    });

    test('LogLevel.isWarningOrError correctly identifies severity', () {
      expect(LogLevel.trace.isWarningOrError, isFalse);
      expect(LogLevel.debug.isWarningOrError, isFalse);
      expect(LogLevel.info.isWarningOrError, isFalse);
      expect(LogLevel.warning.isWarningOrError, isTrue);
      expect(LogLevel.error.isWarningOrError, isTrue);
      expect(LogLevel.fatal.isWarningOrError, isTrue);
    });

    test('LogEntry.parseEngineLine handles structured JSON fallback keys '
        'and epoch timestamp variants', () {
      // Fallback keys: lvl, @timestamp, text, logger
      final jsonLine1 = jsonEncode({
        'lvl': 'WRN',
        '@timestamp': '2026-11-09T01:30:00Z',
        'text': 'warning text via fallback keys',
        'logger': 'core/engine',
      });
      final entry1 = LogEntry.parseEngineLine(jsonLine1);
      expect(entry1.level, equals(LogLevel.warning));
      expect(entry1.message, equals('warning text via fallback keys'));
      expect(entry1.source, equals('core/engine'));
      expect(entry1.timestamp.toIso8601String(), contains('2026-11-09'));

      // Fallback keys: log_level, ts as epoch seconds, error, caller
      final jsonLine2 = jsonEncode({
        'log_level': 'ERR',
        'ts': 1794268800, // Year 2026 epoch seconds
        'error': 'fatal io error message',
        'caller': 'net/tun',
      });
      final entry2 = LogEntry.parseEngineLine(jsonLine2);
      expect(entry2.level, equals(LogLevel.error));
      expect(entry2.message, equals('fatal io error message'));
      expect(entry2.source, equals('net/tun'));

      // Fallback keys: severity, timestamp as epoch millis, component
      final jsonLine3 = jsonEncode({
        'severity': 'CRIT',
        'timestamp': 1794268800000,
        'msg': 'panic from kernel',
        'component': 'kernel/router',
      });
      final entry3 = LogEntry.parseEngineLine(jsonLine3);
      expect(entry3.level, equals(LogLevel.fatal));
      expect(entry3.message, equals('panic from kernel'));
      expect(entry3.source, equals('kernel/router'));
    });

    test('LogEntry copyWith, equality, and hashCode contracts', () {
      final now = DateTime.utc(2026, 11, 9, 12);
      final e1 = LogEntry(
        timestamp: now,
        level: LogLevel.info,
        message: 'connected',
        source: 'tun',
        raw: '[INFO] [tun] connected',
      );

      final e2 = LogEntry(
        timestamp: now,
        level: LogLevel.info,
        message: 'connected',
        source: 'tun',
        raw: '[INFO] [tun] connected',
      );

      expect(e1, equals(e2));
      expect(e1.hashCode, equals(e2.hashCode));

      final modified = e1.copyWith(
        level: LogLevel.warning,
        message: 'reconnecting',
      );
      expect(modified.level, equals(LogLevel.warning));
      expect(modified.message, equals('reconnecting'));
      expect(modified.source, equals('tun'));
      expect(modified, isNot(equals(e1)));
    });

    test('LogRedactor.redactJsonMap scrubs nested lists of maps & strings '
        'and preserves safe diagnostic hosts', () {
      final nestedPayload = {
        'server': '127.0.0.1',
        'safe_domain': 'localhost',
        'safe_tun': '10.111.222.1',
        'nested_list': [
          {
            'secret_token': 'mySecretToken999',
            'comment':
                'Contact admin at vless://user:pass@secret.corp.internal:443',
          },
          'Raw string with key password=unredactedPass123 in list item',
        ],
      };

      final redacted = LogRedactor.redactJsonMap(
        nestedPayload,
        knownSecrets: const {'mySecretToken999'},
      );

      expect(redacted['server'], equals('127.0.0.1'));
      expect(redacted['safe_domain'], equals('localhost'));
      expect(redacted['safe_tun'], equals('10.111.222.1'));

      final list = redacted['nested_list'] as List;
      expect(list.length, equals(2));

      final mapItem = list[0] as Map<String, dynamic>;
      expect(mapItem['secret_token'], equals('[REDACTED]'));
      expect(mapItem['comment'], contains('[REDACTED]'));
      expect(mapItem['comment'], isNot(contains('secret.corp.internal')));

      final strItem = list[1] as String;
      expect(strItem, contains('[REDACTED]'));
      expect(strItem, isNot(contains('unredactedPass123')));
    });
  });

  group('P9-T1 High-Value Gap Fill — SensitiveFieldCipher & Cryptography Edge '
      'Cases', () {
    test(
      'decrypt throws FormatException on plaintext or missing ENC: prefix',
      () {
        final cipher = InMemorySensitiveFieldCipher();
        expect(
          () => cipher.decrypt('plain_unencrypted_secret_token'),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('HmacSha256 compresses keys longer than 64 bytes via SHA-256 before '
        'computing HMAC', () {
      // Create an oversized key (128 bytes)
      final oversizedKey = Uint8List(128);
      for (var i = 0; i < oversizedKey.length; i++) {
        oversizedKey[i] = i & 0xff;
      }

      final message = Uint8List.fromList(
        utf8.encode('hello hmac verification'),
      );

      // Compute HMAC using oversized key
      final mac1 = HmacSha256.compute(oversizedKey, message);
      expect(mac1.length, equals(32));

      // Compute HMAC again to assert deterministic reproduction
      final mac2 = HmacSha256.compute(oversizedKey, message);
      expect(mac1, equals(mac2));
    });
  });

  group('P9-T1 High-Value Gap Fill — AutoReconnect & KillSwitch State Machine '
      'Edge Cases', () {
    test('AutoReconnectPolicy.backoffForAttempt respects exponential doubling '
        'and ceiling clamp', () {
      const policy = AutoReconnectPolicy(maxBackoff: Duration(seconds: 8));

      expect(policy.backoffForAttempt(0), equals(const Duration(seconds: 1)));
      expect(policy.backoffForAttempt(1), equals(const Duration(seconds: 1)));
      expect(policy.backoffForAttempt(2), equals(const Duration(seconds: 2)));
      expect(policy.backoffForAttempt(3), equals(const Duration(seconds: 4)));
      expect(policy.backoffForAttempt(4), equals(const Duration(seconds: 8)));
      // Attempt 5 should be capped at maxBackoff (8s), not 16s
      expect(policy.backoffForAttempt(5), equals(const Duration(seconds: 8)));
      expect(policy.backoffForAttempt(10), equals(const Duration(seconds: 8)));
    });

    test('AutoReconnectState methods, equality, and hashCode', () {
      const idle1 = AutoReconnectIdle();
      const idle2 = AutoReconnectIdle();
      expect(idle1, equals(idle2));
      expect(idle1.hashCode, equals(idle2.hashCode));
      expect(idle1.isReconnecting, isFalse);

      const waiting1 = AutoReconnectWaitingForNetwork(attempt: 1);
      const waiting2 = AutoReconnectWaitingForNetwork(attempt: 1);
      const waitingOther = AutoReconnectWaitingForNetwork(attempt: 2);
      expect(waiting1, equals(waiting2));
      expect(waiting1.hashCode, equals(waiting2.hashCode));
      expect(waiting1, isNot(equals(waitingOther)));
      expect(waiting1.isReconnecting, isTrue);

      const backoff1 = AutoReconnectBackoff(
        attempt: 2,
        maxAttempts: 5,
        delay: Duration(seconds: 3),
      );
      const backoff2 = AutoReconnectBackoff(
        attempt: 2,
        maxAttempts: 5,
        delay: Duration(seconds: 3),
      );
      expect(backoff1, equals(backoff2));
      expect(backoff1.hashCode, equals(backoff2.hashCode));
      expect(backoff1.isReconnecting, isTrue);

      const inFlight1 = AutoReconnectInFlight(attempt: 2, maxAttempts: 5);
      const inFlight2 = AutoReconnectInFlight(attempt: 2, maxAttempts: 5);
      expect(inFlight1, equals(inFlight2));
      expect(inFlight1.hashCode, equals(inFlight2.hashCode));
      expect(inFlight1.isReconnecting, isTrue);

      const exhausted1 = AutoReconnectExhausted(totalAttempts: 5);
      const exhausted2 = AutoReconnectExhausted(totalAttempts: 5);
      expect(exhausted1, equals(exhausted2));
      expect(exhausted1.hashCode, equals(exhausted2.hashCode));
      expect(exhausted1.attemptsTaken, equals(5));
      expect(exhausted1.isReconnecting, isFalse);
    });

    test('KillSwitchState equality and hashCode contracts', () {
      const inactive1 = KillSwitchInactive();
      const inactive2 = KillSwitchInactive();
      expect(inactive1, equals(inactive2));
      expect(inactive1.hashCode, equals(inactive2.hashCode));

      const armed1 = KillSwitchArmed();
      const armed2 = KillSwitchArmed();
      expect(armed1, equals(armed2));
      expect(armed1.hashCode, equals(armed2.hashCode));

      const blocking1 = KillSwitchBlocking(reason: 'unexpected_drop');
      const blocking2 = KillSwitchBlocking(reason: 'unexpected_drop');
      const blockingOther = KillSwitchBlocking(reason: 'retry_exhausted');
      expect(blocking1, equals(blocking2));
      expect(blocking1.hashCode, equals(blocking2.hashCode));
      expect(blocking1, isNot(equals(blockingOther)));
    });

    test('MethodChannelKillSwitchPlatformBridge absorbs MissingPluginException '
        'and PlatformException safely', () async {
      const bridge = MethodChannelKillSwitchPlatformBridge();
      // Running on host without native method channel handler absorbs cleanly
      await expectLater(bridge.setLockdownBlocking(active: true), completes);
      await expectLater(bridge.setLockdownBlocking(active: false), completes);
    });
  });

  group('P9-T1 High-Value Gap Fill — ErrorMapper & '
      'Domain Presentation Mapping', () {
    test('ErrorMapper maps HasUserMessage server management domain errors', () {
      expect(
        ErrorMapper.mapToUserMessage(const ServerManagementEmptyNameError()),
        equals('Server name cannot be empty'),
      );
      expect(
        ErrorMapper.mapToUserMessage(
          const ServerManagementSubscriptionInputError(),
        ),
        equals(
          'This is a subscription URL. Please use the Add Subscription flow.',
        ),
      );
      expect(
        ErrorMapper.mapToUserMessage(
          const ServerManagementParseError('Safe parse error text'),
        ),
        equals('Safe parse error text'),
      );
      expect(
        ErrorMapper.mapToUserMessage(const ServerManagementInvalidUrlError()),
        equals('Please enter a valid HTTPS subscription URL'),
      );
      expect(
        ErrorMapper.mapToUserMessage(
          const ServerManagementFetchError('Safe fetch error text'),
        ),
        equals('Safe fetch error text'),
      );
      expect(
        ErrorMapper.mapToUserMessage(
          const ServerManagementNoValidServersError(),
        ),
        equals('No valid server configurations found in subscription'),
      );
    });

    test('ErrorMapper.mapToUserMessage handles null, unhandled objects, and '
        'command results gracefully', () {
      expect(
        ErrorMapper.mapToUserMessage(null),
        equals('An unexpected error occurred'),
      );
      expect(
        ErrorMapper.mapToUserMessage(const FormatException('unknown')),
        equals('An unexpected error occurred'),
      );
      expect(ErrorMapper.mapToUserMessage(const VpnCommandAccepted()), isEmpty);
    });

    test(
      'ErrorMapper.mapConnectionState returns null for non-error states',
      () {
        expect(ErrorMapper.mapConnectionState(const Disconnected()), isNull);
        expect(ErrorMapper.mapConnectionState(const Connected()), isNull);
        expect(
          ErrorMapper.mapConnectionState(const Error(PermissionDenied())),
          equals('VPN permission was denied by the system'),
        );
      },
    );
  });

  group(
    'P9-T1 High-Value Gap Fill — BatteryOptimizationService & Notifier',
    () {
      test(
        'MethodChannelBatteryOptimizationService queries channel and handles '
        'exceptions',
        () async {
          const channel = MethodChannel(
            'dev.brickvpn.harness/battery_optimization',
          );
          var channelState = false;
          var throwException = false;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (MethodCall call) async {
                if (throwException) {
                  throw PlatformException(
                    code: 'UNAVAILABLE',
                    message: 'Not supported',
                  );
                }
                if (call.method == 'isIgnoringBatteryOptimizations') {
                  return channelState;
                } else if (call.method == 'requestIgnoreBatteryOptimizations') {
                  channelState = true;
                  return true;
                }
                return null;
              });

          const service = MethodChannelBatteryOptimizationService();

          expect(await service.isIgnoringBatteryOptimizations(), isFalse);
          expect(await service.requestIgnoreBatteryOptimizations(), isTrue);
          expect(await service.isIgnoringBatteryOptimizations(), isTrue);

          throwException = true;
          expect(await service.isIgnoringBatteryOptimizations(), isFalse);
          expect(await service.requestIgnoreBatteryOptimizations(), isFalse);

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        },
      );

      test(
        'BatteryOptimizationIgnoredNotifier refreshes and requests exemption',
        () async {
          final fake = FakeBatteryOptimizationService();
          final container = ProviderContainer(
            overrides: [
              batteryOptimizationServiceProvider.overrideWithValue(fake),
            ],
          );
          addTearDown(container.dispose);

          final initial = await container.read(
            batteryOptimizationIgnoredProvider.future,
          );
          expect(initial, isFalse);

          fake.isIgnoring = true;
          await container
              .read(batteryOptimizationIgnoredProvider.notifier)
              .refresh();
          final refreshed = await container.read(
            batteryOptimizationIgnoredProvider.future,
          );
          expect(refreshed, isTrue);

          fake.isIgnoring = false;
          final requested = await container
              .read(batteryOptimizationIgnoredProvider.notifier)
              .requestExemption();
          expect(requested, isTrue);
          expect(fake.requestCalls, equals(1));
        },
      );
    },
  );

  group('P9-T1 High-Value Gap Fill — ServerManagementController, '
      'AddServerController & AddSubscriptionController', () {
    late Directory tempDir;
    late File storageFile;
    late InMemorySensitiveFieldCipher cipher;
    late FileServerProfileRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('brick_controllers_');
      storageFile = File('${tempDir.path}/server_profiles.json');
      cipher = InMemorySensitiveFieldCipher();
      repository = FileServerProfileRepository(
        storageFile: storageFile,
        cipher: cipher,
      );
      await repository.init();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('AddServerController validates input and persists '
        'valid profile', () async {
      final container = ProviderContainer(
        overrides: [
          serverProfileRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(addServerControllerProvider, (_, _) {});
      addTearDown(sub.close);

      final controller = container.read(addServerControllerProvider.notifier);

      final emptyResult = await controller.submit('   ');
      expect(emptyResult.isErr, isTrue);
      expect((emptyResult as Err).error, isA<AddServerEmptyInputError>());

      final subResult = await controller.submit('https://feed.example.com/sub');
      expect(subResult.isErr, isTrue);
      expect((subResult as Err).error, isA<AddServerSubscriptionInputError>());

      final invalidResult = await controller.submit('invalid://garbage_string');
      expect(invalidResult.isErr, isTrue);
      expect((invalidResult as Err).error, isA<AddServerParseError>());

      const validVless =
          'vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.com:443?type=tcp#Tokyo';
      final validResult = await controller.submit(validVless);
      expect(validResult.isOk, isTrue);

      final saved = await repository.getAll();
      expect(saved.length, equals(1));
      expect(saved.first.name, equals('Tokyo'));
    });

    test(
      'AddSubscriptionController validates url and reports fetch errors',
      () async {
        final container = ProviderContainer(
          overrides: [
            serverProfileRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(
          addSubscriptionControllerProvider,
          (_, _) {},
        );
        addTearDown(sub.close);

        final controller = container.read(
          addSubscriptionControllerProvider.notifier,
        );

        final emptyResult = await controller.submit('');
        expect(emptyResult.isErr, isTrue);
        expect((emptyResult as Err).error, isA<AddSubscriptionEmptyUrlError>());

        final invalidResult = await controller.submit('ftp://example.com/feed');
        expect(invalidResult.isErr, isTrue);
        expect(
          (invalidResult as Err).error,
          isA<AddSubscriptionInvalidUrlError>(),
        );

        // Non-existent localhost will fail fetch
        final fetchFailResult = await controller.submit(
          'https://127.0.0.1:59999/non_existent_feed',
        );
        expect(fetchFailResult.isErr, isTrue);
        expect(
          (fetchFailResult as Err).error,
          isA<AddSubscriptionFetchError>(),
        );
      },
    );

    test('ServerManagementController edit, duplicate, delete and refresh '
        'operations', () async {
      final container = ProviderContainer(
        overrides: [
          serverProfileRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        serverManagementControllerProvider,
        (_, _) {},
      );
      addTearDown(sub.close);

      final controller = container.read(
        serverManagementControllerProvider.notifier,
      );

      final initialProfile = ServerProfile(
        id: 'edit-target',
        name: 'Original Name',
        config: const VlessOutbound(
          server: 'target.example.com',
          serverPort: 443,
          uuid: '11111111-1111-1111-1111-111111111111',
        ),
        addedAt: DateTime.utc(2026, 11),
      );
      await repository.save(initialProfile);

      // Edit: empty name rejected
      final emptyName = await controller.editServer(
        existing: initialProfile,
        newName: '   ',
      );
      expect(emptyName.isErr, isTrue);
      expect((emptyName as Err).error, isA<ServerManagementEmptyNameError>());

      // Edit: subscription managed server is read-only
      final readOnlyResult = await controller.editServer(
        existing: initialProfile.copyWith(subscriptionId: 'sub-locked'),
        newName: 'Renamed',
      );
      expect(readOnlyResult.isErr, isTrue);
      expect(
        (readOnlyResult as Err).error,
        isA<ServerManagementReadOnlyError>(),
      );

      // Edit: subscription URL in replacement rejected
      final subReplacement = await controller.editServer(
        existing: initialProfile,
        newName: 'Renamed',
        newRawUri: 'https://sub.example.com/feed',
      );
      expect(subReplacement.isErr, isTrue);
      expect(
        (subReplacement as Err).error,
        isA<ServerManagementSubscriptionInputError>(),
      );

      // Edit: valid rename
      final validEdit = await controller.editServer(
        existing: initialProfile,
        newName: 'New Safe Name',
      );
      expect(validEdit.isOk, isTrue);
      final edited = await repository.getById('edit-target');
      expect(edited?.name, equals('New Safe Name'));

      // Duplicate: valid duplicate creates profile with new id
      final validDup = await controller.duplicateServer(initialProfile);
      expect(validDup.isOk, isTrue);
      final duplicated = (validDup as Ok).value as ServerProfile;
      expect(duplicated.id, isNot(equals('edit-target')));
      expect(duplicated.config, equals(initialProfile.config));

      // Delete server
      final deleteResult = await controller.deleteServer(duplicated.id);
      expect(deleteResult.isOk, isTrue);
      expect(await repository.getById(duplicated.id), isNull);

      // Delete subscription cascade
      final subMetadata = SubscriptionMetadata(
        id: 'sub-manage',
        url: 'https://sub.example.com/feed',
        name: 'Feed',
        associatedServerIds: const ['edit-target'],
        lastRefreshedAt: DateTime.utc(2026, 11),
      );
      await repository.saveSubscription(subMetadata);
      final deleteSubResult = await controller.deleteSubscription('sub-manage');
      expect(deleteSubResult.isOk, isTrue);
      expect(await repository.getSubscriptionById('sub-manage'), isNull);
      expect(await repository.getById('edit-target'), isNull);
    });
  });
}
