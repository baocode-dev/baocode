/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/test/browser/
// terminalMultiLineLinkDetector.test.ts. The file service is a stat
// function over `validResources`; `URI.file` is [pathToFileUri] with the
// suite's OS. The Windows suite runs everywhere (upstream: only on
// Windows), as the port resolves paths by the process's OS.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/links/links.dart';
import 'package:baocode/ide/terminal/links/terminal_link_parsing.dart';
import 'package:baocode/ide/terminal/links/terminal_link_resolver.dart';
import 'package:baocode/ide/terminal/links/terminal_multi_line_link_detector.dart';
import 'package:baocode/ide/terminal/xterm/headless/public/terminal.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm_headless.dart'
    hide Terminal;

import 'link_test_utils.dart';

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
  // User home
  (link: '~/foo', resource: _posixFile('/home/foo')),
  // Relative
  (link: './foo', resource: _posixFile('/parent/cwd/foo')),
  (link: r'./$foo', resource: _posixFile(r'/parent/cwd/$foo')),
  (link: '../foo', resource: _posixFile('/parent/foo')),
  (link: 'foo/bar', resource: _posixFile('/parent/cwd/foo/bar')),
  (link: 'foo/bar+more', resource: _posixFile('/parent/cwd/foo/bar+more')),
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

final List<LinkFormatInfo> supportedLinkFormats = [
  // 5: file content...                         [#181837]
  //   5:3  error                               [#181837]
  const LinkFormatInfo(urlFormat: '{0}\r\n{1}:foo', line: '5'),
  const LinkFormatInfo(urlFormat: '{0}\r\n{1}: foo', line: '5'),
  const LinkFormatInfo(
    urlFormat: '{0}\r\n5:another link\r\n{1}:{2} foo',
    line: '5',
    column: '3',
  ),
  const LinkFormatInfo(
    urlFormat: '{0}\r\n  {1}:{2} foo',
    line: '5',
    column: '3',
  ),
  const LinkFormatInfo(
    urlFormat: '{0}\r\n  5:6  error  another one\r\n  {1}:{2}  error',
    line: '5',
    column: '3',
  ),
  LinkFormatInfo(
    urlFormat: '{0}\r\n  5:6  error  ${'a' * 80}\r\n  {1}:{2}  error',
    line: '5',
    column: '3',
  ),

  // @@ ... <to-file-range> @@ content...       [#182878]   (tests check the entire line, so they don't include the line content at the end of the last @@)
  const LinkFormatInfo(urlFormat: '+++ b/{0}\r\n@@ -7,6 +{1},7 @@', line: '5'),
  const LinkFormatInfo(
    urlFormat:
        '+++ b/{0}\r\n@@ -1,1 +1,1 @@\r\nfoo\r\nbar\r\n@@ -7,6 +{1},7 @@',
    line: '5',
  ),
];

String _link(Object l) =>
    l is String ? l : (l as ({String link, Uri resource})).link;

Uri _resource(Object l, Uri Function(String) file) =>
    l is String ? file(l) : (l as ({String link, Uri resource})).resource;

void main() {
  group('Workbench - TerminalMultiLineLinkDetector', () {
    late TerminalMultiLineLinkDetector detector;
    late Terminal xterm;
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

    Future<void> assertLinksMain(String link, [Uri? resource]) async {
      final uri = resource ?? _posixFile(link);
      final lines = link.split('\r\n');
      final lastLine = lines.last;
      // Count lines, accounting for wrapping
      var lineCount = 0;
      for (final line in lines) {
        lineCount += math.max((line.length / 80).ceil(), 1);
      }
      await assertLinks(TerminalBuiltinLinkType.localFile, link, [
        (
          uri: uri,
          range: [
            [1, lineCount],
            [lastLine.length, lineCount],
          ],
        ),
      ]);
    }

    TerminalMultiLineLinkDetector createDetector(OperatingSystem os) {
      final windows = os == OperatingSystem.windows;
      return TerminalMultiLineLinkDetector(
        xterm,
        TerminalLinkProcessInfo(
          initialCwd: windows ? r'C:\Parent\Cwd' : '/parent/cwd',
          os: os,
        ),
        TerminalFileLinkResolver(
          os: os,
          userHome: windows ? r'C:\Home' : '/home',
          stat: fakeStat(() => validResources, os),
        ),
      );
    }

    setUp(() {
      validResources = [];

      xterm = Terminal(
        ITerminalOptions(allowProposedApi: true, cols: 80, rows: 30),
      );
    });

    tearDown(() {
      xterm.dispose();
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
            test(
              'should detect in "${escapeMultilineTestName(formattedLink)}"',
              () async {
                validResources = [resource];
                await assertLinksMain(formattedLink, resource);
              },
            );
          }
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
            test(
              'should detect in "${escapeMultilineTestName(formattedLink)}"',
              () async {
                validResources = [resource];
                await assertLinksMain(formattedLink, resource);
              },
            );
          }
        });
      }
    });
  });
}

String escapeMultilineTestName(String text) {
  return text.replaceAll('\r\n', r'\r\n');
}
