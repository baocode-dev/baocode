// A markdown file's preview, edited as it shows: the text is the document's
// (bao_markdown's editor), a block's marks shown where the caret is, what
// they make everywhere else.
//
// It edits the document's model itself, so the tab's dirty mark, undo,
// saving, language servers and the agent's change review see one text, and
// what the source tab, the agent or a reload change shows here at once.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../../base/smooth_scroll.dart';
import '../../chat/widgets/code_citation.dart';
import '../../chat/widgets/markdown_math.dart';
import '../../chat/widgets/mermaid_code_block.dart';
import '../../platform/svg_text_transform.dart';
import '../../stash/stash_ai.dart' show polishStashText;
import '../../stash/stash_editor.dart' show StashEditor;
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../l10n/l10n.dart';
import '../../workspace/window_controls.dart';
import '../ide_hover.dart';
import '../ide_menu.dart';
import 'markdown_format_bar.dart';
import 'markdown_front_matter.dart';
import 'markdown_links.dart';
import 'markdown_model_source.dart';
import 'markdown_paste.dart';
import 'markdown_table_menu.dart';
import 'markdown_task_box.dart';

export 'markdown_links.dart';

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
    this.onPaste,
    this.onOpenFile,
    this.onOpenExternal,
    this.onReveal,
    this.background,
    this.padding,
  });

  final String path;
  final EditorDocumentModel model;

  /// Reads a file the document shows (an image), on the project's host.
  final Future<Uint8List> Function(String path) readBytes;

  /// How the host writes paths (a remote project's are POSIX); this
  /// machine's when null.
  final p.Context? pathContext;

  /// Shown, not changed (a revision's text).
  final bool readOnly;

  /// The line (one-based) to show first.
  final int? initialLine;

  /// Told, as the preview goes, the line (one-based) at its top, to show
  /// first when it comes back.
  final ValueChanged<int?>? onLeave;

  /// Told after the preview changed the text.
  final VoidCallback? onEdited;

  /// A paste of the clipboard's files and pictures (put beside the
  /// document, linked to: see [MarkdownPaste]); its text pasted as usual.
  final Future<MarkdownPasteOutcome> Function()? onPaste;

  /// Opens a file a link goes to, and the part of its address after `#`.
  final void Function(String path, String? fragment)? onOpenFile;

  /// Opens a web or mail link.
  final void Function(Uri uri)? onOpenExternal;

  /// Shows a file (the document, one it links to) in the file manager
  /// (Finder, Explorer), from the right click's menu; none for a remote
  /// project's.
  final void Function(String path)? onReveal;

  /// Behind it; the editor's when null.
  final Color? background;

  /// Around its text, for a view of its own laying it out (a
  /// customization's, under its title); as wide as a page reads, in the
  /// middle of a wide one, when null.
  final EdgeInsets? padding;

  @override
  State<IdeMarkdownPreview> createState() => IdeMarkdownPreviewState();
}

class IdeMarkdownPreviewState extends State<IdeMarkdownPreview> {
  late MarkdownController _controller = _controllerOf(widget.model);

  final _editorKey = GlobalKey<MarkdownEditorState>();
  final _formatBar = GlobalKey<MarkdownFormatBarState>();
  final _scroll = SmoothScrollController();
  final _focus = FocusNode(debugLabel: 'markdown preview');
  late final _embeds = _PreviewEmbeds(this);

  /// The images read, by path: read once while the preview shows.
  final Map<String, Future<Uint8List>> _images = {};

  /// Those of [_images] read by now: a line built again (scrolled back
  /// to) shows its image at once, as tall as it is.
  final Map<String, Uint8List> _imagesRead = {};

  Future<Uint8List> _readImage(String path) {
    if (_images[path] case final reading?) return reading;
    final reading = _images[path] = widget.readBytes(path);
    reading.then((bytes) {
      // Not one read again since (the images cleared).
      if (identical(_images[path], reading)) _imagesRead[path] = bytes;
    }, onError: (_) {});
    return reading;
  }

