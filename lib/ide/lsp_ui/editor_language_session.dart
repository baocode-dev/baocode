import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/workbench_theme.dart' show WorkbenchColors, themeColors;
import '../editor/monaco/flutter/document_snapshot.dart';
import '../editor/monaco/flutter/editor_decorations.dart';
import '../editor/monaco/flutter/editor_surface_controller.dart';
import '../editor/monaco/vs/editor/contrib/codeAction/common/types.dart';
import '../ide_commands.dart';
import '../ide_workspace.dart';
import '../lsp/language_features.dart';
import '../lsp/lsp_protocol.dart';
import 'diagnostics.dart';
import 'language_editor.dart';
import 'lsp_convert.dart';
import 'minimal_edits.dart';
import 'semantic_tokens.dart';
import 'suggest_session.dart';

/// A hover card's content, anchored at `[start, end)`.
class IdeHoverState {
  const IdeHoverState({
    required this.start,
    required this.end,
    required this.markdown,
    required this.diagnostics,
    required this.keyboard,
  });

  final int start;
  final int end;
  final String? markdown;
  final List<LspDiagnostic> diagnostics;

  /// Opened with ⌘K ⌘I (stays until the caret moves) rather than the mouse.
  final bool keyboard;
}

/// Signature help showing above the caret.
class IdeSignatureState {
  IdeSignatureState(this.help, this.anchor)
    : activeSignature = help.activeSignature.clamp(
        0,
        help.signatures.length - 1,
      );

  final LspSignatureHelp help;
  final int anchor;
  int activeSignature;

  LspSignature get signature => help.signatures[activeSignature];

  /// The active parameter of [signature] (its own, else the answer's).
  int get activeParameter => signature.activeParameter ?? help.activeParameter;
}

/// A code action as the ported sorting/grouping sees it.
class IdeCodeAction implements CodeActionInfo {
  IdeCodeAction(this.action);

  final LspCodeAction action;

  @override
  String? get kind => action.kind;
  @override
  bool get isPreferred => action.isPreferred;
  @override
  bool get hasDiagnostics => action.diagnostics.isNotEmpty;
  @override
  bool get isDisabled => action.disabledReason != null;
}

/// The ⌘. menu: grouped actions, one selected.
class IdeCodeActionMenu {
  IdeCodeActionMenu(this.anchor, this.groups)
    : actions = [for (final (_, list) in groups) ...list] {
    selected = actions.indexWhere((a) => !a.isDisabled);
    if (selected < 0) selected = 0;
  }

  final int anchor;
  final List<(CodeActionGroup, List<IdeCodeAction>)> groups;
  final List<IdeCodeAction> actions;
  late int selected;
}

/// The inline rename box over `[start, end)`.
class IdeRenameState {
  IdeRenameState({
    required this.start,
    required this.end,
    required this.position,
    required this.version,
    required String placeholder,
  }) : placeholder = placeholder,
       text = TextEditingController(text: placeholder)
         ..selection = TextSelection(
           baseOffset: 0,
           extentOffset: placeholder.length,
         );

  final int start;
  final int end;
  final LspPosition position;
  final int version;
  final String placeholder;
  final TextEditingController text;
  final FocusNode focusNode = FocusNode(debugLabel: 'rename input');

  void dispose() {
    text.dispose();
    focusNode.dispose();
  }
}

/// A short notice under the caret ("No definition found for 'x'").
class IdeEditorMessage {
  const IdeEditorMessage(this.text, this.offset);

  final String text;
  final int offset;
}

enum IdeGoToKind { definition, typeDefinition, implementation, references }

