import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_folding.dart';
import 'package:bao_editor/monaco/flutter/editor_keybindings.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/language_assets.dart';
import 'package:bao_editor/monaco/flutter/language_configuration_assets.dart';
import 'package:bao_editor/monaco/vs/editor/common/languages/language_configuration.dart';

const _assets = MonacoLanguageAssets();

Future<LanguageConfiguration> _language(String id) async =>
    languageConfigurationOf(await _assets.loadRegistered(id))!;

EditorSurfaceController _controller(
  String text, {
  LanguageConfiguration? language,
  List<TextSelection>? selections,
}) {
  final document = EditorDocumentModel(text);
  final controller = EditorSurfaceController(document: document)
    ..languageConfiguration = language;
  addTearDown(() {
    controller.dispose();
    document.dispose();
  });
  if (selections != null) controller.setSelections(selections);
  return controller;
}

TextSelection _at(int offset) => TextSelection.collapsed(offset: offset);

TextSelection _range(int base, int extent) =>
    TextSelection(baseOffset: base, extentOffset: extent);

/// Renders the text with `|` at every caret and `[`/`]` around selections.
String _show(EditorSurfaceController c) {
  final marks = <int, String>{};
  for (final s in c.selections) {
    if (s.isCollapsed) {
      marks[s.extentOffset] = '${marks[s.extentOffset] ?? ''}|';
    } else {
      marks[s.start] = '${marks[s.start] ?? ''}[';
      marks[s.end] = ']${marks[s.end] ?? ''}';
    }
  }
  final text = c.value.text;
  final buffer = StringBuffer();
  for (var i = 0; i <= text.length; i++) {
    buffer.write(marks[i] ?? '');
    if (i < text.length) buffer.write(text[i]);
  }
  return buffer.toString();
}

/// A host that moves one document line per row, keeping the column as x.
class _Host implements EditorViewHost {
  _Host(this.controller);

  final EditorSurfaceController controller;
  bool editable = true;
  final intents = <Intent>[];

  @override
  bool get canEdit => editable;

  @override
  int get pageRowCount => 2;

  @override
  void invokeTextAction(Intent intent) => intents.add(intent);

  int scrolledRows = 0;
  final revealed = <(int, int)>[];
  EditorFoldingModel? folding;
  int foldingChanges = 0;

  @override
  void scrollByRows(int rows) => scrolledRows += rows;

  @override
  void revealRange(int start, int end) => revealed.add((start, end));

  @override
  EditorFoldingModel? get foldingModel => folding;

  @override
  void foldingChanged() => foldingChanges++;

