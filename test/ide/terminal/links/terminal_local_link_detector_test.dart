/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/test/browser/
// terminalLocalLinkDetector.test.ts. The file service is a stat function
// over the files set; `URI.file` is Dart's `Uri.file` with the suite's path
// syntax.
//
// Upstream runs the Windows suite only on Windows (its URIs' separators
// follow the host); the port resolves paths by the process's OS, so the
// suite runs everywhere. Its WSL `/mnt/` test is skipped: there is no WSL
// backend.

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/links/links.dart';
import 'package:monad/ide/terminal/links/terminal_link_parsing.dart';
import 'package:monad/ide/terminal/links/terminal_link_resolver.dart';
import 'package:monad/ide/terminal/links/terminal_local_link_detector.dart';
import 'package:monad/ide/terminal/xterm/headless/public/terminal.dart';
import 'package:monad/ide/terminal/xterm/typings/xterm_headless.dart'
    hide Terminal;

import 'link_test_utils.dart';

// VS Code's `URI.file` for the suite's OS.
Uri _posixFile(String path) => pathToFileUri(path, OperatingSystem.linux);
Uri _windowsFile(String path) => pathToFileUri(path, OperatingSystem.windows);

final List<Object> unixLinks = [
  // Absolute
  '/foo',
  '/foo/bar',
  '/foo/[bar]',
  '/foo/[bar].baz',
  '/foo/[bar]/baz',
  '/foo/bar+more',
  // URI file://
  (link: 'file:///foo', resource: _posixFile('/foo')),
  (link: 'file:///foo/bar', resource: _posixFile('/foo/bar')),
  (link: 'file:///foo/bar%20baz', resource: _posixFile('/foo/bar baz')),
  // User home
  (link: '~/foo', resource: _posixFile('/home/foo')),
  // Relative
  (link: './foo', resource: _posixFile('/parent/cwd/foo')),
  (link: r'./$foo', resource: _posixFile(r'/parent/cwd/$foo')),
  (link: '../foo', resource: _posixFile('/parent/foo')),
  (link: 'foo/bar', resource: _posixFile('/parent/cwd/foo/bar')),
  (link: 'foo/bar+more', resource: _posixFile('/parent/cwd/foo/bar+more')),
];

final List<Object> unixLinksWithIso = [
  // ISO 8601 timestamps - tested separately to avoid line/column suffix
  // conflicts
  (
    link: './test-2025-04-28T11:03:09+02:00.log',
    resource: _posixFile('/parent/cwd/test-2025-04-28T11:03:09+02:00.log'),
  ),
];

final List<Object> windowsLinks = [
  // Absolute
  r'c:\foo',
  (link: r'\\?\C:\foo', resource: _windowsFile(r'C:\foo')),
  'c:/foo',
  'c:/foo/bar',
  r'c:\foo\bar',
  r'c:\foo\bar+more',
  r'c:\foo/bar\baz',
  // URI file://
  (link: 'file:///c:/foo', resource: _windowsFile(r'c:\foo')),
  (link: 'file:///c:/foo/bar', resource: _windowsFile(r'c:\foo\bar')),
  (link: 'file:///c:/foo/bar%20baz', resource: _windowsFile(r'c:\foo\bar baz')),
  // User home
  (link: r'~\foo', resource: _windowsFile(r'C:\Home\foo')),
  (link: '~/foo', resource: _windowsFile(r'C:\Home\foo')),
  // Relative
  (link: r'.\foo', resource: _windowsFile(r'C:\Parent\Cwd\foo')),
  (link: './foo', resource: _windowsFile(r'C:\Parent\Cwd\foo')),
  (link: r'./$foo', resource: _windowsFile(r'C:\Parent\Cwd\$foo')),
  (link: r'..\foo', resource: _windowsFile(r'C:\Parent\foo')),
  (link: 'foo/bar', resource: _windowsFile(r'C:\Parent\Cwd\foo\bar')),
  (link: 'foo/bar', resource: _windowsFile(r'C:\Parent\Cwd\foo\bar')),
  (link: 'foo/[bar]', resource: _windowsFile(r'C:\Parent\Cwd\foo\[bar]')),
  (
    link: 'foo/[bar].baz',
    resource: _windowsFile(r'C:\Parent\Cwd\foo\[bar].baz'),
  ),
  (
    link: 'foo/[bar]/baz',
    resource: _windowsFile(r'C:\Parent\Cwd\foo\[bar]/baz'),
  ),
  (link: r'foo\bar', resource: _windowsFile(r'C:\Parent\Cwd\foo\bar')),
  (
    link: r'foo\[bar].baz',
    resource: _windowsFile(r'C:\Parent\Cwd\foo\[bar].baz'),
  ),
  (
    link: r'foo\[bar]\baz',
    resource: _windowsFile(r'C:\Parent\Cwd\foo\[bar]\baz'),
  ),
  (
    link: r'foo\bar+more',
    resource: _windowsFile(r'C:\Parent\Cwd\foo\bar+more'),
  ),
];

