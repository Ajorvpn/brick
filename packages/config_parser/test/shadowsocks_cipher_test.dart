// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

/// Builds a SIP002 link: `ss://base64(method:password)@host:port#remark`.
String sip002(String method, String password) {
  final userInfo = base64.encode(utf8.encode('$method:$password'));
  return 'ss://$userInfo@example.com:8388#SS';
}

/// Builds a legacy link: `ss://base64(method:password@host:port)#remark`.
String legacy(String method, String password) {
  final payload = base64.encode(
    utf8.encode('$method:$password@example.com:8388'),
  );
  return 'ss://$payload#SS';
}

void main() {
  group('supported ciphers', () {
    // Sampled across both the current AEAD set, the 2022-blake3 family,
    // the plain AEAD set, and the legacy set, per the sing-box docs.
    const good = [
      '2022-blake3-aes-128-gcm',
      '2022-blake3-aes-256-gcm',
      '2022-blake3-chacha20-poly1305',
      'none',
      'aes-128-gcm',
      'aes-256-gcm',
      'chacha20-ietf-poly1305',
      'xchacha20-ietf-poly1305',
      'aes-256-cfb',
      'rc4-md5',
      'xchacha20',
    ];

    test('the verified list has 18 entries', () {
      expect(supportedCiphers, hasLength(18));
    });

    for (final cipher in good) {
      test('SIP002 accepts $cipher', () {
        final result = parseShadowsocksUri(sip002(cipher, 'pw'));
        expect(result.isOk, isTrue, reason: 'expected $cipher to be accepted');
        expect(
          (result as Ok<OutboundConfig, ConfigParseError>).value,
          isA<ShadowsocksOutbound>().having((c) => c.method, 'method', cipher),
        );
      });

      test('legacy accepts $cipher', () {
        final result = parseShadowsocksUri(legacy(cipher, 'pw'));
        expect(result.isOk, isTrue, reason: 'expected $cipher to be accepted');
        expect(
          (result as Ok<OutboundConfig, ConfigParseError>).value,
          isA<ShadowsocksOutbound>().having((c) => c.method, 'method', cipher),
        );
      });
    }
  });

  group('unsupported ciphers', () {
    const bad = [
      'aes-256-gcm-bogus',
      'superfastcipher',
      'aes-128-gcm ',
      'chacha20', // close to but not a real sing-box method
    ];

    for (final cipher in bad) {
      test('SIP002 rejects "${cipher.isEmpty ? '<empty>' : cipher}"', () {
        final result = parseShadowsocksUri(sip002(cipher, 'pw'));
        expect(result.isOk, isFalse, reason: 'expected rejection');
        expect(
          (result as Err<OutboundConfig, ConfigParseError>).error,
          isA<UnsupportedCipherError>(),
        );
      });

      test('legacy rejects "${cipher.isEmpty ? '<empty>' : cipher}"', () {
        final result = parseShadowsocksUri(legacy(cipher, 'pw'));
        expect(result.isOk, isFalse, reason: 'expected rejection');
        expect(
          (result as Err<OutboundConfig, ConfigParseError>).error,
          isA<UnsupportedCipherError>(),
        );
      });
    }
  });

  group('empty method', () {
    // An empty method is caught by the pre-existing "required field
    // missing" guard before cipher validation runs. That is the more
    // accurate category, so it is asserted explicitly rather than being
    // forced into UnsupportedCipherError.
    for (final link in [sip002('', 'pw'), legacy('', 'pw')]) {
      test('rejected as MissingRequiredFieldError', () {
        final result = parseShadowsocksUri(link);
        expect(result.isErr, isTrue);
        expect(
          (result as Err<OutboundConfig, ConfigParseError>).error,
          isA<MissingRequiredFieldError>(),
        );
      });
    }
  });

  group('case-insensitive matching', () {
    test('accepts an upper-cased known cipher and normalises it', () {
      final result = parseShadowsocksUri(sip002('AES-256-GCM', 'pw'));
      expect(result.isOk, isTrue);
      expect(
        (result as Ok<OutboundConfig, ConfigParseError>).value,
        isA<ShadowsocksOutbound>().having(
          (c) => c.method,
          'method',
          'aes-256-gcm',
        ),
      );
    });
  });

  group('SECURITY', () {
    test('error names the cipher but never the password', () {
      const cipher = 'not-a-real-cipher';
      const secret = 'MyShadowsocksPassword123';
      for (final link in [sip002(cipher, secret), legacy(cipher, secret)]) {
        final result = parseShadowsocksUri(link);
        expect(result.isErr, isTrue);
        final error = (result as Err<OutboundConfig, ConfigParseError>).error;
        expect(error, isA<UnsupportedCipherError>());
        // The cipher name is public and intentionally present.
        expect(error.message, contains(cipher));
        expect((error as UnsupportedCipherError).method, cipher);
        // The password must never appear.
        expect(error.message.contains(secret), isFalse);
      }
    });
  });
}
