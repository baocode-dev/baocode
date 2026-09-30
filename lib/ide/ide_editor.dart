import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../theme/cursor_theme.dart';
import '../theme/workbench_theme.dart' hide ColorScheme;
import 'editor/monaco/flutter/diff_editor.dart';
import 'editor/monaco/flutter/diff_editor_model.dart';
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
import 'editor/monaco/flutter/editor_keybindings.dart';
import 'editor/monaco/flutter/language_configuration_assets.dart';
import 'editor/monaco/vs/editor/common/languages/language_configuration_registry.dart'
    show plainTextLanguageConfiguration;
import 'editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'editor/textmate/textmate_syntax.dart';
import 'ide_commands.dart';
import 'ide_find_widget.dart';
import 'ide_menu.dart';
import 'ide_workspace.dart';
import 'lsp/language_features.dart';
import 'lsp/lsp_protocol.dart';
import 'lsp_ui/editor_language_session.dart';
import 'lsp_ui/language_widgets.dart';
import 'lsp_ui/semantic_tokens.dart';
import 'lsp_ui/lsp_convert.dart';
import 'lsp_ui/workspace_edit.dart';

/// Where the caret is, as the status bar shows it. [selectionLength] is the
/// selected UTF-16 length (0 for a caret).
typedef IdeEditorPosition = ({
  Position position,
  int statusColumn,
  int selectionLength,
});

/// The Fast IDE editor: the painted Monaco port by default, with the Flutter
/// TextField kept as a fallback (`--dart-define=MONAD_NATIVE_EDITOR=false`).
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
      defaultValue: true,
    ),
    this.onOpenLocation,
    this.onShowReferences,
    this.onShowCommands,
    this.formatOnSave = false,
    this.onChordKey,
  });

  final IdeWorkspace workspace;
  final IdeDocument active;
  final ValueChanged<Object> onError;
  final ValueChanged<String> onLspStatus;
  final ValueChanged<IdeEditorPosition> onPositionChanged;

  /// Opt out with --dart-define=MONAD_NATIVE_EDITOR=false, or override in
  /// tests. The painted surface is a partial Monaco port; see PARITY.md.
  final bool nativeEditorEnabled;

  /// Opens a go-to target (the workbench records navigation history and
  /// opens other files); without it only targets in the active document
  /// are revealed.
  final Future<void> Function(IdeLocation location)? onOpenLocation;

  /// Lists references (or several definitions) in the workbench's panel.
  final void Function(String title, List<IdeLocation> locations)?
  onShowReferences;

  /// Opens the Command Palette: the context menu's last item.
  final VoidCallback? onShowCommands;

  /// Formats the document before saving (`editor.formatOnSave`, off by
  /// default) when a language server can.
  final bool formatOnSave;

  /// The workbench's chord keybindings, which VS Code resolves with the
  /// editor's: told the key starting a chord here (⌘K), then handed a
  /// [second] key the editor does not bind.
  final void Function(KeyEvent event, {required bool second})? onChordKey;

  @override
  State<IdeEditor> createState() => IdeEditorState();
}

