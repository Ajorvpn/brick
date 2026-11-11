// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

final _tcpTls = TlsSettings(enabled: true);
final _quicTls = TlsSettings(enabled: true, serverName: 'q.example');

/// Exhaustively maps every outbound to a short label.
///
/// Why a switch with no `default`: the compiler must reject this function
/// the moment a seventh concrete outbound joins the hierarchy — the whole
/// point of sealing `OutboundConfig`, `TcpBasedOutbound`, and
/// `QuicBasedOutbound`.
String outboundLabel(OutboundConfig config) => switch (config) {
  VlessOutbound() => 'vless',
  VmessOutbound() => 'vmess',
  TrojanOutbound() => 'trojan',
  ShadowsocksOutbound() => 'ss',
  Hysteria2Outbound() => 'hysteria2',
  TuicOutbound() => 'tuic',
  // AmneziaWgOutbound extends WireGuardOutbound, so it is matched here too;
  // a separate case would be unreachable.
  WireGuardOutbound() => 'wireguard',
};

/// One instance of every concrete outbound, in protocol order.
final List<OutboundConfig> concreteOutbounds = [
  const VlessOutbound(server: 'v.example', serverPort: 443, uuid: 'u-1'),
  const VmessOutbound(server: 'm.example', serverPort: 443, uuid: 'u-2'),
  const TrojanOutbound(server: 't.example', serverPort: 443, password: 'p-1'),
  const ShadowsocksOutbound(
    server: 's.example',
    serverPort: 8388,
    method: '2022-blake3-aes-128-gcm',
    password: 'p-2',
  ),
  Hysteria2Outbound(
    server: 'h.example',
    serverPort: 443,
    password: 'p-3',
    tls: _quicTls,
  ),
  TuicOutbound(
    server: 'q.example',
    serverPort: 443,
    uuid: 'u-3',
    password: 'p-4',
    tls: _quicTls,
  ),
];

