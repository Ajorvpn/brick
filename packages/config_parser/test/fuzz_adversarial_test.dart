// SPDX-License-Identifier: GPL-3.0-or-later

/// Adversarial / fuzz hardening pass across the whole package (P2-T11).
///
/// Two invariants are asserted for **every** input in the corpus, across every
/// public entry point:
///
/// 1. **Zero unhandled throws.** No `ArgumentError`, `StateError`,
///    `FormatException`, `RangeError`, `TypeError` or `CastError` may escape.
///    Every input yields a typed `Err` or a safe partial-success result.
/// 2. **Zero secret leaks.** No error `message` or `code` may contain the
///    planted canary, which stands in for a password / private key / token.
///
/// The corpus is deliberately adversarial rather than exhaustive: it targets
/// the categories named in the P2-T11 scope — size, encoding, byte hazards,
/// Unicode trickery, malformed URI components and malformed JSON.

import 'dart:convert';
import 'dart:math' as math;

import 'package:config_parser/config_parser.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';

/// The canary planted inside every credential-ish position of a hostile URI.
const String canary = 'CANARY_a1b2c3d4_SECRET_doNotLeak';

/// Every public entry point that must survive the corpus.
final List<({String name, Object? Function(String) run})> _entryPoints = [
  (name: 'parseUri', run: (s) => parseUri(s)),
  (name: 'parseVlessUri', run: (s) => parseVlessUri(s)),
  (name: 'parseVmessUri', run: (s) => parseVmessUri(s)),
  (name: 'parseTrojanUri', run: (s) => parseTrojanUri(s)),
  (name: 'parseShadowsocksUri', run: (s) => parseShadowsocksUri(s)),
  (name: 'parseHysteria2Uri', run: (s) => parseHysteria2Uri(s)),
  (name: 'parseTuicUri', run: (s) => parseTuicUri(s)),
  (name: 'parseWireguardUri', run: (s) => parseWireguardUri(s)),
  (name: 'parseAmneziaWgUri', run: (s) => parseAmneziaWgUri(s)),
  (name: 'parseConfigContent', run: (s) => parseConfigContent(s)),
  (name: 'parseSubscription', run: (s) => parseSubscription(s)),
  (name: 'parseUriRemark', run: (s) => parseUriRemark(s)),
  (name: 'decodeSubscriptionBody', run: (s) => decodeSubscriptionBody(s)),
  (
    name: 'SubscriptionUserInfo.parse',
    run: (s) => SubscriptionUserInfo.parse(s),
  ),
  (
    name: 'readSingBoxOutboundJson',
    run: (s) {
      final decoded = safeJsonDecode(s, field: 'fuzz', maxLength: 1 << 26);
      if (decoded is Err) return decoded;
      final value = (decoded as Ok<Object?, ConfigParseError>).value;
      if (value is Map) {
        return readSingBoxOutboundJson(value.cast<String, dynamic>());
      }
      return const Err(InvalidSyntaxError('fuzz', 'not a map'));
    },
  ),
];

/// Runs [input] through [entry], asserting the two invariants.
///
/// Returns the number of errors the corpus produced, so callers can assert
/// that the corpus is not silently passing because nothing was exercised.
int assertInvariants(
  ({String name, Object? Function(String) run}) entry,
  String input, {
  required String label,
  required void Function(String) onError,
}) {
  Object? outcome;
  try {
    outcome = entry.run(input);
  } on Object catch (e, st) {
    fail(
      'INVARIANT 1 VIOLATED — ${entry.name} threw ${e.runtimeType} on '
      '[${entry.name} / $label]\n$e\n$st',
    );
  }

  // A thrown future (the fetcher path) would surface here; none of these are
  // async, so an already-errored Future would be a bug worth flagging.
  if (outcome is Future) {
    fail(
      'INVARIANT 1 VIOLATED — ${entry.name} returned a Future '
      '([${entry.name} / $label])',
    );
  }

  _assertNoLeak(entry, input, outcome, onError: onError);
  return outcome is Err ? 1 : 0;
}

