// Find in a conversation (⌘F): what the user and the agent said, matched
// as the editor's find matches (case, whole words, a regular expression),
// marked where it shows and stepped through, the history scrolling to each
// match.

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import '../ide/ide_find_widget.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'chat_feed.dart';
import 'chat_models.dart';
import 'chat_session.dart';
import 'widgets/markdown_tags.dart';
import 'widgets/markdown_view.dart';

/// A match: in row [item] of the conversation, its [occurrence]th there,
/// [fraction] of the way through the row's text; or an unloaded earlier
/// match in the turn starting at [promptUuid] (found via the session index).
@immutable
class ChatFindMatch {
  const ChatFindMatch(this.item, this.occurrence, this.fraction)
    : promptUuid = null;

  /// A match inside an unloaded earlier turn, resolved once that turn loads.
  const ChatFindMatch.earlier(this.promptUuid, this.occurrence)
    : item = -1,
      fraction = 0;

  final int item;
  final int occurrence;
  final double fraction;

  /// Prompt UUID of the unloaded earlier turn holding this match; null for
  /// matches in already-loaded rows.
  final String? promptUuid;

  bool get isEarlier => promptUuid != null;

  @override
  bool operator ==(Object other) =>
      other is ChatFindMatch &&
      other.item == item &&
      other.occurrence == occurrence &&
      other.promptUuid == promptUuid;

  @override
  int get hashCode => Object.hash(item, occurrence, promptUuid);
}

/// The find of a conversation: whether its bar shows, what it looks for,
/// the matches in [feed] and the one at hand.
class ChatFind extends ChangeNotifier {
  ChatFind() {
    text.addListener(_typed);
  }

