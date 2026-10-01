/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/test/browser/
// terminalWordLinkDetector.test.ts. Setting
// `terminal.integrated.wordSeparators` and firing the configuration change
// is the detector's `wordSeparators` setter.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/links/links.dart';
import 'package:baocode/ide/terminal/links/terminal_word_link_detector.dart';
import 'package:bao_xterm/headless/public/terminal.dart';
import 'package:bao_xterm/typings/xterm_headless.dart' hide Terminal;

import 'link_test_utils.dart';

void main() {
  group('Workbench - TerminalWordLinkDetector', () {
    late TerminalWordLinkDetector detector;
    late Terminal xterm;

    setUp(() {
      xterm = Terminal(
        ITerminalOptions(allowProposedApi: true, cols: 80, rows: 30),
      );
      detector = TerminalWordLinkDetector(xterm, wordSeparators: '');
    });

    tearDown(() {
      xterm.dispose();
    });

    Future<void> assertLink(
      String text,
      List<({String text, List<List<int>> range})> expected,
    ) async {
      await assertLinkHelper(
        text,
        expected,
        detector,
        TerminalBuiltinLinkType.search,
      );
    }

    group('should link words as defined by wordSeparators', () {
      test('" ()[]"', () async {
        detector.wordSeparators = ' ()[]';
        await assertLink('foo', [
          (
            range: [
              [1, 1],
              [3, 1],
            ],
            text: 'foo',
          ),
        ]);
        await assertLink(' foo ', [
          (
            range: [
              [2, 1],
              [4, 1],
            ],
            text: 'foo',
          ),
        ]);
        await assertLink('(foo)', [
          (
            range: [
              [2, 1],
              [4, 1],
            ],
            text: 'foo',
          ),
        ]);
        await assertLink('[foo]', [
          (
            range: [
              [2, 1],
              [4, 1],
            ],
            text: 'foo',
          ),
        ]);
        await assertLink('{foo}', [
          (
            range: [
              [1, 1],
              [5, 1],
            ],
            text: '{foo}',
          ),
        ]);
      });
      test('" "', () async {
        detector.wordSeparators = ' ';
        await assertLink('foo', [
          (
            range: [
              [1, 1],
              [3, 1],
            ],
            text: 'foo',
          ),
        ]);
        await assertLink(' foo ', [
          (
            range: [
              [2, 1],
              [4, 1],
            ],
            text: 'foo',
          ),
        ]);
        await assertLink('(foo)', [
          (
            range: [
              [1, 1],
              [5, 1],
            ],
            text: '(foo)',
          ),
        ]);
        await assertLink('[foo]', [
          (
            range: [
              [1, 1],
              [5, 1],
            ],
            text: '[foo]',
          ),
        ]);
        await assertLink('{foo}', [
          (
            range: [
              [1, 1],
              [5, 1],
            ],
            text: '{foo}',
          ),
        ]);
      });
      test('" []"', () async {
        detector.wordSeparators = ' []';
        await assertLink('aabbccdd.txt ', [
          (
            range: [
              [1, 1],
              [12, 1],
            ],
            text: 'aabbccdd.txt',
          ),
        ]);
        await assertLink(' aabbccdd.txt ', [
          (
            range: [
              [2, 1],
              [13, 1],
            ],
            text: 'aabbccdd.txt',
          ),
        ]);
        await assertLink(' [aabbccdd.txt] ', [
          (
            range: [
              [3, 1],
              [14, 1],
            ],
            text: 'aabbccdd.txt',
          ),
        ]);
      });
    });

    group('should ignore powerline symbols', () {
      for (var i = 0xe0b0; i <= 0xe0bf; i++) {
        test('\\u${i.toRadixString(16)}', () async {
          await assertLink(
            '${String.fromCharCode(i)}foo${String.fromCharCode(i)}',
            [
              (
                range: [
                  [2, 1],
                  [4, 1],
                ],
                text: 'foo',
              ),
            ],
          );
        });
      }
    });

    // These are failing - the link's start x is 1 px too far to the right bc
    // it starts with a wide character, which the terminalLinkHelper
    // currently doesn't account for
    test('should support wide characters', skip: 'Skipped upstream', () async {
      detector.wordSeparators = ' []';
      await assertLink('我是学生.txt ', [
        (
          range: [
            [1, 1],
            [12, 1],
          ],
          text: '我是学生.txt',
        ),
      ]);
      await assertLink(' 我是学生.txt ', [
        (
          range: [
            [2, 1],
            [13, 1],
          ],
          text: '我是学生.txt',
        ),
      ]);
      await assertLink(' [我是学生.txt] ', [
        (
          range: [
            [3, 1],
            [14, 1],
          ],
          text: '我是学生.txt',
        ),
      ]);
    });

    test('should support multiple link results', () async {
      detector.wordSeparators = ' ';
      await assertLink('foo bar', [
        (
          range: [
            [1, 1],
            [3, 1],
          ],
          text: 'foo',
        ),
        (
          range: [
            [5, 1],
            [7, 1],
          ],
          text: 'bar',
        ),
      ]);
    });

    test('should remove trailing colon in the link results', () async {
      detector.wordSeparators = ' ';
      await assertLink('foo:5:6: bar:0:32:', [
        (
          range: [
            [1, 1],
            [7, 1],
          ],
          text: 'foo:5:6',
        ),
        (
          range: [
            [10, 1],
            [17, 1],
          ],
          text: 'bar:0:32',
        ),
      ]);
    });

    test('should support wrapping', () async {
      detector.wordSeparators = ' ';
      await assertLink(
        'fsdjfsdkfjslkdfjskdfjsldkfjsdlkfjslkdjfskldjflskdfjskldjflskdfjsdklfjsdklfjsldkfjsdlkfjsdlkfjsdlkfjsldkfjslkdfjsdlkfjsldkfjsdlkfjskdfjsldkfjsdlkfjslkdfjsdlkfjsldkfjsldkfjsldkfjslkdfjsdlkfjslkdfjsdklfsd',
        [
          (
            range: [
              [1, 1],
              [41, 3],
            ],
            text: 'fsdjfsdkfjslkdfjskdfjsldkfjsdlkfjslkdjfskldjflskdfjskldjflskdfjsdklfjsdklfjsldkfjsdlkfjsdlkfjsdlkfjsldkfjslkdfjsdlkfjsldkfjsdlkfjskdfjsldkfjsdlkfjslkdfjsdlkfjsldkfjsldkfjsldkfjslkdfjsdlkfjslkdfjsdklfsd',
          ),
        ],
      );
    });
    test('should support wrapping with multiple links', () async {
      detector.wordSeparators = ' ';
      await assertLink(
        'fsdjfsdkfjslkdfjskdfjsldkfj sdlkfjslkdjfskldjflskdfjskldjflskdfj sdklfjsdklfjsldkfjsdlkfjsdlkfjsdlkfjsldkfjslkdfjsdlkfjsldkfjsdlkfjskdfjsldkfjsdlkfjslkdfjsdlkfjsldkfjsldkfjsldkfjslkdfjsdlkfjslkdfjsdklfsd',
        [
          (
            range: [
              [1, 1],
              [27, 1],
            ],
            text: 'fsdjfsdkfjslkdfjskdfjsldkfj',
          ),
          (
            range: [
              [29, 1],
              [64, 1],
            ],
            text: 'sdlkfjslkdjfskldjflskdfjskldjflskdfj',
          ),
          (
            range: [
              [66, 1],
              [43, 3],
            ],
            text: 'sdklfjsdklfjsldkfjsdlkfjsdlkfjsdlkfjsldkfjslkdfjsdlkfjsldkfjsdlkfjskdfjsldkfjsdlkfjslkdfjsdlkfjsldkfjsldkfjsldkfjslkdfjsdlkfjslkdfjsdklfsd',
          ),
        ],
      );
    });
    test('does not return any links for empty text', () async {
      detector.wordSeparators = ' ';
      await assertLink('', []);
    });
    test('should support file scheme links', () async {
      detector.wordSeparators = ' ';
      await assertLink('file:///C:/users/test/file.txt ', [
        (
          range: [
            [1, 1],
            [30, 1],
          ],
          text: 'file:///C:/users/test/file.txt',
        ),
      ]);
      await assertLink('file:///C:/users/test/file.txt:1:10 ', [
        (
          range: [
            [1, 1],
            [35, 1],
          ],
          text: 'file:///C:/users/test/file.txt:1:10',
        ),
      ]);
    });
  });
}
