// The HTML of an extension's README, as far as markdown draws it. Upstream
// renders it (sanitized) in the extension editor's webview; here an HTML
// block or inline tag would show as its source, so its images and links
// are kept, block tags part paragraphs, and other tags are dropped.

import 'package:markdown/markdown.dart' as md;

final _tag = RegExp(r'<!--[\s\S]*?-->|<(/?)([a-zA-Z][\w-]*)([^>]*)>');
final _attribute = RegExp(
  r'''([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''',
);

const _blockTags = {
  'p', 'div', 'center', 'figure', 'figcaption', 'details', 'summary', //
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'table', 'tr',
  'blockquote', 'hr', 'section', 'header', 'footer',
};

/// [nodes] (a parsed README) with their HTML as markdown nodes.
List<md.Node> readmeNodes(List<md.Node> nodes) => [
  for (final node in nodes)
    if (node is md.Text && _hasHtml(node.text))
      ..._paragraphs(_tokens(node.text))
    else if (node is md.Element)
      _inElement(node)
    else
      node,
];

md.Node _inElement(md.Element element) {
  final children = element.children;
  // Code is its text, tags and all.
  if (children == null || const {'code', 'pre', 'math'}.contains(element.tag)) {
    return element;
  }
  // Blocks hold blocks; others (`p`, headings, cells) inline nodes.
  final blocks = const {'blockquote', 'li', 'ul', 'ol'}.contains(element.tag);
  final converted = blocks
      ? readmeNodes(children)
      : _inlines(_inlineTokens(children));
  return md.Element(element.tag, converted)
    ..attributes.addAll(element.attributes);
}

bool _hasHtml(String text) => _tag.hasMatch(text);

/// A tag (open, close or empty) or a node.
sealed class _Token {}

class _Open extends _Token {
  _Open(this.tag, this.attributes);
  final String tag;
  final Map<String, String> attributes;
}

class _Close extends _Token {
  _Close(this.tag);
  final String tag;
}

class _Node extends _Token {
  _Node(this.node);
  final md.Node node;
}

List<_Token> _tokens(String html) {
  final tokens = <_Token>[];
  var at = 0;
  void text(String text) {
    if (text.isNotEmpty) tokens.add(_Node(md.Text(text)));
  }

  for (final match in _tag.allMatches(html)) {
    text(html.substring(at, match.start));
    at = match.end;
    final name = match.group(2)?.toLowerCase();
    if (name == null) continue; // A comment.
    if (match.group(1) == '/') {
      tokens.add(_Close(name));
    } else {
      tokens.add(_Open(name, _attributes(match.group(3)!)));
    }
  }
  text(html.substring(at));
  return tokens;
}

List<_Token> _inlineTokens(List<md.Node> nodes) => [
  for (final node in nodes)
    if (node is md.Text && _hasHtml(node.text))
      ..._tokens(node.text)
    else if (node is md.Element)
      _Node(_inElement(node))
    else
      _Node(node),
];

Map<String, String> _attributes(String source) => {
  for (final match in _attribute.allMatches(source))
    match.group(1)!.toLowerCase():
        match.group(2) ?? match.group(3) ?? match.group(4)!,
};

/// [tokens] of an HTML block: a paragraph between block tags.
List<md.Node> _paragraphs(List<_Token> tokens) {
  final paragraphs = <md.Node>[];
  var run = <_Token>[];
  void end() {
    final inlines = _inlines(run, block: true);
    run = [];
    if (inlines.isNotEmpty) paragraphs.add(md.Element('p', inlines));
  }

  for (final token in tokens) {
    final tag = switch (token) {
      _Open(:final tag) || _Close(:final tag) => tag,
      _Node() => null,
    };
    if (tag != null && _blockTags.contains(tag)) {
      end();
    } else {
      run.add(token);
    }
  }
  end();
  return paragraphs;
}

/// [tokens] as inline nodes: images, links and line breaks kept. In an
/// HTML [block], white space collapses as a browser's does.
List<md.Node> _inlines(List<_Token> tokens, {bool block = false}) {
  // Open links, innermost last: (href, their nodes so far).
  final links = <(String?, List<md.Node>)>[];
  final out = <md.Node>[];
  List<md.Node> target() => links.isEmpty ? out : links.last.$2;

  for (final token in tokens) {
    switch (token) {
      case _Open(tag: 'img', :final attributes):
        final src = attributes['src'];
        if (src == null) break;
        target().add(
          md.Element.empty('img')
            ..attributes['src'] = src
            ..attributes['alt'] = attributes['alt'] ?? ''
            ..attributes.addAll({'title': ?attributes['title']}),
        );
      case _Open(tag: 'br'):
        target().add(md.Element.empty('br'));
      case _Open(tag: 'a', :final attributes):
        links.add((attributes['href'], []));
      case _Close(tag: 'a') when links.isNotEmpty:
        var (href, children) = links.removeLast();
        if (block) children = _collapse(children);
        target().add(
          href == null
              ? md.Element('span', children)
              : (md.Element('a', children)..attributes['href'] = href),
        );
      case _Node(:final node):
        target().add(node);
      case _Open() || _Close():
        break;
    }
  }
  // Links never closed.
  while (links.isNotEmpty) {
    final (_, children) = links.removeLast();
    target().addAll(children);
  }
  if (!block) return out;
  return _collapse(out);
}

/// [nodes] with runs of white space as one space, and none at the ends.
List<md.Node> _collapse(List<md.Node> nodes) {
  final out = <md.Node>[];
  for (final node in nodes) {
    if (node is md.Text) {
      final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      final previous = out.lastOrNull;
      final trimmed =
          previous == null ||
              (previous is md.Text && previous.text.endsWith(' ')) ||
              (previous is md.Element && previous.tag == 'br')
          ? text.trimLeft()
          : text;
      if (trimmed.isNotEmpty) out.add(md.Text(trimmed));
    } else {
      out.add(node);
    }
  }
  while (out.isNotEmpty &&
      out.last is md.Text &&
      out.last.textContent.trim().isEmpty) {
    out.removeLast();
  }
  if (out.lastOrNull case md.Text(:final text)) {
    out[out.length - 1] = md.Text(text.trimRight());
  }
  return out;
}
