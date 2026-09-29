import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../theme/cursor_theme.dart';
import 'editor/monaco/flutter/document_snapshot.dart';
import 'editor/monaco/flutter/editor_surface.dart';
import 'editor/monaco/flutter/editor_surface_controller.dart';
import 'editor/monaco/flutter/monaco_syntax.dart';
import 'editor/monaco/flutter/selection_adapter.dart';
import 'editor/monaco/flutter/theme_assets.dart';
import 'editor/monaco/vs/editor/common/core/cursor_columns.dart';
import 'editor/monaco/vs/editor/common/core/position.dart';
import 'editor/monaco/vs/editor/contrib/find/browser/replace_pattern.dart';
import 'editor/monaco/vs/editor/common/model/search/piece_tree_search.dart';
import 'editor/monaco/flutter/editor_document_model.dart';
import 'ide_workspace.dart';

/// A Flutter editor with the experimental painted surface available by opt-in.
/// TextField remains the default while the surface's editing parity is evaluated.
class IdeEditor extends StatefulWidget {
  const IdeEditor({
    super.key,
    required this.workspace,
    required this.active,
    required this.onError,
    required this.onLspStatus,
    required this.onPositionChanged,
    this.nativeEditorEnabled = const bool.fromEnvironment(
      'MONAD_NATIVE_EDITOR',
      defaultValue: false,
    ),
  });

  final IdeWorkspace workspace;
  final IdeDocument active;
  final ValueChanged<Object> onError;
  final ValueChanged<String> onLspStatus;
  final ValueChanged<({Position position, int statusColumn})> onPositionChanged;

  /// Opt in with --dart-define=MONAD_NATIVE_EDITOR=true, or override in tests.
  /// This surface is experimental, not a claim of TextField or Monaco parity.
  final bool nativeEditorEnabled;

  @override
  State<IdeEditor> createState() => IdeEditorState();
}

