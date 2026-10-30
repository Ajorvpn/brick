// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Placeholder screen for the `servers` feature (P4-T5 skeleton).
///
/// Full dynamic server list, addition flows, and QR scanning will be built
/// in Phase 5.
class ServersScreen extends StatelessWidget {
  /// Creates the servers screen.
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('servers.title'.tr())),
      body: Center(
        child: Text(
          'servers.placeholder'.tr(),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
