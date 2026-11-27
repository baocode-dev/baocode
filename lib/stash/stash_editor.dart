import 'dart:async';
import 'dart:math' as math;

import 'package:bao_markdown/bao_markdown.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../base/smooth_scroll.dart' show SmoothScrollController;
import '../chat/chat_models.dart' show ImageAttachment;
import '../chat/composer/composer_files.dart';
import '../chat/composer/file_drop.dart';
import '../chat/floating/hover_tooltip.dart';
import '../chat/widgets/code_citation.dart' show CodeBlockColorizer;
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/image_thumbnails.dart' show showImageGallery;
import '../chat/widgets/markdown_math.dart';
import '../chat/widgets/scroll_edge_fade.dart';
import '../forge/forge_api.dart' show ForgeState;
import '../forge/forge_view.dart' show ForgeStateIcon;
import '../ide/ide_dialog.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_menu.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/material_file_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/editor_launcher.dart' show openExternal;
import '../workspace/window_controls.dart';
import '../ide/ide_motion.dart';
import '../ide/markdown/markdown_format_bar.dart';
import '../ide/markdown/markdown_table_menu.dart';
import '../ide/markdown/markdown_task_box.dart';
import 'stash_forge.dart';
import 'stash_html.dart';
import 'stash_io_stub.dart' if (dart.library.io) 'stash_io.dart' as io;
import 'stash_markdown.dart';
import 'stash_note.dart' show StashNote;
import 'stash_store.dart';

/// What the editor's pictures and files need: where the stash's folder
/// is, and the stash's number (made on the first picture, for a new one
/// nothing was written in yet).
class StashEditorScope extends InheritedWidget {
  const StashEditorScope({
    super.key,
    required this.store,
    required this.ensureNote,
    this.readOnly = false,
    this.onCard,
    required super.child,
  });

  final StashStore store;

  /// A link's tag clicked, at its offset, linking to the url: its menu.
  final void Function(int offset, String url)? onCard;

  /// The stash's number, the stash made first if it was not yet.
  final Future<int> Function() ensureNote;
  final bool readOnly;

  static StashEditorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StashEditorScope>();

  @override
  bool updateShouldNotify(StashEditorScope oldWidget) =>
      store != oldWidget.store || readOnly != oldWidget.readOnly;
}

/// What `[[`, `@` and `#` offer in a stash's text: other stashes (by
/// title, or number), projects. Picked, they go in as links: `stash:12`,
/// `project:<path>`, which [open] follows.
class StashRefs {
  const StashRefs({
    required this.stashes,
    required this.projects,
    required this.open,
  });

  final List<({int id, String title})> Function() stashes;
  final List<({String name, String path})> Function() projects;
  final void Function(String href) open;

  static const stashScheme = 'stash:';
  static const projectScheme = 'project:';

  static String stashHref(int id) => '$stashScheme$id';
  static String projectHref(String path) =>
      '$projectScheme${Uri.encodeComponent(path)}';

  /// The stash a link is to; null for another link.
  static int? stashOf(String href) => href.startsWith(stashScheme)
      ? int.tryParse(href.substring(stashScheme.length))
      : null;

  /// The project a link is to; null for another link.
  static String? projectOf(String href) => href.startsWith(projectScheme)
      ? Uri.decodeComponent(href.substring(projectScheme.length))
      : null;
}

/// The colors a selection can be given: the text's, and the background's
/// (CSS names, which the file keeps and other editors read; their colors
/// here follow the theme).
abstract final class StashColors {
  static const text = [
    'red',
    'orange',
    'gold',
    'green',
    'royalblue',
    'purple',
    'gray',
  ];
  static const background = [
    'mistyrose',
    'peachpuff',
    'lightyellow',
    'honeydew',
    'aliceblue',
    'lavender',
    'gainsboro',
  ];

  static Map<String, Color> palette({required bool dark}) => {
    'red': const Color(0xFFE5534B),
    'orange': const Color(0xFFE0823D),
    'gold': const Color(0xFFD4A72C),
    'green': const Color(0xFF57AB5A),
    'royalblue': const Color(0xFF539BF5),
    'purple': const Color(0xFFB083F0),
    'gray': const Color(0xFF8B949E),
    'mistyrose': dark ? const Color(0x55E5534B) : const Color(0xFFFFE1DF),
    'peachpuff': dark ? const Color(0x55E0823D) : const Color(0xFFFFE6CC),
    'lightyellow': dark ? const Color(0x55D4A72C) : const Color(0xFFFFF5B8),
    'honeydew': dark ? const Color(0x5557AB5A) : const Color(0xFFDDF4DE),
    'aliceblue': dark ? const Color(0x55539BF5) : const Color(0xFFDCEBFF),
    'lavender': dark ? const Color(0x55B083F0) : const Color(0xFFECE2FF),
    'gainsboro': dark ? const Color(0x558B949E) : const Color(0xFFE8EAED),
  };
}

/// A stash's text, edited as it shows (see docs/stash.md): its markdown,
/// its marks shown where the caret is (see [MarkdownEditor]). No `/`
/// commands; marks are typed as markdown is (`# `, `- `, `[] `, `> `,
/// `**…**`) or picked from the bar that shows over a selection, where AI
/// can also make what is selected clearer. Pictures are pasted or dropped
/// in; files are put in (copied up to 200 MB, else linked to); a link
/// pasted alone shows as a card with its page's title.
class StashEditor extends StatefulWidget {
  /// Colors a code block's lines in a language (the app's TextMate, set as
  /// it starts); none under test.
  static CodeBlockColorizer? colorize;

  /// A controller for [markdown], the caret at its end.
  static MarkdownController controllerFor(String markdown) =>
      MarkdownController(
        text: markdown,
        selection: TextSelection.collapsed(offset: markdown.length),
      );

  const StashEditor({
    super.key,
    required this.controller,
    required this.store,
    required this.ensureNote,
    this.focusNode,
    this.scrollController,
    this.autofocus = false,
    this.placeholder,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
    this.onPolish,
    this.readOnly = false,
    this.refs,
  });

  /// What `[[`, `@` and `#` offer; nothing without it.
  final StashRefs? refs;

  final MarkdownController controller;
  final StashStore store;
  final Future<int> Function() ensureNote;
  final FocusNode? focusNode;
  final ScrollController? scrollController;
  final bool autofocus;
  final String? placeholder;
  final EdgeInsets padding;

  /// [text] made clearer (see StashAi.polish); none hides the bar's AI.
  final MarkdownPolish? onPolish;
  final bool readOnly;

  @override
  State<StashEditor> createState() => StashEditorState();
}

class StashEditorState extends State<StashEditor> implements FileDropDelegate {
  final GlobalKey<MarkdownEditorState> _editorKey = GlobalKey();
  late FocusNode _focus = widget.focusNode ?? FocusNode();
  late ScrollController _scroll =
      widget.scrollController ?? SmoothScrollController();
  final GlobalKey _stackKey = GlobalKey();
  late final _StashEmbeds _embeds = _StashEmbeds(this);

