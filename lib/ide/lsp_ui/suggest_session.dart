import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_keybindings.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/snippet/browser/snippet_parser.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/suggest/browser/completion_model.dart';

import '../language/language_features.dart';
import '../language/language_types.dart';
import 'language_editor.dart';
import 'lsp_convert.dart';

/// What opened the suggest widget (upstream `CompletionTriggerKind` plus
/// whether it was asked for).
enum IdeSuggestTrigger { explicit, character, typing }

typedef IdeSuggestItem = CompletionItem<LspCompletionItem>;

/// The completion session of one editor: triggers, requests, filtering with
/// the ported [CompletionModel], selection, resolving and insertion
/// (upstream SuggestModel + SuggestController, simplified: one session, no
/// word-distance ranking, `editor.suggest.insertMode` `insert`).
class IdeSuggestSession {
  IdeSuggestSession(this._editor);

  final IdeLanguageEditor _editor;

  /// `editor.quickSuggestionsDelay`.
  static const quickSuggestionsDelay = Duration(milliseconds: 10);

  /// Rows the widget shows at once (`editor.suggest.maxVisibleSuggestions`).
  static const pageSize = 12;

  bool _active = false;
  IdeSuggestTrigger _trigger = IdeSuggestTrigger.typing;
  int _request = 0;
  bool _loading = false;
  CompletionModel<LspCompletionItem>? _model;
  List<IdeSuggestItem> _items = const [];
  int _selected = 0;
  int _line = -1;
  int _wordStart = 0;
  Timer? _quickTimer;
  final Map<LspCompletionItem, LspCompletionItem> _resolved = Map.identity();
  final Set<LspCompletionItem> _resolving = Set.identity();

  /// Whether the details side panel is expanded (⌃Space toggles).
  bool detailsExpanded = true;

  bool get active => _active;
  bool get loading => _loading;
  IdeSuggestTrigger get triggerKind => _trigger;

  /// Whether the widget shows: items, or an explicit request's
  /// "Loading..." / "No suggestions." line.
  bool get visible =>
      _active && (_items.isNotEmpty || _trigger == IdeSuggestTrigger.explicit);

  List<IdeSuggestItem> get items => _items;
  int get selectedIndex => _selected;
  IdeSuggestItem? get selected =>
      _selected >= 0 && _selected < _items.length ? _items[_selected] : null;

  /// Where the widget anchors: the start of the word being completed.
  int get anchorOffset => _wordStart;

  /// [item] with what resolving filled in, once it has.
  LspCompletionItem resolvedOf(LspCompletionItem item) =>
      _resolved[item] ?? item;

  LanguageFeatures get _languages => _editor.languages;
  String get _path => _editor.document.path;
  DocumentSnapshot get _snapshot => _editor.document.model.snapshot;
  int get _caret => _editor.controller.value.selection.extentOffset;

  int _lineOf(int offset) => _snapshot.positionAtOffset(offset).lineNumber - 1;

  /// Opens completion at the caret (⌃Space, a trigger character, or quick
  /// suggestions while typing a word).
  void trigger({
    IdeSuggestTrigger kind = IdeSuggestTrigger.explicit,
    String? character,
  }) {
    _quickTimer?.cancel();
    if (!_editor.controller.value.selection.isValid) return;
    if (!_languages.supports(_path, LanguageRequest.completion)) {
      if (_active) cancel();
      return;
    }
    final snapshot = _snapshot;
    final caret = _caret;
    final (wordStart, _) = lspWordAt(snapshot, caret);
    _active = true;
    _trigger = kind;
    _line = _lineOf(caret);
    _wordStart = math.min(wordStart, caret);
    _loading = true;
    _model = null;
    _items = const [];
    _selected = 0;
    _editor.changed();
    unawaited(_query(character: character));
  }

