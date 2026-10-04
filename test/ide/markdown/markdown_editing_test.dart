import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/markdown/markdown_editing.dart';
import 'package:baocode/ide/markdown/markdown_structure.dart';
import 'package:flutter_test/flutter_test.dart';

const _caret = '‸';

/// [marked] (its caret `‸`, a selection between `«` and `»`) after [run],
/// marked the same way; null when [run] does nothing.
String? _after(
  String marked,
  MarkdownChange? Function(
    MarkdownStructure structure,
    MarkdownCaret caret,
    int start,
    int end,
  )
  run,
) {
  int at;
  int? base;
  var text = marked;
  if (text.contains('«')) {
    base = text.indexOf('«');
    text = text.replaceFirst('«', '');
    at = text.indexOf('»');
    text = text.replaceFirst('»', '');
  } else {
    at = text.indexOf(_caret);
    text = text.replaceFirst(_caret, '');
  }
  final structure = MarkdownStructure(
    text,
    caretLine: MarkdownStructure(text).lines.lineAt(at),
  );
  final caret = structure.caretAt(at);
  final unit = structure.rows[caret.row].units[caret.unit];
  final start = base == null ? caret.offset : unit.toText(base)!;
  final change = run(structure, caret, start, caret.offset);
  if (change == null) return null;
  final model = EditorDocumentModel(text)..applyOffsetEdits(change.edits);
  final result = model.text;
  if (change.base != change.caret) {
    return '${result.substring(0, change.base)}«'
        '${result.substring(change.base, change.caret)}»'
        '${result.substring(change.caret)}';
  }
  return '${result.substring(0, change.caret)}$_caret${result.substring(change.caret)}';
}

String? _enter(String marked, {bool soft = false}) =>
    _after(marked, (s, c, _, _) => markdownEnter(s, c, soft: soft));
String? _backspace(String marked) =>
    _after(marked, (s, c, _, _) => markdownBackspace(s, c));
String? _delete(String marked) =>
    _after(marked, (s, c, _, _) => markdownDelete(s, c));

