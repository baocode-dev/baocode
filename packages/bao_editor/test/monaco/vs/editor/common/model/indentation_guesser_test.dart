/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../../lib/monaco/LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/test/common/model/textModel.test.ts
// (guess indentation tests) at 6a598d4a13031703d483d103c1d934a36ad27971.

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/editor/common/model/indentation_guesser.dart';

void _testGuess(
  bool defaultInsertSpaces,
  int defaultTabSize,
  bool expectedInsertSpaces,
  int expectedTabSize,
  List<String> text,
  String? msg,
) {
  final lines = text.join('\n').split('\n');
  final r = guessIndentation(
    lines.length,
    (lineNumber) => lines[lineNumber - 1],
    defaultTabSize,
    defaultInsertSpaces,
  );
  expect(r.insertSpaces, expectedInsertSpaces, reason: msg);
  expect(r.tabSize, expectedTabSize, reason: msg);
}

/// [expectedTabSize] is null (cannot guess), an int, or a one-element list
/// (can only guess when inserting spaces).
void _assertGuess(
  bool? expectedInsertSpaces,
  Object? expectedTabSize,
  List<String> text, [
  String? msg,
]) {
  final onlySpaces = expectedTabSize is List ? expectedTabSize[0] as int : null;
  final size = expectedTabSize is int ? expectedTabSize : null;
  if (expectedInsertSpaces == null) {
    _testGuess(true, 13370, true, size ?? onlySpaces ?? 13370, text, msg);
    _testGuess(false, 13371, false, size ?? 13371, text, msg);
  } else if (onlySpaces != null && !expectedInsertSpaces) {
    _testGuess(true, 13370, false, 13370, text, msg);
    _testGuess(false, 13371, false, 13371, text, msg);
  } else {
    _testGuess(
      true,
      13370,
      expectedInsertSpaces,
      size ?? onlySpaces ?? 13370,
      text,
      msg,
    );
    _testGuess(
      false,
      13371,
      expectedInsertSpaces,
      size ?? onlySpaces ?? 13371,
      text,
      msg,
    );
  }
}

