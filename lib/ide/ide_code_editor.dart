import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:bao_editor/monaco/flutter/diff_editor_model.dart'
    show DiffEditorColors;
import 'package:bao_editor/monaco/flutter/editor_code_lens.dart';
import 'package:bao_editor/monaco/flutter/editor_inline_suggest.dart';
import 'package:bao_editor/monaco/flutter/editor_keybindings.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/language_configuration_assets.dart';
import 'package:bao_editor/monaco/flutter/language_overrides.dart';
import 'package:bao_editor/monaco/vs/editor/common/languages/language_configuration_registry.dart'
    show plainTextLanguageConfiguration;
import 'package:bao_editor/textmate/textmate_syntax.dart';

import '../keybindings/keybinding_service.dart';
import '../l10n/command_titles.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/code_font.dart';
import '../theme/workbench_theme.dart' hide ColorScheme;
import 'builtin_formatting.dart';
import 'editor_word_wrap.dart';
import 'ide_agent_edits.dart';
import 'ide_code_find.dart';
import 'ide_find_widget.dart';
import 'ide_menu.dart';
import 'ide_notifications.dart';
import 'ide_status_bar.dart' show IdeLanguageNames;
import 'ide_workspace.dart' show IdeFormatOutcome, IdeWorkspace;
import 'lsp/lsp_protocol.dart';
import 'lsp_ui/lsp_convert.dart';
import 'lsp_ui/minimal_edits.dart';

/// The highlighting of the texts [IdeCodeEditor]s show one after another
/// (the side panel's tabs): one TextMate worker for them all, and each
/// text's tokens kept until [release]d, so a text shown again is colored at
/// once rather than tokenized anew, as the IDE's editor keeps its tabs'.
class IdeCodeHighlights {
  late final TextMateSyntax _textMate = TextMateSyntax(
    themes: WorkbenchThemeService.instance,
  );
  bool _started = false;
  final Map<EditorSurfaceController, (String, TextMateDocument)> _documents =
      {};

  /// The worker, started as it is first asked for; gone with these.
  TextMateSyntax get syntax {
    _started = true;
    return _textMate;
  }

  /// [controller]'s highlighting as the language of [path], if kept.
  TextMateDocument? _documentFor(
    EditorSurfaceController controller,
    String path,
  ) => switch (_documents[controller]) {
    (final kept, final document) when kept == path => document,
    _ => null,
  };

  void _keep(
    EditorSurfaceController controller,
    String path,
    TextMateDocument? document,
  ) {
    final previous = _documents.remove(controller)?.$2;
    if (!identical(previous, document)) previous?.dispose();
    if (document != null) _documents[controller] = (path, document);
  }

  /// Lets go of [controller]'s tokens (its text is gone).
  void release(EditorSurfaceController controller) =>
      _documents.remove(controller)?.$2.dispose();

  void dispose() {
    for (final (_, document) in _documents.values) {
      document.dispose();
    }
    _documents.clear();
    if (_started) _textMate.dispose();
  }
}

/// Formats [path]'s [text] (or [range] of it) with language servers.
typedef IdeTextFormatter = Future<IdeFormatOutcome> Function(
  String path,
  String text, {
  LspRange? range,
  required int tabSize,
  required bool insertSpaces,
});

/// The IDE's editor on its own, for a file edited outside the IDE (a skill,
/// a rule, settings.json, a file beside the chat): [controller]'s text in
/// the workbench's theme, highlighted (TextMate, where the platform has it)
/// and bracketed as the IDE does the language of [path], with the IDE's
/// find and replace ([IdeCodeFind]). No workspace, language server or
/// tabs: the text and its editing alone, with the clipboard and the IDE's
/// formatting in its context menu: by [formatter]'s language servers, else
/// the IDE's own ([BuiltinFormatting]). An agent's change pending in it
/// ([agent]) shows as the IDE's editor shows it, each part to keep or undo.
class IdeCodeEditor extends StatefulWidget {
  const IdeCodeEditor({
    super.key,
    required this.controller,
    required this.path,
    this.focusNode,
    this.readOnly = false,
    this.bare = false,
    this.decorations = const [],
    this.decorationProviders = const [],
    this.inlineSuggest,
    this.codeLens,
    this.gutterIconBuilder,
    this.highlights,
    this.interfaceSized = false,
    this.formatter,
    this.agent,
    this.background,
    this.glyphMargin = true,
  });

