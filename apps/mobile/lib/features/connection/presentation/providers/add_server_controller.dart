// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:config_parser/config_parser.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

/// Sealed hierarchy of domain errors encountered when adding a server link.
///
/// Implements [HasUserMessage] per `CODING_STANDARDS.md` Section 5.1 so that
/// all presentation-layer error mapping is routed through [ErrorMapper].
sealed class AddServerError implements HasUserMessage {
  const AddServerError();
}

/// The user submitted an empty or whitespace-only URI string.
final class AddServerEmptyInputError extends AddServerError {
  const AddServerEmptyInputError();

  @override
  String toUserMessage() => 'add_server.uri_required'.tr();
}

/// The submitted input was identified as a subscription URL or payload.
final class AddServerSubscriptionInputError extends AddServerError {
  const AddServerSubscriptionInputError();

  @override
  String toUserMessage() => 'add_server.error_is_subscription'.tr();
}

/// The submitted input could not be parsed as a valid server configuration.
final class AddServerParseError extends AddServerError {
  const AddServerParseError(this.message);

  /// Safe user-facing error message from the parser (never leaks secrets).
  final String message;

  @override
  String toUserMessage() => message;
}

/// An error occurred while persisting the server profile to storage.
final class AddServerStorageError extends AddServerError {
  const AddServerStorageError();

  @override
  String toUserMessage() => 'servers.storage_error'.tr();
}

/// Provides the controller for validating and persisting new server profiles.
final AsyncNotifierProvider<AddServerController, void>
addServerControllerProvider =
    AsyncNotifierProvider.autoDispose<AddServerController, void>(
      AddServerController.new,
    );

/// Controller responsible for adding a server configuration link.
///
/// Validates manual link pastes (e.g. `vless://`, `trojan://`, etc.) via
/// [parseUri] and persists them via [ServerProfileRepository].
///
/// Rejects subscription links (`http://`, `https://`) and bulk/subscription
/// bodies with a specialized error pointing the user to the subscription flow.
class AddServerController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Initial idle state.
  }

  /// Validates, parses, and persists [rawUri] to the server repository.
  ///
  /// Returns a typed [Result] with [AddServerError] on any failure, satisfying
  /// `CODING_STANDARDS.md` Section 5.1.
  Future<Result<void, AddServerError>> submit(String rawUri) async {
    final uri = rawUri.trim();
    if (uri.isEmpty) {
      const error = AddServerEmptyInputError();
      state = AsyncError<void>(error, StackTrace.current);
      return const Err(error);
    }

    if (_isSubscriptionInput(uri)) {
      const error = AddServerSubscriptionInputError();
      state = AsyncError<void>(error, StackTrace.current);
      return const Err(error);
    }

    state = const AsyncLoading<void>();

    final parsed = parseUri(uri);
    switch (parsed) {
      case Err(:final error):
        final failure = AddServerParseError(error.message);
        state = AsyncError<void>(failure, StackTrace.current);
        return Err(failure);
      case Ok():
        try {
          final repo = await ref.read(serverProfileRepositoryProvider.future);
          await repo.addServer(uri);
          ref.invalidate(savedServersProvider);
          state = const AsyncData<void>(null);
          return const Ok(null);
        } on Object catch (_, st) {
          const failure = AddServerStorageError();
          state = AsyncError<void>(failure, st);
          return const Err(failure);
        }
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

    // Inspect content via config_parser's smart detector:
    final smartResult = parseConfigContent(input);
    if (smartResult case Ok(:final value)) {
      if (value.detectedType == SmartContentType.subscription ||
          value.outbounds.length > 1) {
        return true;
      }
    }

    // Also check if multi-line text contains multiple protocol URIs or lines
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
