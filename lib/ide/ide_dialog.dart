/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Confirmations as VS Code draws its own (`window.dialogStyle: custom`):
// an icon, the message and its detail, and the buttons, the first the
// primary one.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/dialog/dialog.ts and dialog.css, with the color
// theme's colors of dialogs (platform/theme/browser/defaultStyles.ts
// `defaultDialogStyles`).
//
// Deviations: no custom icons.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_button.dart';
import 'ide_hover.dart';
import 'ide_input.dart';

/// The dialog's icon (`Severity`, or a question).
enum IdeDialogType { info, warning, error, question }

/// An input row of a dialog (`IInput`): [obscure] for a password.
class IdeDialogInput {
  const IdeDialogInput({
    this.placeholder,
    this.value = '',
    this.obscure = false,
  });

  final String? placeholder;
  final String value;
  final bool obscure;
}

/// What a dialog was answered with (`IInputResult`): the button chosen,
/// the inputs' values and whether the checkbox was checked.
typedef IdeDialogResult = ({int button, List<String> values, bool checked});

/// [showIdeDialog]'s default `cancel`: Cancel, in the display language.
const ideDialogCancel = '\u0000cancel';

/// Shows a modal dialog; completes with the index of the chosen button, or
/// null when it was dismissed (the [cancel] button, which VS Code adds to
/// every confirmation, Escape, the close button or a click outside).
/// [cancel] is Cancel in the display language unless given; null for none.
Future<int?> showIdeDialog(
  BuildContext context, {
  required String message,
  String? detail,
  required List<String> buttons,
  String? cancel = ideDialogCancel,
  IdeDialogType type = IdeDialogType.warning,
}) => showIdeInputDialog(
  context,
  message: message,
  detail: detail,
  buttons: buttons,
  cancel: cancel,
  type: type,
).then((result) => result?.button);

/// [showIdeDialog] with [inputs] under the message and a [checkbox] (its
/// label) under them, [checked] at first: the button chosen and what was
/// given, or null when dismissed.
Future<IdeDialogResult?> showIdeInputDialog(
  BuildContext context, {
  required String message,
  String? detail,
  required List<String> buttons,
  List<IdeDialogInput> inputs = const [],
  String? checkbox,
  bool checked = false,
  String? cancel = ideDialogCancel,
  IdeDialogType type = IdeDialogType.warning,
}) => showGeneralDialog<IdeDialogResult>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  // `.monaco-dialog-modal-block.dimmed`: the same in every theme.
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => _IdeDialog(
    message: message,
    detail: detail,
    buttons: [
      ...buttons,
      ?(cancel == ideDialogCancel ? context.l10n.commonCancel : cancel),
    ],
    cancels: cancel != null,
    type: type,
    inputs: inputs,
    checkbox: checkbox,
    checked: checked,
  ),
);

class _IdeDialog extends StatefulWidget {
  const _IdeDialog({
    required this.message,
    required this.detail,
    required this.buttons,
    required this.cancels,
    required this.type,
    this.inputs = const [],
    this.checkbox,
    this.checked = false,
  });

  final String message;
  final String? detail;
  final List<String> buttons;

  /// Whether the last button is the Cancel one.
  final bool cancels;
  final IdeDialogType type;
  final List<IdeDialogInput> inputs;
  final String? checkbox;
  final bool checked;

  @override
  State<_IdeDialog> createState() => _IdeDialogState();
}

class _IdeDialogState extends State<_IdeDialog> {
  late final List<TextEditingController> _inputs = [
    for (final input in widget.inputs) TextEditingController(text: input.value),
  ];
  late bool _checked = widget.checked;

  @override
  void dispose() {
    for (final input in _inputs) {
      input.dispose();
    }
    super.dispose();
  }

  var _closed = false;

  /// Closes with [button] chosen; the Cancel one dismisses. Once: Enter
  /// in an input is both a shortcut here and the input's submission.
  void _close(int? button) {
    if (_closed) return;
    _closed = true;
    Navigator.pop(
      context,
      button == null || (widget.cancels && button == widget.buttons.length - 1)
          ? null
          : (
              button: button,
              values: [for (final input in _inputs) input.text],
              checked: _checked,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (message, detail, buttons, type) = (
      widget.message,
      widget.detail,
      widget.buttons,
      widget.type,
    );
    final colors = themeColors;
    final (icon, color) = switch (type) {
      IdeDialogType.info => (
        Codicons.info,
        colors['problemsInfoIcon.foreground'],
      ),
      IdeDialogType.warning => (
        Codicons.warning,
        colors['problemsWarningIcon.foreground'],
      ),
      IdeDialogType.error => (
        Codicons.error,
        colors['problemsErrorIcon.foreground'],
      ),
      IdeDialogType.question => (
        Codicons.question,
        colors['problemsInfoIcon.foreground'],
      ),
    };
    final foreground = colors['editorWidget.foreground'];
    final border = colors.get('widget.border');
    final shadow = colors.get('widget.shadow');
    final width = math.max(
      480.0,
      math.min(560.0, MediaQuery.sizeOf(context).width * .9),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _close(null),
        const SingleActivator(LogicalKeyboardKey.enter): () => _close(0),
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.6),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: border == null ? null : Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  // `--vscode-shadow-xl`, and the theme's around it.
                  const BoxShadow(color: Color(0x26000000), blurRadius: 20),
                  if (shadow != null) BoxShadow(color: shadow, blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 24,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: IdeActionButton(
                        icon: Codicons.close,
                        tooltip: context.l10n.dialogCloseDialog,
                        onPressed: () => _close(null),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 24, color: color),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 22,
                                ),
                                child: SelectableText(
                                  message,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: foreground,
                                  ),
                                ),
                              ),
                              if (detail case final detail?) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  detail,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 20 / 13,
                                    color: foreground,
                                  ),
                                ),
                              ],
                              // `.dialog-message-input`
                              for (final (i, input) in widget.inputs.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: IdeInputBox(
                                    controller: _inputs[i],
                                    placeholder: input.placeholder,
                                    obscureText: input.obscure,
                                    autofocus: i == 0,
                                    semanticsLabel: input.placeholder,
                                    onSubmitted: (_) => _close(0),
                                  ),
                                ),
                              // `.dialog-checkbox-row`
                              if (widget.checkbox case final label?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: _DialogCheckbox(
                                    label: label,
                                    checked: _checked,
                                    onChanged: () =>
                                        setState(() => _checked = !_checked),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20, left: 67),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        for (final (index, label) in buttons.indexed)
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: IdeButton(
                              label: label,
                              secondary: index > 0,
                              onPressed: () => _close(index),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dialog's checkbox and its label (`.monaco-checkbox`, 18px).
class _DialogCheckbox extends StatefulWidget {
  const _DialogCheckbox({
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final VoidCallback onChanged;

  @override
  State<_DialogCheckbox> createState() => _DialogCheckboxState();
}

class _DialogCheckboxState extends State<_DialogCheckbox> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Semantics(
      checked: widget.checked,
      label: widget.label,
      onTap: widget.onChanged,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onChanged(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onChanged,
          child: ExcludeSemantics(
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: colors['checkbox.background'],
                    border: Border.all(
                      color: _focused
                          ? colors['focusBorder']
                          : colors['checkbox.border'],
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: widget.checked
                      ? Icon(
                          Codicons.check,
                          size: 16,
                          color: colors['checkbox.foreground'],
                        )
                      : null,
                ),
                Flexible(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors['editorWidget.foreground'],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
