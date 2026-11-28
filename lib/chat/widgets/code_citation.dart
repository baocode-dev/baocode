import 'dart:async';
import 'dart:math' as math;

import 'package:bao_editor/textmate/textmate_syntax.dart' show TextMateSyntax;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_find.dart' show ChatFindMarks;
import '../side_panel/file_link.dart' show FileLineRange, FileLink;
import '../side_panel/file_open.dart' show FileOpenScope;
import 'hover_builder.dart';
import 'table_selection.dart';
import 'will_change_paint.dart';
import '../selection/chat_selection.dart';

/// Code the agent cited from a file, as it is asked to
/// (`ClaudeLaunch.citingCode`): a block fenced as ```` ```12:15:lib/a.dart ````.
class CodeCitation {
  const CodeCitation(this.start, this.end, this.path);

  /// The citation a fence's info string ([language], as markdown takes
  /// it) is; null for any other.
  static CodeCitation? parse(String? language) {
    final match = _info.firstMatch(language?.trim() ?? '');
    if (match == null) return null;
    final start = int.parse(match[1]!);
    final end = int.parse(match[2]!);
    if (start < 1) return null;
    return CodeCitation(start, end < start ? start : end, match[3]!.trim());
  }

  static final _info = RegExp(r'^(\d+):(\d+):(.+)$');

  /// First and last line, from 1.
  final int start;
  final int end;

  /// As the agent wrote it: relative to where it works, or absolute.
  final String path;

  String get fileName => path.split(RegExp(r'[/\\]')).last;

  /// `Ln 14–16`, or `Ln 14` for a line.
  String get lines => start == end ? 'Ln $start' : 'Ln $start–$end';

  /// [path] made absolute from [root], the folder the agent works in (see
  /// [FileLink.resolvePath]).
  String? pathIn(String root) => FileLink.resolvePath(path, root);

  @override
  bool operator ==(Object other) =>
      other is CodeCitation &&
      other.start == start &&
      other.end == end &&
      other.path == path;

  @override
  int get hashCode => Object.hash(start, end, path);
}

/// The fence a [CodeCitation] opens. Markdown closes a fence at the first
/// bare one in it, so code that has one (a markdown sample, a prompt)
/// would end early, the rest spilling out as text; but a citation says how
/// many lines it holds, and a bare fence just after that many closes it.
/// Without one there (lines left out, still being written), the first does.
class CodeCitationFenceSyntax extends md.BlockSyntax {
  const CodeCitationFenceSyntax();

  @override
  RegExp get pattern => _opening;

  static final _opening = RegExp(r'^( {0,3})(?:(`{3,})([^`]*)|(~{3,})(.*))$');

  @override
  bool canParse(md.BlockParser parser) {
    final match = _opening.firstMatch(parser.current.content);
    return match != null && CodeCitation.parse(match[3] ?? match[5]) != null;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _opening.firstMatch(parser.current.content)!;
    final indent = match[1]!.length;
    final marker = match[2] ?? match[4]!;
    final info = (match[3] ?? match[5]!).trim();
    final citation = CodeCitation.parse(info)!;
    final close = RegExp(
      '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}[ \\t]*\$',
    );
    final cited = citation.end - citation.start + 1;
    // Lines ahead of the opening fence to the closing one: the one after
    // the lines cited (a fence among them, cited from markdown), else the
    // first. Past them too: more lines than cited, the rest of the reply is
    // not code (#308).
    int? end;
    for (var i = 1; end == null || i <= cited + 1; i++) {
      final line = parser.peek(i);
      if (line == null) break;
      if (!close.hasMatch(line.content)) continue;
      end = i == cited + 1 ? i : end ?? i;
    }
    parser.advance();
    final lines = <String>[];
    for (var i = 1; !parser.isDone && i != end; i++) {
      final line = parser.current.content;
      final spaces = line.length - line.trimLeft().length;
      lines.add(line.substring(spaces < indent ? spaces : indent));
      parser.advance();
    }
    if (end != null) {
      parser.advance();
    } else if (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    final text = lines.isEmpty ? '' : '${lines.join('\n')}\n';
    return md.Element('pre', [
      md.Element.text('code', text)..attributes['class'] = 'language-$info',
    ]);
  }
}

/// [code], from the file at [path], in the editor's colors a line at a
/// time; null when its language is not known.
typedef CodeColorizer = Future<List<List<TextSpan>>?> Function(
  String path,
  String code,
);

/// [code] in the language a fence names ([language], an id or an alias),
/// in the editor's colors a line at a time; null when it is not known.
typedef CodeBlockColorizer = Future<List<List<TextSpan>>?> Function(
  String language,
  String code,
);

/// What the [CodeCitationCard]s and [MarkdownCodeBlock]s under it can do:
/// open the file cited and color the code.
class CodeCitationScope extends InheritedWidget {
  const CodeCitationScope({
    super.key,
    this.root,
    this.onOpen,
    this.colorize,
    this.colorizeBlock,
    this.syntax,
    required super.child,
  });

