import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/ide/markdown/markdown_blocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

typedef _Case = (String name, String text, List<(MarkdownBlockKind, int, int)>);

const _p = MarkdownBlockKind.paragraph;
const _h = MarkdownBlockKind.heading;
const _l = MarkdownBlockKind.list;
const _t = MarkdownBlockKind.table;
const _f = MarkdownBlockKind.fence;
const _i = MarkdownBlockKind.indentedCode;
const _q = MarkdownBlockKind.quote;
const _r = MarkdownBlockKind.rule;
const _m = MarkdownBlockKind.math;
const _x = MarkdownBlockKind.html;
const _y = MarkdownBlockKind.frontMatter;

/// Each text's blocks, the empty lines between them aside.
final List<_Case> _cases = [
  ('empty', '', []),
  ('a paragraph', 'one\ntwo', [(_p, 0, 2)]),
  ('paragraphs', 'one\n\n\ntwo\n', [(_p, 0, 1), (_p, 3, 4)]),
  ('atx headings', '# A\ntext\n## B', [(_h, 0, 1), (_p, 1, 2), (_h, 2, 3)]),
  (
    'setext headings',
    'Title\n=====\nSub\nlines\n---\n',
    [(_h, 0, 2), (_h, 2, 5)],
  ),
  (
    'a fence with empty lines and markup in it',
    'a\n```dart\nx\n\n# not a heading\n```\nb',
    [(_p, 0, 1), (_f, 1, 6), (_p, 6, 7)],
  ),
  (
    'a tilde fence closed by a longer one',
    '~~~\n```\n~~~~\nafter',
    [(_f, 0, 3), (_p, 3, 4)],
  ),
  ('an unclosed fence runs to the end', '```\ncode\n\nmore', [(_f, 0, 4)]),
  ('a shorter fence does not close', '````\n```\n````', [(_f, 0, 3)]),
  (
    'indented code with empty lines',
    '    a\n\n    b\n\npara',
    [(_i, 0, 3), (_p, 4, 5)],
  ),
  ('indented lines continue a paragraph', 'para\n    more', [(_p, 0, 2)]),
  (
    'a list, loose, with nested items',
    '- a\n\n- b\n  - c\n\n    deep\n\nafter',
    [(_l, 0, 6), (_p, 7, 8)],
  ),
  ('a lazy continuation', '- item\nlazy line\n- next', [(_l, 0, 3)]),
  ('a heading ends a list', '- a\n# H', [(_l, 0, 1), (_h, 1, 2)]),
  ('another bullet starts another list', '- a\n* b', [(_l, 0, 1), (_l, 1, 2)]),
  ('ordered lists', '1. a\n2. b\n\n3) c', [(_l, 0, 2), (_l, 3, 4)]),
  ('a task list', '- [ ] todo\n- [x] done', [(_l, 0, 2)]),
  ('a fence in an item', '- a\n  ```\n  x\n\n  ```\n- b', [(_l, 0, 6)]),
  (
    'a rule is not a list item',
    '- a\n* * *\n- b',
    [(_l, 0, 1), (_r, 1, 2), (_l, 2, 3)],
  ),
  (
    'only 1 starts a list in a paragraph',
    'text\n2. no\n1. yes',
    [(_p, 0, 2), (_l, 2, 3)],
  ),
  (
    'an empty item does not interrupt a paragraph',
    'text\n-\nmore',
    [(_h, 0, 2), (_p, 2, 3)],
  ),
  (
    'a table to an empty line',
    '| a | b |\n|---|:-:|\n| 1 | 2 |\n3 | 4\n\nx',
    [(_t, 0, 4), (_p, 5, 6)],
  ),
  (
    'a table interrupts a paragraph',
    'para\na | b\n--|--\n1 | 2',
    [(_p, 0, 1), (_t, 1, 4)],
  ),
  ('a table ends at a heading', 'a | b\n-|-\n# H', [(_t, 0, 2), (_h, 2, 3)]),
  (
    'a header whose cells do not match is no table',
    'a | b | c\n-|-',
    [(_p, 0, 2)],
  ),
  (
    'a quote with a lazy line',
    '> one\nlazy\n> two\n\nafter',
    [(_q, 0, 3), (_p, 4, 5)],
  ),
  ('a heading ends a quote', '> q\n# H', [(_q, 0, 1), (_h, 1, 2)]),
  ('rules', '***\n___\n- - -', [(_r, 0, 1), (_r, 1, 2), (_r, 2, 3)]),
  (
    'math blocks',
    r'$$'
        '\nx^2\n'
        r'$$'
        '\n'
        r'\[ y \]'
        '\ntext',
    [(_m, 0, 3), (_m, 3, 4), (_p, 4, 5)],
  ),
  (
    'math interrupts a paragraph',
    'text\n'
        r'$$ a $$',
    [(_p, 0, 1), (_m, 1, 2)],
  ),
  (
    'an unclosed math block runs to the end',
    r'$$'
        '\na\n\nb',
    [(_m, 0, 4)],
  ),
  (
    'an html block to an empty line',
    '<div>\n*x*\n</div>\n\ntext',
    [(_x, 0, 3), (_p, 4, 5)],
  ),
  (
    'a comment to its end',
    '<!--\n\nstill\n-->\nafter',
    [(_x, 0, 4), (_p, 4, 5)],
  ),
  (
    'a pre to its closing tag',
    '<pre>\n\n</pre>\ntext',
    [(_x, 0, 3), (_p, 3, 4)],
  ),
  (
    'a lone tag does not interrupt a paragraph',
    'text\n<span>\nmore',
    [(_p, 0, 3)],
  ),
  ('front matter', '---\ntitle: x\n---\n# H', [(_y, 0, 3), (_h, 3, 4)]),
  ('a rule first is no front matter', '---\n# H', [(_r, 0, 1), (_h, 1, 2)]),
  (
    'link definitions',
    '[a]: http://a\n[b]: http://b\n\ntext [a]',
    [(_p, 0, 2), (_p, 3, 4)],
  ),
  ('a footnote definition', 'text[^1]\n\n[^1]: note', [(_p, 0, 1), (_p, 2, 3)]),
  ('CRLF line breaks', '# A\r\n\r\n- a\r\n- b\r\n', [(_h, 0, 1), (_l, 2, 4)]),
  ('lone CRs', 'a\rb\r\rc', [(_p, 0, 2), (_p, 3, 4)]),
  ('no line break at the end', '# A\ntext', [(_h, 0, 1), (_p, 1, 2)]),
];