  final EditorSurfaceController controller;

  /// What its language is picked by.
  final String path;
  final FocusNode? focusNode;
  final bool readOnly;

  /// Only the text: no line numbers, margins, folds or indent guides, and no
  /// scrolling past its last line. For a sample to be looked at.
  final bool bare;

  /// Painted over the text (lines marked, say).
  final List<EditorDecoration> decorations;

  /// The extension-driven features to paint too (decoration types, inlay
  /// hints), each searched per visible line.
  final List<EditorDecorationProvider> decorationProviders;

  /// Ghost text of an inline completion, if any.
  final EditorInlineSuggestController? inlineSuggest;

  /// CodeLenses, if any.
  final EditorCodeLensController? codeLens;

  /// The image of a decoration's `gutterIconPath`; none painted without it.
  final Widget Function(BuildContext context, EditorGutterIcon icon)?
  gutterIconBuilder;

  /// Where its highlighting is kept past it; its own, gone with it, when
  /// null.
  final IdeCodeHighlights? highlights;

  /// Sized as the window's text is ([AppFonts.uiCodeStyle]), not by the
  /// code size: for a file shown beside the chat.
  final bool interfaceSized;

  /// Formats its text with the project's language servers, shared with
  /// the IDE ([IdeWorkspace.formatOutside]); the IDE's own formatting
  /// alone when null.
  final IdeTextFormatter? formatter;

  /// An agent's change pending in the text, shown in it with Undo and Keep
  /// by each part (as the IDE's editor shows one).
  final IdeAgentDiff? agent;

  /// Behind its text; the editor's when null (a page's own, where it is
  /// laid on one).
  final Color? background;

  /// The margin left of the line numbers (breakpoints, decorations'
  /// icons); none where nothing goes there.
  final bool glyphMargin;

  @override
  State<IdeCodeEditor> createState() => IdeCodeEditorState();
}

class IdeCodeEditorState extends State<IdeCodeEditor> {
  final GlobalKey _surfaceKey = GlobalKey();
  final WorkbenchThemeService _themes = WorkbenchThemeService.instance;
  TextMateSyntax? _ownTextMate;
  TextMateDocument? _highlight;

  TextMateSyntax get _textMate =>
      widget.highlights?.syntax ??
      (_ownTextMate ??= TextMateSyntax(themes: _themes));

  /// Bumped as the language is to be picked anew: an older pick is dropped.
  int _language = 0;

  late final IdeCodeFind _find = IdeCodeFind(
    widget.controller,
    readOnly: widget.readOnly,
  )..addListener(_findChanged);

  /// The text's own, unless it is given one.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode(debugLabel: 'code'));

  /// Bumped as the text scrolls: what is placed by its lines follows.
  final ValueNotifier<int> _viewTick = ValueNotifier(0);

  /// The editor, once laid out.
  EditorSurfaceView? get view => switch (_surfaceKey.currentState) {
    final EditorSurfaceView view => view,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _themes.addListener(_themeChanged);
    widget.controller.addListener(_textChanged);
    EditorLanguageOverrides.instance.addListener(_languageModesChanged);
    _pickLanguage();
  }

  void _findChanged() {
    if (mounted) setState(() {});
  }

  /// A language picked for a file (Change Language Mode): this one's
  /// picked again, as it is now.
  void _languageModesChanged() {
    if (!mounted) return;
    final highlights = widget.highlights;
    _letGo(widget);
    highlights?.release(widget.controller);
    unawaited(_pickNewLanguage(++_language));
  }

