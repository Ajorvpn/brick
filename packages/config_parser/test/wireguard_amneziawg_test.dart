// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

/// 32-byte keys, base64-encoded, as WireGuard requires.
final _privKey = base64.encode(List<int>.generate(32, (i) => i));
final _pubKey = base64.encode(List<int>.generate(32, (i) => 255 - i));
final _psk = base64.encode(List<int>.generate(32, (i) => (i * 7) % 256));

String _wgUri({
  String scheme = 'wireguard',
  Map<String, String> query = const {},
  String? remark = 'WG',
  String? userInfo,
}) {
  final q = query.entries.isEmpty
      ? ''
      : '?${query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  return '$scheme://${userInfo ?? _privKey}@vpn.example.com:51820$q#${remark ?? 'WG'}';
}

void main() {
  group('WireGuard URI parsing', () {
    test('parses a minimal link', () {
      final result = parseWireguardUri(
        _wgUri(query: {'peer_public_key': _pubKey, 'ip': '10.0.0.2/32'}),
      );
      expect(result.isOk, isTrue);
      final wg =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as WireGuardOutbound;
      expect(wg.protocol, ProtocolType.wireguard);
      expect(wg.server, 'vpn.example.com');
      expect(wg.serverPort, 51820);
      expect(wg.privateKey, _privKey);
      expect(wg.peerPublicKey, _pubKey);
      expect(wg.localAddresses, <String>['10.0.0.2/32']);
    });

    test('accepts the wg:// short scheme identically', () {
      final long = parseWireguardUri(
        _wgUri(query: {'peer_public_key': _pubKey, 'ip': '10.0.0.2/32'}),
      );
      final short = parseWireguardUri(
        _wgUri(
          scheme: 'wg',
          query: {'peer_public_key': _pubKey, 'ip': '10.0.0.2/32'},
        ),
      );
      expect(long.isOk, isTrue);
      expect(short.isOk, isTrue);
      expect(
        (long as Ok<OutboundConfig, ConfigParseError>).value,
        (short as Ok<OutboundConfig, ConfigParseError>).value,
      );
    });

    test('parses every optional parameter', () {
      final result = parseWireguardUri(
        _wgUri(
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32,fd00::2/128',
            'preshared_key': _psk,
            'reserved': '1,2,3',
            'mtu': '1420',
            'workers': '4',
            'dns': '1.1.1.1,9.9.9.9',
          },
        ),
      );
      final wg =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as WireGuardOutbound;
      expect(wg.localAddresses, <String>['10.0.0.2/32', 'fd00::2/128']);
      expect(wg.presharedKey, _psk);
      expect(wg.reserved, <int>[1, 2, 3]);
      expect(wg.mtu, 1420);
      expect(wg.workers, 4);
      expect(wg.dnsServers, <String>['1.1.1.1', '9.9.9.9']);
    });

    test('accepts public_key as an alias for peer_public_key', () {
      final result = parseWireguardUri(
        _wgUri(query: {'public_key': _pubKey, 'ip': '10.0.0.2/32'}),
      );
      expect(result.isOk, isTrue);
    });

    test('rejects a missing private key', () {
      final result = parseWireguardUri(
        'wireguard://vpn.example.com:51820?peer_public_key=$_pubKey&ip=10.0.0.2/32',
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>(),
      );
    });

    test('rejects a missing peer public key', () {
      final result = parseWireguardUri(_wgUri(query: {'ip': '10.0.0.2/32'}));
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>().having(
          (e) => e.field,
          'field',
          'peer_public_key',
        ),
      );
    });

    test('rejects a missing ip/address', () {
      final result = parseWireguardUri(
        _wgUri(query: {'peer_public_key': _pubKey}),
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<MissingRequiredFieldError>().having((e) => e.field, 'field', 'ip'),
      );
    });

    test('rejects a key that is not 32 bytes', () {
      final shortKey = base64.encode(List<int>.filled(16, 1));
      final result = parseWireguardUri(
        _wgUri(
          query: {'peer_public_key': _pubKey, 'ip': '10.0.0.2/32'},
          userInfo: shortKey,
        ),
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<CorruptedBase64Error>(),
      );
    });

    test('rejects an out-of-range port', () {
      final result = parseWireguardUri(
        'wireguard://$_privKey@vpn.example.com:99999?peer_public_key=$_pubKey&ip=10.0.0.2/32',
      );
      expect(result.isErr, isTrue);
    });

    test('rejects a bad reserved byte', () {
      final result = parseWireguardUri(
        _wgUri(
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32',
            'reserved': '1,999',
          },
        ),
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidFieldValueError>().having(
          (e) => e.field,
          'field',
          'reserved',
        ),
      );
    });

    test('SECURITY: errors never echo the private key', () {
      final result = parseWireguardUri(
        _wgUri(
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32',
            'reserved': '1,999',
          },
        ),
      );
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(_privKey), isFalse);
    });

    test('SECURITY: errors never echo the pre-shared key', () {
      final result = parseWireguardUri(
        _wgUri(
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32',
            'preshared_key': base64.encode(List<int>.filled(8, 3)),
            'mtu': 'notanumber',
          },
        ),
      );
      expect(result.isErr, isTrue);
      final error = (result as Err<OutboundConfig, ConfigParseError>).error;
      expect(error.message.contains(_psk), isFalse);
    });
  });

  group('AmneziaWG URI parsing', () {
    test('parses all nine obfuscation parameters', () {
      final result = parseAmneziaWgUri(
        _wgUri(
          scheme: 'amneziawg',
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32',
            'jc': '4',
            'jmin': '50',
            'jmax': '1000',
            's1': '15',
            's2': '40',
            'h1': '1234',
            'h2': '5678',
            'h3': '9012',
            'h4': '3456',
          },
        ),
      );
      expect(result.isOk, isTrue);
      final awg =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as AmneziaWgOutbound;
      expect(awg.protocol, ProtocolType.amneziawg);
      expect(awg.obfuscationParams, {
        'jc': 4,
        'jmin': 50,
        'jmax': 1000,
        's1': 15,
        's2': 40,
        'h1': 1234,
        'h2': 5678,
        'h3': 9012,
        'h4': 3456,
      });
    });

    test('accepts the awg:// short scheme', () {
      final result = parseAmneziaWgUri(
        _wgUri(
          scheme: 'awg',
          query: {'peer_public_key': _pubKey, 'ip': '10.0.0.2/32'},
        ),
      );
      expect(result.isOk, isTrue);
    });

    test('rejects an out-of-range obfuscation value', () {
      final result = parseAmneziaWgUri(
        _wgUri(
          scheme: 'amneziawg',
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32',
            'jc': '99999',
          },
        ),
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<OutboundConfig, ConfigParseError>).error,
        isA<InvalidFieldValueError>().having((e) => e.field, 'field', 'jc'),
      );
    });

    test('rejects a non-numeric obfuscation value', () {
      final result = parseAmneziaWgUri(
        _wgUri(
          scheme: 'amneziawg',
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32',
            'h1': 'notanumber',
          },
        ),
      );
      expect(result.isErr, isTrue);
    });
  });

  group('Sing-Box serialization', () {
    test('WireGuard emits the documented 1.10/1.11 schema', () {
      final parsed = parseWireguardUri(
        _wgUri(
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32',
            'preshared_key': _psk,
            'reserved': '1,2,3',
            'mtu': '1408',
            'workers': '2',
          },
        ),
      );
      final config = (parsed as Ok<OutboundConfig, ConfigParseError>).value;
      final json = buildSingBoxOutbound(config, tag: 'wg-out');

      expect(json['type'], 'wireguard');
      expect(json['tag'], 'wg-out');
      expect(json['server'], 'vpn.example.com');
      expect(json['server_port'], 51820);
      expect(json['system_interface'], false);
      expect(json['local_address'], <String>['10.0.0.2/32']);
      expect(json['private_key'], _privKey);
      expect(json['peer_public_key'], _pubKey);
      expect(json['pre_shared_key'], _psk);
      expect(json['reserved'], <int>[1, 2, 3]);
      expect(json['mtu'], 1408);
      expect(json['workers'], 2);
      // WireGuard has no TLS/transport in the sing-box schema.
      expect(json.containsKey('tls'), isFalse);
    });

    test('AmneziaWG serializes as wireguard WITHOUT invented keys', () {
      final parsed = parseAmneziaWgUri(
        _wgUri(
          scheme: 'amneziawg',
          query: {
            'peer_public_key': _pubKey,
            'ip': '10.0.0.2/32',
            'jc': '4',
            'h4': '3456',
          },
        ),
      );
      final config = (parsed as Ok<OutboundConfig, ConfigParseError>).value;
      final json = buildSingBoxOutbound(config);

      // It is a WireGuard tunnel on the wire...
      expect(json['type'], 'wireguard');
      expect(json['system_interface'], false);
      // ...and the obfuscation params are NOT emitted as top-level
      // sing-box keys, because sing-box has no such schema and rejects
      // unknown keys. They are preserved on the domain object instead.
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
          json.containsKey(key),
          isFalse,
          reason: '$key must not be invented',
        );
      }
      final awg = config as AmneziaWgOutbound;
      expect(awg.obfuscationParams['jc'], 4);
    });

    test('every domain protocol still serializes', () {
      final configs = <OutboundConfig>[
        const VlessOutbound(
          server: 'a.com',
          serverPort: 443,
          uuid: 'b831381d-6324-4d53-ad4f-8cda48b30811',
        ),
        const VmessOutbound(
          server: 'b.com',
          serverPort: 443,
          uuid: 'b831381d-6324-4d53-ad4f-8cda48b30811',
        ),
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
          uuid: 'b831381d-6324-4d53-ad4f-8cda48b30811',
          password: 'p',
          tls: TlsSettings(enabled: true),
        ),
        WireGuardOutbound(
          server: 'g.com',
          serverPort: 51820,
          privateKey: _privKey,
          peerPublicKey: _pubKey,
          localAddresses: const <String>['10.0.0.2/32'],
        ),
      ];
      for (final config in configs) {
        expect(
          const SingBoxOutboundSerializer().tryBuild(config).isOk,
          isTrue,
          reason: '${config.protocol} must serialize',
        );
      }
    });
  });

  group('unified router', () {
    test('routes wireguard/wg/amneziawg/awg', () {
      final wgQuery = {'peer_public_key': _pubKey, 'ip': '10.0.0.2/32'};
      expect(parseUri(_wgUri(query: wgQuery)).isOk, isTrue);
      expect(parseUri(_wgUri(scheme: 'wg', query: wgQuery)).isOk, isTrue);
      expect(
        parseUri(_wgUri(scheme: 'amneziawg', query: wgQuery)).isOk,
        isTrue,
      );
      expect(parseUri(_wgUri(scheme: 'awg', query: wgQuery)).isOk, isTrue);
    });

    test('routes each scheme to the right protocol', () {
      final wgQuery = {'peer_public_key': _pubKey, 'ip': '10.0.0.2/32'};
      expect(
        (parseUri(
          _wgUri(query: wgQuery),
        ) as Ok<OutboundConfig, ConfigParseError>).value.protocol,
        ProtocolType.wireguard,
      );
      expect(
        (parseUri(
          _wgUri(scheme: 'awg', query: wgQuery),
        ) as Ok<OutboundConfig, ConfigParseError>).value.protocol,
        ProtocolType.amneziawg,
      );
    });

    test('parses remarks for the new schemes', () {
      final wgQuery = {'peer_public_key': _pubKey, 'ip': '10.0.0.2/32'};
      expect(
        parseUriRemark(_wgUri(remark: 'My%20WG', query: wgQuery)),
        'My WG',
      );
      expect(
        parseUriRemark(
          _wgUri(scheme: 'awg', remark: 'My%20AWG', query: wgQuery),
        ),
        'My AWG',
      );
    });
  });
}
