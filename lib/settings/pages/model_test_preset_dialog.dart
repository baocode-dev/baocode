import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_input.dart';
import '../../l10n/l10n.dart';
import '../../models/model_test_preset.dart';
import 'model_dialogs.dart';
import 'settings_widgets.dart';

String modelTestPresetName(AppLocalizations l10n, ModelTestPreset preset) =>
    switch (preset.id) {
      ModelTestPreset.numbersId => l10n.modelsBenchmarkNumbers,
      ModelTestPreset.shortId => l10n.modelsBenchmarkShort,
      _ => preset.name,
    };

Future<ModelTestPreset?> showModelTestPresetDialog(
  BuildContext context, {
  required ModelTestPreset source,
  required bool adding,
}) => showGeneralDialog<ModelTestPreset>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => _PresetEditor(source: source, adding: adding),
);

class _PresetEditor extends StatefulWidget {
  const _PresetEditor({required this.source, required this.adding});
  final ModelTestPreset source;
  final bool adding;
  @override
  State<_PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends State<_PresetEditor> {
  late final _name = TextEditingController(
    text: widget.adding ? '' : widget.source.name,
  );
  late final _prompt = TextEditingController(text: widget.source.prompt);
  bool _invalid = false;

  void _save() {
    if (_name.text.trim().isEmpty || _prompt.text.trim().isEmpty) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(
      context,
      ModelTestPreset(
        id: widget.adding
            ? 'custom-${DateTime.now().microsecondsSinceEpoch}'
            : widget.source.id,
        name: _name.text.trim(),
        prompt: _prompt.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ModelDialogFrame(
      title: widget.adding ? l10n.modelsPresetAdd : l10n.modelsPresetEdit,
      onSubmit: _save,
      actions: [
        IdeButton(label: l10n.commonSave, onPressed: _save),
        IdeButton(
          label: l10n.commonCancel,
          secondary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.modelsName, style: SettingsText.label),
            const SizedBox(height: 6),
            IdeInputBox(
              controller: _name,
              autofocus: true,
              semanticsLabel: l10n.modelsName,
              validation: _invalid && _name.text.trim().isEmpty
                  ? IdeInputValidation(l10n.modelsPresetRequired)
                  : null,
            ),
            const SizedBox(height: 12),
            Text(l10n.modelsBenchmarkPrompt, style: SettingsText.label),
            const SizedBox(height: 6),
            IdeInputBox(
              controller: _prompt,
              minLines: 4,
              maxLines: 10,
              semanticsLabel: l10n.modelsBenchmarkPrompt,
              validation: _invalid && _prompt.text.trim().isEmpty
                  ? IdeInputValidation(l10n.modelsPresetRequired)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
