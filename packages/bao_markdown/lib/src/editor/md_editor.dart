import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../md_blocks.dart';
import '../md_controller.dart';
import '../md_edits.dart';
import '../md_inline.dart';
import 'md_clipboard.dart';
import 'md_display.dart';
import 'md_embeds.dart';
import 'md_offsets.dart';
import 'md_style.dart';
import 'md_table.dart';
import 'md_text.dart';

/// A code block's lines in their language's colors: spans for each line
/// of [code] (their text the line's); null where the language is not
/// known.
typedef MarkdownCodeColorizer = Future<List<List<InlineSpan>>?> Function(
  String language,
  String code,
);

/// An editor of markdown that shows what it says: the text is the
/// markdown, edited as it is written; a line's marks show where the caret
/// is, what they make everywhere else.
///
/// Its lines are built as they are scrolled to, and built again only when
/// they change: the selection moving paints the lines it is on again, no
/// more.
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.style,
    this.embeds = const MarkdownEmbeds(),
    this.focusNode,
    this.scrollController,
    this.padding = EdgeInsets.zero,
    this.placeholder,
    this.readOnly = false,
    this.autofocus = false,
    this.shrinkWrap = false,
    this.physics,
    this.onKey,
    this.onPaste,
    this.onPasteCopy,
    this.colorize,
    this.onClick,
    this.revealsLinks = true,
    this.keyboardAppearance = Brightness.light,
    this.textAlign = TextAlign.start,
  });

  final MarkdownController controller;
  final MarkdownEditorStyle style;
  final MarkdownEmbeds embeds;
  final FocusNode? focusNode;
  final ScrollController? scrollController;

  /// Around the lines, in the scrolled view.
  final EdgeInsets padding;

  /// Shown where the text is empty.
  final String? placeholder;

  final bool readOnly;
  final bool autofocus;

  /// As tall as its lines, not as the room it is given.
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  /// A key, before the editor's own handling of it: handled, or not.
  final KeyEventResult Function(KeyEvent event)? onKey;

  /// A paste of what the editor did not copy itself: true where this
  /// pasted it (files, pictures, HTML made markdown…), else the text is
  /// put in as it is.
  final Future<bool> Function()? onPaste;

  /// A paste of what an editor of its kind copied: its markdown as it is
  /// to go in (its tags numbered on from those here, say); as it is
  /// without.
  final String Function(String markdown)? onPasteCopy;

  /// Code blocks' colors.
  final MarkdownCodeColorizer? colorize;

  /// A click at [offset] (a link's, ⌘ held…): true where it was taken,
  /// the caret left where it was.
  final bool Function(int offset)? onClick;

  /// Whether a link's marks (its brackets, where it goes) show where the
  /// caret is in it, as other runs' do; else it shows as it does
  /// elsewhere, its text edited as it shows (where it goes, by a bubble
  /// over it, say), nothing moving as the caret comes in.
  final bool revealsLinks;

  final Brightness keyboardAppearance;

  /// How its lines' text is aligned (a table's cell's, as its column).
  final TextAlign textAlign;

  @override
  State<MarkdownEditor> createState() => MarkdownEditorState();
}

/// Where the caret's marks show: the runs of its line it is in, the lines
/// of its block.
@immutable
class _Reveal {
  const _Reveal(this.line, this.column, this.first, this.last, this.key);

  final int line;
  final int column;

  /// The block's lines (the line's alone for most).
  final int first;
  final int last;

  /// The runs the caret is in (what of the line shows with its marks).
  final String key;

  @override
  bool operator ==(Object other) =>
      other is _Reveal &&
      other.line == line &&
      other.first == first &&
      other.last == last &&
      other.key == key;

  @override
  int get hashCode => Object.hash(line, first, last, key);
}

/// What a line's row is built from: it is built again when this changes.
typedef _RowKey = (
  String text,
  MdLineInfo info,
  String? reveal,
  bool block,
  bool top,
  bool bottom,
  Object? code,
  String? source,
  int definitions,
  int look,
);

