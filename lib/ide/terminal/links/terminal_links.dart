/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The terminal's links, for the renderer's hover and ⌘-click: the links of
// a buffer row's wrapped line from the detectors in VS Code's order of
// priority (multi-line, local paths, URIs, words), and the one under a cell.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/
// terminalLinkManager.ts (the detectors and their order,
// `terminal.integrated.enableFileLinks`), terminalLinkDetectorAdapter.ts
// (the wrapped line around a row, the trailing colon, the hover labels),
// terminalLinkOpeners.ts (the line and column a file link opens at, the
// text a word link searches for), and xterm.js c58ea36
// src/browser/Linkifier.ts (the link at a position, lower-priority links
// that overlap higher ones dropped).
//
// Not here: opening links, the hover widget and its modifier tracking, the
// link quick pick (`getLinks`, `openRecentLink`), extension link providers
// and OSC 8 hyperlinks. The renderer caches a row's links while the mouse
// stays on it, as xterm.js' linkifier does.

import 'dart:async';
import 'dart:math' as math;

import '../xterm/typings/xterm_headless.dart';
import 'links.dart';
import 'terminal_link_parsing.dart';
import 'terminal_link_resolver.dart';
import 'terminal_local_link_detector.dart';
import 'terminal_multi_line_link_detector.dart';
import 'terminal_uri_link_detector.dart';
import 'terminal_word_link_detector.dart';

/// What activating a link does.
enum TerminalLinkType {
  /// Open [TerminalLink.uri] in the browser (or the app for its scheme).
  url,

  /// Open [TerminalLink.path] in the editor at [TerminalLink.line] and
  /// [TerminalLink.column].
  localFile,

  /// Reveal [TerminalLink.path] in the explorer
  /// ([TerminalLink.inWorkspace]) or open it.
  localFolder,

  /// Search the workspace for [TerminalLink.searchText] (quick open).
  search,
}

/// A link in the terminal.
class TerminalLink {
  TerminalLink({
    required this.range,
    required this.text,
    required this.type,
    this.inWorkspace = false,
    this.uri,
    this.path,
    this.line,
    this.column,
    this.endLine,
    this.endColumn,
    this.searchText,
  });

  /// The cells of the link, as xterm.js' `ILink.range`: one-based x and y
  /// (buffer line), the end inclusive.
  final IBufferRange range;

  /// The link's text as it appears in the terminal (for a URL, what to open:
  /// the raw text keeps pre-encoded characters).
  final String text;

  final TerminalLinkType type;

  /// For a [TerminalLinkType.localFolder]: whether it is in one of the
  /// workspace folders (VS Code reveals it in the explorer; otherwise it
  /// opens it in a new window).
  final bool inWorkspace;

  /// The URL, or the `file:` URI of a file or folder.
  final Uri? uri;

  /// The absolute path of a file or folder.
  final String? path;

  /// Where in the file to open, one-based; null when the link says nothing.
  final int? line;
  final int? column;
  final int? endLine;
  final int? endColumn;

  /// For a [TerminalLinkType.search] link: what to search for, the word with
  /// a `file://` or `./` prefix and trailing punctuation removed and the
  /// line and column its context gives appended (`foo.ts:12:5`).
  final String? searchText;

  /// Whether the link is shown on hover without the modifier (underline and
  /// tooltip): everything but words.
  bool get isHighConfidence => type != TerminalLinkType.search;

  /// The action the hover names, VS Code's label for the link's type.
  String get label => switch (type) {
    TerminalLinkType.search => 'Search workspace',
    TerminalLinkType.localFile => 'Open file in editor',
    TerminalLinkType.localFolder =>
      inWorkspace ? 'Focus folder in explorer' : 'Open folder in new window',
    TerminalLinkType.url => 'Follow link',
  };

