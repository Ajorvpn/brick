// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/features/connection/presentation/providers/add_server_controller.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

/// Screen for adding a single server profile by manually pasting its URI.
///
/// Implements the direct-save UX mandated by P5-T2: when the user taps Save,
/// the configuration URI is validated and parsed via `config_parser`. If
/// valid, it is persisted immediately and the route pops back to Home. If
/// invalid, the parsed error message is presented via [AppFeedback] and
/// rendered inline on the input field. All user-facing strings are resolved
/// through `.tr()`.
class AddServerScreen extends ConsumerStatefulWidget {
  /// Creates the add-server screen.
  const AddServerScreen({super.key});

  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _inlineError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Reads plain text from system clipboard and populates the text field.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      setState(() {
        _controller.text = text.trim();
        _inlineError = null;
      });
    }
  }

  /// Submits the entered URI directly to the controller.
  Future<void> _save() async {
    setState(() => _inlineError = null);
    final uri = _controller.text;
    final result = await ref
        .read(addServerControllerProvider.notifier)
        .submit(uri);
    if (!mounted) return;
    switch (result) {
      case Ok():
        context.pop();
      case Err(:final error):
        final message = ErrorMapper.mapToUserMessage(error);
        setState(() => _inlineError = message);
        AppFeedback.showError(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(addServerControllerProvider);
    final isLoading = controllerState.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text('add_server.title'.tr())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('add_server_uri_field'),
                controller: _controller,
                enabled: !isLoading,
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: 'add_server.uri_label'.tr(),
                  hintText: 'add_server.paste_hint'.tr(),
                  errorText: _inlineError,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    key: const ValueKey<String>('add_server_paste_button'),
                    icon: const Icon(Icons.paste),
                    tooltip: 'add_server.paste_from_clipboard'.tr(),
                    onPressed: isLoading ? null : _pasteFromClipboard,
                  ),
                ),
                onChanged: (_) {
                  if (_inlineError != null) {
                    setState(() => _inlineError = null);
                  }
                },
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                key: const ValueKey<String>('add_server_save_button'),
                onPressed: isLoading ? null : _save,
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('add_server.save'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