  Future<void> _query({String? character, bool retrigger = false}) async {
    final request = ++_request;
    final snapshot = _snapshot;
    final caret = _caret;
    final position = lspPositionAt(snapshot, caret);
    LspCompletionList list;
    try {
      list = await _languages.completion(
        _path,
        position,
        triggerCharacter: character,
        retrigger: retrigger,
      );
    } catch (error) {
      if (request == _request && !_editor.isDisposed) {
        _loading = false;
        cancel();
        _editor.reportError(error);
      }
      return;
    }
    if (request != _request || !_active || _editor.isDisposed) return;
    if (_lineOf(_caret) != _line) {
      cancel();
      return;
    }
    _loading = false;
    _model = _buildModel(list, snapshot, caret, position);
    _refilter(fresh: true);
  }

  CompletionModel<LspCompletionItem> _buildModel(
    LspCompletionList list,
    DocumentSnapshot snapshot,
    int caret,
    LspPosition request,
  ) {
    final line = request.line + 1;
    final position = Position(line, request.character + 1);
    final lineStart = snapshot.lineStarts[request.line];
    final (wordStart, wordEnd) = lspWordAt(snapshot, caret);
    Position one(LspPosition p) => Position(p.line + 1, p.character + 1);
    final items = <IdeSuggestItem>[
      for (final item in list.items)
        () {
          final edit = item.textEdit;
          final editStart = edit == null
              ? Position(line, math.min(wordStart, caret) - lineStart + 1)
              : one(edit.range.start);
          return IdeSuggestItem(
            position: position,
            completion: item,
            label: item.label,
            editStart: editStart,
            editInsertEnd: item.insertRange != null
                ? one(item.insertRange!.end)
                : edit != null
                ? one(edit.range.end)
                : position,
            editReplaceEnd: edit != null
                ? one(edit.range.end)
                : Position(line, math.max(wordEnd, caret) - lineStart + 1),
            filterText: item.filterText,
            sortText: item.sortText,
            isSnippetKind: item.kind == LspCompletionKind.snippet,
            kindIndex: item.kind.index,
            provider: item.serverId,
            incomplete: list.isIncomplete,
            invalidRange:
                editStart.lineNumber != line ||
                editStart.column > position.column,
          );
        }(),
    ];
    items.sort(getSuggestionComparator(SnippetSortOrder.inline));
    return CompletionModel(
      items,
      position.column,
      _lineContext(request.character + 1),
    );
  }

  LineContext _lineContext(int requestColumn) {
    final snapshot = _snapshot;
    final caret = _caret;
    final line = _lineOf(caret);
    final lineStart = snapshot.lineStarts[line];
    return LineContext(
      snapshot.text.substring(lineStart, caret),
      caret - lineStart + 1 - requestColumn,
    );
  }

  void _refilter({bool fresh = false}) {
    final model = _model;
    if (model == null) return;
    final requestColumn = model.allItems.isEmpty
        ? null
        : model.allItems.first.position.column;
    if (requestColumn != null) {
      model.lineContext = _lineContext(requestColumn);
    }
    _items = model.items;
    if (_items.isEmpty) {
      if (_trigger != IdeSuggestTrigger.explicit) {
        cancel();
        return;
      }
      _selected = 0;
    } else if (fresh || model.lineContext.characterCountDelta <= 0) {
      // Nothing typed since the request: the preselected item wins.
      final word = _items.first.word;
      final preselect = word.isEmpty
          ? _items.indexWhere((item) => item.completion.preselect)
          : -1;
      _selected = preselect < 0 ? 0 : preselect;
    } else {
      // Refiltering selects the best match again.
      _selected = 0;
    }
    _resolveSelected();
    _editor.changed();
  }