  /// Where the agent works, which relative paths are in. Files outside it
  /// do not open.
  final String? root;

  /// Opens the file at [path] (absolute, in [root]) with [start] to [end]
  /// (lines from 1) selected.
  final void Function(String path, int start, int end)? onOpen;

  final CodeColorizer? colorize;

  /// Colors a [MarkdownCodeBlock]'s code by its language.
  final CodeBlockColorizer? colorizeBlock;

  /// The TextMate worker [colorize] colors with, started as it is first
  /// asked for: an edit's diff (an editor's) colored by it too.
  final TextMateSyntax Function()? syntax;

  static CodeCitationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CodeCitationScope>();

  @override
  bool updateShouldNotify(CodeCitationScope oldWidget) =>
      root != oldWidget.root ||
      onOpen != oldWidget.onOpen ||
      colorize != oldWidget.colorize ||
      colorizeBlock != oldWidget.colorizeBlock ||
      syntax != oldWidget.syntax;
}

/// A [CodeCitation] as a card: the file's icon, name and lines, which open
/// it there, over the code with its line numbers, all of it; folded, only
/// the title shows.
class CodeCitationCard extends StatelessWidget {
  const CodeCitationCard({
    super.key,
    required this.citation,
    required this.code,
  });

  final CodeCitation citation;
  final String code;

  /// About a dozen lines: how tall a step's diff may be (not a card).
  static const maxCodeHeight = 220.0;

  @override
  Widget build(BuildContext context) =>
      _CodeCard(code: code, citation: citation);
}

/// A fenced code block as a [CodeCitationCard] is, its language (the
/// first word of the fence's info string) for a title and no line numbers.
/// Plain text (no language, or `text`) has no title, so does not fold.
class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({
    super.key,
    required this.code,
    this.language,
    this.onPreview,
  });

  final String code;
  final String? language;

  /// Back to what the source draws (a diagram), from the title.
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) =>
      _CodeCard(code: code, language: language, onPreview: onPreview);
}

/// A markdown quote, as a plain code block's card: its [child] (the quote
/// rendered) in it, the copy button over its corner copying [text].
class MarkdownQuoteBlock extends StatefulWidget {
  const MarkdownQuoteBlock({
    super.key,
    required this.text,
    required this.child,
  });

  final String text;
  final Widget child;

  @override
  State<MarkdownQuoteBlock> createState() => _MarkdownQuoteBlockState();
}