final List<Object> windowsLinksWithIso = [
  // ISO 8601 timestamps - tested separately to avoid line/column suffix
  // conflicts
  (
    link: r'.\test-2025-04-28T11:03:09+02:00.log',
    resource: _windowsFile(r'C:\Parent\Cwd\test-2025-04-28T11:03:09+02:00.log'),
  ),
];

class LinkFormatInfo {
  const LinkFormatInfo({
    required this.urlFormat,
    this.linkCellStartOffset,
    this.linkCellEndOffset,
    this.line,
    this.column,
  });

  final String urlFormat;

  /// The start offset to the buffer range that is not in the actual link
  /// (but is in the matched area.
  final int? linkCellStartOffset;

  /// The end offset to the buffer range that is not in the actual link (but
  /// is in the matched area.
  final int? linkCellEndOffset;
  final String? line;
  final String? column;
}

const List<LinkFormatInfo> supportedLinkFormats = [
  LinkFormatInfo(urlFormat: '{0}'),
  LinkFormatInfo(urlFormat: '{0}" on line {1}', line: '5'),
  LinkFormatInfo(
    urlFormat: '{0}" on line {1}, column {2}',
    line: '5',
    column: '3',
  ),
  LinkFormatInfo(urlFormat: '{0}":line {1}', line: '5'),
  LinkFormatInfo(
    urlFormat: '{0}":line {1}, column {2}',
    line: '5',
    column: '3',
  ),
  LinkFormatInfo(urlFormat: '{0}": line {1}', line: '5'),
  LinkFormatInfo(urlFormat: '{0}": line {1}, col {2}', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}({1})', line: '5'),
  LinkFormatInfo(urlFormat: '{0} ({1})', line: '5'),
  LinkFormatInfo(urlFormat: '{0}, {1}', line: '5'),
  LinkFormatInfo(urlFormat: '{0}({1},{2})', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0} ({1},{2})', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}: ({1},{2})', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}({1}, {2})', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0} ({1}, {2})', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}: ({1}, {2})', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}({1}:{2})', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0} ({1}:{2})', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}:{1}', line: '5'),
  LinkFormatInfo(urlFormat: '{0}:{1}:{2}', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0} {1}:{2}', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}[{1}]', line: '5'),
  LinkFormatInfo(urlFormat: '{0} [{1}]', line: '5'),
  LinkFormatInfo(urlFormat: '{0}[{1},{2}]', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0} [{1},{2}]', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}: [{1},{2}]', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}[{1}, {2}]', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0} [{1}, {2}]', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}: [{1}, {2}]', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}[{1}:{2}]', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0} [{1}:{2}]', line: '5', column: '3'),
  LinkFormatInfo(urlFormat: '{0}",{1}', line: '5'),
  LinkFormatInfo(urlFormat: "{0}',{1}", line: '5'),
  LinkFormatInfo(urlFormat: '{0}#{1}', line: '5'),
  LinkFormatInfo(urlFormat: '{0}#{1}:{2}', line: '5', column: '5'),
];

const List<Object> windowsFallbackLinks = [
  r'C:\foo bar',
  r'C:\foo bar\baz',
  r'C:\foo\bar baz',
  r'C:\foo/bar baz',
];