  @override
  ({int offset, double x}) verticalTarget(
    int offset,
    int rows, {
    double? preferredX,
  }) {
    final lines = controller.value.text.split('\n');
    var line = 0, start = 0;
    while (line < lines.length - 1 && start + lines[line].length < offset) {
      start += lines[line].length + 1;
      line++;
    }
    final x = preferredX ?? (offset - start).toDouble();
    final target = line + rows;
    if (target < 0) return (offset: 0, x: x);
    if (target >= lines.length) {
      return (offset: controller.value.text.length, x: x);
    }
    var targetStart = 0;
    for (var i = 0; i < target; i++) {
      targetStart += lines[i].length + 1;
    }
    final column = x.round().clamp(0, lines[target].length);
    return (offset: targetStart + column, x: x);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('multi-cursor editing', () {
    test('typing applies to every cursor and undoes as one step', () {
      final c = _controller(
        'foo\nfoo\nfoo',
        selections: [_at(3), _at(7), _at(11)],
      );
      final version = c.document.version;
      c.type('x');
      c.type('y');
      expect(_show(c), 'fooxy|\nfooxy|\nfooxy|');
      expect(c.selections.first, _at(5));
      expect(c.undo(), isTrue);
      expect(_show(c), 'foo|\nfoo|\nfoo|');
      expect(c.document.canUndo, isFalse);
      expect(c.document.version, greaterThan(version));
      expect(c.redo(), isTrue);
      expect(_show(c), 'fooxy|\nfooxy|\nfooxy|');
    });

    test('platform insertion at the primary types at every cursor', () {
      final c = _controller('a\nb', selections: [_at(1), _at(3)]);
      c.value = const TextEditingValue(
        text: 'az\nb',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(_show(c), 'az|\nbz|');
      expect(c.value.text, 'az\nbz');
    });

    test('a cursor move breaks typing coalescing', () {
      final c = _controller('');
      c.type('a');
      c.type('b');
      c.select(1, 1);
      c.type('c');
      expect(c.value.text, 'acb');
      c.undo();
      expect(_show(c), 'a|b');
      c.undo();
      expect(_show(c), '|');
    });

    test('space after a word starts a new undo step, like Monaco', () {
      final c = _controller('');
      for (final ch in 'ab cd'.split('')) {
        c.type(ch);
      }
      c.undo();
      expect(c.value.text, 'ab');
      c.undo();
      expect(c.value.text, '');
    });

    test('overlapping selections merge; the older one wins', () {
      final c = _controller('abcdef', selections: [_range(0, 3), _range(5, 2)]);
      // The last added cursor's direction wins.
      expect(c.selections, [_range(5, 0)]);
      c.setSelections([_at(2), _range(2, 1)]);
      expect(c.selections, [_at(1).copyWith(baseOffset: 2, extentOffset: 1)]);
    });

    test('backspace, delete and enter at every cursor', () {
      final c = _controller('ab\ncd', selections: [_at(1), _at(4)]);
      c.deleteBackward();
      expect(_show(c), '|b\n|d');
      c.deleteForward();
      expect(_show(c), '|\n|');
      c.type('x');
      c.newline();
      expect(_show(c), 'x\n|\nx\n|');
      c.undo();
      expect(_show(c), 'x|\nx|');
    });

    test('paste spreads lines over cursors when the counts match', () {
      final c = _controller('1\n2\n3', selections: [_at(1), _at(3), _at(5)]);
      c.pasteText('a\nb\nc');
      expect(_show(c), '1a|\n2b|\n3c|');
      c.pasteText('xy');
      expect(_show(c), '1axy|\n2bxy|\n3cxy|');
    });

    test('a paste hook takes the paste, or lets the text in', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': 'text'};
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final c = _controller('ab', selections: [_at(1)]);
      var taken = true;
      var calls = 0;
      c.onPaste = () async {
        calls++;
        if (taken) c.pasteText('[link]');
        return taken;
      };
      await c.paste();
      expect(_show(c), 'a[link]|b');
      taken = false;
      await c.paste();
      expect(_show(c), 'a[link]text|b');
      expect(calls, 2);
      // Not editable: not asked.
      await c.paste(canEdit: () => false);
      expect(calls, 2);
    });

    test(
      'copy with empty selections copies whole lines; paste above',
      () async {
        String? clipboard;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          } else if (call.method == 'Clipboard.getData') {
            return {'text': clipboard};
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final c = _controller('one\ntwo', selections: [_at(1)]);
        await c.copy();
        expect(clipboard, 'one\n');
        c.select(5, 5);
        await c.paste();
        expect(_show(c), 'one\none\nt|wo');

        c.setSelections([_range(0, 3), _range(4, 7)]);
        await c.copy();
        expect(clipboard, 'one\none');
        c.setSelections([_at(0), _at(4)]);
        await c.paste();
        expect(c.value.text, 'oneone\noneone\ntwo');
      },
    );

    test('a copy from one place tells where its lines are', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final copies = <(String, int, int)>[];
      final c = _controller('one\ntwo\nthree', selections: [_range(5, 6)])
        ..onCopy = (text, start, end) => copies.add((text, start, end));
      await c.copy();
      // To the start of a line: the lines before it.
      c.setSelections([_range(0, 8)]);
      await c.copy();
      // A cursor's line.
      c.setSelections([_at(9)]);
      await c.copy();
      expect(copies, [('w', 2, 2), ('one\ntwo\n', 1, 2), ('three\n', 3, 3)]);

      // From several places: no lines to tell.
      c.setSelections([_range(0, 1), _range(4, 5)]);
      await c.copy();
      expect(copies, hasLength(3));
    });

    test('cut of empty selections deletes whole lines', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final c = _controller('a\nb\nc', selections: [_at(0), _at(4)]);
      await c.cut();
      expect(_show(c), '|b|');
    });

    test('IME commit is replicated to secondary cursors', () {
      final c = _controller('a\nb', selections: [_at(1), _at(3)]);
      c.value = const TextEditingValue(
        text: 'aか\nb',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      );
      c.value = const TextEditingValue(
        text: 'a家\nb',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(_show(c), 'a家|\nb家|');
      c.undo();
      expect(_show(c), 'a|\nb|');
    });

    test('escape removes secondary cursors, then collapses', () {
      final c = _controller('abc\nabc', selections: [_range(0, 2), _at(5)]);
      expect(c.cancelSelection(), isTrue);
      expect(c.selections, [_range(0, 2)]);
      expect(c.cancelSelection(), isTrue);
      expect(c.selections, [_at(2)]);
      expect(c.cancelSelection(), isFalse);
    });

    test('add next occurrence and select all occurrences', () {
      final c = _controller('foo bar foo foobar foo', selections: [_at(1)]);
      expect(c.addSelectionToNextFindMatch(), isTrue);
      expect(c.selections, [_range(0, 3)]);
      expect(c.addSelectionToNextFindMatch(), isTrue);
      expect(c.selections, [_range(0, 3), _range(8, 11)]);
      // Whole-word matching skips "foobar".
      expect(c.addSelectionToNextFindMatch(), isTrue);
      expect(c.selections.last, _range(19, 22));
      expect(c.cursorUndo(), isTrue);
      expect(c.selections, [_range(0, 3), _range(8, 11)]);
      c.select(9, 9);
      expect(c.selectAllOccurrences(), isTrue);
      expect(c.selections, [_range(8, 11), _range(0, 3), _range(19, 22)]);
    });

    test('add cursors above and below keep the column', () {
      final c = _controller('abcd\nab\nabcd', selections: [_at(3)]);
      final host = _Host(c);
      c.addCursorsVertically(1, host.verticalTarget);
      c.addCursorsVertically(1, host.verticalTarget);
      expect(_show(c), 'abc|d\nab|\nabc|d');
    });

    test('column selection spans lines by visible column', () {
      final c = _controller('abcd\nab\nabcd');
      c.columnSelect(1, 11);
      expect(c.selections, [_range(1, 3), _range(6, 7), _range(9, 11)]);
    });
  });

