import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_column.dart';
import '../chat_models.dart';
import '../composer/composer_files.dart' show splitCodeAppendix;
import '../user_message_style.dart';
import 'user_message_bubble.dart' show UserMessageBubble, UserMessagePreview;

/// Row [ChatMinimapRow.item] of a history as its minimap samples it: whether
/// the item shows (a closed fold hides it), how many fold lines the row
/// begins with, and the gap above it.
typedef ChatMinimapRow = ({
  ChatItem item,
  bool shown,
  int foldLines,
  double gap,
});

/// The part of a history in view: the first and last rows in it, and how
/// far down each the view's edge is (0 at the row's top, 1 at its bottom).
typedef ChatMinimapSpan = ({
  int first,
  double firstAt,
  int last,
  double lastAt,
});

/// How much a minimap's glass stretches as it moves: its edge ahead keeps
/// up with the view quicker than the one behind ([leading] and [trailing],
/// each a spring's stiffness); it gathers itself where it stops.
enum ChatMinimapElasticity {
  /// Not at all: its edges go together.
  off(44, 44),
  subtle(46, 36),
  medium(44, 28),

  /// As it did first.
  bouncy(42, 22);

  const ChatMinimapElasticity(this.leading, this.trailing);

  final double leading;
  final double trailing;

  /// As settings.json has it: its name.
  String get setting => name;
}

/// A conversation's minimap, as an editor's: every row of the history
/// sampled down to strokes (its lines of text, the user's messages, code,
/// steps), the part in view under a drop of liquid glass that follows it
/// (shown while the history is scrolled, or the pointer is over it), and a
/// press or a drag on it scrolls there. In the margin left of the column
/// when there is room for it (not in a narrow pane), and once the
/// conversation is long ([longAfter]).
///
/// Light to keep: an item is sampled once, and again only when it changes
/// (a changed item is a new one); only the strokes in sight are painted, and
/// where the view is is read as they are ([span]), once the list is laid out.
class ChatMinimap extends StatefulWidget {
  const ChatMinimap({
    super.key,
    required this.rowCount,
    required this.rowAt,
    required this.span,
    required this.moved,
    required this.columnIn,
    required this.long,
    required this.scrolling,
    required this.onSeek,
    required this.onSeekEnd,
    this.onPointerDown,
    this.onPointerSignal,
    this.onPointerPanZoomStart,
    this.onPointerPanZoomUpdate,
    this.onPointerPanZoomEnd,
  });

  final int rowCount;
  final ChatMinimapRow Function(int index) rowAt;

  /// The part in view, as laid out; null when there is none.
  final ChatMinimapSpan? Function() span;

  /// Notifies when the view may have moved: a scroll, a new layout.
  final Listenable moved;

  /// The column's left and width in the history, [width] wide.
  final ({double left, double width}) Function(double width) columnIn;

  /// Whether the conversation is long ([longAfter]): shown only then.
  final bool long;

  /// Whether the user is scrolling the history: the glass shows meanwhile.
  final bool Function() scrolling;

  /// Scrolls row [index] to the top of the view, [fraction] of the way
  /// down it.
  final void Function(int index, double fraction) onSeek;

  /// Scrolls to the end, to stay there.
  final VoidCallback onSeekEnd;

  /// The history's own, for a press, the wheel or a trackpad over it: it is
  /// not over the list.
  final PointerDownEventListener? onPointerDown;
  final PointerSignalEventListener? onPointerSignal;
  final PointerPanZoomStartEventListener? onPointerPanZoomStart;
  final PointerPanZoomUpdateEventListener? onPointerPanZoomUpdate;
  final PointerPanZoomEndEventListener? onPointerPanZoomEnd;

  /// Its track's width, however roomy the margin; the glass reaches [_outset]
  /// past it either side.
  static const _narrow = 24.0;
  static const _outset = 3.0;

  /// The least kept between it and the history's left edge, and between it
  /// and the column (more, for the text to breathe beside it); the most
  /// between it and the column, however roomy the margin.
  static const _edgeGap = 12.0;
  static const _columnGap = 20.0;
  static const _maxColumnGap = 32.0;

  /// The margin it takes left of a conversation's column, from the
  /// conversation's edge: a column with a minimap leaves it clear while it
  /// can (see [ChatColumn.room]); at the right it reaches the margin.
  static const room = _edgeGap + _narrow + _columnGap;

  /// The least a column keeps of its width to leave [room]; narrower than
  /// that (a very narrow pane or window only), it gives the room up, and
  /// the minimap is not shown.
  static const roomFrom = 320.0;

  /// How much more than it shows a conversation has before it has one,
  /// in heights of the history: a short one has nothing to find its way
  /// around in, and its steps folded or not would bring it and take it
  /// away (see ChatHistoryView).
  static const longAfter = 1.5;

  /// How tall [item] samples in a column [width] wide, for tests.
  @visibleForTesting
  static double sampledHeight(ChatItem item, {double width = 720}) => _Sampler(
    width,
    bubbles: true,
  ).sample((item: item, shown: true, foldLines: 0, gap: 0)).height;

  /// Kept above and below it.
  static const _inset = 14.0;

  /// Where its track is beside [column] (the history's): its left and
  /// width; null where the margin has no room for it.
  static ({double left, double width})? besides(
    ({double left, double width}) column,
  ) {
    if (column.width <= 0) return null;
    final spare = column.left - _narrow;
    if (spare < _edgeGap + _columnGap) return null;
    // Half way, within bounds: never nearer the edge than [_edgeGap].
    final gap = math.min(
      (spare / 2).clamp(_columnGap, _maxColumnGap),
      spare - _edgeGap,
    );
    return (left: column.left - gap - _narrow, width: _narrow);
  }

  /// settings.json's `chat.minimap`: whether a conversation in the agents'
  /// window has one, as Settings → Appearance turns it on or off. Unset: on.
  /// Off, the history has its scrollbar, and its column the width it had.
  static const settingKey = 'chat.minimap';

  /// Whether the chats have one now; main() keeps it to settings.json
  /// ([follow]).
  static final ValueNotifier<bool> enabled = ValueNotifier(true);

  /// [value] as settings.json has it.
  static bool parse(Object? value) => value != false;

  /// [on] as settings.json keeps it; null (not written) for on.
  static Object? setting(bool on) => on ? null : false;

  /// settings.json's `chat.minimapGlass`: how opaque the glass is (its
  /// body, shadow and light; not the strokes under it, nor how they swell),
  /// as Settings → Appearance sets it, one of [glassSteps]. Unset:
  /// [defaultGlass].
  static const glassKey = 'chat.minimapGlass';

  /// From clear glass to half as much again as it is drawn; by default, a
  /// little clearer than that.
  static const glassSteps = [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5];
  static const defaultGlass = 0.75;

  static final ValueNotifier<double> glass = ValueNotifier(defaultGlass);

  /// [value] as settings.json has it: the step nearest it; [defaultGlass]
  /// when it is not a number.
  static double parseGlass(Object? value) {
    if (value is! num) return defaultGlass;
    var nearest = glassSteps.first;
    for (final step in glassSteps) {
      if ((step - value).abs() < (nearest - value).abs()) nearest = step;
    }
    return nearest;
  }

  /// [opacity] as settings.json keeps it; null (not written) for
  /// [defaultGlass].
  static Object? glassSetting(double opacity) =>
      opacity == defaultGlass ? null : opacity;

  /// settings.json's `chat.minimapElasticity`: how much the glass
  /// stretches as it moves, as Settings → Appearance sets it. Unset:
  /// [defaultElasticity].
  static const elasticityKey = 'chat.minimapElasticity';
  static const defaultElasticity = ChatMinimapElasticity.subtle;

  static final ValueNotifier<ChatMinimapElasticity> elasticity = ValueNotifier(
    defaultElasticity,
  );

  /// [value] as settings.json has it; [defaultElasticity] when it is none.
  static ChatMinimapElasticity parseElasticity(Object? value) =>
      ChatMinimapElasticity.values
          .where((level) => level.setting == value)
          .firstOrNull ??
      defaultElasticity;

  /// [level] as settings.json keeps it; null (not written) for
  /// [defaultElasticity].
  static Object? elasticitySetting(ChatMinimapElasticity level) =>
      level == defaultElasticity ? null : level.setting;

