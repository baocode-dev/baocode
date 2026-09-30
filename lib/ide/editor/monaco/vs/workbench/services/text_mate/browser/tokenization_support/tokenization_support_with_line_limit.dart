/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/textMate/browser/
// tokenizationSupport/tokenizationSupportWithLineLimit.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. Deviation: the limit is a plain
// value, `editor.maxTokenizationLineLength` for the language as the bundled
// extensions' configuration defaults set it (no user settings here).

import '../../../../../../../textmate/vscode_textmate/main.dart';
import '../../../../../editor/common/languages/null_tokenize.dart';
import '../../../../../editor/common/model/text_model_tokens.dart';
import '../text_mate_tokenization_feature_impl.dart';

class TokenizationSupportWithLineLimit implements ITokenizationSupport {
  TokenizationSupportWithLineLimit(
    this._encodedLanguageId,
    this._actual, [
    this._maxTokenizationLineLength = maxTokenizationLineLength,
  ]);

  final int _encodedLanguageId;
  final ITokenizationSupport _actual;
  final int _maxTokenizationLineLength;

  @override
  StateStack getInitialState() => _actual.getInitialState();

  @override
  EncodedTokenizationResult<StateStack> tokenizeEncoded(
    String line,
    bool hasEOL,
    StateStack state,
  ) {
    // Do not attempt to tokenize if a line is too long
    if (line.length >= _maxTokenizationLineLength) {
      return nullTokenizeEncoded(_encodedLanguageId, state);
    }

    return _actual.tokenizeEncoded(line, hasEOL, state);
  }
}