  /// Whether the caret was put somewhere (clicked, moved, revealed): where
  /// the source opens.
  bool _placed = false;

  p.Context get _context => widget.pathContext ?? p.context;

  MarkdownEditorState? get _editor => _editorKey.currentState;

  MarkdownController _controllerOf(EditorDocumentModel model) =>
      MarkdownController.of(EditorModelMarkdownSource(model, onEdited: _edited))
        ..selectionListenable.addListener(_selectionChanged);

  void _selectionChanged() {
    if (_focus.hasFocus) _placed = true;
  }

  bool _editedSoon = false;

  /// Told once the change is made: the edits of one (the bar's marks at
  /// both ends) are one step of the model's Undo, which a source tab told
  /// in between would end.
  void _edited() {
    if (_editedSoon) return;
    _editedSoon = true;
    scheduleMicrotask(() {
      _editedSoon = false;
      widget.onEdited?.call();
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialLine case final line?) {
      final index = (line - 1).clamp(0, _controller.lines.lineCount - 1);
      // The caret there too: where the source opens again.
      _controller.selection = TextSelection.collapsed(
        offset: _controller.lineStart(index),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show(index);
      });
    }
  }

  @override
  void didUpdateWidget(IdeMarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) {
      _images.clear();
      _imagesRead.clear();
      final old = _controller;
      _controller = _controllerOf(widget.model);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } else if (oldWidget.path != widget.path) {
      _images.clear();
      _imagesRead.clear();
    }
  }

  /// The line at the top when the view last came to rest: what is told
  /// as the preview goes (its editor is gone by then).
  late int? _restedAt = widget.initialLine;
  bool _restScheduled = false;

  /// [_restedAt] read after the frame (a scroll may end in its layout).
  void _restSoon() {
    if (_restScheduled) return;
    _restScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restScheduled = false;
      if (mounted) _restedAt = topLine ?? _restedAt;
    });
  }

  @override
  void dispose() {
    widget.onLeave?.call(_restedAt);
    _focus.dispose();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  // --- The workbench's -----------------------------------------------------

  void focus() => _focus.requestFocus();

  /// The line (one-based) at the top of the view.
  int? get topLine {
    final editor = _editor;
    final viewport = editor?.viewportRect;
    if (editor == null || viewport == null) return null;
    // Below the room the caret is kept in from the edge.
    final at = editor.offsetAt(viewport.topLeft + const Offset(48, 12));
    if (at != null) return _controller.lineAt(at) + 1;
    final first = editor.firstVisibleLine;
    return first == null ? null : first + 1;
  }

  /// Where the caret is (one-based), when it was put somewhere: where the
  /// source opens.
  ({int line, int column})? get caret {
    final selection = _controller.selection;
    if (!_placed || !selection.isValid) return null;
    final offset = selection.extentOffset;
    final line = _controller.lineAt(offset);
    return (line: line + 1, column: offset - _controller.lineStart(line) + 1);
  }

  /// Shows [line] (one-based) at the top, the caret at [column] of it.
  void revealLine(int line, [int column = 1]) {
    final index = (line - 1).clamp(0, _controller.lines.lineCount - 1);
    final start = _controller.lineStart(index);
    final length = _controller.lines.content(index).length;
    _controller.selection = TextSelection.collapsed(
      offset: start + (column - 1).clamp(0, length),
    );
    _show(index);
    focus();
    _placed = true;
  }

  /// [line] (from 0) at the top: shown at once where it is laid out, else
  /// once it is.
  void _show(int line) {
    _editor?.revealLine(line);
    _restedAt = line + 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editor?.revealLine(line);
    });
  }

  /// Opens the anchor [fragment] of the document (a link from another).
  void revealAnchor(String fragment) => _open(MarkdownAnchorLink(fragment));

  /// Puts [text] (links, a dropped file's) as a block of its own after the
  /// block at [position] (global), or at the end.
  void insert(String text, {Offset? position}) {
    if (widget.readOnly || text.isEmpty) return;
    final controller = _controller;
    final newline = controller.lines.newline;
    text = text.replaceAll(RegExp('\r\n|\r|\n'), newline);
    final at = position == null ? null : _editor?.offsetAt(position);
    final int offset;
    final String insertion;
    if (at != null) {
      offset = controller.lineEnd(_blockEnd(controller.lineAt(at)));
      insertion = '$newline$newline$text';
    } else {
      offset = controller.length;
      insertion = markdownBlockPrefix(controller.text) + text;
    }
    controller.breakUndo();
    controller.replace(
      offset,
      offset,
      insertion,
      selection: TextSelection.collapsed(offset: offset + insertion.length),
    );
    controller.breakUndo();
  }

  /// The last line of the block [line] is in: a heading's own, a fence's
  /// (a table's…) last, a paragraph's (a list's, a quote's) before the
  /// empty line after it.
  int _blockEnd(int line) {
    final controller = _controller;
    final info = controller.infoOf(line);
    final (_, last) = controller.blockOf(line);
    if (info.kind == MdLineKind.heading ||
        info.kind == MdLineKind.rule ||
        info.kind == MdLineKind.blank ||
        info.isMultiline ||
        info.kind == MdLineKind.html ||
        info.kind == MdLineKind.frontMatter) {
      return last;
    }
    var end = last;
    while (end + 1 < controller.lines.lineCount &&
        controller.infoOf(end + 1).kind != MdLineKind.blank &&
        controller.infoOf(end + 1).kind != MdLineKind.heading) {
      end++;
    }
    return end;
  }

  // --- Links ------------------------------------------------------------------

  /// A click at [offset]: a link there ⌘-clicked (clicked, read only) is
  /// followed, the caret left where it was; else the caret goes there, a
  /// link's bubble over it (as a stash's).
  bool _click(int offset) {
    final keyboard = HardwareKeyboard.instance;
    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final opened = (command || widget.readOnly) && _openLinkAt(offset);
    if (!opened) _placed = true;
    return opened;
  }

  bool _openLinkAt(int offset) {
    final controller = _controller;
    final line = controller.lineAt(offset);
    final column = offset - controller.lineStart(line);
    for (final run in inlinesAt(controller.inlinesOf(line), column).reversed) {
      if (column >= run.end) continue;
      final href = switch (run.kind) {
        MdInlineKind.link ||
        MdInlineKind.autolink ||
        MdInlineKind.url => run.href,
        _ => null,
      };
      if (href == null) continue;
      final target = resolveMarkdownLink(href, widget.path, _context);
      if (target == null) return false;
      _open(target);
      return true;
    }
    return false;
  }

  /// The right click's menu's own: the file there shown in the file
  /// manager (a link's or a picture's, else the document's).
  List<IdeMenuEntry> _contextMenu(int? offset) {
    final reveal = widget.onReveal;
    if (reveal == null) return const [];
    final target = offset == null ? null : _fileAt(offset);
    return [
      IdeMenuAction(
        context.l10n.revealInFileManager,
        onSelected: () => reveal(target ?? widget.path),
      ),
    ];
  }

  /// The project's file a link or a picture at [offset] goes to.
  String? _fileAt(int offset) {
    final controller = _controller;
    final line = controller.lineAt(offset);
    final column = offset - controller.lineStart(line);
    for (final run in inlinesAt(controller.inlinesOf(line), column).reversed) {
      final href = switch (run.kind) {
        MdInlineKind.link || MdInlineKind.image => run.href,
        _ => null,
      };
      if (href == null) continue;
      return switch (resolveMarkdownLink(href, widget.path, _context)) {
        MarkdownFileLink(:final path) => path,
        _ => null,
      };
    }
    return null;
  }

  /// Opens where [href], a link's address, goes.
  void _openHref(String href) {
    if (resolveMarkdownLink(href, widget.path, _context) case final target?) {
      _open(target);
    }
  }

  void _open(MarkdownLinkTarget target) {
    switch (target) {
      case MarkdownAnchorLink(:final anchor):
        if (_heading(anchor) case final line?) _show(line);
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

  int? _heading(String anchor) => markdownHeading(_controller, anchor);

  // --- Pasting ------------------------------------------------------------------

  Future<bool> _paste() async {
    final paste = widget.onPaste;
    if (paste == null || widget.readOnly) return false;
    final version = _controller.textVersion;
    final outcome = await paste();
    if (!mounted) return true;
    switch (outcome) {
      case MarkdownPasteText():
        return false;
      case MarkdownPasteNothing():
        return true;
      case MarkdownPasteLinks(:final text):
        if (_controller.textVersion == version) {
          _editor?.insertText(text);
        } else {
          insert(text);
        }
        return true;
    }
  }

  // --- Building ---------------------------------------------------------------

  MarkdownEditorStyle _style(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        color: AppColors.text,
        fontSize: 14,
        height: 1.65,
        leadingDistribution: TextLeadingDistribution.even,
      ),
    );
    final link = themeColors['textLink.foreground'];
    final heading = TextStyle(
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      height: 1.4,
    );
    return MarkdownEditorStyle(
      text: base,
      headings: [
        heading.copyWith(fontSize: 26),
        heading.copyWith(fontSize: 21),
        heading.copyWith(fontSize: 17.5),
        heading.copyWith(fontSize: 15),
        heading,
        heading.copyWith(fontSize: 13.5),
      ],
      headingSpacing: const [(16, 8), (14, 6), (12, 2), (10, 0), (8, 0)],
      headingRule: AppColors.partBorder,
      bold: const TextStyle(fontWeight: FontWeight.w600),
      code: AppFonts.uiCodeStyle(12.5).copyWith(color: AppColors.inlineCode),
      codeBackground: AppColors.inlineCodeBackground,
      codeBlock: AppFonts.uiCodeStyle(12.5)
          .copyWith(color: AppColors.text, height: 1.5),
      codeBlockBackground: themeColors['textCodeBlock.background'],
      codeBlockBorder: themeColors['chat.requestBorder'],
      // As the chat's tables are.
      table: MdTableStyle(
        border: themeColors['chat.requestBorder'],
        head: AppColors.surfaceRaised,
        accent: AppColors.accent,
        control: themeColors['toolbar.hoverBackground'],
        surface: themeColors['editorWidget.background'],
        shadow: themeColors['widget.shadow'],
      ),
      link: TextStyle(
        color: link,
        decoration: TextDecoration.underline,
        decorationColor: link.withValues(alpha: 0.4),
      ),
      marks: AppColors.textFaint,
      quote: TextStyle(color: AppColors.textMuted),
      quoteBar: AppColors.borderStrong,
      rule: AppColors.border,
      selection:
          DefaultSelectionStyle.of(context).selectionColor ??
          themeColors['editor.selectionBackground'],
      caret: themeColors['editorCursor.foreground'],
      composing: AppColors.textMuted,
      placeholder: TextStyle(color: AppColors.textFaint),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorize =
        CodeCitationScope.maybeOf(context)?.colorizeBlock ??
        StashEditor.colorize;
    return ColoredBox(
      color: widget.background ?? themeColors['editor.background'],
      child: Builder(
        builder: (context) {
          // As wide as the view: a wide table fits.
          final padding =
              widget.padding ?? const EdgeInsets.fromLTRB(32, 24, 32, 160);
          final editor = MarkdownEditor(
            key: _editorKey,
            controller: _controller,
            style: _style(context),
            embeds: _embeds,
            focusNode: _focus,
            scrollController: _scroll,
            // Room after the last line, to bring any to the top.
            padding: padding,
            readOnly: widget.readOnly,
            // The bar's keys on a selection only: without one, ⌘B is the
            // workbench's (its side bar).
            onKey: (event) => _controller.selection.isCollapsed
                ? KeyEventResult.ignored
                : _formatBar.currentState?.handleKey(event) ??
                      KeyEventResult.ignored,
            onPaste: _paste,
            onClick: _click,
            // A link clicked shows as it did, its bubble over it.
            revealsLinks: false,
            colorize: colorize,
            keyboardAppearance: themeColors.dark
                ? Brightness.dark
                : Brightness.light,
          );
          return NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              _restSoon();
              return false;
            },
            // As a stash's: its marks, a link and a model's proofreading
            // over the selection.
            child: MarkdownFormatBar(
              key: _formatBar,
              controller: _controller,
              focusNode: _focus,
              editorKey: _editorKey,
              readOnly: widget.readOnly,
              onPolish: (text) => polishStashText(text, note: _controller.text),
              onOpenLink: _openHref,
              contextMenu: _contextMenu,
              child: editor,
            ),
          );
        },
      ),
    );
  }
}

