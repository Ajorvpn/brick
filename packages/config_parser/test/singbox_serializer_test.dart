// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';

void main() {
  group('VLESS serialization', () {
    test('plain outbound emits the verified sing-box keys', () {
      final out = buildSingBoxOutbound(
        const VlessOutbound(
          server: 'example.com',
          serverPort: 443,
          uuid: _uuid,
        ),
        tag: 'vless-out',
      );

      expect(out['type'], 'vless');
      expect(out['tag'], 'vless-out');
      expect(out['server'], 'example.com');
      expect(out['server_port'], 443);
      expect(out['uuid'], _uuid);
      // Absent optional keys must be omitted, not emitted as null.
      expect(out.containsKey('flow'), isFalse);
      expect(out.containsKey('tls'), isFalse);
      expect(out.containsKey('transport'), isFalse);
      expect(out.containsKey('network'), isFalse);
    });

    test('omits tag when not supplied', () {
      final out = buildSingBoxOutbound(
        const VlessOutbound(server: 'e.com', serverPort: 1, uuid: _uuid),
      );
      expect(out.containsKey('tag'), isFalse);
    });

    test('REALITY + uTLS + flow serialize into the tls object', () {
      final out = buildSingBoxOutbound(
        VlessOutbound(
          server: 'example.com',
          serverPort: 443,
          uuid: _uuid,
          flow: 'xtls-rprx-vision',
          tls: TlsSettings(
            enabled: true,
            serverName: 'example.com',
            alpn: ['h2', 'http/1.1'],
            utls: const UtlsSettings(enabled: true, fingerprint: 'chrome'),
            reality: const RealitySettings(
              enabled: true,
              publicKey: 'PBK',
              shortId: 'ab12',
            ),
          ),
        ),
      );

      expect(out['flow'], 'xtls-rprx-vision');
      final tls = out['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls['server_name'], 'example.com');
      expect(tls['alpn'], ['h2', 'http/1.1']);
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
      expect((tls['utls'] as Map)['enabled'], isTrue);
      expect((tls['reality'] as Map)['public_key'], 'PBK');
      expect((tls['reality'] as Map)['short_id'], 'ab12');
      expect((tls['reality'] as Map)['enabled'], isTrue);
    });

    test('WebSocket transport uses type "ws" and snake_case fields', () {
      final out = buildSingBoxOutbound(
        VlessOutbound(
          server: 'e.com',
          serverPort: 443,
          uuid: _uuid,
          transport: WebSocketTransport(
            path: '/ray',
            headers: {'Host': 'cdn.example.com'},
          ),
        ),
      );

      final transport = out['transport'] as Map<String, dynamic>;
      expect(transport['type'], 'ws');
      expect(transport['path'], '/ray');
      expect((transport['headers'] as Map)['Host'], 'cdn.example.com');
    });

    test('gRPC transport uses service_name', () {
      final out = buildSingBoxOutbound(
        const VlessOutbound(
          server: 'e.com',
          serverPort: 443,
          uuid: _uuid,
          transport: GrpcTransport(serviceName: 'grpcsvc'),
        ),
      );
      final transport = out['transport'] as Map<String, dynamic>;
      expect(transport['type'], 'grpc');
      expect(transport['service_name'], 'grpcsvc');
    });

    test('splithttp maps to sing-box "httpupgrade", NOT "splithttp"', () {
      final out = buildSingBoxOutbound(
        VlessOutbound(
          server: 'e.com',
          serverPort: 443,
          uuid: _uuid,
          transport: HttpUpgradeTransport(host: 'h.com', path: '/s'),
        ),
      );
      final transport = out['transport'] as Map<String, dynamic>;
      expect(transport['type'], 'httpupgrade');
      expect(transport['type'] == 'splithttp', isFalse);
      expect(transport['host'], 'h.com');
      expect(transport['path'], '/s');
    });

    test('network is omitted when it holds a transport name, not "ws"', () {
      // Regression guard: emitting network:"ws" would be invalid sing-box.
      final out = buildSingBoxOutbound(
        const VlessOutbound(
          server: 'e.com',
          serverPort: 443,
          uuid: _uuid,
          network: 'ws',
        ),
      );
      expect(out.containsKey('network'), isFalse);
    });

    test('network IS emitted for a genuine L4 value', () {
      final out = buildSingBoxOutbound(
        const VlessOutbound(
          server: 'e.com',
          serverPort: 443,
          uuid: _uuid,
          network: 'udp',
        ),
      );
      expect(out['network'], 'udp');
    });
  });

  group('VMess serialization', () {
    test('emits every verified vmess key', () {
      final out = buildSingBoxOutbound(
        const VmessOutbound(
          server: 'example.com',
          serverPort: 443,
          uuid: _uuid,
        ),
      );

      expect(out['type'], 'vmess');
      expect(out['security'], 'auto');
      expect(out['alter_id'], 0);
      expect(out['global_padding'], isFalse);
      expect(out['authenticated_length'], isTrue);
      expect(out['server'], 'example.com');
      expect(out['server_port'], 443);
      expect(out['uuid'], _uuid);
    });

    test('preserves a non-default cipher and alterId', () {
      final out = buildSingBoxOutbound(
        const VmessOutbound(
          server: 'e.com',
          serverPort: 1,
          uuid: _uuid,
          security: 'aes-128-gcm',
          alterId: 1,
        ),
      );
      expect(out['security'], 'aes-128-gcm');
      expect(out['alter_id'], 1);
    });
  });

  group('Trojan serialization', () {
    test('emits server, port and password plus tls', () {
      final out = buildSingBoxOutbound(
        TrojanOutbound(
          server: 'example.com',
          serverPort: 443,
          password: 'pw',
          tls: TlsSettings(enabled: true, serverName: 'example.com'),
        ),
      );

      expect(out['type'], 'trojan');
      expect(out['server'], 'example.com');
      expect(out['server_port'], 443);
      expect(out['password'], 'pw');
      expect((out['tls'] as Map)['server_name'], 'example.com');
    });
  });

  group('Shadowsocks serialization', () {
    test('emits method and password', () {
      final out = buildSingBoxOutbound(
        const ShadowsocksOutbound(
          server: 'example.com',
          serverPort: 8388,
          method: 'aes-256-gcm',
          password: 'pw',
        ),
      );

      expect(out['type'], 'shadowsocks');
      expect(out['server'], 'example.com');
      expect(out['server_port'], 8388);
      expect(out['method'], 'aes-256-gcm');
      expect(out['password'], 'pw');
      // Shadowsocks has no TLS/transport in the sing-box schema.
      expect(out.containsKey('tls'), isFalse);
      expect(out.containsKey('transport'), isFalse);
    });

    test('includes plugin fields only when set', () {
      final bare = buildSingBoxOutbound(
        const ShadowsocksOutbound(
          server: 'e.com',
          serverPort: 1,
          method: 'aes-256-gcm',
          password: 'pw',
        ),
      );
      expect(bare.containsKey('plugin'), isFalse);

      final withPlugin = buildSingBoxOutbound(
        const ShadowsocksOutbound(
          server: 'e.com',
          serverPort: 1,
          method: 'aes-256-gcm',
          password: 'pw',
          plugin: 'obfs-local',
          pluginOpts: 'obfs=http',
        ),
      );
      expect(withPlugin['plugin'], 'obfs-local');
      expect(withPlugin['plugin_opts'], 'obfs=http');
    });
  });

  group('multiplex', () {
    test('emits only when enabled, with snake_case keys', () {
      final off = buildSingBoxOutbound(
        const VlessOutbound(
          server: 'e.com',
          serverPort: 1,
          uuid: _uuid,
          multiplex: MultiplexSettings(enabled: false),
        ),
      );
      expect(off.containsKey('multiplex'), isFalse);

      final on = buildSingBoxOutbound(
        const VlessOutbound(
          server: 'e.com',
          serverPort: 1,
          uuid: _uuid,
          multiplex: MultiplexSettings(
            enabled: true,
            protocol: 'smux',
            maxConnections: 4,
          ),
        ),
      );
      final mux = on['multiplex'] as Map<String, dynamic>;
      expect(mux['enabled'], isTrue);
      expect(mux['protocol'], 'smux');
      expect(mux['max_connections'], 4);
    });
  });

  group('unimplemented protocols', () {
    test('tryBuild returns Err for hysteria2 instead of throwing', () {
      final result = const SingBoxOutboundSerializer().tryBuild(
        Hysteria2Outbound(
          server: 'e.com',
          serverPort: 443,
          password: 'pw',
          tls: TlsSettings(enabled: true),
        ),
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<Map<String, dynamic>, ConfigParseError>).error,
        isA<UnsupportedProtocolError>().having(
          (e) => e.protocol,
          'protocol',
          'hysteria2',
        ),
      );
    });

    test('build throws a clear UnsupportedError', () {
      expect(
        () => buildSingBoxOutbound(
          TuicOutbound(
            server: 'e.com',
            serverPort: 443,
            uuid: _uuid,
            password: 'pw',
            tls: TlsSettings(enabled: true),
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('end-to-end: parse then serialize', () {
    test('a parsed VLESS link round-trips into sing-box JSON', () {
      final parsed = parseVlessUri(
        'vless://$_uuid@example.com:443'
        '?security=tls&sni=example.com&type=ws&path=%2Fray#Node',
      );
      expect(parsed.isOk, isTrue);
      final out = buildSingBoxOutbound(
        (parsed as Ok<OutboundConfig, ConfigParseError>).value,
        tag: 'node',
      );

      expect(out['type'], 'vless');
      expect(out['server'], 'example.com');
      expect(out['server_port'], 443);
      expect(out['uuid'], _uuid);
      expect((out['tls'] as Map)['server_name'], 'example.com');
      expect((out['transport'] as Map)['type'], 'ws');
      expect((out['transport'] as Map)['path'], '/ray');
    });

    test('a parsed Shadowsocks link round-trips', () {
      final parsed = parseShadowsocksUri(
        'ss://YWVzLTI1Ni1nY206cHc=@example.com:8388#SS',
      );
      expect(parsed.isOk, isTrue);
      final out = buildSingBoxOutbound(
        (parsed as Ok<OutboundConfig, ConfigParseError>).value,
      );
      expect(out['type'], 'shadowsocks');
      expect(out['method'], 'aes-256-gcm');
      expect(out['server_port'], 8388);
    });
  });
}
