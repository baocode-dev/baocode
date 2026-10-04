// A markdown file's preview, edited a block at a time: VS Code's markdown
// preview (extensions/markdown-language-features), with each block's
// source editable in place as Obsidian's live preview has it.
//
// The preview shows the document's text as the editor holds it (unsaved
// changes too) and changes it only through the document's model, so the
// tab's dirty mark, undo, saving, language servers and the agent's change
// review see one text.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../chat/widgets/code_citation.dart' show MarkdownCodeBlock;
import '../../chat/widgets/markdown_view.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'markdown_block_editor.dart';
import 'markdown_blocks.dart';
import 'markdown_document.dart';
import 'markdown_paste.dart';

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
    this.onOpenFile,
    this.onOpenExternal,
    this.onMessage,
    this.onPaste,
  });

  final String path;
  final EditorDocumentModel model;

  /// Reads a file the document shows (an image), on the project's host.
  final Future<Uint8List> Function(String path) readBytes;

  /// How the host writes paths (a remote project's are POSIX); this
  /// machine's when null.
  final p.Context? pathContext;

  /// Shown, not edited (a revision's text).
  final bool readOnly;

  /// The line (one-based) to show first: the block it is in.
  final int? initialLine;

  /// Told, as the preview goes, the line (one-based) of the block at its
  /// top, to show first when it comes back.
  final ValueChanged<int?>? onLeave;

  /// Told after the preview changed the text.
  final VoidCallback? onEdited;

  /// Opens a file a link goes to, and the part of its address after `#`.
  final void Function(String path, String? fragment)? onOpenFile;

  /// Opens a web or mail link.
  final void Function(Uri uri)? onOpenExternal;

  /// Says something to the user (a block's edit given up).
  final ValueChanged<String>? onMessage;

  /// What a paste in a block's field puts in; the clipboard's text when
  /// null.
  final Future<MarkdownPasteOutcome> Function()? onPaste;

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

  /// The edit of a block in progress, its block's index, and its field.
  MarkdownBlockEdit? _edit;
  int? _editing;
  final _field = TextEditingController();
  final _fieldFocus = FocusNode(debugLabel: 'markdown block');

  /// The images read, by path: read once while the preview shows.
  final Map<String, Future<Uint8List>> _images = {};

  /// The blocks laid out now, for where a drop lands.
  final Map<int, BuildContext> _shown = {};

  p.Context get _context => widget.pathContext ?? p.context;

  /// Whether a block's field has the keyboard.
  bool get editing => _edit != null;

  /// Whether the preview or a block's field has the keyboard.
  bool get hasFocus => _focus.hasFocus || _fieldFocus.hasFocus;

  @override
  void initState() {
    super.initState();
    _listen();
    _fieldFocus.addListener(_fieldFocusChanged);
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
      _endEdit(commit: true);
      unawaited(_changes?.cancel());
      _images.clear();
      _source = MarkdownSource(widget.model.text);
      _listen();
    } else if (oldWidget.path != widget.path) {
      _images.clear();
    }
    if (widget.readOnly && _edit != null) _endEdit(commit: false);
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
    final source = MarkdownSource(widget.model.text);
    final edit = _edit;
    var editing = _editing;
    if (edit != null) {
      // The block edited, where it is now; gone (merged into another, its
      // neighbors changed), its edit is put in.
      editing = null;
      for (final (index, block) in source.blocks.indexed) {
        if (source.lines.starts[block.start] == edit.start &&
            source.lines.ends[block.end - 1] == edit.end) {
          editing = index;
          break;
        }
      }
      if (editing == null && !_isNewBlock(edit)) {
        _endEdit(commit: true);
        return;
      }
    }
    setState(() {
      _source = source;
      if (edit != null && !_isNewBlock(edit)) _editing = editing;
    });
  }

  bool _isNewBlock(MarkdownBlockEdit edit) =>
      edit.original.isEmpty && edit.start == edit.end;

  @override
  void dispose() {
    // Leaving the tab, or the preview for the source: the block's edit is
    // put in.
    _endEdit(commit: true, rebuild: false);
    widget.onLeave?.call(topLine);
    _reparse?.cancel();
    unawaited(_changes?.cancel());
    _fieldFocus.removeListener(_fieldFocusChanged);
    _fieldFocus.dispose();
    _field.dispose();
    _focus.dispose();
    _scroll.dispose();
    _list.dispose();
    super.dispose();
  }

  // --- The workbench's -----------------------------------------------------

  /// Puts the block's edit in (saving, switching to the source).
  Future<void> flush() async => _endEdit(commit: true);

  void focus() {
    if (_fieldFocus.hasFocus) return;
    _focus.requestFocus();
  }

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

  /// Puts [text] (links, a dropped file's) where the edit is, or as a
  /// block of its own after the block at [position] (global), or at the
  /// end.
  void insert(String text, {Offset? position}) {
    if (widget.readOnly || text.isEmpty) return;
    if (_edit != null) {
      _insertInField(text);
      return;
    }
    final model = widget.model;
    final lines = _source.lines;
    int? after;
    if (position != null) {
      for (final MapEntry(key: index, value: context) in _shown.entries) {
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final local = box.globalToLocal(position);
        if (local.dy >= 0 && local.dy <= box.size.height) after = index;
      }
    }
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

  // --- Editing ----------------------------------------------------------------

  void _startEdit(int index) {
    if (widget.readOnly) return;
    if (_editing == index && _edit != null) return;
    _endEdit(commit: true, rebuild: false);
    final model = widget.model;
    final MarkdownBlockEdit edit;
    if (index >= _source.blocks.length) {
      final end = model.text.length;
      edit = MarkdownBlockEdit(
        model,
        start: end,
        end: end,
        prefix: MarkdownBlockEdit.newBlockPrefix(model.text),
        onConflict: _conflict,
      );
    } else {
      final block = _source.blocks[index];
      edit = MarkdownBlockEdit(
        model,
        start: _source.lines.starts[block.start],
        end: _source.lines.ends[block.end - 1],
        onConflict: _conflict,
      );
    }
    _field.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.text.length),
    );
    setState(() {
      _edit = edit;
      _editing = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _edit == edit) _fieldFocus.requestFocus();
    });
  }

  /// Ends the block's edit: [commit] puts its text in.
  void _endEdit({required bool commit, bool rebuild = true}) {
    final edit = _edit;
    if (edit == null) return;
    _edit = null;
    _editing = null;
    var changed = false;
    if (commit) {
      changed = edit.commit(_field.text);
    } else {
      edit.cancel();
    }
    if (changed) {
      // Told after the frame: a tab switched away from is being unbuilt.
      if (rebuild) {
        widget.onEdited?.call();
      } else {
        final onEdited = widget.onEdited;
        scheduleMicrotask(() => onEdited?.call());
      }
    }
    if (!rebuild || !mounted) return;
    final hadFocus = _fieldFocus.hasFocus;
    if (changed) {
      _parseNow();
    } else {
      setState(() {});
    }
    if (hadFocus) _focus.requestFocus();
  }

  void _fieldFocusChanged() {
    // Clicked elsewhere: the edit is done.
    if (!_fieldFocus.hasFocus && _edit != null) _endEdit(commit: true);
  }

  void _conflict() {
    final edit = _edit;
    if (edit == null) return;
    edit.cancel();
    _edit = null;
    _editing = null;
    widget.onMessage?.call(context.l10n.markdownBlockConflict);
    scheduleMicrotask(() {
      if (mounted) setState(() {});
    });
  }

  void _toggleTask(int index, int task) {
    if (widget.readOnly || index >= _source.blocks.length) return;
    final marks = _source.taskMarks(_source.blocks[index]);
    if (task >= marks.length) return;
    _endEdit(commit: true, rebuild: false);
    toggleMarkdownTask(widget.model, marks[task]);
    _parseNow();
    widget.onEdited?.call();
  }

  Future<void> _pasteInField() async {
    final paste = widget.onPaste;
    final edit = _edit;
    if (paste != null) {
      final outcome = await paste();
      if (!mounted || _edit != edit) return;
      switch (outcome) {
        case MarkdownPasteLinks(:final text):
          _insertInField(text);
          return;
        case MarkdownPasteNothing():
          return;
        case MarkdownPasteText():
      }
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || _edit != edit) return;
    if (data?.text case final text? when text.isNotEmpty) _insertInField(text);
  }

  void _insertInField(String text) {
    final value = _field.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    _field.value = value
        .replaced(selection, text)
        .copyWith(
          selection: TextSelection.collapsed(
            offset: selection.start + text.length,
          ),
        );
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

  Widget _image(String src, String alt, String? title) => _MarkdownImage(
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
        // Link definitions alone: shown as they are written, to edit.
        if (nodes.isEmpty) return _SourceText(source, faint: true);
        return MarkdownBlocks(
          nodes: nodes,
          style: _style,
          options: _options(index),
        );
    }
  }

  Widget _item(BuildContext context, int index) {
    final blocks = _source.blocks;
    final Widget child;
    if (index == _editing && _edit != null) {
      child = _BlockField(
        controller: _field,
        focusNode: _fieldFocus,
        onDone: () => _endEdit(commit: true),
        onPaste: () => unawaited(_pasteInField()),
      );
    } else if (index >= blocks.length) {
      child = _AddBlock(onTap: () => _startEdit(index));
    } else {
      child = _Block(
        onTap: widget.readOnly ? null : () => _startEdit(index),
        child: _block(index),
      );
    }
    final kind = index < blocks.length ? blocks[index].kind : null;
    final heading = kind == MarkdownBlockKind.heading;
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
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final count = _source.blocks.length + (widget.readOnly ? 0 : 1);
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
        child: SelectionArea(
          focusNode: _focus,
          child: SuperListView.builder(
            listController: _list,
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 24),
            itemCount: count,
            itemBuilder: _item,
          ),
        ),
      ),
    );
  }
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