/// The line of [controller]'s heading whose anchor is [anchor], anchors
/// made as GitHub makes them: repeats numbered (`usage-1`).
int? markdownHeading(MarkdownController controller, String anchor) {
  final wanted = markdownSlug(markdownDecode(anchor));
  final taken = <String, int>{};
  for (var line = 0; line < controller.lines.lineCount; line++) {
    final info = controller.infoOf(line);
    if (info.kind != MdLineKind.heading) continue;
    final text = controller.lines.content(line);
    final base = markdownSlug(
      _plainHeading(text.substring(info.contentStart, info.contentEnd)),
    );
    final count = taken[base];
    taken[base] = (count ?? 0) + 1;
    final slug = count == null ? base : '$base-$count';
    if (slug == anchor || slug == wanted) return line;
  }
  return null;
}

/// A heading's text without its marks.
String _plainHeading(String markdown) => markdown
    .replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), '')
    .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (match) => match[1]!)
    .replaceAll(RegExp(r'[*`~]'), '')
    // `_` of emphasis, not within a word (`snake_case`).
    .replaceAll(
      RegExp(r'(?<![\p{L}\p{N}])_+|_+(?![\p{L}\p{N}])', unicode: true),
      '',
    );

/// What the preview shows for what is not text: images (the project's
/// files, the web's), formulas, diagrams, front matter, task boxes.
class _PreviewEmbeds extends MarkdownEmbeds {
  _PreviewEmbeds(this.state);

