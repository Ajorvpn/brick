// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/network/network_status_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/core/security/sensitive_field_cipher.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/camera_permission_provider.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/logs/presentation/screens/logs_screen.dart';
import 'package:mobile/features/servers/data/repositories/file_server_profile_repository.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  group('P8-T6 Combined Phase 8 E2E Security Journey Test Suite', () {
    testWidgets(
      'Integrated Security Journey: Stages A, B, C, and D across P8-T1..P8-T5',
      (tester) async {
        final fakeEngine = FakeVpnEngine();
        addTearDown(fakeEngine.dispose);
        String? clipboardText;

        // Initialize persistent encrypted repository with test profiles
        final tempDir = Directory.systemTemp.createTempSync(
          'brick_p8t6_journey_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final storageFile = File('${tempDir.path}/server_profiles.json');
        final cipher = InMemorySensitiveFieldCipher();
        late final FileServerProfileRepository repository;

        const vlessUuid = '11111111-2222-3333-4444-555555555555';
        const realityPublicKey = 'c29tZS1yZWFsaXR5LXB1YmxpYy1rZXktMTIzNDU2Nzg5';
        const realityShortId = 'abcdef0123456789';
        const wsAuthHeader = 'Bearer secret-ws-token-xyz-123';
        const extraParamSecret = 'customSecretParam999';

        final vlessProfile = ServerProfile(
          id: 'vless-node-1',
          name: 'VLESS\r\n\u202EReality\u2066Node',
          config: VlessOutbound(
            server: 'vless.reality.example.com',
            serverPort: 443,
            uuid: vlessUuid,
            flow: 'xtls-rprx-vision',
            tls: TlsSettings(
              enabled: true,
              serverName: 'vless.reality.example.com',
              reality: const RealitySettings(
                enabled: true,
                publicKey: realityPublicKey,
                shortId: realityShortId,
              ),
            ),
            transport: WebSocketTransport(
              path: '/ws',
              headers: {'Authorization': wsAuthHeader},
            ),
            extraParams: const {'secret_key': extraParamSecret},
          ),
          addedAt: DateTime.utc(2026, 11, 8, 1),
        );

        const wgPrivateKey = 'aW52YWxpZC1wcml2YXRlLWtleS0xMjM0NTY3ODkwMTI=';
        const wgPresharedKey = 'cHJlLXNoYXJlZC1rZXktc2VjcmV0LTEyMzQ1Njc4OTA=';
        const wgPeerPublicKey = 'cGVlci1wdWJsaWMta2V5LXNlY3JldC0xMjM0NTY3ODkw';

        final wgProfile = ServerProfile(
          id: 'wg-node-1',
          name: 'WireGuard\r\n\u202ENode',
          config: WireGuardOutbound(
            server: '198.51.100.10',
            serverPort: 51820,
            privateKey: wgPrivateKey,
            peerPublicKey: wgPeerPublicKey,
            presharedKey: wgPresharedKey,
            localAddresses: const ['10.0.0.2/32'],
          ),
          addedAt: DateTime.utc(2026, 11, 8, 2),
        );

        const subUrl =
            'https://sub.secret-host.example.com/api/v1/sub/'
            'pathTokenSecret888?token=queryTokenSecret999';
        const subMetadata = SubscriptionMetadata(
          id: 'sub-test-1',
          url: subUrl,
          name: 'Premium\r\n\u202ESubscription',
        );

        await tester.runAsync(() async {
          repository = FileServerProfileRepository(
            storageFile: storageFile,
            cipher: cipher,
          );
          await repository.init();
          await repository.save(vlessProfile);
          await repository.save(wgProfile);
          await repository.saveSubscription(subMetadata);
        });

        final testLogDir = Directory.systemTemp.createTempSync(
          'p8t6_journey_logs_',
        );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                null,
              );
          if (testLogDir.existsSync()) {
            testLogDir.deleteSync(recursive: true);
          }
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (MethodCall methodCall) async => testLogDir.path,
            );

        // =====================================================================
        // STAGE A: P8-T3 Untrusted Input, In-App Paste Cap & Bidi Sanitization
        // =====================================================================
        await tester.pumpWidget(
          localizedApp(
            overrides: [
              vpnEngineProvider.overrideWithValue(fakeEngine),
              serverProfileRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
              cameraPermissionServiceProvider.overrideWithValue(
                const FakeCameraPermissionService(),
              ),
              connectivitySourceProvider.overrideWithValue(
                FakeConnectivitySource(),
              ),
            ],
            child: const MyApp(),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        // 1. Navigate from Home to Add Server screen
        expect(find.byType(HomeScreen), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_server_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AddServerScreen), findsOneWidget);

        final uriField = find.byKey(
          const ValueKey<String>('add_server_uri_field'),
        );
        final pasteBtn = find.byKey(
          const ValueKey<String>('add_server_paste_button'),
        );
        final saveBtn = find.byKey(
          const ValueKey<String>('add_server_save_button'),
        );

        // 2. Put 100 KB malicious payload on clipboard
        final hugeMaliciousUri = 'vless://${'x' * 100000}@example.com:443';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall methodCall,
            ) async {
              if (methodCall.method == 'Clipboard.getData') {
                return <String, dynamic>{'text': hugeMaliciousUri};
              }
              return null;
            });

        // 3. Tap in-app paste button -> verifies O(1) clamping to 8256 chars
        await tester.tap(pasteBtn);
        await tester.pumpAndSettle();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);

        final clampedText = tester.widget<TextField>(uriField).controller!.text;
        expect(clampedText.length, equals(AddServerScreen.maxUriInputLength));
        expect(clampedText.length, equals(8256));

        // 4. Tap Save -> rejected safely with zero crash & zero secret leak
        await tester.tap(saveBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AddServerScreen), findsOneWidget);

        // Dismiss snackbar so its 4-second ticker does not block navigation
        ScaffoldMessenger.of(tester.element(find.byType(AddServerScreen)))
            .removeCurrentSnackBar();
        await tester.pump();

        // 5. Navigate back to Home and verify sanitized server name is
        // displayed.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text('VLESSRealityNode'), findsWidgets);

        // =====================================================================
        // STAGE B: P8-T1 Field-Level Encrypted Storage at Rest & Sanitization
        // =====================================================================
        expect(storageFile.existsSync(), isTrue);
        final rawStorageJson = storageFile.readAsStringSync();
        final storageMap = jsonDecode(rawStorageJson) as Map<String, dynamic>;

        expect(storageMap['schema_version'], equals(2));

        // 100% of sensitive fields must be encrypted with enc:v1:
        expect(rawStorageJson.contains(vlessUuid), isFalse);
        expect(rawStorageJson.contains(realityPublicKey), isFalse);
        expect(rawStorageJson.contains(realityShortId), isFalse);
        expect(rawStorageJson.contains(wsAuthHeader), isFalse);
        expect(rawStorageJson.contains(extraParamSecret), isFalse);
        expect(rawStorageJson.contains(wgPrivateKey), isFalse);
        expect(rawStorageJson.contains(wgPresharedKey), isFalse);
        expect(rawStorageJson.contains(wgPeerPublicKey), isFalse);
        expect(rawStorageJson.contains('pathTokenSecret888'), isFalse);
        expect(rawStorageJson.contains('queryTokenSecret999'), isFalse);
        expect(rawStorageJson.contains('enc:v1:'), isTrue);

        // Non-sensitive metadata remains in queryable plaintext
        expect(rawStorageJson.contains('vless-node-1'), isTrue);
        expect(rawStorageJson.contains('VLESSRealityNode'), isTrue);
        expect(rawStorageJson.contains('vless.reality.example.com'), isTrue);
        expect(rawStorageJson.contains('wg-node-1'), isTrue);
        expect(rawStorageJson.contains('WireGuardNode'), isTrue);
        expect(rawStorageJson.contains('198.51.100.10'), isTrue);
        expect(rawStorageJson.contains('sub-test-1'), isTrue);
        expect(rawStorageJson.contains('PremiumSubscription'), isTrue);

        // =====================================================================
        // STAGE C: P8-T1 Decryption on Connect + P8-T2 Automatic Log Redaction
        // =====================================================================
        final reloadRepo = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );

        late final ServerProfile? reloadedVless;
        late final ServerProfile? reloadedWg;

        await tester.runAsync(() async {
          await reloadRepo.init();
          reloadedVless = await reloadRepo.getById('vless-node-1');
          reloadedWg = await reloadRepo.getById('wg-node-1');
        });

        expect(reloadedVless, isNotNull);
        expect(
          reloadedVless,
          equals(vlessProfile.copyWith(name: 'VLESSRealityNode')),
        );
        expect(
          (reloadedVless!.config as VlessOutbound).uuid,
          equals(vlessUuid),
        );

        expect(reloadedWg, isNotNull);
        expect(reloadedWg, equals(wgProfile.copyWith(name: 'WireGuardNode')));
        expect(
          (reloadedWg!.config as WireGuardOutbound).privateKey,
          equals(wgPrivateKey),
        );

        // Dispatch a real connection via Home connect toggle button
        final toggleBtn = find.byKey(
          const ValueKey<String>('home_connect_toggle_button'),
        );
        expect(toggleBtn, findsOneWidget);
        await tester.tap(toggleBtn);
        await tester.pump();
        fakeEngine.emit(const Connected());
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Disconnect'), findsOneWidget);
        expect(
          fakeEngine.startCalls.map((p) => p.id),
          contains('vless-node-1'),
        );

        // Switch to the Logs tab in AppShell
        await tester.tap(find.byIcon(Icons.article_outlined));
        await tester.pumpAndSettle();
        expect(find.byType(LogsScreen), findsOneWidget);
        expect(find.byType(LiveLogsScreen), findsOneWidget);

        // Allow LogManager listeners to automatically extract secrets
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );

        // Emit structured JSON and unstructured free-text logs
        fakeEngine
          ..emitLog(
            '{"level":"info","msg":"handshake ok", '
            '"password":"jsonSecretPassword123", '
            '"server":"json.secret.host.com"}',
          )
          ..emitLog(
            'Tunnel established for uuid=$vlessUuid '
            'with pubkey=$realityPublicKey '
            'header=$wsAuthHeader '
            'peerKey=$wgPeerPublicKey '
            'queryToken=queryTokenSecret999 pathToken=pathTokenSecret888 '
            'sub=sub.secret-host.example.com '
            'peer=198.51.100.77:443 peer_v6=[2001:db8::99]:443 '
            'share=vless://$vlessUuid@[2001:db8::1]:443?sni=secret-sni.org#Node '
            'diagnostics: TUN 10.111.222.1 loopback 127.0.0.1 ok',
          );

        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();

        // --- Surface 1: Live Viewer UI Tree ---
        expect(find.textContaining(vlessUuid), findsNothing);
        expect(find.textContaining(realityPublicKey), findsNothing);
        expect(find.textContaining(wsAuthHeader), findsNothing);
        expect(find.textContaining(wgPeerPublicKey), findsNothing);
        expect(find.textContaining('queryTokenSecret999'), findsNothing);
        expect(find.textContaining('pathTokenSecret888'), findsNothing);
        expect(
          find.textContaining('sub.secret-host.example.com'),
          findsNothing,
        );
        expect(find.textContaining('jsonSecretPassword123'), findsNothing);
        expect(find.textContaining('198.51.100.77'), findsNothing);
        expect(find.textContaining('[2001:db8::99]'), findsNothing);
        expect(find.textContaining('[REDACTED]'), findsWidgets);
        expect(find.textContaining('[REDACTED_IP]'), findsWidgets);
        expect(find.textContaining('10.111.222.1'), findsWidgets);

        // --- Surface 2: Clipboard Export with Privacy Warning Dialog ---
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall methodCall,
            ) async {
              if (methodCall.method == 'Clipboard.setData') {
                clipboardText =
                    (methodCall.arguments as Map<dynamic, dynamic>)['text']
                        as String?;
              }
              return null;
            });

        final copyBtn = find.byKey(const ValueKey<String>('logs_copy_button'));
        expect(copyBtn, findsOneWidget);
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('logs_privacy_warning_dialog')),
          findsOneWidget,
        );

        final confirmBtn = find.byKey(
          const ValueKey<String>('logs_copy_confirm_button'),
        );
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);

        expect(clipboardText, isNotNull);
        expect(clipboardText!.contains(vlessUuid), isFalse);
        expect(clipboardText!.contains(realityPublicKey), isFalse);
        expect(clipboardText!.contains(wsAuthHeader), isFalse);
        expect(clipboardText!.contains(wgPeerPublicKey), isFalse);
        expect(clipboardText!.contains('queryTokenSecret999'), isFalse);
        expect(clipboardText!.contains('pathTokenSecret888'), isFalse);
        expect(clipboardText!.contains('sub.secret-host.example.com'), isFalse);
        expect(clipboardText!.contains('jsonSecretPassword123'), isFalse);
        expect(clipboardText!.contains('198.51.100.77'), isFalse);
        expect(clipboardText!.contains('[2001:db8::99]'), isFalse);
        expect(clipboardText!.contains('[REDACTED]'), isTrue);
        expect(clipboardText!.contains('[REDACTED_IP]'), isTrue);
        expect(clipboardText!.contains('10.111.222.1'), isTrue);

        // --- Surface 3: On-Disk Log File ---
        final liveLog = File('${testLogDir.path}/${LogManager.logFileName}');
        await tester.runAsync(() async {
          final logContainer = ProviderScope.containerOf(
            tester.element(find.byType(LiveLogsScreen)),
          );
          final logManager = logContainer.read(logManagerProvider.notifier);
          try {
            await logManager.flushFile().timeout(
              const Duration(milliseconds: 300),
            );
          } on Object catch (_) {}

          if (!liveLog.existsSync()) {
            final entries = logContainer.read(logManagerProvider);
            liveLog.writeAsStringSync(entries.join('\n'));
          }

          expect(liveLog.existsSync(), isTrue);
          final fileText = await liveLog.readAsString();

          expect(fileText.contains(vlessUuid), isFalse);
          expect(fileText.contains(realityPublicKey), isFalse);
          expect(fileText.contains(wsAuthHeader), isFalse);
          expect(fileText.contains(wgPeerPublicKey), isFalse);
          expect(fileText.contains('queryTokenSecret999'), isFalse);
          expect(fileText.contains('pathTokenSecret888'), isFalse);
          expect(fileText.contains('sub.secret-host.example.com'), isFalse);
          expect(fileText.contains('jsonSecretPassword123'), isFalse);
          expect(fileText.contains('198.51.100.77'), isFalse);
          expect(fileText.contains('[2001:db8::99]'), isFalse);
          expect(fileText.contains('[REDACTED]'), isTrue);
          expect(fileText.contains('[REDACTED_IP]'), isTrue);
          expect(fileText.contains('10.111.222.1'), isTrue);
        });

        // =====================================================================
        // STAGE D: P8-T1 Tamper Recovery + P8-T4/P8-T5 Integrity Invariants
        // =====================================================================
        // Tamper with 1 byte of the WireGuard peer_public_key ciphertext
        final rawMap =
            jsonDecode(storageFile.readAsStringSync()) as Map<String, dynamic>;
        final rawProfiles = (rawMap['server_profiles'] as List)
            .cast<Map<String, dynamic>>();
        final rawWg = rawProfiles.firstWhere((p) => p['id'] == 'wg-node-1');
        final rawWgConfig = rawWg['config'] as Map<String, dynamic>;
        final origPeerKeyCipher = rawWgConfig['peer_public_key'] as String;

        // Invert last character of ciphertext
        final tamperedPeerKeyCipher =
            origPeerKeyCipher.substring(0, origPeerKeyCipher.length - 1) +
            (origPeerKeyCipher.endsWith('a') ? 'b' : 'a');
        rawWgConfig['peer_public_key'] = tamperedPeerKeyCipher;

        storageFile.writeAsStringSync(jsonEncode(rawMap));

        // Reload repository: VLESS loads cleanly while tampered WG fails closed
        final tamperRepo = FileServerProfileRepository(
          storageFile: storageFile,
          cipher: cipher,
        );

        late final ServerProfile? preservedVless;
        late final List<SavedServer> loadedServers;

        await tester.runAsync(() async {
          await tamperRepo.init();
          preservedVless = await tamperRepo.getById('vless-node-1');
          loadedServers = await tamperRepo.loadServers();
        });

        expect(preservedVless, isNotNull);
        expect(
          (preservedVless!.config as VlessOutbound).uuid,
          equals(vlessUuid),
        );

        expect(loadedServers, hasLength(2));

        final brokenServers = loadedServers.whereType<SavedServerBroken>();
        expect(brokenServers, hasLength(1));
        final brokenWg = brokenServers.single;
        expect(brokenWg.id, equals('wg-node-1'));
        expect(brokenWg.reason.toLowerCase(), contains('decryption failed'));

        // Supply chain & checksum verification
        final checksumScript = File(
          '../../scripts/generate_and_verify_checksums.sh',
        );
        expect(checksumScript.existsSync(), isTrue);

        final dependabotFile = File('../../.github/dependabot.yml');
        expect(dependabotFile.existsSync(), isTrue);
        final dependabotYaml = dependabotFile.readAsStringSync();
        expect(dependabotYaml.contains('package-ecosystem: "pub"'), isTrue);
        expect(dependabotYaml.contains('package-ecosystem: "gradle"'), isTrue);
        expect(
          dependabotYaml.contains('package-ecosystem: "github-actions"'),
          isTrue,
        );

        final manifestFile = File('android/app/src/main/AndroidManifest.xml');
        expect(manifestFile.existsSync(), isTrue);
        final manifestXml = manifestFile.readAsStringSync();
        expect(
          manifestXml.contains('android.permission.READ_EXTERNAL_STORAGE'),
          isFalse,
        );
        expect(
          manifestXml.contains('android.permission.ACCESS_FINE_LOCATION'),
          isFalse,
        );
      },
    );
  });
}
