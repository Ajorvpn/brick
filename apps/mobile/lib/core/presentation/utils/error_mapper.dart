// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show
        ConnectionErrorReason,
        ConnectionState,
        Error,
        InvalidConfig,
        PermissionDenied,
        PlatformError,
        Unknown;
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:easy_localization/easy_localization.dart';

/// Contract for domain errors that provide their own localized user message.
///
/// Future domain error types (Phase 5+) can implement this interface so they
/// can be seamlessly mapped by [ErrorMapper.mapToUserMessage].
abstract interface class HasUserMessage {
  /// Returns a user-facing, localized message for this error.
  String toUserMessage();
}

/// Standardized mapper translating domain errors, engine command results, and
/// connection failure states into localized user messages.
///
/// Mandated by P4-T3 and `CODING_STANDARDS.md` Section 5.1.
class ErrorMapper {
  ErrorMapper._();

  /// Maps an arbitrary domain error, exception, or failure reason to a
  /// localized, user-facing string suitable for presentation via AppFeedback.
  static String mapToUserMessage(Object? error) {
    if (error == null) {
      return 'error.generic'.tr();
    }

    if (error is HasUserMessage) {
      return error.toUserMessage();
    }

    if (error is ConnectionErrorReason) {
      return switch (error) {
        PermissionDenied() => 'error.vpn_permission_denied'.tr(),
        InvalidConfig() => 'error.invalid_config'.tr(),
        PlatformError() => 'error.platform_error'.tr(),
        Unknown() => 'error.unknown'.tr(),
      };
    }

    if (error is Error) {
      return mapToUserMessage(error.reason);
    }

    if (error is VpnCommandResult) {
      return switch (error) {
        VpnCommandAccepted() => '',
        VpnCommandRejectedBusy() => 'error.server_busy'.tr(),
        VpnCommandRejectedInvalidConfig() => 'error.invalid_config'.tr(),
        VpnCommandRejectedPermissionDenied() =>
          'error.vpn_permission_denied'.tr(),
        VpnCommandFailed() => 'error.platform_error'.tr(),
      };
    }

    return 'error.generic'.tr();
  }

  /// Maps a [ConnectionState] into a localized error message if the state is
  /// [Error], or returns null if the state is not an error.
  static String? mapConnectionState(ConnectionState state) {
    if (state is Error) {
      return mapToUserMessage(state.reason);
    }
    return null;
  }
}