  final IdeMarkdownPreviewState state;

  @override
  Future<MdTableAction?> tableMenu(
    BuildContext context,
    Rect anchor,
    List<List<MdTableAction>> sections, {
    Set<MdTableAction> checked = const {},
  }) => showMarkdownTableMenu(context, anchor, sections, checked: checked);

  @override
  Widget tableScrollbar(
    BuildContext context,
    ScrollController controller, {
    required bool hovered,
    required EdgeInsets padding,
    required MarkdownEditorStyle style,
    required Widget child,
  }) => markdownTableScrollbar(
    context,
    controller,
    hovered: hovered,
    padding: padding,
    child: child,
  );

  @override
  InlineSpan inline(BuildContext context, MdEmbed embed) {
    final run = embed.run;
    if (run.kind == MdInlineKind.math) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: MathView(embed.line.substring(run.innerStart, run.innerEnd)),
      );
    }
    final alt = embed.line.substring(run.innerStart, run.innerEnd);
    final widget = state.widget;
    final width = run.width;
    Widget image = _MarkdownImage(
      target: resolveMarkdownImage(run.href ?? '', widget.path, state._context),
      alt: alt,
      title: run.title,
      read: state._readImage,
      readNow: (path) => state._imagesRead[path],
    );
    if (width != null) image = SizedBox(width: width, child: image);
    return WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: MdEmbedRegion(child: image),
    );
  }

  @override
  bool showsBlock(MdLineKind kind) =>
      kind == MdLineKind.tableHead ||
      kind == MdLineKind.mathOpen ||
      kind == MdLineKind.mathLine ||
      kind == MdLineKind.frontMatter;

  @override
  bool showsCode(String? language) =>
      language?.trim().split(RegExp(r'\s')).first.toLowerCase() == 'mermaid';

  @override
  Widget? block(
    BuildContext context,
    MdBlockEmbed embed,
    MarkdownEditorStyle style,
  ) {
    if (embed.isTable) return super.block(context, embed, style);
    final Widget shown;
    switch (embed.kind) {
      case MdLineKind.frontMatter:
        // Its properties, each value on its line edited in a field (its
        // source the place for the rest); YAML they do not read as.
        if (parseFrontMatterProperties(embed.code) case final properties?) {
          return MdEmbedRegion(
            child: MarkdownFrontMatter(
              properties: properties,
              onChanged: state.widget.readOnly
                  ? null
                  : (key, value) => embed.replace(
                      setFrontMatterValue(embed.source, key, value),
                    ),
            ),
          );
        }
        shown = MarkdownCodeBlock(code: embed.code, language: 'yaml');
      case MdLineKind.fenceOpen:
        shown = MermaidCodeBlock(code: embed.code);
      default:
        shown = MathView(embed.tex, display: true);
    }
    return MdEmbedRegion(child: shown);
  }

  @override
  Widget checkbox(
    BuildContext context,
    bool checked,
    TextStyle style,
    ValueChanged<bool>? onChanged,
  ) => MdEmbedRegion(
    child: MarkdownTaskBox(checked: checked, onChanged: onChanged),
  );

  @override
  Widget rule(BuildContext context, MarkdownEditorStyle style) {
    // As upstream's chat: the separator's color, faint.
    final separator = themeColors['textSeparator.foreground'];
    return Container(
      height: 1,
      color: separator.withValues(alpha: separator.a * 0.33),
    );
  }

  /// Copied, an image's alt text, a formula's TeX.
  @override
  String plainText(MdInline run, String line) =>
      line.substring(run.innerStart, run.innerEnd);
}

