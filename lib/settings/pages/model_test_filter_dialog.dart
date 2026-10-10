import 'package:flutter/material.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_input.dart';
import '../../l10n/l10n.dart';
import 'model_dialogs.dart';
import 'model_test_table.dart';
import 'settings_widgets.dart';

Future<ModelTestColumnFilter?> showModelTestFilterDialog(
  BuildContext context, {
  required ModelTestColumn column,
  required ModelTestColumnFilter filter,
}) => showGeneralDialog<ModelTestColumnFilter>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) =>
      _ColumnFilterDialog(column: column, filter: filter),
);

class _ColumnFilterDialog extends StatefulWidget {
  const _ColumnFilterDialog({required this.column, required this.filter});
  final ModelTestColumn column;
  final ModelTestColumnFilter filter;
  @override
  State<_ColumnFilterDialog> createState() => _ColumnFilterDialogState();
}

class _ColumnFilterDialogState extends State<_ColumnFilterDialog> {
  late final _text = TextEditingController(text: widget.filter.text);
  late final _minimum = TextEditingController(
    text: widget.filter.minimum?.toString(),
  );
  late final _maximum = TextEditingController(
    text: widget.filter.maximum?.toString(),
  );
  bool _invalid = false;

  void _apply() {
    final min = ModelTestColumnFilter.parseNumber(_minimum.text, widget.column);
    final max = ModelTestColumnFilter.parseNumber(_maximum.text, widget.column);
    if (_minimum.text.trim().isNotEmpty && min == null ||
        _maximum.text.trim().isNotEmpty && max == null ||
        min != null && max != null && min > max) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(
      context,
      ModelTestColumnFilter(
        text: _text.text.trim(),
        minimum: min,
        maximum: max,
      ),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ModelDialogFrame(
      title: '${l10n.modelsTableFilter} · ${widget.column.label(l10n)}',
      onSubmit: _apply,
      actions: [
        IdeButton(
          label: l10n.modelsTableClear,
          secondary: true,
          onPressed: () =>
              Navigator.pop(context, const ModelTestColumnFilter()),
        ),
        IdeButton(label: l10n.modelsFetchApply, onPressed: _apply),
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
            Text(l10n.modelsTableContains, style: SettingsText.label),
            const SizedBox(height: 6),
            IdeInputBox(
              controller: _text,
              autofocus: true,
              semanticsLabel: l10n.modelsTableContains,
            ),
            if (widget.column.numeric) ...[
              const SizedBox(height: 12),
              Text(
                widget.column.time
                    ? l10n.modelsTableTimeRange
                    : l10n.modelsTableNumberRange,
                style: SettingsText.description,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: IdeInputBox(
                      controller: _minimum,
                      placeholder: l10n.modelsTableMinimum,
                      semanticsLabel: l10n.modelsTableMinimum,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IdeInputBox(
                      controller: _maximum,
                      placeholder: l10n.modelsTableMaximum,
                      semanticsLabel: l10n.modelsTableMaximum,
                    ),
                  ),
                ],
              ),
              if (_invalid) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.modelsTableInvalidRange,
                  style: SettingsText.description,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
