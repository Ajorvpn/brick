// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

WireGuardOutbound _wg({
  List<String>? addresses,
  List<int>? reserved,
  List<String>? dns,
  int? mtu,
  int? workers,
  String? presharedKey,
}) => WireGuardOutbound(
  server: 'vpn.example.com',
  serverPort: 51820,
  privateKey: 'cHJpdmF0ZS1rZXktZm9yLXRlc3Rpbmctb25seS0zMmJ5dGVzIQ==',
  peerPublicKey: 'cHVibGljLWtleS1mb3ItdGVzdGluZy1vbmx5LTMyYnl0ZXMh',
  localAddresses: addresses ?? <String>['10.0.0.2/32'],
  reserved: reserved,
  dnsServers: dns,
  mtu: mtu,
  workers: workers,
  presharedKey: presharedKey,
);

void main() {
  group('WireGuardOutbound', () {
    test('carries the mandatory and optional fields', () {
      final outbound = _wg(reserved: <int>[1, 2, 3], mtu: 1420, workers: 2);
      expect(outbound.protocol, ProtocolType.wireguard);
      expect(outbound.server, 'vpn.example.com');
      expect(outbound.serverPort, 51820);
      expect(outbound.localAddresses, <String>['10.0.0.2/32']);
      expect(outbound.reserved, <int>[1, 2, 3]);
      expect(outbound.mtu, 1420);
      expect(outbound.workers, 2);
      expect(outbound.tls, isNull);
    });

    test('has value equality including the list fields', () {
      expect(_wg(), _wg());
      expect(_wg().hashCode, _wg().hashCode);
      expect(_wg(reserved: <int>[1, 2]), isNot(_wg(reserved: <int>[3, 4])));
    });

    test('DEFENSIVE COPY: localAddresses is unmodifiable', () {
      final source = <String>['10.0.0.2/32'];
      final outbound = _wg(addresses: source);
      // Mutating the caller's list must not change the domain object.
      source.add('10.0.0.3/32');
      expect(outbound.localAddresses, <String>['10.0.0.2/32']);
      expect(
        () => outbound.localAddresses.add('10.0.0.9/32'),
        throwsUnsupportedError,
      );
    });

    test('DEFENSIVE COPY: reserved and dnsServers are unmodifiable', () {
      final reserved = <int>[1, 2, 3];
      final dns = <String>['1.1.1.1'];
      final outbound = _wg(reserved: reserved, dns: dns);

      reserved.add(9);
      dns.add('8.8.8.8');
      expect(outbound.reserved, <int>[1, 2, 3]);
      expect(outbound.dnsServers, <String>['1.1.1.1']);
      expect(() => outbound.reserved!.add(4), throwsUnsupportedError);
      expect(() => outbound.dnsServers!.add('9.9.9.9'), throwsUnsupportedError);
    });

    test('toJson emits the sing-box field names', () {
      final json = _wg(reserved: <int>[0, 0, 0], mtu: 1408).toJson();
      expect(json['type'], 'wireguard');
      expect(json['server'], 'vpn.example.com');
      expect(json['server_port'], 51820);
      expect(json['local_address'], <String>['10.0.0.2/32']);
      expect(json['private_key'], isA<String>());
      expect(json['peer_public_key'], isA<String>());
      expect(json['reserved'], <int>[0, 0, 0]);
      expect(json['mtu'], 1408);
    });

    test('omits absent optional keys rather than emitting null', () {
      final json = _wg().toJson();
      expect(json.containsKey('pre_shared_key'), isFalse);
      expect(json.containsKey('reserved'), isFalse);
      expect(json.containsKey('mtu'), isFalse);
      expect(json.containsKey('workers'), isFalse);
    });

    test('has no toString override that could leak the private key', () {
      // SECURITY.md: domain value types must not stringify credentials.
      expect(_wg().toString(), isNot(contains('cHJpdmF0ZS1rZXk')));
    });
  });

  group('AmneziaWgOutbound', () {
    AmneziaWgOutbound _awg() => AmneziaWgOutbound(
      server: 'vpn.example.com',
      serverPort: 51820,
      privateKey: 'cHJpdmF0ZS1rZXktZm9yLXRlc3Rpbmctb25seS0zMmJ5dGVzIQ==',
      peerPublicKey: 'cHVibGljLWtleS1mb3ItdGVzdGluZy1vbmx5LTMyYnl0ZXMh',
      localAddresses: const <String>['10.0.0.2/32'],
      jc: 4,
      jmin: 50,
      jmax: 1000,
      s1: 15,
      s2: 40,
      h1: 1234,
      h2: 5678,
      h3: 9012,
      h4: 3456,
    );

    test('extends WireGuardOutbound and reports its own protocol', () {
      final outbound = _awg();
      expect(outbound, isA<WireGuardOutbound>());
      expect(outbound.protocol, ProtocolType.amneziawg);
    });

    test('carries all nine obfuscation parameters', () {
      final outbound = _awg();
      expect(outbound.jc, 4);
      expect(outbound.jmin, 50);
      expect(outbound.jmax, 1000);
      expect(outbound.s1, 15);
      expect(outbound.s2, 40);
      expect(outbound.h1, 1234);
      expect(outbound.h2, 5678);
      expect(outbound.h3, 9012);
      expect(outbound.h4, 3456);
      expect(outbound.obfuscationParams, hasLength(9));
    });

    test('omits obfuscation params that were not set', () {
      final minimal = AmneziaWgOutbound(
        server: 'e.com',
        serverPort: 1,
        privateKey: 'a',
        peerPublicKey: 'b',
        localAddresses: const <String>['10.0.0.2/32'],
        jc: 3,
      );
      expect(minimal.obfuscationParams, <String, int>{'jc': 3});
    });

    test(
      'toJson namespaces the obfuscation block (sing-box has no such key)',
      () {
        final json = _awg().toJson();
        // The WireGuard envelope is still emitted...
        expect(json['type'], 'amneziawg');
        expect(json['local_address'], <String>['10.0.0.2/32']);
        // ...and obfuscation is namespaced rather than invented at top level,
        // because the sing-box WireGuard schema rejects unknown top-level keys.
        final obfuscation = json['amneziawg_obfuscation'] as Map<String, int>;
        expect(obfuscation['jc'], 4);
        expect(obfuscation['h4'], 3456);
        expect(json.containsKey('jc'), isFalse);
      },
    );
  });

  group('Hysteria2Outbound safety', () {
    test('throws ArgumentError (not an assert) on a half-configured obfs', () {
      // Dart strips asserts from release builds, so this must be a real
      // runtime throw to be effective in production.
      expect(
        () => Hysteria2Outbound(
          server: 'e.com',
          serverPort: 443,
          password: 'pw',
          tls: TlsSettings(enabled: true),
          obfsType: 'salamander',
        ),
        throwsArgumentError,
      );
    });

    test('accepts a fully configured or fully absent obfs block', () {
      expect(
        Hysteria2Outbound(
          server: 'e.com',
          serverPort: 443,
          password: 'pw',
          tls: TlsSettings(enabled: true),
          obfsType: 'salamander',
          obfsPassword: 'obfspw',
        ).obfsType,
        'salamander',
      );
      expect(
        Hysteria2Outbound(
          server: 'e.com',
          serverPort: 443,
          password: 'pw',
          tls: TlsSettings(enabled: true),
        ).obfsType,
        isNull,
      );
    });
  });
}
