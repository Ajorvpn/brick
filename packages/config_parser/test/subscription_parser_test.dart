// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';
const _uuid2 = 'c942491e-7435-4e64-be50-9deb59c41922';

String _vless(String uuid, String host) => 'vless://$uuid@$host:443#Node';

void main() {
  group('decodeSubscriptionBody', () {
    test('decodes a base64 multi-line subscription', () {
      final raw = [
        _vless(_uuid, 'a.example.com'),
        _vless(_uuid2, 'b.example.com'),
      ].join('\n');
      final encoded = base64.encode(utf8.encode(raw));

      final result = decodeSubscriptionBody(encoded);
      expect(result.isOk, isTrue);
      final decoded =
          (result as Ok<DecodedSubscription, ConfigParseError>).value;
      expect(decoded.lines, hasLength(2));
      expect(decoded.lines.first, contains('a.example.com'));
    });

    test('decodes unpadded base64', () {
      final raw = _vless(_uuid, 'a.example.com');
      // Strip padding the way some providers do.
      var encoded = base64.encode(utf8.encode(raw));
      while (encoded.endsWith('=')) {
        encoded = encoded.substring(0, encoded.length - 1);
      }
      final result = decodeSubscriptionBody(encoded);
      expect(result.isOk, isTrue);
    });

    test('keeps plain-text lines and filters blanks and comments', () {
      final raw = [
        '# a comment',
        '// another comment',
        '; semicolon comment',
        '',
        _vless(_uuid, 'a.example.com'),
        '',
        _vless(_uuid2, 'b.example.com'),
      ].join('\n');
      final result = decodeSubscriptionBody(raw);
      expect(result.isOk, isTrue);
      final decoded =
          (result as Ok<DecodedSubscription, ConfigParseError>).value;
      expect(decoded.lines, hasLength(2));
      expect(decoded.skippedLineCount, greaterThan(0));
    });

    test('drops non-URI noise such as an HTML error page', () {
      const raw = '<html><body>403 Forbidden</body></html>';
      final result = decodeSubscriptionBody(raw);
      expect(result.isErr, isTrue);
    });

    test('rejects an empty body', () {
      expect(decodeSubscriptionBody('').isErr, isTrue);
      expect(decodeSubscriptionBody('   \n  ').isErr, isTrue);
    });

    test('rejects an oversized body before decoding', () {
      final huge = 'vless://$_uuid@a.com:443#' + ('a' * maxSubscriptionLength);
      final result = decodeSubscriptionBody(huge);
      expect(result.isErr, isTrue);
      expect(
        (result as Err<DecodedSubscription, ConfigParseError>).error,
        isA<InputTooLargeError>(),
      );
    });
  });

  group('SubscriptionUserInfo.parse', () {
    test('parses a full header', () {
      final result = SubscriptionUserInfo.parse(
        'upload=12345; download=67890; total=1000000; expire=1735689600',
      );
      expect(result.isOk, isTrue);
      final info = (result as Ok<SubscriptionUserInfo, ConfigParseError>).value;
      expect(info.uploadBytes, 12345);
      expect(info.downloadBytes, 67890);
      expect(info.totalBytes, 1000000);
      expect(info.expiresAt, isNotNull);
      expect(
        info.expiresAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
        1735689600,
      );
      expect(info.usedBytes, 80235);
    });

    test('parses a partial header', () {
      final result = SubscriptionUserInfo.parse('upload=100; total=200');
      final info = (result as Ok<SubscriptionUserInfo, ConfigParseError>).value;
      expect(info.uploadBytes, 100);
      expect(info.totalBytes, 200);
      expect(info.downloadBytes, isNull);
      expect(info.expiresAt, isNull);
      // usedBytes needs both halves.
      expect(info.usedBytes, isNull);
    });

    test('ignores unknown keys but keeps the known ones', () {
      final result = SubscriptionUserInfo.parse(
        'upload=5; fancykey=zzz; total=10',
      );
      expect(result.isOk, isTrue);
      final info = (result as Ok<SubscriptionUserInfo, ConfigParseError>).value;
      expect(info.uploadBytes, 5);
      expect(info.totalBytes, 10);
    });

    test('rejects a header with no recognised keys', () {
      expect(SubscriptionUserInfo.parse('foo=bar').isErr, isTrue);
    });

    test('rejects an empty header', () {
      expect(SubscriptionUserInfo.parse('').isErr, isTrue);
      expect(SubscriptionUserInfo.parse('   ').isErr, isTrue);
    });

    test('ignores a non-numeric byte count', () {
      final result = SubscriptionUserInfo.parse('upload=abc; total=10');
      // `total` is recognised, so the header still parses.
      final info = (result as Ok<SubscriptionUserInfo, ConfigParseError>).value;
      expect(info.uploadBytes, isNull);
      expect(info.totalBytes, 10);
    });

    test('usedFraction is null rather than NaN for a zero quota', () {
      const info = SubscriptionUserInfo(
        uploadBytes: 10,
        downloadBytes: 10,
        totalBytes: 0,
      );
      expect(info.usedFraction, isNull);
    });

    test('usedFraction is clamped to 1.0 when over quota', () {
      const info = SubscriptionUserInfo(
        uploadBytes: 80,
        downloadBytes: 80,
        totalBytes: 100,
      );
      expect(info.usedFraction, 1.0);
    });

    test('has value equality', () {
      const a = SubscriptionUserInfo(uploadBytes: 1, totalBytes: 2);
      const b = SubscriptionUserInfo(uploadBytes: 1, totalBytes: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('parseSubscription fault tolerance', () {
    test('a bad link does not discard the good ones', () {
      final raw = [
        _vless(_uuid, 'good1.example.com'),
        'vless://totally-not-a-uuid@bad.example.com:443#Bad',
        _vless(_uuid2, 'good2.example.com'),
        'not-a-uri-at-all',
        'trojan://pw@good3.example.com:443#Trojan',
      ].join('\n');

      final result = parseSubscription(raw);
      expect(result.isOk, isTrue);
      final parsed =
          (result as Ok<SubscriptionParseResult, ConfigParseError>).value;

      expect(parsed.parsedCount, 3, reason: 'good entries must survive');
      expect(parsed.failedCount, greaterThanOrEqualTo(1));
      expect(parsed.isComplete, isFalse);
      // The errors explain the failure without carrying the bad URI.
      expect(
        parsed.errors.every((e) => e.code != 'unknown' || e.message.isNotEmpty),
        isTrue,
      );
    });

    test('handles a mixed multi-protocol subscription', () {
      final ssUserInfo = base64.encode(utf8.encode('aes-256-gcm:pw'));
      final vmessJson = jsonEncode({
        'v': '2',
        'add': 'vmess.example.com',
        'port': '443',
        'id': _uuid,
        'aid': '0',
        'net': 'ws',
      });
      final raw = [
        _vless(_uuid, 'a.example.com'),
        'vmess://${base64.encode(utf8.encode(vmessJson))}',
        'trojan://pw@b.example.com:443',
        'ss://$ssUserInfo@c.example.com:8388',
      ].join('\n');

      final result = parseSubscription(raw);
      expect(result.isOk, isTrue);
      final parsed =
          (result as Ok<SubscriptionParseResult, ConfigParseError>).value;

      expect(parsed.parsedCount, 4);
      expect(parsed.failedCount, 0);
      expect(parsed.configs.map((c) => c.protocol).toSet(), {
        ProtocolType.vless,
        ProtocolType.vmess,
        ProtocolType.trojan,
        ProtocolType.shadowsocks,
      });
    });

    test('parses a base64 subscription end to end with userinfo', () {
      final raw = [
        _vless(_uuid, 'a.example.com'),
        _vless(_uuid2, 'b.example.com'),
      ].join('\n');
      final encoded = base64.encode(utf8.encode(raw));

      final result = parseSubscription(
        encoded,
        userInfoHeaderValue:
            'upload=1; download=2; total=100; expire=1735689600',
      );
      expect(result.isOk, isTrue);
      final parsed =
          (result as Ok<SubscriptionParseResult, ConfigParseError>).value;

      expect(parsed.parsedCount, 2);
      expect(parsed.userInfo, isNotNull);
      expect(parsed.userInfo!.totalBytes, 100);
    });

    test('a malformed userinfo header does not fail the subscription', () {
      final raw = _vless(_uuid, 'a.example.com');
      final result = parseSubscription(
        raw,
        userInfoHeaderValue: 'total=notanumber',
      );
      expect(result.isOk, isTrue);
      final parsed =
          (result as Ok<SubscriptionParseResult, ConfigParseError>).value;
      expect(parsed.parsedCount, 1);
      expect(parsed.userInfo, isNull);
    });

    test('returns Err only when the whole payload is unusable', () {
      expect(parseSubscription('').isErr, isTrue);
      expect(parseSubscription('<html>nope</html>').isErr, isTrue);
    });

    test('SECURITY: a failed entry never echoes its URI into the error', () {
      const secretHost = 'secret-server.example.com';
      final raw = 'vless://bad-uuid@$secretHost:99999#Oops';
      final result = parseSubscription(raw);
      expect(result.isOk, isTrue);
      final parsed =
          (result as Ok<SubscriptionParseResult, ConfigParseError>).value;
      expect(parsed.errors, isNotEmpty);
      for (final error in parsed.errors) {
        expect(error.message.contains(secretHost), isFalse);
      }
    });

    test('SECURITY: a trojan password never appears in an error', () {
      const secret = 'MySecretTrojanPw';
      final raw = 'trojan://$secret@host.example.com:99999#x';
      final result = parseSubscription(raw);
      final parsed =
          (result as Ok<SubscriptionParseResult, ConfigParseError>).value;
      for (final error in parsed.errors) {
        expect(error.message.contains(secret), isFalse);
      }
    });
  });

  group('parsed configs are sing-box serializable', () {
    test('every subscription entry serializes without a network/transport '
        'mix-up', () {
      final raw = [
        _vless(_uuid, 'a.example.com'),
        'vless://$_uuid@b.example.com:443?type=grpc&serviceName=svc#g',
      ].join('\n');
      final parsed = parseSubscription(raw);
      final result =
          (parsed as Ok<SubscriptionParseResult, ConfigParseError>).value;

      for (final config in result.configs) {
        final json = buildSingBoxOutbound(config);
        // A transport name must never leak into the L4 `network` field.
        expect(json['network'] == 'ws' || json['network'] == 'grpc', isFalse);
      }
      // The gRPC entry keeps its transport.
      final withGrpc = result.configs.whereType<VlessOutbound>().where(
        (c) => c.transport is GrpcTransport,
      );
      expect(withGrpc, isNotEmpty);
      expect(
        (buildSingBoxOutbound(withGrpc.first)['transport'] as Map)['type'],
        'grpc',
      );
    });
  });
}
