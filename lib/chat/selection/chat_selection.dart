// The conversation's selection, kept in one place: two places in its text,
// each an item, a piece of text in it (in reading order) and an offset in
// that. What is highlighted is painted from them, and what is copied is
// read from them; the text does not keep a selection of its own.
//
// Flutter's own selection lives in the text: each paragraph keeps what of
// it is selected, and a list builds only what it shows. Kept so, the
// conversation's selection needed a second copy across what is not built,
// kept in step with the paragraphs' by item numbers, row numbers and the
// order the text registered in; each a place for the two to part (a
// highlight that copied nothing). Here there is one copy, and the text
// shown is only asked where its characters are.

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A place in the conversation's text: item [item], its piece of text
/// [leaf] (in reading order, see [chatTextLeaves]), character [offset] in
/// that.
@immutable
class ChatTextPos implements Comparable<ChatTextPos> {
  const ChatTextPos(this.item, this.leaf, this.offset);

  final int item;
  final int leaf;
  final int offset;

  @override
  int compareTo(ChatTextPos other) {
    if (item != other.item) return item.compareTo(other.item);
    if (leaf != other.leaf) return leaf.compareTo(other.leaf);
    return offset.compareTo(other.offset);
  }

  bool operator <(ChatTextPos other) => compareTo(other) < 0;
  bool operator >(ChatTextPos other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is ChatTextPos &&
      other.item == item &&
      other.leaf == leaf &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(item, leaf, offset);

  @override
  String toString() => '($item, $leaf, $offset)';
}

/// A piece of the conversation's text as shown: a paragraph, a label
/// selected whole, a thought streaming in.
abstract interface class ChatTextLeaf {
  /// What it is laid out in.
  RenderBox get box;

  /// Its text; offsets count in it.
  String get text;

  /// What a copy of [start] to [end] takes: [text]'s, but for what shows in
  /// place of a character (a formula's TeX for its placeholder).
  String copyOf(int start, int end);

  /// The offset nearest [local], a point in [box].
  int positionAt(Offset local);

  /// Where [start] to [end] shows, in [box].
  List<Rect> rectsFor(int start, int end);

  /// The word around [offset].
  TextRange wordAt(int offset);
}

/// A render object that is a piece of the conversation's text itself
/// (rather than a [RenderParagraph], which is found as one).
abstract interface class ChatTextLeafSource {
  ChatTextLeaf? get chatTextLeaf;
}

/// A piece of text selected whole or not at all, copied as [text].
class AtomicChatTextLeaf implements ChatTextLeaf {
  AtomicChatTextLeaf(this.box, String copied) : _copied = copied;

  @override
  final RenderBox box;
  final String _copied;

  /// One character: in or out.
  @override
  String get text => '￼';

  @override
  String copyOf(int start, int end) => start < end ? _copied : '';

  @override
  int positionAt(Offset local) => local.dx < box.size.width / 2 ? 0 : 1;

  @override
  List<Rect> rectsFor(int start, int end) =>
      start < end ? [Offset.zero & box.size] : const [];

  @override
  TextRange wordAt(int offset) => const TextRange(start: 0, end: 1);
}

/// A [RenderParagraph] (any [Text] or [RichText]) as a piece of the text.
class _ParagraphLeaf implements ChatTextLeaf {
  _ParagraphLeaf(this.paragraph)
    : text = paragraph.text.toPlainText(includeSemanticsLabels: false);

  final RenderParagraph paragraph;

  @override
  RenderBox get box => paragraph;

  @override
  final String text;

  @override
  String copyOf(int start, int end) {
    start = start.clamp(0, text.length);
    end = end.clamp(start, text.length);
    final part = text.substring(start, end);
    if (!part.contains('￼')) return part;
    // Each placeholder's own text, in order: what is in its widget.
    final shown = <String>[];
    var child = paragraph.firstChild;
    while (child != null) {
      shown.add(_copiedIn(child));
      child = paragraph.childAfter(child);
    }
    var placeholder = '￼'.allMatches(text.substring(0, start)).length;
    final buffer = StringBuffer();
    for (final unit in part.split('')) {
      if (unit == '￼') {
        buffer.write(placeholder < shown.length ? shown[placeholder] : '');
        placeholder++;
      } else {
        buffer.write(unit);
      }
    }
    return buffer.toString();
  }

