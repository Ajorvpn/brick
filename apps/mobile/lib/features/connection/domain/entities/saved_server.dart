// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';

/// One row in the user's saved-server list.
///
/// This is a **feature-specific** entity, not a `core_domain` type: it adds
/// the one concept `core_domain` deliberately does not model — the fact
/// that a stored entry may exist on disk but be unreadable (see
/// [SavedServerBroken]). `core_domain` is frozen, so this wrapper composes
/// its existing public types rather than extending them.
///
/// Why the failure mode matters: stored entries are rebuilt by re-running
/// `parseUri()` on the persisted source URI, so a schema/rule change between
/// app versions can leave a saved entry that no longer parses. Dropping it
/// silently would make a server vanish from a user's list with no
/// explanation; a crash would take the whole app down. [SavedServerBroken]
/// is the third option — visible, removable, and free of credential
/// material.
///
/// Security note: like every `core_domain` value type, neither variant
/// overrides `toString()`. [SavedServerBroken.reason] is a
/// `ConfigParseError.message`, which is documented as safe to display
/// because it never interpolates the offending input.
sealed class SavedServer {
  const SavedServer({required this.id});

  /// Stable local identifier, used to remove the entry later.
  final String id;
}

/// A saved entry whose stored URI parsed successfully.
final class SavedServerProfile extends SavedServer {
  /// Wraps [profile], taking its id as this entry's id.
  SavedServerProfile(this.profile) : super(id: profile.id);

  /// The fully-rebuilt profile, ready to hand to the engine.
  final ServerProfile profile;

  /// User-facing label for the list.
  String get name => profile.name;

  /// Protocol shown as text, e.g. `vless`. Text-only by design: the task
  /// brief specifies no iconography, and a text label is unambiguous for
  /// protocols whose icons are easily confused.
  String get protocolLabel => profile.config.protocol.scheme;

  /// `host:port`, the non-secret part of the configuration.
  String get endpoint =>
      '${profile.config.server}:${profile.config.serverPort}';
}

/// A saved entry that could not be rebuilt from its stored URI.
///
/// Carries no credential material: only [reason], a `ConfigParseError`
/// message whose contract states it must never be built by interpolating
/// the offending input, and [id], which is locally generated.
final class SavedServerBroken extends SavedServer {
  /// Creates a broken entry for [id] explaining why via [reason].
  SavedServerBroken({required super.id, required this.reason});

  /// Safe, user-displayable explanation of the parse failure.
  final String reason;
}

/// The non-secret parts of a successfully parsed server URI.
///
/// Deliberately limited to what a user needs to confirm they pasted the
/// right link. The credential-bearing remainder (UUID, password, REALITY
/// key) is **not** represented here, so this object cannot leak it into a
/// widget tree, a log line, or a snapshot.
final class ParsedUriSummary {
  /// Creates a summary.
  const ParsedUriSummary({
    required this.protocol,
    required this.endpoint,
    required this.name,
  });

  /// Canonical URI scheme, e.g. `vless`.
  final String protocol;

  /// `host:port`.
  final String endpoint;

  /// The label the profile will carry (URI fragment, or `host:port`).
  final String name;
}

/// The outcome of validating a pasted URI.
///
/// Sealed so a caller must handle both cases explicitly: there is no
/// "unknown" state, and the error branch carries only a safe message.
sealed class UriValidation {
  const UriValidation();

  /// Creates a successful result.
  const factory UriValidation.parsed(ParsedUriSummary summary) =
      _UriValidationParsed;

  /// Creates a failed result carrying a displayable [message].
  const factory UriValidation.failed(String message) = _UriValidationFailed;

  /// The parsed summary, or `null` when validation failed.
  ParsedUriSummary? get summary => switch (this) {
    _UriValidationParsed(:final summary) => summary,
    _UriValidationFailed() => null,
  };

  /// The safe error message, or `null` when validation succeeded.
  String? get message => switch (this) {
    _UriValidationParsed() => null,
    _UriValidationFailed(:final message) => message,
  };

  /// Whether the URI parsed.
  bool get isValid => this is _UriValidationParsed;
}

final class _UriValidationParsed extends UriValidation {
  const _UriValidationParsed(this.summary);

  @override
  final ParsedUriSummary summary;
}

final class _UriValidationFailed extends UriValidation {
  const _UriValidationFailed(this.message);

  @override
  final String message;
}