/// Language features for the document one editor shows: diagnostics
/// decorations, hover, go to, completion ([suggest]), signature help,
/// rename, formatting, code actions and semantic tokens. The editor forwards
/// its keys, pointer and hover events here and paints what it exposes.
///
/// Requests are debounced where upstream debounces, and answers for an
/// older document version (or a newer request) are dropped.
class EditorLanguageSession extends ChangeNotifier
    implements IdeLanguageEditor {
  EditorLanguageSession({
    required this.languages,
    required this.document,
    required this.controller,
    required this.onError,
    required this.onOpenLocation,
    required this.onShowReferences,
    required this.onApplyWorkspaceEdit,
    required this.onFocusEditor,
    this._semanticTokenStyler,
    this._languageId = 'plaintext',
  }) {
    suggest = IdeSuggestSession(this);
    _version = document.model.version;
    _selection = controller.value.selection;
    controller.addListener(_controllerChanged);
    languages.addListener(_languagesChanged);
    _scheduleSemanticTokens(delay: Duration.zero);
  }

  static const hoverDelay = Duration(milliseconds: 300);
  static const hoverHideDelay = Duration(milliseconds: 300);
  static const lightbulbDelay = Duration(milliseconds: 250);
  static const semanticTokensDelay = Duration(milliseconds: 300);
  static const signatureHelpDelay = Duration(milliseconds: 120);
  static const messageDuration = Duration(seconds: 3);

  @override
  final LanguageFeatures languages;
  @override
  final IdeDocument document;
  @override
  final EditorSurfaceController controller;
  final ValueChanged<Object> onError;
  final Future<void> Function(IdeLocation location) onOpenLocation;
  final void Function(String title, List<IdeLocation> locations)
  onShowReferences;
  final Future<bool> Function(LspWorkspaceEdit edit) onApplyWorkspaceEdit;
  final VoidCallback onFocusEditor;

  late final IdeSuggestSession suggest;

  bool _disposed = false;
  late int _version;
  late TextSelection _selection;

  String get path => document.path;
  DocumentSnapshot get _snapshot => document.model.snapshot;
  int get _caret => controller.value.selection.extentOffset;

  bool supports(LanguageRequest request) => languages.supports(path, request);

  @override
  bool get isDisposed => _disposed;

  @override
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void reportError(Object error) {
    if (!_disposed) onError(error);
  }

  @override
  void runCommand(LspCommand command, {String? serverId}) {
    switch (command.command) {
      case 'editor.action.triggerParameterHints':
        triggerSignatureHelp();
      case 'editor.action.triggerSuggest':
        suggest.trigger();
      default:
        unawaited(
          languages
              .executeCommand(path, command, serverId: serverId)
              .catchError(reportError),
        );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_controllerChanged);
    languages.removeListener(_languagesChanged);
    for (final timer in [
      _hoverTimer,
      _hoverHideTimer,
      _lightbulbTimer,
      _semanticTimer,
      _signatureTimer,
      _messageTimer,
    ]) {
      timer?.cancel();
    }
    suggest.cancel();
    _rename?.dispose();
    super.dispose();
  }

  void _controllerChanged() {
    if (_disposed) return;
    final version = document.model.version;
    final selection = controller.value.selection;
    if (version != _version) {
      _version = version;
      _selection = selection;
      final typed = controller.lastTypedText;
      _hideHover();
      _message = null;
      _codeActionMenu = null;
      if (_rename != null) cancelRename();
      suggest.onTextChanged(typed);
      _signatureOnTextChanged(typed);
      _scheduleSemanticTokens();
      _scheduleLightbulb();
      notifyListeners();
    } else if (selection != _selection) {
      _selection = selection;
      suggest.onSelectionChanged();
      if (_hover?.keyboard ?? false) _hideHover();
      _message = null;
      _codeActionMenu = null;
      if (_signature != null) _scheduleSignatureHelp(retrigger: true);
      _scheduleLightbulb();
      notifyListeners();
    }
  }

  void _languagesChanged() {
    if (_disposed) return;
    if (_semantic == null) _scheduleSemanticTokens();
    _scheduleLightbulb();
    notifyListeners();
  }

  // ---- decorations ---------------------------------------------------------

  List<EditorDecoration> _decorations = const [];
  DocumentSnapshot? _decorationSnapshot;
  List<LspDiagnostic>? _decorationDiagnostics;
  (int, int)? _decorationLink;
  WorkbenchColors? _decorationColors;

  /// Diagnostics squiggles and the Cmd/Ctrl+hover link underline, in the
  /// current color theme. The same list instance comes back while nothing
  /// changed.
  List<EditorDecoration> get decorations {
    final snapshot = _snapshot;
    final diagnostics = languages.diagnosticsFor(path);
    final colors = themeColors;
    if (identical(snapshot, _decorationSnapshot) &&
        _sameDiagnostics(diagnostics, _decorationDiagnostics) &&
        _link == _decorationLink &&
        identical(colors, _decorationColors)) {
      return _decorations;
    }
    _decorationSnapshot = snapshot;
    _decorationDiagnostics = diagnostics;
    _decorationLink = _link;
    _decorationColors = colors;
    _decorations = [
      ...ideDiagnosticDecorations(snapshot, diagnostics),
      if (_link case (final start, final end))
        EditorDecoration(
          start: start,
          end: end,
          // `.goto-definition-link`.
          underlineColor: colors['editorLink.activeForeground'],
          underlineStyle: EditorUnderlineStyle.solid,
        ),
    ];
    return _decorations;
  }

  static bool _sameDiagnostics(List<LspDiagnostic> a, List<LspDiagnostic>? b) {
    if (identical(a, b)) return true;
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  // ---- semantic tokens -----------------------------------------------------

  IdeSemanticTokens? _semantic;
  Timer? _semanticTimer;
  int _semanticRequest = 0;
  int _semanticStyling = 0;
  (DocumentSnapshot, List<LspSemanticToken>)? _semanticSource;
  IdeSemanticTokenStyler? _semanticTokenStyler;
  String _languageId;
  Map<int, List<TextSpan>>? _overlayBase;
  IdeSemanticTokens? _overlayTokens;
  Map<int, List<TextSpan>>? _overlay;

  /// Styles the semantic tokens: the editor's color theme, as
  /// [ideSemanticTokenStyler] makes it. Null: [ideDefaultColorThemeId]'s,
  /// loaded from the bundled assets. Setting it restyles the latest tokens.
  IdeSemanticTokenStyler? get semanticTokenStyler => _semanticTokenStyler;
  set semanticTokenStyler(IdeSemanticTokenStyler? styler) {
    if (identical(styler, _semanticTokenStyler)) return;
    _semanticTokenStyler = styler;
    unawaited(_styleSemanticTokens());
  }

  /// The document's (VS Code's) language id, which semantic token rules
  /// may select. Setting it restyles the latest tokens.
  String get languageId => _languageId;
  set languageId(String languageId) {
    if (languageId == _languageId) return;
    _languageId = languageId;
    unawaited(_styleSemanticTokens());
  }

  /// [base] syntax spans restyled with the latest semantic tokens.
  Map<int, List<TextSpan>>? styledLines(Map<int, List<TextSpan>>? base) {
    final tokens = _semantic;
    if (tokens == null || tokens.isEmpty) return base;
    if (!identical(base, _overlayBase) || !identical(tokens, _overlayTokens)) {
      _overlayBase = base;
      _overlayTokens = tokens;
      _overlay = tokens.overlay(base);
    }
    return _overlay;
  }

  void _scheduleSemanticTokens({Duration delay = semanticTokensDelay}) {
    _semanticTimer?.cancel();
    _semanticTimer = Timer(delay, () => unawaited(_requestSemanticTokens()));
  }

  Future<void> _requestSemanticTokens() async {
    if (_disposed || !supports(LanguageRequest.semanticTokens)) return;
    final request = ++_semanticRequest;
    final snapshot = _snapshot;
    List<LspSemanticToken>? tokens;
    try {
      tokens = await languages.semanticTokens(path);
    } catch (error) {
      return;
    }
    if (_disposed || request != _semanticRequest || tokens == null) return;
    // Tokens for an older text still apply to the lines it did not change.
    _semanticSource = (snapshot, tokens);
    await _styleSemanticTokens();
  }

  /// Styles the latest tokens with the styler and language id; the default
  /// styler may still have to load.
  Future<void> _styleSemanticTokens() async {
    final source = _semanticSource;
    if (_disposed || source == null) return;
    final styling = ++_semanticStyling;
    var styler = _semanticTokenStyler;
    if (styler == null) {
      try {
        styler = await ideDefaultSemanticTokenStyler();
      } catch (_) {
        // Without the theme files, the syntax styles stay.
        return;
      }
      if (_disposed || styling != _semanticStyling) return;
    }
    _semantic = IdeSemanticTokens(
      source.$1,
      source.$2,
      styler: styler,
      languageId: _languageId,
    );
    notifyListeners();
  }

  // ---- messages --------------------------------------------------------------

  IdeEditorMessage? _message;
  Timer? _messageTimer;

  IdeEditorMessage? get message => _message;

  void showMessage(String text, {int? offset}) {
    _messageTimer?.cancel();
    _message = IdeEditorMessage(text, offset ?? _caret);
    _messageTimer = Timer(messageDuration, () {
      _message = null;
      changed();
    });
    changed();
  }

  // ---- hover -----------------------------------------------------------------

  IdeHoverState? _hover;
  Timer? _hoverTimer;
  Timer? _hoverHideTimer;
  int _hoverRequest = 0;
  int? _pointerOffset;
  (int, int)? _link;

  IdeHoverState? get hover => _hover;

  /// The Cmd/Ctrl+hover link under the pointer, if any.
  (int, int)? get link => _link;

  /// The pointer is over the text at [offset] (null: it left the text).
  void onPointerHover(int? offset) {
    _pointerOffset = offset;
    _updateLink();
    final current = _hover;
    if (offset == null) {
      _hoverTimer?.cancel();
      if (current != null && !current.keyboard) _scheduleHoverHide();
      return;
    }
    if (current != null &&
        !current.keyboard &&
        offset >= current.start &&
        offset <= current.end) {
      _hoverHideTimer?.cancel();
      return;
    }
    if (current != null && !current.keyboard) _scheduleHoverHide();
    _hoverTimer?.cancel();
    _hoverTimer = Timer(
      hoverDelay,
      () => unawaited(_showHover(offset, keyboard: false)),
    );
  }

  /// The pointer entered (true) or left the hover card.
  void onHoverCardPointer(bool inside) {
    if (inside) {
      _hoverHideTimer?.cancel();
    } else if (_hover != null && !_hover!.keyboard) {
      _scheduleHoverHide();
    }
  }

  void _scheduleHoverHide() {
    _hoverHideTimer?.cancel();
    _hoverHideTimer = Timer(hoverHideDelay, () {
      _hideHover();
      changed();
    });
  }

  void _hideHover() {
    _hoverTimer?.cancel();
    _hoverHideTimer?.cancel();
    _hoverRequest++;
    _hover = null;
  }

  /// ⌘K ⌘I: the hover at the caret.
  Future<void> showHoverAtCaret() => _showHover(_caret, keyboard: true);

  Future<void> _showHover(int offset, {required bool keyboard}) async {
    if (_disposed) return;
    final request = ++_hoverRequest;
    final version = document.model.version;
    final snapshot = _snapshot;
    final position = lspPositionAt(snapshot, offset);
    final diagnostics = [
      for (final d in languages.diagnosticsFor(path))
        if (_covers(snapshot, d.range, offset)) d,
    ];
    LspHover? hover;
    if (supports(LanguageRequest.hover)) {
      try {
        hover = await languages.hover(path, position);
      } catch (error) {
        hover = null;
      }
    }
    if (_disposed ||
        request != _hoverRequest ||
        version != document.model.version) {
      return;
    }
    if (hover == null && diagnostics.isEmpty) {
      if (_hover != null) {
        _hover = null;
        notifyListeners();
      }
      return;
    }
    var (start, end) = lspWordAt(snapshot, offset);
    if (hover?.range case final range?) {
      (start, end) = lspOffsetsOf(snapshot, range);
    } else if (start == end && diagnostics.isNotEmpty) {
      (start, end) = ideDiagnosticOffsets(snapshot, diagnostics.first.range);
    }
    _hoverHideTimer?.cancel();
    _hover = IdeHoverState(
      start: start,
      end: end,
      markdown: hover?.markdown,
      diagnostics: diagnostics,
      keyboard: keyboard,
    );
    notifyListeners();
  }

  static bool _covers(DocumentSnapshot snapshot, LspRange range, int offset) {
    final (start, end) = ideDiagnosticOffsets(snapshot, range);
    return offset >= start && offset <= end;
  }

  bool get _linkModifier {
    final keyboard = HardwareKeyboard.instance;
    return ideUsesMacKeys ? keyboard.isMetaPressed : keyboard.isControlPressed;
  }

  void _updateLink() {
    final offset = _pointerOffset;
    (int, int)? next;
    if (offset != null &&
        _linkModifier &&
        supports(LanguageRequest.definition)) {
      final word = lspWordAt(_snapshot, offset);
      if (word.$1 < word.$2) next = word;
    }
    if (next != _link) {
      _link = next;
      changed();
    }
  }

  /// The view scrolled: hovers follow upstream and close.
  void onViewChanged() {
    if (_hover != null && !_hover!.keyboard) {
      _hideHover();
      changed();
    }
  }

  /// Cmd/Ctrl+click goes to the definition under the pointer. Returns
  /// whether it took the click.
  bool onPointerDown(int offset, PointerDownEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event.buttons & kPrimaryButton == 0 ||
        !_linkModifier ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        !supports(LanguageRequest.definition)) {
      return false;
    }
    controller.select(offset, offset);
    _link = null;
    unawaited(goTo(IdeGoToKind.definition, offset: offset));
    return true;
  }

  // ---- go to -------------------------------------------------------------------

  int _goToRequest = 0;

  static const _goToLanguage = {
    IdeGoToKind.definition: LanguageRequest.definition,
    IdeGoToKind.typeDefinition: LanguageRequest.typeDefinition,
    IdeGoToKind.implementation: LanguageRequest.implementation,
    IdeGoToKind.references: LanguageRequest.references,
  };

  static const _goToNames = {
    IdeGoToKind.definition: 'definition',
    IdeGoToKind.typeDefinition: 'type definition',
    IdeGoToKind.implementation: 'implementation',
    IdeGoToKind.references: 'references',
  };

  /// Go to Definition (and friends) at [offset] or the caret: one target
  /// opens, several also list in the references panel, references always
  /// list there.
  Future<void> goTo(IdeGoToKind kind, {int? offset}) async {
    if (_disposed) return;
    final at = offset ?? _caret;
    final snapshot = _snapshot;
    final (wordStart, wordEnd) = lspWordAt(snapshot, at);
    final word = snapshot.text.substring(wordStart, wordEnd);
    if (!supports(_goToLanguage[kind]!)) {
      showMessage(
        "No ${_goToNames[kind]} found${word.isEmpty ? '' : " for '$word'"}",
        offset: at,
      );
      return;
    }
    final request = ++_goToRequest;
    final version = document.model.version;
    final position = lspPositionAt(snapshot, at);
    List<LspLocation> locations;
    try {
      locations = await switch (kind) {
        IdeGoToKind.definition => languages.definition(path, position),
        IdeGoToKind.typeDefinition => languages.typeDefinition(path, position),
        IdeGoToKind.implementation => languages.implementation(path, position),
        IdeGoToKind.references => languages.references(path, position),
      };
    } catch (error) {
      reportError(error);
      return;
    }
    if (_disposed ||
        request != _goToRequest ||
        version != document.model.version) {
      return;
    }
    final targets = <IdeLocation>[];
    for (final location in locations) {
      final target = IdeLocation.of(location);
      if (target != null && !targets.contains(target)) targets.add(target);
    }
    if (targets.isEmpty) {
      showMessage(
        "No ${_goToNames[kind]} found${word.isEmpty ? '' : " for '$word'"}",
        offset: at,
      );
      return;
    }
    if (kind == IdeGoToKind.references) {
      onShowReferences(
        word.isEmpty ? 'References' : "References to '$word'",
        targets,
      );
      return;
    }
    if (targets.length > 1) {
      onShowReferences(switch (kind) {
        IdeGoToKind.typeDefinition => 'Type Definitions',
        IdeGoToKind.implementation => 'Implementations',
        _ => 'Definitions',
      }, targets);
    }
    await onOpenLocation(targets.first);
  }

  // ---- signature help ------------------------------------------------------

  IdeSignatureState? _signature;
  Timer? _signatureTimer;
  int _signatureRequest = 0;

  IdeSignatureState? get signature => _signature;

  void _signatureOnTextChanged(String? typed) {
    final last = typed == null || typed.isEmpty
        ? null
        : typed.substring(typed.length - 1);
    if (last != null &&
        languages.signatureHelpTriggerCharacters(path).contains(last)) {
      _signatureTimer?.cancel();
      unawaited(triggerSignatureHelp(character: last));
      return;
    }
    if (_signature != null) {
      final retrigger =
          last != null &&
          languages.signatureHelpRetriggerCharacters(path).contains(last);
      _scheduleSignatureHelp(
        retrigger: true,
        character: retrigger ? last : null,
      );
    }
  }

  void _scheduleSignatureHelp({bool retrigger = false, String? character}) {
    _signatureTimer?.cancel();
    _signatureTimer = Timer(
      signatureHelpDelay,
      () => unawaited(
        triggerSignatureHelp(character: character, retrigger: retrigger),
      ),
    );
  }

  /// ⇧⌘Space, a trigger character, or a retrigger while it shows.
  Future<void> triggerSignatureHelp({
    String? character,
    bool retrigger = false,
  }) async {
    if (_disposed || !supports(LanguageRequest.signatureHelp)) return;
    final request = ++_signatureRequest;
    final snapshot = _snapshot;
    final caret = _caret;
    LspSignatureHelp? help;
    try {
      help = await languages.signatureHelp(
        path,
        lspPositionAt(snapshot, caret),
        triggerCharacter: character,
        retrigger: retrigger || _signature != null,
      );
    } catch (error) {
      help = null;
    }
    if (_disposed || request != _signatureRequest) return;
    if (help == null || help.signatures.isEmpty) {
      if (_signature != null) {
        _signature = null;
        notifyListeners();
      }
      return;
    }
    final previous = _signature;
    _signature = IdeSignatureState(help, caret);
    // Keep the overload the user picked when the server does not care.
    if (previous != null &&
        help.activeSignature == 0 &&
        previous.help.signatures.length == help.signatures.length &&
        previous.activeSignature < help.signatures.length) {
      _signature!.activeSignature = previous.activeSignature;
    }
    notifyListeners();
  }

  void cancelSignatureHelp() {
    _signatureTimer?.cancel();
    _signatureRequest++;
    if (_signature == null) return;
    _signature = null;
    changed();
  }

  void cycleSignature(int delta) {
    final state = _signature;
    if (state == null) return;
    final count = state.help.signatures.length;
    state.activeSignature = (state.activeSignature + delta + count) % count;
    changed();
  }

  // ---- rename ------------------------------------------------------------------

  IdeRenameState? _rename;
  int _renameRequest = 0;

  IdeRenameState? get rename => _rename;

  /// F2: asks where to rename, then shows the input.
  Future<void> startRename() async {
    if (_disposed) return;
    final at = _caret;
    if (!supports(LanguageRequest.rename)) {
      showMessage("The element can't be renamed.", offset: at);
      return;
    }
    final request = ++_renameRequest;
    final version = document.model.version;
    final snapshot = _snapshot;
    final position = lspPositionAt(snapshot, at);
    ({LspRange range, String placeholder})? prepared;
    try {
      prepared = await languages.prepareRename(path, position);
    } catch (error) {
      showMessage('$error', offset: at);
      return;
    }
    if (_disposed ||
        request != _renameRequest ||
        version != document.model.version) {
      return;
    }
    var (start, end) = prepared == null
        ? lspWordAt(snapshot, at)
        : lspOffsetsOf(snapshot, prepared.range);
    if (start == end) {
      showMessage("The element can't be renamed.", offset: at);
      return;
    }
    _rename?.dispose();
    _suggestAndHintsOff();
    _rename = IdeRenameState(
      start: start,
      end: end,
      position: position,
      version: version,
      placeholder: prepared?.placeholder ?? snapshot.text.substring(start, end),
    );
    notifyListeners();
  }

  void _suggestAndHintsOff() {
    suggest.cancel();
    cancelSignatureHelp();
    _hideHover();
  }

  /// Enter in the rename input.
  Future<void> acceptRename() async {
    final state = _rename;
    if (state == null) return;
    final newName = state.text.text;
    _rename = null;
    notifyListeners();
    onFocusEditor();
    // Dispose after the input has unmounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => state.dispose());
    if (newName.isEmpty || newName == state.placeholder) return;
    LspWorkspaceEdit? edit;
    try {
      edit = await languages.rename(path, state.position, newName);
    } catch (error) {
      showMessage('Rename failed: $error', offset: state.start);
      return;
    }
    if (_disposed) return;
    if (edit == null || edit.isEmpty) {
      showMessage('No result.', offset: state.start);
      return;
    }
    if (document.model.version != state.version) {
      showMessage(
        'Rename was cancelled because the document changed.',
        offset: state.start,
      );
      return;
    }
    final applied = await onApplyWorkspaceEdit(edit);
    if (!applied && !_disposed) {
      showMessage("Rename couldn't be applied.", offset: state.start);
    }
  }

  void cancelRename() {
    final state = _rename;
    if (state == null) return;
    _rename = null;
    changed();
    onFocusEditor();
    WidgetsBinding.instance.addPostFrameCallback((_) => state.dispose());
  }

  // ---- formatting --------------------------------------------------------------

  int _formatRequest = 0;

  /// Format Document, or Format Selection with [selection] (the caret's
  /// line when nothing is selected), as one undo step keeping the cursors.
  /// Returns whether the document changed.
  Future<bool> format({bool selection = false}) async {
    if (_disposed) return false;
    final request = selection
        ? LanguageRequest.rangeFormat
        : LanguageRequest.format;
    if (!supports(request)) {
      showMessage(
        selection
            ? 'No formatter for selections in this file.'
            : 'No formatter for this file.',
      );
      return false;
    }
    final id = ++_formatRequest;
    final version = document.model.version;
    final snapshot = _snapshot;
    LspRange? range;
    if (selection) {
      final s = controller.value.selection;
      if (s.isCollapsed) {
        final line = snapshot.positionAtOffset(s.extentOffset).lineNumber - 1;
        range = lspRangeOf(
          snapshot,
          snapshot.lineStarts[line],
          snapshot.contentEnds[line],
        );
      } else {
        range = lspRangeOf(snapshot, s.start, s.end);
      }
    }
    List<LspTextEdit> edits;
    try {
      edits = await languages.format(
        path,
        range: range,
        tabSize: controller.tabSize,
        insertSpaces: controller.insertSpaces,
      );
    } catch (error) {
      reportError(error);
      return false;
    }
    if (_disposed ||
        id != _formatRequest ||
        version != document.model.version) {
      return false;
    }
    final offsets = lspOffsetEdits(snapshot, edits);
    if (offsets == null || offsets.isEmpty) return false;
    return controller.applyEdits(minimalOffsetEdits(snapshot.text, offsets));
  }

  // ---- code actions ------------------------------------------------------------

  Timer? _lightbulbTimer;
  int _actionsRequest = 0;
  List<IdeCodeAction> _lightbulbActions = const [];
  int? _lightbulbLine;
  IdeCodeActionMenu? _codeActionMenu;

  /// The zero-based line whose glyph margin shows the lightbulb.
  int? get lightbulbLine => _lightbulbActions.isEmpty ? null : _lightbulbLine;

  /// Whether a preferred quick fix is among the lightbulb's actions.
  bool get lightbulbHasPreferredFix =>
      _lightbulbActions.any((a) => a.isPreferred);

  IdeCodeActionMenu? get codeActionMenu => _codeActionMenu;

  void _scheduleLightbulb() {
    _lightbulbTimer?.cancel();
    _actionsRequest++;
    if (!supports(LanguageRequest.codeActions)) {
      if (_lightbulbActions.isNotEmpty) {
        _lightbulbActions = const [];
        changed();
      }
      return;
    }
    _lightbulbTimer = Timer(lightbulbDelay, () async {
      final line = _snapshot.positionAtOffset(_caret).lineNumber - 1;
      final actions = await _fetchCodeActions();
      if (actions == null || _disposed) return;
      _lightbulbActions = [
        for (final a in actions)
          if (!a.isDisabled) a,
      ];
      _lightbulbLine = line;
      notifyListeners();
    });
  }

  /// Actions for the selection (or caret) with the diagnostics it touches;
  /// null when superseded.
  Future<List<IdeCodeAction>?> _fetchCodeActions() async {
    final request = ++_actionsRequest;
    final version = document.model.version;
    final snapshot = _snapshot;
    final selection = controller.value.selection;
    final range = lspRangeOf(snapshot, selection.start, selection.end);
    final diagnostics = [
      for (final d in languages.diagnosticsFor(path))
        if (_intersects(snapshot, d.range, selection.start, selection.end)) d,
    ];
    List<LspCodeAction> actions;
    try {
      actions = await languages.codeActions(
        path,
        range,
        diagnostics: diagnostics,
      );
    } catch (error) {
      return null;
    }
    if (_disposed ||
        request != _actionsRequest ||
        version != document.model.version) {
      return null;
    }
    return sortCodeActions([for (final a in actions) IdeCodeAction(a)]);
  }

  static bool _intersects(
    DocumentSnapshot snapshot,
    LspRange range,
    int start,
    int end,
  ) {
    final (a, b) = ideDiagnosticOffsets(snapshot, range);
    return a <= end && start <= b;
  }

  /// ⌘. (or a lightbulb click): the code actions menu at the caret; only
  /// those of kind [only] and its subkinds for Refactor... (`refactor`) and
  /// Source Action... (`source`).
  Future<void> showCodeActions({String? only}) async {
    if (_disposed) return;
    final at = _caret;
    final none = switch (only) {
      'refactor' => 'No refactorings available',
      'source' => 'No source actions available',
      _ => 'No code actions available',
    };
    if (!supports(LanguageRequest.codeActions)) {
      showMessage(none, offset: at);
      return;
    }
    _lightbulbTimer?.cancel();
    var actions = await _fetchCodeActions();
    if (actions == null || _disposed) return;
    if (only != null) {
      actions = [
        for (final action in actions)
          if (action.kind case final kind?
              when kind == only || kind.startsWith('$only.'))
            action,
      ];
    }
    if (actions.isEmpty) {
      showMessage(none, offset: at);
      return;
    }
    _suggestAndHintsOff();
    _codeActionMenu = IdeCodeActionMenu(at, groupCodeActions(actions));
    notifyListeners();
  }

  void closeCodeActions() {
    if (_codeActionMenu == null) return;
    _codeActionMenu = null;
    changed();
    onFocusEditor();
  }

  void selectCodeAction(int index) {
    final menu = _codeActionMenu;
    if (menu == null || index < 0 || index >= menu.actions.length) return;
    menu.selected = index;
    changed();
  }

  /// Applies [action]: resolves it when it came without an edit, applies the
  /// edit, then runs its command.
  Future<void> applyCodeAction(IdeCodeAction action) async {
    if (action.isDisabled) return;
    _codeActionMenu = null;
    changed();
    onFocusEditor();
    var resolved = action.action;
    if (resolved.edit == null) {
      try {
        resolved = await languages.resolveCodeAction(path, resolved);
      } catch (_) {
        // Keep what the list gave.
      }
    }
    if (_disposed) return;
    if (resolved.edit case final edit?) {
      final applied = await onApplyWorkspaceEdit(edit);
      if (!applied) {
        showMessage("The code action couldn't be applied.");
        return;
      }
    }
    if (resolved.command case final command?) {
      runCommand(
        command,
        serverId: resolved.serverId ?? action.action.serverId,
      );
    }
  }

  // ---- keys and commands -------------------------------------------------------

  /// Keys for the language widgets, before the editor's own bindings.
  KeyEventResult handleKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      // Keys are pressed/released after this event is handled.
      scheduleMicrotask(_updateLink);
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final plain =
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    if (_codeActionMenu case final menu?) {
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowUp) {
        final delta = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
        final count = menu.actions.length;
        var next = menu.selected;
        for (var i = 0; i < count; i++) {
          next = (next + delta + count) % count;
          if (!menu.actions[next].isDisabled) break;
        }
        selectCodeAction(next);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        unawaited(applyCodeAction(menu.actions[menu.selected]));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        closeCodeActions();
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    final suggested = suggest.handleKey(event);
    if (suggested != KeyEventResult.ignored || suggest.visible) {
      if (suggested != KeyEventResult.ignored) return suggested;
    }
    if (_signature case final state?) {
      if (key == LogicalKeyboardKey.escape && plain) {
        cancelSignatureHelp();
        return KeyEventResult.handled;
      }
      if (plain &&
          !suggest.visible &&
          state.help.signatures.length > 1 &&
          (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown)) {
        cycleSignature(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape && plain) {
      if (_hover != null) {
        _hideHover();
        changed();
        return KeyEventResult.handled;
      }
      if (_message != null) {
        _message = null;
        changed();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Runs a language command of `editorLanguageCommandLabels`; false for
  /// ids it does not own (problem navigation belongs to the workbench).
  bool run(String id) {
    switch (id) {
      case 'editor.action.revealDefinition':
        unawaited(goTo(IdeGoToKind.definition));
      case 'editor.action.goToTypeDefinition':
        unawaited(goTo(IdeGoToKind.typeDefinition));
      case 'editor.action.goToImplementation':
        unawaited(goTo(IdeGoToKind.implementation));
      case 'editor.action.goToReferences':
        unawaited(goTo(IdeGoToKind.references));
      case 'editor.action.rename':
        unawaited(startRename());
      case 'editor.action.formatDocument':
        unawaited(format());
      case 'editor.action.formatSelection':
        unawaited(format(selection: true));
      case 'editor.action.quickFix':
        unawaited(showCodeActions());
      case 'editor.action.refactor':
        unawaited(showCodeActions(only: 'refactor'));
      case 'editor.action.sourceAction':
        unawaited(showCodeActions(only: 'source'));
      case 'editor.action.triggerSuggest':
        suggest.trigger();
      case 'editor.action.triggerParameterHints':
        unawaited(triggerSignatureHelp());
      case 'editor.action.showHover':
        unawaited(showHoverAtCaret());
      default:
        return false;
    }
    return true;
  }
}
