// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:config_parser/config_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/servers/data/services/built_in_directory_sync_service.dart';
import 'package:mobile/features/servers/domain/built_in_feed_config.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

/// Provides the remote fetcher used by the built-in directory sync.
///
/// Overridden in every widget test so no test ever reaches the network.
final Provider<BuiltInFeedFetcher> builtInFeedFetcherProvider =
    Provider<BuiltInFeedFetcher>((ref) => fetchBuiltInDirectoryFeed);

/// Downloads one directory payload through the hardened subscription fetcher.
///
/// The body is captured while [SubscriptionFetcher] consumes it, so the caller
/// gets the exact bytes that passed the HTTPS-only, redirect, size-cap and
/// status-code checks — never a second, unchecked request.
Future<Result<String, ConfigParseError>> fetchBuiltInDirectoryFeed(
  Uri uri,
) async {
  final capture = _CapturingTransport(HttpClientTransport());
  final fetcher = SubscriptionFetcher(transport: capture);
  try {
    final result = await fetcher.fetchSubscription(
      uri,
      maxBytes: kBuiltInFeedMaxBytes,
    );
    if (result case Err(:final error)) {
      return Err(error);
    }
    final body = capture.takeBody();
    if (body == null) {
      return const Err(ResponseDecodingError('server directory body'));
    }
    return Ok(body);
  } on Object {
    // The fetcher is documented never to throw; this is the belt-and-braces
    // path so a feed failure can never surface as an app crash.
    return const Err(NetworkFailureError('the directory could not be fetched'));
  } finally {
    fetcher.close();
  }
}

/// Provides the directory sync service.
final Provider<BuiltInDirectorySyncService>
builtInDirectorySyncServiceProvider = Provider<BuiltInDirectorySyncService>((
  ref,
) {
  return BuiltInDirectorySyncService(
    loadRepository: () => ref.read(serverProfileRepositoryProvider.future),
    preferences: ref.watch(appPreferencesRepositoryProvider),
    fetcher: ref.watch(builtInFeedFetcherProvider),
  );
});

/// Provides the observable directory-sync state used by the UI.
final Provider<BuiltInDirectorySyncController>
builtInDirectorySyncControllerProvider =
    Provider<BuiltInDirectorySyncController>((ref) {
      final controller = BuiltInDirectorySyncController(
        sync: ref.watch(builtInDirectorySyncServiceProvider),
        // The service persists a fallback active server while writing the
        // directory, so the in-memory notifier must re-read it: otherwise a
        // fresh install stays with `null` until the app restarts.
        onDirectoryChanged: () => ref
          ..invalidate(savedServersProvider)
          ..invalidate(activeServerIdProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Observable status of the built-in directory, consumed by `ServersScreen`.
///
/// Deliberately a plain [ChangeNotifier] behind a Riverpod [Provider]: the
/// provider stays alive for the lifetime of the app shell, so a completed
/// background sync can never notify a disposed object.
final class BuiltInDirectorySyncController extends ChangeNotifier {
  /// Creates a controller over [sync].
  BuiltInDirectorySyncController({
    required this.sync,
    required this.onDirectoryChanged,
  });

  final BuiltInDirectorySyncService sync;
  final void Function() onDirectoryChanged;

  bool _isSyncing = false;
  bool _hasFailed = false;
  int _serverCount = 0;
  bool _disposed = false;

  /// Whether a sync attempt is currently running.
  bool get isSyncing => _isSyncing;

  /// Whether the most recent attempt failed (cached servers may still exist).
  bool get hasFailed => _hasFailed;

  /// Servers held by the directory after the most recent attempt.
  int get serverCount => _serverCount;

  /// Runs the throttled automatic sync.
  Future<DirectorySyncResult> syncIfNeeded() => _execute(sync.syncIfNeeded);

  /// Runs an immediate sync, bypassing the recency throttle.
  Future<DirectorySyncResult> forceSync() => _execute(sync.forceSync);

  Future<DirectorySyncResult> _execute(
    Future<DirectorySyncResult> Function({void Function()? onStart}) run,
  ) async {
    final result = await run(onStart: _markStarted);
    _markFinished(result);
    return result;
  }

  void _markStarted() {
    if (_disposed) return;
    _isSyncing = true;
    _hasFailed = false;
    notifyListeners();
  }

  void _markFinished(DirectorySyncResult result) {
    if (_disposed) return;
    _isSyncing = false;
    _serverCount = result.serverCount;
    _hasFailed = result is DirectorySyncFailure;
    if (result is DirectorySyncSuccess) {
      onDirectoryChanged();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Forwards every response chunk unchanged while remembering the final body.
///
/// Only the last response is retained: redirect hops are drained by the
/// fetcher before the next [send], and the capturing buffer is reset on each
/// call, so whatever remains is the payload that was actually parsed.
final class _CapturingTransport implements SubscriptionTransport {
  _CapturingTransport(this._inner);

  final SubscriptionTransport _inner;
  BytesBuilder? _buffer;

  @override
  Future<TransportResponse> send(Uri uri, Map<String, String> headers) async {
    final response = await _inner.send(uri, headers);
    // Reset per hop: a redirect body drained by the fetcher is replaced by the
    // next response's chunks.
    final buffer = BytesBuilder(copy: false);
    _buffer = buffer;
    return TransportResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.body.map((chunk) {
        buffer.add(chunk);
        return chunk;
      }),
    );
  }

  /// The decoded final body, or `null` if nothing was captured.
  ///
  /// Called only after the fetcher has finished reading the body stream.
  String? takeBody() {
    final bytes = _buffer?.takeBytes();
    if (bytes == null || bytes.isEmpty) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  void close() => _inner.close();
}