  final GlobalKey<MarkdownFormatBarState> _formatBar = GlobalKey();

  MarkdownController get _controller => widget.controller;

  /// The editor itself.
  MarkdownEditorState? get markdownEditor => _editorKey.currentState;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(StashEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      // Another stash's text: what was edited of the last one's goes.
      _ref = null;
      _refOptions = const [];
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _focus.removeListener(_focusChanged);
      if (oldWidget.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode();
      _focus.addListener(_focusChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) _scroll.dispose();
      _scroll = widget.scrollController ?? SmoothScrollController();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _focus.removeListener(_focusChanged);
    if (widget.focusNode == null) _focus.dispose();
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  /// Puts the keyboard in the text, at its end unless [keepSelection].
  void focusEnd({bool keepSelection = false}) {
    if (!keepSelection) {
      _controller.selection = TextSelection.collapsed(
        offset: _controller.length,
      );
    }
    _focus.requestFocus();
  }

  void _focusChanged() => _changed();

  int _seenVersion = -1;

  void _changed() {
    if (_controller.textVersion != _seenVersion) {
      _seenVersion = _controller.textVersion;
      // The bar's marks, the menus' options: as the text is now.
    }
    _refChanged();
  }

  // --- `[[`, `@` and `#` ---------------------------------------------------------

  _RefTrigger? _ref;
  List<_RefOption> _refOptions = const [];
  int _refHighlighted = 0;

  /// Where the trigger dismissed with Esc starts (it stays dismissed while
  /// typed on).
  int? _refDismissed;

  void _refChanged() {
    final refs = widget.refs;
    final trigger = refs == null || widget.readOnly ? null : _findRef();
    if (trigger == null || trigger.from != _refDismissed) _refDismissed = null;
    final shown = trigger != null && _refDismissed == null;
    final options = shown ? _optionsFor(refs!, trigger) : const <_RefOption>[];
    final visible = shown && options.isNotEmpty;
    if (!visible && _ref == null) return;
    if (!mounted) return;
    setState(() {
      _ref = visible ? trigger : null;
      _refOptions = options;
      _refHighlighted = _refHighlighted.clamp(
        0,
        math.max(0, options.length - 1),
      );
    });
  }

  _RefTrigger? _findRef() {
    final selection = _controller.selection;
    if (!selection.isValid || !selection.isCollapsed || !_focus.hasFocus) {
      return null;
    }
    final caret = selection.baseOffset;
    final line = _controller.lineAt(caret);
    final lineStart = _controller.lineStart(line);
    final info = _controller.infoOf(line);
    if (!info.hasInline) return null;
    final before = _controller.lines
        .content(line)
        .substring(0, caret - lineStart);
    if (RegExp(r'\[\[([^\[\]\n]*)$').firstMatch(before) case final m?) {
      return _RefTrigger(_RefKind.title, lineStart + m.start, caret, m[1]!);
    }
    if (RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before) case final m?) {
      return _RefTrigger(
        _RefKind.project,
        caret - m[1]!.length - 1,
        caret,
        m[1]!,
      );
    }
    if (RegExp(r'(?:^|\s)#([^\s#]+)$').firstMatch(before) case final m?) {
      return _RefTrigger(
        _RefKind.number,
        caret - m[1]!.length - 1,
        caret,
        m[1]!,
      );
    }
    return null;
  }

  List<_RefOption> _optionsFor(StashRefs refs, _RefTrigger trigger) {
    final query = trigger.query.toLowerCase();
    if (trigger.kind == _RefKind.project) {
      return [
        for (final project in refs.projects())
          if (project.name.toLowerCase().contains(query))
            _RefOption(
              label: project.name,
              detail: project.path,
              text: '@${project.name}',
              href: StashRefs.projectHref(project.path),
            ),
      ].take(8).toList();
    }
    return [
      for (final stash in refs.stashes())
        if ('${stash.id}'.startsWith(query) ||
            stash.title.toLowerCase().contains(query))
          _RefOption(
            label: stash.title.isEmpty ? '#${stash.id}' : stash.title,
            detail: '#${stash.id}',
            text: trigger.kind == _RefKind.number || stash.title.isEmpty
                ? '#${stash.id}'
                : stash.title,
            href: StashRefs.stashHref(stash.id),
          ),
    ].take(8).toList();
  }

  void _acceptRef(int index) {
    final trigger = _ref;
    if (trigger == null || index >= _refOptions.length) return;
    final option = _refOptions[index];
    // `]]` typed already after the caret goes too.
    var end = trigger.to;
    if (trigger.kind == _RefKind.title &&
        _controller.substring(end, math.min(end + 2, _controller.length)) ==
            ']]') {
      end += 2;
    }
    final link = '[${stashLinkText(option.text)}](${option.href}) ';
    _controller.replace(
      trigger.from,
      end,
      link,
      selection: TextSelection.collapsed(offset: trigger.from + link.length),
    );
    setState(() {
      _ref = null;
      _refOptions = const [];
      _refHighlighted = 0;
    });
  }

  KeyEventResult _key(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final key = event.logicalKey;
    if (command && !keyboard.isShiftPressed && !keyboard.isAltPressed) {
      // The bar's marks and link (⌘K, put in its field: nothing else's
      // here, with no selection); there is no finding in a stash.
      if (_formatBar.currentState?.handleKey(event) == KeyEventResult.handled ||
          key == LogicalKeyboardKey.keyK) {
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyF) {
        return KeyEventResult.skipRemainingHandlers;
      }
    }
    if (_ref == null || _refOptions.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(
        () => _refHighlighted = (_refHighlighted + 1) % _refOptions.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _refHighlighted =
            (_refHighlighted - 1 + _refOptions.length) % _refOptions.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _acceptRef(_refHighlighted);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _refDismissed = _ref?.from;
        _ref = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Under the caret, in the stack's box.
  Offset? _caretBottom() {
    final caret = markdownEditor?.caretRect();
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (caret == null || stack == null || !stack.attached) return null;
    return stack.globalToLocal(caret.bottomLeft);
  }

  Widget _refMenu(BuildContext context) {
    final at = _caretBottom() ?? Offset.zero;
    return Positioned(
      left: at.dx,
      top: at.dy + 4,
      child: PopIn(
        alignment: Alignment.topLeft,
        offset: const Offset(0, -4),
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: themeColors['editorSuggestWidget.background'],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: themeColors['editorSuggestWidget.border'],
            ),
            boxShadow: [
              BoxShadow(color: themeColors['widget.shadow'], blurRadius: 16),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, option) in _refOptions.indexed)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onHover: (_) {
                    if (_refHighlighted != i) {
                      setState(() => _refHighlighted = i);
                    }
                  },
                  child: GestureDetector(
                    onTap: () => _acceptRef(i),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: i == _refHighlighted
                            ? themeColors['editorSuggestWidget.selectedBackground']
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            option.href.startsWith(StashRefs.projectScheme)
                                ? Codicons.folder
                                : Codicons.note,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              option.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: AppColors.textFaint,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A link ⌘-clicked (or clicked, read only): followed at once.
  void _openLink(String href) {
    if (_isRef(href)) {
      widget.refs?.open(href);
      return;
    }
    unawaited(openExternal(href));
  }

  /// A click at [offset]: a link ⌘-clicked (clicked, read only) is
  /// followed, the caret left where it was.
  bool _click(int offset) {
    final keyboard = HardwareKeyboard.instance;
    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (!command && !widget.readOnly) return false;
    final found = _controller.linkAt(offset);
    if (found == null) return false;
    final (line, run) = found;
    final column = offset - _controller.lineStart(line);
    final href = run.href;
    if (href == null || !(run.start < column && column < run.end)) {
      return false;
    }
    _openLink(href);
    return true;
  }

  static bool _isRef(String href) =>
      StashRefs.stashOf(href) != null || StashRefs.projectOf(href) != null;

  /// Where the pointer last went down, the window's: where a link's menu
  /// opens.
  Offset? _pressedAt;

  /// A card clicked: open it, or edit where it goes in the bar. [card] is
  /// where its markdown starts.
  Future<void> _linkMenu(String href, {required int card}) async {
    final l10n = context.l10n;
    final at = _pressedAt ?? Offset.zero;
    await showIdeMenu(
      context,
      anchor: Rect.fromLTWH(at.dx, at.dy, 1, 1),
      entries: [
        IdeMenuAction(l10n.stashLinkOpen, onSelected: () => _openLink(href)),
        if (!widget.readOnly)
          IdeMenuAction(
            l10n.stashLinkEdit,
            onSelected: () {
              final found = _controller.linkAt(card + 1);
              if (found == null) return;
              final (line, run) = found;
              final start = _controller.lineStart(line);
              _formatBar.currentState?.editLink(
                href,
                TextSelection(
                  baseOffset: start + run.start,
                  extentOffset: start + run.end,
                ),
                apply: (href) => _relinkCard(card, href),
              );
            },
          ),
      ],
    );
  }

  // --- Files dragged in ----------------------------------------------------------

  /// Where files dragged over the text would go: shown as a caret.
  int? _dropAt;

  int _dropOffset(Offset position) {
    final end = _controller.length;
    final editor = markdownEditor;
    final viewport = editor?.viewportRect;
    if (editor == null || viewport == null || !viewport.contains(position)) {
      return end;
    }
    return (editor.offsetAt(position) ?? end).clamp(0, end);
  }

  @override
  void fileDragOver(Offset position, List<ComposerFile> files) {
    if (widget.readOnly) return;
    final at = _dropOffset(position);
    if (at != _dropAt) setState(() => _dropAt = at);
  }

  @override
  void fileDragLeave() {
    if (_dropAt != null) setState(() => _dropAt = null);
  }

  @override
  void fileDrop(Offset position, List<ComposerFile> files) {
    if (widget.readOnly) return;
    final at = _dropAt ?? _dropOffset(position);
    setState(() => _dropAt = null);
    _controller.selection = TextSelection.collapsed(offset: at);
    _focus.requestFocus();
    unawaited(insertFiles(files));
  }

  /// The caret's box at [offset], in the stack's.
  Rect? _caretBox(int offset) {
    final caret = markdownEditor?.caretRect(offset);
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (caret == null || stack == null || !stack.attached) return null;
    final origin = stack.globalToLocal(caret.topLeft);
    return Rect.fromLTWH(origin.dx, origin.dy, 2, caret.height);
  }

  // --- Pasting and dropping ----------------------------------------------------

  /// Pictures and files on the clipboard go in as such; a lone link as a
  /// card; code as a code block; a web page (or a document) as the
  /// markdown it makes. Other text goes in as it is (markdown, as what it
  /// says). Copied in a stash, it is pasted as it was there first (see
  /// [MarkdownEditorState.paste]).
  Future<bool> _paste() async {
    if (widget.readOnly) return true;
    final files = await WindowControls.readPasteboardFiles();
    if (files.isNotEmpty) {
      await insertFiles(files);
      return true;
    }
    final images = await WindowControls.readPasteboardImages();
    if (images.isNotEmpty) {
      for (final image in images) {
        await insertImageBytes(image.bytes, name: image.name);
      }
      return true;
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text != null &&
        RegExp(r'^https?://\S+$').hasMatch(text) &&
        _controller.selection.isCollapsed &&
        _lineIsEmpty()) {
      insertCard(text);
      return true;
    }
    if (text != null && !text.contains('```') && looksLikeCode(text)) {
      var fence = '```';
      while (text.contains(fence)) {
        fence += '`';
      }
      insertMarkdown('$fence\n$text\n$fence');
      return true;
    }
    final html = await WindowControls.readPasteboardHtml();
    if (html != null && html.trim().isNotEmpty) {
      final markdown = stashHtmlToMarkdown(html);
      if (markdown.isNotEmpty) {
        insertMarkdown(markdown);
        return true;
      }
    }
    if (text != null && _looksLikeMarkdown(text)) {
      insertMarkdown(text);
      return true;
    }
    return false;
  }

  /// Lines of code (from an editor, a terminal): two lines or more that
  /// look like code's for sure, or one and the rest like code's too.
  /// Prose (`for the record…`) and markdown's lists (indented as code is)
  /// are not.
  @visibleForTesting
  static bool looksLikeCode(String text) {
    final lines = text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return false;
    // Ends and words only code has.
    final sure = RegExp(
      r'[;{}]\s*$|=>|\)\s*\{|^\s*(#include|#import|import\s+[\w.{*"'
      "'"
      r']|from\s+[\w.]+\s+import|export\s|def\s+\w+\s*\(|class\s+\w+|fn\s+\w+|func\s+\w+|function\s*\w*\s*\(|(const|let|var|final)\s+\w+\s*[=:]|(public|private|protected|static)\s|package\s+[\w.]+|use\s+\w+::|struct\s+\w+|enum\s+\w+|interface\s+\w+)',
    );
    // Lines that go on as code does: indented, or a statement's start.
    final likely = RegExp(
      r'^(\s{2,}|\t)\S|^\s*(if|for|while|return|switch|case|else|elif|try|catch|await|async)\b.*[:(]',
    );
    final markdownItem = RegExp(r'^\s*([-*+]|\d+[.)])\s|^\s*#{1,6}\s|^\s*>');
    var sureLines = 0;
    var codeLines = 0;
    for (final line in lines) {
      if (sure.hasMatch(line)) {
        sureLines++;
        codeLines++;
      } else if (!markdownItem.hasMatch(line) && likely.hasMatch(line)) {
        codeLines++;
      }
    }
    return sureLines >= 2 || (sureLines >= 1 && codeLines == lines.length);
  }

  static bool _looksLikeMarkdown(String text) => RegExp(
    r'(^|\n)\s{0,3}(#{1,6}\s|[-*+]\s|\d+[.)]\s|>\s?|```|\|.*\||\$\$)|\*\*[^*\n]+\*\*|\[[^\]\n]+\]\([^)\s]+\)|!\[',
  ).hasMatch(text);

  /// [markdown] in place of the selection: a block (code, a table, a
  /// list…) on lines of its own, the line it is put in broken before it
  /// and after it; the caret after it.
  void insertMarkdown(String markdown) {
    final newline = _controller.lines.newline;
    var text = markdown.replaceAll('\r\n', '\n').trimRight();
    if (newline != '\n') text = text.replaceAll('\n', newline);
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.length;
    final end = selection.isValid ? selection.end : _controller.length;
    final blocks = MdBlocks(MdLines(text));
    bool block(MdLineInfo info) =>
        info.kind != MdLineKind.paragraph && info.kind != MdLineKind.blank;
    final line = _controller.lineAt(start);
    final lineStart = _controller.lineStart(line);
    final before = _controller.substring(lineStart, start);
    final after = _controller.substring(
      end,
      _controller.lineEnd(_controller.lineAt(end)),
    );
    if (blocks.length > 0 &&
        block(blocks.info(0)) &&
        before.trim().isNotEmpty) {
      text = '$newline$text';
    }
    if (blocks.length > 0 &&
        block(blocks.info(blocks.length - 1)) &&
        after.trim().isNotEmpty) {
      text = '$text$newline';
    }
    _controller.breakUndo();
    _controller.replace(start, end, text);
    _controller.breakUndo();
  }

  bool _lineIsEmpty() {
    final offset = _controller.selection.baseOffset;
    final line = _controller.lineAt(offset);
    return _controller.lines
        .content(line)
        .substring(_controller.textStartOf(line))
        .trim()
        .isEmpty;
  }

  /// Puts [bytes], a picture, in at the caret, kept in the stash's folder.
  Future<void> insertImageBytes(Uint8List bytes, {String? name}) async {
    final scope = widget.store;
    final id = await widget.ensureNote();
    final path = await scope.addImage(id, bytes, name: name);
    _insertInline(stashPictureMarkdown(path));
  }

  /// Puts [files] in at the caret: pictures as pictures, others as links
  /// to them (copied into the stash's folder up to 200 MB; past it the
  /// user is asked whether to copy it anyway).
  Future<void> insertFiles(List<ComposerFile> files) async {
    final id = await widget.ensureNote();
    for (final file in files) {
      final added = await widget.store.addFile(
        id,
        file.path,
        copyAnyway: false,
      );
      if (added == null && !file.directory) continue;
      var path = added?.path ?? file.path;
      if (added != null && !added.copied && mounted) {
        final l10n = context.l10n;
        final choice = await showIdeDialog(
          context,
          message: l10n.stashBigFileTitle(file.name),
          detail: l10n.stashBigFileDetail,
          buttons: [l10n.stashBigFileLink, l10n.stashBigFileCopy],
          type: IdeDialogType.question,
        );
        // Cancelled: not put in.
        if (choice == null || choice > 1) continue;
        if (choice == 1) {
          path =
              (await widget.store.addFile(
                id,
                file.path,
                copyAnyway: true,
              ))?.path ??
              path;
        }
      }
      if (file.maybeImage && !file.directory) {
        _insertInline(stashPictureMarkdown(path));
      } else {
        _insertInline(stashFileMarkdown(file.name, path));
      }
    }
  }

  /// A card for [url] at the caret, titled once its page says.
  void insertCard(String url) {
    _insertInline(stashCardMarkdown(url, url));
    unawaited(_titleCard(url));
  }

  Future<void> _titleCard(String url) async {
    final title = await _forgeTitle(url) ?? await io.fetchPageTitle(url);
    if (title == null || !mounted) return;
    final untitled = stashCardMarkdown(url, url);
    final at = _controller.text.indexOf(untitled);
    if (at < 0) return;
    _controller.replace(
      at,
      at + untitled.length,
      stashCardMarkdown(title, url),
      selection: _controller.selection,
    );
  }

  /// An issue's or pull request's card's title (`o/r#3 Its title`), as
  /// its forge says, where it can be asked.
  Future<String?> _forgeTitle(String url) async {
    final forge = StashForge.current;
    final ref = forge?.refOf(url);
    final api = ref == null ? null : forge!.accounts.apiOf(ref);
    if (ref == null || api == null) return null;
    try {
      return '${ref.fullTag} ${(await api.item(ref)).title}';
    } on Object {
      return null;
    }
  }

  /// [markdown] (a picture's, a file's, a card's) and a space after it at
  /// the caret, in one edit Undo takes back; the caret after them.
  void _insertInline(String markdown) {
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.length;
    final end = selection.isValid ? selection.end : _controller.length;
    _controller.breakUndo();
    _controller.replace(start, end, '$markdown ');
    _controller.breakUndo();
  }

  /// A stash's markdown as a model is given it: its pictures and files as
  /// their paths (see [stashTextForModel]).
  MarkdownForModel _forModel(String markdown) {
    final asked = stashTextForModel(markdown, widget.store.absolute);
    return (
      text: asked.text,
      back: (reply) => stashTextFromModel(
        reply,
        asked.attachments,
        endsLine: markdown.endsWith('\n'),
      ),
    );
  }

  /// The card at [card] (where its markdown starts) going to [href]
  /// instead, titled again; as it was for none.
  void _relinkCard(int card, String href) {
    final found = _controller.linkAt(card + 1);
    if (href.isEmpty || found == null) return;
    final (line, run) = found;
    final start = _controller.lineStart(line);
    final markdown = stashCardMarkdown(href, href);
    _controller.replace(
      start + run.start,
      start + run.end,
      markdown,
      selection: TextSelection.collapsed(
        offset: start + run.start + markdown.length,
      ),
    );
    unawaited(_titleCard(href));
  }

  /// Its text as a model is given it (see [stashTextPart]).
  StashTextPart? get textPart =>
      stashTextPart(_controller.text, widget.store.absolute);

  /// Its text, given to a model as [asked] ([textPart]), [reply] in its
  /// place: a step Undo takes back. Whether it was: not when the text is no
  /// longer [asked].
  bool rewrite(String asked, String reply) {
    final part = textPart;
    if (part == null || part.text != asked) return false;
    final replaced = stashTextFromModel(
      reply,
      part.attachments,
      endsLine: part.endsLine,
    );
    _controller.breakUndo();
    _controller.replace(
      0,
      part.end,
      replaced,
      selection: TextSelection.collapsed(offset: replaced.length),
    );
    _controller.breakUndo();
    return true;
  }

  // --- Building ----------------------------------------------------------------

  MarkdownEditorStyle _style(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        color: AppColors.text,
        fontSize: 14,
        height: 1.55,
        // Glyphs centered in the line box, as the caret is.
        leadingDistribution: TextLeadingDistribution.even,
      ),
    );
    final dark = themeColors.dark;
    final link = themeColors['textLink.foreground'];
    final heading = TextStyle(
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      height: 1.4,
    );
    return MarkdownEditorStyle(
      text: base,
      headings: [
        heading.copyWith(fontSize: 20),
        heading.copyWith(fontSize: 17),
        heading.copyWith(fontSize: 15),
        heading,
        heading,
        heading,
      ],
      bold: const TextStyle(fontWeight: FontWeight.w600),
      code: AppFonts.uiCodeStyle(12.5).copyWith(color: AppColors.inlineCode),
      codeBackground: AppColors.inlineCodeBackground,
      // As the chat's code blocks are: typed in, in place.
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
      colorOf: dark ? _darkColor : _lightColor,
    );
  }

  static final _lightPalette = StashColors.palette(dark: false);
  static final _darkPalette = StashColors.palette(dark: true);

  static Color? _lightColor(String css) =>
      _lightPalette[css.trim().toLowerCase()] ?? parseCssColor(css);

  static Color? _darkColor(String css) =>
      _darkPalette[css.trim().toLowerCase()] ?? parseCssColor(css);

  @override
  Widget build(BuildContext context) {
    final editor = MarkdownEditor(
      key: _editorKey,
      controller: _controller,
      style: _style(context),
      embeds: _embeds,
      focusNode: _focus,
      scrollController: _scroll,
      padding: widget.padding,
      placeholder: widget.placeholder,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      onKey: _key,
      onPaste: _paste,
      onClick: _click,
      // A link clicked shows as it did, its bubble over it.
      revealsLinks: false,
      colorize: StashEditor.colorize,
      keyboardAppearance: themeColors.dark ? Brightness.dark : Brightness.light,
    );
    return IdeMotion(
      lively: true,
      child: StashEditorScope(
        store: widget.store,
        ensureNote: widget.ensureNote,
        readOnly: widget.readOnly,
        onCard: (offset, url) => unawaited(_linkMenu(url, card: offset)),
        child: Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: MarkdownFormatBar(
                key: _formatBar,
                controller: _controller,
                focusNode: _focus,
                editorKey: _editorKey,
                readOnly: widget.readOnly,
                onPolish: widget.onPolish,
                forModel: _forModel,
                onOpenLink: _openLink,
                // Web links: not a stash's or a project's, a card or a file.
                linkShown: (href, run) =>
                    !_isRef(href) && !isStashCard(run) && !isStashFile(run),
                child: FileDropRegion(
                  delegate: this,
                  child: Listener(
                    onPointerDown: (event) => _pressedAt = event.position,
                    // Fading out at an edge scrolled past, the caret with it.
                    child: ScrollEdgeFade(child: editor),
                  ),
                ),
              ),
            ),
            if (_dropAt case final at?)
              if (_caretBox(at) case final box?)
                Positioned.fromRect(
                  rect: box,
                  child: IgnorePointer(
                    child: ColoredBox(color: AppColors.accent),
                  ),
                ),
            if (_ref != null && _refOptions.isNotEmpty) _refMenu(context),
          ],
        ),
      ),
    );
  }
}

enum _RefKind { title, project, number }

/// `[[query`, `@query` or `#query` before the caret: [from] to [to].
class _RefTrigger {
  const _RefTrigger(this.kind, this.from, this.to, this.query);