  /// Sets [enabled], [glass] and [elasticity] from [read] now and whenever
  /// [changes] notifies.
  static void follow(Listenable changes, Object? Function(String key) read) {
    void update() {
      enabled.value = parse(read(settingKey));
      glass.value = parseGlass(read(glassKey));
      elasticity.value = parseElasticity(read(elasticityKey));
    }

    update();
    changes.addListener(update);
  }

  @override
  State<ChatMinimap> createState() => _ChatMinimapState();
}

class _ChatMinimapState extends State<ChatMinimap>
    with TickerProviderStateMixin {
  // --- Samples ---------------------------------------------------------------

  /// Each item's, as last sampled: a changed item is a new one.
  Map<ChatItem, _Sample> _samples = Map.identity();
  List<_Sample> _rows = const [];

  /// Where each row starts, in the strokes' own coordinates; the last, where
  /// they end.
  Float64List _tops = Float64List(1);
  double get _extent => _tops.last;

  /// The rows that are the user's messages, in order, and where each one's
  /// mark is in the strokes.
  List<int> _users = const [];
  List<double> _usersAt = const [];

  /// What they were sampled for: the column's width (in steps of 16, not
  /// sampled anew at each width a pane is dragged through) and the user's
  /// messages' style.
  double _columnWidth = 0;
  UserMessageStyle? _style;
  bool _stale = true;

  void _sync(double columnWidth) {
    final width = math.max(160.0, (columnWidth / 16).round() * 16.0);
    final style = UserMessageStyle.current.value;
    if (width != _columnWidth || style != _style) {
      _samples = Map.identity();
      _columnWidth = width;
      _style = style;
      _stale = true;
    }
    if (!_stale) return;
    _stale = false;
    final sampler = _Sampler(width, bubbles: style == UserMessageStyle.bubble);
    final count = widget.rowCount;
    final samples = Map<ChatItem, _Sample>.identity();
    final rows = <_Sample>[];
    final tops = Float64List(count + 1);
    final users = <int>[];
    final usersAt = <double>[];
    var y = 0.0;
    for (var index = 0; index < count; index++) {
      final row = widget.rowAt(index);
      var sample = samples[row.item] ?? _samples[row.item];
      if (sample == null || !sample.fits(row)) sample = sampler.sample(row);
      samples[row.item] = sample;
      rows.add(sample);
      tops[index] = y;
      if (sample.user case final at?) {
        users.add(index);
        usersAt.add(y + at);
      }
      y += sample.height;
    }
    tops[count] = y;
    _users = users;
    _usersAt = usersAt;
    // The tiles above the first row that changed (or moved) still hold.
    var same = 0;
    final common = math.min(count, _rows.length);
    while (same < common &&
        identical(rows[same], _rows[same]) &&
        tops[same] == _tops[same]) {
      same++;
    }
    if (same < common || count != _rows.length) _dropTilesFrom(tops[same]);
    _samples = samples;
    _rows = rows;
    _tops = tops;
  }

  /// The row at [y], one that shows something if any does there.
  int _rowAt(double y) {
    var low = 0;
    var high = _rows.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_tops[middle] <= y) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    while (low > 0 && _tops[low + 1] <= _tops[low]) {
      low--;
    }
    return low;
  }

  // --- The glass -------------------------------------------------------------
  //
  // Its top and bottom, in the strokes' coordinates, each follow where the
  // view's are as a spring (critically damped: no overshoot), the edge ahead
  // the quicker, as much as [ChatMinimap.elasticity] says: it stretches as it
  // goes, and gathers itself where it stops.

  double _top = double.nan;
  double _bottom = double.nan;
  double _topSpeed = 0;
  double _bottomSpeed = 0;
  double _aimTop = double.nan;
  double _aimBottom = double.nan;

  /// The glass is never shorter: a long conversation's view is a sliver.
  static const _minGlass = 10.0;

  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  final _Repaint _repaint = _Repaint();

  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  /// Motion turned down: the glass goes straight where the view is.
  bool _still = false;

  /// Where on the glass a press holds it, while it does; and whether it has
  /// been dragged (the glass then keeps to the pointer, not springs).
  double? _grab;
  bool _dragged = false;

  double _viewHeight = 0;

  /// Its width, as last placed.
  double _width = ChatMinimap._narrow;

  // --- Showing the glass -----------------------------------------------------
  //
  // Out of sight at rest: it comes as the user scrolls, or points at the
  // minimap, and goes a moment after.

  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 450),
  );
  Timer? _conceal;
  bool _hovered = false;
  bool _revealScheduled = false;

  /// Since the glass was last told to show.
  final Stopwatch _sinceShown = Stopwatch();

  /// Whether it was told to show just now, and does: told every frame of a
  /// scroll, once in a while does.
  bool get _showing =>
      (_reveal.status == AnimationStatus.forward ||
          _reveal.status == AnimationStatus.completed) &&
      _sinceShown.isRunning &&
      _sinceShown.elapsedMilliseconds < 120;

  void _show() {
    if (_showing) return;
    _sinceShown
      ..reset()
      ..start();
    _reveal.forward();
    _conceal?.cancel();
    _conceal = Timer(const Duration(milliseconds: 900), () {
      if (!_hovered && _grab == null) _reveal.reverse();
    });
  }

  /// [_show] after this frame: it is seen to while painting.
  void _showSoon() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (mounted) _show();
    });
  }

  void _setHovered(bool value) {
    _hovered = value;
    _hover.animateTo(value ? 1 : 0);
    _show();
  }

  void _aim(ChatMinimapSpan span) {
    final count = _rows.length;
    if (count == 0) return;
    double at(int index, double fraction) {
      final row = index.clamp(0, count - 1);
      return _tops[row] +
          fraction.clamp(0.0, 1.0) * (_tops[row + 1] - _tops[row]);
    }

    final top = at(span.first, span.firstAt);
    final bottom = math.max(top, at(span.last, span.lastAt));
    if (top == _aimTop && bottom == _aimBottom) return;
    if (!_aimTop.isNaN && !_showing && widget.scrolling()) _showSoon();
    _aimTop = top;
    _aimBottom = bottom;
    if (_top.isNaN || _dragged || _still) {
      _settle();
    } else if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _settle() {
    _ticker.stop();
    _top = _aimTop;
    _bottom = _aimBottom;
    _topSpeed = 0;
    _bottomSpeed = 0;
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    final down = _aimTop + _aimBottom > _top + _bottom;
    final ChatMinimapElasticity(:leading, :trailing) =
        ChatMinimap.elasticity.value;
    final top = _spring(
      _top,
      _topSpeed,
      _aimTop,
      down ? trailing : leading,
      dt,
    );
    final bottom = _spring(
      _bottom,
      _bottomSpeed,
      _aimBottom,
      down ? leading : trailing,
      dt,
    );
    _top = top.$1;
    _topSpeed = top.$2;
    _bottom = bottom.$1;
    _bottomSpeed = bottom.$2;
    if ((_top - _aimTop).abs() < 0.05 &&
        (_bottom - _aimBottom).abs() < 0.05 &&
        _topSpeed.abs() < 1 &&
        _bottomSpeed.abs() < 1) {
      _settle();
    }
    _repaint.ping();
  }

  /// [x] moving at [speed] toward [aim], [dt] seconds on.
  static (double, double) _spring(
    double x,
    double speed,
    double aim,
    double omega,
    double dt,
  ) {
    final away = x - aim;
    final decay = math.exp(-omega * dt);
    final pull = speed + omega * away;
    return (
      aim + (away + pull * dt) * decay,
      (speed - omega * pull * dt) * decay,
    );
  }

  /// The glass as drawn in a minimap [height] tall: its top and height, and
  /// how far the strokes under it are scrolled. Taller than the minimap,
  /// they scroll with it, as much of them above it as below it.
  ({double top, double height, double offset}) _glass(double height) {
    final extent = _extent;
    final glass = math.max(_bottom - _top, _minGlass);
    final top = _top.clamp(0.0, math.max(0.0, extent - glass));
    final offset = extent <= height || extent <= glass
        ? 0.0
        : (top * (extent - height) / (extent - glass)).clamp(
            0.0,
            extent - height,
          );
    return (top: top - offset, height: glass, offset: offset);
  }

  /// Where the glass's top is in the strokes, drawn at [drawn] in a
  /// minimap [height] tall (the other way from [_glass]).
  double _topAt(double drawn, double height) {
    final extent = _extent;
    final glass = math.max(_bottom - _top, _minGlass);
    final scale = extent <= height
        ? 1.0
        : (extent - glass) / math.max(1.0, height - glass);
    return (drawn * scale).clamp(0.0, math.max(0.0, extent - glass));
  }

  /// Scrolls the history to have its view's top at [top] in the strokes.
  void _seek(double top) {
    if (_rows.isEmpty) return;
    final glass = math.max(_bottom - _top, _minGlass);
    if (top >= _extent - glass - 0.5) {
      widget.onSeekEnd();
      return;
    }
    final index = _rowAt(top);
    final height = _tops[index + 1] - _tops[index];
    widget.onSeek(
      index,
      height <= 0 ? 0 : ((top - _tops[index]) / height).clamp(0.0, 1.0),
    );
  }

  void _handleDown(PointerDownEvent event) {
    widget.onPointerDown?.call(event);
    if (event.buttons != kPrimaryButton || _top.isNaN || _rows.isEmpty) return;
    _show();
    final y = event.localPosition.dy;
    if (_lit case final row?) {
      // On a message's mark: to it, at the view's top; dragged on, as the
      // glass is.
      _pressedAt = y;
      _snap();
      widget.onSeek(row, 0);
      return;
    }
    final glass = _glass(_viewHeight);
    if (y >= glass.top && y <= glass.top + glass.height) {
      _grab = y - glass.top;
    } else {
      // Brought there, the glass's middle under the pointer; dragged on from
      // there.
      _grab = glass.height / 2;
      _seek(_topAt(y - _grab!, _viewHeight));
    }
    _repaint.ping();
  }

  void _handleMove(PointerMoveEvent event) {
    if (_pressedAt case final from?) {
      if ((event.localPosition.dy - from).abs() < 4) return;
      _pressedAt = null;
      _grab = _glass(_viewHeight).height / 2;
    }
    final grab = _grab;
    if (grab == null) return;
    _dragged = true;
    _seek(_topAt(event.localPosition.dy - grab, _viewHeight));
  }

  void _handleUp(PointerEvent event) {
    if (_pressedAt != null) {
      _pressedAt = null;
      _snap();
      return;
    }
    if (_grab == null) return;
    _grab = null;
    _dragged = false;
    _show();
    _repaint.ping();
    _snap();
  }

  // --- The user's messages ---------------------------------------------------
  //
  // What a user looks for in a conversation is mostly what they asked: each
  // of their messages is one mark over the strokes, never dimmed. The
  // pointer over the minimap is drawn to the nearest within [_snapReach]: it
  // lights up, a press goes to it, and beside the minimap a peek shows it
  // and the start of what answered it, at once.

  static const _snapReach = 26.0;

  /// How far past the glass, either side, the pointer is still over the
  /// minimap (to its left as far as the margin goes).
  static const _reachOut = 12.0;
  static const _reachIn = 10.0;

  /// The marks as last painted: each one's row, and where it is down the
  /// minimap.
  final List<int> _drawnRows = [];
  final List<double> _drawnAt = [];

  /// Where the pointer is down the minimap, while it is over it.
  double? _pointerAt;

  /// The mark the pointer is drawn to (its row), and the one it left: the
  /// one lights up as the other goes out.
  int? _lit;
  int? _unlit;
  late final AnimationController _lighting = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  /// What the peek shows: the message's row, and how far down the
  /// minimap's box its mark is.
  final ValueNotifier<({int row, double at})?> _peek = ValueNotifier(null);

  /// Where a press on a mark was, until it is let go or dragged on.
  double? _pressedAt;

  bool _snapScheduled = false;

  void _pointAt(double? y) {
    _pointerAt = y;
    _snap();
  }

  /// Lights the mark nearest the pointer, if one is near it, and peeks at
  /// it; none while the glass is held.
  void _snap() {
    final pointer = _pointerAt;
    int? row;
    var at = 0.0;
    if (pointer != null && _grab == null && _pressedAt == null) {
      var nearest = _snapReach;
      for (var i = 0; i < _drawnRows.length; i++) {
        final distance = (_drawnAt[i] - pointer).abs();
        if (distance < nearest) {
          nearest = distance;
          row = _drawnRows[i];
          at = _drawnAt[i];
        }
      }
    }
    if (row != _lit) {
      _unlit = _lit;
      _lit = row;
      _lighting.forward(from: 0);
    }
    _peek.value = row == null ? null : (row: row, at: at + ChatMinimap._inset);
  }

  /// [_snap] after this frame: the marks have been painted where they are
  /// now, under a pointer that has not moved (a scroll, the glass going).
  void _snapSoon() {
    if (_snapScheduled) return;
    _snapScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _snapScheduled = false;
      if (mounted) _snap();
    });
  }

  /// What the peek shows about the message at [row]: the end of the
  /// agent's words before it, it, and the start of those after it; and how
  /// far down it the message's first line is.
  ({Widget card, double firstLine}) _peekAt(int row) {
    final item = widget.rowAt(row).item;
    if (item is! UserMessageItem) {
      return (card: const SizedBox.shrink(), firstLine: 0);
    }
    String? said(int from, int step) {
      for (var at = from, n = 0; at >= 0 && at < widget.rowCount; at += step) {
        if (n++ == 400) break;
        final other = widget.rowAt(at).item;
        if (other is UserMessageItem) break;
        if (other is AssistantTextItem) {
          final text = _excerpt(other.text, end: step < 0);
          if (text.isNotEmpty) return text;
        }
      }
      return null;
    }

    final before = said(row - 1, -1);
    return (
      card: _PeekCard(message: item, before: before, after: said(row + 1, 1)),
      firstLine: _PeekCard.firstLine(before: before != null),
    );
  }

  static final _spaces = RegExp(r'\s+');
  static final _fences = RegExp(r'^\s*(`{3,}|~{3,})', multiLine: true);

  /// The agent's [text], its markup dropped, its code and tables' rules
  /// left out: its first lines, or its last ([end]).
  static String _excerpt(String text, {bool end = false}) {
    const most = 8;
    // Of a long text, only as much as is wanted; in a code block or not
    // as the fences before the cut say.
    var code = false;
    if (end && text.length > 2400) {
      final cut = text.lastIndexOf('\n', text.length - 2400);
      if (cut > 0) {
        code = _fences.allMatches(text.substring(0, cut)).length.isOdd;
        text = text.substring(cut + 1);
      }
    }
    final lines = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (_Sampler._fence.hasMatch(line)) {
        code = !code;
        continue;
      }
      if (code ||
          line.isEmpty ||
          _Sampler._tableRule.hasMatch(line) ||
          _Sampler._rule.hasMatch(line)) {
        continue;
      }
      final plain = _Sampler._plain(
        line.replaceFirst(_Sampler._listOrHeading, ''),
      ).replaceAll('|', ' ').replaceAll(_spaces, ' ').trim();
      if (plain.isNotEmpty) lines.add(plain);
      if (!end && lines.length == most) break;
    }
    return (end && lines.length > most
            ? lines.sublist(lines.length - most)
            : lines)
        .join('\n');
  }

  @override
  void didUpdateWidget(ChatMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _stale = true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _conceal?.cancel();
    _dropTilesFrom(double.negativeInfinity);
    _reveal.dispose();
    _hover.dispose();
    _lighting.dispose();
    _peek.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _still = MediaQuery.disableAnimationsOf(context);
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final column = widget.columnIn(constraints.maxWidth);
        final place = ChatMinimap.besides(column);
        final fits = place != null;
        // Out of sight, nothing is sampled.
        if (place != null) {
          _sync(column.width);
          _width = place.width;
        }
        _viewHeight = math.max(
          0.0,
          constraints.maxHeight - 2 * ChatMinimap._inset,
        );
        final shown = fits && widget.long && widget.rowCount > 0;
        final left = math.max(0.0, place?.left ?? 0);
        final out = math.max(
          0.0,
          math.min(_reachOut, left - ChatMinimap._outset),
        );
        return Stack(
          children: [
            // Wide enough for the glass, which is wider than the track, and
            // a little more for the pointer.
            Positioned(
              left: left - ChatMinimap._outset - out,
              top: ChatMinimap._inset,
              bottom: ChatMinimap._inset,
              width: _width + 2 * ChatMinimap._outset + out + _reachIn,
              child: IgnorePointer(
                ignoring: !shown,
                child: AnimatedOpacity(
                  opacity: shown ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: ValueListenableBuilder(
                    valueListenable: _peek,
                    builder: (context, peek, child) => MouseRegion(
                      cursor: peek != null
                          ? SystemMouseCursors.click
                          : MouseCursor.defer,
                      onEnter: (event) {
                        _setHovered(true);
                        _pointAt(event.localPosition.dy);
                      },
                      onHover: (event) => _pointAt(event.localPosition.dy),
                      onExit: (_) {
                        _setHovered(false);
                        _pointAt(null);
                      },
                      child: child,
                    ),
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _handleDown,
                      onPointerMove: _handleMove,
                      onPointerUp: _handleUp,
                      onPointerCancel: _handleUp,
                      onPointerSignal: widget.onPointerSignal,
                      onPointerPanZoomStart: widget.onPointerPanZoomStart,
                      onPointerPanZoomUpdate: widget.onPointerPanZoomUpdate,
                      onPointerPanZoomEnd: widget.onPointerPanZoomEnd,
                      child: Padding(
                        padding: EdgeInsets.only(left: out, right: _reachIn),
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _MinimapPainter(
                              this,
                              Listenable.merge([
                                widget.moved,
                                _repaint,
                                _hover,
                                _reveal,
                                _lighting,
                                ChatMinimap.glass,
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Over the column, from beside the minimap: nothing to point at.
            if (shown)
              Positioned.fill(
                child: IgnorePointer(
                  child: _Peek(
                    target: _peek,
                    left: left + _width + ChatMinimap._outset + 10,
                    maxWidth: math.min(440.0, column.width * 0.8),
                    content: _peekAt,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // --- Painting --------------------------------------------------------------
  //
  // A scroll repaints it every frame, so a frame does little: the strokes are
  // drawn once into images, tiles [_tile] tall at the screen's pixels (again
  // only where the samples under them change), and a frame places a few,
  // whole pixels apart; a gradient is made again only when what it is made
  // of changes (the glass's are made where it is at the origin, and moved
  // there); nothing is blurred.

  /// How far in from either end the strokes fade out, where there are more
  /// past it.
  static const _fade = 28.0;

  /// The strokes out of view while the glass shows: dimmer than those under
  /// it, and how far the one shades into the other; all of them, while it
  /// does not.
  static const _dim = 0.68;
  static const _rest = 0.8;
  static const _soft = 4.0;

  /// How much the strokes swell at the glass's middle while it shows, how
  /// far past its ends they still do (pressed a little together there, to
  /// make the room), and the bands they are put back in.
  static const _swell = 0.18;
  static const _swellReach = 48.0;
  static const _band = 3.0;

  /// How much of the theme's accent is in the light on the glass (its rim
  /// and gleam), the rest the text's color.
  static const _tint = 0.3;

  /// How much stronger the strokes are under the pointer: the tiles are
  /// recorded so, and the mask takes them down at rest (no stroke is so
  /// strong as to be opaque either way).
  static const _hoverStrength = 1.3;

  static const _tile = 256.0;
  static const _maxTiles = 24;

  /// How thick a user's message's mark is.
  static const _userMark = 3.0;
  final Paint _userPaint = Paint();

  final Map<int, ui.Image> _tiles = {};

  /// The screen's pixels to the minimap's, as last built.
  double _pixelRatio = 1;

  /// What the tiles were drawn with: the minimap's width, colors and pixels.
  (double, Color, Color, double)? _tileLook;
  List<Paint> _tonePaints = const [];

  final Paint _fill = Paint();
  final Paint _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8;
  final Paint _layer = Paint();
  final Paint _tilePaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _clear = Paint()..blendMode = BlendMode.clear;

  /// Where each band of [_placeSwollen] is put, and what of a tile it is,
  /// kept from frame to frame.
  Float32List _swellAt = Float32List(0);
  Float32List _swellTransforms = Float32List(0);
  Float32List _swellRects = Float32List(0);
  final Paint _masking = Paint()..blendMode = BlendMode.dstIn;
  final _Kept<Shader> _trackShader = _Kept();
  final _Kept<Shader> _bodyShader = _Kept();
  final _Kept<Shader> _rimShader = _Kept();
  final _Kept<Shader> _gleamShader = _Kept();
  final _Kept<Shader> _maskShader = _Kept();

  /// Drops the tiles reaching below [y] in the strokes: what they show has
  /// changed.
  void _dropTilesFrom(double y) {
    _tiles.removeWhere((index, image) {
      if ((index + 1) * _tile <= y) return false;
      image.dispose();
      return true;
    });
  }

  void _paint(Canvas canvas, Size box) {
    // The track, inside the room left either side of it for the glass.
    final size = Size(box.width - 2 * ChatMinimap._outset, box.height);
    if (_rows.isEmpty || size.isEmpty) return;
    canvas
      ..save()
      ..translate(ChatMinimap._outset, 0);
    _paintTrack(canvas, size);
    canvas.restore();
  }

  void _paintTrack(Canvas canvas, Size size) {
    if (widget.span() case final span?) _aim(span);
    if (_top.isNaN) return;
    final hover = Curves.easeOut.transform(_hover.value);
    final shown = Curves.easeOutCubic.transform(_reveal.value);
    final ink = AppColors.text.withValues(alpha: 1);
    final accent = AppColors.accent.withValues(alpha: 1);
    final look = (_width, ink, accent, _pixelRatio);
    if (look != _tileLook) {
      _dropTilesFrom(double.negativeInfinity);
      _tileLook = look;
      _tonePaints = _paintsFor(ink, accent);
    }
    final bounds = Offset.zero & size;
    // The strokes' layer: as wide as the glass, for those it swells.
    final layer = Rect.fromLTRB(
      -ChatMinimap._outset,
      0,
      size.width + ChatMinimap._outset,
      size.height,
    );
    final glass = _glass(size.height);

    // The track: a breath of the text's color, gone at either end.
    _fill
      ..color = const Color(0xFF000000)
      ..shader = _trackShader.keep((size, ink, hover), () {
        final track = 0.02 + 0.016 * hover;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ink.withValues(alpha: 0),
            ink.withValues(alpha: track),
            ink.withValues(alpha: track),
            ink.withValues(alpha: 0),
          ],
          stops: const [0, 0.16, 0.84, 1],
        ).createShader(bounds);
      });
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(5)),
      _fill,
    );

    // The glass, a little wider than the track, gathers in from either side
    // as it comes.
    final pinch = (1 - shown) * size.width * 0.18 - ChatMinimap._outset;
    final pane = Rect.fromLTRB(
      pinch,
      glass.top,
      size.width - pinch,
      glass.top + glass.height,
    );
    final radius = Radius.circular(math.min(7, glass.height / 2));
    final lift =
        (1 + 0.3 * hover + (_grab != null ? 0.35 : 0)) *
        shown *
        ChatMinimap.glass.value;
    // Clear glass: none of it drawn.
    if (lift > 0) {
      canvas
        ..save()
        ..translate(pane.left, pane.top);
      _paintGlassBody(canvas, pane.size, radius, ink, lift);
      canvas.restore();
    }

    // The strokes, faded at the ends and dimmed out of view in one mask;
    // swelling toward the glass's middle, as the Dock's icons toward the
    // pointer.
    final offset = glass.offset;
    canvas.saveLayer(layer, _layer);
    _placeTiles(canvas, offset, 0, size.height);
    final swell = _swell * shown;
    final reach = glass.height / 2 + _swellReach;
    final middle = glass.top + glass.height / 2;
    if (swell > 0) {
      // Taken out about the glass, and put back swollen.
      canvas.drawRect(
        Rect.fromLTRB(layer.left, middle - reach, layer.right, middle + reach),
        _clear,
      );
      _placeSwollen(canvas, offset, middle, reach, swell);
    }
    final above = (offset / _fade).clamp(0.0, 1.0);
    final below = ((_extent - offset - size.height) / _fade).clamp(0.0, 1.0);
    _masking.shader = _maskShader.keep(
      // Where the glass is matters only while it shows.
      (
        size.height,
        shown > 0 ? glass.top : 0,
        shown > 0 ? glass.height : 0,
        above,
        below,
        hover,
        shown,
      ),
      () => _mask(size.height, glass, above, below, hover, shown),
    );
    canvas
      ..drawRect(layer, _masking)
      ..restore();

    _paintUsers(
      canvas,
      size,
      offset: offset,
      middle: middle,
      reach: reach,
      swell: swell,
      above: above,
      below: below,
      hover: hover,
      accent: accent,
    );

    if (lift > 0) {
      canvas
        ..save()
        ..translate(pane.left, pane.top);
      // Its light a little of the theme's color.
      _paintGlassLight(
        canvas,
        pane.size,
        radius,
        Color.lerp(ink, accent, _tint)!,
        lift,
      );
      canvas.restore();
    }
    _evictTiles(offset + size.height / 2);
    if (_pointerAt != null) _snapSoon();
  }

  /// The user's messages' marks, each where its row's strokes are (swollen
  /// as they are about the glass, faded as they are at the ends), not
  /// dimmed with them; the one the pointer is drawn to wider, as wide as
  /// the glass, and bolder.
  void _paintUsers(
    Canvas canvas,
    Size size, {
    required double offset,
    required double middle,
    required double reach,
    required double swell,
    required double above,
    required double below,
    required double hover,
    required Color accent,
  }) {
    _drawnRows.clear();
    _drawnAt.clear();
    if (_users.isEmpty) return;
    final snapped = (offset * _pixelRatio).roundToDouble() / _pixelRatio;
    final lighting = Curves.easeOutCubic.transform(_lighting.value);
    final height = size.height;
    for (var i = 0; i < _users.length; i++) {
      var y = _usersAt[i] - snapped;
      if (y < -height) continue;
      if (y > 2 * height) break;
      if (swell > 0 && (y - middle).abs() < reach) {
        final u = (y - middle) / reach;
        y =
            middle +
            reach *
                (u +
                    swell /
                        2 *
                        (math.sin(math.pi * u) / math.pi +
                            math.sin(2 * math.pi * u) / (2 * math.pi)));
      }
      var edge = 1.0;
      if (y < _fade) edge *= 1 - above * (1 - y / _fade).clamp(0.0, 1.0);
      if (y > height - _fade) {
        edge *= 1 - below * (1 - (height - y) / _fade).clamp(0.0, 1.0);
      }
      if (edge <= 0.02 || y < -4 || y > height + 4) continue;
      final row = _users[i];
      // Too faded to be seen, not to be pointed at.
      if (edge > 0.3) {
        _drawnRows.add(row);
        _drawnAt.add(y);
      }
      final lit = row == _lit
          ? lighting
          : row == _unlit
          ? 1 - lighting
          : 0.0;
      final out = ChatMinimap._outset * lit;
      final thickness = _userMark + 2 * lit;
      _userPaint.color = accent.withValues(
        alpha: edge * (0.78 + 0.1 * hover + (0.22 - 0.1 * hover) * lit),
      );
      canvas.drawRRect(
        RRect.fromLTRBR(
          1 - out,
          y - thickness / 2,
          size.width - 1 + out,
          y + thickness / 2,
          Radius.circular(thickness / 2),
        ),
        _userPaint,
      );
    }
  }

  /// The tiles of the strokes from [from] down to [to] in the minimap, the
  /// strokes [offset] up.
  void _placeTiles(Canvas canvas, double offset, double from, double to) {
    if (to <= from) return;
    // On the screen's pixels: an image placed between them would blur.
    final snapped = (offset * _pixelRatio).roundToDouble() / _pixelRatio;
    final first = math.max(0, ((snapped + from) / _tile).floor());
    final last = ((snapped + to) / _tile).ceil() - 1;
    for (var index = first; index <= last; index++) {
      final image = _tiles[index] ??= _draw(index);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, index * _tile - snapped, _width, _tile),
        _tilePaint,
      );
    }
  }

  /// The strokes [reach] either side of [middle] in the minimap (the strokes
  /// [offset] up), swollen by [swell] at [middle] and less away from it:
  /// thin bands of the tiles, each scaled as much as the bands around it
  /// are, in one draw a tile.
  ///
  /// Band u (from -1 to 1 across) is put at f(u) = u + swell/2 · (sin πu/π +
  /// sin 2πu/2π): f'(u) is 1 + swell at the middle and 1 at the ends, smooth
  /// into the strokes either side, which are not moved.
  void _placeSwollen(
    Canvas canvas,
    double offset,
    double middle,
    double reach,
    double swell,
  ) {
    final bands = math.max(2, (2 * reach / _band).ceil());
    if (_swellAt.length < bands + 1) {
      _swellAt = Float32List(bands + 1);
      // A band reaches two tiles at most.
      _swellTransforms = Float32List(4 * (bands + 4));
      _swellRects = Float32List(4 * (bands + 4));
    }
    for (var i = 0; i <= bands; i++) {
      final u = -1 + 2 * i / bands;
      _swellAt[i] =
          middle +
          reach *
              (u +
                  swell /
                      2 *
                      (math.sin(math.pi * u) / math.pi +
                          math.sin(2 * math.pi * u) / (2 * math.pi)));
    }
    final snapped = (offset * _pixelRatio).roundToDouble() / _pixelRatio;
    final step = 2 * reach / bands;
    final from = math.max(0.0, middle - reach + snapped);
    final to = math.min(_extent, middle + reach + snapped);
    if (to <= from) return;
    final center = _width / 2;
    for (var index = (from / _tile).floor(); index * _tile < to; index++) {
      final image = _tiles[index] ??= _draw(index);
      final tileTop = index * _tile;
      var count = 0;
      for (var i = 0; i < bands; i++) {
        // The band, in the strokes, and what of it is this tile's.
        final top = middle - reach + i * step + snapped;
        final low = math.max(top, math.max(tileTop, from));
        final high = math.min(top + step, math.min(tileTop + _tile, to));
        if (high <= low) continue;
        final scale = (_swellAt[i + 1] - _swellAt[i]) / step;
        final k = count * 4;
        _swellTransforms
          ..[k] = scale / _pixelRatio
          ..[k + 1] = 0
          ..[k + 2] = center - scale * center
          ..[k + 3] = _swellAt[i] + (low - top) * scale;
        _swellRects
          ..[k] = 0
          ..[k + 1] = (low - tileTop) * _pixelRatio
          ..[k + 2] = image.width.toDouble()
          ..[k + 3] = (high - tileTop) * _pixelRatio;
        count++;
      }
      if (count == 0) continue;
      canvas.drawRawAtlas(
        image,
        Float32List.sublistView(_swellTransforms, 0, count * 4),
        Float32List.sublistView(_swellRects, 0, count * 4),
        null,
        null,
        null,
        _tilePaint,
      );
    }
  }

  /// Keeps the tiles nearest [middle] in the strokes, [_maxTiles] at most.
  void _evictTiles(double middle) {
    if (_tiles.length <= _maxTiles) return;
    final here = middle / _tile;
    final far = _tiles.keys.toList()
      ..sort((a, b) => (b - here).abs().compareTo((a - here).abs()));
    for (final index in far.take(_tiles.length - _maxTiles)) {
      _tiles.remove(index)!.dispose();
    }
  }

  /// Tile [index] of the strokes, drawn at the screen's pixels.
  ui.Image _draw(int index) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pixelRatio);
    final top = index * _tile;
    final bottom = top + _tile;
    canvas.clipRect(Rect.fromLTWH(0, 0, _width, _tile));
    const left = 3.0;
    final width = _width - 2 * left;
    final paints = _tonePaints;
    for (
      var row = _rowAt(top);
      row < _rows.length && _tops[row] < bottom;
      row++
    ) {
      final marks = _rows[row].marks;
      final rowTop = _tops[row] - top;
      for (var m = 0; m < marks.length; m += 5) {
        final y = rowTop + marks[m + 2];
        final height = marks[m + 3];
        if (y > _tile || y + height < 0) continue;
        final x = left + marks[m] * width;
        final w = math.max(1.0, marks[m + 1] * width);
        final tone = marks[m + 4].toInt();
        if (_Tone.values[tone].block) {
          canvas.drawRRect(
            RRect.fromLTRBR(x, y, x + w, y + height, const Radius.circular(1)),
            paints[tone],
          );
        } else {
          canvas.drawRect(Rect.fromLTWH(x, y, w, height), paints[tone]);
        }
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (_width * _pixelRatio).ceil(),
      (_tile * _pixelRatio).ceil(),
    );
    picture.dispose();
    return image;
  }

  /// Each [_Tone]'s paint, as strong as under the pointer.
  static List<Paint> _paintsFor(Color ink, Color accent) {
    Paint paint(Color color, double alpha) => Paint()
      ..color = color.withValues(alpha: math.min(1, alpha * _hoverStrength));
    return [
      for (final tone in _Tone.values)
        switch (tone) {
          _Tone.text => paint(ink, 0.34),
          _Tone.strong => paint(ink, 0.55),
          _Tone.faint => paint(ink, 0.2),
          _Tone.code => paint(ink, 0.26),
          _Tone.added => paint(AppColors.added.withValues(alpha: 1), 0.75),
          _Tone.removed => paint(AppColors.removed.withValues(alpha: 1), 0.75),
          _Tone.codeBlock => paint(ink, 0.06),
        },
    ];
  }

  /// The glass [size] at the origin, under the strokes: a shadow only
  /// outside it, and its body, clearer in the middle than at its ends, as a
  /// drop of water.
  ///
  /// Each shadow is a ring between the glass and one a hair wider, reaching
  /// further down: below it, hardly beside it, its corners as round as the
  /// glass's (one only moved down would cut into the glass, and show as two
  /// slivers curling about the corners).
  void _paintGlassBody(
    Canvas canvas,
    Size size,
    Radius radius,
    Color ink,
    double lift,
  ) {
    final glass = RRect.fromRectAndRadius(Offset.zero & size, radius);
    _fill
      ..shader = null
      ..color = const Color(0xFF000000).withValues(alpha: 0.035 * lift);
    canvas.drawDRRect(_below(glass, 0.4, 2.2), glass, _fill);
    _fill.color = const Color(0xFF000000).withValues(alpha: 0.05 * lift);
    canvas.drawDRRect(_below(glass, 0.2, 1), glass, _fill);
    _fill
      ..color = const Color(0xFF000000)
      ..shader = _bodyShader.keep(
        (size, ink, lift),
        () => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ink.withValues(alpha: 0.085 * lift),
            ink.withValues(alpha: 0.03 * lift),
            ink.withValues(alpha: 0.024 * lift),
            ink.withValues(alpha: 0.055 * lift),
          ],
          stops: const [0, 0.3, 0.7, 1],
        ).createShader(Offset.zero & size),
      );
    canvas.drawRRect(glass, _fill);
  }

  /// [glass], [side] wider either side and above, [down] further below:
  /// round where it is, so all round it.
  static RRect _below(RRect glass, double side, double down) => RRect.fromLTRBR(
    glass.left - side,
    glass.top - side,
    glass.right + side,
    glass.bottom + down,
    glass.tlRadius + Radius.circular(side),
  );

  /// Light on the glass [size] at the origin, over the strokes: its rim
  /// catching it, brightest at the top and again (less) at the bottom, and a
  /// gleam inside its top, the glass's own shape a little in, for its
  /// corners to be the glass's.
  void _paintGlassLight(
    Canvas canvas,
    Size size,
    Radius radius,
    Color ink,
    double lift,
  ) {
    final glass = RRect.fromRectAndRadius(Offset.zero & size, radius);
    _rim
      ..color = const Color(0xFF000000)
      ..shader = _rimShader.keep(
        (size, ink, lift),
        () => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ink.withValues(alpha: 0.26 * lift),
            ink.withValues(alpha: 0.1 * lift),
            ink.withValues(alpha: 0.07 * lift),
            ink.withValues(alpha: 0.14 * lift),
          ],
          stops: const [0, 0.15, 0.85, 1],
        ).createShader(Offset.zero & size),
      );
    canvas.drawRRect(glass.deflate(0.4), _rim);
    final inner = glass.deflate(1.2);
    if (inner.isEmpty) return;
    final reach = math.min(9.0, size.height * 0.35);
    _fill
      ..color = const Color(0xFF000000)
      ..shader = _gleamShader.keep(
        (reach, ink, lift),
        () => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ink.withValues(alpha: 0.1 * lift),
            ink.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 1.2, 1, reach)),
      );
    canvas.drawRRect(inner, _fill);
  }

  /// The strokes' alpha down the minimap: faded toward an end with more past
  /// it ([above], [below]: as far as there is, up to [_fade]), down to as
  /// strong as at rest unless under the pointer, and, as much as the glass
  /// shows ([shown]), dimmed away from it.
  Shader _mask(
    double height,
    ({double top, double height, double offset}) glass,
    double above,
    double below,
    double hover,
    double shown,
  ) {
    final strength = (1 + (_hoverStrength - 1) * hover) / _hoverStrength;
    final rest = (_rest + (1 - _rest) * 0.5 * hover) * strength;
    final lit = rest + (strength - rest) * shown;
    final dim = rest + ((_dim + 0.25 * hover) * strength - rest) * shown;
    final top = glass.top;
    final bottom = glass.top + glass.height;
    double alpha(double y) {
      var edge = 1.0;
      if (y < _fade) edge *= 1 - above * (1 - y / _fade);
      if (y > height - _fade) edge *= 1 - below * (1 - (height - y) / _fade);
      final light = y < top - _soft || y > bottom + _soft
          ? dim
          : y < top
          ? dim + (lit - dim) * (y - top + _soft) / _soft
          : y > bottom
          ? lit - (lit - dim) * (y - bottom) / _soft
          : lit;
      return edge * light;
    }

    final ys = <double>{
      0,
      _fade / 2,
      _fade,
      height - _fade,
      height - _fade / 2,
      height,
      top - _soft,
      top,
      bottom,
      bottom + _soft,
    }.where((y) => y >= 0 && y <= height).toList()..sort();
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [for (final y in ys) Color.fromRGBO(255, 255, 255, alpha(y))],
      stops: [for (final y in ys) y / height],
    ).createShader(Rect.fromLTWH(0, 0, 1, height));
  }
}

