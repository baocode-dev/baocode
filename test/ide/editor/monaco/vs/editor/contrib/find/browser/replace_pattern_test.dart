/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Adapted from pinned VS Code src/vs/editor/contrib/find/test/browser/
// replacePattern.test.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// RegExpMatch.group can be null for an unmatched capture (JS: undefined).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/contrib/find/browser/replace_pattern.dart';

List<String?>? _matches(String target, RegExp search) {
  final match = search.firstMatch(target);
  if (match == null) return null;
  return [for (var i = 0; i <= match.groupCount; i++) match.group(i)];
}

void _assertParse(String input, List<ReplacePiece> expectedPieces) {
  final actual = parseReplaceString(input);
  final expected = ReplacePattern(expectedPieces);
  expect(
    actual.hasReplacementPatterns,
    expected.hasReplacementPatterns,
    reason: 'Parsing $input',
  );
  // The upstream assertion compares the internal pieces and static/dynamic
  // discriminant, not just the resulting replacement string.
  if (!expected.hasReplacementPatterns) {
    expect(
      actual.buildReplaceString(null),
      expected.buildReplaceString(null),
      reason: 'Parsing $input',
    );
    return;
  }
  // Distinct captures (including two-digit indices) expose the ordering,
  // indices, static pieces and copied case-operation lists.
  final captures = <String?>['full', for (var i = 1; i < 100; i++) 'aB$i'];
  expect(
    actual.buildReplaceString(captures),
    expected.buildReplaceString(captures),
    reason: 'Parsing $input',
  );
}

void _assertReplace(
  String target,
  RegExp search,
  String replaceString,
  String expected,
) {
  expect(
    parseReplaceString(replaceString)
        .buildReplaceString(_matches(target, search)),
    expected,
    reason: '$target / ${search.pattern} / $replaceString',
  );
}

