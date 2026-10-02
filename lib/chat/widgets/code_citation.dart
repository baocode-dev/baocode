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

/// What the [CodeCitationCard]s under it can do: open the file cited and
/// color the code.
class CodeCitationScope extends InheritedWidget {
  const CodeCitationScope({
    super.key,
    this.root,
    this.onOpen,
    this.colorize,
    required super.child,
  });

  /// Where the agent works, which relative paths are in. Files outside it
  /// do not open.
  final String? root;

  /// Opens the file at [path] (absolute, in [root]) with [start] to [end]
  /// (lines from 1) selected.
  final void Function(String path, int start, int end)? onOpen;

  final CodeColorizer? colorize;

  static CodeCitationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CodeCitationScope>();

  @override
  bool updateShouldNotify(CodeCitationScope oldWidget) =>
      root != oldWidget.root ||
      onOpen != oldWidget.onOpen ||
      colorize != oldWidget.colorize;
}

/// A [CodeCitation] as a card: the file's icon, name and lines, which open
/// it there, over the code with its line numbers. Taller than
/// [maxCodeHeight], the code scrolls; folded, only the title shows.
class CodeCitationCard extends StatefulWidget {
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
  State<CodeCitationCard> createState() => _CodeCitationCardState();
}

class _CodeCitationCardState extends State<CodeCitationCard> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  bool _expanded = true;
  bool _hovered = false;
  bool _copied = false;
  Timer? _copiedTimer;

  CodeColorizer? _colorize;

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
    final colorize = CodeCitationScope.maybeOf(context)?.colorize;
    if (colorize != _colorize) {
      _colorize = colorize;
      _uncolored = false;
      _coloredCode = null;
    }
    _colorSoon();
  }

  @override
  void didUpdateWidget(CodeCitationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.citation.path != widget.citation.path) _uncolored = false;
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
    final colorize = _colorize;
    final code = widget.code;
    if (colorize == null || _uncolored || _coloring || code == _coloredCode) {
      return;
    }
    _coloring = true;
    colorize(widget.citation.path, code).then(
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

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final line = colors['chat.requestBorder'];
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: colors['textCodeBlock.background'],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
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

  /// The chevron and the empty space fold it; the file opens it there.
  Widget _title(BuildContext context) {
    final citation = widget.citation;
    final scope = CodeCitationScope.maybeOf(context);
    final open = scope?.onOpen;
    final path = switch (scope?.root) {
      final root? => citation.pathIn(root),
      null => null,
    };
    final l10n = context.l10n;
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
          onTap: () => open(path, citation.start, citation.end),
          child: file,
        ),
      );
    }
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
                _IconButton(
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
                    child: IdeHover(message: citation.path, child: file),
                  ),
                ),
                Visibility.maintain(
                  visible: _hovered || _copied,
                  child: _IconButton(
                    icon: _copied ? Codicons.check : Codicons.copy,
                    tooltip: l10n.commonCopy,
                    onTap: _copy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Line numbers from the citation's first, beside the code; both scroll
  /// down together, the code alone sideways.
  Widget _body() {
    final lines = widget.code.split('\n');
    final style = TextStyle(
      color: themeColors['editor.foreground'],
      fontFamily: AppFonts.mono,
      fontSize: 12,
      height: 1.5,
    );
    final last = widget.citation.start + lines.length - 1;
    final numbers = SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 14),
        child: Text(
          [for (var i = widget.citation.start; i <= last; i++) '$i'].join('\n'),
          textAlign: TextAlign.right,
          style: style.copyWith(
            color: themeColors['editorLineNumber.foreground'],
          ),
        ),
      ),
    );
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
                  child: Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: _hovered,
                    // Not the vertical one's.
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 12),
                      child: code,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small icon button of the card's title.
class _IconButton extends StatelessWidget {
  const _IconButton({
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
