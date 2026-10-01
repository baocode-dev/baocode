import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/editor_launcher.dart';
import 'markdown_math.dart';

/// GitHub-flavored markdown as plain widgets (so a surrounding
/// `SelectionArea` selects and copies it): headings, paragraphs, lists
/// (and task lists), code blocks, quotes, tables, rules, and inline
/// strong, emphasis, strikethrough, code, links and TeX math.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key, this.style});

  final String data;

  /// [baseStyle] when null.
  final TextStyle? style;

  static TextStyle get baseStyle =>
      TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.6);

  static TextStyle get codeStyle => TextStyle(
    color: AppColors.inlineCode,
    fontFamily: AppFonts.mono,
    fontSize: 12.5,
    backgroundColor: AppColors.inlineCodeBackground,
  );

  static final _document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    blockSyntaxes: const [MathBlockSyntax()],
    inlineSyntaxes: [InlineMathSyntax()],
    encodeHtml: false,
  );

  @override
  Widget build(BuildContext context) {
    final nodes = _document.parse(data);
    return _Blocks(nodes: nodes, style: style ?? baseStyle);
  }
}

class _Blocks extends StatelessWidget {
  const _Blocks({required this.nodes, required this.style});

  final List<md.Node> nodes;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final node in nodes) {
      final block = _block(node, style);
      if (block == null) continue;
      if (children.isNotEmpty) children.add(SizedBox(height: _gap(node)));
      children.add(block);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  static double _gap(md.Node node) => switch (node) {
    md.Element(tag: 'h1' || 'h2' || 'h3') => 12,
    _ => 8,
  };
}

Widget? _block(md.Node node, TextStyle style) {
  if (node is md.Text) {
    if (node.text.trim().isEmpty) return null;
    return Text.rich(TextSpan(style: style, text: node.text));
  }
  if (node is! md.Element) return null;
  switch (node.tag) {
    case 'math':
      return MathView(node.textContent, display: true);
    case 'p':
      return Text.rich(_inlines(node.children ?? const [], style));
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      final size = switch (node.tag) {
        'h1' => 19.0,
        'h2' => 17.0,
        'h3' => 15.0,
        _ => 13.5,
      };
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text.rich(
          _inlines(
            node.children ?? const [],
            style.copyWith(
              color: AppColors.textPrimary,
              fontSize: size,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      );
    case 'ul' || 'ol':
      return _List(node: node, style: style);
    case 'pre':
      final code = node.children?.firstOrNull;
      final text = code is md.Element ? code.textContent : node.textContent;
      final language = code is md.Element
          ? code.attributes['class']?.replaceFirst('language-', '')
          : null;
      return MarkdownCodeBlock(
        code: text.endsWith('\n') ? text.substring(0, text.length - 1) : text,
        language: language,
      );
    case 'blockquote':
      return Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: themeColors['textBlockQuote.background'],
          border: Border(
            left: BorderSide(
              color: themeColors['textBlockQuote.border'],
              width: 3,
            ),
          ),
        ),
        child: _Blocks(
          nodes: node.children ?? const [],
          style: style.copyWith(color: AppColors.textMuted),
        ),
      );
    case 'hr':
      // As upstream's chat: the separator's color, faint.
      final separator = themeColors['textSeparator.foreground'];
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(
          height: 1,
          color: separator.withValues(alpha: separator.a * 0.33),
        ),
      );
    case 'table':
      return _Table(node: node, style: style);
    default:
      return Text.rich(_inlines([node], style));
  }
}

/// A list, numbered or not, whose items may hold blocks and nested lists.
class _List extends StatelessWidget {
  const _List({required this.node, required this.style});

  final md.Element node;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final ordered = node.tag == 'ol';
    final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
    final items = [
      for (final child in node.children ?? const <md.Node>[])
        if (child is md.Element && child.tag == 'li') child,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, item) in items.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ordered ? 24 : 18,
                  child: _marker(item, ordered ? '${start + i}.' : '•'),
                ),
                Expanded(child: _itemBody(item)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _marker(md.Element item, String text) {
    final checkbox = item.children?.firstOrNull;
    if (checkbox is md.Element && checkbox.tag == 'input') {
      final checked = checkbox.attributes['checked'] != null;
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Icon(
          checked ? Icons.check_box_rounded : Icons.check_box_outline_blank,
          size: 14,
          color: checked ? AppColors.added : AppColors.textMuted,
        ),
      );
    }
    return Text(text, style: style.copyWith(color: AppColors.textMuted));
  }

  /// An item's text and blocks: a tight item's text is inline children, a
  /// loose one's is paragraphs.
  Widget _itemBody(md.Element item) {
    final children = [
      for (final child in item.children ?? const <md.Node>[])
        if (!(child is md.Element && child.tag == 'input')) child,
    ];
    final inline = <md.Node>[];
    final blocks = <Widget>[];
    void flush() {
      if (inline.isEmpty) return;
      blocks.add(Text.rich(_inlines([...inline], style)));
      inline.clear();
    }

    for (final child in children) {
      final isBlock =
          child is md.Element &&
          const {
            'p',
            'ul',
            'ol',
            'pre',
            'blockquote',
            'table',
            'h1',
            'h2',
            'h3',
            'h4',
            'hr',
          }.contains(child.tag);
      if (!isBlock) {
        inline.add(child);
        continue;
      }
      flush();
      final block = _block(child, style);
      if (block != null) blocks.add(block);
    }
    flush();
    if (blocks.length == 1) return blocks.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, block) in blocks.indexed) ...[
          if (i > 0) const SizedBox(height: 4),
          block,
        ],
      ],
    );
  }
}

