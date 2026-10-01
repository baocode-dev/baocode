/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/textMate/browser/
// tokenizationSupport/textMateTokenizationSupport.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `tokenizeEncoded`. Deviations:
// no tokenization-time telemetry, no background tokenizer factory, and the
// `onDidEncounterLanguage` event is a callback. The line-limit wrapper is
// tokenization_support_with_line_limit.dart.

import '../../../../../../../textmate/vscode_textmate/main.dart';
import '../../../../../editor/common/languages/null_tokenize.dart';
import '../../../../../editor/common/model/text_model_tokens.dart';

class TextMateTokenizationSupport implements ITokenizationSupport {
  TextMateTokenizationSupport(
    this._grammar,
    this._initialState,
    this._containsEmbeddedLanguages, {
    this.onDidEncounterLanguage,
    this.onTimeLimitReached,
  });

  final IGrammar _grammar;
  final StateStack _initialState;
  final bool _containsEmbeddedLanguages;
  final List<bool> _seenLanguages = [];
  final void Function(int languageId)? onDidEncounterLanguage;

  /// Upstream's `console.warn` when a line hits the 500 ms limit.
  final void Function(String line)? onTimeLimitReached;

  @override
  StateStack getInitialState() => _initialState;

  @override
  EncodedTokenizationResult<StateStack> tokenizeEncoded(
    String line,
    bool hasEOL,
    StateStack state,
  ) {
    final textMateResult = _grammar.tokenizeLine2(line, state, 500);

    if (textMateResult.stoppedEarly) {
      onTimeLimitReached?.call(
        line.length > 100 ? line.substring(0, 100) : line,
      );
      // return the state at the beginning of the line
      return EncodedTokenizationResult(textMateResult.tokens, state);
    }

    if (_containsEmbeddedLanguages) {
      final seenLanguages = _seenLanguages;
      final tokens = textMateResult.tokens;

      // Must check if any of the embedded languages was hit
      for (var i = 0, len = tokens.length >>> 1; i < len; i++) {
        final metadata = tokens[(i << 1) + 1];
        final languageId = EncodedTokenAttributes.getLanguageId(metadata);

        // Upstream's array has holes, which read as unseen.
        while (languageId >= seenLanguages.length) {
          seenLanguages.add(false);
        }
        if (!seenLanguages[languageId]) {
          seenLanguages[languageId] = true;
          onDidEncounterLanguage?.call(languageId);
        }
      }
    }

    // try to save an object if possible
    final endState = state.equals(textMateResult.ruleStack)
        ? state
        : textMateResult.ruleStack;

    return EncodedTokenizationResult(textMateResult.tokens, endState);
  }
}