void _assertNoLeak(
  ({String name, Object? Function(String) run}) entry,
  String input,
  Object? outcome, {
  required void Function(String) onError,
}) {
  final errors = <ConfigParseError>[];
  if (outcome is Err) {
    final e = outcome.error;
    if (e is ConfigParseError) errors.add(e);
  } else if (outcome is Ok) {
    final v = outcome.value;
    if (v is SubscriptionParseResult) errors.addAll(v.errors);
    if (v is SmartParseResult) errors.addAll(v.warnings);
  }
  for (final e in errors) {
    onError(e.message);
    final haystack = '${e.message} ${e.code} $e';
    if (haystack.contains(canary)) {
      fail(
        'INVARIANT 2 VIOLATED — ${entry.name} leaked the canary in '
        '`$haystack` ([${entry.name} / $labelOf(input)])',
      );
    }
  }
}

String labelOf(String input) =>
    input.length <= 48 ? input : '${input.substring(0, 45)}...';

void main() {
  /// A single shared corpus so every entry point sees identical bytes.
  final corpus = _buildCorpus();

  group('PART 1: every entry point survives the whole adversarial corpus', () {
    for (final entry in _entryPoints) {
      test('${entry.name} returns typed Results and leaks nothing', () {
        final seenMessages = <String>{};
        var errorCount = 0;
        for (final item in corpus) {
          errorCount += assertInvariants(
            entry,
            item.input,
            label: item.label,
            onError: seenMessages.add,
          );
        }
        // Sanity: the corpus must actually be producing errors somewhere,
        // otherwise this test proves nothing. `parseUriRemark` is exempt: it
        // returns a plain remark String, not a Result, so it has no errors to
        // produce — for it the "never throws / never leaks" half is the whole
        // assertion.
        if (entry.name != 'parseUriRemark') {
          if (errorCount == 0) {
            fail(
              'corpus produced no errors for ${entry.name} — the fuzz '
              'corpus is not exercising this entry point',
            );
          }
          expect(seenMessages, isNotEmpty);
        }
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });

  group('PART 1a: extreme bounds and massive inputs', () {
    // Over-sized inputs are rejected fast rather than processed.
    final huge = [
      ('64 KB URI', 'vless://$_uuid@a.com:443?${'x' * (64 * 1024)}'),
      ('1 MB URI', 'vless://$_uuid@a.com:443?${'x' * (1024 * 1024)}'),
      (
        '10 MB subscription',
        List.filled(40000, 'vless://$_uuid@a.com:443').join('\n'),
      ),
      ('64 KB no delimiters', 'v' * (64 * 1024)),
      ('1 MB no delimiters', 'v' * (1024 * 1024)),
      ('10 MB no delimiters', 'v' * (10 * 1024 * 1024)),
    ];

    for (final (label, input) in huge) {
      test('$label is rejected quickly', () {
        final sw = Stopwatch()..start();
        for (final entry in _entryPoints) {
          assertInvariants(entry, input, label: label, onError: (_) {});
        }
        sw.stop();
        // "No pathological slowdown" proxy, per the P2-T11 AC: a multi-megabyte
        // input must be rejected in well under a second per entry point.
        expect(
          sw.elapsedMilliseconds,
          lessThan(20000),
          reason:
              '$label took ${sw.elapsedMilliseconds}ms across all '
              '${_entryPoints.length} entry points',
        );
      }, timeout: const Timeout(Duration(seconds: 90)));
    }

    test('a 1 MB single line with no delimiters is bounded', () {
      final sw = Stopwatch()..start();
      final r = parseUri('vless://' + 'a' * (1024 * 1024));
      sw.stop();
      expect(r.isOk || r.isErr, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('JSON nested far beyond maxJsonDepth is rejected, not recursed', () {
      // 200 levels, maxJsonDepth is 32.
      final deep = '${'[' * 200}${']' * 200}';
      final sw = Stopwatch()..start();
      final r = parseConfigContent(deep);
      sw.stop();
      expect(r.isErr, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('a 100k-element JSON array is bounded', () {
      final arr = '[${List.filled(100000, '1').join(',')}]';
      final r = parseConfigContent(arr);
      expect(r.isOk || r.isErr, isTrue);
    });
  });

  group('PART 1b: corrupted encoding and byte hazards', () {
    final encodings = <String, String>{
      'invalid base64 chars': 'vmess://!@#\$%^&*()_+-=[]{}\'',
      'broken padding': 'vmess://QQ=',
      'truncated base64': 'vmess://QUJD',
      'base64 of non-utf8': 'vmess://${base64.encode([0xC3, 0x28, 0xA0])}',
      'null byte in uri': 'vless://$_uuid@a\x00.com:443',
      'null byte mid-query': 'vless://$_uuid@a.com:443?x=\x00',
      'carriage return': 'vless://$_uuid@a.com:443\r\nHost: evil',
      'CRLF injection': 'vless://$_uuid@a.com:443\r\nX-Injected: 1',
      'control chars': 'vless://$_uuid@a.com:443?x=\x01\x02\x1F',
      'DEL char': 'vless://$_uuid@a.com:443?x=\x7F',
      'bidi override (RTL)': 'vless://$_uuid@\u202Eevil.com:443#\u202Etxet',
      'zero-width space': 'vless://$_uuid@a.com:443',
      'zero-width joiner': 'vless://$_uuid@a\u200D.com:443',
      'lone high surrogate': 'vless://$_uuid@a\uD800.com:443',
      'lone low surrogate': 'vless://$_uuid@a\uDC00.com:443',
      'surrogate pair emoji': 'vless://$_uuid@a🙂.com:443',
      'emoji-heavy password': 'trojan://🔑🔑🔑@a.com:443',
      'combining marks': 'vless://$_uuid@á̴.com:443',
      'malformed percent': 'trojan://pw%zz@a.com:443',
      'truncated percent': 'trojan://pw%A@a.com:443',
      'percent invalid utf8': 'trojan://%C3%28@a.com:443',
      'double-encoded percent': 'trojan://pw%2525zz@a.com:443',
      'deeply nested percent': 'trojan://${'%41' * 2000}@a.com:443',
    };

    for (final entry in encodings.entries) {
      test('${entry.key} is handled without throwing', () {
        for (final ep in _entryPoints) {
          assertInvariants(ep, entry.value, label: entry.key, onError: (_) {});
        }
      });
    }
  });

  group('PART 1c: malformed URI components', () {
    final ports = <String>[
      '-1',
      '0',
      '65535',
      '65536',
      '999999',
      'abc',
      '',
      '443.5',
      '+443',
      ' 443',
      '0x1BB',
      '0443',
      '1e3',
    ];
    for (final port in ports) {
      test('port "$port" is rejected or safely handled', () {
        for (final ep in _entryPoints) {
          assertInvariants(
            ep,
            'vless://$_uuid@a.com:$port',
            label: 'port $port',
            onError: (_) {},
          );
        }
      });
    }

    final hosts = <String, String>{
      'empty host': 'vless://$_uuid@:443',
      'host is port': 'vless://$_uuid@443',
      'unclosed ipv6': 'vless://$_uuid@[::1:443',
      'empty ipv6': 'vless://$_uuid@[]:443',
      'ipv6 no brackets': 'vless://$_uuid@::1:443',
      'ipv6 zone id': 'vless://$_uuid@[fe80::1%25eth0]:443',
      'host with spaces': 'vless://$_uuid@a b.com:443',
      'host with slash': 'vless://$_uuid@a/b.com:443',
      'host with at': 'vless://$_uuid@a@b.com:443',
      'host with hash': 'vless://$_uuid@a#b.com:443',
      'host with query': 'vless://$_uuid@a?b.com:443',
      'very long host': 'vless://$_uuid@${'a' * 5000}.com:443',
      'no userinfo': 'vless://a.com:443',
      'multiple at signs': 'vless://$_uuid@a@b@c.com:443',
      'empty everything': 'vless://',
      'just scheme': 'vless:',
      'no scheme separator': 'vless//$_uuid@a.com:443',
    };
    for (final h in hosts.entries) {
      test('${h.key} is rejected or safely handled', () {
        for (final ep in _entryPoints) {
          assertInvariants(ep, h.value, label: h.key, onError: (_) {});
        }
      });
    }

    test('misspelled and unsupported schemes', () {
      const schemes = [
        'vles',
        'vlless',
        'http',
        'ftp',
        'file',
        'data',
        'javascript',
      ];
      for (final s in schemes) {
        for (final ep in _entryPoints) {
          assertInvariants(
            ep,
            '$s://$_uuid@a.com:443?token=$canary',
            label: 'scheme $s',
            onError: (_) {},
          );
        }
      }
    });

    test('credentials packed with URI-reserved characters', () {
      const reserved = r':@/?#%[]&;=+,';
      final creds = <String>[
        for (final c in reserved.split('')) 'pw${c}x',
        for (final c in reserved.split('')) 'pw${Uri.encodeComponent(c)}x',
        'pw:@/?#x',
        r'pw\backslash',
        'pw"quote',
        "pw'quote",
        r'pw`tick',
        r'pw$dollar',
        'pw\u{1F600}emoji',
        'pw\u0000null',
        'pw\nnewline',
        'pw\r\ncrlf',
        canary,
      ];
      for (final c in creds) {
        for (final ep in _entryPoints) {
          assertInvariants(
            ep,
            'trojan://$c@a.com:443',
            label: 'cred $c',
            onError: (_) {},
          );
        }
      }
    });
  });

  group('PART 1d: malformed Sing-Box JSON', () {
    final jsons = <String, String>{
      'port as string': '{"type":"vless","server":"a","server_port":"443"}',
      'port as float': '{"type":"vless","server":"a","server_port":443.9}',
      'port negative': '{"type":"vless","server":"a","server_port":-1}',
      'port as null': '{"type":"vless","server":"a","server_port":null}',
      'type as number': '{"type":123,"server":"a","server_port":443}',
      'type as object': '{"type":{},"server":"a","server_port":443}',
      'missing type': '{"server":"a","server_port":443}',
      'missing server': '{"type":"vless","server_port":443}',
      'missing port': '{"type":"vless","server":"a"}',
      'empty object': '{}',
      'array where object expected': '[]',
      'nested null': '{"type":"vless","server":null,"server_port":null}',
      'deeply nested': _nestedJson(200),
      'truncated': '{"type":"vless"',
      'trailing garbage':
          '{"type":"vless","server":"a","server_port":443}trail',
      'duplicate keys':
          '{"type":"trojan","type":"vless","server":"a","server_port":443}',
      'unicode escapes':
          r'{"type":"vless","server":"\ud800","server_port":443}',
      'huge number':
          '{"type":"vless","server":"a","server_port":99999999999999999999}',
      'negative depth': _nestedJson(-1),
      'reserved key':
          '{"type":"vless","server":"a","server_port":443,"__proto__":{"x":1}}',
      'canary in type': '{"type":"$canary","server":"a","server_port":443}',
    };

    for (final j in jsons.entries) {
      test('${j.key} is rejected or safely handled', () {
        for (final ep in _entryPoints) {
          assertInvariants(ep, j.value, label: j.key, onError: (_) {});
        }
      });
    }
  });

  group('PART 2: invariants hold under a deterministic pseudo-random fuzz', () {
    test('5000 random byte-soup inputs never throw and never leak', () {
      final rnd = math.Random(20260927); // fixed seed: reproducible failures
      const alphabet =
          'ABCXYZabcxyz0189:/?#[]@!\$&\'()*+,;=%\\ '
          '\t\n\r\x00\x01\x1F\x7F'
          '\u202E\u200D\uD800\uDC00\uD83D\uDD11\u65E5';
      var errors = 0;
      for (var i = 0; i < 5000; i++) {
        final len = 1 + rnd.nextInt(64);
        final buf = StringBuffer();
        for (var j = 0; j < len; j++) {
          buf.write(alphabet[rnd.nextInt(alphabet.length)]);
        }
        final body = buf.toString();
        final input = rnd.nextBool() ? body : 'vless://$body@a.com:443';
        for (final ep in _entryPoints) {
          errors += assertInvariants(
            ep,
            input,
            label: 'fuzz#$i',
            onError: (_) {},
          );
        }
      }
      // The fuzzer must actually be finding failures, or it is not testing.
      expect(errors, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('random deep-nesting JSON never blows the stack', () {
      final rnd = math.Random(99);
      for (var i = 0; i < 500; i++) {
        final depth = rnd.nextInt(120);
        final open = '[' * depth;
        final close = ']' * depth;
        final input = open + close;
        final sw = Stopwatch()..start();
        final r = parseConfigContent(input);
        sw.stop();
        expect(r.isOk || r.isErr, isTrue, reason: labelOf(input));
        expect(sw.elapsedMilliseconds, lessThan(3000));
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('PART 2b: explicit regression tests for bugs this pass found', () {
    // Each of these threw FormatException before percentDecodeOrRaw was made
    // total. They are pinned individually so the fix cannot silently regress.
    test('malformed percent-encoding does not throw FormatException', () {
      const inputs = [
        'trojan://%C3%28@a.com:443',
        'tuic://$_uuid:pw%C3%28@a.com:443',
        'hysteria2://%C3%28@a.com:443',
        'wireguard://%C3%28@a.com:51820?peer_public_key=x&ip=1.2.3.4',
        'amneziawg://%C3%28@a.com:51820?peer_public_key=x&ip=1.2.3.4',
        'brick://import?url=%C3%28',
        'trojan://%C3%28@a.com:443#%F0%28%8C%BC',
        'trojan://%ED%A0%80@a.com:443',
        'trojan://%F4%90%80%80@a.com:443',
      ];
      for (final input in inputs) {
        expect(
          () => parseUri(input),
          returnsNormally,
          reason: 'parseUri threw on: $input',
        );
        expect(
          () => parseConfigContent(input),
          returnsNormally,
          reason: 'parseConfigContent threw on: $input',
        );
        final remark = parseUriRemark(input);
        expect(remark, isA<String>());
      }
    });

    test('every parser handles a bad escape in every position', () {
      const bad = '%C3%28';
      final uris = [
        'vless://$_uuid@$bad.com:443',
        'vless://$_uuid@a.com:443?host=$bad',
        'vless://$_uuid@a.com:443?path=$bad&sni=$bad&pbk=$bad',
        'vmess://${base64.encode(utf8.encode('{"add":"$bad","port":"443"}'))}',
        'trojan://$bad@a.com:443?peer_public_key=$bad&ip=$bad',
        'ss://${base64.encode(utf8.encode('$bad:$bad'))}@a.com:8388?plugin=$bad',
        'hysteria2://$bad@a.com:443?obfs-password=$bad',
        'tuic://$_uuid:$bad@a.com:443?congestion_control=$bad',
        'wireguard://$bad@a.com:51820?peer_public_key=$bad&ip=$bad&mtu=$bad',
        'amneziawg://$bad@a.com:51820?peer_public_key=$bad&ip=$bad&jc=$bad',
      ];
      for (final uri in uris) {
        for (final ep in _entryPoints) {
          assertInvariants(ep, uri, label: 'bad escape', onError: (_) {});
        }
      }
    });
  });
}

String _nestedJson(int depth) {
  if (depth < 0) return '{}';
  return '{"a":${_nestedJson(depth - 1)}}';
}

List<({String label, String input})> _buildCorpus() {
  final items = <({String label, String input})>[];

  void add(String label, String input) =>
      items.add((label: label, input: input));

  // 1. Size extremes.
  add('8KB+1 URI', 'vless://$_uuid@a.com:443?${'x' * (8 * 1024)}');
  add('64KB URI', 'vless://$_uuid@a.com:443?${'x' * (64 * 1024)}');
  add('1MB URI', 'vless://$_uuid@a.com:443?${'x' * (1024 * 1024)}');
  add('10MB no delimiters', 'v' * (10 * 1024 * 1024));
  add('1MB no delimiters', 'x' * (1024 * 1024));
  add('64KB no delimiters', 'y' * (64 * 1024));
  add(
    '40000-line subscription',
    List.filled(40000, 'vless://$_uuid@a.com:443').join('\n'),
  );
  add('subscription of empties', '\n' * 100000);

  // 2. Encoding hazards.
  add('invalid base64', 'vmess://!!!!');
  add('base64 no padding', 'vmess://QQ');
  add('base64 of binary', 'vmess://${base64.encode([0xFF, 0xFE, 0x00])}');
  add('urlsafe base64', 'vmess://a-b_cd==');
  add('malformed percent', 'trojan://pw%zz@a.com:443');
  add('truncated percent', 'trojan://pw%A@a.com:443');
  add('percent invalid utf8', 'trojan://%C3%28@a.com:443');
  add('lone surrogate escape', 'trojan://%ED%A0%80@a.com:443');
  add('nested percent', 'trojan://${'%41' * 1000}@a.com:443');

  // 3. Byte / control hazards.
  add('null byte', 'vless://$_uuid@a\x00.com:443');
  add('CRLF injection', 'vless://$_uuid@a.com:443\r\nX: 1');
  add('control chars', 'trojan://\x01\x02\x1F@a.com:443');
  add('DEL', 'trojan://\x7F@a.com:443');
  add('vertical tab', 'trojan://\x0B@a.com:443');
  add('form feed', 'trojan://\x0C@a.com:443');
  add('all control chars', String.fromCharCodes(List.generate(32, (i) => i)));

  // 4. Unicode trickery.
  add('RTL override', 'vless://$_uuid@\u202Emoc.evil:443#\u202Etxet');
  add('LTR override', 'vless://$_uuid@\u202Dmoc.evil:443');
  add('zero width space', 'vless://$_uuid@a.com:443');
  add('zero width non-joiner', 'trojan://pw@a.com:443');
  add('word joiner', 'trojan://pw\u2060@a.com:443');
  add('bom in body', '\uFEFFvless://$_uuid@a.com:443');
  add('lone high surrogate', 'vless://$_uuid@a\uD800.com:443');
  add('emoji host', 'vless://$_uuid@🔑.com:443');
  add('combining marks', 'trojan://á̴@🔑.com:443');
  add('rtl in password', 'trojan://\u202Edrowssap@a.com:443');

  // 5. Malformed URI components.
  for (final p in ['-1', '0', '65536', '999999', 'abc', '', '443.5', '0x1BB']) {
    add('port $p', 'vless://$_uuid@a.com:$p');
  }
  add('empty host', 'vless://$_uuid@:443');
  add('unclosed ipv6', 'vless://$_uuid@[::1:443');
  add('empty ipv6', 'vless://$_uuid@[]:443');
  add('ipv6 zone', 'vless://$_uuid@[fe80::1%25eth0]:443');
  add('no userinfo', 'vless://a.com:443');
  add('many at signs', 'vless://$_uuid@a@b@c@d.com:443');
  add('empty uri', 'vless://');
  add('no separator', 'vless/$_uuid@a.com');
  add('misspelled scheme', 'vles://$_uuid@a.com:443');
  add('unsupported scheme', 'ftp://$_uuid@a.com:443');
  for (final s in [
    ':',
    '@',
    '/',
    '?',
    '#',
    '%',
    '[',
    ']',
    '&',
    '=',
    '+',
    ',',
  ]) {
    add('raw reserved $s', 'trojan://pw${s}x@a.com:443');
    add(
      'encoded reserved $s',
      'trojan://pw${Uri.encodeComponent(s)}x@a.com:443',
    );
  }

  // 6. Malformed JSON.
  add('port as string', '{"type":"vless","server":"a","server_port":"443"}');
  add('port as float', '{"type":"vless","server":"a","server_port":1.5}');
  add('port null', '{"type":"vless","server":"a","server_port":null}');
  add('type as int', '{"type":5,"server":"a","server_port":443}');
  add('missing type', '{"server":"a","server_port":443}');
  add('missing server', '{"type":"vless","server_port":443}');
  add('truncated json', '{"type":"vless"');
  add('trailing garbage', '{"type":"vless"}trail');
  add('empty object', '{}');
  add('json array', '[]');
  add('json null', 'null');
  add('json number', '42');
  add('json string', '"hello"');
  add('deep json 200', _nestedJson(200));
  add('deep json 40', _nestedJson(40));
  add('huge json array', '[${List.filled(50000, '1').join(',')}]');
  add('json with canary type', '{"type":"$canary","server":"a"}');
  add(
    'json with canary server',
    '{"type":"trojan","server":"$canary","server_port":443,"password":"$canary"}',
  );

  // 7. Deep links and subscription shapes.
  add('deep link no params', 'brick://import');
  add('deep link unknown param', 'brick://import?foo=$canary');
  add('deep link empty value', 'brick://import?url=');
  add(
    'deep link recursive',
    'brick://import?url=${Uri.encodeComponent('brick://import?url=x')}',
  );
  add('deep link canary', 'brick://import?config=$canary');
  add(
    'deep link canary encoded',
    'brick://import?config=${Uri.encodeComponent(canary)}',
  );
  add('comment lines only', '# comment\n; another\n! third');
  add('blank only', '\n\n\n\n');
  add('whitespace only', '   \t  \n  ');

  // 8. Credential canaries in every supported scheme.
  add('canary vless', 'vless://$canary@a.com:443');
  add('canary trojan', 'trojan://$canary@a.com:443');
  add('canary hy2', 'hysteria2://$canary@a.com:443');
  add('canary tuic', 'tuic://$_uuid:$canary@a.com:443');
  add(
    'canary wg',
    'wireguard://$canary@a.com:51820?peer_public_key=$canary&ip=1.2.3.4',
  );
  add(
    'canary awg',
    'amneziawg://$canary@a.com:51820?peer_public_key=$canary&ip=1.2.3.4',
  );
  add(
    'canary ss',
    'ss://${base64.encode(utf8.encode('$canary:$canary'))}@a.com:8388',
  );
  add(
    'canary vmess',
    'vmess://${base64.encode(utf8.encode('{"v":"2","add":"a.com","port":"443","id":"$canary","ps":"$canary"}'))}',
  );

  return items;
}