/// A table in a card as the steps' are, as wide as its columns up to the
/// width there is; wider, it scrolls sideways, with a bar to show it while
/// the pointer is over it or it scrolls.
class _Table extends StatefulWidget {
  const _Table({required this.node, required this.style});

  final md.Element node;
  final TextStyle style;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  final _scroll = ScrollController();
  bool _hovered = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final rows = <(bool, List<md.Element>)>[];
    for (final section in widget.node.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      for (final row in section.children ?? const <md.Node>[]) {
        if (row is! md.Element || row.tag != 'tr') continue;
        rows.add((
          section.tag == 'thead',
          [
            for (final cell in row.children ?? const <md.Node>[])
              if (cell is md.Element) cell,
          ],
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows
        .map((row) => row.$2.length)
        .reduce((a, b) => a > b ? a : b);
    final line = BorderSide(color: themeColors['chat.requestBorder']);
    final table = Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      // The card draws the edge.
      border: TableBorder.symmetric(inside: line),
      children: [
        for (final (header, cells) in rows)
          TableRow(
            decoration: header
                ? BoxDecoration(color: AppColors.surfaceRaised)
                : null,
            children: [
              for (var i = 0; i < columns; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: i < cells.length
                      ? Text.rich(
                          _inlines(
                            cells[i].children ?? const [],
                            header
                                ? style.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  )
                                : style,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        // The edge over the cells, the header's color clipped to the corners.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.fromBorderSide(line),
        ),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: _hovered,
            interactive: true,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: table,
            ),
          ),
        ),
      ),
    );
  }
}

/// A fenced code block: monospace, scrolling sideways, its language shown.
class MarkdownCodeBlock extends StatelessWidget {
  const MarkdownCodeBlock({super.key, required this.code, this.language});

  final String code;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Container(
      decoration: BoxDecoration(
        color: colors['textCodeBlock.background'],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors['chat.requestBorder']),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (language case final language? when language.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(
                language,
                style: TextStyle(color: AppColors.textFaint, fontSize: 11),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Text(
              code,
              style: TextStyle(
                color: colors['editor.foreground'],
                fontFamily: AppFonts.mono,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TextSpan _inlines(List<md.Node> nodes, TextStyle style) =>
    TextSpan(style: style, children: [for (final node in nodes) _inline(node)]);

InlineSpan _inline(md.Node node) {
  if (node is md.Text) return TextSpan(text: _unescape(node.text));
  if (node is! md.Element) return const TextSpan();
  final children = node.children ?? const <md.Node>[];
  List<InlineSpan> inner() => [for (final child in children) _inline(child)];
  return switch (node.tag) {
    'strong' || 'b' => TextSpan(
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      children: inner(),
    ),
    'em' || 'i' => TextSpan(
      style: const TextStyle(fontStyle: FontStyle.italic),
      children: inner(),
    ),
    'del' => TextSpan(
      style: const TextStyle(decoration: TextDecoration.lineThrough),
      children: inner(),
    ),
    'code' => TextSpan(
      text: ' ${_unescape(node.textContent)} ',
      style: MarkdownView.codeStyle,
    ),
    'a' => switch (_linkRecognizer(node.attributes['href'])) {
      final recognizer? => TextSpan(
        style: TextStyle(color: AppColors.accent),
        children: [for (final span in inner()) _linked(span, recognizer)],
      ),
      null => TextSpan(
        style: TextStyle(color: AppColors.accent),
        children: inner(),
      ),
    },
    'math' => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: MathView(
        node.textContent,
        display: node.attributes['display'] == 'block',
      ),
    ),
    'br' => const TextSpan(text: '\n'),
    'img' => TextSpan(text: '[${node.attributes['alt'] ?? 'image'}]'),
    _ => TextSpan(children: inner()),
  };
}

/// Opens [href] in the default browser (or mail app). Only web and mail
/// links: the text is the agent's, and `open` would as well run a local
/// file or app.
GestureRecognizer? _linkRecognizer(String? href) {
  final uri = href == null ? null : Uri.tryParse(href.trim());
  if (uri == null || !const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
    return null;
  }
  return TapGestureRecognizer()..onTap = () => openExternal(uri.toString());
}

/// [span] with every piece of its text tappable: a tap lands on the
/// innermost span, which does not inherit its parent's recognizer.
InlineSpan _linked(InlineSpan span, GestureRecognizer recognizer) =>
    switch (span) {
      TextSpan(:final text, :final style, :final children) => TextSpan(
        text: text,
        style: style,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
        children: [
          for (final child in children ?? const <InlineSpan>[])
            _linked(child, recognizer),
        ],
      ),
      _ => span,
    };

String _unescape(String text) => text
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");