  group('navigation', () {
    test('word moves stop at word starts and ends', () {
      final c = _controller('foo bar_baz  (qux)', selections: [_at(0)]);
      c.moveWordRight();
      expect(c.value.selection, _at(3));
      c.moveWordRight();
      expect(c.value.selection, _at(11));
      // A single separator before a word is skipped, like Monaco.
      c.moveWordRight();
      expect(c.value.selection, _at(17));
      c.moveWordLeft();
      expect(c.value.selection, _at(14));
      c.moveWordLeft();
      expect(c.value.selection, _at(13));
      c.moveWordLeft();
      expect(c.value.selection, _at(4));
      c.moveWordLeft(extend: true);
      expect(c.value.selection, _range(4, 0));
    });

    test('delete word left and right', () {
      final c = _controller('foo bar  baz', selections: [_at(9)]);
      // Whitespace heuristics: a run of spaces is deleted first.
      c.deleteWordLeft();
      expect(_show(c), 'foo bar|baz');
      c.deleteWordLeft();
      expect(_show(c), 'foo |baz');
      c.deleteWordRight();
      expect(_show(c), 'foo |');
      c.select(2, 2);
      c.deleteAllLeft();
      expect(_show(c), '|o ');
    });

    test('smart home toggles between indentation and line start', () {
      final c = _controller('    abc', selections: [_at(7)]);
      c.moveToLineStart();
      expect(c.value.selection, _at(4));
      c.moveToLineStart();
      expect(c.value.selection, _at(0));
      c.moveToLineStart();
      expect(c.value.selection, _at(4));
      c.moveToLineEnd(extend: true);
      expect(c.value.selection, _range(4, 7));
    });

    test('vertical moves keep a sticky column; page moves use the host', () {
      final c = _controller('abcd\na\nabcd\nabcd', selections: [_at(3)]);
      final host = _Host(c);
      c.moveVertical(1, host.verticalTarget);
      expect(c.value.selection, _at(6));
      c.moveVertical(1, host.verticalTarget);
      expect(c.value.selection, _at(10));
      c.moveVertical(-host.pageRowCount, host.verticalTarget);
      expect(c.value.selection, _at(3));
      c.moveVertical(-1, host.verticalTarget);
      expect(c.value.selection, _at(0));
    });

    test('word and line selection helpers', () {
      final c = _controller('foo.bar baz\nnext');
      expect(c.wordRangeAt(5), const TextRange(start: 4, end: 7));
      c.selectWordAt(9);
      expect(c.value.selection, _range(8, 11));
      c.selectLineAt(2);
      expect(c.value.selection, _range(0, 12));
      c.selectLineAt(0, anchorOffset: 13);
      expect(c.value.selection, _range(16, 0));
      c.expandLineSelection();
      expect(c.value.selection.start, 0);
    });
  });

