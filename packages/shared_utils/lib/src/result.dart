// SPDX-License-Identifier: GPL-3.0-or-later

/// A value that is either a success ([Ok]) or an expected failure ([Err]).
///
/// Use [Result] for expected, recoverable failures — for example an invalid
/// subscription URL, a rejected VPN command, or a storage write that can
/// legitimately fail. Return the failure as an [Err] value instead of
/// throwing, so the failure path stays explicit in every signature and cannot
/// be silently swallowed by an empty `catch` block (a documented root cause
/// of the legacy prototype's silent native-bridge failures).
///
/// Dart `Exception`s remain reserved for truly unexpected programmer errors:
/// invariant violations, null where the type system already guarantees
/// non-null, and similar bugs. In short: an [Err] is data the caller is
/// expected to handle, while an exception is a bug report.
///
/// Because [Result] is `sealed`, its direct subtypes ([Ok] and [Err]) can
/// only be defined in this library, and the analyzer statically checks that
/// any `switch` over a [Result] handles both variants — a forgotten variant
/// is a compile-time error, not a runtime surprise.
sealed class Result<T, E> {
  /// Single shared constructor for the [Result] hierarchy.
  ///
  /// [Result] itself is never instantiated directly: it is implicitly
  /// abstract, and every value is an [Ok] or an [Err].
  const Result._();

  /// Creates a successful result wrapping [value].
  const factory Result.ok(T value) = Ok<T, E>;

  /// Creates a failed result carrying [error].
  const factory Result.err(E error) = Err<T, E>;

  /// Whether this result is an [Ok] (a success).
  bool get isOk;

  /// Whether this result is an [Err] (a failure).
  bool get isErr;

  /// Transforms the success value with [transform], leaving a failure — and
  /// its error — untouched.
  Result<R, E> map<R>(R Function(T value) transform);

  /// Transforms the failure error with [transform], leaving a success — and
  /// its value — untouched.
  Result<T, R> mapErr<R>(R Function(E error) transform);

  /// Folds the result into a single value of type [R] by applying exactly
  /// one of the two required handlers: [ok] for a success, [err] for a
  /// failure. Both handlers are required, so an error path cannot be
  /// silently omitted at the call site.
  R fold<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  });
}

/// The success variant of [Result], wrapping a [value] of type [T].
final class Ok<T, E> extends Result<T, E> {
  /// Creates a success result wrapping [value].
  const Ok(this.value) : super._();

  /// The wrapped success value.
  final T value;

  @override
  bool get isOk => true;

  @override
  bool get isErr => false;

  @override
  Result<R, E> map<R>(R Function(T value) transform) => Ok(transform(value));

  @override
  Result<T, R> mapErr<R>(R Function(E error) transform) => Ok<T, R>(value);

  @override
  R fold<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) {
    return ok(value);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is Ok<T, E> &&
          other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);
}

/// The failure variant of [Result], wrapping an [error] of type [E].
final class Err<T, E> extends Result<T, E> {
  /// Creates a failure result carrying [error].
  const Err(this.error) : super._();

  /// The wrapped failure error.
  final E error;

  @override
  bool get isOk => false;

  @override
  bool get isErr => true;

  @override
  Result<R, E> map<R>(R Function(T value) transform) => Err<R, E>(error);

  @override
  Result<T, R> mapErr<R>(R Function(E error) transform) =>
      Err<T, R>(transform(error));

  @override
  R fold<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) {
    return err(error);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is Err<T, E> &&
          other.error == error;

  @override
  int get hashCode => Object.hash(runtimeType, error);
}
