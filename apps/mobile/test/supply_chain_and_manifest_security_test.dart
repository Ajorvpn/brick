// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P8-T5 Dependency and Supply-Chain Security Test Suite', () {
    test('Test 1: AndroidManifest least-privilege permission and service '
        'enforcement', () {
      const approvedPermissions = <String>{
        'android.permission.INTERNET',
        'android.permission.ACCESS_NETWORK_STATE',
        'android.permission.BIND_VPN_SERVICE',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        'android.permission.CAMERA',
      };

      const prohibitedInvasivePermissions = <String>[
        'android.permission.READ_EXTERNAL_STORAGE',
        'android.permission.WRITE_EXTERNAL_STORAGE',
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
        'android.permission.READ_PHONE_STATE',
        'android.permission.READ_CONTACTS',
        'android.permission.RECORD_AUDIO',
        'android.permission.QUERY_ALL_PACKAGES',
        'android.permission.SYSTEM_ALERT_WINDOW',
        'android.permission.INSTALL_PACKAGES',
      ];

      final manifestFiles = [
        File('android/app/src/main/AndroidManifest.xml'),
        File(
          '../../packages/vpn_engine_android/android/src/main/'
          'AndroidManifest.xml',
        ),
      ];

      final declaredPermissions = <String>{};

      for (final file in manifestFiles) {
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Manifest file ${file.path} must exist',
        );
        final content = file.readAsStringSync();

        // Extract all <uses-permission android:name="..." />
        final permissionMatches = RegExp(
          r'<uses-permission(?:-[a-z0-9]+)?\b[^>]*?\bandroid:name\s*=\s*"([^"]+)"',
          multiLine: true,
          caseSensitive: false,
        ).allMatches(content);

        for (final match in permissionMatches) {
          final name = match.group(1);
          if (name != null) {
            declaredPermissions.add(name);
          }
        }

        // Assert zero prohibited/invasive permissions
        for (final prohibited in prohibitedInvasivePermissions) {
          expect(
            content.contains(prohibited),
            isFalse,
            reason: 'Prohibited permission $prohibited in ${file.path}',
          );
        }
      }

      expect(declaredPermissions, isNotEmpty);

      // Assert all declared permissions are in approved allowlist
      for (final permission in declaredPermissions) {
        expect(
          approvedPermissions.contains(permission),
          isTrue,
          reason: 'Unexpected unapproved permission: $permission',
        );
      }

      // Assert BrickVpnService has android:exported="false"
      final engineManifest = File(
        '../../packages/vpn_engine_android/android/src/main/'
        'AndroidManifest.xml',
      ).readAsStringSync();
      expect(engineManifest.contains('android:exported="false"'), isTrue);
      expect(
        engineManifest.contains(
          'android:permission="android.permission.BIND_VPN_SERVICE"',
        ),
        isTrue,
      );
    });

    test('Test 2: Dependabot configuration verification', () {
      final dependabotFile = File('../../.github/dependabot.yml');
      expect(
        dependabotFile.existsSync(),
        isTrue,
        reason: '.github/dependabot.yml must exist',
      );

      final content = dependabotFile.readAsStringSync();

      expect(content.contains('version: 2'), isTrue);

      // Verify ecosystems and directories are present
      expect(content.contains('package-ecosystem: "pub"'), isTrue);
      expect(content.contains('directory: "/apps/mobile/android"'), isTrue);
      expect(
        content.contains('directory: "/packages/vpn_engine_android/android"'),
        isTrue,
      );
      expect(content.contains('package-ecosystem: "github-actions"'), isTrue);
      expect(content.contains('interval: "weekly"'), isTrue);
    });

    test('Test 3: pubspec.lock supply-chain integrity verification', () {
      final lockFile = File('../../pubspec.lock');
      expect(
        lockFile.existsSync(),
        isTrue,
        reason: 'Root pubspec.lock must exist',
      );

      final lines = lockFile.readAsLinesSync();

      // Ensure zero unpinned git: dependencies
      expect(
        lines.any((l) => l.trim() == 'source: git'),
        isFalse,
        reason: 'pubspec.lock must not contain unpinned git: sources',
      );

      // Ensure all hosted packages point to official pub registry
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains('url: "') || line.contains("url: '")) {
          expect(
            line.contains('https://pub.dev') ||
                line.contains('https://pub.dartlang.org'),
            isTrue,
            reason:
                'Untrusted package registry URL found in pubspec.lock: $line',
          );
        }
      }

      // Verify neither cupertino_ui nor material_ui are direct dependencies
      for (final targetPkg in ['cupertino_ui:', 'material_ui:']) {
        final pkgIndex = lines.indexWhere(
          (l) => l.trim() == targetPkg && l.startsWith('  '),
        );
        if (pkgIndex != -1) {
          // Check subsequent lines until next top-level package
          var isDirect = false;
          for (var i = pkgIndex + 1; i < lines.length; i++) {
            final l = lines[i];
            if (l.startsWith('  ') && !l.startsWith('    ')) break;
            if (l.contains('dependency: "direct main"')) {
              isDirect = true;
              break;
            }
          }
          expect(
            isDirect,
            isFalse,
            reason: '$targetPkg must not be a direct dependency',
          );
        }
      }
    });

    test(
      'Test 4: scripts/generate_and_verify_checksums.sh end-to-end execution',
      () {
        final scriptFile = File(
          '../../scripts/generate_and_verify_checksums.sh',
        );
        expect(
          scriptFile.existsSync(),
          isTrue,
          reason: 'Checksum script must exist',
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'p8_t5_checksum_test_',
        );
        try {
          // Create dummy test artifacts including spaces in filename
          final artifact1 = File('${tempDir.path}/app-arm64-v8a-release.apk');
          final artifact2 = File(
            '${tempDir.path}/release artifact with space.apk',
          );
          final debugArtifact = File('${tempDir.path}/app-debug.apk');
          artifact1.writeAsStringSync('binary-data-arm64-node-test-1234');
          artifact2.writeAsStringSync('binary-data-custom-space-test-5678');
          debugArtifact.writeAsStringSync('binary-data-debug-artifact-1234');

          // Run checksum script targeting tempDir
          final result = Process.runSync('bash', [
            scriptFile.absolute.path,
            tempDir.path,
          ]);

          expect(
            result.exitCode,
            equals(0),
            reason: 'Script failed: ${result.stderr}\n${result.stdout}',
          );

          final sumsFile = File('${tempDir.path}/SHA256SUMS.txt');
          expect(sumsFile.existsSync(), isTrue);

          final lines = sumsFile.readAsLinesSync();
          expect(lines.length, equals(2));

          // Sorted order check
          expect(lines[0].contains('app-arm64-v8a-release.apk'), isTrue);
          expect(lines[1].contains('release artifact with space.apk'), isTrue);

          // Verify debug artifact is excluded from SHA256SUMS.txt
          final sumsContent = sumsFile.readAsStringSync();
          expect(sumsContent.contains('app-debug.apk'), isFalse);

          // Verify format: 64 hex characters followed by two spaces and name
          final lineRegex = RegExp(r'^[a-f0-9]{64}  .+$');
          expect(lineRegex.hasMatch(lines[0]), isTrue);
          expect(lineRegex.hasMatch(lines[1]), isTrue);

          // Tamper test: modify one byte in artifact1
          artifact1.writeAsStringSync('tampered-binary-data-attacker-999');
          final tamperCheck = Process.runSync('sha256sum', [
            '-c',
            '--ignore-missing',
            sumsFile.path,
          ], workingDirectory: tempDir.path);

          expect(
            tamperCheck.exitCode,
            isNot(equals(0)),
            reason: 'Tampering was not detected by sha256sum -c!',
          );
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );
  });
}
