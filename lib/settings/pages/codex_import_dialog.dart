import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_input.dart';
import '../../l10n/l10n.dart';
import 'model_dialogs.dart';
import 'settings_widgets.dart';

/// Credentials stay in this dialog until the user explicitly imports them.
Future<String?> showCodexImportDialog(BuildContext context) =>
    showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierLabel: context.l10n.commonDismiss,
      barrierColor: const Color(0x80000000),
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => const _CodexImportDialog(),
    );

class _CodexImportDialog extends StatefulWidget {
  const _CodexImportDialog();

  @override
  State<_CodexImportDialog> createState() => _CodexImportDialogState();
}

class _CodexImportDialogState extends State<_CodexImportDialog> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    if (_input.text.trim().isEmpty) return;
    Navigator.pop(context, _input.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ModelDialogFrame(
      title: l10n.modelsAccountsImportTitle,
      maxWidth: 640,
      actions: [
        IdeButton(
          label: l10n.modelsAccountsImport,
          onPressed: _input.text.trim().isEmpty ? null : _submit,
        ),
        IdeButton(
          label: l10n.commonCancel,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.modelsAccountsImportConfirmDetail,
            style: SettingsText.description,
          ),
          const SizedBox(height: 12),
          Flexible(
            child: IdeInputBox(
              controller: _input,
              autofocus: true,
              minLines: 6,
              maxLines: 10,
              semanticsLabel: l10n.modelsAccountsPaste,
              placeholder: l10n.modelsAccountsPastePlaceholder,
              onChanged: (_) => setState(() {}),
              shortcuts: {
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    _submit,
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _submit,
              },
            ),
          ),
        ],
      ),
    );
  }
}
