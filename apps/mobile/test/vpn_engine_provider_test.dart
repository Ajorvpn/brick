// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';

void main() {
  group('vpnEngineProvider', () {
    test('resolves a VpnEngine bound to the mock implementation', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final engine = container.read(vpnEngineProvider);
      expect(engine, isA<VpnEngine>());
      expect(engine, isA<MockVpnEngine>());
    });

    test('is a stable singleton across repeated reads', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(vpnEngineProvider),
        same(container.read(vpnEngineProvider)),
      );
    });

    test('survives losing all listeners (keepAlive), so a live tunnel is '
        'not killed by navigation', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Watching then unlistening is what auto-dispose would react to.
      final first = container.read(vpnEngineProvider);
      container.listen(vpnEngineProvider, (_, _) {}).close();
      await Future<void>.delayed(Duration.zero);

      // The engine must still be usable, i.e. NOT disposed.
      expect(container.read(vpnEngineProvider), same(first));
      expect(await first.getStatus(), isA<ConnectionState>());
    });

    test('can be overridden with a different engine for tests', () async {
      final stub = MockVpnEngine(connectDelay: Duration.zero);
      final container = ProviderContainer(
        overrides: [vpnEngineProvider.overrideWithValue(stub)],
      );
      addTearDown(container.dispose);

      expect(container.read(vpnEngineProvider), same(stub));
    });
  });
}
