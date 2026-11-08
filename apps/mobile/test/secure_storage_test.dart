// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/security/sensitive_field_cipher.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/servers/data/repositories/file_server_profile_repository.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';

import 'localization_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File storageFile;
  late InMemorySensitiveFieldCipher cipher;
  late FileServerProfileRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('brick_p8t1_test_');
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

  // Test profiles for all 8 supported protocols with sensitive secrets
  final vlessRealityProfile = ServerProfile(
    id: 'vless-reality-1',
    name: 'VLESS Reality Node',
    config: VlessOutbound(
      server: 'vless.reality.example.com',
      serverPort: 443,
      uuid: '11111111-2222-3333-4444-555555555555',
      flow: 'xtls-rprx-vision',
      tls: TlsSettings(
        enabled: true,
        serverName: 'vless.reality.example.com',
        reality: const RealitySettings(
          enabled: true,
          publicKey: 'reality-public-key-secret-12345',
          shortId: 'reality-short-id-secret-6789',
        ),
      ),
    ),
    addedAt: DateTime.utc(2026, 11, 7, 1),
  );

  final vmessProfile = ServerProfile(
    id: 'vmess-1',
    name: 'VMess Secret Node',
    config: const VmessOutbound(
      server: 'vmess.example.com',
      serverPort: 443,
      uuid: '22222222-3333-4444-5555-666666666666',
    ),
    addedAt: DateTime.utc(2026, 11, 7, 1, 10),
  );

  final trojanProfile = ServerProfile(
    id: 'trojan-1',
    name: 'Trojan Secret Node',
    config: TrojanOutbound(
      server: 'trojan.example.com',
      serverPort: 443,
      password: 'trojan-secret-password-xyz',
      tls: TlsSettings(enabled: true, serverName: 'trojan.example.com'),
    ),
    addedAt: DateTime.utc(2026, 11, 7, 1, 20),
  );

  final ssProfile = ServerProfile(
    id: 'ss-1',
    name: 'Shadowsocks Secret Node',
    config: const ShadowsocksOutbound(
      server: 'ss.example.com',
      serverPort: 8388,
      method: 'aes-256-gcm',
      password: 'ss-secret-password-abc',
    ),
    addedAt: DateTime.utc(2026, 11, 7, 1, 30),
  );

  final hy2Profile = ServerProfile(
    id: 'hy2-1',
    name: 'Hysteria2 Secret Node',
    config: Hysteria2Outbound(
      server: 'hy2.example.com',
      serverPort: 443,
      password: 'hy2-secret-password-auth',
      obfsType: 'salamander',
      obfsPassword: 'hy2-obfs-secret-password',
      tls: TlsSettings(enabled: true, serverName: 'hy2.example.com'),
    ),
    addedAt: DateTime.utc(2026, 11, 7, 1, 40),
  );

  final tuicProfile = ServerProfile(
    id: 'tuic-1',
    name: 'TUIC Secret Node',
    config: TuicOutbound(
      server: 'tuic.example.com',
      serverPort: 8443,
      uuid: '33333333-4444-5555-6666-777777777777',
      password: 'tuic-secret-password-def',
      tls: TlsSettings(enabled: true, serverName: 'tuic.example.com'),
    ),
    addedAt: DateTime.utc(2026, 11, 7, 1, 50),
  );

  final wgProfile = ServerProfile(
    id: 'wg-1',
    name: 'WireGuard Secret Node',
    config: WireGuardOutbound(
      server: 'wg.example.com',
      serverPort: 51820,
      privateKey: 'wg-secret-private-key-12345678901=',
      peerPublicKey: 'aW52YWxpZC1wdWJsaWMta2V5LTEyMzQ1Njc4OTAxMg==',
      presharedKey: 'wg-secret-psk-123456789012345678=',
      localAddresses: const ['10.0.0.2/32'],
    ),
    addedAt: DateTime.utc(2026, 11, 7, 2),
  );

  final awgProfile = ServerProfile(
    id: 'awg-1',
    name: 'AmneziaWG Secret Node',
    config: AmneziaWgOutbound(
      server: 'awg.example.com',
      serverPort: 51820,
      privateKey: 'awg-secret-private-key-1234567890=',
      peerPublicKey: 'aW52YWxpZC1wdWJsaWMta2V5LTEyMzQ1Njc4OTAxMg==',
      presharedKey: 'awg-secret-psk-123456789012345678=',
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
    addedAt: DateTime.utc(2026, 11, 7, 2, 10),
  );

  const secretSub = SubscriptionMetadata(
    id: 'sub-secret-1',
    url: 'https://example.com/api/sub?token=super-secret-user-uuid-token',
    name: 'Premium Subscription',
  );

  final all8Profiles = [
    vlessRealityProfile,
    vmessProfile,
    trojanProfile,
    ssProfile,
    hy2Profile,
    tuicProfile,
    wgProfile,
    awgProfile,
  ];

  final sensitiveStrings = [
    '11111111-2222-3333-4444-555555555555',
    'reality-public-key-secret-12345',
    'reality-short-id-secret-6789',
    '22222222-3333-4444-5555-666666666666',
    'trojan-secret-password-xyz',
    'ss-secret-password-abc',
    'hy2-secret-password-auth',
    'hy2-obfs-secret-password',
    '33333333-4444-5555-6666-777777777777',
    'tuic-secret-password-def',
    'wg-secret-private-key-12345678901=',
    'wg-secret-psk-123456789012345678=',
    'awg-secret-private-key-1234567890=',
    'awg-secret-psk-123456789012345678=',
    'super-secret-user-uuid-token',
  ];

  group('P8-T1 Secure Storage for Sensitive Server Fields Test Suite', () {
    test(
      'Scenario 1: All 8 protocols zero-plaintext-at-rest verification',
      () async {
        for (final profile in all8Profiles) {
          await repository.save(profile);
        }
        await repository.saveSubscription(secretSub);

        expect(storageFile.existsSync(), isTrue);
        final rawFileContent = await storageFile.readAsString();

        // 1. Assert NONE of the sensitive secrets appear in the on-disk file
        for (final secret in sensitiveStrings) {
          expect(
            rawFileContent.contains(secret),
            isFalse,
            reason: 'Secret "$secret" must never be written in plaintext!',
          );
        }

        // 2. Assert non-sensitive fields ARE visible in plaintext for query
        // efficiency without decryption round-trip
        for (final profile in all8Profiles) {
          expect(rawFileContent.contains(profile.id), isTrue);
          expect(rawFileContent.contains(profile.name), isTrue);
          expect(rawFileContent.contains(profile.config.server), isTrue);
          expect(
            rawFileContent.contains(profile.config.serverPort.toString()),
            isTrue,
          );
        }
        expect(rawFileContent.contains(secretSub.id), isTrue);
        expect(rawFileContent.contains(secretSub.name), isTrue);

        // 3. Inspect JSON structure directly to confirm enc:v1: prefixes
        final dynamic decoded = jsonDecode(rawFileContent);
        expect(decoded, isA<Map<String, dynamic>>());
        final map = decoded as Map<String, dynamic>;
        expect(map['schema_version'], equals(2));

        final profiles = map['server_profiles'] as List<dynamic>;
        expect(profiles, hasLength(8));
        for (final p in profiles) {
          final pMap = p as Map<String, dynamic>;
          final config = pMap['config'] as Map<String, dynamic>;
          final type = config['type'] as String;

          if (type == 'vless') {
            expect((config['uuid'] as String).startsWith('enc:v1:'), isTrue);
            final reality =
                (config['tls'] as Map<String, dynamic>)['reality']
                    as Map<String, dynamic>;
            expect(
              (reality['public_key'] as String).startsWith('enc:v1:'),
              isTrue,
            );
            expect(
              (reality['short_id'] as String).startsWith('enc:v1:'),
              isTrue,
            );
          } else if (type == 'vmess') {
            expect((config['uuid'] as String).startsWith('enc:v1:'), isTrue);
          } else if (type == 'trojan' ||
              type == 'shadowsocks' ||
              type == 'ss') {
            expect(
              (config['password'] as String).startsWith('enc:v1:'),
              isTrue,
            );
          } else if (type == 'hysteria2') {
            expect(
              (config['password'] as String).startsWith('enc:v1:'),
              isTrue,
            );
            final obfs = config['obfs'] as Map<String, dynamic>;
            expect((obfs['password'] as String).startsWith('enc:v1:'), isTrue);
          } else if (type == 'tuic') {
            expect((config['uuid'] as String).startsWith('enc:v1:'), isTrue);
            expect(
              (config['password'] as String).startsWith('enc:v1:'),
              isTrue,
            );
          } else if (type == 'wireguard' || type == 'amneziawg') {
            expect(
              (config['private_key'] as String).startsWith('enc:v1:'),
              isTrue,
            );
            expect(
              (config['pre_shared_key'] as String).startsWith('enc:v1:'),
              isTrue,
            );
            expect(
              (config['peer_public_key'] as String).startsWith('enc:v1:'),
              isTrue,
            );
          } else {
            fail('Unexpected unverified protocol type: $type');
          }
        }

        final subscriptions = map['subscriptions'] as List<dynamic>;
        expect(subscriptions, hasLength(1));
        final subMap = subscriptions.first as Map<String, dynamic>;
        expect((subMap['url'] as String).startsWith('enc:v1:'), isTrue);
      },
    );

    test(
      'Scenario 2: Full decryption round-trip across all 8 protocols',
      () async {
        for (final profile in all8Profiles) {
          await repository.save(profile);
        }
        await repository.saveSubscription(secretSub);

        // Re-instantiate repository targeting same file
        final repo2 = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );
        await repo2.init();

        final reloadedProfiles = await repo2.getAll();
        expect(reloadedProfiles, hasLength(8));

        for (var i = 0; i < all8Profiles.length; i++) {
          expect(
            reloadedProfiles[i],
            equals(all8Profiles[i]),
            reason: 'Profile ${all8Profiles[i].name} must decrypt identically!',
          );
        }

        final reloadedSub = await repo2.getSubscriptionById(secretSub.id);
        expect(reloadedSub, equals(secretSub));
        expect(reloadedSub?.url, equals(secretSub.url));

        // Assert decrypted profile can be passed to VpnEngine
        final fakeEngine = FakeVpnEngine();
        final startResult = await fakeEngine.start(reloadedProfiles.first);
        expect(startResult, isA<VpnCommandAccepted>());
        expect(fakeEngine.startCalls, contains(reloadedProfiles.first));
      },
    );

    test('Scenario 3: Automatic schema v1 -> v2 migration with plaintext '
        'elimination', () async {
      // Construct legacy schema 1 JSON file with raw plaintext secrets
      final legacyV1Payload = <String, dynamic>{
        'schema_version': 1,
        'updated_at': DateTime.utc(2026, 10, 31).toIso8601String(),
        'server_profiles': [
          vlessRealityProfile.toJson(),
          trojanProfile.toJson(),
        ],
        'subscriptions': [secretSub.toJson()],
        'broken_servers': <String, dynamic>{},
      };

      await storageFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(legacyV1Payload),
        flush: true,
      );

      // Before migration: file contains plaintext passwords and tokens
      var rawContent = await storageFile.readAsString();
      expect(rawContent.contains('trojan-secret-password-xyz'), isTrue);
      expect(rawContent.contains('super-secret-user-uuid-token'), isTrue);
      expect(rawContent.contains('"schema_version": 1'), isTrue);

      // Load repository (triggers automatic migration)
      final migratorRepo = FileServerProfileRepository(
        storageFile: storageFile,
        cipher: cipher,
      );
      await migratorRepo.init();

      final loaded = await migratorRepo.getAll();
      expect(loaded, hasLength(2));
      expect(loaded[0], equals(vlessRealityProfile));
      expect(loaded[1], equals(trojanProfile));

      final loadedSub = await migratorRepo.getSubscriptionById(secretSub.id);
      expect(loadedSub, equals(secretSub));

      // After migration: file rewritten to schema 2 and plaintext is gone!
      rawContent = await storageFile.readAsString();
      expect(rawContent.contains('trojan-secret-password-xyz'), isFalse);
      expect(rawContent.contains('super-secret-user-uuid-token'), isFalse);
      expect(rawContent.contains('"schema_version": 2'), isTrue);
      expect(rawContent.contains('enc:v1:'), isTrue);
    });

    test(
      'Scenario 4: Tamper / authentication failure resilience fails closed to '
      'broken server',
      () async {
        await repository.save(vlessRealityProfile);
        await repository.save(trojanProfile);

        // Read raw JSON, locate Trojan encrypted password, tamper with 1 char
        final content = await storageFile.readAsString();
        final dynamic decoded = jsonDecode(content);
        final map = decoded as Map<String, dynamic>;
        final profiles = map['server_profiles'] as List<dynamic>;

        final trojanMap = profiles[1] as Map<String, dynamic>;
        final config = trojanMap['config'] as Map<String, dynamic>;
        final originalCiphertext = config['password'] as String;

        // Tamper with one base64 character in ciphertext
        final lastChar = originalCiphertext[originalCiphertext.length - 1];
        final tamperedChar = (lastChar == 'A') ? 'B' : 'A';
        final tamperedCiphertext =
            originalCiphertext.substring(0, originalCiphertext.length - 1) +
            tamperedChar;
        config['password'] = tamperedCiphertext;

        await storageFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(map),
          flush: true,
        );

        // Reload repository
        final reloadRepo = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );
        await reloadRepo.init();

        // Valid VLESS server still loads cleanly
        final validProfiles = await reloadRepo.getAll();
        expect(validProfiles, hasLength(1));
        expect(validProfiles.single.id, equals('vless-reality-1'));

        // Tampered Trojan server surfaces safely as broken server
        final servers = await reloadRepo.loadServers();
        expect(servers, hasLength(2));
        final broken = servers.whereType<SavedServerBroken>().single;
        expect(broken.id, equals('trojan-1'));
        expect(broken.reason, contains('Decryption failed'));
      },
    );

    test(
      'Scenario 5: MethodChannel AndroidKeystoreSensitiveFieldCipher bridge',
      () async {
        const channel = MethodChannel('dev.brickvpn.harness/secure_storage');
        final log = <MethodCall>[];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              log.add(call);
              final args = call.arguments as Map<dynamic, dynamic>;
              if (call.method == 'encrypt') {
                final plaintext = args['plaintext'] as String;
                return 'enc:v1:mocked_$plaintext';
              } else if (call.method == 'decrypt') {
                final ciphertext = args['ciphertext'] as String;
                return ciphertext.replaceAll('enc:v1:mocked_', '');
              }
              return null;
            });

        const keystoreCipher = AndroidKeystoreSensitiveFieldCipher();

        final enc = await keystoreCipher.encrypt('my-secret-credential');
        expect(enc, equals('enc:v1:mocked_my-secret-credential'));
        expect(log.last.method, equals('encrypt'));
        expect(
          log.last.arguments,
          equals({'plaintext': 'my-secret-credential'}),
        );

        final dec = await keystoreCipher.decrypt(enc);
        expect(dec, equals('my-secret-credential'));
        expect(log.last.method, equals('decrypt'));
        expect(log.last.arguments, equals({'ciphertext': enc}));

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      },
    );

    test(
      'Scenario 6: NIST FIPS 180-4 and RFC 4231 standard crypto test vectors',
      () {
        String toHex(Uint8List bytes) =>
            bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

        // NIST FIPS 180-4 Vector 1: "abc"
        final hashAbc = Sha256.hash(Uint8List.fromList(utf8.encode('abc')));
        expect(
          toHex(hashAbc),
          equals(
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          ),
        );

        // NIST FIPS 180-4 Vector 2: Empty string ""
        final hashEmpty = Sha256.hash(Uint8List(0));
        expect(
          toHex(hashEmpty),
          equals(
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          ),
        );

        // NIST FIPS 180-4 Vector 3: 448-bit block boundary
        final hashLong = Sha256.hash(
          Uint8List.fromList(
            utf8.encode(
              'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
            ),
          ),
        );
        expect(
          toHex(hashLong),
          equals(
            '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
          ),
        );

        // RFC 4231 Test Case 2: key="Jefe", data="what do ya want for nothing?"
        final hmac = HmacSha256.compute(
          Uint8List.fromList(utf8.encode('Jefe')),
          Uint8List.fromList(utf8.encode('what do ya want for nothing?')),
        );
        expect(
          toHex(hmac),
          equals(
            '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
          ),
        );
      },
    );

    test('Scenario 7: AndroidKeystoreSensitiveFieldCipher fails closed on '
        'PlatformException', () async {
      const channel = MethodChannel('dev.brickvpn.harness/secure_storage');

      // Configure mock channel to throw PlatformException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'HARDWARE_KEY_INVALIDATED',
              message: 'Hardware key invalidated by OS',
            );
          });

      const keystoreCipher = AndroidKeystoreSensitiveFieldCipher();

      // Must fail closed with FormatException rather than silently downgrading
      expect(
        () => keystoreCipher.encrypt('test-secret'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('HARDWARE_KEY_INVALIDATED'),
          ),
        ),
      );

      expect(
        () => keystoreCipher.decrypt('enc:v1:sample_ciphertext'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('HARDWARE_KEY_INVALIDATED'),
          ),
        ),
      );

      // Fallback ONLY works on MissingPluginException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw MissingPluginException();
          });

      final fallbackEncrypted = await keystoreCipher.encrypt('fallback-test');
      expect(keystoreCipher.isEncrypted(fallbackEncrypted), isTrue);
      final fallbackDecrypted = await keystoreCipher.decrypt(fallbackEncrypted);
      expect(fallbackDecrypted, equals('fallback-test'));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'Scenario 8: plugin_opts and transport.headers encryption and decryption',
      () async {
        final profileWithPlugin = ServerProfile(
          id: 'ss-plugin-1',
          name: 'Shadowsocks Plugin Node',
          config: const ShadowsocksOutbound(
            server: 'ss.example.com',
            serverPort: 8388,
            method: '2022-blake3-aes-128-gcm',
            password: 'ss-secret-password-xyz',
            plugin: 'v2ray-plugin',
            pluginOpts:
                'server;tls;host=mysecret.domain.com;token=secret-token-12345',
          ),
          addedAt: DateTime.utc(2026, 11, 7, 2),
        );

        await repository.save(profileWithPlugin);

        // Raw file must NOT contain plaintext plugin_opts token
        var rawContent = await storageFile.readAsString();
        expect(rawContent.contains('secret-token-12345'), isFalse);
        expect(rawContent.contains('enc:v1:'), isTrue);

        // Reload repo and verify decrypted plugin_opts matches
        final reloadRepo = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );
        await reloadRepo.init();

        final loaded = await reloadRepo.getById('ss-plugin-1');
        expect(loaded, isNotNull);
        final ss = loaded!.config as ShadowsocksOutbound;
        expect(
          ss.pluginOpts,
          equals(
            'server;tls;host=mysecret.domain.com;token=secret-token-12345',
          ),
        );

        // Test transport.headers encryption via real VlessOutbound with
        // WebSocketTransport
        final vlessWsProfile = ServerProfile(
          id: 'vless-ws-1',
          name: 'VLESS WebSocket Node',
          config: VlessOutbound(
            server: 'vless.example.com',
            serverPort: 443,
            uuid: '44444444-5555-6666-7777-888888888888',
            transport: WebSocketTransport(
              path: '/ws',
              headers: {
                'Authorization': 'Bearer super-secret-auth-token-12345',
                'X-Custom-Secret': 'custom-secret-header-val',
              },
            ),
          ),
          addedAt: DateTime.utc(2026, 11, 7, 3),
        );

        await repository.save(vlessWsProfile);

        rawContent = await storageFile.readAsString();
        expect(
          rawContent.contains('Bearer super-secret-auth-token-12345'),
          isFalse,
        );
        expect(rawContent.contains('custom-secret-header-val'), isFalse);
        expect(rawContent.contains('enc:v1:'), isTrue);

        // Reload fresh FileServerProfileRepository and assert decrypted headers
        final reloadRepoWs = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );
        await reloadRepoWs.init();
        final loadedWs = await reloadRepoWs.getById('vless-ws-1');
        expect(loadedWs, isNotNull);
        expect(loadedWs, equals(vlessWsProfile));
        final ws =
            (loadedWs!.config as VlessOutbound).transport!
                as WebSocketTransport;
        expect(
          ws.headers?['Authorization'],
          equals('Bearer super-secret-auth-token-12345'),
        );
        expect(
          ws.headers?['X-Custom-Secret'],
          equals('custom-secret-header-val'),
        );

        // Test HttpTransport with null path (verifies null is preserved, not mutated to '/')
        final vlessHttpNullPathProfile = ServerProfile(
          id: 'vless-http-null-path',
          name: 'VLESS HTTP Null Path Node',
          config: VlessOutbound(
            server: 'vless-null.example.com',
            serverPort: 443,
            uuid: '55555555-6666-7777-8888-999999999999',
            transport: HttpTransport(
              headers: {'X-Null-Path-Secret': 'secret-headers-without-path'},
            ),
          ),
          addedAt: DateTime.utc(2026, 11, 7, 3),
        );

        await repository.save(vlessHttpNullPathProfile);
        final reloadRepoNullPath = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );
        await reloadRepoNullPath.init();
        final loadedHttpNull = await reloadRepoNullPath.getById(
          'vless-http-null-path',
        );
        expect(loadedHttpNull, isNotNull);
        expect(loadedHttpNull, equals(vlessHttpNullPathProfile));
        final httpNull =
            (loadedHttpNull!.config as VlessOutbound).transport!
                as HttpTransport;
        expect(httpNull.path, isNull);
        expect(
          httpNull.headers?['X-Null-Path-Secret'],
          equals('secret-headers-without-path'),
        );
      },
    );

    test(
      'Scenario 9: extra_params string values encryption and decryption',
      () async {
        final tuicExtraProfile = ServerProfile(
          id: 'tuic-extra-1',
          name: 'TUIC Extra Node',
          config: TuicOutbound(
            server: 'tuic.example.com',
            serverPort: 443,
            uuid: '11111111-2222-3333-4444-555555555555',
            password: 'tuic-password',
            congestionControl: 'bbr',
            tls: TlsSettings(enabled: true),
            extraParams: {
              'secret_param_key': 'super-secret-extra-val-999',
              'numeric_param': 42,
            },
          ),
          addedAt: DateTime.utc(2026, 11, 7),
        );

        await repository.save(tuicExtraProfile);

        final rawContent = await storageFile.readAsString();
        expect(rawContent.contains('super-secret-extra-val-999'), isFalse);
        expect(rawContent.contains('enc:v1:'), isTrue);

        // Reload and assert decrypted
        final reloadedRepo2 = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );
        await reloadedRepo2.init();
        final loadedTuic =
            (await reloadedRepo2.getById('tuic-extra-1'))!.config
                as TuicOutbound;
        expect(
          loadedTuic.extraParams?['secret_param_key'],
          equals('super-secret-extra-val-999'),
        );
        expect(loadedTuic.extraParams?['numeric_param'], equals(42));
      },
    );
  });
}
