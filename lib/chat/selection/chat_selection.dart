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

import '../../base/smooth_scroll.dart';

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

/// Whether a press that selects in a conversation is held now. What
/// follows the end of what is written in a part of it that scrolls on its
/// own (a command's output, a thought) stays where it is meanwhile: the
/// text under the pointer would go on up, and the selection's end with it.
/// Let go, it follows again if it did.
abstract final class ChatSelectionHold {
  static final ValueNotifier<bool> held = ValueNotifier(false);
}

/// A [SmoothScrollController] for a view that follows the end of what is
/// written into it, its offset counted from that end ([ScrollView.reverse]):
/// while a press that selects is held ([ChatSelectionHold]), what comes in
/// at the end does not move what shows; let go, back at the end if it was.
class HeldTailScrollController extends SmoothScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _HeldTailPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class _HeldTailPosition extends ScrollPositionWithSingleContext
    with WheelGliding {
  _HeldTailPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  }) {
    ChatSelectionHold.held.addListener(_heldChanged);
  }

  double? _max;

  /// At the end when the press was held: back there once let go.
  bool _atEndWhenHeld = false;

  void _heldChanged() {
    if (!hasPixels || !hasContentDimensions) return;
    if (ChatSelectionHold.held.value) {
      _atEndWhenHeld = pixels <= minScrollExtent + 0.5;
    } else if (_atEndWhenHeld) {
      _atEndWhenHeld = false;
      if (pixels != minScrollExtent) jumpTo(minScrollExtent);
    }
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final was = _max;
    _max = maxScrollExtent;
    final accepted = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    // Counted from the end, what came in there would push what shows on:
    // as much further from it, it stays.
    if (ChatSelectionHold.held.value &&
        was != null &&
        hasPixels &&
        axisDirectionIsReversed(axisDirection) &&
        (maxScrollExtent - was).abs() >= 0.5) {
      correctPixels(
        (pixels + maxScrollExtent - was).clamp(
          minScrollExtent,
          maxScrollExtent,
        ),
      );
      return false;
    }
    return accepted;
  }

  @override
  void dispose() {
    ChatSelectionHold.held.removeListener(_heldChanged);
    super.dispose();
  }
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

  /// Each piece's text, its copy, how it joins the one before, and what
  /// each placeholder character in its text copies as (a chip's label, a
  /// formula's TeX), in order.
  final List<
    ({String text, String copied, String join, List<String> placeholders})
  >
  pieces;

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
          : _slice(piece.text, piece.placeholders, from, to);
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

  // A part of a piece: its text's, each placeholder in it as it copies.
  static String _slice(
    String text,
    List<String> placeholders,
    int from,
    int to,
  ) {
    from = from.clamp(0, text.length);
    to = to.clamp(from, text.length);
    final part = text.substring(from, to);
    if (!part.contains('￼')) return part;
    var next = '￼'.allMatches(text.substring(0, from)).length;
    final buffer = StringBuffer();
    for (final unit in part.split('')) {
      if (unit == '￼') {
        if (next < placeholders.length) buffer.write(placeholders[next]);
        next++;
      } else {
        buffer.write(unit);
      }
    }
    return buffer.toString();
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

  /// The pieces of the items that hold an end, as when the ends were put
  /// there: to find the ends again once pieces come or go before them (a
  /// long reply's segment built again, coming back into view; the item
  /// built anew), the ends counting pieces.
  final Map<int, List<({RenderBox box, String text})>> _endLeaves = {};

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
    _syncItem(item.index);
    _endText[item.index] = item.text();
  }

  /// The ends in item [index] (if built) moved to the same text in its
  /// pieces now.
  void _syncItem(int index) {
    if (_items[index] case final item? when item.attached) {
      _syncWith(item, item.leaves());
    }
  }

  void _syncEnds() {
    if (_anchor case final anchor?) _syncItem(anchor.item);
    if (_focus case final focus? when focus.item != _anchor?.item) {
      _syncItem(focus.item);
    }
  }

  /// [item]'s pieces are [leaves] now: the ends in it moved to the same
  /// text, if pieces came or went before them.
  void _syncWith(RenderChatSelectionItem item, List<ChatTextLeaf> leaves) {
    final index = item.index;
    final old = _endLeaves[index];
    if (old == null) return;
    var same = old.length == leaves.length;
    for (var i = 0; same && i < leaves.length; i++) {
      same = identical(old[i].box, leaves[i].box);
    }
    if (same) return;
    ChatTextPos? moved(ChatTextPos? pos) {
      if (pos == null || pos.item != index) return pos;
      return _placeAgain(pos, old, leaves);
    }

    _anchor = moved(_anchor);
    _focus = moved(_focus);
    if (_unit case (final start, final end)) {
      _unit = (moved(start)!, moved(end)!);
    }
    _endLeaves[index] = [
      for (final leaf in leaves) (box: leaf.box, text: leaf.text),
    ];
  }

  @visibleForTesting
  static ChatTextPos placeAgain(
    ChatTextPos pos,
    List<({RenderBox box, String text})> old,
    List<ChatTextLeaf> leaves,
  ) => _placeAgain(pos, old, leaves);

  /// Where [pos], a place among the pieces [old], is among [leaves].
  static ChatTextPos _placeAgain(
    ChatTextPos pos,
    List<({RenderBox box, String text})> old,
    List<ChatTextLeaf> leaves,
  ) {
    if (pos.leaf >= old.length || leaves.isEmpty) return pos;
    final was = old[pos.leaf];
    ChatTextPos at(int leaf, int offset) => ChatTextPos(pos.item, leaf, offset);
    // The same piece, elsewhere in the order.
    for (var i = 0; i < leaves.length; i++) {
      if (identical(leaves[i].box, was.box)) return at(i, pos.offset);
    }
    // A piece let go of (a segment's box, its text whole) laid out again,
    // in pieces: its start or its end.
    final inside = [
      for (var i = 0; i < leaves.length; i++)
        if (_isUnder(leaves[i].box, was.box)) i,
    ];
    if (inside.isNotEmpty) {
      return pos.offset == 0
          ? at(inside.first, 0)
          : at(inside.last, leaves[inside.last].text.length);
    }
    // Built anew: the piece with the same text, as many such before it.
    if (was.text != '￼') {
      var nth = 0;
      for (var i = 0; i < pos.leaf; i++) {
        if (old[i].text == was.text) nth++;
      }
      for (var i = 0; i < leaves.length; i++) {
        if (leaves[i].text == was.text && nth-- == 0) {
          return at(i, pos.offset.clamp(0, leaves[i].text.length));
        }
      }
    }
    bool wasThere(RenderBox box) => old.any((o) => identical(o.box, box));
    // Else as far on from the nearest piece before it still there: built
    // anew there (a header's text changed), the same place in it; nothing
    // new there, it went (a header's second line), and the place is where
    // it was, between the pieces still there, not inside one of them.
    for (var k = pos.leaf - 1; k >= 0; k--) {
      for (var i = 0; i < leaves.length; i++) {
        if (identical(leaves[i].box, old[k].box)) {
          final j = i + pos.leaf - k;
          if (j < leaves.length && !wasThere(leaves[j].box)) {
            return at(j, pos.offset.clamp(0, leaves[j].text.length));
          }
          return at(i, leaves[i].text.length);
        }
      }
    }
    // None before it there: the start of the first after it still there.
    for (var k = pos.leaf + 1; k < old.length; k++) {
      for (var i = 0; i < leaves.length; i++) {
        if (identical(leaves[i].box, old[k].box)) {
          if (i > 0 && !wasThere(leaves[i - 1].box)) {
            return at(i - 1, pos.offset.clamp(0, leaves[i - 1].text.length));
          }
          return at(i, 0);
        }
      }
    }
    // None of its pieces left: the same place, as far as it goes.
    final leaf = math.min(pos.leaf, leaves.length - 1);
    return at(leaf, pos.offset.clamp(0, leaves[leaf].text.length));
  }

  static bool _isUnder(RenderObject object, RenderObject ancestor) {
    for (RenderObject? node = object.parent; node != null; node = node.parent) {
      if (identical(node, ancestor)) return true;
    }
    return false;
  }

  /// The pieces of the items holding an end now, as the ends are put
  /// there.
  void _rememberLeaves() {
    final anchor = _anchor;
    final focus = _focus;
    for (final pos in [anchor, focus]) {
      if (pos == null) continue;
      if (_items[pos.item] case final item? when item.attached) {
        _endLeaves[pos.item] = [
          for (final leaf in item.leaves()) (box: leaf.box, text: leaf.text),
        ];
      }
    }
    _endLeaves.removeWhere(
      (index, _) => index != anchor?.item && index != focus?.item,
    );
  }

  // --- Changes --------------------------------------------------------------

  void clear() {
    if (_anchor == null && _focus == null && !_all) return;
    _anchor = _focus = null;
    _unit = null;
    _all = false;
    _endText.clear();
    _endLeaves.clear();
    notifyListeners();
  }

  /// A press at [pos]: nothing selected, the selection to start there.
  void start(ChatTextPos pos) {
    _all = false;
    _unit = null;
    _granularity = TextGranularity.character;
    _anchor = _focus = pos;
    _endText.clear();
    _endLeaves.clear();
    _rememberLeaves();
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
    _endLeaves.clear();
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
    // [pos] is a place among the pieces now: the ends too.
    _syncEnds();
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
    _syncEnds();
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
    _endLeaves.clear();
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
    final leaves = {
      for (final MapEntry(:key, :value) in _endLeaves.entries)
        key + count: value,
    };
    _endLeaves
      ..clear()
      ..addAll(leaves);
  }

  /// The item at index [from] now at [to], the others where they were (a
  /// turn's status row, the last, as what the turn does comes in before
  /// it): what is selected in it stays with it.
  void moveItem(int from, int to) {
    if (from == to) return;
    ChatTextPos? moved(ChatTextPos? pos) => pos == null || pos.item != from
        ? pos
        : ChatTextPos(to, pos.leaf, pos.offset);
    _anchor = moved(_anchor);
    _focus = moved(_focus);
    if (_unit case (final start, final end)) {
      _unit = (moved(start)!, moved(end)!);
    }
    if (_endText.remove(from) case final text?) _endText[to] = text;
    if (_endLeaves.remove(from) case final leaves?) _endLeaves[to] = leaves;
  }

  void _rememberEnds() {
    _rememberLeaves();
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
          _syncItem(item.index);
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
    _syncEnds();
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

  /// The place in the text nearest [global], among the items built (of
  /// what of them is in [shown], globally, if given: the list's view, not
  /// rows laid out beyond it, hidden); null when none is.
  ChatTextPos? positionAt(Offset global, {Rect? shown}) {
    // The nearest item with text in view: one only partly in it may show
    // none of its text (a gap of its, its text all beyond).
    final tried = <RenderChatSelectionItem>{};
    while (true) {
      final item = _itemNear(global, shown, tried);
      if (item == null) return null;
      if (item.positionAt(global, shown: shown) case final pos?) return pos;
      tried.add(item);
    }
  }

  RenderChatSelectionItem? _itemNear(
    Offset global,
    Rect? shown,
    Set<RenderChatSelectionItem> tried,
  ) {
    RenderChatSelectionItem? best;
    var bestDistance = double.infinity;
    for (final item in _items.values) {
      if (!item.attached || !item.hasSize || tried.contains(item)) continue;
      final showing = item._showing();
      if (showing.isEmpty) continue;
      var top = showing.top;
      var bottom = showing.bottom;
      if (shown != null) {
        top = math.max(top, shown.top);
        bottom = math.min(bottom, shown.bottom);
        if (bottom <= top) continue;
      }
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

  /// [range] trimmed to the text in it, as far as it is built: a start
  /// with only blanks after it in its piece (the line break after a
  /// message, a drag begun beside it) moved on to the next piece, an end
  /// with only blanks before it back to the one before. Null when nothing
  /// but blanks is selected.
  (ChatTextPos, ChatTextPos)? textRange() {
    final range = this.range;
    if (range == null) return null;
    var (start, end) = range;
    List<ChatTextLeaf>? leavesOf(int index) => switch (_items[index]) {
      final item? when item.attached => item.leaves(),
      _ => null,
    };
    bool blank(String text, int from, int to) {
      for (var i = from; i < to; i++) {
        if (text.codeUnitAt(i) > 0x20) return false;
      }
      return true;
    }

    var leaves = leavesOf(start.item);
    while (start < end && leaves != null) {
      if (start.leaf < leaves.length) {
        final text = leaves[start.leaf].text;
        final from = start.offset.clamp(0, text.length);
        if (!blank(text, from, text.length)) break;
        start = ChatTextPos(start.item, start.leaf + 1, 0);
      } else {
        start = ChatTextPos(start.item + 1, 0, 0);
        leaves = leavesOf(start.item);
      }
    }
    leaves = leavesOf(end.item);
    while (start < end && leaves != null) {
      final leaf = math.min(end.leaf, leaves.length - 1);
      if (leaf >= 0) {
        final text = leaves[leaf].text;
        final to = end.offset.clamp(0, text.length);
        if (!blank(text, 0, to)) break;
      }
      if (leaf > 0) {
        end = ChatTextPos(end.item, leaf - 1, leaves[leaf - 1].text.length);
      } else if (end.item > 0) {
        leaves = leavesOf(end.item - 1);
        end = ChatTextPos(
          end.item - 1,
          math.max(0, (leaves?.length ?? 1) - 1),
          leaves?.lastOrNull?.text.length ?? 0,
        );
      } else {
        break;
      }
    }
    return start < end ? (start, end) : null;
  }

  /// The character [pos] is at the end of ([after]: at the start of), and
  /// the piece of text it is in ([leaf]), in the box of its item (see
  /// [builtItems]): where a selection's end is, if built. A line's height,
  /// for a piece of no text.
  ({Rect char, Rect leaf})? charRectAt(ChatTextPos pos, {bool after = false}) {
    final item = _items[pos.item];
    if (item == null || !item.attached) return null;
    final leaves = item.leaves();
    if (leaves.isEmpty) return null;
    final leaf = leaves[math.min(pos.leaf, leaves.length - 1)];
    final length = leaf.text.length;
    final offset = pos.offset.clamp(0, length);
    final start = math.max(
      0,
      math.min(after ? offset : offset - 1, length - 1),
    );
    final rects = leaf.rectsFor(start, math.min(length, start + 1));
    final box = Offset.zero & leaf.box.size;
    final toItem = leaf.box.getTransformTo(item);
    return (
      char: MatrixUtils.transformRect(toItem, rects.firstOrNull ?? box),
      leaf: MatrixUtils.transformRect(toItem, box),
    );
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
    _controller._syncWith(this, leaves);
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
    final pieces =
        <
          ({String text, String copied, String join, List<String> placeholders})
        >[];
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
        placeholders: [
          for (var i = 0; i < leaf.text.length; i++)
            if (leaf.text.codeUnitAt(i) == 0xFFFC) leaf.copyOf(i, i + 1),
        ],
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

  /// What of this item shows, globally: clipped by what clips it on the
  /// way up (its row folding away, its height moving and what is past it
  /// cut off; the list's edges). What does not show is not selected in,
  /// as in a browser: a press there is on what shows there.
  Rect _showing() {
    var rect = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    RenderObject child = this;
    var parent = child.parent;
    while (parent != null) {
      final clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        rect = rect.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
        if (rect.isEmpty) return Rect.zero;
      }
      child = parent;
      parent = child.parent;
    }
    return rect;
  }

  /// What of [leaf] shows, in its own coordinates: clipped by what clips
  /// it on the way up to the item (a code block's scroll view), and what
  /// clips the item ([_showing]).
  Rect _visibleIn(ChatTextLeaf leaf, [Rect? shown]) {
    var rect = Offset.zero & leaf.box.size;
    var limit = _showing();
    if (shown != null) limit = limit.intersect(shown);
    if (limit.isEmpty) return Rect.zero;
    final toLeaf = Matrix4.tryInvert(leaf.box.getTransformTo(null));
    if (toLeaf != null) {
      rect = rect.intersect(MatrixUtils.transformRect(toLeaf, limit));
      if (rect.isEmpty) return Rect.zero;
    }
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

  /// The place nearest [global] in this item's text (in what of it is in
  /// [shown], globally, if given: null if none of its text is).
  ChatTextPos? positionAt(Offset global, {Rect? shown}) {
    final leaves = this.leaves();
    if (leaves.isEmpty) return ChatTextPos(index, 0, 0);
    // The piece whose lines hold the point's height, nearest across; else
    // the nearest above or below.
    var best = -1;
    var bestScore = double.infinity;
    for (var i = 0; i < leaves.length; i++) {
      final leaf = leaves[i];
      if (!leaf.box.hasSize) continue;
      final visible = _visibleIn(leaf, shown);
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
    if (best < 0) {
      if (shown != null) return null;
      best = 0;
    }
    final leaf = leaves[best];
    final visible = _visibleIn(leaf, shown);
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
    _controller._syncWith(this, leaves);
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
