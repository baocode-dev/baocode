// A markdown file's preview: VS Code's markdown preview
// (extensions/markdown-language-features). It shows; the source edits:
// a double click opens the source where it was, as VS Code's
// `markdown.preview.doubleClickToSwitchToEditor` does, the caret on the
// text clicked.
//
// The preview shows the document's text as the editor holds it (unsaved
// changes too). What it changes (a task box ticked, a file dropped), it
// changes through the document's model, so the tab's dirty mark, undo,
// saving, language servers and the agent's change review see one text.

import 'dart:async';
import 'dart:math' as math;

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../chat/widgets/code_citation.dart' show MarkdownCodeBlock;
import '../../chat/widgets/markdown_view.dart';
import '../../platform/svg_text_transform.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'markdown_block_editor.dart';
import 'markdown_blocks.dart';
import 'markdown_document.dart';
import '../ide_hover.dart';

/// Whether [path] is a markdown file the preview shows.
bool isMarkdownPath(String path) {
  final extension = p.extension(path).toLowerCase();
  return extension == '.md' || extension == '.markdown';
}

/// The preview of the markdown file at [path], whose text is [model]'s.
class IdeMarkdownPreview extends StatefulWidget {
  const IdeMarkdownPreview({
    super.key,
    required this.path,
    required this.model,
    required this.readBytes,
    this.pathContext,
    this.readOnly = false,
    this.initialLine,
    this.onLeave,
    this.onEdited,
    this.onEdit,
    this.onOpenFile,
    this.onOpenExternal,
  });

  final String path;
  final EditorDocumentModel model;

  /// Reads a file the document shows (an image), on the project's host.
  final Future<Uint8List> Function(String path) readBytes;

  /// How the host writes paths (a remote project's are POSIX); this
  /// machine's when null.
  final p.Context? pathContext;

  /// Shown, not changed (a revision's text): no task box ticks.
  final bool readOnly;

  /// The line (one-based) to show first: the block it is in.
  final int? initialLine;

  /// Told, as the preview goes, the line (one-based) of the block at its
  /// top, to show first when it comes back.
  final ValueChanged<int?>? onLeave;

  /// Told after the preview changed the text.
  final VoidCallback? onEdited;

  /// Opens the source at a line and column (one-based): where the preview
  /// was double clicked.
  final void Function(int line, int column)? onEdit;

  /// Opens a file a link goes to, and the part of its address after `#`.
  final void Function(String path, String? fragment)? onOpenFile;

  /// Opens a web or mail link.
  final void Function(Uri uri)? onOpenExternal;

  @override
  State<IdeMarkdownPreview> createState() => IdeMarkdownPreviewState();
}

class IdeMarkdownPreviewState extends State<IdeMarkdownPreview> {
  late MarkdownSource _source = MarkdownSource(widget.model.text);
  StreamSubscription<EditorContentChangeEvent>? _changes;
  Timer? _reparse;

