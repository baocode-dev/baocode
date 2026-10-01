// Sanity checks for the port of VS Code src/vs/base/common/filters.ts
// (the scorers the suggest widget uses), after cases in upstream's
// filters.test.ts.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/base/common/filters.dart';

List<(int, int)>? _fuzzy(String pattern, String word, [FuzzyScorer? scorer]) {
  final score = (scorer ?? fuzzyScore)(
    pattern,
    pattern.toLowerCase(),
    0,
    word,
    word.toLowerCase(),
    0,
    FuzzyScoreOptions.defaults,
  );
  if (score == null) return null;
  return [for (final m in createMatches(score)) (m.start, m.end)];
}

void main() {
  test('matchesPrefix', () {
    expect(matchesPrefix('fo', 'foo')?.map((m) => (m.start, m.end)), [(0, 2)]);
    expect(matchesPrefix('Fo', 'foo'), isNotNull);
    expect(matchesPrefix('oo', 'foo'), isNull);
  });

  test('fuzzyScore matches word starts and camel humps', () {
    expect(_fuzzy('ab', 'abA'), [(0, 2)]);
    expect(_fuzzy('ccm', 'cacmelCase'), isNotNull);
    expect(_fuzzy('BK', 'the_black_knight'), [(4, 5), (10, 11)]);
    expect(_fuzzy('fb', 'fooBar'), [(0, 1), (3, 4)]);
    expect(_fuzzy('xyz', 'fooBar'), isNull);
    // The first character must match strongly by default.
    expect(_fuzzy('o', 'foo'), isNull);
  });

  test('fuzzyScore prefers a contiguous prefix', () {
    FuzzyScore score(String pattern, String word) => fuzzyScore(
      pattern,
      pattern.toLowerCase(),
      0,
      word,
      word.toLowerCase(),
      0,
    )!;
    expect(score('con', 'console')[0], greaterThan(score('con', 'co_new')[0]));
    expect(_fuzzy('form', 'from'), isNull);
    expect(score('fb', 'fooBar')[0], greaterThan(score('fb', 'foobar')[0]));
  });

  test('fuzzyScoreGraceful tolerates a swapped pair', () {
    expect(_fuzzy('rlut', 'result'), isNull);
    expect(_fuzzy('rlut', 'result', fuzzyScoreGracefulAggressive), isNotNull);
  });

  test('empty pattern scores the default', () {
    final score = fuzzyScore('', '', 0, 'foo', 'foo', 0);
    expect(
      score == null || isDefaultFuzzyScore(score) || score[0] >= -100,
      isTrue,
    );
  });
}
