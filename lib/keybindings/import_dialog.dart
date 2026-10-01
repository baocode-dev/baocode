/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Importing keybindings from VS Code, Cursor and the like: which editor's
// (or profile's) `keybindings.json`, whether it replaces ours or merges
// into it, and whether their keymap extension comes along; then what was
// imported, and which commands the app does not have yet.
//
// Drawn as VS Code draws its own dialogs (see ide_dialog.dart), with its
// checkboxes: src/vs/base/browser/ui/toggle/toggle.css
// (`.monaco-custom-toggle.monaco-checkbox`) at VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971, colored by the theme's
// `checkbox.*` colors.
//
// Deviations: VS Code has no such dialog, and no radio buttons of this
// kind; they are its checkboxes, round.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ide/ide_button.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_quick_input.dart' show IdeKeycap;
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'keybinding_entry.dart';
import 'vscode_import.dart';

/// Imports [source]'s keybindings into ours ([importKeybindings]).
typedef ImportKeybindings = Future<KeybindingsImportReport> Function(
  KeybindingsSource source,
  KeybindingsImportMode mode,
);

/// Imports a keymap extension ([importKeymapExtension]).
typedef ImportKeymap = Future<KeymapImportResult> Function(
  KeymapExtension extension,
);

/// Makes keymap [id] the one in use (the `baocode.keymap` setting).
typedef SelectKeymap = FutureOr<void> Function(String id);

/// Shows [KeybindingsImportDialog]; completes when it is closed.
Future<void> showKeybindingsImportDialog(
  BuildContext context, {
  required KeybindingsDetection detection,
  required ImportKeybindings importKeybindings,
  required ImportKeymap importKeymap,
  required SelectKeymap selectKeymap,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => KeybindingsImportDialog(
    detection: detection,
    importKeybindings: importKeybindings,
    importKeymap: importKeymap,
    selectKeymap: selectKeymap,
  ),
);

/// The import dialog: [detection]'s sources and keymaps to pick from, then
/// the report.
class KeybindingsImportDialog extends StatefulWidget {
  const KeybindingsImportDialog({
    super.key,
    required this.detection,
    required this.importKeybindings,
    required this.importKeymap,
    required this.selectKeymap,
  });

  final KeybindingsDetection detection;
  final ImportKeybindings importKeybindings;
  final ImportKeymap importKeymap;
  final SelectKeymap selectKeymap;

  @override
  State<KeybindingsImportDialog> createState() =>
      _KeybindingsImportDialogState();
}

/// What the import did: each part's result or error.
class _Outcome {
  KeybindingsSource? source;
  KeybindingsImportReport? report;
  KeymapImportResult? keymap;
  final errors = <String>[];
}

class _KeybindingsImportDialogState extends State<KeybindingsImportDialog> {
  KeybindingsSource? _source;
  var _mode = KeybindingsImportMode.merge;

  /// The keymap to import and use, if any.
  KeymapExtension? _keymap;
  var _importing = false;
  _Outcome? _outcome;

  @override
  void initState() {
    super.initState();
    final sources = widget.detection.sources;
    _source =
        sources.where((source) => source.entryCount > 0).firstOrNull ??
        sources.firstOrNull;
    _keymap = widget.detection.keymaps.firstOrNull;
  }

  bool get _canImport =>
      !_importing && _outcome == null && (_source != null || _keymap != null);

  Future<void> _import() async {
    if (!_canImport) return;
    final l10n = context.l10n;
    setState(() => _importing = true);
    final outcome = _Outcome()..source = _source;
    if (_source case final source?) {
      try {
        outcome.report = await widget.importKeybindings(source, _mode);
      } on Object catch (error) {
        outcome.errors.add(l10n.impKeybindingsError('$error'));
      }
    }
    if (_keymap case final extension?) {
      try {
        final result = await widget.importKeymap(extension);
        await widget.selectKeymap(result.id);
        outcome.keymap = result;
      } on Object catch (error) {
        outcome.errors.add(l10n.impKeymapError(extension.name, '$error'));
      }
    }
    if (!mounted) return;
    setState(() {
      _importing = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final border = colors.get('widget.border');
    final shadow = colors.get('widget.shadow');
    final size = MediaQuery.sizeOf(context);
    final width = math.max(480.0, math.min(560.0, size.width * .9));
    final outcome = _outcome;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            outcome == null ? _import() : Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.6),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: width,
              constraints: BoxConstraints(maxHeight: size.height * .85),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: border == null ? null : Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  const BoxShadow(color: Color(0x26000000), blurRadius: 20),
                  if (shadow != null) BoxShadow(color: shadow, blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, top: 4),
                          child: _Text(
                            context.l10n.impTitle,
                            size: 14,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IdeActionButton(
                        icon: Codicons.close,
                        tooltip: context.l10n.dialogCloseDialog,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: outcome == null
                            ? _choices()
                            : _report(outcome),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        if (outcome == null) ...[
                          _button(
                            context.l10n.impImport,
                            _canImport ? _import : null,
                          ),
                          _button(
                            context.l10n.commonCancel,
                            () => Navigator.pop(context),
                            secondary: true,
                          ),
                        ] else
                          _button(
                            context.l10n.commonClose,
                            () => Navigator.pop(context),
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

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    bool secondary = false,
  }) => Padding(
    padding: const EdgeInsets.all(4),
    child: IdeButton(label: label, secondary: secondary, onPressed: onPressed),
  );

  List<Widget> _choices() {
    final sources = widget.detection.sources;
    final keymaps = widget.detection.keymaps;
    final l10n = context.l10n;
    return [
      if (sources.isEmpty && keymaps.isEmpty)
        _Text(l10n.impNothingFound, description: true),
      if (sources.isNotEmpty) ...[
        _Heading(l10n.impKeybindingsFrom),
        for (final source in sources)
          _Choice(
            radio: true,
            checked: _source == source,
            label: source.label,
            description: l10n.impKeybindingCount(source.entryCount),
            detail: source.path,
            onChanged: _importing
                ? null
                : () => setState(() => _source = source),
          ),
        const SizedBox(height: 12),
        _Heading(l10n.impImportAs),
        _Choice(
          radio: true,
          checked: _mode == KeybindingsImportMode.merge,
          label: l10n.impMerge,
          detail: l10n.impMergeDetail,
          onChanged: _importing
              ? null
              : () => setState(() => _mode = KeybindingsImportMode.merge),
        ),
        _Choice(
          radio: true,
          checked: _mode == KeybindingsImportMode.replace,
          label: l10n.impReplace,
          detail: l10n.impReplaceDetail,
          onChanged: _importing
              ? null
              : () => setState(() => _mode = KeybindingsImportMode.replace),
        ),
      ],
      if (keymaps.isNotEmpty) ...[
        const SizedBox(height: 12),
        _Heading(l10n.kbKeymap),
        for (final keymap in keymaps)
          _Choice(
            checked: _keymap == keymap,
            label: l10n.impAlsoUse(keymap.name),
            description: keymap.version,
            detail: l10n.impInstalledIn(
              [for (final product in keymap.products) product.label].join(', '),
            ),
            onChanged: _importing
                ? null
                : () => setState(
                    () => _keymap = _keymap == keymap ? null : keymap,
                  ),
          ),
      ],
    ];
  }

  List<Widget> _report(_Outcome outcome) {
    final report = outcome.report;
    final keymap = outcome.keymap;
    final platform = KeybindingPlatform.current;
    final l10n = context.l10n;
    return [
      if (report != null) ...[
        _Text(
          l10n.impImportedFrom(outcome.source!.label),
          weight: FontWeight.w600,
        ),
        const SizedBox(height: 4),
        _Text(
          report.unsupported.isEmpty
              ? l10n.impApplied(report.supported)
              : l10n.impAppliedUnsupported(
                  report.supported,
                  report.unsupported.length,
                ),
        ),
        if (report.duplicates > 0)
          _Text(l10n.impDuplicates(report.duplicates), description: true),
        if (report.backupPath case final backup?)
          _Text(l10n.impBackup(backup), description: true),
        if (report.unsupported.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Heading(l10n.impNotSupportedYet),
          _Text(l10n.impNotSupportedDetail, description: true),
          const SizedBox(height: 6),
          for (final entry in report.unsupported)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  if (entry.keyFor(platform) case final key?
                      when key.isNotEmpty) ...[
                    IdeKeycap(key),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: _Text(entry.command, selectable: true)),
                ],
              ),
            ),
        ],
      ],
      if (keymap != null) ...[
        if (report != null) const SizedBox(height: 12),
        _Text(
          keymap.builtIn
              ? l10n.impKeymapBuiltIn(keymap.name)
              : l10n.impKeymapImported(keymap.name),
        ),
      ],
      for (final error in outcome.errors) ...[
        const SizedBox(height: 8),
        _Text(error, color: themeColors['errorForeground'], selectable: true),
      ],
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: _Text(text, weight: FontWeight.w600),
  );
}

/// 13px text in the dialog's color, or the description color.
class _Text extends StatelessWidget {
  const _Text(
    this.text, {
    this.size = 13,
    this.weight,
    this.description = false,
    this.color,
    this.selectable = false,
  });

  final String text;
  final double size;
  final FontWeight? weight;
  final bool description;
  final Color? color;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: size,
      height: 18 / 13,
      fontWeight: weight,
      color:
          color ??
          themeColors[description
              ? 'descriptionForeground'
              : 'editorWidget.foreground'],
    );
    return selectable
        ? SelectableText(text, style: style)
        : Text(text, style: style);
  }
}