  final _RefKind kind;
  final int from;
  final int to;
  final String query;
}

class _RefOption {
  const _RefOption({
    required this.label,
    required this.detail,
    required this.text,
    required this.href,
  });

  final String label;
  final String detail;

  /// What goes in the text, linked to [href].
  final String text;
  final String href;
}

// --- What is not text ------------------------------------------------------------

/// What a stash shows for what is not text: pictures, files and cards as
/// tags, formulas, tables, tasks' boxes and rules as the app draws them.
class _StashEmbeds extends MarkdownEmbeds {
  _StashEmbeds(this.state);

  final StashEditorState state;

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
  bool isAtomic(MdInline run, String line) =>
      run.kind == MdInlineKind.image ||
      run.kind == MdInlineKind.math ||
      isStashCard(run) ||
      isStashFile(run);

  @override
  InlineSpan inline(BuildContext context, MdEmbed embed) {
    final run = embed.run;
    final Widget child;
    if (run.kind == MdInlineKind.image) {
      child = _PictureChip(embed: embed);
    } else if (run.kind == MdInlineKind.math) {
      child = _FormulaChip(embed: embed);
    } else if (isStashCard(run)) {
      child = _CardChip(embed: embed);
    } else {
      child = _FileChip(embed: embed);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: MdEmbedRegion(child: child),
    );
  }

