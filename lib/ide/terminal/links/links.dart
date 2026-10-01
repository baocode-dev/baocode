/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the terminal's link detectors share: the detector interface, the
// links they find, their types, and what they know of the terminal's
// process.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/links.ts.
// `ITerminalLinkResolver` is terminal_link_resolver.dart's
// [TerminalLinkResolver]; the process manager the detectors take is
// [TerminalLinkProcessInfo]. External link providers (extensions), link
// openers, hover actions and custom `activate` callbacks are not ported.

import 'dart:async';

import 'package:bao_xterm/typings/xterm_headless.dart';

import 'terminal_link_parsing.dart';

/// A link detector can search for and return links within the xterm.js
/// buffer. A single link detector can return multiple links of differing
/// types.
abstract interface class ITerminalLinkDetector {
  /// The xterm.js instance this detector belongs to.
  Terminal get xterm;

  /// The maximum link length possible for this detector, this puts a cap on
  /// how much of a wrapped line to consider to prevent performance problems.
  int get maxLinkLength;

  /// Detects links within the _wrapped_ line range provided and returns them
  /// as an array.
  ///
  /// [lines] are the individual buffer lines that make up the wrapped line.
  /// [startLine] is the start of the wrapped line; this _will not_ be
  /// validated that it is indeed the start of a wrapped line. [endLine] is
  /// the end of the wrapped line; this _will not_ be validated that it is
  /// indeed the end of a wrapped line.
  FutureOr<List<TerminalSimpleLink>> detect(
    List<IBufferLine> lines,
    int startLine,
    int endLine,
  );
}

/// A selection in the editor a link opens: upstream's
/// `ITextEditorSelection`, one-based.
typedef TextEditorSelection = ({
  int startLineNumber,
  int startColumn,
  int? endLineNumber,
  int? endColumn,
});

/// A link a detector found (upstream's `ITerminalSimpleLink`).
class TerminalSimpleLink {
  TerminalSimpleLink({
    required this.text,
    this.parsedLink,
    required this.bufferRange,
    required this.type,
    this.uri,
    this.contextLine,
    this.selection,
    this.disableTrimColon = false,
  });

  /// The text of the link.
  String text;

  IParsedLink? parsedLink;

  /// The buffer range of the link.
  final IBufferRange bufferRange;

  /// The type of link, which determines how it is handled when activated.
  final TerminalBuiltinLinkType type;

  /// The URI of the link if it has been resolved.
  Uri? uri;

  /// An optional full line to be used for context when resolving.
  String? contextLine;

  /// The location or selection range of the link.
  TextEditorSelection? selection;

  /// Whether to trim a trailing colon at the end of a path.
  bool disableTrimColon;

  @override
  String toString() =>
      'TerminalSimpleLink($type, "$text", $bufferRange, uri: $uri)';
}

enum TerminalBuiltinLinkType {
  /// The link is validated to be a file on the file system and will open an
  /// editor.
  localFile,

  /// The link is validated to be a folder on the file system and is outside
  /// the workspace. It will reveal the folder within the explorer.
  localFolderOutsideWorkspace,

  /// The link is validated to be a folder on the file system and is within
  /// the workspace and will reveal the folder within the explorer.
  localFolderInWorkspace,

  /// A low confidence link which will search for the file in the workspace.
  /// If there is a single match, it will open the file; otherwise, it will
  /// present the matches in a quick pick.
  search,

  /// A link whose text is a valid URI.
  url,
}

/// What the detectors know of the terminal's process: upstream's
/// `Pick<ITerminalProcessManager, 'initialCwd' | 'os' | 'remoteAuthority' |
/// 'userHome'>`. Remote terminals are not supported, so there is no
/// `remoteAuthority`; the user's home is the resolver's.
class TerminalLinkProcessInfo {
  TerminalLinkProcessInfo({this.initialCwd = '', this.os});

  /// The directory relative links resolve against; empty when unknown.
  String initialCwd;

  /// The process's operating system; the host's when null.
  OperatingSystem? os;
}
