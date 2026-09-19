// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_utils/shared_utils.dart';
import 'package:test/test.dart';

void main() {
  group('construction and exhaustive matching', () {
    String describe(Result<int, String> result) => switch (result) {
      Ok<int, String>(:final value) => 'ok:$value',
      Err<int, String>(:final error) => 'err:$error',
    };

    test('should expose success when constructed directly or via factory', () {
      const result = Ok<int, String>(42);
      expect(result.value, 42);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(const Result<int, String>.ok(42), result);
      expect(describe(result), 'ok:42');
    });

    test('should expose failure when constructed directly or via factory', () {
      const result = Err<int, String>('rejected');
      expect(result.error, 'rejected');
      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(const Result<int, String>.err('rejected'), result);
      expect(describe(result), 'err:rejected');
    });
  });

  group('map and mapErr', () {
    test('should change success type when mapping an Ok', () {
      var calls = 0;
      final result = const Ok<int, String>(2).map<String>((value) {
        calls++;
        return '$value';
      });
      expect(result, const Ok<String, String>('2'));
      expect(calls, 1);
    });

    test('should preserve error identity when mapping an Err', () {
      final error = Object();
      final result = Err<int, Object>(error).map<String>((_) {
        fail('Success callback must not run');
      });
      expect(result, Err<String, Object>(error));
      expect(result.fold(ok: (_) => null, err: (e) => e), same(error));
    });

    test('should change error type when mapping an Err error', () {
      var calls = 0;
      final result = const Err<int, String>('bad').mapErr<int>((error) {
        calls++;
        return error.length;
      });
      expect(result, const Err<int, int>(3));
      expect(calls, 1);
    });

    test('should preserve value identity when mapping an Ok error', () {
      final value = Object();
      final result = Ok<Object, String>(value).mapErr<int>((_) {
        fail('Error callback must not run');
      });
      expect(result, Ok<Object, int>(value));
      expect(result.fold(ok: (v) => v, err: (_) => null), same(value));
    });

    test('should propagate programmer errors when a transform throws', () {
      final bug = StateError('invariant');
      expect(
        () => const Ok<int, String>(1).map<int>((_) => throw bug),
        throwsA(same(bug)),
      );
      expect(
        () => const Err<int, String>('e').mapErr<int>((_) => throw bug),
        throwsA(same(bug)),
      );
    });
  });

  group('fold', () {
    test('should invoke only success once when folding an Ok', () {
      var calls = 0;
      final value = const Ok<int, String>(2).fold<String>(
        ok: (value) {
          calls++;
          return '$value';
        },
        err: (_) => fail('Error handler must not run'),
      );
      expect(value, '2');
      expect(calls, 1);
    });

    test('should invoke only error once when folding an Err', () {
      var calls = 0;
      final value = const Err<int, String>('e').fold<String>(
        ok: (_) => fail('Success handler must not run'),
        err: (error) {
          calls++;
          return error;
        },
      );
      expect(value, 'e');
      expect(calls, 1);
    });

    test('should propagate programmer errors when a handler throws', () {
      final bug = StateError('invariant');
      expect(
        () =>
            const Ok<int, String>(1)
                .fold<int>(ok: (_) => throw bug, err: (_) => 0),
        throwsA(same(bug)),
      );
      expect(
        () =>
            const Err<int, String>('e')
                .fold<int>(ok: (_) => 0, err: (_) => throw bug),
        throwsA(same(bug)),
      );
    });
  });
}
