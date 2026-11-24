// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';

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
        File('${repoRoot.path}/packages/core_domain/pubspec.yaml'),
        File('${repoRoot.path}/packages/config_parser/pubspec.yaml'),
        File('${repoRoot.path}/packages/core_vpn_engine/pubspec.yaml'),
        File('${repoRoot.path}/packages/shared_utils/pubspec.yaml'),
        File('${repoRoot.path}/packages/ui_theme/pubspec.yaml'),
        File('${repoRoot.path}/packages/vpn_engine_android/pubspec.yaml'),
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

      // Verify official Google Play Policy source link
      expect(
        content.contains(
          'https://support.google.com/googleplay/android-developer/answer/12564964',
        ),
        isTrue,
        reason: 'Policy document must cite official Google Play VpnService URL',
      );

      // Verify every referenced repo path in backticks genuinely exists
      final repoPathRegex = RegExp('`((?:apps|packages)/[^`]+)`');
      final matches = repoPathRegex.allMatches(content);
      expect(matches, isNotEmpty);

      for (final match in matches) {
        final relPath = match.group(1)!;
        final file = File('${repoRoot.path}/$relPath');
        final dir = Directory('${repoRoot.path}/$relPath');
        expect(
          file.existsSync() || dir.existsSync(),
          isTrue,
          reason:
              'Path "$relPath" cited in play-store-vpn-compliance.md '
              'does not exist on disk',
        );
      }
    });

    test('Alignment 1: zero external payment URLs or checkout strings in app '
        'sources and translations', () {
      const prohibitedPaymentTokens = <String>[
        'stripe.com',
        'buy.stripe',
        'paypal.com',
        'checkout.',
        'checkout_url',
        'upgrade to pro',
        'upgrade_to_pro',
        'in_app_purchase',
        'play_billing',
        'billingclient',
        'zarinpal',
        'idpay',
        'زرین‌پال',
        'ارتقا به پرو',
      ];

      final roots = <Directory>[
        Directory('${repoRoot.path}/apps/mobile/lib'),
        Directory('${repoRoot.path}/apps/mobile/assets/translations'),
      ];

      for (final root in roots) {
        expect(
          root.existsSync(),
          isTrue,
          reason: 'Payment-audit root ${root.path} must exist',
        );
        final files = root.listSync(recursive: true).whereType<File>();

        for (final file in files) {
          final content = file.readAsStringSync().toLowerCase();
          for (final token in prohibitedPaymentTokens) {
            expect(
              content.contains(token),
              isFalse,
              reason:
                  'Found prohibited payment token "$token" in '
                  '${file.path}',
            );
          }
        }
      }
    });

    test(
      'Alignment 1: onboarding and privacy copy carry accurate Free-plan '
      'wording, no rigid "no account ever" absolute, and EN/FA key parity',
      () {
        // German was retired in Alignment #1B; only EN + FA ship now.
        final deFile = File(
          '${repoRoot.path}/apps/mobile/assets/translations/de.json',
        );
        expect(
          deFile.existsSync(),
          isFalse,
          reason: 'de.json must not exist; the German locale was removed',
        );

        final en = jsonDecode(
          File('${repoRoot.path}/apps/mobile/assets/translations/en.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        final fa = jsonDecode(
          File('${repoRoot.path}/apps/mobile/assets/translations/fa.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;

        final rigidAbsolutes = <String>[
          'no account ever',
          'zero account',
          'never needs an account',
          'never require an account',
          'requires no account',
          '100% free forever',
          'no monetization',
          'no paid plan',
        ];

        // Persian equivalents of the same over-promises. `بدون نیاز به حساب`
        // is deliberately absent: it is the accurate Free-plan wording.
        final rigidAbsolutesFa = <String>[
          'بدون حساب برای همیشه',
          'هرگز نیاز به حساب ندارد',
          'بدون هیچ مدل درآمدی',
          'برای همیشه رایگان',
        ];

        void auditLeaves(
          Map<String, dynamic> doc,
          String locale, [
          List<String>? absolutes,
        ]) {
          final auditedAbsolutes = absolutes ?? rigidAbsolutes;
          void walk(Object? node, String path) {
            if (node is Map) {
              for (final entry in node.entries) {
                walk(entry.value, '$path.${entry.key}');
              }
              return;
            }
            if (node is List) {
              for (var i = 0; i < node.length; i++) {
                walk(node[i], '$path[$i]');
              }
              return;
            }
            final text = (node! as String).toLowerCase();
            expect(
              text.trim().isNotEmpty,
              isTrue,
              reason: 'Empty leaf at $path in $locale translations',
            );
            for (final absolute in auditedAbsolutes) {
              expect(
                text.contains(absolute),
                isFalse,
                reason:
                    'Rigid absolute "$absolute" remains at $path in $locale '
                    'translations',
              );
            }
          }

          walk(doc, locale);
        }

        // Zero contradictory absolutes anywhere in either locale.
        auditLeaves(en, 'en');
        auditLeaves(fa, 'fa', rigidAbsolutesFa);

        // The accurate Free-plan wording is actually present.
        final enOnboarding = en['onboarding'] as Map<String, dynamic>;
        final faOnboarding = fa['onboarding'] as Map<String, dynamic>;
        expect(
          (enOnboarding['step2_point1'] as String).toLowerCase(),
          contains('free to start'),
        );
        expect(
          (enOnboarding['step2_point1'] as String).toLowerCase(),
          contains('no account required'),
        );
        // Persian: "Free to start — no account required".
        expect(faOnboarding['step2_point1'] as String, contains('شروع رایگان'));
        expect(
          faOnboarding['step2_point1'] as String,
          contains('بدون نیاز به حساب'),
        );

        final enSettings = en['settings'] as Map<String, dynamic>;
        final faSettings = fa['settings'] as Map<String, dynamic>;
        expect(
          (enSettings['privacy_policy_body'] as String).toLowerCase(),
          contains('free plan needs no account'),
        );
        // Persian: "The Free plan needs no account."
        expect(
          faSettings['privacy_policy_body'] as String,
          contains('طرح رایگان به حساب کاربری نیاز ندارد'),
        );
        // The future Pro disclosure must survive translation too.
        expect(
          faSettings['privacy_policy_body'] as String,
          contains('Brick Pro'),
        );

        // Recursive EN/FA key parity for the audited surfaces.
        Set<String> leafKeys(Object? node, [String prefix = '']) {
          if (node is Map) {
            return {
              for (final entry in node.entries)
                ...leafKeys(entry.value, '$prefix.${entry.key}'),
            };
          }
          return {prefix};
        }

        expect(leafKeys(en), equals(leafKeys(fa)));
      },
    );

    test('Item #4: anonymous server-probe diagnostics are strictly opt-in and '
        'honestly disclosed under Google Play Data Safety', () {
      // 1. Default OFF everywhere: fake repo (used by every widget test and
      //    by the app when preferences are unavailable) and production.
      expect(
        FakeAppPreferencesRepository().isAnonymousProbeReportingEnabled(),
        isFalse,
        reason: 'Anonymous diagnostics must be opt-in only',
      );

      // 2. Still zero prohibited third-party analytics/telemetry SDKs in the
      //    build configs that ship the app.
      const prohibitedAnalytics = <String>[
        'firebase_analytics',
        'firebase_crashlytics',
        'firebase_core',
        'posthog',
        'mixpanel',
        'amplitude',
        'appsflyer',
        'adjust',
        'datadog',
        'segment_analytics',
        'sentry_flutter',
        'braze',
        'bugsnag',
      ];
      final buildConfigs = <File>[
        File('${repoRoot.path}/apps/mobile/pubspec.yaml'),
        File('${repoRoot.path}/apps/mobile/android/app/build.gradle.kts'),
      ];
      for (final file in buildConfigs) {
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync().toLowerCase();
        for (final sdk in prohibitedAnalytics) {
          expect(
            content.contains(sdk),
            isFalse,
            reason:
                'Found prohibited analytics/telemetry SDK "$sdk" in '
                '${file.path}',
          );
        }
      }

      // 3. The privacy policy discloses the optional diagnostics instead of
      //    claiming that nothing can ever leave the device.
      final privacy = File('${repoRoot.path}/docs/privacy-policy.md')
          .readAsStringSync();
      expect(privacy.contains('Anonymous Server Health Diagnostics'), isTrue);
      expect(privacy.toLowerCase(), contains('off by default'));
      expect(privacy.contains('node_hash'), isTrue);
      expect(privacy.contains('Data Safety'), isTrue);
      // Permanent invariants survive the addition.
      expect(privacy.contains('Zero Traffic Logging'), isTrue);
      expect(privacy.contains('zero-data-collection'), isTrue);

      // 4. The Play compliance doc maps the payload to the exact Data Safety
      //    category and marks it optional and unlinked.
      final compliance = File(
        '${repoRoot.path}/docs/release/play-store-vpn-compliance.md',
      ).readAsStringSync();
      expect(compliance.contains('App info and performance'), isTrue);
      expect(compliance.contains('Diagnostics'), isTrue);
      expect(compliance.toLowerCase(), contains('optional'));
      expect(compliance.toLowerCase(), contains('off by default'));
      expect(compliance.contains('node_hash'), isTrue);
      expect(
        compliance.contains('Not linked to identity'),
        isTrue,
        reason: 'The Data Safety answer must state the data is unlinked',
      );
    });
  });
}
