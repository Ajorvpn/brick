// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_utils/shared_utils.dart';
import 'package:test/test.dart';

void main() {
  group('redact', () {
    test('exists as a top-level String -> String function', () {
      // Compile-time proof that the helper is exported from the barrel with
      // the contract SECURITY.md Section 4 requires.
      const String Function(String, {Iterable<String> knownSecrets}) fn =
          redact;
      expect(redact, same(fn));
    });

    test('returns a String for arbitrary input', () {
      expect(redact('hello'), isA<String>());
    });

    test('passes through empty and whitespace-only strings unchanged', () {
      expect(redact(''), '');
      expect(redact('   '), '   ');
    });

    test('passes through non-sensitive log message unchanged', () {
      expect(
        redact('Tunnel interface tun0 configured successfully'),
        'Tunnel interface tun0 configured successfully',
      );
    });

    test('redacts known secrets (length >= 4)', () {
      const text = 'Connected to endpoint with token superSecretToken12345';
      final redacted = redact(
        text,
        knownSecrets: ['superSecretToken12345', 'foo'],
      );
      expect(redacted, 'Connected to endpoint with token [REDACTED]');
    });

    test('redacts share links and subscription URIs across protocols', () {
      expect(
        redact(
          'Imported profile from vless://1111-2222@example.com:443?type=ws#Node',
        ),
        'Imported profile from vless://[REDACTED]',
      );
      expect(
        redact(
          'Fetching subscription from https://sub.provider.com/api/v1/sub?token=xyz',
        ),
        'Fetching subscription from https://[REDACTED]',
      );
      expect(
        redact('Config trojan://secretPassword@1.2.3.4:443#TrojanNode'),
        'Config trojan://[REDACTED]',
      );
    });

    test('redacts structured JSON sensitive fields', () {
      const json =
          '{"level":"info","password":"secretPassword123","uuid":"11111111-2222-3333-4444-555555555555"}';
      final result = redact(json);
      expect(result.contains('secretPassword123'), isFalse);
      expect(result.contains('"password":"[REDACTED]"'), isTrue);
    });

    test('redacts key-value free-text assignments', () {
      expect(
        redact('Handshake failed: password=mySecretPassword; retry=1'),
        'Handshake failed: password=[REDACTED]; retry=1',
      );
      expect(
        redact('Authenticating with token: mySecretToken-xyz'),
        'Authenticating with token: [REDACTED]',
      );
    });

    test('redacts RFC 4122 UUIDs', () {
      expect(
        redact(
          'Session created for user 12345678-abcd-ef01-2345-6789abcdef01 in tunnel',
        ),
        'Session created for user [REDACTED_UUID] in tunnel',
      );
    });

    test(
      'redacts external IPv4 and IPv6 while preserving loopback/TUN addresses',
      () {
        // External IPv4
        expect(
          redact('Connecting to 198.51.100.25:443'),
          'Connecting to [REDACTED_IP]',
        );

        // External IPv6
        expect(
          redact('Connecting to [2001:db8::1]:443'),
          'Connecting to [REDACTED_IP]',
        );

        // Safe internal TUN / loopback addresses
        expect(
          redact('Assigned TUN IP 10.111.222.1 netmask 255.255.255.0'),
          'Assigned TUN IP 10.111.222.1 netmask 255.255.255.0',
        );
        expect(
          redact('Listening on 127.0.0.1:8080 and 0.0.0.0'),
          'Listening on 127.0.0.1:8080 and 0.0.0.0',
        );
        expect(redact('Routing via ::1 and ::'), 'Routing via ::1 and ::');
      },
    );

    test('preserves timestamps without misidentifying as IPv6', () {
      expect(
        redact('2026-11-05 14:30:00 INFO Connection established'),
        '2026-11-05 14:30:00 INFO Connection established',
      );
    });
  });
}
