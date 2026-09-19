// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

/// Exhaustively maps every state to a label.
///
/// Why a switch with no `default`: if a sixth [ConnectionState] variant is
/// ever added, the analyzer must fail this function until the new variant is
/// handled here — that compile-time guarantee is the entire point of the
/// sealed hierarchy.
String describeState(ConnectionState state) => switch (state) {
  Disconnected() => 'disconnected',
  Connecting() => 'connecting',
  Connected() => 'connected',
  Disconnecting() => 'disconnecting',
  Error(reason: final reason) => 'error:${describeReason(reason)}',
};

/// Exhaustively maps every failure category to a label, for the same
/// exhaustiveness reason as [describeState]: no `default`, no string parsing.
String describeReason(ConnectionErrorReason reason) => switch (reason) {
  PermissionDenied() => 'permission-denied',
  InvalidConfig() => 'invalid-config',
  PlatformError(detail: final detail) => 'platform:$detail',
  Unknown() => 'unknown',
};

void main() {
  group('construction and exhaustive matching', () {
    test('every variant matches its own label', () {
      expect(describeState(const Disconnected()), 'disconnected');
      expect(describeState(const Connecting()), 'connecting');
      expect(describeState(const Connected()), 'connected');
      expect(describeState(const Disconnecting()), 'disconnecting');
      expect(
        describeState(const Error(PermissionDenied())),
        'error:permission-denied',
      );
    });

    test('every error reason matches its own label', () {
      expect(describeReason(const PermissionDenied()), 'permission-denied');
      expect(describeReason(const InvalidConfig()), 'invalid-config');
      expect(
        describeReason(const PlatformError('vpn-service died')),
        'platform:vpn-service died',
      );
      expect(describeReason(const Unknown()), 'unknown');
    });

    test('error state carries its reason through pattern matching', () {
      const state = Error(PlatformError('tunnel closed'));
      expect(switch (state) {
        Error(reason: PlatformError(detail: final detail)) => detail,
        _ => fail('expected an Error carrying a PlatformError'),
      }, 'tunnel closed');
    });
  });

  group('equality and hashCode', () {
    test('same stateless variant instances are equal', () {
      expect(const Disconnected(), const Disconnected());
      expect(const Connecting(), const Connecting());
      expect(const Connected(), const Connected());
      expect(const Disconnecting(), const Disconnecting());
      expect(const PermissionDenied(), const PermissionDenied());
      expect(const InvalidConfig(), const InvalidConfig());
      expect(const Unknown(), const Unknown());
    });

    test('identical instance takes the fast path', () {
      const state = Connected();
      expect(identical(state, state), isTrue);
      expect(state, state);
    });

    test('different variants are not equal', () {
      expect(const Disconnected(), isNot(const Connecting()));
      expect(const Connected(), isNot(const Disconnecting()));
      expect(
        const Error(PermissionDenied()),
        isNot(const Error(InvalidConfig())),
      );
      expect(
        const Error(PlatformError('a')),
        isNot(const Error(PlatformError('b'))),
      );
      expect(const PermissionDenied(), isNot(const InvalidConfig()));
    });

    test('error states compare by reason value', () {
      expect(
        const Error(PlatformError('boom')),
        const Error(PlatformError('boom')),
      );
      expect(
        const Error(PlatformError('boom')).hashCode,
        const Error(PlatformError('boom')).hashCode,
      );
    });

    test('equal values share hashCode', () {
      expect(const Disconnected().hashCode, const Disconnected().hashCode);
      expect(const Unknown().hashCode, const Unknown().hashCode);
    });
  });
}