  /// What a placeholder's widget copies as: the text of the pieces in it.
  static String _copiedIn(RenderObject object) {
    final leaves = <ChatTextLeaf>[];
    _collect(object, leaves);
    return [for (final leaf in leaves) leaf.copyOf(0, leaf.text.length)].join();
  }

  @override
  int positionAt(Offset local) =>
      paragraph.getPositionForOffset(local).offset.clamp(0, text.length);

  @override
  List<Rect> rectsFor(int start, int end) => [
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    ))
      box.toRect(),
  ];

  @override
  TextRange wordAt(int offset) =>
      paragraph.getWordBoundary(TextPosition(offset: offset));
}

/// What is out of the conversation's selection: a control's label, a card
/// that selects on its own. (Out of Flutter's too, for a selection area
/// around it elsewhere.)
class ChatUnselectable extends StatelessWidget {
  const ChatUnselectable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SelectionContainer.disabled(child: _Unselectable(child: child));
}

class _Unselectable extends SingleChildRenderObjectWidget {
  const _Unselectable({super.child});

  @override
  RenderChatUnselectable createRenderObject(BuildContext context) =>
      RenderChatUnselectable();
}

class RenderChatUnselectable extends RenderProxyBox {}

/// Text that copies its pieces on one line apart by [separator] (a table's
/// cells by tabs), not by a space.
class ChatTextRow extends SingleChildRenderObjectWidget {
  const ChatTextRow({super.key, required this.separator, super.child});

  final String separator;

  @override
  RenderChatTextRow createRenderObject(BuildContext context) =>
      RenderChatTextRow(separator);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatTextRow renderObject,
  ) => renderObject.separator = separator;
}

class RenderChatTextRow extends RenderProxyBox {
  RenderChatTextRow(this.separator);

  String separator;
}

/// A piece of text found in an item, and the groups it is in (outermost
/// first): what joins it to the one before on a line is the innermost
/// group's both are in.
typedef _Found = ({ChatTextLeaf leaf, List<RenderChatTextRow> groups});

void _collect(
  RenderObject object,
  List<ChatTextLeaf> leaves, [
  List<List<RenderChatTextRow>>? paths,
  List<RenderChatTextRow> groups = const [],
]) {
  if (object is RenderChatUnselectable) return;
  if (object is RenderOffstage && object.offstage) return;
  if (object is RenderBox && !object.hasSize) return;
  if (object is ChatTextLeafSource) {
    if ((object as ChatTextLeafSource).chatTextLeaf case final leaf?) {
      leaves.add(leaf);
      paths?.add(groups);
      return;
    }
  }
  if (object is RenderParagraph) {
    // Text (a [Text]'s) registers for selection; an icon's glyph does not.
    if (object.registrar != null) {
      leaves.add(_ParagraphLeaf(object));
      paths?.add(groups);
    }
    return;
  }
  final inner = object is RenderChatTextRow ? [...groups, object] : groups;
  object.visitChildren((child) => _collect(child, leaves, paths, inner));
}

List<_Found> _findLeaves(RenderObject root) {
  final leaves = <ChatTextLeaf>[];
  final paths = <List<RenderChatTextRow>>[];
  root.visitChildren((child) => _collect(child, leaves, paths));
  return [
    for (var i = 0; i < leaves.length; i++) (leaf: leaves[i], groups: paths[i]),
  ];
}

/// What joins two pieces on one line, in the groups [a] and [b].
String _joinOnLine(List<RenderChatTextRow> a, List<RenderChatTextRow> b) {
  var join = ' ';
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (!identical(a[i], b[i])) break;
    join = a[i].separator;
  }
  return join;
}

