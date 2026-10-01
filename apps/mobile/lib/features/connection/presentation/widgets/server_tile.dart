// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart' show ServerProfile;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';

/// One row in the saved-server list.
///
/// Renders a [SavedServerProfile] as name + protocol + endpoint, or a
/// [SavedServerBroken] as an error entry with a Remove action.
///
/// Protocol is **text only** (e.g. `vless`), taken from
/// `OutboundConfig.protocol.scheme`. Deliberate: icons for eight protocols
/// are easy to confuse, and the brief specifies text.
///
/// A broken entry renders no endpoint and no Connect button — it can never
/// reach the engine — and shows only [SavedServerBroken.reason], which
/// `config_parser` guarantees does not interpolate the offending input.
class ServerTile extends StatelessWidget {
  /// Creates a tile for [server].
  const ServerTile({
    required this.server,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRemove,
    super.key,
  });

  /// The entry to render.
  final SavedServer server;

  /// Invoked with this profile when Connect is tapped.
  final void Function(ServerProfile profile) onConnect;

  /// Invoked when Disconnect is tapped.
  final VoidCallback onDisconnect;

  /// Invoked when Remove is tapped (broken entries only).
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return switch (server) {
      SavedServerProfile() => _buildProfile(context),
      SavedServerBroken() => _buildBroken(context),
    };
  }

  Widget _buildProfile(BuildContext context) {
    final profile = server as SavedServerProfile;

    return Card(
      key: ValueKey<String>('server_tile_${profile.id}'),
      child: ListTile(
        title: Text(profile.name),
        // Protocol and endpoint are the non-secret identity of the server.
        //
        // Keyed per entry: the tile also renders Connect/Disconnect `Text`
        // buttons, so a type-based or positional finder cannot distinguish
        // this line from its siblings and silently asserts on the wrong
        // widget when the layout changes.
        subtitle: Text(
          '${profile.protocolLabel} · ${profile.endpoint}',
          key: ValueKey<String>('server_tile_subtitle_${profile.id}'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => onConnect(profile.profile),
              child: Text('connection.connect'.tr()),
            ),
            TextButton(
              onPressed: onDisconnect,
              child: Text('connection.disconnect'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBroken(BuildContext context) {
    final broken = server as SavedServerBroken;

    return Card(
      key: ValueKey<String>('server_tile_broken_${broken.id}'),
      child: ListTile(
        title: Text('connection.broken_title'.tr()),
        // The reason is a ConfigParseError.message, which by contract never
        // contains the pasted input, so no credential is echoed here.
        // Keyed for the same reason as the profile tile's subtitle above.
        subtitle: Text(
          broken.reason,
          key: ValueKey<String>('server_tile_subtitle_${broken.id}'),
        ),
        trailing: TextButton(
          onPressed: onRemove,
          child: Text('connection.remove'.tr()),
        ),
      ),
    );
  }
}
