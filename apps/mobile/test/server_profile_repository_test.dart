// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/servers/data/repositories/file_server_profile_repository.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';

void main() {
  late Directory tempDir;
  late File storageFile;
  late FileServerProfileRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('brick_p5t1_test_');
    storageFile = File('${tempDir.path}/server_profiles.json');
    repository = FileServerProfileRepository(storageFile: storageFile);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  final vlessProfile = ServerProfile(
    id: 'vless-1',
    name: 'VLESS Primary',
    config: VlessOutbound(
      server: 'vless.example.com',
      serverPort: 443,
      uuid: '11111111-2222-3333-4444-555555555555',
      flow: 'xtls-rprx-vision',
      tls: TlsSettings(enabled: true, serverName: 'vless.example.com'),
    ),
    addedAt: DateTime.utc(2026, 10, 31, 1),
    lastUsedAt: DateTime.utc(2026, 10, 31, 2),
    subscriptionId: 'sub-1',
  );

  final trojanProfile = ServerProfile(
    id: 'trojan-1',
    name: 'Trojan Node',
    config: TrojanOutbound(
      server: 'trojan.example.com',
      serverPort: 443,
      password: 'trojan-secret-password',
      tls: TlsSettings(enabled: true, serverName: 'trojan.example.com'),
    ),
    addedAt: DateTime.utc(2026, 10, 31, 1, 30),
  );

  final ssProfile = ServerProfile(
    id: 'ss-1',
    name: 'Shadowsocks Node',
    config: const ShadowsocksOutbound(
      server: 'ss.example.com',
      serverPort: 8388,
      method: 'aes-256-gcm',
      password: 'ss-secret-password',
    ),
    addedAt: DateTime.utc(2026, 10, 31, 1, 45),
  );

  final wgProfile = ServerProfile(
    id: 'wg-1',
    name: 'WireGuard Peer',
    config: WireGuardOutbound(
      server: 'wg.example.com',
      serverPort: 51820,
      privateKey: 'aW52YWxpZC1wcml2YXRlLWtleS0xMjM0NTY3ODkwMTI=',
      peerPublicKey: 'aW52YWxpZC1wdWJsaWMta2V5LTEyMzQ1Njc4OTAxMg==',
      localAddresses: const ['10.0.0.2/32'],
    ),
    addedAt: DateTime.utc(2026, 10, 31, 2),
  );

  final vmessProfile = ServerProfile(
    id: 'vmess-1',
    name: 'VMess Node',
    config: const VmessOutbound(
      server: 'vmess.example.com',
      serverPort: 443,
      uuid: '22222222-3333-4444-5555-666666666666',
    ),
    addedAt: DateTime.utc(2026, 10, 31, 2, 15),
  );

  final hy2Profile = ServerProfile(
    id: 'hy2-1',
    name: 'Hysteria2 Node',
    config: Hysteria2Outbound(
      server: 'hy2.example.com',
      serverPort: 443,
      password: 'hy2-secret-password',
      tls: TlsSettings(enabled: true, serverName: 'hy2.example.com'),
    ),
    addedAt: DateTime.utc(2026, 10, 31, 2, 30),
  );

  final tuicProfile = ServerProfile(
    id: 'tuic-1',
    name: 'TUIC Node',
    config: TuicOutbound(
      server: 'tuic.example.com',
      serverPort: 8443,
      uuid: '33333333-4444-5555-6666-777777777777',
      password: 'tuic-secret-password',
      tls: TlsSettings(enabled: true, serverName: 'tuic.example.com'),
    ),
    addedAt: DateTime.utc(2026, 10, 31, 2, 45),
  );

  final awgProfile = ServerProfile(
    id: 'awg-1',
    name: 'AmneziaWG Node',
    config: AmneziaWgOutbound(
      server: 'awg.example.com',
      serverPort: 51820,
      privateKey: 'aW52YWxpZC1wcml2YXRlLWtleS0xMjM0NTY3ODkwMTI=',
      peerPublicKey: 'aW52YWxpZC1wdWJsaWMta2V5LTEyMzQ1Njc4OTAxMg==',
      localAddresses: const ['10.0.0.3/32'],
      jc: 4,
      jmin: 40,
      jmax: 70,
      s1: 15,
      s2: 25,
      h1: 12345678,
      h2: 23456789,
      h3: 34567890,
      h4: 45678901,
    ),
    addedAt: DateTime.utc(2026, 10, 31, 3),
  );

  final allProfiles = <ServerProfile>[
    vlessProfile,
    trojanProfile,
    ssProfile,
    wgProfile,
    vmessProfile,
    hy2Profile,
    tuicProfile,
    awgProfile,
  ];

  final testSub = SubscriptionMetadata(
    id: 'sub-1',
    url: 'https://example.com/api/sub?token=secret123',
    name: 'Primary Subscription',
    lastRefreshedAt: DateTime.utc(2026, 10, 31),
    associatedServerIds: const ['vless-1', 'trojan-1'],
    userInfo: const SubscriptionUserInfo(
      uploadBytes: 1024,
      downloadBytes: 2048,
      totalBytes: 1000000000,
    ),
  );

  group('ServerProfile CRUD & multi-protocol support (all 8 protocols)', () {
    test('starts with empty list when file does not exist', () async {
      expect(await repository.getAll(), isEmpty);
      expect(storageFile.existsSync(), isFalse);
    });

    test('supports full CRUD across all 8 outbound protocols', () async {
      // Create / Save all 8 protocols
      for (final profile in allProfiles) {
        await repository.save(profile);
      }

      // Read List
      final all = await repository.getAll();
      expect(all, hasLength(8));
      for (var i = 0; i < allProfiles.length; i++) {
        expect(all[i], equals(allProfiles[i]));
      }

      // Read Single
      final fetched = await repository.getById('trojan-1');
      expect(fetched, equals(trojanProfile));
      expect(await repository.getById('non-existent'), isNull);

      // Update
      final updated = trojanProfile.copyWith(name: 'Updated Trojan Name');
      await repository.save(updated);
      expect(await repository.getById('trojan-1'), equals(updated));
      expect((await repository.getAll()).length, equals(8));

      // Delete
      await repository.delete('ss-1');
      expect(await repository.getById('ss-1'), isNull);
      expect((await repository.getAll()).length, equals(7));
    });
  });

  group('Persistence & Re-instantiation across all 8 protocols', () {
    test('all 8 protocols survive re-instantiation identically', () async {
      for (final profile in allProfiles) {
        await repository.save(profile);
      }

      // Second repository pointing to the same file
      final repo2 = FileServerProfileRepository(storageFile: storageFile);
      await repo2.init();

      final reloaded = await repo2.getAll();
      expect(reloaded, hasLength(8));
      expect(reloaded[0].config, isA<VlessOutbound>());
      expect(reloaded[1].config, isA<TrojanOutbound>());
      expect(reloaded[2].config, isA<ShadowsocksOutbound>());
      expect(reloaded[3].config, isA<WireGuardOutbound>());
      expect(reloaded[4].config, isA<VmessOutbound>());
      expect(reloaded[5].config, isA<Hysteria2Outbound>());
      expect(reloaded[6].config, isA<TuicOutbound>());
      expect(reloaded[7].config, isA<AmneziaWgOutbound>());

      for (var i = 0; i < allProfiles.length; i++) {
        expect(reloaded[i], equals(allProfiles[i]));
      }
    });

    test('writes version 1 envelope to disk', () async {
      await repository.save(vlessProfile);
      await repository.saveSubscription(testSub);

      expect(storageFile.existsSync(), isTrue);
      final dynamic decoded = jsonDecode(await storageFile.readAsString());
      expect(decoded, isA<Map<String, dynamic>>());
      final raw = decoded as Map<String, dynamic>;
      expect(raw['schema_version'], equals(1));
      expect(raw['updated_at'], isA<String>());
      final profiles = raw['server_profiles'] as List<dynamic>;
      expect(profiles, hasLength(1));
      final subscriptions = raw['subscriptions'] as List<dynamic>;
      expect(subscriptions, hasLength(1));
    });
  });

  group('Broken servers persistence (Defect D4)', () {
    test('persists and restores broken servers across restarts', () async {
      final envelopeWithBroken = {
        'schema_version': 1,
        'updated_at': DateTime.utc(2026, 10, 31).toIso8601String(),
        'server_profiles': [vlessProfile.toJson()],
        'subscriptions': <dynamic>[],
        'broken_servers': {'broken-1': 'Invalid outbound format'},
      };
      await storageFile.writeAsString(jsonEncode(envelopeWithBroken));

      final repo1 = FileServerProfileRepository(storageFile: storageFile);
      await repo1.init();

      final servers1 = await repo1.loadServers();
      expect(servers1, hasLength(2));
      expect(servers1.any((s) => s is SavedServerBroken), isTrue);

      // Mutate repository: add another profile, saving to disk
      await repo1.save(trojanProfile);

      // Re-instantiate repo2 and verify broken servers were not wiped
      final repo2 = FileServerProfileRepository(storageFile: storageFile);
      await repo2.init();

      final servers2 = await repo2.loadServers();
      expect(servers2, hasLength(3));
      final broken = servers2.whereType<SavedServerBroken>().single;
      expect(broken.id, equals('broken-1'));
      expect(broken.reason, equals('Invalid outbound format'));
    });
  });

  group('Concurrency and race control (Defect D3)', () {
    test('concurrent init and write operations complete safely', () async {
      // Fire concurrent reads and writes simultaneously
      await Future.wait([
        repository.init(),
        repository.save(vlessProfile),
        repository.save(trojanProfile),
        repository.getAll(),
        repository.saveSubscription(testSub),
      ]);

      final all = await repository.getAll();
      expect(all, hasLength(2));
      expect(await repository.getAllSubscriptions(), hasLength(1));
    });
  });

  group('SubscriptionMetadata CRUD & round-trip', () {
    test('supports full CRUD and re-instantiation round-trip', () async {
      await repository.saveSubscription(testSub);

      // Read single
      final fetched = await repository.getSubscriptionById('sub-1');
      expect(fetched, equals(testSub));
      expect(fetched?.userInfo?.usedBytes, equals(3072));

      // Read all
      final all = await repository.getAllSubscriptions();
      expect(all, hasLength(1));
      expect(all.single, equals(testSub));

      // Re-instantiate
      final repo2 = FileServerProfileRepository(storageFile: storageFile);
      await repo2.init();
      expect(await repo2.getSubscriptionById('sub-1'), equals(testSub));

      // Update
      final updated = testSub.copyWith(name: 'Updated Subscription');
      await repository.saveSubscription(updated);
      expect(await repository.getSubscriptionById('sub-1'), equals(updated));

      // Delete
      await repository.deleteSubscription('sub-1');
      expect(await repository.getSubscriptionById('sub-1'), isNull);
      expect(await repository.getAllSubscriptions(), isEmpty);
    });

    test(
      'saveSubscriptionWithProfiles saves subscription and profiles atomically '
      'and survives re-instantiation',
      () async {
        final profiles = [vlessProfile, trojanProfile];
        await repository.saveSubscriptionWithProfiles(testSub, profiles);

        final loadedSub = await repository.getSubscriptionById('sub-1');
        expect(loadedSub, equals(testSub));

        final loadedProfiles = await repository.getAll();
        expect(loadedProfiles, hasLength(2));
        expect(loadedProfiles, containsAll([vlessProfile, trojanProfile]));

        // Re-instantiate repo from disk
        final repo2 = FileServerProfileRepository(storageFile: storageFile);
        await repo2.init();
        expect(await repo2.getSubscriptionById('sub-1'), equals(testSub));
        final reloadedProfiles = await repo2.getAll();
        expect(reloadedProfiles, hasLength(2));
        expect(reloadedProfiles, containsAll([vlessProfile, trojanProfile]));
      },
    );

    test('replaceSubscriptionProfiles atomically replaces profiles and updates '
        'subscription surviving re-instantiation', () async {
      // Initial setup: save subscription with 2 profiles
      await repository.saveSubscriptionWithProfiles(testSub, [
        vlessProfile,
        trojanProfile,
      ]);
      expect(await repository.getAll(), hasLength(2));

      // Create replacement: 1 profile (ssProfile tagged with sub-1)
      final newProfile = ssProfile.copyWith(subscriptionId: 'sub-1');
      final updatedSub = testSub.copyWith(
        name: 'Refreshed Subscription',
        associatedServerIds: [newProfile.id],
        lastRefreshedAt: DateTime.utc(2026, 11, 2),
      );

      await repository.replaceSubscriptionProfiles(updatedSub, [newProfile]);

      // Verify in-memory state
      final fetchedSub = await repository.getSubscriptionById('sub-1');
      expect(fetchedSub?.name, equals('Refreshed Subscription'));
      expect(fetchedSub?.associatedServerIds, equals([newProfile.id]));

      final fetchedProfiles = await repository.getAll();
      expect(fetchedProfiles, hasLength(1));
      expect(fetchedProfiles.single.id, equals(newProfile.id));

      // Re-instantiate repository from disk and verify persistence
      final repo2 = FileServerProfileRepository(storageFile: storageFile);
      await repo2.init();

      final reloadedSub = await repo2.getSubscriptionById('sub-1');
      expect(reloadedSub?.name, equals('Refreshed Subscription'));
      expect(reloadedSub?.associatedServerIds, equals([newProfile.id]));

      final reloadedProfiles = await repo2.getAll();
      expect(reloadedProfiles, hasLength(1));
      expect(reloadedProfiles.single.id, equals(newProfile.id));
    });

    test(
      'deleteSubscriptionCascade atomically removes subscription and all its '
      'profiles surviving re-instantiation',
      () async {
        // Save subscription with 2 profiles
        await repository.saveSubscriptionWithProfiles(testSub, [
          vlessProfile,
          trojanProfile,
        ]);
        // Also save an independent standalone profile
        await repository.save(ssProfile);
        expect(await repository.getAll(), hasLength(3));

        // Cascade delete the subscription
        await repository.deleteSubscriptionCascade('sub-1');

        // Subscription and its profiles are removed, standalone remains
        expect(await repository.getSubscriptionById('sub-1'), isNull);
        final remaining = await repository.getAll();
        expect(remaining, hasLength(1));
        expect(remaining.single.id, equals(ssProfile.id));

        // Re-instantiate repository from disk and verify persistence
        final repo2 = FileServerProfileRepository(storageFile: storageFile);
        await repo2.init();

        expect(await repo2.getSubscriptionById('sub-1'), isNull);
        final reloaded = await repo2.getAll();
        expect(reloaded, hasLength(1));
        expect(reloaded.single.id, equals(ssProfile.id));
      },
    );
  });

  group('Graceful error recovery', () {
    test('recovers cleanly from corrupt JSON without throwing', () async {
      await storageFile.writeAsString('{ invalid json syntax');
      final repo = FileServerProfileRepository(storageFile: storageFile);
      await repo.init();

      expect(await repo.getAll(), isEmpty);
      expect(await repo.getAllSubscriptions(), isEmpty);

      // Should be able to write normally after recovery
      await repo.save(vlessProfile);
      expect(await repo.getAll(), hasLength(1));
    });

    test('recovers cleanly from non-Map payload', () async {
      await storageFile.writeAsString('[1, 2, 3]');
      final repo = FileServerProfileRepository(storageFile: storageFile);
      await repo.init();

      expect(await repo.getAll(), isEmpty);
    });

    test('recovers cleanly from unsupported schema version', () async {
      final invalidSchema = {
        'schema_version': 99,
        'server_profiles': [vlessProfile.toJson()],
      };
      await storageFile.writeAsString(jsonEncode(invalidSchema));

      final repo = FileServerProfileRepository(storageFile: storageFile);
      await repo.init();

      expect(await repo.getAll(), isEmpty);
    });
  });

  group('Legacy compatibility & security (Defect D1)', () {
    test(
      'addServer parses and persists, loadServers returns SavedServerProfile',
      () async {
        const uri =
            'vless://11111111-2222-3333-4444-555555555555@example.com:443#Test';
        await repository.addServer(uri);

        final loaded = await repository.loadServers();
        expect(loaded, hasLength(1));
        expect(loaded.first, isA<SavedServerProfile>());

        final profile = (loaded.first as SavedServerProfile).profile;
        expect(profile.name, equals('Test'));
        expect(profile.config.server, equals('example.com'));

        await repository.removeServer(profile.id);
        expect(await repository.loadServers(), isEmpty);
      },
    );

    test(
      'addServer rejects invalid URI with safe ArgumentError (no URI leak)',
      () async {
        const sensitiveUri =
            'invalid://user:super_secret_token@example.com:443';
        expect(
          () => repository.addServer(sensitiveUri),
          throwsA(
            isA<ArgumentError>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Refusing to persist an unparseable server URI'),
                )
                .having(
                  (e) => e.toString(),
                  'toString',
                  isNot(contains('super_secret_token')),
                ),
          ),
        );
      },
    );
  });
}
