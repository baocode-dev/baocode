/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Links whose path is on an earlier line: ripgrep's and ESLint's
// `16:5 ...` under the file's name, and Git diff hunks (`@@ -8,11 +8,11 @@`)
// under `+++ b/<path>`.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/
// terminalMultiLineLinkDetector.ts. Workspace folders are paths; a link's
// URI is the `file:` URI of the path the resolver found.

import '../xterm/typings/xterm_headless.dart';
import 'links.dart';
import 'terminal_link_helpers.dart';
import 'terminal_link_resolver.dart';
import 'terminal_local_link_detector.dart';

abstract final class _Constants {
  /// The max line length to try extract word links from.
  static const int maxLineLength = 2000;

  /// The maximum length of a link to resolve against the file system. This
  /// limit is put in place to avoid sending excessive data when remote
  /// connections are in place.
  static const int maxResolvedLinkLength = 1024;
}

final List<RegExp> _lineNumberPrefixMatchers = [
  // Ripgrep:
  //   /some/file
  //   16:searchresult
  //   16:    searchresult
  // Eslint:
  //   /some/file
  //     16:5  error ...
  RegExp(r'^ *(?<link>(?<line>\d+):(?<col>\d+)?)'),
];

final List<RegExp> _gitDiffMatchers = [
  // --- a/some/file
  // +++ b/some/file
  // @@ -8,11 +8,11 @@ file content...
  RegExp(r'^(?<link>@@ .+ \+(?<toFileLine>\d+),(?<toFileCount>\d+) @@)'),
];

final RegExp _startsWithDigit = RegExp(r'^\s*\d');
final RegExp _gitDiffToFile = RegExp(r'\+\+\+ b\/(?<path>.+)');

class TerminalMultiLineLinkDetector implements ITerminalLinkDetector {
  TerminalMultiLineLinkDetector(
    this.xterm,
    this._processManager,
    this._linkResolver, {
    this._workspaceFolders = const [],
  });

  static const String id = 'multiline';

  // This was chosen as a reasonable maximum line length given the tradeoff
  // between performance and how likely it is to encounter such a large line
  // length. Some useful reference points:
  // - Window old max length: 260 ($MAX_PATH)
  // - Linux max length: 4096 ($PATH_MAX)
  @override
  final int maxLinkLength = 500;

  @override
  final Terminal xterm;

  final TerminalLinkProcessInfo _processManager;
  final TerminalLinkResolver _linkResolver;
  final List<String> _workspaceFolders;

  @override
  Future<List<TerminalSimpleLink>> detect(
    List<IBufferLine> lines,
    int startLine,
    int endLine,
  ) async {
    final links = <TerminalSimpleLink>[];
    final os = _processManager.os ?? hostOperatingSystem;

    // Get the text representation of the wrapped line
    final text = getXtermLineContent(
      xterm.buffer.active,
      startLine,
      endLine,
      xterm.cols,
    );
    if (text == '' || text.length > _Constants.maxLineLength) {
      return [];
    }

    // Match against the fallback matchers which are mainly designed to catch
    // paths with spaces that aren't possible using the regular mechanism.
    for (final matcher in _lineNumberPrefixMatchers) {
      final match = matcher.firstMatch(text);
      if (match == null) {
        continue;
      }
      final link = namedGroupOrNull(match, 'link');
      final line = namedGroupOrNull(match, 'line');
      final col = namedGroupOrNull(match, 'col');
      if (link == null || link.isEmpty || line == null) {
        continue;
      }

      // Don't try resolve any links of excessive length
      if (link.length > _Constants.maxResolvedLinkLength) {
        continue;
      }

      // Scan up looking for the first line that could be a path
      String? possiblePath;
      for (var index = startLine - 1; index >= 0; index--) {
        // Ignore lines that aren't at the beginning of a wrapped line
        if (xterm.buffer.active.getLine(index)?.isWrapped ?? false) {
          continue;
        }
        final text = getXtermLineContent(
          xterm.buffer.active,
          index,
          index,
          xterm.cols,
        );
        if (!_startsWithDigit.hasMatch(text)) {
          possiblePath = text;
          break;
        }
      }
      if (possiblePath == null || possiblePath.isEmpty) {
        continue;
      }

      // Check if the first non-matching line is an absolute or relative link
      final linkStat = await _linkResolver.resolve(
        possiblePath,
        _processManager.initialCwd,
      );
      if (linkStat != null) {
        final type = getTerminalLinkType(
          linkStat.path,
          linkStat.isDirectory,
          _workspaceFolders,
          os,
        );

        // Convert the entire line's text string index into a wrapped buffer
        // range
        final bufferRange = convertLinkRangeToBuffer(lines, xterm.cols, (
          startColumn: 1,
          startLineNumber: 1,
          endColumn: 1 + text.length,
          endLineNumber: 1,
        ), startLine);

        final simpleLink = TerminalSimpleLink(
          text: link,
          uri: pathToFileUri(linkStat.path, os),
          selection: (
            startLineNumber: int.parse(line),
            startColumn: col != null && col.isNotEmpty ? int.parse(col) : 1,
            endLineNumber: null,
            endColumn: null,
          ),
          disableTrimColon: true,
          bufferRange: bufferRange,
          type: type,
        );
        links.add(simpleLink);

        // Break on the first match
        break;
      }
    }

    if (links.isEmpty) {
      for (final matcher in _gitDiffMatchers) {
        final match = matcher.firstMatch(text);
        if (match == null) {
          continue;
        }
        final link = namedGroupOrNull(match, 'link');
        final toFileLine = namedGroupOrNull(match, 'toFileLine');
        final toFileCount = namedGroupOrNull(match, 'toFileCount');
        if (link == null || link.isEmpty || toFileLine == null) {
          continue;
        }

        // Don't try resolve any links of excessive length
        if (link.length > _Constants.maxResolvedLinkLength) {
          continue;
        }

        // Scan up looking for the first line that could be a path
        String? possiblePath;
        for (var index = startLine - 1; index >= 0; index--) {
          // Ignore lines that aren't at the beginning of a wrapped line
          if (xterm.buffer.active.getLine(index)?.isWrapped ?? false) {
            continue;
          }
          final text = getXtermLineContent(
            xterm.buffer.active,
            index,
            index,
            xterm.cols,
          );
          final match = _gitDiffToFile.firstMatch(text);
          if (match != null) {
            possiblePath = match.namedGroup('path');
            break;
          }
        }
        if (possiblePath == null || possiblePath.isEmpty) {
          continue;
        }

        // Check if the first non-matching line is an absolute or relative
        // link
        final linkStat = await _linkResolver.resolve(
          possiblePath,
          _processManager.initialCwd,
        );
        if (linkStat != null) {
          final type = getTerminalLinkType(
            linkStat.path,
            linkStat.isDirectory,
            _workspaceFolders,
            os,
          );

          // Convert the link to the buffer range
          final bufferRange = convertLinkRangeToBuffer(lines, xterm.cols, (
            startColumn: 1,
            startLineNumber: 1,
            endColumn: 1 + link.length,
            endLineNumber: 1,
          ), startLine);

          final simpleLink = TerminalSimpleLink(
            text: link,
            uri: pathToFileUri(linkStat.path, os),
            selection: (
              startLineNumber: int.parse(toFileLine),
              startColumn: 1,
              endLineNumber:
                  int.parse(toFileLine) + int.parse(toFileCount ?? '0'),
              endColumn: null,
            ),
            bufferRange: bufferRange,
            type: type,
          );
          links.add(simpleLink);

          // Break on the first match
          break;
        }
      }
    }

    return links;
  }
}