void main() {
  group('blocks', () {
    for (final (name, text, expected) in _cases) {
      test(name, () {
        final blocks = splitMarkdownBlocks(MarkdownLines(text));
        expect([
          for (final block in blocks)
            if (block.kind != MarkdownBlockKind.blank)
              (block.kind, block.start, block.end),
        ], expected);
      });
    }
  });

  test('the blocks put together are the text, byte for byte', () {
    final texts = [
      for (final (_, text, _) in _cases) text,
      for (final (_, text, _) in _cases) '\n\n$text\n\n',
      _cases.map((c) => c.$2).join('\n\n'),
      _cases.map((c) => c.$2).join('\r\n'),
    ];
    for (final text in texts) {
      final lines = MarkdownLines(text);
      final blocks = splitMarkdownBlocks(lines);
      var line = 0;
      final buffer = StringBuffer();
      for (final block in blocks) {
        expect(block.start, line, reason: 'contiguous in ${_show(text)}');
        expect(block.end, greaterThan(block.start));
        line = block.end;
        buffer.write(
          text.substring(
            lines.starts[block.start],
            block.end < lines.length ? lines.starts[block.end] : text.length,
          ),
        );
      }
      if (text.isNotEmpty) expect(line, lines.length);
      expect(buffer.toString(), text);
    }
  });

  test('each block parses to what it was in the whole document', () {
    // Those running to the end, or only first, aside.
    const aside = {
      'an unclosed fence runs to the end',
      'an unclosed math block runs to the end',
      'front matter',
      'a rule first is no front matter',
      // Footnotes are numbered over the whole document.
      'a footnote definition',
    };
    final document = [
      for (final (name, text, _) in _cases)
        if (!aside.contains(name)) text,
    ].join('\n\n');
    String html(String text) => md.renderToHtml(
      _document().parseLines(text.split(RegExp('\r\n|\r|\n'))),
    );
    final lines = MarkdownLines(document);
    final blocks = [
      for (final block in splitMarkdownBlocks(lines))
        if (block.kind != MarkdownBlockKind.blank)
          lines.source(block.start, block.end),
    ];
    // One document for the blocks, which has read the link definitions
    // first, as the preview reads them.
    final shared = _document();
    for (final block in blocks) {
      shared.parseLines(block.split(RegExp('\r\n|\r|\n')));
    }
    final pieces = [
      for (final block in blocks)
        md.renderToHtml(shared.parseLines(block.split(RegExp('\r\n|\r|\n')))),
    ];
    expect(
      pieces.join().replaceAll('\n', ''),
      html(document).replaceAll('\n', ''),
    );
  });

  test('lines and offsets', () {
    final lines = MarkdownLines('a\r\nbc\n\nd');
    expect(lines.length, 4);
    expect([for (var i = 0; i < 4; i++) lines[i]], ['a', 'bc', '', 'd']);
    expect(lines.lineBreak, '\r\n');
    expect(lines.source(0, 2), 'a\r\nbc');
    expect(lines.lineAt(0), 0);
    expect(lines.lineAt(3), 1);
    expect(lines.lineAt(8), 3);
    expect(MarkdownLines('x\n').length, 2);
    expect(MarkdownLines('').length, 1);
  });
}

md.Document _document() => md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  blockSyntaxes: MarkdownView.blockSyntaxes,
  inlineSyntaxes: MarkdownView.inlineSyntaxes,
  encodeHtml: false,
);

String _show(String text) =>
    text.replaceAll('\n', r'\n').replaceAll('\r', r'\r');