class IdeEditorState extends State<IdeEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.active.text,
  );
  late final FocusNode _focusNode = FocusNode(debugLabel: 'ide editor');
  late final ScrollController _scrollController = ScrollController();
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode(debugLabel: 'ide find');
  late DocumentSnapshot _snapshot = widget.active.model.snapshot;
  // Controllers own selection; the workspace documents own text and undo.
  // Cache by document identity so closing/reopening a path starts a new session.
  final Map<IdeDocument, EditorSurfaceController> _nativeControllers = {};
  EditorSurfaceController? _nativeController;
  final MonacoSyntaxService _syntax = MonacoSyntaxService();
  final Map<IdeDocument, TokenizedDocument> _tokenizedDocuments = {};
  late final Future<MonacoBuiltinTheme> _theme = const MonacoThemeAssets().load(
    'vs-dark',
  );
  MonacoBuiltinTheme? _loadedTheme;
  Map<int, List<TextSpan>>? _styledLines;
  IdeDocument? _syntaxDocument;
  String? _syntaxText;
  int _syntaxRequest = 0;

  TextEditingValue get _editingValue =>
      _nativeController?.value ?? _controller.value;

  String get _editorStatus => widget.nativeEditorEnabled
      ? 'Native editor (experimental)'
      : 'Native editor';
  bool _findVisible = false;
  bool _replaceVisible = false;
  bool _findMatchCase = false;
  bool _findWholeWord = false;
  bool _findRegex = false;
  List<FindMatch> _findResults = [];
  int _findIndex = -1;
  String _path = '';
  bool _syncing = false;
  bool _positionUpdatePending = false;
  Position? _reportedPosition;
  int? _reportedStatusColumn;

  @override
  void initState() {
    super.initState();
    _path = widget.active.path;
    _controller.addListener(_selectionChanged);
    _findController.addListener(_refreshFindResults);
    widget.workspace.addListener(_workspaceChanged);
    if (widget.nativeEditorEnabled) _activateNativeController();
    _selectionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLspStatus(_editorStatus);
    });
  }

  void _activateNativeController() {
    final doc = widget.active;
    _nativeController = _nativeControllers.putIfAbsent(doc, () {
      final controller = EditorSurfaceController(document: doc.model);
      var previousText = controller.value.text;
      controller.addListener(() {
        final textChanged = previousText != controller.value.text;
        previousText = controller.value.text;
        if (_syncing) return;
        if (identical(_nativeController, controller)) {
          _snapshot = doc.model.snapshot;
          _selectionChanged();
          if (textChanged) _refreshFindResults();
        }
        if (textChanged) {
          widget.workspace.notifyDocumentChanged(doc);
          if (identical(_nativeController, controller)) _scheduleSyntax();
        }
      });
      return controller;
    });
    _workspaceChanged();
    _snapshot = doc.model.snapshot;
    _selectionChanged();
    _scheduleSyntax();
  }

  void _scheduleSyntax() {
    if (!widget.nativeEditorEnabled || _nativeController == null) return;
    final doc = widget.active;
    final snapshot = doc.model.snapshot;
    if (identical(_syntaxDocument, doc) && _syntaxText == snapshot.text) return;
    _syntaxDocument = doc;
    _syntaxText = snapshot.text;
    _styledLines = null;
    final request = ++_syntaxRequest;
    unawaited(_computeSyntax(request, doc, snapshot));
  }

  Future<void> _computeSyntax(
    int request,
    IdeDocument doc,
    DocumentSnapshot snapshot,
  ) async {
    try {
      final theme = await _theme;
      final tokenized = await _syntax.tokenizeFileIncremental(
        snapshot,
        doc.path,
        previous: _tokenizedDocuments[doc],
      );
      if (!mounted ||
          !widget.nativeEditorEnabled ||
          !identical(widget.active, doc) ||
          doc.text != snapshot.text ||
          request != _syntaxRequest) {
        return;
      }
      setState(() {
        _loadedTheme = theme;
        if (tokenized != null) _tokenizedDocuments[doc] = tokenized;
        _styledLines = tokenized == null
            ? null
            : _syntax.styledLines(
                snapshot,
                tokenized.lines,
                theme.styleForToken,
              );
      });
    } catch (error) {
      if (mounted && request == _syntaxRequest) widget.onError(error);
    }
  }

  void _workspaceChanged() {
    if (!widget.nativeEditorEnabled) return;
    final open = widget.workspace.documents;
    var activeChanged = false;
    _syncing = true;
    try {
      for (final entry in _nativeControllers.entries.toList()) {
        final controller = entry.value;
        if (!open.contains(entry.key)) {
          _nativeControllers.remove(entry.key);
          _tokenizedDocuments.remove(entry.key);
          if (identical(_nativeController, controller)) {
            _nativeController = null;
            _focusNode.unfocus();
          }
          controller.dispose();
        } else if (controller.value.text != entry.key.text) {
          // External edits/undo already changed the shared model. Refresh the
          // view without applying another edit or invalidating its history.
          controller.syncFromDocument();
          if (identical(_nativeController, controller)) {
            _snapshot = entry.key.model.snapshot;
            activeChanged = true;
          }
        }
      }
    } finally {
      _syncing = false;
    }
    if (activeChanged) {
      _selectionChanged();
      _scheduleFindRefresh();
    }
  }

  void _disposeNativeControllers() {
    _nativeController = null;
    _syntaxRequest++;
    _syntaxDocument = null;
    _syntaxText = null;
    _styledLines = null;
    _tokenizedDocuments.clear();
    for (final controller in _nativeControllers.values) {
      controller.dispose();
    }
    _nativeControllers.clear();
  }

  void _scheduleFindRefresh() {
    if (!_findVisible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshFindResults();
    });
  }

  void _selectionChanged() {
    if (widget.nativeEditorEnabled && _nativeController == null) return;
    if (_snapshot.text != _editingValue.text) {
      _snapshot = DocumentSnapshot(_editingValue.text);
    }
    if (_positionUpdatePending) return;
    _positionUpdatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionUpdatePending = false;
      if (!mounted ||
          (widget.nativeEditorEnabled && _nativeController == null)) {
        return;
      }
      final position = editorSelectionOf(
        _editingValue,
        snapshot: _snapshot,
      ).caret;
      final lineIndex = position.lineNumber - 1;
      final lineText = _snapshot.text.substring(
        _snapshot.lineStarts[lineIndex],
        _snapshot.contentEnds[lineIndex],
      );
      final statusColumn = CursorColumns.toStatusbarColumn(
        lineText,
        position.column,
        4,
      );
      if ((_reportedPosition?.equals(position) ?? false) &&
          _reportedStatusColumn == statusColumn) {
        return;
      }
      _reportedPosition = position;
      _reportedStatusColumn = statusColumn;
      widget.onPositionChanged((
        position: position,
        statusColumn: statusColumn,
      ));
    });
  }

  @override
  void didUpdateWidget(IdeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final workspaceChanged = oldWidget.workspace != widget.workspace;
    if (workspaceChanged) {
      oldWidget.workspace.removeListener(_workspaceChanged);
      _disposeNativeControllers();
      widget.workspace.addListener(_workspaceChanged);
    }
    var changed = false;
    if (widget.nativeEditorEnabled) {
      changed =
          oldWidget.active != widget.active ||
          !oldWidget.nativeEditorEnabled ||
          workspaceChanged;
      _activateNativeController();
    } else {
      if (oldWidget.nativeEditorEnabled) _disposeNativeControllers();
      if (oldWidget.active.path != widget.active.path ||
          _controller.text != widget.active.text ||
          oldWidget.nativeEditorEnabled ||
          workspaceChanged) {
        _replaceText(widget.active.text);
        changed = true;
      }
    }
    _path = widget.active.path;
    if (changed) _scheduleFindRefresh();
    if (oldWidget.nativeEditorEnabled != widget.nativeEditorEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLspStatus(_editorStatus);
      });
    }
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_workspaceChanged);
    _disposeNativeControllers();
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _replaceText(String text) {
    _syncing = true;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _snapshot = widget.active.model.snapshot;
    _syncing = false;
  }

  void _changed(String text) {
    if (!_syncing) {
      widget.workspace.edit(_path, text);
      _snapshot = widget.active.model.snapshot;
      _refreshFindResults();
    }
  }

  SearchParams get _searchParams => SearchParams(
    _findController.text,
    isRegex: _findRegex,
    matchCase: _findMatchCase,
    wordSeparators: _findWholeWord
        ? '`~!@#\$%^&*()-=+[{]}\\|;:\'",.<>/?'
        : null,
  );

  void _refreshFindResults() {
    if (!_findVisible) return;
    final results = widget.active.model.findMatches(_searchParams);
    if (!mounted) return;
    setState(() {
      _findResults = results;
      _findIndex = -1;
    });
  }

  void openFind() {
    setState(() => _findVisible = true);
    _refreshFindResults();
    _findFocusNode.requestFocus();
    _findController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _findController.text.length,
    );
  }

  void _closeFind() {
    setState(() => _findVisible = false);
    _focusNode.requestFocus();
  }

  void _selectFindResult({bool backwards = false}) {
    if (_findResults.isEmpty) return;
    final selection = _editingValue.selection;
    final offset = _findIndex >= 0
        ? backwards
              ? _snapshot.offsetAtPosition(
                  _findResults[_findIndex].range.getStartPosition(),
                )
              : _snapshot.offsetAtPosition(
                  _findResults[_findIndex].range.getEndPosition(),
                )
        : selection.extentOffset;
    var start = _snapshot.positionAtOffset(offset);
    if (_findIndex >= 0 && _findResults[_findIndex].range.isEmpty()) {
      final length = _snapshot.text.length;
      if (backwards) {
        start = _snapshot.positionAtOffset(offset == 0 ? length : offset - 1);
      } else {
        var next = offset < length ? offset + 1 : 0;
        while (next < length &&
            start.equals(_snapshot.positionAtOffset(next))) {
          next++;
        }
        start = _snapshot.positionAtOffset(next);
      }
    }
    final match = backwards
        ? widget.active.model.findPreviousMatch(_searchParams, start)
        : widget.active.model.findNextMatch(_searchParams, start);
    if (match == null) return;
    final index = _findResults.indexWhere(
      (item) => item.range.equalsRange(match.range),
    );
    setState(() => _findIndex = index);
    _selectOffsets(
      _snapshot.offsetAtPosition(match.range.getStartPosition()),
      _snapshot.offsetAtPosition(match.range.getEndPosition()),
    );
  }

  ReplacePattern get _replacePattern => _findRegex
      ? parseReplaceString(_replaceController.text)
      : ReplacePattern.fromStaticValue(_replaceController.text);

  void _replaceCurrent() {
    if (_findResults.isEmpty) return;
    if (_findIndex < 0) {
      _selectFindResult();
      return;
    }
    final range = _findResults[_findIndex].range;
    final start = _snapshot.offsetAtPosition(range.getStartPosition());
    final end = _snapshot.offsetAtPosition(range.getEndPosition());
    if (_editingValue.selection.start != start ||
        _editingValue.selection.end != end) {
      _selectOffsets(start, end);
      return;
    }
    final matches = widget.active.model.findMatches(
      _searchParams,
      captureMatches: _findRegex,
      limitResultCount: _findIndex + 1,
    );
    if (_findIndex >= matches.length ||
        !matches[_findIndex].range.equalsRange(range)) {
      _refreshFindResults();
      return;
    }
    final replacement = _replacePattern.buildReplaceString(
      matches[_findIndex].matches,
    );
    widget.workspace.applyEdits(widget.active.path, [
      EditorDocumentEdit(range, replacement),
    ]);
    _snapshot = widget.active.model.snapshot;
    _selectOffsets(start + replacement.length, start + replacement.length);
    _refreshFindResults();
  }

  void _replaceAll() {
    final document = widget.active;
    final matches = document.model.findMatches(
      _searchParams,
      captureMatches: _findRegex,
      limitResultCount: 0x1fffffffffffff,
    );
    if (matches.isEmpty) return;
    final pattern = _replacePattern;
    widget.workspace.applyEdits(document.path, [
      for (final match in matches)
        EditorDocumentEdit(
          match.range,
          pattern.buildReplaceString(match.matches),
        ),
    ]);
    _snapshot = document.model.snapshot;
    _refreshFindResults();
  }

  void _selectOffsets(int base, int extent) {
    if (widget.nativeEditorEnabled) {
      _nativeController?.select(base, extent);
      _nativeController?.revealSelection();
    } else {
      _controller.selection = TextSelection(
        baseOffset: base,
        extentOffset: extent,
      );
    }
  }

  /// Flushes before changing tabs or layouts. The experimental controller edits
  /// the workspace's model synchronously, so it has no separate text to flush.
  Future<void> flush() async {
    if (!_syncing && !widget.nativeEditorEnabled) {
      widget.workspace.edit(_path, _controller.text);
    }
  }

  Future<void> save() async {
    try {
      await flush();
      final doc = widget.workspace.active;
      if (doc != null) await widget.workspace.save(doc);
    } catch (error) {
      if (mounted) widget.onError(error);
    }
  }

  Future<void> closeDocument(IdeDocument doc) async {
    if (widget.nativeEditorEnabled && identical(doc, widget.active)) {
      _focusNode.unfocus();
    }
    // The workspace owns closing/disposal. Its notification releases the cached
    // controller only after the document is actually removed from the open set.
  }

  Future<void> revealLine(int line) async {
    if (line < 1) return;
    final offset = _snapshot.offsetAtPosition(Position(line, 1));
    _selectOffsets(offset, offset);
    if (_focusNode.canRequestFocus) _focusNode.requestFocus();
  }

  Future<void> retryLanguageServer() async {
    widget.onLspStatus(_editorStatus);
  }

  @override
  Widget build(BuildContext context) {
    final language = p.extension(widget.active.path).toLowerCase();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(save()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(save()),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): openFind,
      },
      child: ColoredBox(
        color: CursorColors.code,
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.nativeEditorEnabled
                  ? _nativeController == null
                        ? const SizedBox.expand()
                        : EditorSurface(
                            controller: _nativeController!,
                            focusNode: _focusNode,
                            backgroundColor:
                                _loadedTheme?.background ?? CursorColors.code,
                            caretColor: CursorColors.accent,
                            styledLines: _styledLines,
                            style: TextStyle(
                              color:
                                  _loadedTheme?.foreground ??
                                  CursorColors.textPrimary,
                              fontFamily: CursorFonts.mono,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          )
                  : TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      autocorrect: false,
                      enableSuggestions: false,
                      cursorColor: CursorColors.accent,
                      onChanged: _changed,
                      style: const TextStyle(
                        color: CursorColors.textPrimary,
                        fontFamily: CursorFonts.mono,
                        fontSize: 13,
                        height: 1.45,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          20,
                        ),
                        hintText: language.isEmpty
                            ? 'Start typing…'
                            : 'Edit $language…',
                        hintStyle: const TextStyle(
                          color: CursorColors.textFaint,
                        ),
                      ),
                    ),
            ),
            if (_findVisible)
              Positioned(
                top: 8,
                right: 12,
                width: 440,
                child: Material(
                  elevation: 6,
                  color: CursorColors.surface,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          _closeFind,
                      const SingleActivator(LogicalKeyboardKey.enter):
                          _selectFindResult,
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        shift: true,
                      ): () =>
                          _selectFindResult(backwards: true),
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _findController,
                                focusNode: _findFocusNode,
                                decoration: const InputDecoration(
                                  hintText: 'Find',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Text(
                              '${_findResults.isEmpty ? 0 : _findIndex + 1}/${_findResults.length}',
                            ),
                            IconButton(
                              tooltip: 'Toggle replace',
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => setState(
                                () => _replaceVisible = !_replaceVisible,
                              ),
                              icon: const Icon(Icons.find_replace, size: 17),
                            ),
                            IconButton(
                              tooltip: 'Match case',
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              color: _findMatchCase
                                  ? CursorColors.accent
                                  : CursorColors.textMuted,
                              onPressed: () {
                                _findMatchCase = !_findMatchCase;
                                _refreshFindResults();
                              },
                              icon: const Text('Aa'),
                            ),
                            IconButton(
                              tooltip: 'Whole word',
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              color: _findWholeWord
                                  ? CursorColors.accent
                                  : CursorColors.textMuted,
                              onPressed: () {
                                _findWholeWord = !_findWholeWord;
                                _refreshFindResults();
                              },
                              icon: const Text('W'),
                            ),
                            IconButton(
                              tooltip: 'Regular expression',
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              color: _findRegex
                                  ? CursorColors.accent
                                  : CursorColors.textMuted,
                              onPressed: () {
                                _findRegex = !_findRegex;
                                _refreshFindResults();
                              },
                              icon: const Text('.*'),
                            ),
                            IconButton(
                              tooltip: 'Previous match',
                              onPressed: () =>
                                  _selectFindResult(backwards: true),
                              icon: const Icon(
                                Icons.keyboard_arrow_up,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next match',
                              onPressed: () => _selectFindResult(),
                              icon: const Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close find',
                              onPressed: _closeFind,
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                        if (_replaceVisible)
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _replaceController,
                                  decoration: const InputDecoration(
                                    hintText: 'Replace',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Replace match',
                                onPressed: _replaceCurrent,
                                icon: const Icon(Icons.find_replace, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Replace all',
                                onPressed: _replaceAll,
                                icon: const Icon(Icons.done_all, size: 18),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Retained for the editor-area status bar and future syntax services.
String languageNameForFile(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.dart' => 'Dart',
      '.js' || '.jsx' => 'JavaScript',
      '.ts' || '.tsx' => 'TypeScript',
      '.py' => 'Python',
      '.json' => 'JSON',
      '.md' => 'Markdown',
      '.yaml' || '.yml' => 'YAML',
      '.html' => 'HTML',
      '.css' => 'CSS',
      '.rs' => 'Rust',
      '.go' => 'Go',
      '.java' => 'Java',
      '.c' || '.h' => 'C',
      '.cc' || '.cpp' || '.hpp' => 'C++',
      '.sh' || '.bash' => 'Shell',
      _ => 'Plain Text',
    };