/// A value made again only when what it is made of ([keep]'s key) changes.
class _Kept<T extends Object> {
  Object? _key;
  T? _value;

  T keep(Object key, T Function() make) {
    final value = _value;
    if (value != null && key == _key) return value;
    _key = key;
    return _value = make();
  }
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// A user's message beside the minimap, as [target] says: its [content],
/// [left] in, the message's first line level with its mark. It comes at once (a breath of a fade),
/// glides from one message to the next, and goes as quickly.
class _Peek extends StatefulWidget {
  const _Peek({
    required this.target,
    required this.left,
    required this.maxWidth,
    required this.content,
  });

  final ValueListenable<({int row, double at})?> target;
  final double left;
  final double maxWidth;
  final ({Widget card, double firstLine}) Function(int row) content;

  @override
  State<_Peek> createState() => _PeekState();
}

class _PeekState extends State<_Peek> with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    reverseDuration: const Duration(milliseconds: 120),
  )..addStatusListener(_faded);
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: 1,
  );
  final _Repaint _moved = _Repaint();

  /// The message shown, kept while it fades out; where its mark was, and
  /// where it glides from.
  int? _row;
  double _from = 0;
  double _to = 0;

  double get _at =>
      ui.lerpDouble(_from, _to, Curves.easeOutCubic.transform(_glide.value))!;

  @override
  void initState() {
    super.initState();
    widget.target.addListener(_changed);
    if (widget.target.value case final target?) {
      _row = target.row;
      _from = _to = target.at;
      _fade.forward();
    }
  }

  @override
  void didUpdateWidget(_Peek oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      oldWidget.target.removeListener(_changed);
      widget.target.addListener(_changed);
    }
  }

  void _changed() {
    final target = widget.target.value;
    if (target == null) {
      _fade.reverse();
      return;
    }
    if (_row == null || _fade.value == 0) {
      // Out of sight: straight there.
      _from = _to = target.at;
      _glide.value = 1;
    } else if (target.row != _row) {
      _from = _at;
      _to = target.at;
      _glide.forward(from: 0);
    } else {
      // The same, moved (the strokes scrolled under it): along with it.
      _from = _to = target.at;
    }
    if (target.row != _row) {
      setState(() => _row = target.row);
    } else {
      _moved.ping();
    }
    _fade.forward();
  }

  void _faded(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() => _row = null);
    }
  }

  @override
  void dispose() {
    widget.target.removeListener(_changed);
    _fade.dispose();
    _glide.dispose();
    _moved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    if (row == null) return const SizedBox.shrink();
    final content = widget.content(row);
    return AnimatedBuilder(
      animation: Listenable.merge([_fade, _glide, _moved]),
      builder: (context, child) {
        final fade = Curves.easeOut.transform(_fade.value);
        return CustomSingleChildLayout(
          delegate: _PeekLayout(
            widget.left,
            _at - content.firstLine,
            widget.maxWidth,
          ),
          child: Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(-4 * (1 - fade), 0),
              child: child,
            ),
          ),
        );
      },
      child: RepaintBoundary(child: content.card),
    );
  }
}

