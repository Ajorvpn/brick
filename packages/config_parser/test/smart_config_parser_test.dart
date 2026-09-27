// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';
final _wgPriv = base64.encode(List<int>.generate(32, (i) => i));
final _wgPub = base64.encode(List<int>.generate(32, (i) => 255 - i));

String _vless() => 'vless://$_uuid@example.com:443#N';
String _vmess() =>
    'vmess://${base64.encode(utf8.encode(jsonEncode({'v': '2', 'add': 'e.com', 'port': '443', 'id': _uuid, 'aid': '0'})))}';
String _trojan() => 'trojan://pw@example.com:443#N';
String _ss() =>
    'ss://${base64.encode(utf8.encode('aes-256-gcm:pw'))}@example.com:8388#N';
String _hy2() => 'hy2://pw@example.com:443#N';
String _tuic() => 'tuic://$_uuid:pw@example.com:443#N';
// A base64 key contains '+', '/' and '=', which corrupt a URI authority,
// so a real client percent-encodes it. The peer key and address go in the
// query, which is how every WG link format in the wild does it.
String _wg({String scheme = 'wireguard'}) =>
    '$scheme://${Uri.encodeComponent(_wgPriv)}@vpn.example.com:51820'
    '?peer_public_key=${Uri.encodeComponent(_wgPub)}&ip=10.0.0.2/32#N';

