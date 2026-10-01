import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/settings/jsonc.dart';

/// [text] with [path] set to [value] (or removed, or inserted) as
/// [modifyJsonc] edits it.
String modify(
  String text,
  List<Object> path,
  Object? value, {
  bool remove = false,
  bool insert = false,
  JsoncFormatting? formatting,
}) => applyJsoncEdits(
  text,
  modifyJsonc(
    text,
    path,
    value,
    remove: remove,
    insert: insert,
    formatting: formatting,
  ),
);

const twoSpaces = JsoncFormatting(tabSize: 2);

void main() {
  group('parseJsonc', () {
    test('reads comments and trailing commas', () {
      final errors = <JsoncParseError>[];
      final value = parseJsonc(
        '// Settings\n'
        '{\n'
        '  /* the theme */ "workbench.colorTheme": "Monokai", // trailing\n'
        '  "list": [1, 2.5, -3e2, true, false, null,],\n'
        '  "nested": {"a": {"b": "c\\n\\u0041"},},\n'
        '}\n',
        errors: errors,
      );
      expect(errors, isEmpty);
      expect(value, {
        'workbench.colorTheme': 'Monokai',
        'list': [1, 2.5, -300.0, true, false, null],
        'nested': {
          'a': {'b': 'c\nA'},
        },
      });
    });

    test('keeps the order written; the last of duplicate keys wins', () {
      final value = parseJsonc('{"b": 1, "a": 2, "b": 3}') as Map;
      expect(value.keys, ['b', 'a']);
      expect(value['b'], 3);
    });

    test('empty content, or only comments, is null without errors', () {
      for (final text in ['', '  \n', '// nothing\n/* here */']) {
        final errors = <JsoncParseError>[];
        expect(parseJsonc(text, errors: errors), isNull);
        expect(errors, isEmpty, reason: text);
      }
    });

    test('reports what does not parse, and reads what it can', () {
      const text = '{\n  "a": 1\n  "b": ,\n  "c": [1 2]\n';
      final errors = <JsoncParseError>[];
      final value = parseJsonc(text, errors: errors);
      expect(value, {
        'a': 1,
        'c': [1, 2],
      });
      expect(errors.map((e) => e.code), [
        JsoncErrorCode.commaExpected,
        JsoncErrorCode.valueExpected,
        JsoncErrorCode.commaExpected,
        JsoncErrorCode.closeBraceExpected,
      ]);
      expect(errors.first.message, 'Comma expected');
      expect(errors.first.location(text), (line: 3, column: 3));
      expect(errors.first.describe(text), 'Comma expected at line 3, column 3');
    });

    test('an unterminated string, comment or a stray symbol', () {
      for (final (text, code) in [
        ('{"a": "b', JsoncErrorCode.unexpectedEndOfString),
        ('{} /* open', JsoncErrorCode.unexpectedEndOfComment),
        ('{"a": x}', JsoncErrorCode.invalidSymbol),
        ('{"a": 1} 2', JsoncErrorCode.endOfFileExpected),
        ('{"a": "\\q"}', JsoncErrorCode.invalidEscapeCharacter),
      ]) {
        final errors = <JsoncParseError>[];
        parseJsonc(text, errors: errors);
        expect(errors.map((e) => e.code), contains(code), reason: text);
      }
    });

    test('a byte order mark is whitespace', () {
      expect(parseJsonc('﻿{"a": 1}'), {'a': 1});
    });

    test('the tree knows where each value is', () {
      const text = '{"a": [10, {"b": true}]}';
      final root = parseJsoncTree(text)!;
      final node = root.find(['a', 1, 'b'])!;
      expect(text.substring(node.offset, node.end), 'true');
      expect(root.find(['a', 5]), isNull);
      expect(root.find(['x']), isNull);
    });
  });

  group('modifyJsonc sets', () {
    test('an existing value in place, comments kept', () {
      const text =
          '{\n'
          '  // The theme.\n'
          '  "workbench.colorTheme": "Dark 2026", // was light\n'
          '  "editor.fontSize": 13\n'
          '}';
      expect(
        modify(text, ['workbench.colorTheme'], 'Monokai'),
        '{\n'
        '  // The theme.\n'
        '  "workbench.colorTheme": "Monokai", // was light\n'
        '  "editor.fontSize": 13\n'
        '}',
      );
    });

    test('a new property after the last one, on a line of its own', () {
      const text =
          '{\n'
          '    "a": 1 // one\n'
          '    // The end.\n'
          '}\n';
      expect(
        modify(text, ['b'], {'c': true}),
        '{\n'
        '    "a": 1, // one\n'
        '    // The end.\n'
        '    "b": {\n'
        '        "c": true\n'
        '    }\n'
        '}\n',
      );
    });

    test('keeps a trailing comma where there was one', () {
      expect(modify('{\n  "a": 1,\n}', ['b'], 2), '{\n  "a": 1,\n  "b": 2,\n}');
    });

    test('in an empty file, a file of comments, `{}` and `{\\n}`', () {
      expect(modify('', ['a'], 1), '{\n    "a": 1\n}');
      expect(
        modify('// Settings\n', ['a'], 1),
        '// Settings\n{\n    "a": 1\n}',
      );
      expect(modify('{}', ['a'], 1), '{\n    "a": 1\n}');
      expect(modify('{\n}\n', ['a'], 1), '{\n    "a": 1\n}\n');
      expect(
        modify('{\n\t// comment\n}', ['a'], 'x'),
        '{\n\t// comment\n\t"a": "x"\n}',
      );
    });

    test('nested objects, created on the way', () {
      const text = '{\n  "a": {\n    "b": 1\n  }\n}';
      expect(
        modify(text, ['a', 'c'], 2),
        '{\n  "a": {\n    "b": 1,\n    "c": 2\n  }\n}',
      );
      expect(
        modify(text, ['x', 'y'], [1]),
        '{\n  "a": {\n    "b": 1\n  },\n  "x": {\n    "y": [\n      1\n    ]\n  }\n}',
      );
    });

    test('a value in a single-line object lays that line out', () {
      expect(
        modify('{"a": 1}', ['b'], 2, formatting: twoSpaces),
        '{\n  "a": 1,\n  "b": 2\n}',
      );
    });

    test('the last of duplicate keys', () {
      expect(modify('{"a": 1, "a": 2}', ['a'], 3), '{"a": 1, "a": 3}');
    });

    test('keeps \\r\\n line breaks', () {
      expect(
        modify('{\r\n  "a": 1\r\n}\r\n', ['b'], 2),
        '{\r\n  "a": 1,\r\n  "b": 2\r\n}\r\n',
      );
    });

    test('through something else throws', () {
      expect(
        () => modifyJsonc('[]', ['a'], 1),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => modifyJsonc('{"a": 1}', ['a', 'b'], 1),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('modifyJsonc removes', () {
    test('a property with its line and trailing comment', () {
      const text =
          '{\n'
          '  // About a.\n'
          '  "a": 1, // one\n'
          '  "b": 2 // two\n'
          '}';
      expect(
        modify(text, ['a'], null, remove: true),
        '{\n  // About a.\n  "b": 2 // two\n}',
      );
      expect(
        modify(text, ['b'], null, remove: true),
        '{\n  // About a.\n  "a": 1 // one\n}',
      );
    });

    test('the last element of an array, and the only one', () {
      const text = '[\n  1,\n  2\n]';
      expect(modify(text, [1], null, remove: true), '[\n  1\n]');
      expect(modify('[\n  1\n]', [0], null, remove: true), '[\n]');
      expect(modify('[1, 2, 3]', [2], null, remove: true), '[1, 2]');
      expect(modify('[1, 2, 3]', [0], null, remove: true), '[2, 3]');
      expect(modify('[1, 2, 3]', [1], null, remove: true), '[1, 3]');
      expect(modify('[ 1 ]', [0], null, remove: true), '[]');
      expect(modify('{"a": 1}', ['a'], null, remove: true), '{}');
      expect(
        modify('[1, /* two */ 2]', [1], null, remove: true),
        '[1 /* two */]',
      );
    });

    test('an element spanning lines, trailing comma and all', () {
      const text =
          '[\n'
          '  {\n'
          '    "key": "cmd+a"\n'
          '  },\n'
          '  // Mine.\n'
          '  {\n'
          '    "key": "cmd+b"\n'
          '  },\n'
          ']\n';
      expect(
        modify(text, [0], null, remove: true),
        '[\n  // Mine.\n  {\n    "key": "cmd+b"\n  },\n]\n',
      );
      expect(
        modify(text, [1], null, remove: true),
        '[\n  {\n    "key": "cmd+a"\n  },\n  // Mine.\n]\n',
      );
    });

    test('nothing when it is not there', () {
      expect(modifyJsonc('{"a": 1}', ['b'], null, remove: true), isEmpty);
      expect(modifyJsonc('[1]', [3], null, remove: true), isEmpty);
      expect(modifyJsonc('', ['a'], null, remove: true), isEmpty);
      expect(modifyJsonc('{}', ['a', 'b'], null, remove: true), isEmpty);
    });
  });

  group('modifyJsonc inserts', () {
    test('into an empty array: `[]`, `[\\n]` and one with comments', () {
      expect(
        modify('[]', [-1], {'key': 'cmd+k', 'command': 'x'}, insert: true),
        '[\n    {\n        "key": "cmd+k",\n        "command": "x"\n    }\n]',
      );
      expect(
        modify(
          '// Keys\n[\n]\n',
          [0],
          {'key': 'a'},
          insert: true,
          formatting: twoSpaces,
        ),
        '// Keys\n[\n  {\n    "key": "a"\n  }\n]\n',
      );
      expect(
        modify(
          '[\n  // Place your key bindings here\n]',
          [-1],
          {'key': 'a'},
          insert: true,
        ),
        '[\n  // Place your key bindings here\n  {\n    "key": "a"\n  }\n]',
      );
    });

    test('appends after the last element, at its indentation', () {
      const text = '[\n  {\n    "key": "a"\n  } // first\n]';
      expect(
        modify(text, [1], {'key': 'b'}, insert: true),
        '[\n  {\n    "key": "a"\n  }, // first\n  {\n    "key": "b"\n  }\n]',
      );
      expect(
        modify(text, [-1], 'x', insert: true),
        '[\n  {\n    "key": "a"\n  }, // first\n  "x"\n]',
      );
    });

    test('before an element', () {
      expect(
        modify('[\n  1,\n  2\n]', [1], 5, insert: true),
        '[\n  1,\n  5,\n  2\n]',
      );
      expect(modify('[1, 2]', [0], 5, insert: true), '[5, 1, 2]');
    });

    test('a set index past the end appends; one inside replaces', () {
      expect(modify('[\n  1\n]', [4], 2), '[\n  1,\n  2\n]');
      expect(modify('[\n  1\n]', [0], 2), '[\n  2\n]');
    });

    test('in an empty file, as the first segment says', () {
      expect(modify('', [-1], 1, insert: true), '[\n    1\n]');
    });
  });

  test('applyJsoncEdits makes edits in any order, and refuses overlaps', () {
    expect(
      applyJsoncEdits('abcdef', const [
        JsoncEdit(4, 1, 'E'),
        JsoncEdit(0, 1, 'A'),
        JsoncEdit(2, 0, '-'),
        JsoncEdit(2, 0, '+'),
      ]),
      'Ab-+cdEf',
    );
    expect(
      () => applyJsoncEdits('abc', const [
        JsoncEdit(0, 2, ''),
        JsoncEdit(1, 1, ''),
      ]),
      throwsArgumentError,
    );
  });

  test('JsoncFormatting.detect', () {
    final tabs = JsoncFormatting.detect('{\n\t"a": {\n\t\t"b": 1\n\t}\n}');
    expect(tabs.insertSpaces, isFalse);
    final two = JsoncFormatting.detect(
      '{\r\n  "a": {\r\n    "b": 1\r\n  }\r\n}',
    );
    expect((two.insertSpaces, two.tabSize, two.eol), (true, 2, '\r\n'));
    final none = JsoncFormatting.detect('{}');
    expect((none.insertSpaces, none.tabSize, none.eol), (true, 4, '\n'));
    final comment = JsoncFormatting.detect('/*\n * x\n */\n{\n    "a": 1\n}');
    expect(comment.tabSize, 4);
  });

  test('an edit is one, and none when nothing changes', () {
    expect(modifyJsonc('{"a": 1}', ['a'], 1), isEmpty);
    expect(modifyJsonc('{"a": 1}', ['a'], 2), [const JsoncEdit(6, 1, '2')]);
  });
}