const List<LinkFormatInfo> supportedFallbackLinkFormats = [
  // Python style error: File "<path>", line <line>
  LinkFormatInfo(urlFormat: 'File "{0}"', linkCellStartOffset: 5),
  LinkFormatInfo(
    urlFormat: 'File "{0}", line {1}',
    line: '5',
    linkCellStartOffset: 5,
  ),
  // Unknown tool #200166: FILE  <path>:<line>:<col>
  LinkFormatInfo(urlFormat: ' FILE  {0}', linkCellStartOffset: 7),
  LinkFormatInfo(
    urlFormat: ' FILE  {0}:{1}',
    line: '5',
    linkCellStartOffset: 7,
  ),
  LinkFormatInfo(
    urlFormat: ' FILE  {0}:{1}:{2}',
    line: '5',
    column: '3',
    linkCellStartOffset: 7,
  ),
  // Some C++ compile error formats
  LinkFormatInfo(urlFormat: '{0}({1}) :', line: '5', linkCellEndOffset: -2),
  LinkFormatInfo(
    urlFormat: '{0}({1},{2}) :',
    line: '5',
    column: '3',
    linkCellEndOffset: -2,
  ),
  LinkFormatInfo(
    urlFormat: '{0}({1}, {2}) :',
    line: '5',
    column: '3',
    linkCellEndOffset: -2,
  ),
  LinkFormatInfo(urlFormat: '{0}({1}):', line: '5', linkCellEndOffset: -1),
  LinkFormatInfo(
    urlFormat: '{0}({1},{2}):',
    line: '5',
    column: '3',
    linkCellEndOffset: -1,
  ),
  LinkFormatInfo(
    urlFormat: '{0}({1}, {2}):',
    line: '5',
    column: '3',
    linkCellEndOffset: -1,
  ),
  LinkFormatInfo(urlFormat: '{0}:{1} :', line: '5', linkCellEndOffset: -2),
  LinkFormatInfo(
    urlFormat: '{0}:{1}:{2} :',
    line: '5',
    column: '3',
    linkCellEndOffset: -2,
  ),
  LinkFormatInfo(urlFormat: '{0}:{1}:', line: '5', linkCellEndOffset: -1),
  LinkFormatInfo(
    urlFormat: '{0}:{1}:{2}:',
    line: '5',
    column: '3',
    linkCellEndOffset: -1,
  ),
  // PowerShell prompt
  LinkFormatInfo(
    urlFormat: 'PS {0}>',
    linkCellStartOffset: 3,
    linkCellEndOffset: -1,
  ),
  // Cmd prompt
  LinkFormatInfo(urlFormat: '{0}>', linkCellEndOffset: -1),
  // The whole line is the path
  LinkFormatInfo(urlFormat: '{0}'),
];

String _link(Object l) =>
    l is String ? l : (l as ({String link, Uri resource})).link;

Uri _resource(Object l, Uri Function(String) file) =>
    l is String ? file(l) : (l as ({String link, Uri resource})).resource;

