// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_theme/ui_theme.dart';

/// Freezes the Phase 11 ("Obsidian Glass & Brick Ember") UI/UX contract.
///
/// These are static, deterministic contract checks: no widget pumping, no
/// timers, no platform channels. They exist so that a later phase cannot
/// silently regress the design system, the bundled-typography policy, the
/// localization surface, or the governance truth rules.
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

  File file(String relativePath) => File('${repoRoot.path}/$relativePath');

  String read(String relativePath) {
    final target = file(relativePath);
    expect(target.existsSync(), isTrue, reason: '$relativePath must exist');
    return target.readAsStringSync();
  }

  /// Extracts a roadmap task block starting at `### <taskId>`.
  String roadmapBlock(String content, String taskId) {
    final start = content.indexOf('### $taskId');
    expect(
      start,
      greaterThanOrEqualTo(0),
      reason: '$taskId must be in ROADMAP',
    );
    final tail = content.substring(start);
    final end = tail.indexOf('\n### ', 4);
    return end < 0 ? tail : tail.substring(0, end);
  }

  /// Flattens every nested key path of a translation document.
  Set<String> leafPaths(Map<String, dynamic> node, [String prefix = '']) {
    final paths = <String>{};
    node.forEach((key, value) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        paths.addAll(leafPaths(value, path));
      } else {
        paths.add(path);
      }
    });
    return paths;
  }

  void expectLeavesNonEmpty(Map<String, dynamic> node, String path) {
    node.forEach((key, value) {
      final next = path.isEmpty ? key : '$path.$key';
      if (value is Map<String, dynamic>) {
        expectLeavesNonEmpty(value, next);
      } else {
        expect(value, isA<String>(), reason: '$next must be a string');
        expect(
          (value as String).trim(),
          isNotEmpty,
          reason: '$next must not be empty',
        );
      }
    });
  }

  group('P11-T7: Phase 11 UI/UX Closeout Contract Suite', () {
    test('Test 1: Phase 11 deliverables exist, are non-empty and carry SPDX '
        'headers', () {
      const lib = 'apps/mobile/lib';
      final dartDeliverables = <String>[
        'docs/design/style-guide.md',
        'docs/design/phase11-ui-ux-closeout-report.md',
        '$lib/features/onboarding/presentation/screens/onboarding_screen.dart',
        'packages/ui_theme/lib/src/widgets/brick_glass_card.dart',
        'packages/ui_theme/lib/src/widgets/brick_protocol_pill.dart',
        'packages/ui_theme/lib/src/widgets/brick_status_dot.dart',
        'packages/ui_theme/lib/src/widgets/brick_section_header.dart',
        'packages/ui_theme/lib/src/widgets/brick_power_orb.dart',
        'packages/ui_theme/lib/src/widgets/brick_telemetry_card.dart',
        'packages/ui_theme/lib/src/widgets/brick_skeleton_box.dart',
      ];

      for (final relativePath in dartDeliverables) {
        final target = file(relativePath);
        expect(
          target.existsSync(),
          isTrue,
          reason: '$relativePath must exist on disk',
        );
        expect(
          target.lengthSync(),
          greaterThan(0),
          reason: '$relativePath must not be empty',
        );
        if (relativePath.endsWith('.dart')) {
          expect(
            target.readAsStringSync().startsWith(
              '// SPDX-License-Identifier: GPL-3.0-or-later',
            ),
            isTrue,
            reason:
                '$relativePath must start with the GPL-3.0-or-later SPDX '
                'identifier',
          );
        }
      }

      // The closeout report must be a real report, not a stub.
      final report = read('docs/design/phase11-ui-ux-closeout-report.md');
      expect(report.length, greaterThan(4000));
      expect(report.contains('P11-T7'), isTrue);
      expect(report.contains('Human Physical-Device Walkthrough'), isTrue);
    });

    test(
      'Test 2: bundled OFL-1.1 fonts, Invariant 37 and pubspec contract',
      () {
        final pubspec = read('apps/mobile/pubspec.yaml');

        // Family names must match the typography layer byte-for-byte, otherwise
        // the bundled assets would never be selected at runtime.
        expect(
          pubspec.contains('family: ${BrickTypography.primaryFontFamily}'),
          isTrue,
        );
        expect(
          pubspec.contains('family: ${BrickTypography.monoFontFamily}'),
          isTrue,
        );
        expect(BrickTypography.primaryFontFamily, 'Inter');
        expect(BrickTypography.monoFontFamily, 'JetBrains Mono');

        // Invariant 37: zero runtime network font fetching.
        expect(
          pubspec.contains('google_fonts'),
          isFalse,
          reason: 'Invariant 37 forbids runtime network font fetching',
        );

        const ttfAssets = <String>[
          'apps/mobile/assets/fonts/InterVariable.ttf',
          'apps/mobile/assets/fonts/JetBrainsMono-Regular.ttf',
          'apps/mobile/assets/fonts/JetBrainsMono-Medium.ttf',
          'apps/mobile/assets/fonts/JetBrainsMono-Bold.ttf',
        ];
        const licenceAssets = <String>[
          'apps/mobile/assets/fonts/OFL-Inter.txt',
          'apps/mobile/assets/fonts/OFL-JetBrainsMono.txt',
        ];

        var totalTtfBytes = 0;
        for (final relativePath in ttfAssets) {
          final target = file(relativePath);
          expect(target.existsSync(), isTrue, reason: '$relativePath missing');
          totalTtfBytes += target.lengthSync();

          final bytes = target.readAsBytesSync();
          expect(bytes.length, greaterThan(12));
          final signature = bytes.sublist(0, 4);
          final hex = signature
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          final isSfnt =
              hex == '00010000' ||
              hex == '4f54544f' || // 'OTTO'
              hex == '74727565' || // 'true'
              hex == '74746366'; // 'ttcf'
          expect(isSfnt, isTrue, reason: '$relativePath is not an sfnt font');
        }
        expect(
          totalTtfBytes,
          lessThan(5 * 1024 * 1024),
          reason: 'Bundled .ttf payload must stay under the 5 MB ceiling',
        );

        for (final relativePath in licenceAssets) {
          final target = file(relativePath);
          expect(target.existsSync(), isTrue, reason: '$relativePath missing');
          final text = target.readAsStringSync();
          expect(text.contains('SIL OPEN FONT LICENSE'), isTrue);
        }
      },
    );

    test('Test 3: recursive EN <-> FA localization parity, placeholder parity '
        'and clean trailing newlines', () {
      const enPath = 'apps/mobile/assets/translations/en.json';
      const faPath = 'apps/mobile/assets/translations/fa.json';

      // The German locale was retired in Alignment #1B: the app ships English
      // and Persian only, so a resurrected de.json must fail this contract.
      expect(
        file('apps/mobile/assets/translations/de.json').existsSync(),
        isFalse,
        reason: 'de.json must not ship; German was replaced by Persian',
      );

      final enRaw = read(enPath);
      final faRaw = read(faPath);

      for (final entry in <String, String>{
        enPath: enRaw,
        faPath: faRaw,
      }.entries) {
        expect(
          entry.value.endsWith('\n'),
          isTrue,
          reason: '${entry.key} must end with a newline',
        );
        expect(
          entry.value.endsWith('\n\n'),
          isFalse,
          reason: '${entry.key} must not end with a blank line',
        );
      }

      final en = jsonDecode(enRaw) as Map<String, dynamic>;
      final fa = jsonDecode(faRaw) as Map<String, dynamic>;

      final enKeys = leafPaths(en);
      final faKeys = leafPaths(fa);

      expect(enKeys, isNotEmpty);
      expect(
        enKeys.difference(faKeys),
        isEmpty,
        reason: 'Keys present in EN but missing in FA',
      );
      expect(
        faKeys.difference(enKeys),
        isEmpty,
        reason: 'Keys present in FA but missing in EN',
      );

      expectLeavesNonEmpty(en, '');
      expectLeavesNonEmpty(fa, '');

      // Every `{placeholder}` must survive translation verbatim, otherwise
      // easy_localization's namedArgs interpolation renders a literal token.
      Map<String, String> flatLeaves(
        Map<String, dynamic> node, [
        String prefix = '',
      ]) {
        final out = <String, String>{};
        node.forEach((key, value) {
          final path = prefix.isEmpty ? key : '$prefix.$key';
          if (value is Map<String, dynamic>) {
            out.addAll(flatLeaves(value, path));
          } else {
            out[path] = value as String;
          }
        });
        return out;
      }

      final enFlat = flatLeaves(en);
      final faFlat = flatLeaves(fa);
      final placeholder = RegExp(r'\{[A-Za-z0-9_]+\}');

      for (final key in enFlat.keys) {
        Set<String?> tokens(String value) => placeholder
            .allMatches(value)
            .map((match) => match.group(0))
            .toSet();
        expect(
          tokens(faFlat[key]!),
          equals(tokens(enFlat[key]!)),
          reason: 'Placeholder drift at "$key" between EN and FA',
        );
      }
    });

    test('Test 4: design-system anti-regression source guard across the five '
        'redesigned screens and the app shell', () {
      const lib = 'apps/mobile/lib';
      final screens = <String>[
        '$lib/core/presentation/widgets/app_shell.dart',
        '$lib/features/connection/presentation/screens/home_screen.dart',
        '$lib/features/servers/presentation/screens/servers_screen.dart',
        '$lib/features/settings/presentation/screens/settings_screen.dart',
        '$lib/features/settings/presentation/screens/live_logs_screen.dart',
        '$lib/features/onboarding/presentation/screens/onboarding_screen.dart',
      ];

      for (final relativePath in screens) {
        final source = read(relativePath);
        expect(
          source.contains('FontWeight.w600'),
          isFalse,
          reason: '$relativePath must use only w400/w500/w700',
        );
        expect(
          source.contains('Colors.orange'),
          isFalse,
          reason: '$relativePath must use Brick semantic colors',
        );
        expect(
          source.contains("fontFamily: 'monospace'"),
          isFalse,
          reason: '$relativePath must use BrickTypography.monoFontFamily',
        );
        // The closeout report's "no 13sp" and "onAccent on brand fills" claims
        // are enforced here, not merely asserted in prose.
        expect(
          source.contains('fontSize: 13'),
          isFalse,
          reason: '$relativePath must stay on the 4-size type scale (no 13sp)',
        );
        expect(
          source.contains('foregroundColor: Colors.white'),
          isFalse,
          reason: '$relativePath must never paint Colors.white on a fill',
        );
      }

      for (final relativePath in <String>[
        '$lib/features/connection/presentation/screens/home_screen.dart',
        '$lib/features/settings/presentation/screens/settings_screen.dart',
        '$lib/features/settings/presentation/screens/live_logs_screen.dart',
        '$lib/features/onboarding/presentation/screens/onboarding_screen.dart',
      ]) {
        expect(
          read(relativePath).contains('colors.onAccent'),
          isTrue,
          reason: '$relativePath must use colors.onAccent on brand fills',
        );
      }

      final shell = read(screens.first);
      expect(
        shell.contains('extendBody: true'),
        isTrue,
        reason: 'The dock must float over real content for the blur to work',
      );
      expect(
        shell.contains('Opacity('),
        isFalse,
        reason: 'Ghost opacity widgets are forbidden in the dock',
      );

      final router = read('apps/mobile/lib/core/router/app_router.dart');
      expect(
        router.contains('ref.read(onboardingCompletedProvider)'),
        isTrue,
        reason: 'The first-run gate must read (not watch) the preference',
      );
      expect(
        router.contains('ref.watch(onboardingCompletedProvider)'),
        isFalse,
        reason: 'Watching the gate would rebuild the keepAlive router',
      );
    });

    test('Test 5: reduced motion and optical typography across ui_theme '
        'primitives', () {
      const animatedPrimitives = <String>[
        'packages/ui_theme/lib/src/widgets/brick_power_orb.dart',
        'packages/ui_theme/lib/src/widgets/brick_status_dot.dart',
        'packages/ui_theme/lib/src/widgets/brick_skeleton_box.dart',
        'packages/ui_theme/lib/src/widgets/brick_glass_card.dart',
      ];

      for (final relativePath in animatedPrimitives) {
        final source = read(relativePath);
        expect(
          source.contains('MediaQuery.disableAnimationsOf(context)'),
          isTrue,
          reason: '$relativePath must honour WCAG 2.1 SC 2.3.3',
        );
      }

      const color = Color(0xFF000000);
      final regular = BrickTypography.uiStyle(
        fontSize: BrickTypography.sizeBody,
        fontWeight: FontWeight.w400,
        color: color,
      );
      final medium = BrickTypography.uiStyle(
        fontSize: BrickTypography.sizeBody,
        fontWeight: FontWeight.w500,
        color: color,
      );
      final bold = BrickTypography.uiStyle(
        fontSize: BrickTypography.sizeBody,
        fontWeight: FontWeight.w700,
        color: color,
      );

      expect(regular.fontVariations, const <FontVariation>[
        FontVariation('wght', 400),
      ]);
      expect(medium.fontVariations, const <FontVariation>[
        FontVariation('wght', 500),
      ]);
      expect(bold.fontVariations, const <FontVariation>[
        FontVariation('wght', 700),
      ]);
      expect(regular.fontFamily, 'Inter');
      expect(regular.fontFamilyFallback, BrickTypography.primaryFontFallbacks);
    });

    test('Test 6: governance consistency — truth rule and status cap', () {
      final architecture = read('AI_ROLES/ARCHITECTURE.md');

      for (final section in <String>['13.3', '13.4', '13.5', '13.6', '13.7']) {
        expect(
          architecture.contains('### $section'),
          isTrue,
          reason: 'ARCHITECTURE.md must document $section',
        );
      }
      expect(
        architecture.contains('Section 13.x'),
        isFalse,
        reason: 'No unresolved section placeholders may remain',
      );

      final roadmap = read('AI_ROLES/ROADMAP.md');

      // P11-T1 was accepted by the human; nothing after it may claim
      // completion without the same sign-off.
      expect(
        roadmapBlock(roadmap, 'P11-T1').contains('Completed'),
        isTrue,
        reason: 'P11-T1 is human-approved',
      );
      for (final taskId in <String>[
        'P11-T2',
        'P11-T3',
        'P11-T4',
        'P11-T5',
        'P11-T6',
      ]) {
        final block = roadmapBlock(roadmap, taskId);
        expect(
          block.contains('**Status:** Ready for Human Review'),
          isTrue,
          reason: '$taskId must stay at Ready for Human Review',
        );
        expect(
          block.contains('**Status:** Completed'),
          isFalse,
          reason: '$taskId may not be marked Completed without human sign-off',
        );
      }

      // P11-T7 is proposed for human sign-off: the monorepo is green, but the
      // physical-device walkthrough it depends on has not happened yet.
      final closeout = roadmapBlock(roadmap, 'P11-T7');
      expect(
        closeout.contains('**Status:** Ready for Human Review'),
        isTrue,
        reason: 'P11-T7 must be proposed for human sign-off',
      );
      expect(
        closeout.contains('**Status:** Completed'),
        isFalse,
        reason: 'Only the human may close a phase',
      );

      final projectState = read('AI_ROLES/PROJECT_STATE.md');
      expect(
        projectState.contains('**P11-T7**'),
        isTrue,
        reason: 'PROJECT_STATE must carry the P11-T7 ledger entry',
      );
      expect(
        projectState.contains('phase11-ui-ux-closeout-report.md'),
        isTrue,
        reason: 'PROJECT_STATE must point at the closeout report',
      );
    });
  });
}
