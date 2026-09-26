// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';

/// Convenience conversion from a parsed [OutboundConfig] to the
/// [ServerProfile] container the app persists.
///
/// Why this is an explicit, caller-supplied conversion rather than something
/// the parsers do themselves: `ServerProfile` requires an `id` and an
/// `addedAt`, which a pure parser cannot know. Phase 2 requires every
/// parser to be a pure, deterministic function (no `DateTime.now()`, no
/// random UUID generation), so the identity and timestamp are supplied here
/// by the caller, who owns profile creation and persistence.
extension OutboundConfigProfileX on OutboundConfig {
  /// Wraps this config in a [ServerProfile].
  ///
  /// [customRemark] becomes the profile's user-facing [ServerProfile.name].
  /// When omitted, a `host:port` label is derived so the profile is always
  /// identifiable in the UI list.
  ServerProfile toServerProfile({
    required String id,
    required DateTime addedAt,
    String? customRemark,
    DateTime? lastUsedAt,
    String? subscriptionId,
  }) {
    return ServerProfile(
      id: id,
      name: (customRemark != null && customRemark.isNotEmpty)
          ? customRemark
          : '$server:$serverPort',
      config: this,
      addedAt: addedAt,
      lastUsedAt: lastUsedAt,
      subscriptionId: subscriptionId,
    );
  }
}
