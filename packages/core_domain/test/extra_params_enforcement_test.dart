// SPDX-License-Identifier: GPL-3.0-or-later

// Runtime enforcement of the extraParams escape-hatch policy from
// COMPETITIVE_RESEARCH.md section 4.1: `extraParams` exists so a future
// protocol option can be modeled BEFORE it gets a typed field, but every
// STANDARD instance must keep it null.
//
// This test file fails the build if anyone starts populating
// `extraParams` inside default constructors or constructors' default
// values — which would silently bypass type safety and leak unvalidated
// keys into Phase 3/8 serialization. Populating it requires a deliberate
// design review, and this file is the tripwire that forces that review.

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

void main() {
  group('default instances keep extraParams null (escape-hatch policy)', () {
    test('VlessOutbound keeps extraParams null', () {
      expect(
        const VlessOutbound(
          server: 'v',
          serverPort: 443,
          uuid: 'u',
        ).extraParams,
        isNull,
      );
    });

    test('VmessOutbound keeps extraParams null', () {
      expect(
        const VmessOutbound(
          server: 'm',
          serverPort: 443,
          uuid: 'u',
        ).extraParams,
        isNull,
      );
    });

    test('TrojanOutbound keeps extraParams null', () {
      expect(
        const TrojanOutbound(
          server: 't',
          serverPort: 443,
          password: 'p',
        ).extraParams,
        isNull,
      );
    });

    test('ShadowsocksOutbound keeps extraParams null', () {
      expect(
        const ShadowsocksOutbound(
          server: 's',
          serverPort: 8388,
          method: '2022-blake3-aes-128-gcm',
          password: 'p',
        ).extraParams,
        isNull,
      );
    });

    test('Hysteria2Outbound keeps extraParams null', () {
      expect(
        const Hysteria2Outbound(
          server: 'h',
          serverPort: 443,
          password: 'p',
          tls: TlsSettings(enabled: true),
        ).extraParams,
        isNull,
      );
    });

    test('TuicOutbound keeps extraParams null', () {
      expect(
        const TuicOutbound(
          server: 'q',
          serverPort: 443,
          uuid: 'u',
          password: 'p',
          tls: TlsSettings(enabled: true),
        ).extraParams,
        isNull,
      );
    });
  });
}
