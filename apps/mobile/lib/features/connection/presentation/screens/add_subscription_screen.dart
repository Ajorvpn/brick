// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/features/connection/presentation/providers/add_subscription_controller.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

/// Screen for adding a subscription source and importing its server profiles.
///
/// Features:
/// 1. URL and Name text fields with clipboard paste affordance.
/// 2. Import button that invokes [AddSubscriptionController.submit].
/// 3. Partial success policy: shows success snackbar with imported server count
///    and navigates back cleanly.
/// 4. Error mapping via [ErrorMapper.mapToUserMessage] and
///    [AppFeedback.showError].
/// 5. Full localization across all strings.
class AddSubscriptionScreen extends ConsumerStatefulWidget {
  /// Creates the add subscription screen.
  const AddSubscriptionScreen({super.key});

  /// Maximum allowed characters for the subscription URL field.
  static const int maxUrlInputLength = 8256;

  /// Maximum allowed characters for the subscription display name field.
  static const int maxNameInputLength = 128;

  @override
  ConsumerState<AddSubscriptionScreen> createState() =>
      _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends ConsumerState<AddSubscriptionScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  String? _inlineError;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      final trimmed = text.trim();
      final bounded = trimmed.length > AddSubscriptionScreen.maxUrlInputLength
          ? trimmed.substring(0, AddSubscriptionScreen.maxUrlInputLength)
          : trimmed;
      setState(() {
        _urlController.text = bounded;
        _inlineError = null;
      });
    }
  }

  Future<void> _import() async {
    setState(() => _inlineError = null);
    final url = _urlController.text;
    final name = _nameController.text;

    final result = await ref
        .read(addSubscriptionControllerProvider.notifier)
        .submit(url, rawName: name);

    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        final message = value.skippedCount > 0
            ? 'add_subscription.partial_success_message'.tr(
                namedArgs: {
                  'count': value.importedCount.toString(),
                  'skipped': value.skippedCount.toString(),
                },
              )
            : 'add_subscription.success_message'.tr(
                namedArgs: {'count': value.importedCount.toString()},
              );
        AppFeedback.showSuccess(context, message);
        context.pop();
      case Err(:final error):
        final message = ErrorMapper.mapToUserMessage(error);
        setState(() => _inlineError = message);
        AppFeedback.showError(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controllerState = ref.watch(addSubscriptionControllerProvider);
    final isLoading = controllerState.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text('add_subscription.title'.tr())),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey<String>('add_subscription_url_field'),
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'add_subscription.url_label'.tr(),
                hintText: 'add_subscription.url_hint'.tr(),
                errorText: _inlineError,
                suffixIcon: IconButton(
                  key: const ValueKey<String>('add_subscription_paste_button'),
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'add_subscription.paste_from_clipboard'.tr(),
                  onPressed: isLoading ? null : _pasteFromClipboard,
                ),
              ),
              enabled: !isLoading,
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  AddSubscriptionScreen.maxUrlInputLength,
                ),
              ],
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey<String>('add_subscription_name_field'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'add_subscription.name_label'.tr(),
                hintText: 'add_subscription.name_hint'.tr(),
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(
                  AddSubscriptionScreen.maxNameInputLength,
                ),
              ],
              enabled: !isLoading,
              autocorrect: false,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey<String>('add_subscription_import_button'),
              onPressed: isLoading ? null : _import,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('add_subscription.import_button'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