  @override
  bool showsBlock(MdLineKind kind) =>
      kind == MdLineKind.tableHead ||
      kind == MdLineKind.mathOpen ||
      kind == MdLineKind.mathLine;

  @override
  Widget? block(
    BuildContext context,
    MdBlockEmbed embed,
    MarkdownEditorStyle style,
  ) {
    if (embed.isTable) return super.block(context, embed, style);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MathView(embed.tex, display: true),
    );
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
  Widget rule(BuildContext context, MarkdownEditorStyle style) =>
      Container(height: 1, color: AppColors.border);

  /// Copied, a picture's or a file's path (`@/…/shot.png`): pasted in a
  /// message, the picture or a tag of the file; a card's title and url; a
  /// formula's TeX.
  @override
  String plainText(MdInline run, String line) {
    final href = run.href ?? '';
    if (run.kind == MdInlineKind.math) {
      return line.substring(run.innerStart, run.innerEnd);
    }
    if (isStashCard(run)) {
      return '${stashUnescape(line.substring(run.innerStart, run.innerEnd))} '
          '$href';
    }
    if (href.isEmpty) return '';
    if (run.kind == MdInlineKind.image && isRemoteStashPicture(href)) {
      return href;
    }
    return fileReferenceText(state.widget.store.absolute(href));
  }
}

/// Which picture of [controller]'s text the one at [offset] is, from 1.
int _pictureNumber(MarkdownController controller, int offset) {
  var number = 0;
  for (final run in _runsOf(controller)) {
    if (run.start > offset) break;
    if (run.picture) number++;
  }
  return math.max(1, number);
}

/// [stashRunsOf] [controller], once for each of its texts.
List<StashRun> _runsOf(MarkdownController controller) {
  final cached = _runsCache[controller];
  if (cached != null && cached.$1 == controller.textVersion) return cached.$2;
  final runs = stashRunsOf(controller);
  _runsCache[controller] = (controller.textVersion, runs);
  return runs;
}

final _runsCache = Expando<(int, List<StashRun>)>();

class _PictureChip extends StatelessWidget {
  const _PictureChip({required this.embed});

