/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The editor shown for a file the text editor does not show: VS Code's
// placeholder editors.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/browser/parts/editor/editorPlaceholder.ts (layout and the
// error editor), media/editorplaceholder.css, binaryEditor.ts (binary
// files), src/vs/workbench/contrib/files/browser/editors/textFileEditor.ts
// and src/vs/workbench/common/editor.ts (`createTooLargeFileError`).
//
// Deviations: no Configure Limit (there is no setting for it), no Create
// File for a missing file, and no Show Logs; a file not shown can be opened
// in its default app.

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'file_service.dart';
import 'ide_button.dart';

/// The placeholder's colors in the color theme.
abstract final class IdePlaceholderColors {
  static Color get error => themeColors['editorError.foreground'];
  static Color get warning => themeColors['editorWarning.foreground'];

  /// The workbench's `foreground`, which it inherits.
  static Color get label => themeColors['foreground'];
}

/// An action of a placeholder: its first is the primary button.
typedef IdePlaceholderAction = ({String label, VoidCallback run});

/// What the placeholder for [error] says, in [l10n]'s language (English
/// when null), and the icon it shows.
({IconData icon, Color color, String label}) idePlaceholderContents(
  Object error, {
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? englishLocalizations;
  return switch (error) {
    IdeBinaryFileException() => (
      icon: Codicons.warning,
      color: IdePlaceholderColors.warning,
      label: strings.placeholderBinary,
    ),
    IdeFileTooLargeException(:final size) => (
      icon: Codicons.warning,
      color: IdePlaceholderColors.warning,
      label: strings.placeholderTooLarge(ideFormatSize(size)),
    ),
    IdeFileNotFoundException() => (
      icon: Codicons.error,
      color: IdePlaceholderColors.error,
      label: strings.placeholderNotFound,
    ),
    _ => (
      icon: Codicons.error,
      color: IdePlaceholderColors.error,
      label: strings.placeholderUnexpected,
    ),
  };
}

/// `ByteSize.formatSize`: bytes whole, larger units to two places.
String ideFormatSize(int size) {
  const kb = 1024, mb = kb * 1024, gb = mb * 1024, tb = gb * 1024;
  if (size < kb) return '${size}B';
  if (size < mb) return '${(size / kb).toStringAsFixed(2)}KB';
  if (size < gb) return '${(size / mb).toStringAsFixed(2)}MB';
  if (size < tb) return '${(size / gb).toStringAsFixed(2)}GB';
  return '${(size / tb).toStringAsFixed(2)}TB';
}

/// `.monaco-editor-pane-placeholder`: a 48px icon, the label (14px, at
/// most 450px wide) and the buttons, centered 10px apart. The icon goes
/// when there is 200px or less of height.
class IdeEditorPlaceholder extends StatelessWidget {
  const IdeEditorPlaceholder({
    super.key,
    required this.error,
    required this.onOpenAnyway,
    required this.onRetry,
    this.onOpenInDefaultApp,
  });

  final Object error;

  /// Binary and very large files: Open Anyway.
  final VoidCallback onOpenAnyway;

  /// Other errors: Try Again.
  final VoidCallback onRetry;

  /// Opens the file in the app the system opens it with, for a file that
  /// is there; none where there is no such app (the web).
  final VoidCallback? onOpenInDefaultApp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final contents = idePlaceholderContents(error, l10n: l10n);
    final IdePlaceholderAction? external = switch (onOpenInDefaultApp) {
      final run? when error is! IdeFileNotFoundException => (
        label: l10n.openInDefaultApp,
        run: run,
      ),
      _ => null,
    };
    final List<IdePlaceholderAction> actions = switch (error) {
      // A binary file is likelier one for another app than for text.
      IdeBinaryFileException() => [
        ?external,
        (label: l10n.placeholderOpenAnyway, run: onOpenAnyway),
      ],
      IdeFileTooLargeException() => [
        (label: l10n.placeholderOpenAnyway, run: onOpenAnyway),
        ?external,
      ],
      _ => [(label: l10n.placeholderTryAgain, run: onRetry), ?external],
    };
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (constraints.maxHeight > 200) ...[
                  Icon(contents.icon, size: 48, color: contents.color),
                  const SizedBox(height: 10),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: SelectableText(
                    contents.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: IdePlaceholderColors.label,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (final (index, action) in actions.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 5,
                        ),
                        child: IdeButton(
                          label: action.label,
                          secondary: index > 0,
                          onPressed: action.run,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