  final _list = ListController();
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'markdown preview');

  /// The images read, by path: read once while the preview shows.
  final Map<String, Future<Uint8List>> _images = {};

  /// The blocks laid out now, for where a drop lands and a double click
  /// is.
  final Map<int, BuildContext> _shown = {};

  p.Context get _context => widget.pathContext ?? p.context;

  @override
  void initState() {
    super.initState();
    _listen();
    if (widget.initialLine case final line?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) revealLine(line);
      });
    }
  }

  @override
  void didUpdateWidget(IdeMarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) {
      unawaited(_changes?.cancel());
      _images.clear();
      _source = MarkdownSource(widget.model.text);
      _listen();
    } else if (oldWidget.path != widget.path) {
      _images.clear();
    }
  }

  void _listen() {
    _changes = widget.model.changes.listen((_) {
      _reparse?.cancel();
      _reparse = Timer(const Duration(milliseconds: 120), _parse);
    });
  }

  /// Its own changes are shown at once; others' a moment after.
  void _parseNow() {
    _reparse?.cancel();
    _parse();
  }

  void _parse() {
    if (!mounted) return;
    setState(() => _source = MarkdownSource(widget.model.text));
  }

  @override
  void dispose() {
    widget.onLeave?.call(topLine);
    _reparse?.cancel();
    unawaited(_changes?.cancel());
    _focus.dispose();
    _scroll.dispose();
    _list.dispose();
    super.dispose();
  }

  // --- The workbench's -----------------------------------------------------

  void focus() => _focus.requestFocus();

  /// The line (one-based) of the block at the top of the view.
  int? get topLine {
    final blocks = _source.blocks;
    if (blocks.isEmpty) return null;
    final range = _list.isAttached ? _list.visibleRange : null;
    final index = (range?.$1 ?? 0).clamp(0, blocks.length - 1);
    return blocks[index].start + 1;
  }

  /// Shows the block [line] (one-based) is in at the top.
  void revealLine(int line, [int column = 1]) {
    final index = _source.blockAt(line - 1);
    if (index == null) return;
    _jumpTo(index);
    focus();
  }

  void _jumpTo(int index) {
    if (!_list.isAttached || !_scroll.hasClients) return;
    _list.jumpToItem(index: index, scrollController: _scroll, alignment: 0);
  }

  /// Puts [text] (links, a dropped file's) as a block of its own after the
  /// block at [position] (global), or at the end.
  void insert(String text, {Offset? position}) {
    if (widget.readOnly || text.isEmpty) return;
    final model = widget.model;
    final lines = _source.lines;
    final after = position == null ? null : _blockAt(position);
    final String insertion;
    final int offset;
    if (after != null && after < _source.blocks.length) {
      final lineBreak = lines.lineBreak;
      offset = lines.ends[_source.blocks[after].end - 1];
      insertion = '$lineBreak$lineBreak${_withLineBreak(text, lineBreak)}';
    } else {
      offset = model.text.length;
      insertion =
          MarkdownBlockEdit.newBlockPrefix(model.text) +
          _withLineBreak(text, lines.lineBreak);
    }
    model.closeUndoGroup();
    model.applyOffsetEdits([EditorOffsetEdit(offset, offset, insertion)]);
    model.closeUndoGroup();
    _parseNow();
    widget.onEdited?.call();
  }

  static String _withLineBreak(String text, String lineBreak) =>
      text.replaceAll(RegExp('\r\n|\r|\n'), lineBreak);

  /// The block laid out at [global], if one is.
  int? _blockAt(Offset global) {
    for (final MapEntry(key: index, value: context) in _shown.entries) {
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final local = box.globalToLocal(global);
      if (local.dy >= 0 && local.dy <= box.size.height) return index;
    }
    return null;
  }

  void _toggleTask(int index, int task) {
    if (widget.readOnly || index >= _source.blocks.length) return;
    final marks = _source.taskMarks(_source.blocks[index]);
    if (task >= marks.length) return;
    toggleMarkdownTask(widget.model, marks[task]);
    _parseNow();
    widget.onEdited?.call();
  }

  // --- A double click: the source, there ---------------------------------------

  /// The last click, to tell a double click: the preview's text selects a
  /// word on one, and a double click is told here beside it.
  ({Duration time, Offset position})? _lastClick;

  void _pointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse &&
        event.kind != PointerDeviceKind.touch) {
      return;
    }
    if (event.buttons != kPrimaryButton) return;
    final last = _lastClick;
    final double =
        last != null &&
        event.timeStamp - last.time <= kDoubleTapTimeout &&
        (event.position - last.position).distance <= kDoubleTapSlop;
    _lastClick = double
        ? null
        : (time: event.timeStamp, position: event.position);
    if (!double) return;
    final onEdit = widget.onEdit;
    if (onEdit == null) return;
    final at = sourceAt(event.position);
    if (at == null) return;
    // After the gesture: the click's word is selected first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) onEdit(at.line, at.column);
    });
  }

  /// The source's line and column (one-based) of the text shown at
  /// [global]: the block's first line when no text is there.
  ({int line, int column})? sourceAt(Offset global) {
    final index = _blockAt(global);
    if (index == null || index >= _source.blocks.length) return null;
    final block = _source.blocks[index];
    final lines = _source.lines;
    final start = lines.starts[block.start];
    final fallback = (line: block.start + 1, column: 1);
    final box = _shown[index]?.findRenderObject();
    if (box is! RenderBox) return fallback;
    // The block's texts, in order, and the one at the point.
    final texts = <RenderParagraph>[];
    void collect(RenderObject object) {
      if (object is RenderParagraph) texts.add(object);
      object.visitChildren(collect);
    }

    collect(box);
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(global));
    RenderParagraph? hit;
    for (final entry in result.path) {
      if (entry.target case final RenderParagraph paragraph) {
        hit = paragraph;
        break;
      }
    }
    if (hit == null || !texts.contains(hit)) return fallback;
    final shown = hit.text.toPlainText();
    final offset = hit
        .getPositionForOffset(hit.globalToLocal(global))
        .offset
        .clamp(0, shown.length);
    final before = StringBuffer();
    for (final text in texts) {
      if (identical(text, hit)) break;
      before
        ..write(text.text.toPlainText())
        ..write('\n');
    }
    before.write(shown.substring(0, offset));
    final source = _source.source(block);
    final at = markdownSourceOffset(
      source,
      shown: shown,
      offset: offset,
      before: before.toString(),
    );
    if (at == null) return fallback;
    final line = lines.lineAt(start + at);
    return (line: line + 1, column: start + at - lines.starts[line] + 1);
  }

  // --- Links and images -------------------------------------------------------

  GestureRecognizer? _link(String? href) {
    final target = resolveMarkdownLink(href, widget.path, _context);
    if (target == null) return null;
    return TapGestureRecognizer()..onTap = () => _open(target);
  }

  void _open(MarkdownLinkTarget target) {
    switch (target) {
      case MarkdownAnchorLink(:final anchor):
        if (_source.heading(anchor) case final index?) _jumpTo(index);
      case MarkdownExternalLink(:final uri):
        widget.onOpenExternal?.call(uri);
      case MarkdownFileLink(:final path, :final fragment):
        if (_context.equals(path, widget.path)) {
          if (fragment != null) _open(MarkdownAnchorLink(fragment));
        } else {
          widget.onOpenFile?.call(path, fragment);
        }
    }
  }

  /// Opens the anchor [fragment] of the document (a link from another).
  void revealAnchor(String fragment) => _open(MarkdownAnchorLink(fragment));

  // HTML shows as its source here: no image has a size of its own.
  Widget _image(
    String src,
    String alt,
    String? title, {
    double? width,
    double? height,
  }) => _MarkdownImage(
    target: resolveMarkdownImage(src, widget.path, _context),
    alt: alt,
    title: title,
    read: (path) => _images.putIfAbsent(path, () => widget.readBytes(path)),
  );

  // --- Building ---------------------------------------------------------------

  static TextStyle get _style =>
      TextStyle(color: AppColors.text, fontSize: 14, height: 1.65);

  MarkdownOptions _options(int index) => MarkdownOptions(
    headingSizes: const [26, 21, 17.5, 15, 14, 13.5],
    headingRules: true,
    gap: 10,
    headingGap: 16,
    link: _link,
    image: _image,
    onToggleTask: widget.readOnly ? null : (task) => _toggleTask(index, task),
  );

  Widget _block(int index) {
    final block = _source.blocks[index];
    final source = _source.source(block);
    switch (block.kind) {
      case MarkdownBlockKind.frontMatter:
        final lines = source.split(RegExp('\r\n|\r|\n'));
        return MarkdownCodeBlock(
          code: lines.sublist(1, lines.length - 1).join('\n'),
          language: 'yaml',
        );
      case MarkdownBlockKind.html:
        return _SourceText(source);
      default:
        final nodes = _source.parse(block);
        // Link definitions alone: shown as they are written.
        if (nodes.isEmpty) return _SourceText(source, faint: true);
        return MarkdownBlocks(
          nodes: nodes,
          style: _style,
          options: _options(index),
        );
    }
  }

  Widget _item(BuildContext context, int index) {
    final heading = _source.blocks[index].kind == MarkdownBlockKind.heading;
    return _Shown(
      index: index,
      shown: _shown,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              32,
              heading && index > 0 ? 12 : 4,
              32,
              4,
            ),
            child: _block(index),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return Actions(
      actions: {
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            if (widget.readOnly || !model.undo()) return null;
            _parseNow();
            widget.onEdited?.call();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            if (widget.readOnly || !model.redo()) return null;
            _parseNow();
            widget.onEdited?.call();
            return null;
          },
        ),
      },
      child: ColoredBox(
        color: themeColors['editor.background'],
        child: Listener(
          onPointerDown: _pointerDown,
          child: SelectionArea(
            focusNode: _focus,
            child: SuperListView.builder(
              listController: _list,
              controller: _scroll,
              // Room after the last block, to bring any to the top.
              padding: const EdgeInsets.only(top: 24, bottom: 160),
              itemCount: _source.blocks.length,
              itemBuilder: _item,
            ),
          ),
        ),
      ),
    );
  }
}