  final MdEmbed embed;

  @override
  Widget build(BuildContext context) {
    final scope = StashEditorScope.maybeOf(context);
    final src = embed.run.href ?? '';
    final remote = isRemoteStashPicture(src);
    final path = scope == null || remote ? src : scope.store.absolute(src);
    final ImageProvider picture = remote
        ? NetworkImage(path)
        : io.stashImageProvider(path);
    Widget broken(BuildContext context, Object _, StackTrace? _) =>
        Icon(Codicons.fileMedia, size: 12, color: AppColors.textFaint);
    final controller = embed.controller;
    return _StashChip(
      textStyle: embed.style,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(2.5),
        child: Image(
          image: ResizeImage(picture, width: 42),
          width: 14,
          height: 14,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: broken,
        ),
      ),
      // Numbered as it comes in the text, pictures put in before it
      // counted.
      labelOf: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Text(
          context.l10n.imageChip(
            _pictureNumber(controller, embed.offset() ?? controller.length),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.text, fontSize: 12),
        ),
      ),
      label: '',
      preview: (context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 240),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image(
            image: ResizeImage(picture, width: 960),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: broken,
          ),
        ),
      ),
      onTap: () => unawaited(
        _openPicture(
          context,
          path,
          remote: remote,
          gallery: scope == null
              ? const []
              : _gallery(controller, scope.store.absolute),
        ),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.embed});

  final MdEmbed embed;

  @override
  Widget build(BuildContext context) {
    final run = embed.run;
    final scope = StashEditorScope.maybeOf(context);
    final path = run.href ?? '';
    final absolute = scope == null ? path : scope.store.absolute(path);
    final name = stashUnescape(
      embed.line.substring(run.innerStart, run.innerEnd),
    );
    return _StashChip(
      textStyle: embed.style,
      leading: FileIcon(absolute, size: 14),
      label: name.isEmpty ? p.basename(path) : name,
      // Linked to where it is (too big to copy), not kept with the stash.
      detail: p.isAbsolute(path) ? '↗' : null,
      hint: absolute,
      onTap: () => unawaited(openExternal(absolute)),
      onSecondaryTap: () =>
          unawaited(WindowControls.revealInFileManager(absolute)),
    );
  }
}