/// The peek [left] in, its top at [top] as far as the box lets it (8
/// from its edges), at most [maxWidth] wide.
class _PeekLayout extends SingleChildLayoutDelegate {
  _PeekLayout(this.left, this.top, this.maxWidth);

  final double left;
  final double top;
  final double maxWidth;

  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
          0.0,
          math.min(maxWidth, constraints.maxWidth - left - _margin),
        ),
        maxHeight: math.max(0.0, constraints.maxHeight - 2 * _margin),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    left,
    top.clamp(
      _margin,
      math.max(_margin, size.height - childSize.height - _margin),
    ),
  );

  @override
  bool shouldRelayout(_PeekLayout oldDelegate) =>
      oldDelegate.left != left ||
      oldDelegate.top != top ||
      oldDelegate.maxWidth != maxWidth;
}

/// A glimpse of the conversation about a user's message, on its page: the
/// end of what the agent said [before] it, the message as its bubble
/// ([UserMessagePreview]), the start of what it said [after]. Fading into
/// the card at its top and bottom, as more goes on past them; nothing in
/// it scrolls.
class _PeekCard extends StatelessWidget {
  const _PeekCard({required this.message, this.before, this.after});

  final UserMessageItem message;
  final String? before;
  final String? after;

  static const _pad = 12.0;
  static const _gap = 10.0;

