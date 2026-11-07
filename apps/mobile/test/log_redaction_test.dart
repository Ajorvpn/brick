// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/log_entry.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/logging/log_redactor.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';

import 'localization_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestLocalization);

  group('P8-T2 Systematic Log Redaction Across All Surfaces', () {
    test('Scenario 1: Structured JSON log redaction', () {
      final jsonPayload = jsonEncode(<String, dynamic>{
        'level': 'info',
        'time': '2026-11-07T00:00:00Z',
        'source': 'tun',
        'msg': 'tunnel handshake completed successfully',
        'uuid': '11111111-2222-3333-4444-555555555555',
        'password': 'topSecretPassword123',
        'private_key': 'privateKeySecret456',
        'pre_shared_key': 'pskSecret789',
        'public_key': 'realityPublicKeySecret',
        'short_id': 'realityShortIdSecret',
        'obfs_password': 'obfsPasswordSecret',
        'server': 'vpn.secret.node.com',
        'url': 'https://secret.url/path?token=tokenValue',
      });

      final entry = LogEntry.fromRaw(jsonPayload);

      // Level, timestamp, and non-sensitive diagnostic messages are preserved
      expect(entry.level, equals(LogLevel.info));
      expect(entry.source, equals('tun'));
      expect(
        entry.message,
        contains('tunnel handshake completed successfully'),
      );

      // Raw JSON line and structured fields have sensitive values replaced
      expect(entry.raw.contains('topSecretPassword123'), isFalse);
      expect(entry.raw.contains('privateKeySecret456'), isFalse);
      expect(entry.raw.contains('pskSecret789'), isFalse);
      expect(entry.raw.contains('realityPublicKeySecret'), isFalse);
      expect(entry.raw.contains('realityShortIdSecret'), isFalse);
      expect(entry.raw.contains('obfsPasswordSecret'), isFalse);
      expect(entry.raw.contains('vpn.secret.node.com'), isFalse);
      expect(entry.raw.contains('https://secret.url'), isFalse);

      expect(entry.raw.contains('"password":"[REDACTED]"'), isTrue);
      expect(entry.raw.contains('"uuid":"[REDACTED]"'), isTrue);
      expect(entry.raw.contains('"server":"[REDACTED_HOST]"'), isTrue);
    });

    test(
      'Scenario 2: All 8 protocols known-secret & '
      'share-link redaction',
      () async {
      final profiles = <ServerProfile>[
        // 1. VLESS Reality
        ServerProfile(
          id: 'vless-1',
          name: 'VLESS Node',
          config: VlessOutbound(
            server: 'vless.reality.example.com',
            serverPort: 443,
            uuid: '11111111-aaaa-bbbb-cccc-111111111111',
            tls: TlsSettings(
              enabled: true,
              serverName: 'vless.reality.example.com',
              reality: const RealitySettings(
                enabled: true,
                publicKey: 'vlessRealityPublicKeySecret123',
                shortId: 'vlessRealityShortIdSecret456',
              ),
            ),
          ),
          addedAt: DateTime.utc(2026, 11, 7, 1),
        ),
        // 2. VMess
        ServerProfile(
          id: 'vmess-1',
          name: 'VMess Node',
          config: const VmessOutbound(
            server: 'vmess.example.com',
            serverPort: 443,
            uuid: '22222222-aaaa-bbbb-cccc-222222222222',
          ),
          addedAt: DateTime.utc(2026, 11, 7, 1),
        ),
        // 3. Trojan
        ServerProfile(
          id: 'trojan-1',
          name: 'Trojan Node',
          config: TrojanOutbound(
            server: 'trojan.example.com',
            serverPort: 443,
            password: 'trojanSecretPassword789',
            tls: TlsSettings(enabled: true, serverName: 'trojan.example.com'),
          ),
          addedAt: DateTime.utc(2026, 11, 7, 1),
        ),
        // 4. Shadowsocks
        ServerProfile(
          id: 'ss-1',
          name: 'Shadowsocks Node',
          config: const ShadowsocksOutbound(
            server: 'ss.example.com',
            serverPort: 8388,
            method: 'aes-256-gcm',
            password: 'ssSecretPassword321',
            plugin: 'v2ray-plugin',
            pluginOpts: 'host=secret-ss-plugin-host.com;tls',
          ),
          addedAt: DateTime.utc(2026, 11, 7, 1),
        ),
        // 5. Hysteria2
        ServerProfile(
          id: 'hy2-1',
          name: 'Hysteria2 Node',
          config: Hysteria2Outbound(
            server: 'hy2.example.com',
            serverPort: 443,
            password: 'hy2SecretPassword654',
            obfsType: 'salamander',
            obfsPassword: 'hy2ObfsPassword987',
            tls: TlsSettings(enabled: true, serverName: 'hy2.example.com'),
          ),
          addedAt: DateTime.utc(2026, 11, 7, 1),
        ),
        // 6. TUIC
        ServerProfile(
          id: 'tuic-1',
          name: 'TUIC Node',
          config: TuicOutbound(
            server: 'tuic.example.com',
            serverPort: 8443,
            uuid: '33333333-aaaa-bbbb-cccc-333333333333',
            password: 'tuicSecretPassword456',
            tls: TlsSettings(enabled: true, serverName: 'tuic.example.com'),
          ),
          addedAt: DateTime.utc(2026, 11, 7, 1),
        ),
        // 7. WireGuard
        ServerProfile(
          id: 'wg-1',
          name: 'WireGuard Node',
          config: WireGuardOutbound(
            server: 'wg.example.com',
            serverPort: 51820,
            localAddresses: const ['10.0.0.2/32'],
            privateKey: 'wgPrivateKeySecret111',
            presharedKey: 'wgPresharedKeySecret222',
            peerPublicKey: 'wgPeerPublicKeySecret333',
          ),
          addedAt: DateTime.utc(2026, 11, 7, 1),
        ),
        // 8. AmneziaWG
        ServerProfile(
          id: 'awg-1',
          name: 'AmneziaWG Node',
          config: WireGuardOutbound(
            server: 'awg.example.com',
            serverPort: 51820,
            localAddresses: const ['10.0.0.3/32'],
            privateKey: 'awgPrivateKeySecret444',
            presharedKey: 'awgPresharedKeySecret555',
            peerPublicKey: 'awgPeerPublicKeySecret666',
          ),
          addedAt: DateTime.utc(2026, 11, 7, 1),
        ),
      ];

      const sub = SubscriptionMetadata(
        id: 'sub-1',
        name: 'Secret Subscription',
        url: 'https://sub-provider.example.com/api/get?token=secretSubToken777',
      );

      final allSecrets = <String>{};
      for (final p in profiles) {
        allSecrets.addAll(LogRedactor.extractSecretsFromProfile(p));
      }
      allSecrets.addAll(LogRedactor.extractSecretsFromSubscription(sub));

      expect(allSecrets.contains('vless.reality.example.com'), isTrue);
      expect(allSecrets.contains('vlessRealityPublicKeySecret123'), isTrue);
      expect(allSecrets.contains('trojanSecretPassword789'), isTrue);
      expect(allSecrets.contains('ssSecretPassword321'), isTrue);
      expect(allSecrets.contains('hy2ObfsPassword987'), isTrue);
      expect(allSecrets.contains('tuicSecretPassword456'), isTrue);
      expect(allSecrets.contains('wgPrivateKeySecret111'), isTrue);
      expect(allSecrets.contains('secretSubToken777'), isTrue);

      // Native unstructured log echoing raw secrets and share link URIs
      const rawLogLine =
          'Connected to vless.reality.example.com using '
          'password=trojanSecretPassword789 '
          'and token secretSubToken777 with URI '
          'vless://11111111-aaaa-bbbb-cccc-111111111111@vless.reality.example.com:443?type=reality';

      final safeLog = LogRedactor.redactRawLine(
        rawLogLine,
        knownSecrets: allSecrets,
      );

      expect(safeLog.contains('vless.reality.example.com'), isFalse);
      expect(safeLog.contains('trojanSecretPassword789'), isFalse);
      expect(safeLog.contains('secretSubToken777'), isFalse);
      expect(safeLog.contains('vless://[REDACTED]'), isTrue);
    });

    test(
      'Scenario 3: Free-text pattern redaction & internal TUN IP preservation',
      () {
        const logLine =
            'Dialing external peer 203.0.113.45:443 and [2001:db8::1]:443 '
            'for session 98765432-abcd-ef01-2345-6789abcdef01; assigned TUN IP '
            '10.111.222.1 netmask 255.255.255.0 with loopback '
            '127.0.0.1 and ::1. '
            'Initializing tunnel. Latency spike: 120ms.';

        final safeLog = LogRedactor.redactRawLine(logLine);

        // External IPs and UUID are scrubbed
        expect(safeLog.contains('203.0.113.45:443'), isFalse);
        expect(safeLog.contains('[2001:db8::1]:443'), isFalse);
        expect(
          safeLog.contains('98765432-abcd-ef01-2345-6789abcdef01'),
          isFalse,
        );

        expect(safeLog.contains('[REDACTED_IP]'), isTrue);
        expect(safeLog.contains('[REDACTED_UUID]'), isTrue);

        // Safe diagnostic addresses remain intact
        expect(safeLog.contains('10.111.222.1'), isTrue);
        expect(safeLog.contains('255.255.255.0'), isTrue);
        expect(safeLog.contains('127.0.0.1'), isTrue);
        expect(safeLog.contains('::1'), isTrue);

        // Normal text is preserved
        expect(safeLog.contains('Initializing tunnel'), isTrue);
        expect(safeLog.contains('Latency spike: 120ms'), isTrue);
      },
    );

    test('Scenario 4: Cross-surface consistency across Viewer, '
        'Clipboard, and Disk', () async {
      final testTempDir = await Directory.systemTemp.createTemp(
        'log_redaction_surface_test_',
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'getTemporaryDirectory') {
                return testTempDir.path;
              }
              return null;
            },
          );

      final fakeEngine = FakeVpnEngine();
      final container = ProviderContainer(
        overrides: [vpnEngineProvider.overrideWithValue(fakeEngine)],
      );
      addTearDown(() async {
        container.dispose();
        await fakeEngine.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        if (testTempDir.existsSync()) {
          await testTempDir.delete(recursive: true);
        }
      });

      // Initialize logManagerProvider and wait for sink initialization
      container.read(logManagerProvider);
      await pumpEventQueue();

      const sensitiveSecret = 'SuperSecretUserPassword999';
      container.read(logManagerProvider.notifier).registerKnownSecrets([
        sensitiveSecret,
      ]);

      // Emit log line with sensitive password, external IP, and trojan URI
      fakeEngine.emitLog(
        '2026-11-07 00:00:00 INFO Authenticating with '
        'password=$sensitiveSecret to 198.51.100.99:443 via '
        'trojan://secretToken@trojan.com:443',
      );
      await pumpEventQueue();

      // Surface 1: Live Viewer ring buffer
      final structuredEntries = container.read(structuredLogEntriesProvider);
      expect(structuredEntries, isNotEmpty);
      final viewerText = structuredEntries
          .map((e) => '${e.raw} ${e.message}')
          .join('\n');
      expect(viewerText.contains(sensitiveSecret), isFalse);
      expect(viewerText.contains('198.51.100.99'), isFalse);
      expect(viewerText.contains('[REDACTED]'), isTrue);
      expect(viewerText.contains('[REDACTED_IP]'), isTrue);
      expect(viewerText.contains('trojan://[REDACTED]'), isTrue);

      // Surface 2: Clipboard Export string formatting
      final clipboardExport = structuredEntries
          .map((entry) {
            final time = entry.timestamp.toUtc().toIso8601String();
            final sourceTag = (entry.source != null && entry.source!.isNotEmpty)
                ? ' [${entry.source}]'
                : '';
            final msg = entry.message.isNotEmpty ? entry.message : entry.raw;
            return '$time [${entry.level.label}]$sourceTag $msg';
          })
          .join('\n');
      expect(clipboardExport.contains(sensitiveSecret), isFalse);
      expect(clipboardExport.contains('198.51.100.99'), isFalse);
      expect(clipboardExport.contains('[REDACTED]'), isTrue);
      expect(clipboardExport.contains('[REDACTED_IP]'), isTrue);
      expect(clipboardExport.contains('trojan://[REDACTED]'), isTrue);

      // Surface 3: On-Disk Temporary File
      await container.read(logManagerProvider.notifier).flushFile();
      await pumpEventQueue();

      final logFile = File('${testTempDir.path}/${LogManager.logFileName}');
      expect(logFile.existsSync(), isTrue);
      final fileContents = await logFile.readAsString();
      expect(fileContents.contains(sensitiveSecret), isFalse);
      expect(fileContents.contains('198.51.100.99'), isFalse);
      expect(fileContents.contains('[REDACTED]'), isTrue);
      expect(fileContents.contains('[REDACTED_IP]'), isTrue);
      expect(fileContents.contains('trojan://[REDACTED]'), isTrue);
    });
  });
}