/// `$…$`, as the formula it is: clicked, its TeX edited in a dialog.
class _FormulaChip extends StatelessWidget {
  const _FormulaChip({required this.embed});

  final MdEmbed embed;

  @override
  Widget build(BuildContext context) {
    final run = embed.run;
    final tex = embed.line.substring(run.innerStart, run.innerEnd);
    final readOnly = StashEditorScope.maybeOf(context)?.readOnly ?? false;
    return GestureDetector(
      onTap: readOnly
          ? null
          : () async {
              final edited = await showStashTextDialog(
                context,
                title: context.l10n.stashFormulaTitle,
                text: tex,
                monospace: true,
              );
              if (edited == null) return;
              final trimmed = edited.trim().replaceAll('\n', ' ');
              embed.replace(trimmed.isEmpty ? '' : '\$$trimmed\$');
            },
      child: MouseRegion(
        cursor: readOnly ? MouseCursor.defer : SystemMouseCursors.click,
        child: MathView(tex),
      ),
    );
  }
}

class _CardChip extends StatelessWidget {
  const _CardChip({required this.embed});

  final MdEmbed embed;

  @override
  Widget build(BuildContext context) {
    final run = embed.run;
    final url = run.href ?? '';
    final title = stashUnescape(
      embed.line.substring(run.innerStart, run.innerEnd),
    );
    void onTap() {
      final scope = StashEditorScope.maybeOf(context);
      final offset = embed.offset();
      if (scope?.onCard case final onCard? when offset != null) {
        onCard(offset, url);
      } else {
        unawaited(openExternal(url));
      }
    }

    // An issue or pull request: in its state, titled as it is now.
    final forge = StashForge.current;
    if (forge?.refOf(url) case final ref?) {
      return ListenableBuilder(
        listenable: forge!,
        builder: (context, _) {
          final link = forge.stashOf(url)?.issueOf(url);
          final now = forge.itemOf(url)?.title ?? link?.title;
          return _StashChip(
            textStyle: embed.style,
            leading: ForgeStateIcon(
              ref.kind,
              forge.itemOf(url)?.state ?? ForgeState.parse(link?.state),
              size: 12,
            ),
            label: now == null
                ? (title.isEmpty || title == url ? ref.fullTag : title)
                : '${ref.fullTag} $now',
            hint: url,
            onTap: onTap,
          );
        },
      );
    }
    return _StashChip(
      textStyle: embed.style,
      leading: Icon(Codicons.globe, size: 12, color: AppColors.textMuted),
      label: title.isEmpty ? url : title,
      hint: url,
      onTap: onTap,
    );
  }
}

// --- A stash's text, for a model --------------------------------------------------

/// A stash's text as a model is given it ([stashTextForModel]): up to
/// its requirement section ([StashNote.requirementHeading]) if one was
/// written, which stays as it is; [end] where it ends in the markdown,
/// [endsLine] whether it ends its line.
typedef StashTextPart = ({
  int end,
  String text,
  List<(String, String)> attachments,
  bool endsLine,
});

/// [markdown]'s text (see [StashTextPart]); null when it has none.
StashTextPart? stashTextPart(
  String markdown,
  String Function(String path) absolute,
) {
  final end = _textEnd(markdown);
  if (end == 0) return null;
  final slice = markdown.substring(0, end);
  final asked = stashTextForModel(slice, absolute);
  if (asked.text.trim().isEmpty) return null;
  return (
    end: end,
    text: asked.text,
    attachments: asked.attachments,
    endsLine: slice.endsWith('\n'),
  );
}

/// [markdown] with [reply], a model's to its text given it as [asked]
/// ([stashTextPart]), in the text's place; null when the text is no
/// longer [asked].
String? stashTextRewrite(
  String markdown,
  String asked,
  String reply,
  String Function(String path) absolute,
) {
  final part = stashTextPart(markdown, absolute);
  if (part == null || part.text != asked) return null;
  final replaced = stashTextFromModel(
    reply,
    part.attachments,
    endsLine: part.endsLine,
  );
  return markdown.replaceRange(0, part.end, replaced);
}

