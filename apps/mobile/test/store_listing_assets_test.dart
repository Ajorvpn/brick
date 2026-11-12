// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory repoRoot;

  setUpAll(() {
    var dir = Directory.current;
    while (!File('${dir.path}/pubspec.yaml').existsSync() ||
        !Directory('${dir.path}/apps').existsSync()) {
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
    repoRoot = dir;
  });

  Map<String, int> parsePngMetadata(Uint8List bytes) {
    const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
    expect(
      bytes.length,
      greaterThanOrEqualTo(26),
      reason: 'PNG must be at least 26 bytes long',
    );
    for (var i = 0; i < 8; i++) {
      expect(
        bytes[i],
        equals(pngSignature[i]),
        reason: 'PNG signature mismatch at byte $i',
      );
    }
    final chunkType = String.fromCharCodes(bytes.sublist(12, 16));
    expect(chunkType, equals('IHDR'), reason: 'First chunk must be IHDR');

    final byteData = ByteData.sublistView(bytes);
    final width = byteData.getUint32(16);
    final height = byteData.getUint32(20);
    final bitDepth = byteData.getUint8(24);
    final colorType = byteData.getUint8(25);

    return {
      'width': width,
      'height': height,
      'bitDepth': bitDepth,
      'colorType': colorType,
    };
  }

  group('P10-T5: Google Play Store Listing & Assets Verification Suite', () {
    test('Test 1: Icon & Feature Graphic PNG Header & Dimensions', () {
      final iconFile = File(
        '${repoRoot.path}/docs/release/store-assets/icon-512x512.png',
      );
      final featureFile = File(
        '${repoRoot.path}/docs/release/store-assets/feature-graphic-1024x500.png',
      );

      expect(iconFile.existsSync(), isTrue, reason: 'icon-512x512.png exists');
      expect(
        featureFile.existsSync(),
        isTrue,
        reason: 'feature-graphic-1024x500.png exists',
      );

      final iconBytes = iconFile.readAsBytesSync();
      expect(
        iconBytes.length,
        lessThan(1024 * 1024),
        reason: 'Icon must be < 1024 KB per Play Console requirements',
      );
      final iconDim = parsePngMetadata(iconBytes);
      expect(iconDim['width'], equals(512));
      expect(iconDim['height'], equals(512));
      expect(iconDim['colorType'], equals(6)); // 32-bit RGBA

      final featureBytes = featureFile.readAsBytesSync();
      expect(
        featureBytes.length,
        lessThan(15 * 1024 * 1024),
        reason: 'Feature graphic must be < 15 MB per Play Console requirements',
      );
      final featureDim = parsePngMetadata(featureBytes);
      expect(featureDim['width'], equals(1024));
      expect(featureDim['height'], equals(500));
    });

    test('Test 2: Play Store Phone Screenshots PNG Binary & Dimension '
        'Validation', () {
      // Assert AndroidManifest has android:label="Brick VPN"
      final manifestFile = File(
        '${repoRoot.path}/apps/mobile/android/app/src/main/AndroidManifest.xml',
      );
      expect(manifestFile.existsSync(), isTrue);
      final manifestContent = manifestFile.readAsStringSync();
      expect(manifestContent.contains('android:label="Brick VPN"'), isTrue);
      expect(manifestContent.contains('android:label="mobile"'), isFalse);

      final screenshotFiles = [
        '01_home_disconnected.png',
        '02_home_connected.png',
        '03_servers_and_subscriptions.png',
        '04_live_logs_redacted.png',
      ];

      for (final filename in screenshotFiles) {
        final file = File(
          '${repoRoot.path}/docs/release/store-assets/screenshots/$filename',
        );
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Screenshot $filename must exist',
        );

        final bytes = file.readAsBytesSync();
        expect(
          bytes.length,
          greaterThan(5 * 1024),
          reason: 'Screenshot $filename must be non-empty (> 5 KB)',
        );

        final dim = parsePngMetadata(bytes);
        expect(
          dim['width'],
          equals(1080),
          reason: 'Screenshot $filename width must be 1080',
        );
        expect(
          dim['height'],
          equals(1920),
          reason:
              'Screenshot $filename height must be 1920 (9:16 aspect ratio)',
        );
        expect(
          dim['colorType'],
          equals(6),
          reason: 'Screenshot $filename must be 8-bit/color RGBA (type 6)',
        );
      }
    });

    test('Test 3: Store Listing Character Limits & Honesty Verification', () {
      final listingFile = File(
        '${repoRoot.path}/docs/release/store-listing.md',
      );
      expect(
        listingFile.existsSync(),
        isTrue,
        reason: 'store-listing.md must exist',
      );
      final content = listingFile.readAsStringSync();

      // Ensure no placeholder tokens
      expect(
        content.contains('TODO'),
        isFalse,
        reason: 'store-listing.md must not contain TODO',
      );
      expect(
        content.contains('TBD'),
        isFalse,
        reason: 'store-listing.md must not contain TBD',
      );

      // Extract App Title
      final titleMatch = RegExp(r'### App Title\s*\n`([^`]+)`')
          .firstMatch(content);
      expect(titleMatch, isNotNull, reason: 'App Title block must exist');
      final appTitle = titleMatch!.group(1)!.trim();
      expect(appTitle.length, greaterThanOrEqualTo(1));
      expect(
        appTitle.length,
        lessThanOrEqualTo(30),
        reason: 'App Title <= 30 chars limit',
      );
      expect(appTitle, equals('Brick VPN'));

      // Extract Short Description
      final shortDescMatch = RegExp(r'### Short Description\s*\n`([^`]+)`')
          .firstMatch(content);
      expect(
        shortDescMatch,
        isNotNull,
        reason: 'Short Description block must exist',
      );
      final shortDesc = shortDescMatch!.group(1)!.trim();
      expect(shortDesc.length, greaterThanOrEqualTo(1));
      expect(
        shortDesc.length,
        lessThanOrEqualTo(80),
        reason: 'Short Description <= 80 chars limit',
      );

      // Extract Full Description
      final fullDescMatch = RegExp(
        r'### Full Description\s*\n([\s\S]+?)(?=\n\*\([^\)]+limit\)\*|\n## 2\.)',
      ).firstMatch(content);
      expect(
        fullDescMatch,
        isNotNull,
        reason: 'Full Description block must exist',
      );
      final fullDesc = fullDescMatch!.group(1)!.trim();
      expect(fullDesc.length, greaterThanOrEqualTo(100));
      expect(
        fullDesc.length,
        lessThanOrEqualTo(4000),
        reason: 'Full Description <= 4000 chars limit',
      );

      // Verify all 8 core supported protocols are mentioned
      final requiredProtocols = [
        'VLESS',
        'Reality',
        'VMess',
        'Trojan',
        'Shadowsocks',
        'WireGuard',
        'AmneziaWG',
        'Hysteria2',
        'TUIC',
      ];
      for (final proto in requiredProtocols) {
        expect(
          fullDesc.contains(proto),
          isTrue,
          reason: 'Full description must mention protocol $proto',
        );
      }

      // Verify open source & core engine mentioned
      expect(fullDesc.contains('Sing-box'), isTrue);
      expect(fullDesc.contains('GPL-3.0'), isTrue);
      expect(fullDesc.contains('Bring Your Own Server'), isTrue);

      // Verify 3-surface log redaction exact wording
      expect(
        fullDesc.contains(
          'Live UI viewer, clipboard export, and on-disk diagnostic logs',
        ),
        isTrue,
      );
    });

    test('Test 4: Privacy Policy Completeness & Permission Disclosure', () {
      final privacyFile = File('${repoRoot.path}/docs/privacy-policy.md');
      expect(
        privacyFile.existsSync(),
        isTrue,
        reason: 'docs/privacy-policy.md must exist',
      );
      final content = privacyFile.readAsStringSync();

      // Zero placeholders
      expect(
        content.contains('TODO'),
        isFalse,
        reason: 'privacy-policy.md must not contain TODO',
      );
      expect(
        content.contains('TBD'),
        isFalse,
        reason: 'privacy-policy.md must not contain TBD',
      );

      // Zero-data collection commitment
      expect(content.contains('zero-data-collection'), isTrue);
      expect(content.contains('GPL-3.0-or-later'), isTrue);

      // Check all 8 Android permissions
      final requiredPermissions = [
        'BIND_VPN_SERVICE',
        'INTERNET',
        'ACCESS_NETWORK_STATE',
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_SPECIAL_USE',
        'POST_NOTIFICATIONS',
        'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        'CAMERA',
      ];
      for (final perm in requiredPermissions) {
        expect(
          content.contains(perm),
          isTrue,
          reason: 'Privacy policy must disclose Android permission $perm',
        );
      }

      // Check log buffer, storage limits, and presentation surfaces
      final requiredLogAndStorageTerms = [
        'cache/brick_vpn_live.log',
        '1000 lines',
        '512 KB',
        'maxLogFileBytes',
        'LiveLogsScreen',
        'logs_copy_button',
      ];
      for (final term in requiredLogAndStorageTerms) {
        expect(
          content.contains(term),
          isTrue,
          reason: 'Privacy policy must contain term "$term"',
        );
      }

      // Check encrypted credential fields and scheme
      final requiredEncryptedFields = [
        'peer_public_key',
        'tls.reality.public_key',
        'short_id',
        'obfs.password',
        'plugin_opts',
        'transport.headers',
        'extra_params',
        'enc:v1:',
      ];
      for (final field in requiredEncryptedFields) {
        expect(
          content.contains(field),
          isTrue,
          reason: 'Privacy policy must disclose encrypted field "$field"',
        );
      }
    });
  });
}