  /// How much of what came before shows: its last lines, under the fade.
  static const _before = 52.0;

  /// How far into the fade the top and bottom are.
  static const _fade = 28.0;

  /// From the card's top to the middle of the message's first line: past
  /// the room for what came before, the bubble's padding and half a line.
  static double firstLine({required bool before}) =>
      _pad + (before ? _before + _gap : 0) + 10 + 10;

  @override
  Widget build(BuildContext context) {
    final contrast = themeColors.highContrast;
    final style = TextStyle(
      color: AppColors.text,
      fontSize: 12.5,
      height: 1.55,
    );
    final faded = before != null || after != null;
    Widget body = Padding(
      padding: const EdgeInsets.all(_pad),
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (before case final before?) ...[
              // Its end: a list held at its end, shorter than it is.
              SizedBox(
                height: _before,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.bottomLeft,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: _said(before, style),
                  ),
                ),
              ),
              const SizedBox(height: _gap),
            ],
            UserMessagePreview(
              text: message.text,
              images: message.images,
              maxLines: 4,
            ),
            if (after case final after?) ...[
              const SizedBox(height: _gap),
              _said(after, style, maxLines: 6),
            ],
          ],
        ),
      ),
    );
    if (faded) {
      body = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final top = before != null ? _fade / bounds.height : 0.0;
          final bottom = after != null ? _fade / bounds.height : 0.0;
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0x00FFFFFF),
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0, top, 1 - bottom, 1],
          ).createShader(bounds);
        },
        child: body,
      );
    }
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.code,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.partBorder),
          boxShadow: contrast
              ? null
              : [
                  BoxShadow(
                    color: themeColors['widget.shadow'],
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  const BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: body),
      ),
    );
  }

  /// The agent's words, as the history's, a little smaller.
  static Widget _said(String text, TextStyle style, {int? maxLines}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.clip,
      style: style,
    ),
  );
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.state, Listenable repaint) : super(repaint: repaint);

  final _ChatMinimapState state;

  @override
  void paint(Canvas canvas, Size size) => state._paint(canvas, size);

  // Painted anew for what it was built with, whatever that is.
  @override
  bool shouldRepaint(_MinimapPainter oldDelegate) => true;
}