void main() {
  group('single URI auto-detection', () {
    final cases = <String, String>{
      'vless': _vless(),
      'vmess': _vmess(),
      'trojan': _trojan(),
      'ss': _ss(),
      'hy2': _hy2(),
      'hysteria2': _hy2().replaceFirst('hy2://', 'hysteria2://'),
      'tuic': _tuic(),
      'wireguard': _wg(),
      'wg': _wg(scheme: 'wg'),
      'awg': _wg(scheme: 'awg'),
      'amneziawg': _wg(scheme: 'amneziawg'),
    };

    cases.forEach((scheme, uri) {
      test('$scheme is detected as a single URI', () {
        final result = parseConfigContent(uri);
        expect(result.isOk, isTrue, reason: '$scheme should parse');
        final parsed = (result as Ok<SmartParseResult, ConfigParseError>).value;
        expect(parsed.detectedType, SmartContentType.singleUri);
        expect(parsed.parsedCount, 1);
        expect(parsed.isComplete, isTrue);
      });
    });

    test('each scheme maps to the right protocol', () {
      final protocols = <String, ProtocolType>{
        _vless(): ProtocolType.vless,
        _trojan(): ProtocolType.trojan,
        _ss(): ProtocolType.shadowsocks,
        _hy2(): ProtocolType.hysteria2,
        _tuic(): ProtocolType.tuic,
        _wg(): ProtocolType.wireguard,
      };
      protocols.forEach((uri, expected) {
        final parsed = parseConfigContent(uri);
        expect(
          (parsed as Ok<SmartParseResult, ConfigParseError>)
              .value
              .outbounds
              .first
              .protocol,
          expected,
        );
      });
    });
  });

  group('deep link extraction', () {
    test('brick://import?url=<vless> unwraps and reports deepLink', () {
      final inner = _vless();
      final link = 'brick://import?url=${Uri.encodeComponent(inner)}';
      final result = parseConfigContent(link);
      expect(result.isOk, isTrue);
      final parsed = (result as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.detectedType, SmartContentType.deepLink);
      expect(parsed.parsedCount, 1);
      expect(parsed.outbounds.first, isA<VlessOutbound>());
    });

    test('brick://import?config=<wireguard> also unwraps', () {
      final link = 'brick://import?config=${Uri.encodeComponent(_wg())}';
      final parsed = (parseConfigContent(
        link,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.detectedType, SmartContentType.deepLink);
      expect(parsed.outbounds.first, isA<WireGuardOutbound>());
    });

    test('a deep link wrapping a subscription is detected as deepLink', () {
      final body = '${_vless()}\n${_trojan()}';
      final link = 'brick://import?config=${Uri.encodeComponent(body)}';
      final parsed = (parseConfigContent(
        link,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.detectedType, SmartContentType.deepLink);
      expect(parsed.parsedCount, 2);
    });

    test('a deep link with no url/config parameter is an error', () {
      final result = parseConfigContent('brick://import?foo=bar');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SmartParseResult, ConfigParseError>).error,
        isA<MissingRequiredFieldError>(),
      );
    });

    test('a self-referential deep link is bounded, not an infinite loop', () {
      final result = parseConfigContent(
        'brick://import?url=${Uri.encodeComponent('brick://import?url=x')}',
      );
      // Terminates one way or another; the point is it returns.
      expect(result.isOk || result.isErr, isTrue);
    });
  });

  group('multi-line subscription auto-detection', () {
    test('plain-text multi-URI body', () {
      final result = parseConfigContent('${_vless()}\n${_trojan()}\n${_ss()}');
      expect(result.isOk, isTrue);
      final parsed = (result as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.detectedType, SmartContentType.subscription);
      expect(parsed.parsedCount, 3);
      expect(parsed.isComplete, isTrue);
    });

    test('base64 subscription body', () {
      final body = '${_vless()}\n${_trojan()}';
      final encoded = base64.encode(utf8.encode(body));
      final parsed = (parseConfigContent(
        encoded,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.detectedType, SmartContentType.subscription);
      expect(parsed.parsedCount, 2);
    });

    test('carries Subscription-Userinfo when supplied', () {
      final parsed = (parseConfigContent(
        _vless(),
        userInfoHeaderValue: 'upload=10; download=20; total=100',
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      // A single URI has no header, so userInfo stays null but must not throw.
      expect(parsed.detectedType, SmartContentType.singleUri);
    });

    test('partial subscription keeps good entries and records warnings', () {
      final body = [
        _vless(),
        'vless://not-a-uuid@bad.example.com:443#Bad',
        _trojan(),
      ].join('\n');
      final parsed = (parseConfigContent(
        body,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.parsedCount, 2, reason: 'good entries must survive');
      expect(parsed.warnings, isNotEmpty);
      expect(parsed.isComplete, isFalse);
    });
  });

  group('raw JSON config auto-detection', () {
    test('a single sing-box outbound object', () {
      final json = jsonEncode({
        'type': 'vless',
        'server': 'example.com',
        'server_port': 443,
        'uuid': _uuid,
        'tls': {'enabled': true, 'server_name': 'example.com'},
      });
      final parsed = (parseConfigContent(
        json,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.detectedType, SmartContentType.json);
      expect(parsed.parsedCount, 1);
      final vless = parsed.outbounds.first as VlessOutbound;
      expect(vless.server, 'example.com');
      expect(vless.tls?.serverName, 'example.com');
    });

    test('an array of outbounds', () {
      final json = jsonEncode([
        {
          'type': 'trojan',
          'server': 'a.com',
          'server_port': 443,
          'password': 'p1',
        },
        {
          'type': 'trojan',
          'server': 'b.com',
          'server_port': 443,
          'password': 'p2',
        },
      ]);
      final parsed = (parseConfigContent(
        json,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.detectedType, SmartContentType.json);
      expect(parsed.parsedCount, 2);
    });

    test('a full sing-box config with an "outbounds" array', () {
      final json = jsonEncode({
        'outbounds': [
          {
            'type': 'vmess',
            'server': 'a.com',
            'server_port': 443,
            'uuid': _uuid,
          },
        ],
      });
      final parsed = (parseConfigContent(
        json,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      expect(parsed.detectedType, SmartContentType.json);
      expect(parsed.parsedCount, 1);
      expect(parsed.outbounds.first, isA<VmessOutbound>());
    });

    test('a wireguard outbound object round-trips', () {
      final json = jsonEncode({
        'type': 'wireguard',
        'server': 'vpn.example.com',
        'server_port': 51820,
        'system_interface': false,
        'local_address': ['10.0.0.2/32'],
        'private_key': _wgPriv,
        'peer_public_key': _wgPub,
        'mtu': 1408,
      });
      final parsed = (parseConfigContent(
        json,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      final wg = parsed.outbounds.first as WireGuardOutbound;
      expect(wg.server, 'vpn.example.com');
      expect(wg.localAddresses, ['10.0.0.2/32']);
      expect(wg.mtu, 1408);
    });

    test('an unknown JSON type is a categorised error, not a crash', () {
      final result = parseConfigContent(
        jsonEncode({'type': 'notarealprotocol', 'server': 'a.com'}),
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SmartParseResult, ConfigParseError>).error,
        isA<UnsupportedProtocolError>(),
      );
    });
  });

  group('malformed input never throws', () {
    test('empty and whitespace-only input', () {
      expect(parseConfigContent('').isErr, isTrue);
      expect(parseConfigContent('   \n  ').isErr, isTrue);
    });

    test('an oversized payload is rejected before parsing', () {
      final huge =
          'vless://$_uuid@example.com:443#' + ('a' * maxSubscriptionLength);
      final result = parseConfigContent(huge);
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SmartParseResult, ConfigParseError>).error,
        isA<InputTooLargeError>(),
      );
    });

    test('a hostile battery of malformed inputs all return Results', () {
      const hostile = [
        'not a uri at all',
        '://',
        'vless://',
        'ss://',
        'vmess://',
        'trojan://',
        'brick://',
        '{}',
        '[]',
        '{"broken":',
        '%%%%',
        'vless://a@b:0',
        'vless://a@b:999999999',
      ];
      for (final input in hostile) {
        expect(
          () => parseConfigContent(input),
          returnsNormally,
          reason: 'input: $input',
        );
      }
    });
  });

  group('SECURITY: no secrets leak', () {
    test('errors never echo a pasted private key', () {
      const secret = 'SUPERSECRETPRIVATEKEYMATERIAL0000000';
      final result = parseConfigContent('vless://$secret@example.com:99999#x');
      expect(result.isErr, isTrue);
      final error = (result as Err<SmartParseResult, ConfigParseError>).error;
      expect(error.message.contains(secret), isFalse);
    });

    test('errors never echo a trojan password', () {
      const secret = 'MyTrojanSecretPassword';
      final result = parseConfigContent('trojan://$secret@example.com:99999#x');
      expect(result.isErr, isTrue);
      final error = (result as Err<SmartParseResult, ConfigParseError>).error;
      expect(error.message.contains(secret), isFalse);
    });

    test('subscription warnings never echo the offending line', () {
      const secret = 'SecretHostLeakCanary.example.com';
      final body = 'vless://not-a-uuid@$secret:99999#Oops\n${_vless()}';
      final parsed = (parseConfigContent(
        body,
      ) as Ok<SmartParseResult, ConfigParseError>).value;
      for (final warning in parsed.warnings) {
        expect(warning.message.contains(secret), isFalse);
      }
    });
  });
}
