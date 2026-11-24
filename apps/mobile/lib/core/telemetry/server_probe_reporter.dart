// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mobile/core/telemetry/server_probe_report.dart';

/// Sends one encoded batch to [endpoint]. Injected in tests so the reporter can
/// be proven deterministic without any socket.
typedef ServerProbeTransport = Future<void> Function(
  Uri endpoint,
  String jsonBody,
);

/// Fire-and-forget, censorship-resilient uploader for anonymous probe reports.
///
/// ============================================================================
/// SAFETY CONTRACT — FOUR GATES BEFORE ANY BYTE LEAVES THE DEVICE
/// ============================================================================
/// 1. Opt-in: nothing is buffered or sent unless `isEnabled()` returns `true`.
/// 2. Endpoint: HTTPS only, non-empty host, no userinfo, and no loopback,
///    private or link-local literal address (blocks cleartext leaks and SSRF).
/// 3. Rate limit + batch cap: at most one flush per [minFlushInterval] and at
///    most [maxBatchSize] reports per request; the queue is ring-capped, so
///    offline memory stays tiny.
/// 4. Resilience: a 3-second timeout, standard `dart:io` `HttpClient`, minimal
///    headers (no device/app fingerprint), and every I/O path wrapped in
///    `try / on Object`. A blocked, censored or unreachable collector can
///    never throw, never log an endpoint, and never delay a VPN connection.
///
/// The collector URL comes from `--dart-define=BRICK_PROBE_ENDPOINT=...`. It is
/// empty in every shipped build until the owner configures one, so the default
/// posture is zero outbound traffic even if a user opts in.
/// ============================================================================
class ServerProbeReporter {
  /// Creates a reporter.
  ///
  /// [isEnabled] is read on every call, so toggling the Settings switch takes
  /// effect immediately without rebuilding any provider graph.
  ServerProbeReporter({
    required this.isEnabled,
    Uri? endpoint,
    ServerProbeTransport? transport,
    this.minFlushInterval = const Duration(seconds: 60),
    this.maxBatchSize = 20,
    DateTime Function()? clock,
  }) : _endpoint = endpoint ?? endpointFromEnvironment(),
       _transport = transport ?? _httpTransport,
       _clock = clock ?? DateTime.now;

  /// Opt-in predicate, read on every submit/flush.
  final bool Function() isEnabled;

  /// Hard ceiling for a single flush; a slow collector never holds anything.
  static const Duration requestTimeout = Duration(seconds: 3);

  /// Dart-define key holding the optional collector URL.
  static const String endpointEnvironmentKey = 'BRICK_PROBE_ENDPOINT';

  /// Minimum delay between flushes.
  final Duration minFlushInterval;

  /// Maximum reports per request (also the queue capacity).
  final int maxBatchSize;

  final Uri? _endpoint;
  final ServerProbeTransport _transport;
  final DateTime Function() _clock;
  final List<ServerProbeReport> _queue = <ServerProbeReport>[];
  DateTime? _lastFlushAt;
  bool _inFlight = false;

  /// The configured collector, or `null` when none was compiled in.
  ///
  /// Exposed for configuration assertions only; it is never logged.
  Uri? get endpoint => _endpoint;

  /// Number of reports currently buffered (bounded by [maxBatchSize]).
  int get pendingCount => _queue.length;

  /// Reads the optional collector URL from `BRICK_PROBE_ENDPOINT`.
  static Uri? endpointFromEnvironment() {
    const raw = String.fromEnvironment(endpointEnvironmentKey);
    if (raw.trim().isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) {
      return null;
    }
    return parsed;
  }

