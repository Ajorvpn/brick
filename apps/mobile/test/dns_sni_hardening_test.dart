// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P7-T3 DNS & IP-SNI Hardening Verification', () {
    const uuid = '11111111-2222-3333-4444-555555555555';

    test('RFC 6066: Valid domain SNI is preserved on domain endpoint', () {
      final outbound = VlessOutbound(
        server: 'node.example.com',
        serverPort: 443,
        uuid: uuid,
        tls: TlsSettings(enabled: true, serverName: 'node.example.com'),
      );
      final json = buildSingBoxOutbound(outbound);
      final tls = json['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls['server_name'], equals('node.example.com'));
    });

    test('RFC 6066: Valid domain SNI is preserved on IP endpoint', () {
      final outbound = VlessOutbound(
        server: '198.51.100.1',
        serverPort: 443,
        uuid: uuid,
        tls: TlsSettings(enabled: true, serverName: 'sni.example.com'),
      );
      final json = buildSingBoxOutbound(outbound);
      final tls = json['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls['server_name'], equals('sni.example.com'));
    });

    test('RFC 6066: Raw IPv4 literal is never emitted in tls.server_name', () {
      final outbound = VlessOutbound(
        server: '198.51.100.1',
        serverPort: 443,
        uuid: uuid,
        tls: TlsSettings(enabled: true, serverName: '198.51.100.1'),
      );
      final json = buildSingBoxOutbound(outbound);
      final tls = json['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls.containsKey('server_name'), isFalse);
    });

    test('RFC 6066: Raw IPv6 literal is never emitted in tls.server_name', () {
      final outbound = VlessOutbound(
        server: '2001:db8::1',
        serverPort: 443,
        uuid: uuid,
        tls: TlsSettings(enabled: true, serverName: '2001:db8::1'),
      );
      final json = buildSingBoxOutbound(outbound);
      final tls = json['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls.containsKey('server_name'), isFalse);
    });

    test('RFC 6066: Bracketed IPv6 literal [::1] is never emitted', () {
      final outbound = VlessOutbound(
        server: '[::1]',
        serverPort: 443,
        uuid: uuid,
        tls: TlsSettings(enabled: true, serverName: '[::1]'),
      );
      final json = buildSingBoxOutbound(outbound);
      final tls = json['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls.containsKey('server_name'), isFalse);
    });

    test('RFC 6066: IP literal in extraParams is sanitized', () {
      final outbound = Hysteria2Outbound(
        server: '198.51.100.1',
        serverPort: 443,
        password: 'pass',
        tls: TlsSettings(enabled: true),
        extraParams: {'server_name': '198.51.100.1'},
      );
      final json = buildSingBoxOutbound(outbound);
      final tls = json['tls'] as Map<String, dynamic>;
      expect(tls.containsKey('server_name'), isFalse);
    });
  });
}
