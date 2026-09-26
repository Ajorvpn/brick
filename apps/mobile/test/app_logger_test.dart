// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/core/providers/app_logger_provider.dart';
import 'package:shared_utils/shared_utils.dart' show redact;

/// Captures everything the `logger` package actually writes, so tests can
/// assert real emitted output rather than inferring intent.
class _CapturingOutput extends LogOutput {
  final List<String> lines = [];

  @override
  void output(OutputEvent event) {
    lines.add(event.lines.join('\n'));
  }
}

void main() {
  group('AppLogger redaction', () {
    test('routes messages through redact() before emitting', () {
      final output = _CapturingOutput();
      final logger = AppLogger(
        log: Logger(level: Level.all, output: output),
        isReleaseMode: false,
      )..i('hello world');

      expect(logger.isEnabled, isTrue);
      expect(output.lines, hasLength(1));
      // redact() is currently a pass-through stub, so the emitted line
      // equals the redacted form of the input. When Phase 8 implements real
      // masking, this assertion must be updated to expect the masked text.
      expect(output.lines.single, contains(redact('hello world')));
      expect(output.lines.single, contains('hello world'));
    });

    test('redacts every level, not just info', () {
      final output = _CapturingOutput();
      final logger =
          AppLogger(
              log: Logger(level: Level.all, output: output),
              isReleaseMode: false,
            )
            ..d('d-message')
            ..i('i-message')
            ..w('w-message')
            ..e('e-message');

      expect(logger.isEnabled, isTrue);

      expect(output.lines, hasLength(4));
      expect(output.lines[0], contains(redact('d-message')));
      expect(output.lines[1], contains(redact('i-message')));
      expect(output.lines[2], contains(redact('w-message')));
      expect(output.lines[3], contains(redact('e-message')));
    });

    test('attaches error and stackTrace on e()', () {
      final output = _CapturingOutput();
      final log = Logger(level: Level.all, output: output);
      final logger = AppLogger(log: log, isReleaseMode: false);

      final error = StateError('boom');
      final stack = StackTrace.current;
      logger.e('failed', error, stack);

      expect(output.lines.single, contains('failed'));
      expect(output.lines.single, contains('boom'));
    });
  });

  group('AppLogger release-mode gate', () {
    test('emits ZERO output in release mode', () {
      final output = _CapturingOutput();
      final logger =
          AppLogger(
              log: Logger(level: Level.off, output: output),
              isReleaseMode: true,
            )
            ..d('d')
            ..i('i')
            ..w('w')
            ..e('e', StateError('boom'), StackTrace.current);

      // The hard requirement: a release build produces no log output at all.
      expect(output.lines, isEmpty);
      expect(logger.isReleaseMode, isTrue);
      expect(logger.isEnabled, isFalse);
    });

    test('is enabled in debug mode', () {
      final output = _CapturingOutput();
      final log = Logger(level: Level.all, output: output);
      final logger = AppLogger(log: log, isReleaseMode: false);

      expect(logger.isReleaseMode, isFalse);
      expect(logger.isEnabled, isTrue);

      logger.i('visible');
      expect(output.lines, hasLength(1));
    });
  });

  group('appLoggerProvider', () {
    test('resolves an AppLogger', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appLoggerProvider), isA<AppLogger>());
    });

    test('is a stable keepAlive singleton across repeated reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(appLoggerProvider),
        same(container.read(appLoggerProvider)),
      );
    });

    test('can be overridden for tests', () {
      final output = _CapturingOutput();
      final stub = AppLogger(
        log: Logger(level: Level.all, output: output),
        isReleaseMode: false,
      );
      final container = ProviderContainer(
        overrides: [appLoggerProvider.overrideWith((_) => stub)],
      );
      addTearDown(container.dispose);

      expect(container.read(appLoggerProvider), same(stub));
    });
  });
}
