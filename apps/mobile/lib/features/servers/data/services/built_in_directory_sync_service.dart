// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart' show ServerProfile;
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:mobile/features/servers/domain/built_in_feed_config.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

/// Downloads one feed URL and returns its **raw** body.
///
/// Returning the body (rather than a parsed result) lets the caller pair each
/// URI line with its own `#remark`, which is the only place the feed carries
/// country metadata. The returned body is already bounded, HTTPS-only and
/// redirect-checked by [SubscriptionFetcher].
typedef BuiltInFeedFetcher = Future<Result<String, ConfigParseError>> Function(
  Uri uri,
);

/// Supplies the profile repository. Async because the production repository
/// itself is provided as a `FutureProvider`.
typedef BuiltInDirectoryRepositoryLoader =
    Future<ServerProfileRepository> Function();

/// Outcome of one directory sync attempt.
sealed class DirectorySyncResult {
  const DirectorySyncResult();

  /// Number of servers the directory holds after this attempt.
  ///
  /// On a failure this is the number of cached servers that were preserved.
  int get serverCount;

  /// Whether the stored directory is usable after this attempt.
  bool get succeeded;

  /// Whether the attempt was skipped because the cache is still fresh.
  bool get skipped;
}

/// The directory was refreshed from a mirror.
final class DirectorySyncSuccess extends DirectorySyncResult {
  /// Creates a successful sync outcome.
  const DirectorySyncSuccess({
    required this.serverCount,
    required this.skippedLineCount,
  });

  @override
  final int serverCount;

  /// Lines the parser rejected and dropped without failing the sync.
  final int skippedLineCount;

  @override
  bool get succeeded => true;

  @override
  bool get skipped => false;
}

/// Every mirror failed, timed out, or produced no usable servers.
///
/// Nothing was written: the previously cached directory is intact.
final class DirectorySyncFailure extends DirectorySyncResult {
  /// Creates a failed sync outcome carrying [serverCount] cached servers.
  const DirectorySyncFailure({required this.serverCount});

  @override
  final int serverCount;

  @override
  bool get succeeded => false;

  @override
  bool get skipped => false;
}

/// The cache is still fresh, so no network attempt was made.
final class DirectorySyncSkipped extends DirectorySyncResult {
  /// Creates a skipped outcome carrying [serverCount] cached servers.
  const DirectorySyncSkipped({required this.serverCount});

  @override
  final int serverCount;

  @override
  bool get succeeded => true;

  @override
  bool get skipped => true;
}

/// Synchronises the built-in official server directory.
///
/// Contract:
/// - **Cache-first:** the encrypted on-device store is the source of truth.
///   A failed or empty fetch never deletes anything.
/// - **Mirror failover:** feed URLs are tried in order; the first one that
///   yields at least one `sing-box`-compatible server wins.
/// - **Single-flight:** concurrent callers share one in-progress attempt, so a
///   rebuild storm can never double-fetch.
/// - **Throttled:** [syncIfNeeded] returns immediately while the last
///   successful sync is younger than [kBuiltInDirectorySyncInterval], unless
///   nothing is cached at all. [forceSync] always runs.
final class BuiltInDirectorySyncService {
  /// Creates a sync service.
  BuiltInDirectorySyncService({
    required this.loadRepository,
    required this.preferences,
    required this.fetcher,
    List<Uri>? feedUrls,
    this.feedTimeout = kBuiltInFeedTimeout,
    this.clock = DateTime.now,
  }) : _feedUrls = List<Uri>.unmodifiable(feedUrls ?? resolveBuiltInFeedUrls());

  /// Loads the profile repository the directory is written to.
  final BuiltInDirectoryRepositoryLoader loadRepository;

  /// Non-secret preferences holding the sync timestamp and acceptance flag.
  final AppPreferencesRepository preferences;

  /// Remote fetcher, overridden in tests via `builtInFeedFetcherProvider`.
  final BuiltInFeedFetcher fetcher;

  /// Deadline for a single mirror attempt.
  ///
  /// A blackholed host (`raw.githubusercontent.com` under national filtering)
  /// would otherwise hold the sync open indefinitely; timing out makes the
  /// failover to the next mirror deterministic.
  final Duration feedTimeout;

  /// Injectable clock, fixed in tests.
  final DateTime Function() clock;

  final List<Uri> _feedUrls;

  Future<DirectorySyncResult>? _inFlight;

  /// The resolved feed URLs, in attempt order.
  List<Uri> get feedUrls => _feedUrls;

  /// Runs an automatic sync when the cache is missing or stale.
  ///
  /// [onStart] fires only when a network attempt actually begins, so a skipped
  /// (still-fresh) call never flashes a progress indicator.
  Future<DirectorySyncResult> syncIfNeeded({void Function()? onStart}) async {
    final repository = await loadRepository();
    final cached = await repository.getAll();
    if (!_isStale(cached)) {
      return DirectorySyncSkipped(serverCount: cached.length);
    }
    return await _singleFlight(onStart: onStart);
  }

  /// Runs a sync immediately, bypassing the recency throttle.
  Future<DirectorySyncResult> forceSync({void Function()? onStart}) =>
      _singleFlight(onStart: onStart);

  Future<DirectorySyncResult> _singleFlight({void Function()? onStart}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _run(onStart: onStart);
    _inFlight = future;
    // Cleared before the future is handed back so a later call can retry.
    unawaited(future.whenComplete(() => _inFlight = null));
    return future;
  }

