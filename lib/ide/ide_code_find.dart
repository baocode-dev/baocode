import 'package:flutter/material.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:bao_editor/monaco/vs/editor/common/model/search/piece_tree_search.dart';
import 'package:bao_editor/monaco/vs/editor/contrib/find/browser/replace_pattern.dart';

import 'ide_find_widget.dart';

/// The IDE editor's find and replace (see `IdeEditorState`'s) for an
/// editor of its own ([IdeCodeEditor]'s): the same widget, matches and
/// moves, over [controller]'s text. Its host shows [widget] while
/// [visible], paints [decorations], and runs the find commands its keys
/// resolve to through [runCommand].
class IdeCodeFind extends ChangeNotifier {
  IdeCodeFind(this._controller, {this.readOnly = false}) {
    findController.addListener(_search);
    _controller.addListener(_textChanged);
  }

  EditorSurfaceController _controller;
  EditorSurfaceController get controller => _controller;
  set controller(EditorSurfaceController controller) {
    if (identical(controller, _controller)) return;
    _controller.removeListener(_textChanged);
    _controller = controller;
    controller.addListener(_textChanged);
    _searched = null;
    _search();
  }

  /// No replacing in a text that cannot be edited.
  bool readOnly;

  final TextEditingController findController = TextEditingController();
  final TextEditingController replaceController = TextEditingController();
  final FocusNode findFocusNode = FocusNode(debugLabel: 'code find');
  final FocusNode replaceFocusNode = FocusNode(debugLabel: 'code replace');

  bool get visible => _visible;
  bool _visible = false;
  bool get replaceVisible => _visible && _replaceVisible && !readOnly;
  bool _replaceVisible = false;
  bool _matchCase = false;
  bool _wholeWord = false;
  bool _regex = false;
  List<FindMatch> _results = const [];
  int _index = -1;

  /// The text last searched: searched again once it changes.
  DocumentSnapshot? _searched;
  bool _disposed = false;

  EditorDocumentModel get _model => _controller.document;

  SearchParams get _params => SearchParams(
    findController.text,
    isRegex: _regex,
    matchCase: _matchCase,
    wordSeparators: _wholeWord ? '`~!@#\$%^&*()-=+[{]}\\|;:\'",.<>/?' : null,
  );

  void _textChanged() {
    if (_visible && !identical(_searched, _model.snapshot)) _search();
  }

  void _search() {
    if (!_visible || _disposed) return;
    _searched = _model.snapshot;
    _results = _model.findMatches(_params);
    _index = -1;
    notifyListeners();
  }

