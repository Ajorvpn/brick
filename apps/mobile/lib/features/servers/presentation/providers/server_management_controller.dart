// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/subscription_fetcher_provider.dart';
import 'package:mobile/features/connection/presentation/providers/add_subscription_controller.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

/// Sealed hierarchy of domain errors encountered during server management.
///
/// Implements [HasUserMessage] per `CODING_STANDARDS.md` Section 5.1 so that
/// all presentation-layer error mapping is routed through [ErrorMapper].
sealed class ServerManagementError implements HasUserMessage {
  const ServerManagementError();
}

/// The user submitted an empty or whitespace-only server name.
final class ServerManagementEmptyNameError extends ServerManagementError {
  const ServerManagementEmptyNameError();

  @override
  String toUserMessage() => 'servers.name_required'.tr();
}

/// The submitted replacement URI was identified as a subscription URL or
/// payload.
final class ServerManagementSubscriptionInputError
    extends ServerManagementError {
  const ServerManagementSubscriptionInputError();

  @override
  String toUserMessage() => 'add_server.error_is_subscription'.tr();
}

/// The submitted replacement URI could not be parsed as a valid configuration.
final class ServerManagementParseError extends ServerManagementError {
  const ServerManagementParseError(this.message);

  /// Safe user-facing error message from the parser (never leaks secrets).
  final String message;

  @override
  String toUserMessage() => message;
}

/// The subscription URL is malformed or invalid.
final class ServerManagementInvalidUrlError extends ServerManagementError {
  const ServerManagementInvalidUrlError();

  @override
  String toUserMessage() => 'add_subscription.invalid_url'.tr();
}

/// A transport or network error occurred while refreshing the subscription.
final class ServerManagementFetchError extends ServerManagementError {
  const ServerManagementFetchError(this.message);

  /// Safe user-facing error message from the fetcher (never leaks secrets).
  final String message;

  @override
  String toUserMessage() => message;
}

/// The refreshed subscription content contained zero usable server
/// configurations.
final class ServerManagementNoValidServersError extends ServerManagementError {
  const ServerManagementNoValidServersError();

  @override
  String toUserMessage() => 'add_subscription.no_valid_servers'.tr();
}

/// An error occurred during persistence to storage.
final class ServerManagementStorageError extends ServerManagementError {
  const ServerManagementStorageError();

  @override
  String toUserMessage() => 'servers.storage_error'.tr();
}

/// Direct editing of a subscription-sourced server was attempted.
final class ServerManagementReadOnlyError extends ServerManagementError {
  const ServerManagementReadOnlyError();

  @override
  String toUserMessage() => 'servers.read_only_error'.tr();
}

/// Provides the controller for server management actions.
final serverManagementControllerProvider =
    AsyncNotifierProvider<ServerManagementController, Set<String>>(
      ServerManagementController.new,
    );

/// Controller responsible for server editing, duplication, deletion, and
/// subscription refresh / deletion.
///
/// State represents the set of [SubscriptionMetadata.id]s currently undergoing
/// an active refresh operation.
class ServerManagementController extends AsyncNotifier<Set<String>> {
  static int _dupSequence = 0;

  @override
  FutureOr<Set<String>> build() => const <String>{};

  /// Edits [existing] standalone server's display name and optionally parses
  /// and updates its configuration via [newRawUri].
  Future<Result<void, ServerManagementError>> editServer({
    required ServerProfile existing,
    required String newName,
    String? newRawUri,
  }) async {
    if (existing.subscriptionId != null &&
        existing.subscriptionId!.isNotEmpty) {
      return const Err(ServerManagementReadOnlyError());
    }

    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      return const Err(ServerManagementEmptyNameError());
    }

    ServerProfile updatedProfile;
    final trimmedUri = newRawUri?.trim();

    if (trimmedUri != null && trimmedUri.isNotEmpty) {
      if (_isSubscriptionInput(trimmedUri)) {
        return const Err(ServerManagementSubscriptionInputError());
      }

      final parsed = parseUri(trimmedUri);
      switch (parsed) {
        case Err(:final error):
          return Err(ServerManagementParseError(error.message));
        case Ok(:final value):
          updatedProfile = value.toServerProfile(
            id: existing.id,
            addedAt: existing.addedAt,
            lastUsedAt: existing.lastUsedAt,
            customRemark: trimmedName,
          );
      }
    } else {
      updatedProfile = existing.copyWith(name: trimmedName);
    }

