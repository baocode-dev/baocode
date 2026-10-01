// Ported from VS Code src/vs/editor/contrib/suggest/test/browser/
// completionModel.test.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// Score comparisons of JS arrays (string coercion) are left out; the order
// assertions stay. Each item gets its own provider, as upstream's helper.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/common/core/position.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/contrib/suggest/browser/completion_model.dart';

// languages.CompletionItemKind
const _property = 9;
const _operator = 11;
const _snippet = 27;

CompletionItem<String> createSuggestItem(
  String label,
  int overwriteBefore, {
  int kind = _property,
  bool incomplete = false,
  Position position = const Position(1, 1),
  String? sortText,
  String? filterText,
}) => CompletionItem(
  position: position,
  completion: label,
  label: label,
  editStart: Position(position.lineNumber, position.column - overwriteBefore),
  editInsertEnd: position,
  editReplaceEnd: position,
  sortText: sortText,
  filterText: filterText,
  isSnippetKind: kind == _snippet,
  kindIndex: kind,
  provider: Object(),
  incomplete: incomplete,
);

void main() {
  late CompletionModel<String> model;

  setUp(() {
    model = CompletionModel(
      [
        createSuggestItem('foo', 3),
        createSuggestItem('Foo', 3),
        createSuggestItem('foo', 2),
      ],
      1,
      const LineContext('foo', 0),
    );
  });

  test('filtering - cached', () {
    final itemsNow = model.items;
    var itemsThen = model.items;
    expect(identical(itemsNow, itemsThen), isTrue);

    // still the same context
    model.lineContext = const LineContext('foo', 0);
    itemsThen = model.items;
    expect(identical(itemsNow, itemsThen), isTrue);

    // different context, refilter
    model.lineContext = const LineContext('foo1', 1);
    itemsThen = model.items;
    expect(identical(itemsNow, itemsThen), isFalse);
  });

  test('complete/incomplete', () {
    expect(model.getIncompleteProvider().length, 0);

    final incompleteModel = CompletionModel(
      [
        createSuggestItem('foo', 3, incomplete: true),
        createSuggestItem('foo', 2),
      ],
      1,
      const LineContext('foo', 0),
    );
    expect(incompleteModel.getIncompleteProvider().length, 1);
  });

  test('Fuzzy matching of snippets stopped working with inline snippet '
      'suggestions #49895', () {
    const at = Position(1, 2);
    final model = CompletionModel(
      [
        for (var i = 1; i <= 5; i++)
          createSuggestItem('foobar$i', 1, position: at),
        createSuggestItem('foofoo1', 1, incomplete: true, position: at),
      ],
      2,
      const LineContext('f', 0),
    );
    expect(model.getIncompleteProvider().length, 1);
    expect(model.items.length, 6);
  });

  test('proper current word when length=0, #16380', () {
    model = CompletionModel(
      [
        createSuggestItem('    </div', 4),
        createSuggestItem('a', 0),
        createSuggestItem('p', 0),
        createSuggestItem('    </tag', 4),
        createSuggestItem('    XYZ', 4),
      ],
      1,
      const LineContext('   <', 0),
    );

    expect(model.items.length, 4);
    expect(
      [for (final item in model.items) item.completion],
      ['    </div', '    </tag', 'a', 'p'],
    );
  });

  test('keep snippet sorting with prefix: top, #25495', () {
    model = CompletionModel(
      [
        createSuggestItem('Snippet1', 1, kind: _snippet),
        createSuggestItem('tnippet2', 1, kind: _snippet),
        createSuggestItem('semver', 1),
      ],
      1,
      const LineContext('s', 0),
      snippetSuggestions: SnippetSortOrder.top,
    );

    expect(
      [for (final item in model.items) item.completion],
      ['Snippet1', 'semver'],
    );
  });

  test('keep snippet sorting with prefix: bottom, #25495', () {
    model = CompletionModel(
      [
        createSuggestItem('snippet1', 1, kind: _snippet),
        createSuggestItem('tnippet2', 1, kind: _snippet),
        createSuggestItem('Semver', 1),
      ],
      1,
      const LineContext('s', 0),
      snippetSuggestions: SnippetSortOrder.bottom,
    );

    expect(
      [for (final item in model.items) item.completion],
      ['Semver', 'snippet1'],
    );
  });

  test('keep snippet sorting with prefix: inline, #25495', () {
    model = CompletionModel(
      [
        createSuggestItem('snippet1', 1, kind: _snippet),
        createSuggestItem('tnippet2', 1, kind: _snippet),
        createSuggestItem('Semver', 1),
      ],
      1,
      const LineContext('s', 0),
    );

    final [a, b] = model.items;
    expect(a.completion, 'snippet1');
    expect(b.completion, 'Semver');
    expect(a.score[0], greaterThan(b.score[0]));
  });

  test('filterText seems ignored in autocompletion, #26874', () {
    final item1 = createSuggestItem('Map - java.util', 1, filterText: 'Map');
    final item2 = createSuggestItem('Map - java.util', 1);

    model = CompletionModel([item1, item2], 1, const LineContext('M', 0));
    expect(model.items.length, 2);

    model.lineContext = const LineContext('Map ', 3);
    expect(model.items.length, 1);
  });

  test("Vscode 1.12 no longer obeys 'sortText' in completion items (from "
      'language server), #26096', () {
    final item1 = createSuggestItem(
      '<- groups',
      2,
      position: const Position(1, 3),
      sortText: '00002',
      filterText: '  groups',
    );
    final item2 = createSuggestItem(
      'source',
      0,
      position: const Position(1, 3),
      sortText: '00001',
      filterText: 'source',
    );
    final items = [item1, item2]
      ..sort(getSuggestionComparator(SnippetSortOrder.inline));

    model = CompletionModel(items, 3, const LineContext('  ', 0));

    expect(
      [for (final item in model.items) item.completion],
      ['source', '<- groups'],
    );
  });

  test('Completion item sorting broken when using label details #153026', () {
    final itemZZZ = createSuggestItem('ZZZ', 0, kind: _operator);
    final itemAAA = createSuggestItem('AAA', 0, kind: _operator);
    final itemIII = createSuggestItem('III', 0, kind: _operator);

    final actual = [itemZZZ, itemAAA, itemIII]
      ..sort(getSuggestionComparator(SnippetSortOrder.inline));
    expect(actual, [itemAAA, itemIII, itemZZZ]);
  });

  test(
    'Score only filtered items when typing more, score all when typing less',
    () {
      model = CompletionModel(
        [
          createSuggestItem('console', 0),
          createSuggestItem('co_new', 0),
          createSuggestItem('bar', 0),
          createSuggestItem('car', 0),
          createSuggestItem('foo', 0),
        ],
        1,
        const LineContext('', 0),
      );
      expect(model.items.length, 5);

      // narrow down once
      model.lineContext = const LineContext('c', 1);
      expect(model.items.length, 3);

      // query gets longer, narrow down the narrow-down'ed-set from before
      model.lineContext = const LineContext('cn', 2);
      expect(model.items.length, 2);

      // query gets shorter, refilter everything
      model.lineContext = const LineContext('', 0);
      expect(model.items.length, 5);
    },
  );

  test('Have more relaxed suggest matching algorithm #15419', () {
    model = CompletionModel(
      [
        createSuggestItem('result', 0),
        createSuggestItem('replyToUser', 0),
        createSuggestItem('randomLolut', 0),
        createSuggestItem('car', 0),
        createSuggestItem('foo', 0),
      ],
      1,
      const LineContext('', 0),
    );

    model.lineContext = const LineContext('rlut', 4);
    expect(
      [for (final item in model.items) item.completion],
      ['result', 'replyToUser', 'randomLolut'],
    );
  });

  test('Emmet suggestion not appearing at the top of the list in jsx files, '
      '#39518', () {
    model = CompletionModel(
      [
        createSuggestItem('from', 0),
        createSuggestItem('form', 0),
        createSuggestItem('form:get', 0),
        createSuggestItem('testForeignMeasure', 0),
        createSuggestItem('fooRoom', 0),
      ],
      1,
      const LineContext('', 0),
    );

    model.lineContext = const LineContext('form', 4);
    expect(model.items.length, 5);
    final [first, second, third, ...] = model.items;
    expect(first.completion, 'form');
    expect(second.completion, 'form:get');
    expect(third.completion, 'from');
  });
}
