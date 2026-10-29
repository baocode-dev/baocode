import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import '../../l10n/l10n.dart';
import 'markdown_view.dart';
import 'step_header.dart';

/// A block between tags on lines of their own, as models write theirs
/// (`<analysis>` … `</analysis>`), or HTML's `<details>` (its `<summary>`
/// its title): a [TagSection]. HTML's other tags stay as they were, text.
/// Unclosed (still streaming): to the end.
class TagBlockSyntax extends md.BlockSyntax {
  const TagBlockSyntax();

  /// Its element's tag; what it was between, its attributes.
  static const tag = 'tag-section';
  static const nameAttribute = 'name';
  static const titleAttribute = 'title';
  static const openAttribute = 'open';

  @override
  RegExp get pattern => _opening;

  static final _opening = RegExp(r'^ {0,3}<([A-Za-z][\w-]*)(\s[^<>]*)?>\s*$');
  static final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
  static final _summary = RegExp(
    r'^\s*<summary(?:\s[^<>]*)?>(.*)</summary>\s*$',
    caseSensitive: false,
  );
  static final _markup = RegExp(r'<[^<>]*>');

  @override
  bool canParse(md.BlockParser parser) {
    final name = _opening.firstMatch(parser.current.content)?[1];
    if (name == null) return false;
    final lower = name.toLowerCase();
    return lower == 'details' || lower == 'summary' || !_html.contains(lower);
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _opening.firstMatch(parser.current.content)!;
    final name = match[1]!;
    final escaped = RegExp.escape(name);
    final opens = RegExp(
      '^ {0,3}<$escaped(?:\\s[^<>]*)?>\\s*\$',
      caseSensitive: false,
    );
    final closes = RegExp('^ {0,3}</$escaped\\s*>\\s*\$', caseSensitive: false);
    parser.advance();
    final lines = <String>[];
    // The same tag within it, and code, whose lines are not tags.
    var depth = 0;
    String? fence;
    while (!parser.isDone) {
      final line = parser.current.content;
      parser.advance();
      if (fence != null) {
        final trimmed = line.trim();
        if (trimmed.length >= fence.length &&
            trimmed.split('').every((char) => char == fence![0])) {
          fence = null;
        }
      } else if (_fence.firstMatch(line) case final opening?) {
        fence = opening[1];
      } else if (closes.hasMatch(line)) {
        if (depth-- == 0) break;
      } else if (opens.hasMatch(line)) {
        depth++;
      }
      lines.add(line);
    }

    final details = name.toLowerCase() == 'details';
    String? title;
    // `<summary>…</summary>` first in a `<details>`: its title.
    if (details) {
      final first = lines.indexWhere((line) => line.trim().isNotEmpty);
      if (first >= 0) {
        if (_summary.firstMatch(lines[first]) case final summary?) {
          title = summary[1]!.replaceAll(_markup, '').trim();
          lines.removeAt(first);
        }
      }
    }
    final children = parser.document.parseLines(lines);
    // Or a `<summary>` of lines of its own.
    if (details && title == null) {
      if (children.firstOrNull case final md.Element first
          when first.tag == tag &&
              first.attributes[nameAttribute]?.toLowerCase() == 'summary') {
        title = first.textContent.trim().split('\n').first;
        children.removeAt(0);
      }
    }
    return md.Element(tag, children)
      ..attributes[nameAttribute] = name
      ..attributes.addAll({
        if (title != null && title.isNotEmpty) titleAttribute: title,
        if (details && (match[2] ?? '').contains(RegExp(r'\bopen\b')))
          openAttribute: '',
      });
  }

  /// HTML's elements but `<details>` and `<summary>`: a line of one of these
  /// is left to the markdown's HTML.
  static const _html = {
    'a', 'abbr', 'address', 'area', 'article', 'aside', 'audio', 'b', //
    'base', 'basefont', 'bdi', 'bdo', 'blockquote', 'body', 'br', 'button',
    'canvas', 'caption', 'center', 'cite', 'code', 'col', 'colgroup', 'data',
    'dd', 'del', 'dfn', 'dialog', 'dir', 'div', 'dl', 'dt', 'em', 'embed',
    'fieldset', 'figcaption', 'figure', 'font', 'footer', 'form', 'frame',
    'frameset', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'head', 'header', 'hr',
    'html', 'i', 'iframe', 'img', 'input', 'ins', 'kbd', 'label', 'legend',
    'li', 'link', 'main', 'map', 'mark', 'menu', 'menuitem', 'meta', 'meter',
    'nav', 'noframes', 'noscript', 'object', 'ol', 'optgroup', 'option',
    'output', 'p', 'param', 'picture', 'pre', 'progress', 'q', 'rp', 'rt',
    'ruby', 's', 'samp', 'script', 'section', 'select', 'small', 'source',
    'span', 'strike', 'strong', 'style', 'sub', 'sup', 'svg', 'table',
    'tbody', 'td', 'template', 'textarea', 'tfoot', 'th', 'thead', 'time',
    'title', 'tr', 'track', 'tt', 'u', 'ul', 'var', 'video', 'wbr',
  };
}

/// A [TagBlockSyntax] block: headed by its tag's name ("Analysis"), or a
/// `<details>`'s summary, and folding there; open, but for a `<details>`
/// not marked so.
class TagSection extends StatefulWidget {
  const TagSection({
    super.key,
    required this.node,
    required this.style,
    required this.options,
  });

  final md.Element node;
  final TextStyle style;
  final MarkdownOptions options;

  /// What heads [node]: its summary, or its tag's name as words; null for a
  /// `<details>` without a summary.
  static String? titleOf(md.Element node) {
    if (node.attributes[TagBlockSyntax.titleAttribute] case final title?) {
      return title;
    }
    final name = node.attributes[TagBlockSyntax.nameAttribute] ?? '';
    final words = name.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (words.isEmpty || name.toLowerCase() == 'details') return null;
    return words[0].toUpperCase() + words.substring(1);
  }

  @override
  State<TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends State<TagSection> {
  late bool _open =
      widget.node.attributes[TagBlockSyntax.nameAttribute]?.toLowerCase() !=
          'details' ||
      widget.node.attributes.containsKey(TagBlockSyntax.openAttribute);

  @override
  Widget build(BuildContext context) {
    final children = widget.node.children ?? const <md.Node>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        StepHeader(
          verb: TagSection.titleOf(widget.node) ?? context.l10n.markdownDetails,
          expanded: _open,
          onToggle: children.isEmpty
              ? null
              : () => setState(() => _open = !_open),
        ),
        if (_open && children.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            child: MarkdownBlocks(
              nodes: children,
              style: widget.style,
              options: widget.options,
            ),
          ),
      ],
    );
  }
}
