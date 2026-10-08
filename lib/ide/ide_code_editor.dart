import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/language_configuration_assets.dart';
import 'package:bao_editor/monaco/vs/editor/common/languages/language_configuration_registry.dart'
    show plainTextLanguageConfiguration;
import 'package:bao_editor/textmate/textmate_syntax.dart';

import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' hide ColorScheme;

/// The highlighting of the texts [IdeCodeEditor]s show one after another
/// (the side panel's tabs): one TextMate worker for them all, and each
/// text's tokens kept until [release]d, so a text shown again is colored at
/// once rather than tokenized anew, as the IDE's editor keeps its tabs'.
class IdeCodeHighlights {
  late final TextMateSyntax syntax = TextMateSyntax(
    themes: WorkbenchThemeService.instance,
  );
  bool _started = false;
  final Map<EditorSurfaceController, (String, TextMateDocument)> _documents =
      {};

  TextMateSyntax get _syntax {
    _started = true;
    return syntax;
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
    if (_started) syntax.dispose();
  }
}

/// The IDE's editor on its own, for a file edited outside the IDE (a skill,
/// a rule, settings.json): [controller]'s text in the workbench's theme,
/// highlighted (TextMate, where the platform has it) and bracketed as the
/// IDE does the language of [path]. No workspace, language server, find or
/// tabs: the text and its editing alone.
class IdeCodeEditor extends StatefulWidget {
  const IdeCodeEditor({
    super.key,
    required this.controller,
    required this.path,
    this.focusNode,
    this.readOnly = false,
    this.decorations = const [],
    this.highlights,
  });

  final EditorSurfaceController controller;

  /// What its language is picked by.
  final String path;
  final FocusNode? focusNode;
  final bool readOnly;

  /// Painted over the text (lines marked, say).
  final List<EditorDecoration> decorations;

  /// Where its highlighting is kept past it; its own, gone with it, when
  /// null.
  final IdeCodeHighlights? highlights;

  @override
  State<IdeCodeEditor> createState() => IdeCodeEditorState();
}

class IdeCodeEditorState extends State<IdeCodeEditor> {
  final GlobalKey _surfaceKey = GlobalKey();
  final WorkbenchThemeService _themes = WorkbenchThemeService.instance;
  TextMateSyntax? _ownTextMate;
  TextMateDocument? _highlight;

  TextMateSyntax get _textMate =>
      widget.highlights?._syntax ??
      (_ownTextMate ??= TextMateSyntax(themes: _themes));

  /// Bumped as the language is to be picked anew: an older pick is dropped.
  int _language = 0;

  @override
  void initState() {
    super.initState();
    _themes.addListener(_themeChanged);
    widget.controller.addListener(_textChanged);
    _pickLanguage();
  }

  @override
  void didUpdateWidget(IdeCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _letGo(widget);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _viewChanged());
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

  /// The lines on screen go to the TextMate worker first.
  void _viewChanged() {
    final highlight = _highlight;
    final view = _surfaceKey.currentState;
    if (!mounted || highlight == null || view is! EditorSurfaceView) return;
    if ((view as EditorSurfaceView).visibleLineRange case final range?) {
      highlight.setViewport(range.first, range.last);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _themes.colors;
    return EditorSurface(
      key: _surfaceKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly,
      backgroundColor: colors['editor.background'],
      selectionColor: colors['editor.selectionBackground'],
      caretColor: colors['editorCursor.foreground'],
      theme: EditorViewTheme.fromColors(colors.get),
      styledLines: _highlight?.styledLines,
      showMinimap: false,
      decorations: widget.decorations,
      onViewChanged: _viewChanged,
      style: AppFonts.codeStyle(13)
          .copyWith(color: colors['editor.foreground'], height: 1.45),
    );
  }
}
