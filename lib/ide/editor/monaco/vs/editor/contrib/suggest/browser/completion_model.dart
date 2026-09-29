/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/contrib/suggest/browser/completionModel.ts
// and the CompletionItem/comparators of suggest.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: [CompletionItem] carries the label, filter/sort text, kind
// (snippet or not), edit range columns and a caller payload instead of a
// `languages.CompletionItem`; "providers" are opaque keys. Word distance
// (locality bonus) is not ported: every distance is 0. Resolving is left to
// the caller. `stats` is not computed.

import '../../../../base/common/filters.dart';
import '../../../common/core/position.dart';

/// `SnippetSortOrder`.
enum SnippetSortOrder { top, inline, bottom }

/// One suggestion, positioned in the document it was requested for.
class CompletionItem<T> {
  CompletionItem({
    required this.position,
    required this.completion,
    required String label,
    required this.editStart,
    required this.editInsertEnd,
    required this.editReplaceEnd,
    this.filterText,
    String? sortText,
    this.isSnippetKind = false,
    this.kindIndex = 0,
    this.provider,
    this.incomplete = false,
    bool invalidRange = false,
  }) : textLabel = label,
       labelLow = label.toLowerCase(),
       sortTextLow = (sortText ?? label).toLowerCase(),
       filterTextLow = filterText?.toLowerCase(),
       isInvalid =
           label.isEmpty ||
           invalidRange ||
           editStart.lineNumber != position.lineNumber ||
           editInsertEnd.lineNumber != position.lineNumber ||
           editReplaceEnd.lineNumber != position.lineNumber;

  /// Where completion was requested (one-based).
  final Position position;

  /// The caller's item.
  final T completion;
  final String textLabel;
  final String labelLow;
  final String? filterText;
  final String sortTextLow;
  final String? filterTextLow;
  final Position editStart;
  final Position editInsertEnd;
  final Position editReplaceEnd;
  final bool isSnippetKind;

  /// Kind order, the last tie breaker of the default comparator.
  final int kindIndex;

  /// Who offered it (an incomplete list is re-queried per provider).
  final Object? provider;

  /// Whether the list this came from was incomplete.
  final bool incomplete;
  final bool isInvalid;

  // sorting, filtering
  FuzzyScore score = fuzzyScoreDefault;
  int distance = 0;
  int idx = 0;
  String word = '';
}

int _defaultComparator(CompletionItem a, CompletionItem b) {
  // check with 'sortText'
  final bySort = a.sortTextLow.compareTo(b.sortTextLow);
  if (bySort != 0) return bySort;
  // check with 'label'
  final byLabel = a.textLabel.compareTo(b.textLabel);
  if (byLabel != 0) return byLabel;
  // check with 'type'
  return a.kindIndex - b.kindIndex;
}

int _snippetUpComparator(CompletionItem a, CompletionItem b) {
  if (a.isSnippetKind != b.isSnippetKind) return a.isSnippetKind ? -1 : 1;
  return _defaultComparator(a, b);
}

int _snippetDownComparator(CompletionItem a, CompletionItem b) {
  if (a.isSnippetKind != b.isSnippetKind) return a.isSnippetKind ? 1 : -1;
  return _defaultComparator(a, b);
}

/// The initial order of a fresh list (`getSuggestionComparator`).
int Function(CompletionItem a, CompletionItem b) getSuggestionComparator(
  SnippetSortOrder order,
) => switch (order) {
  SnippetSortOrder.top => _snippetUpComparator,
  SnippetSortOrder.bottom => _snippetDownComparator,
  SnippetSortOrder.inline => _defaultComparator,
};

class LineContext {
  const LineContext(this.leadingLineContent, this.characterCountDelta);

  final String leadingLineContent;
  final int characterCountDelta;
}

enum _Refilter { nothing, all, incr }

/// Sorted, filtered completion view model.
class CompletionModel<T> {
  CompletionModel(
    List<CompletionItem<T>> items,
    int column,
    LineContext lineContext, {
    this.filterGraceful = true,
    SnippetSortOrder snippetSuggestions = SnippetSortOrder.inline,
    this.fuzzyScoreOptions = FuzzyScoreOptions.defaults,
  }) : _items = items,
       _column = column,
       _lineContext = lineContext,
       _snippetCompareFn = switch (snippetSuggestions) {
         SnippetSortOrder.top => _compareCompletionItemsSnippetsUp,
         SnippetSortOrder.bottom => _compareCompletionItemsSnippetsDown,
         SnippetSortOrder.inline => _compareCompletionItems,
       };

  final List<CompletionItem<T>> _items;
  final int _column;
  final bool filterGraceful;
  final FuzzyScoreOptions fuzzyScoreOptions;
  final int Function(CompletionItem a, CompletionItem b) _snippetCompareFn;

  LineContext _lineContext;
  _Refilter _refilterKind = _Refilter.all;
  List<CompletionItem<T>>? _filteredItems;
  Map<Object?, List<CompletionItem<T>>>? _itemsByProvider;

  List<CompletionItem<T>> get allItems => _items;

  LineContext get lineContext => _lineContext;

  set lineContext(LineContext value) {
    if (_lineContext.leadingLineContent != value.leadingLineContent ||
        _lineContext.characterCountDelta != value.characterCountDelta) {
      _refilterKind =
          _lineContext.characterCountDelta < value.characterCountDelta &&
              _filteredItems != null
          ? _Refilter.incr
          : _Refilter.all;
      _lineContext = value;
    }
  }