/// Where [markdown]'s text ends: before a requirement section's heading
/// and the empty lines above it, if there is one; else at its end.
int _textEnd(String markdown) {
  final heading = RegExp(
    '^ {0,3}${RegExp.escape(StashNote.requirementHeading)}[ \\t]*\\r?\$',
    multiLine: true,
  );
  final match = heading.firstMatch(markdown);
  if (match == null) return markdown.length;
  var end = match.start;
  // The empty lines above it go with it; the line before keeps its end.
  while (end > 0 &&
      markdown[end - 1] == '\n' &&
      (end < 2 || markdown[end - 2] == '\n')) {
    end--;
  }
  return end;
}

/// [slice] (a part of a stash's markdown) as a model is given it: each
/// picture and file in it as its path in brackets (`[/…/shot.png]`),
/// which says what it is where a model only reads; with the markdown each
/// such path stands for (see [stashTextFromModel]).
@visibleForTesting
({String text, List<(String, String)> attachments}) stashTextForModel(
  String slice,
  String Function(String path) absolute,
) {
  final attachments = <(String, String)>[];
  final text = StringBuffer();
  var at = 0;
  for (final run in stashRuns(slice)) {
    final where = run.picture && isRemoteStashPicture(run.path)
        ? run.path
        : absolute(run.path);
    final token = '[$where]';
    text
      ..write(slice.substring(at, run.start))
      ..write(token);
    attachments.add((token, slice.substring(run.start, run.end)));
    at = run.end;
  }
  text.write(slice.substring(at));
  return (text: text.toString().trimRight(), attachments: attachments);
}

/// [reply], a model's to [stashTextForModel], as a stash's markdown: the
/// paths in brackets the pictures and files they were, those it left out
/// put after it (none is lost). [endsLine]: the part ended its line.
@visibleForTesting
String stashTextFromModel(
  String reply,
  List<(String, String)> attachments, {
  required bool endsLine,
}) {
  var text = reply.trimRight();
  final left = <String>[];
  for (final (token, markdown) in attachments) {
    final at = text.indexOf(token);
    if (at < 0) {
      left.add(markdown);
    } else {
      text = text.replaceRange(at, at + token.length, markdown);
    }
  }
  if (left.isNotEmpty) text = '$text ${left.join(' ')}';
  // The line goes on after it, as it did.
  return endsLine ? '$text\n' : text;
}

/// The picture whole, as the chat's are; a remote one in the browser.
/// [gallery] is the stash's pictures on this machine (absolute), which
/// the arrows go through from it.
Future<void> _openPicture(
  BuildContext context,
  String path, {
  required bool remote,
  List<String> gallery = const [],
}) async {
  if (remote) {
    await openExternal(path);
    return;
  }
  final pictures = gallery.contains(path) ? gallery : [path];
  showImageGallery(
    context,
    count: pictures.length,
    index: pictures.indexOf(path),
    load: (index) => _readPicture(pictures[index]),
  );
}

/// The picture at [path] (on this machine); null when it cannot be read.
Future<ImageAttachment?> _readPicture(String path) async {
  final bytes = await io.readBytesFile(path);
  if (bytes == null) return null;
  final type = switch (p.extension(path).toLowerCase()) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    _ => 'image/png',
  };
  return ImageAttachment(bytes: bytes, mediaType: type, name: p.basename(path));
}

/// [controller]'s pictures on this machine, in order, by their absolute
/// paths ([absolute]).
List<String> _gallery(
  MarkdownController controller,
  String Function(String) absolute,
) => [
  for (final attachment in StashAttachment.fromRuns(_runsOf(controller)))
    if (attachment.picture && !isRemoteStashPicture(attachment.path))
      absolute(attachment.path),
];

/// A picture or a file of a stash's text, as [StashAttachments] shows it.
@immutable
class StashAttachment {
  const StashAttachment.picture(this.path) : name = null;
  const StashAttachment.file(this.path, this.name);

  /// As the text has it: kept with the stash (relative), a file's where it
  /// is, or a picture's url.
  final String path;

  /// A file's; null for a picture.
  final String? name;

  bool get picture => name == null;

  /// Each picture and file of [markdown] once, as they first come: one
  /// put in twice is one.
  static List<StashAttachment> of(String markdown) =>
      fromRuns(stashRuns(markdown));

  /// Each of [runs] once (see [of]).
  static List<StashAttachment> fromRuns(List<StashRun> runs) {
    final seen = <String>{};
    final found = <StashAttachment>[];
    for (final run in runs) {
      final attachment = run.picture
          ? StashAttachment.picture(run.path)
          : StashAttachment.file(run.path, run.name);
      if (seen.add('${run.picture}:${run.path}')) found.add(attachment);
    }
    return found;
  }

  @override
  bool operator ==(Object other) =>
      other is StashAttachment && other.path == path && other.name == name;

  @override
  int get hashCode => Object.hash(path, name);
}

/// The pictures and files of the text in [controller], above it: each once,
/// however often it is put in. Nothing while there are none.
class StashAttachments extends StatefulWidget {
  const StashAttachments({
    super.key,
    required this.controller,
    required this.store,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 8),
  });

  final MarkdownController controller;
  final StashStore store;
  final EdgeInsets padding;

  static const tileSize = 64.0;

  @override
  State<StashAttachments> createState() => _StashAttachmentsState();
}

class _StashAttachmentsState extends State<StashAttachments> {
  List<StashAttachment> _found = const [];
  int _version = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _found = _read();
  }

  @override
  void didUpdateWidget(StashAttachments oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _version = -1;
      _found = _read();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  List<StashAttachment> _read() {
    _version = widget.controller.textVersion;
    return StashAttachment.fromRuns(_runsOf(widget.controller));
  }

  void _changed() {
    // The selection moved: the text is as it was.
    if (widget.controller.textVersion == _version) return;
    final found = _read();
    if (listEquals(found, _found)) return;
    setState(() => _found = found);
  }

  @override
  Widget build(BuildContext context) {
    if (_found.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: StashAttachments.tileSize + widget.padding.vertical,
      child: ScrollEdgeFade(
        axis: Axis.horizontal,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          itemCount: _found.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) => _AttachmentTile(
            attachment: _found[index],
            store: widget.store,
            gallery: [
              for (final found in _found)
                if (found.picture && !isRemoteStashPicture(found.path))
                  widget.store.absolute(found.path),
            ],
          ),
        ),
      ),
    );
  }
}

/// A stash's first picture, small, else its first file's icon; null for
/// one with neither.
class StashAttachmentIcon extends StatelessWidget {
  const StashAttachmentIcon({
    super.key,
    required this.attachment,
    required this.store,
    this.size = 16,
  });

  final StashAttachment attachment;
  final StashStore store;
  final double size;