void main() {
  group('Workbench - TerminalLocalLinkDetector', () {
    late TerminalLocalLinkDetector detector;
    late Terminal xterm;
    // Upstream's TestFileService: every file exists until files are set.
    List<Uri>? files;
    late List<Uri> validResources;

    Future<void> assertLinks(
      TerminalBuiltinLinkType type,
      String text,
      List<({Uri uri, List<List<int>> range})> expected,
    ) async {
      final race = await Future.any([
        assertLinkHelper(text, expected, detector, type).then((_) => 'success'),
        Future<String>.delayed(
          const Duration(milliseconds: 2),
          () => 'timeout',
        ),
      ]);
      expect(
        race,
        'success',
        reason: 'Awaiting link assertion for "$text" timed out',
      );
    }

    Future<void> assertLinksWithWrapped(String link, [Uri? resource]) async {
      final uri = resource ?? _posixFile(link);
      await assertLinks(TerminalBuiltinLinkType.localFile, link, [
        (
          uri: uri,
          range: [
            [1, 1],
            [link.length, 1],
          ],
        ),
      ]);
      await assertLinks(TerminalBuiltinLinkType.localFile, ' $link ', [
        (
          uri: uri,
          range: [
            [2, 1],
            [link.length + 1, 1],
          ],
        ),
      ]);
      await assertLinks(TerminalBuiltinLinkType.localFile, '($link)', [
        (
          uri: uri,
          range: [
            [2, 1],
            [link.length + 1, 1],
          ],
        ),
      ]);
      await assertLinks(TerminalBuiltinLinkType.localFile, '[$link]', [
        (
          uri: uri,
          range: [
            [2, 1],
            [link.length + 1, 1],
          ],
        ),
      ]);
    }

    TerminalLocalLinkDetector createDetector(OperatingSystem os) {
      final windows = os == OperatingSystem.windows;
      return TerminalLocalLinkDetector(
        xterm,
        TerminalLinkProcessInfo(
          initialCwd: windows ? r'C:\Parent\Cwd' : '/parent/cwd',
          os: os,
        ),
        TerminalFileLinkResolver(
          os: os,
          userHome: windows ? r'C:\Home' : '/home',
          stat: fakeStat(() => files, os),
        ),
      );
    }

    setUp(() {
      files = null;
      validResources = [];

      xterm = Terminal(
        ITerminalOptions(allowProposedApi: true, cols: 80, rows: 30),
      );
    });

    tearDown(() {
      xterm.dispose();
    });

    group('platform independent', () {
      setUp(() {
        detector = createDetector(OperatingSystem.linux);
      });

      test('should support multiple link results', () async {
        validResources = [
          _posixFile('/parent/cwd/foo'),
          _posixFile('/parent/cwd/bar'),
        ];
        files = validResources;
        await assertLinks(TerminalBuiltinLinkType.localFile, './foo ./bar', [
          (
            range: [
              [1, 1],
              [5, 1],
            ],
            uri: _posixFile('/parent/cwd/foo'),
          ),
          (
            range: [
              [7, 1],
              [11, 1],
            ],
            uri: _posixFile('/parent/cwd/bar'),
          ),
        ]);
      });

      test('should support trimming extra quotes', () async {
        validResources = [_posixFile('/parent/cwd/foo')];
        files = validResources;
        await assertLinks(
          TerminalBuiltinLinkType.localFile,
          '"foo"" on line 5',
          [
            (
              range: [
                [1, 1],
                [16, 1],
              ],
              uri: _posixFile('/parent/cwd/foo'),
            ),
          ],
        );
      });

      test('should support trimming extra square brackets', () async {
        validResources = [_posixFile('/parent/cwd/foo')];
        files = validResources;
        await assertLinks(
          TerminalBuiltinLinkType.localFile,
          '"foo]" on line 5',
          [
            (
              range: [
                [1, 1],
                [16, 1],
              ],
              uri: _posixFile('/parent/cwd/foo'),
            ),
          ],
        );
      });

      test('should support finding links after brackets', () async {
        validResources = [_posixFile('/parent/cwd/foo')];
        files = validResources;
        await assertLinks(TerminalBuiltinLinkType.localFile, 'bar[foo:5', [
          (
            range: [
              [5, 1],
              [9, 1],
            ],
            uri: _posixFile('/parent/cwd/foo'),
          ),
        ]);
      });
    });

    group('macOS/Linux', () {
      setUp(() {
        detector = createDetector(OperatingSystem.linux);
      });

      for (final l in unixLinks) {
        final baseLink = _link(l);
        final resource = _resource(l, _posixFile);
        group('Link: $baseLink', () {
          for (var i = 0; i < supportedLinkFormats.length; i++) {
            final linkFormat = supportedLinkFormats[i];
            final formattedLink = format(linkFormat.urlFormat, [
              baseLink,
              linkFormat.line,
              linkFormat.column,
            ]);
            test('should detect in "$formattedLink"', () async {
              validResources = [resource];
              files = validResources;
              await assertLinksWithWrapped(formattedLink, resource);
            });
          }
        });
      }

      test('Git diff links', () async {
        validResources = [_posixFile('/parent/cwd/foo/bar')];
        files = validResources;
        await assertLinks(
          TerminalBuiltinLinkType.localFile,
          'diff --git a/foo/bar b/foo/bar',
          [
            (
              uri: validResources[0],
              range: [
                [14, 1],
                [20, 1],
              ],
            ),
            (
              uri: validResources[0],
              range: [
                [24, 1],
                [30, 1],
              ],
            ),
          ],
        );
        await assertLinks(TerminalBuiltinLinkType.localFile, '--- a/foo/bar', [
          (
            uri: validResources[0],
            range: [
              [7, 1],
              [13, 1],
            ],
          ),
        ]);
        await assertLinks(TerminalBuiltinLinkType.localFile, '+++ b/foo/bar', [
          (
            uri: validResources[0],
            range: [
              [7, 1],
              [13, 1],
            ],
          ),
        ]);
      });

      // Test ISO 8601 links separately with only base format to avoid suffix
      // conflicts
      // Note: Only test plain format as colons are excluded path characters
      // in the regex, so wrapped contexts (spaces, parentheses, brackets)
      // won't work
      for (final l in unixLinksWithIso) {
        final baseLink = _link(l);
        final resource = _resource(l, _posixFile);
        test('should detect ISO 8601 link: $baseLink', () async {
          validResources = [resource];
          files = validResources;
          await assertLinks(TerminalBuiltinLinkType.localFile, baseLink, [
            (
              uri: resource,
              range: [
                [1, 1],
                [baseLink.length, 1],
              ],
            ),
          ]);
        });
      }
    });

    group('Windows', () {
      setUp(() {
        detector = createDetector(OperatingSystem.windows);
      });

      for (final l in windowsLinks) {
        final baseLink = _link(l);
        final resource = _resource(l, _windowsFile);
        group('Link "$baseLink"', () {
          for (var i = 0; i < supportedLinkFormats.length; i++) {
            final linkFormat = supportedLinkFormats[i];
            final formattedLink = format(linkFormat.urlFormat, [
              baseLink,
              linkFormat.line,
              linkFormat.column,
            ]);
            test('should detect in "$formattedLink"', () async {
              validResources = [resource];
              files = validResources;
              await assertLinksWithWrapped(formattedLink, resource);
            });
          }
        });
      }

      for (final l in windowsFallbackLinks) {
        final baseLink = _link(l);
        final resource = _resource(l, _windowsFile);
        group('Fallback link "$baseLink"', () {
          for (var i = 0; i < supportedFallbackLinkFormats.length; i++) {
            final linkFormat = supportedFallbackLinkFormats[i];
            final formattedLink = format(linkFormat.urlFormat, [
              baseLink,
              linkFormat.line,
              linkFormat.column,
            ]);
            final linkCellStartOffset = linkFormat.linkCellStartOffset ?? 0;
            final linkCellEndOffset = linkFormat.linkCellEndOffset ?? 0;
            test('should detect in "$formattedLink"', () async {
              validResources = [resource];
              files = validResources;
              await assertLinks(
                TerminalBuiltinLinkType.localFile,
                formattedLink,
                [
                  (
                    uri: resource,
                    range: [
                      [1 + linkCellStartOffset, 1],
                      [formattedLink.length + linkCellEndOffset, 1],
                    ],
                  ),
                ],
              );
            });
          }
        });
      }

      test('Git diff links', () async {
        final resource = _windowsFile(r'C:\Parent\Cwd\foo\bar');
        validResources = [resource];
        files = validResources;
        await assertLinks(
          TerminalBuiltinLinkType.localFile,
          'diff --git a/foo/bar b/foo/bar',
          [
            (
              uri: resource,
              range: [
                [14, 1],
                [20, 1],
              ],
            ),
            (
              uri: resource,
              range: [
                [24, 1],
                [30, 1],
              ],
            ),
          ],
        );
        await assertLinks(TerminalBuiltinLinkType.localFile, '--- a/foo/bar', [
          (
            uri: resource,
            range: [
              [7, 1],
              [13, 1],
            ],
          ),
        ]);
        await assertLinks(TerminalBuiltinLinkType.localFile, '+++ b/foo/bar', [
          (
            uri: resource,
            range: [
              [7, 1],
              [13, 1],
            ],
          ),
        ]);
      });

      // Test ISO 8601 links separately with only base format to avoid suffix
      // conflicts
      // Note: Only test plain format as colons are excluded path characters
      // in the regex, so wrapped contexts (spaces, parentheses, brackets)
      // won't work
      for (final l in windowsLinksWithIso) {
        final baseLink = _link(l);
        final resource = _resource(l, _windowsFile);
        test('should detect ISO 8601 link: $baseLink', () async {
          validResources = [resource];
          files = validResources;
          await assertLinks(TerminalBuiltinLinkType.localFile, baseLink, [
            (
              uri: resource,
              range: [
                [1, 1],
                [baseLink.length, 1],
              ],
            ),
          ]);
        });
      }

      group('WSL', () {
        test(
          'Unix -> Windows /mnt/ style links',
          skip: 'No WSL backend to ask for wslpath',
          () async {
            validResources = [_windowsFile(r'C:\foo\bar')];
            files = validResources;
            await assertLinksWithWrapped('/mnt/c/foo/bar', validResources[0]);
          },
        );

        test(r'Windows -> Unix \\wsl$\ style links', () async {
          validResources = [_windowsFile(r'\\wsl$\Debian\home\foo\bar')];
          files = validResources;
          await assertLinksWithWrapped(
            r'\\wsl$\Debian\home\foo\bar',
            validResources[0],
          );
        });

        test(r'Windows -> Unix \\wsl.localhost\ style links', () async {
          validResources = [
            _windowsFile(r'\\wsl.localhost\Debian\home\foo\bar'),
          ];
          files = validResources;
          await assertLinksWithWrapped(
            r'\\wsl.localhost\Debian\home\foo\bar',
            validResources[0],
          );
        });
      });
    });
  });
}
