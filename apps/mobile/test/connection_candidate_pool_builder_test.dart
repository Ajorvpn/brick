// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/domain/services/connection_candidate_pool_builder.dart';

ServerProfile _vless(String id, String name, {int port = 443}) => ServerProfile(
  id: id,
  name: name,
  addedAt: DateTime.utc(2026, 11, 20),
  config: VlessOutbound(
    server: '$id.example.com',
    serverPort: port,
    uuid: '11111111-2222-3333-4444-555555555555',
    tls: TlsSettings(enabled: true),
  ),
);

ServerProfile _ss(String id, String name, {int port = 8388}) => ServerProfile(
  id: id,
  name: name,
  addedAt: DateTime.utc(2026, 11, 20),
  config: ShadowsocksOutbound(
    server: '$id.example.com',
    serverPort: port,
    method: '2022-blake3-aes-128-gcm',
    password: 'PLACEHOLDER-PASSWORD',
  ),
);

ServerProfile _trojan(String id, String name, {int port = 443}) =>
    ServerProfile(
      id: id,
      name: name,
      addedAt: DateTime.utc(2026, 11, 20),
      config: TrojanOutbound(
        server: '$id.example.com',
        serverPort: port,
        password: 'PLACEHOLDER-PASSWORD',
        tls: TlsSettings(enabled: true),
      ),
    );

ServerProfile _vmess(String id, String name, {int port = 443}) => ServerProfile(
  id: id,
  name: name,
  addedAt: DateTime.utc(2026, 11, 20),
  config: VmessOutbound(
    server: '$id.example.com',
    serverPort: port,
    uuid: '11111111-2222-3333-4444-555555555555',
    tls: TlsSettings(enabled: true),
  ),
);

ServerProfile _wg(String id, String name) => ServerProfile(
  id: id,
  name: name,
  addedAt: DateTime.utc(2026, 11, 20),
  config: WireGuardOutbound(
    server: '$id.example.com',
    serverPort: 51820,
    privateKey: 'PLACEHOLDER-PRIVATE-KEY',
    peerPublicKey: 'PLACEHOLDER-PUBLIC-KEY',
    localAddresses: const ['10.0.0.2/32'],
  ),
);

ServerProfile _awg(String id, String name) => ServerProfile(
  id: id,
  name: name,
  addedAt: DateTime.utc(2026, 11, 20),
  config: AmneziaWgOutbound(
    server: '$id.example.com',
    serverPort: 51820,
    privateKey: 'PLACEHOLDER-PRIVATE-KEY',
    peerPublicKey: 'PLACEHOLDER-PUBLIC-KEY',
    localAddresses: const ['10.0.0.2/32'],
    jc: 4,
    h1: 100,
  ),
);

