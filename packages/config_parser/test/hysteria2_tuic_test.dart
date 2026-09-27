// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';

void main() {
  group('Hysteria2 parsing', () {
    test('parses a minimal hy2:// link', () {
      final result = parseHysteria2Uri('hy2://myauth@example.com:443#Node');
      expect(result.isOk, isTrue);
      final hy2 =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as Hysteria2Outbound;
      expect(hy2.server, 'example.com');
      expect(hy2.serverPort, 443);
      expect(hy2.password, 'myauth');
      expect(hy2.protocol, ProtocolType.hysteria2);
      // Hysteria2 is QUIC-over-TLS: TLS is always on.
      expect(hy2.tls.enabled, isTrue);
      // SNI defaults to the server host when not given.
      expect(hy2.tls.serverName, 'example.com');
    });

    test('parses the long hysteria2:// scheme identically', () {
      final short = parseHysteria2Uri('hy2://pw@example.com:443#N');
      final long = parseHysteria2Uri('hysteria2://pw@example.com:443#N');
      expect(short.isOk, isTrue);
      expect(long.isOk, isTrue);
      expect(
        (short as Ok<OutboundConfig, ConfigParseError>).value,
        (long as Ok<OutboundConfig, ConfigParseError>).value,
      );
    });

    test('parses sni, insecure, alpn and bandwidth', () {
      final result = parseHysteria2Uri(
        'hy2://pw@example.com:443'
        '?sni=cdn.example.com&insecure=1&alpn=h3&upmbps=50&downmbps=200#N',
      );
      final hy2 =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as Hysteria2Outbound;
      expect(hy2.tls.serverName, 'cdn.example.com');
      expect(hy2.tls.insecure, isTrue);
      expect(hy2.tls.alpn, ['h3']);
      expect(hy2.upMbps, 50);
      expect(hy2.downMbps, 200);
    });

    test('accepts up/down and up_mbps/down_mbps spellings', () {
      final a = parseHysteria2Uri('hy2://pw@example.com:443?up=10&down=20');
      final b = parseHysteria2Uri(
        'hy2://pw@example.com:443?up_mbps=10&down_mbps=20',
      );
      final hy2a =
          (a as Ok<OutboundConfig, ConfigParseError>).value
              as Hysteria2Outbound;
      final hy2b =
          (b as Ok<OutboundConfig, ConfigParseError>).value
              as Hysteria2Outbound;
      expect(hy2a.upMbps, 10);
      expect(hy2a.downMbps, 20);
      expect(hy2b.upMbps, 10);
      expect(hy2b.downMbps, 20);
    });

    test('parses salamander obfuscation', () {
      final result = parseHysteria2Uri(
        'hy2://pw@example.com:443?obfs=salamander&obfs-password=obfspw#N',
      );
      final hy2 =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as Hysteria2Outbound;
      expect(hy2.obfsType, 'salamander');
      expect(hy2.obfsPassword, 'obfspw');
    });

    test('rejects an obfs type sing-box does not support', () {
      final result = parseHysteria2Uri(
        'hy2://pw@example.com:443?obfs=nonsense&obfs-password=x',
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidFieldValueError>().having((e) => e.field, 'field', 'obfs'),
      );
    });

    test('rejects obfs without a password', () {
      final result = parseHysteria2Uri(
        'hy2://pw@example.com:443?obfs=salamander',
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>(),
      );
    });

    test('rejects a missing auth string', () {
      final result = parseHysteria2Uri('hy2://example.com:443');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>(),
      );
    });

    test('rejects an invalid port', () {
      final result = parseHysteria2Uri('hy2://pw@example.com:99999');
      expect(result.isErr, isTrue);
    });

    test('rejects a non-hysteria2 scheme', () {
      final result = parseHysteria2Uri('vless://u@example.com:443');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<UnsupportedSchemeError>(),
      );
    });

    test('SECURITY: the auth secret never appears in an error', () {
      const secret = 'SuperSecretHy2Auth';
      // Force a later failure (bad port).
      final result = parseHysteria2Uri('hy2://$secret@example.com:99999');
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(secret), isFalse);
    });

    test('SECURITY: the obfs password never appears in an error', () {
      const secret = 'MyObfsSecret';
      final result = parseHysteria2Uri(
        'hy2://pw@example.com:443?obfs=bogus&obfs-password=$secret',
      );
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(secret), isFalse);
    });
  });

  group('Hysteria2 serialization', () {
    test('emits the verified sing-box keys', () {
      final parsed = parseHysteria2Uri(
        'hy2://pw@example.com:443?sni=cdn.example.com&upmbps=50&downmbps=200'
        '&obfs=salamander&obfs-password=obfspw#N',
      );
      final config = (parsed as Ok<OutboundConfig, ConfigParseError>).value;
      final out = buildSingBoxOutbound(config, tag: 'hy2-out');

      expect(out['type'], 'hysteria2');
      expect(out['tag'], 'hy2-out');
      expect(out['server'], 'example.com');
      expect(out['server_port'], 443);
      expect(out['password'], 'pw');
      expect(out['up_mbps'], 50);
      expect(out['down_mbps'], 200);

      final obfs = out['obfs'] as Map<String, dynamic>;
      expect(obfs['type'], 'salamander');
      expect(obfs['password'], 'obfspw');

      final tls = out['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls['server_name'], 'cdn.example.com');
    });

    test('omits obfs unless both halves are present', () {
      final bare = buildSingBoxOutbound(
        Hysteria2Outbound(
          server: 'e.com',
          serverPort: 443,
          password: 'pw',
          tls: TlsSettings(enabled: true),
        ),
      );
      expect(bare.containsKey('obfs'), isFalse);
    });
  });

  group('TUIC parsing', () {
    test('parses a tuic:// link with uuid and password', () {
      final result = parseTuicUri(
        'tuic://$_uuid:mypassword@example.com:443#Node',
      );
      expect(result.isOk, isTrue);
      final tuic =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as TuicOutbound;
      expect(tuic.server, 'example.com');
      expect(tuic.serverPort, 443);
      expect(tuic.uuid, _uuid);
      expect(tuic.password, 'mypassword');
      expect(tuic.protocol, ProtocolType.tuic);
      expect(tuic.tls.enabled, isTrue);
    });

    test('percent-decodes the password', () {
      final result = parseTuicUri(
        'tuic://$_uuid:p%40ss%3Aword@example.com:443',
      );
      final tuic =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as TuicOutbound;
      expect(tuic.password, 'p@ss:word');
    });

    test('parses congestion control and udp relay mode', () {
      final result = parseTuicUri(
        'tuic://$_uuid:pw@example.com:443'
        '?congestion_control=bbr&udp_relay_mode=native#N',
      );
      final tuic =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as TuicOutbound;
      expect(tuic.congestionControl, 'bbr');
      expect(tuic.udpRelayMode, 'native');
    });

    test('rejects an unsupported congestion control', () {
      final result = parseTuicUri(
        'tuic://$_uuid:pw@example.com:443?congestion_control=fastest',
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidFieldValueError>().having(
          (e) => e.field,
          'field',
          'congestion_control',
        ),
      );
    });

    test('rejects a malformed uuid without echoing it', () {
      const bad = 'definitely-not-a-uuid';
      final result = parseTuicUri('tuic://$bad:pw@example.com:443');
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(bad), isFalse);
    });

    test('rejects userinfo with no password separator', () {
      final result = parseTuicUri('tuic://$_uuid@example.com:443');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidSyntaxError>(),
      );
    });

    test('rejects a missing port', () {
      final result = parseTuicUri('tuic://$_uuid:pw@example.com');
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>(),
      );
    });

    test('SECURITY: the password never appears in an error', () {
      const secret = 'MyTuicSecretPassword';
      final result = parseTuicUri('tuic://$_uuid:$secret@example.com:99999');
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(secret), isFalse);
    });
  });

  group('TUIC serialization', () {
    test('emits the verified sing-box keys', () {
      final parsed = parseTuicUri(
        'tuic://$_uuid:pw@example.com:443'
        '?congestion_control=bbr&udp_relay_mode=native&sni=cdn.example.com',
      );
      final config = (parsed as Ok<OutboundConfig, ConfigParseError>).value;
      final out = buildSingBoxOutbound(config, tag: 'tuic-out');

      expect(out['type'], 'tuic');
      expect(out['tag'], 'tuic-out');
      expect(out['server'], 'example.com');
      expect(out['server_port'], 443);
      expect(out['uuid'], _uuid);
      expect(out['password'], 'pw');
      expect(out['congestion_control'], 'bbr');
      expect(out['udp_relay_mode'], 'native');
      expect((out['tls'] as Map)['server_name'], 'cdn.example.com');
    });

    test('emits disable_sni carried through extraParams', () {
      final parsed = parseTuicUri(
        'tuic://$_uuid:pw@example.com:443?disable_sni=1',
      );
      final config = (parsed as Ok<OutboundConfig, ConfigParseError>).value;
      final out = buildSingBoxOutbound(config);
      expect((out['tls'] as Map)['disable_sni'], isTrue);
    });

    test('defaults congestion_control to cubic', () {
      final out = buildSingBoxOutbound(
        TuicOutbound(
          server: 'e.com',
          serverPort: 443,
          uuid: _uuid,
          password: 'pw',
          tls: TlsSettings(enabled: true),
        ),
      );
      expect(out['congestion_control'], 'cubic');
    });
  });

  group('unified router', () {
    test('routes hy2, hysteria2 and tuic', () {
      expect(parseUri('hy2://pw@example.com:443').isOk, isTrue);
      expect(parseUri('hysteria2://pw@example.com:443').isOk, isTrue);
      expect(parseUri('tuic://$_uuid:pw@example.com:443').isOk, isTrue);
    });

    test('routes each scheme to the right protocol', () {
      final hy2 = parseUri('hy2://pw@example.com:443');
      final tuic = parseUri('tuic://$_uuid:pw@example.com:443');
      expect(
        (hy2 as Ok<OutboundConfig, ConfigParseError>).value.protocol,
        ProtocolType.hysteria2,
      );
      expect(
        (tuic as Ok<OutboundConfig, ConfigParseError>).value.protocol,
        ProtocolType.tuic,
      );
    });

    test('parses remarks for the new schemes', () {
      expect(parseUriRemark('hy2://pw@example.com:443#My%20Node'), 'My Node');
      expect(
        parseUriRemark('tuic://$_uuid:pw@example.com:443#TUIC%20Node'),
        'TUIC Node',
      );
    });
  });

  group('all six protocols now serialize', () {
    test('tryBuild no longer rejects any domain protocol', () {
      final configs = <OutboundConfig>[
        const VlessOutbound(server: 'a.com', serverPort: 443, uuid: _uuid),
        const VmessOutbound(server: 'b.com', serverPort: 443, uuid: _uuid),
        const TrojanOutbound(server: 'c.com', serverPort: 443, password: 'p'),
        const ShadowsocksOutbound(
          server: 'd.com',
          serverPort: 8388,
          method: 'aes-256-gcm',
          password: 'p',
        ),
        Hysteria2Outbound(
          server: 'e.com',
          serverPort: 443,
          password: 'p',
          tls: TlsSettings(enabled: true),
        ),
        TuicOutbound(
          server: 'f.com',
          serverPort: 443,
          uuid: _uuid,
          password: 'p',
          tls: TlsSettings(enabled: true),
        ),
      ];
      for (final config in configs) {
        final result = const SingBoxOutboundSerializer().tryBuild(config);
        expect(
          result.isOk,
          isTrue,
          reason: '${config.protocol.name} must serialize',
        );
        expect(buildSingBoxOutbound(config)['type'], config.protocol.name);
      }
    });
  });
}