  bool _isStale(List<ServerProfile> cached) {
    if (cached.isEmpty) return true;
    final last = preferences.getLastDirectorySyncAt();
    if (last == null) return true;
    return clock().toUtc().difference(last.toUtc()) >=
        kBuiltInDirectorySyncInterval;
  }

  Future<DirectorySyncResult> _run({void Function()? onStart}) async {
    final repository = await loadRepository();
    final cachedBefore = await repository.getAll();

    onStart?.call();

    for (final feedUri in _feedUrls) {
      final body = await _fetch(feedUri);
      if (body == null) continue;

      final parsed = _parseDirectory(body);
      if (parsed.profiles.isEmpty) continue;

      final persisted = await _persist(repository, parsed.profiles);
      // A write failure is local (disk or Keystore), not a mirror problem: the
      // next mirror would download into the same broken store, so stop here.
      if (!persisted) {
        return DirectorySyncFailure(serverCount: cachedBefore.length);
      }

      return DirectorySyncSuccess(
        serverCount: parsed.profiles.length,
        skippedLineCount: parsed.skippedLineCount,
      );
    }

    // Every mirror failed: keep whatever is already cached, untouched.
    return DirectorySyncFailure(serverCount: cachedBefore.length);
  }

  Future<String?> _fetch(Uri uri) async {
    try {
      final result = await fetcher(uri).timeout(feedTimeout);
      return switch (result) {
        Ok(:final value) => value,
        Err() => null,
      };
    } on Object {
      // Blocked, censored, offline, malformed: try the next mirror. Nothing
      // about the URL or the payload is ever logged.
      return null;
    }
  }

  ({List<ServerProfile> profiles, int skippedLineCount}) _parseDirectory(
    String body,
  ) {
    final decoded = decodeSubscriptionBody(body);
    if (decoded is! Ok<DecodedSubscription, ConfigParseError>) {
      return (profiles: const <ServerProfile>[], skippedLineCount: 0);
    }

    final addedAt = clock().toUtc();
    final profiles = <ServerProfile>[];
    var skipped = 0;

    for (final line in decoded.value.lines) {
      if (profiles.length >= kBuiltInFeedMaxServers) break;

      final parsed = parseSubscription(line);
      if (parsed case Ok(:final value) when value.configs.isNotEmpty) {
        final index = profiles.length + 1;
        profiles.add(
          value.configs.first.toServerProfile(
            id: '${kBuiltInDirectorySubscriptionId}_srv_$index',
            addedAt: addedAt,
            customRemark: _remarkFor(line, index),
            subscriptionId: kBuiltInDirectorySubscriptionId,
          ),
        );
      } else {
        // Unsupported or malformed line: skipped silently, never fatal.
        skipped++;
      }
    }

    return (profiles: profiles, skippedLineCount: skipped);
  }

  /// Reads the display name the feed put after `#`, falling back to a stable
  /// generated label so a nameless line still groups predictably.
  ///
  /// The fragment is sliced off the raw line rather than read from a parsed
  /// `Uri`: the live feed's remarks contain spaces and `|` characters, which
  /// are not legal URI syntax, so `Uri.tryParse` returns `null` for a line that
  /// the config parser accepts perfectly well.
  String _remarkFor(String line, int index) {
    final hashIndex = line.indexOf('#');
    if (hashIndex >= 0 && hashIndex + 1 < line.length) {
      final raw = line.substring(hashIndex + 1).trim();
      if (raw.isNotEmpty) {
        try {
          final decoded = Uri.decodeFull(raw).trim();
          if (decoded.isNotEmpty) return decoded;
        } on Object {
          // A stray `%` is not a percent-escape: keep the literal text.
          return raw;
        }
      }
    }
    return '$kBuiltInDirectoryName $index';
  }

  Future<bool> _persist(
    ServerProfileRepository repository,
    List<ServerProfile> profiles,
  ) async {
    final now = clock().toUtc();
    final ids = <String>{for (final profile in profiles) profile.id};

    final metadata = SubscriptionMetadata(
      id: kBuiltInDirectorySubscriptionId,
      // The subscription URL is encrypted at rest by the repository, exactly
      // like any other saved subscription.
      url: _feedUrls.first.toString(),
      name: kBuiltInDirectoryName,
      lastRefreshedAt: now,
      associatedServerIds: ids.toList(growable: false),
    );

    try {
      // Atomic replace of this subscription's servers only; standalone servers
      // and unrelated subscriptions are untouched.
      await repository.replaceSubscriptionProfiles(metadata, profiles);
    } on Object {
      return false;
    }

    await _preserveActiveServer(profiles, ids);
    await preferences.setLastDirectorySyncAt(now);
    return true;
  }

  Future<void> _preserveActiveServer(
    List<ServerProfile> profiles,
    Set<String> ids,
  ) async {
    final activeId = preferences.getActiveServerId();
    if (activeId == null) {
      await preferences.setActiveServerId(profiles.first.id);
      return;
    }
    const prefix = '${kBuiltInDirectorySubscriptionId}_srv_';
    if (activeId.startsWith(prefix) && !ids.contains(activeId)) {
      // The selected directory server disappeared (rotated out of the feed):
      // fall back to the first freshly synced server.
      await preferences.setActiveServerId(profiles.first.id);
    }
    // A user-owned standalone server stays selected.
  }
}
