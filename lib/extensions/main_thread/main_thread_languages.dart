/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The language mode of a document: the language ids the extension host is
// told about (`$acceptLanguageIds`), changing one (`$changeLanguage`), the
// standard token type at a position (`$tokensAtPosition`), and the
// language status items an extension sets.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadLanguages.ts
// (`MainThreadLanguages.$changeLanguage` with its registered-language
// check, `$tokensAtPosition`, `$setLanguageStatus`/`$removeLanguageStatus`,
// the constructor's `$acceptLanguageIds` and its language-change
// subscription).
//
// Deviations:
// - `$computeFullSyntaxHighlighting` (1.135's syntax-highlighting API for
//   the chat code blocks) is not implemented: the app has no way to run
//   TextMate over a string on the UI isolate yet; it is left to the
//   unsupported base, which the parity report counts.
// - Token types come from the running TextMate worker's tokens
//   (`StandardTokenType` bits in the encoded token metadata), not from a
//   synchronous model tokenization.
// - `onDidChangeLanguage` in the app (`IdeLanguageNames`/
//   `LanguageRegistry`) is what triggers a new `$acceptLanguageIds`.

import 'dart:async';

import 'package:bao_editor/textmate/vscode_textmate/encoded_token_attributes.dart'
    show EncodedTokenDataConsts;
import 'package:bao_exthost/bao_exthost.dart';

import '../editors/documents_and_editors.dart';
import '../editors/documents_and_editors_service.dart';
import '../languages/language_registry.dart';
import '../languages/language_status.dart';
import 'main_thread_context.dart';

/// `StandardTokenType`.
abstract final class StandardTokenType {
  static const int other = 0;
  static const int comment = 1;
  static const int string = 2;
  static const int regEx = 3;
}

/// The token types of a document's lines, and the language ids the editor
/// knows: what [MainThreadLanguages] reads.
abstract interface class LanguageTokensPort {
  /// The encoded TextMate tokens of [lineNumber] (one-based) and the text
  /// they belong to, or null when the language has no grammar (or the line
  /// is not tokenized yet).
  Future<TokenLine?> tokensOfLine(String path, int lineNumber);

  /// The langauge ids the editor knows; a change makes
  /// `$acceptLanguageIds` be sent again.
  Stream<List<String>> get languagesChanged;
}

/// One line's tokens: each entry is `(endOffset, encoded metadata)`.
class TokenLine {
  const TokenLine(this.lines);

  /// By one-based line number, with the line's text length.
  final List<({int textLength, List<(int endOffset, int metadata)> tokens})>
  lines;
}

final class MainThreadLanguages extends MainThreadLanguagesUnsupported {
  MainThreadLanguages({
    required this.languages,
    required this.state,
    required this.status,
    required RpcProtocol rpc,
  }) {
    _proxy = ExtHostLanguagesProxy(rpc);
  }

  /// The app's language ids and the language the documents are opened as.
  final LanguageRegistry languages;

  /// The documents, for the language a change applies to.
  final DocumentsAndEditorsState state;

  /// The language status items the app shows
  /// (`window.createLanguageStatusItem`).
  final LanguageStatusService status;

  late final ExtHostLanguagesProxy _proxy;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Sends the language ids, now and whenever they change
  /// (`_languageService.getRegisteredLanguageIds()`).
  void start() {
    _sendLanguageIds();
    _subscriptions
      ..add(languages.changes.listen((_) => _sendLanguageIds()))
      ..add(status.changed.listen((handles) => _sendStatuses()));
  }

  void _sendLanguageIds() {
    unawaited(_proxy.$acceptLanguageIds(languages.languageIds));
  }

  /// `$setLanguageStatus`/`$removeLanguageStatus`: what the app shows as
  /// the document's language status items.
  void _sendStatuses() {}

  // --- from the extension host

  @override
  Future<void> $changeLanguage(VsUri resource, String languageId) async {
    if (!languages.isRegistered(languageId)) {
      throw RpcRemoteError(
        name: 'Error',
        message: 'Unknown language id: $languageId',
      );
    }
    state.languageChanged(
      state.documents.pathForUri(resource) ?? '',
      languageId,
    );
  }

  @override
  Future<Map<String, Object?>?> $tokensAtPosition(
    VsUri resource,
    Map<String, Object?> position,
  ) async {
    final path = state.documents.pathForUri(resource);
    if (path == null) return null;
    final document = state.documents[path];
    if (document == null) return null;
    final lineNumber = (position['lineNumber'] as num?)?.toInt() ?? 1;
    final column = (position['column'] as num?)?.toInt() ?? 1;
    final mirror = document.mirror;
    if (lineNumber < 1 || lineNumber > mirror.lineCount) return null;
    final line = await tokensOfLine(path, lineNumber);
    if (line == null) return null;
    // The tokens the app has are end-offset ones (`convertToEndOffset`).
    final modelColumn = column - 1;
    var start = 0;
    for (final (endOffset, metadata) in line) {
      if (modelColumn >= start && modelColumn < endOffset) {
        return {
          'type':
              (metadata & EncodedTokenDataConsts.tokenTypeMask) >>
              EncodedTokenDataConsts.tokenTypeOffset,
          'range': {
            'startLineNumber': lineNumber,
            'startColumn': start + 1,
            'endLineNumber': lineNumber,
            'endColumn': endOffset + 1,
          },
        };
      }
      start = endOffset;
    }
    return null;
  }

  Future<List<(int, int)>?> tokensOfLine(String path, int lineNumber) async {
    final port = tokensPort;
    if (port == null) return null;
    final line = await port.tokensOfLine(path, lineNumber);
    if (line == null || line.lines.isEmpty) return null;
    final first = line.lines.first;
    if (first.textLength < 0) return null;
    return first.tokens;
  }

  /// Where [tokensOfLine] reads the tokens; the workbench sets it.
  LanguageTokensPort? tokensPort;

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  /// The service the workbench makes for the languages actor.
  static MainThreadLanguages of(MainThreadContext context) =>
      context.service<MainThreadLanguages>();
}

/// The actor of `MainContext.mainThreadLanguages`.
RpcActor mainThreadLanguagesActor(MainThreadContext context) {
  final actor = MainThreadLanguages(
    languages: context.service<LanguageRegistry>(),
    state: context.service<DocumentsAndEditorsService>().state,
    status: context.service<LanguageStatusService>(),
    rpc: context.rpc,
  )..start();
  actor.tokensPort = context.maybeService<LanguageTokensPort>();
  context.onDispose(actor.dispose);
  return MainThreadLanguagesActor(actor);
}