void main() {
  group('exhaustive switching over the sealed hierarchy', () {
    test('should match every concrete outbound without a default clause', () {
      expect(outboundLabel(concreteOutbounds[0]), 'vless');
      expect(outboundLabel(concreteOutbounds[1]), 'vmess');
      expect(outboundLabel(concreteOutbounds[2]), 'trojan');
      expect(outboundLabel(concreteOutbounds[3]), 'ss');
      expect(outboundLabel(concreteOutbounds[4]), 'hysteria2');
      expect(outboundLabel(concreteOutbounds[5]), 'tuic');
    });

    test(
      'should expose all six protocol types through the polymorphic getter',
      () {
        expect(concreteOutbounds.map((c) => c.protocol).toList(), [
          ProtocolType.vless,
          ProtocolType.vmess,
          ProtocolType.trojan,
          ProtocolType.shadowsocks,
          ProtocolType.hysteria2,
          ProtocolType.tuic,
        ]);
      },
    );

    test('should stamp schema version 1 on every outbound', () {
      for (final config in concreteOutbounds) {
        expect(config.schemaVersion, 1);
      }
    });
  });

  group('toJson discriminators', () {
    test('should emit type equal to protocol.scheme for every outbound', () {
      for (final config in concreteOutbounds) {
        final json = config.toJson();
        expect(
          json['type'],
          config.protocol.scheme,
          reason: 'discriminator mismatch for ${config.server}',
        );
        expect(json['server'], config.server);
        expect(json['server_port'], config.serverPort);
      }
    });
  });

  group('equality and identity', () {
    test('structurally equal outbounds are equal and share hashCode', () {
      final a = VlessOutbound(
        server: 'v.example',
        serverPort: 443,
        uuid: 'u',
        tls: TlsSettings(enabled: true, alpn: ['h2']),
      );
      final b = VlessOutbound(
        server: 'v.example',
        serverPort: 443,
        uuid: 'u',
        tls: TlsSettings(enabled: true, alpn: ['h2']),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(identical(a, b), isFalse);
    });

    test('the identical instance takes the fast path', () {
      final config = concreteOutbounds[0];
      expect(identical(config, config), isTrue);
      expect(config, config);
    });

    test('outbounds differing in one field are not equal', () {
      const a = TrojanOutbound(
        server: 't.example',
        serverPort: 443,
        password: 'p',
      );
      const b = TrojanOutbound(
        server: 't.example',
        serverPort: 443,
        password: 'other',
      );
      expect(a, isNot(b));
    });

    test('instances of different concrete types are never equal', () {
      expect(concreteOutbounds[0], isNot(concreteOutbounds[4]));
      expect(concreteOutbounds[3], isNot(concreteOutbounds[5]));
      expect(
        const VlessOutbound(server: 'x', serverPort: 1, uuid: 'u'),
        isNot(const VmessOutbound(server: 'x', serverPort: 1, uuid: 'u')),
      );
    });
  });

  group('family-specific construction', () {
    test('TcpBasedOutbound defaults leave every shared block null', () {
      const config = VlessOutbound(
        server: 'v.example',
        serverPort: 443,
        uuid: 'u',
      );
      expect(config.network, isNull);
      expect(config.tls, isNull);
      expect(config.transport, isNull);
      expect(config.multiplex, isNull);
    });

    test('QuicBasedOutbound requires tls at compile time (non-nullable)', () {
      // The absence of a compile error in this file proves `tls` is
      // non-nullable on the QUIC family; at runtime we assert the value
      // is carried through untouched.
      final config = Hysteria2Outbound(
        server: 'h.example',
        serverPort: 443,
        password: 'p',
        tls: _quicTls,
      );
      expect(identical(config.tls, _quicTls), isTrue);
      expect(config.quic, isNull);
    });

    test('VmessOutbound applies its security defaults', () {
      const config = VmessOutbound(
        server: 'm.example',
        serverPort: 443,
        uuid: 'u',
      );
      expect(config.security, 'auto');
      expect(config.alterId, 0);
      expect(config.globalPadding, isFalse);
      expect(config.authenticatedLength, isTrue);
    });

    test('TuicOutbound keeps zeroRttHandshake disabled by default', () {
      final config = TuicOutbound(
        server: 'q.example',
        serverPort: 443,
        uuid: 'u',
        password: 'p',
        tls: _quicTls,
      );
      expect(
        config.zeroRttHandshake,
        isFalse,
        reason: '0-RTT is replayable; the default MUST stay disabled',
      );
      expect(config.udpOverStream, isFalse);
      expect(config.congestionControl, 'cubic');
      expect(config.heartbeat, const Duration(seconds: 10));
    });
  });

  group('family serialization', () {
    test('TcpBasedOutbound omits null blocks and nests present ones', () {
      final transport = WebSocketTransport(path: '/ray');
      final json = VlessOutbound(
        server: 'v.example',
        serverPort: 443,
        uuid: 'u-1',
        tls: _tcpTls,
        transport: transport,
      ).toJson();
      expect(json['type'], 'vless');
      expect(json['uuid'], 'u-1');
      expect(json['tls'], _tcpTls.toJson());
      expect(json['transport'], transport.toJson());
      expect(json.containsKey('network'), isFalse);
      expect(json.containsKey('multiplex'), isFalse);
      expect(json.containsKey('flow'), isFalse);
    });

    test('ShadowsocksOutbound serializes plugin and udp_over_tcp fields', () {
      const config = ShadowsocksOutbound(
        server: 's.example',
        serverPort: 8388,
        method: '2022-blake3-aes-128-gcm',
        password: 'p',
        plugin: 'obfs-local',
        pluginOpts: 'obfs=http',
        udpOverTcp: true,
      );
      expect(config.toJson(), {
        'type': 'ss',
        'server': 's.example',
        'server_port': 8388,
        'method': '2022-blake3-aes-128-gcm',
        'password': 'p',
        'plugin': 'obfs-local',
        'plugin_opts': 'obfs=http',
        'udp_over_tcp': true,
      });
    });

    test('Hysteria2Outbound nests the obfs block when obfs is configured', () {
      final json = Hysteria2Outbound(
        server: 'h.example',
        serverPort: 443,
        password: 'p',
        tls: _quicTls,
        upMbps: 100,
        downMbps: 200,
        obfsType: 'salamander',
        obfsPassword: 'obfs-secret',
      ).toJson();
      expect(json['type'], 'hysteria2');
      expect(json['up_mbps'], 100);
      expect(json['down_mbps'], 200);
      expect(json['obfs'], {'type': 'salamander', 'password': 'obfs-secret'});
      expect(json['tls'], _quicTls.toJson());
      expect(json.containsKey('server_ports'), isFalse);
    });

    test('Hysteria2Outbound omits the obfs block when none is configured', () {
      final json = Hysteria2Outbound(
        server: 'h.example',
        serverPort: 443,
        password: 'p',
        tls: _quicTls,
      ).toJson();
      expect(json.containsKey('obfs'), isFalse);
    });

    group('Hysteria2Outbound obfs pairing validation', () {
      // Why this matters: a partially-set obfs block serialized to
      // `{"obfs": {"type": null, "password": "..."}}`, which sing-box
      // rejects. The constructor now refuses the state outright rather
      // than emitting a config that only fails at Phase 3 runtime.

      test('throws ArgumentError when only obfsType is set', () {
        expect(
          () => Hysteria2Outbound(
            server: 'h.example',
            serverPort: 443,
            password: 'p',
            tls: _quicTls,
            obfsType: 'salamander',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws ArgumentError when only obfsPassword is set', () {
        expect(
          () => Hysteria2Outbound(
            server: 'h.example',
            serverPort: 443,
            password: 'p',
            tls: _quicTls,
            obfsPassword: 'obfs-secret',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('does not leak the obfs password into the error message', () {
        Object? caught;
        try {
          Hysteria2Outbound(
            server: 'h.example',
            serverPort: 443,
            password: 'p',
            tls: _quicTls,
            obfsPassword: 'super-secret-obfs-value',
          );
        } on ArgumentError catch (error) {
          caught = error;
        }
        expect(caught, isNotNull);
        expect(
          '$caught',
          isNot(contains('super-secret-obfs-value')),
          reason: 'obfs passwords are credential material (SECURITY.md)',
        );
      });

      test('succeeds when both obfs fields are set', () {
        final outbound = Hysteria2Outbound(
          server: 'h.example',
          serverPort: 443,
          password: 'p',
          tls: _quicTls,
          obfsType: 'salamander',
          obfsPassword: 'obfs-secret',
        );
        expect(outbound.toJson()['obfs'], {
          'type': 'salamander',
          'password': 'obfs-secret',
        });
      });

      test('succeeds when neither obfs field is set', () {
        final outbound = Hysteria2Outbound(
          server: 'h.example',
          serverPort: 443,
          password: 'p',
          tls: _quicTls,
        );
        expect(outbound.toJson().containsKey('obfs'), isFalse);
      });
    });

    test('TuicOutbound serializes its defaults explicitly', () {
      final json = TuicOutbound(
        server: 'q.example',
        serverPort: 443,
        uuid: 'u',
        password: 'p',
        tls: _quicTls,
      ).toJson();
      expect(json['type'], 'tuic');
      expect(json['congestion_control'], 'cubic');
      expect(json['udp_over_stream'], isFalse);
      expect(json['zero_rtt_handshake'], isFalse);
      expect(
        json['heartbeat'],
        10000000,
        reason: 'Duration(seconds: 10) serialized as integer microseconds',
      );
      expect(json['tls'], _quicTls.toJson());
      expect(json.containsKey('udp_relay_mode'), isFalse);
      expect(json.containsKey('quic'), isFalse);
    });
  });

  group('source-level modifier verification', () {
    test('every concrete outbound is final; every family is sealed', () {
      // Dart cannot introspect `final`/`sealed` at runtime, so this test
      // asserts the declarations textually. If someone demotes a concrete
      // outbound to an extensible class (breaking the closed hierarchy)
      // or unseals a family, this test fails.
      final source = File('lib/src/outbound_config.dart').readAsStringSync();
      for (final name in [
        'VlessOutbound',
        'VmessOutbound',
        'TrojanOutbound',
        'ShadowsocksOutbound',
        'Hysteria2Outbound',
        'TuicOutbound',
      ]) {
        expect(
          source,
          contains('final class $name'),
          reason: '$name must be declared as `final class`',
        );
      }
      expect(source, contains('sealed class OutboundConfig'));
      expect(source, contains('sealed class TcpBasedOutbound'));
      expect(source, contains('sealed class QuicBasedOutbound'));
    });
  });

  group(
    'P9-T1 gap filling: equality, hashCode, toJson and composition coverage',
    () {
      test(
        'VmessOutbound equality, hashCode, and optional fields in toJson',
        () {
          const vmess1 = VmessOutbound(
            server: 'vmess.example',
            serverPort: 443,
            uuid: 'uuid-vmess',
            security: 'aes-128-gcm',
            alterId: 1,
            globalPadding: true,
            authenticatedLength: true,
            packetEncoding: 'packetaddr',
            network: 'tcp',
            multiplex: MultiplexSettings(enabled: true),
            extraParams: {'k1': 'v1'},
          );
          const vmess2 = VmessOutbound(
            server: 'vmess.example',
            serverPort: 443,
            uuid: 'uuid-vmess',
            security: 'aes-128-gcm',
            alterId: 1,
            globalPadding: true,
            authenticatedLength: true,
            packetEncoding: 'packetaddr',
            network: 'tcp',
            multiplex: MultiplexSettings(enabled: true),
            extraParams: {'k1': 'v1'},
          );
          const vmessDifferent = VmessOutbound(
            server: 'vmess.diff',
            serverPort: 443,
            uuid: 'uuid-vmess',
          );

          expect(vmess1, equals(vmess2));
          expect(vmess1.hashCode, equals(vmess2.hashCode));
          expect(vmess1, isNot(equals(vmessDifferent)));

          final json = vmess1.toJson();
          expect(json['network'], 'tcp');
          expect(json['packet_encoding'], 'packetaddr');
          expect(json['multiplex'], isA<Map<String, dynamic>>());
          expect(json['k1'], 'v1');
        },
      );

      test(
        'TrojanOutbound equality, hashCode, and optional fields in toJson',
        () {
          const trojan1 = TrojanOutbound(
            server: 'trojan.example',
            serverPort: 443,
            password: 'pass',
            network: 'tcp',
            multiplex: MultiplexSettings(enabled: false),
            extraParams: {'custom_tag': 'tr1'},
          );
          const trojan2 = TrojanOutbound(
            server: 'trojan.example',
            serverPort: 443,
            password: 'pass',
            network: 'tcp',
            multiplex: MultiplexSettings(enabled: false),
            extraParams: {'custom_tag': 'tr1'},
          );
          const trojanDiff = TrojanOutbound(
            server: 'trojan.example',
            serverPort: 8443,
            password: 'pass',
          );

          expect(trojan1, equals(trojan2));
          expect(trojan1.hashCode, equals(trojan2.hashCode));
          expect(trojan1, isNot(equals(trojanDiff)));

          final json = trojan1.toJson();
          expect(json['network'], 'tcp');
          expect(json['multiplex'], isA<Map<String, dynamic>>());
          expect(json['custom_tag'], 'tr1');
        },
      );

      test(
        'ShadowsocksOutbound equality, hashCode, and optional fields in toJson',
        () {
          const ss1 = ShadowsocksOutbound(
            server: 'ss.example',
            serverPort: 8388,
            method: '2022-blake3-aes-128-gcm',
            password: 'secret',
            network: 'tcp',
            plugin: 'obfs-local',
            pluginOpts: 'obfs=http',
            udpOverTcp: true,
            multiplex: MultiplexSettings(enabled: true),
            extraParams: {'extra': 123},
          );
          const ss2 = ShadowsocksOutbound(
            server: 'ss.example',
            serverPort: 8388,
            method: '2022-blake3-aes-128-gcm',
            password: 'secret',
            network: 'tcp',
            plugin: 'obfs-local',
            pluginOpts: 'obfs=http',
            udpOverTcp: true,
            multiplex: MultiplexSettings(enabled: true),
            extraParams: {'extra': 123},
          );
          const ssDiff = ShadowsocksOutbound(
            server: 'ss.example',
            serverPort: 8388,
            method: 'aes-256-gcm',
            password: 'secret',
          );

          expect(ss1, equals(ss2));
          expect(ss1.hashCode, equals(ss2.hashCode));
          expect(ss1, isNot(equals(ssDiff)));

          final json = ss1.toJson();
          expect(json['network'], 'tcp');
          expect(json['multiplex'], isA<Map<String, dynamic>>());
          expect(json['extra'], 123);
        },
      );

      test(
        'Hysteria2Outbound equality, hashCode, and optional fields in toJson',
        () {
          final hy1 = Hysteria2Outbound(
            server: 'hy.example',
            serverPort: 443,
            tls: _quicTls,
            password: 'pass',
            upMbps: 100,
            downMbps: 500,
            serverPorts: ['443', '10000-20000'],
            obfsType: 'salamander',
            obfsPassword: 'obfs-secret',
            bbrProfile: 'balanced',
            quic: const QuicSettings(disablePathMtuDiscovery: true),
            extraParams: {'tag': 'hy-node'},
          );
          final hy2 = Hysteria2Outbound(
            server: 'hy.example',
            serverPort: 443,
            tls: _quicTls,
            password: 'pass',
            upMbps: 100,
            downMbps: 500,
            serverPorts: ['443', '10000-20000'],
            obfsType: 'salamander',
            obfsPassword: 'obfs-secret',
            bbrProfile: 'balanced',
            quic: const QuicSettings(disablePathMtuDiscovery: true),
            extraParams: {'tag': 'hy-node'},
          );
          final hyDiff = Hysteria2Outbound(
            server: 'hy.other',
            serverPort: 443,
            tls: _quicTls,
            password: 'pass',
          );

          expect(hy1, equals(hy2));
          expect(hy1.hashCode, equals(hy2.hashCode));
          expect(hy1, isNot(equals(hyDiff)));

          final json = hy1.toJson();
          expect(json['server_ports'], ['443', '10000-20000']);
          expect(json['bbr_profile'], 'balanced');
          expect(json['quic'], isA<Map<String, dynamic>>());
          expect(json['tag'], 'hy-node');
        },
      );

      test(
        'TuicOutbound equality, hashCode, and optional fields in toJson',
        () {
          final tuic1 = TuicOutbound(
            server: 'tuic.example',
            serverPort: 443,
            tls: _quicTls,
            uuid: 'uuid-tuic',
            password: 'pass',
            congestionControl: 'bbr',
            udpRelayMode: 'quic',
            udpOverStream: true,
            zeroRttHandshake: true,
            heartbeat: const Duration(seconds: 20),
            quic: const QuicSettings(disablePathMtuDiscovery: false),
            extraParams: {'custom': 'field'},
          );
          final tuic2 = TuicOutbound(
            server: 'tuic.example',
            serverPort: 443,
            tls: _quicTls,
            uuid: 'uuid-tuic',
            password: 'pass',
            congestionControl: 'bbr',
            udpRelayMode: 'quic',
            udpOverStream: true,
            zeroRttHandshake: true,
            heartbeat: const Duration(seconds: 20),
            quic: const QuicSettings(disablePathMtuDiscovery: false),
            extraParams: {'custom': 'field'},
          );
          final tuicDiff = TuicOutbound(
            server: 'tuic.example',
            serverPort: 443,
            tls: _quicTls,
            uuid: 'different-uuid',
            password: 'pass',
          );

          expect(tuic1, equals(tuic2));
          expect(tuic1.hashCode, equals(tuic2.hashCode));
          expect(tuic1, isNot(equals(tuicDiff)));

          final json = tuic1.toJson();
          expect(json['udp_relay_mode'], 'quic');
          expect(json['quic'], isA<Map<String, dynamic>>());
          expect(json['custom'], 'field');
        },
      );

      test('WireGuardOutbound optional fields serialization in toJson', () {
        final wg = WireGuardOutbound(
          server: 'wg.example',
          serverPort: 51820,
          localAddresses: ['10.0.0.2/32'],
          privateKey: 'privkey',
          peerPublicKey: 'pubkey',
          presharedKey: 'psk',
          reserved: [1, 2, 3],
          mtu: 1360,
          workers: 2,
          dnsServers: ['1.1.1.1'],
        );

        final json = wg.toJson();
        expect(json['pre_shared_key'], 'psk');
        expect(json['reserved'], [1, 2, 3]);
        expect(json['mtu'], 1360);
        expect(json['workers'], 2);
        expect(json['dns_servers'], ['1.1.1.1']);
      });

      test('extraParams map equality and hashCode branches', () {
        const out1 = VmessOutbound(
          server: 's.com',
          serverPort: 443,
          uuid: 'u',
          extraParams: {'a': '1', 'b': '2'},
        );
        const out2 = VmessOutbound(
          server: 's.com',
          serverPort: 443,
          uuid: 'u',
          extraParams: {'a': '1'},
        );
        const out3 = VmessOutbound(
          server: 's.com',
          serverPort: 443,
          uuid: 'u',
          extraParams: {'a': '1', 'b': '3'},
        );
        const out4 = VmessOutbound(
          server: 's.com',
          serverPort: 443,
          uuid: 'u',
          extraParams: {'a': '1', 'c': '2'},
        );

        expect(out1 == out2, isFalse);
        expect(out1 == out3, isFalse);
        expect(out1 == out4, isFalse);
      });

      test('Composition types equality and hashCode coverage', () {
        const reality1 = RealitySettings(
          enabled: true,
          publicKey: 'pk',
          shortId: 's1',
          spiderX: 'sp',
        );
        const reality2 = RealitySettings(
          enabled: true,
          publicKey: 'pk',
          shortId: 's1',
          spiderX: 'sp',
        );
        const realityDiff = RealitySettings(
          enabled: true,
          publicKey: 'pk',
          shortId: 's2',
          spiderX: 'sp',
        );
        expect(reality1, equals(reality2));
        expect(reality1.hashCode, equals(reality2.hashCode));
        expect(reality1, isNot(equals(realityDiff)));

        const fragment1 = TlsFragmentSettings(
          enabled: true,
          size: '10-20',
          sleep: '2-4',
        );
        const fragment2 = TlsFragmentSettings(
          enabled: true,
          size: '10-20',
          sleep: '2-4',
        );
        const fragmentDiff = TlsFragmentSettings(
          enabled: false,
          size: '10-20',
          sleep: '2-4',
        );
        expect(fragment1, equals(fragment2));
        expect(fragment1.hashCode, equals(fragment2.hashCode));
        expect(fragment1, isNot(equals(fragmentDiff)));

        const grpc1 = GrpcTransport(
          serviceName: 'svc',
          idleTimeout: Duration(seconds: 10),
          pingTimeout: Duration(seconds: 5),
          permitWithoutStream: true,
        );
        const grpc2 = GrpcTransport(
          serviceName: 'svc',
          idleTimeout: Duration(seconds: 10),
          pingTimeout: Duration(seconds: 5),
          permitWithoutStream: true,
        );
        const grpcDiff = GrpcTransport(serviceName: 'svc_other');
        expect(grpc1, equals(grpc2));
        expect(grpc1.hashCode, equals(grpc2.hashCode));
        expect(grpc1, isNot(equals(grpcDiff)));

        const quic1 = QuicSettings(
          disablePathMtuDiscovery: true,
          idleTimeout: Duration(seconds: 40),
          keepAlivePeriod: Duration(seconds: 20),
        );
        const quic2 = QuicSettings(
          disablePathMtuDiscovery: true,
          idleTimeout: Duration(seconds: 40),
          keepAlivePeriod: Duration(seconds: 20),
        );
        const quicDiff = QuicSettings(disablePathMtuDiscovery: false);
        expect(quic1, equals(quic2));
        expect(quic1.hashCode, equals(quic2.hashCode));
        expect(quic1, isNot(equals(quicDiff)));

        const mux1 = MultiplexSettings(
          enabled: true,
          protocol: 'smux',
          maxConnections: 8,
          minStreams: 2,
          maxStreams: 10,
          padding: true,
        );
        const mux2 = MultiplexSettings(
          enabled: true,
          protocol: 'smux',
          maxConnections: 8,
          minStreams: 2,
          maxStreams: 10,
          padding: true,
        );
        const muxDiff = MultiplexSettings(enabled: false, maxConnections: 4);
        expect(mux1, equals(mux2));
        expect(mux1.hashCode, equals(mux2.hashCode));
        expect(mux1, isNot(equals(muxDiff)));
      });

      test('ConnectionState hashCode and identity equality branches', () {
        const disconnected = Disconnected();
        const connecting = Connecting();
        const connected = Connected();
        const disconnecting = Disconnecting();
        const err1 = Error(InvalidConfig());
        const err2 = Error(InvalidConfig());

        expect(disconnected.hashCode, isA<int>());
        expect(connecting.hashCode, isA<int>());
        expect(connected.hashCode, isA<int>());
        expect(disconnecting.hashCode, isA<int>());
        expect(err1.hashCode, equals(err2.hashCode));
        expect(disconnected == disconnected, isTrue);
        expect(connecting == connecting, isTrue);
        expect(connected == connected, isTrue);
        expect(disconnecting == disconnecting, isTrue);
      });
    },
  );
}
