// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P10-T1 Release Signing & Key Isolation Security Suite', () {
    final repoRoot = Directory.current.parent.parent;

    test('Criterion 3: Zero private key or credential files in repo tree', () {
      final forbiddenExtensions = ['.jks', '.keystore', '.p12', '.pem', '.der'];
      final forbiddenFileNames = ['key.properties', 'keystore.env'];

      final foundViolations = <String>[];

      for (final entity in repoRoot.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final path = entity.path;

        // Skip build artifacts and git internals
        if (path.contains('/.git/') ||
            path.contains('/build/') ||
            path.contains('/.dart_tool/')) {
          continue;
        }

        final fileName = entity.uri.pathSegments.last;

        for (final ext in forbiddenExtensions) {
          if (fileName.endsWith(ext)) {
            foundViolations.add(path);
          }
        }

        for (final name in forbiddenFileNames) {
          if (fileName == name) {
            foundViolations.add(path);
          }
        }
      }

      expect(
        foundViolations,
        isEmpty,
        reason:
            'Private key material or credential files discovered in git tree: '
            '$foundViolations',
      );
    });

    test('Criterion 1 & 3: Defensive .gitignore rules block key material', () {
      final rootGitignore = File('${repoRoot.path}/.gitignore');
      expect(rootGitignore.existsSync(), isTrue);
      final rootContent = rootGitignore.readAsStringSync();

      expect(rootContent.contains('*.jks'), isTrue);
      expect(rootContent.contains('*.keystore'), isTrue);
      expect(rootContent.contains('*.p12'), isTrue);
      expect(rootContent.contains('key.properties'), isTrue);
      expect(rootContent.contains('keystore.env'), isTrue);

      final androidGitignore = File(
        '${repoRoot.path}/apps/mobile/android/.gitignore',
      );
      expect(androidGitignore.existsSync(), isTrue);
      final androidContent = androidGitignore.readAsStringSync();

      expect(androidContent.contains('*.jks'), isTrue);
      expect(androidContent.contains('*.keystore'), isTrue);
      expect(androidContent.contains('*.p12'), isTrue);
      expect(androidContent.contains('key.properties'), isTrue);
      expect(androidContent.contains('keystore.env'), isTrue);
    });

    test(
      'Criterion 2: build.gradle.kts configures release signing with v2/v3',
      () {
        final gradleFile = File(
          '${repoRoot.path}/apps/mobile/android/app/build.gradle.kts',
        );
        expect(gradleFile.existsSync(), isTrue);
        final content = gradleFile.readAsStringSync();

        // Verified signing config structure
        expect(content.contains('create("release")'), isTrue);
        expect(content.contains('enableV1Signing = false'), isTrue);
        expect(content.contains('enableV2Signing = true'), isTrue);
        expect(content.contains('enableV3Signing = true'), isTrue);

        // Verified environment and key.properties loading
        expect(
          content.contains('System.getenv("BRICK_KEYSTORE_PATH")'),
          isTrue,
        );
        expect(
          content.contains('System.getenv("BRICK_KEYSTORE_PASSWORD")'),
          isTrue,
        );
        expect(content.contains('System.getenv("BRICK_KEY_ALIAS")'), isTrue);
        expect(content.contains('System.getenv("BRICK_KEY_PASSWORD")'), isTrue);

        // Verified zero hardcoded passwords
        expect(content.contains('storePassword = "'), isFalse);
        expect(content.contains('keyPassword = "'), isFalse);
      },
    );

    test(
      'Criterion 3: CI pipeline includes signing & secure keystore wiping',
      () {
        final ciFile = File('${repoRoot.path}/.github/workflows/ci.yml');
        expect(ciFile.existsSync(), isTrue);
        final content = ciFile.readAsStringSync();

        expect(content.contains('ANDROID_KEYSTORE_BASE64'), isTrue);
        expect(content.contains('BRICK_KEYSTORE_PATH'), isTrue);
        expect(
          content.contains(
            'Release signing secrets are not configured in GitHub Actions',
          ),
          isTrue,
        );
        expect(content.contains('flutter build apk --release'), isTrue);
        expect(content.contains('flutter build appbundle --release'), isTrue);
        expect(content.contains('apksigner'), isTrue);
        expect(
          content.contains(
            '563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b',
          ),
          isTrue,
        );
        expect(content.contains('generate_and_verify_checksums.sh'), isTrue);
        expect(content.contains('Wipe ephemeral release keystore'), isTrue);
        expect(
          content.contains(r'rm -f "$RUNNER_TEMP/brickvpn-release.jks"'),
          isTrue,
        );
      },
    );

    test(
      'Criterion 4: verifying-releases.md publishes official SHA-256 digest',
      () {
        final verifyDoc = File('${repoRoot.path}/docs/verifying-releases.md');
        expect(verifyDoc.existsSync(), isTrue);
        final content = verifyDoc.readAsStringSync();

        expect(
          content.contains('[PENDING_PHASE10_PRODUCTION_KEY_FINGERPRINT]'),
          isFalse,
        );
        expect(
          content.contains(
            '563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b',
          ),
          isTrue,
        );
        expect(
          content.contains(
            '56:3D:AF:71:96:C5:65:AD:43:2B:F5:80:0E:2A:9E:AA:'
            'E0:A1:09:18:B0:48:9E:79:65:E6:3D:97:38:27:30:3B',
          ),
          isTrue,
        );
      },
    );

    test(
      'Criterion 4: release-signing-and-key-recovery.md documents parameters',
      () {
        final recoveryDoc = File(
          '${repoRoot.path}/docs/release-signing-and-key-recovery.md',
        );
        expect(recoveryDoc.existsSync(), isTrue);
        final content = recoveryDoc.readAsStringSync();

        expect(content.contains('4096 bits'), isTrue);
        expect(content.contains('SHA256withRSA'), isTrue);
        expect(content.contains('10,000 days'), isTrue);
        expect(content.contains('brickvpn_release'), isTrue);
        expect(
          content.contains('INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES'),
          isTrue,
        );
        expect(content.contains('Primary Secure Vault'), isTrue);
        expect(content.contains('Cold Offline Hardware Storage'), isTrue);
      },
    );
  });
}
