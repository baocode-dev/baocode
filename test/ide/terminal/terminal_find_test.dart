// New (not a port): TerminalFind against the headless terminal, with the
// search addon's stand-in browser terminal (a selection model and a
// decoration service) from its tests.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/terminal_find.dart';
import 'package:bao_xterm/addons/addon_search/typings/addon_search.dart';
import 'package:bao_xterm/common/async.dart';
import 'package:bao_xterm/common/services/services.dart'
    show IInternalDecoration;
import 'package:bao_xterm/typings/xterm.dart' show ITerminalOptions;

import 'package:bao_xterm/testing/search_test_terminal.dart';

final ISearchDecorationOptions _colors = ISearchDecorationOptions(
  matchBackground: '#20404e',
  matchOverviewRuler: '#3a94bc99',
  activeMatchBackground: '#27678290',
  activeMatchColorOverviewRuler: '#a0a0a0cc',
);

void main() {
  late SearchTestTerminal terminal;
  late TerminalFind find;
  late int changes;

  Future<void> write(String data) {
    final c = Completer<void>();
    terminal.write(data, c.complete);
    return c.future;
  }

  /// The decorations of a layer, as the renderer paints them.
  List<IInternalDecoration> layer(String layer) => terminal
      .decorationService
      .decorations
      .where((d) => (d.options.layer ?? 'bottom') == layer)
      .toList();

  setUp(() {
    terminal = SearchTestTerminal(ITerminalOptions(cols: 80, rows: 24));
    find = TerminalFind(terminal, decorations: _colors);
    changes = 0;
    find.onDidChange((_) => changes++);
  });

  tearDown(() {
    find.dispose();
    terminal.dispose();
  });

  test('starts hidden, without a query or results', () {
    expect(find.isVisible, isFalse);
    expect(find.inputValue, '');
    expect(find.resultCount, 0);
    expect(find.resultIndex, -1);
    expect(find.foundMatch, isFalse);
    expect(find.regexError, isNull);
  });

  test('reveal without a query shows the widget and searches nothing', () {
    find.reveal();
    expect(find.isVisible, isTrue);
    expect(find.resultCount, 0);
    expect(terminal.hasSelection(), isFalse);
    expect(changes, greaterThan(0));
  });

  test('typing finds the last match and highlights every match', () async {
    await write('foo bar\r\nfoo baz\r\nfoo');
    find.reveal();
    find.inputValue = 'foo';

    expect(terminal.getSelectionPosition(), bufferRange(0, 2, 3, 2));
    expect(find.resultCount, 3);
    expect(find.resultIndex, 2);
    expect(find.foundMatch, isTrue);

    final matches = layer('bottom');
    expect(matches.map((d) => d.marker.line), [0, 1, 2]);
    expect(matches.map((d) => d.options.backgroundColor).toSet(), {'#20404e'});
    final active = layer('top').single;
    expect(active.marker.line, 2);
    expect(active.options.x, 0);
    expect(active.options.width, 3);
    expect(active.options.backgroundColor, '#27678290');
  });

  test('setting the same query again does not search', () async {
    await write('foo foo');
    find.inputValue = 'foo';
    find.find(true);
    expect(find.resultIndex, 0);
    find.inputValue = 'foo';
    expect(find.resultIndex, 0);
  });

  test('typing on keeps the current match while it still matches', () async {
    await write('foo foobar foo');
    find.inputValue = 'foo';
    expect(find.resultIndex, 2);
    find.find(true);
    expect(terminal.getSelectionPosition(), bufferRange(4, 0, 7, 0));

    find.inputValue = 'foob';
    expect(terminal.getSelectionPosition(), bufferRange(4, 0, 8, 0));
    expect(find.resultCount, 1);
    expect(find.resultIndex, 0);

    find.inputValue = '';
    expect(terminal.hasSelection(), isFalse);
    expect(find.resultCount, 0);
    expect(find.resultIndex, -1);
    expect(find.foundMatch, isFalse);
  });

  test('previous and next go up and down, wrapping around', () async {
    await write('a\r\na\r\na');
    find.inputValue = 'a';
    expect(find.resultIndex, 2);

    final indexes = <int>[];
    for (final previous in [true, true, true, false, false]) {
      find.find(previous);
      indexes.add(find.resultIndex);
    }
    expect(indexes, [1, 0, 2, 0, 1]);
    expect(terminal.getSelectionPosition(), bufferRange(0, 1, 1, 1));
  });

  test('reveal takes a one-line selection as the query', () async {
    await write('hello world\r\nhello');
    terminal.select(0, 0, 5);

    find.reveal();
    expect(find.inputValue, 'hello');
    expect(find.resultCount, 2);
    // The selected occurrence stays the current match.
    expect(find.resultIndex, 0);
    expect(terminal.getSelectionPosition(), bufferRange(0, 0, 5, 0));
  });

  test('reveal keeps the query over a multi-line selection', () async {
    await write('hello world\r\nhello');
    find.reveal();
    find.inputValue = 'world';
    find.hide();
    terminal.select(6, 0, 80);
    expect(terminal.getSelection(), 'world\nhello');

    find.reveal();
    expect(find.inputValue, 'world');
    expect(find.resultCount, 1);
    expect(find.resultIndex, 0);
  });

  test(
    'findNext shows the widget with a one-line selection as the query',
    () async {
      await write('foo bar foo');
      terminal.select(4, 0, 3);

      find.findNext();
      expect(find.isVisible, isTrue);
      expect(find.inputValue, 'bar');
      expect(find.resultCount, 1);
      expect(find.resultIndex, 0);
      expect(terminal.getSelectionPosition(), bufferRange(4, 0, 7, 0));

      // Visible: the selection no longer replaces the query.
      terminal.select(0, 0, 3);
      find.findPrevious();
      expect(find.inputValue, 'bar');
    },
  );

  test('toggling an option finds the last match with it', () async {
    await write('foo Foo foo Foo');
    find.inputValue = 'foo';
    find.find(true);
    expect(terminal.getSelectionPosition(), bufferRange(8, 0, 11, 0));

    // From no selection: the last match, not the one above the current.
    find.toggleCaseSensitive();
    expect(find.caseSensitive, isTrue);
    expect(find.isVisible, isTrue);
    expect(terminal.getSelectionPosition(), bufferRange(8, 0, 11, 0));
    // As in VS Code, the highlights are not found again for new options with
    // the same query (xterm.js compares the new options with themselves).
    expect(find.resultCount, 4);
    expect(find.resultIndex, 2);

    find.find(true);
    expect(terminal.getSelectionPosition(), bufferRange(0, 0, 3, 0));
    find.toggleCaseSensitive();
    expect(find.caseSensitive, isFalse);
    expect(terminal.getSelectionPosition(), bufferRange(12, 0, 15, 0));
  });

  test('whole word and regex', () async {
    await write('a1\r\nba22');
    find.toggleRegex();
    expect(find.regex, isTrue);
    find.inputValue = r'a\d+';
    expect(terminal.getSelection(), 'a22');
    expect(find.resultCount, 2);

    find.toggleWholeWord();
    expect(find.wholeWord, isTrue);
    expect(terminal.getSelection(), 'a1');
  });

  test('an invalid regex is reported, not thrown', () async {
    await write('foo(');
    find.toggleRegex();
    find.inputValue = 'foo';
    expect(find.resultCount, 1);
    expect(find.foundMatch, isTrue);

    find.inputValue = 'foo(';
    expect(find.regexError, isNotNull);
    expect(find.foundMatch, isFalse);

    find.toggleRegex();
    expect(find.regexError, isNull);
    expect(find.resultCount, 1);
    expect(find.foundMatch, isTrue);
    expect(terminal.getSelection(), 'foo(');
  });

  test('hide clears the highlights and keeps the selected match', () async {
    await write('foo foo');
    find.reveal();
    find.inputValue = 'foo';
    expect(terminal.decorationService.decorations, isNotEmpty);

    find.hide();
    expect(find.isVisible, isFalse);
    expect(terminal.decorationService.decorations, isEmpty);
    expect(terminal.getSelectionPosition(), bufferRange(4, 0, 7, 0));
  });

  test('a new selection clears the current match highlight', () async {
    await write('foo foo');
    find.inputValue = 'foo';
    expect(layer('top'), hasLength(1));

    terminal.select(0, 0, 2);
    expect(layer('top'), isEmpty);
    expect(layer('bottom'), hasLength(2));
  });

  test('clearActiveDecoration clears the current match highlight', () async {
    await write('foo foo');
    find.inputValue = 'foo';
    expect(layer('top'), hasLength(1));

    find.clearActiveDecoration();
    expect(layer('top'), isEmpty);
    expect(terminal.hasSelection(), isTrue);
  });

  test('the count follows new output', () async {
    await write('abc ');
    find.reveal();
    find.inputValue = 'abc';
    expect(find.resultCount, 1);

    final before = changes;
    await write('abc');
    await timeout(300);
    expect(find.resultCount, 2);
    expect(find.resultIndex, 0);
    expect(changes, greaterThan(before));
  });

  test('new colors apply from the next search on', () async {
    await write('foo foo');
    find.inputValue = 'foo';
    find.decorations = ISearchDecorationOptions(
      matchOverviewRuler: '#000000',
      activeMatchBackground: '#ff0000',
      activeMatchColorOverviewRuler: '#000000',
    );
    expect(layer('top').single.options.backgroundColor, '#27678290');

    find.find(true);
    expect(layer('top').single.options.backgroundColor, '#ff0000');
  });

  test('searches fire onBeforeSearch and onAfterSearch', () async {
    await write('foo');
    final events = <String>[];
    find.onBeforeSearch((_) => events.add('before'));
    find.onAfterSearch((_) => events.add('after'));
    find.inputValue = 'foo';
    find.find(false);
    expect(events, ['before', 'after', 'before', 'after']);
  });

  test('dispose removes the highlights', () async {
    await write('foo foo');
    find.inputValue = 'foo';
    expect(terminal.decorationService.decorations, isNotEmpty);

    find.dispose();
    expect(terminal.decorationService.decorations, isEmpty);
  });
}