void main() {
  test('guess indentation 1', () {
    _assertGuess(null, null, ['x', 'x', 'x', 'x', 'x', 'x', 'x'], 'no clues');
    _assertGuess(false, null, [
      '\tx',
      'x',
      'x',
      'x',
      'x',
      'x',
      'x',
    ], 'no spaces, 1xTAB');
    _assertGuess(true, 2, ['  x', 'x', 'x', 'x', 'x', 'x', 'x'], '1x2');
    _assertGuess(false, null, [
      '\tx',
      '\tx',
      '\tx',
      '\tx',
      '\tx',
      '\tx',
      '\tx',
    ], '7xTAB');
    _assertGuess(
      null,
      [2],
      ['\tx', '  x', '\tx', '  x', '\tx', '  x', '\tx', '  x'],
      '4x2, 4xTAB',
    );
    _assertGuess(false, null, [
      '\tx',
      ' x',
      '\tx',
      ' x',
      '\tx',
      ' x',
      '\tx',
      ' x',
    ], '4x1, 4xTAB');
    _assertGuess(false, null, [
      '\tx',
      '\tx',
      '  x',
      '\tx',
      '  x',
      '\tx',
      '  x',
      '\tx',
      '  x',
    ], '4x2, 5xTAB');
    _assertGuess(false, null, [
      '\tx',
      '\tx',
      'x',
      '\tx',
      'x',
      '\tx',
      'x',
      '\tx',
      '  x',
    ], '1x2, 5xTAB');
    _assertGuess(false, null, [
      '\tx',
      '\tx',
      'x',
      '\tx',
      'x',
      '\tx',
      'x',
      '\tx',
      '    x',
    ], '1x4, 5xTAB');
    _assertGuess(false, null, [
      '\tx',
      '\tx',
      'x',
      '\tx',
      'x',
      '\tx',
      '  x',
      '\tx',
      '    x',
    ], '1x2, 1x4, 5xTAB');
    _assertGuess(null, null, [
      'x',
      ' x',
      ' x',
      ' x',
      ' x',
      ' x',
      ' x',
      ' x',
    ], '7x1 - 1 space is never guessed as an indentation');
    _assertGuess(true, null, [
      'x',
      '          x',
      ' x',
      ' x',
      ' x',
      ' x',
      ' x',
      ' x',
    ], '1x10, 6x1');
    _assertGuess(null, null, [
      '',
      '  ',
      '    ',
      '      ',
      '        ',
      '          ',
      '            ',
      '              ',
    ], 'whitespace lines don\'t count');
    _assertGuess(true, 3, [
      'x',
      '   x',
      '   x',
      '    x',
      'x',
      '   x',
      '   x',
      '    x',
      'x',
      '   x',
      '   x',
      '    x',
    ], '6x3, 3x4');
    _assertGuess(true, 5, [
      'x',
      '     x',
      '     x',
      '    x',
      'x',
      '     x',
      '     x',
      '    x',
      'x',
      '     x',
      '     x',
      '    x',
    ], '6x5, 3x4');
    _assertGuess(true, 7, [
      'x',
      '       x',
      '       x',
      '     x',
      'x',
      '       x',
      '       x',
      '    x',
      'x',
      '       x',
      '       x',
      '    x',
    ], '6x7, 1x5, 2x4');
    _assertGuess(true, 2, [
      'x',
      '  x',
      '  x',
      '  x',
      '  x',
      'x',
      '  x',
      '  x',
      '  x',
      '  x',
    ], '8x2');
    _assertGuess(true, 2, [
      'x',
      '  x',
      '  x',
      'x',
      '  x',
      '  x',
      'x',
      '  x',
      '  x',
      'x',
      '  x',
      '  x',
    ], '8x2');
    _assertGuess(true, 2, [
      'x',
      '  x',
      '    x',
      'x',
      '  x',
      '    x',
      'x',
      '  x',
      '    x',
      'x',
      '  x',
      '    x',
    ], '4x2, 4x4');
    _assertGuess(true, 2, [
      'x',
      '  x',
      '  x',
      '    x',
      'x',
      '  x',
      '  x',
      '    x',
      'x',
      '  x',
      '  x',
      '    x',
    ], '6x2, 3x4');
    _assertGuess(true, 2, [
      'x',
      '  x',
      '  x',
      '    x',
      '    x',
      'x',
      '  x',
      '  x',
      '    x',
      '    x',
    ], '4x2, 4x4');
    _assertGuess(true, 2, [
      'x',
      '  x',
      '    x',
      '    x',
      'x',
      '  x',
      '    x',
      '    x',
    ], '2x2, 4x4');
    _assertGuess(true, 4, [
      'x',
      '    x',
      '    x',
      'x',
      '    x',
      '    x',
      'x',
      '    x',
      '    x',
      'x',
      '    x',
      '    x',
    ], '8x4');
    _assertGuess(true, 2, [
      'x',
      '  x',
      '    x',
      '    x',
      '      x',
      'x',
      '  x',
      '    x',
      '    x',
      '      x',
    ], '2x2, 4x4, 2x6');
    _assertGuess(true, 2, [
      'x',
      '  x',
      '    x',
      '    x',
      '      x',
      '      x',
      '        x',
    ], '1x2, 2x4, 2x6, 1x8');
    _assertGuess(true, 4, [
      'x',
      '    x',
      '    x',
      '    x',
      '     x',
      '        x',
      'x',
      '    x',
      '    x',
      '    x',
      '     x',
      '        x',
    ], '6x4, 2x5, 2x8');
    _assertGuess(true, 4, [
      'x',
      '    x',
      '    x',
      '    x',
      '     x',
      '        x',
      '        x',
    ], '3x4, 1x5, 2x8');
    _assertGuess(true, 4, [
      'x',
      'x',
      '    x',
      '    x',
      '     x',
      '        x',
      '        x',
      'x',
      'x',
      '    x',
      '    x',
      '     x',
      '        x',
      '        x',
    ], '6x4, 2x5, 4x8');
    _assertGuess(true, 3, [
      'x',
      ' x',
      ' x',
      ' x',
      ' x',
      ' x',
      'x',
      '   x',
      '    x',
      '    x',
    ], '5x1, 2x0, 1x3, 2x4');
    _assertGuess(false, null, ['\t x', ' \t x', '\tx'], 'mixed whitespace 1');
    _assertGuess(false, null, ['\tx', '\t    x'], 'mixed whitespace 2');
  });

  test('issue #44991: Wrong indentation size auto-detection', () {
    _assertGuess(true, 4, [
      'a = 10             # 0 space indent',
      'b = 5              # 0 space indent',
      'if a > 10:         # 0 space indent',
      '    a += 1         # 4 space indent      delta 4 spaces',
      '    if b > 5:      # 4 space indent',
      '        b += 1     # 8 space indent      delta 4 spaces',
      '        b += 1     # 8 space indent',
      '        b += 1     # 8 space indent',
      '# comment line 1   # 0 space indent      delta 8 spaces',
      '# comment line 2   # 0 space indent',
      '# comment line 3   # 0 space indent',
      '        b += 1     # 8 space indent      delta 8 spaces',
      '        b += 1     # 8 space indent',
      '        b += 1     # 8 space indent',
    ]);
  });

  test('issue #55818: Broken indentation detection', () {
    _assertGuess(true, 2, [
      '',
      '/* REQUIRE */',
      '',
      'const foo = require ( \'foo\' ),',
      '      bar = require ( \'bar\' );',
      '',
      '/* MY FN */',
      '',
      'function myFn () {',
      '',
      '  const asd = 1,',
      '        dsa = 2;',
      '',
      '  return bar ( foo ( asd ) );',
      '',
      '}',
      '',
      '/* EXPORT */',
      '',
      'module.exports = myFn;',
      '',
    ]);
  });

  test('issue #70832: Broken indentation detection', () {
    _assertGuess(false, null, [
      'x',
      'x',
      'x',
      'x',
      '	x',
      '		x',
      '    x',
      '		x',
      '	x',
      '		x',
      '	x',
      '	x',
      '	x',
      '	x',
      'x',
    ]);
  });

  test('issue #62143: Broken indentation detection', () {
    _assertGuess(true, 2, ['x', 'x', '  x', '  x']);
    _assertGuess(true, 2, ['x', '  - item2', '  - item3']);
  });

  test('issue #84217: Broken indentation detection', () {
    _assertGuess(true, 4, ['def main():', '    print(\'hello\')']);
    _assertGuess(true, 4, [
      'def main():',
      '    with open(\'foo\') as fp:',
      '        print(fp.read())',
    ]);
  });

  test('issue #65668: YAML file indented with 2 spaces', () {
    _assertGuess(true, 2, [
      'version: 2',
      '',
      'jobs:',
      '  build:',
      '    docker:',
      '      - circleci/golang:1.11',
      '',
      '  environment:',
      '    TEST_RESULTS: /tmp/test-results',
      '',
      '  steps:',
      '    - checkout',
      '    - run: mkdir -p \$TEST_RESULTS',
      '',
      '    - restore_cache:',
      '        keys:',
      '          - v1-pkg-cache',
      '',
      '    - run:',
      '        name: dep ensure',
      '        command: dep ensure -v',
      '',
      '    - run:',
      '        name: Run unit tests',
      '        command: |',
      '          trap "go-junit-report <\${TEST_RESULTS}/go-test.out > \${TEST_RESULTS}/go-test-report.xml" EXIT',
      '          go test -v ./... | tee \${TEST_RESULTS}/go-test.out',
      '',
      '    - run:',
      '        name: Build',
      '        command: go build -v',
      '',
      '    - save_cache:',
      '        key: v1-pkg-cache',
      '        paths:',
      '          - "/go/pkg"',
      '',
      '    - store_artifacts:',
      '        path: /tmp/test-results',
      '        destination: raw-test-output',
      '',
      '    - store_test_results:',
      '        path: /tmp/test-results',
    ]);
  });

  test(
    'issue #249040: 4-space indent should win over 2-space when predominant',
    () {
      _assertGuess(true, 4, [
        'function foo() {',
        '    let a = 1;',
        '    let b = 2;',
        '    if (true) {',
        '        console.log(a);',
        '        console.log(b);',
        '    }',
        '    const obj = {',
        '      x: 1,', // 2-space indent here
        '      y: 2', // 2-space indent here
        '    };',
        '    return obj;',
        '}',
      ]);
    },
  );
}