/// Where in [source] (a block's markdown) is the text shown at [offset] of
/// [shown] (a text of the block as it renders), [before] the block's text
/// shown up to there: the text from there found in the source (as long a
/// piece as is found, marks being in the source and not shown), the same
/// time over as it is shown before. Null when it is not found.
int? markdownSourceOffset(
  String source, {
  required String shown,
  required int offset,
  required String before,
}) {
  // What follows the point, on its line; at a line's end, what leads to it.
  final lineEnd = shown.indexOf('\n', offset);
  final ahead = shown.substring(offset, lineEnd < 0 ? shown.length : lineEnd);
  final lineStart = shown.lastIndexOf('\n', math.max(offset - 1, 0)) + 1;
  final behind = offset > lineStart ? shown.substring(lineStart, offset) : '';
  final forward = ahead.trim().isNotEmpty;
  final piece = forward ? ahead : behind;
  if (piece.trim().isEmpty) return null;
  for (var length = math.min(piece.length, 24); length > 0; length--) {
    final needle = forward
        ? piece.substring(0, length)
        : piece.substring(piece.length - length);
    if (needle.trim().isEmpty) continue;
    final found = needle.allMatches(source).map((m) => m.start).toList();
    if (found.isEmpty) continue;
    // The same occurrence as shown: as many before it.
    final shownBefore = forward
        ? needle.allMatches(before).length
        : needle.allMatches(before).length - 1;
    final at = found[shownBefore.clamp(0, found.length - 1)];
    return forward ? at : at + needle.length;
  }
  return null;
}

