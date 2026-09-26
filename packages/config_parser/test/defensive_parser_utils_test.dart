// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:config_parser/config_parser.dart';
import 'package:test/test.dart';

void main() {
  group('enforceMaxLength', () {
    test('passes input at exactly the limit', () {
      final result = enforceMaxLength('abc', maxLength: 3, what: 'thing');
      expect(result.isOk, isTrue);
    });

    test('rejects input one char over the limit', () {
      final result = enforceMaxLength('abcd', maxLength: 3, what: 'thing');
      expect(result.isErr, isTrue);
      final error = (result as dynamic).error as ConfigParseError;
      expect(error, isA<InputTooLargeError>());
      expect((error as InputTooLargeError).actualLength, 4);
    });

    test('rejects a MULTI-MEGABYTE input quickly (memory-DoS guard)', () {
      // The ROADMAP requires a multi-megabyte adversarial input to be
      // rejected fast rather than decoded.
      final hostile = 'A' * (4 * 1024 * 1024);
      final stopwatch = Stopwatch()..start();
      final result = enforceMaxLength(
        hostile,
        maxLength: maxUriLength,
        what: 'subscription body',
      );
      stopwatch.stop();

      expect(result.isErr, isTrue);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(1000),
        reason: 'oversized input must be rejected without decoding it',
      );
    });
  });

  group('safeBase64Decode', () {
    test('decodes standard base64 with padding', () {
      // 'hello' -> aGVsbG8=
      final result = safeBase64Decode('aGVsbG8=');
      expect(result.isOk, isTrue);
      expect(utf8.decode((result as dynamic).value as List<int>), 'hello');
    });

    test('decodes base64 without padding', () {
      final result = safeBase64Decode('aGVsbG8');
      expect(result.isOk, isTrue);
      expect(utf8.decode((result as dynamic).value as List<int>), 'hello');
    });

    test('decodes URL-safe base64 (- and _) and normalises it', () {
      // 0xFB 0xFF encodes to '+/' standard, '-_' URL-safe.
      final urlSafe = safeBase64Decode('-_8=');
      final standard = safeBase64Decode('+/8=');
      expect(urlSafe.isOk, isTrue);
      expect(standard.isOk, isTrue);
      expect(
        (urlSafe as dynamic).value,
        (standard as dynamic).value,
        reason: 'both alphabets must decode to identical bytes',
      );
    });

    test('enforces an exact expected byte length (32-byte key)', () {
      final good32 = base64.encode(List<int>.filled(32, 7));
      expect(
        safeBase64Decode(good32, field: 'PrivateKey', expectedBytes: 32).isOk,
        isTrue,
      );

      final tooShort = base64.encode(List<int>.filled(16, 7));
      final result = safeBase64Decode(
        tooShort,
        field: 'PrivateKey',
        expectedBytes: 32,
      );
      expect(result.isErr, isTrue);
      expect(
        (result as dynamic).error,
        isA<CorruptedBase64Error>().having(
          (e) => e.expectedBytes,
          'expectedBytes',
          32,
        ),
      );
    });

    test('rejects invalid base64 without throwing', () {
      final result = safeBase64Decode('not valid base64 !!!');
      expect(result.isErr, isTrue);
      expect((result as dynamic).error, isA<CorruptedBase64Error>());
    });

    test('rejects empty input', () {
      expect(safeBase64Decode('').isErr, isTrue);
    });

    test('rejects a null byte in the payload', () {
      final result = safeBase64Decode('aGVsbG8\x00');
      // A raw NUL is not in the base64 alphabet and must be refused.
      expect(result.isErr, isTrue);
      expect((result as dynamic).error, isA<CorruptedBase64Error>());
    });

    test('SECURITY: error never contains the key material', () {
      const secret = 'SUPERSECRETKEYMATERIAL1234567890AB';
      final result = safeBase64Decode(
        '${secret}!!!',
        field: 'PrivateKey',
        expectedBytes: 32,
      );
      expect(result.isErr, isTrue);
      final error = (result as dynamic).error as ConfigParseError;
      expect(error.message.contains(secret), isFalse);
    });
  });

  group('safeBase64DecodeToString', () {
    test('decodes base64-wrapped UTF-8', () {
      final encoded = base64.encode(utf8.encode('vless://abc'));
      final result = safeBase64DecodeToString(encoded);
      expect(result.isOk, isTrue);
      expect((result as dynamic).value, 'vless://abc');
    });

    test('rejects non-UTF-8 bytes', () {
      // 0xFF 0xFE 0xFD is not valid UTF-8.
      final result = safeBase64DecodeToString(
        base64.encode([0xFF, 0xFE, 0xFD]),
      );
      expect(result.isErr, isTrue);
      expect((result as dynamic).error, isA<CorruptedBase64Error>());
    });

    test('rejects an over-long decoded payload', () {
      // Decode is fine, but the decoded text exceeds the cap.
      final big = base64.encode(utf8.encode('x' * (maxUriLength + 1)));
      final result = safeBase64DecodeToString(
        big,
        maxDecodedLength: maxUriLength,
      );
      expect(result.isErr, isTrue);
      expect((result as dynamic).error, isA<InputTooLargeError>());
    });
  });

  group('safeUriParse', () {
    test('parses a valid URI', () {
      final result = safeUriParse('vless://uuid@example.com:443');
      expect(result.isOk, isTrue);
      expect((result as dynamic).value.scheme, 'vless');
    });

    test('rejects a malformed URI without throwing', () {
      final result = safeUriParse('ht!tp://%%%');
      expect(result.isErr, isTrue);
      expect((result as dynamic).error, isA<InvalidSyntaxError>());
    });

    test('rejects a URI with no scheme', () {
      final result = safeUriParse('just-some-text');
      expect(result.isErr, isTrue);
    });

    test('rejects empty input', () {
      expect(safeUriParse('').isErr, isTrue);
    });

    test('rejects an oversized URI before parsing it', () {
      final huge = 'vless://' + ('a' * (maxUriLength + 10));
      final result = safeUriParse(huge);
      expect(result.isErr, isTrue);
      expect((result as dynamic).error, isA<InputTooLargeError>());
    });
  });

  group('safeJsonDecode', () {
    test('decodes a valid JSON object', () {
      final result = safeJsonDecode('{"a":1}');
      expect(result.isOk, isTrue);
      expect(((result as dynamic).value as Map)['a'], 1);
    });

    test('decodes a JSON array', () {
      final result = safeJsonDecode('[1,2,3]');
      expect(result.isOk, isTrue);
    });

    test('rejects malformed JSON without throwing', () {
      final result = safeJsonDecode('{not json');
      expect(result.isErr, isTrue);
      expect((result as dynamic).error, isA<InvalidSyntaxError>());
    });

    test('rejects empty / whitespace-only input', () {
      expect(safeJsonDecode('').isErr, isTrue);
      expect(safeJsonDecode('   ').isErr, isTrue);
    });

    test('rejects nesting deeper than maxJsonDepth', () {
      // Build a deliberately deep object.
      final deep = '${'[' * (maxJsonDepth + 5)}1${']' * (maxJsonDepth + 5)}';
      final result = safeJsonDecode(deep);
      expect(result.isErr, isTrue);
      expect((result as dynamic).error, isA<InvalidSyntaxError>());
    });

    test('rejects a multi-megabyte JSON body quickly', () {
      final huge = '[${'"x",' * 200000}0]';
      final stopwatch = Stopwatch()..start();
      final result = safeJsonDecode(huge, maxLength: maxUriLength);
      stopwatch.stop();
      expect(result.isErr, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });
}