/// An image of the document: a file of the project's host, read with
/// [read], or a web one; its alt text when it cannot be shown.
class _MarkdownImage extends StatelessWidget {
  const _MarkdownImage({
    required this.target,
    required this.alt,
    required this.title,
    required this.read,
    required this.readNow,
  });

  final ({Uri? url, String? path})? target;
  final String alt;
  final String? title;
  final Future<Uint8List> Function(String path) read;

  /// What [read] has read by now.
  final Uint8List? Function(String path) readNow;

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: LayoutBuilder(
                  builder: (context, constraints) => InteractiveViewer(
                    minScale: .1,
                    maxScale: 8,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: SizedBox.fromSize(
                      size: constraints.biggest,
                      child: _image(expanded: true),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              // Below a header the window draws itself: its buttons take
              // the clicks there, over this one.
              top: WindowControls.drawsHeader ? AppMetrics.headerHeight + 8 : 8,
              right: 8,
              child: IdeActionButton(
                icon: Codicons.close,
                tooltip: context.l10n.dialogCloseDialog,
                size: 32,
                iconSize: 20,
                color: Colors.white,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clickable(BuildContext context, Widget image) => MouseRegion(
    cursor: SystemMouseCursors.zoomIn,
    child: GestureDetector(onTap: () => _preview(context), child: image),
  );

  Widget _image({bool expanded = false}) {
    final target = this.target;
    if (target?.url case final url?) {
      return Image.network(
        url.toString(),
        fit: expanded ? BoxFit.contain : null,
        errorBuilder: (context, _, _) => _missing(),
        frameBuilder: (context, child, frame, _) =>
            expanded || frame == null ? child : _clickable(context, child),
      );
    }
    if (target?.path case final path?) {
      return FutureBuilder<Uint8List>(
        future: read(path),
        initialData: readNow(path),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _missing();
          final bytes = snapshot.data;
          if (bytes == null) return const SizedBox(width: 16, height: 16);
          if (p.extension(path).toLowerCase() == '.svg') {
            final image = SvgPicture(
              SvgTextBytesLoader(bytes),
              fit: BoxFit.contain,
              errorBuilder: (context, _, _) => _missing(),
            );
            return expanded ? image : _clickable(context, image);
          }
          return Image.memory(
            bytes,
            fit: expanded ? BoxFit.contain : null,
            errorBuilder: (context, _, _) => _missing(),
            frameBuilder: (context, child, frame, _) =>
                expanded || frame == null ? child : _clickable(context, child),
          );
        },
      );
    }
    return _missing();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image();
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
