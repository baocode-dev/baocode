/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/test/browser/
// terminalLinkParsing.test.ts. The parsed links are records, so the object
// literals are record literals; `undefined` is null.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/links/terminal_link_parsing.dart';

class ITestLink {
  const ITestLink({
    required this.link,
    required this.prefix,
    required this.suffix,
    required this.hasRow,
    required this.hasCol,
    this.hasRowEnd = false,
    this.hasColEnd = false,
  });

  final String link;
  final String? prefix;
  final String? suffix;
  // TODO: These has vars would be nicer as a flags enum
  final bool hasRow;
  final bool hasCol;
  final bool hasRowEnd;
  final bool hasColEnd;
}

const List<OperatingSystem> operatingSystems = [
  OperatingSystem.linux,
  OperatingSystem.macintosh,
  OperatingSystem.windows,
];
const Map<OperatingSystem, String> osTestPath = {
  OperatingSystem.linux: '/test/path/linux',
  OperatingSystem.macintosh: '/test/path/macintosh',
  OperatingSystem.windows: r'C:\test\path\windows',
};
const Map<OperatingSystem, String> osLabel = {
  OperatingSystem.linux: '[Linux]',
  OperatingSystem.macintosh: '[macOS]',
  OperatingSystem.windows: '[Windows]',
};

