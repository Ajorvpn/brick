// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart'
    show OutboundConfig, ServerProfile;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/security/sensitive_field_cipher.dart';
import 'package:mobile/features/connection/domain/usecases/build_server_profile.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/add_subscription_screen.dart';
import 'package:mobile/features/connection/presentation/screens/qr_scan_screen.dart';
import 'package:mobile/features/servers/data/repositories/file_server_profile_repository.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:mobile/main.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

import 'localization_test_harness.dart';

/// Fake implementation of [SubscriptionTransport] for testing adversarial
/// network responses and redirect conditions.
class _AdversarialSubscriptionTransport implements SubscriptionTransport {
  _AdversarialSubscriptionTransport({required this.handler});

  Future<TransportResponse> Function(Uri uri, Map<String, String> headers)
  handler;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) =>
      handler(uri, headers);

  @override
  void close() {}
}

void main() {
  setUpAll(initTestLocalization);

  group('P8-T3 Input Validation & Untrusted-Data Security Review', () {
    test('Test 1: All 8 protocol parsers + SmartConfigParser adversarial '
        'battery', () async {
      const secretToken = 'verySecretTokenXYZ123456789';

      // 1. Oversized URI (100 KB) bounds enforcement (< 50ms)
      final stopwatch = Stopwatch()..start();
      final oversizedUri =
          'vless://11111111-2222-3333-4444-555555555555@'
          '${'a' * 100000}.example.com:443';
      final oversizedRes = parseUri(oversizedUri);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50));
      expect(oversizedRes, isA<Err<OutboundConfig, ConfigParseError>>());
      final oversizedErr =
          (oversizedRes as Err<OutboundConfig, ConfigParseError>).error;
      expect(oversizedErr, isA<InputTooLargeError>());

      // 2. Null-byte injection (\x00 in UUID/credentials)
      const nullByteUri =
          'vless://11111111-2222-3333-4444-55555555555\x00@'
          'example.com:443#Name';
      final nullByteRes = parseUri(nullByteUri);
      expect(nullByteRes, isA<Err<OutboundConfig, ConfigParseError>>());

      // 3. CRLF header injection (\r\n)
      const crlfUri =
          'trojan://$secretToken@example.com:443\r\n'
          'X-Injected: true#Node';
      final crlfRes = parseUri(crlfUri);
      expect(crlfRes, isA<Err<OutboundConfig, ConfigParseError>>());
      final crlfErr = (crlfRes as Err<OutboundConfig, ConfigParseError>).error;
      expect(crlfErr.message.contains(secretToken), isFalse);

      // 4. Malformed Base64 / Percent-encoding across protocols
      // 4A: Shadowsocks
      final ssMalformedRes = parseUri(
        'ss://%ZZ%E0%80@example.com:443#SSBadPercent',
      );
      expect(ssMalformedRes, isA<Err<OutboundConfig, ConfigParseError>>());

      final ssCorruptB64 = parseUri('ss://invalid_base64!!!@example.com:443');
      expect(ssCorruptB64, isA<Err<OutboundConfig, ConfigParseError>>());

      // 4B: VMess
      final vmessMalformedRes = parseUri('vmess://not-valid-base64---===!');
      expect(vmessMalformedRes, isA<Err<OutboundConfig, ConfigParseError>>());

      // 4C: WireGuard (bad private key byte length)
      final wgMalformedRes = parseUri(
        'wg://not-32-bytes@198.51.100.1:51820?publickey=invalid',
      );
      expect(wgMalformedRes, isA<Err<OutboundConfig, ConfigParseError>>());

      // 4D: TUIC (non-UUID token)
      final tuicMalformedRes = parseUri(
        'tuic://not-a-valid-uuid@example.com:443',
      );
      expect(tuicMalformedRes, isA<Err<OutboundConfig, ConfigParseError>>());

      // 5. Out-of-range ports across protocols
      final port0Res = parseUri(
        'vless://11111111-2222-3333-4444-555555555555@example.com:0',
      );
      expect(port0Res, isA<Err<OutboundConfig, ConfigParseError>>());

      final port65536Res = parseUri('trojan://$secretToken@example.com:65536');
      expect(port65536Res, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (port65536Res as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      final portNegRes = parseUri('hy2://pwd@example.com:-1');
      expect(portNegRes, isA<Err<OutboundConfig, ConfigParseError>>());

      // 6. Half-configured Hysteria2 obfuscation (obfs without password)
      final hy2HalfObfsRes = parseUri(
        'hy2://pwd@example.com:443?obfs=salamander',
      );
      expect(hy2HalfObfsRes, isA<Err<OutboundConfig, ConfigParseError>>());

      // 7. Non-numeric AmneziaWG obfuscation parameters
      final awgNonNumericRes = parseUri(
        'awg://aW52YWxpZC1wcml2YXRlLWtleS0xMjM0NTY3ODkwMTI=@198.51.100.1:51820'
        '?public_key=aW52YWxpZC1wdWJsaWMta2V5LTEyMzQ1Njc4OTAxMg==&address=10.0.0.2/32'
        '&jc=bad&jmin=xyz&s1=invalid',
      );
      expect(awgNonNumericRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (awgNonNumericRes as Err<OutboundConfig, ConfigParseError>)
            .error
            .message
            .contains('bad'),
        isFalse,
      );

      // 8. Deeply nested JSON resource-exhaustion vector (depth 50)
      final deeplyNested = <String, dynamic>{};
      var cursor = deeplyNested;
      for (var i = 0; i < 50; i++) {
        final nextMap = <String, dynamic>{};
        cursor['nest'] = nextMap;
        cursor = nextMap;
      }
      cursor['type'] = 'vless';
      final nestedJson = jsonEncode(deeplyNested);
      final nestedRes = parseConfigContent(nestedJson);
      expect(nestedRes, isA<Err<SmartParseResult, ConfigParseError>>());

      // 9. Self-referential brick://import recursion loop
      final loopRes = parseConfigContent(
        'brick://import?url=brick://import?url=brick://import',
      );
      expect(loopRes, isA<Err<SmartParseResult, ConfigParseError>>());

      // 10. Individual zero secret-echoing check across all 8 protocol parsers
      // 10A: VLESS
      final vlessEchoRes = parseUri(
        'vless://$secretToken@example.com:invalid_port',
      );
      expect(vlessEchoRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (vlessEchoRes as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      // 10B: VMess (base64 JSON payload with secretToken and invalid port)
      final vmessB64 = base64Encode(
        utf8.encode(
          jsonEncode({
            'v': '2',
            'ps': 'node',
            'add': 'example.com',
            'port': 'invalid_port',
            'id': secretToken,
            'aid': '0',
            'net': 'tcp',
            'type': 'none',
          }),
        ),
      );
      final vmessEchoRes = parseUri('vmess://$vmessB64');
      expect(vmessEchoRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (vmessEchoRes as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      // 10C: Trojan
      final trojanEchoRes = parseUri(
        'trojan://$secretToken@example.com:invalid_port',
      );
      expect(trojanEchoRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (trojanEchoRes as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      // 10D: Shadowsocks
      final ssB64 = base64UrlEncode(utf8.encode('aes-256-gcm:$secretToken'));
      final ssEchoRes = parseUri('ss://$ssB64@example.com:invalid_port');
      expect(ssEchoRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (ssEchoRes as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      // 10E: Hysteria2
      final hy2EchoRes = parseUri(
        'hy2://$secretToken@example.com:invalid_port?obfs=salamander&obfs-password=$secretToken',
      );
      expect(hy2EchoRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (hy2EchoRes as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      // 10F: TUIC
      final tuicEchoRes = parseUri(
        'tuic://$secretToken:$secretToken@example.com:invalid_port',
      );
      expect(tuicEchoRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (tuicEchoRes as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      // 10G: WireGuard
      final wgEchoRes = parseUri(
        'wireguard://aW52YWxpZC1wcml2YXRlLWtleS0xMjM0NTY3ODkwMTI=@example.com:invalid_port'
        '?public_key=aW52YWxpZC1wdWJsaWMta2V5LTEyMzQ1Njc4OTAxMg==&address=10.0.0.2/32'
        '&preshared_key=$secretToken',
      );
      expect(wgEchoRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (wgEchoRes as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      // 10H: AmneziaWG
      final awgEchoRes = parseUri(
        'awg://aW52YWxpZC1wcml2YXRlLWtleS0xMjM0NTY3ODkwMTI=@example.com:invalid_port'
        '?public_key=aW52YWxpZC1wdWJsaWMta2V5LTEyMzQ1Njc4OTAxMg==&address=10.0.0.2/32'
        '&preshared_key=$secretToken&private_key=$secretToken',
      );
      expect(awgEchoRes, isA<Err<OutboundConfig, ConfigParseError>>());
      expect(
        (awgEchoRes as Err<OutboundConfig, ConfigParseError>).error.message
            .contains(secretToken),
        isFalse,
      );

      // 11. Remark Sanitization against Control Chars, Newlines & RTL
      // Bidi Spoofing
      const buildProfile = BuildServerProfile();
      final profileRes = buildProfile(
        uri:
            'vless://11111111-2222-3333-4444-555555555555@example.com:443'
            '#Clean%0A%0D%E2%80%AEName',
        id: 'clean-profile-1',
        addedAt: DateTime.utc(2026, 11, 7),
      );
      expect(profileRes, isA<Ok<ServerProfile, ConfigParseError>>());
      final profile = (profileRes as Ok<ServerProfile, ConfigParseError>).value;
      expect(profile.name.contains('\n'), isFalse);
      expect(profile.name.contains('\r'), isFalse);
      expect(profile.name.contains('\u202E'), isFalse);
      expect(profile.name, equals('CleanName'));

      // Verify FileServerProfileRepository sanitizes both server and
      // subscription names on save
      final tempDir = Directory.systemTemp.createTempSync('repo_sanitize_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final testRepo = FileServerProfileRepository(
        storageFile: File('${tempDir.path}/server_profiles.json'),
        cipher: InMemorySensitiveFieldCipher(),
      );
      await testRepo.init();

      final hostileProfile = ServerProfile(
        id: 'hostile-prof-1',
        name: 'Hostile\r\n\u202EServer',
        config: profile.config,
        addedAt: DateTime.utc(2026, 11, 7),
      );
      await testRepo.save(hostileProfile);
      final savedProf = await testRepo.getById('hostile-prof-1');
      expect(savedProf, isNotNull);
      expect(savedProf!.name.contains('\n'), isFalse);
      expect(savedProf.name.contains('\r'), isFalse);
      expect(savedProf.name.contains('\u202E'), isFalse);
      expect(savedProf.name, equals('HostileServer'));

      const hostileSub = SubscriptionMetadata(
        id: 'hostile-sub-1',
        url: 'https://example.com/sub',
        name: 'Hostile\r\n\u202ESubscription',
      );
      await testRepo.saveSubscription(hostileSub);
      final savedSub = await testRepo.getSubscriptionById('hostile-sub-1');
      expect(savedSub, isNotNull);
      expect(savedSub!.name.contains('\n'), isFalse);
      expect(savedSub.name.contains('\r'), isFalse);
      expect(savedSub.name.contains('\u202E'), isFalse);
      expect(savedSub.name, equals('HostileSubscription'));
    });

    testWidgets('Test 2: AddServerScreen manual paste adversarial security', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
      );

      // Navigate to Add Server screen
      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();
      expect(find.byType(AddServerScreen), findsOneWidget);

      final uriField = find.byKey(
        const ValueKey<String>('add_server_uri_field'),
      );
      final saveBtn = find.byKey(
        const ValueKey<String>('add_server_save_button'),
      );

      // 1. Adversarial input: 100 KB oversized string
      final hugePayload = 'vless://${'x' * 100000}@example.com:443';
      await tester.enterText(uriField, hugePayload);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // UI presents safe localized error, zero crash, screen remains active
      expect(find.byType(AddServerScreen), findsOneWidget);
      expect(dataSource.records, isEmpty);

      // 2. Adversarial input: invalid port with sensitive password
      const pastedSecret = 'mySuperSecretPastedPassword999';
      await tester.enterText(
        uriField,
        'trojan://$pastedSecret@example.com:999999#Test',
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Assert password NEVER leaked into UI error message or SnackBar
      expect(find.byType(AddServerScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining(pastedSecret),
        ),
        findsNothing,
      );
      expect(dataSource.records, isEmpty);

      // Clean field
      await tester.enterText(uriField, '');
      await tester.pumpAndSettle();
      expect(find.textContaining(pastedSecret), findsNothing);

      // 3. Adversarial input: CRLF injected URI
      await tester.enterText(
        uriField,
        'vless://11111111-2222-3333-4444-555555555555@'
        'example.com:443\r\nBad:True',
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(find.byType(AddServerScreen), findsOneWidget);

      // 4. Adversarial input: raw JSON with unknown protocol type
      await tester.enterText(
        uriField,
        '{"type":"malicious_protocol","server":"1.2.3.4"}',
      );
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(find.byType(AddServerScreen), findsOneWidget);
      expect(dataSource.records, isEmpty);
    });

    testWidgets('Test 3: QrScanScreen hostile barcode security', (
      tester,
    ) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      Future<void> Function(String rawValue)? onDetectCallback;

      Widget mockScanner(
        BuildContext context,
        Future<void> Function(String rawValue) onDetect,
      ) {
        onDetectCallback = onDetect;
        return ElevatedButton(
          key: const ValueKey<String>('mock_scan_button'),
          onPressed: () {},
          child: const Text('Scan'),
        );
      }

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
        scannerBuilder: mockScanner,
      );

      // Navigate to QR Scan Screen
      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_scan_qr_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrScanScreen), findsOneWidget);
      expect(onDetectCallback, isNotNull);

      // 1. Hostile QR payload: malformed URI with sensitive token
      const qrSecret = 'qrSecretToken888';
      await onDetectCallback!('trojan://$qrSecret@example.com:999999');
      await tester.pumpAndSettle();

      // Verified: error surfaced safely, secret never echoed, remains on screen
      expect(find.byType(QrScanScreen), findsOneWidget);
      expect(find.textContaining(qrSecret), findsNothing);
      expect(dataSource.records, isEmpty);

      // 2. Hostile QR payload: subscription URL scanned in server QR screen
      const qrSubToken = 'qrSubscriptionToken555';
      await onDetectCallback!(
        'https://sub.example.com/subscribe?token=$qrSubToken',
      );
      await tester.pumpAndSettle();

      // Verified: rejected as subscription, secret never echoed, unlocks
      expect(find.byType(QrScanScreen), findsOneWidget);
      expect(find.textContaining(qrSubToken), findsNothing);
      expect(dataSource.records, isEmpty);

      // 3. Hostile QR payload: malformed UTF-8 / non-URI junk
      await onDetectCallback!(':::malformed/percent%ZZ//junk:::');
      await tester.pumpAndSettle();
      expect(find.byType(QrScanScreen), findsOneWidget);
      expect(dataSource.records, isEmpty);
    });

    testWidgets(
      'Test 4: AddSubscriptionScreen & SubscriptionFetcher network security',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        late _AdversarialSubscriptionTransport transport;
        final fetcher = SubscriptionFetcher(
          transport: transport = _AdversarialSubscriptionTransport(
            handler: (uri, headers) async {
              return TransportResponse(
                statusCode: HttpStatus.ok,
                headers: const {},
                body: Stream.value(utf8.encode('')),
              );
            },
          ),
        );

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          subscriptionFetcher: fetcher,
        );

        // Navigate to Add Subscription screen directly from HomeScreen
        await tester.tap(
          find.byKey(const ValueKey<String>('home_add_subscription_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AddSubscriptionScreen), findsOneWidget);

        final urlField = find.byKey(
          const ValueKey<String>('add_subscription_url_field'),
        );
        final saveBtn = find.byKey(
          const ValueKey<String>('add_subscription_import_button'),
        );

        // 1. Cleartext HTTP rejection (HTTPS enforcement)
        const httpSecret = 'cleartextSubSecret111';
        await tester.enterText(
          urlField,
          'http://insecure.example.com/sub?token=$httpSecret',
        );
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(find.byType(AddSubscriptionScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining(httpSecret),
          ),
          findsNothing,
        );
        expect(dataSource.records, isEmpty);

        // Clean field
        await tester.enterText(urlField, '');
        await tester.pumpAndSettle();
        expect(find.textContaining(httpSecret), findsNothing);

        // 2. Disallowed schemes: file://, javascript:, data:
        await tester.enterText(urlField, 'file:///etc/passwd');
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(find.byType(AddSubscriptionScreen), findsOneWidget);

        await tester.enterText(urlField, 'javascript:alert(1)');
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();
        expect(find.byType(AddSubscriptionScreen), findsOneWidget);

        // 3. Direct SubscriptionFetcher verification: HTTPS -> HTTP
        // redirect downgrade rejection
        const downgradeSecret = 'secretDowngradeToken456';
        transport.handler = (uri, headers) async {
          if (uri.scheme == 'https') {
            return const TransportResponse(
              statusCode: HttpStatus.found, // 302
              headers: {'location': 'http://insecure.example.com/downgraded'},
              body: Stream.empty(),
            );
          }
          return TransportResponse(
            statusCode: HttpStatus.ok,
            headers: const {},
            body: Stream.value(utf8.encode('vless://...')),
          );
        };

        final downgradeRes = await fetcher.fetchSubscription(
          Uri.parse('https://secure.example.com/sub?token=$downgradeSecret'),
        );
        expect(
          downgradeRes,
          isA<Err<SubscriptionParseResult, ConfigParseError>>(),
        );
        final downgradeErr =
            (downgradeRes as Err<SubscriptionParseResult, ConfigParseError>)
                .error;
        expect(downgradeErr, isA<InsecureTransportError>());
        expect(downgradeErr.message.contains(downgradeSecret), isFalse);

        // 4. Direct SubscriptionFetcher verification: Redirect loop >
        // maxRedirects (5 hops)
        var hops = 0;
        transport.handler = (uri, headers) async {
          hops++;
          return TransportResponse(
            statusCode: HttpStatus.found,
            headers: {'location': 'https://secure.example.com/hop_${hops + 1}'},
            body: const Stream.empty(),
          );
        };

        final loopRes = await fetcher.fetchSubscription(
          Uri.parse('https://secure.example.com/hop_1'),
        );
        expect(loopRes, isA<Err<SubscriptionParseResult, ConfigParseError>>());
        final loopErr =
            (loopRes as Err<SubscriptionParseResult, ConfigParseError>).error;
        expect(loopErr, isA<TooManyRedirectsError>());
        expect(hops, equals(maxRedirects + 1));

        // 5. Direct SubscriptionFetcher verification: Oversized body stream
        // abort (> 5 MB)
        transport.handler = (uri, headers) async {
          // Stream 6 chunks of 1 MB each (6 MB total > 5 MB limit)
          Stream<List<int>> generateHugeStream() async* {
            final chunk = List<int>.filled(1024 * 1024, 65); // 1 MB of 'A'
            for (var i = 0; i < 6; i++) {
              yield chunk;
            }
          }

          return TransportResponse(
            statusCode: HttpStatus.ok,
            headers: const {},
            body: generateHugeStream(),
          );
        };

        final hugeRes = await fetcher.fetchSubscription(
          Uri.parse('https://secure.example.com/huge'),
        );
        expect(hugeRes, isA<Err<SubscriptionParseResult, ConfigParseError>>());
        final hugeErr =
            (hugeRes as Err<SubscriptionParseResult, ConfigParseError>).error;
        expect(hugeErr, isA<InputTooLargeError>());

        // 6. Failed network transport with secret token in URL -> zero token
        // leakage in UI
        const networkSecret = 'subSecretToken777';
        transport.handler = (uri, headers) async {
          throw const SocketException('Connection reset by peer');
        };

        await tester.enterText(
          urlField,
          'https://sub.example.com/api/v1?token=$networkSecret',
        );
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(find.byType(AddSubscriptionScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining(networkSecret),
          ),
          findsNothing,
        );

        // Clean field
        await tester.enterText(urlField, '');
        await tester.pumpAndSettle();
        expect(find.textContaining(networkSecret), findsNothing);
      },
    );
  });
}