  @override
  void didUpdateWidget(IdeCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _find
      ..controller = widget.controller
      ..readOnly = widget.readOnly;
    if (!identical(oldWidget.agent, widget.agent)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _highlightAgent());
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_textChanged);
      widget.controller.addListener(_textChanged);
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.path != widget.path ||
        !identical(oldWidget.highlights, widget.highlights)) {
      // Not the last text's colors on this one meanwhile.
      _letGo(oldWidget);
      _pickLanguage();
    }
  }

  @override
  void dispose() {
    _language++;
    _themes.removeListener(_themeChanged);
    widget.controller.removeListener(_textChanged);
    EditorLanguageOverrides.instance.removeListener(_languageModesChanged);
    _letGo(widget);
    _find.dispose();
    _ownFocusNode?.dispose();
    _viewTick.dispose();
    _ownTextMate?.dispose();
    super.dispose();
  }

  /// Stops showing the highlighting; disposes it unless [old]'s
  /// highlights keep it.
  void _letGo(IdeCodeEditor old) {
    final highlight = _highlight;
    _highlight = null;
    highlight?.removeListener(_highlighted);
    if (old.highlights == null) {
      highlight?.dispose();
    } else {
      highlight?.clearViewport();
    }
  }

  void _show(TextMateDocument? highlight) {
    _highlight = highlight?..addListener(_highlighted);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewChanged();
      _highlightAgent();
    });
  }

  /// The deleted code of [IdeCodeEditor.agent]'s change in the text's
  /// language too; after the build (its host hears of it).
  void _highlightAgent() {
    final languageId = _highlight?.languageId;
    if (!mounted || languageId == null) return;
    widget.agent?.diff.highlight(_textMate, languageId);
  }

  void _themeChanged() {
    if (mounted) setState(() {});
  }

  /// Tokens follow the edit at once; the worker sends the lines it
  /// retokenizes.
  void _textChanged() {
    final highlight = _highlight;
    final snapshot = widget.controller.document.snapshot;
    if (highlight == null || identical(highlight.snapshot, snapshot)) return;
    highlight.update(snapshot);
  }

  /// The kept highlighting at once (its language configuration is on the
  /// controller already), else the language picked anew.
  void _pickLanguage() {
    final request = ++_language;
    if (widget.highlights?._documentFor(widget.controller, widget.path)
        case final kept?) {
      _show(kept);
      _textChanged();
      return;
    }
    unawaited(_pickNewLanguage(request));
  }

  Future<void> _pickNewLanguage(int request) async {
    final controller = widget.controller;
    final path = widget.path;
    final highlights = widget.highlights;
    final snapshot = controller.document.snapshot;
    final firstLine = snapshot.text.substring(0, snapshot.contentEnds.first);
    final first = firstLine.startsWith('﻿')
        ? firstLine.substring(1)
        : firstLine;
    try {
      final configuration = await languageConfigurationForPath(
        path,
        firstLine: first,
      );
      if (!mounted || request != _language) return;
      controller.languageConfiguration =
          configuration ?? plainTextLanguageConfiguration;
      final languageId = await _textMate.languageIdForPath(
        path,
        firstLine: first,
      );
      if (!mounted || request != _language) return;
      _letGo(widget);
      final highlight = languageId == null
          ? null
          : _textMate.open(languageId, controller.document.snapshot);
      highlights?._keep(controller, path, highlight);
      setState(() => _show(highlight));
    } on Object {
      // Plain text, then: the editing is the same.
    }
  }

  /// Scrolls the text from [start] to [end] into view, centered where it
  /// was out of it; once laid out.
  void revealRange(int start, int end) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final view = _surfaceKey.currentState;
      if (mounted && view is EditorSurfaceView) {
        (view as EditorSurfaceView).revealRange(start, end);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _highlighted() {
    if (mounted) setState(() {});
  }

  /// Its language, as highlighted; by the extension until then.
  String? get _languageId =>
      _highlight?.languageId ??
      switch (p.extension(widget.path).toLowerCase()) {
        '.json' => 'json',
        '.jsonc' => 'jsonc',
        _ => null,
      };

  /// Whether Format Document is offered: where it can be edited, and
  /// language servers or the IDE itself may format it.
  bool get _formats =>
      !widget.readOnly &&
      (widget.formatter != null || BuiltinFormatting.supports(_languageId));

  bool get _hasSelection =>
      widget.controller.selections.any((selection) => !selection.isCollapsed);

  static const _formatCommands = {
    'editor.action.formatDocument',
    'editor.action.formatSelection',
    'editor.action.format',
  };

  /// The IDE editor's find commands, run by [IdeCodeFind].
  static const _findCommands = {
    'actions.find',
    'editor.action.startFindReplaceAction',
    'editor.action.nextMatchFindAction',
    'editor.action.previousMatchFindAction',
    'editor.action.nextSelectionMatchFindAction',
    'editor.action.previousSelectionMatchFindAction',
    'actions.findWithSelection',
    'closeFindWidget',
    'toggleFindCaseSensitive',
    'toggleFindWholeWord',
    'toggleFindRegex',
    'editor.action.replaceOne',
    'editor.action.replaceAll',
  };

  /// Find and replace, Format Document, Format Selection and Toggle Word
  /// Wrap by their keybindings.
  KeyEventResult _onKey(KeyEvent event) {
    final found = KeybindingService.instance.resolveEvent(
      event,
      context: (key) => switch (key) {
        'editorTextFocus' || 'editorFocus' || 'textInputFocus' => true,
        'editorReadonly' => widget.readOnly,
        'editorHasSelection' => _hasSelection,
        'findWidgetVisible' => _find.visible,
        'findInputFocussed' || 'replaceInputFocussed' => false,
        'editorHasFormattingProvider' ||
        'editorHasDocumentFormattingProvider' ||
        'editorHasDocumentSelectionFormattingProvider' => _formats,
        _ => null,
      },
      canRun: (item) =>
          _findCommands.contains(item.command) ||
          item.command == EditorWordWrap.commandId ||
          _formats && _formatCommands.contains(item.command),
    );
    if (found is! KeybindingFound) return KeyEventResult.ignored;
    if (found.command == EditorWordWrap.commandId) {
      EditorWordWrap.toggle();
      return KeyEventResult.handled;
    }
    if (_findCommands.contains(found.command)) {
      return _find.runCommand(found.command)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    unawaited(
      _format(
        selection:
            found.command == 'editor.action.formatSelection' ||
            found.command == 'editor.action.format' && _hasSelection,
      ),
    );
    return KeyEventResult.handled;
  }

  /// Bumped by each format: an older one's answer is dropped.
  int _formatting = 0;

  /// Format Document (Format Selection with [selection]: the lines
  /// selected, the caret's when none is), as one undo step keeping the
  /// cursors: by [IdeCodeEditor.formatter]'s language servers, else the
  /// IDE itself; else says there is no formatter, and which server would
  /// be one.
  Future<void> _format({bool selection = false}) async {
    final controller = widget.controller;
    final request = ++_formatting;
    final version = controller.document.version;
    final snapshot = controller.document.snapshot;
    IdeFormatOutcome? outcome;
    if (widget.formatter case final formatter?) {
      LspRange? range;
      if (selection) {
        final selected = controller.value.selection;
        if (selected.isCollapsed) {
          final line =
              snapshot.positionAtOffset(selected.extentOffset).lineNumber - 1;
          range = lspRangeOf(
            snapshot,
            snapshot.lineStarts[line],
            snapshot.contentEnds[line],
          );
        } else {
          range = lspRangeOf(snapshot, selected.start, selected.end);
        }
      }
      try {
        outcome = await formatter(
          widget.path,
          snapshot.text,
          range: range,
          tabSize: controller.tabSize,
          insertSpaces: controller.insertSpaces,
        );
      } on Object catch (error) {
        if (mounted) {
          IdeNotificationsScope.maybeOf(context)
              ?.notify(IdeSeverity.error, '$error');
        }
        return;
      }
      if (!mounted ||
          request != _formatting ||
          controller.document.version != version) {
        return;
      }
      if (outcome.edits case final edits?) {
        final offsets = lspOffsetEdits(snapshot, edits);
        if (offsets != null && offsets.isNotEmpty) {
          controller.applyEdits(minimalOffsetEdits(snapshot.text, offsets));
        }
        return;
      }
    }
    if (BuiltinFormatting.supports(_languageId)) {
      BuiltinFormatting.format(controller, _languageId, selection: selection);
      return;
    }
    _noFormatter(selection: selection, outcome: outcome);
  }

  void _noFormatter({required bool selection, IdeFormatOutcome? outcome}) {
    final notifications = IdeNotificationsScope.maybeOf(context);
    if (notifications == null) return;
    final l10n = context.l10n;
    if (outcome case IdeFormatOutcome(:final missing?, :final install?)) {
      notifications.notify(
        IdeSeverity.info,
        l10n.langNoFormatterInstall(
          missing,
          IdeLanguageNames.forPath(widget.path),
        ),
        primary: [
          IdeNotificationAction(l10n.extInstall, () async {
            try {
              await install();
            } on Object catch (error) {
              notifications.notify(IdeSeverity.error, '$error');
            }
          }),
        ],
      );
      return;
    }
    notifications.notify(
      IdeSeverity.info,
      selection ? l10n.langNoSelectionFormatter : l10n.langNoFormatter,
    );
  }

  void _runEditorCommand(String id) {
    final host = _surfaceKey.currentState;
    if (!mounted || host is! EditorViewHost) return;
    runEditorCommand(id, widget.controller, host as EditorViewHost);
  }

  /// Formatting (where the IDE formats the language), then the clipboard.
  void _showContextMenu(Offset position) {
    final l10n = context.l10n;
    final keys = KeybindingService.instance;
    IdeMenuAction item(
      String id,
      String english,
      VoidCallback run, {
      bool enabled = true,
    }) => IdeMenuAction(
      localizedCommandLabel(l10n, id, english),
      keybinding: keys.labelFor(id),
      enabled: enabled,
      onSelected: run,
    );
    IdeMenuAction editorItem(String id, {bool enabled = true}) => item(
      id,
      editorCommandLabels[id]!,
      () => _runEditorCommand(id),
      enabled: enabled,
    );
    final editable = !widget.readOnly;
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          if (_formats)
            [
              item(
                'editor.action.formatDocument',
                editorLanguageCommandLabels['editor.action.formatDocument']!,
                () => unawaited(_format()),
              ),
              if (_hasSelection)
                item(
                  'editor.action.formatSelection',
                  editorLanguageCommandLabels['editor.action.formatSelection']!,
                  () => unawaited(_format(selection: true)),
                ),
            ],
          [
            editorItem('editor.action.clipboardCutAction', enabled: editable),
            editorItem('editor.action.clipboardCopyAction'),
            editorItem('editor.action.clipboardPasteAction', enabled: editable),
          ],
          [wordWrapMenuAction(l10n)],
        ]),
      ),
    );
  }

  /// The lines on screen go to the TextMate worker first.
  void _viewChanged() {
    if (!mounted) return;
    _viewTick.value++;
    final highlight = _highlight;
    final view = _surfaceKey.currentState;
    if (!mounted || highlight == null || view is! EditorSurfaceView) return;
    if ((view as EditorSurfaceView).visibleLineRange case final range?) {
      highlight.setViewport(range.first, range.last);
    }
  }

  /// Keeps or undoes a part of [agent]'s change, telling of what failed.
  Future<void> _actOnAgentChange(Future<void> Function() act) async {
    try {
      await act();
    } on Object catch (error) {
      if (mounted) {
        IdeNotificationsScope.maybeOf(context)
            ?.notify(IdeSeverity.error, '$error');
      }
    }
  }

  /// Undo and Keep by each part of [agent]'s change; null without one.
  Widget? _agentHunkActions(IdeAgentDiff? agent) {
    final changes = agent?.diff.model.mappings;
    if (agent == null || changes == null || changes.isEmpty) return null;
    // Placed by the text as laid out this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewTick.value++;
    });
    return IdeAgentHunkActions(
      changes: changes,
      snapshot: widget.controller.document.snapshot,
      view: () => view,
      repaint: _viewTick,
      onUndo: (change) =>
          unawaited(_actOnAgentChange(() => agent.undo(change))),
      onKeep: (change) =>
          unawaited(_actOnAgentChange(() => agent.keep(change))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _themes.colors;
    final style =
        (widget.interfaceSized
                ? AppFonts.uiCodeStyle(13)
                : AppFonts.codeStyle(13))
            .copyWith(color: colors['editor.foreground'], height: 1.45);
    final agent = widget.bare ? null : widget.agent;
    // In the code's scale, which the deleted code of an agent change is
    // drawn in.
    Widget surface(BuildContext context) {
      final parts = agent?.parts(
        colors: DiffEditorColors.from(colors.get),
        style: style,
        textScaler: MediaQuery.textScalerOf(context),
      );
      return ValueListenableBuilder(
        valueListenable: EditorWordWrap.on,
        builder: (context, wrap, _) => EditorSurface(
          key: _surfaceKey,
          controller: widget.controller,
          focusNode: _focusNode,
          readOnly: widget.readOnly,
          // The font's sample shows its lines as they are.
          wrap: wrap && !widget.bare,
          lineNumbers: !widget.bare,
          glyphMargin: widget.glyphMargin && !widget.bare,
          folding: !widget.bare,
          indentGuides: !widget.bare,
          scrollBeyondLastLine: !widget.bare,
          backgroundColor: widget.background ?? colors['editor.background'],
          selectionColor: colors['editor.selectionBackground'],
          caretColor: colors['editorCursor.foreground'],
          // The gutter on its background too, where it lies on a page.
          theme: EditorViewTheme.fromColors(
            (id) => id == 'editorGutter.background' && widget.background != null
                ? widget.background
                : colors.get(id),
          ),
          styledLines: _highlight?.styledLines,
          showMinimap: false,
          decorations: [
            ...widget.decorations,
            ...?parts?.decorations,
            ..._find.decorations,
          ],
          viewZones: parts?.zones ?? const [],
          decorationProviders: widget.decorationProviders,
          inlineSuggest: widget.inlineSuggest,
          codeLens: widget.codeLens,
          codeLensColors: EditorCodeLensColors.from(colors.get),
          gutterIconBuilder: widget.gutterIconBuilder,
          onViewChanged: _viewChanged,
          onKeyEvent: widget.bare ? null : _onKey,
          onContextMenu: widget.bare ? null : _showContextMenu,
          style: style,
        ),
      );
    }

    final text = widget.interfaceSized
        ? Builder(builder: surface)
        : CodeTextScale(child: Builder(builder: surface));
    if (widget.bare) return text;
    return Stack(
      children: [
        Positioned.fill(child: text),
        if (_agentHunkActions(agent) case final hunks?)
          Positioned.fill(child: hunks),
        if (_find.visible)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: SizedBox(
                    width: math.min(
                      IdeFindWidget.width,
                      math.max(240, constraints.maxWidth - 28),
                    ),
                    child: _find.widget(
                      onClose: () {
                        if (_focusNode.canRequestFocus) {
                          _focusNode.requestFocus();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