const int testRow = 339;
const int testCol = 12;
const int testRowEnd = 341;
const int testColEnd = 789;
const List<ITestLink> testLinks = [
  // Simple
  ITestLink(
    link: 'foo',
    prefix: null,
    suffix: null,
    hasRow: false,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo:339',
    prefix: null,
    suffix: ':339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo:339:12',
    prefix: null,
    suffix: ':339:12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo:339:12-789',
    prefix: null,
    suffix: ':339:12-789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: false,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo:339.12',
    prefix: null,
    suffix: ':339.12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo:339.12-789',
    prefix: null,
    suffix: ':339.12-789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: false,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo:339.12-341.789',
    prefix: null,
    suffix: ':339.12-341.789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: true,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo#339',
    prefix: null,
    suffix: '#339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo#339:12',
    prefix: null,
    suffix: '#339:12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo#339:12-789',
    prefix: null,
    suffix: '#339:12-789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: false,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo#339.12',
    prefix: null,
    suffix: '#339.12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo#339.12-789',
    prefix: null,
    suffix: '#339.12-789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: false,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo#339.12-341.789',
    prefix: null,
    suffix: '#339.12-341.789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: true,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo 339',
    prefix: null,
    suffix: ' 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo 339:12',
    prefix: null,
    suffix: ' 339:12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo 339:12-789',
    prefix: null,
    suffix: ' 339:12-789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: false,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo 339.12',
    prefix: null,
    suffix: ' 339.12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo 339.12-789',
    prefix: null,
    suffix: ' 339.12-789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: false,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo 339.12-341.789',
    prefix: null,
    suffix: ' 339.12-341.789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: true,
    hasColEnd: true,
  ),
  ITestLink(
    link: 'foo, 339',
    prefix: null,
    suffix: ', 339',
    hasRow: true,
    hasCol: false,
  ),

  // Double quotes
  ITestLink(
    link: '"foo",339',
    prefix: '"',
    suffix: '",339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: '"foo",339:12',
    prefix: '"',
    suffix: '",339:12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo",339.12',
    prefix: '"',
    suffix: '",339.12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo", line 339',
    prefix: '"',
    suffix: '", line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: '"foo", line 339, col 12',
    prefix: '"',
    suffix: '", line 339, col 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo", line 339, column 12',
    prefix: '"',
    suffix: '", line 339, column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo":line 339',
    prefix: '"',
    suffix: '":line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: '"foo":line 339, col 12',
    prefix: '"',
    suffix: '":line 339, col 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo":line 339, column 12',
    prefix: '"',
    suffix: '":line 339, column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo": line 339',
    prefix: '"',
    suffix: '": line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: '"foo": line 339, col 12',
    prefix: '"',
    suffix: '": line 339, col 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo": line 339, column 12',
    prefix: '"',
    suffix: '": line 339, column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo" on line 339',
    prefix: '"',
    suffix: '" on line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: '"foo" on line 339, col 12',
    prefix: '"',
    suffix: '" on line 339, col 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo" on line 339, column 12',
    prefix: '"',
    suffix: '" on line 339, column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo" line 339',
    prefix: '"',
    suffix: '" line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: '"foo" line 339 column 12',
    prefix: '"',
    suffix: '" line 339 column 12',
    hasRow: true,
    hasCol: true,
  ),

  // Single quotes
  ITestLink(
    link: "'foo',339",
    prefix: "'",
    suffix: "',339",
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: "'foo',339:12",
    prefix: "'",
    suffix: "',339:12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo',339.12",
    prefix: "'",
    suffix: "',339.12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo', line 339",
    prefix: "'",
    suffix: "', line 339",
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: "'foo', line 339, col 12",
    prefix: "'",
    suffix: "', line 339, col 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo', line 339, column 12",
    prefix: "'",
    suffix: "', line 339, column 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo':line 339",
    prefix: "'",
    suffix: "':line 339",
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: "'foo':line 339, col 12",
    prefix: "'",
    suffix: "':line 339, col 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo':line 339, column 12",
    prefix: "'",
    suffix: "':line 339, column 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo': line 339",
    prefix: "'",
    suffix: "': line 339",
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: "'foo': line 339, col 12",
    prefix: "'",
    suffix: "': line 339, col 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo': line 339, column 12",
    prefix: "'",
    suffix: "': line 339, column 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo' on line 339",
    prefix: "'",
    suffix: "' on line 339",
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: "'foo' on line 339, col 12",
    prefix: "'",
    suffix: "' on line 339, col 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo' on line 339, column 12",
    prefix: "'",
    suffix: "' on line 339, column 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo' line 339",
    prefix: "'",
    suffix: "' line 339",
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: "'foo' line 339 column 12",
    prefix: "'",
    suffix: "' line 339 column 12",
    hasRow: true,
    hasCol: true,
  ),

  // No quotes
  ITestLink(
    link: 'foo, line 339',
    prefix: null,
    suffix: ', line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo, line 339, col 12',
    prefix: null,
    suffix: ', line 339, col 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo, line 339, column 12',
    prefix: null,
    suffix: ', line 339, column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo:line 339',
    prefix: null,
    suffix: ':line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo:line 339, col 12',
    prefix: null,
    suffix: ':line 339, col 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo:line 339, column 12',
    prefix: null,
    suffix: ':line 339, column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo: line 339',
    prefix: null,
    suffix: ': line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo: line 339, col 12',
    prefix: null,
    suffix: ': line 339, col 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo: line 339, column 12',
    prefix: null,
    suffix: ': line 339, column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo on line 339',
    prefix: null,
    suffix: ' on line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo on line 339, col 12',
    prefix: null,
    suffix: ' on line 339, col 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo on line 339, column 12',
    prefix: null,
    suffix: ' on line 339, column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo line 339',
    prefix: null,
    suffix: ' line 339',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo line 339 column 12',
    prefix: null,
    suffix: ' line 339 column 12',
    hasRow: true,
    hasCol: true,
  ),

  // Parentheses
  ITestLink(
    link: 'foo(339)',
    prefix: null,
    suffix: '(339)',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo(339,12)',
    prefix: null,
    suffix: '(339,12)',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo(339, 12)',
    prefix: null,
    suffix: '(339, 12)',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo (339)',
    prefix: null,
    suffix: ' (339)',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo (339,12)',
    prefix: null,
    suffix: ' (339,12)',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo (339, 12)',
    prefix: null,
    suffix: ' (339, 12)',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo: (339)',
    prefix: null,
    suffix: ': (339)',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo: (339,12)',
    prefix: null,
    suffix: ': (339,12)',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo: (339, 12)',
    prefix: null,
    suffix: ': (339, 12)',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo(339:12)',
    prefix: null,
    suffix: '(339:12)',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo (339:12)',
    prefix: null,
    suffix: ' (339:12)',
    hasRow: true,
    hasCol: true,
  ),

  // Square brackets
  ITestLink(
    link: 'foo[339]',
    prefix: null,
    suffix: '[339]',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo[339,12]',
    prefix: null,
    suffix: '[339,12]',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo[339, 12]',
    prefix: null,
    suffix: '[339, 12]',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo [339]',
    prefix: null,
    suffix: ' [339]',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo [339,12]',
    prefix: null,
    suffix: ' [339,12]',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo [339, 12]',
    prefix: null,
    suffix: ' [339, 12]',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo: [339]',
    prefix: null,
    suffix: ': [339]',
    hasRow: true,
    hasCol: false,
  ),
  ITestLink(
    link: 'foo: [339,12]',
    prefix: null,
    suffix: ': [339,12]',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo: [339, 12]',
    prefix: null,
    suffix: ': [339, 12]',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo[339:12]',
    prefix: null,
    suffix: '[339:12]',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo [339:12]',
    prefix: null,
    suffix: ' [339:12]',
    hasRow: true,
    hasCol: true,
  ),

  // OCaml-style
  ITestLink(
    link: '"foo", line 339, character 12',
    prefix: '"',
    suffix: '", line 339, character 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo", line 339, characters 12-789',
    prefix: '"',
    suffix: '", line 339, characters 12-789',
    hasRow: true,
    hasCol: true,
    hasColEnd: true,
  ),
  ITestLink(
    link: '"foo", lines 339-341',
    prefix: '"',
    suffix: '", lines 339-341',
    hasRow: true,
    hasCol: false,
    hasRowEnd: true,
  ),
  ITestLink(
    link: '"foo", lines 339-341, characters 12-789',
    prefix: '"',
    suffix: '", lines 339-341, characters 12-789',
    hasRow: true,
    hasCol: true,
    hasRowEnd: true,
    hasColEnd: true,
  ),

  // Non-breaking space
  ITestLink(
    link: 'foo\u00A0339:12',
    prefix: null,
    suffix: '\u00A0339:12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: '"foo" on line 339,\u00A0column 12',
    prefix: '"',
    suffix: '" on line 339,\u00A0column 12',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: "'foo' on line\u00A0339, column 12",
    prefix: "'",
    suffix: "' on line\u00A0339, column 12",
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo (339,\u00A012)',
    prefix: null,
    suffix: ' (339,\u00A012)',
    hasRow: true,
    hasCol: true,
  ),
  ITestLink(
    link: 'foo\u00A0[339, 12]',
    prefix: null,
    suffix: '\u00A0[339, 12]',
    hasRow: true,
    hasCol: true,
  ),
];
final List<ITestLink> testLinksWithSuffix = testLinks
    .where((e) => e.suffix != null)
    .toList();

