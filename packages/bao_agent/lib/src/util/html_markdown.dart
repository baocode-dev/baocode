import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// [source] (an HTML page) as Markdown: its title, then its text,
/// headings, links, lists, code and tables; scripts, styles and the page's
/// furniture left out.
String htmlToMarkdown(String source, {Uri? base}) {
  final document = html.parse(source);
  final body = document.body ?? document.documentElement;
  if (body == null) return '';
  final out = _Writer(base);
  out.children(body);
  final text = out.result();
  // A page may say what it is only in its <head>.
  final title = document.querySelector('title')?.text.trim() ?? '';
  if (title.isEmpty || text.startsWith(title) || text.startsWith('# $title')) {
    return text;
  }
  return text.isEmpty ? title : '$title\n\n$text';
}

/// The title of the HTML page [source], if it has one.
String? htmlTitle(String source) {
  final title = html.parse(source).querySelector('title')?.text.trim();
  return title == null || title.isEmpty ? null : title;
}

class _Writer {
  _Writer(this.base);

  final Uri? base;
  final StringBuffer _out = StringBuffer();
  final List<String> _lists = [];
  final List<int> _counters = [];
  int _pre = 0;

  static const _skipped = {
    'script',
    'style',
    'noscript',
    'template',
    'svg',
    'canvas',
    'iframe',
    'head',
    'button',
    'select',
    'form',
    'input',
    'textarea',
    'nav',
    'footer',
  };

  static const _blocks = {
    'p',
    'div',
    'section',
    'article',
    'main',
    'header',
    'aside',
    'figure',
    'figcaption',
    'details',
    'summary',
    'dl',
    'dt',
    'dd',
    'address',
  };

  String result() => _out
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  void _block() {
    final text = _out.toString();
    if (text.isEmpty || text.endsWith('\n\n')) return;
    _out.write(text.endsWith('\n') ? '\n' : '\n\n');
  }

  void _line() {
    final text = _out.toString();
    if (text.isEmpty || text.endsWith('\n')) return;
    _out.write('\n');
  }

  void children(Node node) {
    for (final child in node.nodes) {
      visit(child);
    }
  }

  String _inline(Node node) {
    final inner = _Writer(base).._pre = _pre;
    inner.children(node);
    return inner.result().replaceAll('\n', ' ');
  }

  void visit(Node node) {
    if (node is Text) {
      final text = node.text;
      if (_pre > 0) {
        _out.write(text);
      } else {
        final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
        final current = _out.toString();
        if (collapsed == ' ' &&
            (current.isEmpty ||
                current.endsWith(' ') ||
                current.endsWith('\n'))) {
          return;
        }
        _out.write(collapsed);
      }
      return;
    }
    if (node is! Element) {
      if (node is Document || node is DocumentFragment) children(node);
      return;
    }
    final tag = node.localName ?? '';
    if (_skipped.contains(tag)) return;
    if (node.attributes['hidden'] != null ||
        node.attributes['aria-hidden'] == 'true') {
      return;
    }
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _block();
        _out.write('${'#' * int.parse(tag.substring(1))} ${_inline(node)}');
        _block();
      case 'br':
        _out.write('\n');
      case 'hr':
        _block();
        _out.write('---');
        _block();
      case 'pre':
        _block();
        final code = node.querySelector('code');
        final language = (code?.className ?? '')
            .split(' ')
            .where((c) => c.startsWith('language-'))
            .map((c) => c.substring(9))
            .firstOrNull;
        _out.write('```${language ?? ''}\n${node.text.trimRight()}\n```');
        _block();
      case 'code' when _pre == 0:
        final text = node.text;
        _out.write(text.contains('`') ? '`` $text ``' : '`$text`');
      case 'strong' || 'b':
        final text = _inline(node).trim();
        if (text.isNotEmpty) _out.write('**$text**');
      case 'em' || 'i':
        final text = _inline(node).trim();
        if (text.isNotEmpty) _out.write('*$text*');
      case 'a':
        final text = _inline(node).trim();
        final href = node.attributes['href'];
        if (href == null || href.startsWith('javascript:') || text.isEmpty) {
          _out.write(text);
        } else {
          _out.write('[$text](${_resolve(href)})');
        }
      case 'img':
        final alt = node.attributes['alt'] ?? '';
        final src = node.attributes['src'];
        if (src != null && alt.isNotEmpty) {
          _out.write('![$alt](${_resolve(src)})');
        }
      case 'ul' || 'ol':
        _line();
        if (_lists.isEmpty) _block();
        _lists.add(tag);
        _counters.add(0);
        children(node);
        _lists.removeLast();
        _counters.removeLast();
        _line();
        if (_lists.isEmpty) _block();
      case 'li':
        _line();
        final depth = _lists.isEmpty ? 0 : _lists.length - 1;
        final ordered = _lists.isNotEmpty && _lists.last == 'ol';
        String marker = '-';
        if (ordered) {
          _counters[_counters.length - 1]++;
          marker = '${_counters.last}.';
        }
        _out.write('${'  ' * depth}$marker ');
        children(node);
        _line();
      case 'blockquote':
        _block();
        final inner = _Writer(base)..children(node);
        _out.write(
          inner.result().split('\n').map((line) => '> $line').join('\n'),
        );
        _block();
      case 'table':
        _block();
        _table(node);
        _block();
      default:
        if (_blocks.contains(tag)) {
          _block();
          children(node);
          _block();
        } else {
          children(node);
        }
    }
  }

  void _table(Element table) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return;
    var header = true;
    for (final row in rows) {
      final cells = [
        for (final cell in row.children)
          if (cell.localName == 'td' || cell.localName == 'th')
            _inline(cell).trim().replaceAll('|', r'\|'),
      ];
      if (cells.isEmpty) continue;
      _out.writeln('| ${cells.join(' | ')} |');
      if (header) {
        _out.writeln('| ${cells.map((_) => '---').join(' | ')} |');
        header = false;
      }
    }
  }

  String _resolve(String href) {
    final base = this.base;
    if (base == null) return href;
    try {
      return base.resolve(href).toString();
    } on FormatException {
      return href;
    }
  }
}
