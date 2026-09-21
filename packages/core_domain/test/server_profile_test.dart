// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:test/test.dart';

void main() {
  final addedAt = DateTime.utc(2026, 9, 21, 12);
  final lastUsedAt = DateTime.utc(2026, 9, 21, 13);
  final config = VlessOutbound(server: 'v.example', serverPort: 443, uuid: 'u');

  ServerProfile buildProfile() => ServerProfile(
    id: 'p1',
    name: 'Home server',
    config: config,
    addedAt: addedAt,
  );

  group('construction', () {
    test('should expose every field when fully constructed', () {
      final profile = ServerProfile(
        id: 'p2',
        name: 'Backup',
        config: config,
        addedAt: addedAt,
        lastUsedAt: lastUsedAt,
        subscriptionId: 'sub-1',
      );
      expect(profile.id, 'p2');
      expect(profile.name, 'Backup');
      expect(identical(profile.config, config), isTrue);
      expect(profile.addedAt, addedAt);
      expect(profile.lastUsedAt, lastUsedAt);
      expect(profile.subscriptionId, 'sub-1');
      expect(profile.schemaVersion, 1);
    });

    test('should default lastUsedAt and subscriptionId to null', () {
      final profile = buildProfile();
      expect(profile.lastUsedAt, isNull);
      expect(profile.subscriptionId, isNull);
    });
  });

  group('equality and hashCode', () {
    test(
      'profiles with identical field values are equal and share hashCode',
      () {
        expect(buildProfile(), buildProfile());
        expect(buildProfile().hashCode, buildProfile().hashCode);
      },
    );

    test('profiles differing only in id are not equal', () {
      final other = buildProfile().copyWith(id: 'other');
      expect(buildProfile(), isNot(other));
    });

    test('profiles differing only in config payload are not equal', () {
      final other = buildProfile().copyWith(
        config: VlessOutbound(server: 'v.example', serverPort: 443, uuid: 'u2'),
      );
      expect(buildProfile(), isNot(other));
    });

    test('the identical instance takes the fast path', () {
      final profile = buildProfile();
      expect(identical(profile, profile), isTrue);
      expect(profile, profile);
    });
  });

  group('copyWith', () {
    test('should return an equal profile when no field is overridden', () {
      final profile = buildProfile();
      expect(profile.copyWith(), profile);
    });

    test('should replace id', () {
      expect(buildProfile().copyWith(id: 'x').id, 'x');
    });

    test('should replace name', () {
      expect(buildProfile().copyWith(name: 'Office').name, 'Office');
    });

    test('should replace config', () {
      final trojanConfig = TrojanOutbound(
        server: 't.example',
        serverPort: 443,
        password: 'p',
      );
      expect(
        buildProfile().copyWith(config: trojanConfig).config,
        trojanConfig,
      );
    });

    test('should replace addedAt', () {
      final when = DateTime.utc(2026, 1, 1);
      expect(buildProfile().copyWith(addedAt: when).addedAt, when);
    });

    test('should replace lastUsedAt and subscriptionId when provided', () {
      final updated = buildProfile().copyWith(
        lastUsedAt: lastUsedAt,
        subscriptionId: 'sub-9',
      );
      expect(updated.lastUsedAt, lastUsedAt);
      expect(updated.subscriptionId, 'sub-9');
    });

    test('should keep existing nullable values when override is omitted', () {
      // Documented limitation: copyWith cannot clear a nullable field back
      // to null; omitted overrides keep the current value.
      final updated = buildProfile().copyWith(lastUsedAt: lastUsedAt);
      expect(updated.copyWith().lastUsedAt, lastUsedAt);
    });
  });

  group('toJson', () {
    test(
      'should nest the polymorphic config JSON and stamp schema_version',
      () {
        final json = buildProfile().toJson();
        expect(json['id'], 'p1');
        expect(json['name'], 'Home server');
        expect(json['added_at'], '2026-09-21T12:00:00.000Z');
        expect(json['schema_version'], 1);
        final configJson = json['config'] as Map<String, dynamic>;
        expect(configJson['type'], 'vless');
        expect(configJson['server'], 'v.example');
        expect(configJson['server_port'], 443);
        expect(json.containsKey('last_used_at'), isFalse);
        expect(json.containsKey('subscription_id'), isFalse);
      },
    );

    test('should include optional timestamps when set', () {
      final json = buildProfile()
          .copyWith(lastUsedAt: lastUsedAt, subscriptionId: 'sub-1')
          .toJson();
      expect(json['last_used_at'], '2026-09-21T13:00:00.000Z');
      expect(json['subscription_id'], 'sub-1');
    });
  });
}