  group('language-aware typing', () {
    late LanguageConfiguration typescript;
    late LanguageConfiguration python;

    setUpAll(() async {
      typescript = await _language('typescript');
      python = await _language('python');
    });

    test('auto-closes brackets and quotes and types over the close', () {
      final c = _controller('', language: typescript);
      c.type('(');
      expect(_show(c), '(|)');
      c.type('a');
      c.type(')');
      expect(_show(c), '(a)|');
      c.type(' ');
      c.type('"');
      expect(_show(c), '(a) "|"');
      c.type('"');
      expect(_show(c), '(a) ""|');
    });

    test('does not auto-close before a word or inside a string', () {
      final c = _controller('foo', language: typescript, selections: [_at(0)]);
      c.type('(');
      expect(_show(c), '(|foo');
      final s = _controller("'ab'", language: typescript, selections: [_at(2)]);
      s.type("'");
      expect(_show(s), "'a'|b'");
    });

    test('surrounds a selection and deletes an empty pair', () {
      final c = _controller(
        'foo',
        language: typescript,
        selections: [_range(0, 3)],
      );
      c.type('[');
      expect(_show(c), '[[foo]]');
      // Not auto-closed before a word character.
      c.select(1, 1);
      c.type('(');
      expect(_show(c), '[(|foo]');
      c.select(5, 5);
      c.type('(');
      expect(_show(c), '[(foo(|)]');
      c.deleteBackward();
      expect(_show(c), '[(foo|]');
    });

    test('enter keeps indentation and splits brackets', () {
      final c = _controller(
        '    f() {}',
        language: typescript,
        selections: [_at(9)],
      );
      c.newline();
      expect(_show(c), '    f() {\n        |\n    }');
      c.type('x');
      c.newline();
      expect(_show(c), '    f() {\n        x\n        |\n    }');
    });

    test('enter applies onEnterRules for doc comments', () {
      final c = _controller('/** a', language: typescript);
      c.newline();
      expect(_show(c), '/** a\n * |');
    });

    test('python indents after a colon', () {
      final c = _controller('if x:', language: python);
      c.newline();
      expect(_show(c), 'if x:\n    |');
    });

    test('electric close bracket outdents', () {
      final c = _controller('{\n    ', language: typescript);
      c.type('}');
      expect(_show(c), '{\n}|');
    });

    test('tab indents to the next stop and outdent removes it', () {
      final c = _controller('ab', selections: [_at(1)]);
      c.tab();
      expect(_show(c), 'a   |b');
      c.setSelections([_range(0, 2)]);
      c.indentLines();
      expect(c.value.text, '    a   b');
      c.outdentLines();
      expect(c.value.text, 'a   b');
    });

    test('uses the document EOL for inserted line breaks', () {
      final c = _controller('a\r\nb', selections: [_at(1)]);
      c.newline();
      expect(c.value.text, 'a\r\n\r\nb');
      c.pasteText('x\ny');
      expect(c.value.text, 'a\r\nx\r\ny\r\nb');
    });

    test('platform typing goes through the interceptors', () {
      final c = _controller(
        'ab',
        language: typescript,
        selections: [_range(0, 2)],
      );
      c.value = const TextEditingValue(
        text: '(',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(_show(c), '([ab])');
      c.select(4, 4);
      c.value = const TextEditingValue(
        text: '(ab)"',
        selection: TextSelection.collapsed(offset: 5),
      );
      expect(_show(c), '(ab)"|"');
    });

    test('null language keeps plain typing', () {
      final c = _controller('');
      c.type('(');
      expect(_show(c), '(|');
    });
  });

  group('comments', () {
    test('toggles line comments for several languages', () async {
      for (final (id, expected) in [
        ('typescript', '// a\n// b'),
        ('python', '# a\n# b'),
        ('shell', '# a\n# b'),
        ('css', '/* a\nb */'),
        ('html', '<!-- a\nb -->'),
      ]) {
        final c = _controller(
          'a\nb',
          language: await _language(id),
          selections: [_range(0, 3)],
        );
        expect(c.toggleLineComment(), isTrue, reason: id);
        expect(c.value.text, expected, reason: id);
        c.toggleLineComment();
        expect(c.value.text, 'a\nb', reason: id);
      }
    });

    test('line comments keep indentation and toggle per cursor', () async {
      final c = _controller(
        '    a\n        b\nc',
        language: await _language('typescript'),
        selections: [_at(5), _at(15)],
      );
      c.toggleLineComment();
      expect(c.value.text, '    // a\n        // b\nc');
      c.undo();
      expect(c.value.text, '    a\n        b\nc');
    });

    test('toggles block comments', () async {
      final c = _controller(
        'let a = 1;',
        language: await _language('typescript'),
        selections: [_range(4, 5)],
      );
      expect(c.toggleBlockComment(), isTrue);
      expect(c.value.text, 'let /* a */ = 1;');
      c.toggleBlockComment();
      expect(c.value.text, 'let a = 1;');
    });

    test('no comments without a language', () {
      final c = _controller('a');
      expect(c.toggleLineComment(), isFalse);
    });
  });

  group('line operations', () {
    test('move lines up and down', () {
      final c = _controller('1\n2\n3', selections: [_at(0)]);
      c.moveLines(down: true);
      expect(_show(c), '2\n|1\n3');
      c.moveLines(down: true);
      expect(_show(c), '2\n3\n|1');
      c.moveLines(down: false);
      c.moveLines(down: false);
      expect(_show(c), '|1\n2\n3');
    });

    test('copy lines, delete lines and insert lines', () {
      final c = _controller('ab\ncd', selections: [_at(1)]);
      c.copyLines(down: true);
      expect(_show(c), 'ab\na|b\ncd');
      c.deleteLines();
      expect(_show(c), 'ab\nc|d');
      c.insertLineAfter();
      expect(_show(c), 'ab\ncd\n|');
      c.insertLineBefore();
      expect(_show(c), 'ab\ncd\n|\n');
    });

    test('line operations keep CRLF line endings', () {
      final c = _controller('1\r\n2\r\n3', selections: [_at(0)]);
      c.moveLines(down: true);
      expect(c.value.text, '2\r\n1\r\n3');
      c.copyLines(down: false);
      expect(c.value.text, '2\r\n1\r\n1\r\n3');
      c.insertLineAfter();
      expect(c.value.text, '2\r\n1\r\n\r\n1\r\n3');
    });

    test('transform case', () {
      final c = _controller('hello world', selections: [_at(2)]);
      c.transformCase(upper: true);
      expect(_show(c), 'HE|LLO world');
    });
  });

  group('indentation detection', () {
    test('detects tabs and space sizes', () {
      final c = _controller('a\n\tb\n\t\tc');
      c.detectIndentation();
      expect(c.insertSpaces, isFalse);
      final s = _controller('a\n  b\n    c\n  d');
      s.detectIndentation();
      expect((s.insertSpaces, s.tabSize), (true, 2));
    });
  });

  group('language configuration assets', () {
    test('every pinned language configuration converts', () async {
      for (final registration in await _assets.registrations()) {
        final language = await _assets.loadRegistered(registration.id);
        final conf = languageConfigurationOf(language);
        if (language.configuration != null) {
          expect(conf, isNotNull, reason: registration.id);
        }
      }
      final ts = await _language('typescript');
      expect(ts.comments?.lineComment?.comment, '//');
      expect(ts.comments?.blockComment, ('/*', '*/'));
      expect(ts.autoClosingPairs!.last.notIn, ['string']);
      expect(
        ts.onEnterRules!.first.action.indentAction,
        IndentAction.indentOutdent,
      );
      final conf = await languageConfigurationForPath('lib/main.py');
      expect(conf?.comments?.lineComment?.comment, '#');
    });

    test('accepts list and string shapes', () {
      final conf = languageConfigurationFromMonaco({
        'comments': {
          'lineComment': {'comment': ';', 'noIndent': true},
        },
        'autoClosingPairs': [
          ['(', ')'],
          {'open': '"', 'close': '"', 'notIn': 'string'},
        ],
        'surroundingPairs': [
          ['<', '>'],
        ],
      });
      expect(conf.comments?.lineComment?.noIndent, isTrue);
      expect(conf.autoClosingPairs!.map((p) => p.close), [')', '"']);
      expect(conf.autoClosingPairs!.last.notIn, ['string']);
      expect(conf.surroundingPairs!.single.open, '<');
    });
  });

  group('commands and keybindings', () {
    test('every labelled command runs and has a keybinding lookup', () {
      for (final id in editorCommandLabels.keys) {
        final c = _controller('a\nb', selections: [_at(0)]);
        runEditorCommand(id, c, _Host(c));
        editorCommandKeybindingLabel(id);
      }
      expect(
        editorCommandKeybindingLabel(
          'editor.action.copyLinesDownAction',
          platform: TargetPlatform.macOS,
        ),
        '⌥⇧↓',
      );
      expect(
        editorCommandKeybindingLabel(
          'editor.action.commentLine',
          platform: TargetPlatform.linux,
        ),
        'Ctrl+/',
      );
      expect(
        editorCommandKeybindingLabel(
          'editor.action.moveSelectionToNextFindMatch',
        ),
        isNull,
      );
      final c = _controller('a');
      final host = _Host(c)..editable = false;
      expect(runEditorCommand('editor.action.deleteLines', c, host), isFalse);
      expect(c.value.text, 'a');
      expect(runEditorCommand('nope', c, host), isFalse);
    });

    Future<KeyEventResult> press(
      WidgetTester tester,
      EditorSurfaceController c,
      EditorViewHost host,
      LogicalKeyboardKey key, {
      List<LogicalKeyboardKey> modifiers = const [],
    }) async {
      for (final modifier in modifiers) {
        await simulateKeyDownEvent(modifier);
      }
      final result = handleEditorKeyEvent(
        c,
        host,
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: key,
          timeStamp: Duration.zero,
        ),
      );
      for (final modifier in modifiers.reversed) {
        await simulateKeyUpEvent(modifier);
      }
      return result;
    }

    testWidgets('macOS bindings edit, and app shortcuts are ignored', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final c = _controller('foo bar\nfoo', selections: [_at(7)]);
        final host = _Host(c);
        const meta = LogicalKeyboardKey.metaLeft;
        const alt = LogicalKeyboardKey.altLeft;
        const shift = LogicalKeyboardKey.shiftLeft;
        const control = LogicalKeyboardKey.controlLeft;
        for (final (key, mods) in [
          (LogicalKeyboardKey.keyS, [meta]),
          (LogicalKeyboardKey.keyF, [meta]),
          (LogicalKeyboardKey.keyH, [meta]),
          (LogicalKeyboardKey.keyP, [meta]),
          (LogicalKeyboardKey.keyP, [meta, shift]),
          (LogicalKeyboardKey.keyW, [meta]),
          (LogicalKeyboardKey.keyG, [meta]),
          (LogicalKeyboardKey.keyB, [meta]),
          (LogicalKeyboardKey.keyJ, [meta]),
          (LogicalKeyboardKey.keyK, [meta]),
          (LogicalKeyboardKey.tab, [control]),
          (LogicalKeyboardKey.bracketLeft, [meta, shift]),
          (LogicalKeyboardKey.bracketRight, [meta, shift]),
        ]) {
          expect(
            await press(tester, c, host, key, modifiers: mods),
            KeyEventResult.ignored,
            reason: '$key $mods',
          );
        }
        expect(c.value.text, 'foo bar\nfoo');
        expect(
          await press(
            tester,
            c,
            host,
            LogicalKeyboardKey.arrowLeft,
            modifiers: [alt],
          ),
          KeyEventResult.handled,
        );
        expect(c.value.selection, _at(4));
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.arrowLeft,
          modifiers: [meta],
        );
        expect(c.value.selection, _at(0));
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.keyD,
          modifiers: [meta],
        );
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.keyD,
          modifiers: [meta],
        );
        expect(c.selections, [_range(0, 3), _range(8, 11)]);
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.slash,
          modifiers: [meta],
        );
        expect(c.value.text, 'foo bar\nfoo');
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.arrowDown,
          modifiers: [alt],
        );
        expect(c.value.text, 'foo bar\nfoo');
        expect(
          await press(tester, c, host, LogicalKeyboardKey.escape),
          KeyEventResult.handled,
        );
        expect(c.selections, hasLength(1));
        await press(tester, c, host, LogicalKeyboardKey.escape);
        expect(
          await press(tester, c, host, LogicalKeyboardKey.escape),
          KeyEventResult.ignored,
        );
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.backspace,
          modifiers: [meta],
        );
        expect(c.value.text, ' bar\nfoo');
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.keyK,
          modifiers: [meta, shift],
        );
        expect(c.value.text, 'foo');
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.keyZ,
          modifiers: [meta],
        );
        expect(c.value.text, ' bar\nfoo');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Windows/Linux bindings use Ctrl for words', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final c = _controller('foo bar', selections: [_at(7)]);
        final host = _Host(c);
        await press(
          tester,
          c,
          host,
          LogicalKeyboardKey.backspace,
          modifiers: [LogicalKeyboardKey.controlLeft],
        );
        expect(c.value.text, 'foo ');
        await press(tester, c, host, LogicalKeyboardKey.home);
        expect(c.value.selection, _at(0));
        expect(
          await press(
            tester,
            c,
            host,
            LogicalKeyboardKey.keyS,
            modifiers: [LogicalKeyboardKey.controlLeft],
          ),
          KeyEventResult.ignored,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('macOS selectors drive word and line commands', () {
      final c = _controller('foo bar', selections: [_at(7)]);
      final host = _Host(c);
      handleEditorSelector(c, host, 'moveWordLeft:');
      expect(c.value.selection, _at(4));
      handleEditorSelector(c, host, 'moveToBeginningOfLineAndModifySelection:');
      expect(c.value.selection, _range(4, 0));
      handleEditorSelector(c, host, 'moveToEndOfLine:');
      handleEditorSelector(c, host, 'deleteWordBackward:');
      expect(c.value.text, 'foo ');
      handleEditorSelector(c, host, 'insertNewline:');
      expect(c.value.text, 'foo \n');
    });
  });

  group('keybindings', () {
    test('Go to Bracket jumps to the partner of the bracket at a caret', () {
      final c = _controller('f(a[1], b) + x', selections: [_at(1), _at(13)]);
      final host = _Host(c);
      expect(runEditorCommand('editor.action.jumpToBracket', c, host), isTrue);
      // The caret at `(` goes to `)`; the one touching no bracket stays.
      expect(_show(c), 'f(a[1], b|) + |x');
      expect(runEditorCommand('editor.action.jumpToBracket', c, host), isTrue);
      expect(_show(c), 'f|(a[1], b) + |x');
      final none = _controller('abc', selections: [_at(1)]);
      expect(
        runEditorCommand('editor.action.jumpToBracket', none, _Host(none)),
        isFalse,
      );
      expect(
        editorCommandKeybindingLabel(
          'editor.action.jumpToBracket',
          platform: TargetPlatform.macOS,
        ),
        '⇧⌘\\',
      );
    });

    testWidgets('a resolver decides what a key runs', (tester) async {
      final c = _controller('(a)', selections: [_at(0)]);
      final host = _Host(c);
      KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: key,
        timeStamp: Duration.zero,
      );
      String? resolved;
      KeyEventResult press(LogicalKeyboardKey key) =>
          handleEditorKeyEvent(c, host, down(key), resolve: (_) => resolved);
      // An editor command runs.
      resolved = 'editor.action.jumpToBracket';
      expect(press(LogicalKeyboardKey.keyE), KeyEventResult.handled);
      expect(_show(c), '(a|)');
      // Another command is the workbench's: the key goes on to it.
      resolved = 'workbench.action.navigateBack';
      expect(press(LogicalKeyboardKey.keyE), KeyEventResult.ignored);
      // No keybinding: a cursor key does nothing (its command is unbound,
      // and the text system and focus traversal do not get it); typing is
      // left alone, and Enter types a line break.
      resolved = null;
      expect(press(LogicalKeyboardKey.arrowLeft), KeyEventResult.handled);
      expect(_show(c), '(a|)');
      expect(press(LogicalKeyboardKey.keyE), KeyEventResult.ignored);
      expect(c.value.text, '(a)');
      expect(press(LogicalKeyboardKey.enter), KeyEventResult.handled);
      expect(c.value.text, '(a\n)');
      // The cursor keys are commands.
      resolved = 'cursorLeft';
      expect(press(LogicalKeyboardKey.arrowLeft), KeyEventResult.handled);
      expect(_show(c), '(a|\n)');
    });
  });

  group('keyboard commands', () {
    bool run(String id, EditorSurfaceController c, [_Host? host]) =>
        runEditorCommand(id, c, host ?? _Host(c));

    test('cursor moves, with and without selecting', () {
      final c = _controller('  foo bar\nbaz', selections: [_at(6)]);
      expect(run('cursorLeft', c), isTrue);
      expect(_show(c), '  foo| bar\nbaz');
      expect(run('cursorRightSelect', c), isTrue);
      expect(_show(c), '  foo[ ]bar\nbaz');
      expect(run('cancelSelection', c), isTrue);
      expect(_show(c), '  foo |bar\nbaz');
      expect(run('cursorHome', c), isTrue);
      expect(_show(c), '  |foo bar\nbaz');
      expect(run('cursorLineStart', c), isTrue);
      expect(_show(c), '|  foo bar\nbaz');
      expect(run('cursorLineEndSelect', c), isTrue);
      expect(_show(c), '[  foo bar]\nbaz');
      expect(run('cursorBottom', c), isTrue);
      expect(_show(c), '  foo bar\nbaz|');
      expect(run('cursorUp', c), isTrue);
      expect(_show(c), '  f|oo bar\nbaz');
      expect(run('cursorWordLeft', c), isTrue);
      expect(_show(c), '  |foo bar\nbaz');
      expect(run('cursorWordRightSelect', c), isTrue);
      expect(_show(c), '  [foo] bar\nbaz');
      expect(run('cursorTopSelect', c), isTrue);
      expect(c.value.selection, _range(2, 0));
    });

    test('deletion and line breaks', () {
      final c = _controller('ab cd', selections: [_at(1)]);
      expect(run('deleteRight', c), isTrue);
      expect(_show(c), 'a| cd');
      expect(run('deleteLeft', c), isTrue);
      expect(_show(c), '| cd');
      expect(run('lineBreakInsert', c), isTrue);
      expect(_show(c), '|\n cd');
      c.select(5, 5);
      expect(run('deleteWordLeft', c), isTrue);
      expect(_show(c), '\n |');
      final readOnly = _Host(c)..editable = false;
      expect(run('deleteLeft', c, readOnly), isFalse);
      expect(c.value.text, '\n ');
    });

    test('scrolling moves the view, not the caret', () {
      final c = _controller('a\nb\nc', selections: [_at(0)]);
      final host = _Host(c);
      expect(run('scrollLineDown', c, host), isTrue);
      expect(run('scrollPageUp', c, host), isTrue);
      expect(host.scrolledRows, 1 - host.pageRowCount);
      expect(_show(c), '|a\nb\nc');
    });

    test('snippet placeholders: next, previous, leave', () {
      final c = _controller('', selections: [_at(0)]);
      c.insertSnippet(r'f(${1:a}, ${2:b})$0');
      expect(_show(c), 'f([a], b)');
      expect(run('jumpToNextSnippetPlaceholder', c), isTrue);
      expect(_show(c), 'f(a, [b])');
      expect(run('jumpToPrevSnippetPlaceholder', c), isTrue);
      expect(_show(c), 'f([a], b)');
      expect(run('leaveSnippet', c), isTrue);
      expect(c.inSnippetMode, isFalse);
    });

    test('editor.action.joinLines', () {
      final c = _controller('a\n  b\nc', selections: [_at(0)]);
      expect(run('editor.action.joinLines', c), isTrue);
      expect(c.value.text, 'a b\nc');
      expect(_show(c), 'a| b\nc');
      // A selection joins the lines it spans.
      final d = _controller('a\nb\nc\nd', selections: [_range(0, 5)]);
      expect(run('editor.action.joinLines', d), isTrue);
      expect(d.value.text, 'a b c\nd');
      expect(d.document.canUndo, isTrue);
    });

    test('editor.action.duplicateSelection', () {
      final c = _controller('ab\ncd', selections: [_range(0, 1)]);
      expect(run('editor.action.duplicateSelection', c), isTrue);
      expect(_show(c), 'a[a]b\ncd');
      // A caret duplicates its line.
      final d = _controller('ab\ncd', selections: [_at(1)]);
      expect(run('editor.action.duplicateSelection', d), isTrue);
      expect(d.value.text, 'ab\nab\ncd');
      expect(d.value.selection.baseOffset, 4);
    });

    test('editor.action.insertCursorAtEndOfEachLineSelected', () {
      final c = _controller('ab\ncd\nef', selections: [_range(0, 7)]);
      expect(
        run('editor.action.insertCursorAtEndOfEachLineSelected', c),
        isTrue,
      );
      expect(_show(c), 'ab|\ncd|\ne|f');
    });

    test('smart select expands and shrinks', () {
      final c = _controller('foo(bar, baz)', selections: [_at(5)]);
      expect(run('editor.action.smartSelect.expand', c), isTrue);
      expect(_show(c), 'foo([bar], baz)');
      expect(run('editor.action.smartSelect.grow', c), isTrue);
      expect(_show(c), 'foo([bar, baz])');
      expect(run('editor.action.smartSelect.shrink', c), isTrue);
      expect(_show(c), 'foo([bar], baz)');
    });

    test('symbol highlights: next and previous, revealed', () {
      final c = _controller('foo x foo y foo', selections: [_at(1)]);
      final host = _Host(c);
      expect(run('editor.action.wordHighlight.next', c, host), isTrue);
      expect(c.value.selection, _at(6));
      expect(host.revealed.last, (6, 9));
      expect(run('editor.action.wordHighlight.prev', c, host), isTrue);
      expect(c.value.selection, _at(0));
    });

    test('folding commands act on the view\'s folding model', () {
      const text = 'a {\n  b\n  c\n}\nd {\n  e\n  f\n}';
      final c = _controller(text, selections: [_at(6)]);
      final host = _Host(c);
      // Without folding there is nothing to fold.
      expect(run('editor.fold', c, host), isFalse);
      final model = host.folding = EditorFoldingModel()
        ..updateSnapshot(c.document.snapshot)
        ..recompute(tabSize: 4);
      expect(model.regions.length, 2);
      expect(run('editor.fold', c, host), isTrue);
      expect(model.isCollapsedAt(1), isTrue);
      expect(model.isCollapsedAt(5), isFalse);
      expect(host.foldingChanges, 1);
      expect(run('editor.unfold', c, host), isTrue);
      expect(model.hasCollapsed, isFalse);
      expect(run('editor.toggleFold', c, host), isTrue);
      expect(model.isCollapsedAt(1), isTrue);
      expect(run('editor.unfoldAll', c, host), isTrue);
      expect(run('editor.foldAll', c, host), isTrue);
      expect(model.isCollapsedAt(1) && model.isCollapsedAt(5), isTrue);
      expect(run('editor.unfoldAll', c, host), isTrue);
      expect(run('editor.foldAllExcept', c, host), isTrue);
      expect(model.isCollapsedAt(1), isFalse);
      expect(model.isCollapsedAt(5), isTrue);
      expect(run('editor.unfoldAll', c, host), isTrue);
      // Fold Level 1 leaves the region with the caret, as upstream.
      expect(run('editor.foldLevel1', c, host), isTrue);
      expect(model.isCollapsedAt(1), isFalse);
      expect(model.isCollapsedAt(5), isTrue);
      expect(run('editor.foldAll', c, host), isTrue);
      // Nothing changes: false, and the view is left alone.
      final changes = host.foldingChanges;
      expect(run('editor.foldAll', c, host), isFalse);
      expect(host.foldingChanges, changes);
    });

    test('marker regions and block comments fold by the language', () async {
      final language = await _language('typescript');
      const text =
          '/*\n * doc\n */\n'
          'function f() {\n  return 1;\n}\n'
          '//#region r\nlet x;\n//#endregion\n';
      final c = _controller(text, language: language, selections: [_at(0)]);
      final host = _Host(c);
      final model = host.folding = EditorFoldingModel()
        ..updateSnapshot(c.document.snapshot)
        ..recompute(tabSize: 4, rules: language.folding);
      expect(run('editor.foldAllBlockComments', c, host), isTrue);
      expect(model.isCollapsedAt(1), isTrue);
      expect(model.isCollapsedAt(4), isFalse);
      expect(run('editor.foldAllMarkerRegions', c, host), isTrue);
      expect(model.isCollapsedAt(7), isTrue);
      expect(run('editor.unfoldAllMarkerRegions', c, host), isTrue);
      expect(model.isCollapsedAt(7), isFalse);
      expect(model.isCollapsedAt(1), isTrue);
    });
  });

  group('typing commands', () {
    test('typeOverride takes the keyboard\'s text; typeDefault does not', () {
      final c = _controller('ab', selections: [_at(1)]);
      final taken = <String>[];
      c.typeOverride = (text) {
        taken.add(text);
        return text != 'y';
      };
      c.type('x');
      expect(_show(c), 'a|b');
      c.type('y');
      expect(_show(c), 'ay|b');
      // From the platform, as the keyboard types.
      c.value = c.value.copyWith(
        text: 'ayzb',
        selection: _at(3),
        composing: TextRange.empty,
      );
      expect(taken, ['x', 'y', 'z']);
      expect(_show(c), 'ay|b');
      c.typeDefault('q');
      expect(_show(c), 'ayq|b');
    });

    test('compositionType replaces around each caret', () {
      final c = _controller('abc\ndef', selections: [_at(2), _at(6)]);
      // replacePreviousChar: one before each caret.
      c.compositionType('X', replacePrevCharCnt: 1);
      expect(_show(c), 'aX|c\ndX|f');
      c.compositionType('YZ', replaceNextCharCnt: 1, positionDelta: -1);
      expect(_show(c), 'aXY|Z\ndXY|Z');
      // A selection is left alone (a canceled composition).
      c.setSelections([_range(0, 1)]);
      c.compositionType('Q', replacePrevCharCnt: 1);
      expect(_show(c), '[a]XYZ\ndXYZ');
    });
  });
}
