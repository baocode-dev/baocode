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
  });

  final EditorSurfaceController controller;

  /// What its language is picked by.
  final String path;
  final FocusNode? focusNode;
  final bool readOnly;

  /// Painted over the text (lines marked, say).
  final List<EditorDecoration> decorations;

  @override
  State<IdeCodeEditor> createState() => IdeCodeEditorState();
}

class IdeCodeEditorState extends State<IdeCodeEditor> {
  final GlobalKey _surfaceKey = GlobalKey();
  final WorkbenchThemeService _themes = WorkbenchThemeService.instance;
  late final TextMateSyntax _textMate = TextMateSyntax(themes: _themes);
  TextMateDocument? _highlight;

  /// Bumped as the language is to be picked anew: an older pick is dropped.
  int _language = 0;

  @override
  void initState() {
    super.initState();
    _themes.addListener(_themeChanged);
    widget.controller.addListener(_textChanged);
    unawaited(_pickLanguage());
  }

  @override
  void didUpdateWidget(IdeCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_textChanged);
      widget.controller.addListener(_textChanged);
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.path != widget.path) {
      unawaited(_pickLanguage());
    }
  }

  @override
  void dispose() {
    _language++;
    _themes.removeListener(_themeChanged);
    widget.controller.removeListener(_textChanged);
    _highlight?.dispose();
    _textMate.dispose();
    super.dispose();
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

  Future<void> _pickLanguage() async {
    final request = ++_language;
    final controller = widget.controller;
    final path = widget.path;
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
      _highlight?.dispose();
      _highlight = languageId == null
          ? null
          : (_textMate.open(languageId, controller.document.snapshot)
              ?..addListener(_highlighted));
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _viewChanged());
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
      style: TextStyle(
        color: colors['editor.foreground'],
        fontFamily: AppFonts.mono,
        fontSize: 13,
        height: 1.45,
      ),
    );
  }
}
