// The bar over a markdown editor's selection: its marks (bold, a link, a
// color, a list…) and a model's proofreading; over a web link the caret is
// in, where it goes, opened or edited. A stash's and a markdown file's
// preview alike.

import 'dart:async';
import 'dart:math' as math;

import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../chat/widgets/hover_builder.dart';
import '../../l10n/l10n.dart';
import '../../models/auxiliary_model_menu.dart';
import '../../models/model_providers.dart';
import '../../stash/stash_ai.dart' show StashAiException;
import '../../stash/stash_editor.dart' show StashColors;
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../ide_commands.dart' show IdeKeybinding;
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_menu.dart';
import '../ide_motion.dart';

/// [markdown] (the selection's) as a model is given it, and a reply to it
/// as markdown again.
typedef MarkdownForModel = ({String text, String Function(String reply) back});

/// A link the caret is in: where it goes, its text, where that shows; in
/// a table's [cell] (its editor), of the cell's text.
typedef _CaretLink = ({
  String href,
  TextSelection range,
  Rect around,
  MarkdownEditorState? cell,
});

/// [child], [editorKey]'s editor of [controller], with the bar over its
/// selection (see the file's head).
class MarkdownFormatBar extends StatefulWidget {
  const MarkdownFormatBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.editorKey,
    required this.onOpenLink,
    required this.child,
    this.readOnly = false,
    this.onPolish,
    this.forModel,
    this.linkShown,
    this.contextMenu,
  });

  final MarkdownController controller;
  final FocusNode focusNode;
  final GlobalKey<MarkdownEditorState> editorKey;
  final Widget child;

  /// No bar: nothing is changed.
  final bool readOnly;

  /// [text] proofread (see polishStashText); none hides the bar's AI.
  final Future<String?> Function(String text)? onPolish;

  /// What the model is given of the selection's markdown, and how its reply
  /// goes back; the markdown as it is by default.
  final MarkdownForModel Function(String markdown)? forModel;

  /// Opens a link's address, from the bar over it.
  final void Function(String href) onOpenLink;

  /// Whether the caret in [run], a link to [href], shows the bar over it
  /// (not a stash's card, say); every one by default.
  final bool Function(String href, MdInline run)? linkShown;

  /// The host's own of the right click's menu, last: for where the text
  /// was clicked ([offset]; none past it), its file's, say.
  final List<IdeMenuEntry> Function(int? offset)? contextMenu;

  @override
  State<MarkdownFormatBar> createState() => MarkdownFormatBarState();
}

class MarkdownFormatBarState extends State<MarkdownFormatBar> {
  final GlobalKey _stackKey = GlobalKey();

  /// The selection's bounds, in the stack's box, for the bar over (or
  /// under) it; none without one.
  Rect? _barAround;
  bool _polishing = false;

  /// A menu opened from the bar (the model picker, the marks under "…") is
  /// showing: it takes the keyboard, and the bar stays where it is.
  bool _barMenu = false;