  /// Whether the cell at one-based [x] and [y] is part of the link, as
  /// xterm.js' `_linkAtPosition` for a terminal [cols] wide.
  bool containsPosition(int x, int y, int cols) {
    final lower = range.start.y * cols + range.start.x;
    final upper = range.end.y * cols + range.end.x;
    final current = y * cols + x;
    return lower <= current && current <= upper;
  }

  @override
  String toString() => 'TerminalLink($type, "$text", $range)';
}

/// Finds the links of a terminal's buffer.
class TerminalLinkDetection {
  TerminalLinkDetection(
    this.xterm, {
    required TerminalLinkResolver resolver,
    String initialCwd = '',
    OperatingSystem? os,
    String wordSeparators = terminalDefaultWordSeparators,
    bool enableFileLinks = true,
    String? Function(int line)? cwdForLine,
    this.workspaceFolders = const [],
    String? urlProtocol,
  }) : _processInfo = TerminalLinkProcessInfo(initialCwd: initialCwd, os: os) {
    _wordDetector = TerminalWordLinkDetector(
      xterm,
      wordSeparators: wordSeparators,
      urlProtocol: urlProtocol,
    );
    // Setup link detectors in their order of priority
    detectors = [
      if (enableFileLinks) ...[
        TerminalMultiLineLinkDetector(
          xterm,
          _processInfo,
          resolver,
          workspaceFolders: workspaceFolders,
        ),
        TerminalLocalLinkDetector(
          xterm,
          _processInfo,
          resolver,
          cwdForLine: cwdForLine,
          workspaceFolders: workspaceFolders,
        ),
      ],
      TerminalUriLinkDetector(
        xterm,
        _processInfo,
        resolver,
        workspaceFolders: workspaceFolders,
      ),
      _wordDetector,
    ];
  }

  final Terminal xterm;

  /// The workspace's folders, absolute paths.
  final List<String> workspaceFolders;

  final TerminalLinkProcessInfo _processInfo;
  late final TerminalWordLinkDetector _wordDetector;

  /// The detectors, highest priority first.
  late final List<ITerminalLinkDetector> detectors;

  final Map<(int, int), Future<List<TerminalLink>>> _activeRequests = {};

  /// The directory relative paths resolve against: the process's initial
  /// cwd, empty until known.
  String get initialCwd => _processInfo.initialCwd;
  set initialCwd(String value) => _processInfo.initialCwd = value;

  /// `terminal.integrated.wordSeparators`.
  set wordSeparators(String value) => _wordDetector.wordSeparators = value;

  OperatingSystem get _os => _processInfo.os ?? hostOperatingSystem;

  /// The links of the wrapped line that buffer row [y] (0-based, absolute:
  /// the scrollback's first line is 0) is part of, highest priority first; a
  /// link that overlaps a higher priority one on row [y] is left out.
  Future<List<TerminalLink>> provideLinks(int y) async {
    final replies = [
      for (final reply in await _provideAll(y + 1)) [...reply],
    ];
    _removeIntersectingLinks(y + 1, replies);
    return [for (final reply in replies) ...reply];
  }

  /// The link at the cell in column [x] of buffer row [y] (both 0-based, [y]
  /// absolute), from the highest priority detector that has one there.
  Future<TerminalLink?> linkAt(int x, int y) async {
    final replies = await _provideAll(y + 1);
    for (final reply in replies) {
      for (final link in reply) {
        if (link.containsPosition(x + 1, y + 1, xterm.cols)) {
          return link;
        }
      }
    }
    return null;
  }

  Future<List<List<TerminalLink>>> _provideAll(int bufferLineNumber) {
    return Future.wait([
      for (var i = 0; i < detectors.length; i++)
        _provideLinksOnce(i, bufferLineNumber),
    ]);
  }

  Future<List<TerminalLink>> _provideLinksOnce(
    int detector,
    int bufferLineNumber,
  ) {
    final key = (detector, bufferLineNumber);
    final activeRequest = _activeRequests[key];
    if (activeRequest != null) {
      return activeRequest;
    }
    final request = _provideLinks(detectors[detector], bufferLineNumber);
    _activeRequests[key] = request;
    return request.whenComplete(() => _activeRequests.remove(key));
  }

