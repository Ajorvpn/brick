// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/subscription_fetcher_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

/// Sealed hierarchy of domain errors encountered when adding a subscription.
///
/// Implements [HasUserMessage] per `CODING_STANDARDS.md` Section 5.1 so that
/// all presentation-layer error mapping is routed through [ErrorMapper].
sealed class AddSubscriptionError implements HasUserMessage {
  const AddSubscriptionError();
}

/// The user submitted an empty or whitespace-only subscription URL.
final class AddSubscriptionEmptyUrlError extends AddSubscriptionError {
  const AddSubscriptionEmptyUrlError();

  @override
  String toUserMessage() => 'add_subscription.url_required'.tr();
}

/// The submitted input was not a valid HTTPS or HTTP URI.
final class AddSubscriptionInvalidUrlError extends AddSubscriptionError {
  const AddSubscriptionInvalidUrlError();

  @override
  String toUserMessage() => 'add_subscription.invalid_url'.tr();
}

/// A network, HTTP, or transport error occurred while fetching the URL.
final class AddSubscriptionFetchError extends AddSubscriptionError {
  const AddSubscriptionFetchError(this.message);

  /// Safe user-facing error message from the parser (never leaks secrets).
  final String message;

  @override
  String toUserMessage() => message;
}

/// The fetched payload yielded zero usable server configurations.
final class AddSubscriptionNoValidServersError extends AddSubscriptionError {
  const AddSubscriptionNoValidServersError();

  @override
  String toUserMessage() => 'add_subscription.no_valid_servers'.tr();
}

/// Represents the result of importing a subscription's server profiles.
@immutable
final class SubscriptionImportOutcome {
  /// Creates an import outcome snapshot.
  const SubscriptionImportOutcome({
    required this.importedCount,
    required this.skippedCount,
  });

  /// The number of valid server profiles successfully parsed and saved.
  final int importedCount;

  /// The number of invalid or unparseable lines skipped during import.
  final int skippedCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionImportOutcome &&
          runtimeType == other.runtimeType &&
          importedCount == other.importedCount &&
          skippedCount == other.skippedCount;

  @override
  int get hashCode => Object.hash(importedCount, skippedCount);
}

/// An error occurred while persisting the subscription or servers to storage.
final class AddSubscriptionStorageError extends AddSubscriptionError {
  const AddSubscriptionStorageError();

  @override
  String toUserMessage() => 'add_subscription.storage_error'.tr();
}

/// Provides the controller for validating, fetching, and persisting
/// subscriptions.
final AsyncNotifierProvider<AddSubscriptionController, void>
addSubscriptionControllerProvider =
    AsyncNotifierProvider.autoDispose<AddSubscriptionController, void>(
      AddSubscriptionController.new,
    );

/// Controller responsible for fetching and importing subscription servers.
///
/// Implements the partial-success policy:
/// - If a subscription contains both valid and malformed servers, persists all
///   valid profiles and saves the [SubscriptionMetadata].
/// - Fails with [Err] only if network transport fails or if zero valid servers
///   could be parsed.
class AddSubscriptionController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Initial idle state.
  }

  /// Fetches [rawUrl], parses its contents, and persists valid servers.
  ///
  /// Returns [Ok] with [SubscriptionImportOutcome] on success.
  Future<Result<SubscriptionImportOutcome, AddSubscriptionError>> submit(
    String rawUrl, {
    String? rawName,
  }) async {
    final urlStr = rawUrl.trim();
    if (urlStr.isEmpty) {
      const error = AddSubscriptionEmptyUrlError();
      state = AsyncError<void>(error, StackTrace.current);
      return const Err(error);
    }

    final uri = Uri.tryParse(urlStr);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme.toLowerCase() != 'https' &&
            uri.scheme.toLowerCase() != 'http')) {
      const error = AddSubscriptionInvalidUrlError();
      state = AsyncError<void>(error, StackTrace.current);
      return const Err(error);
    }

    state = const AsyncLoading<void>();

    final fetcher = ref.read(subscriptionFetcherProvider);
    final fetchResult = await fetcher.fetchSubscription(uri);

    switch (fetchResult) {
      case Err(:final error):
        final failure = AddSubscriptionFetchError(error.message);
        state = AsyncError<void>(failure, StackTrace.current);
        return Err(failure);

      case Ok(:final value):
        if (value.configs.isEmpty) {
          const failure = AddSubscriptionNoValidServersError();
          state = AsyncError<void>(failure, StackTrace.current);
          return const Err(failure);
        }

        try {
          final repo = await ref.read(serverProfileRepositoryProvider.future);
          final now = DateTime.now();
          final subId = 'sub_${now.microsecondsSinceEpoch.toRadixString(36)}';
          final subName = (rawName != null && rawName.trim().isNotEmpty)
              ? rawName.trim()
              : (uri.host.isNotEmpty ? uri.host : 'Subscription');

          final profiles = <ServerProfile>[];
          final associatedServerIds = <String>[];

          for (var i = 0; i < value.configs.length; i++) {
            final config = value.configs[i];
            final profileId = '${subId}_srv_${i + 1}';
            associatedServerIds.add(profileId);
            final profile = config.toServerProfile(
              id: profileId,
              addedAt: now,
              customRemark: '$subName - ${config.server}:${config.serverPort}',
              subscriptionId: subId,
            );
            profiles.add(profile);
          }

          final metadata = SubscriptionMetadata(
            id: subId,
            url: urlStr,
            name: subName,
            lastRefreshedAt: now,
            associatedServerIds: associatedServerIds,
            userInfo: value.userInfo,
          );

          await repo.saveSubscriptionWithProfiles(metadata, profiles);

          ref.invalidate(savedServersProvider);
          state = const AsyncData<void>(null);
          return Ok(
            SubscriptionImportOutcome(
              importedCount: profiles.length,
              skippedCount: value.errors.length,
            ),
          );
        } on Object {
          const failure = AddSubscriptionStorageError();
          state = AsyncError<void>(failure, StackTrace.current);
          return const Err(failure);
        }
    }
  }
}