void main() {
  group('Enter', () {
    test('splits a paragraph, a heading; Shift+Enter breaks a line', () {
      expect(_enter('one‸two'), 'one\n\n‸two');
      expect(_enter('a\n\nend‸'), 'a\n\nend\n\n‸');
      expect(_enter('one‸two', soft: true), 'one\n‸two');
      expect(_enter('# Ti‸tle\n'), '# Ti\n\n‸tle\n');
      expect(_enter('# Title‸\n\nnext'), '# Title\n\n‸\n\nnext');
      expect(_enter('x\n\n‸# Title'), 'x\n\n‸\n\n# Title');
    });

    test('in a quote, stays in it; on its empty paragraph, leaves it', () {
      expect(_enter('> a‸b'), '> a\n>\n> ‸b');
      expect(_enter('> a\n>\n> ‸'), '> a\n\n‸');
    });

    test('continues a list; an empty item leaves it or goes out a level', () {
      expect(_enter('- a‸b'), '- a\n- ‸b');
      expect(_enter('1. a‸\n2. c'), '1. a\n2. ‸\n2. c');
      expect(_enter('- [x] done‸'), '- [x] done\n- [ ] ‸');
      expect(_enter('> * a‸'), '> * a\n> * ‸');
      expect(_enter('- a\n- ‸\n- c'), '- a\n\n‸\n\n- c');
      expect(_enter('- a\n- ‸'), '- a\n\n‸');
      expect(_enter('- a\n  - b\n  - ‸'), '- a\n  - b\n- ‸');
    });

    test('in code, a line break, its indent kept; a fence alone opens one', () {
      expect(_enter('```\n  x‸\n```'), '```\n  x\n  ‸\n```');
      expect(_enter('```js‸'), '```js\n‸\n```');
      expect(_enter(r'$$‸'), '\$\$\n‸\n\$\$');
    });

    test('in a table, the cell below, a new row after the last', () {
      expect(
        _enter('| a | b |\n|---|---|\n| 1‸ | 2 |'),
        '| a   | b   |\n| --- | --- |\n| 1   | 2   |\n| ‸    |     |',
      );
      expect(
        _enter('| a‸ | b |\n|---|---|\n| 1 | 2 |'),
        '| a | b |\n|---|---|\n| 1‸ | 2 |',
      );
    });
  });

  group('Backspace at a row\'s start', () {
    test('takes its marks off', () {
      expect(_backspace('- ‸a'), '‸a');
      expect(_backspace('- [ ] ‸a'), '- ‸a');
      expect(_backspace('## ‸Title'), '‸Title');
      expect(
        _backspace('Title\n===\n'.replaceFirst('Title', '‸Title')),
        '‸Title\n',
      );
      expect(_backspace('> ‸a'), '‸a');
      expect(_backspace('> > ‸a'), '> ‸a');
    });

    test('joins it to the row before; leaves code alone', () {
      expect(_backspace('one\n\n‸two'), 'one‸two');
      expect(_backspace('- a\n\n‸b'), '- a‸b');
      expect(_backspace('one\n\n‸\n\ntwo'), 'one‸\n\ntwo');
      expect(_backspace('```\nx\n```\n\n‸b'), '```\nx‸\n```\n\nb');
      expect(_backspace('```\n‸\n```'), '‸');
      expect(_backspace('‸first'), isNull);
    });

    test('Delete at the end joins the next row', () {
      expect(_delete('one‸\n\ntwo'), 'one‸two');
      expect(_delete('one‸\n\n- two'), 'one‸two');
      expect(_delete('one‸\n\n```\nx\n```'), isNull);
    });
  });

  test('Tab nests a list item in the one before; Shift+Tab takes it out', () {
    String? indent(String marked, {bool outdent = false}) => _after(
      marked,
      (s, c, _, _) => markdownIndentItem(s, c, outdent: outdent),
    );
    expect(indent('- a\n- b‸\n  more'), '- a\n  - b‸\n    more');
    expect(indent('1. a\n2. b‸'), '1. a\n   2. b‸');
    expect(indent('- a‸'), isNull);
    expect(indent('- a\n  - b‸', outdent: true), '- a\n- b‸');
    expect(indent('> - a\n> - ‸b'), '> - a\n>   - ‸b');
  });

  test('lists, quotes and headings toggled', () {
    expect(
      _after('a‸b\nc', (s, c, _, _) => markdownToggleList(s, c)),
      '- a‸b\n  c',
    );
    expect(_after('- a‸', (s, c, _, _) => markdownToggleList(s, c)), 'a‸');
    expect(
      _after('- a‸', (s, c, _, _) => markdownToggleList(s, c, ordered: true)),
      '1. a‸',
    );
    expect(
      _after('- a‸', (s, c, _, _) => markdownToggleList(s, c, task: true)),
      '- [ ] a‸',
    );
    expect(
      _after('a‸\nb', (s, c, _, _) => markdownToggleQuote(s, c)),
      '> a‸\n> b',
    );
    expect(_after('> a‸', (s, c, _, _) => markdownToggleQuote(s, c)), 'a‸');
    expect(
      _after('one\ntw‸o', (s, c, _, _) => markdownSetHeading(s, c, 2)),
      '## one tw‸o',
    );
    expect(
      _after('# a‸', (s, c, _, _) => markdownSetHeading(s, c, 3)),
      '### a‸',
    );
    expect(_after('# a‸', (s, c, _, _) => markdownSetHeading(s, c, 0)), 'a‸');
    expect(
      _after('a‸\n---', (s, c, _, _) => markdownSetHeading(s, c, 1)),
      '# a‸',
    );
  });

  test('inline marks wrap the selection, or come off', () {
    String? bold(String marked, [String mark = '**']) => _after(
      marked,
      (s, c, start, end) => markdownToggleInline(
        s,
        c,
        start < end ? start : end,
        start < end ? end : start,
        mark,
      ),
    );
    expect(bold('a «bc » d'), 'a **«bc»**  d');
    expect(bold('a **«bc»** d'), 'a «bc» d');
    expect(bold('a **b‸c** d'), 'a b‸c d');
    expect(bold('a ‸ d'), 'a **‸** d');
    expect(bold('«x»', '`'), '`«x»`');
    expect(bold('> - «x»', '~~'), '> - ~~«x»~~');
  });

  test('blocks inserted in an empty paragraph, or after the row', () {
    String? insert(String marked, MarkdownBlockInsert kind) =>
        _after(marked, (s, c, _, _) => markdownInsertBlock(s, c, kind));
    expect(insert('a‸', MarkdownBlockInsert.code), 'a\n\n```\n‸```');
    expect(
      insert('a\n\n‸\n\nb', MarkdownBlockInsert.math),
      'a\n\n\$\$\n‸\$\$\n\nb',
    );
    expect(
      insert('‸', MarkdownBlockInsert.table),
      '|‸  |  |\n| --- | --- |\n|  |  |',
    );
    expect(insert('> a‸', MarkdownBlockInsert.rule), '> a\n>\n> ---\n> ‸');
  });

  test('tables: rows and columns added, taken out, aligned', () {
    const table = '| a | b |\n|---|--:|\n| 1‸ | 2 |';
    String? edit(MarkdownTableEdit edit) =>
        _after(table, (s, c, _, _) => markdownEditTable(s, c, edit));
    expect(
      edit(MarkdownTableEdit.columnRight),
      '| a   |     | b   |\n| --- | --- | --: |\n| 1   | ‸    | 2   |',
    );
    expect(
      edit(MarkdownTableEdit.rowAbove),
      '| a   | b   |\n| --- | --: |\n| ‸    |     |\n| 1   | 2   |',
    );
    expect(edit(MarkdownTableEdit.deleteColumn), '| b   |\n| --: |\n| 2‸   |');
    expect(
      edit(MarkdownTableEdit.alignCenter),
      '| a   | b   |\n| :-: | --: |\n| 1‸   | 2   |',
    );
    expect(edit(MarkdownTableEdit.deleteTable), '‸');
    // Wide characters take two columns.
    expect(
      _after(
        '| 中文 |\n|-|\n| x‸ |',
        (s, c, _, _) => markdownEditTable(s, c, MarkdownTableEdit.alignLeft),
      ),
      '| 中文 |\n| :--- |\n| x‸    |',
    );
  });
}
