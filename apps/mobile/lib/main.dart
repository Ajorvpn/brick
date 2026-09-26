// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/router/app_router.dart';

void main() {
  // `ProviderScope` is the root of the Riverpod container: every provider
  // in the app (`lib/core/`, and each feature's `presentation/providers/`)
  // is resolved from this scope. Keeping it here — and nowhere else — means
  // a test can replace the whole container by pumping its own
  // `ProviderScope` with `overrides:` (see CODING_STANDARDS.md Section 4).
  runApp(const ProviderScope(child: MyApp()));
}

/// Application root.
///
/// [ConsumerWidget] because it reads exactly one provider — the router —
/// and nothing else. Per CODING_STANDARDS.md Section 4, widgets should
/// watch only the specific providers they need; keeping this list at one
/// entry means unrelated state changes never rebuild the root.
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(routerConfig: router, title: 'Brick VPN');
  }
}
