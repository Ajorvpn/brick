// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

const _reality = RealitySettings(enabled: true, publicKey: 'pk', shortId: '01');
const _utls = UtlsSettings(enabled: true, fingerprint: 'chrome');
const _fragment = TlsFragmentSettings(enabled: true, size: '10-30');

/// Fully-populated TLS block reused by equality and serialization tests.
const _tlsFull = TlsSettings(
  enabled: true,
  serverName: 'example.com',
  alpn: ['h2', 'http/1.1'],
  utls: _utls,
  reality: _reality,
  fragment: _fragment,
);

/// Exhaustively maps every transport to a label.
///
/// Why a switch with no `default`: adding a fifth transport must break this
/// function at compile time until it is handled — the same sealed-hierarchy
/// guarantee the domain relies on.
String transportLabel(TransportSettings transport) => switch (transport) {
  WebSocketTransport() => 'ws',
  GrpcTransport() => 'grpc',
  HttpTransport() => 'http',
  HttpUpgradeTransport() => 'httpupgrade',
};

void main() {
  group('RealitySettings', () {
    test('should be value-equal to an identical copy and share hashCode', () {
      const other = RealitySettings(
        enabled: true,
        publicKey: 'pk',
        shortId: '01',
      );
      expect(_reality, other);
      expect(_reality.hashCode, other.hashCode);
    });

    test('should not be equal when the public key differs', () {
      const other = RealitySettings(
        enabled: true,
        publicKey: 'other',
        shortId: '01',
      );
      expect(_reality, isNot(other));
    });

    test('should serialize snake_case keys and omit a null spiderX', () {
      expect(_reality.toJson(), {
        'enabled': true,
        'public_key': 'pk',
        'short_id': '01',
      });
    });

    test('should include spider_x in toJson when set', () {
      const withSpider = RealitySettings(
        enabled: true,
        publicKey: 'pk',
        shortId: '01',
        spiderX: '/',
      );
      expect(withSpider.toJson()['spider_x'], '/');
    });
  });

  group('UtlsSettings', () {
    test('should be value-equal and share hashCode', () {
      const other = UtlsSettings(enabled: true, fingerprint: 'chrome');
      expect(_utls, other);
      expect(_utls.hashCode, other.hashCode);
    });

    test('should not be equal when the fingerprint differs', () {
      const other = UtlsSettings(enabled: true, fingerprint: 'firefox');
      expect(_utls, isNot(other));
    });

    test('should serialize both fields', () {
      expect(_utls.toJson(), {'enabled': true, 'fingerprint': 'chrome'});
    });
  });

  group('TlsFragmentSettings', () {
    test('should be value-equal and share hashCode', () {
      const other = TlsFragmentSettings(enabled: true, size: '10-30');
      expect(_fragment, other);
      expect(_fragment.hashCode, other.hashCode);
    });

    test('should omit null size and sleep from toJson', () {
      expect(_fragment.toJson(), {'enabled': true, 'size': '10-30'});
    });

    test('should include size and sleep when set', () {
      const full = TlsFragmentSettings(
        enabled: true,
        size: '10-30',
        sleep: '5-10ms',
      );
      expect(full.toJson(), {
        'enabled': true,
        'size': '10-30',
        'sleep': '5-10ms',
      });
    });
  });

  group('TlsSettings', () {
    test('should be value-equal including structurally-equal alpn lists', () {
      const other = TlsSettings(
        enabled: true,
        serverName: 'example.com',
        alpn: ['h2', 'http/1.1'],
        utls: _utls,
        reality: _reality,
        fragment: _fragment,
      );
      const original = TlsSettings(
        enabled: true,
        serverName: 'example.com',
        alpn: ['h2', 'http/1.1'],
        utls: _utls,
        reality: _reality,
        fragment: _fragment,
      );
      expect(original, other);
      expect(original.hashCode, other.hashCode);
    });

    test('should not be equal when alpn lists differ', () {
      const other = TlsSettings(enabled: true, alpn: ['h3']);
      expect(const TlsSettings(enabled: true, alpn: ['h2']), isNot(other));
    });

    test('should default insecure to false', () {
      expect(const TlsSettings(enabled: true).insecure, isFalse);
    });

    test('should serialize nested blocks with snake_case keys', () {
      expect(_tlsFull.toJson(), {
        'enabled': true,
        'server_name': 'example.com',
        'insecure': false,
        'alpn': ['h2', 'http/1.1'],
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
        'reality': {'enabled': true, 'public_key': 'pk', 'short_id': '01'},
        'fragment': {'enabled': true, 'size': '10-30'},
      });
    });

    test('should omit every null optional field when minimal', () {
      expect(const TlsSettings(enabled: true).toJson(), {
        'enabled': true,
        'insecure': false,
      });
    });
  });

  group('TransportSettings exhaustiveness', () {
    test('should switch over all four transports without a default clause', () {
      expect(transportLabel(const WebSocketTransport(path: '/')), 'ws');
      expect(transportLabel(const GrpcTransport(serviceName: 'g')), 'grpc');
      expect(transportLabel(const HttpTransport()), 'http');
      expect(transportLabel(const HttpUpgradeTransport()), 'httpupgrade');
    });

    test('transports of different subtypes are never equal', () {
      expect(
        const WebSocketTransport(path: '/'),
        isNot(const GrpcTransport(serviceName: 'g')),
      );
      expect(
        transportLabel(const WebSocketTransport(path: '/')),
        isNot(transportLabel(const HttpUpgradeTransport())),
      );
    });
  });

  group('WebSocketTransport', () {
    test('should be value-equal including structurally-equal header maps', () {
      const other = WebSocketTransport(
        path: '/ray',
        headers: {'Host': 'example.com'},
        maxEarlyData: 2048,
        earlyDataHeaderName: 'sec-websocket-protocol',
      );
      const original = WebSocketTransport(
        path: '/ray',
        headers: {'Host': 'example.com'},
        maxEarlyData: 2048,
        earlyDataHeaderName: 'sec-websocket-protocol',
      );
      expect(original, other);
      expect(original.hashCode, other.hashCode);
    });

    test('should serialize snake_case keys under the ws discriminator', () {
      const transport = WebSocketTransport(
        path: '/ray',
        headers: {'Host': 'example.com'},
        maxEarlyData: 2048,
        earlyDataHeaderName: 'sec-websocket-protocol',
      );
      expect(transport.toJson(), {
        'type': 'ws',
        'path': '/ray',
        'headers': {'Host': 'example.com'},
        'max_early_data': 2048,
        'early_data_header_name': 'sec-websocket-protocol',
      });
    });
  });

  group('GrpcTransport', () {
    test('should default permitWithoutStream to false', () {
      expect(
        const GrpcTransport(serviceName: 'g').permitWithoutStream,
        isFalse,
      );
    });

    test('should serialize durations as integer microseconds', () {
      const transport = GrpcTransport(
        serviceName: 'GunService',
        idleTimeout: Duration(seconds: 30),
        pingTimeout: Duration(seconds: 10),
      );
      expect(transport.toJson(), {
        'type': 'grpc',
        'service_name': 'GunService',
        'idle_timeout': 30000000,
        'ping_timeout': 10000000,
        'permit_without_stream': false,
      });
    });

    test('should be value-equal and share hashCode', () {
      const other = GrpcTransport(serviceName: 'g');
      expect(const GrpcTransport(serviceName: 'g'), other);
      expect(const GrpcTransport(serviceName: 'g').hashCode, other.hashCode);
    });
  });

  group('HttpTransport', () {
    test('should be value-equal including host lists and header maps', () {
      const other = HttpTransport(
        host: ['example.com'],
        path: '/h2',
        method: 'GET',
        headers: {'Host': 'example.com'},
      );
      const original = HttpTransport(
        host: ['example.com'],
        path: '/h2',
        method: 'GET',
        headers: {'Host': 'example.com'},
      );
      expect(original, other);
      expect(original.hashCode, other.hashCode);
    });

    test('should serialize snake_case keys under the http discriminator', () {
      const transport = HttpTransport(
        host: ['example.com'],
        path: '/h2',
        method: 'GET',
      );
      expect(transport.toJson(), {
        'type': 'http',
        'host': ['example.com'],
        'path': '/h2',
        'method': 'GET',
      });
    });
  });

  group('HttpUpgradeTransport', () {
    test('should be value-equal and serialize with its own discriminator', () {
      const other = HttpUpgradeTransport(
        host: 'example.com',
        path: '/up',
        headers: {'Host': 'example.com'},
      );
      const original = HttpUpgradeTransport(
        host: 'example.com',
        path: '/up',
        headers: {'Host': 'example.com'},
      );
      expect(original, other);
      expect(original.hashCode, other.hashCode);
      expect(original.toJson(), {
        'type': 'httpupgrade',
        'host': 'example.com',
        'path': '/up',
        'headers': {'Host': 'example.com'},
      });
    });
  });

  group('QuicSettings', () {
    test('should default disablePathMtuDiscovery to false', () {
      expect(const QuicSettings().disablePathMtuDiscovery, isFalse);
    });

    test('should serialize durations as integer microseconds', () {
      const settings = QuicSettings(
        initialPacketSize: 1200,
        idleTimeout: Duration(seconds: 30),
        keepAlivePeriod: Duration(seconds: 15),
      );
      expect(settings.toJson(), {
        'initial_packet_size': 1200,
        'disable_path_mtu_discovery': false,
        'idle_timeout': 30000000,
        'keep_alive_period': 15000000,
      });
    });

    test('should be value-equal and share hashCode', () {
      const other = QuicSettings(initialPacketSize: 1200);
      expect(const QuicSettings(initialPacketSize: 1200), other);
      expect(
        const QuicSettings(initialPacketSize: 1200).hashCode,
        other.hashCode,
      );
      expect(const QuicSettings(), isNot(other));
    });
  });

  group('MultiplexSettings', () {
    test('should serialize all fields with snake_case keys', () {
      const settings = MultiplexSettings(
        enabled: true,
        protocol: 'smux',
        maxConnections: 4,
        minStreams: 4,
        maxStreams: 8,
        padding: true,
      );
      expect(settings.toJson(), {
        'enabled': true,
        'protocol': 'smux',
        'max_connections': 4,
        'min_streams': 4,
        'max_streams': 8,
        'padding': true,
      });
    });

    test('should be value-equal and share hashCode', () {
      const other = MultiplexSettings(enabled: true, protocol: 'smux');
      expect(const MultiplexSettings(enabled: true, protocol: 'smux'), other);
      expect(
        const MultiplexSettings(enabled: true, protocol: 'smux').hashCode,
        other.hashCode,
      );
      expect(
        const MultiplexSettings(enabled: true, protocol: 'yamux'),
        isNot(other),
      );
    });
  });
}