/// Keeps [shown] told which blocks are laid out.
class _Shown extends StatefulWidget {
  const _Shown({required this.index, required this.shown, required this.child});

  final int index;
  final Map<int, BuildContext> shown;
  final Widget child;

  @override
  State<_Shown> createState() => _ShownState();
}

class _ShownState extends State<_Shown> {
  @override
  void initState() {
    super.initState();
    widget.shown[widget.index] = context;
  }

  @override
  void didUpdateWidget(_Shown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (identical(oldWidget.shown[oldWidget.index], context)) {
        oldWidget.shown.remove(oldWidget.index);
      }
      widget.shown[widget.index] = context;
    }
  }

  @override
  void dispose() {
    if (identical(widget.shown[widget.index], context)) {
      widget.shown.remove(widget.index);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A block shown as it is written: HTML, link definitions.
class _SourceText extends StatelessWidget {
  const _SourceText(this.source, {this.faint = false});

  final String source;
  final bool faint;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: faint
        ? null
        : BoxDecoration(
            color: themeColors['textCodeBlock.background'],
            borderRadius: BorderRadius.circular(6),
          ),
    child: Text(
      source,
      style: AppFonts.uiCodeStyle(12.5).copyWith(
        color: faint ? AppColors.textMuted : AppColors.text,
        height: 1.5,
      ),
    ),
  );
}

/// An image of the document: a file of the project's host, read with
/// [read], or a web one; its alt text when it cannot be shown.
class _MarkdownImage extends StatelessWidget {
  const _MarkdownImage({
    required this.target,
    required this.alt,
    required this.title,
    required this.read,
  });

  final ({Uri? url, String? path})? target;
  final String alt;
  final String? title;
  final Future<Uint8List> Function(String path) read;

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    final Widget image;
    if (target?.url case final url?) {
      image = Image.network(
        url.toString(),
        errorBuilder: (context, _, _) => _missing(),
      );
    } else if (target?.path case final path?) {
      image = FutureBuilder<Uint8List>(
        future: read(path),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _missing();
          final bytes = snapshot.data;
          if (bytes == null) return const SizedBox(width: 16, height: 16);
          if (p.extension(path).toLowerCase() == '.svg') {
            return SvgPicture(
              SvgTextBytesLoader(bytes),
              errorBuilder: (context, _, _) => _missing(),
            );
          }
          return Image.memory(
            bytes,
            errorBuilder: (context, _, _) => _missing(),
          );
        },
      );
    } else {
      image = _missing();
    }
    final tip = title ?? (alt.isEmpty ? null : alt);
    return tip == null
        ? image
        : IdeHover(message: tip, followMouse: true, child: image);
  }

  Widget _missing() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 14, color: AppColors.textMuted),
        if (alt.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(alt, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ],
    ),
  );
}