  List<CompletionItem<T>> get items {
    _ensureCachedState();
    return _filteredItems!;
  }

  Map<Object?, List<CompletionItem<T>>> getItemsByProvider() {
    _ensureCachedState();
    return _itemsByProvider!;
  }

  Set<Object?> getIncompleteProvider() {
    _ensureCachedState();
    return {
      for (final MapEntry(key: provider, value: items)
          in getItemsByProvider().entries)
        if (items.isNotEmpty && items.first.incomplete) provider,
    };
  }

  void _ensureCachedState() {
    if (_refilterKind != _Refilter.nothing) _createCachedState();
  }

  void _createCachedState() {
    _itemsByProvider = {};

    final leadingLineContent = _lineContext.leadingLineContent;
    final characterCountDelta = _lineContext.characterCountDelta;
    var word = '';
    var wordLow = '';

    // incrementally filter less
    final source = _refilterKind == _Refilter.all ? _items : _filteredItems!;
    final target = <CompletionItem<T>>[];

    // picks a score function based on the number of
    // items that we have to score/filter and based on the
    // user-configuration
    final FuzzyScorer scoreFn = (!filterGraceful || source.length > 2000)
        ? fuzzyScore
        : fuzzyScoreGracefulAggressive;

    for (var i = 0; i < source.length; i++) {
      final item = source[i];
      if (item.isInvalid) continue; // SKIP invalid items

      // keep all items by their provider
      _itemsByProvider!.putIfAbsent(item.provider, () => []).add(item);

      // 'word' is that remainder of the current line that we
      // filter and score against. In theory each suggestion uses a
      // different word, but in practice not - that's why we cache
      final overwriteBefore = item.position.column - item.editStart.column;
      final wordLen =
          overwriteBefore +
          characterCountDelta -
          (item.position.column - _column);
      if (word.length != wordLen) {
        word = wordLen <= 0
            ? ''
            : leadingLineContent.substring(
                wordLen > leadingLineContent.length
                    ? 0
                    : leadingLineContent.length - wordLen,
              );
        wordLow = word.toLowerCase();
      }

      // remember the word against which this item was
      // scored
      item.word = word;

      if (wordLen <= 0) {
        // when there is nothing to score against, don't
        // event try to do. Use a const rank and rely on
        // the fallback-sort using the initial sort order.
        // use a score of `-100` because that is out of the
        // bound of values `fuzzyScore` will return
        item.score = fuzzyScoreDefault;
      } else {
        // skip word characters that are whitespace until
        // we have hit the replace range (overwriteBefore)
        var wordPos = 0;
        while (wordPos < overwriteBefore && wordPos < word.length) {
          final ch = word.codeUnitAt(wordPos);
          if (ch == 0x20 || ch == 0x09) {
            wordPos += 1;
          } else {
            break;
          }
        }

        if (wordPos >= wordLen) {
          // the wordPos at which scoring starts is the whole word
          // and therefore the same rules as not having a word apply
          item.score = fuzzyScoreDefault;
        } else if (item.filterText != null) {
          // when there is a `filterText` it must match the `word`.
          // if it matches we check with the label to compute highlights
          // and if that doesn't yield a result we have no highlights,
          // despite having the match
          final match = scoreFn(
            word,
            wordLow,
            wordPos,
            item.filterText!,
            item.filterTextLow!,
            0,
            fuzzyScoreOptions,
          );
          if (match == null) continue; // NO match
          if (item.filterText!.toLowerCase() == item.labelLow) {
            // filterText and label are actually the same -> use good highlights
            item.score = match;
          } else {
            // re-run the scorer on the label in the hope of a result BUT use
            // the rank of the filterText-match
            item.score = anyScore(
              word,
              wordLow,
              wordPos,
              item.textLabel,
              item.labelLow,
              0,
            );
            item.score[0] = match[0]; // use score from filterText
          }
        } else {
          // by default match `word` against the `label`
          final match = scoreFn(
            word,
            wordLow,
            wordPos,
            item.textLabel,
            item.labelLow,
            0,
            fuzzyScoreOptions,
          );
          if (match == null) continue; // NO match
          item.score = match;
        }
      }

      item.idx = i;
      item.distance = 0;
      target.add(item);
    }

    _filteredItems = target..sort(_snippetCompareFn);
    _refilterKind = _Refilter.nothing;
  }

  static int _compareCompletionItems(CompletionItem a, CompletionItem b) {
    if (a.score[0] > b.score[0]) {
      return -1;
    } else if (a.score[0] < b.score[0]) {
      return 1;
    } else if (a.distance < b.distance) {
      return -1;
    } else if (a.distance > b.distance) {
      return 1;
    } else if (a.idx < b.idx) {
      return -1;
    } else if (a.idx > b.idx) {
      return 1;
    } else {
      return 0;
    }
  }

  static int _compareCompletionItemsSnippetsDown(
    CompletionItem a,
    CompletionItem b,
  ) {
    if (a.isSnippetKind != b.isSnippetKind) return a.isSnippetKind ? 1 : -1;
    return _compareCompletionItems(a, b);
  }

  static int _compareCompletionItemsSnippetsUp(
    CompletionItem a,
    CompletionItem b,
  ) {
    if (a.isSnippetKind != b.isSnippetKind) return a.isSnippetKind ? -1 : 1;
    return _compareCompletionItems(a, b);
  }
}