class IdeEditorState extends State<IdeEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.active.text,
  );
  late final FocusNode _focusNode = FocusNode(debugLabel: 'ide editor');
  // The surface's state implements EditorViewHost, which editor commands use.
  final GlobalKey _surfaceKey = GlobalKey();
  late final ScrollController _scrollController = ScrollController();
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode(debugLabel: 'ide find');
  final FocusNode _replaceFocusNode = FocusNode(debugLabel: 'ide replace');
  late DocumentSnapshot _snapshot = widget.active.model.snapshot;
  // Controllers own selection; the workspace documents own text and undo.
  // Cache by document identity so closing/reopening a path starts a new session.
  final Map<IdeDocument, EditorSurfaceController> _nativeControllers = {};
  EditorSurfaceController? _nativeController;
  final MonacoSyntaxService _syntax = MonacoSyntaxService();
  final Map<IdeDocument, TokenizedDocument> _tokenizedDocuments = {};
  // VS Code's grammars and theme where the platform has them; Monarch
  // highlights the rest (the web, language packs, languages without one).
  final TextMateSyntax _textMate = TextMateSyntax();
  // Each by the path its language was picked for.
  final Map<IdeDocument, (String, TextMateDocument)> _textMateDocuments = {};
  bool _textMateRequested = false;
  final WorkbenchThemeService _themes = WorkbenchThemeService.instance;
  ThemeTypeSelector? _monarchTheme;
  late Future<MonacoBuiltinTheme> _theme = _loadMonarchTheme();
  Map<int, List<TextSpan>>? _styledLines;
  IdeDocument? _styledDocument;
  DocumentSnapshot? _styledSnapshot;
  IdeDocument? _syntaxDocument;
  String? _syntaxText;
  int _syntaxRequest = 0;
  EditorLanguageSession? _language;

  /// Each open diff tab's diff and original side.
  final Map<IdeDocument, _DiffOriginal> _diffs = {};
  EditorKeyChord? _pendingChord;
  bool _languageRebuildScheduled = false;

  TextEditingValue get _editingValue =>
      _nativeController?.value ?? _controller.value;

  String get _editorStatus =>
      widget.nativeEditorEnabled ? 'Monaco editor' : 'Text editor';
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
  int? _reportedSelectionLength;

  @override
  void initState() {
    super.initState();
    _path = widget.active.path;
    _controller.addListener(_selectionChanged);
    _findController.addListener(_refreshFindResults);
    widget.workspace.addListener(_workspaceChanged);
    _themes.addListener(_colorThemeChanged);
    if (widget.nativeEditorEnabled) _activateNativeController();
    _selectionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLspStatus(_editorStatus);
    });
  }

  void _activateNativeController() {
    if (!_textMateRequested) {
      _textMateRequested = true;
      unawaited(_textMate.theme);
    }
    final doc = widget.active;
    _nativeController = _nativeControllers.putIfAbsent(doc, () {
      final controller = EditorSurfaceController(document: doc.model)
        ..detectIndentation();
      unawaited(_loadLanguageConfiguration(doc, controller));
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
    _syncLanguageSession();
  }

  /// Keeps one [EditorLanguageSession] for the active document when the
  /// workspace has language services.
  void _syncLanguageSession() {
    final languages = widget.workspace.languages;
    final controller = _nativeController;
    final doc = widget.active;
    if (languages == null ||
        controller == null ||
        !widget.nativeEditorEnabled ||
        doc.readOnly) {
      _disposeLanguageSession();
      return;
    }
    final current = _language;
    if (current != null &&
        identical(current.controller, controller) &&
        identical(current.document, doc) &&
        identical(current.languages, languages)) {
      return;
    }
    _disposeLanguageSession();
    _language = EditorLanguageSession(
      languages: languages,
      document: doc,
      controller: controller,
      onError: (error) {
        if (mounted) widget.onError(error);
      },
      onOpenLocation: _openLocation,
      onShowReferences: (title, locations) =>
          widget.onShowReferences?.call(title, locations),
      onApplyWorkspaceEdit: applyWorkspaceEdit,
      onFocusEditor: focus,
      semanticTokenStyler: _semanticTokenStyler,
      languageId: _textMateDocuments[doc]?.$2.languageId ?? 'plaintext',
    )..addListener(_languageChanged);
  }

  void _disposeLanguageSession() {
    final session = _language;
    if (session == null) return;
    _language = null;
    session
      ..removeListener(_languageChanged)
      ..dispose();
  }

  void _languageChanged() => _rebuildSoon();

  /// setState, after this frame when called while building.
  void _rebuildSoon() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_languageRebuildScheduled) return;
      _languageRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _languageRebuildScheduled = false;
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  Future<void> _openLocation(IdeLocation location) async {
    if (widget.onOpenLocation case final open?) return open(location);
    if (location.path == widget.active.path) revealRange(location.range);
  }

  /// The language session of the active document (tests and the
  /// workbench read its state).
  @visibleForTesting
  EditorLanguageSession? get languageSession => _language;

  /// Applies a workspace edit (rename, code actions, `workspace/applyEdit`):
  /// one undo step per document, cursors mapped in open editors. See
  /// [applyLspWorkspaceEdit] for unopened files.
  Future<bool> applyWorkspaceEdit(LspWorkspaceEdit edit) =>
      applyLspWorkspaceEdit(
        widget.workspace,
        edit,
        applyTo: (doc, edits) {
          final controller = _nativeControllers[doc];
          if (controller == null) return false;
          controller.applyEdits(edits);
          return true;
        },
      );

  /// Selects the protocol [range] (or places the caret at its start unless
  /// [select]) in the active document and scrolls it into view, centered
  /// when it was outside the viewport.
  void revealRange(LspRange range, {bool select = false}) {
    final snapshot = widget.active.model.snapshot;
    final (start, end) = lspOffsetsOf(snapshot, range);
    if (widget.nativeEditorEnabled) {
      final controller = _nativeController;
      if (controller == null) return;
      if (select) {
        controller.select(start, end);
      } else {
        controller.select(start, start);
      }
      controller.revealSelection();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final view = _surfaceKey.currentState;
        if (mounted && view is EditorSurfaceView) {
          (view as EditorSurfaceView).revealRange(start, end);
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    } else {
      _controller.selection = TextSelection(
        baseOffset: start,
        extentOffset: select ? end : start,
      );
    }
    focus();
  }

  /// Keys the language widgets and language commands take before the
  /// editor's own bindings; everything else (e.g. F8, workbench shortcuts)
  /// keeps bubbling.
  KeyEventResult _onEditorKey(KeyEvent event) {
    final session = _language;
    if (session == null) return KeyEventResult.ignored;
    final result = session.handleKey(event);
    if (result != KeyEventResult.ignored) return result;
    if (_modifierKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    final chord = editorKeyChordOf(event);
    if (chord == null) return KeyEventResult.ignored;
    if (_pendingChord case final pending?) {
      _pendingChord = null;
      final id = matchEditorLanguageKey(chord, pending: pending);
      if (id != null && id != editorChordPrefix) {
        session.run(id);
      } else {
        // The workbench's (⌘K ⌘T); upstream swallows unbound ones too.
        widget.onChordKey?.call(event, second: true);
      }
      return KeyEventResult.handled;
    }
    final id = matchEditorLanguageKey(chord);
    if (id == null || id.startsWith('editor.action.marker.')) {
      return KeyEventResult.ignored;
    }
    if (id == editorChordPrefix) {
      _pendingChord = chord;
      widget.onChordKey?.call(event, second: false);
      return KeyEventResult.handled;
    }
    return session.run(id) ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  static final _modifierKeys = {
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
  };

  void _viewChanged() {
    _language?.onViewChanged();
    _textMateViewportChanged();
    _languageChanged();
  }

  /// The lines on screen go to the TextMate worker first.
  void _textMateViewportChanged() {
    final document = _textMateDocuments[widget.active]?.$2;
    final view = _surfaceKey.currentState;
    if (document == null || view is! EditorSurfaceView) return;
    if ((view as EditorSurfaceView).visibleLineRange case final range?) {
      document.setViewport(range.first, range.last);
      _diffs[widget.active]?.textMate?.setViewport(range.first, range.last);
    }
  }

  /// Snippet placeholders (`editor.snippetTabstopHighlight*`).
  List<EditorDecoration> _snippetDecorations(
    EditorSurfaceController controller,
    WorkbenchColors colors,
  ) => [
    for (final (start, end, _, isFinal) in controller.snippetPlaceholders)
      if (isFinal)
        EditorDecoration(
          start: start,
          end: end,
          borderColor: colors['editor.snippetFinalTabstopHighlightBorder'],
        )
      else
        EditorDecoration(
          start: start,
          end: end,
          backgroundColor: colors['editor.snippetTabstopHighlightBackground'],
        ),
  ];

  Future<void> _loadLanguageConfiguration(
    IdeDocument doc,
    EditorSurfaceController controller,
  ) async {
    try {
      final snapshot = doc.model.snapshot;
      final firstLine = snapshot.text.substring(0, snapshot.contentEnds.first);
      final configuration = await languageConfigurationForPath(
        doc.path,
        firstLine: firstLine.startsWith('\uFEFF')
            ? firstLine.substring(1)
            : firstLine,
      );
      if (!mounted || !identical(_nativeControllers[doc], controller)) return;
      setState(
        () => controller.languageConfiguration =
            configuration ?? plainTextLanguageConfiguration,
      );
    } catch (error) {
      if (mounted) widget.onError(error);
    }
  }

  /// Monaco's built-in theme of the workbench theme's type: the colors of
  /// what Monarch highlights.
  Future<MonacoBuiltinTheme> _loadMonarchTheme() {
    final theme = _monarchTheme = getThemeTypeSelector(_themes.colorTheme.type);
    return const MonacoThemeAssets().load(theme.value);
  }

  /// Semantic tokens in the current theme's rules (`getTokenStyleMetadata`).
  IdeSemanticTokenStyler get _semanticTokenStyler {
    final theme = _themes.colorTheme;
    if (!identical(theme, _semanticStylerTheme)) {
      _semanticStylerTheme = theme;
      _semanticStyler = ideSemanticTokenStyler(theme);
    }
    return _semanticStyler!;
  }

  ColorThemeData? _semanticStylerTheme;
  IdeSemanticTokenStyler? _semanticStyler;

  /// TextMate recolors its documents itself; semantic tokens take the new
  /// theme's rules; Monarch's lines are styled again when the theme type
  /// changes.
  void _colorThemeChanged() {
    if (!mounted) return;
    _language?.semanticTokenStyler = _semanticTokenStyler;
    if (getThemeTypeSelector(_themes.colorTheme.type) == _monarchTheme) return;
    _theme = _loadMonarchTheme();
    _tokenizedDocuments.clear();
    _syntaxDocument = null;
    _scheduleSyntax();
  }

  void _scheduleSyntax() {
    if (!widget.nativeEditorEnabled || _nativeController == null) return;
    final doc = widget.active;
    final snapshot = doc.model.snapshot;
    if (identical(_syntaxDocument, doc) && _syntaxText == snapshot.text) return;
    _syntaxDocument = doc;
    _syntaxText = snapshot.text;
    final textMate = _textMateDocuments[doc];
    if (textMate != null && textMate.$1 == doc.path) {
      // Tokens follow the edit at once; the worker sends the lines it
      // retokenizes.
      _syntaxRequest++;
      textMate.$2.update(snapshot);
      _styledDocument = doc;
      _styledSnapshot = null;
      _styledLines = textMate.$2.styledLines;
      _rebuildSoon();
      return;
    }
    _textMateDocuments.remove(doc)?.$2.dispose();
    // Keep painting the previous spans until the new ones arrive: lines whose
    // text no longer matches fall back to plain text in the layout.
    if (!identical(_tokenizedDocuments[doc]?.snapshot, _styledSnapshot) ||
        !identical(_styledDocument, doc)) {
      _styledLines = null;
    }
    final request = ++_syntaxRequest;
    unawaited(_computeSyntax(request, doc, snapshot));
  }

  /// Code in hovers, in the editor's theme: TextMate's when it has the
  /// language, else Monarch's.
  Future<List<List<TextSpan>>?> _colorizeCode(
    String language,
    String code,
  ) async =>
      await _textMate.colorize(language, code) ??
      await _syntax.colorize(
        monarchLanguageIdFor(language),
        code,
        (await _theme).styleForToken,
      );

  Future<void> _computeSyntax(
    int request,
    IdeDocument doc,
    DocumentSnapshot snapshot,
  ) async {
    try {
      final firstLine = snapshot.text.substring(0, snapshot.contentEnds.first);
      final textMateLanguage = await _textMate.languageIdForPath(
        doc.path,
        firstLine: firstLine.startsWith('\uFEFF')
            ? firstLine.substring(1)
            : firstLine,
      );
      if (!mounted ||
          !widget.nativeEditorEnabled ||
          !identical(widget.active, doc) ||
          request != _syntaxRequest) {
        return;
      }
      if (textMateLanguage != null) {
        _openTextMate(doc, textMateLanguage);
        return;
      }
      final theme = await _theme;
      final tokenized = await _syntax.tokenizeFileIncremental(
        snapshot,
        doc.path,
        previous: _tokenizedDocuments[doc],
        isCancelled: () => !mounted || request != _syntaxRequest,
      );
      if (!mounted ||
          !widget.nativeEditorEnabled ||
          !identical(widget.active, doc) ||
          doc.text != snapshot.text ||
          request != _syntaxRequest) {
        return;
      }
      setState(() {
        if (tokenized != null) _tokenizedDocuments[doc] = tokenized;
        _styledDocument = doc;
        _styledSnapshot = tokenized?.snapshot;
        _styledLines = tokenized == null
            ? null
            : _syntax.styledLines(
                snapshot,
                tokenized.lines,
                theme.styleForToken,
              );
      });
    } on TokenizationCancelled {
      // A newer edit superseded this pass.
    } catch (error) {
      if (mounted && request == _syntaxRequest) widget.onError(error);
    }
  }

  /// Highlights [doc] with TextMate from now on.
  void _openTextMate(IdeDocument doc, String languageId) {
    final snapshot = doc.model.snapshot;
    final document = _textMate.open(languageId, snapshot);
    if (document == null) return;
    _textMateDocuments.remove(doc)?.$2.dispose();
    _textMateDocuments[doc] = (doc.path, document);
    if (identical(_language?.document, doc)) _language?.languageId = languageId;
    document.addListener(() {
      if (!mounted || !identical(widget.active, doc)) return;
      if (!identical(_textMateDocuments[doc]?.$2, document)) return;
      _styledLines = document.styledLines;
      _rebuildSoon();
    });
    _tokenizedDocuments.remove(doc);
    _syntaxText = snapshot.text;
    _diffs[doc]?.highlight(_textMate, languageId);
    setState(() {
      _styledDocument = doc;
      _styledSnapshot = null;
      _styledLines = document.styledLines;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textMateViewportChanged();
    });
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
          _diffs.remove(entry.key)?.dispose();
          _tokenizedDocuments.remove(entry.key);
          _textMateDocuments.remove(entry.key)?.$2.dispose();
          if (identical(_language?.controller, controller)) {
            _disposeLanguageSession();
          }
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
    _disposeLanguageSession();
    _nativeController = null;
    _syntaxRequest++;
    _syntaxDocument = null;
    _syntaxText = null;
    _styledLines = null;
    _tokenizedDocuments.clear();
    for (final (_, document) in _textMateDocuments.values) {
      document.dispose();
    }
    _textMateDocuments.clear();
    for (final controller in _nativeControllers.values) {
      controller.dispose();
    }
    _nativeControllers.clear();
    for (final diff in _diffs.values) {
      diff.dispose();
    }
    _diffs.clear();
  }

  /// [doc]'s diff and original side, where it is a diff tab.
  _DiffOriginal? _diffOf(IdeDocument doc) {
    final original = doc.diff;
    if (original == null) return null;
    return _diffs.putIfAbsent(doc, () {
      final diff = _DiffOriginal(original, doc.model, onChanged: _rebuildSoon);
      if (_textMateDocuments[doc]?.$2.languageId case final language?) {
        diff.highlight(_textMate, language);
      }
      return diff;
    });
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
      final selection = _editingValue.selection;
      final selectionLength = selection.isValid
          ? (selection.end - selection.start).abs()
          : 0;
      if ((_reportedPosition?.equals(position) ?? false) &&
          _reportedStatusColumn == statusColumn &&
          _reportedSelectionLength == selectionLength) {
        return;
      }
      _reportedPosition = position;
      _reportedStatusColumn = statusColumn;
      _reportedSelectionLength = selectionLength;
      widget.onPositionChanged((
        position: position,
        statusColumn: statusColumn,
        selectionLength: selectionLength,
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
    _themes.removeListener(_colorThemeChanged);
    _disposeNativeControllers();
    _textMate.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    _replaceFocusNode.dispose();
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

  /// Whether the find widget is open.
  bool get findVisible => _findVisible;

  /// Whether the find widget shows its replace row.
  bool get replaceVisible => _findVisible && _replaceVisible;

  /// The current find matches (capped at 999, as the counter shows), for
  /// painting as decorations. Empty while the find widget is closed.
  List<FindMatch> get findMatches =>
      _findVisible ? List.unmodifiable(_findResults) : const [];

  /// Index into [findMatches] of the current match, or -1 when none.
  int get findIndex => _findVisible ? _findIndex : -1;

  /// Commands contributed by the editor to the workbench's command palette.
  /// Their keybindings are only labels there: the editor dispatches its keys.
  List<IdeCommand> get editorCommands => [
    if (widget.nativeEditorEnabled)
      for (final MapEntry(key: id, value: label) in editorCommandLabels.entries)
        IdeCommand(
          id: id,
          label: label,
          category: 'Editor',
          keybindingLabel: editorCommandKeybindingLabel(id),
          enabled: _nativeController != null,
          run: () => _runEditorCommand(id),
        ),
    if (widget.nativeEditorEnabled && widget.workspace.languages != null)
      for (final MapEntry(key: id, value: label)
          in editorLanguageCommandLabels.entries)
        // Problem navigation spans files: the workbench owns it.
        if (!id.startsWith('editor.action.marker.'))
          IdeCommand(
            id: id,
            label: label,
            category: 'Editor',
            keybindingLabel: editorLanguageKeybindingLabel(id),
            enabled: _language != null && _languageCommandEnabled(id),
            run: () => _runLanguageCommand(id),
          ),
  ];

  bool _languageCommandEnabled(String id) {
    final session = _language;
    if (session == null) return false;
    final request = switch (id) {
      'editor.action.revealDefinition' => LanguageRequest.definition,
      'editor.action.goToTypeDefinition' => LanguageRequest.typeDefinition,
      'editor.action.goToImplementation' => LanguageRequest.implementation,
      'editor.action.goToReferences' => LanguageRequest.references,
      'editor.action.rename' => LanguageRequest.rename,
      'editor.action.formatDocument' => LanguageRequest.format,
      'editor.action.formatSelection' => LanguageRequest.rangeFormat,
      'editor.action.quickFix' ||
      'editor.action.refactor' ||
      'editor.action.sourceAction' => LanguageRequest.codeActions,
      'editor.action.triggerSuggest' => LanguageRequest.completion,
      'editor.action.triggerParameterHints' => LanguageRequest.signatureHelp,
      _ => null,
    };
    return request == null || session.supports(request);
  }

  /// The editor's context menu (`MenuId.EditorContext`): go-to commands,
  /// then modifications, then the clipboard, then the Command Palette; the
  /// language items only while the language server has the feature, as
  /// VS Code hides them without a provider.
  void _showContextMenu(Offset position) {
    if (_nativeController == null) return;
    final hasSelection = _nativeController!.selections.any(
      (selection) => !selection.isCollapsed,
    );
    final language = _language != null;
    IdeMenuAction languageItem(String id) => IdeMenuAction(
      editorLanguageCommandLabels[id]!,
      keybinding: editorLanguageKeybindingLabel(id),
      onSelected: () => _runLanguageCommand(id),
    );
    IdeMenuAction editorItem(String id) => IdeMenuAction(
      editorCommandLabels[id]!,
      keybinding: editorCommandKeybindingLabel(id),
      onSelected: () => _runEditorCommand(id),
    );
    List<IdeMenuAction> languageItems(List<String> ids) => [
      for (final id in ids)
        if (language && _languageCommandEnabled(id)) languageItem(id),
    ];
    final showCommands = widget.onShowCommands;
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          languageItems(const [
            'editor.action.revealDefinition',
            'editor.action.goToTypeDefinition',
            'editor.action.goToImplementation',
            'editor.action.goToReferences',
          ]),
          [
            ...languageItems(const ['editor.action.rename']),
            editorItem('editor.action.changeAll'),
            ...languageItems([
              'editor.action.formatDocument',
              if (hasSelection) 'editor.action.formatSelection',
              'editor.action.refactor',
              'editor.action.sourceAction',
            ]),
          ],
          [
            editorItem('editor.action.clipboardCutAction'),
            editorItem('editor.action.clipboardCopyAction'),
            editorItem('editor.action.clipboardPasteAction'),
          ],
          [
            if (showCommands != null)
              IdeMenuAction(
                'Command Palette...',
                keybinding: const IdeKeybinding(
                  LogicalKeyboardKey.keyP,
                  primary: true,
                  shift: true,
                ).label(),
                onSelected: showCommands,
              ),
          ],
        ]),
      ),
    );
  }

  /// Palette language commands run once the editor has focus again.
  void _runLanguageCommand(String id) {
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _language?.run(id);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Shows the hover (with the diagnostics) at the caret, e.g. after the
  /// workbench moved to a problem.
  void showHoverAtCaret() {
    final session = _language;
    if (session != null) unawaited(session.showHoverAtCaret());
  }

  /// The active document's indentation, as the status bar shows it.
  String get indentationLabel {
    final controller = _nativeController;
    if (controller == null) return 'Spaces: 4';
    return controller.insertSpaces
        ? 'Spaces: ${controller.tabSize}'
        : 'Tab Size: ${controller.tabSize}';
  }

  /// Palette commands run once the editor has focus again, since the surface
  /// only accepts edits while focused.
  void _runEditorCommand(String id) {
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _nativeController;
      final host = _surfaceKey.currentState;
      if (!mounted || controller == null || host is! EditorViewHost) return;
      runEditorCommand(id, controller, host as EditorViewHost);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Find matches as surface decorations; the current match is emphasized.
  List<EditorDecoration> get _findDecorations {
    if (!_findVisible || _findResults.isEmpty) return const [];
    final snapshot = widget.active.model.snapshot;
    return [
      for (var i = 0; i < _findResults.length; i++)
        if (i == _findIndex)
          EditorDecoration.currentFindMatch(
            snapshot.offsetAtPosition(_findResults[i].range.getStartPosition()),
            snapshot.offsetAtPosition(_findResults[i].range.getEndPosition()),
          )
        else
          EditorDecoration.findMatch(
            snapshot.offsetAtPosition(_findResults[i].range.getStartPosition()),
            snapshot.offsetAtPosition(_findResults[i].range.getEndPosition()),
          ),
    ];
  }

  /// Opens (or focuses) the find widget, showing the replace row when
  /// [replace] is set. A single-line selection seeds the search text.
  void openFind({bool replace = false}) {
    final selection = _editingValue.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final selected = selection.textInside(_editingValue.text);
      if (!selected.contains('\n') && !selected.contains('\r')) {
        _findController.text = selected;
      }
    }
    setState(() {
      _findVisible = true;
      if (replace) _replaceVisible = true;
    });
    _refreshFindResults();
    _findFocusNode.requestFocus();
    _findController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _findController.text.length,
    );
  }

  /// Opens the find widget with its replace row (⌥⌘F / Ctrl+H).
  void openReplace() => openFind(replace: true);

  /// Closes the find widget and returns focus to the text.
  void closeFind() {
    if (_findVisible) setState(() => _findVisible = false);
    focus();
  }

  /// Moves keyboard focus to the text.
  void focus() {
    if (_focusNode.canRequestFocus) _focusNode.requestFocus();
  }

  void _toggleFindOption(void Function() toggle) {
    setState(toggle);
    _refreshFindResults();
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
      final session = _language;
      if (widget.formatOnSave &&
          session != null &&
          session.supports(LanguageRequest.format)) {
        await session.format();
      }
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

  /// Places the caret at one-based [line] and [column] (clamped to the
  /// document and line), reveals it and focuses the text.
  Future<void> revealLine(int line, [int column = 1]) async {
    if (line < 1) return;
    final offset = _snapshot.offsetAtPosition(
      Position(line, column < 1 ? 1 : column),
    );
    _selectOffsets(offset, offset);
    focus();
  }

  Future<void> retryLanguageServer() async {
    widget.onLspStatus(_editorStatus);
  }

  Widget _buildFindWidget() => IdeFindWidget(
    findController: _findController,
    replaceController: _replaceController,
    findFocusNode: _findFocusNode,
    replaceFocusNode: _replaceFocusNode,
    replaceVisible: _replaceVisible,
    matchCase: _findMatchCase,
    wholeWord: _findWholeWord,
    regex: _findRegex,
    matchCount: _findResults.length,
    currentIndex: _findIndex,
    onToggleReplace: () => setState(() => _replaceVisible = !_replaceVisible),
    onToggleMatchCase: () =>
        _toggleFindOption(() => _findMatchCase = !_findMatchCase),
    onToggleWholeWord: () =>
        _toggleFindOption(() => _findWholeWord = !_findWholeWord),
    onToggleRegex: () => _toggleFindOption(() => _findRegex = !_findRegex),
    onPrevious: () => _selectFindResult(backwards: true),
    onNext: _selectFindResult,
    onClose: closeFind,
    onReplace: _replaceCurrent,
    onReplaceAll: _replaceAll,
  );

  TextStyle _editorStyle(WorkbenchColors colors) => TextStyle(
    color: colors['editor.foreground'],
    fontFamily: CursorFonts.mono,
    fontSize: 13,
    height: 1.45,
  );

  /// The active document's editor; in a diff, the modified side, with
  /// what the diff gives it ([side]).
  Widget _surface(WorkbenchColors colors, {DiffEditorSide? side}) =>
      EditorSurface(
        key: _surfaceKey,
        controller: _nativeController!,
        focusNode: _focusNode,
        readOnly: widget.active.readOnly,
        backgroundColor: colors['editor.background'],
        selectionColor: colors['editor.selectionBackground'],
        caretColor: colors['editorCursor.foreground'],
        theme: EditorViewTheme.fromColors(colors.get),
        styledLines: _language?.styledLines(_styledLines) ?? _styledLines,
        decorations: [
          ...?side?.decorations,
          ...?_language?.decorations,
          ..._snippetDecorations(_nativeController!, colors),
          ..._findDecorations,
        ],
        // A diff editor's editors fold nothing and have no minimap.
        viewZones: side?.zones ?? const [],
        scrollPosition: side?.scrollPosition,
        folding: side == null,
        showMinimap: side == null,
        onKeyEvent: _onEditorKey,
        onHover: _language == null
            ? null
            : (offset, _) => _language?.onPointerHover(offset),
        onContentPointerDown: _language?.onPointerDown,
        onContextMenu: _showContextMenu,
        onViewChanged: _viewChanged,
        contentCursor: _language?.link == null
            ? null
            : SystemMouseCursors.click,
        style: _editorStyle(colors),
      );

  /// A diff tab's editors: the original, read-only, and the document.
  Widget _diffEditor(WorkbenchColors colors, _DiffOriginal diff) {
    final theme = EditorViewTheme.fromColors(colors.get);
    final type = getThemeTypeSelector(_themes.colorTheme.type);
    return DiffEditor(
      key: ObjectKey(diff),
      model: diff.model,
      style: _editorStyle(colors),
      theme: theme,
      colors: DiffEditorColors.from(colors.get),
      dark:
          type == ThemeTypeSelector.vsDark || type == ThemeTypeSelector.hcBlack,
      originalStyledLines: diff.textMate?.styledLines,
      border: colors.get('diffEditor.border'),
      sashHover: colors.get('sash.hoverBorder'),
      original: (context, side) {
        final controller = diff.controller;
        if (controller == null) return const SizedBox.expand();
        return EditorSurface(
          key: ObjectKey(controller),
          controller: controller,
          readOnly: true,
          backgroundColor: colors['editor.background'],
          selectionColor: colors['editor.selectionBackground'],
          caretColor: colors['editorCursor.foreground'],
          theme: theme,
          styledLines: diff.textMate?.styledLines,
          decorations: side.decorations,
          viewZones: side.zones,
          scrollPosition: side.scrollPosition,
          glyphMargin: side.sideBySide,
          folding: false,
          showMinimap: false,
          style: _editorStyle(colors),
        );
      },
      modified: (context, side) => _surface(colors, side: side),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = p.extension(widget.active.path).toLowerCase();
    final colors = _themes.colors;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(save()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(save()),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): openFind,
        // Replace: ⌥⌘F or ⌘H on macOS (where ⌃H deletes), Ctrl+H elsewhere.
        if (ideUsesMacKeys) ...{
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true, alt: true):
              openReplace,
          const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
              openReplace,
        } else
          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
              openReplace,
      },
      child: ColoredBox(
        color: colors['editor.background'],
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.nativeEditorEnabled
                  ? _nativeController == null
                        ? const SizedBox.expand()
                        : _diffOf(widget.active) == null
                        ? _surface(colors)
                        : _diffEditor(colors, _diffOf(widget.active)!)
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
                      cursorColor: colors['editorCursor.foreground'],
                      onChanged: _changed,
                      style: TextStyle(
                        color: colors['editor.foreground'],
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
                        hintStyle: TextStyle(
                          color: colors['editor.placeholder.foreground'],
                        ),
                      ),
                    ),
            ),
            if (_language case final session?)
              Positioned.fill(
                child: IdeLanguageOverlay(
                  session: session,
                  colorize: _colorizeCode,
                  language:
                      _textMateDocuments[widget.active]?.$2.languageId ??
                      _tokenizedDocuments[widget.active]?.languageId,
                  view: () => switch (_surfaceKey.currentState) {
                    final EditorSurfaceView view => view,
                    _ => null,
                  },
                ),
              ),
            if (_findVisible)
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
                        child: _buildFindWidget(),
                      ),
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

/// A diff tab's original side in the editor: its text as a read-only
/// document, highlighted as the modified is, and the diff between them.
class _DiffOriginal {
  _DiffOriginal(
    this.original,
    EditorDocumentModel modified, {
    required this.onChanged,
  }) : model = DiffEditorModel(original: original.text, modified: modified) {
    original.text.addListener(_textChanged);
    _textChanged();
  }

  final IdeDiffOriginal original;
  final DiffEditorModel model;
  final VoidCallback onChanged;

  EditorDocumentModel? _document;
  EditorSurfaceController? controller;
  TextMateDocument? textMate;

  void _textChanged() {
    final text = original.text.value;
    if (text == null || text == _document?.text) return;
    controller?.dispose();
    _document?.dispose();
    final document = _document = EditorDocumentModel(text);
    controller = EditorSurfaceController(document: document);
    textMate?.update(document.snapshot);
    onChanged();
  }

  /// Highlights the original as [languageId], as the modified is.
  void highlight(TextMateSyntax syntax, String languageId) {
    final document = _document;
    if (document == null || textMate?.languageId == languageId) return;
    textMate?.dispose();
    textMate = syntax.open(languageId, document.snapshot)
      ?..addListener(onChanged);
    onChanged();
  }

  void dispose() {
    original.text.removeListener(_textChanged);
    model.dispose();
    textMate?.dispose();
    controller?.dispose();
    _document?.dispose();
  }
}