/// A block, its background lit while the pointer is over it when a click
/// edits it.
class _Block extends StatefulWidget {
  const _Block({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Block> createState() => _BlockState();
}

class _BlockState extends State<_Block> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    if (onTap == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.hover.withValues(alpha: AppColors.hover.a * 0.5)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A block's source in a field, to edit: done with ⌘Enter (Ctrl+Enter),
/// Escape, or a click elsewhere.
class _BlockField extends StatelessWidget {
  const _BlockField({
    required this.controller,
    required this.focusNode,
    required this.onDone,
    required this.onPaste,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onDone;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): onDone,
      const SingleActivator(LogicalKeyboardKey.enter, control: true): onDone,
      const SingleActivator(LogicalKeyboardKey.escape): onDone,
    },
    child: Actions(
      actions: {
        PasteTextIntent: CallbackAction<PasteTextIntent>(
          onInvoke: (_) {
            onPaste();
            return null;
          },
        ),
      },
      child: TextField(
        key: const ValueKey('markdown-block-field'),
        controller: controller,
        focusNode: focusNode,
        maxLines: null,
        minLines: 1,
        style: TextStyle(
          color: themeColors['editor.foreground'],
          fontFamily: AppFonts.mono,
          fontSize: 13,
          height: 1.5,
        ),
        cursorColor: themeColors['editorCursor.foreground'],
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: themeColors['input.background'],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: themeColors['focusBorder']),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: themeColors['focusBorder']),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: themeColors['focusBorder']),
          ),
        ),
      ),
    ),
  );
}

/// The room after the last block: a click starts a new one.
class _AddBlock extends StatelessWidget {
  const _AddBlock({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.text,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 120),
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          context.l10n.markdownAddBlock,
          style: TextStyle(
            color: AppColors.textMuted.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
      ),
    ),
  );
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
      style: TextStyle(
        color: faint ? AppColors.textMuted : AppColors.text,
        fontFamily: AppFonts.mono,
        fontSize: 12.5,
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
            return SvgPicture.memory(
              bytes,
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
    return tip == null ? image : Tooltip(message: tip, child: image);
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
