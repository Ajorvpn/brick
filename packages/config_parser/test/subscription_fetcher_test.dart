// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:test/test.dart';

const _uuid = 'b831381d-6324-4d53-ad4f-8cda48b30811';
String _vless(String host) => 'vless://$_uuid@$host:443#Node';

/// A scripted [SubscriptionTransport]: no sockets, fully deterministic.
class FakeTransport implements SubscriptionTransport {
  FakeTransport(this._respond);

  /// Builds a transport that streams raw [bytes].
  factory FakeTransport.bytes(List<int> bytes) => FakeTransport(
    (uri, headers) async => TransportResponse(
      statusCode: 200,
      headers: const {},
      body: Stream<List<int>>.value(bytes),
    ),
  );

  /// Builds a single 200 response carrying [body].
  factory FakeTransport.ok(String body, {Map<String, String> headers = const {}}) =>
      FakeTransport(
        (uri, headers) async => TransportResponse(
          statusCode: 200,
          headers: headers,
          body: Stream<List<int>>.value(utf8.encode(body)),
        ),
      );

  /// Responds with a fixed status code.
  factory FakeTransport.status(int code) => FakeTransport(
    (uri, headers) async => TransportResponse(
      statusCode: code,
      headers: const {},
      body: const Stream<List<int>>.empty(),
    ),
  );

  /// Never completes before the fetcher's deadline elapses.
  factory FakeTransport.hang() => FakeTransport((uri, headers) async {
    await Future<void>.delayed(const Duration(seconds: 30));
    return TransportResponse(
      statusCode: 200,
      headers: const {},
      body: const Stream<List<int>>.empty(),
    );
  });

  /// Throws, simulating a DNS/socket failure.
  factory FakeTransport.throws() =>
      FakeTransport((uri, headers) async => throw const SocketException('boom'));

  final Future<TransportResponse> Function(Uri, Map<String, String>) _respond;

  /// Every URI requested, in order (redirect chains are observable here).
  final List<Uri> requestedUris = [];

  /// Every set of headers sent, in order.
  final List<Map<String, String>> sentHeaders = [];

  bool closed = false;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) {
    requestedUris.add(uri);
    sentHeaders.add(Map.of(headers));
    return _respond(uri, headers);
  }

  @override
  void close() => closed = true;
}

/// A transport that streams [chunks], recording whether it was cancelled
/// early (which is how the size cap is proven to actually abort the stream).
class ChunkedTransport implements SubscriptionTransport {
  ChunkedTransport(this.chunkSize, this.totalChunks);

  final int chunkSize;
  final int totalChunks;
  bool cancelledEarly = false;
  int chunksDelivered = 0;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async {
    late StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        var sent = 0;
        void pump() {
          if (sent >= totalChunks) {
            unawaited(controller.close());
            return;
          }
          sent++;
          chunksDelivered++;
          controller.add(List<int>.filled(chunkSize, 0x41));
          scheduleMicrotask(pump);
        }

        pump();
      },
      onCancel: () => cancelledEarly = true,
    );
    return TransportResponse(
      statusCode: 200,
      headers: const {},
      body: controller.stream,
    );
  }

  @override
  void close() {}
}

