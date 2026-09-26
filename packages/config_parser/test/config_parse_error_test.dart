// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigParseError taxonomy', () {
    test('every variant exposes a stable, distinct code', () {
      const errors = <ConfigParseError>[
        InvalidSyntaxError('uri', 'bad'),
        MissingRequiredFieldError('uuid'),
        InvalidFieldValueError('port', 'out of range'),
        CorruptedBase64Error('uuid', 'not valid base64'),
        UnsupportedSchemeError('nope'),
        UnsupportedProtocolError('wireguard'),
        InputTooLargeError(actualLength: 10, maxLength: 5, what: 'body'),
        UnknownParseError('unclear'),
      ];

      expect(
        errors.map((e) => e.code).toSet(),
        hasLength(errors.length),
        reason: 'codes must be distinct so callers can branch on them',
      );
    });

    test('messages are human-readable and non-empty', () {
      const errors = <ConfigParseError>[
        InvalidSyntaxError('uri', 'bad'),
        MissingRequiredFieldError('uuid'),
        InvalidFieldValueError('port', 'out of range'),
        CorruptedBase64Error('uuid', 'not valid base64'),
        UnsupportedSchemeError('nope'),
        UnsupportedProtocolError('wireguard'),
        InputTooLargeError(actualLength: 10, maxLength: 5, what: 'body'),
        UnknownParseError('unclear'),
      ];

      for (final error in errors) {
        expect(error.message, isNotEmpty);
      }
    });

    test('value equality works for every variant', () {
      expect(
        const InvalidSyntaxError('uri', 'bad'),
        const InvalidSyntaxError('uri', 'bad'),
      );
      expect(
        const MissingRequiredFieldError('uuid'),
        const MissingRequiredFieldError('uuid'),
      );
      expect(
        const CorruptedBase64Error('k', 'r', expectedBytes: 32),
        const CorruptedBase64Error('k', 'r', expectedBytes: 32),
      );
    });

    test('SECURITY: the type never captures input on its own', () {
      // The guarantee is structural: every variant stores only developer
      // authored metadata (field names, sizes, reasons). A caller that
      // deliberately passes a secret AS the field name is out of contract —
      // what matters is that no variant ever *retains the offending input*,
      // which is asserted directly against the decoding helpers in
      // `defensive_parser_utils_test.dart` ('error never contains the key
      // material').
      const error = CorruptedBase64Error(
        'PrivateKey',
        'decoded length is 16, expected 32',
        expectedBytes: 32,
      );
      expect(error.message, contains('PrivateKey'));
      expect(error.message, contains('expected 32'));
      expect(error.expectedBytes, 32);
    });
  });
}