void main() {
  group('TerminalLinkParsing', () {
    group('removeLinkSuffix', () {
      for (final testLink in testLinks) {
        test('`${testLink.link}`', () {
          expect(
            removeLinkSuffix(testLink.link),
            testLink.suffix == null
                ? testLink.link
                : testLink.link.replaceFirst(testLink.suffix!, ''),
          );
        });
      }
    });
    group('getLinkSuffix', () {
      for (final testLink in testLinks) {
        test('`${testLink.link}`', () {
          expect(
            getLinkSuffix(testLink.link),
            testLink.suffix == null
                ? null
                : (
                    row: testLink.hasRow ? testRow : null,
                    col: testLink.hasCol ? testCol : null,
                    rowEnd: testLink.hasRowEnd ? testRowEnd : null,
                    colEnd: testLink.hasColEnd ? testColEnd : null,
                    suffix: (
                      index: testLink.link.length - testLink.suffix!.length,
                      text: testLink.suffix!,
                    ),
                  ),
          );
        });
      }
    });
    group('detectLinkSuffixes', () {
      for (final testLink in testLinks) {
        test('`${testLink.link}`', () {
          expect(
            detectLinkSuffixes(testLink.link),
            testLink.suffix == null
                ? <ILinkSuffix>[]
                : [
                    (
                      row: testLink.hasRow ? testRow : null,
                      col: testLink.hasCol ? testCol : null,
                      rowEnd: testLink.hasRowEnd ? testRowEnd : null,
                      colEnd: testLink.hasColEnd ? testColEnd : null,
                      suffix: (
                        index: testLink.link.length - testLink.suffix!.length,
                        text: testLink.suffix!,
                      ),
                    ),
                  ],
          );
        });
      }

      test('foo(1, 2) bar[3, 4] baz on line 5', () {
        expect(detectLinkSuffixes('foo(1, 2) bar[3, 4] baz on line 5'), [
          (
            col: 2,
            row: 1,
            rowEnd: null,
            colEnd: null,
            suffix: (index: 3, text: '(1, 2)'),
          ),
          (
            col: 4,
            row: 3,
            rowEnd: null,
            colEnd: null,
            suffix: (index: 13, text: '[3, 4]'),
          ),
          (
            col: null,
            row: 5,
            rowEnd: null,
            colEnd: null,
            suffix: (index: 23, text: ' on line 5'),
          ),
        ]);
      });
    });
    group('removeLinkQueryString', () {
      test('should remove any query string from the link', () {
        expect(removeLinkQueryString('?a=b'), '');
        expect(removeLinkQueryString('foo?a=b'), 'foo');
        expect(removeLinkQueryString('./foo?a=b'), './foo');
        expect(removeLinkQueryString('/foo/bar?a=b'), '/foo/bar');
        expect(removeLinkQueryString('foo?a=b?'), 'foo');
        expect(removeLinkQueryString('foo?a=b&c=d'), 'foo');
      });
      test('should respect ? in UNC paths', () {
        expect(removeLinkQueryString(r'\\?\foo?a=b'), r'\\?\foo');
      });
    });
    group('detectLinks', () {
      test('foo(1, 2) bar[3, 4] "baz" on line 5', () {
        expect(
          detectLinks(
            'foo(1, 2) bar[3, 4] "baz" on line 5',
            OperatingSystem.linux,
          ),
          <IParsedLink>[
            (
              path: (index: 0, text: 'foo'),
              prefix: null,
              suffix: (
                col: 2,
                row: 1,
                rowEnd: null,
                colEnd: null,
                suffix: (index: 3, text: '(1, 2)'),
              ),
            ),
            (
              path: (index: 10, text: 'bar'),
              prefix: null,
              suffix: (
                col: 4,
                row: 3,
                rowEnd: null,
                colEnd: null,
                suffix: (index: 13, text: '[3, 4]'),
              ),
            ),
            (
              path: (index: 21, text: 'baz'),
              prefix: (index: 20, text: '"'),
              suffix: (
                col: null,
                row: 5,
                rowEnd: null,
                colEnd: null,
                suffix: (index: 24, text: '" on line 5'),
              ),
            ),
          ],
        );
      });

      test(
        'should detect multiple links when opening brackets are in the text',
        () {
          expect(
            detectLinks('notlink[foo:45]', OperatingSystem.linux),
            <IParsedLink>[
              (
                path: (index: 0, text: 'notlink[foo'),
                prefix: null,
                suffix: (
                  col: null,
                  row: 45,
                  rowEnd: null,
                  colEnd: null,
                  suffix: (index: 11, text: ':45'),
                ),
              ),
              (
                path: (index: 8, text: 'foo'),
                prefix: null,
                suffix: (
                  col: null,
                  row: 45,
                  rowEnd: null,
                  colEnd: null,
                  suffix: (index: 11, text: ':45'),
                ),
              ),
            ],
          );
        },
      );

      test('should extract the link prefix', () {
        expect(
          detectLinks('"foo", line 5, col 6', OperatingSystem.linux),
          <IParsedLink>[
            (
              path: (index: 1, text: 'foo'),
              prefix: (index: 0, text: '"'),
              suffix: (
                row: 5,
                col: 6,
                rowEnd: null,
                colEnd: null,
                suffix: (index: 4, text: '", line 5, col 6'),
              ),
            ),
          ],
        );
      });

      test('should be smart about determining the link prefix when multiple prefix characters exist', () {
        expect(
          detectLinks('echo \'"foo", line 5, col 6\'', OperatingSystem.linux),
          <IParsedLink>[
            (
              path: (index: 7, text: 'foo'),
              prefix: (index: 6, text: '"'),
              suffix: (
                row: 5,
                col: 6,
                rowEnd: null,
                colEnd: null,
                suffix: (index: 10, text: '", line 5, col 6'),
              ),
            ),
          ],
          reason: 'The outer single quotes should be excluded from the link prefix and suffix',
        );
      });

      test(
        'should detect both suffix and non-suffix links on a single line',
        () {
          expect(
            detectLinks(
              'PS C:\\Github\\microsoft\\vscode> echo \'"foo", line 5, col 6\'',
              OperatingSystem.windows,
            ),
            <IParsedLink>[
              (
                path: (index: 3, text: r'C:\Github\microsoft\vscode'),
                prefix: null,
                suffix: null,
              ),
              (
                path: (index: 38, text: 'foo'),
                prefix: (index: 37, text: '"'),
                suffix: (
                  row: 5,
                  col: 6,
                  rowEnd: null,
                  colEnd: null,
                  suffix: (index: 41, text: '", line 5, col 6'),
                ),
              ),
            ],
          );
        },
      );

      group('"|"', () {
        test('should exclude pipe characters from link paths', () {
          expect(
            detectLinks(
              r'|C:\Github\microsoft\vscode|',
              OperatingSystem.windows,
            ),
            <IParsedLink>[
              (
                path: (index: 1, text: r'C:\Github\microsoft\vscode'),
                prefix: null,
                suffix: null,
              ),
            ],
          );
        });
        test(
          'should exclude pipe characters from link paths with suffixes',
          () {
            expect(
              detectLinks(
                r'|C:\Github\microsoft\vscode:400|',
                OperatingSystem.windows,
              ),
              <IParsedLink>[
                (
                  path: (index: 1, text: r'C:\Github\microsoft\vscode'),
                  prefix: null,
                  suffix: (
                    col: null,
                    row: 400,
                    rowEnd: null,
                    colEnd: null,
                    suffix: (index: 27, text: ':400'),
                  ),
                ),
              ],
            );
          },
        );
      });

      group('"<>"', () {
        for (final os in operatingSystems) {
          test(
            'should exclude bracket characters from link paths ${osLabel[os]}',
            () {
              expect(detectLinks('<${osTestPath[os]}<', os), <IParsedLink>[
                (
                  path: (index: 1, text: osTestPath[os]!),
                  prefix: null,
                  suffix: null,
                ),
              ]);
              expect(detectLinks('>${osTestPath[os]}>', os), <IParsedLink>[
                (
                  path: (index: 1, text: osTestPath[os]!),
                  prefix: null,
                  suffix: null,
                ),
              ]);
            },
          );
          test(
            'should exclude bracket characters from link paths with suffixes ${osLabel[os]}',
            () {
              expect(detectLinks('<${osTestPath[os]}:400<', os), <IParsedLink>[
                (
                  path: (index: 1, text: osTestPath[os]!),
                  prefix: null,
                  suffix: (
                    col: null,
                    row: 400,
                    rowEnd: null,
                    colEnd: null,
                    suffix: (index: 1 + osTestPath[os]!.length, text: ':400'),
                  ),
                ),
              ]);
              expect(detectLinks('>${osTestPath[os]}:400>', os), <IParsedLink>[
                (
                  path: (index: 1, text: osTestPath[os]!),
                  prefix: null,
                  suffix: (
                    col: null,
                    row: 400,
                    rowEnd: null,
                    colEnd: null,
                    suffix: (index: 1 + osTestPath[os]!.length, text: ':400'),
                  ),
                ),
              ]);
            },
          );
        }
      });

      group('query strings', () {
        for (final os in operatingSystems) {
          test(
            'should exclude query strings from link paths ${osLabel[os]}',
            () {
              expect(detectLinks('${osTestPath[os]}?a=b', os), <IParsedLink>[
                (
                  path: (index: 0, text: osTestPath[os]!),
                  prefix: null,
                  suffix: null,
                ),
              ]);
              expect(
                detectLinks('${osTestPath[os]}?a=b&c=d', os),
                <IParsedLink>[
                  (
                    path: (index: 0, text: osTestPath[os]!),
                    prefix: null,
                    suffix: null,
                  ),
                ],
              );
            },
          );
          test('should not detect links starting with ? within query strings that contain posix-style paths (#204195)', () {
            // ? appended to the cwd will exist since it's just the cwd
            expect(
              detectLinks(
                'http://foo.com/?bar=/a/b&baz=c',
                os,
              ).any((e) => e.path.text.startsWith('?')),
              false,
            );
          });
          test('should not detect links starting with ? within query strings that contain Windows-style paths (#204195)', () {
            // ? appended to the cwd will exist since it's just the cwd
            expect(
              detectLinks(
                r'http://foo.com/?bar=a:\b&baz=c',
                os,
              ).any((e) => e.path.text.startsWith('?')),
              false,
            );
          });
        }
      });

      group('should detect file names in git diffs', () {
        test('--- a/foo/bar', () {
          for (final prefix in ['a', 'c', 'w', 'i', 'o']) {
            expect(
              detectLinks('--- $prefix/foo/bar', OperatingSystem.linux),
              <IParsedLink>[
                (path: (index: 6, text: 'foo/bar'), prefix: null, suffix: null),
              ],
            );
          }
        });
        test('+++ b/foo/bar', () {
          for (final prefix in ['b', 'c', 'w', 'i', 'o']) {
            expect(
              detectLinks('+++ $prefix/foo/bar', OperatingSystem.linux),
              <IParsedLink>[
                (path: (index: 6, text: 'foo/bar'), prefix: null, suffix: null),
              ],
            );
          }
        });
        test('diff --git a/foo/bar b/foo/baz', () {
          for (final (sourcePrefix, destinationPrefix) in [
            ('a', 'b'),
            ('c', 'w'),
            ('i', 'o'),
          ]) {
            expect(
              detectLinks(
                'diff --git $sourcePrefix/foo/bar $destinationPrefix/foo/baz',
                OperatingSystem.linux,
              ),
              <IParsedLink>[
                (
                  path: (index: 13, text: 'foo/bar'),
                  prefix: null,
                  suffix: null,
                ),
                (
                  path: (index: 23, text: 'foo/baz'),
                  prefix: null,
                  suffix: null,
                ),
              ],
            );
          }
        });
        test('numeric prefixes used by git diff --no-index', () {
          expect(
            [
              detectLinks('--- 1/foo/bar', OperatingSystem.linux),
              detectLinks('+++ 2/foo/baz', OperatingSystem.linux),
              detectLinks(
                'diff --git 1/foo/bar 2/foo/baz',
                OperatingSystem.linux,
              ),
            ],
            <List<IParsedLink>>[
              [(path: (index: 6, text: 'foo/bar'), prefix: null, suffix: null)],
              [(path: (index: 6, text: 'foo/baz'), prefix: null, suffix: null)],
              [
                (
                  path: (index: 13, text: 'foo/bar'),
                  prefix: null,
                  suffix: null,
                ),
                (
                  path: (index: 23, text: 'foo/baz'),
                  prefix: null,
                  suffix: null,
                ),
              ],
            ],
          );
        });
        test('reversed numeric prefixes used by git diff --no-index -R', () {
          expect(
            [
              detectLinks('--- 2/foo/baz', OperatingSystem.linux),
              detectLinks('+++ 1/foo/bar', OperatingSystem.linux),
              detectLinks(
                'diff --git 2/foo/baz 1/foo/bar',
                OperatingSystem.linux,
              ),
            ],
            <List<IParsedLink>>[
              [(path: (index: 6, text: 'foo/baz'), prefix: null, suffix: null)],
              [(path: (index: 6, text: 'foo/bar'), prefix: null, suffix: null)],
              [
                (
                  path: (index: 13, text: 'foo/baz'),
                  prefix: null,
                  suffix: null,
                ),
                (
                  path: (index: 23, text: 'foo/bar'),
                  prefix: null,
                  suffix: null,
                ),
              ],
            ],
          );
        });
        test('ordinary numeric line suffix', () {
          expect(detectLinks('foo 1', OperatingSystem.linux), <IParsedLink>[
            (
              path: (index: 0, text: 'foo'),
              prefix: null,
              suffix: (
                row: 1,
                col: null,
                rowEnd: null,
                colEnd: null,
                suffix: (index: 3, text: ' 1'),
              ),
            ),
          ]);
        });
        test('numeric suffix followed by a path separator', () {
          expect(detectLinks('foo 1/bar', OperatingSystem.linux), <IParsedLink>[
            (path: (index: 4, text: '1/bar'), prefix: null, suffix: null),
          ]);
        });
        test('ordinary numeric line suffix after diff --git text', () {
          expect(
            detectLinks('diff --git foo.ts:123', OperatingSystem.linux),
            <IParsedLink>[
              (
                path: (index: 11, text: 'foo.ts'),
                prefix: null,
                suffix: (
                  row: 123,
                  col: null,
                  rowEnd: null,
                  colEnd: null,
                  suffix: (index: 17, text: ':123'),
                ),
              ),
            ],
          );
        });
      });

      group('should detect 3 suffix links on a single line', () {
        for (var i = 0; i < testLinksWithSuffix.length - 2; i++) {
          final link1 = testLinksWithSuffix[i];
          final link2 = testLinksWithSuffix[i + 1];
          final link3 = testLinksWithSuffix[i + 2];
          final line = ' ${link1.link} ${link2.link} ${link3.link} ';
          test('`${line.replaceAll('\u00A0', '<nbsp>')}`', () {
            expect(detectLinks(line, OperatingSystem.linux).length, 3);
            expect(link1.suffix, isNotNull);
            expect(link2.suffix, isNotNull);
            expect(link3.suffix, isNotNull);
            final IParsedLink detectedLink1 = (
              prefix: link1.prefix != null
                  ? (index: 1, text: link1.prefix!)
                  : null,
              path: (
                index: 1 + (link1.prefix?.length ?? 0),
                text: link1.link
                    .replaceFirst(link1.suffix!, '')
                    .replaceFirst(link1.prefix ?? '', ''),
              ),
              suffix: (
                row: link1.hasRow ? testRow : null,
                col: link1.hasCol ? testCol : null,
                rowEnd: link1.hasRowEnd ? testRowEnd : null,
                colEnd: link1.hasColEnd ? testColEnd : null,
                suffix: (
                  index: 1 + (link1.link.length - link1.suffix!.length),
                  text: link1.suffix!,
                ),
              ),
            );
            final IParsedLink detectedLink2 = (
              prefix: link2.prefix != null
                  ? (
                      index:
                          (detectedLink1.prefix?.index ??
                              detectedLink1.path.index) +
                          link1.link.length +
                          1,
                      text: link2.prefix!,
                    )
                  : null,
              path: (
                index:
                    (detectedLink1.prefix?.index ?? detectedLink1.path.index) +
                    link1.link.length +
                    1 +
                    (link2.prefix ?? '').length,
                text: link2.link
                    .replaceFirst(link2.suffix!, '')
                    .replaceFirst(link2.prefix ?? '', ''),
              ),
              suffix: (
                row: link2.hasRow ? testRow : null,
                col: link2.hasCol ? testCol : null,
                rowEnd: link2.hasRowEnd ? testRowEnd : null,
                colEnd: link2.hasColEnd ? testColEnd : null,
                suffix: (
                  index:
                      (detectedLink1.prefix?.index ??
                          detectedLink1.path.index) +
                      link1.link.length +
                      1 +
                      (link2.link.length - link2.suffix!.length),
                  text: link2.suffix!,
                ),
              ),
            );
            final IParsedLink detectedLink3 = (
              prefix: link3.prefix != null
                  ? (
                      index:
                          (detectedLink2.prefix?.index ??
                              detectedLink2.path.index) +
                          link2.link.length +
                          1,
                      text: link3.prefix!,
                    )
                  : null,
              path: (
                index:
                    (detectedLink2.prefix?.index ?? detectedLink2.path.index) +
                    link2.link.length +
                    1 +
                    (link3.prefix ?? '').length,
                text: link3.link
                    .replaceFirst(link3.suffix!, '')
                    .replaceFirst(link3.prefix ?? '', ''),
              ),
              suffix: (
                row: link3.hasRow ? testRow : null,
                col: link3.hasCol ? testCol : null,
                rowEnd: link3.hasRowEnd ? testRowEnd : null,
                colEnd: link3.hasColEnd ? testColEnd : null,
                suffix: (
                  index:
                      (detectedLink2.prefix?.index ??
                          detectedLink2.path.index) +
                      link2.link.length +
                      1 +
                      (link3.link.length - link3.suffix!.length),
                  text: link3.suffix!,
                ),
              ),
            );
            expect(detectLinks(line, OperatingSystem.linux), [
              detectedLink1,
              detectedLink2,
              detectedLink3,
            ]);
          });
        }
      });
      // Upstream asserts in the suite body; a test here.
      test('should ignore links with suffixes when the path itself is the empty string', () {
        expect(detectLinks('""",1', OperatingSystem.linux), <IParsedLink>[]);
      });
    });
  });
}