void main() {
  group('Replace Pattern test (pinned VS Code)', () {
    test('parse replace string', () {
      _assertParse('hello', [ReplacePiece.staticValue('hello')]);
      _assertParse(r'\thello', [ReplacePiece.staticValue('\thello')]);
      _assertParse(r'h\tello', [ReplacePiece.staticValue('h\tello')]);
      _assertParse(r'hello\t', [ReplacePiece.staticValue('hello\t')]);
      _assertParse(r'\nhello', [ReplacePiece.staticValue('\nhello')]);
      _assertParse(r'\\thello', [ReplacePiece.staticValue(r'\thello')]);
      _assertParse(r'h\\tello', [ReplacePiece.staticValue(r'h\tello')]);
      _assertParse(r'hello\\t', [ReplacePiece.staticValue(r'hello\t')]);
      _assertParse(r'\\\thello', [ReplacePiece.staticValue('\\\thello')]);
      _assertParse(r'\\\\thello', [ReplacePiece.staticValue(r'\\thello')]);
      _assertParse('hello\\', [ReplacePiece.staticValue('hello\\')]);
      _assertParse(r'hello\x', [ReplacePiece.staticValue(r'hello\x')]);
      _assertParse(r'hello\0', [ReplacePiece.staticValue(r'hello\0')]);
      _assertParse(r'hello$&', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(0),
      ]);
      _assertParse(r'hello$0', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(0),
      ]);
      _assertParse(r'hello$02', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(0),
        ReplacePiece.staticValue('2'),
      ]);
      _assertParse(r'hello$1', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(1),
      ]);
      _assertParse(r'hello$2', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(2),
      ]);
      _assertParse(r'hello$9', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(9),
      ]);
      _assertParse(r'$9hello', [
        ReplacePiece.matchIndex(9),
        ReplacePiece.staticValue('hello'),
      ]);
      _assertParse(r'hello$12', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(12),
      ]);
      _assertParse(r'hello$99', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(99),
      ]);
      _assertParse(r'hello$99a', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(99),
        ReplacePiece.staticValue('a'),
      ]);
      _assertParse(r'hello$1a', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(1),
        ReplacePiece.staticValue('a'),
      ]);
      _assertParse(r'hello$100', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(10),
        ReplacePiece.staticValue('0'),
      ]);
      _assertParse(r'hello$100a', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(10),
        ReplacePiece.staticValue('0a'),
      ]);
      _assertParse(r'hello$10a0', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(10),
        ReplacePiece.staticValue('a0'),
      ]);
      _assertParse(r'hello$$', [ReplacePiece.staticValue(r'hello$')]);
      _assertParse(r'hello$$0', [ReplacePiece.staticValue(r'hello$0')]);
      _assertParse(r'hello$`', [ReplacePiece.staticValue(r'hello$`')]);
      _assertParse("hello\$'", [ReplacePiece.staticValue("hello\$'")]);
    });

    test('parse replace string with case modifiers', () {
      _assertParse(r'hello\U$1', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.caseOps(1, ['U']),
      ]);
      _assertReplace(
        'func privateFunc(',
        RegExp(r'func (\w+)\('),
        r'func \U$1(',
        'func PRIVATEFUNC(',
      );
      _assertParse(r'hello\u$1', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.caseOps(1, ['u']),
      ]);
      _assertReplace(
        'func privateFunc(',
        RegExp(r'func (\w+)\('),
        r'func \u$1(',
        'func PrivateFunc(',
      );
      _assertParse(r'hello\L$1', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.caseOps(1, ['L']),
      ]);
      _assertReplace(
        'func privateFunc(',
        RegExp(r'func (\w+)\('),
        r'func \L$1(',
        'func privatefunc(',
      );
      _assertParse(r'hello\l$1', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.caseOps(1, ['l']),
      ]);
      _assertReplace(
        'func PrivateFunc(',
        RegExp(r'func (\w+)\('),
        r'func \l$1(',
        'func privateFunc(',
      );
      _assertParse(r'hello$1\u\u\U$4goodbye', [
        ReplacePiece.staticValue('hello'),
        ReplacePiece.matchIndex(1),
        ReplacePiece.caseOps(4, ['u', 'u', 'U']),
        ReplacePiece.staticValue('goodbye'),
      ]);
      _assertReplace(
        'hellogooDbye',
        RegExp(r'hello(\w+)'),
        r'hello\u\u\l\l\U$1',
        'helloGOodBYE',
      );
    });

    test('replace has JavaScript semantics', () {
      _assertReplace('hi', RegExp('hi'), 'hello', 'hello');
      _assertReplace('hi', RegExp('hi'), r'\t', '\t');
      _assertReplace('hi', RegExp('hi'), r'\n', '\n');
      _assertReplace('hi', RegExp('hi'), r'\\t', r'\t');
      _assertReplace('hi', RegExp('hi'), r'\\n', r'\n');
      _assertReplace('hi', RegExp('hi'), r'hello$&', 'hellohi');
      _assertReplace('hi', RegExp('hi'), r'hello$0', 'hellohi');
      _assertReplace('hi', RegExp('hi'), r'hello$&1', 'hellohi1');
      _assertReplace('hi', RegExp('hi'), r'hello$01', 'hellohi1');
      _assertReplace('hi', RegExp(r'(hi)'), r'hello$10', 'hellohi0');
      _assertReplace(
        'hi',
        RegExp(r'(hi)()()()()()()()()()'),
        r'hello$10',
        'hello',
      );
      _assertReplace('hi', RegExp(r'(hi)'), r'hello$100', 'hellohi00');
      _assertReplace('hi', RegExp(r'(hi)'), r'hello$20', r'hello$20');
    });

    test('get replace string if given text is a complete match', () {
      _assertReplace('bla', RegExp('bla'), 'hello', 'hello');
      _assertReplace('bla', RegExp('(bla)'), 'hello', 'hello');
      _assertReplace('bla', RegExp('(bla)'), r'hello$0', 'hellobla');
      final search = RegExp(
        r'''let\s+(\w+)\s*=\s*require\s*\(\s*['"]([\w.\-/]+)\s*['"]\s*\)\s*''',
      );
      _assertReplace(
        "let fs = require('fs')",
        search,
        "import * as \$1 from '\$2';",
        "import * as fs from 'fs';",
      );
      _assertReplace(
        "let something = require('fs')",
        search,
        "import * as \$1 from '\$2';",
        "import * as something from 'fs';",
      );
      _assertReplace(
        "let something = require('fs')",
        search,
        "import * as \$1 from '\$1';",
        "import * as something from 'something';",
      );
      _assertReplace(
        "let something = require('fs')",
        search,
        "import * as \$2 from '\$1';",
        "import * as fs from 'something';",
      );
      _assertReplace(
        "let something = require('fs')",
        search,
        "import * as \$0 from '\$0';",
        "import * as let something = require('fs') from 'let something = require('fs')';",
      );
      _assertReplace(
        "let fs = require('fs')",
        search,
        "import * as \$1 from '\$2';",
        "import * as fs from 'fs';",
      );
      _assertReplace('for ()', RegExp(r'for(.*)'), r'cat$1', 'cat ()');
      _assertReplace(
        'HRESULT OnAmbientPropertyChange(DISPID   dispid);',
        RegExp(r'\b\s{3}\b'),
        ' ',
        ' ',
      );
    });

    test('get replace string if match is sub-string of the text', () {
      final target = 'this is a bla text';
      _assertReplace(target, RegExp('bla'), 'hello', 'hello');
      _assertReplace(target, RegExp(r'this(?=.*bla)'), 'that', 'that');
      final first = RegExp(r'(th)is(?=.*bla)');
      _assertReplace(target, first, r'$1at', 'that');
      _assertReplace(target, first, r'$1e', 'the');
      _assertReplace(target, first, r'$1ere', 'there');
      _assertReplace(target, first, r'$1', 'th');
      _assertReplace(target, first, r'ma$1', 'math');
      _assertReplace(target, first, r'ma$1s', 'maths');
      _assertReplace(target, first, r'$0', 'this');
      _assertReplace(target, first, r'$0$1', 'thisth');
      final last = RegExp(r'b(la)(?=\stext$)');
      _assertReplace(target, RegExp(r'bla(?=\stext$)'), 'foo', 'foo');
      _assertReplace(target, last, r'f$1', 'fla');
      _assertReplace(target, last, r'f$0', 'fbla');
      _assertReplace(target, last, r'$0ah', 'blaah');
    });

    test('issue #19740: unmatched capture is empty rather than undefined', () {
      _assertReplace('abcd', RegExp(r'a(z)?'), r'a{$1}', 'a{}');
    });

    const preserveCases = <(List<String?>, String, String)>[
      (['abc'], 'Def', 'def'),
      (['Abc'], 'Def', 'Def'),
      (['ABC'], 'Def', 'DEF'),
      (['abc', 'Abc'], 'Def', 'def'),
      (['Abc', 'abc'], 'Def', 'Def'),
      (['ABC', 'abc'], 'Def', 'DEF'),
      (['aBc', 'abc'], 'Def', 'def'),
      (['AbC'], 'Def', 'Def'),
      (['aBC'], 'Def', 'def'),
      (['aBc'], 'DeF', 'deF'),
      (['Foo-Bar'], 'newfoo-newbar', 'Newfoo-Newbar'),
      (['Foo-Bar-Abc'], 'newfoo-newbar-newabc', 'Newfoo-Newbar-Newabc'),
      (['Foo-Bar-abc'], 'newfoo-newbar', 'Newfoo-newbar'),
      (['foo-Bar'], 'newfoo-newbar', 'newfoo-Newbar'),
      (['foo-BAR'], 'newfoo-newbar', 'newfoo-NEWBAR'),
      (['foO-BAR'], 'NewFoo-NewBar', 'newFoo-NEWBAR'),
      (['Foo_Bar'], 'newfoo_newbar', 'Newfoo_Newbar'),
      (['Foo_Bar_Abc'], 'newfoo_newbar_newabc', 'Newfoo_Newbar_Newabc'),
      (['Foo_Bar_abc'], 'newfoo_newbar', 'Newfoo_newbar'),
      (['Foo_Bar-abc'], 'newfoo_newbar-abc', 'Newfoo_newbar-abc'),
      (['foo_Bar'], 'newfoo_newbar', 'newfoo_Newbar'),
      (['Foo_BAR'], 'newfoo_newbar', 'Newfoo_NEWBAR'),
    ];

    test('buildReplaceStringWithCasePreserved test', () {
      for (final (matches, replacement, expected) in preserveCases) {
        expect(
          buildReplaceStringWithCasePreserved(matches, replacement),
          expected,
          reason: '$matches / $replacement',
        );
      }
    });

    test('preserve case', () {
      for (final (matches, replacement, expected) in preserveCases) {
        expect(
          parseReplaceString(replacement).buildReplaceString(matches, true),
          expected,
          reason: '$matches / $replacement',
        );
      }
      expect(
        parseReplaceString('replacement').buildReplaceString(null, true),
        'replacement',
      );
      expect(
        parseReplaceString(r'\U$1').buildReplaceString(['abc', 'mixed'], true),
        'MIXED',
      );
    });

    test(
      'empty, no match, and unsupported tokens retain upstream behavior',
      () {
        expect(parseReplaceString('').hasReplacementPatterns, isFalse);
        expect(
          ReplacePattern.fromStaticValue(r'$1').buildReplaceString(['a', 'b']),
          r'$1',
        );
        expect(parseReplaceString(r'$1').buildReplaceString(null), '');
        expect(parseReplaceString(r'$1').buildReplaceString(['a']), r'$1');
        expect(parseReplaceString(r'$1').buildReplaceString(['a', null]), '');
        expect(parseReplaceString(r'$0').buildReplaceString(null), '');
        expect(parseReplaceString(r'$&').buildReplaceString(['a']), 'a');
        expect(
          parseReplaceString(r'$20').buildReplaceString(['a', 'b']),
          r'$20',
        );
        expect(parseReplaceString(r'$12').buildReplaceString(['a', 'b']), 'b2');
        expect(parseReplaceString(r'$19').buildReplaceString(['a', 'b']), 'b9');
        expect(
          parseReplaceString(r'\u\u\U$1').buildReplaceString(['a', 'abCd']),
          'ABCD',
        );
        expect(
          parseReplaceString(r'\E$1').buildReplaceString(['a', 'b']),
          r'\Eb',
        );
        expect(parseReplaceString(r'\uend').buildReplaceString(['a']), 'end');
        expect(
          parseReplaceString(r'$$$1').buildReplaceString(['a', 'b']),
          r'$b',
        );
        final ops = ['u'];
        final piece = ReplacePiece.caseOps(1, ops);
        ops.add('U');
        expect(piece.caseOps, ['u']);
      },
    );
  });
}
