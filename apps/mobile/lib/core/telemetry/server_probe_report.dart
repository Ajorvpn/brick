// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

/// Coarse network class attached to an anonymous probe report.
///
/// Deliberately only three values: the collector learns "was this roughly
/// Wi-Fi or cellular", never an SSID, BSSID, carrier, IP address or any other
/// identifying network detail.
enum ProbeNetworkType {
  /// Wi-Fi transport.
  wifi('wifi'),

  /// Mobile/cellular transport.
  cellular('cellular'),

  /// Anything else (Ethernet, VPN-only, unknown).
  other('other');

  ProbeNetworkType(this.wireValue);

  /// The exact string used on the wire.
  final String wireValue;
}

/// A single anonymous server-health measurement.
///
/// ============================================================================
/// PRIVACY CONTRACT — STRICT 5-KEY ALLOWLIST
/// ============================================================================
/// [toJson] emits exactly five keys and nothing else. There is no field for a
/// hostname, IP, port, UUID, password, private key, server remark, device
/// identifier, advertising ID, user identifier, app version, or locale — such
/// data simply cannot be represented by this type, so it cannot leak.
///
/// - `node_hash`: first 16 lowercase hex chars of SHA-256 over the canonical
///   `protocol|host|port` tuple. A stable, non-reversible server identity.
/// - `ok`: whether the reachability probe succeeded.
/// - `latency_ms`: rounded-trip latency clamped to `0..30000`, always `null`
///   when the probe failed (a failed probe has no latency to report).
/// - `network_type`: [ProbeNetworkType] wire value.
/// - `hour_utc`: UTC timestamp truncated to the hour (`YYYY-MM-DDTHH:00:00Z`)
///   so requests cannot be correlated across a day by exact timing.
/// ============================================================================
@immutable
class ServerProbeReport {
  const ServerProbeReport._({
    required this.nodeHash,
    required this.ok,
    required this.latencyMs,
    required this.networkType,
    required this.hourUtc,
  });

  /// Builds a report, applying every privacy rule at construction time.
  ///
  /// [latencyMs] is clamped to `0..30000` and forced to `null` when [ok] is
  /// `false`; [observedAt] is truncated to its UTC hour. No caller can bypass
  /// these constraints, so an over-eager feature cannot widen the payload.
  factory ServerProbeReport.create({
    required String nodeHash,
    required bool ok,
    int? latencyMs,
    required ProbeNetworkType networkType,
    required DateTime observedAt,
  }) {
    if (!_nodeHashPattern.hasMatch(nodeHash)) {
      throw ArgumentError.value(
        nodeHash,
        'nodeHash',
        'Must be a 16-character lowercase hex SHA-256 prefix',
      );
    }
    return ServerProbeReport._(
      nodeHash: nodeHash,
      ok: ok,
      latencyMs: ok ? _clampLatency(latencyMs) : null,
      networkType: networkType,
      hourUtc: formatHourUtc(observedAt),
    );
  }

  /// Upper bound for [latencyMs]; a probe slower than this is not a useful
  /// signal and a larger number would only describe the user's connection.
  static const int maxLatencyMs = 30000;

  /// The only accepted [nodeHash] shape: a truncated hex digest.
  ///
  /// Enforced at construction so no caller can pass a raw host, IP, UUID or
  /// secret in place of a digest.
  static final RegExp _nodeHashPattern = RegExp(r'^[0-9a-f]{16}$');

  /// First 16 lowercase hex chars of SHA-256 over `protocol|host|port`.
  final String nodeHash;

  /// Whether the probe succeeded.
  final bool ok;

  /// Latency in milliseconds, or `null` when unknown or [ok] is `false`.
  final int? latencyMs;

  /// Coarse network class.
  final ProbeNetworkType networkType;

  /// UTC hour bucket in `YYYY-MM-DDTHH:00:00Z` form.
  final String hourUtc;