    try {
      final repo = await ref.read(serverProfileRepositoryProvider.future);
      await repo.save(updatedProfile);
      ref.invalidate(savedServersProvider);
      return const Ok(null);
    } on Object {
      return const Err(ServerManagementStorageError());
    }
  }

  /// Duplicates [source] server profile into an independent standalone server.
  Future<Result<ServerProfile, ServerManagementError>> duplicateServer(
    ServerProfile source,
  ) async {
    final now = DateTime.now().toUtc();
    final newId =
        'standalone_${now.microsecondsSinceEpoch.toRadixString(36)}_'
        '${(++_dupSequence).toRadixString(36)}';
    final copyName = 'servers.copy_suffix'.tr(namedArgs: {'name': source.name});

    final duplicated = ServerProfile(
      id: newId,
      name: copyName,
      config: source.config,
      addedAt: now,
    );

    try {
      final repo = await ref.read(serverProfileRepositoryProvider.future);
      await repo.save(duplicated);
      ref.invalidate(savedServersProvider);
      return Ok(duplicated);
    } on Object {
      return const Err(ServerManagementStorageError());
    }
  }

  /// Deletes the server profile or broken entry with [id].
  Future<Result<void, ServerManagementError>> deleteServer(String id) async {
    try {
      final repo = await ref.read(serverProfileRepositoryProvider.future);
      await repo.delete(id);
      ref.invalidate(savedServersProvider);
      return const Ok(null);
    } on Object {
      return const Err(ServerManagementStorageError());
    }
  }

  /// Atomically cascades deletion of [subscriptionId] and all its child
  /// servers.
  Future<Result<void, ServerManagementError>> deleteSubscription(
    String subscriptionId,
  ) async {
    try {
      final repo = await ref.read(serverProfileRepositoryProvider.future);
      await repo.deleteSubscriptionCascade(subscriptionId);
      ref.invalidate(savedServersProvider);
      return const Ok(null);
    } on Object {
      return const Err(ServerManagementStorageError());
    }
  }

  /// Manually refreshes [subscription] using the Full-Replace diffing policy.
  ///
  /// Atomically replaces all existing server profiles belonging to the
  /// subscription if at least 1 valid server is returned. If refresh fails
  /// (network error or 0 valid servers), preserves existing profiles untouched.
  Future<Result<SubscriptionImportOutcome, ServerManagementError>>
  refreshSubscription(SubscriptionMetadata subscription) async {
    final uri = Uri.tryParse(subscription.url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme.toLowerCase() != 'https' &&
            uri.scheme.toLowerCase() != 'http')) {
      return const Err(ServerManagementInvalidUrlError());
    }

    final current = state.value ?? <String>{};
    state = AsyncData({...current, subscription.id});

    try {
      final fetcher = ref.read(subscriptionFetcherProvider);
      final fetchResult = await fetcher.fetchSubscription(uri);

      switch (fetchResult) {
        case Err(:final error):
          return Err(ServerManagementFetchError(error.message));
        case Ok(:final value):
          if (value.configs.isEmpty) {
            return const Err(ServerManagementNoValidServersError());
          }

          final repo = await ref.read(serverProfileRepositoryProvider.future);
          final now = DateTime.now().toUtc();
          final profiles = <ServerProfile>[];
          final newIds = <String>[];

          for (var i = 0; i < value.configs.length; i++) {
            final config = value.configs[i];
            final profileId = '${subscription.id}_srv_${i + 1}';
            newIds.add(profileId);
            final profile = config.toServerProfile(
              id: profileId,
              addedAt: now,
              customRemark:
                  '${subscription.name} - '
                  '${config.server}:${config.serverPort}',
              subscriptionId: subscription.id,
            );
            profiles.add(profile);
          }

          final updatedSub = subscription.copyWith(
            lastRefreshedAt: now,
            associatedServerIds: newIds,
            userInfo: value.userInfo,
          );

          await repo.replaceSubscriptionProfiles(updatedSub, profiles);
          ref.invalidate(savedServersProvider);

          return Ok(
            SubscriptionImportOutcome(
              importedCount: profiles.length,
              skippedCount: value.errors.length,
            ),
          );
      }
    } on Object {
      return const Err(ServerManagementStorageError());
    } finally {
      final updated = (state.value ?? <String>{})
          .where((id) => id != subscription.id)
          .toSet();
      state = AsyncData(updated);
    }
  }

  /// Returns true if [input] represents a subscription URL or payload.
  static bool _isSubscriptionInput(String input) {
    final lower = input.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('sub://')) {
      return true;
    }

    final parsedUri = Uri.tryParse(input);
    final scheme = parsedUri?.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https' || scheme == 'sub') {
      return true;
    }

    final smartResult = parseConfigContent(input);
    if (smartResult case Ok(:final value)) {
      if (value.detectedType == SmartContentType.subscription ||
          value.outbounds.length > 1) {
        return true;
      }
    }

    if (input.contains('\n')) {
      final lines = input
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(growable: false);
      if (lines.length > 1) {
        return true;
      }
    }

    return false;
  }
}
