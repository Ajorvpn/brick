// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:test/test.dart';

/// Exhaustively maps every command result to a label.
///
/// Why a switch with no `default`: adding a sixth outcome must break this
/// function at compile time until it is handled — the sealed-hierarchy
/// guarantee this type exists for.
String resultLabel(VpnCommandResult result) => switch (result) {
  VpnCommandAccepted() => 'accepted',
  VpnCommandRejectedBusy() => 'rejected-busy',
  VpnCommandRejectedInvalidConfig() => 'rejected-invalid-config',
  VpnCommandRejectedPermissionDenied() => 'rejected-permission-denied',
  VpnCommandFailed() => 'failed',
};

void main() {
  group('exhaustive switching over the sealed hierarchy', () {
    test('should match every variant without a default clause', () {
      const results = <VpnCommandResult>[
        VpnCommandAccepted(),
        VpnCommandRejectedBusy(),
        VpnCommandRejectedInvalidConfig(),
        VpnCommandRejectedPermissionDenied(),
        VpnCommandFailed(),
      ];
      expect(results.map(resultLabel).toList(), [
        'accepted',
        'rejected-busy',
        'rejected-invalid-config',
        'rejected-permission-denied',
        'failed',
      ]);
    });

    test('variants of different types are never equal', () {
      expect(const VpnCommandAccepted(), isNot(const VpnCommandFailed()));
      expect(
        const VpnCommandRejectedBusy(),
        isNot(const VpnCommandRejectedPermissionDenied()),
      );
    });
  });

  group('equality and identity', () {
    test('stateless variants are value-equal and share hashCode', () {
      const variants = <VpnCommandResult>[
        VpnCommandAccepted(),
        VpnCommandRejectedBusy(),
        VpnCommandRejectedInvalidConfig(),
        VpnCommandRejectedPermissionDenied(),
        VpnCommandFailed(),
      ];
      for (final variant in variants) {
        final sameType = variant.runtimeType;
        final copy = resultsOf(sameType);
        expect(variant, copy, reason: '$sameType must be value-equal');
        expect(
          variant.hashCode,
          copy.hashCode,
          reason: '$sameType must share hashCode',
        );
      }
    });

    test('the identical instance takes the fast path', () {
      const result = VpnCommandAccepted();
      expect(identical(result, result), isTrue);
      expect(result, result);
    });
  });

  group('toJson discriminators', () {
    test('should emit the exact variant scheme for every outcome', () {
      expect(const VpnCommandAccepted().toJson(), {'type': 'accepted'});
      expect(const VpnCommandRejectedBusy().toJson(), {
        'type': 'rejected_busy',
      });
      expect(const VpnCommandRejectedInvalidConfig().toJson(), {
        'type': 'rejected_invalid_config',
      });
      expect(const VpnCommandRejectedPermissionDenied().toJson(), {
        'type': 'rejected_permission_denied',
      });
      expect(const VpnCommandFailed().toJson(), {'type': 'failed'});
    });

    test('should agree with the type getter for every variant', () {
      const results = <VpnCommandResult>[
        VpnCommandAccepted(),
        VpnCommandRejectedBusy(),
        VpnCommandRejectedInvalidConfig(),
        VpnCommandRejectedPermissionDenied(),
        VpnCommandFailed(),
      ];
      for (final result in results) {
        expect(result.toJson()['type'], result.type);
      }
    });
  });
}

/// Rebuilds a default instance of the given result runtime type, used to
/// prove stateless value equality without mirrors.
VpnCommandResult resultsOf(Type type) {
  if (type == VpnCommandAccepted) {
    return const VpnCommandAccepted();
  }
  if (type == VpnCommandRejectedBusy) {
    return const VpnCommandRejectedBusy();
  }
  if (type == VpnCommandRejectedInvalidConfig) {
    return const VpnCommandRejectedInvalidConfig();
  }
  if (type == VpnCommandRejectedPermissionDenied) {
    return const VpnCommandRejectedPermissionDenied();
  }
  if (type == VpnCommandFailed) {
    return const VpnCommandFailed();
  }
  fail('unreachable: unknown VpnCommandResult runtime type $type');
}