  /// The only payload shape this app will ever transmit.
  ///
  /// Exactly five keys: `node_hash`, `ok`, `latency_ms`, `network_type`,
  /// `hour_utc`. Adding a key here is a privacy-policy change, not a code
  /// change.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'node_hash': nodeHash,
      'ok': ok,
      'latency_ms': latencyMs,
      'network_type': networkType.wireValue,
      'hour_utc': hourUtc,
    };
  }

  /// Truncates [timestamp] to its UTC hour and formats it as
  /// `YYYY-MM-DDTHH:00:00Z`.
  static String formatHourUtc(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final bucket = DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
    final year = bucket.year.toString().padLeft(4, '0');
    final month = bucket.month.toString().padLeft(2, '0');
    final day = bucket.day.toString().padLeft(2, '0');
    final hour = bucket.hour.toString().padLeft(2, '0');
    return '$year-$month-${day}T$hour:00:00Z';
  }

  /// Derives the anonymous node identity for a server.
  ///
  /// The digest is taken over
  /// `'${protocol.toLowerCase().trim()}|${host.toLowerCase().trim()}|$port'`
  /// and truncated to its first 16 hex characters, so casing or stray
  /// whitespace on either field cannot mint a second identity for one server.
  /// The host is never stored, transmitted, or logged: only this irreversible
  /// digest leaves the device.
  static String computeNodeHash({
    required String protocol,
    required String host,
    required int port,
  }) {
    final canonical =
        '${protocol.toLowerCase().trim()}|${host.toLowerCase().trim()}|$port';
    final digest = _sha256(utf8.encode(canonical));
    final hex = StringBuffer();
    for (final byte in digest) {
      hex.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString().substring(0, 16);
  }

  static int? _clampLatency(int? value) {
    if (value == null) {
      return null;
    }
    return value.clamp(0, maxLatencyMs);
  }
}

/// Round constants for SHA-256 (FIPS 180-4 Section 4.2.2).
const List<int> _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, //
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, //
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, //
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, //
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, //
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, //
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, //
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, //
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, //
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, //
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, //
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, //
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, //
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, //
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2, //
];

const int _mask32 = 0xffffffff;

int _rotr(int value, int bits) {
  return ((value >> bits) | (value << (32 - bits))) & _mask32;
}

/// Self-contained FIPS 180-4 SHA-256.
///
/// Implemented locally instead of adding `package:crypto`, because this
/// payload is a 16-hex-char digest and a new dependency would be a permanent
/// supply-chain and reproducibility cost for one hash.
List<int> _sha256(List<int> message) {
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;

  final bitLength = message.length * 8;
  final padded = <int>[...message, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  for (var shift = 56; shift >= 0; shift -= 8) {
    padded.add((bitLength >> shift) & 0xff);
  }

  final w = List<int>.filled(64, 0);
  for (var offset = 0; offset < padded.length; offset += 64) {
    for (var t = 0; t < 16; t++) {
      final i = offset + t * 4;
      w[t] =
          (padded[i] << 24) |
          (padded[i + 1] << 16) |
          (padded[i + 2] << 8) |
          padded[i + 3];
    }
    for (var t = 16; t < 64; t++) {
      final s0 = _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ (w[t - 15] >> 3);
      final s1 = _rotr(w[t - 2], 17) ^ _rotr(w[t - 2], 19) ^ (w[t - 2] >> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & _mask32;
    }

    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    var f = h5;
    var g = h6;
    var h = h7;

    for (var t = 0; t < 64; t++) {
      final sigma1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final choose = (e & f) ^ ((~e & _mask32) & g);
      final temp1 = (h + sigma1 + choose + _k[t] + w[t]) & _mask32;
      final sigma0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (sigma0 + majority) & _mask32;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & _mask32;
    }

    h0 = (h0 + a) & _mask32;
    h1 = (h1 + b) & _mask32;
    h2 = (h2 + c) & _mask32;
    h3 = (h3 + d) & _mask32;
    h4 = (h4 + e) & _mask32;
    h5 = (h5 + f) & _mask32;
    h6 = (h6 + g) & _mask32;
    h7 = (h7 + h) & _mask32;
  }

  final digest = <int>[];
  for (final word in <int>[h0, h1, h2, h3, h4, h5, h6, h7]) {
    digest
      ..add((word >> 24) & 0xff)
      ..add((word >> 16) & 0xff)
      ..add((word >> 8) & 0xff)
      ..add(word & 0xff);
  }
  return digest;
}
