// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P10-T4 Google Play Store VPN Policy Compliance Suite', () {
    late final Directory repoRoot;

    setUpAll(() {
      var dir = Directory.current;
      while (!File('${dir.path}/pubspec.yaml').existsSync() ||
          !Directory('${dir.path}/packages').existsSync()) {
        final parent = dir.parent;
        if (parent.path == dir.path) {
          throw StateError('Could not find repository root');
        }
        dir = parent;
      }
      repoRoot = dir;
    });

    test('Criterion 3: Zero prohibited ad, tracking, or telemetry SDKs '
        'in build configs', () {
      const prohibitedPatterns = <String>[
        'google_mobile_ads',
        'admob',
        'firebase_analytics',
        'firebase_crashlytics',
        'facebook_app_events',
        'appsflyer',
        'adjust',
        'mixpanel',
        'amplitude',
        'onesignal',
        'sentry_flutter',
        'purchases_flutter',
        'unity_ads',
        'applovin',
      ];

      final filesToAudit = <File>[
        File('${repoRoot.path}/pubspec.yaml'),
        File('${repoRoot.path}/pubspec.lock'),
        File('${repoRoot.path}/apps/mobile/pubspec.yaml'),
        File('${repoRoot.path}/apps/mobile/android/app/build.gradle.kts'),
        File(
          '${repoRoot.path}/packages/vpn_engine_android/android/build.gradle.kts',
        ),
      ];

      for (final file in filesToAudit) {
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Audit file ${file.path} should exist',
        );
        final content = file.readAsStringSync().toLowerCase();
        for (final pattern in prohibitedPatterns) {
          expect(
            content.contains(pattern),
            isFalse,
            reason: 'Found prohibited SDK pattern "$pattern" in ${file.path}',
          );
        }
      }
    });

    test('Criterion 1 & 3: Manifest declares valid VpnService specialUse '
        'and zero AD_ID permissions', () {
      final manifests = <File>[
        File(
          '${repoRoot.path}/apps/mobile/android/app/src/main/AndroidManifest.xml',
        ),
        File(
          '${repoRoot.path}/packages/vpn_engine_android/android/src/main/AndroidManifest.xml',
        ),
      ];

      for (final manifest in manifests) {
        expect(manifest.existsSync(), isTrue);
        final content = manifest.readAsStringSync();

        // Zero advertising permissions
        expect(
          content.contains('com.google.android.gms.permission.AD_ID'),
          isFalse,
          reason: 'AD_ID permission must not exist in ${manifest.path}',
        );
        expect(
          content.contains('ACCESS_ADSERVICES_AD_ID'),
          isFalse,
          reason: 'ACCESS_ADSERVICES_AD_ID must not exist in ${manifest.path}',
        );
      }

      // Verify BrickVpnService specialUse declaration in plugin manifest
      final pluginManifest = File(
        '${repoRoot.path}/packages/vpn_engine_android/android/src/main/AndroidManifest.xml',
      );
      final pluginContent = pluginManifest.readAsStringSync();

      expect(
        pluginContent.contains(
          'android:permission="android.permission.BIND_VPN_SERVICE"',
        ),
        isTrue,
      );
      expect(pluginContent.contains('android:exported="false"'), isTrue);
      expect(
        pluginContent.contains('android:foregroundServiceType="specialUse"'),
        isTrue,
      );
      expect(
        pluginContent.contains(
          'android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"',
        ),
        isTrue,
      );
      expect(pluginContent.contains('android:value="vpn"'), isTrue);
    });

    test('Criterion 3: Zero ad-injection, ad-display, or analytics code '
        'in application sources', () {
      const prohibitedSourceTokens = <String>[
        'AdWidget',
        'InterstitialAd',
        'BannerAd',
        'RewardedAd',
        'AdvertisingIdClient',
        'FirebaseAnalytics',
      ];

      // Audit Dart files under apps/mobile/lib/
      final mobileLibDir = Directory('${repoRoot.path}/apps/mobile/lib');
      final dartFiles = mobileLibDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final dartFile in dartFiles) {
        final content = dartFile.readAsStringSync();
        for (final token in prohibitedSourceTokens) {
          expect(
            content.contains(token),
            isFalse,
            reason: 'Found forbidden token "$token" in ${dartFile.path}',
          );
        }
      }

      // Audit Kotlin files under packages/vpn_engine_android/
      final kotlinDir = Directory(
        '${repoRoot.path}/packages/vpn_engine_android/android/src/main/kotlin',
      );
      final kotlinFiles = kotlinDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt'));

      for (final ktFile in kotlinFiles) {
        final content = ktFile.readAsStringSync();
        for (final token in prohibitedSourceTokens) {
          expect(
            content.contains(token),
            isFalse,
            reason: 'Found forbidden token "$token" in ${ktFile.path}',
          );
        }
      }
    });

    test('Criterion 1 & 2: play-store-vpn-compliance.md contains all '
        'required declaration fields', () {
      final complianceDoc = File(
        '${repoRoot.path}/docs/release/play-store-vpn-compliance.md',
      );
      expect(
        complianceDoc.existsSync(),
        isTrue,
        reason: 'play-store-vpn-compliance.md deliverable must exist',
      );

      final content = complianceDoc.readAsStringSync();

      // Section 1: Policy matrix & encryption requirements
      expect(
        content.contains('Google Play VpnService Policy Requirements'),
        isTrue,
      );
      expect(
        content.contains('Mandatory Device-to-Endpoint Encryption'),
        isTrue,
      );
      expect(content.contains('Zero Ad Manipulation & Monetization'), isTrue);

      // Section 2: VpnService Declaration Form responses
      expect(
        content.contains('Is VPN the core functionality of your app?'),
        isTrue,
      );
      expect(
        content.contains(
          'Does your app encrypt all traffic from the device '
          'to the VPN tunnel endpoint?',
        ),
        isTrue,
      );
      expect(
        content.contains('Video Demonstration Walkthrough Script'),
        isTrue,
      );

      // Section 3: Foreground service declaration
      expect(content.contains('FOREGROUND_SERVICE_SPECIAL_USE'), isTrue);
      expect(
        content.contains('PROPERTY_SPECIAL_USE_FGS_SUBTYPE = "vpn"'),
        isTrue,
      );

      // Section 4: Data Safety questionnaire responses
      expect(content.contains('Data Safety Questionnaire'), isTrue);
      expect(
        content.contains(
          'Does your app collect or share any of the required user data types?',
        ),
        isTrue,
      );

      // Section 5: Codebase audit confirmation
      expect(content.contains('Monorepo Codebase Audit Confirmation'), isTrue);
    });
  });
}