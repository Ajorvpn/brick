// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';

/// Screen for adding one server by pasting its URI.
///
/// Flow: paste → Parse → review protocol/host → Save.
///
/// ### Why parsing is a separate step
///
/// Parse and Save are distinct so the user sees what was understood before
/// anything is written to disk. The parsed protocol and endpoint are the
/// only parts of the URI that are ever displayed; the credential-bearing
/// remainder is never echoed back.
///
/// ### Credential handling
///
/// On failure the screen shows `ConfigParseError.message`, **never** the raw
/// input. That is not a stylistic choice: `config_parse_error.dart` states
/// every variant stores only structural metadata and that no variant holds
/// the offending value, so `message` is structurally incapable of carrying
/// a UUID or password. The raw text stays inside the [TextField] the user
/// typed it into.
///
/// Layering: `presentation/`. Calls the saved-servers provider only; the
/// parsing itself happens in the `domain/` use case, never in the widget.
class AddServerScreen extends ConsumerStatefulWidget {
  /// Creates the add-server screen.
  const AddServerScreen({super.key});

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  final TextEditingController _controller = TextEditingController();

  /// What the last Parse produced, for the Save button to act on.
  ///
  /// `null` means nothing valid has been parsed, so Save stays disabled.
  String? _validatedUri;

  /// Protocol/endpoint of the last successful parse, shown as a preview.
  ParsedUriSummary? _summary;

  /// Localized parse-failure message, or `null` when the last parse passed.
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Validates the pasted text without persisting it.
  Future<void> _parse() async {
    final uri = _controller.text.trim();
    if (uri.isEmpty) {
      setState(() {
        _summary = null;
        _errorMessage = 'connection.uri_required'.tr();
      });
      return;
    }

    // Validation only — nothing is written here. The user confirms what was
    // understood before any storage write happens.
    final validation = await ref
        .read(savedServersProvider.notifier)
        .validateUri(uri);
    if (!mounted) {
      return;
    }
    setState(() {
      if (validation.isValid) {
        _summary = validation.summary;
        _errorMessage = null;
        _validatedUri = uri;
      } else {
        _summary = null;
        _validatedUri = null;
        // `message` is a ConfigParseError.message, which by contract never
        // interpolates the offending input.
        _errorMessage = validation.message;
      }
    });
  }

  /// Persists the validated URI and returns to the list.
  Future<void> _save() async {
    final uri = _validatedUri;
    if (uri == null) {
      return;
    }
    final error = await ref.read(savedServersProvider.notifier).addServer(uri);
    if (!mounted) {
      return;
    }
    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('connection.add_server'.tr())),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              // Not a password field: the user must be able to see what they
              // pasted. Obfuscation is not the control here — secure storage
              // is, and that is tracked as a Phase 11 blocker.
              decoration: InputDecoration(
                labelText: 'connection.uri_label'.tr(),
                border: const OutlineInputBorder(),
              ),
              // Enter should not submit a form that does not exist.
              onSubmitted: (_) => _parse(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _parse,
                    child: Text('connection.parse'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    // Enabled only once a Parse has succeeded, so Save can
                    // never write an unvalidated URI.
                    onPressed: _validatedUri == null ? null : _save,
                    child: Text('connection.save'.tr()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_summary != null)
              Text(
                // Protocol + endpoint only: the credential-bearing remainder
                // of the URI is never rendered here.
                '${_summary!.protocol} · ${_summary!.endpoint}',
                key: const ValueKey<String>('add_server_parsed'),
              ),
            if (_summary != null) const SizedBox(height: 8),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                key: const ValueKey<String>('add_server_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
