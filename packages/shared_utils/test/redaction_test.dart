// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_utils/shared_utils.dart';
import 'package:test/test.dart';

void main() {
  group('redact', () {
    test('exists as a top-level String -> String function', () {
      // Compile-time proof that the helper is exported from the barrel with
      // the contract SECURITY.md Section 4 requires.
      const String Function(String) fn = redact;
      expect(redact, same(fn));
    });

    test('returns a String for arbitrary input', () {
      expect(redact('hello'), isA<String>());
    });

    test('is currently a pass-through stub (Phase 1)', () {
      // This assertion pins the CURRENT stub behaviour. It is expected to
      // FAIL once Phase 8 implements real redaction, at which point this
      // test must be rewritten to assert masking instead of identity.
      expect(redact('plain message'), 'plain message');
    });

    test('passes through empty and whitespace-only strings unchanged', () {
      expect(redact(''), '');
      expect(redact('   '), '   ');
    });

    test('passes through strings containing sensitive-looking content '
        'unchanged (stub)', () {
      // Documents the current, deliberately-unimplemented state. A real
      // implementation would mask these; until then they pass through.
      expect(redact('uuid=1234-abcd'), 'uuid=1234-abcd');
      expect(redact('host=192.168.1.1'), 'host=192.168.1.1');
    });
  });
}