  /// Whether [uri] is an acceptable collector target.
  ///
  /// Rejects anything that is not HTTPS, has no host, carries userinfo, or
  /// points at loopback / private / link-local space.
  static bool isSecureEndpoint(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') {
      return false;
    }
    if (uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) {
      return false;
    }
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return false;
    }
    final address = InternetAddress.tryParse(host);
    if (address != null && _isBlockedAddress(address)) {
      return false;
    }
    return true;
  }

  /// Records [report] and attempts a flush. Never throws.
  ///
  /// Returns the number of reports actually delivered (0 when any gate blocks).
  Future<int> submit(ServerProbeReport report) async {
    if (!isEnabled()) {
      // Not opted in: wipe anything still buffered and never buffer this
      // report. Nothing about a user's servers is retained for later
      // transmission.
      _queue.clear();
      return 0;
    }
    final target = _endpoint;
    if (target == null || !isSecureEndpoint(target)) {
      // No usable collector: buffering would only retain data for a send that
      // can never happen, so drop it immediately.
      return 0;
    }
    _enqueue(report);
    return await flush();
  }

  /// Fire-and-forget variant: schedules [submit] without awaiting it.
  void record(ServerProbeReport report) {
    unawaited(submit(report));
  }

  /// Flushes the buffered batch if every gate allows it. Never throws.
  Future<int> flush() async {
    try {
      if (!isEnabled()) {
        // Checked BEFORE the in-flight guard: turning the switch off must wipe
        // the queue immediately even while an earlier request is still open.
        // When that request completes, `removeWhere` over an empty queue is a
        // safe no-op.
        _queue.clear();
        return 0;
      }
      if (_inFlight) {
        // An overlapping flush would resend the same reports and race the
        // queue bookkeeping; let the in-progress send finish first.
        return 0;
      }
      final target = _endpoint;
      if (target == null || !isSecureEndpoint(target)) {
        return 0;
      }
      if (_queue.isEmpty) {
        return 0;
      }
      final now = _clock();
      final last = _lastFlushAt;
      if (last != null && now.difference(last) < minFlushInterval) {
        return 0;
      }

      final batch = _queue.take(maxBatchSize).toList(growable: false);
      // Count the attempt, not just successes, so a failing collector cannot
      // be retried faster than the opt-in user agreed to.
      _lastFlushAt = now;
      final body = jsonEncode(<String, Object?>{
        'reports': <Map<String, Object?>>[
          for (final report in batch) report.toJson(),
        ],
      });

      _inFlight = true;
      try {
        // A timed-out or non-2xx request is NOT a delivery: it throws, so the
        // batch stays queued and nothing is counted.
        await _transport(target, body).timeout(requestTimeout);
      } on Object {
        return 0;
      } finally {
        _inFlight = false;
      }

      // Remove exactly the reports that were sent. The ring cap may have
      // evicted the head while the request was in flight, so removing by
      // position would silently discard a report that was never transmitted.
      _queue.removeWhere((item) => batch.any((sent) => identical(sent, item)));
      return batch.length;
    } on Object {
      // Blocked, censored, offline, malformed response: stay silent. Reports
      // remain queued (ring-capped) for the next permitted attempt.
      return 0;
    }
  }

  void _enqueue(ServerProbeReport report) {
    _queue.add(report);
    if (_queue.length > maxBatchSize) {
      _queue.removeRange(0, _queue.length - maxBatchSize);
    }
  }

  /// The real `dart:io` transport.
  ///
  /// Public only so a test can prove the header and status-code behaviour
  /// against a real loopback socket instead of a closure. Annotated
  /// [visibleForTesting] so production code cannot call it directly and bypass
  /// the `isSecureEndpoint()` gate.
  @visibleForTesting
  static Future<void> httpTransport(Uri endpoint, String jsonBody) {
    return _httpTransport(endpoint, jsonBody);
  }

  static Future<void> _httpTransport(Uri endpoint, String jsonBody) async {
    final client = HttpClient()
      ..connectionTimeout = requestTimeout
      // dart:io otherwise sends `User-Agent: Dart/3.x (dart:io)`, a library
      // and version fingerprint the contract forbids.
      ..userAgent = null;
    try {
      final request = await client.postUrl(endpoint);
      // A redirect could downgrade to cleartext or land on internal space,
      // bypassing `isSecureEndpoint()` entirely. Never follow one.
      request
        ..followRedirects = false
        ..maxRedirects = 0;
      // Minimal headers only: no app version, device model, locale or any
      // other fingerprint.
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.removeAll(HttpHeaders.userAgentHeader);
      request.add(utf8.encode(jsonBody));
      final response = await request.close();
      final status = response.statusCode;
      await response.drain<void>();
      if (status < 200 || status >= 300) {
        // A DPI block page (403 / 429 / 502) is not a delivery: throwing keeps
        // the batch queued so `flush()` returns 0 and drops nothing.
        throw HttpException('Collector returned HTTP $status');
      }
    } finally {
      client.close(force: true);
    }
  }

  static bool _isBlockedAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length == 4) {
      return _isBlockedIpv4(bytes);
    }
    if (bytes.length == 16) {
      // `::ffff:0:0/96` IPv4-mapped: judge the embedded IPv4 address, or
      // `https://[::ffff:127.0.0.1]/` would slip past every IPv4 rule.
      final isIpv4Mapped =
          bytes.take(10).every((byte) => byte == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff;
      if (isIpv4Mapped) {
        return _isBlockedIpv4(bytes.sublist(12));
      }
      // `::` and `::1`.
      final highBytesZero = bytes.take(15).every((byte) => byte == 0);
      if (highBytesZero && bytes[15] <= 1) {
        return true;
      }
      // `fc00::/7` unique-local.
      if ((bytes[0] & 0xfe) == 0xfc) {
        return true;
      }
      // `fe80::/10` link-local.
      if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) {
        return true;
      }
      // `ff00::/8` multicast.
      if (bytes[0] == 0xff) {
        return true;
      }
      return false;
    }
    return true;
  }

  static bool _isBlockedIpv4(List<int> bytes) {
    final a = bytes[0];
    final b = bytes[1];
    if (a == 0 || a == 10 || a == 127) {
      return true;
    }
    // `100.64.0.0/10` carrier-grade NAT.
    if (a == 100 && b >= 64 && b <= 127) {
      return true;
    }
    if (a == 172 && b >= 16 && b <= 31) {
      return true;
    }
    if (a == 192 && b == 168) {
      return true;
    }
    if (a == 169 && b == 254) {
      return true;
    }
    // `224.0.0.0/4` multicast plus reserved and broadcast space.
    if (a >= 224) {
      return true;
    }
    return false;
  }
}