/// What a stroke is, for its color; the blocks (a code block's, a plan's)
/// rounded, under the strokes in them.
enum _Tone {
  text,
  strong,
  faint,
  code,
  added,
  removed,
  codeBlock(block: true);

  const _Tone({this.block = false});

  final bool block;
}

/// A row sampled: its height in the minimap and its strokes, five numbers
/// each: left and width across the column (0 to 1), top and height down
/// from the row's top, and [_Tone] index.
class _Sample {
  _Sample(this.row, this.height, this.marks, {this.user});

  final ChatMinimapRow row;
  final double height;
  final Float32List marks;

  /// The user's message: where its mark is, down from the row's top.
  final double? user;

  /// Whether it stands for [other], whose item is its own.
  bool fits(ChatMinimapRow other) =>
      other.shown == row.shown &&
      other.foldLines == row.foldLines &&
      other.gap == row.gap;
}

/// Samples rows of a column [width] wide into strokes, at the heights the
/// history lays them out (roughly: a history's real heights are only known
/// for what it has laid out), scaled down by [_scale].
class _Sampler {
  _Sampler(this.width, {required this.bubbles});

  final double width;

  /// Whether the user's messages are bubbles at the right, as wide as their
  /// text, or as wide as the column.
  final bool bubbles;

  /// The minimap's pixels to the history's, down it.
  static const _scale = 0.14;

