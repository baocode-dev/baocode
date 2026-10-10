/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The active document's language status items as one status bar entry: its
// icon the most severe item's (`{}`, `{·}`, `{!}`) or a spinner while one is
// busy, its hover listing each item's label, detail and command, its click
// a menu of those commands.
//
// Adapted from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/languageStatus/browser/languageStatus.ts
// (`_update`'s combined entry, `_severityToComboCodicon`, `_renderStatus`).
//
// Deviations: no pinned (dedicated) entries; the commands are offered in a
// menu on click, where upstream's hover has links.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_menu.dart';
import '../../ide/ide_status_bar.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../window/codicon_label.dart';
import 'language_status.dart';

/// `_severityToComboCodicon`.
String _comboCodicon(int severity) => switch (severity) {
  LanguageStatusSeverity.error => r'$(bracket-error)',
  LanguageStatusSeverity.warning => r'$(bracket-dot)',
  _ => r'$(bracket)',
};

/// [statuses] (the active document's, in order) as the status bar's
/// language status entry; null for none. [run] runs a command.
IdeStatusBarItem? extensionLanguageStatusItem(
  List<LanguageStatus> statuses, {
  required String name,
  required Future<void> Function(Map<String, Object?> command) run,
  required BuildContext Function() context,
}) {
  if (statuses.isEmpty) return null;
  final busy = statuses.any((s) => s.busy);
  final first = statuses.first;
  return IdeStatusBarItem(
    busy ? r'$(loading~spin)' : _comboCodicon(first.severity),
    key: const ValueKey('status.languageStatus'),
    semanticsLabel:
        '$name: ${[for (final s in statuses) s.accessibilityLabel ?? '${s.label} ${s.detail}'.trim()].join(', ')}',
    tooltipContent: _LanguageStatusHover(statuses),
    onTap: () {
      final commands = [
        for (final status in statuses)
          if (status.command case final command?) (status, command),
      ];
      if (commands.isEmpty) return;
      final buildContext = context();
      final box = buildContext.findRenderObject() as RenderBox?;
      unawaited(
        showIdeMenu(
          buildContext,
          position: box == null
              ? Offset.zero
              : box.localToGlobal(box.size.bottomRight(Offset.zero)),
          entries: [
            for (final (status, command) in commands)
              IdeMenuAction(
                '${status.name}: ${command['title'] ?? command['id']}',
                onSelected: () => unawaited(run(command)),
              ),
          ],
        ),
      );
    },
  );
}

class _LanguageStatusHover extends StatelessWidget {
  const _LanguageStatusHover(this.statuses);

  final List<LanguageStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final foreground = themeColors['editorHoverWidget.foreground'];
    final description = themeColors['descriptionForeground'];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final status in statuses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExtensionLabel.parse(
                          status.text.isEmpty ? status.name : status.text,
                        ).build(fontSize: 13, color: foreground),
                        if (status.detail.isNotEmpty)
                          ExtensionLabel.parse(status.detail)
                              .build(fontSize: 12, color: description),
                      ],
                    ),
                  ),
                  if (status.command case final command?)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        '${command['title'] ?? ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: themeColors['textLink.foreground'],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
