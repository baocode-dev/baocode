/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Finds URLs (`http://`, `https://`) and `file://` URIs in a wrapped line;
// a `file://` URI is a link only when the file or folder exists.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/
// terminalUriLinkDetector.ts. URIs are Dart's [Uri] (which drops an empty
// port and lower-cases the host: `file://c:/foo` is `file://c/foo`), so the
// "unrecognized authority" check reads the authority off the text. A URL
// Dart cannot parse is skipped (upstream's `URI.parse` accepts anything).
// Workspace folders are paths instead of the workspace context service.

import 'package:bao_xterm/typings/xterm_headless.dart';

import 'link_computer.dart';
import 'links.dart';
import 'terminal_link_helpers.dart';
import 'terminal_link_resolver.dart';
import 'terminal_local_link_detector.dart';

abstract final class _Constants {
  /// The maximum number of links in a line to resolve against the file
  /// system. This limit is put in place to avoid sending excessive data when
  /// remote connections are in place.
  static const int maxResolvedLinksInLine = 10;
}

final RegExp _lineAndColSuffix = RegExp(r':\d+(:\d+)?$');
final RegExp _authority = RegExp(r'^[^:/?#]+://([^/?#]*)');

class TerminalUriLinkDetector implements ITerminalLinkDetector {
  TerminalUriLinkDetector(
    this.xterm,
    this._processManager,
    this._linkResolver, {
    this._workspaceFolders = const [],
  });

  static const String id = 'uri';

  // 2048 is the maximum URL length
  @override
  final int maxLinkLength = 2048;

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

    final linkComputerTarget = _TerminalLinkAdapter(xterm, startLine, endLine);
    final computedLinks = LinkComputer.computeLinks(linkComputerTarget);

    var resolvedLinkCount = 0;
    for (final computedLink in computedLinks) {
      final bufferRange = convertLinkRangeToBuffer(
        lines,
        xterm.cols,
        computedLink.range,
        startLine,
      );

      // Check if the link is within the mouse position
      final uri = Uri.tryParse(_excludeLineAndColSuffix(computedLink.url));
      if (uri == null) {
        continue;
      }

      final text = computedLink.url;

      // Don't try resolve any links of excessive length
      if (text.length > maxLinkLength) {
        continue;
      }

      // Handle non-file scheme links
      if (uri.scheme != 'file') {
        links.add(
          TerminalSimpleLink(
            text: text,
            uri: uri,
            bufferRange: bufferRange,
            type: TerminalBuiltinLinkType.url,
          ),
        );
        continue;
      }

      // Filter out URI with unrecognized authorities
      final authority = _authority.firstMatch(text)?.group(1) ?? '';
      if (authority.length != 2 && authority.endsWith(':')) {
        continue;
      }

      // As a fallback URI, treat the authority as local to the workspace.
      // This is required for `ls --hyperlink` support for example which
      // includes the hostname in the URI like
      // `file://Some-Hostname/mnt/c/foo/bar`.
      final uriCandidates = <Uri>[uri];
      if (uri.authority.isNotEmpty) {
        uriCandidates.add(
          Uri(
            scheme: uri.scheme,
            path: uri.path,
            query: uri.hasQuery ? uri.query : null,
            fragment: uri.hasFragment ? uri.fragment : null,
          ),
        );
      }

      // Iterate over all candidates, pushing the candidate on the first
      // that's verified
      for (final uriCandidate in uriCandidates) {
        final linkStat = await _linkResolver.resolve(
          uriCandidate.toString(),
          _processManager.initialCwd,
        );

        // Create the link if validated
        if (linkStat != null) {
          final type = getTerminalLinkType(
            linkStat.path,
            linkStat.isDirectory,
            _workspaceFolders,
            _processManager.os ?? hostOperatingSystem,
          );
          links.add(
            TerminalSimpleLink(
              // Use computedLink.url to retain the line/col suffix
              text: computedLink.url,
              uri: uriCandidate,
              bufferRange: bufferRange,
              type: type,
            ),
          );
          resolvedLinkCount++;
          break;
        }
      }

      // Stop early if too many links exist in the line
      if (++resolvedLinkCount >= _Constants.maxResolvedLinksInLine) {
        break;
      }
    }

    return links;
  }

  String _excludeLineAndColSuffix(String path) {
    return path.replaceFirst(_lineAndColSuffix, '');
  }
}

class _TerminalLinkAdapter implements ILinkComputerTarget {
  _TerminalLinkAdapter(this._xterm, this._lineStart, this._lineEnd);

  final Terminal _xterm;
  final int _lineStart;
  final int _lineEnd;

  @override
  int getLineCount() {
    return 1;
  }

  @override
  String getLineContent(int lineNumber) {
    return getXtermLineContent(
      _xterm.buffer.active,
      _lineStart,
      _lineEnd,
      _xterm.cols,
    );
  }
}
