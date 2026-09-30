/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Confirmations as VS Code draws its own (`window.dialogStyle: custom`):
// an icon, the message and its detail, and the buttons, the first the
// primary one.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/base/browser/ui/dialog/dialog.ts and dialog.css, with the
// `editorWidget.*` and `widget.*` colors of Dark 2026.
//
// Deviations: no checkbox or input rows, and no custom icons.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/codicons.dart';
import 'ide_button.dart';
import 'ide_hover.dart';

/// The dialog's icon (`Severity`, or a question).
enum IdeDialogType { info, warning, error, question }

/// Shows a modal dialog; completes with the index of the chosen button, or
/// null when it was dismissed (the [cancel] button, which VS Code adds to
/// every confirmation, Escape, the close button or a click outside).
Future<int?> showIdeDialog(
  BuildContext context, {
  required String message,
  String? detail,
  required List<String> buttons,
  String? cancel = 'Cancel',
  IdeDialogType type = IdeDialogType.warning,
}) => showGeneralDialog<int>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Dismiss',
  barrierColor: const Color(0x4D000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => _IdeDialog(
    message: message,
    detail: detail,
    buttons: [...buttons, ?cancel],
    cancels: cancel != null,
    type: type,
  ),
);

class _IdeDialog extends StatelessWidget {
  const _IdeDialog({
    required this.message,
    required this.detail,
    required this.buttons,
    required this.cancels,
    required this.type,
  });

  final String message;
  final String? detail;
  final List<String> buttons;

  /// Whether the last button is the Cancel one.
  final bool cancels;
  final IdeDialogType type;

  static const _background = Color(0xFF202122);
  static const _foreground = Color(0xFFBFBFBF);

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      IdeDialogType.info => (Codicons.info, const Color(0xFF3794FF)),
      IdeDialogType.warning => (Codicons.warning, const Color(0xFFCCA700)),
      IdeDialogType.error => (Codicons.error, const Color(0xFFF14C4C)),
      IdeDialogType.question => (Codicons.question, const Color(0xFF3794FF)),
    };
    final width = math.max(
      480.0,
      math.min(560.0, MediaQuery.sizeOf(context).width * .9),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            Navigator.pop(context, 0),
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
                color: _background,
                border: Border.all(color: IdeHoverColors.border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: IdeHoverColors.shadow,
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
                        tooltip: 'Close Dialog',
                        onPressed: () => Navigator.pop(context),
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
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _foreground,
                                  ),
                                ),
                              ),
                              if (detail case final detail?) ...[
                                const SizedBox(height: 4),
                                SelectableText(
                                  detail,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 20 / 13,
                                    color: _foreground,
                                  ),
                                ),
                              ],
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
                              onPressed: () => Navigator.pop(
                                context,
                                cancels && index == buttons.length - 1
                                    ? null
                                    : index,
                              ),
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