  final TextEditingController text = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'BaoCode chat find');

  /// What it searches: set by the history it shows over.
  ChatFeed? get feed => _feed;
  ChatFeed? _feed;
  set feed(ChatFeed? feed) {
    if (identical(feed, _feed)) return;
    _feed?.removeListener(_feedChanged);
    _feed = feed;
    if (_visible) feed?.addListener(_feedChanged);
    _texts.clear();
    _pendingEarlier = null;
    _search(keep: false);
  }

  bool get visible => _visible;
  bool _visible = false;

  bool matchCase = false;
  bool wholeWord = false;
  bool regex = false;

  List<ChatFindMatch> get matches => _matches;
  List<ChatFindMatch> _matches = const [];

  /// The match at hand; -1 for none.
  int get current => _current;
  int _current = -1;

  ChatFindMatch? get currentMatch =>
      _current < 0 || _current >= _matches.length ? null : _matches[_current];

  /// Counts the times the match at hand was asked to be brought into view:
  /// the history scrolls to it as this changes.
  int get reveals => _reveals;
  int _reveals = 0;

  /// The last of [reveals] a mark brought into view (see [ChatFindMarks]).
  int _revealed = 0;

  /// A search's query was shown before the conversation it found it in
  /// was read: its first match is brought into view once there.
  bool _revealFound = false;

  /// What it looks for, as the options say; null for nothing (nothing
  /// typed, or no regular expression).
  RegExp? get pattern => _visible ? _pattern : null;
  RegExp? _pattern;

  RegExp? _compile() {
    final query = text.text;
    if (query.isEmpty) return null;
    var source = regex ? query : RegExp.escape(query);
    if (wholeWord) source = r'\b(?:' + source + r')\b';
    try {
      final pattern = RegExp(source, caseSensitive: matchCase);
      // One matching nothing would match everywhere.
      if (pattern.hasMatch('')) return null;
      return pattern;
    } on FormatException {
      return null;
    }
  }

  /// Shows the bar, focused, its text all selected; looking for [query]
  /// when given (a search's), its first match brought into view.
  void show({String? query}) {
    if (!_visible) {
      _visible = true;
      _feed?.addListener(_feedChanged);
    }
    if (query != null) {
      text.removeListener(_typed);
      text.text = query;
      text.addListener(_typed);
    }
    text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.text.length,
    );
    _revealFound = query != null;
    _search(keep: query == null, reveal: query != null);
    focusNode.requestFocus();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    _revealFound = false;
    _pendingEarlier = null;
    _searchGen++;
    _feed?.removeListener(_feedChanged);
    _matches = const [];
    _loadedMatches = const [];
    _earlierMatches = const [];
    _current = -1;
    notifyListeners();
  }

  void next() => _step(1);
  void previous() => _step(-1);

  void toggleMatchCase() {
    matchCase = !matchCase;
    _pendingEarlier = null;
    _search(keep: false, reveal: true);
  }

  void toggleWholeWord() {
    wholeWord = !wholeWord;
    _pendingEarlier = null;
    _search(keep: false, reveal: true);
  }

  void toggleRegex() {
    regex = !regex;
    _pendingEarlier = null;
    _search(keep: false, reveal: true);
  }

  /// Notes that the view is loading earlier history to reveal [match] so the
  /// next search pass selects and reveals the corresponding loaded match.
  void expectingEarlier(ChatFindMatch match) {
    if (!match.isEarlier) return;
    _pendingEarlier = (
      promptUuid: match.promptUuid!,
      occurrence: match.occurrence,
    );
  }

  void _step(int by) {
    if (_matches.isEmpty) return;
    _revealFound = false;
    _pendingEarlier = null;
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
    _revealFound = false;
    _pendingEarlier = null;
    _search(keep: false, reveal: true);
  }

  /// A search is due after this frame: a conversation read back comes as
  /// a burst of changes, searched once it is all there (its turns folded
  /// as they end up), not once per change.
  bool _due = false;

  void _feedChanged() {
    if (_due) return;
    _due = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        if (!_due) return;
        _due = false;
        _search(keep: true);
      })
      ..ensureVisualUpdate();
  }

  String? _searched;
  int _searchGen = 0;
  List<ChatFindMatch> _loadedMatches = const [];
  List<ChatFindMatch> _earlierMatches = const [];
  ({String promptUuid, int occurrence})? _pendingEarlier;

  /// Each item's text as last searched: an item streamed or edited is a
  /// new one, its text found anew.
  final Map<ChatItem, String> _texts = Map.identity();

  /// The matches anew: the one at hand kept where it still is ([keep]), or
  /// the first, brought into view with [reveal].
  void _search({required bool keep, bool reveal = false}) {
    _due = false;
    _searched = text.text;
    final gen = ++_searchGen;
    final before = currentMatch;
    final pattern = _pattern = _compile();
    final feed = _feed;
    final found = <ChatFindMatch>[];
    if (_visible && pattern != null && feed != null) {
      final texts = <ChatItem, String>{};
      for (var i = 0; i < feed.itemCount; i++) {
        final item = feed.itemAt(i);
        final text = texts[item] = _texts[item] ?? searchableText(item);
        if (text.isEmpty) continue;
        var occurrence = 0;
        for (final match in pattern.allMatches(text)) {
          if (match.end == match.start) continue;
          found.add(ChatFindMatch(i, occurrence++, match.start / text.length));
        }
      }
      _texts
        ..clear()
        ..addAll(texts);
    }
    _loadedMatches = found;
    _earlierMatches = const [];
    _matches = found;
    if (_pendingEarlier case final pending? when found.isNotEmpty) {
      _pendingEarlier = null;
      _revealFound = false;
      _current = pending.occurrence.clamp(0, found.length - 1);
      _reveals++;
    } else if (_revealFound && found.isNotEmpty) {
      _revealFound = false;
      _current = 0;
      _reveals++;
    } else if (keep && before != null && found.contains(before)) {
      _current = found.indexOf(before);
    } else {
      _current = found.isEmpty ? -1 : 0;
      if (reveal && found.isNotEmpty) _reveals++;
    }
    notifyListeners();

    if (_visible &&
        pattern != null &&
        feed is ChatSession &&
        feed.hasEarlierHistory) {
      unawaited(
        _searchEarlier(
          gen,
          feed,
          pattern,
          revealIfNone: (reveal || _revealFound) && found.isEmpty,
        ),
      );
    }
  }

  Future<void> _searchEarlier(
    int gen,
    ChatSession session,
    RegExp pattern, {
    required bool revealIfNone,
  }) async {
    final hits = await session.searchEarlier(pattern);
    if (gen != _searchGen || !_visible || !identical(_feed, session)) return;
    if (hits.isEmpty) return;
    final earlier = <ChatFindMatch>[
      for (final hit in hits)
        for (var o = 0; o < hit.occurrences; o++)
          ChatFindMatch.earlier(hit.promptUuid, o),
    ];
    if (earlier.isEmpty) return;
    final before = currentMatch;
    _earlierMatches = earlier;
    _matches = [..._earlierMatches, ..._loadedMatches];
    if (before != null && !before.isEarlier) {
      final at = _matches.indexOf(before);
      if (at >= 0) _current = at;
    } else if (revealIfNone) {
      _revealFound = false;
      _current = 0;
      _reveals++;
    } else if (_current < 0) {
      _current = 0;
    }
    notifyListeners();
  }

  /// What of [item] is searched, as it shows: what the user said, and the
  /// agent's words without their markdown.
  static String searchableText(ChatItem item) => switch (item) {
    UserMessageItem(:final text) => text,
    AssistantTextItem(:final text) => markdownText(text),
    _ => '',
  };

  /// [markdown]'s text as [MarkdownView] shows it, its blocks a line apart.
  static String markdownText(String markdown) {
    final out = StringBuffer();
    void visit(md.Node node) {
      switch (node) {
        case md.Text(:final text):
          out.write(text.replaceAll(_htmlComment, ''));
        case md.Element(tag: 'math'):
          break;
        // Its title over it, as it shows.
        case md.Element(tag: TagBlockSyntax.tag, :final children):
          if (out.isNotEmpty) out.write('\n');
          if (TagSection.titleOf(node) case final title?) {
            out.write(title);
          }
          children?.forEach(visit);
          out.write('\n');
        case md.Element(:final tag, :final children):
          final block = _blocks.contains(tag);
          if (block && out.isNotEmpty) out.write('\n');
          children?.forEach(visit);
          if (block) out.write('\n');
      }
    }

    MarkdownView.document(tags: true).parse(markdown).forEach(visit);
    return out.toString();
  }

  static final _htmlComment = RegExp(r'<!--[\s\S]*?-->');
  static const _blocks = {
    'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'pre', 'blockquote', //
    'tr', 'td', 'th', 'hr', 'ul', 'ol', 'table',
  };

  @override
  void dispose() {
    _due = false;
    _feed?.removeListener(_feedChanged);
    text.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

/// The find over the conversation under it (see [ChatFindRow]).
class ChatFindScope extends InheritedNotifier<ChatFind> {
  const ChatFindScope({
    super.key,
    required ChatFind? find,
    required super.child,
  }) : super(notifier: find);

  static ChatFind? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatFindScope>()?.notifier;
}

/// Row [index] of the conversation, the matches in it marked (where a
/// [ChatFindMarks] shows text), in the order they are in it.
class ChatFindRow extends StatelessWidget {
  const ChatFindRow({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  /// Whether the find's match at hand is in the row [context] is in: what
  /// hides part of the row (a long message's lines) shows it all then.
  static bool holdsCurrent(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowScope>()?.current != null;

  @override
  Widget build(BuildContext context) {
    final find = ChatFindScope.maybeOf(context);
    final pattern = find?.pattern;
    final match = find?.currentMatch;
    return _RowScope(
      find: pattern == null ? null : find,
      pattern: pattern,
      current: match?.item == index ? match!.occurrence : null,
      reveals: find?.reveals ?? 0,
      child: _RowBox(child: child),
    );
  }
}

class _RowScope extends InheritedWidget {
  const _RowScope({
    required this.find,
    required this.pattern,
    required this.current,
    required this.reveals,
    required super.child,
  });

  final ChatFind? find;
  final RegExp? pattern;
  final int? current;
  final int reveals;

  @override
  bool updateShouldNotify(_RowScope oldWidget) =>
      find != oldWidget.find ||
      pattern != oldWidget.pattern ||
      current != oldWidget.current ||
      // A reveal only matters to the row holding the match at hand.
      (current != null && reveals != oldWidget.reveals);
}

/// A row's box: where its marks count their matches from.
class _RowBox extends SingleChildRenderObjectWidget {
  const _RowBox({required super.child});

  @override
  _RenderRow createRenderObject(BuildContext context) => _RenderRow();
}

class _RenderRow extends RenderProxyBox {
  /// Per mark, the matches before it in the row; null until asked for,
  /// once each time it paints.
  Map<_RenderMarks, int>? _starts;

  int startOf(_RenderMarks marks) {
    final starts = _starts ??= _count();
    return starts[marks] ?? 0;
  }

  Map<_RenderMarks, int> _count() {
    final starts = Map<_RenderMarks, int>.identity();
    var count = 0;
    void visit(RenderObject node) {
      if (node is _RenderMarks) {
        starts[node] = count;
        count += node._matches.length;
        return;
      }
      node.visitChildren(visit);
    }

    visitChildren(visit);
    return starts;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _starts = null;
    super.paint(context, offset);
  }
}

/// [child], a [Text] (or one inside, as [Text.rich] puts it), with the
/// matches of the conversation's find marked on its text: under it, as a
/// selection is; the one at hand brought into view when asked to.
class ChatFindMarks extends SingleChildRenderObjectWidget {
  const ChatFindMarks({super.key, required super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderMarks()..scope = _scopeOf(context);

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) =>
      (renderObject as _RenderMarks).scope = _scopeOf(context);

  static _RowScope? _scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_RowScope>();
}

class _RenderMarks extends RenderProxyBox {
  _RowScope? _scope;
  set scope(_RowScope? value) {
    final old = _scope;
    _scope = value;
    if (old?.pattern != value?.pattern ||
        old?.current != value?.current ||
        old?.reveals != value?.reveals) {
      markNeedsPaint();
    }
  }

  /// The paragraph within: [Text] may put a mouse region around it.
  RenderParagraph? get _paragraph {
    RenderObject? node = child;
    while (node != null && node is! RenderParagraph) {
      RenderObject? only;
      node.visitChildren((c) => only ??= c);
      node = only;
    }
    return node as RenderParagraph?;
  }

  /// The matches in the paragraph's text as last laid out: found again
  /// for another text or pattern.
  List<TextSelection> get _matches {
    final pattern = _scope?.pattern;
    final paragraph = _paragraph;
    if (pattern == null || paragraph == null) return const [];
    final text = paragraph.text;
    if (identical(text, _matchedText) && identical(pattern, _matchedBy)) {
      return _found;
    }
    _matchedText = text;
    _matchedBy = pattern;
    final plain = text.toPlainText(includeSemanticsLabels: false);
    return _found = [
      for (final match in pattern.allMatches(plain))
        if (match.end > match.start)
          TextSelection(baseOffset: match.start, extentOffset: match.end),
    ];
  }

  InlineSpan? _matchedText;
  RegExp? _matchedBy;
  List<TextSelection> _found = const [];

  _RenderRow? get _row {
    for (var node = parent; node != null; node = node.parent) {
      if (node is _RenderRow) return node;
    }
    return null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final scope = _scope;
    final paragraph = _paragraph;
    final matches = _matches;
    if (scope != null && paragraph != null && matches.isNotEmpty) {
      final colors = themeColors;
      final others = Paint()
        ..color =
            colors.get('editor.findMatchHighlightBackground') ??
            const Color(0x66EA5C00);
      final atHand = Paint()
        ..color =
            colors.get('editor.findMatchBackground') ?? const Color(0xFF9E6A03);
      final transform = paragraph.getTransformTo(this);
      final start = scope.current == null ? 0 : (_row?.startOf(this) ?? 0);
      Rect? shown;
      for (final (i, match) in matches.indexed) {
        final current = start + i == scope.current;
        for (final box in paragraph.getBoxesForSelection(match)) {
          final rect = MatrixUtils.transformRect(transform, box.toRect());
          if (current) shown = shown?.expandToInclude(rect) ?? rect;
          context.canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect.shift(offset),
              const Radius.circular(2),
            ),
            current ? atHand : others,
          );
        }
      }
      final find = scope.find;
      if (shown != null && find != null && find._revealed != scope.reveals) {
        find._revealed = scope.reveals;
        final rect = shown;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!attached) return;
          showOnScreen(
            rect: rect.inflate(48),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        });
      }
    }
    super.paint(context, offset);
  }
}

/// The find bar over a conversation: the editor's.
class ChatFindBar extends StatelessWidget {
  const ChatFindBar({super.key, required this.find});

  final ChatFind find;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: find,
    builder: (context, _) {
      if (!find.visible) return const SizedBox.shrink();
      return IdeFindWidget(
        findController: find.text,
        findFocusNode: find.focusNode,
        matchCase: find.matchCase,
        wholeWord: find.wholeWord,
        regex: find.regex,
        matchCount: find.matches.length,
        currentIndex: find.current,
        onToggleMatchCase: find.toggleMatchCase,
        onToggleWholeWord: find.toggleWholeWord,
        onToggleRegex: find.toggleRegex,
        onPrevious: find.previous,
        onNext: find.next,
        onClose: find.hide,
      );
    },
  );
}