  Future<List<TerminalLink>> _provideLinks(
    ITerminalLinkDetector detector,
    int bufferLineNumber,
  ) async {
    final buffer = detector.xterm.buffer.active;
    var startLine = bufferLineNumber - 1;
    var endLine = startLine;

    final line = buffer.getLine(startLine);
    if (line == null) {
      return [];
    }
    final lines = <IBufferLine>[line];

    // Cap the maximum context on either side of the line being provided, by
    // taking the context around the line being provided for this ensures the
    // line the pointer is on will have links provided.
    final cols = detector.xterm.cols;
    final maxCharacterContext = math.max(detector.maxLinkLength, cols);
    final maxLineContext = (maxCharacterContext / cols).ceil();
    final minStartLine = math.max(startLine - maxLineContext, 0);
    final maxEndLine = math.min(endLine + maxLineContext, buffer.length);

    while (startLine >= minStartLine &&
        (buffer.getLine(startLine)?.isWrapped ?? false)) {
      final previous = buffer.getLine(startLine - 1);
      if (previous == null) {
        break;
      }
      lines.insert(0, previous);
      startLine--;
    }

    while (endLine < maxEndLine &&
        (buffer.getLine(endLine + 1)?.isWrapped ?? false)) {
      lines.add(buffer.getLine(endLine + 1)!);
      endLine++;
    }

    final detectedLinks = await detector.detect(lines, startLine, endLine);
    return [for (final link in detectedLinks) _createTerminalLink(link)];
  }

  TerminalLink _createTerminalLink(TerminalSimpleLink l) {
    // Remove trailing colon if there is one so the link is more useful
    if (!l.disableTrimColon && l.text.isNotEmpty && l.text.endsWith(':')) {
      l.text = l.text.substring(0, l.text.length - 1);
      l.bufferRange.end.x--;
    }
    final os = _os;
    final uri = l.uri;
    final path = uri != null && uri.scheme == 'file'
        ? fileUriToPath(uri, os)
        : null;

    // The editor selection a file opens at, as TerminalLocalFileLinkOpener
    int? line, column, endLine, endColumn;
    if (path != null) {
      final selection = l.selection;
      if (selection != null) {
        line = selection.startLineNumber;
        column = selection.startColumn;
        endLine = selection.endLineNumber;
        endColumn = selection.endColumn;
      } else {
        final linkSuffix = l.parsedLink != null
            ? l.parsedLink!.suffix
            : getLinkSuffix(l.text);
        if (linkSuffix?.row != null) {
          line = linkSuffix!.row;
          column = linkSuffix.col ?? 1;
          endLine = linkSuffix.rowEnd;
          endColumn = linkSuffix.colEnd;
        }
      }
    }

    return TerminalLink(
      range: l.bufferRange,
      text: l.text,
      type: switch (l.type) {
        TerminalBuiltinLinkType.url => TerminalLinkType.url,
        TerminalBuiltinLinkType.localFile => TerminalLinkType.localFile,
        TerminalBuiltinLinkType.localFolderInWorkspace ||
        TerminalBuiltinLinkType.localFolderOutsideWorkspace =>
          TerminalLinkType.localFolder,
        TerminalBuiltinLinkType.search => TerminalLinkType.search,
      },
      inWorkspace: l.type == TerminalBuiltinLinkType.localFolderInWorkspace,
      uri: uri,
      path: path,
      line: line,
      column: column,
      endLine: endLine,
      endColumn: endColumn,
      searchText: l.type == TerminalBuiltinLinkType.search
          ? terminalSearchLinkText(
              l.text,
              contextLine: l.contextLine,
              os: os,
              workspaceFolders: workspaceFolders,
            )
          : null,
    );
  }

