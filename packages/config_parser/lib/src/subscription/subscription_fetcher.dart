// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

import '../config_parse_error.dart';
import '../defensive_parser_utils.dart' show maxSubscriptionLength;
import 'subscription_parser.dart';

/// Default `User-Agent` sent with every subscription request.
const String defaultSubscriptionUserAgent = 'BrickVPN/1.0';

/// Default deadline for a whole subscription fetch, including redirects.
///
/// **Why 10 seconds.** A subscription is a small, static document on a CDN,
/// not a stream: on a healthy mobile connection it arrives in well under a
/// second. Ten seconds is generous enough to absorb a slow-but-progressing
/// TLS handshake and a cold DNS lookup on a poor network, while still
/// bounding the worst case so a black-holed connection cannot hold a user on a
/// spinner. The deadline covers the *entire* fetch, all redirects and body
/// reads combined, not each hop — otherwise a 5-redirect chain could take 5x
/// the intended wait.
const Duration defaultFetchTimeout = Duration(seconds: 10);

/// Maximum number of HTTP redirects followed before giving up.
///
/// **Why 5.** Real providers occasionally chain a couple of CDN redirects; a
/// limit of 5 covers that comfortably. A larger number buys nothing for a
/// legitimate user and only widens the loop an attacker gets for free, since
/// the redirect chain is entirely server-controlled.
const int maxRedirects = 5;

/// A single HTTP response, as returned by a [SubscriptionTransport].
final class TransportResponse {
  /// Creates a transport response.
  const TransportResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// The HTTP status code.
  final int statusCode;

  /// Response headers, with lower-cased keys.
  final Map<String, String> headers;

  /// The response body, delivered as a byte stream so the caller can enforce
  /// a size cap *incrementally* instead of buffering first.
  final Stream<List<int>> body;

  /// The `Location` header, if the response is a redirect.
  String? get location => headers['location'];
}

/// The seam that makes this testable offline.
///
/// Implementations perform exactly **one** HTTP round trip and must **not**
/// follow redirects themselves. Keeping redirect handling in the fetcher is
/// deliberate: the HTTPS-only rule has to be re-checked on every hop, and a
/// transport that followed redirects internally would silently downgrade
/// `https` to `http` before the fetcher ever saw it.
abstract interface class SubscriptionTransport {
  /// Performs one request to [uri] with [headers] and returns the response.
  ///
  /// Implementations should throw on transport failure; the fetcher maps any
  /// thrown object to a `NetworkFailureError` so that no exception string
  /// (which can embed the host, and therefore the subscription token) escapes.
  Future<TransportResponse> send(Uri uri, Map<String, String> headers);

  /// Releases any underlying resources.
  void close();
}

/// The production [SubscriptionTransport], backed by `dart:io`'s
/// `HttpClient`.
///
/// This is the only place in the package that performs network I/O. TLS
/// certificate validation is left entirely at the platform default: there is
/// deliberately no `badCertificateCallback` override anywhere in this file.
final class HttpClientTransport implements SubscriptionTransport {
  /// Creates a transport, optionally over an injected [client] (for tests).
  HttpClientTransport({HttpClient? client}) : _client = client ?? HttpClient() {
    // Do not let the OS pool connections indefinitely for a client that is
    // used once per fetch.
    _client.connectionTimeout = defaultFetchTimeout;
  }

  final HttpClient _client;

  /// Copies [headers] with lower-cased keys and first-value-wins semantics,
  /// so callers can look a header up case-insensitively as HTTP requires.
  static Map<String, String> _lowercaseHeaders(HttpHeaders headers) {
    final out = <String, String>{};
    // `HttpHeaders.forEach` yields (name, values) with a List<String> value.
    headers.forEach((name, values) {
      if (values.isNotEmpty) {
        out[name.toLowerCase()] = values.first;
      }
    });
    return out;
  }

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async {
    final request = await _client.getUrl(uri);
    // Security policy lives in the fetcher; see the interface doc.
    request.followRedirects = false;
    request.maxRedirects = 0;
    headers.forEach(request.headers.set);
    final response = await request.close();
    return TransportResponse(
      statusCode: response.statusCode,
      headers: _lowercaseHeaders(response.headers),
      body: response,
    );
  }

  @override
  void close() => _client.close(force: true);
}

/// Fetches a subscription over HTTPS and parses it.
///
/// This is the network half of subscription support, kept strictly separate
/// from the pure parsing in `parseSubscription` (`SECURITY.md` §5). Every
/// failure is an `Err`; nothing here throws, and no URL, host, header value or
/// response byte is ever stored in an error, because a subscription URL
/// normally embeds an access token.
final class SubscriptionFetcher {
  /// Creates a fetcher over [transport], defaulting to a real HTTP client.
  SubscriptionFetcher({SubscriptionTransport? transport})
    : _transport = transport ?? HttpClientTransport();

  final SubscriptionTransport _transport;

