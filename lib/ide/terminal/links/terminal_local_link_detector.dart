/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Finds paths to files and folders that exist in a wrapped line: absolute,
// relative to the cwd, `~/`, with the line and column suffixes of compilers
// and linters; then, when none is found, the formats that allow spaces in
// paths (Python tracebacks, C++ compilers, prompts, the whole line); then
// text styled apart (bold, underlined) that is a path.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/
// terminalLocalLinkDetector.ts. The capability store is [cwdForLine] (shell
// integration's cwd of a line, when known); workspace folders are paths; a
// link's URI is the `file:` URI of the path the resolver found.

import 'package:bao_xterm/typings/xterm_headless.dart';

import 'links.dart';
import 'terminal_link_helpers.dart';
import 'terminal_link_parsing.dart';
import 'terminal_link_resolver.dart';

abstract final class _Constants {
  /// The max line length to try extract word links from.
  static const int maxLineLength = 2000;

  /// The maximum number of links in a line to resolve against the file
  /// system. This limit is put in place to avoid sending excessive data when
  /// remote connections are in place.
  static const int maxResolvedLinksInLine = 10;

  /// The maximum length of a link to resolve against the file system. This
  /// limit is put in place to avoid sending excessive data when remote
  /// connections are in place.
  static const int maxResolvedLinkLength = 1024;
}

final List<RegExp> _fallbackMatchers = [
  // Python style error: File "<path>", line <line>
  RegExp(r'^ *File (?<link>"(?<path>.+)"(, line (?<line>\d+))?)'),
  // Unknown tool #200166: FILE  <path>:<line>:<col>
  RegExp(r'^ +FILE +(?<link>(?<path>.+)(?::(?<line>\d+)(?::(?<col>\d+))?)?)'),
  // Some C++ compile error formats:
  // C:\foo\bar baz(339) : error ...
  // C:\foo\bar baz(339,12) : error ...
  // C:\foo\bar baz(339, 12) : error ...
  // C:\foo\bar baz(339): error ...       [#178584, Visual Studio CL/NVIDIA CUDA compiler]
  // C:\foo\bar baz(339,12): ...
  // C:\foo\bar baz(339, 12): ...
  RegExp(r'^(?<link>(?<path>.+)\((?<line>\d+)(?:, ?(?<col>\d+))?\)) ?:'),
  // C:\foo/bar baz:339 : error ...
  // C:\foo/bar baz:339:12 : error ...
  // C:\foo/bar baz:339: error ...
  // C:\foo/bar baz:339:12: error ...     [#178584, Clang]
  RegExp(r'^(?<link>(?<path>.+):(?<line>\d+)(?::(?<col>\d+))?) ?:'),
  // PowerShell and cmd prompt
  RegExp(r'^(?:PS\s+)?(?<link>(?<path>[^>]+))>'),
  // The whole line is the path
  RegExp(r'^ *(?<link>(?<path>.+))'),
];

final RegExp _relativeDirectoryPrefix = RegExp(r'^(\.\.[\/\\])+');
final RegExp _specialEndCharRegex = RegExp(r'''[\[\]"'\.]$''');

/// The named [group] of [match], or null when the expression has no such
/// group (JavaScript's `groups.col` is undefined then; Dart throws).
String? namedGroupOrNull(RegExpMatch match, String group) =>
    match.groupNames.contains(group) ? match.namedGroup(group) : null;

class TerminalLocalLinkDetector implements ITerminalLinkDetector {
  TerminalLocalLinkDetector(
    this.xterm,
    this._processManager,
    this._linkResolver, {
    this._cwdForLine,
    this._workspaceFolders = const [],
  });

  static const String id = 'local';

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

  /// The cwd of the command whose output has buffer line `line` (the
  /// one-based y of a link's start, as upstream passes it), when shell
  /// integration knows it; upstream's command detection capability.
  final String? Function(int line)? _cwdForLine;
  final List<String> _workspaceFolders;

  OperatingSystem get _os => _processManager.os ?? hostOperatingSystem;

