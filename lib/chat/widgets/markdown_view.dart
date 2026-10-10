import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/editor_launcher.dart';
import '../side_panel/file_link.dart';
import '../side_panel/file_open.dart';
import 'code_citation.dart';
import 'hover_scrollbar.dart';
import 'inline_code.dart';
import 'markdown_math.dart';
import 'mermaid_code_block.dart';

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

  /// Inline code's, its background painted by [InlineCodeText].
  static TextStyle get codeStyle =>
      AppFonts.uiCodeStyle(12.5).copyWith(color: AppColors.inlineCode);

  /// The block syntaxes of its own, before GFM's: code citations and TeX.
  static const blockSyntaxes = <md.BlockSyntax>[
    CodeCitationFenceSyntax(),
    MathBlockSyntax(),
  ];
  static List<md.InlineSyntax> get inlineSyntaxes => [InlineMathSyntax()];

  /// A document parsing as it does; one keeps the link definitions it
  /// read (see the IDE's markdown preview).
  static md.Document document() => md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    blockSyntaxes: blockSyntaxes,
    inlineSyntaxes: inlineSyntaxes,
    encodeHtml: false,
  );

  static final _document = document();

  @override
  Widget build(BuildContext context) {
    final nodes = _document.parse(data);
    // In a chat whose files open (see FileOpenScope): links to them, and
    // inline code naming one once it is known to be there.
    final files = FileOpenScope.maybeOf(context);
    if (files == null) {
      return MarkdownBlocks(nodes: nodes, style: style ?? baseStyle);
    }
    Widget? icon(FileLink? link) {
      final path = link == null ? null : files.resolve(link.path);
      if (path == null) return null;
      return _isFolder(link!.path, files.existence.known(path))
          ? FolderIcon(path, size: _fileIconSize)
          : FileIcon(path, size: _fileIconSize);
    }

    final options = MarkdownOptions(
      link: (href) => _linkRecognizer(href) ?? files.linkRecognizer(href),
      code: files.codeRecognizer,
      linkIcon: (href) => icon(FileLink.parseHref(href)),
      codeIcon: (code) => icon(FileLink.parseText(code)),
    );
    Widget blocks(BuildContext context) => MarkdownBlocks(
      nodes: nodes,
      style: style ?? baseStyle,
      options: options,
    );
    // Code is a link, and a link's icon a file's, once the file is found.
    if (!data.contains('`') && !data.contains('](')) return blocks(context);
    return ListenableBuilder(
      listenable: files.existence,
      builder: (context, _) => blocks(context),
    );
  }
}

/// How [MarkdownBlocks] draws and what its links, images and task boxes
/// do: as the chat's by default.
@immutable
class MarkdownOptions {
  const MarkdownOptions({
    this.headingSizes = const [19, 17, 15, 13.5, 13.5, 13.5],
    this.headingRules = false,
    this.gap = 8,
    this.headingGap = 12,
    this.link,
    this.code,
    this.linkIcon,
    this.codeIcon,
    this.image,
    this.onToggleTask,
  });

  /// `h1` to `h6`'s font sizes.
  final List<double> headingSizes;

  /// Whether `h1` and `h2` have a line under them, as GitHub's.
  final bool headingRules;

  /// The space between blocks, and before and after a heading.
  final double gap;
  final double headingGap;

  /// What a tap on a link to `href` does; web and mail links open in the
  /// browser when null, others nothing.
  final GestureRecognizer? Function(String? href)? link;

  /// What a tap on inline code does (it names a file, say); nothing when
  /// null, or it gives none.
  final GestureRecognizer? Function(String code)? code;

  /// What is drawn before a link to `href` (or inline code, see [code]):
  /// the icon of the file or folder it opens, say; nothing when null.
  final Widget? Function(String? href)? linkIcon;
  final Widget? Function(String code)? codeIcon;

  /// An image (`![alt](src "title")`, or HTML's with its [width] and
  /// [height] in pixels); its alt text in brackets when null.
  final Widget Function(
    String src,
    String alt,
    String? title, {
    double? width,
    double? height,
  })?
  image;

  /// Called with a task list box's number (see [numberTasks]) when it is
  /// clicked; the boxes are only drawn when null.
  final ValueChanged<int>? onToggleTask;
}

