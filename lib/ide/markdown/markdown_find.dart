// Find in a markdown file's preview (⌘F): matched in its text as the
// editor's find matches (case, whole words, a regular expression), the
// match at hand selected and brought into view.

import 'package:flutter/widgets.dart';

/// The find of a preview: whether its bar shows, what it looks for, the
/// matches in [source]'s text and the one at hand.
class MarkdownFind extends ChangeNotifier {
  MarkdownFind(this.source) {
    text.addListener(_typed);
  }

  /// The text searched, as it is now.
  final String Function() source;

  final TextEditingController text = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'markdown preview find');

  bool get visible => _visible;
  bool _visible = false;

  bool matchCase = false;
  bool wholeWord = false;
  bool regex = false;

  List<TextRange> get matches => _matches;
  List<TextRange> _matches = const [];

  /// The match at hand; -1 for none.
  int get current => _current;
  int _current = -1;

  TextRange? get currentMatch =>
      _current < 0 || _current >= _matches.length ? null : _matches[_current];

  /// Counts the times the match at hand was asked to be shown: the
  /// preview selects it and scrolls to it as this changes.
  int get reveals => _reveals;
  int _reveals = 0;

  /// The text last searched, and the query: searched anew once either
  /// changed.
  String? _searchedIn;
  String? _searched;

  RegExp? _compile() {
    final query = text.text;
    if (query.isEmpty) return null;
    var pattern = regex ? query : RegExp.escape(query);
    if (wholeWord) pattern = r'\b(?:' + pattern + r')\b';
    try {
      final compiled = RegExp(pattern, caseSensitive: matchCase);
      // One matching nothing would match everywhere.
      if (compiled.hasMatch('')) return null;
      return compiled;
    } on FormatException {
      return null;
    }
  }

  /// Shows the bar, focused, its text all selected; looking for [query]
  /// when given (what is selected), from [from] on.
  void show({String? query, int from = 0}) {
    _visible = true;
    if (query != null && query.isNotEmpty) {
      text.removeListener(_typed);
      text.text = query;
      text.addListener(_typed);
    }
    text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.text.length,
    );
    _search(from: from);
    focusNode.requestFocus();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    _matches = const [];
    _current = -1;
    notifyListeners();
  }

  void next() => _step(1);
  void previous() => _step(-1);

  void toggleMatchCase() {
    matchCase = !matchCase;
    _search(from: currentMatch?.start ?? 0);
  }

  void toggleWholeWord() {
    wholeWord = !wholeWord;
    _search(from: currentMatch?.start ?? 0);
  }

  void toggleRegex() {
    regex = !regex;
    _search(from: currentMatch?.start ?? 0);
  }

  void _step(int by) {
    // The file edited since: its matches where they are now.
    if (source() != _searchedIn) {
      _search(from: currentMatch?.start ?? 0, reveal: false);
    }
    if (_matches.isEmpty) return;
    _current = _current < 0
        ? (by > 0 ? 0 : _matches.length - 1)
        : (_current + by) % _matches.length;
    _reveals++;
    notifyListeners();
  }

  void _typed() {
    final value = text.value;
    // A selection moving is no new text, nor a word the IME still composes.
    if (value.text == _searched) return;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    _search(from: currentMatch?.start ?? 0);
  }

  /// The matches anew, the one at hand the first at or after [from] (the
  /// first of all past the last), shown unless not to [reveal].
  void _search({required int from, bool reveal = true}) {
    _searched = text.text;
    final source = _searchedIn = this.source();
    final pattern = _compile();
    _matches = !_visible || pattern == null
        ? const []
        : [
            for (final match in pattern.allMatches(source))
              if (match.end > match.start)
                TextRange(start: match.start, end: match.end),
          ];
    if (_matches.isEmpty) {
      _current = -1;
    } else {
      final at = _matches.indexWhere((match) => match.start >= from);
      _current = at < 0 ? 0 : at;
      if (reveal) _reveals++;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    text.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