void main() {
  group('ConnectionCandidatePoolBuilder', () {
    test(
      'returns empty list when primary is AmneziaWgOutbound or limit <= 0',
      () {
        final awgPrimary = _awg('awg-p', '🇩🇪 Germany AWG');
        final deVless = _vless('de-v', '🇩🇪 Germany VLESS');

        expect(
          ConnectionCandidatePoolBuilder.buildCandidatePool(
            primary: awgPrimary,
            allServers: [awgPrimary, deVless],
          ),
          isEmpty,
        );
        expect(
          ConnectionCandidatePoolBuilder.buildCandidatePool(
            primary: deVless,
            allServers: [deVless],
            maxCandidates: 0,
          ),
          isEmpty,
        );
      },
    );

    test(
      'keeps primary first, deduplicates by ID, excludes AmneziaWG, and caps '
      'at maxCandidates',
      () {
        final primary = _ss('de-01', '🇩🇪 Germany 01 | SS');
        final duplicate = _ss('de-01', '🇩🇪 Germany 01 Duplicate | SS');
        final awg = _awg('awg-1', '🇩🇪 Germany AWG');
        final others = <ServerProfile>[
          _vless('de-02', '🇩🇪 Germany 02 | VLESS'),
          _trojan('uk-01', '🇬🇧 United Kingdom 01 | TROJAN'),
          _vmess('us-01', '🇺🇸 United States 01 | VMESS'),
          _wg('nl-01', '🇳🇱 Netherlands 01 | WG'),
          _vless('fr-01', '🇫🇷 France 01 | VLESS'),
          _ss('fi-01', '🇫🇮 Finland 01 | SS'),
          _trojan('ca-01', '🇨🇦 Canada 01 | TROJAN'),
          _vmess('sg-01', '🇸🇬 Singapore 01 | VMESS'),
          _vless('jp-01', '🇯🇵 Japan 01 | VLESS'),
          _ss('au-01', '🇦🇺 Australia 01 | SS'),
        ];

        final pool = ConnectionCandidatePoolBuilder.buildCandidatePool(
          primary: primary,
          allServers: [duplicate, awg, primary, ...others],
        );

        expect(pool, hasLength(10));
        expect(pool.first.id, equals('de-01'));
        expect(pool.map((p) => p.id).toSet(), hasLength(10));
        expect(pool.any((p) => p.config is AmneziaWgOutbound), isFalse);
      },
    );

    test(
      'global mode picks up to 2 diverse-protocol siblings in primary country '
      'before cross-country round-robin',
      () {
        final primary = _ss('de-ss-1', '🇩🇪 Germany 01 | SS');
        final all = <ServerProfile>[
          primary,
          _ss('de-ss-2', '🇩🇪 Germany 02 | SS'),
          _vless('de-vless-1', '🇩🇪 Germany 03 | VLESS'),
          _trojan('de-trojan-1', '🇩🇪 Germany 04 | TROJAN'),
          _vmess('uk-vmess-1', '🇬🇧 United Kingdom 01 | VMESS'),
          _vless('uk-vless-1', '🇬🇧 United Kingdom 02 | VLESS'),
          _wg('us-wg-1', '🇺🇸 United States 01 | WG'),
          _trojan('nl-trojan-1', '🇳🇱 Netherlands 01 | TROJAN'),
        ];

        final pool = ConnectionCandidatePoolBuilder.buildCandidatePool(
          primary: primary,
          allServers: all,
        );

        expect(pool, hasLength(8));
        expect(pool[0].id, equals('de-ss-1'));
        // Next two slots are diverse-protocol siblings in Germany.
        expect(pool[1].id, equals('de-vless-1'));
        expect(pool[2].id, equals('de-trojan-1'));
        // Then round-robin UK, US, NL with diverse protocols, then de-ss-2.
        expect(
          pool.sublist(3, 6).map((p) => p.id),
          containsAll(['us-wg-1', 'nl-trojan-1']),
        );
        expect(pool[3].id.startsWith('uk-'), isTrue);
        expect(pool[4].id, equals('us-wg-1'));
        expect(pool[5].id, equals('nl-trojan-1'));
        expect(pool.last.id, equals('de-ss-2'));
      },
    );

    test(
      'global mode still tops up small single-country list beyond 3 entries',
      () {
        final primary = _vless('de-1', '🇩🇪 Germany 01 | VLESS');
        final all = <ServerProfile>[
          primary,
          _vless('de-2', '🇩🇪 Germany 02 | VLESS'),
          _vless('de-3', '🇩🇪 Germany 03 | VLESS'),
          _vless('de-4', '🇩🇪 Germany 04 | VLESS'),
          _vless('de-5', '🇩🇪 Germany 05 | VLESS'),
        ];

        final pool = ConnectionCandidatePoolBuilder.buildCandidatePool(
          primary: primary,
          allServers: all,
        );

        expect(
          pool.map((p) => p.id),
          equals(['de-1', 'de-2', 'de-3', 'de-4', 'de-5']),
        );
      },
    );

    test('restrictToCountryCode limits pool to target country and rotates '
        'non-primary protocols first', () {
      final primary = _ss('de-ss-1', '🇩🇪 Germany 01 | SS');
      final all = <ServerProfile>[
        primary,
        _ss('de-ss-2', '🇩🇪 Germany 02 | SS'),
        _vless('de-vless-1', '🇩🇪 Germany 03 | VLESS'),
        _vless('de-vless-2', '🇩🇪 Germany 04 | VLESS'),
        _trojan('de-trojan-1', '🇩🇪 Germany 05 | TROJAN'),
        _vless('uk-vless-1', '🇬🇧 United Kingdom 01 | VLESS'),
        _vmess('us-vmess-1', '🇺🇸 United States 01 | VMESS'),
      ];

      final pool = ConnectionCandidatePoolBuilder.buildCandidatePool(
        primary: primary,
        allServers: all,
        restrictToCountryCode: ' de ',
      );

      expect(
        pool.map((p) => p.id),
        equals([
          'de-ss-1',
          'de-vless-1',
          'de-trojan-1',
          'de-ss-2',
          'de-vless-2',
        ]),
      );
    });
  });
}
