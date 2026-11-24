// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

/// Stable subscription identifier of the built-in official server directory.
///
/// Every synced profile is tagged with this identifier so a later sync can
/// atomically replace exactly the directory's servers and nothing else.
const String kBuiltInDirectorySubscriptionId = 'brick_official_directory';

/// Display name of the built-in official server directory.
const String kBuiltInDirectoryName = 'Brick VPN';

/// Primary feed: the publisher's generated `sub` branch (Base64 payload).
///
/// Verified against the live repository: `Ajorvpn/brick-sub-collector` keeps
/// its generated subscription on the `sub` branch, refreshed every 12 hours by
/// `.github/workflows/update.yml`.
const String kBuiltInDirectoryPrimaryUrl =
    'https://raw.githubusercontent.com/Ajorvpn/brick-sub-collector/sub/sub.txt';

/// Censorship-resilient mirror of the same file, served by jsDelivr.
///
/// Used only when the primary host is blocked, slow, or failing.
const String kBuiltInDirectoryMirrorUrl =
    'https://cdn.jsdelivr.net/gh/Ajorvpn/brick-sub-collector@sub/sub.txt';

/// Ordered feed URLs, tried in turn until one yields usable servers.
const List<String> kDefaultBuiltInFeedUrls = <String>[
  kBuiltInDirectoryPrimaryUrl,
  kBuiltInDirectoryMirrorUrl,
];

/// Build-time environment key for overriding the feed URLs.
///
/// Comma-separated absolute HTTPS URLs, e.g.
/// `--dart-define=BRICK_SUB_URLS=https://a.example/sub.txt,https://b.example`.
const String kBuiltInFeedUrlsEnvironmentKey = 'BRICK_SUB_URLS';

/// The `BRICK_SUB_URLS` value compiled into this build (empty when unset).
const String kCompiledBuiltInFeedUrls = String.fromEnvironment(
  kBuiltInFeedUrlsEnvironmentKey,
);

/// Maximum directory payload accepted from a single mirror (2 MiB).
///
/// The real feed is ~10 KiB; the cap exists so a hostile or misconfigured
/// mirror cannot stream an unbounded body into memory.
const int kBuiltInFeedMaxBytes = 2 * 1024 * 1024;

/// Deadline for one mirror attempt, covering the whole fetch.
const Duration kBuiltInFeedTimeout = Duration(seconds: 10);

/// How long a successful directory sync stays fresh before the next automatic
/// background refresh.
const Duration kBuiltInDirectorySyncInterval = Duration(minutes: 30);

/// Hard ceiling on servers imported from one directory payload.
const int kBuiltInFeedMaxServers = 500;

/// Resolves the ordered feed URLs for this build.
///
/// [override] defaults to the compiled `BRICK_SUB_URLS` value. When it holds
/// one or more entries, those replace the compiled-in defaults entirely, so a
/// future server or Pro rollout needs no code change. Every candidate must be
/// an absolute `https` URL with a hostname and no embedded credentials, and a
/// literal loopback/private/link-local/multicast host is rejected:
/// [resolveBuiltInFeedUrls] is the only path a feed URL takes to the network.
///
/// An override whose entries are all invalid falls back to
/// [kDefaultBuiltInFeedUrls] rather than leaving the app with no directory.
List<Uri> resolveBuiltInFeedUrls({String override = kCompiledBuiltInFeedUrls}) {
  final candidates = <String>[
    if (override.trim().isNotEmpty)
      ...override
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
    else
      ...kDefaultBuiltInFeedUrls,
  ];

  final accepted = <Uri>[];
  for (final candidate in candidates) {
    final uri = Uri.tryParse(candidate);
    if (uri == null) continue;
    if (uri.scheme.toLowerCase() != 'https') continue;
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) continue;
    if (isBlockedBuiltInFeedHost(uri.host)) continue;
    accepted.add(uri);
  }

  if (accepted.isEmpty) {
    return List<Uri>.unmodifiable(kDefaultBuiltInFeedUrls.map(Uri.parse));
  }
  return List<Uri>.unmodifiable(accepted);
}

/// Whether [host] is a literal address that must never be fetched.
///
/// Hostnames are allowed through: they are resolved and TLS-verified by the
/// platform, and a hostname that resolves to private space cannot be detected
/// without a DNS lookup of a URL that may itself embed a token. Literal
/// addresses are the case an attacker controls directly, so they are rejected
/// here — loopback, unspecified, private, CGNAT, link-local, multicast and
/// reserved IPv4, plus their IPv6 equivalents including `::ffff:0:0/96`
/// mapped forms.
bool isBlockedBuiltInFeedHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  if (normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized.endsWith('.local')) {
    return true;
  }

  final address = InternetAddress.tryParse(normalized);
  if (address == null) return false;

  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }

  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return _isBlockedIpv4(bytes);
  }
  if (bytes.length != 16) return true;

  // `::ffff:a.b.c.d` (IPv4-mapped): judge the embedded IPv4 address.
  final isMapped =
      bytes[0] == 0 &&
      bytes[1] == 0 &&
      bytes[2] == 0 &&
      bytes[3] == 0 &&
      bytes[4] == 0 &&
      bytes[5] == 0 &&
      bytes[6] == 0 &&
      bytes[7] == 0 &&
      bytes[8] == 0 &&
      bytes[9] == 0 &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (isMapped) {
    return _isBlockedIpv4(bytes.sublist(12));
  }

  // `fc00::/7` unique-local.
  if ((bytes[0] & 0xfe) == 0xfc) return true;
  // `ff00::/8` multicast.
  if (bytes[0] == 0xff) return true;
  // `::` unspecified.
  if (bytes.every((byte) => byte == 0)) return true;

  return false;
}

bool _isBlockedIpv4(List<int> bytes) {
  if (bytes.length != 4) return true;
  final first = bytes[0];
  final second = bytes[1];

  if (first == 0 || first == 10 || first == 127) return true;
  if (first == 169 && second == 254) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  if (first == 192 && second == 168) return true;
  // CGNAT `100.64.0.0/10`.
  if (first == 100 && second >= 64 && second <= 127) return true;
  // Multicast, reserved and broadcast space.
  if (first >= 224) return true;

  return false;
}