  @override
  Future<List<TerminalSimpleLink>> detect(
    List<IBufferLine> lines,
    int startLine,
    int endLine,
  ) async {
    final links = <TerminalSimpleLink>[];

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

    var stringIndex = -1;
    var resolvedLinkCount = 0;

    final os = _os;
    final parsedLinks = detectLinks(text, os);
    for (final parsedLink in parsedLinks) {
      // Don't try resolve any links of excessive length
      if (parsedLink.path.text.length > _Constants.maxResolvedLinkLength) {
        continue;
      }

      // Convert the link text's string index into a wrapped buffer range
      final bufferRange = convertLinkRangeToBuffer(lines, xterm.cols, (
        startColumn: (parsedLink.prefix?.index ?? parsedLink.path.index) + 1,
        startLineNumber: 1,
        endColumn:
            parsedLink.path.index +
            parsedLink.path.text.length +
            (parsedLink.suffix?.suffix.text.length ?? 0) +
            1,
        endLineNumber: 1,
      ), startLine);

      // Get a single link candidate if the cwd of the line is known
      final linkCandidates = <String>[];
      final osPath = osPathModule(os);
      final isUri = parsedLink.path.text.startsWith('file://');
      if (osPath.isAbsolute(parsedLink.path.text) ||
          parsedLink.path.text.startsWith('~') ||
          isUri) {
        linkCandidates.add(parsedLink.path.text);
      } else {
        final cwdForLine = _cwdForLine;
        if (cwdForLine != null) {
          final absolutePath = updateLinkWithRelativeCwd(
            cwdForLine(bufferRange.start.y),
            parsedLink.path.text,
            osPath,
          );
          // Only add a single exact link candidate if the cwd is available,
          // this may cause the link to not be resolved but that should only
          // occur when the actual file does not exist. Doing otherwise could
          // cause unexpected results where handling via the word link
          // detector is preferable.
          if (absolutePath != null) {
            linkCandidates.addAll(absolutePath);
          }
        }
        // Fallback to resolving against the initial cwd, removing any
        // relative directory prefixes
        if (linkCandidates.isEmpty) {
          linkCandidates.add(parsedLink.path.text);
          if (_relativeDirectoryPrefix.hasMatch(parsedLink.path.text)) {
            linkCandidates.add(
              parsedLink.path.text.replaceFirst(_relativeDirectoryPrefix, ''),
            );
          }
        }
      }

      // If any candidates end with special characters that are likely to not
      // be part of the link, add a candidate excluding them.
      final trimRangeMap = <String, int>{};
      final specialEndLinkCandidates = <String>[];
      for (final candidate in linkCandidates) {
        var previous = candidate;
        var removed = previous.replaceFirst(_specialEndCharRegex, '');
        var trimRange = 0;
        while (removed != previous) {
          // Only trim the link if there is no suffix, otherwise the
          // underline would be incorrect
          if (parsedLink.suffix == null) {
            trimRange++;
          }
          specialEndLinkCandidates.add(removed);
          trimRangeMap[removed] = trimRange;
          previous = removed;
          removed = removed.replaceFirst(_specialEndCharRegex, '');
        }
      }
      linkCandidates.addAll(specialEndLinkCandidates);

      // Validate the path and convert to the outgoing type
      final simpleLink = await _validateAndGetLink(
        null,
        bufferRange,
        linkCandidates,
        trimRangeMap,
      );
      if (simpleLink != null) {
        simpleLink.parsedLink = parsedLink;
        final suffix = parsedLink.suffix;
        simpleLink.text = text.substring(
          parsedLink.prefix?.index ?? parsedLink.path.index,
          suffix != null
              ? suffix.suffix.index + suffix.suffix.text.length
              : parsedLink.path.index + parsedLink.path.text.length,
        );
        links.add(simpleLink);
      }

      // Stop early if too many links exist in the line
      if (++resolvedLinkCount >= _Constants.maxResolvedLinksInLine) {
        break;
      }
    }

    // Match against the fallback matchers which are mainly designed to catch
    // paths with spaces that aren't possible using the regular mechanism.
    if (links.isEmpty) {
      for (final matcher in _fallbackMatchers) {
        final match = matcher.firstMatch(text);
        if (match == null) {
          continue;
        }
        final link = namedGroupOrNull(match, 'link');
        final path = namedGroupOrNull(match, 'path');
        final line = namedGroupOrNull(match, 'line');
        final col = namedGroupOrNull(match, 'col');
        if (link == null || link.isEmpty || path == null || path.isEmpty) {
          continue;
        }

        // Don't try resolve any links of excessive length
        if (link.length > _Constants.maxResolvedLinkLength) {
          continue;
        }

        // Convert the link text's string index into a wrapped buffer range
        stringIndex = text.indexOf(link);
        final bufferRange = convertLinkRangeToBuffer(lines, xterm.cols, (
          startColumn: stringIndex + 1,
          startLineNumber: 1,
          endColumn: stringIndex + link.length + 1,
          endLineNumber: 1,
        ), startLine);

        // Validate and add link
        final suffix = line != null && line.isNotEmpty
            ? ':$line${col != null && col.isNotEmpty ? ':$col' : ''}'
            : '';
        final simpleLink = await _validateAndGetLink(
          '$path$suffix',
          bufferRange,
          [path],
        );
        if (simpleLink != null) {
          links.add(simpleLink);
        }
      }
    }

    // Sometimes links are styled specially in the terminal like underlined
    // or bolded, try split the line by attributes and test whether it matches
    // a path
    if (links.isEmpty) {
      final rangeCandidates = getXtermRangesByAttr(
        xterm.buffer.active,
        startLine,
        endLine,
        xterm.cols,
      );
      for (final rangeCandidate in rangeCandidates) {
        var text = '';
        for (var y = rangeCandidate.start.y; y <= rangeCandidate.end.y; y++) {
          final line = xterm.buffer.active.getLine(y);
          if (line == null) {
            break;
          }
          final lineStartX = y == rangeCandidate.start.y
              ? rangeCandidate.start.x
              : 0;
          final lineEndX = y == rangeCandidate.end.y
              ? rangeCandidate.end.x
              : xterm.cols - 1;
          text += line.translateToString(false, lineStartX, lineEndX);
        }

        // HACK: Adjust to 1-based for link API
        rangeCandidate.start.x++;
        rangeCandidate.start.y++;
        rangeCandidate.end.y++;

        // Validate and add link
        final simpleLink = await _validateAndGetLink(text, rangeCandidate, [
          text,
        ]);
        if (simpleLink != null) {
          links.add(simpleLink);
        }

        // Stop early if too many links exist in the line
        if (++resolvedLinkCount >= _Constants.maxResolvedLinksInLine) {
          break;
        }
      }
    }

    return links;
  }

