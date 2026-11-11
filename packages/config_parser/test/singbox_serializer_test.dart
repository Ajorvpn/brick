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

  group('QUIC-based protocols', () {
    // P2-T5 added Hysteria2 and TUIC, so every domain protocol serializes.
    test('tryBuild succeeds for hysteria2', () {
      final result = const SingBoxOutboundSerializer().tryBuild(
        Hysteria2Outbound(
          server: 'e.com',
          serverPort: 443,
          password: 'pw',
          tls: TlsSettings(enabled: true),
        ),
      );
      expect(result.isOk, isTrue);
      expect(
        (result as Ok<Map<String, dynamic>, ConfigParseError>).value['type'],
        'hysteria2',
      );
    });

    test('tryBuild succeeds for tuic', () {
      final result = const SingBoxOutboundSerializer().tryBuild(
        TuicOutbound(
          server: 'e.com',
          serverPort: 443,
          uuid: 'b831381d-6324-4d53-ad4f-8cda48b30811',
          password: 'pw',
          tls: TlsSettings(enabled: true),
        ),
      );
      expect(result.isOk, isTrue);
      expect(
        (result as Ok<Map<String, dynamic>, ConfigParseError>).value['type'],
        'tuic',
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

  // Pins the CURRENT accepted behaviour of AmneziaWG serialization, which is
  // correct today but load-bearing in a subtle way: `tryBuild` first sets
  // `'type': config.protocol.name` (which is 'amneziawg'), and the WireGuard
  // branch's `map` then overwrites it with 'wireguard' via `out.addAll(map)`.
  // The result is right for sing-box (which has no amneziawg outbound type),
  // but it depends on that overwrite ORDER. A refactor that reorders those
  // two statements would silently emit `"type": "amneziawg"`, which sing-box
  // would reject. This test fails loudly if that ever happens.
  group('AmneziaWG serialization lock-in', () {
    AmneziaWgOutbound _awg() => AmneziaWgOutbound(
      server: 'vpn.example.com',
      serverPort: 51820,
      privateKey: 'PLACEHOLDER-PRIVATE-KEY',
      peerPublicKey: 'PLACEHOLDER-PUBLIC-KEY',
      localAddresses: const ['10.0.0.2/32'],
      jc: 4,
      h1: 100,
    );

    test('emits type "wireguard", not "amneziawg"', () {
      final out = buildSingBoxOutbound(_awg());
      expect(out['type'], 'wireguard');
    });

    test('preserves the inherited WireGuard envelope', () {
      final out = buildSingBoxOutbound(_awg());
      expect(out['type'], 'wireguard');
      expect(out['server'], 'vpn.example.com');
      expect(out['server_port'], 51820);
      expect(out['local_address'], ['10.0.0.2/32']);
    });

    test('obfuscation params are NOT emitted as top-level sing-box keys', () {
      // sing-box has no AmneziaWG schema and rejects unknown top-level keys,
      // so these are deliberately omitted at runtime.
      final out = buildSingBoxOutbound(_awg());
      for (final key in [
        'jc',
        'jmin',
        'jmax',
        's1',
        's2',
        'h1',
        'h2',
        'h3',
        'h4',
      ]) {
        expect(
          out.containsKey(key),
          isFalse,
          reason: '$key must not be top-level',
        );
      }
    });
  });

  group('P7-T3 RFC 6066 SNI hardening', () {
    test('preserves valid domain SNI on domain endpoints', () {
      final out = buildSingBoxOutbound(
        VlessOutbound(
          server: 'node.example.com',
          serverPort: 443,
          uuid: _uuid,
          tls: TlsSettings(enabled: true, serverName: 'node.example.com'),
        ),
      );
      final tls = out['tls'] as Map<String, dynamic>;
      expect(tls['server_name'], 'node.example.com');
    });

    test('preserves valid domain SNI on IP-based endpoints', () {
      final out = buildSingBoxOutbound(
        VlessOutbound(
          server: '203.0.113.5',
          serverPort: 443,
          uuid: _uuid,
          tls: TlsSettings(enabled: true, serverName: 'cdn.example.com'),
        ),
      );
      final tls = out['tls'] as Map<String, dynamic>;
      expect(tls['server_name'], 'cdn.example.com');
    });

    test('omits server_name when serverName is null or empty', () {
      final outNull = buildSingBoxOutbound(
        VlessOutbound(
          server: 'node.example.com',
          serverPort: 443,
          uuid: _uuid,
          tls: TlsSettings(enabled: true),
        ),
      );
      final tlsNull = outNull['tls'] as Map<String, dynamic>;
      expect(tlsNull.containsKey('server_name'), isFalse);

      final outEmpty = buildSingBoxOutbound(
        VlessOutbound(
          server: 'node.example.com',
          serverPort: 443,
          uuid: _uuid,
          tls: TlsSettings(enabled: true, serverName: ''),
        ),
      );
      final tlsEmpty = outEmpty['tls'] as Map<String, dynamic>;
      expect(tlsEmpty.containsKey('server_name'), isFalse);
    });

    test('omits server_name when serverName is raw IPv4 literal', () {
      final out = buildSingBoxOutbound(
        VlessOutbound(
          server: '203.0.113.5',
          serverPort: 443,
          uuid: _uuid,
          tls: TlsSettings(enabled: true, serverName: '203.0.113.5'),
        ),
      );
      final tls = out['tls'] as Map<String, dynamic>;
      expect(tls.containsKey('server_name'), isFalse);
    });

    test('omits server_name when serverName is raw IPv6 literal', () {
      final out = buildSingBoxOutbound(
        VlessOutbound(
          server: '2001:db8::1',
          serverPort: 443,
          uuid: _uuid,
          tls: TlsSettings(enabled: true, serverName: '2001:db8::1'),
        ),
      );
      final tls = out['tls'] as Map<String, dynamic>;
      expect(tls.containsKey('server_name'), isFalse);
    });

    test(
      'omits server_name when serverName is bracketed IPv6 literal [::1]',
      () {
        final out = buildSingBoxOutbound(
          VlessOutbound(
            server: '[::1]',
            serverPort: 443,
            uuid: _uuid,
            tls: TlsSettings(enabled: true, serverName: '[::1]'),
          ),
        );
        final tls = out['tls'] as Map<String, dynamic>;
        expect(tls.containsKey('server_name'), isFalse);
      },
    );

    test('omits server_name in extraParams when it is an IP literal', () {
      final out = buildSingBoxOutbound(
        Hysteria2Outbound(
          server: '203.0.113.5',
          serverPort: 443,
          password: 'pass',
          tls: TlsSettings(enabled: true),
          extraParams: {'server_name': '203.0.113.5', 'insecure': true},
        ),
      );
      final tls = out['tls'] as Map<String, dynamic>;
      expect(tls.containsKey('server_name'), isFalse);
      expect(tls['insecure'], isTrue);
    });
  });

  group(
    'P9-T1 gap filling: transports and extra options in buildSingBoxOutbound',
    () {
      test(
        'serializes GrpcTransport, HttpTransport, and HttpUpgradeTransport',
        () {
          final grpcOut = buildSingBoxOutbound(
            const VlessOutbound(
              server: 'grpc.example.com',
              serverPort: 443,
              uuid: _uuid,
              transport: GrpcTransport(serviceName: 'grpc-service'),
            ),
          );
          final grpcTransport = grpcOut['transport'] as Map<String, dynamic>;
          expect(grpcTransport['type'], 'grpc');
          expect(grpcTransport['service_name'], 'grpc-service');

          final httpOut = buildSingBoxOutbound(
            VmessOutbound(
              server: 'http.example.com',
              serverPort: 443,
              uuid: _uuid,
              transport: HttpTransport(
                host: ['cdn.example.com'],
                path: '/stream',
                method: 'POST',
                headers: {'User-Agent': 'brick/1.0'},
              ),
            ),
          );
          final httpTransport = httpOut['transport'] as Map<String, dynamic>;
          expect(httpTransport['type'], 'http');
          expect(httpTransport['host'], ['cdn.example.com']);
          expect(httpTransport['path'], '/stream');
          expect(httpTransport['method'], 'POST');
          expect(httpTransport['headers'], {'User-Agent': 'brick/1.0'});

          final upgradeOut = buildSingBoxOutbound(
            TrojanOutbound(
              server: 'upgrade.example.com',
              serverPort: 443,
              password: 'pass',
              transport: HttpUpgradeTransport(
                host: 'ws.example.com',
                path: '/upgrade',
              ),
            ),
          );
          final upgradeTransport =
              upgradeOut['transport'] as Map<String, dynamic>;
          expect(upgradeTransport['type'], 'httpupgrade');
          expect(upgradeTransport['host'], 'ws.example.com');
          expect(upgradeTransport['path'], '/upgrade');
        },
      );
    },
  );

  group('P9-T1 gap filling: readSingBoxOutboundJson exhaustive coverage', () {
    test('validates type and server/port syntax', () {
      final noType = readSingBoxOutboundJson({});
      expect(noType.isErr, isTrue);
      expect((noType as Err).error, isA<InvalidSyntaxError>());

      final badType = readSingBoxOutboundJson({'type': 'invalid_vpn_proto'});
      expect(badType.isErr, isTrue);
      expect((badType as Err).error, isA<UnsupportedProtocolError>());

      final noServer = readSingBoxOutboundJson({'type': 'shadowsocks'});
      expect(noServer.isErr, isTrue);
      expect((noServer as Err).error, isA<MissingRequiredFieldError>());

      final noPort = readSingBoxOutboundJson({
        'type': 'shadowsocks',
        'server': 'ss.example.com',
      });
      expect(noPort.isErr, isTrue);
      expect((noPort as Err).error, isA<MissingRequiredFieldError>());
    });

    test('reads shadowsocks outbound and validates mandatory fields', () {
      final missingMethod = readSingBoxOutboundJson({
        'type': 'shadowsocks',
        'server': 'ss.example.com',
        'server_port': 8388,
      });
      expect(missingMethod.isErr, isTrue);

      final missingPass = readSingBoxOutboundJson({
        'type': 'shadowsocks',
        'server': 'ss.example.com',
        'server_port': 8388,
        'method': '2022-blake3-aes-128-gcm',
      });
      expect(missingPass.isErr, isTrue);

      final valid = readSingBoxOutboundJson({
        'type': 'shadowsocks',
        'server': 'ss.example.com',
        'server_port': 8388,
        'method': '2022-blake3-aes-128-gcm',
        'password': 'sec',
        'plugin': 'obfs-local',
        'plugin_opts': 'obfs=http',
        'udp_over_tcp': true,
      });
      expect(valid.isOk, isTrue);
      final ss = (valid as Ok).value as ShadowsocksOutbound;
      expect(ss.server, 'ss.example.com');
      expect(ss.plugin, 'obfs-local');
      expect(ss.udpOverTcp, isTrue);
    });

    test('reads trojan outbound and validates mandatory fields', () {
      final missingPass = readSingBoxOutboundJson({
        'type': 'trojan',
        'server': 'tr.example.com',
        'server_port': 443,
      });
      expect(missingPass.isErr, isTrue);

      final valid = readSingBoxOutboundJson({
        'type': 'trojan',
        'server': 'tr.example.com',
        'server_port': 443,
        'password': 'sec',
        'tls': {
          'enabled': true,
          'server_name': 'sni.example.com',
          'alpn': ['h2', 'http/1.1'],
          'insecure': true,
          'utls': {'fingerprint': 'chrome'},
          'reality': {'enabled': true, 'public_key': 'pubk', 'short_id': 'sid'},
        },
      });
      expect(valid.isOk, isTrue);
      final tr = (valid as Ok).value as TrojanOutbound;
      expect(tr.server, 'tr.example.com');
      expect(tr.tls?.serverName, 'sni.example.com');
      expect(tr.tls?.insecure, isTrue);
      expect(tr.tls?.reality?.publicKey, 'pubk');
      expect(tr.tls?.utls?.fingerprint, 'chrome');
    });

    test('reads vmess and vless outbounds and validates mandatory fields', () {
      final missingVmessUuid = readSingBoxOutboundJson({
        'type': 'vmess',
        'server': 'vm.example.com',
        'server_port': 443,
      });
      expect(missingVmessUuid.isErr, isTrue);

      final validVmess = readSingBoxOutboundJson({
        'type': 'vmess',
        'server': 'vm.example.com',
        'server_port': 443,
        'uuid': _uuid,
        'security': 'chacha20-poly1305',
        'alter_id': 16,
      });
      expect(validVmess.isOk, isTrue);
      final vm = (validVmess as Ok).value as VmessOutbound;
      expect(vm.security, 'chacha20-poly1305');
      expect(vm.alterId, 16);

      final missingVlessUuid = readSingBoxOutboundJson({
        'type': 'vless',
        'server': 'vl.example.com',
        'server_port': 443,
      });
      expect(missingVlessUuid.isErr, isTrue);

      final validVless = readSingBoxOutboundJson({
        'type': 'vless',
        'server': 'vl.example.com',
        'server_port': 443,
        'uuid': _uuid,
        'flow': 'xtls-rprx-vision',
        'packet_encoding': 'xudp',
      });
      expect(validVless.isOk, isTrue);
      final vl = (validVless as Ok).value as VlessOutbound;
      expect(vl.flow, 'xtls-rprx-vision');
      expect(vl.packetEncoding, 'xudp');
    });

    test('reads hysteria2 and tuic outbounds', () {
      final missingHyPass = readSingBoxOutboundJson({
        'type': 'hysteria2',
        'server': 'hy.example.com',
        'server_port': 443,
      });
      expect(missingHyPass.isErr, isTrue);

      final validHy = readSingBoxOutboundJson({
        'type': 'hysteria2',
        'server': 'hy.example.com',
        'server_port': 443,
        'password': 'sec',
        'up_mbps': 50,
        'down_mbps': 100,
        'obfs': {'type': 'salamander', 'password': 'obfs-pass'},
      });
      expect(validHy.isOk, isTrue);
      final hy = (validHy as Ok).value as Hysteria2Outbound;
      expect(hy.upMbps, 50);
      expect(hy.downMbps, 100);
      expect(hy.obfsType, 'salamander');

      final missingTuicUuid = readSingBoxOutboundJson({
        'type': 'tuic',
        'server': 'tuic.example.com',
        'server_port': 443,
      });
      expect(missingTuicUuid.isErr, isTrue);

      final missingTuicPass = readSingBoxOutboundJson({
        'type': 'tuic',
        'server': 'tuic.example.com',
        'server_port': 443,
        'uuid': _uuid,
      });
      expect(missingTuicPass.isErr, isTrue);

      final validTuic = readSingBoxOutboundJson({
        'type': 'tuic',
        'server': 'tuic.example.com',
        'server_port': 443,
        'uuid': _uuid,
        'password': 'sec',
        'congestion_control': 'bbr',
        'udp_relay_mode': 'quic',
        'udp_over_stream': true,
        'zero_rtt_handshake': true,
      });
      expect(validTuic.isOk, isTrue);
      final tuic = (validTuic as Ok).value as TuicOutbound;
      expect(tuic.congestionControl, 'bbr');
      expect(tuic.udpRelayMode, 'quic');
      expect(tuic.udpOverStream, isTrue);
      expect(tuic.zeroRttHandshake, isTrue);
    });

    test('reads wireguard and amneziawg outbounds', () {
      final missingPriv = readSingBoxOutboundJson({
        'type': 'wireguard',
        'server': 'wg.example.com',
        'server_port': 51820,
      });
      expect(missingPriv.isErr, isTrue);

      final missingPub = readSingBoxOutboundJson({
        'type': 'wireguard',
        'server': 'wg.example.com',
        'server_port': 51820,
        'private_key': 'priv',
      });
      expect(missingPub.isErr, isTrue);

      final missingAddr = readSingBoxOutboundJson({
        'type': 'wireguard',
        'server': 'wg.example.com',
        'server_port': 51820,
        'private_key': 'priv',
        'peer_public_key': 'pub',
      });
      expect(missingAddr.isErr, isTrue);

      final emptyAddr = readSingBoxOutboundJson({
        'type': 'wireguard',
        'server': 'wg.example.com',
        'server_port': 51820,
        'private_key': 'priv',
        'peer_public_key': 'pub',
        'local_address': [''],
      });
      expect(emptyAddr.isErr, isTrue);

      final validWg = readSingBoxOutboundJson({
        'type': 'wireguard',
        'server': 'wg.example.com',
        'server_port': 51820,
        'private_key': 'priv',
        'peer_public_key': 'pub',
        'local_address': ['10.0.0.2/32'],
        'pre_shared_key': 'psk',
        'reserved': [1, 2, 3],
        'mtu': 1420,
        'workers': 4,
      });
      expect(validWg.isOk, isTrue);
      final wg = (validWg as Ok).value as WireGuardOutbound;
      expect(wg.presharedKey, 'psk');
      expect(wg.reserved, [1, 2, 3]);
      expect(wg.mtu, 1420);
      expect(wg.workers, 4);

      final validAwg = readSingBoxOutboundJson({
        'type': 'wireguard',
        'server': 'wg.example.com',
        'server_port': 51820,
        'private_key': 'priv',
        'peer_public_key': 'pub',
        'local_address': ['10.0.0.2/32'],
        'amneziawg_obfuscation': {
          'jc': 3,
          'jmin': 10,
          'jmax': 50,
          's1': 15,
          's2': 20,
          'h1': 1,
          'h2': 2,
          'h3': 3,
          'h4': 4,
        },
      });
      expect(validAwg.isOk, isTrue);
      final awg = (validAwg as Ok).value as AmneziaWgOutbound;
      expect(awg.jc, 3);
      expect(awg.jmin, 10);
      expect(awg.jmax, 50);
      expect(awg.s1, 15);
      expect(awg.s2, 20);
      expect(awg.h1, 1);
    });
  });
}