/// Numbers the task list boxes of [nodes], in the order their lines come,
/// for [MarkdownOptions.onToggleTask].
void numberTasks(List<md.Node> nodes) {
  var count = 0;
  void visit(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'input') node.attributes[_taskAttribute] = '${count++}';
    node.children?.forEach(visit);
  }

  nodes.forEach(visit);
}

const _taskAttribute = 'data-task';

/// Parsed markdown ([MarkdownView.document]) as widgets.
class MarkdownBlocks extends StatelessWidget {
  const MarkdownBlocks({
    super.key,
    required this.nodes,
    required this.style,
    this.options = const MarkdownOptions(),
  });

  final List<md.Node> nodes;
  final TextStyle style;
  final MarkdownOptions options;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final node in nodes) {
      final block = _block(node, style, options);
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

  double _gap(md.Node node) => switch (node) {
    md.Element(tag: 'h1' || 'h2' || 'h3') => options.headingGap,
    _ => options.gap,
  };
}

Widget? _block(md.Node node, TextStyle style, MarkdownOptions options) {
  if (node is md.Text) {
    if (node.text.trim().isEmpty) return null;
    return Text.rich(TextSpan(style: style, text: node.text));
  }
  if (node is! md.Element) return null;
  switch (node.tag) {
    case 'math':
      return MathView(node.textContent, display: true);
    case 'p':
      return InlineCodeText(
        _inlines(node.children ?? const [], style, options),
      );
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      final level = int.parse(node.tag.substring(1));
      final heading = Padding(
        padding: const EdgeInsets.only(top: 2),
        child: InlineCodeText(
          _inlines(
            node.children ?? const [],
            style.copyWith(
              color: AppColors.textPrimary,
              fontSize: options.headingSizes[level - 1],
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            options,
          ),
        ),
      );
      if (!options.headingRules || level > 2) return heading;
      return Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: themeColors['textSeparator.foreground']),
          ),
        ),
        child: heading,
      );
    case 'ul' || 'ol':
      return _List(node: node, style: style, options: options);
    case 'pre':
      final code = node.children?.firstOrNull;
      final text = code is md.Element ? code.textContent : node.textContent;
      final language = code is md.Element
          ? code.attributes['class']?.replaceFirst('language-', '')
          : null;
      final body = text.endsWith('\n')
          ? text.substring(0, text.length - 1)
          : text;
      if (CodeCitation.parse(language) case final citation?) {
        return CodeCitationCard(citation: citation, code: body);
      }
      // `python title="a.py"`: the language is the first word.
      final name = language?.trim().split(RegExp(r'\s')).first;
      if (name?.toLowerCase() == 'mermaid') {
        return MermaidCodeBlock(code: body);
      }
      return MarkdownCodeBlock(
        code: body,
        language: name == null || name.isEmpty ? null : name,
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
        child: MarkdownBlocks(
          nodes: node.children ?? const [],
          style: style.copyWith(color: AppColors.textMuted),
          options: options,
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
      return _Table(node: node, style: style, options: options);
    default:
      return InlineCodeText(_inlines([node], style, options));
  }
}

/// A list, numbered or not, whose items may hold blocks and nested lists.
class _List extends StatelessWidget {
  const _List({required this.node, required this.style, required this.options});

  final md.Element node;
  final TextStyle style;
  final MarkdownOptions options;

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
      final box = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Icon(
          checked ? Icons.check_box_rounded : Icons.check_box_outline_blank,
          size: 14,
          color: checked ? AppColors.added : AppColors.textMuted,
        ),
      );
      final toggle = options.onToggleTask;
      final task = int.tryParse(checkbox.attributes[_taskAttribute] ?? '');
      if (toggle == null || task == null) return box;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => toggle(task),
          child: box,
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
      blocks.add(InlineCodeText(_inlines([...inline], style, options)));
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
      final block = _block(child, style, options);
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
  const _Table({
    required this.node,
    required this.style,
    required this.options,
  });

  final md.Element node;
  final TextStyle style;
  final MarkdownOptions options;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  final _scroll = ScrollController();

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
                      ? InlineCodeText(
                          _inlines(
                            cells[i].children ?? const [],
                            header
                                ? style.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  )
                                : style,
                            widget.options,
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
        child: HoverScrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        ),
      ),
    );
  }
}