  /// Fetches [url] and parses the body into a [SubscriptionParseResult].
  ///
  /// Enforces, in order: HTTPS-only scheme (on the initial URL *and* every
  /// redirect hop), a whole-fetch [timeout], a [maxBytes] cap applied
  /// incrementally to the response stream, a 200-only status check, and a
  /// redirect limit of [maxRedirects].
  ///
  /// [headers] are merged over the defaults, so a caller can add (or
  /// override) headers such as `User-Agent`. [userInfoHeaderValue] is passed
  /// through to the parser so quota metadata survives the round trip.
  Future<Result<SubscriptionParseResult, ConfigParseError>> fetchSubscription(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = defaultFetchTimeout,
    int maxBytes = maxSubscriptionLength,
    String? userInfoHeaderValue,
  }) async {
    final schemeCheck = _requireHttps(url);
    if (schemeCheck case Err(:final error)) {
      return Err(error);
    }

    final requestHeaders = <String, String>{
      'user-agent': defaultSubscriptionUserAgent,
      'accept': '*/*',
      if (headers != null)
        ...headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
    };

    try {
      for (var hop = 0; hop <= maxRedirects; hop++) {
        final sent = await _send(url, requestHeaders, timeout);
        if (sent case Err(:final error)) {
          return Err(error);
        }
        final response =
            (sent as Ok<TransportResponse, ConfigParseError>).value;

        if (_isRedirect(response.statusCode)) {
          final location = response.location;
          if (location == null || location.isEmpty) {
            return Err<SubscriptionParseResult, ConfigParseError>(
              // A redirect with no Location is not actionable; report the
              // status itself rather than inventing a failure.
              HttpStatusError(response.statusCode),
            );
          }
          final next = url.resolve(location);
          // Re-check HTTPS on every hop: a redirect must not be able to
          // downgrade the connection to plaintext.
          final hopCheck = _requireHttps(next);
          if (hopCheck case Err(:final error)) {
            return Err(error);
          }
          // Drain and discard the redirect body so the socket can be reused
          // and no stray bytes are read.
          await response.body.drain<void>();
          url = next;
          continue;
        }

        if (response.statusCode != HttpStatus.ok) {
          await response.body.drain<void>();
          return Err<SubscriptionParseResult, ConfigParseError>(
            HttpStatusError(response.statusCode),
          );
        }

        final bodyResult = await _readBounded(response.body, maxBytes);
        if (bodyResult case Err(:final error)) {
          return Err(error);
        }
        final text = (bodyResult as Ok<String, ConfigParseError>).value;
        return parseSubscription(
          text,
          userInfoHeaderValue:
              userInfoHeaderValue ?? _userInfoFrom(response.headers),
        );
      }
    } on TimeoutException {
      // Defensive: the send path converts its own timeout. A stray one can
      // still surface from redirect resolution or the body reader.
      return Err(NetworkTimeoutError('subscription fetch', timeout));
    } on Object {
      // Deliberately discard the exception object: `dart:io` messages embed
      // the host, and a host is part of a credential-bearing URL.
      return Err(NetworkFailureError('the request could not be completed'));
    }

    return Err(TooManyRedirectsError(maxRedirects));
  }

  /// Pulls the `Subscription-Userinfo` header, if the server sent one.
  ///
  /// The content type is deliberately ignored: providers frequently serve a
  /// base64 subscription as `application/octet-stream` or mislabel it
  /// entirely, and the parser sniffs the payload anyway. Gating quota parsing
  /// on a content type would silently drop usage data.
  String? _userInfoFrom(Map<String, String> headers) =>
      headers['subscription-userinfo'];

  /// Sends one request, converting both a deadline breach and any transport
  /// exception into a typed error.
  ///
  /// Returning a `Result` rather than throwing keeps the "this file contains
  /// no `throw`" property literally true, rather than merely true in effect.
  /// The exception object is deliberately discarded: a `dart:io` message
  /// embeds the host, and a subscription host is part of a credential-bearing
  /// URL.
  Future<Result<TransportResponse, ConfigParseError>> _send(
    Uri url,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    try {
      return Ok(await _transport.send(url, headers).timeout(timeout));
    } on TimeoutException {
      return Err(NetworkTimeoutError('subscription fetch', timeout));
    } on Object {
      return Err(NetworkFailureError('the request could not be completed'));
    }
  }

  /// Reads [stream], aborting as soon as more than [maxBytes] have arrived.
  ///
  /// The cap is checked per chunk and the subscription is cancelled
  /// immediately on breach, so a hostile server streaming an endless body is
  /// cut off after `maxBytes` rather than after exhausting memory.
  Future<Result<String, ConfigParseError>> _readBounded(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    late final StreamSubscription<List<int>> subscription;
    final completer = Completer<Result<String, ConfigParseError>>();

    subscription = stream.listen(
      (chunk) {
        total += chunk.length;
        if (total > maxBytes) {
          if (!completer.isCompleted) {
            completer.complete(
              Err(
                InputTooLargeError(
                  actualLength: total,
                  maxLength: maxBytes,
                  what: 'subscription body',
                ),
              ),
            );
          }
          unawaited(subscription.cancel());
          return;
        }
        builder.add(chunk);
      },
      onError: (Object _) {
        if (!completer.isCompleted) {
          // Response body bytes are untrusted and may echo the request URL.
          completer.complete(
            Err(NetworkFailureError('the response stream failed')),
          );
        }
      },
      onDone: () {
        if (completer.isCompleted) return;
        try {
          final bytes = builder.takeBytes();
          completer.complete(Ok<String, ConfigParseError>(_decodeUtf8(bytes)));
        } on FormatException {
          completer.complete(
            const Err(ResponseDecodingError('subscription body')),
          );
        }
      },
      cancelOnError: false,
    );

    return completer.future;
  }

  /// Decodes strictly as UTF-8, tolerating only a leading BOM.
  String _decodeUtf8(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }
    return utf8.decode(bytes);
  }

  static bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently || // 301
      status == HttpStatus.found || // 302
      status == HttpStatus.seeOther || // 303
      status == HttpStatus.temporaryRedirect || // 307
      status == HttpStatus.permanentRedirect; // 308

  static Result<void, ConfigParseError> _requireHttps(Uri url) {
    if (url.scheme.toLowerCase() == 'https') {
      return const Ok(null);
    }
    return Err(InsecureTransportError(url.scheme));
  }

  /// Closes the underlying transport.
  void close() => _transport.close();
}