void main() {
  group('successful fetch', () {
    test('a 200 body is fetched and parsed', () async {
      final transport = FakeTransport.ok('${_vless('a.com')}\n${_vless('b.com')}');
      final fetcher = SubscriptionFetcher(transport: transport);

      final result = await fetcher.fetchSubscription(
        Uri.parse('https://sub.example.com/list?token=SECRET'),
      );

      expect(result.isOk, isTrue);
      final parsed =
          (result as Ok<SubscriptionParseResult, ConfigParseError>).value;
      expect(parsed.configs, hasLength(2));
      expect(parsed.configs.first, isA<VlessOutbound>());
      expect(parsed.errors, isEmpty);
    });

    test('a base64 subscription body is decoded by the parser', () async {
      final body = base64.encode(
        utf8.encode('${_vless('a.com')}\n${_vless('b.com')}'),
      );
      final fetcher = SubscriptionFetcher(
        transport: FakeTransport.ok(body),
      );
      final result = await fetcher.fetchSubscription(
        Uri.parse('https://sub.example.com/list'),
      );
      expect(result.isOk, isTrue);
      expect(
        (result as Ok<SubscriptionParseResult, ConfigParseError>).value.configs,
        hasLength(2),
      );
    });

    test('Subscription-Userinfo is carried through to the parse result', () async {
      final fetcher = SubscriptionFetcher(
        transport: FakeTransport.ok(
          _vless('a.com'),
          headers: {
            'subscription-userinfo':
                'upload=10; download=20; total=100; expire=1700000000',
          },
        ),
      );
      final result = await fetcher.fetchSubscription(
        Uri.parse('https://sub.example.com/list'),
      );
      final parsed =
          (result as Ok<SubscriptionParseResult, ConfigParseError>).value;
      // The header reaches the parser; the value itself is not echoed.
      expect(parsed.configs, hasLength(1));
    });
  });

  group('HTTPS enforcement', () {
    test('a plain http:// URL is rejected without any request', () async {
      final transport = FakeTransport.ok(_vless('a.com'));
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('http://sub.example.com/list'));

      expect(result.isErr, isTrue);
      final error =
          (result as Err<SubscriptionParseResult, ConfigParseError>).error;
      expect(error, isA<InsecureTransportError>());
      expect(error.code, 'insecure_transport');
      expect(transport.requestedUris, isEmpty, reason: 'must not hit network');
    });

    test('a non-HTTP scheme is rejected too', () async {
      final transport = FakeTransport.ok(_vless('a.com'));
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('ftp://sub.example.com/list'));
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SubscriptionParseResult, ConfigParseError>).error,
        isA<InsecureTransportError>(),
      );
    });
  });

  group('size limit', () {
    test('an oversized body returns InputTooLargeError and cancels the stream',
        () async {
      // 1 KiB chunks; a 4 KiB cap trips after 5 chunks.
      final transport = ChunkedTransport(1024, 1000);
      final fetcher = SubscriptionFetcher(transport: transport);

      final result = await fetcher.fetchSubscription(
        Uri.parse('https://sub.example.com/list'),
        maxBytes: 4096,
      );

      expect(result.isErr, isTrue);
      final error =
          (result as Err<SubscriptionParseResult, ConfigParseError>).error;
      expect(error, isA<InputTooLargeError>());
      expect((error as InputTooLargeError).maxLength, 4096);
      // Proves the cap aborts the stream rather than buffering everything.
      expect(transport.cancelledEarly, isTrue);
      expect(
        transport.chunksDelivered,
        lessThan(1000),
        reason: 'must not read the whole oversized body',
      );
    });

    test('a body exactly at the cap is accepted', () async {
      // Boundary: the cap is inclusive, so length == maxBytes must pass.
      final body = _vless('a.com');
      final result = await SubscriptionFetcher(
        transport: FakeTransport.ok(body),
      ).fetchSubscription(
        Uri.parse('https://sub.example.com/list'),
        maxBytes: utf8.encode(body).length,
      );
      expect(result.isOk, isTrue);
    });

    test('one byte over the cap is rejected', () async {
      final body = _vless('a.com');
      final result = await SubscriptionFetcher(
        transport: FakeTransport.ok(body),
      ).fetchSubscription(
        Uri.parse('https://sub.example.com/list'),
        maxBytes: utf8.encode(body).length - 1,
      );
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SubscriptionParseResult, ConfigParseError>).error,
        isA<InputTooLargeError>(),
      );
    });
  });

  group('timeout', () {
    test('a stalled request returns NetworkTimeoutError', () async {
      final fetcher = SubscriptionFetcher(transport: FakeTransport.hang());
      final result = await fetcher.fetchSubscription(
        Uri.parse('https://sub.example.com/list'),
        timeout: const Duration(milliseconds: 120),
      );
      expect(result.isErr, isTrue);
      final error =
          (result as Err<SubscriptionParseResult, ConfigParseError>).error;
      expect(error, isA<NetworkTimeoutError>());
      expect(error.code, 'network_timeout');
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('HTTP status handling', () {
    for (final code in [301, 400, 403, 404, 429, 500, 503]) {
      test('status $code is surfaced as HttpStatusError', () async {
        final result = await SubscriptionFetcher(
          transport: FakeTransport.status(code),
        ).fetchSubscription(Uri.parse('https://sub.example.com/list'));
        expect(result.isErr, isTrue);
        final error =
            (result as Err<SubscriptionParseResult, ConfigParseError>).error;
        if (code == 301) {
          // A 301 with no Location header is not actionable.
          expect(error, isA<HttpStatusError>());
        } else {
          expect(error, isA<HttpStatusError>());
          expect((error as HttpStatusError).statusCode, code);
        }
      });
    }

    test('a transport exception becomes NetworkFailureError', () async {
      final result = await SubscriptionFetcher(
        transport: FakeTransport.throws(),
      ).fetchSubscription(Uri.parse('https://sub.example.com/list'));
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SubscriptionParseResult, ConfigParseError>).error,
        isA<NetworkFailureError>(),
      );
    });
  });

  group('redirects', () {
    RedirectTransport chain(List<String> locations) => RedirectTransport(
      locations
          .map((l) => TransportResponse(
                statusCode: 302,
                headers: {'location': l},
                body: const Stream<List<int>>.empty(),
              ))
          .toList(),
    );

    test('follows a redirect and returns the final body', () async {
      final transport = RedirectTransport([
        TransportResponse(
          statusCode: 302,
          headers: {'location': 'https://cdn.example.com/final'},
          body: const Stream<List<int>>.empty(),
        ),
      ], finalBody: _vless('a.com'));
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('https://sub.example.com/list'));
      expect(result.isOk, isTrue);
      expect(transport.requestedUris.map((u) => u.host),
          ['sub.example.com', 'cdn.example.com']);
    });

    test('caps the redirect chain at maxRedirects', () async {
      final transport = chain(List.filled(20, 'https://sub.example.com/next'));
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('https://sub.example.com/list'));
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SubscriptionParseResult, ConfigParseError>).error,
        isA<TooManyRedirectsError>(),
      );
      // maxRedirects + the initial request.
      expect(transport.requestedUris, hasLength(maxRedirects + 1));
    });

    test('refuses a redirect that downgrades to http', () async {
      final transport = RedirectTransport([
        TransportResponse(
          statusCode: 302,
          headers: {'location': 'http://evil.example.com/list'},
          body: const Stream<List<int>>.empty(),
        ),
      ], finalBody: _vless('a.com'));
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('https://sub.example.com/list'));
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SubscriptionParseResult, ConfigParseError>).error,
        isA<InsecureTransportError>(),
        reason: 'a redirect must not downgrade to plaintext',
      );
    });

    test('a relative redirect Location resolves against the current URL',
        () async {
      final transport = RedirectTransport([
        TransportResponse(
          statusCode: 302,
          headers: {'location': '/v2/list'},
          body: const Stream<List<int>>.empty(),
        ),
      ], finalBody: _vless('a.com'));
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('https://sub.example.com/v1/list'));
      expect(result.isOk, isTrue);
      expect(
        transport.requestedUris.last.toString(),
        'https://sub.example.com/v2/list',
      );
    });
  });

  group('headers', () {
    test('sends the default User-Agent', () async {
      final transport = FakeTransport.ok(_vless('a.com'));
      await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('https://sub.example.com/list'));
      expect(transport.sentHeaders.single['user-agent'], 'BrickVPN/1.0');
    });

    test('a caller-supplied User-Agent overrides the default', () async {
      final transport = FakeTransport.ok(_vless('a.com'));
      await SubscriptionFetcher(transport: transport).fetchSubscription(
        Uri.parse('https://sub.example.com/list'),
        headers: {'User-Agent': 'CustomAgent/9.9'},
      );
      expect(transport.sentHeaders.single['user-agent'], 'CustomAgent/9.9');
    });

    test('extra headers are forwarded, keys lower-cased', () async {
      final transport = FakeTransport.ok(_vless('a.com'));
      await SubscriptionFetcher(transport: transport).fetchSubscription(
        Uri.parse('https://sub.example.com/list'),
        headers: {'X-Custom': 'value'},
      );
      expect(transport.sentHeaders.single['x-custom'], 'value');
    });
  });

  group('decoding', () {
    test('invalid UTF-8 returns ResponseDecodingError', () async {
      final transport = FakeTransport.bytes([0xC3, 0x28, 0xA0, 0xA1]);
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('https://sub.example.com/list'));
      expect(result.isErr, isTrue);
      expect(
        (result as Err<SubscriptionParseResult, ConfigParseError>).error,
        isA<ResponseDecodingError>(),
      );
    });

    test('a UTF-8 BOM is tolerated', () async {
      final body = _vless('a.com');
      final withBom = [0xEF, 0xBB, 0xBF, ...utf8.encode(body)];
      final transport = FakeTransport.bytes(withBom);
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('https://sub.example.com/list'));
      expect(result.isOk, isTrue);
      expect(
        (result as Ok<SubscriptionParseResult, ConfigParseError>).value.configs,
        hasLength(1),
      );
    });
  });

  group('SECURITY: no credentials leak', () {
    const token = 'CANARY_TOKEN_a1b2c3d4e5';

    test('a token in the URL never reaches an error message', () async {
      final cases = <SubscriptionTransport>[
        FakeTransport.status(500),
        FakeTransport.status(404),
        FakeTransport.throws(),
        FakeTransport.hang(),
        ChainedDowngradeTransport(),
      ];
      for (final transport in cases) {
        final result = await SubscriptionFetcher(transport: transport)
            .fetchSubscription(
              Uri.parse('https://sub.example.com/list?token=$token'),
              timeout: const Duration(milliseconds: 120),
            );
        expect(result.isErr, isTrue, reason: 'expected an error');
        final error =
            (result as Err<SubscriptionParseResult, ConfigParseError>).error;
        expect(error.message.contains(token), isFalse,
            reason: 'token leaked via ${error.code}');
        expect(error.code.contains(token), isFalse);
      }
    });

    test('a token in the host never reaches an error message', () async {
      final result = await SubscriptionFetcher(
        transport: FakeTransport.status(403),
      ).fetchSubscription(
        Uri.parse('http://$token.example.com/list'),
      );
      final error = (result as Err<SubscriptionParseResult, ConfigParseError>).error;
      expect(error.message.contains(token), isFalse);
    });

    test('an exception message from the transport is not propagated', () async {
      // The real SocketException message includes the host.
      final transport = ThrowingTransport(const SocketException(
        'Connection failed: sub.example.com, token=$token',
      ));
      final result = await SubscriptionFetcher(transport: transport)
          .fetchSubscription(Uri.parse('https://sub.example.com/list'));
      final error = (result as Err<SubscriptionParseResult, ConfigParseError>).error;
      expect(error.message.contains(token), isFalse);
      expect(error.message.contains('sub.example.com'), isFalse);
    });

    test('no badCertificateCallback-style TLS override exists', () {
      // Guards against a future edit weakening certificate validation.
      // Comments and doc comments are stripped first, otherwise this guard
      // would match its own explanatory prose.
      final source = File(
        'lib/src/subscription/subscription_fetcher.dart',
      ).readAsStringSync();
      final code = source
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//.*'), '');
      expect(code.contains('badCertificateCallback'), isFalse);
      expect(code.contains('SecurityContext'), isFalse);
      expect(code.contains('withTrustedRoots'), isFalse);
    });
  });

  group('HttpClientTransport against a real loopback server', () {
    late HttpServer server;

    Future<void> serve(
      Future<void> Function(HttpRequest) handler,
    ) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        try {
          await handler(req);
        } on Object {
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
        }
      });
    }

    tearDown(() async => server.close(force: true));

    test('returns the status and body of a real response', () async {
      await serve((req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.text
          ..write('hello from loopback');
        await req.response.close();
      });

      final transport = HttpClientTransport();
      addTearDown(transport.close);
      final response = await transport.send(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        const {'user-agent': 'BrickVPN/1.0'},
      );

      expect(response.statusCode, 200);
      final bytes = await response.body.expand((c) => c).toList();
      expect(utf8.decode(bytes), 'hello from loopback');
    });

    test('does NOT follow redirects itself (policy stays in the fetcher)',
        () async {
      await serve((req) async {
        req.response
          ..statusCode = 302
          ..headers.set('location', 'http://127.0.0.1:${server.port}/final');
        await req.response.close();
      });

      final transport = HttpClientTransport();
      addTearDown(transport.close);
      final response = await transport.send(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        const {},
      );
      expect(response.statusCode, 302);
      expect(response.location, isNotNull);
    });
  });
}

/// Serves a scripted sequence of redirects, then [finalBody].
class RedirectTransport implements SubscriptionTransport {
  RedirectTransport(this.responses, {this.finalBody = ''});

  final List<TransportResponse> responses;
  final String finalBody;
  final List<Uri> requestedUris = [];
  int _call = 0;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async {
    requestedUris.add(uri);
    if (_call < responses.length) {
      return responses[_call++];
    }
    return TransportResponse(
      statusCode: 200,
      headers: const {},
      body: Stream<List<int>>.value(utf8.encode(finalBody)),
    );
  }

  @override
  void close() {}
}

/// Redirects straight to an http:// URL.
class ChainedDowngradeTransport implements SubscriptionTransport {
  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async {
    return TransportResponse(
      statusCode: 302,
      headers: const {'location': 'http://evil.example.com/'},
      body: const Stream<List<int>>.empty(),
    );
  }

  @override
  void close() {}
}

/// Throws a specific, message-bearing exception.
class ThrowingTransport implements SubscriptionTransport {
  ThrowingTransport(this.error);
  final Object error;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async =>
      throw error;

  @override
  void close() {}
}


