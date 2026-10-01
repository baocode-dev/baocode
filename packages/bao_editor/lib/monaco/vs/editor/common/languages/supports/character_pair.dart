/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/languages/supports/characterPair.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.

import '../language_configuration.dart';

class CharacterPairSupport {
  CharacterPairSupport(LanguageConfiguration config)
    : _autoClosingPairs = [
        if (config.autoClosingPairs != null)
          for (final pair in config.autoClosingPairs!)
            StandardAutoClosingPairConditional(pair)
        else if (config.brackets != null)
          for (final bracket in config.brackets!)
            StandardAutoClosingPairConditional(
              AutoClosingPairConditional(bracket.$1, bracket.$2),
            ),
        if (config.docComment != null)
          // IDocComment is legacy, only partially supported
          StandardAutoClosingPairConditional(
            AutoClosingPairConditional(
              config.docComment!.open,
              config.docComment!.close ?? '',
            ),
          ),
      ],
      _autoCloseBeforeForQuotes =
          config.autoCloseBefore ?? defaultAutoCloseBeforeLanguageDefinedQuotes,
      _autoCloseBeforeForBrackets =
          config.autoCloseBefore ??
          defaultAutoCloseBeforeLanguageDefinedBrackets,
      _surroundingPairs = config.surroundingPairs {
    _surroundingPairsResolved =
        _surroundingPairs ??
        [
          for (final pair in _autoClosingPairs)
            AutoClosingPair(pair.open, pair.close),
        ];
  }

  static const defaultAutoCloseBeforeLanguageDefinedQuotes = ';:.,=}])> \n\t';
  static const defaultAutoCloseBeforeLanguageDefinedBrackets =
      '\'"`;:.,=}])> \n\t';
  static const defaultAutoCloseBeforeWhitespace = ' \n\t';

  final List<StandardAutoClosingPairConditional> _autoClosingPairs;
  final List<AutoClosingPair>? _surroundingPairs;
  late final List<AutoClosingPair> _surroundingPairsResolved;
  final String _autoCloseBeforeForQuotes;
  final String _autoCloseBeforeForBrackets;

  List<StandardAutoClosingPairConditional> getAutoClosingPairs() =>
      _autoClosingPairs;

  String getAutoCloseBeforeSet(bool forQuotes) =>
      forQuotes ? _autoCloseBeforeForQuotes : _autoCloseBeforeForBrackets;

  List<AutoClosingPair> getSurroundingPairs() => _surroundingPairsResolved;
}