/// The pieces of text under [root], in reading order.
List<ChatTextLeaf> chatTextLeaves(RenderObject root) => [
  for (final found in _findLeaves(root)) found.leaf,
];

/// An item's text as last seen: each piece's, and how it joins the one
/// before. Kept for an item that holds an end of the selection, to copy
/// from once it is no longer built.
@immutable
class ChatItemText {
  const ChatItemText(this.pieces);

  final List<({String text, String copied, String join})> pieces;

  /// The text from [start] to [end] (null for its start or end), pieces
  /// joined as they show.
  String copy(ChatTextPos? start, ChatTextPos? end) {
    final buffer = StringBuffer();
    for (var i = 0; i < pieces.length; i++) {
      if (start != null && i < start.leaf) continue;
      if (end != null && i > end.leaf) break;
      final piece = pieces[i];
      final from = start != null && i == start.leaf ? start.offset : 0;
      final to = end != null && i == end.leaf ? end.offset : piece.text.length;
      final part = from == 0 && to >= piece.text.length
          ? piece.copied
          : _slice(piece.text, piece.copied, from, to);
      if (part.isEmpty) continue;
      if (buffer.isNotEmpty) {
        final written = buffer.toString();
        final spaced =
            written.endsWith(' ') ||
            written.endsWith('\n') ||
            part.startsWith(' ');
        buffer.write(
          piece.join == '\n'
              ? '\n'
              : (spaced && piece.join == ' ' ? '' : piece.join),
        );
      }
      buffer.write(part);
    }
    return buffer.toString();
  }

  // A part of a piece whose copy is its text (placeholders aside, a part
  // of one whose copy differs is its text's part).
  static String _slice(String text, String copied, int from, int to) {
    from = from.clamp(0, text.length);
    to = to.clamp(from, text.length);
    if (text == copied) return text.substring(from, to);
    // An atomic piece (one placeholder character): in or out.
    if (text.length == 1) return from < to ? copied : '';
    return text.substring(from, to).replaceAll('￼', '');
  }
}

/// The selection of a conversation, and what is shown of it to ask.
class ChatSelectionController extends ChangeNotifier {
  ChatSelectionController({required this.plainTextOf, required this.itemCount});

  /// The text of item [index], from the conversation (built or not).
  final String Function(int index) plainTextOf;
  final int Function() itemCount;

  ChatTextPos? _anchor;
  ChatTextPos? _focus;

  /// For a selection by words or paragraphs: the unit the press was on,
  /// which stays selected whichever way it is dragged.
  (ChatTextPos, ChatTextPos)? _unit;
  TextGranularity _granularity = TextGranularity.character;

  /// Everything, built or not.
  bool _all = false;

  /// Items built now, by index: what is laid out of each.
  final Map<int, RenderChatSelectionItem> _items = {};

  /// The text of the items that hold an end, as last built.
  final Map<int, ChatItemText> _endText = {};

  ChatTextPos? get anchor => _anchor;
  ChatTextPos? get focus => _focus;
  bool get selectsAll => _all;

  /// The selection's start and end, in order; null when nothing is
  /// selected.
  (ChatTextPos, ChatTextPos)? get range {
    if (_all) {
      final count = itemCount();
      if (count == 0) return null;
      return (
        const ChatTextPos(0, 0, 0),
        ChatTextPos(count - 1, 1 << 30, 1 << 30),
      );
    }
    final anchor = _anchor;
    final focus = _focus;
    if (anchor == null || focus == null || anchor == focus) return null;
    return anchor < focus ? (anchor, focus) : (focus, anchor);
  }

  bool get hasSelection => range != null;

  /// Whether item [index] holds an end of what is selected.
  bool holdsEnd(int index) {
    final range = this.range;
    return range != null && (range.$1.item == index || range.$2.item == index);
  }

  void _attach(RenderChatSelectionItem item) => _items[item.index] = item;

  void _detach(RenderChatSelectionItem item) {
    if (identical(_items[item.index], item)) {
      _rememberText(item);
      _items.remove(item.index);
    }
  }