  MarkdownController get _controller => widget.controller;
  FocusNode get _focus => widget.focusNode;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_barSoon);
    _focus.addListener(_barSoon);
    _linkFocus.addListener(_linkFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listenCells();
    });
  }

  /// The editor whose tables' cells are listened to: the caret in one, a
  /// link's bar goes with it.
  MarkdownEditorState? _cellsOf;

  void _listenCells() {
    final editor = widget.editorKey.currentState;
    if (identical(editor, _cellsOf)) return;
    _cellsOf?.tableCellChanges.removeListener(_barSoon);
    _cellsOf = editor;
    editor?.tableCellChanges.addListener(_barSoon);
  }

  /// The editor of the table's cell typed in; none while the caret is in
  /// none.
  MarkdownEditorState? _typedCell() {
    final cell = widget.editorKey.currentState?.tableCell;
    return cell != null && cell.hasFocus ? cell : null;
  }

  /// The keyboard back to where the text was typed: [cell], a table's
  /// cell, or the editor.
  void _refocus(MarkdownEditorState? cell) => cell != null && cell.mounted
      ? cell.requestFocus()
      : _focus.requestFocus();

  @override
  void didUpdateWidget(MarkdownFormatBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_barSoon);
      widget.controller.addListener(_barSoon);
      // Another text: what was edited of the last one's goes.
      _linking = false;
      _applyLink = null;
      _caretLink = null;
      _barAround = null;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_barSoon);
      widget.focusNode.addListener(_barSoon);
    }
    if (oldWidget.readOnly != widget.readOnly) _barSoon();
  }

  @override
  void dispose() {
    _controller.removeListener(_barSoon);
    _focus.removeListener(_barSoon);
    _cellsOf?.tableCellChanges.removeListener(_barSoon);
    _linkFocus.dispose();
    _linkText.dispose();
    super.dispose();
  }

  bool _barScheduled = false;

  /// The bar (and the link's) where the selection is, once it is laid out.
  void _barSoon() {
    if (_barScheduled) return;
    _barScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barScheduled = false;
      if (mounted) _placeBar();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _placeBar() {
    _listenCells();
    final selection = _controller.selection;
    Rect? around;
    if (_contextMenu) {
      // The right click's menu shows alone.
    } else if (_linkCell case final cell? when _linking && cell.mounted) {
      // A link's address typed for a table's cell: over its text there.
      around = _selectionBounds(cell.controller.selection, cell);
    } else if (!widget.readOnly &&
        (_focus.hasFocus || _linking || _barMenu) &&
        selection.isValid &&
        !selection.isCollapsed &&
        // In code (a table's source…), only proofreading: none without it.
        (widget.onPolish != null || !_inRaw(selection))) {
      around = _selectionBounds(selection);
    }
    final link = around == null ? _linkAtCaret() : null;
    if (around == _barAround &&
        link?.href == _caretLink?.href &&
        link?.range == _caretLink?.range &&
        link?.around == _caretLink?.around &&
        link?.cell == _caretLink?.cell &&
        _barVersion == _controller.textVersion) {
      return;
    }
    setState(() {
      _barAround = around;
      _caretLink = link;
      _barVersion = _controller.textVersion;
    });
  }

  /// The text the bar's marks were read from.
  int _barVersion = -1;

  /// Shows the bar while a menu opened from it shows, and keeps it once
  /// one closes: the editor's focus comes back with the menu.
  void _barMenuShown(bool open) {
    if (!mounted || _barMenu == open) return;
    setState(() => _barMenu = open);
    if (!open) _barSoon();
  }

  /// The web link the caret is in, and where its text is (stack's box):
  /// a bar over it opens or edits it, the text typed on as ever. In a
  /// table's [cell], [range] is of the cell's text.
  _CaretLink? _caretLink;

  _CaretLink? _linkAtCaret() {
    if (widget.readOnly || _contextMenu || !_focus.hasFocus || _linking) {
      return null;
    }
    final cell = _typedCell();
    final text = cell?.controller ?? _controller;
    final selection = text.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final link = _webLinkAt(selection.baseOffset, text);
    if (link == null) return null;
    final around = _selectionBounds(link.range, cell);
    if (around == null) return null;
    return (href: link.href, range: link.range, around: around, cell: cell);
  }

  /// The link [offset] is in (not at its ends) of [text] (the editor's by
  /// default): where it goes, and its text.
  ({String href, TextSelection range})? _webLinkAt(
    int offset, [
    MarkdownController? text,
  ]) {
    text ??= _controller;
    final found = text.linkAt(offset);
    if (found == null) return null;
    final (line, run) = found;
    final start = text.lineStart(line);
    final column = offset - start;
    final href = run.href;
    if (href == null ||
        !(run.start < column && column < run.end) ||
        !(widget.linkShown?.call(href, run) ?? true)) {
      return null;
    }
    return (
      href: href,
      range: TextSelection(
        baseOffset: start + run.innerStart,
        extentOffset: start + run.innerEnd,
      ),
    );
  }

  /// [selection]'s bounds (of [cell]'s text, a table's cell's, if given),
  /// in the stack's box: what of it is in the editor's view, none where it
  /// is scrolled out of it.
  Rect? _selectionBounds(TextSelection selection, [MarkdownEditorState? cell]) {
    final editor = widget.editorKey.currentState;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (editor == null || stack == null || !stack.attached) return null;
    final rects = (cell ?? editor).selectionRects(selection);
    if (rects.isEmpty) return null;
    var bounds = rects.reduce((a, b) => a.expandToInclude(b));
    if (editor.viewportRect case final view?) {
      if (!bounds.overlaps(view)) return null;
      bounds = bounds.intersect(view);
    }
    return Rect.fromPoints(
      stack.globalToLocal(bounds.topLeft),
      stack.globalToLocal(bounds.bottomRight),
    );
  }

  /// The text scrolled: the bar goes with the selection at once (by as
  /// much as it was scrolled), where it is laid out then once it is.
  bool _scrolled(ScrollUpdateNotification notification) {
    final delta = notification.scrollDelta;
    if (notification.metrics.axis == Axis.vertical &&
        delta != null &&
        delta != 0 &&
        (_barAround != null || _caretLink != null) &&
        // Not while laying out (the text scrolled to its caret).
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      final by = Offset(0, -delta);
      setState(() {
        _barAround = _barAround?.shift(by);
        if (_caretLink case final link?) {
          _caretLink = (
            href: link.href,
            range: link.range,
            around: link.around.shift(by),
            cell: link.cell,
          );
        }
      });
    }
    _barSoon();
    return false;
  }

  // --- Keys ---------------------------------------------------------------------

  /// ⌘B, ⌘I and ⌘U mark the selection, ⌘K links it (Ctrl elsewhere):
  /// what the editor's [MarkdownEditor.onKey] asks first.
  KeyEventResult handleKey(KeyEvent event) {
    if (event is KeyUpEvent ||
        widget.readOnly ||
        _controller.isComposing ||
        _inRaw(_controller.selection)) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (!command || keyboard.isShiftPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyK when !_controller.selection.isCollapsed:
        link();
      case LogicalKeyboardKey.keyB:
        _controller.toggleInline(MdInlineKind.strong);
      case LogicalKeyboardKey.keyI:
        _controller.toggleInline(MdInlineKind.emphasis);
      case LogicalKeyboardKey.keyU:
        _controller.toggleUnderline();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Whether [selection] is on a line whose text is not markdown's (code,
  /// math, a table's source, HTML): no marks there.
  bool _inRaw(TextSelection selection) {
    if (!selection.isValid) return false;
    final last = _controller.lineAt(selection.end);
    for (var line = _controller.lineAt(selection.start); line <= last; line++) {
      final info = _controller.infoOf(line);
      if (!info.hasInline &&
          info.kind != MdLineKind.blank &&
          info.kind != MdLineKind.setextUnderline) {
        return true;
      }
    }
    return false;
  }

  // --- Marks ------------------------------------------------------------------------

  bool _has(MdInlineKind kind, {String? tag}) =>
      _controller.isInline(kind, tag: tag);

  void _toggle(MdInlineKind kind) {
    if (kind == MdInlineKind.styleTag) {
      _controller.toggleUnderline();
    } else {
      _controller.toggleInline(kind);
    }
    _focus.requestFocus();
  }

  void _format(MdLineFormat format) {
    _controller.setLineFormat(format);
    _focus.requestFocus();
  }

  void _color(String key, String? name) {
    if (key == 'background') {
      _controller.setColor(
        background: name,
        setColor: false,
        setBackground: true,
      );
    } else {
      _controller.setColor(color: name);
    }
    _focus.requestFocus();
  }

  void _clearFormat() {
    _controller.clearInline();
    _focus.requestFocus();
  }

  // --- Links ------------------------------------------------------------------------

  /// The link typed in the bar, in place of its buttons, while one is.
  bool _linking = false;
  final TextEditingController _linkText = TextEditingController();
  final FocusNode _linkFocus = FocusNode();

  /// What the link typed does, in place of linking the selection to it.
  void Function(String href)? _applyLink;

  /// Where the selection goes, typed in the bar ([current] there first);
  /// [apply] given it in place of linking the selection to it.
  void link({String? current, void Function(String href)? apply}) {
    _applyLink = apply;
    _linkText.text =
        current ?? _webLinkAt(_controller.selection.start + 1)?.href ?? '';
    _linkText.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _linkText.text.length,
    );
    setState(() => _linking = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_linking) _linkFocus.requestFocus();
    });
  }

  /// The table's cell whose link's address is typed in the bar: open
  /// meanwhile, the keyboard the bar's.
  MarkdownEditorState? _linkCell;

  /// [range], a link's text (of [cell]'s, a table's cell's, if given),
  /// selected, where it goes ([href]) edited in the bar (see [link]).
  void editLink(
    String href,
    TextSelection range, {
    void Function(String href)? apply,
    MarkdownEditorState? cell,
  }) {
    if (cell != null && cell.mounted) {
      _linkCell = cell;
      widget.editorKey.currentState?.holdTableCell(true);
      cell.controller.selection = range;
    } else {
      _controller.selection = range;
      _focus.requestFocus();
    }
    link(current: href, apply: apply);
  }

  /// The table's cell a link was edited for let go: closed unless the
  /// keyboard is back in it.
  void _releaseLinkCell() {
    if (_linkCell == null) return;
    _linkCell = null;
    widget.editorKey.currentState?.holdTableCell(false);
  }

  /// The link typed, on the selection (none for an empty one); back to the
  /// text either way.
  void _endLink({required bool apply}) {
    if (!_linking) return;
    final custom = _applyLink;
    _applyLink = null;
    final cell = _linkCell;
    final href = _linkText.text.trim();
    if (apply && custom != null) {
      custom(href);
    } else if (apply && (cell == null || cell.mounted)) {
      (cell?.controller ?? _controller).setLink(href.isEmpty ? null : href);
    }
    setState(() => _linking = false);
    _refocus(cell);
    _releaseLinkCell();
  }

  /// Clicked elsewhere: what was typed is dropped.
  void _linkFocusChanged() {
    if (_linking && !_linkFocus.hasFocus) {
      _applyLink = null;
      setState(() => _linking = false);
      _releaseLinkCell();
      _barSoon();
    }
  }

  Widget _linkField(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Codicons.link, size: 14, color: AppColors.textMuted),
      const SizedBox(width: 6),
      SizedBox(
        width: 240,
        child: IdeInputBox(
          controller: _linkText,
          focusNode: _linkFocus,
          placeholder: 'https://',
          fontSize: 12.5,
          semanticsLabel: context.l10n.stashLinkTitle,
          onSubmitted: (_) => _endLink(apply: true),
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _endLink(apply: false),
          },
        ),
      ),
      const SizedBox(width: 2),
      _BarButton(
        icon: Codicons.check,
        tooltip: context.l10n.commonOk,
        onTap: () => _endLink(apply: true),
      ),
    ],
  );

  /// Over the link the caret is in (a click puts it there, not opening
  /// it): where it goes, opened; its address copied or edited; the link
  /// taken off its text.
  Widget _linkBar(BuildContext context) {
    final link = _caretLink!;
    final l10n = context.l10n;
    return _SelectionBar(
      around: link.around,
      children: [
        _BarButton(
          icon: _linkIcon(link.href),
          label: _shortUrl(link.href),
          tooltip: l10n.stashLinkOpen,
          onTap: () => widget.onOpenLink(link.href),
        ),
        const _BarDivider(),
        _BarButton(
          icon: Codicons.copy,
          tooltip: l10n.stashLinkCopy,
          onTap: () => _copyLink(link.href, cell: link.cell),
        ),
        _BarButton(
          icon: Codicons.edit,
          tooltip: l10n.stashLinkEdit,
          onTap: () => editLink(link.href, link.range, cell: link.cell),
        ),
        _BarButton(
          icon: Codicons.close,
          tooltip: l10n.stashLinkRemove,
          onTap: () => _removeLink(link.range, cell: link.cell),
        ),
      ],
    );
  }

  /// What [href] goes to: a heading of the text's, a page on the web, a
  /// file.
  static IconData _linkIcon(String href) {
    if (href.startsWith('#')) return Codicons.listTree;
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(href) &&
        !href.startsWith('file:')) {
      return Codicons.globe;
    }
    return Codicons.file;
  }

  /// [url] without its scheme, its escapes read, cut short.
  static String _shortUrl(String url) {
    var bare = url.replaceFirst(RegExp(r'^https?://'), '');
    try {
      bare = Uri.decodeFull(bare);
    } on ArgumentError {
      // Not escaped as a URL's are: as it is.
    }
    return bare.length > 40 ? '${bare.substring(0, 39)}…' : bare;
  }

  void _copyLink(String href, {MarkdownEditorState? cell}) {
    unawaited(Clipboard.setData(ClipboardData(text: href)));
    _refocus(cell);
  }

  /// The link whose text is [range] (of [cell]'s, a table's cell's, if
  /// given) taken off it, the text kept.
  void _removeLink(TextSelection range, {MarkdownEditorState? cell}) {
    // The cell closed meanwhile: its range is no longer its text's.
    if (widget.readOnly || (cell != null && !cell.mounted)) return;
    final text = cell?.controller ?? _controller;
    text.selection = range;
    text.setLink(null);
    _refocus(cell);
  }

  // --- The right click's menu ------------------------------------------------------

  /// Its menu showing: no bar over the selection or a link meanwhile.
  bool _contextMenu = false;

  /// What there is to do where the text was right-clicked ([global]): its
  /// link's, the clipboard's, Undo's, the selection's marks. The caret
  /// goes there first, unless it was in the selection.
  Future<void> _showContextMenu(Offset global) async {
    final editor = widget.editorKey.currentState;
    if (editor == null || _contextMenu) return;
    final at = editor.offsetAt(global);
    var selection = _controller.selection;
    final inSelection =
        at != null &&
        selection.isValid &&
        !selection.isCollapsed &&
        at >= selection.start &&
        at <= selection.end;
    if (at != null && !inSelection) {
      _controller.selection = TextSelection.collapsed(offset: at);
      selection = _controller.selection;
    }
    _focus.requestFocus();
    final link = at == null ? null : _webLinkAt(at);
    final editable = !widget.readOnly;
    final selected = selection.isValid && !selection.isCollapsed;
    final marks = editable && selected && !_inRaw(selection);
    final l10n = context.l10n;
    String? keys(LogicalKeyboardKey key, {bool shift = false}) =>
        IdeKeybinding(key, primary: true, shift: shift).label();
    setState(() {
      _contextMenu = true;
      _barAround = null;
      _caretLink = null;
    });
    try {
      await showIdeMenu(
        context,
        position: global,
        entries: ideMenuGroups([
          if (link != null)
            [
              IdeMenuAction(
                l10n.stashLinkOpen,
                onSelected: () => widget.onOpenLink(link.href),
              ),
              IdeMenuAction(
                l10n.stashLinkCopy,
                onSelected: () => _copyLink(link.href),
              ),
              if (editable) ...[
                IdeMenuAction(
                  l10n.stashLinkEdit,
                  onSelected: () => editLink(link.href, link.range),
                ),
                IdeMenuAction(
                  l10n.stashLinkRemove,
                  onSelected: () => _removeLink(link.range),
                ),
              ],
            ],
          if (editable)
            [
              IdeMenuAction(
                l10n.commonUndo,
                keybinding: keys(LogicalKeyboardKey.keyZ),
                enabled: _controller.canUndo,
                onSelected: _controller.undo,
              ),
              IdeMenuAction(
                l10n.commonRedo,
                keybinding: keys(LogicalKeyboardKey.keyZ, shift: true),
                enabled: _controller.canRedo,
                onSelected: _controller.redo,
              ),
            ],
          [
            if (editable)
              IdeMenuAction(
                l10n.commonCut,
                keybinding: keys(LogicalKeyboardKey.keyX),
                enabled: selected,
                onSelected: () => unawaited(editor.copy(cut: true)),
              ),
            IdeMenuAction(
              l10n.commonCopy,
              keybinding: keys(LogicalKeyboardKey.keyC),
              enabled: selected,
              onSelected: () => unawaited(editor.copy()),
            ),
            if (editable)
              IdeMenuAction(
                l10n.commonPaste,
                keybinding: keys(LogicalKeyboardKey.keyV),
                onSelected: () => unawaited(editor.paste()),
              ),
            IdeMenuAction(
              l10n.commonSelectAll,
              keybinding: keys(LogicalKeyboardKey.keyA),
              onSelected: () => _controller.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _controller.length,
              ),
            ),
          ],
          if (marks)
            [
              IdeMenuAction(
                l10n.stashFormatLink,
                keybinding: keys(LogicalKeyboardKey.keyK),
                onSelected: () => this.link(),
              ),
              IdeMenuAction(
                l10n.stashFormatMenu,
                submenu: _formatEntries(l10n, keys),
              ),
            ],
          ?widget.contextMenu?.call(at),
        ]),
      );
    } finally {
      if (mounted) {
        setState(() => _contextMenu = false);
        _focus.requestFocus();
        _barSoon();
      }
    }
  }

  /// Every mark there is for the selection, those it has checked.
  List<IdeMenuEntry> _formatEntries(
    AppLocalizations l10n,
    String? Function(LogicalKeyboardKey key) keys,
  ) {
    final format = _controller.lineFormat;
    IdeMenuAction inline(String label, MdInlineKind kind, {String? key}) =>
        IdeMenuAction(
          label,
          keybinding: key,
          checked: _has(kind),
          onSelected: () => _toggle(kind),
        );
    IdeMenuAction line(String label, MdLineFormat value) => IdeMenuAction(
      label,
      checked: format == value,
      onSelected: () => _format(value),
    );
    return [
      inline(
        l10n.stashFormatBold,
        MdInlineKind.strong,
        key: keys(LogicalKeyboardKey.keyB),
      ),
      inline(
        l10n.stashFormatItalic,
        MdInlineKind.emphasis,
        key: keys(LogicalKeyboardKey.keyI),
      ),
      IdeMenuAction(
        l10n.stashFormatUnderline,
        keybinding: keys(LogicalKeyboardKey.keyU),
        checked: _has(MdInlineKind.styleTag, tag: 'u'),
        onSelected: () => _toggle(MdInlineKind.styleTag),
      ),
      inline(l10n.stashFormatStrike, MdInlineKind.strike),
      inline(l10n.stashFormatCode, MdInlineKind.code),
      const IdeMenuSeparator(),
      line(l10n.stashFormatHeading1, MdLineFormat.heading1),
      line(l10n.stashFormatHeading2, MdLineFormat.heading2),
      line(l10n.stashFormatHeading3, MdLineFormat.heading3),
      const IdeMenuSeparator(),
      line(l10n.stashFormatBullets, MdLineFormat.bullet),
      line(l10n.stashFormatNumbers, MdLineFormat.numbered),
      line(l10n.stashFormatTasks, MdLineFormat.task),
      line(l10n.stashFormatQuote, MdLineFormat.quote),
      line(l10n.stashFormatCodeBlock, MdLineFormat.code),
      const IdeMenuSeparator(),
      IdeMenuAction(l10n.stashFormatClear, onSelected: _clearFormat),
    ];
  }

  // --- Proofreading -------------------------------------------------------------

  Future<void> _polish() async {
    final polish = widget.onPolish;
    final selection = _controller.selection;
    if (polish == null || selection.isCollapsed || _polishing) return;
    final slice = _controller.substring(selection.start, selection.end);
    final asked = widget.forModel?.call(slice) ?? _asIs(slice);
    if (asked.text.trim().isEmpty) return;
    setState(() => _polishing = true);
    try {
      final String? better;
      try {
        better = await polish(asked.text);
      } on StashAiException catch (error) {
        if (!mounted) return;
        final l10n = context.l10n;
        await showIdeDialog(
          context,
          message: l10n.stashPolishFailed(
            error.message ?? l10n.stashAiNoAnswer,
          ),
          buttons: [l10n.commonOk],
          cancel: null,
          type: IdeDialogType.error,
        );
        return;
      }
      if (better == null || !mounted) return;
      // Only if the text is as it was when asked.
      if (selection.end > _controller.length ||
          _controller.substring(selection.start, selection.end) != slice) {
        return;
      }
      final replaced = asked.back(better);
      _controller.breakUndo();
      _controller.replace(
        selection.start,
        selection.end,
        replaced,
        selection: TextSelection(
          baseOffset: selection.start,
          extentOffset: selection.start + replaced.length,
        ),
      );
      _controller.breakUndo();
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  /// [markdown] as it is, a reply in the text's line breaks, the line it
  /// ended still ended.
  MarkdownForModel _asIs(String markdown) {
    final newline = _controller.lines.newline;
    final ended = RegExp(r'(\r\n|\r|\n)$').hasMatch(markdown);
    return (
      text: markdown,
      back: (reply) {
        var text = reply.replaceAll(RegExp('\r\n|\r|\n'), newline);
        if (ended && !text.endsWith(newline)) text = text.trimRight() + newline;
        return text;
      },
    );
  }

  // --- Building ---------------------------------------------------------------------

  Widget _bar(BuildContext context, Rect around) {
    final l10n = context.l10n;
    final format = _controller.lineFormat;
    Widget button(
      IconData icon,
      String tip,
      VoidCallback onTap, {
      bool active = false,
    }) => _BarButton(icon: icon, tooltip: tip, onTap: onTap, active: active);
    final raw = _inRaw(_controller.selection);
    // What is used most; the rest under "…". In code, only proofreading.
    final items = <Widget>[
      if (!raw) ...[
        button(
          Codicons.bold,
          l10n.stashFormatBold,
          () => _toggle(MdInlineKind.strong),
          active: _has(MdInlineKind.strong),
        ),
        button(
          Codicons.italic,
          l10n.stashFormatItalic,
          () => _toggle(MdInlineKind.emphasis),
          active: _has(MdInlineKind.emphasis),
        ),
        button(
          Codicons.strikethrough,
          l10n.stashFormatStrike,
          () => _toggle(MdInlineKind.strike),
          active: _has(MdInlineKind.strike),
        ),
        button(
          Codicons.code,
          l10n.stashFormatCode,
          () => _toggle(MdInlineKind.code),
          active: _has(MdInlineKind.code),
        ),
        button(
          Codicons.link,
          l10n.stashFormatLink,
          link,
          active: _has(MdInlineKind.link),
        ),
        _ColorButton(
          tooltip: l10n.stashFormatColor,
          onPick: (key, name) => _color(key, name),
        ),
        const _BarDivider(),
        button(
          Codicons.listUnordered,
          l10n.stashFormatBullets,
          () => _format(MdLineFormat.bullet),
          active: format == MdLineFormat.bullet,
        ),
        button(
          Codicons.checklist,
          l10n.stashFormatTasks,
          () => _format(MdLineFormat.task),
          active: format == MdLineFormat.task,
        ),
        Builder(
          builder: (context) => _BarButton(
            icon: Codicons.ellipsis,
            tooltip: l10n.stashFormatMore,
            active: _moreActive(),
            onTap: () {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              unawaited(
                _more(context, box.localToGlobal(Offset.zero) & box.size),
              );
            },
          ),
        ),
      ],
      if (widget.onPolish != null) ...[
        if (!raw) const _BarDivider(),
        Builder(
          builder: (context) => _BarButton(
            icon: Codicons.sparkle,
            label: _polishing ? l10n.stashPolishing : l10n.stashPolish,
            tooltip: l10n.stashPolishHint,
            onTap: () {
              if (anchorOf(context) case final anchor?) {
                unawaited(withActionsModel(context, anchor, _polish));
              }
            },
            busy: _polishing,
          ),
        ),
        Builder(
          builder: (context) => _BarButton(
            icon: Codicons.chevronDown,
            tooltip: l10n.aiModelTooltip(
              actionsModelName(l10n, ModelProviders.current) ??
                  l10n.aiModelNone,
            ),
            onTap: () {
              if (anchorOf(context) case final anchor?) {
                unawaited(pickActionsModel(context, anchor));
              }
            },
          ),
        ),
      ],
    ];
    return _SelectionBar(
      around: around,
      children: _linking ? [_linkField(context)] : items,
    );
  }

  /// The bar, told when a menu opened from it shows and hides: while one
  /// does, the bar stays (see [_barMenuShown]).
  Widget _barWithMenus(BuildContext context, Rect around) =>
      IdeMenuAnchorScope(onMenu: _barMenuShown, child: _bar(context, around));

  /// Whether the selection has one of the marks under "…".
  bool _moreActive() {
    final format = _controller.lineFormat;
    return format == MdLineFormat.heading1 ||
        format == MdLineFormat.heading2 ||
        format == MdLineFormat.heading3 ||
        format == MdLineFormat.numbered ||
        format == MdLineFormat.quote ||
        _has(MdInlineKind.styleTag, tag: 'u');
  }

  /// The marks used less, in a menu under "…": [from] the button's context,
  /// under the bar's scope (see [_barWithMenus]).
  Future<void> _more(BuildContext from, Rect anchor) async {
    final l10n = from.l10n;
    final format = _controller.lineFormat;
    await showIdeMenu(
      from,
      anchor: anchor,
      entries: [
        IdeMenuAction(
          l10n.stashFormatHeading1,
          checked: format == MdLineFormat.heading1,
          onSelected: () => _format(MdLineFormat.heading1),
        ),
        IdeMenuAction(
          l10n.stashFormatHeading2,
          checked: format == MdLineFormat.heading2,
          onSelected: () => _format(MdLineFormat.heading2),
        ),
        IdeMenuAction(
          l10n.stashFormatHeading3,
          checked: format == MdLineFormat.heading3,
          onSelected: () => _format(MdLineFormat.heading3),
        ),
        const IdeMenuSeparator(),
        IdeMenuAction(
          l10n.stashFormatNumbers,
          checked: format == MdLineFormat.numbered,
          onSelected: () => _format(MdLineFormat.numbered),
        ),
        IdeMenuAction(
          l10n.stashFormatQuote,
          checked: format == MdLineFormat.quote,
          onSelected: () => _format(MdLineFormat.quote),
        ),
        IdeMenuAction(
          l10n.stashFormatCodeBlock,
          checked: format == MdLineFormat.code,
          onSelected: () => _format(MdLineFormat.code),
        ),
        IdeMenuAction(
          l10n.stashFormatUnderline,
          checked: _has(MdInlineKind.styleTag, tag: 'u'),
          onSelected: () => _toggle(MdInlineKind.styleTag),
        ),
        const IdeMenuSeparator(),
        IdeMenuAction(l10n.stashFormatClear, onSelected: _clearFormat),
      ],
    );
    // Back in the text, its selection as it was.
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _stackKey,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: _scrolled,
            // What is right-clicked in it (a chip, a table's cell) first.
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onSecondaryTapUp: (details) =>
                  unawaited(_showContextMenu(details.globalPosition)),
              child: widget.child,
            ),
          ),
        ),
        // Its menus grow in from a little, as the stash's do.
        if (_barAround case final around?)
          IdeMotion(lively: true, child: _barWithMenus(context, around))
        else if (_caretLink != null)
          IdeMotion(lively: true, child: _linkBar(context)),
      ],
    );
  }
}

