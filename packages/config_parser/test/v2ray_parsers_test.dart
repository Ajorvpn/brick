// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

/// A syntactically valid UUID, reused across tests. It is a dummy value, not
/// a real credential.
const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';

void main() {
  group('VLESS', () {
    test('parses a plain TCP link', () {
      final result = parseVlessUri(
        'vless://$_uuid@example.com:443#My%20Server',
      );
      expect(result.isOk, isTrue);
      final config = (result as Ok<OutboundConfig, ConfigParseError>).value;
      expect(config, isA<VlessOutbound>());
      final vless = config as VlessOutbound;
      expect(vless.server, 'example.com');
      expect(vless.serverPort, 443);
      expect(vless.uuid, _uuid);
      expect(vless.protocol, ProtocolType.vless);
      expect(vless.tls, isNull);
      expect(vless.transport, isNull);
    });

    test('parses a WebSocket + TLS link', () {
      final result = parseVlessUri(
        'vless://$_uuid@example.com:443'
        '?type=ws&security=tls&path=%2Fray&host=cdn.example.com&sni=example.com'
        '#WS',
      );
      expect(result.isOk, isTrue);
      final vless =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as VlessOutbound;
      // `network` is the L4 network in sing-box, never the transport name.
      // 'ws' belongs to the transport block (P2-T4 fix).
      expect(vless.network, isNull);
      expect(vless.transport, isA<WebSocketTransport>());
      expect((vless.transport! as WebSocketTransport).path, '/ray');
      expect(
        (vless.transport! as WebSocketTransport).headers?['Host'],
        'cdn.example.com',
      );
      expect(vless.tls, isNotNull);
      expect(vless.tls!.serverName, 'example.com');
    });

    test('parses a gRPC link and requires serviceName', () {
      final ok = parseVlessUri(
        'vless://$_uuid@example.com:443?type=grpc&serviceName=grpcsvc#g',
      );
      expect(ok.isOk, isTrue);
      final vless =
          (ok as Ok<OutboundConfig, ConfigParseError>).value as VlessOutbound;
      expect(vless.transport, isA<GrpcTransport>());

      final missing = parseVlessUri(
        'vless://$_uuid@example.com:443?type=grpc#g',
      );
      expect(missing.isErr, isTrue);
      expect(
        ((missing as Err<OutboundConfig, ConfigParseError>).error),
        isA<MissingRequiredFieldError>().having(
          (e) => e.field,
          'field',
          'serviceName',
        ),
      );
    });

    test('parses a REALITY link with flow', () {
      final result = parseVlessUri(
        'vless://$_uuid@example.com:443'
        '?security=reality&pbk=PUBLICKEY&sid=abcd&spx=%2F&fp=chrome'
        '&flow=xtls-rprx-vision#REALITY',
      );
      expect(result.isOk, isTrue);
      final vless =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as VlessOutbound;
      expect(vless.tls!.reality, isNotNull);
      expect(vless.tls!.reality!.publicKey, 'PUBLICKEY');
      expect(vless.tls!.reality!.shortId, 'abcd');
      expect(vless.tls!.utls!.fingerprint, 'chrome');
      expect(vless.flow, 'xtls-rprx-vision');
    });

    test('parses a splithttp link', () {
      final result = parseVlessUri(
        'vless://$_uuid@example.com:443?type=splithttp&path=%2Fsplit#S',
      );
      expect(result.isOk, isTrue);
      final vless =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as VlessOutbound;
      expect(vless.transport, isA<HttpUpgradeTransport>());
    });

    test('rejects a missing UUID', () {
      final result = parseVlessUri('vless://example.com:443#NoUUID');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>(),
      );
    });

    test('rejects a malformed UUID without echoing it', () {
      const bad = 'not-a-uuid-secret-value';
      final result = parseVlessUri('vless://$bad@example.com:443#x');
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error, isA<InvalidFieldValueError>());
      expect(error.message.contains(bad), isFalse);
    });

    test('rejects an out-of-range port', () {
      final result = parseVlessUri('vless://$_uuid@example.com:99999#x');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidFieldValueError>().having((e) => e.field, 'field', 'port'),
      );
    });

    test('rejects an unknown transport type', () {
      final result = parseVlessUri(
        'vless://$_uuid@example.com:443?type=teleport#x',
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidFieldValueError>().having((e) => e.field, 'field', 'type'),
      );
    });

    test('rejects a non-vless scheme', () {
      final result = parseVlessUri('trojan://pw@example.com:443');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<UnsupportedSchemeError>(),
      );
    });
  });

  group('VMess', () {
    String vmessLink(Map<String, Object?> json) =>
        'vmess://${base64.encode(utf8.encode(jsonEncode(json)))}';

    test('parses a v2rayN base64-JSON link', () {
      final result = parseVmessUri(
        vmessLink({
          'v': '2',
          'ps': 'My VMess',
          'add': 'example.com',
          'port': '443',
          'id': _uuid,
          'aid': '0',
          'net': 'ws',
          'path': '/vm',
          'host': 'cdn.example.com',
          'tls': 'tls',
        }),
      );
      expect(result.isOk, isTrue);
      final vmess =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as VmessOutbound;
      expect(vmess.server, 'example.com');
      expect(vmess.serverPort, 443);
      expect(vmess.uuid, _uuid);
      expect(vmess.alterId, 0);
      // `net` in v2rayN JSON is the transport, not the L4 network.
      expect(vmess.network, isNull);
      expect(vmess.transport, isA<WebSocketTransport>());
      expect(vmess.tls, isNotNull);
      expect(vmess.protocol, ProtocolType.vmess);
    });

    test('rejects a corrupted base64 payload', () {
      final result = parseVmessUri('vmess://!!!not-base64!!!');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<CorruptedBase64Error>(),
      );
    });

    test('rejects base64 that decodes to non-JSON', () {
      final result = parseVmessUri(
        'vmess://${base64.encode(utf8.encode('not json at all'))}',
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidSyntaxError>(),
      );
    });

    test('rejects a missing address', () {
      final result = parseVmessUri(vmessLink({'port': '443', 'id': _uuid}));
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>().having((e) => e.field, 'field', 'add'),
      );
    });

    test('rejects an invalid port', () {
      final result = parseVmessUri(
        vmessLink({'add': 'example.com', 'port': 'abc', 'id': _uuid}),
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidFieldValueError>().having((e) => e.field, 'field', 'port'),
      );
    });

    test('rejects a malformed uuid without echoing it', () {
      const bad = 'totally-not-a-uuid';
      final result = parseVmessUri(
        vmessLink({'add': 'example.com', 'port': '443', 'id': bad}),
      );
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(bad), isFalse);
    });

    test('extracts the remark', () {
      final link = vmessLink({
        'ps': 'My VMess',
        'add': 'example.com',
        'port': '443',
        'id': _uuid,
      });
      expect(parseUriRemark(link), 'My VMess');
    });
  });

  group('Trojan', () {
    test('parses a trojan link with TLS', () {
      final result = parseTrojanUri(
        'trojan://mypassword@example.com:443?sni=example.com#Trojan%20Node',
      );
      expect(result.isOk, isTrue);
      final trojan =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as TrojanOutbound;
      expect(trojan.server, 'example.com');
      expect(trojan.serverPort, 443);
      expect(trojan.password, 'mypassword');
      expect(trojan.tls, isNotNull);
      expect(trojan.protocol, ProtocolType.trojan);
    });

    test('percent-decodes the password', () {
      final result = parseTrojanUri('trojan://p%40ss%3Aword@example.com:443#x');
      expect(result.isOk, isTrue);
      final trojan =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as TrojanOutbound;
      expect(trojan.password, 'p@ss:word');
    });

    test('rejects a missing password', () {
      final result = parseTrojanUri('trojan://example.com:443#x');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>().having(
          (e) => e.field,
          'field',
          'password',
        ),
      );
    });

    test('rejects a missing port', () {
      final result = parseTrojanUri('trojan://pw@example.com#x');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>().having(
          (e) => e.field,
          'field',
          'port',
        ),
      );
    });

    test('SECURITY: error never contains the password', () {
      const secret = 'sup3rSecretTrojanPassword';
      // Force a later failure (bad port) so an error is produced at all.
      final result = parseTrojanUri('trojan://$secret@example.com:99999#x');
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(secret), isFalse);
    });
  });

  group('Shadowsocks', () {
    test('parses SIP002 with base64 userinfo', () {
      final userInfo = base64.encode(utf8.encode('aes-256-gcm:secretpw'));
      final result = parseShadowsocksUri(
        'ss://$userInfo@example.com:8388#SS%20Node',
      );
      expect(result.isOk, isTrue);
      final ss =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as ShadowsocksOutbound;
      expect(ss.server, 'example.com');
      expect(ss.serverPort, 8388);
      expect(ss.method, 'aes-256-gcm');
      expect(ss.password, 'secretpw');
      expect(ss.protocol, ProtocolType.shadowsocks);
    });

    test('parses SIP002 with literal userinfo', () {
      final result = parseShadowsocksUri(
        'ss://aes-256-gcm:secretpw@example.com:8388#x',
      );
      expect(result.isOk, isTrue);
      final ss =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as ShadowsocksOutbound;
      expect(ss.method, 'aes-256-gcm');
      expect(ss.password, 'secretpw');
    });

    test('parses the legacy fully-base64 form', () {
      final legacy = base64.encode(
        utf8.encode('chacha20-ietf-poly1305:legacypw@example.com:9000'),
      );
      final result = parseShadowsocksUri('ss://$legacy#Legacy');
      expect(result.isOk, isTrue);
      final ss =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as ShadowsocksOutbound;
      expect(ss.server, 'example.com');
      expect(ss.serverPort, 9000);
      expect(ss.method, 'chacha20-ietf-poly1305');
      expect(ss.password, 'legacypw');
    });

    test('rejects a missing method separator', () {
      final userInfo = base64.encode(utf8.encode('nocolonhere'));
      final result = parseShadowsocksUri('ss://$userInfo@example.com:8388#x');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidSyntaxError>(),
      );
    });

    test('rejects a missing port', () {
      final userInfo = base64.encode(utf8.encode('aes-256-gcm:pw'));
      final result = parseShadowsocksUri('ss://$userInfo@example.com#x');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidSyntaxError>(),
      );
    });

    test('rejects a legacy payload with no @ separator', () {
      final bad = base64.encode(utf8.encode('method:passwordhost:8388'));
      final result = parseShadowsocksUri('ss://$bad#x');
      expect(result.isErr, isTrue);
    });

    test('SECURITY: error never contains the password', () {
      const secret = 'MySecretShadowsocksPassword';
      final userInfo = base64.encode(utf8.encode('aes-256-gcm:$secret'));
      final result = parseShadowsocksUri('ss://$userInfo@example.com:99999#x');
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(secret), isFalse);
    });
  });

  group('unified parseUri router', () {
    test('routes each supported scheme', () {
      expect(parseUri('vless://$_uuid@example.com:443').isOk, isTrue);
      expect(
        parseUri(
          'vmess://${base64.encode(utf8.encode(jsonEncode({'add': 'example.com', 'port': '443', 'id': _uuid})))}',
        ).isOk,
        isTrue,
      );
      expect(parseUri('trojan://pw@example.com:443').isOk, isTrue);
      final userInfo = base64.encode(utf8.encode('aes-256-gcm:pw'));
      expect(parseUri('ss://$userInfo@example.com:8388').isOk, isTrue);
    });

    test('returns UnsupportedSchemeError for an unknown scheme', () {
      // hysteria2 is now a supported scheme (P2-T5); use a genuinely
      // unknown scheme here.
      final result = parseUri('notarealprotocol://pw@example.com:443');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<UnsupportedSchemeError>().having(
          (e) => e.scheme,
          'scheme',
          'notarealprotocol',
        ),
      );
    });

    test('rejects a string with no scheme separator', () {
      final result = parseUri('just some text');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidSyntaxError>(),
      );
    });

    test('rejects an oversized URI before parsing', () {
      final huge = 'vless://$_uuid@example.com:443#' + ('a' * maxUriLength);
      final result = parseUri(huge);
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InputTooLargeError>(),
      );
    });

    test('never throws on hostile input', () {
      const hostile = [
        '',
        'vless://',
        'vless://@',
        'vless://uuid@',
        'ss://',
        'ss://@',
        'vmess://',
        'trojan://',
        '://',
        'vless://u@h:0',
        'vless://u@h:99999999999999999999',
      ];
      for (final input in hostile) {
        expect(() => parseUri(input), returnsNormally, reason: 'input: $input');
      }
    });
  });

  group('toServerProfile extension', () {
    test('wraps a parsed config with caller-supplied identity', () {
      final parsed = parseVlessUri('vless://$_uuid@example.com:443#Remark');
      final config = (parsed as Ok<OutboundConfig, ConfigParseError>).value;
      final addedAt = DateTime.utc(2026, 9, 26);
      final profile = config.toServerProfile(
        id: 'profile-id-1',
        addedAt: addedAt,
        customRemark: 'My Node',
      );
      expect(profile.id, 'profile-id-1');
      expect(profile.name, 'My Node');
      expect(profile.addedAt, addedAt);
      expect(profile.config, config);
    });

    test('derives a host:port name when no remark is given', () {
      final parsed = parseVlessUri('vless://$_uuid@example.com:443');
      final config = (parsed as Ok<OutboundConfig, ConfigParseError>).value;
      final profile = config.toServerProfile(
        id: 'x',
        addedAt: DateTime.utc(2026),
      );
      expect(profile.name, 'example.com:443');
    });
  });
}