  void _renumber(RenderChatSelectionItem item, int from) {
    if (identical(_items[from], item)) _items.remove(from);
    _items[item.index] = item;
  }

  /// The items built now, by index.
  Map<int, RenderChatSelectionItem> get builtItems => _items;

  void _rememberText(RenderChatSelectionItem item) {
    if (!holdsEnd(item.index) || !item.attached) return;
    _endText[item.index] = item.text();
  }

  // --- Changes --------------------------------------------------------------

  void clear() {
    if (_anchor == null && _focus == null && !_all) return;
    _anchor = _focus = null;
    _unit = null;
    _all = false;
    _endText.clear();
    notifyListeners();
  }

  /// A press at [pos]: nothing selected, the selection to start there.
  void start(ChatTextPos pos) {
    _all = false;
    _unit = null;
    _granularity = TextGranularity.character;
    _anchor = _focus = pos;
    _endText.clear();
    notifyListeners();
  }

  /// A unit of text pressed on (a word, a paragraph): selected, and a drag
  /// from it extends by the same units.
  void selectUnit(ChatTextPos start, ChatTextPos end, TextGranularity unit) {
    _all = false;
    _granularity = unit;
    _unit = (start, end);
    _anchor = start;
    _focus = end;
    _endText.clear();
    _rememberEnds();
    notifyListeners();
  }

  /// The selection's moving end to [pos] (by the press's units: [unitAt]
  /// gives the one there).
  void extendTo(
    ChatTextPos pos, {
    (ChatTextPos, ChatTextPos)? Function(ChatTextPos pos, TextGranularity unit)?
    unitAt,
  }) {
    if (_all) {
      _all = false;
      _anchor ??= const ChatTextPos(0, 0, 0);
    }
    _anchor ??= pos;
    if (_unit case (final start, final end)
        when _granularity != TextGranularity.character) {
      final around = unitAt?.call(pos, _granularity) ?? (pos, pos);
      if (pos < start) {
        _anchor = end;
        _focus = around.$1;
      } else {
        _anchor = start;
        _focus = around.$2 > end ? around.$2 : end;
      }
    } else {
      _focus = pos;
    }
    _rememberEnds();
    notifyListeners();
  }

  /// Shift+click: the end nearest [pos] moves there.
  void extendNearestTo(ChatTextPos pos) {
    final range = this.range;
    if (range == null) {
      extendTo(pos);
      return;
    }
    _all = false;
    _unit = null;
    _granularity = TextGranularity.character;
    if (pos < range.$1) {
      _anchor = range.$2;
    } else if (pos > range.$2) {
      _anchor = range.$1;
    } else {
      _anchor ??= range.$1;
    }
    _focus = pos;
    _rememberEnds();
    notifyListeners();
  }

  void selectAll() {
    _all = true;
    _unit = null;
    _endText.clear();
    notifyListeners();
  }

  /// [count] items came in before all the others (earlier history).
  void shiftItems(int count) {
    ChatTextPos? shifted(ChatTextPos? pos) => pos == null
        ? null
        : ChatTextPos(pos.item + count, pos.leaf, pos.offset);
    _anchor = shifted(_anchor);
    _focus = shifted(_focus);
    if (_unit case (final start, final end)) {
      _unit = (shifted(start)!, shifted(end)!);
    }
    final text = {
      for (final MapEntry(:key, :value) in _endText.entries) key + count: value,
    };
    _endText
      ..clear()
      ..addAll(text);
  }

  void _rememberEnds() {
    final range = this.range;
    if (range == null) return;
    for (final index in {range.$1.item, range.$2.item}) {
      if (_items[index] case final item? when item.attached) {
        _endText[index] = item.text();
      }
    }
    _endText.removeWhere(
      (index, _) => index != range.$1.item && index != range.$2.item,
    );
  }

