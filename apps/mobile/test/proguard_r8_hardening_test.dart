// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P10-T2 / P10-T3 ProGuard / R8 Hardening & Dual Distribution Suite', () {
    late final Directory repoRoot;
    final requireBuiltArtifacts =
        Platform.environment['VERIFY_RELEASE_ARTIFACTS'] == 'true';

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

    test(
      'Criterion 1: build.gradle.kts enables R8 minification & shrinking',
      () {
        final gradleFile = File(
          '${repoRoot.path}/apps/mobile/android/app/build.gradle.kts',
        );
        expect(gradleFile.existsSync(), isTrue);
        final content = gradleFile.readAsStringSync();

        expect(content.contains('isMinifyEnabled = true'), isTrue);
        expect(content.contains('isShrinkResources = true'), isTrue);
        expect(content.contains('proguard-android-optimize.txt'), isTrue);
        expect(content.contains('proguard-rules.pro'), isTrue);
      },
    );

    test('Criterion 1: vpn_engine_android declares consumerProguardFiles', () {
      final buildFile = File(
        '${repoRoot.path}/packages/vpn_engine_android/android/build.gradle.kts',
      );
      expect(buildFile.existsSync(), isTrue);
      final content = buildFile.readAsStringSync();

      expect(
        content.contains('consumerProguardFiles("proguard-rules.pro")'),
        isTrue,
      );
    });

    test('Criterion 1: vpn_engine_android keeps gomobile', () {
      final rulesFile = File(
        '${repoRoot.path}/packages/vpn_engine_android/android/proguard-rules.pro',
      );
      expect(rulesFile.existsSync(), isTrue);
      final content = rulesFile.readAsStringSync();

      // Gomobile runtime keep rules
      expect(content.contains('-keep class go.** { *; }'), isTrue);
      expect(content.contains('-dontwarn go.**'), isTrue);

      // Sing-box / Libbox keep rules
      expect(
        content.contains('-keep class io.nekohasekai.libbox.** { *; }'),
        isTrue,
      );
      expect(
        content.contains('-keep interface io.nekohasekai.libbox.** { *; }'),
        isTrue,
      );
      expect(content.contains('-dontwarn io.nekohasekai.libbox.**'), isTrue);
      expect(content.contains('-keep class libbox.** { *; }'), isTrue);
      expect(content.contains('-keep interface libbox.** { *; }'), isTrue);
      expect(content.contains('-dontwarn libbox.**'), isTrue);

      // Plugin harness keep rules
      expect(
        content.contains('-keep class dev.brickvpn.harness.** { *; }'),
        isTrue,
      );
      expect(
        content.contains('-keep interface dev.brickvpn.harness.** { *; }'),
        isTrue,
      );

      // Optimization attributes preservation
      expect(
        content.contains(
          <String>[
            '-keepattributes *Annotation*,Signature,InnerClasses,',
            'EnclosingMethod,Exceptions,SourceFile,LineNumberTable',
          ].join(),
        ),
        isTrue,
      );

      // Enum static method preservation
      expect(content.contains('-keepclassmembers enum * {'), isTrue);
    });

    test('Criterion 1: app proguard rules keep Flutter & native methods', () {
      final appRulesFile = File(
        '${repoRoot.path}/apps/mobile/android/app/proguard-rules.pro',
      );
      expect(appRulesFile.existsSync(), isTrue);
      final content = appRulesFile.readAsStringSync();

      // Flutter embedding keep rules
      expect(content.contains('-keep class io.flutter.app.** { *; }'), isTrue);
      expect(
        content.contains('-keep class io.flutter.plugin.** { *; }'),
        isTrue,
      );
      expect(
        content.contains('-keep class io.flutter.plugins.** { *; }'),
        isTrue,
      );
      expect(
        content.contains('-dontwarn com.google.android.play.core.**'),
        isTrue,
      );

      // Gomobile & Libbox keep rules
      expect(content.contains('-keep class go.** { *; }'), isTrue);
      expect(
        content.contains('-keep class io.nekohasekai.libbox.** { *; }'),
        isTrue,
      );
      expect(
        content.contains('-keep class dev.brickvpn.harness.** { *; }'),
        isTrue,
      );

      // Native method preservation
      expect(
        content.contains(
          '-keepclasseswithmembernames class * {\n    native <methods>;\n}',
        ),
        isTrue,
      );

      // Optimization attributes preservation
      expect(
        content.contains(
          <String>[
            '-keepattributes *Annotation*,Signature,InnerClasses,',
            'EnclosingMethod,Exceptions,SourceFile,LineNumberTable',
          ].join(),
        ),
        isTrue,
      );
      expect(content.contains('-renamesourcefileattribute SourceFile'), isTrue);

      // Enum static method preservation
      expect(content.contains('-keepclassmembers enum * {'), isTrue);

      // Google ML Kit Barcode Scanning & Barhopper keep rules
      expect(
        content.contains(
          '-keep class com.google.android.libraries.barhopper.**',
        ),
        isTrue,
      );
      expect(content.contains('-keep class com.google.mlkit.**'), isTrue);

      // AndroidX CameraX & DataStore keep rules
      expect(content.contains('-keep class androidx.camera.**'), isTrue);
      expect(content.contains('-keep class androidx.datastore.**'), isTrue);

      // Application MainActivity & Flutter plugin registrants
      expect(content.contains('-keep class dev.brickvpn.mobile.**'), isTrue);
    });

    test('Criterion 1 & 2: R8 seeds.txt preserves gomobile and libbox', () {
      final seedsFile = File(
        '${repoRoot.path}/apps/mobile/build/app/outputs/mapping/release/seeds.txt',
      );
      if (requireBuiltArtifacts || seedsFile.existsSync()) {
        expect(
          seedsFile.existsSync(),
          isTrue,
          reason: 'R8 seeds.txt must exist from release build',
        );
        final seeds = seedsFile.readAsStringSync();
        expect(seeds.contains('go.Seq'), isTrue);
        expect(seeds.contains('io.nekohasekai.libbox'), isTrue);
        expect(seeds.contains('dev.brickvpn.harness'), isTrue);
        expect(seeds.contains('dev.brickvpn.mobile.MainActivity'), isTrue);
        expect(seeds.contains('barhopper'), isTrue);
      }
    });

    test('P10-T3: CI pipeline builds split-ABI, universal APK, and bundle', () {
      final ciFile = File('${repoRoot.path}/.github/workflows/ci.yml');
      expect(ciFile.existsSync(), isTrue);
      final content = ciFile.readAsStringSync();

      expect(
        content.contains('flutter build apk --release --split-per-abi'),
        isTrue,
      );
      expect(content.contains('flutter build apk --release'), isTrue);
      expect(content.contains('flutter build appbundle --release'), isTrue);
      expect(
        content.contains(
          'cp build/app/outputs/bundle/release/app-release.aab '
          'build/app/outputs/flutter-apk/app-release.aab',
        ),
        isTrue,
      );
      expect(
        content.contains(
          'for apk in apps/mobile/build/app/outputs/flutter-apk/*.apk; do',
        ),
        isTrue,
      );
      expect(
        content.contains(
          'keytool -printcert -jarfile '
          'apps/mobile/build/app/outputs/bundle/release/app-release.aab',
        ),
        isTrue,
      );
      expect(
        content.contains(
          <String>[
            '56:3D:AF:71:96:C5:65:AD:43:2B:F5:80:0E:2A:9E:AA:',
            'E0:A1:09:18:B0:48:9E:79:65:E6:3D:97:38:27:30:3B',
          ].join(),
        ),
        isTrue,
      );
    });

    test('P10-T3 Criterion 1 & 2: Built AAB and Split-ABI APKs contain exact '
        'expected native ABI .so libraries', () {
      final aabFile = File(
        '${repoRoot.path}/apps/mobile/build/app/outputs/bundle/release/app-release.aab',
      );
      final arm64Apk = File(
        '${repoRoot.path}/apps/mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
      );
      final arm32Apk = File(
        '${repoRoot.path}/apps/mobile/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk',
      );
      final x8664Apk = File(
        '${repoRoot.path}/apps/mobile/build/app/outputs/flutter-apk/app-x86_64-release.apk',
      );
      final universalApk = File(
        '${repoRoot.path}/apps/mobile/build/app/outputs/flutter-apk/app-release.apk',
      );

      if (requireBuiltArtifacts || aabFile.existsSync()) {
        expect(
          aabFile.existsSync(),
          isTrue,
          reason: 'app-release.aab must exist on disk',
        );
        expect(
          arm64Apk.existsSync(),
          isTrue,
          reason: 'app-arm64-v8a-release.apk must exist on disk',
        );
        expect(
          arm32Apk.existsSync(),
          isTrue,
          reason: 'app-armeabi-v7a-release.apk must exist on disk',
        );
        expect(
          x8664Apk.existsSync(),
          isTrue,
          reason: 'app-x86_64-release.apk must exist on disk',
        );
        expect(
          universalApk.existsSync(),
          isTrue,
          reason: 'app-release.apk must exist on disk',
        );

        // 1. Inspect app-release.aab
        final aabResult = Process.runSync('unzip', <String>[
          '-Z1',
          aabFile.path,
        ]);
        expect(aabResult.exitCode, equals(0));
        final aabLines = (aabResult.stdout as String).split('\n');

        expect(aabLines.contains('base/lib/arm64-v8a/libgojni.so'), isTrue);
        expect(aabLines.contains('base/lib/arm64-v8a/libapp.so'), isTrue);
        expect(aabLines.contains('base/lib/armeabi-v7a/libgojni.so'), isTrue);
        expect(aabLines.contains('base/lib/armeabi-v7a/libapp.so'), isTrue);
        expect(aabLines.contains('base/lib/x86_64/libgojni.so'), isTrue);
        expect(aabLines.contains('base/lib/x86_64/libapp.so'), isTrue);

        // 2. Inspect app-arm64-v8a-release.apk
        final arm64Result = Process.runSync('unzip', <String>[
          '-Z1',
          arm64Apk.path,
        ]);
        expect(arm64Result.exitCode, equals(0));
        final arm64Lines = (arm64Result.stdout as String).split('\n');
        expect(arm64Lines.contains('lib/arm64-v8a/libgojni.so'), isTrue);
        expect(arm64Lines.contains('lib/arm64-v8a/libapp.so'), isTrue);
        expect(
          arm64Lines.any((l) => l.startsWith('lib/armeabi-v7a/')),
          isFalse,
        );
        expect(arm64Lines.any((l) => l.startsWith('lib/x86_64/')), isFalse);

        // Verify compiled binary manifest has android:label="Brick VPN"
        final androidHome =
            Platform.environment['ANDROID_HOME'] ??
            Platform.environment['ANDROID_SDK_ROOT'] ??
            '/home/bellard/Android/Sdk';
        final apkanalyzerBin = File(
          '$androidHome/cmdline-tools/latest/bin/apkanalyzer',
        );
        final aaptBin = File('$androidHome/build-tools/36.0.0/aapt');

        var manifestOutput = '';
        if (apkanalyzerBin.existsSync()) {
          final res = Process.runSync(apkanalyzerBin.path, <String>[
            'manifest',
            'print',
            arm64Apk.path,
          ]);
          expect(res.exitCode, equals(0));
          manifestOutput = res.stdout as String;
        } else if (aaptBin.existsSync()) {
          final res = Process.runSync(aaptBin.path, <String>[
            'dump',
            'badging',
            arm64Apk.path,
          ]);
          expect(res.exitCode, equals(0));
          manifestOutput = res.stdout as String;
        } else {
          final res = Process.runSync('apkanalyzer', <String>[
            'manifest',
            'print',
            arm64Apk.path,
          ], runInShell: true);
          expect(res.exitCode, equals(0));
          manifestOutput = res.stdout as String;
        }
        expect(manifestOutput.contains('Brick VPN'), isTrue);
        expect(manifestOutput.contains('android:label="mobile"'), isFalse);

        // 3. Inspect app-armeabi-v7a-release.apk
        final arm32Result = Process.runSync('unzip', <String>[
          '-Z1',
          arm32Apk.path,
        ]);
        expect(arm32Result.exitCode, equals(0));
        final arm32Lines = (arm32Result.stdout as String).split('\n');
        expect(arm32Lines.contains('lib/armeabi-v7a/libgojni.so'), isTrue);
        expect(arm32Lines.contains('lib/armeabi-v7a/libapp.so'), isTrue);
        expect(arm32Lines.any((l) => l.startsWith('lib/arm64-v8a/')), isFalse);
        expect(arm32Lines.any((l) => l.startsWith('lib/x86_64/')), isFalse);

        // 4. Inspect app-x86_64-release.apk
        final x86Result = Process.runSync('unzip', <String>[
          '-Z1',
          x8664Apk.path,
        ]);
        expect(x86Result.exitCode, equals(0));
        final x86Lines = (x86Result.stdout as String).split('\n');
        expect(x86Lines.contains('lib/x86_64/libgojni.so'), isTrue);
        expect(x86Lines.contains('lib/x86_64/libapp.so'), isTrue);
        expect(x86Lines.any((l) => l.startsWith('lib/arm64-v8a/')), isFalse);
        expect(x86Lines.any((l) => l.startsWith('lib/armeabi-v7a/')), isFalse);

        // 5. Inspect universal app-release.apk
        final universalResult = Process.runSync('unzip', <String>[
          '-Z1',
          universalApk.path,
        ]);
        expect(universalResult.exitCode, equals(0));
        final universalLines = (universalResult.stdout as String).split('\n');
        expect(universalLines.contains('lib/arm64-v8a/libgojni.so'), isTrue);
        expect(universalLines.contains('lib/armeabi-v7a/libgojni.so'), isTrue);
        expect(universalLines.contains('lib/x86_64/libgojni.so'), isTrue);
      }
    });
  });
}