  /// The document changed; [typed] is what the keyboard just inserted.
  void onTextChanged(String? typed) {
    final caret = _caret;
    final last = typed == null || typed.isEmpty
        ? null
        : typed.substring(typed.length - 1);
    final triggers = last == null
        ? const <String>{}
        : _languages.completionTriggerCharacters(_path);
    if (_active) {
      if (last != null && triggers.contains(last)) {
        trigger(kind: IdeSuggestTrigger.character, character: last);
        return;
      }
      if (_lineOf(caret) != _line || caret < _wordStart) {
        cancel();
        return;
      }
      final (wordStart, _) = lspWordAt(_snapshot, caret);
      if (typed == null &&
          wordStart == caret &&
          _trigger == IdeSuggestTrigger.typing) {
        // Deleted the whole word that opened quick suggestions.
        cancel();
        return;
      }
      if (_model case final model?
          when model.getIncompleteProvider().isNotEmpty) {
        unawaited(_query(retrigger: true));
      }
      _refilter();
      return;
    }
    if (last == null) return;
    if (triggers.contains(last)) {
      trigger(kind: IdeSuggestTrigger.character, character: last);
    } else if (lspIsWordUnit(last.codeUnitAt(0)) &&
        !RegExp(r'^\d$').hasMatch(last)) {
      _quickTimer?.cancel();
      final version = _editor.document.model.version;
      _quickTimer = Timer(quickSuggestionsDelay, () {
        if (_editor.isDisposed ||
            _active ||
            _editor.document.model.version != version) {
          return;
        }
        final caret = _caret;
        final (wordStart, _) = lspWordAt(_snapshot, caret);
        if (wordStart < caret) trigger(kind: IdeSuggestTrigger.typing);
      });
    }
  }

  /// The caret moved without an edit.
  void onSelectionChanged() {
    if (!_active) return;
    final caret = _caret;
    final selection = _editor.controller.value.selection;
    if (!selection.isCollapsed ||
        _lineOf(caret) != _line ||
        caret < _wordStart) {
      cancel();
      return;
    }
    final (_, wordEnd) = lspWordAt(_snapshot, _wordStart);
    if (caret > math.max(wordEnd, _wordStart)) {
      cancel();
      return;
    }
    _refilter();
  }

  void cancel() {
    _quickTimer?.cancel();
    if (!_active) return;
    _active = false;
    _request++;
    _loading = false;
    _model = null;
    _items = const [];
    _selected = 0;
    _editor.changed();
  }

  void select(int index) {
    if (_items.isEmpty) return;
    final next = index.clamp(0, _items.length - 1);
    if (next == _selected) return;
    _selected = next;
    _resolveSelected();
    _editor.changed();
  }

  void _move(int delta, {bool wrap = true}) {
    if (_items.isEmpty) return;
    final length = _items.length;
    var next = _selected + delta;
    if (wrap && delta.abs() == 1) {
      next = (next + length) % length;
    } else {
      next = next.clamp(0, length - 1);
    }
    select(next);
  }

  void _resolveSelected() {
    final item = selected?.completion;
    if (item == null || _resolved.containsKey(item) || !_resolving.add(item)) {
      return;
    }
    final request = _request;
    unawaited(
      _languages
          .resolveCompletion(_path, item)
          .then((resolved) {
            _resolving.remove(item);
            _resolved[item] = resolved;
            if (request == _request &&
                !_editor.isDisposed &&
                identical(selected?.completion, item)) {
              _editor.changed();
            }
          })
          .catchError((Object _) {
            _resolving.remove(item);
          }),
    );
  }

