// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory repoRoot;
  final verifyReleaseArtifacts =
      Platform.environment['VERIFY_RELEASE_ARTIFACTS'] == 'true';

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

  group('P10-T6: GitHub Release Publication Readiness Suite', () {
    test('Test 1: Release Notes Content, Protocols, Limitations & '
        'Checksums', () {
      final releaseNotesFile = File(
        '${repoRoot.path}/docs/release/github-release-v1.0.0.md',
      );
      expect(
        releaseNotesFile.existsSync(),
        isTrue,
        reason: 'docs/release/github-release-v1.0.0.md must exist',
      );
      final notes = releaseNotesFile.readAsStringSync();

      // Zero placeholder checks
      expect(notes.contains('TODO'), isFalse);
      expect(notes.contains('TBD'), isFalse);

      // Verify targetSdk 36 lock
      expect(notes.contains('targetSdk 36'), isTrue);

      // Verify all 8 core supported protocols
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
          notes.contains(proto),
          isTrue,
          reason: 'Release notes must mention protocol $proto',
        );
      }

      // Verify BYOS architecture, Sing-box engine, and GPL-3.0
      expect(notes.contains('Bring Your Own Server'), isTrue);
      expect(notes.contains('Sing-box'), isTrue);
      expect(notes.contains('GPL-3.0-or-later'), isTrue);

      // Verify Sideloading ("Install unknown apps") guide
      expect(notes.contains('Install unknown apps'), isTrue);
      expect(notes.contains('Special app access'), isTrue);
      expect(notes.contains('Allow from this source'), isTrue);

      // Verify 5 known limitations
      expect(notes.contains('Minimal Functional MVP UI'), isTrue);
      expect(notes.contains('Android-Only MVP Scope'), isTrue);
      expect(
        notes.contains('Unstructured Free-Text Native Log Redaction'),
        isTrue,
      );
      expect(notes.contains('OEM Background Killer Quirks'), isTrue);
      expect(notes.contains('Reproducible Builds'), isTrue);

      // Verify production certificate fingerprint
      expect(
        notes.toLowerCase().contains(
          '563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b',
        ),
        isTrue,
        reason:
            'Release notes must publish production SHA-256 cert fingerprint',
      );

      // Check SHA256SUMS matching if present on disk
      final checksumFile = File(
        '${repoRoot.path}/apps/mobile/build/app/outputs/flutter-apk/SHA256SUMS.txt',
      );
      if (checksumFile.existsSync()) {
        final checksumContent = checksumFile.readAsStringSync();
        for (final line in checksumContent.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final hash = parts[0].trim();
            final filename = parts[1].trim();
            expect(
              notes.contains(hash),
              isTrue,
              reason:
                  'Release notes must embed SHA-256 hash $hash for $filename',
            );
          }
        }
      }
    });

    test('Test 2: Root README.md Download & Installation Reference Audit', () {
      final readmeFile = File('${repoRoot.path}/README.md');
      expect(readmeFile.existsSync(), isTrue);
      final readme = readmeFile.readAsStringSync();

      expect(
        readme.contains('https://github.com/Ajorvpn/brick/releases'),
        isTrue,
      );
      expect(readme.contains('app-arm64-v8a-release.apk'), isTrue);
      expect(readme.contains('docs/verifying-releases.md'), isTrue);
      expect(readme.contains('docs/privacy-policy.md'), isTrue);
      expect(readme.contains('docs/release/github-release-v1.0.0.md'), isTrue);
    });

    test('Test 3: prepare_github_release_bundle.sh Execution & Validation', () {
      final scriptFile = File(
        '${repoRoot.path}/scripts/prepare_github_release_bundle.sh',
      );
      expect(scriptFile.existsSync(), isTrue);

      // Check executable permission
      final stat = scriptFile.statSync();
      expect(
        stat.mode & 0x49 != 0,
        isTrue,
        reason: 'prepare_github_release_bundle.sh must be executable',
      );

      if (verifyReleaseArtifacts) {
        final result = Process.runSync('bash', [scriptFile.path]);
        expect(
          result.exitCode,
          equals(0),
          reason:
              'prepare_github_release_bundle.sh stdout:\n${result.stdout}\n'
              'stderr:\n${result.stderr}',
        );
      }
    });
  });
}
