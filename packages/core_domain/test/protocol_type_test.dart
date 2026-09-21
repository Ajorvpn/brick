// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

void main() {
  group('values and order', () {
    test('declares exactly the six supported protocols in canonical order', () {
      expect(ProtocolType.values, [
        ProtocolType.vless,
        ProtocolType.vmess,
        ProtocolType.trojan,
        ProtocolType.shadowsocks,
        ProtocolType.hysteria2,
        ProtocolType.tuic,
      ]);
    });
  });

  group('canonical URI schemes', () {
    test('vless uses the vless scheme', () {
      expect(ProtocolType.vless.scheme, 'vless');
    });

    test('vmess uses the vmess scheme', () {
      expect(ProtocolType.vmess.scheme, 'vmess');
    });

    test('trojan uses the trojan scheme', () {
      expect(ProtocolType.trojan.scheme, 'trojan');
    });

    test('shadowsocks uses the ss scheme per SIP-002 convention', () {
      expect(ProtocolType.shadowsocks.scheme, 'ss');
    });

    test('hysteria2 uses the hysteria2 scheme', () {
      expect(ProtocolType.hysteria2.scheme, 'hysteria2');
    });

    test('tuic uses the tuic scheme', () {
      expect(ProtocolType.tuic.scheme, 'tuic');
    });
  });
}