  /// The history's prose: a character's width (a wide one's twice), and a
  /// line's height (13.5 at 1.6).
  static const _char = 6.8;
  static const _line = 21.6;
  static const _stroke = 1.4;

  /// A step's line (a tool call, a thought, a fold).
  static const _stepLine = 28.0;

  final List<double> _marks = [];
  double _y = 0;
  double? _userAt;

  _Sample sample(ChatMinimapRow row) {
    _marks.clear();
    _userAt = null;
    _y = row.gap * _scale;
    for (var i = 0; i < row.foldLines; i++) {
      _step(20);
    }
    if (row.shown) {
      switch (row.item) {
        case final UserMessageItem item:
          _user(item);
        case AssistantTextItem(:final text):
          _markdown(text);
        case ThinkingItem():
          _step(12);
        case ToolCallItem(:final label, :final target):
          _step((label ?? target).length + 8.0);
        case TerminalItem(:final description, :final command):
          _step((description ?? command).length + 4.0);
        case AgentItem(:final description):
          _step(description.length + 6.0);
        case final CodeDiffItem diff:
          _step(
            diff.fileName.length + 4.0,
            added: diff.added,
            removed: diff.removed,
          );
        case final PlanItem plan:
          _plan(plan);
        case NoticeItem(:final kind, :final text):
          _step(
            math.min(text.length, 60).toDouble(),
            tone: kind == NoticeKind.error ? _Tone.removed : _Tone.faint,
          );
        case LiveStatusItem(:final label):
          _step(label.length.toDouble());
      }
    }
    return _Sample(row, _y, Float32List.fromList(_marks), user: _userAt);
  }

  void _mark(double x, double w, double y, double h, _Tone tone) {
    final left = x.clamp(0.0, width);
    final right = (x + w).clamp(0.0, width);
    if (right <= left) return;
    _marks.addAll([
      left / width,
      (right - left) / width,
      y,
      h,
      tone.index.toDouble(),
    ]);
  }

  /// A stroke [thickness] thick in the middle of a line [line] tall at the
  /// current height, which it leaves where it is.
  void _bar(double x, double w, double line, double thickness, _Tone tone) =>
      _mark(x, w, _y + (line * _scale - thickness) / 2, thickness, tone);

  /// A block from [top] to the current height, under the strokes since
  /// [at].
  void _block(int at, double top, double x, double w, _Tone tone) {
    final left = x.clamp(0.0, width);
    final right = (x + w).clamp(0.0, width);
    _marks.insertAll(at, [
      left / width,
      (right - left) / width,
      top,
      _y - top,
      tone.index.toDouble(),
    ]);
  }

  /// [text] as lines from [x] to [right], wrapped there: each but the last
  /// a little short of it, as words wrap.
  void _prose(
    String text, {
    double x = 0,
    double? right,
    _Tone tone = _Tone.text,
    double char = _char,
    double line = _line,
    double thickness = _stroke,
  }) {
    final room = math.max(char * 4, (right ?? width) - x);
    var left = _units(text) * char;
    var row = text.length;
    while (left > room) {
      final full = room * _ragged(row++);
      _bar(x, full, line, thickness, tone);
      _y += line * _scale;
      left -= full;
    }
    if (left > 0) _bar(x, left, line, thickness, tone);
    _y += line * _scale;
  }

  /// How far short of the column's end a wrapped line ends, by [seed].
  static double _ragged(int seed) => 1 - (seed * 7 + 3) % 11 / 10 * 0.12;

