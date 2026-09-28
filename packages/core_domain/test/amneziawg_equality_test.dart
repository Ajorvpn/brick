// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

/// Obvious, non-secret placeholders. No real key material is used or printed.
const _fakePrivate = 'PLACEHOLDER-PRIVATE-KEY';
const _fakePublic = 'PLACEHOLDER-PUBLIC-KEY';

AmneziaWgOutbound _awg({
  int? jc,
  int? jmin,
  int? jmax,
  int? s1,
  int? s2,
  int? h1,
  int? h2,
  int? h3,
  int? h4,
}) {
  return AmneziaWgOutbound(
    server: 'vpn.example.com',
    serverPort: 51820,
    privateKey: _fakePrivate,
    peerPublicKey: _fakePublic,
    localAddresses: const ['10.0.0.2/32'],
    jc: jc,
    jmin: jmin,
    jmax: jmax,
    s1: s1,
    s2: s2,
    h1: h1,
    h2: h2,
    h3: h3,
    h4: h4,
  );
}

void main() {
  group('AmneziaWgOutbound equality', () {
    test('two identical instances are equal and share a hashCode', () {
      final a = _awg(jc: 4, h1: 100, h4: 400);
      final b = _awg(jc: 4, h1: 100, h4: 400);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('the identical() fast path short-circuits to true', () {
      final a = _awg(jc: 4);
      expect(identical(a, a), isTrue);
      expect(a, equals(a));
    });

    test('a fully-populated instance equals a copy of itself', () {
      final a = _awg(
        jc: 1,
        jmin: 2,
        jmax: 3,
        s1: 4,
        s2: 5,
        h1: 6,
        h2: 7,
        h3: 8,
        h4: 9,
      );
      final b = _awg(
        jc: 1,
        jmin: 2,
        jmax: 3,
        s1: 4,
        s2: 5,
        h1: 6,
        h2: 7,
        h3: 8,
        h4: 9,
      );
      expect(a, equals(b));
    });

    // Each of the nine AWG-only parameters must participate in equality.
    // The failure message names the parameter so a regression is diagnosable.
    final differences = <String, (AmneziaWgOutbound, AmneziaWgOutbound)>{
      'jc': (_awg(jc: 1), _awg(jc: 2)),
      'jmin': (_awg(jmin: 1), _awg(jmin: 2)),
      'jmax': (_awg(jmax: 1), _awg(jmax: 2)),
      's1': (_awg(s1: 1), _awg(s1: 2)),
      's2': (_awg(s2: 1), _awg(s2: 2)),
      'h1': (_awg(h1: 1), _awg(h1: 2)),
      'h2': (_awg(h2: 1), _awg(h2: 2)),
      'h3': (_awg(h3: 1), _awg(h3: 2)),
      'h4': (_awg(h4: 1), _awg(h4: 2)),
    };

    differences.forEach((name, pair) {
      test('instances differing only in "$name" are NOT equal', () {
        expect(
          pair.$1,
          isNot(equals(pair.$2)),
          reason: 'AmneziaWG parameter "$name" must participate in equality',
        );
      });
    });

    test('a set-vs-null difference in a parameter is also unequal', () {
      expect(_awg(jc: 4), isNot(equals(_awg())));
      expect(_awg(), isNot(equals(_awg(jc: 4))));
    });

    test('AWG is never equal to a plain WireGuard with the same fields', () {
      final wg = WireGuardOutbound(
        server: 'vpn.example.com',
        serverPort: 51820,
        privateKey: _fakePrivate,
        peerPublicKey: _fakePublic,
        localAddresses: const ['10.0.0.2/32'],
      );
      expect(_awg(), isNot(equals(wg)));
      expect(wg, isNot(equals(_awg())));
    });

    test('equality still honours the inherited WireGuard fields', () {
      // If the parent fields were ignored, these two would wrongly be equal.
      final base = _awg(jc: 4);
      final otherServer = AmneziaWgOutbound(
        server: 'other.example.com',
        serverPort: 51820,
        privateKey: _fakePrivate,
        peerPublicKey: _fakePublic,
        localAddresses: const ['10.0.0.2/32'],
        jc: 4,
      );
      expect(base, isNot(equals(otherServer)));

      final otherPort = AmneziaWgOutbound(
        server: 'vpn.example.com',
        serverPort: 51821,
        privateKey: _fakePrivate,
        peerPublicKey: _fakePublic,
        localAddresses: const ['10.0.0.2/32'],
        jc: 4,
      );
      expect(base, isNot(equals(otherPort)));
    });

    test('no AWG instance defines a toString override', () {
      // Guards the SECURITY.md rule that secret-bearing types must not expose
      // a default dump. Placeholder keys only, so nothing sensitive is printed.
      expect(_awg(jc: 4).toString(), isNot(contains(_fakePrivate)));
    });
  });
}