  Future<({String link, ResolvedTerminalLink stat})?> _validateLinkCandidates(
    List<String> linkCandidates,
  ) async {
    for (final link in linkCandidates) {
      final result = await _linkResolver.resolve(
        link,
        _processManager.initialCwd,
      );
      if (result != null) {
        return (link: link, stat: result);
      }
    }
    return null;
  }

  /// Validates a set of link candidates and returns a link if validated.
  ///
  /// [linkText] is the link text, this should be null to use the link stat
  /// value. [trimRangeMap] is a map of link candidates to the amount of
  /// buffer range they need trimmed.
  Future<TerminalSimpleLink?> _validateAndGetLink(
    String? linkText,
    IBufferRange bufferRange,
    List<String> linkCandidates, [
    Map<String, int>? trimRangeMap,
  ]) async {
    final linkStat = await _validateLinkCandidates(linkCandidates);
    if (linkStat != null) {
      final os = _os;
      final type = getTerminalLinkType(
        linkStat.stat.path,
        linkStat.stat.isDirectory,
        _workspaceFolders,
        os,
      );

      // Offset the buffer range if the link range was trimmed
      final trimRange = trimRangeMap?[linkStat.link];
      if (trimRange != null && trimRange != 0) {
        bufferRange.end.x -= trimRange;
        if (bufferRange.end.x < 0) {
          bufferRange.end.y--;
          bufferRange.end.x += xterm.cols;
        }
      }

      return TerminalSimpleLink(
        text: linkText ?? linkStat.link,
        uri: pathToFileUri(linkStat.stat.path, os),
        bufferRange: bufferRange,
        type: type,
      );
    }
    return null;
  }
}

/// A folder is in the workspace when it is one of [workspaceFolders] or
/// inside one (upstream's `extUri.isEqualOrParent` over the workspace
/// context's folders).
TerminalBuiltinLinkType getTerminalLinkType(
  String path,
  bool isDirectory,
  List<String> workspaceFolders,
  OperatingSystem os,
) {
  if (isDirectory) {
    // Check if directory is inside workspace
    final osPath = osPathContext(os);
    for (final folder in workspaceFolders) {
      if (osPath.equals(path, folder) || osPath.isWithin(folder, path)) {
        return TerminalBuiltinLinkType.localFolderInWorkspace;
      }
    }
    return TerminalBuiltinLinkType.localFolderOutsideWorkspace;
  } else {
    return TerminalBuiltinLinkType.localFile;
  }
}
