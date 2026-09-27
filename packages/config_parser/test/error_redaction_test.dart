// SPDX-License-Identifier: GPL-3.0-or-later
// Phase 2 closeout audit (P2-T12): redaction regression suite.
import 'dart:convert';

import 'package:config_parser/config_parser.dart';
import 'package:shared_utils/shared_utils.dart' show Err;
import 'package:test/test.dart';

const _secret = 'CANARY_7f3a9c2eSECRETVALUE_do_not_leak';
const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';

void main() {
  test('no parser error message echoes any input secret', () {
    final hostile = <String>[
      'vless://$_uuid:$_secret@e.com:443#$_secret',
      'vless://$_secret@e.com:443#$_secret',
      'vmess://${base64.encode(utf8.encode('{"v":"2","add":"e.com","port":"443","id":"$_secret","ps":"$_secret"}'))}',
      'trojan://$_secret@e.com:443#$_secret',
      'ss://${base64.encode(utf8.encode('$_secret:$_secret'))}@e.com:8388#$_secret',
      'ss://$_secret',
      'hy2://$_secret@e.com:443#$_secret',
      'tuic://$_uuid:$_secret@e.com:443#$_secret',
      'wireguard://$_secret@e.com:51820?peer_public_key=$_secret&ip=$_secret',
      'amneziawg://$_secret@e.com:51820?peer_public_key=$_secret&ip=$_secret',
      'nosuch://$_secret@e.com:443',
      _secret,
      '$_secret\n$_secret\n$_secret',
      base64.encode(utf8.encode(_secret)),
      '{"type":"$_secret","server":"$_secret","server_port":1}',
      '{"type":"shadowsocks","server":"e.com","server_port":1,"method":"$_secret","password":"$_secret"}',
      'brick://import?url=$_secret',
      'brick://import?config=$_secret',
    ];
    for (final input in hostile) {
      final r = parseConfigContent(input);
      if (r case Err<SmartParseResult, ConfigParseError>(:final error)) {
        final e = error.message;
        expect(
          e.contains(_secret),
          isFalse,
          reason: 'LEAK from parseConfigContent for: ${input.split('?').first}',
        );
      }
      // An Ok result legitimately retains the secret in the outbound itself
      // (that is the payload's whole purpose); only the error path is
      // constrained.
    }
  });

  test('sanitiseEchoedIdentifier keeps real tokens, drops everything else', () {
    // A genuine token survives verbatim, so the diagnostic stays useful.
    expect(
      UnsupportedSchemeError('notavpn').message,
      'Unsupported scheme: notavpn',
    );
    expect(
      UnsupportedProtocolError('wireguard').message,
      'Unsupported protocol: wireguard',
    );
    expect(
      UnsupportedCipherError('chacha20-ietf-poly1305').message,
      contains('chacha20-ietf-poly1305'),
    );

    // Untrusted shapes do not.
    expect(
      UnsupportedProtocolError('UPPER').message,
      contains('(unprintable)'),
    );
    expect(
      UnsupportedProtocolError('has space').message,
      contains('(unprintable)'),
    );
    expect(UnsupportedProtocolError('').message, contains('(empty)'));
    expect(
      UnsupportedProtocolError('a' * 33).message,
      contains('over 32 chars'),
    );
  });

  test('an untrusted JSON type cannot smuggle a secret into a message', () {
    final r = parseConfigContent(
      jsonEncode({'type': _secret, 'server': 'e.com', 'server_port': 1}),
    );
    expect(r.isErr, isTrue);
    if (r case Err<SmartParseResult, ConfigParseError>(:final error)) {
      expect(error.message.contains(_secret), isFalse);
    }
  });
}
