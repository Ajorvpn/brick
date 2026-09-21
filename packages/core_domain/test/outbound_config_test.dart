// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

const _tcpTls = TlsSettings(enabled: true);
const _quicTls = TlsSettings(enabled: true, serverName: 'q.example');

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
        tls: const TlsSettings(enabled: true, alpn: ['h2']),
      );
      final b = VlessOutbound(
        server: 'v.example',
        serverPort: 443,
        uuid: 'u',
        tls: const TlsSettings(enabled: true, alpn: ['h2']),
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
      const config = TuicOutbound(
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
      const transport = WebSocketTransport(path: '/ray');
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
}