  /// Drops the links that overlap a higher priority provider's on row [y]
  /// (one-based), as xterm.js' `_removeIntersectingLinks`.
  void _removeIntersectingLinks(int y, List<List<TerminalLink>> replies) {
    final occupiedCells = <int>{};
    for (final providerReply in replies) {
      for (var i = 0; i < providerReply.length; i++) {
        final link = providerReply[i];
        final startX = link.range.start.y < y ? 0 : link.range.start.x;
        final endX = link.range.end.y > y ? xterm.cols : link.range.end.x;
        for (var x = startX; x <= endX; x++) {
          if (occupiedCells.contains(x)) {
            providerReply.removeAt(i--);
            break;
          }
          occupiedCells.add(x);
        }
      }
    }
  }
}

final RegExp _fileSchemePrefix = RegExp(r'^file:\/\/\/?');
final RegExp _relativePrefix = RegExp(r'^(\.+[\\/])+');
final RegExp _iso8601Pattern = RegExp(r':\d{2}:\d{2}[+-]\d{2}:\d{2}\.[a-z]+');
final RegExp _nonNumberSuffix = RegExp(r':[^\\/\d][^\d]*$');
final RegExp _trailingPeriod = RegExp(r'\.$');

/// What a word link searches the workspace for: the first half of VS Code's
/// `TerminalSearchLinkOpener.open` (before it looks for an exact match and
/// falls back to quick open with this text). [contextLine] is the word's
/// line, whose parsed links give the word a line and column;
/// [workspaceFolders]' names are removed from the start.
String terminalSearchLinkText(
  String linkText, {
  String? contextLine,
  required OperatingSystem os,
  List<String> workspaceFolders = const [],
}) {
  final osPath = osPathContext(os);
  final pathSeparator = osPath.separator;

  // Remove file:/// and any leading ./ or ../ since quick access doesn't
  // understand that format
  var text = linkText.replaceFirst(_fileSchemePrefix, '');
  text = osPath.normalize(text).replaceFirst(_relativePrefix, '');

  // Try extract any trailing line and column numbers by matching the text
  // against parsed links. This will give a search link `foo` on a line like
  // `"foo", line 10` to open the quick pick with `foo:10` as the contents.
  //
  // This also normalizes the path to remove suffixes like :10 or :5.0-4
  if (contextLine != null && contextLine.isNotEmpty) {
    // Skip suffix parsing if the text looks like it contains an ISO 8601
    // timestamp format
    if (!_iso8601Pattern.hasMatch(linkText)) {
      final parsedLinks = detectLinks(contextLine, os);
      // Optimistically check that the link _starts with_ the parsed link
      // text. If so, continue to use the parsed link
      for (final parsedLink in parsedLinks) {
        final suffix = parsedLink.suffix;
        if (suffix != null && linkText.startsWith(parsedLink.path.text)) {
          if (suffix.row != null) {
            // Normalize the path based on the parsed link
            text = parsedLink.path.text;
            text += ':${suffix.row}';
            if (suffix.col != null) {
              text += ':${suffix.col}';
            }
          }
          break;
        }
      }
    }
  }

  // Remove `:<one or more non number characters>` from the end of the link.
  // Examples:
  // - Ruby stack traces: <link>:in ...
  // - Grep output: <link>:<result line>
  // This only happens when the colon is _not_ followed by a forward- or
  // back-slash as that would break absolute Windows paths (eg. `C:/Users/...`).
  text = text.replaceFirst(_nonNumberSuffix, '');

  // Remove any trailing periods after the line/column numbers, to prevent
  // breaking the search feature, #200257
  // Examples:
  // "Check your code Test.tsx:12:45." -> Test.tsx:12:45
  // "Check your code Test.tsx:12." -> Test.tsx:12
  text = text.replaceFirst(_trailingPeriod, '');

  // If any of the names of the folders in the workspace matches a prefix of
  // the link, remove that prefix and continue
  for (final folder in workspaceFolders) {
    final name = osPath.basename(folder);
    if (text.startsWith('$name$pathSeparator')) {
      text = text.substring(name.length + 1);
    }
  }
  return text;
}