/// A checkbox (`.monaco-checkbox`) or radio button with its label, a
/// [description] beside it and a [detail] under it.
class _Choice extends StatefulWidget {
  const _Choice({
    this.radio = false,
    required this.checked,
    required this.label,
    this.description,
    this.detail,
    required this.onChanged,
  });

  final bool radio;
  final bool checked;
  final String label;
  final String? description;
  final String? detail;
  final VoidCallback? onChanged;

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final enabled = widget.onChanged != null;
    final box = Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.only(right: 9),
      decoration: BoxDecoration(
        color: colors['checkbox.background'],
        border: Border.all(
          color: _focused ? colors['focusBorder'] : colors['checkbox.border'],
        ),
        shape: widget.radio ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.radio ? null : BorderRadius.circular(3),
      ),
      child: widget.checked
          ? Icon(
              widget.radio ? Codicons.circleSmallFilled : Codicons.check,
              size: widget.radio ? 14 : 16,
              color: colors['checkbox.foreground'],
            )
          : null,
    );
    return Semantics(
      checked: widget.checked,
      inMutuallyExclusiveGroup: widget.radio,
      enabled: enabled,
      label: widget.label,
      value: widget.description,
      hint: widget.detail,
      onTap: widget.onChanged,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onChanged?.call(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onChanged,
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  box,
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              text: widget.label,
                              children: [
                                if (widget.description case final description?)
                                  TextSpan(
                                    text: '  $description',
                                    style: TextStyle(
                                      color: colors['descriptionForeground'],
                                    ),
                                  ),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              height: 18 / 13,
                              color: colors['editorWidget.foreground'],
                            ),
                          ),
                          if (widget.detail case final detail?)
                            Text(
                              detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 16 / 12,
                                color: colors['descriptionForeground'],
                              ),
                            ),
                        ],
                      ),
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
