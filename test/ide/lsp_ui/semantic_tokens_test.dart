// Semantic token styles as the editor paints them: the styler of a color
// theme against VS Code's golden data (semantic_token_fixture.dart), and the
// overlay that applies them to the syntax spans.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp_ui/semantic_tokens.dart';

import 'semantic_token_fixture.dart';

final fixture = SemanticTokenFixture.instance;

/// Every recorded token of [themeId] through [styler]; the differences.
List<String> compareMatrix(String themeId, IdeSemanticTokenStyler styler) {
  final differences = <String>[];
  for (final language in fixture.languages) {
    for (final type in fixture.tokenTypes) {
      for (final set in fixture.modifierSets) {
        final modifiers = fixture.modifiersOf(set);
        final want = fixture.semanticHighlighting(themeId)
            ? fixture.style(themeId, type, modifiers, language)
            : null;
        final got = styler(type, modifiers, language);
        if (got != want) {
          differences.add('$language $type $modifiers: $got != $want');
        }
      }
    }
  }
  return differences;
}

/// [result] is [base] with the attributes [style] sets replaced.
void expectApplied(TextStyle? result, TextStyle base, IdeTokenStyle style) {
  bool has(TextDecoration? d, TextDecoration flag) =>
      (d ?? TextDecoration.none).contains(flag);
  expect(result, isNotNull);
  expect(result!.color, style.foreground ?? base.color);
  expect(
    result.fontStyle,
    style.italic == null
        ? base.fontStyle
        : style.italic!
        ? FontStyle.italic
        : FontStyle.normal,
  );
  expect(
    result.fontWeight,
    style.bold == null
        ? base.fontWeight
        : style.bold!
        ? FontWeight.bold
        : FontWeight.normal,
  );
  expect(
    has(result.decoration, TextDecoration.underline),
    style.underline ?? has(base.decoration, TextDecoration.underline),
  );
  expect(
    has(result.decoration, TextDecoration.lineThrough),
    style.strikethrough ?? has(base.decoration, TextDecoration.lineThrough),
  );
}

final _styledBase = TextStyle(
  color: Color(0xFF123456),
  fontStyle: FontStyle.italic,
  fontWeight: FontWeight.bold,
  decoration: TextDecoration.combine([
    TextDecoration.underline,
    TextDecoration.lineThrough,
  ]),
);
const _plainBase = TextStyle(color: Color(0xFF654321));

