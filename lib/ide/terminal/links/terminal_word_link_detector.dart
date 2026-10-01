/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The fallback, low-confidence links: every word of a wrapped line, split
// by `terminal.integrated.wordSeparators` (and the powerline symbols), to
// search the workspace for.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/
// terminalWordLinkDetector.ts. The separators are a setter rather than a
// configuration listener; the product's URL protocol (`vscode:` links) is
// [TerminalWordLinkDetector.urlProtocol], none by default.

import 'package:bao_xterm/typings/xterm_headless.dart';

import 'links.dart';
import 'terminal_link_helpers.dart';

/// `terminal.integrated.wordSeparators`' default.
const String terminalDefaultWordSeparators = ' ()[]{}\',"`─‘’“”|';

abstract final class _Constants {
  /// The max line length to try extract word links from.
  static const int maxLineLength = 2000;
}

class _Word {
  _Word(this.startIndex, this.endIndex, this.text);

  int startIndex;
  int endIndex;
  String text;
}

class TerminalWordLinkDetector implements ITerminalLinkDetector {
  TerminalWordLinkDetector(
    this.xterm, {
    String wordSeparators = terminalDefaultWordSeparators,
    this.urlProtocol,
  }) {
    this.wordSeparators = wordSeparators;
  }

  static const String id = 'word';

  // Word links typically search the workspace so it makes sense that their
  // maximum link length is quite small.
  @override
  final int maxLinkLength = 100;

  @override
  final Terminal xterm;

  /// The product's URL protocol (upstream's `productService.urlProtocol`):
  /// words with this scheme are URL links.
  final String? urlProtocol;

  late RegExp _separatorRegex;

  /// `terminal.integrated.wordSeparators`.
  set wordSeparators(String separators) {
    _refreshSeparatorCodes(separators);
  }

  @override
  List<TerminalSimpleLink> detect(
    List<IBufferLine> lines,
    int startLine,
    int endLine,
  ) {
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

    // Parse out all words from the wrapped line
    final words = _parseWords(text);

    // Map the words to ITerminalLink objects
    for (final word in words) {
      if (word.text == '') {
        continue;
      }
      if (word.text.isNotEmpty && word.text[word.text.length - 1] == ':') {
        word.text = word.text.substring(0, word.text.length - 1);
        word.endIndex--;
      }
      final bufferRange = convertLinkRangeToBuffer(lines, xterm.cols, (
        startColumn: word.startIndex + 1,
        startLineNumber: 1,
        endColumn: word.endIndex + 1,
        endLineNumber: 1,
      ), startLine);

      // Support this product's URL protocol
      final urlProtocol = this.urlProtocol;
      if (urlProtocol != null &&
          word.text.toLowerCase().startsWith('${urlProtocol.toLowerCase()}:')) {
        final uri = Uri.tryParse(word.text);
        if (uri != null) {
          links.add(
            TerminalSimpleLink(
              text: word.text,
              uri: uri,
              bufferRange: bufferRange,
              type: TerminalBuiltinLinkType.url,
            ),
          );
        }
        continue;
      }

      // Search links
      links.add(
        TerminalSimpleLink(
          text: word.text,
          bufferRange: bufferRange,
          type: TerminalBuiltinLinkType.search,
          contextLine: text,
        ),
      );
    }

    return links;
  }

  List<_Word> _parseWords(String text) {
    final words = <_Word>[];
    final splitWords = text.split(_separatorRegex);
    var runningIndex = 0;
    for (var i = 0; i < splitWords.length; i++) {
      words.add(
        _Word(runningIndex, runningIndex + splitWords[i].length, splitWords[i]),
      );
      runningIndex += splitWords[i].length + 1;
    }
    return words;
  }

  void _refreshSeparatorCodes(String separators) {
    final powerlineSymbols = StringBuffer();
    for (var i = 0xe0b0; i <= 0xe0bf; i++) {
      powerlineSymbols.writeCharCode(i);
    }
    _separatorRegex = RegExp(
      '[${escapeRegExpCharacters(separators)}$powerlineSymbols]',
    );
  }
}

/// Escapes the characters that are special in a regular expression
/// (upstream's `strings.escapeRegExpCharacters`).
String escapeRegExpCharacters(String value) {
  return value.replaceAllMapped(
    RegExp(r'[\\\{\}\*\+\?\|\^\$\.\[\]\(\)]'),
    (match) => '\\${match[0]}',
  );
}
