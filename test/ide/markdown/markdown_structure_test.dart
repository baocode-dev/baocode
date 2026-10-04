import 'package:baocode/ide/markdown/markdown_structure.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// [text]'s rows, each as its kind, its marks (a list item's, its quotes')
/// and its units' texts.
List<String> _rows(String text, {int? caretLine}) => [
  for (final row in MarkdownStructure(text, caretLine: caretLine).rows)
    [
      row.kind.name,
      if (row.level > 0) 'h${row.level}',
      if (row.item case final item?)
        '${'  ' * (row.depth - 1)}${item.number != null ? '${item.number}${item.bullet}' : item.bullet}'
            '${item.task != null ? (item.checked ? ' [x]' : ' [ ]') : ''}',
      if (row.quotes.isNotEmpty) '>' * row.quotes.length,
      row.units.map((unit) => '"${unit.text}"').join(' '),
    ].join(' '),
];

/// [text] with the edit replacing [start, end) of [unit] of [row] with
/// [inserted].
String _edit(
  String text,
  int row,
  int unit,
  int start,
  int end,
  String inserted,
) {
  final structure = MarkdownStructure(text);
  final edit = structure.rows[row].units[unit].edit(start, end, inserted).edit;
  final model = EditorDocumentModel(text)..applyOffsetEdits([edit]);
  return model.text;
}

void main() {
  test('paragraphs and headings: their text, without their marks', () {
    expect(_rows('# Title #\n\nOne\ntwo.\n\nSub\n---\n'), [
      'heading h1 "Title"',
      'paragraph "One\ntwo."',
      'heading h2 "Sub"',
    ]);
    expect(_rows('#\n\n## '), ['heading h1 ""', 'heading h2 ""']);
  });

  test('lists: an item\'s content its rows, nested lists theirs', () {
    expect(_rows('- a\n  more\n- [ ] b\n  1. c\n  2. d\n\n    para\n- [x] e'), [
      'paragraph - "a\nmore"',
      'paragraph - [ ] "b"',
      'paragraph   1. "c"',
      'paragraph   2. "d"',
      'paragraph "para"',
      'paragraph - [x] "e"',
    ]);
    // Numbered as rendered: from the first item's number.
    expect(_rows('3. a\n3. b'), ['paragraph 3. "a"', 'paragraph 4. "b"']);
    // Empty items have a row to type in.
    expect(_rows('- a\n-\n- [ ]'), [
      'paragraph - "a"',
      'paragraph - ""',
      'paragraph - [ ] ""',
    ]);
    expect(_rows('- ```js\n  code\n  ```'), ['code - "code"']);
  });

  test('quotes hold blocks', () {
    expect(_rows('> # T\n> a\nlazy\n>\n> - b\n> > c'), [
      'heading h1 > "T"',
      'paragraph > "a\nlazy"',
      'paragraph - > "b"',
      'paragraph >> "c"',
    ]);
  });

  test('code, math, HTML, rules, front matter, definitions', () {
    expect(
      _rows(
        '---\na: 1\n---\n\n```dart\nx\ny\n```\n\n    indented\n\n'
        r'$$'
        '\nx^2\n'
        r'$$'
        '\n\n'
        r'$$ y $$'
        '\n\n<div>\nhi\n</div>\n\n***\n\n[a]: https://a.b',
      ),
      [
        'frontMatter "a: 1"',
        'code "x\ny"',
        'code "indented"',
        'math "x^2"',
        'math " y "',
        'html "<div>\nhi\n</div>"',
        'rule "***"',
        'definition "[a]: https://a.b"',
      ],
    );
    final structure = MarkdownStructure('``` js\nx\n```\n\n[A]: <b c>');
    final info = structure.rows.first.info!;
    expect(structure.text.substring(info.$1, info.$2), 'js');
    expect(structure.references, {'a': 'b c'});
    expect(_rows('```\n```'), ['code ""']);
  });

  test('tables: a unit a cell, missing ones too', () {
    expect(_rows('| a | b |\n|:-|--:|\n| 1 |\n|  | x \\| y |'), [
      'table "a" "b" "1" "" "" "x \\| y"',
    ]);
    final table = MarkdownStructure('a | b\n:-:|-\n1 | 2').rows.single.table!;
    expect(table.align, ['center', null]);
    expect(table.cells, hasLength(2));
  });

  test('empty lines: those more than the blocks need, and the caret\'s', () {
    expect(_rows(''), ['paragraph ""']);
    expect(_rows('a\n\n\n\nb'), [
      'paragraph "a"',
      'paragraph ""',
      'paragraph "b"',
    ]);
    expect(_rows('a\n\nb'), ['paragraph "a"', 'paragraph "b"']);
    expect(_rows('a\n\nb', caretLine: 1), [
      'paragraph "a"',
      'paragraph ""',
      'paragraph "b"',
    ]);
    expect(_rows('a\n'), ['paragraph "a"']);
    expect(_rows('a\n\n\n'), ['paragraph "a"', 'paragraph ""']);
    expect(_rows('\n\na'), ['paragraph ""', 'paragraph "a"']);
    expect(_rows('a\n\n\n\n\n\nb'), [
      'paragraph "a"',
      'paragraph ""',
      'paragraph ""',
      'paragraph "b"',
    ]);
  });

  test('an edit of a unit changes its lines\' content', () {
    // A line break typed in a quote continues it; in an item, indented.
    expect(_edit('> ab', 0, 0, 1, 1, '\n'), '> a\n> b');
    expect(_edit('- ab\r\n- c', 0, 0, 1, 1, '\nx'), '- a\r\n  xb\r\n- c');
    // Across lines: the marks between go with the line break.
    expect(_edit('> a\n> b', 0, 0, 1, 2, ''), '> ab');
    // Empty: what goes around it there too.
    expect(_edit('```\n```', 0, 0, 0, 0, 'x'), '```\nx\n```');
    expect(_edit('```', 0, 0, 0, 0, 'x'), '```\nx');
    expect(_edit('-', 0, 0, 0, 0, 'x'), '- x');
    expect(_edit('#', 0, 0, 0, 0, 'x'), '# x');
    expect(
      _edit('|a|b|\n|-|-|\n||  |', 0, 2, 0, 0, 'x|y'),
      '|a|b|\n|-|-|\n| x\\|y |  |',
    );
    expect(
      _edit('|a|b|\n|-|-|\n|1', 0, 3, 0, 0, 'x'),
      '|a|b|\n|-|-|\n|1 | x |',
    );
  });

  test('a caret on marks is put in the unit after them', () {
    final structure = MarkdownStructure('# Head\n\n> - item');
    expect(structure.caretAt(0), (row: 0, unit: 0, offset: 0));
    expect(structure.caretAt(4), (row: 0, unit: 0, offset: 2));
    expect(structure.caretAt(8), (row: 1, unit: 0, offset: 0));
    expect(structure.caretAt(7), (row: 0, unit: 0, offset: 4));
    expect(structure.caretAt(16), (row: 1, unit: 0, offset: 4));
    expect(structure.anchors, {0: 'head'});
  });
}