class MarkdownEditorState extends State<MarkdownEditor>
    with SingleTickerProviderStateMixin, TextInputClient, DeltaTextInputClient {
  MarkdownController get controller => widget.controller;

  late final MdPaintState _paint = MdPaintState(controller, widget.style);

  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  ScrollController? _ownScroll;
  ScrollController get scrollController =>
      widget.scrollController ?? (_ownScroll ??= ScrollController());

  final GlobalKey _scrollKey = GlobalKey();

  /// Rows built, by their lines' ids: built again when their key changes.
  final Map<int, (_RowKey, Widget, MdLineDisplay?)> _rows = {};

  /// Changes when what all rows are built with does (style, scale…).
  int _look = 0;

  _Reveal? _reveal;
  int _seenVersion = -1;
  TextSelection _seenSelection = const TextSelection.collapsed(offset: -1);

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    _focus.addListener(_focusChanged);
    _seenVersion = controller.textVersion;
    _seenSelection = controller.selection;
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).autofocus(_focus);
      });
    }
  }

  TextScaler? _scaler;
  TextDirection? _direction;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    if (scaler != _scaler || direction != _direction) {
      _scaler = scaler;
      _direction = direction;
      _look++;
    }
  }

  @override
  void didUpdateWidget(MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _paint.controller = widget.controller;
      _rows.clear();
      _highlighted.clear();
      _seenVersion = controller.textVersion;
      _seenSelection = controller.selection;
      _syncRemote();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_focusChanged);
      if (widget.focusNode != null) {
        _ownFocus?.dispose();
        _ownFocus = null;
      }
      _focus.addListener(_focusChanged);
    }
    if (oldWidget.scrollController != widget.scrollController &&
        widget.scrollController != null) {
      _ownScroll?.dispose();
      _ownScroll = null;
    }
    if (oldWidget.style != widget.style ||
        oldWidget.embeds != widget.embeds ||
        oldWidget.readOnly != widget.readOnly ||
        oldWidget.colorize != widget.colorize) {
      _paint.style = widget.style;
      _paint.changed();
      _look++;
    }
    if (oldWidget.readOnly != widget.readOnly) {
      if (widget.readOnly) {
        _closeInput();
      } else if (_focus.hasPrimaryFocus) {
        _openInput();
      }
    }
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    _focus.removeListener(_focusChanged);
    _closeInput();
    _blink?.cancel();
    _colorTimer?.cancel();
    _list.dispose();
    _autoscroll?.dispose();
    _ownFocus?.dispose();
    _ownScroll?.dispose();
    _paint.dispose();
    _tableCellChanges.dispose();
    super.dispose();
  }

  // --- What changed --------------------------------------------------------------

  void _changed() {
    final textChanged = controller.textVersion != _seenVersion;
    final selection = controller.selection;
    final selectionChanged = selection != _seenSelection;
    _seenVersion = controller.textVersion;
    _seenSelection = selection;
    _paint.changed();
    if (textChanged) {
      if (_rows.length > controller.lines.lineCount + 512) _pruneRows();
      setState(() {});
    } else if (selectionChanged && _computeReveal() != _reveal) {
      setState(() {});
    }
    if (selectionChanged && _focus.hasPrimaryFocus) _enterTableSoon();
    if (selectionChanged || textChanged) {
      if (!_verticalMove) _verticalX = null;
      _restartBlink();
      if (!_pointerSelecting) _showCaretSoon();
      _imeGeometrySoon();
    }
    _syncRemote();
  }

  void _pruneRows() {
    final lines = controller.lines;
    _rows.removeWhere((id, _) => lines.indexOfId(id) < 0);
  }

  void _focusChanged() {
    final focused = _focus.hasPrimaryFocus;
    _paint.focused = focused;
    if (focused) {
      if (!controller.selection.isValid) {
        controller.selection = TextSelection.collapsed(
          offset: controller.length,
        );
      }
      _openInput();
      _restartBlink();
      _enterTableSoon();
    } else {
      _closeInput();
      _blink?.cancel();
      _blink = null;
    }
    if (mounted) setState(() {});
  }

  bool get hasFocus => _focus.hasFocus;

  // --- Tables ------------------------------------------------------------------------

  /// Tables show as tables and are edited in their cells (see [MdTable]).
  bool get _tablesEdited =>
      !widget.readOnly && widget.embeds.showsBlock(MdLineKind.tableHead);

  /// The tables shown, by their first lines' ids.
  final Map<int, MdTableEditing> _tables = {};

  /// [table], the table whose first line's id is [lineId], shown: the
  /// caret put in it goes into its cells.
  void attachTable(int lineId, MdTableEditing table) => _tables[lineId] = table;

  void detachTable(int lineId, MdTableEditing table) {
    if (identical(_tables[lineId], table)) _tables.remove(lineId);
  }

  /// The editor of a table's cell being typed in (or held open, see
  /// [holdTableCell]); none while none is.
  MarkdownEditorState? get tableCell {
    for (final table in _tables.values) {
      if (table.cellEditor case final editor?) return editor;
    }
    return null;
  }

  /// Told as a table's cell is opened or closed, focused or left, and as
  /// its text or its caret changes: what is over it (a link's bar) goes
  /// with it.
  Listenable get tableCellChanges => _tableCellChanges;
  final _tableCellChanges = ValueNotifier(0);

  /// What a table tells of its cell (see [tableCellChanges]).
  void tableCellChanged() => _tableCellChanges.value++;

  /// While [held], the cell being typed in stays open without the keyboard
  /// (a link's address typed in a bar over it, say).
  void holdTableCell(bool held) {
    for (final table in _tables.values) {
      table.cellHeld = held;
    }
  }

  bool _tableEntryScheduled = false;

  /// The caret come into a table (by the keys, Undo…): into the cell it
  /// is in, once the table is laid out.
  void _enterTableSoon() {
    if (_tableEntryScheduled || !_tablesEdited) return;
    final selection = controller.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final offset = selection.baseOffset.clamp(0, controller.length);
    if (!controller.infoOf(controller.lineAt(offset)).isTable) return;
    _tableEntryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tableEntryScheduled = false;
      if (!mounted || !_focus.hasPrimaryFocus) return;
      final selection = controller.selection;
      if (!selection.isValid || !selection.isCollapsed) return;
      final offset = selection.baseOffset.clamp(0, controller.length);
      final line = controller.lineAt(offset);
      if (!controller.infoOf(line).isTable) return;
      final (first, _) = controller.blockOf(line);
      _tables[controller.lines.idOf(first)]?.focusAt(offset);
    });
  }

  /// The caret is drawn now: the editor focused, nothing selected, and
  /// the caret in its blink's on half.
  bool get caretShowing =>
      _paint.focused &&
      _paint.caretOn &&
      controller.selection.isValid &&
      controller.selection.isCollapsed;

  /// The keyboard to the editor.
  void requestFocus() => _focus.requestFocus();

  // --- The caret's blink -----------------------------------------------------------

  Timer? _blink;

  static const _blinkDelay = Duration(milliseconds: 500);
  static const _blinkHalf = Duration(milliseconds: 530);

  /// On at once (it moved), blinking from a moment later.
  void _restartBlink() {
    _blink?.cancel();
    _paint.caretOn = true;
    if (!_focus.hasPrimaryFocus) return;
    _blink = Timer(_blinkDelay, () {
      _paint.caretOn = false;
      _blink = Timer.periodic(_blinkHalf, (_) {
        _paint.caretOn = !_paint.caretOn;
      });
    });
  }

  // --- Where the caret's marks show ------------------------------------------------

  _Reveal? _computeReveal() {
    if (!_focus.hasPrimaryFocus || widget.readOnly) return null;
    final selection = controller.selection;
    if (!selection.isValid) return null;
    final base = selection.baseOffset.clamp(0, controller.length);
    final line = controller.lineAt(base);
    final column = base - controller.lineStart(line);
    final info = controller.infoOf(line);
    // A table is edited in its cells, never as its markdown.
    if (info.isTable && _tablesEdited) return null;
    var (first, last) = (line, line);
    if (info.isMultiline ||
        info.kind == MdLineKind.indentedCode ||
        info.kind == MdLineKind.setextUnderline ||
        (info.kind == MdLineKind.heading && info.setext)) {
      (first, last) = controller.blockOf(line);
    }
    return _Reveal(line, column, first, last, _revealKey(line, column));
  }

  /// The runs of [line] the column is in: what shows with its marks.
  String _revealKey(int line, int column) {
    final info = controller.infoOf(line);
    if (!info.hasInline) return '';
    final text = controller.lines.line(line);
    final buffer = StringBuffer();
    for (final run in inlinesAt(controller.inlinesOf(line), column)) {
      if (widget.embeds.isAtomic(run, text)) break;
      if (!_revealed(run)) continue;
      buffer
        ..write(run.start)
        ..write(':')
        ..write(run.end)
        ..write(',');
    }
    return buffer.toString();
  }

  /// Whether [run] shows its marks where the caret is in it.
  bool _revealed(MdInline run) =>
      widget.revealsLinks ||
      !(run.kind == MdInlineKind.link || run.kind == MdInlineKind.autolink);

  // --- Rows -------------------------------------------------------------------------

  /// Whether [line] is the first of a block shown as a widget where the
  /// caret is not in it.
  bool _startsShownBlock(int line, MdLineInfo info) => switch (info.kind) {
    MdLineKind.tableHead ||
    MdLineKind.mathOpen ||
    MdLineKind.mathLine => widget.embeds.showsBlock(info.kind),
    MdLineKind.frontMatter =>
      widget.embeds.showsBlock(info.kind) &&
          controller.blockOf(line).$1 == line,
    MdLineKind.fenceOpen => widget.embeds.showsCode(info.language),
    _ => false,
  };

  /// A line of a block shown as its first line's widget.
  bool _inShownBlock(int line, MdLineInfo info) {
    if (!(info.isTable ||
        info.isMath ||
        info.isFence ||
        info.kind == MdLineKind.mathLine ||
        info.kind == MdLineKind.frontMatter)) {
      return false;
    }
    final (first, _) = controller.blockOf(line);
    return _startsShownBlock(first, controller.infoOf(first));
  }

  _RowKey _keyOf(int index) {
    final lines = controller.lines;
    final info = controller.infoOf(index);
    final text = lines.line(index);
    final reveal = _reveal;
    final onLine = reveal != null && reveal.line == index;
    final inBlock =
        reveal != null && index >= reveal.first && index <= reveal.last;
    var top = false;
    var bottom = false;
    if (info.isFence || info.kind == MdLineKind.indentedCode) {
      bool same(int other) {
        if (other < 0 || other >= lines.lineCount) return false;
        final next = controller.infoOf(other);
        return info.kind == MdLineKind.indentedCode
            ? next.kind == MdLineKind.indentedCode
            : next.isFence &&
                  !(other > index && next.kind == MdLineKind.fenceOpen) &&
                  !(other < index && next.kind == MdLineKind.fenceClose);
      }

      top = info.kind == MdLineKind.fenceOpen || !same(index - 1);
      bottom = info.kind == MdLineKind.fenceClose || !same(index + 1);
    }
    Object? code;
    if (info.kind == MdLineKind.fence) code = _codeSpans(index, info);
    String? source;
    if (!inBlock && _startsShownBlock(index, info)) {
      final (first, last) = controller.blockOf(index);
      source = controller.substring(
        controller.lineStart(first),
        controller.lineEnd(last),
      );
    }
    return (
      text,
      info,
      onLine ? _revealKey(index, reveal.column) : null,
      inBlock,
      top,
      bottom,
      code,
      source,
      info.hasInline ? controller.blocks.definitionsVersion : 0,
      _look,
    );
  }

  Widget _row(BuildContext context, int index) {
    final id = controller.lines.idOf(index);
    final key = _keyOf(index);
    final cached = _rows[id];
    if (cached != null && cached.$1 == key) return cached.$2;
    final (row, display) = _buildRow(context, index, id, key);
    _rows[id] = (key, row, display);
    return row;
  }

  /// What [index]'s line shows now (as its row does).
  MdLineDisplay _displayOf(int index) {
    final id = controller.lines.idOf(index);
    final key = _keyOf(index);
    final cached = _rows[id];
    if (cached != null && cached.$1 == key && cached.$3 != null) {
      return cached.$3!;
    }
    return _display(index, id, key);
  }

  MdLineDisplay _display(int index, int id, _RowKey key) {
    final info = key.$2;
    final style = widget.style;
    final content = controller.lines.content(index);
    final lineStyle = lineStyleOf(info, style);
    final reveal = _reveal;
    return buildLineDisplay(
      content,
      info,
      controller.inlinesOf(index),
      style: style,
      lineStyle: lineStyle,
      reveal: key.$3 != null ? reveal?.column : null,
      revealed: _revealed,
      blockRevealed:
          key.$4 || (_isBlockLine(info) && !_inShownBlock(index, info)),
      isAtomic: (run) => widget.embeds.isAtomic(run, content),
      atomic: (run, textStyle) => widget.embeds.inline(
        context,
        MdEmbed(
          controller: controller,
          lineId: id,
          run: run,
          line: content,
          style: textStyle,
        ),
      ),
      code: key.$7 as List<InlineSpan>?,
    );
  }

  /// A table's or math's line: shown as written where no widget is.
  static bool _isBlockLine(MdLineInfo info) =>
      info.isTable || info.isMath || info.kind == MdLineKind.mathLine;

  (Widget, MdLineDisplay?) _buildRow(
    BuildContext context,
    int index,
    int id,
    _RowKey key,
  ) {
    final style = widget.style;
    final info = key.$2;
    final lineStyle = lineStyleOf(info, style);
    final scaler = _scaler ?? TextScaler.noScaling;
    final fontSize = scaler.scale(lineStyle.fontSize ?? 14);
    final lineHeight = fontSize * (lineStyle.height ?? 1.2);
    final inBlock = key.$4;
    // Shown by its block's first line, or not at all: nothing of its own.
    if (key.$8 == null &&
        !inBlock &&
        (_inShownBlock(index, info) ||
            info.kind == MdLineKind.setextUnderline)) {
      return (
        KeyedSubtree(key: ValueKey(id), child: const SizedBox.shrink()),
        null,
      );
    }
    MdLineDisplay? display;
    Widget content;
    Widget box(Widget child, {int? lastLineId}) => MdLineBox(
      state: _paint,
      lineId: id,
      lastLineId: lastLineId,
      offsets: MdOffsets.plain(0),
      fontSize: fontSize,
      isText: false,
      child: child,
    );

    if (key.$8 != null) {
      // A table, a formula: its widget, its lines' rows empty.
      final (_, last) = controller.blockOf(index);
      final embed = MdBlockEmbed(
        controller: controller,
        lineId: id,
        kind: info.kind,
        language: info.language,
        source: key.$8!,
        style: lineStyle,
        onEdit: () => _editBlock(id),
      );
      content = box(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child:
              widget.embeds.block(context, embed, style) ??
              Text(embed.source, style: lineStyle),
        ),
        lastLineId: controller.lines.idOf(last),
      );
    } else if (!inBlock && info.kind == MdLineKind.rule) {
      content = box(
        SizedBox(
          height: lineHeight,
          child: Center(child: widget.embeds.rule(context, style)),
        ),
      );
    } else if (!inBlock &&
        (info.kind == MdLineKind.fenceOpen ||
            info.kind == MdLineKind.fenceClose)) {
      content = box(const SizedBox(width: double.infinity));
    } else {
      display = _display(index, id, key);
      content = MdLineBox(
        state: _paint,
        lineId: id,
        offsets: display.offsets,
        fontSize: fontSize,
        child: RichText(
          text: display.span,
          textDirection: _direction ?? TextDirection.ltr,
          textAlign: widget.textAlign,
          textScaler: scaler,
          softWrap: true,
        ),
      );
    }

    // An item's bullet, number or box before its text.
    if (info.kind == MdLineKind.item) {
      final text = controller.lines.content(index);
      final Widget leading;
      if (info.task > 0) {
        leading = Align(
          alignment: Alignment.centerLeft,
          child: widget.embeds.checkbox(
            context,
            info.task == 2,
            lineStyle,
            widget.readOnly ? null : (_) => _toggleTask(id),
          ),
        );
      } else if (info.ordered) {
        leading = Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Align(
            alignment: Alignment.centerRight,
            child: widget.embeds.number(
              context,
              text.substring(info.markerStart, info.markerEnd),
              lineStyle,
            ),
          ),
        );
      } else {
        leading = Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: widget.embeds.bullet(context, info.level, lineStyle),
          ),
        );
      }
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: style.bulletWidth,
            height: lineHeight,
            child: leading,
          ),
          Expanded(child: content),
        ],
      );
    }

    // A code block's slice of its box.
    final top = key.$5;
    final bottom = key.$6;
    if ((info.isFence || info.kind == MdLineKind.indentedCode) &&
        key.$8 == null) {
      final padding = style.codeBlockPadding;
      content = CustomPaint(
        painter: _CodeBoxPainter(
          top: top,
          bottom: bottom,
          color: style.codeBlockBackground,
          border: style.codeBlockBorder,
          radius: style.codeBlockRadius,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            top ? padding.top : 0,
            padding.right,
            bottom ? padding.bottom : 0,
          ),
          child: content,
        ),
      );
      content = Padding(
        padding: EdgeInsets.only(top: top ? 4 : 0, bottom: bottom ? 4 : 0),
        child: content,
      );
    }

    // In a list: as far in as its item's text.
    final level = info.kind == MdLineKind.item
        ? info.level
        : (info.kind == MdLineKind.paragraph || info.isFence) && info.level > 0
        ? info.level - 1
        : -1;
    var indent = 0.0;
    if (level >= 0) {
      indent = level * style.listIndent;
      if (info.kind != MdLineKind.item) indent += style.bulletWidth;
    }
    if (indent > 0) {
      content = Padding(
        padding: EdgeInsets.only(left: indent),
        child: content,
      );
    }

    if (info.quoteDepth > 0) {
      final step = style.quoteBarWidth + style.quoteIndent;
      content = CustomPaint(
        painter: _QuoteBarsPainter(
          depth: info.quoteDepth,
          color: style.quoteBar,
          width: style.quoteBarWidth,
          step: step,
        ),
        child: Padding(
          padding: EdgeInsets.only(left: info.quoteDepth * step),
          child: content,
        ),
      );
    }

    if (info.kind == MdLineKind.heading) {
      if (style.headingRule case final rule? when info.level <= 2) {
        content = Container(
          padding: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: rule)),
          ),
          child: content,
        );
      }
      final (above, below) = style.headingSpace(info.level);
      if (above > 0 || below > 0) {
        content = Padding(
          padding: EdgeInsets.only(top: above, bottom: below),
          child: content,
        );
      }
    }
    return (KeyedSubtree(key: ValueKey(id), child: content), display);
  }

  int? _indexOfKey(Key key) {
    if (key is! ValueKey<int>) return null;
    final index = controller.lines.indexOfId(key.value);
    return index < 0 ? null : index;
  }

  void _toggleTask(int id) {
    final line = controller.lines.indexOfId(id);
    if (line < 0) return;
    controller.toggleTask(line);
  }

  /// The caret put at the start of the block [id] is the first line of,
  /// its markdown shown to be edited.
  void _editBlock(int id) {
    final line = controller.lines.indexOfId(id);
    if (line < 0 || widget.readOnly) return;
    _focus.requestFocus();
    controller.selection = TextSelection.collapsed(
      offset: controller.lineStart(line),
    );
  }

  // --- Code's colors --------------------------------------------------------------

  /// Spans by `language\0line`.
  final Map<String, List<InlineSpan>> _highlighted = {};
  final Set<int> _toColor = {};
  Timer? _colorTimer;

  List<InlineSpan>? _codeSpans(int index, MdLineInfo info) {
    final language = info.language;
    if (widget.colorize == null || language == null || language.isEmpty) {
      return null;
    }
    final code = controller.lines
        .content(index)
        .substring(
          info.contentStart.clamp(0, controller.lines.content(index).length),
        );
    final spans = _highlighted['$language\u0000$code'];
    if (spans != null) return spans;
    final (first, _) = controller.blockOf(index);
    _toColor.add(controller.lines.idOf(first));
    _colorTimer ??= Timer(const Duration(milliseconds: 120), _colorNow);
    return null;
  }

  Future<void> _colorNow() async {
    _colorTimer = null;
    final ids = {..._toColor};
    _toColor.clear();
    final colorize = widget.colorize;
    if (colorize == null) return;
    if (_highlighted.length > 4000) _highlighted.clear();
    var colored = false;
    for (final id in ids) {
      final index = controller.lines.indexOfId(id);
      if (index < 0) continue;
      final (first, last) = controller.blockOf(index);
      final language = controller.infoOf(first).language;
      if (language == null || language.isEmpty) continue;
      final codes = <String>[];
      for (var i = first; i <= last; i++) {
        final info = controller.infoOf(i);
        if (info.kind != MdLineKind.fence) continue;
        final text = controller.lines.content(i);
        codes.add(text.substring(info.contentStart.clamp(0, text.length)));
      }
      if (codes.isEmpty) continue;
      final result = await colorize(language, codes.join('\n'));
      if (!mounted) return;
      for (var i = 0; i < codes.length; i++) {
        final code = codes[i];
        var spans = result != null && i < result.length ? result[i] : null;
        if (spans != null &&
            TextSpan(children: spans)
                    .toPlainText(includeSemanticsLabels: false) !=
                code) {
          spans = null;
        }
        _highlighted['$language\u0000$code'] = spans ?? [TextSpan(text: code)];
      }
      colored = true;
    }
    if (colored && mounted) setState(() {});
  }

  // --- Where things are -----------------------------------------------------------

  final ListController _list = ListController();

  /// How tall line [index] is, before it is laid out: its text's lines at
  /// about a character's width each.
  double _estimate(int? index, double width) {
    final style = widget.style.text;
    final fontSize = style.fontSize ?? 14;
    final lineHeight = fontSize * (style.height ?? 1.2);
    if (index == null || index >= controller.lines.lineCount) {
      return lineHeight;
    }
    final length = controller.lines.content(index).length;
    final perLine = math.max(1.0, width / (fontSize * 0.6));
    return lineHeight * math.max(1, (length / perLine).ceil());
  }

  RenderMdLine? _boxOf(int line) {
    final box = _paint.boxes[controller.lines.idOf(line)];
    return box != null && box.attached && box.hasSize ? box : null;
  }

  /// The offset of the text at [global] (the nearest line's, nearest
  /// character's): of the lines below it only where [down], above it
  /// where not.
  int? offsetAt(Offset global, {bool? down}) {
    RenderMdLine? best;
    var bestDistance = double.infinity;
    for (final box in _paint.boxes.values) {
      if (!box.attached || !box.hasSize || box.size.height <= 0) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (down == true && top < global.dy - 0.5) continue;
      if (down == false && bottom > global.dy + 0.5) continue;
      final distance = global.dy < top
          ? top - global.dy
          : global.dy >= bottom
          ? global.dy - bottom + 0.01
          : 0.0;
      if (distance < bestDistance) {
        best = box;
        bestDistance = distance;
        if (distance == 0) break;
      }
    }
    if (best == null) return null;
    final line = controller.lines.indexOfId(best.lineId);
    if (line < 0) return null;
    final start = controller.lineStart(line);
    final local = best.globalToLocal(global);
    if (best.paragraph == null) {
      // A block shown as one thing (a table, a formula): before it in its
      // upper half, after it in its lower.
      final last = best.lastLineId == null
          ? line
          : controller.lines.indexOfId(best.lastLineId!);
      return local.dy > best.size.height / 2 && last >= line
          ? controller.lineEnd(last)
          : start;
    }
    final clamped = Offset(
      local.dx,
      local.dy.clamp(0, math.max(0, best.size.height - 0.5)),
    );
    final column = best.columnAt(clamped);
    return start + column.clamp(0, controller.lines.content(line).length);
  }

  /// The caret's box at [offset] (the selection's end by default) on the
  /// screen; null where its line is not laid out.
  Rect? caretRect([int? offset]) {
    offset ??= controller.selection.extentOffset;
    if (offset < 0) return null;
    final line = controller.lineAt(offset.clamp(0, controller.length));
    final box = _boxOf(line);
    if (box == null) return null;
    final rect = box.caretRect(offset - controller.lineStart(line));
    return MatrixUtils.transformRect(box.getTransformTo(null), rect);
  }

  /// The boxes [selection] is laid out in, on the screen (of the lines
  /// that are).
  List<Rect> selectionRects(TextSelection selection) {
    if (!selection.isValid) return const [];
    final rects = <Rect>[];
    final first = controller.lineAt(selection.start);
    final last = controller.lineAt(selection.end);
    for (var line = first; line <= last; line++) {
      final box = _boxOf(line);
      if (box == null) continue;
      final start = controller.lineStart(line);
      final from = math.max(selection.start - start, 0);
      final to = math.min(
        selection.end - start,
        controller.lines.content(line).length,
      );
      final transform = box.getTransformTo(null);
      for (final rect in box.rectsFor(from, to)) {
        rects.add(MatrixUtils.transformRect(transform, rect));
      }
    }
    return rects;
  }

  RenderBox? get _viewport {
    final box = _scrollKey.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// The scrolled view's box on the screen.
  Rect? get viewportRect {
    final viewport = _viewport;
    if (viewport == null) return null;
    return viewport.localToGlobal(Offset.zero) & viewport.size;
  }

  // --- Keeping the caret in view ---------------------------------------------------

  bool _showCaretScheduled = false;

  void _showCaretSoon() {
    if (_showCaretScheduled || !_focus.hasPrimaryFocus) return;
    _showCaretScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showCaretScheduled = false;
      if (!mounted) return;
      final selection = controller.selection;
      if (selection.isValid) ensureVisible(selection.extentOffset);
    });
  }

  /// Scrolled to [offset] where it is out of view: to its line's estimated
  /// place where it is not laid out, then to it once it is.
  void ensureVisible(int offset, {int tries = 3}) {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final viewport = _viewport;
    if (viewport == null) return;
    offset = offset.clamp(0, controller.length);
    final line = controller.lineAt(offset);
    final box = _boxOf(line);
    if (box != null) {
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(viewport),
        _lineRect(box, offset - controller.lineStart(line)),
      );
      const margin = 8.0;
      final height = viewport.size.height;
      var target = position.pixels;
      if (rect.top < margin) {
        target += rect.top - margin;
      } else if (rect.bottom > height - margin) {
        target += math.min(rect.bottom - height + margin, rect.top - margin);
      }
      target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if (target != position.pixels) position.jumpTo(target);
      return;
    }
    if (tries <= 0) return;
    // Not laid out: about where it is, then exactly.
    if (_list.isAttached) {
      _list.jumpToItem(
        index: line,
        scrollController: scrollController,
        alignment: 0.5,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureVisible(offset, tries: tries - 1);
    });
  }

  /// The first line in view; null before the lines are laid out.
  int? get firstVisibleLine {
    if (!_list.isAttached) return null;
    return _list.visibleRange?.$1;
  }

  /// Scrolled to [line], at the top of the view ([alignment] 0) or as far
  /// down it as [alignment] says.
  void revealLine(int line, {double alignment = 0}) {
    if (!_list.isAttached || !scrollController.hasClients) return;
    _list.jumpToItem(
      index: line.clamp(0, controller.lines.lineCount - 1),
      scrollController: scrollController,
      alignment: alignment,
    );
  }

  /// The line box (a wrapped line's) [column] is in, in [box]'s.
  Rect _lineRect(RenderMdLine box, int column) {
    final paragraph = box.paragraph;
    if (paragraph == null) return Offset.zero & box.size;
    final caret = box.caretRect(column);
    final position = TextPosition(offset: box.offsets.toShown(column));
    final height = paragraph.getFullHeightForCaret(position);
    return Rect.fromLTWH(
      caret.left,
      caret.center.dy - height / 2,
      caret.width,
      height,
    );
  }

  // --- Pointer --------------------------------------------------------------------

  /// A click's or drag's selecting (the caret not scrolled to as it moves).
  bool _pointerSelecting = false;

  /// Where a click put the caret: a double click's word is that one's.
  int? _tapOffset;

  /// Where the last click went down (the window's), and the recognizer's
  /// count of the click its run of clicks started with, less one.
  Offset? _tapAt;
  int _tapCountFrom = 0;

  /// How far a click may be from the one before it to make it a double
  /// click: the recognizer's own is wide enough to take one on the next
  /// line, a word away, for one.
  static const _doubleClickSlop = 6.0;

  /// What a drag keeps selected from: a click's offset, a word's ends.
  TextSelection _dragFrom = const TextSelection.collapsed(offset: 0);
  int _tapCount = 1;
  Offset? _dragAt;

  /// A pointer an embed (a chip with its own taps) took.
  int? _claimed;

  /// The editor leaves pointer [pointer] (down on a widget of its own) to
  /// it.
  void claimPointer(int pointer) => _claimed = pointer;

  bool _allows(PointerDownEvent event) => event.pointer != _claimed;

  void _tapDown(TapDragDownDetails details) {
    if (!_focus.hasPrimaryFocus) _focus.requestFocus();
    final counted = details.consecutiveTapCount;
    final last = _tapAt;
    _tapAt = details.globalPosition;
    if (counted == 1 ||
        last == null ||
        (details.globalPosition - last).distance > _doubleClickSlop) {
      _tapCountFrom = counted - 1;
    }
    final count = counted - _tapCountFrom;
    _tapCount = count;
    final at = count > 1 && _tapOffset != null
        ? _tapOffset!
        : offsetAt(details.globalPosition);
    if (at == null) return;
    _pointerSelecting = true;
    final selection = controller.selection;
    if (count == 1) {
      _tapOffset = at;
      if (!HardwareKeyboard.instance.isShiftPressed &&
          (widget.onClick?.call(at) ?? false)) {
        _pointerSelecting = false;
        _tapOffset = null;
        _clickTaken = true;
        return;
      }
      if (HardwareKeyboard.instance.isShiftPressed && selection.isValid) {
        _dragFrom = TextSelection.collapsed(offset: selection.baseOffset);
        controller.selection = selection.extendTo(TextPosition(offset: at));
      } else {
        _dragFrom = TextSelection.collapsed(offset: at);
        controller.selection = TextSelection.collapsed(offset: at);
      }
    } else if (count == 2) {
      final (start, end) = _wordAt(at);
      _dragFrom = TextSelection(baseOffset: start, extentOffset: end);
      controller.selection = _dragFrom;
    } else {
      final line = controller.lineAt(at);
      final start = controller.lineStart(line) + controller.textStartOf(line);
      _dragFrom = TextSelection(
        baseOffset: start,
        extentOffset: controller.lineEnd(line),
      );
      controller.selection = _dragFrom;
    }
  }

  void _tapUp(TapDragUpDetails details) {
    _pointerSelecting = false;
    // Taken (a link opened, gone to its heading): the view left where it
    // went, not brought back to the caret.
    if (_clickTaken) {
      _clickTaken = false;
      return;
    }
    _showCaretSoon();
  }

  /// The click going down was taken by [MarkdownEditor.onClick].
  bool _clickTaken = false;

  void _dragStart(TapDragStartDetails details) {
    _pointerSelecting = true;
    _dragAt = details.globalPosition;
  }

  void _dragUpdate(TapDragUpdateDetails details) {
    _dragAt = details.globalPosition;
    _selectTo(details.globalPosition);
    _checkAutoscroll();
  }

  void _dragEnd(TapDragEndDetails details) {
    _pointerSelecting = false;
    _dragAt = null;
    _stopAutoscroll();
  }

  void _dragCancel() {
    _pointerSelecting = false;
    _dragAt = null;
    _stopAutoscroll();
  }

  /// The selection from where the drag started to [global].
  void _selectTo(Offset global) {
    final viewport = viewportRect;
    if (viewport != null) {
      global = Offset(
        global.dx,
        global.dy.clamp(
          viewport.top + 1,
          math.max(viewport.top + 1, viewport.bottom - 1),
        ),
      );
    }
    final at = offsetAt(global);
    if (at == null) return;
    final from = _dragFrom;
    if (_tapCount >= 2 && !from.isCollapsed) {
      // By words (or lines), the first one's kept.
      final (start, end) = _tapCount == 2
          ? _wordAt(at)
          : (
              controller.lineStart(controller.lineAt(at)),
              controller.lineEnd(controller.lineAt(at)),
            );
      controller.selection = at < from.start
          ? TextSelection(baseOffset: from.end, extentOffset: start)
          : TextSelection(
              baseOffset: from.start,
              extentOffset: math.max(end, from.end),
            );
      return;
    }
    controller.selection = TextSelection(
      baseOffset: from.baseOffset,
      extentOffset: at,
    );
  }

  /// The word at [offset] (its line's, as laid out where it is).
  (int, int) _wordAt(int offset) {
    final line = controller.lineAt(offset);
    final start = controller.lineStart(line);
    final column = offset - start;
    final box = _boxOf(line);
    if (box != null && box.paragraph != null) {
      final (from, to) = box.wordAt(column);
      return (start + from, start + math.max(from, to));
    }
    final text = controller.lines.content(line);
    var from = column;
    var to = column;
    bool word(int i) =>
        RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(text[i]);
    while (from > 0 && word(from - 1)) {
      from--;
    }
    while (to < text.length && word(to)) {
      to++;
    }
    return (start + from, start + to);
  }

  // --- Scrolling while a drag is past an edge ---------------------------------------

  Ticker? _autoscroll;
  Duration _lastTick = Duration.zero;

  /// How far past the view's edge the drag is (up negative).
  double _pastEdge() {
    final at = _dragAt;
    final viewport = viewportRect;
    if (at == null || viewport == null) return 0;
    if (at.dy < viewport.top) return at.dy - viewport.top;
    if (at.dy > viewport.bottom) return at.dy - viewport.bottom;
    return 0;
  }

  void _checkAutoscroll() {
    if (_pastEdge() == 0) {
      _stopAutoscroll();
      return;
    }
    final ticker = _autoscroll ??= createTicker(_autoscrollTick);
    if (!ticker.isActive) {
      _lastTick = Duration.zero;
      ticker.start();
    }
  }

  void _stopAutoscroll() {
    if (_autoscroll?.isActive ?? false) _autoscroll!.stop();
  }

  void _autoscrollTick(Duration elapsed) {
    final past = _pastEdge();
    if (past == 0 || !scrollController.hasClients) {
      _stopAutoscroll();
      return;
    }
    final seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (seconds <= 0) return;
    final speed = math.min(4000.0, 300 + 12 * past.abs());
    final position = scrollController.position;
    final target = (position.pixels + speed * seconds * past.sign).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) position.jumpTo(target);
    _selectTo(_dragAt!);
  }

  // --- The keyboard's input ----------------------------------------------------------

  TextInputConnection? _connection;

  /// What the platform was last told of the text: some lines around the
  /// caret's ([_told]).
  TextEditingValue _remote = TextEditingValue.empty;

  /// Those lines as told, each atom one character: where the platform's
  /// offsets are in the text.
  MdTold _told = MdTold.empty;

  /// The selection was too long to tell the platform: it was told of the
  /// caret alone; what it types replaces the selection.
  bool _remoteCaretOnly = false;

  /// The text's offset of [remote], an offset in [_remote].
  int _sourceAt(int remote) => _told.toSource(remote);

  bool get _hasInput => _connection?.attached ?? false;

  void _openInput() {
    if (widget.readOnly || _hasInput) return;
    final connection = _connection = TextInput.attach(
      this,
      TextInputConfiguration(
        // Windows takes no client without the view it types into.
        viewId: View.of(context).viewId,
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        enableDeltaModel: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardAppearance: widget.keyboardAppearance,
        textCapitalization: TextCapitalization.none,
      ),
    );
    _remote = _windowValue();
    connection
      ..show()
      ..setEditingState(_remote);
    _imeGeometrySoon();
  }

  void _closeInput() {
    _connection?.close();
    _connection = null;
    if (controller.isComposing) controller.composing = TextRange.empty;
  }

  /// The lines around the selection, as the platform is told of them.
  TextEditingValue _windowValue() {
    final selection = controller.selection;
    if (!selection.isValid) {
      _told = MdTold.empty;
      _remoteCaretOnly = false;
      return TextEditingValue.empty;
    }
    final lines = controller.lines;
    var first = math.max(0, controller.lineAt(selection.start) - 1);
    var last = math.min(
      lines.lineCount - 1,
      controller.lineAt(selection.end) + 1,
    );
    var start = lines.lineStart(first);
    var end = lines.lineEnd(last);
    var told = _tell(start, end);
    _remoteCaretOnly = false;
    if (told.text.length > 4000) {
      final line = controller.lineAt(selection.extentOffset);
      first = last = line;
      start = lines.lineStart(line);
      end = lines.lineEnd(line);
      told = _tell(start, end);
      _remoteCaretOnly = !selection.isCollapsed;
    }
    _told = told;
    final text = told.text;

    TextSelection remoteSelection;
    if (_remoteCaretOnly) {
      remoteSelection = TextSelection.collapsed(
        offset: told.toTold(selection.extentOffset),
      );
    } else {
      remoteSelection = TextSelection(
        baseOffset: told.toTold(selection.baseOffset),
        extentOffset: told.toTold(selection.extentOffset),
        affinity: selection.affinity,
      );
    }
    final composing = controller.composing;
    return TextEditingValue(
      text: text,
      selection: remoteSelection,
      composing:
          controller.isComposing &&
              composing.start >= start &&
              composing.end <= end
          ? TextRange(
              start: told.toTold(composing.start),
              end: told.toTold(composing.end),
            )
          : TextRange.empty,
    );
  }

  /// [start] to [end] of the text as the platform is told of it.
  MdTold _tell(int start, int end) =>
      MdTold.of(controller.substring(start, end), start: start);

  /// Tells the platform of the text where it differs from what it has.
  void _syncRemote() {
    if (!_hasInput || _applyingRemote) return;
    final start = _told.start;
    final value = _windowValue();
    if (start == _told.start && _sameAsRemote(value)) return;
    _remote = value;
    _connection!.setEditingState(value);
  }

  /// Whether [value] is what the platform has: a composing region of no
  /// length (Windows starts composing with one) is none. Told it again as
  /// it composes, Windows ends what it composes, and what it composes next
  /// goes in before it, not over it.
  bool _sameAsRemote(TextEditingValue value) {
    bool none(TextRange range) => !range.isValid || range.isCollapsed;
    return value.text == _remote.text &&
        value.selection == _remote.selection &&
        (value.composing == _remote.composing ||
            (none(value.composing) && none(_remote.composing)));
  }

  bool _applyingRemote = false;

  @override
  TextEditingValue? get currentTextEditingValue => _remote;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    for (final delta in deltas) {
      _applyDelta(_composedOverSelection(delta));
    }
    _syncRemote();
  }

  /// [delta] as what the platform did. Windows' engine (Linux's too),
  /// composing over a selection, deletes the selection but tells of what
  /// it composes as put in where the selection starts: the selection
  /// stayed after it, and the text was out of step with the platform's.
  TextEditingDelta _composedOverSelection(TextEditingDelta delta) {
    final selection = _remote.selection;
    final composing = delta.composing;
    if (!selection.isValid ||
        selection.isCollapsed ||
        !composing.isValid ||
        composing.isCollapsed ||
        delta.oldText != _remote.text) {
      return delta;
    }
    final (int at, int end, String text) = switch (delta) {
      TextEditingDeltaInsertion() => (
        delta.insertionOffset,
        delta.insertionOffset,
        delta.textInserted,
      ),
      TextEditingDeltaReplacement() => (
        delta.replacedRange.start,
        delta.replacedRange.end,
        delta.replacementText,
      ),
      _ => (-1, -1, ''),
    };
    if (at != selection.start ||
        end != at ||
        composing.start != at ||
        composing.end != at + text.length) {
      return delta;
    }
    return TextEditingDeltaReplacement(
      oldText: delta.oldText,
      replacementText: text,
      replacedRange: TextRange(start: selection.start, end: selection.end),
      selection: delta.selection,
      composing: composing,
    );
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    // Not as deltas: what changed is where the old and new differ.
    final old = _remote.text;
    final text = value.text;
    if (old == text) {
      _applyDelta(
        TextEditingDeltaNonTextUpdate(
          oldText: old,
          selection: value.selection,
          composing: value.composing,
        ),
      );
    } else {
      var prefix = 0;
      final shortest = math.min(old.length, text.length);
      while (prefix < shortest &&
          old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
        prefix++;
      }
      var suffix = 0;
      while (suffix < shortest - prefix &&
          old.codeUnitAt(old.length - 1 - suffix) ==
              text.codeUnitAt(text.length - 1 - suffix)) {
        suffix++;
      }
      _applyDelta(
        TextEditingDeltaReplacement(
          oldText: old,
          replacementText: text.substring(prefix, text.length - suffix),
          replacedRange: TextRange(start: prefix, end: old.length - suffix),
          selection: value.selection,
          composing: value.composing,
        ),
      );
    }
    _syncRemote();
  }

  void _applyDelta(TextEditingDelta delta) {
    if (widget.readOnly) return;
    var (int start, int end, String text) = switch (delta) {
      TextEditingDeltaInsertion() => (
        delta.insertionOffset,
        delta.insertionOffset,
        delta.textInserted,
      ),
      TextEditingDeltaDeletion() => (
        delta.deletedRange.start,
        delta.deletedRange.end,
        '',
      ),
      TextEditingDeltaReplacement() => (
        delta.replacedRange.start,
        delta.replacedRange.end,
        delta.replacementText,
      ),
      _ => (-1, -1, ''),
    };
    final old = _remote.text;
    if (start >= 0 &&
        end > start &&
        end <= old.length &&
        text.contains(MdAtoms.shown)) {
      // An input method that shows a suggestion after the caret as it
      // composes (an inline emoji) replaces from before what it composes,
      // the atoms there given back as the character they were told as:
      // what it gives back as it was is left be.
      (start, end, text) = _trimmed(old, start, end, text);
    }
    final told = text;
    final clean = MdAtoms.strip(text.replaceAll(MdAtoms.shown, ''));
    final cleaned = clean.length != text.length;
    text = clean;
    final sourceStart = start < 0 ? -1 : _sourceAt(start);
    final sourceEnd = start < 0 ? -1 : _sourceAt(end);
    try {
      _remote = delta.apply(_remote);
    } catch (_) {
      // Out of step with the platform: told again below.
    }
    if (start >= 0) _told = _told.edited(start, end, told);
    TextSelection selection(TextSelection remote) => cleaned
        ? TextSelection.collapsed(offset: sourceStart + text.length)
        : TextSelection(
            baseOffset: _sourceAt(remote.baseOffset),
            extentOffset: _sourceAt(remote.extentOffset),
            affinity: remote.affinity,
          );
    TextRange composing(TextRange remote) =>
        !cleaned && remote.isValid && !remote.isCollapsed
        ? TextRange(start: _sourceAt(remote.start), end: _sourceAt(remote.end))
        : TextRange.empty;
    _applyingRemote = true;
    try {
      if (start < 0) {
        controller.selection = selection(delta.selection);
        controller.composing = composing(delta.composing);
        return;
      }
      // Enter, typed as a line's end (on a phone's keyboard).
      if (text == '\n' &&
          start == end &&
          !delta.composing.isValid &&
          !controller.isComposing) {
        _applyingRemote = false;
        _enter();
        return;
      }
      final current = controller.selection;
      if (_remoteCaretOnly && !current.isCollapsed) {
        // The platform knew of the caret only: the selection is what is
        // typed over.
        controller.replace(
          current.start,
          current.end,
          text,
          kind: text.isEmpty ? MdEditKind.deleting : MdEditKind.typing,
          composing:
              !cleaned &&
                  delta.composing.isValid &&
                  !delta.composing.isCollapsed
              ? TextRange(
                  start: current.start + delta.composing.start - start,
                  end: current.start + delta.composing.end - start,
                )
              : TextRange.empty,
        );
        return;
      }
      controller.replace(
        sourceStart,
        sourceEnd,
        text,
        selection: selection(delta.selection),
        kind: text.isEmpty ? MdEditKind.deleting : MdEditKind.typing,
        composing: composing(delta.composing),
      );
      if (text == ' ' && !controller.isComposing) controller.expandTyped();
    } finally {
      _applyingRemote = false;
    }
  }

  /// [start] to [end] of [old] replaced by [text], less what it leaves as
  /// it was at either end (not between a surrogate pair's halves).
  static (int, int, String) _trimmed(
    String old,
    int start,
    int end,
    String text,
  ) {
    final replaced = old.substring(start, end);
    final shorter = math.min(replaced.length, text.length);
    var head = 0;
    while (head < shorter &&
        replaced.codeUnitAt(head) == text.codeUnitAt(head)) {
      head++;
    }
    if (head > 0 && _isLead(replaced.codeUnitAt(head - 1))) head--;
    var tail = 0;
    while (tail < shorter - head &&
        replaced.codeUnitAt(replaced.length - 1 - tail) ==
            text.codeUnitAt(text.length - 1 - tail)) {
      tail++;
    }
    if (tail > 0 && _isTrail(replaced.codeUnitAt(replaced.length - tail))) {
      tail--;
    }
    return (start + head, end - tail, text.substring(head, text.length - tail));
  }

  static bool _isLead(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  static bool _isTrail(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) _enter();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
    if (controller.isComposing) controller.composing = TextRange.empty;
  }

  @override
  void performSelector(String selectorName) {
    final intent = intentForMacOSSelector(selectorName);
    final context = _focus.context;
    if (intent != null && context != null) Actions.invoke(context, intent);
  }

  bool _imeGeometryScheduled = false;

  /// The platform told where the text and the caret are, for its input
  /// method's window to be by them.
  void _imeGeometrySoon() {
    if (_imeGeometryScheduled || !_hasInput) return;
    _imeGeometryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _imeGeometryScheduled = false;
      if (!mounted || !_hasInput) return;
      final editor = context.findRenderObject();
      if (editor is! RenderBox || !editor.hasSize) return;
      final connection = _connection!;
      connection.setEditableSizeAndTransform(
        editor.size,
        editor.getTransformTo(null),
      );
      final selection = controller.selection;
      if (!selection.isValid) return;
      final line = controller.lineAt(selection.extentOffset);
      final box = _boxOf(line);
      if (box == null) return;
      final transform = box.getTransformTo(editor);
      final start = controller.lineStart(line);
      final caret = MatrixUtils.transformRect(
        transform,
        box.caretRect(selection.extentOffset - start),
      );
      connection.setCaretRect(caret);
      final composing = controller.composing;
      if (controller.isComposing &&
          controller.lineAt(composing.start) == line) {
        final rects = box.rectsFor(
          composing.start - start,
          math.min(
            composing.end - start,
            controller.lines.content(line).length,
          ),
        );
        connection.setComposingRect(
          rects.isEmpty
              ? caret
              : MatrixUtils.transformRect(transform, rects.first),
        );
      } else {
        connection.setComposingRect(caret);
      }
    });
  }

  // --- Keys --------------------------------------------------------------------------

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    // Not one for a widget in it with the keyboard (a table's cell).
    if (!_focus.hasPrimaryFocus) return KeyEventResult.ignored;
    final own = widget.onKey?.call(event);
    if (own != null && own != KeyEventResult.ignored) return own;
    if (event is KeyUpEvent || widget.readOnly || controller.isComposing) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final modified =
        keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (modified) return KeyEventResult.ignored;
      _enter(plain: keyboard.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      if (modified) return KeyEventResult.ignored;
      if (keyboard.isShiftPressed) {
        controller.outdent();
      } else if (!controller.indent() &&
          controller
                  .infoOf(controller.lineAt(controller.selection.start))
                  .kind !=
              MdLineKind.item) {
        _insert('\t');
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _enter({bool plain = false}) {
    if (widget.readOnly) return;
    controller.breakUndo();
    controller.insertNewline(plain: plain);
    controller.breakUndo();
  }

  void _insert(String text) {
    final selection = controller.selection;
    if (!selection.isValid || widget.readOnly) return;
    controller.replace(selection.start, selection.end, text);
  }

  // --- Moving the caret ------------------------------------------------------------

  /// A vertical move's x, kept while moving up and down.
  double? _verticalX;
  bool _verticalMove = false;

  void _select(TextSelection selection) {
    controller.selection = selection;
  }

  /// [offset] the caret's (the selection's end's, [extend]ing it).
  void _moveTo(int offset, {required bool extend}) {
    final selection = controller.selection;
    offset = offset.clamp(0, controller.length);
    _select(
      extend && selection.isValid
          ? selection.extendTo(TextPosition(offset: offset))
          : TextSelection.collapsed(offset: offset),
    );
  }

  /// The offset a character on from [offset] (as the line shows).
  int _nextCharacter(int offset, bool forward) {
    final line = controller.lineAt(offset);
    final start = controller.lineStart(line);
    final display = _displayOf(line);
    final offsets = display.offsets;
    final shown = offsets.toShown(offset - start);
    final text = display.span.toPlainText(includeSemanticsLabels: false);
    final end = _shownEnd(offsets);
    if (forward) {
      if (shown >= end) {
        if (line + 1 >= controller.lines.lineCount) return offset;
        return controller.lineStart(line + 1) +
            _displayOf(line + 1).offsets.toSource(0);
      }
      final range = CharacterRange.at(text, shown)..moveNext();
      final next = shown + range.current.length;
      final column = next >= end
          ? offsets.sourceLength
          : offsets.toSource(next);
      return start +
          math.max(column, offset - start + 1).clamp(0, offsets.sourceLength);
    }
    if (shown <= 0) {
      if (line == 0) return offset;
      return controller.lineEnd(line - 1);
    }
    final range = CharacterRange.at(text, shown)..moveBack();
    final previous = shown - range.current.length;
    final column = offsets.toSource(previous);
    return start +
        math.min(column, offset - start - 1).clamp(0, offsets.sourceLength);
  }

  /// Where a line's shown text ends (before what only shows after it).
  static int _shownEnd(MdOffsets offsets) =>
      offsets.toShown(offsets.sourceLength);

  /// The offset a word on from [offset].
  int _nextWord(int offset, bool forward) {
    final line = controller.lineAt(offset);
    final start = controller.lineStart(line);
    final display = _displayOf(line);
    final offsets = display.offsets;
    final text = display.span.toPlainText(includeSemanticsLabels: false);
    final end = _shownEnd(offsets);
    var shown = offsets.toShown(offset - start);
    final box = _boxOf(line);
    TextRange wordAt(int at) {
      final paragraph = box?.paragraph;
      if (paragraph != null) {
        return paragraph.getWordBoundary(TextPosition(offset: at));
      }
      var from = at;
      var to = at;
      bool word(int i) =>
          RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(text[i]);
      if (at < text.length && word(at)) {
        while (from > 0 && word(from - 1)) {
          from--;
        }
        while (to < text.length && word(to)) {
          to++;
        }
      } else {
        to = math.min(text.length, at + 1);
      }
      return TextRange(start: from, end: to);
    }

    bool blank(int from, int to) => text.substring(from, to).trim().isEmpty;
    if (forward) {
      if (shown >= end) return _nextCharacter(offset, true);
      while (shown < end) {
        final range = wordAt(shown);
        if (range.end > shown && !blank(shown, math.min(range.end, end))) {
          final to = math.min(range.end, end);
          return start +
              (to >= end ? offsets.sourceLength : offsets.toSource(to));
        }
        shown = math.max(range.end, shown + 1);
      }
      return start + offsets.sourceLength;
    }
    if (shown <= 0) return _nextCharacter(offset, false);
    while (shown > 0) {
      final range = wordAt(shown - 1);
      if (range.start < shown && !blank(range.start, shown)) {
        return start + offsets.toSource(range.start);
      }
      shown = math.min(range.start, shown - 1);
    }
    return start + offsets.toSource(0);
  }

  /// The ends of the line (as laid out, wrapped) [offset] is on.
  (int, int) _visualLine(int offset) {
    final line = controller.lineAt(offset);
    final start = controller.lineStart(line);
    final box = _boxOf(line);
    if (box != null && box.paragraph != null) {
      final (from, to) = box.visualLineAt(
        offset - start,
        affinity: controller.selection.affinity,
      );
      return (start + from, start + to);
    }
    return (start + controller.textStartOf(line), controller.lineEnd(line));
  }

  /// The offset a line up or down from [offset] (as laid out), as near the
  /// x the moving started at as there is.
  int _nextLine(int offset, bool forward) {
    final line = controller.lineAt(offset);
    final box = _boxOf(line);
    final start = controller.lineStart(line);
    if (box == null) {
      final target = line + (forward ? 1 : -1);
      if (target < 0) return 0;
      if (target >= controller.lines.lineCount) return controller.length;
      final column = offset - start;
      return controller.lineStart(target) +
          column.clamp(
            controller.textStartOf(target),
            controller.lines.content(target).length,
          );
    }
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      _lineRect(box, offset - start),
    );
    final x = _verticalX ??= rect.center.dx;
    final y = forward ? rect.bottom + 0.5 : rect.top - 0.5;
    final found = offsetAt(Offset(x, y), down: forward);
    if (found == null) return forward ? controller.length : 0;
    // Nothing laid out past it: to the first line's start, the last's
    // end.
    if (forward ? found < offset : found > offset) {
      return forward ? controller.length : 0;
    }
    if (found == offset) return forward ? controller.length : 0;
    return found;
  }

  void _vertical(bool forward, {required bool extend, bool page = false}) {
    final selection = controller.selection;
    if (!selection.isValid) return;
    if (!extend && !selection.isCollapsed && !page) {
      _moveTo(forward ? selection.end : selection.start, extend: false);
      return;
    }
    _verticalMove = true;
    try {
      var offset = selection.extentOffset;
      if (page) {
        final height = _viewport?.size.height ?? 400;
        final lineHeight =
            (widget.style.text.fontSize ?? 14) *
            (widget.style.text.height ?? 1.2);
        final count = math.max(1, (height / lineHeight).floor() - 1);
        final line = controller.lineAt(offset);
        final target = (line + (forward ? count : -count)).clamp(
          0,
          controller.lines.lineCount - 1,
        );
        offset =
            controller.lineStart(target) +
            (offset - controller.lineStart(line)).clamp(
              controller.textStartOf(target),
              controller.lines.content(target).length,
            );
      } else {
        offset = _nextLine(offset, forward);
      }
      _moveTo(offset, extend: extend);
    } finally {
      _verticalMove = false;
    }
  }

  // --- Copying and pasting ------------------------------------------------------------

  /// [start] to [end] as text: what it shows, a picture as its embeds'
  /// [MarkdownEmbeds.plainText].
  String plainText(int start, int end) {
    if (start >= end) return '';
    final first = controller.lineAt(start);
    final last = controller.lineAt(end);
    final parts = <String>[];
    for (var line = first; line <= last; line++) {
      final info = controller.infoOf(line);
      final content = controller.lines.content(line);
      final lineStart = controller.lineStart(line);
      final from = math.max(start - lineStart, 0);
      final to = math.min(end - lineStart, content.length);
      if (first != last &&
          (info.kind == MdLineKind.fenceOpen ||
              info.kind == MdLineKind.fenceClose ||
              info.kind == MdLineKind.setextUnderline)) {
        continue;
      }
      if (!info.hasInline) {
        final textStart = info.isFence ? info.contentStart : 0;
        parts.add(
          content.substring(math.min(math.max(from, textStart), to), to),
        );
        continue;
      }
      final display = buildLineDisplay(
        content,
        info,
        controller.inlinesOf(line),
        style: widget.style,
        isAtomic: (run) => widget.embeds.isAtomic(run, content),
        atomic: (run, _) =>
            TextSpan(text: widget.embeds.plainText(run, content)),
      );
      final shown = display.span.toPlainText(includeSemanticsLabels: false);
      final a = display.offsets.toShown(from);
      final b = to >= content.length
          ? _shownEnd(display.offsets)
          : display.offsets.toShown(to);
      parts.add(shown.substring(a, math.max(a, b)).replaceAll('\u200B', ''));
    }
    return parts.join('\n');
  }

  /// The selection copied (cut, where [cut]): as text, and as its markdown
  /// for an editor of its kind to paste (see [MdClipboard]).
  Future<void> copy({bool cut = false}) async {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final clip = MdClip(
      plain: plainText(selection.start, selection.end),
      markdown: controller.substring(selection.start, selection.end),
      fromPlain: controller.plain,
    );
    if (cut && !widget.readOnly) {
      controller.replace(selection.start, selection.end, '');
    }
    await MdClipboard.instance.write(clip);
  }

  /// What the clipboard has, put in place of the selection: an editor's
  /// copy of its kind as its markdown, else [MarkdownEditor.onPaste]'s or
  /// the text.
  Future<void> paste() async {
    if (widget.readOnly) return;
    final (:text, :clip) = await MdClipboard.instance.read();
    if (!mounted) return;
    if (clip != null && clip.fromPlain == controller.plain) {
      insertText(widget.onPasteCopy?.call(clip.markdown) ?? clip.markdown);
      return;
    }
    if (widget.onPaste != null && await widget.onPaste!()) return;
    if (!mounted || text == null || text.isEmpty) return;
    insertText(MdAtoms.strip(text));
  }

  /// [text] in place of the selection (its line ends the text's), the
  /// caret after it.
  void insertText(String text) {
    final selection = controller.selection;
    if (!selection.isValid) return;
    text = text.replaceAll('\r\n', '\n');
    if (controller.lines.newline != '\n') {
      text = text.replaceAll('\n', controller.lines.newline);
    }
    controller.breakUndo();
    controller.replace(selection.start, selection.end, text);
    controller.breakUndo();
  }

  // --- Actions -----------------------------------------------------------------------

  bool get _editable => !widget.readOnly && !controller.isComposing;
  bool get _movable => !controller.isComposing;

  late final Map<Type, Action<Intent>> _actions = {
    DoNothingAndStopPropagationTextIntent: DoNothingAction(consumesKey: false),
    DeleteCharacterIntent: _Act<DeleteCharacterIntent>(
      (intent) => intent.forward
          ? controller.deleteForward(isAtomic: widget.embeds.isAtomic)
          : controller.deleteBackward(isAtomic: widget.embeds.isAtomic),
      () => _editable,
    ),
    DeleteToNextWordBoundaryIntent: _Act<DeleteToNextWordBoundaryIntent>(
      (intent) => _deleteTo((offset) => _nextWord(offset, intent.forward)),
      () => _editable,
    ),
    DeleteToLineBreakIntent: _Act<DeleteToLineBreakIntent>(
      (intent) => _deleteTo((offset) {
        final (start, end) = _visualLine(offset);
        return intent.forward ? end : start;
      }),
      () => _editable,
    ),
    ExtendSelectionByCharacterIntent: _Act<ExtendSelectionByCharacterIntent>((
      intent,
    ) {
      final selection = controller.selection;
      if (!selection.isValid) return;
      if (intent.collapseSelection && !selection.isCollapsed) {
        _moveTo(
          intent.forward ? selection.end : selection.start,
          extend: false,
        );
        return;
      }
      _moveTo(
        _nextCharacter(selection.extentOffset, intent.forward),
        extend: !intent.collapseSelection,
      );
    }, () => _movable),
    ExtendSelectionToNextWordBoundaryIntent:
        _Act<ExtendSelectionToNextWordBoundaryIntent>(
          (intent) => _moveTo(
            _nextWord(controller.selection.extentOffset, intent.forward),
            extend: !intent.collapseSelection,
          ),
          () => _movable,
        ),
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent:
        _Act<ExtendSelectionToNextWordBoundaryOrCaretLocationIntent>((intent) {
          final selection = controller.selection;
          final next = _nextWord(selection.extentOffset, intent.forward);
          // Not past the selection's other end: to it, first.
          final base = selection.baseOffset;
          final crosses = intent.forward
              ? selection.extentOffset < base && next > base
              : selection.extentOffset > base && next < base;
          _moveTo(crosses ? base : next, extend: true);
        }, () => _movable),
    ExtendSelectionToLineBreakIntent: _Act<ExtendSelectionToLineBreakIntent>((
      intent,
    ) {
      final selection = controller.selection;
      if (!selection.isValid) return;
      final (start, end) = _visualLine(selection.extentOffset);
      _moveTo(intent.forward ? end : start, extend: !intent.collapseSelection);
    }, () => _movable),
    ExpandSelectionToLineBreakIntent: _Act<ExpandSelectionToLineBreakIntent>((
      intent,
    ) {
      final selection = controller.selection;
      if (!selection.isValid) return;
      final (start, end) = _visualLine(selection.extentOffset);
      _select(
        intent.forward
            ? TextSelection(
                baseOffset: math.min(selection.start, selection.baseOffset),
                extentOffset: end,
              )
            : TextSelection(
                baseOffset: math.max(selection.end, selection.baseOffset),
                extentOffset: start,
              ),
      );
    }, () => _movable),
    ExtendSelectionToDocumentBoundaryIntent:
        _Act<ExtendSelectionToDocumentBoundaryIntent>(
          (intent) => _moveTo(
            intent.forward ? controller.length : 0,
            extend: !intent.collapseSelection,
          ),
          () => _movable,
        ),
    ExpandSelectionToDocumentBoundaryIntent:
        _Act<ExpandSelectionToDocumentBoundaryIntent>(
          (intent) =>
              _moveTo(intent.forward ? controller.length : 0, extend: true),
          () => _movable,
        ),
    ExtendSelectionToNextParagraphBoundaryIntent:
        _Act<ExtendSelectionToNextParagraphBoundaryIntent>(
          (intent) => _moveTo(
            _paragraphEdge(controller.selection.extentOffset, intent.forward),
            extend: !intent.collapseSelection,
          ),
          () => _movable,
        ),
    ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent:
        _Act<ExtendSelectionToNextParagraphBoundaryOrCaretLocationIntent>(
          (intent) => _moveTo(
            _paragraphEdge(controller.selection.extentOffset, intent.forward),
            extend: true,
          ),
          () => _movable,
        ),
    ExtendSelectionVerticallyToAdjacentLineIntent:
        _Act<ExtendSelectionVerticallyToAdjacentLineIntent>(
          (intent) =>
              _vertical(intent.forward, extend: !intent.collapseSelection),
          () => _movable,
        ),
    ExtendSelectionVerticallyToAdjacentPageIntent:
        _Act<ExtendSelectionVerticallyToAdjacentPageIntent>(
          (intent) => _vertical(
            intent.forward,
            extend: !intent.collapseSelection,
            page: true,
          ),
          () => _movable,
        ),
    SelectAllTextIntent: _Act<SelectAllTextIntent>(
      (_) => _select(
        TextSelection(baseOffset: 0, extentOffset: controller.length),
      ),
      () => _movable,
    ),
    CopySelectionTextIntent: _Act<CopySelectionTextIntent>(
      (intent) => copy(cut: intent.collapseSelection),
      () => controller.selection.isValid && !controller.selection.isCollapsed,
    ),
    PasteTextIntent: _Act<PasteTextIntent>((_) => paste(), () => _editable),
    UndoTextIntent: _Act<UndoTextIntent>(
      (_) => controller.undo(),
      () => _editable,
    ),
    RedoTextIntent: _Act<RedoTextIntent>(
      (_) => controller.redo(),
      () => _editable,
    ),
  };

  /// A paragraph's (line's) start or end on from [offset].
  int _paragraphEdge(int offset, bool forward) {
    var line = controller.lineAt(offset);
    if (forward) {
      if (offset >= controller.lineEnd(line) &&
          line + 1 < controller.lines.lineCount) {
        line++;
      }
      return controller.lineEnd(line);
    }
    final start = controller.lineStart(line) + controller.textStartOf(line);
    if (offset <= start && line > 0) {
      line--;
      return controller.lineStart(line) + controller.textStartOf(line);
    }
    return start;
  }

  /// From the caret to [to]'s offset deleted (the selection, where there
  /// is one).
  void _deleteTo(int Function(int offset) to) {
    final selection = controller.selection;
    if (!selection.isValid) return;
    if (!selection.isCollapsed) {
      controller.replace(selection.start, selection.end, '');
      return;
    }
    final target = to(selection.extentOffset);
    final start = math.min(target, selection.extentOffset);
    final end = math.max(target, selection.extentOffset);
    if (start == end) return;
    controller.replace(
      start,
      end,
      '',
      selection: TextSelection.collapsed(offset: start),
      kind: MdEditKind.deleting,
    );
  }

  // --- Building ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    _reveal = _computeReveal();
    final lines = controller.lines;
    Widget scroll = CustomScrollView(
      key: _scrollKey,
      controller: scrollController,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      slivers: [
        SliverPadding(
          padding: widget.padding,
          // A jump far off (to the caret, by the scrollbar) lays out the
          // lines it lands on, not all those before them.
          sliver: _KeepTopLine(
            sliver: SuperSliverList(
              listController: _list,
              extentEstimation: _estimate,
              delegate: SliverChildBuilderDelegate(
                _row,
                childCount: lines.lineCount,
                findChildIndexCallback: _indexOfKey,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        ),
      ],
    );
    if (widget.placeholder != null && controller.length == 0) {
      scroll = Stack(
        children: [
          scroll,
          Positioned(
            left: widget.padding.left,
            top: widget.padding.top,
            right: widget.padding.right,
            child: IgnorePointer(
              child: Text(
                widget.placeholder!,
                style: widget.style.text.merge(widget.style.placeholder),
                textScaler: _scaler,
              ),
            ),
          ),
        ],
      );
    }
    return Actions(
      actions: _actions,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _key,
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: {
              _MouseSelect: GestureRecognizerFactoryWithHandlers<_MouseSelect>(
                () => _MouseSelect(_allows),
                (recognizer) => recognizer
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onTapDown = _tapDown
                  ..onTapUp = _tapUp
                  ..onDragStart = _dragStart
                  ..onDragUpdate = _dragUpdate
                  ..onDragEnd = _dragEnd
                  ..onCancel = _dragCancel,
              ),
              _TouchTap: GestureRecognizerFactoryWithHandlers<_TouchTap>(
                () => _TouchTap(_allows),
                (recognizer) => recognizer.onTapUp = (details) {
                  if (!_focus.hasPrimaryFocus) _focus.requestFocus();
                  final at = offsetAt(details.globalPosition);
                  if (at == null || (widget.onClick?.call(at) ?? false)) {
                    return;
                  }
                  _moveTo(at, extend: false);
                },
              ),
              _TouchHold: GestureRecognizerFactoryWithHandlers<_TouchHold>(
                () => _TouchHold(_allows),
                (recognizer) => recognizer.onLongPressStart = (details) {
                  if (!_focus.hasPrimaryFocus) _focus.requestFocus();
                  final at = offsetAt(details.globalPosition);
                  if (at == null) return;
                  final (start, end) = _wordAt(at);
                  _select(TextSelection(baseOffset: start, extentOffset: end));
                },
              ),
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _imeGeometrySoon();
                return false;
              },
              child: scroll,
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the line at the top of the view where it is when lines above it
/// change height after they were laid out (an image shown once it is
/// read, a diagram once drawn): the list moves the view only for lines it
/// lays out anew, and the lines under them would jump down.
class _KeepTopLine extends SingleChildRenderObjectWidget {
  const _KeepTopLine({required Widget sliver}) : super(child: sliver);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderKeepTopLine();
}

class _RenderKeepTopLine extends RenderProxySliver {
  @override
  void performLayout() {
    final list = child;
    if (list is! RenderSliverMultiBoxAdaptor) return super.performLayout();
    final top = constraints.scrollOffset;
    // The first line in view (the last to start above its top), and where
    // it was.
    RenderBox? anchor;
    double? was;
    for (var box = list.firstChild; box != null; box = list.childAfter(box)) {
      final offset = list.childScrollOffset(box);
      if (offset == null) continue;
      if (offset > top && anchor != null) break;
      anchor = box;
      was = offset;
      if (offset > top) break;
    }
    list.layout(constraints, parentUsesSize: true);
    geometry = list.geometry;
    // At the top the lines are where they are; the list's own correction
    // first.
    if (anchor == null || top <= 0 || anchor.parent != list) return;
    if (geometry!.scrollOffsetCorrection != null) return;
    final now = list.childScrollOffset(anchor);
    if (now == null) return;
    final shift = math.max(now - was!, -top);
    if (shift.abs() > precisionErrorTolerance) {
      geometry = SliverGeometry(scrollOffsetCorrection: shift);
    }
  }
}

/// An action of the editor's, while [enabled].
class _Act<T extends Intent> extends Action<T> {
  _Act(this._invoke, [this._enabled]);

  final void Function(T intent) _invoke;
  final bool Function()? _enabled;

  @override
  bool isEnabled(T intent) => _enabled?.call() ?? true;

  @override
  Object? invoke(T intent) {
    _invoke(intent);
    return null;
  }
}

/// A mouse's clicks (double, triple) and drags, selecting.
class _MouseSelect extends TapAndPanGestureRecognizer {
  _MouseSelect(this._allows)
    : super(
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
          PointerDeviceKind.unknown,
        },
      );

  final bool Function(PointerDownEvent event) _allows;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      (event is! PointerDownEvent || _allows(event)) &&
      super.isPointerAllowed(event);
}

class _TouchTap extends TapGestureRecognizer {
  _TouchTap(this._allows)
    : super(supportedDevices: const {PointerDeviceKind.touch});

  final bool Function(PointerDownEvent event) _allows;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _allows(event) && super.isPointerAllowed(event);
}

class _TouchHold extends LongPressGestureRecognizer {
  _TouchHold(this._allows)
    : super(supportedDevices: const {PointerDeviceKind.touch});

  final bool Function(PointerDownEvent event) _allows;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _allows(event) && super.isPointerAllowed(event);
}

/// A code block's box, a line's slice of it: its top (rounded) on the
/// first line's, its bottom on the last's, its sides on all.
class _CodeBoxPainter extends CustomPainter {
  const _CodeBoxPainter({
    required this.top,
    required this.bottom,
    required this.color,
    required this.border,
    required this.radius,
  });

  final bool top;
  final bool bottom;
  final Color color;
  final Color border;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndCorners(
      rect,
      topLeft: top ? Radius.circular(radius) : Radius.zero,
      topRight: top ? Radius.circular(radius) : Radius.zero,
      bottomLeft: bottom ? Radius.circular(radius) : Radius.zero,
      bottomRight: bottom ? Radius.circular(radius) : Radius.zero,
    );
    canvas.drawRRect(shape, Paint()..color = color);
    final stroke = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final inset = shape.deflate(0.5);
    final path = Path();
    // The sides, and the ends this slice has.
    if (top && bottom) {
      path.addRRect(inset);
    } else {
      final left = inset.left;
      final right = inset.right;
      if (top) {
        path
          ..moveTo(left, size.height)
          ..lineTo(left, inset.top + radius)
          ..arcToPoint(
            Offset(left + radius, inset.top),
            radius: Radius.circular(radius),
          )
          ..lineTo(right - radius, inset.top)
          ..arcToPoint(
            Offset(right, inset.top + radius),
            radius: Radius.circular(radius),
          )
          ..lineTo(right, size.height);
      } else if (bottom) {
        path
          ..moveTo(left, 0)
          ..lineTo(left, inset.bottom - radius)
          ..arcToPoint(
            Offset(left + radius, inset.bottom),
            radius: Radius.circular(radius),
            clockwise: false,
          )
          ..lineTo(right - radius, inset.bottom)
          ..arcToPoint(
            Offset(right, inset.bottom - radius),
            radius: Radius.circular(radius),
            clockwise: false,
          )
          ..lineTo(right, 0);
      } else {
        path
          ..moveTo(left, 0)
          ..lineTo(left, size.height)
          ..moveTo(right, 0)
          ..lineTo(right, size.height);
      }
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_CodeBoxPainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.color != color ||
      old.border != border ||
      old.radius != radius;
}

/// A quote's bars, one for each level it is quoted in.
class _QuoteBarsPainter extends CustomPainter {
  const _QuoteBarsPainter({
    required this.depth,
    required this.color,
    required this.width,
    required this.step,
  });

  final int depth;
  final Color color;
  final double width;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i < depth; i++) {
      canvas.drawRect(Rect.fromLTWH(i * step, 0, width, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_QuoteBarsPainter old) =>
      old.depth != depth ||
      old.color != color ||
      old.width != width ||
      old.step != step;
}

/// A widget in the editor's text with taps of its own (a chip's): the
/// editor leaves the pointers down on it to it.
class MdEmbedRegion extends StatelessWidget {
  const MdEmbedRegion({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => context
        .findAncestorStateOfType<MarkdownEditorState>()
        ?.claimPointer(event.pointer),
    child: child,
  );
}