void main() {
  group('the styler of a theme matches VS Code', () {
    for (final themeId in [...fixture.themeIds, 'Synthetic Dark']) {
      test(themeId, () async {
        final theme = await fixture.loadTheme(themeId);
        expect(compareMatrix(themeId, ideSemanticTokenStyler(theme)), isEmpty);
      });
    }
  });

  testWidgets('the default styler is Monokai, from the bundled assets', (
    tester,
  ) async {
    final styler = await ideDefaultSemanticTokenStyler();
    expect(compareMatrix(ideDefaultColorThemeId, styler), isEmpty);
    expect(await ideDefaultSemanticTokenStyler(), same(styler));
  });

  test('a theme without semanticHighlighting styles nothing', () async {
    const themeId = 'Default High Contrast Light';
    final theme = await fixture.loadTheme(themeId);
    expect(theme.semanticHighlighting, isFalse);
    final styler = ideSemanticTokenStyler(theme);
    expect(compareMatrix(themeId, styler), isEmpty);
    expect(styler('class', {}, 'typescript'), isNull);

    const text = 'class Foo {}';
    final base = {
      1: [
        TextSpan(text: 'class ', style: _plainBase),
        TextSpan(text: 'Foo', style: _styledBase),
        TextSpan(text: ' {}'),
      ],
    };
    final tokens = IdeSemanticTokens(DocumentSnapshot(text), const [
      LspSemanticToken(0, 0, 5, 'keyword', {}),
      LspSemanticToken(0, 6, 3, 'class', {'declaration'}),
    ], styler: styler);
    expect(tokens.isEmpty, isTrue);
    expect(tokens.overlay(base)[1], same(base[1]));

    // `editor.semanticHighlighting.enabled: true` overrides the theme.
    final enabled = ideSemanticTokenStyler(
      theme,
      semanticHighlightingEnabled: true,
    );
    expect(
      enabled('class', {'declaration'}, 'typescript'),
      fixture.style(themeId, 'class', {'declaration'}, 'typescript'),
    );
    // And `false` turns it off for a theme that has it.
    final dark = await fixture.loadTheme(ideDefaultColorThemeId);
    expect(
      ideSemanticTokenStyler(dark, semanticHighlightingEnabled: false)(
        'class',
        {},
        'typescript',
      ),
      isNull,
    );
  });

  test('the overlay replaces the attributes a style sets and keeps the '
      'others', () async {
    const themeId = 'Synthetic Dark';
    final styler = ideSemanticTokenStyler(await fixture.loadTheme(themeId));
    const text = 'alpha beta gamma delta omega sigma';
    final cases = [
      ('alpha', 'variable', {'readonly'}),
      ('beta', 'parameter', <String>{}),
      ('gamma', 'property', {'static'}),
      ('delta', 'comment', <String>{}),
      ('omega', 'enumMember', <String>{}),
      ('sigma', 'label', {'async'}),
    ];
    final expected = {
      for (final (word, type, modifiers) in cases)
        word: fixture.style(themeId, type, modifiers, 'plaintext')!,
    };
    // The cases cover setting, clearing and keeping each attribute.
    for (final attribute in <bool? Function(IdeTokenStyle)>[
      (s) => s.bold,
      (s) => s.italic,
      (s) => s.underline,
      (s) => s.strikethrough,
    ]) {
      expect(expected.values.map(attribute), containsAll([true, false, null]));
    }
    expect(expected.values.map((s) => s.foreground), contains(isNull));

    final tokens = IdeSemanticTokens(DocumentSnapshot(text), [
      for (final (word, type, modifiers) in cases)
        LspSemanticToken(0, text.indexOf(word), word.length, type, modifiers),
    ], styler: styler);
    for (final base in [_styledBase, _plainBase]) {
      final spans = tokens.overlay({
        1: [TextSpan(text: text, style: base)],
      })[1]!;
      expect(spans.map((s) => s.text).join(), text);
      for (final (word, _, _) in cases) {
        final span = spans.firstWhere((s) => s.text == word);
        expectApplied(span.style, base, expected[word]!);
      }
      // Text between tokens keeps the syntax style.
      expect(spans.firstWhere((s) => s.text == ' ').style, same(base));
    }
  });

  test('a bundled theme\'s font styles reach the spans', () async {
    // Monokai underlines and italicizes some token types.
    const themeId = 'Monokai';
    final styler = ideSemanticTokenStyler(await fixture.loadTheme(themeId));
    final styled = <(String, Set<String>, IdeTokenStyle)>[];
    for (final type in fixture.tokenTypes) {
      final style = fixture.style(themeId, type, {}, 'dart');
      if (style != null &&
          (style.italic ?? style.bold ?? style.underline) != null) {
        styled.add((type, {}, style));
      }
    }
    expect(styled, isNotEmpty);
    expect(styled.map((s) => s.$3.underline), contains(true));
    expect(styled.map((s) => s.$3.italic), contains(true));
    for (final (type, modifiers, style) in styled) {
      const text = 'name';
      final tokens = IdeSemanticTokens(
        DocumentSnapshot(text),
        [LspSemanticToken(0, 0, 4, type, modifiers)],
        styler: styler,
        languageId: 'dart',
      );
      final span = tokens.overlay({
        1: const [TextSpan(text: text, style: _plainBase)],
      })[1]!.single;
      expectApplied(span.style, _plainBase, style);
    }
  });

  test('the language id selects language rules', () async {
    const themeId = 'Synthetic Dark';
    final styler = ideSemanticTokenStyler(await fixture.loadTheme(themeId));
    final typescript = styler('function', {}, 'typescript');
    final dart = styler('function', {}, 'dart');
    expect(typescript, fixture.style(themeId, 'function', {}, 'typescript'));
    expect(dart, fixture.style(themeId, 'function', {}, 'dart'));
    expect(typescript, isNot(dart));
    const text = 'f()';
    final spans = IdeSemanticTokens(
      DocumentSnapshot(text),
      const [LspSemanticToken(0, 0, 1, 'function', {})],
      styler: styler,
      languageId: 'typescript',
    ).overlay(null)[1]!;
    expect(spans.first.style!.color, typescript!.foreground);
  });

  test('a line whose text changed keeps its syntax spans', () async {
    final styler = ideSemanticTokenStyler(
      await fixture.loadTheme(ideDefaultColorThemeId),
    );
    final tokens = IdeSemanticTokens(
      DocumentSnapshot('class Foo {}\nvar x;\n'),
      const [
        LspSemanticToken(0, 6, 3, 'class', {}),
        LspSemanticToken(1, 4, 1, 'variable', {}),
      ],
      styler: styler,
    );
    final base = {
      1: const [TextSpan(text: 'class Fooo {}', style: _plainBase)],
      2: const [TextSpan(text: 'var x;', style: _plainBase)],
    };
    final overlay = tokens.overlay(base);
    expect(overlay[1], same(base[1]));
    expect(
      overlay[2]!.firstWhere((s) => s.text == 'x').style!.color,
      fixture
          .style(ideDefaultColorThemeId, 'variable', {}, 'plaintext')!
          .foreground,
    );
  });
}
