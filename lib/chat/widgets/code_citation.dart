import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../side_panel/file_link.dart' show FileLineRange, FileLink;
import '../side_panel/file_open.dart' show FileOpenScope;
import 'hover_builder.dart';
import 'wheel_latch.dart';

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

  /// [path] in [root], the folder the agent works in; null when outside.
  String? pathIn(String root) {
    final full = p.normalize(p.isAbsolute(path) ? path : p.join(root, path));
    return p.isWithin(root, full) ? full : null;
  }

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
    // Lines ahead of the opening fence to the closing one.
    int? end;
    for (var i = 1; i <= cited + 1; i++) {
      final line = parser.peek(i);
      if (line == null) break;
      if (!close.hasMatch(line.content)) continue;
      end ??= i;
      if (i == cited + 1) end = i;
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

  static CodeCitationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CodeCitationScope>();

  @override
  bool updateShouldNotify(CodeCitationScope oldWidget) =>
      root != oldWidget.root ||
      onOpen != oldWidget.onOpen ||
      colorize != oldWidget.colorize ||
      colorizeBlock != oldWidget.colorizeBlock;
}

/// A [CodeCitation] as a card: the file's icon, name and lines, which open
/// it there, over the code with its line numbers. Taller than
/// [maxCodeHeight], the code scrolls; folded, only the title shows.
class CodeCitationCard extends StatelessWidget {
  const CodeCitationCard({
    super.key,
    required this.citation,
    required this.code,
  });

  final CodeCitation citation;
  final String code;

  /// About a dozen lines.
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

class _CodeCardState extends State<_CodeCard> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
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
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Colors the code unless it is colored, one request at a time: code
  /// that grew meanwhile is asked for once that one is answered.
  void _colorSoon() {
    final code = widget.code;
    if (_uncolored || _coloring || code == _coloredCode) return;
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
        if (lines == null) {
          _uncolored = true;
        } else {
          setState(() {
            _coloredLines = code.split('\n');
            _colors = lines;
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
                      child: _copyButton(context),
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

  Widget _copyButton(BuildContext context) => SelectionContainer.disabled(
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
    return SelectionContainer.disabled(
      child: HoverBuilder(
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            // Faintly lit while hovered.
            color: hovered
                ? hover.withValues(alpha: hover.a * 0.6)
                : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
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

  /// Line numbers from the citation's first, beside the code; both scroll
  /// down together, the code alone sideways. A code block has none. Both
  /// scrollbars at the edges of the card, not of the code as long as it
  /// is.
  Widget _body() {
    final lines = widget.code.split('\n');
    final citation = widget.citation;
    final style = TextStyle(
      color: themeColors['editor.foreground'],
      fontFamily: AppFonts.mono,
      fontSize: 12,
      height: 1.5,
    );
    final numbers = switch (citation) {
      final citation? => SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 14),
          child: Text(
            [for (var i = 0; i < lines.length; i++) '${citation.start + i}']
                .join('\n'),
            textAlign: TextAlign.right,
            style: style.copyWith(
              color: themeColors['editorLineNumber.foreground'],
            ),
          ),
        ),
      ),
      null => const SizedBox(width: 12),
    };
    // Where the code starts: the sideways scrollbar's track from there.
    final gutter = switch (citation) {
      final citation? => _numbersWidth(
        '${citation.start + lines.length - 1}',
        style,
      ),
      null => 12.0,
    };
    final code = Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final (i, line) in lines.indexed) ...[
            if (i > 0) const TextSpan(text: '\n'),
            if (i < _colors.length &&
                i < _coloredLines.length &&
                _coloredLines[i] == line)
              ..._colors[i]
            else
              TextSpan(text: line),
          ],
        ],
      ),
      softWrap: false,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: CodeCitationCard.maxCodeHeight,
      ),
      // The scrollbar's padding is the media's.
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(padding: EdgeInsets.only(left: gutter)),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: _hovered,
          // The code's, inside the vertical one.
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: Scrollbar(
            controller: _vertical,
            thumbVisibility: _hovered,
            child: SingleChildScrollView(
              controller: _vertical,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: WheelLatch(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    numbers,
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 12),
                        child: code,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

/// A small icon button of a code card's title, or a diagram's toolbar.
class CodeBlockIconButton extends StatelessWidget {
  const CodeBlockIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: tooltip,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
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
              color: hovered ? AppColors.text : AppColors.textMuted,
            ),
          ),
        ),
      ),
    ),
  );
}