  /// Called as the items are laid out: the text of those holding an end is
  /// kept up to date (it streams), read once the frame is laid out.
  void didLayOut(RenderChatSelectionItem item) {
    if (!holdsEnd(item.index) || !_laidOut.add(item)) return;
    if (_laidOut.length > 1) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final item in _laidOut) {
        if (item.attached && holdsEnd(item.index)) {
          _endText[item.index] = item.text();
        }
      }
      _laidOut.clear();
    });
  }

  final Set<RenderChatSelectionItem> _laidOut = {};

  // --- Reading ---------------------------------------------------------------

  /// What of item [index] is selected: from (null: its start) to (null:
  /// its end); null when none of it is.
  ({ChatTextPos? from, ChatTextPos? to})? selectedIn(int index) {
    final range = this.range;
    if (range == null) return null;
    final (start, end) = range;
    if (index < start.item || index > end.item) return null;
    return (
      from: index == start.item ? start : null,
      to: index == end.item ? end : null,
    );
  }

  /// The selected text, the items between the ends whole, built or not.
  String? selectedText() {
    final range = this.range;
    if (range == null) return null;
    final (start, end) = range;
    final count = itemCount();
    final parts = <String>[];
    for (var index = start.item; index <= end.item && index < count; index++) {
      final from = index == start.item ? start : null;
      final to = index == end.item ? end : null;
      final String text;
      if (_items[index] case final item? when item.attached) {
        text = item.text().copy(from, to);
      } else if (from == null && to == null) {
        text = plainTextOf(index);
      } else if (_endText[index] case final kept?) {
        text = kept.copy(from, to);
      } else {
        // An end item never built while it was one: all of it.
        text = _all ? plainTextOf(index) : '';
      }
      if (text.isNotEmpty) parts.add(text);
    }
    final text = parts.join('\n');
    return text.isEmpty ? null : text;
  }

  // --- Places ------------------------------------------------------------------

  /// The place in the text nearest [global], among the items built; null
  /// when none is.
  ChatTextPos? positionAt(Offset global) {
    final item = _itemNear(global);
    if (item == null) return null;
    return item.positionAt(global);
  }

  RenderChatSelectionItem? _itemNear(Offset global) {
    RenderChatSelectionItem? best;
    var bestDistance = double.infinity;
    for (final item in _items.values) {
      if (!item.attached || !item.hasSize) continue;
      final top = item.localToGlobal(Offset.zero).dy;
      final bottom = top + item.size.height;
      final distance = global.dy < top
          ? top - global.dy
          : global.dy > bottom
          ? global.dy - bottom
          : 0.0;
      if (distance < bestDistance ||
          (distance == bestDistance &&
              best != null &&
              // Between two (a gap): the one below, read next.
              item.index > best.index &&
              distance > 0 &&
              global.dy < top)) {
        best = item;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The word, or paragraph (a line of a piece of text), at [pos].
  (ChatTextPos, ChatTextPos)? unitAt(ChatTextPos pos, TextGranularity unit) {
    final item = _items[pos.item];
    if (item == null || !item.attached) return null;
    final leaves = item.leaves();
    if (pos.leaf >= leaves.length) return null;
    final leaf = leaves[pos.leaf];
    final TextRange range;
    if (unit == TextGranularity.word) {
      range = leaf.wordAt(pos.offset.clamp(0, leaf.text.length));
    } else {
      final text = leaf.text;
      final at = pos.offset.clamp(0, text.length);
      final start = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
      final end = text.indexOf('\n', at);
      range = TextRange(start: start, end: end == -1 ? text.length : end);
    }
    return (
      ChatTextPos(pos.item, pos.leaf, range.start),
      ChatTextPos(pos.item, pos.leaf, range.end),
    );
  }

  /// Where [pos] shows, globally (a point on its line), if built.
  Offset? globalOf(ChatTextPos pos) {
    final item = _items[pos.item];
    if (item == null || !item.attached) return null;
    final leaves = item.leaves();
    if (leaves.isEmpty) return item.localToGlobal(Offset.zero);
    final leaf = leaves[math.min(pos.leaf, leaves.length - 1)];
    final offset = pos.offset.clamp(0, leaf.text.length);
    final rects = leaf.rectsFor(
      math.max(0, offset - 1),
      math.min(leaf.text.length, offset + 1),
    );
    final rect = rects.isEmpty ? Offset.zero & leaf.box.size : rects.first;
    return leaf.box.localToGlobal(rect.center);
  }
}

/// The conversation item [index] whose text is under it, and its
/// selection's [controller].
class ChatSelectionItemScope extends InheritedWidget {
  const ChatSelectionItemScope({
    super.key,
    required this.index,
    required this.controller,
    required super.child,
  });

  final int index;
  final ChatSelectionController controller;

  /// Whether the item holds an end of the selection (its text must stay
  /// laid out to be copied from there).
  bool get holdsEnd => controller.holdsEnd(index);

  static ChatSelectionItemScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatSelectionItemScope>();

  @override
  bool updateShouldNotify(ChatSelectionItemScope oldWidget) =>
      index != oldWidget.index || controller != oldWidget.controller;
}

/// An item of the conversation: its text found under it, its part of the
/// selection painted over it.
class ChatSelectionItem extends SingleChildRenderObjectWidget {
  const ChatSelectionItem({
    super.key,
    required this.index,
    required this.controller,
    required this.color,
    super.child,
  });

  final int index;
  final ChatSelectionController controller;
  final Color color;

  @override
  RenderChatSelectionItem createRenderObject(BuildContext context) =>
      RenderChatSelectionItem(index, controller, color);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatSelectionItem renderObject,
  ) {
    renderObject
      ..index = index
      ..controller = controller
      ..color = color;
  }
}

class RenderChatSelectionItem extends RenderProxyBox {
  RenderChatSelectionItem(this._index, this._controller, this._color);

  int _index;
  int get index => _index;
  set index(int value) {
    if (value == _index) return;
    final from = _index;
    _index = value;
    if (attached) _controller._renumber(this, from);
    markNeedsPaint();
  }

  ChatSelectionController _controller;
  set controller(ChatSelectionController value) {
    if (identical(value, _controller)) return;
    if (attached) {
      _controller
        ..removeListener(markNeedsPaint)
        .._detach(this);
      value
        ..addListener(markNeedsPaint)
        .._attach(this);
    }
    _controller = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller
      ..addListener(markNeedsPaint)
      .._attach(this);
  }

  @override
  void detach() {
    _controller
      ..removeListener(markNeedsPaint)
      .._detach(this);
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _controller.didLayOut(this);
  }

  /// Its pieces of text, in reading order.
  List<ChatTextLeaf> leaves() => chatTextLeaves(this);

  @visibleForTesting
  ChatSelectionController get controller => _controller;

  /// The selected part of each of its pieces of text, in reading order
  /// (empty where none is).
  List<TextRange> _selectedRanges(List<ChatTextLeaf> leaves) {
    final selected = _controller.selectedIn(index);
    return [
      for (var i = 0; i < leaves.length; i++)
        switch (selected) {
          null => TextRange.empty,
          (:final from, :final to)
              when (from != null && i < from.leaf) ||
                  (to != null && i > to.leaf) =>
            TextRange.empty,
          (:final from, :final to) => TextRange(
            start: (from != null && i == from.leaf ? from.offset : 0).clamp(
              0,
              leaves[i].text.length,
            ),
            end:
                (to != null && i == to.leaf ? to.offset : leaves[i].text.length)
                    .clamp(0, leaves[i].text.length),
          ),
        },
    ];
  }

  /// Whether some of the text laid out in [box] (a paragraph) shows
  /// selected.
  @visibleForTesting
  bool showsSelected(RenderBox box) {
    final leaves = this.leaves();
    final ranges = _selectedRanges(leaves);
    for (var i = 0; i < leaves.length; i++) {
      if (identical(leaves[i].box, box) && ranges[i].end > ranges[i].start) {
        return true;
      }
    }
    return false;
  }

  /// Its text as it shows now.
  ChatItemText text() {
    final found = _findLeaves(this);
    final pieces = <({String text, String copied, String join})>[];
    Rect? previous;
    List<RenderChatTextRow> previousGroups = const [];
    for (final (:leaf, :groups) in found) {
      final sameLine = _joinOnLine(previousGroups, groups);
      previousGroups = groups;
      final box = _bounds(leaf);
      final onLine =
          previous != null &&
          box != null &&
          box.top < previous.bottom - 1 &&
          previous.top < box.bottom - 1;
      pieces.add((
        text: leaf.text,
        copied: leaf.copyOf(0, leaf.text.length),
        join: onLine ? sameLine : '\n',
      ));
      previous = box ?? previous;
    }
    return ChatItemText(pieces);
  }

  Rect? _bounds(ChatTextLeaf leaf) {
    final box = leaf.box;
    if (!box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(this),
      Offset.zero & box.size,
    );
  }

  /// What of [leaf] shows, in its own coordinates: clipped by what clips
  /// it on the way up to the item (a code block's scroll view).
  Rect _visibleIn(ChatTextLeaf leaf) {
    var rect = Offset.zero & leaf.box.size;
    RenderObject child = leaf.box;
    var parent = child.parent;
    while (parent != null && !identical(child, this)) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        final toLeaf = Matrix4.tryInvert(leaf.box.getTransformTo(parent));
        if (toLeaf != null) {
          rect = rect.intersect(MatrixUtils.transformRect(toLeaf, clip));
        }
      }
      child = parent;
      parent = child.parent;
    }
    return rect;
  }

  /// The place nearest [global] in this item's text.
  ChatTextPos positionAt(Offset global) {
    final leaves = this.leaves();
    if (leaves.isEmpty) return ChatTextPos(index, 0, 0);
    // The piece whose lines hold the point's height, nearest across; else
    // the nearest above or below.
    var best = 0;
    var bestScore = double.infinity;
    for (var i = 0; i < leaves.length; i++) {
      final leaf = leaves[i];
      if (!leaf.box.hasSize) continue;
      final visible = _visibleIn(leaf);
      if (visible.isEmpty) continue;
      final box = MatrixUtils.transformRect(
        leaf.box.getTransformTo(null),
        visible,
      );
      final dy = global.dy < box.top
          ? box.top - global.dy
          : global.dy > box.bottom
          ? global.dy - box.bottom
          : 0.0;
      final dx = global.dx < box.left
          ? box.left - global.dx
          : global.dx > box.right
          ? global.dx - box.right
          : 0.0;
      final score = dy * 10000 + dx;
      if (score < bestScore) {
        best = i;
        bestScore = score;
      }
    }
    final leaf = leaves[best];
    final visible = _visibleIn(leaf);
    var local = leaf.box.globalToLocal(global);
    if (!visible.isEmpty) {
      local = Offset(
        local.dx.clamp(visible.left, visible.right),
        local.dy.clamp(visible.top, math.max(visible.top, visible.bottom - 1)),
      );
    }
    return ChatTextPos(index, best, leaf.positionAt(local));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_controller.selectedIn(index) == null) return;
    final leaves = this.leaves();
    final ranges = _selectedRanges(leaves);
    final paint = Paint()..color = _color;
    final canvas = context.canvas;
    for (var i = 0; i < leaves.length; i++) {
      final range = ranges[i];
      final leaf = leaves[i];
      if (range.end <= range.start || !leaf.box.attached) continue;
      final rects = leaf.rectsFor(range.start, range.end);
      if (rects.isEmpty) continue;
      final visible = _visibleIn(leaf);
      final transform = leaf.box.getTransformTo(this);
      for (final rect in rects) {
        final shown = rect.intersect(visible);
        if (shown.isEmpty) continue;
        canvas.drawRect(
          MatrixUtils.transformRect(transform, shown).shift(offset),
          paint,
        );
      }
    }
  }
}