  /// A step's line: its icon, its label as long as [units] of text, and
  /// how many lines it [added] and [removed], if it edits.
  void _step(
    double units, {
    _Tone tone = _Tone.faint,
    int? added,
    int? removed,
  }) {
    _mark(0, 8, _y + (_stepLine * _scale - 1.6) / 2, 1.6, _Tone.faint);
    final label = math.min(units * 6.4, width * 0.6);
    _bar(16, label, _stepLine, 1.2, tone);
    var x = 16 + label + 8;
    double count(int lines) => (math.log(lines + 1) * 7).clamp(5.0, 40.0);
    if (added != null && added > 0) {
      _bar(x, count(added), _stepLine, 1.2, _Tone.added);
      x += count(added) + 5;
    }
    if (removed != null && removed > 0) {
      _bar(x, count(removed), _stepLine, 1.2, _Tone.removed);
    }
    _y += _stepLine * _scale;
  }

  /// The user's message: as tall as its bubble, but no strokes of its own;
  /// the minimap marks it with one mark at its middle ([_Sample.user]).
  void _user(UserMessageItem item) {
    const padX = 14.0;
    const padY = 9.0;
    const thumb = 56.0;
    final most = bubbles ? width * 0.85 : width;
    // As the bubble shows it: what goes after its text (a long paste, lines
    // of a file) only as the tag in it, and of a long one its first lines.
    final lines = splitCodeAppendix(item.text).body.trimRight().split('\n');
    var widest = item.images.length * (thumb + 6);
    for (final line in lines) {
      widest = math.max(widest, _units(line) * _char);
    }
    final bubble = bubbles
        ? math.min(most, math.max(widest, 40) + 2 * padX)
        : width;
    final top = _y;
    _y += padY * _scale;
    if (item.images.isNotEmpty) _y += (thumb + 8) * _scale;
    final room = math.max(_char * 4, bubble - 2 * padX);
    var rows = 0;
    for (final line in lines) {
      rows += math.max(1, (_units(line) * _char / room).ceil());
    }
    // Up to one line more than it collapses to shows whole.
    const collapsed = UserMessageBubble.collapsedLines;
    if (rows > collapsed + 1) rows = collapsed;
    _y += (rows * _line + padY) * _scale;
    _userAt = (top + _y) / 2;
  }

  void _plan(PlanItem plan) {
    const pad = 14.0;
    final at = _marks.length;
    final top = _y;
    _y += 12 * _scale;
    _prose(
      plan.name,
      x: pad,
      right: width - pad,
      tone: _Tone.strong,
      line: 26,
      thickness: 1.8,
    );
    var shown = 0;
    for (final line in (plan.text ?? '').split('\n')) {
      final text = _plain(line.replaceFirst(_listOrHeading, '')).trim();
      if (text.isEmpty || text == plan.name) continue;
      if (shown++ == 8) break;
      _prose(text, x: pad, right: width - pad);
    }
    _y += 12 * _scale;
    _block(at, top, 0, width, _Tone.codeBlock);
  }

  static final _fence = RegExp(r'^\s*(`{3,}|~{3,})');
  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');
  static final _quote = RegExp(r'^\s*>\s?(.*)$');
  static final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
  static final _tableRule = RegExp(r'^\s*\|?[\s:|-]*-{2,}[\s:|-]*$');
  static final _listOrHeading = RegExp(r'^\s*(#{1,6}|[-*+]|\d+[.)])\s+');
  static final _linkTarget = RegExp(r'\]\([^)]*\)');
  static final _markers = RegExp(r'[*`\[\]]');

  /// [line] without what markdown takes out of it: emphasis, code ticks,
  /// links' targets.
  static String _plain(String line) =>
      line.replaceAll(_linkTarget, '').replaceAll(_markers, '');

  /// The agent's words, as markdown lays them out: headings, lists, quotes,
  /// tables and code blocks.
  void _markdown(String text) {
    String? fence;
    var codeAt = 0;
    var codeTop = 0.0;
    var tableRow = -1;
    // Space asked for before what comes next, and whether anything has.
    var gap = 0.0;
    var started = false;
    void next(double before) {
      if (started) _y += math.max(gap, before) * _scale;
      gap = 0;
      started = true;
    }

    void closeCode() {
      _y += 10 * _scale;
      _block(codeAt, codeTop, 0, width, _Tone.codeBlock);
      fence = null;
      gap = 10;
    }

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (fence case final open?) {
        if (line.trimLeft().startsWith(open)) {
          closeCode();
        } else {
          _code(line);
        }
        continue;
      }
      if (_fence.firstMatch(line) case final match?) {
        next(10);
        fence = match.group(1)!.substring(0, 3);
        codeAt = _marks.length;
        codeTop = _y;
        // Its header: the language, its buttons.
        _y += 30 * _scale;
        tableRow = -1;
        continue;
      }
      if (line.trim().isEmpty) {
        gap = math.max(gap, 10);
        tableRow = -1;
        continue;
      }
      if (line.trimLeft().startsWith('|')) {
        if (_tableRule.hasMatch(line)) continue;
        next(tableRow < 0 ? 10 : 0);
        tableRow++;
        _tableRow(line, header: tableRow == 0);
        continue;
      }
      if (tableRow >= 0) {
        tableRow = -1;
        gap = math.max(gap, 10);
      }
      if (_heading.firstMatch(line) case final match?) {
        next(16);
        final level = match.group(1)!.length;
        final (char, height) = switch (level) {
          1 => (10.0, 32.0),
          2 => (9.0, 29.0),
          3 => (8.0, 26.0),
          _ => (7.2, 24.0),
        };
        _prose(
          _plain(match.group(2)!),
          tone: _Tone.strong,
          char: char,
          line: height,
          thickness: level <= 2 ? 2.0 : 1.7,
        );
        gap = 4;
        continue;
      }
      if (_rule.hasMatch(line)) {
        next(10);
        _bar(0, width, 16, 0.6, _Tone.faint);
        _y += 16 * _scale;
        gap = 10;
        continue;
      }
      if (_quote.firstMatch(line) case final match?) {
        next(0);
        final top = _y;
        _prose(_plain(match.group(1)!), x: 14);
        _mark(0, 3, top, _y - top, _Tone.faint);
        continue;
      }
      if (_bullet.firstMatch(line) case final match?) {
        next(0);
        final x = 20 + match.group(1)!.length ~/ 2 * 18.0;
        _bar(x - 12, 4, _line, 1.4, _Tone.strong);
        _prose(_plain(match.group(3)!), x: x);
        continue;
      }
      next(0);
      _prose(_plain(line));
    }
    // Still being written.
    if (fence != null) closeCode();
  }

  /// A line of code: at its indent, not wrapped (the block scrolls).
  void _code(String line) {
    const char = 7.4;
    const height = 19.0;
    final text = line.trimLeft();
    if (text.isNotEmpty) {
      final indent = _units(line.substring(0, line.length - text.length));
      _bar(14 + indent * char, _units(text) * char, height, 1.2, _Tone.code);
    }
    _y += height * _scale;
  }

  void _tableRow(String line, {required bool header}) {
    const height = 36.0;
    var cells = line.trim().split('|');
    if (cells.first.trim().isEmpty) cells = cells.sublist(1);
    if (cells.isNotEmpty && cells.last.trim().isEmpty) {
      cells = cells.sublist(0, cells.length - 1);
    }
    if (cells.isEmpty) return;
    final cell = width / cells.length;
    for (final (i, text) in cells.indexed) {
      _bar(
        i * cell + 10,
        math.min(_units(_plain(text.trim())) * _char, cell - 20),
        height,
        1.4,
        header ? _Tone.strong : _Tone.text,
      );
    }
    _y += height * _scale;
  }

  /// How many characters wide [text] is: a wide one (Chinese, Japanese,
  /// Korean, an emoji) two, a tab four.
  static double _units(String text) {
    var units = 0.0;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      units += c == 0x09
          ? 4
          : c >= 0xD800 && c <= 0xDBFF
          ? 2
          : c >= 0xDC00 && c <= 0xDFFF
          ? 0
          : _wide(c)
          ? 2
          : 1;
    }
    return units;
  }

  static bool _wide(int c) =>
      (c >= 0x1100 && c <= 0x115F) ||
      (c >= 0x2E80 && c <= 0xA4CF) ||
      (c >= 0xAC00 && c <= 0xD7A3) ||
      (c >= 0xF900 && c <= 0xFAFF) ||
      (c >= 0xFE30 && c <= 0xFE4F) ||
      (c >= 0xFF00 && c <= 0xFF60) ||
      (c >= 0xFFE0 && c <= 0xFFE6);
}
