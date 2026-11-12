// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

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

  group('P10-T8: Phase 10 Closeout & Android MVP Milestone Suite', () {
    test('Test 1: Play Store Submission Guide Structure, Signing Strategy & '
        'MASA Deferral', () {
      final guideFile = File(
        '${repoRoot.path}/docs/release/play-store-submission-guide.md',
      );
      expect(
        guideFile.existsSync(),
        isTrue,
        reason: 'play-store-submission-guide.md must exist',
      );
      final content = guideFile.readAsStringSync();

      // Zero placeholders
      expect(content.contains('TODO'), isFalse);
      expect(content.contains('TBD'), isFalse);

      // Section 1: Signing Strategy & Certificate Uniformity
      expect(content.contains('Play App Signing'), isTrue);
      expect(content.contains('PEPK'), isTrue);
      expect(content.contains('cross-channel certificate uniformity'), isTrue);
      expect(
        content.contains('INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES'),
        isTrue,
      );
      expect(
        content.toLowerCase().contains(
          '563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b',
        ),
        isTrue,
      );

      // Section 2 & 3: Closed/Internal Track Runbook & Reviewer Playbook
      expect(content.contains('Internal Testing'), isTrue);
      expect(content.contains('Closed Testing'), isTrue);
      expect(content.contains('App Access'), isTrue);
      expect(content.contains('FOREGROUND_SERVICE_SPECIAL_USE'), isTrue);
      expect(content.contains('VpnService.prepare'), isTrue);

      // Section 4: MASA Deferral & Specific Thresholds
      expect(content.contains('Mobile App Security Assessment (MASA)'), isTrue);
      expect(content.contains('10,000'), isTrue);
      expect(content.contains('250'), isTrue);
      expect(content.contains('90'), isTrue);
      expect(content.contains('App Defense Alliance'), isTrue);
    });

    test('Test 2: MVP Milestone Retrospective, Legacy Prototype Comparison & '
        'Phase 11 Handoff', () {
      final retroFile = File(
        '${repoRoot.path}/docs/release/mvp-milestone-retrospective.md',
      );
      expect(
        retroFile.existsSync(),
        isTrue,
        reason: 'mvp-milestone-retrospective.md must exist',
      );
      final content = retroFile.readAsStringSync();

      // Zero placeholders
      expect(content.contains('TODO'), isFalse);
      expect(content.contains('TBD'), isFalse);

      // Section 1: Legacy prototype comparison points
      expect(content.contains('Monolithic Spaghetti'), isTrue);
      expect(content.contains('CommandCoordinator'), isTrue);
      expect(content.contains('VpnStateMachine'), isTrue);
      expect(content.contains('hijack-dns'), isTrue);
      expect(content.contains('AES-256-GCM'), isTrue);
      expect(content.contains('LogRedactor'), isTrue);
      expect(content.contains('seeds.txt'), isTrue);

      // Section 2: Verification summary on Samsung SM-A205F
      expect(content.contains('Samsung SM-A205F'), isTrue);
      expect(content.contains('SM_A205F_RUNNING_PID=24311'), isTrue);

      // Section 3: Carried-forward limitations
      expect(content.contains('Deliberately Minimal Placeholder UI'), isTrue);
      expect(
        content.contains('Unstructured Free-Text Native Log Redaction'),
        isTrue,
      );
      expect(content.contains('OEM Battery-Optimization Quirks'), isTrue);
      expect(content.contains('Reproducible Docker Builds'), isTrue);

      // Section 4: Phase 11 handoff statement
      expect(content.contains('Phase 11'), isTrue);
      expect(content.contains('P11-T1'), isTrue);
      expect(content.contains('Visual Identity and Style Guide'), isTrue);
    });

    test('Test 3: Comprehensive Phase 10 Artifact Ledger Existence & '
        'Non-Emptiness Audit', () {
      final phase10Files = [
        'docs/verifying-releases.md',
        'docs/release-signing-and-key-recovery.md',
        'docs/privacy-policy.md',
        'docs/release/play-store-vpn-compliance.md',
        'docs/release/store-listing.md',
        'docs/release/github-release-v1.0.0.md',
        'docs/release/play-store-submission-guide.md',
        'docs/release/mvp-milestone-retrospective.md',
        'scripts/prepare_github_release_bundle.sh',
        'docs/release/store-assets/icon-512x512.png',
        'docs/release/store-assets/feature-graphic-1024x500.png',
        'docs/release/store-assets/screenshots/01_home_disconnected.png',
        'docs/release/store-assets/screenshots/02_home_connected.png',
        'docs/release/store-assets/screenshots/03_servers_and_subscriptions.png',
        'docs/release/store-assets/screenshots/04_live_logs_redacted.png',
      ];

      for (final relativePath in phase10Files) {
        final file = File('${repoRoot.path}/$relativePath');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'Artifact $relativePath must exist',
        );
        expect(
          file.lengthSync(),
          greaterThan(0),
          reason: 'Artifact $relativePath must not be empty',
        );
      }
    });

    test('Test 4: PROJECT_STATE.md contains full Android MVP Milestone '
        'Summary, Legacy Comparison, 6 Carried-Forward Limitations & '
        'Phase 11 Handoff', () {
      final projectStateFile = File(
        '${repoRoot.path}/AI_ROLES/PROJECT_STATE.md',
      );
      expect(
        projectStateFile.existsSync(),
        isTrue,
        reason: 'AI_ROLES/PROJECT_STATE.md must exist',
      );
      final content = projectStateFile.readAsStringSync();

      expect(
        content.contains(
          'Android MVP Milestone Summary (Phases 0–10 Complete)',
        ),
        isTrue,
        reason: 'PROJECT_STATE.md must have Android MVP Milestone Summary',
      );
      expect(
        content.contains(
          'Retrospective Comparison: Legacy Prototype Collapse vs. '
          'Rebuilt Android MVP',
        ),
        isTrue,
        reason: 'PROJECT_STATE.md must have Retrospective Comparison section',
      );
      expect(
        content.contains(
          'Consolidated Known Limitations & Deferred Items Carried Forward to '
          'Phase 11+',
        ),
        isTrue,
        reason:
            'PROJECT_STATE.md must have Consolidated Known Limitations section',
      );
      expect(content.contains('Google MASA'), isTrue);
      expect(content.contains('10,000'), isTrue);
      expect(content.contains('250'), isTrue);
      expect(content.contains('90'), isTrue);
      expect(
        content.contains(
          'Phase 11 — Full UI/UX Design & Implementation '
          '(P11-T1: Design System Foundation: Visual Identity and Style Guide)',
        ),
        isTrue,
        reason: 'PROJECT_STATE.md must contain Phase 11 handoff statement',
      );

      // Verify removal of stale Phase 1-3 contradictions and EOF newline
      expect(
        content.contains(
          '23 Flutter tests pass. The app has **not** yet been run on a device',
        ),
        isFalse,
        reason:
            'PROJECT_STATE.md must not contain stale test count/device claim',
      );
      expect(
        content.contains('CI Status: RED on master (as of 2026-09-28)'),
        isFalse,
        reason: 'PROJECT_STATE.md must not contain stale red CI claim',
      );
      expect(
        content.contains('Agent (P2-T9)'),
        isFalse,
        reason: 'PROJECT_STATE.md must not contain stale Phase 2 next steps',
      );
      expect(
        content.endsWith('\n'),
        isTrue,
        reason: 'PROJECT_STATE.md must end with a trailing newline',
      );
    });

    test('Test 5: ROADMAP.md Phase 10 tasks P10-T1..P10-T8 have clean single '
        'Status lines and zero duplicate or unchecked checkboxes', () {
      final roadmapFile = File('${repoRoot.path}/AI_ROLES/ROADMAP.md');
      expect(
        roadmapFile.existsSync(),
        isTrue,
        reason: 'AI_ROLES/ROADMAP.md must exist',
      );
      final content = roadmapFile.readAsStringSync();

      final startIndex = content.indexOf('### P10-T1');
      final endIndex = content.indexOf('## Phase 11');
      expect(
        startIndex,
        greaterThanOrEqualTo(0),
        reason: '### P10-T1 must exist in ROADMAP.md',
      );
      expect(
        endIndex,
        greaterThan(startIndex),
        reason: '## Phase 11 must exist in ROADMAP.md',
      );

      final phase10Slice = content.substring(startIndex, endIndex);

      expect(
        RegExp(
          r'^\*\*Status:\*\*',
          multiLine: true,
        ).allMatches(phase10Slice).length,
        equals(8),
        reason: 'Phase 10 slice must have exactly 8 Status lines',
      );
      expect(
        RegExp(
          r'^\*\*Status:\*\* Completed ✅$',
          multiLine: true,
        ).allMatches(phase10Slice).length,
        equals(7),
        reason:
            'Phase 10 slice must have exactly 7 Completed tasks (P10-T1..T7)',
      );
      expect(
        RegExp(
          r'^\*\*Status:\*\* Ready for Human Review$',
          multiLine: true,
        ).allMatches(phase10Slice).length,
        equals(1),
        reason:
            'Phase 10 slice must have exactly 1 Ready for Review task (P10-T8)',
      );
      expect(
        phase10Slice.contains('**Status:** Not Started'),
        isFalse,
        reason: 'Phase 10 slice must not contain any Not Started status',
      );
      expect(
        phase10Slice.contains('- [ ]'),
        isFalse,
        reason: 'Phase 10 slice must not contain any unchecked checkboxes',
      );
    });
  });
}
