/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/test/browser/
// terminalUriLinkDetector.test.ts. The file service is a stat function over
// `validResources`; URIs are Dart's (`URI.parse` is `Uri.parse`, `URI.file`
// is [uriFile]).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/links/links.dart';
import 'package:monad/ide/terminal/links/terminal_link_parsing.dart';
import 'package:monad/ide/terminal/links/terminal_link_resolver.dart';
import 'package:monad/ide/terminal/links/terminal_uri_link_detector.dart';
import 'package:monad/ide/terminal/xterm/headless/public/terminal.dart';
import 'package:monad/ide/terminal/xterm/typings/xterm_headless.dart'
    hide Terminal;

import 'link_test_utils.dart';

void main() {
  group('Workbench - TerminalUriLinkDetector', () {
    late TerminalUriLinkDetector detector;
    late Terminal xterm;
    var validResources = <Uri>[];

    setUp(() {
      validResources = [];

      xterm = Terminal(
        ITerminalOptions(allowProposedApi: true, cols: 80, rows: 30),
      );
      detector = TerminalUriLinkDetector(
        xterm,
        TerminalLinkProcessInfo(
          initialCwd: '/parent/cwd',
          os: OperatingSystem.linux,
        ),
        TerminalFileLinkResolver(
          os: OperatingSystem.linux,
          userHome: '/home',
          stat: fakeStat(() => validResources, OperatingSystem.linux),
        ),
      );
    });

    tearDown(() {
      xterm.dispose();
    });

    Future<void> assertLink(
      TerminalBuiltinLinkType type,
      String text,
      List<({Uri uri, List<List<int>> range})> expected,
    ) async {
      await assertLinkHelper(text, expected, detector, type);
    }

    final linkComputerCases =
        <
          (
            /* Link type      */ TerminalBuiltinLinkType,
            /* Line text      */ String,
            /* Link and range */ List<({Uri uri, List<List<int>> range})>,
            /* Stat resource  */ Uri?,
          )
        >[
          (
            TerminalBuiltinLinkType.url,
            'x = "http://foo.bar";',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'x = (http://foo.bar);',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            "x = 'http://foo.bar';",
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'x =  http://foo.bar ;',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'x = <http://foo.bar>;',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'x = {http://foo.bar};',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '(see http://foo.bar)',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '[see http://foo.bar]',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '{see http://foo.bar}',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '<see http://foo.bar>',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '<url>http://foo.bar</url>',
            [
              (
                range: [
                  [6, 1],
                  [19, 1],
                ],
                uri: Uri.parse('http://foo.bar'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '// Click here to learn more. https://go.microsoft.com/fwlink/?LinkID=513275&clcid=0x409',
            [
              (
                range: [
                  [30, 1],
                  [7, 2],
                ],
                uri: Uri.parse(
                  'https://go.microsoft.com/fwlink/?LinkID=513275&clcid=0x409',
                ),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '// Click here to learn more. https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx',
            [
              (
                range: [
                  [30, 1],
                  [28, 2],
                ],
                uri: Uri.parse(
                  'https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx',
                ),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '// https://github.com/projectkudu/kudu/blob/master/Kudu.Core/Scripts/selectNodeVersion.js',
            [
              (
                range: [
                  [4, 1],
                  [9, 2],
                ],
                uri: Uri.parse(
                  'https://github.com/projectkudu/kudu/blob/master/Kudu.Core/Scripts/selectNodeVersion.js',
                ),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '<!-- !!! Do not remove !!!   WebContentRef(link:https://go.microsoft.com/fwlink/?LinkId=166007, area:Admin, updated:2015, nextUpdate:2016, tags:SqlServer)   !!! Do not remove !!! -->',
            [
              (
                range: [
                  [49, 1],
                  [14, 2],
                ],
                uri: Uri.parse(
                  'https://go.microsoft.com/fwlink/?LinkId=166007',
                ),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'For instructions, see https://go.microsoft.com/fwlink/?LinkId=166007.</value>',
            [
              (
                range: [
                  [23, 1],
                  [68, 1],
                ],
                uri: Uri.parse(
                  'https://go.microsoft.com/fwlink/?LinkId=166007',
                ),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'For instructions, see https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx.</value>',
            [
              (
                range: [
                  [23, 1],
                  [21, 2],
                ],
                uri: Uri.parse(
                  'https://msdn.microsoft.com/en-us/library/windows/desktop/aa365247(v=vs.85).aspx',
                ),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'x = "https://en.wikipedia.org/wiki/Zürich";',
            [
              (
                range: [
                  [6, 1],
                  [41, 1],
                ],
                uri: Uri.parse('https://en.wikipedia.org/wiki/Zürich'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '請參閱 http://go.microsoft.com/fwlink/?LinkId=761051。',
            [
              (
                range: [
                  [8, 1],
                  [53, 1],
                ],
                uri: Uri.parse('http://go.microsoft.com/fwlink/?LinkId=761051'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '（請參閱 http://go.microsoft.com/fwlink/?LinkId=761051）',
            [
              (
                range: [
                  [10, 1],
                  [55, 1],
                ],
                uri: Uri.parse('http://go.microsoft.com/fwlink/?LinkId=761051'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.localFile,
            'x = "file:///foo.bar";',
            [
              (
                range: [
                  [6, 1],
                  [20, 1],
                ],
                uri: Uri.parse('file:///foo.bar'),
              ),
            ],
            Uri.parse('file:///foo.bar'),
          ),
          (
            TerminalBuiltinLinkType.localFile,
            'x = "file://c:/foo.bar";',
            [
              (
                range: [
                  [6, 1],
                  [22, 1],
                ],
                uri: Uri.parse('file://c:/foo.bar'),
              ),
            ],
            Uri.parse('file://c:/foo.bar'),
          ),
          (
            TerminalBuiltinLinkType.localFile,
            'x = "file://shares/foo.bar";',
            [
              (
                range: [
                  [6, 1],
                  [26, 1],
                ],
                uri: Uri.parse('file://shares/foo.bar'),
              ),
            ],
            Uri.parse('file://shares/foo.bar'),
          ),
          (
            TerminalBuiltinLinkType.localFile,
            'x = "file://shäres/foo.bar";',
            [
              (
                range: [
                  [6, 1],
                  [26, 1],
                ],
                uri: Uri.parse('file://shäres/foo.bar'),
              ),
            ],
            Uri.parse('file://shäres/foo.bar'),
          ),
          (
            TerminalBuiltinLinkType.url,
            'Some text, then http://www.bing.com.',
            [
              (
                range: [
                  [17, 1],
                  [35, 1],
                ],
                uri: Uri.parse('http://www.bing.com'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            "let url = `http://***/_api/web/lists/GetByTitle('Teambuildingaanvragen')/items`;",
            [
              (
                range: [
                  [12, 1],
                  [78, 1],
                ],
                uri: Uri.parse(
                  "http://***/_api/web/lists/GetByTitle('Teambuildingaanvragen')/items",
                ),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '7. At this point, ServiceMain has been called.  There is no functionality presently in ServiceMain, but you can consult the [MSDN documentation](https://msdn.microsoft.com/en-us/library/windows/desktop/ms687414(v=vs.85).aspx) to add functionality as desired!',
            [
              (
                range: [
                  [66, 2],
                  [64, 3],
                ],
                uri: Uri.parse(
                  'https://msdn.microsoft.com/en-us/library/windows/desktop/ms687414(v=vs.85).aspx',
                ),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'let x = "http://[::1]:5000/connect/token"',
            [
              (
                range: [
                  [10, 1],
                  [40, 1],
                ],
                uri: Uri.parse('http://[::1]:5000/connect/token'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            '2. Navigate to **https://portal.azure.com**',
            [
              (
                range: [
                  [18, 1],
                  [41, 1],
                ],
                uri: Uri.parse('https://portal.azure.com'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'POST|https://portal.azure.com|2019-12-05|',
            [
              (
                range: [
                  [6, 1],
                  [29, 1],
                ],
                uri: Uri.parse('https://portal.azure.com'),
              ),
            ],
            null,
          ),
          (
            TerminalBuiltinLinkType.url,
            'aa  https://foo.bar/[this is foo site]  aa',
            [
              (
                range: [
                  [5, 1],
                  [38, 1],
                ],
                uri: Uri.parse('https://foo.bar/[this is foo site]'),
              ),
            ],
            null,
          ),
        ];
    for (final c in linkComputerCases) {
      test('link computer case: `${c.$2}`', () async {
        validResources = c.$4 != null ? [c.$4!] : [];
        await assertLink(c.$1, c.$2, c.$3);
      });
    }

    test('should support multiple link results', () async {
      await assertLink(
        TerminalBuiltinLinkType.url,
        'http://foo.bar http://bar.foo',
        [
          (
            range: [
              [1, 1],
              [14, 1],
            ],
            uri: Uri.parse('http://foo.bar'),
          ),
          (
            range: [
              [16, 1],
              [29, 1],
            ],
            uri: Uri.parse('http://bar.foo'),
          ),
        ],
      );
    });
    test('should detect file:// links with :line suffix', () async {
      validResources = [uriFile('c:/folder/file')];
      await assertLink(
        TerminalBuiltinLinkType.localFile,
        'file:///c:/folder/file:23',
        [
          (
            range: [
              [1, 1],
              [25, 1],
            ],
            uri: Uri.parse('file:///c:/folder/file'),
          ),
        ],
      );
    });
    test('should detect file:// links with :line:col suffix', () async {
      validResources = [uriFile('c:/folder/file')];
      await assertLink(
        TerminalBuiltinLinkType.localFile,
        'file:///c:/folder/file:23:10',
        [
          (
            range: [
              [1, 1],
              [28, 1],
            ],
            uri: Uri.parse('file:///c:/folder/file'),
          ),
        ],
      );
    });
    test(
      'should filter out https:// link that exceed 4096 characters',
      () async {
        // 8 + 200 * 10 = 2008 characters
        await assertLink(
          TerminalBuiltinLinkType.url,
          'https://${'foobarbaz/' * 200}',
          [
            (
              range: [
                [1, 1],
                [8, 26],
              ],
              uri: Uri.parse('https://${'foobarbaz/' * 200}'),
            ),
          ],
        );
        // 8 + 450 * 10 = 4508 characters
        await assertLink(
          TerminalBuiltinLinkType.url,
          'https://${'foobarbaz/' * 450}',
          [],
        );
      },
    );
    test(
      'should filter out file:// links that exceed 4096 characters',
      () async {
        // 8 + 200 * 10 = 2008 characters
        validResources = [uriFile('/${'foobarbaz/' * 200}')];
        await assertLink(
          TerminalBuiltinLinkType.localFile,
          'file:///${'foobarbaz/' * 200}',
          [
            (
              uri: Uri.parse('file:///${'foobarbaz/' * 200}'),
              range: [
                [1, 1],
                [8, 26],
              ],
            ),
          ],
        );
        // 8 + 450 * 10 = 4508 characters
        validResources = [uriFile('/${'foobarbaz/' * 450}')];
        await assertLink(
          TerminalBuiltinLinkType.localFile,
          'file:///${'foobarbaz/' * 450}',
          [],
        );
      },
    );
  });
}