// --- The bar over the selection ------------------------------------------------

/// Over the selection, or under it where there is no room above (it
/// never covers what is selected while there is room for it at all).
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.around, required this.children});

  final Rect around;
  final List<Widget> children;

  static const _height = 32.0;
  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final above = around.top - _gap - _height;
          final below = around.bottom + _gap;
          final double top;
          var over = true;
          if (above >= 0) {
            top = above;
          } else if (below + _height <= box.maxHeight) {
            top = below;
            over = false;
          } else {
            // Selected past both ends: over the end in view.
            top = math.max(0, box.maxHeight - _height - _gap);
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: top,
                // The editor's own: a click on it is not one beside the
                // editor, which would take its focus (and the bar) away
                // before the button had it.
                child: TextFieldTapRegion(
                  // Coming in from the selection's side.
                  child: PopIn(
                    alignment: over
                        ? Alignment.bottomCenter
                        : Alignment.topCenter,
                    offset: Offset(0, over ? 4 : -4),
                    child: _bar(around.center.dx),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(double x) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bar = Container(
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: themeColors['editorWidget.background'],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: themeColors['editorWidget.border']),
            boxShadow: [
              BoxShadow(
                color: themeColors['widget.shadow'],
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        );
        return Align(
          alignment: Alignment(
            ((x / math.max(1, constraints.maxWidth)) * 2 - 1).clamp(-1, 1),
            0,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: bar,
          ),
        );
      },
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: AppColors.border,
  );
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? label;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.textPrimary : AppColors.textMuted;
    return IdeHover(
      message: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          // Keeps the editor's focus (and selection).
          onTapDown: (_) {},
          onTap: busy ? null : onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 24,
            constraints: const BoxConstraints(minWidth: 24),
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 6),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: active
                  ? themeColors['toolbar.activeBackground']
                  : hovered
                  ? themeColors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: label != null && icon == Icons.title
                ? Text(
                    label!,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: busy ? AppColors.accent : color,
                      ),
                      if (label case final label?) ...[
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: TextStyle(color: color, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The text's and the background's colors, in a menu.
class _ColorButton extends StatefulWidget {
  const _ColorButton({required this.tooltip, required this.onPick});

  final String tooltip;
  final void Function(String key, String? name) onPick;

  @override
  State<_ColorButton> createState() => _ColorButtonState();
}

class _ColorButtonState extends State<_ColorButton> {
  final _key = GlobalKey();
  OverlayEntry? _entry;

  void _open() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context);
    final origin = box.localToGlobal(
      Offset(0, box.size.height + 6),
      ancestor: overlay.context.findRenderObject(),
    );
    final palette = StashColors.palette(dark: themeColors.dark);
    Widget swatch(String key, String? name, {required bool background}) {
      final color = name == null ? null : palette[name];
      return GestureDetector(
        onTap: () {
          _close();
          widget.onPick(key, name);
        },
        child: Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: background ? color : null,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            name == null ? '∅' : 'A',
            style: TextStyle(
              color: background ? AppColors.text : (color ?? AppColors.text),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      );
    }

    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _close,
            ),
          ),
          Positioned(
            left: origin.dx,
            top: origin.dy,
            // Like the bar, picking a color is still inside the editor.
            child: TextFieldTapRegion(
              child: PopIn(
                alignment: Alignment.topLeft,
                offset: const Offset(0, -4),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: themeColors['editorWidget.background'],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: themeColors['editorWidget.border'],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: themeColors['widget.shadow'],
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          swatch('color', null, background: false),
                          for (final name in StashColors.text)
                            swatch('color', name, background: false),
                        ],
                      ),
                      Row(
                        children: [
                          swatch('background', null, background: true),
                          for (final name in StashColors.background)
                            swatch('background', name, background: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: _key,
    child: _BarButton(
      icon: Codicons.symbolColor,
      tooltip: widget.tooltip,
      onTap: _open,
    ),
  );
}