  /// [body]'s (markdown) pictures first, then its files: the first.
  static StashAttachment? of(String body) {
    final found = StashAttachment.of(body);
    return found.where((a) => a.picture).firstOrNull ?? found.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final path = attachment.picture && isRemoteStashPicture(attachment.path)
        ? attachment.path
        : store.absolute(attachment.path);
    if (!attachment.picture) return FileIcon(path, size: size);
    final ImageProvider picture = isRemoteStashPicture(attachment.path)
        ? NetworkImage(path)
        : io.stashImageProvider(path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image(
        image: ResizeImage(picture, width: (size * 3).round()),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) => Icon(
          Codicons.fileMedia,
          size: size - 2,
          color: AppColors.textFaint,
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.store,
    this.gallery = const [],
  });

  final StashAttachment attachment;
  final StashStore store;

  /// The stash's pictures, which the arrows go through from this one.
  final List<String> gallery;

  @override
  Widget build(BuildContext context) {
    final remote = attachment.picture && isRemoteStashPicture(attachment.path);
    final path = remote ? attachment.path : store.absolute(attachment.path);
    const size = StashAttachments.tileSize;
    final Widget content;
    if (attachment.picture) {
      final ImageProvider picture = remote
          ? NetworkImage(path)
          : io.stashImageProvider(path);
      content = Image(
        image: ResizeImage(picture, width: (size * 3).round()),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, _, _) => Center(
          child: Icon(Codicons.fileMedia, size: 20, color: AppColors.textFaint),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
        child: Column(
          children: [
            FileIcon(path, size: 22),
            const Spacer(),
            Text(
              attachment.name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
            ),
          ],
        ),
      );
    }
    return IdeHover(
      message: attachment.picture ? p.basename(path) : path,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: () => unawaited(
            attachment.picture
                ? _openPicture(context, path, remote: remote, gallery: gallery)
                : openExternal(path),
          ),
          onSecondaryTap: remote
              ? null
              : () => unawaited(WindowControls.revealInFileManager(path)),
          child: Container(
            width: size,
            height: size,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hovered ? AppColors.borderStrong : AppColors.partBorder,
              ),
            ),
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : AppColors.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// A picture, a file, code, a table or a link, as a tag in the text: what
/// it is beside its label, larger ([preview]) or told ([hint]) on hover.
class _StashChip extends StatelessWidget {
  const _StashChip({
    required this.textStyle,
    required this.leading,
    required this.label,
    this.detail,
    this.preview,
    this.hint,
    this.onTap,
    this.onSecondaryTap,
    this.labelOf,
  });

  /// The text's around it, to be centered on.
  final TextStyle textStyle;
  final Widget leading;
  final String label;

  /// In place of [label], where it changes as the text does.
  final WidgetBuilder? labelOf;

  /// After [label], fainter.
  final String? detail;
  final WidgetBuilder? preview;
  final String? hint;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    Widget chip = _CenteredOnText(
      textStyle: textStyle,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          height: 1.25,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        child: HoverBuilder(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onTap,
            onSecondaryTap: onSecondaryTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.fromLTRB(3, 1, 5, 1),
              decoration: BoxDecoration(
                color: hovered && onTap != null
                    ? AppColors.hover
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: themeColors['chat.requestBorder']),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(dimension: 14, child: Center(child: leading)),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child:
                        labelOf?.call(context) ??
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.text, fontSize: 12),
                        ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      detail,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (preview case final preview?) {
      chip = HoverTooltip(content: preview, child: chip);
    } else if (hint case final hint?) {
      chip = IdeHover(message: hint, child: chip);
    }
    return chip;
  }
}

/// Whether [src] is a picture on the web rather than in the stash's folder.
bool isRemoteStashPicture(String src) =>
    src.startsWith('http://') || src.startsWith('https://');

/// Asks for text in a dialog: a formula's TeX, a table's or code's
/// markdown. Null when cancelled.
Future<String?> showStashTextDialog(
  BuildContext context, {
  required String title,
  required String text,
  bool monospace = false,
  int lines = 4,
}) {
  final controller = TextEditingController(text: text);
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.commonDismiss,
    barrierColor: const Color(0x80000000),
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) {
      final l10n = context.l10n;
      return Center(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: themeColors['editorWidget.background'],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: themeColors['editorWidget.border']),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _SubmitIntent(),
                    SingleActivator(LogicalKeyboardKey.enter, control: true):
                        _SubmitIntent(),
                  },
                  child: Actions(
                    actions: {
                      _SubmitIntent: CallbackAction<_SubmitIntent>(
                        onInvoke: (_) {
                          Navigator.of(context).pop(controller.text);
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: lines,
                      maxLines: lines + 8,
                      cursorColor: AppColors.text,
                      style:
                          (monospace
                                  ? AppFonts.uiCodeStyle(12.5)
                                  : const TextStyle(fontSize: 13))
                              .copyWith(color: themeColors['input.foreground']),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: themeColors['input.background'],
                        contentPadding: const EdgeInsets.all(10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: AppColors.borderStrong),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: themeColors['focusBorder'],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _DialogButton(
                      label: l10n.commonCancel,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    _DialogButton(
                      label: l10n.commonOk,
                      primary: true,
                      onTap: () => Navigator.of(context).pop(controller.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: primary
              ? (hovered
                    ? themeColors['button.hoverBackground']
                    : themeColors['button.background'])
              : (hovered ? AppColors.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: primary ? Colors.transparent : AppColors.borderStrong,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: primary ? themeColors['button.foreground'] : AppColors.text,
            fontSize: 12.5,
          ),
        ),
      ),
    ),
  );
}

// As the chat input's tags are (composer_embeds.dart), the stash's own copy.

/// Reports a baseline that puts the child's vertical center on the center of
/// the glyphs of [textStyle], so a baseline-aligned token sits optically
/// centered on the surrounding text regardless of what else is on the line.
class _CenteredOnText extends SingleChildRenderObjectWidget {
  const _CenteredOnText({required this.textStyle, required super.child});

  final TextStyle textStyle;

  /// Distance from the alphabetic baseline up to the glyph center.
  double _glyphCenterAboveBaseline(TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: textStyle.copyWith(height: null)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final metrics = painter.computeLineMetrics().first;
    painter.dispose();
    return (metrics.ascent - metrics.descent) / 2;
  }

  @override
  _RenderCenteredOnText createRenderObject(BuildContext context) =>
      _RenderCenteredOnText(
        _glyphCenterAboveBaseline(MediaQuery.textScalerOf(context)),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCenteredOnText renderObject,
  ) {
    renderObject.centerAboveBaseline = _glyphCenterAboveBaseline(
      MediaQuery.textScalerOf(context),
    );
  }
}

class _RenderCenteredOnText extends RenderProxyBox {
  _RenderCenteredOnText(this._centerAboveBaseline);

  double _centerAboveBaseline;
  set centerAboveBaseline(double value) {
    if (value == _centerAboveBaseline) return;
    _centerAboveBaseline = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      size.height / 2 + _centerAboveBaseline;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => getDryLayout(constraints).height / 2 + _centerAboveBaseline;
}