TextSpan _inlines(
  List<md.Node> nodes,
  TextStyle style,
  MarkdownOptions options,
) => TextSpan(
  style: style,
  children: [for (final node in nodes) _inline(node, options)],
);

InlineSpan _inline(md.Node node, MarkdownOptions options) {
  if (node is md.Text) return TextSpan(text: _unescape(node.text));
  if (node is! md.Element) return const TextSpan();
  final children = node.children ?? const <md.Node>[];
  List<InlineSpan> inner() => [
    for (final child in children) _inline(child, options),
  ];
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
    'code' => switch (options.code?.call(_unescape(node.textContent))) {
      // A file's: in the link's color, its icon first in the background.
      final recognizer? => InlineCodeSpan(
        style: MarkdownView.codeStyle.copyWith(color: AppColors.accent),
        children: [
          if (options.codeIcon?.call(_unescape(node.textContent))
              case final icon?)
            _linkIcon(
              icon,
              recognizer,
              const EdgeInsets.only(left: 4, right: 3),
            )
          else
            const TextSpan(text: ' '),
          TextSpan(
            text: '${_unescape(node.textContent)} ',
            recognizer: recognizer,
            mouseCursor: SystemMouseCursors.click,
          ),
        ],
      ),
      null => InlineCodeSpan(
        text: ' ${_unescape(node.textContent)} ',
        style: MarkdownView.codeStyle,
      ),
    },
    'a' => switch ((options.link ?? _linkRecognizer)(node.attributes['href'])) {
      final recognizer? => TextSpan(
        style: TextStyle(color: AppColors.accent),
        children: [
          if (options.linkIcon?.call(node.attributes['href']) case final icon?)
            _linkIcon(icon, recognizer, const EdgeInsets.only(right: 3)),
          for (final span in inner()) _linked(span, recognizer),
        ],
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
    'img' => switch (options.image) {
      final image? => WidgetSpan(
        child: image(
          _unescape(node.attributes['src'] ?? ''),
          _unescape(node.attributes['alt'] ?? ''),
          node.attributes['title'],
          width: double.tryParse(node.attributes['width'] ?? ''),
          height: double.tryParse(node.attributes['height'] ?? ''),
        ),
      ),
      null => TextSpan(text: '[${node.attributes['alt'] ?? 'image'}]'),
    },
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

const _fileIconSize = 14.0;

/// Whether a link to [written] (as the agent wrote it), [known] to be a
/// file or not (see [FileExistence.known]), goes to a folder: one written
/// with a slash after it, or a name without an extension that is not a
/// file found (`lib/ide`, not `LICENSE`).
bool _isFolder(String written, bool? known) {
  if (written.endsWith('/') || written.endsWith(r'\')) return true;
  if (known == true) return false;
  final name = written.split(RegExp(r'[/\\]')).last;
  // A leading dot is not an extension's (`.github`).
  return name.lastIndexOf('.') <= 0;
}

/// [icon] before a link: a tap on it goes where the link does.
WidgetSpan _linkIcon(
  Widget icon,
  GestureRecognizer recognizer,
  EdgeInsets padding,
) {
  icon = Padding(padding: padding, child: icon);
  if (recognizer is TapGestureRecognizer) {
    icon = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: recognizer.onTap,
        child: icon,
      ),
    );
  }
  return WidgetSpan(alignment: PlaceholderAlignment.middle, child: icon);
}

/// [span] with every piece of its text tappable: a tap lands on the
/// innermost span, which does not inherit its parent's recognizer.
InlineSpan _linked(InlineSpan span, GestureRecognizer recognizer) =>
    switch (span) {
      // Code in a link keeps its background, and goes where the link does.
      InlineCodeSpan(:final text, :final style) => InlineCodeSpan(
        text: text,
        style: style,
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
      ),
      // An image in a link (`[![alt](src)](href)`).
      WidgetSpan(:final child, :final alignment)
          when recognizer is TapGestureRecognizer =>
        WidgetSpan(
          alignment: alignment,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: recognizer.onTap, child: child),
          ),
        ),
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