class _MarkdownQuoteBlockState extends State<MarkdownQuoteBlock> {
  bool _hovered = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.text)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final background = colors['textCodeBlock.background'];
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors['chat.requestBorder']),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Clear of the copy button on the right.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 36, 8),
              child: widget.child,
            ),
            Positioned(
              top: 5,
              right: 6,
              child: ChatUnselectable(
                child: Visibility.maintain(
                  visible: _hovered || _copied,
                  child: CodeBlockIconButton(
                    icon: _copied ? Codicons.check : Codicons.copy,
                    tooltip: context.l10n.commonCopy,
                    onTap: _copy,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A [citation]'s card, or a code block's in [language] without one.
class _CodeCard extends StatefulWidget {
  const _CodeCard({
    required this.code,
    this.citation,
    this.language,
    this.onPreview,
  });

  final String code;
  final CodeCitation? citation;
  final String? language;
  final VoidCallback? onPreview;

  @override
  State<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<_CodeCard> with SidewaysWrap {
  final _horizontal = ScrollController();

  /// The code's, to keep its paragraphs (their boxes, the selection in them)
  /// while wrapping moves them to another place in the tree.
  final _code = GlobalKey();
  bool _expanded = true;
  bool _hovered = false;
  bool _copied = false;
  Timer? _copiedTimer;

  CodeColorizer? _colorize;
  CodeBlockColorizer? _colorizeBlock;

  /// The lines last colored, and their colors: kept for those still the
  /// same while the agent writes on.
  List<String> _coloredLines = const [];
  List<List<TextSpan>> _colors = const [];
  String? _coloredCode;

  /// The theme's colors [_colors] were made in: another theme colors the
  /// code again, as an editor recolors its tokens.
  Object? _coloredIn;
  bool _coloring = false;

  /// Its language has no grammar: no use asking again.
  bool _uncolored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = CodeCitationScope.maybeOf(context);
    if (scope?.colorize != _colorize ||
        scope?.colorizeBlock != _colorizeBlock) {
      _colorize = scope?.colorize;
      _colorizeBlock = scope?.colorizeBlock;
      _uncolored = false;
      _coloredCode = null;
    }
    _colorSoon();
  }

  @override
  void didUpdateWidget(_CodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.citation?.path != widget.citation?.path ||
        oldWidget.language != widget.language) {
      _uncolored = false;
    }
    _colorSoon();
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _horizontal.dispose();
    super.dispose();
  }

  /// Colors the code unless it is colored, one request at a time: code
  /// that grew meanwhile is asked for once that one is answered.
  void _colorSoon() {
    final code = widget.code;
    final theme = themeColors;
    if (_uncolored ||
        _coloring ||
        (code == _coloredCode && identical(theme, _coloredIn))) {
      return;
    }
    final colored = switch ((widget.citation, widget.language)) {
      (final citation?, _) => _colorize?.call(citation.path, code),
      (null, final language?) => _colorizeBlock?.call(language, code),
      _ => null,
    };
    if (colored == null) return;
    _coloring = true;
    colored.then(
      (lines) {
        _coloring = false;
        if (!mounted) return;
        _coloredCode = code;
        _coloredIn = theme;
        if (lines == null) {
          _uncolored = true;
        } else {
          final coloredLines = code.split('\n');
          setState(() {
            // A line colored as it was keeps its spans: its paragraph is
            // not built again.
            _colors = [
              for (final (i, spans) in lines.indexed)
                i < _colors.length &&
                        i < _coloredLines.length &&
                        i < coloredLines.length &&
                        _coloredLines[i] == coloredLines[i] &&
                        listEquals(_colors[i], spans)
                    ? _colors[i]
                    : spans,
            ];
            _coloredLines = coloredLines;
          });
        }
        _colorSoon();
      },
      onError: (_) {
        _coloring = false;
        _uncolored = true;
      },
    );
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.code)));
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Plain text: a fence that names no language, nor a file.
  bool get _plain =>
      widget.citation == null &&
      widget.onPreview == null &&
      switch (widget.language?.toLowerCase()) {
        null || 'text' || 'txt' || 'plaintext' => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    // Built again for a new theme: its colors for the code.
    _colorSoon();
    final colors = themeColors;
    final line = colors['chat.requestBorder'];
    final background = colors['textCodeBlock.background'];
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: line),
        ),
        clipBehavior: Clip.antiAlias,
        child: _plain
            // No title to fold it by: the text, the copy button over its
            // corner.
            ? Stack(
                children: [
                  _body(),
                  Positioned(
                    top: 5,
                    right: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // Opaque, to hide the text under it: the card's
                        // color is often a see-through one.
                        color: Color.alphaBlend(
                          background,
                          colors['editor.background'],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Only while hovered, not to hide more of the
                          // text under it the rest of the time.
                          if (canWrap && _hovered)
                            ChatUnselectable(child: wrapButton(context)),
                          _copyButton(context),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _title(context),
                  if (_expanded) ...[
                    Divider(height: 1, thickness: 1, color: line),
                    _body(),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _copyButton(BuildContext context) => ChatUnselectable(
    child: Visibility.maintain(
      visible: _hovered || _copied,
      child: CodeBlockIconButton(
        icon: _copied ? Codicons.check : Codicons.copy,
        tooltip: context.l10n.commonCopy,
        onTap: _copy,
      ),
    ),
  );

  /// The chevron and the empty space fold it; the file opens it there.
  Widget _title(BuildContext context) {
    final l10n = context.l10n;
    final hover = AppColors.hover;
    return ChatUnselectable(
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            // Faintly lit while hovered.
            color: hovered
                ? hover.withValues(alpha: hover.a * 0.6)
                : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
            child: Row(
              children: [
                CodeBlockIconButton(
                  icon: _expanded
                      ? Codicons.chevronDown
                      : Codicons.chevronRight,
                  tooltip: _expanded
                      ? l10n.cmdListCollapse
                      : l10n.cmdListExpand,
                  onTap: () => setState(() => _expanded = !_expanded),
                ),
                const SizedBox(width: 2),
                // The rest of the row, the copy button at its end.
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: switch (widget.citation) {
                      final citation? => _file(context, citation),
                      null => Text(
                        widget.language ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    },
                  ),
                ),
                if (widget.onPreview case final onPreview?)
                  CodeBlockIconButton(
                    icon: Codicons.preview,
                    tooltip: l10n.sidePanelPreview,
                    onTap: onPreview,
                  ),
                if (canWrap && _expanded) wrapButton(context),
                _copyButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The cited file's icon, name and lines, which open it there.
  Widget _file(BuildContext context, CodeCitation citation) {
    final scope = CodeCitationScope.maybeOf(context);
    final open = scope?.onOpen;
    final files = FileOpenScope.maybeOf(context);
    // As the chat's file links are found, in a workspace's folders and the
    // files the agent read too.
    final path = switch ((files, scope?.root)) {
      (final files?, _) => files.resolve(citation.path),
      (null, final root?) => citation.pathIn(root),
      _ => null,
    };
    final opens = open != null && path != null;
    Widget file = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FileIcon(citation.fileName, size: 15),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            citation.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.text, fontSize: 12.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          citation.lines,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
    if (opens) {
      file = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Where it is of the places it may be, as a link's.
          onTap: () => files != null
              ? files.openLink(
                  FileLink(
                    citation.path,
                    FileLineRange(citation.start, citation.end),
                  ),
                )
              : open(path, citation.start, citation.end),
          child: file,
        ),
      );
    }
    return IdeHover(message: citation.path, child: file);
  }

  /// Lines to a paragraph of the code: code the agent writes on lays out
  /// its last paragraph again, not all of it. One paragraph of a long block
  /// took hundreds of ms a frame on a slow Mac (YQAHVBDB).
  static const _linesPerParagraph = 40;

  /// The code's paragraphs last built, kept while their lines, colors and
  /// style are the same.
  List<_CodeParagraph> _paragraphs = const [];

  /// Line [index]'s colors, if it was colored as it is.
  List<TextSpan>? _colorsOf(int index, String line) =>
      index < _colors.length &&
          index < _coloredLines.length &&
          _coloredLines[index] == line
      ? _colors[index]
      : null;

  /// Paragraph [index] of [lines]: the one last built if it is the same.
  _CodeParagraph _paragraph(
    int index,
    List<String> lines,
    TextStyle style,
    bool wrap,
  ) {
    final start = index * _linesPerParagraph;
    final own = lines.sublist(
      start,
      math.min(start + _linesPerParagraph, lines.length),
    );
    final colors = [
      for (final (i, line) in own.indexed) _colorsOf(start + i, line),
    ];
    if (index < _paragraphs.length) {
      final built = _paragraphs[index];
      if (built.isOf(own, colors, style, wrap)) return built;
    }
    final widget = ChatFindMarks(
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            for (final (i, line) in own.indexed) ...[
              if (i > 0) const TextSpan(text: '\n'),
              if (colors[i] case final spans?)
                ...spans
              else
                TextSpan(text: line),
            ],
          ],
        ),
        softWrap: wrap,
      ),
    );
    return _CodeParagraph(own, colors, style, wrap, widget);
  }

  /// Wrapped, a citation's [code] with each line's number beside where the
  /// line starts: a line may take several rows, which a column of numbers
  /// beside the paragraphs would not follow. The code stays the paragraphs
  /// it is unwrapped, so find, copy and the selection go by the same text.
  Widget _numbered(
    Widget code,
    List<String> lines,
    CodeCitation citation,
    TextStyle style,
  ) {
    final numberStyle = style.copyWith(
      color: themeColors['editorLineNumber.foreground'],
    );
    final starts = <({int paragraph, int offset})>[];
    var offset = 0;
    for (final (i, line) in lines.indexed) {
      if (i % _linesPerParagraph == 0) offset = 0;
      starts.add((paragraph: i ~/ _linesPerParagraph, offset: offset));
      offset += line.length + 1;
    }
    if (_numbersOf != (citation.start, numberStyle)) {
      _numbersOf = (citation.start, numberStyle);
      _numbers = const [];
    }
    _numbers = _numbers.length >= lines.length
        ? _numbers.sublist(0, lines.length)
        : [
            ..._numbers,
            for (var i = _numbers.length; i < lines.length; i++)
              _number(citation.start + i, numberStyle),
          ];
    return _LineNumbers(
      // The numbers' column's width, its padding on the left (the card's
      // edge here) left out.
      gutter: _numbersWidth('${citation.start + lines.length - 1}', style) - 12,
      starts: starts,
      code: code,
      numbers: _numbers,
    );
  }

  /// The line numbers last built wrapped, and the first number and style
  /// they were built of: code the agent writes on adds numbers, not builds
  /// them all again.
  List<Widget> _numbers = const [];
  (int, TextStyle)? _numbersOf;

  // Not read out: a screen reader reads the code, then would read all the
  // numbers after it.
  static Widget _number(int number, TextStyle style) => ExcludeSemantics(
    child: ChatUnselectable(
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        // Its box is as wide as the widest number, to the pixel: one wide as
        // that must not wrap for rounding.
        child: Text(
          '$number',
          textAlign: TextAlign.right,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: style,
        ),
      ),
    ),
  );

  /// Line numbers from the citation's first, beside the code; the code
  /// scrolls sideways alone, its scrollbar at the card's bottom, not the
  /// code's. A code block has no numbers.
  Widget _body() {
    final lines = widget.code.split('\n');
    final citation = widget.citation;
    final style = AppFonts.uiCodeStyle(12)
        .copyWith(color: themeColors['editor.foreground'], height: 1.5);
    final count = (lines.length + _linesPerParagraph - 1) ~/ _linesPerParagraph;
    final wrap = wrapped;
    final numbers = switch (citation) {
      // As the code's paragraphs, so a line's number lies beside it.
      // Wrapped, beside the code where each line starts ([_numbered]).
      final citation? when !wrap => ChatUnselectable(
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var j = 0; j < count; j++)
                Text(
                  [
                    for (
                      var i = j * _linesPerParagraph;
                      i < math.min((j + 1) * _linesPerParagraph, lines.length);
                      i++
                    )
                      '${citation.start + i}',
                  ].join('\n'),
                  textAlign: TextAlign.right,
                  style: style.copyWith(
                    color: themeColors['editorLineNumber.foreground'],
                  ),
                ),
            ],
          ),
        ),
      ),
      _ => const SizedBox(width: 12),
    };
    // Where the code starts: the sideways scrollbar's track from there.
    final gutter = switch (citation) {
      final citation? when !wrap => _numbersWidth(
        '${citation.start + lines.length - 1}',
        style,
      ),
      _ => 12.0,
    };
    _paragraphs = [
      for (var j = 0; j < count; j++) _paragraph(j, lines, style, wrap),
    ];
    Widget code = KeyedSubtree(
      key: _code,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final paragraph in _paragraphs) paragraph.widget],
      ),
    );
    if (wrap && citation != null) {
      code = _numbered(code, lines, citation, style);
    }
    Widget scroll(Widget code) =>
        NotificationListener<ScrollMetricsNotification>(
          onNotification: onScrollMetrics,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: 12),
            // Copied a line to a line, as one paragraph was.
            child: TableSelection.lines(
              registrar: SelectionContainer.maybeOf(context),
              child: WillChangePaint(child: code),
            ),
          ),
        );
    // As tall as its lines, so nothing scrolls down in it: the page does.
    return MediaQuery(
      // The scrollbar's padding is the media's.
      data: MediaQuery.of(context)
          .copyWith(padding: EdgeInsets.only(left: gutter)),
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: _hovered,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              numbers,
              Expanded(
                // The code's selection is its own, not the scroll view's.
                child: SelectionContainer.disabled(
                  child: wrap
                      // As wide as there is room for (its padding left
                      // out), so its lines wrap there and nothing scrolls.
                      ? LayoutBuilder(
                          builder: (_, constraints) => scroll(
                            SizedBox(
                              width: math.max(0, constraints.maxWidth - 12),
                              child: code,
                            ),
                          ),
                        )
                      : scroll(code),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The line numbers' width with their padding: as wide as the last.
  double _numbersWidth(String last, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: last, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + 12 + 14;
  }
}

/// A paragraph of a [_CodeCard]'s code, and what it was built of.
class _CodeParagraph {
  const _CodeParagraph(
    this.lines,
    this.colors,
    this.style,
    this.wrap,
    this.widget,
  );

  final List<String> lines;

  /// Each line's spans, the very ones; null for one not colored.
  final List<List<TextSpan>?> colors;
  final TextStyle style;

  /// Whether its lines wrap.
  final bool wrap;
  final Widget widget;

  bool isOf(
    List<String> lines,
    List<List<TextSpan>?> colors,
    TextStyle style,
    bool wrap,
  ) {
    if (style != this.style ||
        wrap != this.wrap ||
        !listEquals(lines, this.lines)) {
      return false;
    }
    for (var i = 0; i < colors.length; i++) {
      if (!identical(colors[i], this.colors[i])) return false;
    }
    return true;
  }
}

/// A wrapped citation's code, its line numbers in a [gutter] before it, each
/// level with where its line starts as the code is laid out.
class _LineNumbers extends MultiChildRenderObjectWidget {
  _LineNumbers({
    required this.gutter,
    required this.starts,
    required Widget code,
    required List<Widget> numbers,
  }) : super(children: [code, ...numbers]);

  final double gutter;

  /// Each number's line: the code's paragraph it is in, and where it
  /// starts in that paragraph's text.
  final List<({int paragraph, int offset})> starts;

  @override
  _RenderLineNumbers createRenderObject(BuildContext context) =>
      _RenderLineNumbers(gutter, starts);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLineNumbers renderObject,
  ) {
    renderObject
      ..gutter = gutter
      ..starts = starts;
  }
}

class _LineNumbersParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays the code out first, its first child, then each number after it
/// where the code's paragraphs put the start of its line.
class _RenderLineNumbers extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LineNumbersParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LineNumbersParentData> {
  _RenderLineNumbers(this._gutter, this._starts);

  double _gutter;
  set gutter(double value) {
    if (value == _gutter) return;
    _gutter = value;
    markNeedsLayout();
  }

  List<({int paragraph, int offset})> _starts;
  set starts(List<({int paragraph, int offset})> value) {
    if (listEquals(value, _starts)) return;
    _starts = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LineNumbersParentData) {
      child.parentData = _LineNumbersParentData();
    }
  }

  BoxConstraints _codeConstraints(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: math.max(0, constraints.maxWidth - _gutter));

  @override
  double computeMinIntrinsicWidth(double height) =>
      _gutter + (firstChild?.getMinIntrinsicWidth(height) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _gutter + (firstChild?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.getMinIntrinsicHeight(math.max(0, width - _gutter)) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.getMaxIntrinsicHeight(math.max(0, width - _gutter)) ?? 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final code =
        firstChild?.getDryLayout(_codeConstraints(constraints)) ?? Size.zero;
    return constraints.constrain(Size(_gutter + code.width, code.height));
  }

  @override
  void performLayout() {
    final code = firstChild;
    if (code == null) {
      size = constraints.smallest;
      return;
    }
    code.layout(_codeConstraints(constraints), parentUsesSize: true);
    (code.parentData! as _LineNumbersParentData).offset = Offset(_gutter, 0);
    final paragraphs = <RenderParagraph>[];
    void collect(RenderObject node) {
      if (node is RenderParagraph) {
        paragraphs.add(node);
      } else {
        node.visitChildren(collect);
      }
    }

    code.visitChildren(collect);

    // Each line's top in the code: its paragraph's, and where the line
    // starts below that.
    final tops = List.filled(_starts.length, 0.0);
    final laid = <_LaidParagraph>[];
    var i = 0;
    for (final (j, paragraph) in paragraphs.indexed) {
      final from = i;
      while (i < _starts.length && _starts[i].paragraph == j) {
        i++;
      }
      final offsets = [for (var k = from; k < i; k++) _starts[k].offset];
      final was = j < _laid.length ? _laid[j] : null;
      final within = was != null && was.isOf(paragraph, offsets)
          ? was
          : _LaidParagraph.of(paragraph, offsets);
      laid.add(within);
      final top = MatrixUtils.transformPoint(
        paragraph.getTransformTo(code),
        Offset.zero,
      ).dy;
      for (var k = from; k < i; k++) {
        tops[k] = top + within.tops[k - from];
      }
    }
    _laid = laid;

    var height = code.size.height;
    i = 0;
    for (var number = childAfter(code); number != null; i++) {
      number.layout(
        BoxConstraints.tightFor(width: _gutter),
        parentUsesSize: true,
      );
      final top = i < tops.length ? tops[i] : 0.0;
      (number.parentData! as _LineNumbersParentData).offset = Offset(0, top);
      height = math.max(height, top + number.size.height);
      number = childAfter(number);
    }
    size = constraints.constrain(Size(_gutter + code.size.width, height));
  }

  /// The code's paragraphs as last laid out, each with where its lines
  /// start: code the agent writes on lays out its last paragraph again,
  /// whose lines alone are found again.
  List<_LaidParagraph> _laid = const [];

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A paragraph of a wrapped citation's code as laid out, and how far below
/// its top each of its lines starts.
class _LaidParagraph {
  _LaidParagraph(
    this.paragraph,
    this.text,
    this.constraints,
    this.offsets,
    this.tops,
  );

  factory _LaidParagraph.of(RenderParagraph paragraph, List<int> offsets) =>
      _LaidParagraph(
        paragraph,
        paragraph.text,
        paragraph.constraints,
        offsets,
        [
          for (final offset in offsets)
            paragraph
                .getOffsetForCaret(TextPosition(offset: offset), Rect.zero)
                .dy,
        ],
      );

  final RenderParagraph paragraph;
  final InlineSpan text;
  final BoxConstraints constraints;
  final List<int> offsets;
  final List<double> tops;

  /// Whether [paragraph] is laid out as this was, its lines starting at
  /// [offsets] as these did.
  bool isOf(RenderParagraph paragraph, List<int> offsets) =>
      identical(paragraph, this.paragraph) &&
      identical(paragraph.text, text) &&
      paragraph.constraints == constraints &&
      listEquals(offsets, this.offsets);
}

/// Content that scrolls sideways when wider than there is room for (a code
/// card's lines, a table), which the reader may wrap to the width there is
/// instead: the button to, shown once it is wider ([canWrap]).
///
/// [onScrollMetrics] listens to the sideways scroll view's metrics.
mixin SidewaysWrap<T extends StatefulWidget> on State<T> {
  /// Wrapped to the width there is, rather than scrolling sideways.
  bool wrapped = false;

  /// Wider than there is room for, as last laid out unwrapped.
  bool _overflows = false;

  /// Whether there is anything to wrap, or it is wrapped: when to offer
  /// the button.
  bool get canWrap => _overflows || wrapped;

  bool onScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    final overflows = notification.metrics.maxScrollExtent > 0;
    // Wrapped, nothing overflows: whether it would unwrapped is kept.
    if (!wrapped && overflows != _overflows) {
      setState(() => _overflows = overflows);
    }
    return false;
  }

  Widget wrapButton(BuildContext context) => CodeBlockIconButton(
    icon: Codicons.wordWrap,
    tooltip: context.l10n.cmdToggleWordWrap,
    selected: wrapped,
    onTap: () => setState(() => wrapped = !wrapped),
  );
}

/// A small icon button of a code card's title, or a diagram's toolbar.
class CodeBlockIconButton extends StatelessWidget {
  const CodeBlockIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// On (a toggle's): in the accent's color.
  final bool selected;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: tooltip,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      toggled: selected ? true : null,
      label: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: hovered
                  ? themeColors['toolbar.hoverBackground']
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              icon,
              size: 14,
              color: selected
                  ? AppColors.accent
                  : hovered
                  ? AppColors.text
                  : AppColors.textMuted,
            ),
          ),
        ),
      ),
    ),
  );
}
