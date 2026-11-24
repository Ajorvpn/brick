// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Ok;
import 'package:test/test.dart';

/// A syntactically valid dummy UUID, not a real credential.
const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';

VlessOutbound _vless(String query) {
  final result = parseVlessUri(
    'vless://$_uuid@example.com:443?security=tls&$query#N',
  );
  expect(result.isOk, isTrue, reason: 'link must parse: $query');
  return (result as Ok<OutboundConfig, ConfigParseError>).value
      as VlessOutbound;
}

void main() {
  group('ALPN query decoding (double-encoded feeds)', () {
    test('single-encoded alpn=h2%2Chttp%2F1.1 yields both tokens', () {
      expect(_vless('alpn=h2%2Chttp%2F1.1').tls?.alpn, ['h2', 'http/1.1']);
    });

    test('double-encoded alpn=http%252F1.1 is decoded, not passed verbatim', () {
      // The proven live defect: `Uri.queryParameters` decodes one layer only,
      // so sing-box received the literal `["http%2F1.1"]` and the TLS
      // handshake could not negotiate ALPN on that node.
      expect(_vless('alpn=http%252F1.1').tls?.alpn, ['http/1.1']);
    });

    test('double-encoded list alpn=h2%252Chttp%252F1.1 yields both tokens', () {
      expect(
        _vless('alpn=h2%252Chttp%252F1.1').tls?.alpn,
        ['h2', 'http/1.1'],
      );
    });

    test('malformed alpn=%ZZ never throws and yields no usable token', () {
      late VlessOutbound outbound;
      expect(
        () => outbound = _vless('alpn=%ZZ'),
        returnsNormally,
        reason: 'a malformed escape must degrade, never abort the parse',
      );
      expect(outbound.tls?.alpn, ['%ZZ']);
    });

    test('empty and whitespace-only alpn values yield no ALPN list', () {
      expect(_vless('alpn=').tls?.alpn, isNull);
      expect(_vless('alpn=%20').tls?.alpn, isNull);
    });

    test('Hysteria2 applies the same normalization', () {
      final result = parseHysteria2Uri(
        'hy2://pw@example.com:443?alpn=http%252F1.1#N',
      );
      expect(result.isOk, isTrue);
      final hy2 =
          (result as Ok<OutboundConfig, ConfigParseError>).value
              as Hysteria2Outbound;
      expect(hy2.tls.alpn, ['http/1.1']);
    });
  });
}
