// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

void main() {
  group('construction', () {
    test('stores bytes and the moment the counters were read', () {
      final moment = DateTime.utc(2026, 1, 1, 12);
      final stats = TrafficStats(
        txBytes: 1024,
        rxBytes: 2048,
        timestamp: moment,
      );

      expect(stats.txBytes, 1024);
      expect(stats.rxBytes, 2048);
      expect(stats.timestamp, moment);
    });
  });

  group('equality and hashCode', () {
    TrafficStats snapshot() => TrafficStats(
      txBytes: 10,
      rxBytes: 20,
      timestamp: DateTime.utc(2026, 2, 2, 8, 30),
    );

    test('snapshots with identical readings are equal', () {
      expect(snapshot(), snapshot());
    });

    test('identical instance takes the fast path', () {
      final stats = snapshot();
      expect(identical(stats, stats), isTrue);
      expect(stats, stats);
    });

    test('each field participates in equality', () {
      final base = snapshot();
      expect(
        base,
        isNot(
          TrafficStats(
            txBytes: 11,
            rxBytes: base.rxBytes,
            timestamp: base.timestamp,
          ),
        ),
      );
      expect(
        base,
        isNot(
          TrafficStats(
            txBytes: base.txBytes,
            rxBytes: 21,
            timestamp: base.timestamp,
          ),
        ),
      );
      expect(
        base,
        isNot(
          TrafficStats(
            txBytes: base.txBytes,
            rxBytes: base.rxBytes,
            timestamp: DateTime.utc(2026, 2, 2, 8, 31),
          ),
        ),
      );
    });

    test('equal snapshots share hashCode', () {
      expect(snapshot().hashCode, snapshot().hashCode);
    });
  });
}