  /// Opens (or focuses) the widget, its replace row with [replace]; the
  /// selection, on one line, is searched for.
  void open({bool replace = false}) {
    final value = _controller.value;
    final selection = value.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final selected = selection.textInside(value.text);
      if (!selected.contains('\n') && !selected.contains('\r')) {
        findController.text = selected;
      }
    }
    _visible = true;
    if (replace) _replaceVisible = true;
    _search();
    findFocusNode.requestFocus();
    findController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: findController.text.length,
    );
  }

  void close() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  /// The search string a find command takes from the selection (upstream
  /// `getSelectionSearchString`): the word at a caret, or the selected text
  /// when it is on one line (any lines with [multiline]).
  String? _selectionSearchString({bool multiline = false}) {
    final value = _controller.value;
    final selection = value.selection;
    if (!selection.isValid) return null;
    if (selection.isCollapsed) {
      return _controller.wordAt(selection.extentOffset);
    }
    final text = selection.textInside(value.text);
    if (!multiline && (text.contains('\n') || text.contains('\r'))) {
      return null;
    }
    return text.length < 524288 ? text : null;
  }

  /// Shows the widget without moving the focus, searching for [seed] when
  /// given (escaped in regular expression mode).
  void _reveal({String? seed}) {
    final shown = !_visible;
    _visible = true;
    final text = seed == null ? null : (_regex ? RegExp.escape(seed) : seed);
    if (text != null && text != findController.text) {
      // Its listener searches again.
      findController.text = text;
    } else if (shown) {
      _search();
    }
  }

  void _toggle(void Function() toggle) {
    toggle();
    _search();
  }

  /// The match after the current one (before it with [backwards]), else
  /// after the selection; selected and scrolled to.
  void select({bool backwards = false}) {
    if (_results.isEmpty) return;
    final snapshot = _model.snapshot;
    final selection = _controller.value.selection;
    final offset = _index >= 0 && _index < _results.length
        ? snapshot.offsetAtPosition(
            backwards
                ? _results[_index].range.getStartPosition()
                : _results[_index].range.getEndPosition(),
          )
        // Upstream: from the selection's start backwards, else its end.
        : backwards
        ? selection.start
        : selection.end;
    var start = snapshot.positionAtOffset(
      offset.clamp(0, snapshot.text.length),
    );
    if (_index >= 0 &&
        _index < _results.length &&
        _results[_index].range.isEmpty()) {
      final length = snapshot.text.length;
      if (backwards) {
        start = snapshot.positionAtOffset(offset == 0 ? length : offset - 1);
      } else {
        var next = offset < length ? offset + 1 : 0;
        while (next < length && start.equals(snapshot.positionAtOffset(next))) {
          next++;
        }
        start = snapshot.positionAtOffset(next);
      }
    }
    final match = backwards
        ? _model.findPreviousMatch(_params, start)
        : _model.findNextMatch(_params, start);
    if (match == null) return;
    _index = _results.indexWhere((item) => item.range.equalsRange(match.range));
    _selectRange(match.range.getStartPosition(), match.range.getEndPosition());
    notifyListeners();
  }

  void _selectRange(Position start, Position end) {
    final snapshot = _model.snapshot;
    _controller
      ..select(snapshot.offsetAtPosition(start), snapshot.offsetAtPosition(end))
      ..revealSelection();
  }

  ReplacePattern get _replacePattern => _regex
      ? parseReplaceString(replaceController.text)
      : ReplacePattern.fromStaticValue(replaceController.text);

  void _replaceOne() {
    if (readOnly || _results.isEmpty) return;
    if (_index < 0 || _index >= _results.length) return select();
    final snapshot = _model.snapshot;
    final range = _results[_index].range;
    final start = snapshot.offsetAtPosition(range.getStartPosition());
    final end = snapshot.offsetAtPosition(range.getEndPosition());
    final selection = _controller.value.selection;
    if (selection.start != start || selection.end != end) {
      _selectRange(range.getStartPosition(), range.getEndPosition());
      return;
    }
    final matches = _model.findMatches(
      _params,
      captureMatches: _regex,
      limitResultCount: _index + 1,
    );
    if (_index >= matches.length || !matches[_index].range.equalsRange(range)) {
      return _search();
    }
    final replacement = _replacePattern.buildReplaceString(
      matches[_index].matches,
    );
    _controller.applyEdits([EditorOffsetEdit(start, end, replacement)]);
    final after = start + replacement.length;
    _controller.select(after, after);
    _search();
  }

  void _replaceAll() {
    if (readOnly) return;
    final snapshot = _model.snapshot;
    final matches = _model.findMatches(
      _params,
      captureMatches: _regex,
      limitResultCount: 0x1fffffffffffff,
    );
    if (matches.isEmpty) return;
    final pattern = _replacePattern;
    _controller.applyEdits([
      for (final match in matches)
        EditorOffsetEdit(
          snapshot.offsetAtPosition(match.range.getStartPosition()),
          snapshot.offsetAtPosition(match.range.getEndPosition()),
          pattern.buildReplaceString(match.matches),
        ),
    ]);
    _search();
  }

  /// The commands of the editor's find (see `IdeEditorState`'s): whether
  /// [id] is one, run.
  bool runCommand(String id) {
    switch (id) {
      case 'actions.find':
        open();
      case 'editor.action.startFindReplaceAction':
        open(replace: true);
      case 'editor.action.nextMatchFindAction':
      case 'editor.action.previousMatchFindAction':
        final backwards = id == 'editor.action.previousMatchFindAction';
        _reveal(
          seed: findController.text.isEmpty ? _selectionSearchString() : null,
        );
        select(backwards: backwards);
      case 'editor.action.nextSelectionMatchFindAction':
      case 'editor.action.previousSelectionMatchFindAction':
        _reveal(seed: _selectionSearchString());
        select(
          backwards: id == 'editor.action.previousSelectionMatchFindAction',
        );
      case 'actions.findWithSelection':
        _reveal(seed: _selectionSearchString(multiline: true));
      case 'closeFindWidget':
        if (!_visible) return false;
        close();
      case 'toggleFindCaseSensitive':
        _toggle(() => _matchCase = !_matchCase);
      case 'toggleFindWholeWord':
        _toggle(() => _wholeWord = !_wholeWord);
      case 'toggleFindRegex':
        _toggle(() => _regex = !_regex);
      case 'editor.action.replaceOne':
        if (!_visible) return false;
        _replaceOne();
      case 'editor.action.replaceAll':
        if (!_visible) return false;
        _replaceAll();
      default:
        return false;
    }
    return true;
  }

  /// The matches as the text's decorations; the current one stands out.
  List<EditorDecoration> get decorations {
    if (!_visible || _results.isEmpty) return const [];
    final snapshot = _model.snapshot;
    int offset(Position position) => snapshot.offsetAtPosition(position);
    return [
      for (var i = 0; i < _results.length; i++)
        if (i == _index)
          EditorDecoration.currentFindMatch(
            offset(_results[i].range.getStartPosition()),
            offset(_results[i].range.getEndPosition()),
          )
        else
          EditorDecoration.findMatch(
            offset(_results[i].range.getStartPosition()),
            offset(_results[i].range.getEndPosition()),
          ),
    ];
  }

  /// The widget, its keys VS Code's ([IdeFindWidget]'s own); [onClose]
  /// after it closes (the text focused again).
  Widget widget({required VoidCallback onClose}) => IdeFindWidget(
    findController: findController,
    replaceController: replaceController,
    findFocusNode: findFocusNode,
    replaceFocusNode: replaceFocusNode,
    replaceVisible: replaceVisible,
    matchCase: _matchCase,
    wholeWord: _wholeWord,
    regex: _regex,
    matchCount: _results.length,
    currentIndex: _index,
    onToggleReplace: readOnly
        ? null
        : () {
            _replaceVisible = !_replaceVisible;
            notifyListeners();
          },
    onToggleMatchCase: () => _toggle(() => _matchCase = !_matchCase),
    onToggleWholeWord: () => _toggle(() => _wholeWord = !_wholeWord),
    onToggleRegex: () => _toggle(() => _regex = !_regex),
    onPrevious: () => select(backwards: true),
    onNext: select,
    onClose: () {
      close();
      onClose();
    },
    onReplace: _replaceOne,
    onReplaceAll: _replaceAll,
    commandIds: editorFindCommandIds,
    // Lines found across, as the editor's.
    multiline: true,
  );

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_textChanged);
    findController.dispose();
    replaceController.dispose();
    findFocusNode.dispose();
    replaceFocusNode.dispose();
    super.dispose();
  }
}