  /// Keys while the widget shows. Commit characters accept the selection
  /// and still type (the result is then [KeyEventResult.ignored]). With
  /// [commandKeys] false only those: the app's keybindings run the
  /// widget's commands ([selectNext], [acceptSelected], [cancel], ...).
  KeyEventResult handleKey(KeyEvent event, {bool commandKeys = true}) {
    if (!visible || event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final chord = editorKeyChordOf(event);
    if (commandKeys &&
        chord != null &&
        matchEditorLanguageKey(chord) == 'editor.action.triggerSuggest') {
      toggleDetails();
      return KeyEventResult.handled;
    }
    final modified =
        keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed;
    final key = event.logicalKey;
    if (!modified && commandKeys) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _move(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _move(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.pageDown) {
        _move(pageSize - 1, wrap: false);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.pageUp) {
        _move(-(pageSize - 1), wrap: false);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        cancel();
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.tab) &&
          !keyboard.isShiftPressed) {
        final item = selected;
        if (item == null) {
          cancel();
          return KeyEventResult.ignored;
        }
        accept(item);
        return KeyEventResult.handled;
      }
    }
    if (!modified) {
      if (event.character case final character?
          when character.length == 1 && selected != null) {
        final item = selected!;
        final commit = resolvedOf(item.completion).commitCharacters;
        if (commit.contains(character)) {
          accept(item);
          return KeyEventResult.ignored;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  /// selectNextSuggestion: the next item, after the last the first.
  void selectNext() => _move(1);

  /// selectPrevSuggestion: the previous item, before the first the last.
  void selectPrevious() => _move(-1);

  /// selectNextPageSuggestion.
  void selectNextPage() => _move(pageSize - 1, wrap: false);

  /// selectPrevPageSuggestion.
  void selectPreviousPage() => _move(-(pageSize - 1), wrap: false);

  /// toggleSuggestionDetails: expands or collapses the details panel.
  void toggleDetails() {
    detailsExpanded = !detailsExpanded;
    _editor.changed();
  }

  /// acceptSelectedSuggestion, or with [alternative]
  /// acceptAlternativeSelectedSuggestion (the other `insertMode`: the item
  /// replaces the rest of the word too). False when no item is selected.
  bool acceptSelected({bool alternative = false}) {
    final item = selected;
    if (!visible || item == null) return false;
    accept(item, replace: alternative);
    return true;
  }

  /// Inserts [item] (upstream SuggestController._insertSuggestion); with
  /// [replace], over its replace range (to the end of the word) rather
  /// than its insert range.
  void accept(IdeSuggestItem item, {bool replace = false}) {
    final controller = _editor.controller;
    final original = item.completion;
    final completion = resolvedOf(original);
    final snapshot = _snapshot;
    final caret = _caret;
    final line = _lineOf(caret);
    final lineStart = snapshot.lineStarts[line];
    final column = caret - lineStart + 1;
    final overwriteBefore = math.max(0, column - item.editStart.column);
    final overwriteAfter = math.max(
      0,
      (replace ? item.editReplaceEnd : item.editInsertEnd).column -
          item.position.column,
    );
    final text = original.isSnippet
        ? original.text
        : SnippetParser.escape(original.text);
    final additional =
        lspOffsetEdits(snapshot, completion.additionalTextEdits) ??
        const <EditorOffsetEdit>[];
    final needsResolve =
        !_resolved.containsKey(original) &&
        completion.additionalTextEdits.isEmpty;
    cancel();
    controller.insertSnippet(
      text,
      overwriteBefore: overwriteBefore,
      overwriteAfter: overwriteAfter,
      additionalEdits: additional,
    );
    if (needsResolve) {
      unawaited(_applyLateEdits(original, snapshot, caret - overwriteBefore));
    }
    if (completion.command case final command?) {
      _editor.runCommand(command, serverId: completion.serverId);
    }
  }

  /// Additional edits a resolve brings after the insertion (imports):
  /// applied as their own step when they sit before the inserted text and
  /// nothing else changed meanwhile.
  Future<void> _applyLateEdits(
    LspCompletionItem item,
    DocumentSnapshot before,
    int insertStart,
  ) async {
    final version = _editor.document.model.version;
    LspCompletionItem resolved;
    try {
      resolved = await _languages.resolveCompletion(_path, item);
    } catch (_) {
      return;
    }
    if (_editor.isDisposed ||
        resolved.additionalTextEdits.isEmpty ||
        _editor.document.model.version != version) {
      return;
    }
    final edits = lspOffsetEdits(before, resolved.additionalTextEdits);
    if (edits == null || edits.any((e) => e.end > insertStart)) return;
    _editor.controller.applyEdits(edits);
  }
}
