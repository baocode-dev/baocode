import 'package:baocode/ide/markdown/markdown_inline.dart';
import 'package:flutter_test/flutter_test.dart';

/// [text]'s elements, each as its kind and the text it covers, its content
/// in brackets when that is less.
List<String> _parse(String text, {Map<String, String> references = const {}}) {
  String describe(MarkdownInline inline) {
    final whole = text.substring(inline.start, inline.end);
    final content = text.substring(inline.contentStart, inline.contentEnd);
    final children = inline.children.map(describe).join(' ');
    return '${inline.kind.name} $whole'
        '${content == whole ? '' : ' [$content]'}'
        '${inline.target != null ? ' -> ${inline.target}' : ''}'
        '${children.isEmpty ? '' : ' {$children}'}';
  }

  return [
    for (final inline in parseMarkdownInlines(text, references: references))
      describe(inline),
  ];
}

void main() {
  test('emphasis, strong and strikethrough', () {
    expect(_parse('a **b** c'), ['strong **b** [b]']);
    expect(_parse('*a* and _b_'), ['emphasis *a* [a]', 'emphasis _b_ [b]']);
    expect(_parse('***both***'), [
      'emphasis ***both*** [**both**] {strong **both** [both]}',
    ]);
    expect(_parse('**a *b* c**'), [
      'strong **a *b* c** [a *b* c] {emphasis *b* [b]}',
    ]);
    expect(_parse('~~gone~~'), ['strike ~~gone~~ [gone]']);
    // Not flanking, inside a word with `_`, or unclosed: text.
    expect(_parse('a * b *'), isEmpty);
    expect(_parse('snake_case_name'), isEmpty);
    expect(_parse('**open'), isEmpty);
    expect(_parse('2*3*4'), ['emphasis *3* [3]']);
    // The rule of three.
    expect(_parse('*a**b*'), ['emphasis *a**b* [a**b]']);
  });

  test('code spans come first; their insides are code', () {
    expect(_parse('`a*b*`'), ['code `a*b*` [a*b*]']);
    expect(_parse('``a ` b``'), ['code ``a ` b`` [a ` b]']);
    expect(_parse('*a `*` b*'), [
      'emphasis *a `*` b* [a `*` b] {code `*` [*]}',
    ]);
    expect(_parse('```unclosed'), isEmpty);
  });

  test('links and images, inline and by reference', () {
    expect(_parse('[a](b.md)'), ['link [a](b.md) [a] -> b.md']);
    expect(_parse('[a **b**](<c d.md> "T")'), [
      'link [a **b**](<c d.md> "T") [a **b**] -> c d.md {strong **b** [b]}',
    ]);
    expect(_parse('![alt](img/x.png)'), [
      'image ![alt](img/x.png) [alt] -> img/x.png',
    ]);
    expect(_parse('[![i](x.png)](y)'), [
      'link [![i](x.png)](y) [![i](x.png)] -> y {image ![i](x.png) [i] -> x.png}',
    ]);
    expect(_parse('[a](b(c))'), ['link [a](b(c)) [a] -> b(c)']);
    expect(_parse('[a] (b)'), isEmpty);
    expect(_parse('[no link]'), isEmpty);
    final references = {'docs': 'https://dart.dev'};
    expect(
      _parse('[Docs] and [x][docs] and [docs][]', references: references),
      [
        'link [Docs] [Docs] -> https://dart.dev',
        'link [x][docs] [x] -> https://dart.dev',
        'link [docs][] [docs] -> https://dart.dev',
      ],
    );
    // No links in links.
    expect(_parse('[a [b](c) d](e)'), ['link [b](c) [b] -> c']);
  });

  test('autolinks, bare URLs, HTML, TeX and escapes', () {
    expect(_parse('<https://a.b> <me@x.org>'), [
      'autolink <https://a.b> [https://a.b] -> https://a.b',
      'autolink <me@x.org> [me@x.org] -> mailto:me@x.org',
    ]);
    expect(_parse('see https://a.b/c. and (www.d.e)'), [
      'url https://a.b/c -> https://a.b/c',
      'url www.d.e -> http://www.d.e',
    ]);
    expect(_parse('a<br>b <span class="x">c</span>'), [
      'html <br>',
      'html <span class="x">',
      'html </span>',
    ]);
    expect(_parse(r'$x^2$ costs $5 and $10, \(y\)'), [
      r'math $x^2$ [x^2]',
      r'math \(y\) [y]',
    ]);
    expect(_parse(r'\*not\* \a'), [r'escape \* [*]', r'escape \* [*]']);
  });
}
