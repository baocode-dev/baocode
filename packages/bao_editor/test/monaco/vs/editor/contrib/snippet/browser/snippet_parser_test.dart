// Ported from VS Code src/vs/editor/contrib/snippet/test/browser/
// snippetParser.test.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// `instanceof` checks become `isA` matchers; JS RegExp literals become
// [SnippetRegExp]s.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/editor/contrib/snippet/browser/snippet_parser.dart';

void _assertText(String value, String expected) {
  expect(SnippetParser.asInsertText(value), expected, reason: value);
}

void _assertMarker(Object input, List<Matcher> ctors) {
  final List<Marker> marker;
  if (input is TextmateSnippet) {
    marker = [...input.children];
  } else if (input is String) {
    marker = SnippetParser().parse(input).children.toList();
  } else {
    marker = [...input as List<Marker>];
  }
  final expected = [...ctors];
  while (marker.isNotEmpty) {
    final m = marker.removeLast();
    expect(expected, isNotEmpty, reason: 'more markers than expected');
    final ctor = expected.removeLast();
    expect(m, ctor, reason: '$input');
  }
  expect(expected, isEmpty, reason: '$input');
}

void _assertTextAndMarker(String value, String escaped, List<Matcher> ctors) {
  _assertText(value, escaped);
  _assertMarker(value, ctors);
}

void _assertEscaped(String value, String expected) {
  expect(SnippetParser.escape(value), expected);
}

final _text = isA<Text>();
final _placeholder = isA<Placeholder>();
final _variable = isA<Variable>();

void main() {
  test('Scanner', () {
    final scanner = Scanner();
    expect(scanner.next().type, TokenType.eof);

    void expectTokens(String text, List<TokenType> types) {
      scanner.text(text);
      for (final type in types) {
        expect(scanner.next().type, type, reason: text);
      }
    }

    expectTokens('abc', [TokenType.variableName, TokenType.eof]);
    expectTokens('{{abc}}', [
      TokenType.curlyOpen,
      TokenType.curlyOpen,
      TokenType.variableName,
      TokenType.curlyClose,
      TokenType.curlyClose,
      TokenType.eof,
    ]);
    expectTokens('abc() ', [
      TokenType.variableName,
      TokenType.format,
      TokenType.eof,
    ]);
    expectTokens('abc 123', [
      TokenType.variableName,
      TokenType.format,
      TokenType.int_,
      TokenType.eof,
    ]);
    expectTokens(r'$foo', [
      TokenType.dollar,
      TokenType.variableName,
      TokenType.eof,
    ]);
    expectTokens(r'$foo_bar', [
      TokenType.dollar,
      TokenType.variableName,
      TokenType.eof,
    ]);
    expectTokens(r'$foo-bar', [
      TokenType.dollar,
      TokenType.variableName,
      TokenType.dash,
      TokenType.variableName,
      TokenType.eof,
    ]);
    expectTokens(r'${foo}', [
      TokenType.dollar,
      TokenType.curlyOpen,
      TokenType.variableName,
      TokenType.curlyClose,
      TokenType.eof,
    ]);
    expectTokens(r'${1223:foo}', [
      TokenType.dollar,
      TokenType.curlyOpen,
      TokenType.int_,
      TokenType.colon,
      TokenType.variableName,
      TokenType.curlyClose,
      TokenType.eof,
    ]);
    expectTokens(r'\${}', [
      TokenType.backslash,
      TokenType.dollar,
      TokenType.curlyOpen,
      TokenType.curlyClose,
    ]);
    expectTokens(r'${foo/regex/format/option}', [
      TokenType.dollar,
      TokenType.curlyOpen,
      TokenType.variableName,
      TokenType.forwardslash,
      TokenType.variableName,
      TokenType.forwardslash,
      TokenType.variableName,
      TokenType.forwardslash,
      TokenType.variableName,
      TokenType.curlyClose,
      TokenType.eof,
    ]);
  });

  test('Parser, escaped', () {
    _assertEscaped(r'foo$0', r'foo\$0');
    _assertEscaped(r'foo\$0', r'foo\\\$0');
    _assertEscaped(r'f$1oo$0', r'f\$1oo\$0');
    _assertEscaped(r'${1:foo}$0', r'\${1:foo\}\$0');
    _assertEscaped(r'$', r'\$');
  });

  test('Parser, text', () {
    _assertText(r'$', r'$');
    _assertText(r'\\$', r'\$');
    _assertText('{', '{');
    _assertText(r'\}', '}');
    _assertText(r'\abc', r'\abc');
    _assertText(r'foo${f:\}}bar', 'foo}bar');
    _assertText(r'\{', r'\{');
    _assertText(r'I need \\\$', r'I need \$');
    _assertText(r'\', r'\');
    _assertText(r'\{{', r'\{{');
    _assertText('{{', '{{');
    _assertText('{{dd', '{{dd');
    _assertText('}}', '}}');
    _assertText('ff}}', 'ff}}');

    _assertText('farboo', 'farboo');
    _assertText('far{{}}boo', 'far{{}}boo');
    _assertText('far{{123}}boo', 'far{{123}}boo');
    _assertText(r'far\{{123}}boo', r'far\{{123}}boo');
    _assertText('far{{id:bern}}boo', 'far{{id:bern}}boo');
    _assertText('far{{id:bern {{basel}}}}boo', 'far{{id:bern {{basel}}}}boo');
    _assertText(
      'far{{id:bern {{id:basel}}}}boo',
      'far{{id:bern {{id:basel}}}}boo',
    );
    _assertText(
      'far{{id:bern {{id2:basel}}}}boo',
      'far{{id:bern {{id2:basel}}}}boo',
    );
  });

  test('Parser, TM text', () {
    _assertTextAndMarker(r'foo${1:bar}}', 'foobar}', [
      _text,
      _placeholder,
      _text,
    ]);
    _assertTextAndMarker(r'foo${1:bar}${2:foo}}', 'foobarfoo}', [
      _text,
      _placeholder,
      _placeholder,
      _text,
    ]);
    _assertTextAndMarker(r'foo${1:bar\}${2:foo}}', 'foobar}foo', [
      _text,
      _placeholder,
    ]);

    final placeholder =
        SnippetParser().parse(r'foo${1:bar\}${2:foo}}').children[1]
            as Placeholder;
    final children = placeholder.children;
    expect(placeholder.index, 1);
    expect(children[0], _text);
    expect(children[0].toString(), 'bar}');
    expect(children[1], _placeholder);
    expect(children[1].toString(), 'foo');
  });

  test('Parser, placeholder', () {
    _assertTextAndMarker('farboo', 'farboo', [_text]);
    _assertTextAndMarker('far{{}}boo', 'far{{}}boo', [_text]);
    _assertTextAndMarker('far{{123}}boo', 'far{{123}}boo', [_text]);
    _assertTextAndMarker(r'far\{{123}}boo', r'far\{{123}}boo', [_text]);
  });

  test('Parser, literal code', () {
    _assertTextAndMarker('far`123`boo', 'far`123`boo', [_text]);
    _assertTextAndMarker(r'far\`123\`boo', r'far\`123\`boo', [_text]);
  });

  test('Parser, variables/tabstop', () {
    _assertTextAndMarker(r'$far-boo', '-boo', [_variable, _text]);
    _assertTextAndMarker(r'\$far-boo', r'$far-boo', [_text]);
    _assertTextAndMarker(r'far$farboo', 'far', [_text, _variable]);
    _assertTextAndMarker(r'far${farboo}', 'far', [_text, _variable]);
    _assertTextAndMarker(r'$123', '', [_placeholder]);
    _assertTextAndMarker(r'$farboo', '', [_variable]);
    _assertTextAndMarker(r'$far12boo', '', [_variable]);
    _assertTextAndMarker(r'000_${far}_000', '000__000', [
      _text,
      _variable,
      _text,
    ]);
    _assertTextAndMarker(r'FFF_${TM_SELECTED_TEXT}_FFF$0', 'FFF__FFF', [
      _text,
      _variable,
      _text,
      _placeholder,
    ]);
  });

  test('Parser, variables/placeholder with defaults', () {
    _assertTextAndMarker(r'${name:value}', 'value', [_variable]);
    _assertTextAndMarker(r'${1:value}', 'value', [_placeholder]);
    _assertTextAndMarker(r'${1:bar${2:foo}bar}', 'barfoobar', [_placeholder]);

    _assertTextAndMarker(r'${name:value', r'${name:value', [_text]);
    _assertTextAndMarker(r'${1:bar${2:foobar}', r'${1:barfoobar', [
      _text,
      _placeholder,
    ]);
  });

  test('Parser, variable transforms', () {
    _assertTextAndMarker(r'${foo///}', '', [_variable]);
    _assertTextAndMarker(r'${foo/regex/format/gmi}', '', [_variable]);
    _assertTextAndMarker(r'${foo/([A-Z][a-z])/format/}', '', [_variable]);

    // invalid regex
    _assertTextAndMarker(
      r'${foo/([A-Z][a-z])/format/GMI}',
      r'${foo/([A-Z][a-z])/format/GMI}',
      [_text],
    );
    _assertTextAndMarker(
      r'${foo/([A-Z][a-z])/format/funky}',
      r'${foo/([A-Z][a-z])/format/funky}',
      [_text],
    );
    _assertTextAndMarker(
      r'${foo/([A-Z][a-z]/format/}',
      r'${foo/([A-Z][a-z]/format/}',
      [_text],
    );

    // tricky regex
    _assertTextAndMarker(r'${foo/m\/atch/$1/i}', '', [_variable]);
    _assertMarker(r'${foo/regex/format/options}', [_text]);

    // incomplete
    _assertTextAndMarker(r'${foo///', r'${foo///', [_text]);
    _assertTextAndMarker(
      r'${foo/regex/format/options',
      r'${foo/regex/format/options',
      [_text],
    );

    // format string
    _assertMarker(r'${foo/.*/${0:fooo}/i}', [_variable]);
    _assertMarker(r'${foo/.*/${1}/i}', [_variable]);
    _assertMarker(r'${foo/.*/$1/i}', [_variable]);
    _assertMarker(r'${foo/.*/This-$1-encloses/i}', [_variable]);
    _assertMarker(r'${foo/.*/complex${1:else}/i}', [_variable]);
    _assertMarker(r'${foo/.*/complex${1:-else}/i}', [_variable]);
    _assertMarker(r'${foo/.*/complex${1:+if}/i}', [_variable]);
    _assertMarker(r'${foo/.*/complex${1:?if:else}/i}', [_variable]);
    _assertMarker(r'${foo/.*/complex${1:/upcase}/i}', [_variable]);
  });

  test('Parser, placeholder transforms', () {
    _assertTextAndMarker(r'${1///}', '', [_placeholder]);
    _assertTextAndMarker(r'${1/regex/format/gmi}', '', [_placeholder]);
    _assertTextAndMarker(r'${1/([A-Z][a-z])/format/}', '', [_placeholder]);

    // tricky regex
    _assertTextAndMarker(r'${1/m\/atch/$1/i}', '', [_placeholder]);
    _assertMarker(r'${1/regex/format/options}', [_text]);

    // incomplete
    _assertTextAndMarker(r'${1///', r'${1///', [_text]);
    _assertTextAndMarker(
      r'${1/regex/format/options',
      r'${1/regex/format/options',
      [_text],
    );
  });

  test('No way to escape forward slash in snippet regex #36715', () {
    _assertMarker(r'${TM_DIRECTORY/src\//$1/}', [_variable]);
  });

  test('No way to escape forward slash in snippet format section #37562', () {
    _assertMarker(r'${TM_SELECTED_TEXT/a/\/$1/g}', [_variable]);
    _assertMarker(r'${TM_SELECTED_TEXT/a/in\/$1ner/g}', [_variable]);
    _assertMarker(r'${TM_SELECTED_TEXT/a/end\//g}', [_variable]);
  });

  test('Parser, placeholder with choice', () {
    _assertTextAndMarker(r'${1|one,two,three|}', 'one', [_placeholder]);
    _assertTextAndMarker(r'${1|one|}', 'one', [_placeholder]);
    _assertTextAndMarker(r'${1|one1,two2|}', 'one1', [_placeholder]);
    _assertTextAndMarker(r'${1|one1\,two2|}', 'one1,two2', [_placeholder]);
    _assertTextAndMarker(r'${1|one1\|two2|}', 'one1|two2', [_placeholder]);
    _assertTextAndMarker(r'${1|one1\atwo2|}', r'one1\atwo2', [_placeholder]);
    _assertTextAndMarker(r'${1|one,two,three,|}', r'${1|one,two,three,|}', [
      _text,
    ]);
    _assertTextAndMarker(r'${1|one,', r'${1|one,', [_text]);

    final snippet = SnippetParser().parse(r'${1|one,two,three|}');
    final expected = <bool Function(Marker)>[
      (m) => m is Placeholder,
      (m) => m is Choice && m.options.length == 3,
    ];
    snippet.walk((marker) {
      expect(expected.removeAt(0)(marker), isTrue);
      return true;
    });
  });

  test('Snippet choices: unable to escape comma and pipe, #31521', () {
    _assertTextAndMarker(
      r'console.log(${1|not\, not, five, 5, 1   23|});',
      'console.log(not, not);',
      [_text, _placeholder, _text],
    );
  });

  test('Marker, toTextmateString()', () {
    void assertTextsnippetString(String input, String expected) {
      expect(SnippetParser().parse(input).toTextmateString(), expected);
    }

    assertTextsnippetString(r'$1', r'$1');
    assertTextsnippetString(r'\$1', r'\$1');
    assertTextsnippetString(
      r'console.log(${1|not\, not, five, 5, 1   23|});',
      r'console.log(${1|not\, not, five, 5, 1   23|});',
    );
    assertTextsnippetString(
      r'console.log(${1|not\, not, \| five, 5, 1   23|});',
      r'console.log(${1|not\, not, \| five, 5, 1   23|});',
    );
    assertTextsnippetString(
      r'${1|cho\,ices,wi\|th,esc\\aping,chall\\\,enges|}',
      r'${1|cho\,ices,wi\|th,esc\\aping,chall\\\,enges|}',
    );
    assertTextsnippetString('this is text', 'this is text');
    assertTextsnippetString(
      r'this ${1:is ${2:nested with $var}}',
      r'this ${1:is ${2:nested with ${var}}}',
    );
    assertTextsnippetString(
      r'this ${1:is ${2:nested with $var}}}',
      r'this ${1:is ${2:nested with ${var}}}\}',
    );
  });

  test('Marker, toTextmateString() <-> identity', () {
    void assertIdent(String input) {
      final snippet = SnippetParser().parse(input);
      final input2 = snippet.toTextmateString();
      final snippet2 = SnippetParser().parse(input2);

      void check(Marker marker1, Marker marker2) {
        expect(marker1.runtimeType, marker2.runtimeType);
        expect(marker1.children.length, marker2.children.length);
        expect(marker1.toString(), marker2.toString());
        for (var i = 0; i < marker1.children.length; i++) {
          check(marker1.children[i], marker2.children[i]);
        }
      }

      check(snippet, snippet2);
    }

    assertIdent(r'$1');
    assertIdent(r'\$1');
    assertIdent(r'console.log(${1|not\, not, five, 5, 1   23|});');
    assertIdent(r'console.log(${1|not\, not, \| five, 5, 1   23|});');
    assertIdent('this is text');
    assertIdent(r'this ${1:is ${2:nested with $var}}');
    assertIdent(r'this ${1:is ${2:nested with $var}}}');
    assertIdent(r'this ${1:is ${2:nested with $var}} and repeating $1');
  });

  test('Parser, choise marker', () {
    final placeholders = SnippetParser()
        .parse(r'${1|one,two,three|}')
        .placeholders;
    expect(placeholders.length, 1);
    expect(placeholders[0].choice, isA<Choice>());
    expect(placeholders[0].children[0], isA<Choice>());
    expect((placeholders[0].children[0] as Choice).options.length, 3);

    _assertText(r'${1|one,two,three|}', 'one');
    _assertText(r'\${1|one,two,three|}', r'${1|one,two,three|}');
    _assertText(r'${1\|one,two,three|}', r'${1\|one,two,three|}');
    _assertText(r'${1||}', r'${1||}');
  });

  test("Backslash character escape in choice tabstop doesn't work #58494", () {
    final placeholders = SnippetParser()
        .parse(r'${1|\,,},$,\|,\\|}')
        .placeholders;
    expect(placeholders.length, 1);
    expect(placeholders[0].choice, isA<Choice>());
  });

  test('Parser, only textmate', () {
    final p = SnippetParser();
    _assertMarker(p.parse('far{{}}boo'), [_text]);
    _assertMarker(p.parse('far{{123}}boo'), [_text]);
    _assertMarker(p.parse(r'far\{{123}}boo'), [_text]);

    _assertMarker(p.parse(r'far$0boo'), [_text, _placeholder, _text]);
    _assertMarker(p.parse(r'far${123}boo'), [_text, _placeholder, _text]);
    _assertMarker(p.parse(r'far\${123}boo'), [_text]);
  });

  test('Parser, real world', () {
    var marker = SnippetParser()
        .parse(r'console.warn(${1: $TM_SELECTED_TEXT })')
        .children;

    expect(marker[0].toString(), 'console.warn(');
    expect(marker[1], _placeholder);
    expect(marker[2].toString(), ')');

    final placeholder = marker[1] as Placeholder;
    expect(placeholder.index, 1);
    expect(placeholder.children.length, 3);
    expect(placeholder.children[0], _text);
    expect(placeholder.children[1], _variable);
    expect(placeholder.children[2], _text);
    expect(placeholder.children[0].toString(), ' ');
    expect(placeholder.children[1].toString(), '');
    expect(placeholder.children[2].toString(), ' ');

    final nestedVariable = placeholder.children[1] as Variable;
    expect(nestedVariable.name, 'TM_SELECTED_TEXT');
    expect(nestedVariable.children.length, 0);

    marker = SnippetParser().parse(r'$TM_SELECTED_TEXT').children;
    expect(marker.length, 1);
    expect(marker[0], _variable);
  });

  test('Parser, transform example', () {
    final children = SnippetParser()
        .parse(
          r'${1:name} : ${2:type}${3/\s:=(.*)/${1:+ :=}${1}/};'
          '\n\$0',
        )
        .children;

    // ${1:name}
    expect(children[0], _placeholder);
    expect(children[0].children.length, 1);
    expect(children[0].children[0].toString(), 'name');
    expect((children[0] as Placeholder).transform, isNull);

    // :
    expect(children[1], _text);
    expect(children[1].toString(), ' : ');

    // ${2:type}
    expect(children[2], _placeholder);
    expect(children[2].children.length, 1);
    expect(children[2].children[0].toString(), 'type');

    // ${3/\\s:=(.*)/${1:+ :=}${1}/}
    expect(children[3], _placeholder);
    expect(children[3].children.length, 0);
    final transform = (children[3] as Placeholder).transform!;
    expect(transform.regexp.source, r'\s:=(.*)');
    expect(transform.regexp.flags, '');
    expect(transform.children.length, 2);
    expect(transform.children[0], isA<FormatString>());
    expect((transform.children[0] as FormatString).index, 1);
    expect((transform.children[0] as FormatString).ifValue, ' :=');
    expect(transform.children[1], isA<FormatString>());
    expect((transform.children[1] as FormatString).index, 1);
    expect(children[4], _text);
    expect(children[4].toString(), ';\n');
  });

  test('Parser, default placeholder values', () {
    _assertMarker(r'errorContext: `${1:err}`, error: $1', [
      _text,
      _placeholder,
      _text,
      _placeholder,
    ]);

    final children = SnippetParser()
        .parse(r'errorContext: `${1:err}`, error:$1')
        .children;
    final p1 = children[1] as Placeholder;
    final p2 = children[3] as Placeholder;

    expect(p1.index, 1);
    expect(p1.children.length, 1);
    expect(p1.children[0].toString(), 'err');

    expect(p2.index, 1);
    expect(p2.children.length, 1);
    expect(p2.children[0].toString(), 'err');
  });

  test('Parser, default placeholder values and one transform', () {
    _assertMarker(r'errorContext: `${1:err}`, error: ${1/err/ok/}', [
      _text,
      _placeholder,
      _text,
      _placeholder,
    ]);

    final children = SnippetParser()
        .parse(r'errorContext: `${1:err}`, error:${1/err/ok/}')
        .children;
    final p3 = children[1] as Placeholder;
    final p4 = children[3] as Placeholder;

    expect(p3.index, 1);
    expect(p3.children.length, 1);
    expect(p3.children[0].toString(), 'err');
    expect(p3.transform, isNull);

    expect(p4.index, 1);
    expect(p4.children.length, 1);
    expect(p4.children[0].toString(), 'err');
    expect(p4.transform, isNotNull);
  });

  test('Repeated snippet placeholder should always inherit, #31040', () {
    _assertText(r'${1:foo}-abc-$1', 'foo-abc-foo');
    _assertText(r'${1:foo}-abc-${1}', 'foo-abc-foo');
    _assertText(r'${1:foo}-abc-${1:bar}', 'foo-abc-foo');
    _assertText(r'${1}-abc-${1:foo}', 'foo-abc-foo');
  });

  test('backspace esapce in TM only, #16212', () {
    expect(SnippetParser.asInsertText(r'Foo \\${abc}bar'), r'Foo \bar');
  });

  test('colon as variable/placeholder value, #16717', () {
    expect(
      SnippetParser.asInsertText(r'${TM_SELECTED_TEXT:foo:bar}'),
      'foo:bar',
    );
    expect(SnippetParser.asInsertText(r'${1:foo:bar}'), 'foo:bar');
  });

  test('incomplete placeholder', () {
    _assertTextAndMarker(r'${1:}', '', [_placeholder]);
  });

  test('marker#len', () {
    void assertLen(String template, List<int> lengths) {
      final expected = [...lengths];
      SnippetParser().parse(template, true).walk((m) {
        expect(m.len(), expected.removeAt(0), reason: template);
        return true;
      });
      expect(expected, isEmpty);
    }

    assertLen(r'text$0', [4, 0]);
    assertLen(r'$1text$0', [0, 4, 0]);
    assertLen(r'te$1xt$0', [2, 0, 2, 0]);
    assertLen(r'errorContext: `${1:err}`, error: $0', [15, 0, 3, 10, 0]);
    assertLen(r'errorContext: `${1:err}`, error: $1$0', [
      15,
      0,
      3,
      10,
      0,
      3,
      0,
    ]);
    assertLen(r'$TM_SELECTED_TEXT$0', [0, 0]);
    assertLen(r'${TM_SELECTED_TEXT:def}$0', [0, 3, 0]);
  });

  test('parser, parent node', () {
    var snippet = SnippetParser().parse(r'This ${1:is ${2:nested}}$0', true);

    expect(snippet.placeholders.length, 3);
    var first = snippet.placeholders[0];
    final second = snippet.placeholders[1];
    expect(first.index, 1);
    expect(second.index, 2);
    expect(identical(second.parent, first), isTrue);
    expect(identical(first.parent, snippet), isTrue);

    snippet = SnippetParser().parse(r'${VAR:default${1:value}}$0', true);
    expect(snippet.placeholders.length, 2);
    first = snippet.placeholders[0];
    expect(first.index, 1);

    expect(snippet.children[0], _variable);
    expect(identical(first.parent, snippet.children[0]), isTrue);
  });

  test('TextmateSnippet#enclosingPlaceholders', () {
    final snippet = SnippetParser().parse(r'This ${1:is ${2:nested}}$0', true);
    final [first, second, ...] = snippet.placeholders;

    expect(snippet.enclosingPlaceholders(first), isEmpty);
    expect(snippet.enclosingPlaceholders(second), [first]);
  });

  test('TextmateSnippet#offset', () {
    var snippet = SnippetParser().parse(r'te$1xt', true);
    expect(snippet.offset(snippet.children[0]), 0);
    expect(snippet.offset(snippet.children[1]), 2);
    expect(snippet.offset(snippet.children[2]), 2);

    snippet = SnippetParser().parse(r'${TM_SELECTED_TEXT:def}', true);
    expect(snippet.offset(snippet.children[0]), 0);
    expect(snippet.offset(snippet.children[0].children[0]), 0);

    // forgein marker
    expect(snippet.offset(Text('foo')), -1);
  });

  test('TextmateSnippet#placeholder', () {
    var snippet = SnippetParser().parse(r'te$1xt$0', true);
    expect(snippet.placeholders.length, 2);

    snippet = SnippetParser().parse(r'te$1xt$1$0', true);
    expect(snippet.placeholders.length, 3);

    snippet = SnippetParser().parse(r'te$1xt$2$0', true);
    expect(snippet.placeholders.length, 3);

    snippet = SnippetParser().parse(r'${1:bar${2:foo}bar}$0', true);
    expect(snippet.placeholders.length, 3);
  });

  test('TextmateSnippet#replace 1/2', () {
    final snippet = SnippetParser().parse(r'aaa${1:bbb${2:ccc}}$0', true);

    expect(snippet.placeholders.length, 3);
    final second = snippet.placeholders[1];
    expect(second.index, 2);

    final enclosing = snippet.enclosingPlaceholders(second);
    expect(enclosing.length, 1);
    expect(enclosing[0].index, 1);

    final nested = SnippetParser().parse(r'ddd$1eee$0', true);
    snippet.replace(second, nested.children);

    expect(snippet.toString(), 'aaabbbdddeee');
    expect(snippet.placeholders.length, 4);
    expect(snippet.placeholders[0].index, 1);
    expect(snippet.placeholders[1].index, 1);
    expect(snippet.placeholders[2].index, 0);
    expect(snippet.placeholders[3].index, 0);

    final newEnclosing = snippet.enclosingPlaceholders(snippet.placeholders[1]);
    expect(identical(newEnclosing[0], snippet.placeholders[0]), isTrue);
    expect(newEnclosing.length, 1);
    expect(newEnclosing[0].index, 1);
  });

  test('TextmateSnippet#replace 2/2', () {
    final snippet = SnippetParser().parse(r'aaa${1:bbb${2:ccc}}$0', true);

    expect(snippet.placeholders.length, 3);
    final second = snippet.placeholders[1];
    expect(second.index, 2);

    final nested = SnippetParser().parse(r'dddeee$0', true);
    snippet.replace(second, nested.children);

    expect(snippet.toString(), 'aaabbbdddeee');
    expect(snippet.placeholders.length, 3);
  });

  test('Snippet order for placeholders, #28185', () {
    expect(Placeholder.compareByIndex(Placeholder(10), Placeholder(2)), 1);
  });

  test('Maximum call stack size exceeded, #28983', () {
    SnippetParser().parse(r'${1:${foo:${1}}}');
  });

  test('Snippet can freeze the editor, #30407', () {
    final seen = <Marker>{};
    SnippetParser()
        .parse(
          r'class ${1:${TM_FILENAME/(?:\A|_)([A-Za-z0-9]+)(?:\.rb)?/(?2::\u$1)/g}} < ${2:Application}Controller'
          '\n  \$3\nend',
        )
        .walk((marker) {
          expect(seen.add(marker), isTrue);
          return true;
        });

    seen.clear();
    SnippetParser().parse(r'${1:${FOO:abc$1def}}').walk((marker) {
      expect(seen.add(marker), isTrue);
      return true;
    });
  });

  test(r'Snippets: make parser ignore `${0|choice|}`, #31599', () {
    _assertTextAndMarker(r'${0|foo,bar|}', r'${0|foo,bar|}', [_text]);
    _assertTextAndMarker(r'${1|foo,bar|}', 'foo', [_placeholder]);
  });

  test('Transform -> FormatString#resolve', () {
    // shorthand functions
    expect(FormatString(1, 'upcase').resolve('foo'), 'FOO');
    expect(FormatString(1, 'downcase').resolve('FOO'), 'foo');
    expect(FormatString(1, 'capitalize').resolve('bar'), 'Bar');
    expect(
      FormatString(1, 'capitalize').resolve('bar no repeat'),
      'Bar no repeat',
    );
    expect(FormatString(1, 'pascalcase').resolve('bar-foo'), 'BarFoo');
    expect(FormatString(1, 'pascalcase').resolve('bar-42-foo'), 'Bar42Foo');
    expect(
      FormatString(1, 'pascalcase').resolve('snake_AndPascalCase'),
      'SnakeAndPascalCase',
    );
    expect(
      FormatString(1, 'pascalcase').resolve('kebab-AndPascalCase'),
      'KebabAndPascalCase',
    );
    expect(
      FormatString(1, 'pascalcase').resolve('_justPascalCase'),
      'JustPascalCase',
    );
    expect(FormatString(1, 'camelcase').resolve('bar-foo'), 'barFoo');
    expect(FormatString(1, 'camelcase').resolve('bar-42-foo'), 'bar42Foo');
    expect(
      FormatString(1, 'camelcase').resolve('snake_AndCamelCase'),
      'snakeAndCamelCase',
    );
    expect(
      FormatString(1, 'camelcase').resolve('kebab-AndCamelCase'),
      'kebabAndCamelCase',
    );
    expect(
      FormatString(1, 'camelcase').resolve('_JustCamelCase'),
      'justCamelCase',
    );
    expect(FormatString(1, 'kebabcase').resolve('barFoo'), 'bar-foo');
    expect(FormatString(1, 'kebabcase').resolve('BarFoo'), 'bar-foo');
    expect(FormatString(1, 'kebabcase').resolve('ABarFoo'), 'a-bar-foo');
    expect(FormatString(1, 'kebabcase').resolve('bar42Foo'), 'bar42-foo');
    expect(
      FormatString(1, 'kebabcase').resolve('snake_AndPascalCase'),
      'snake-and-pascal-case',
    );
    expect(
      FormatString(1, 'kebabcase').resolve('kebab-AndCamelCase'),
      'kebab-and-camel-case',
    );
    expect(
      FormatString(1, 'kebabcase').resolve('_justPascalCase'),
      'just-pascal-case',
    );
    expect(FormatString(1, 'kebabcase').resolve('__UPCASE__'), 'upcase');
    expect(FormatString(1, 'kebabcase').resolve('__BAR_FOO__'), 'bar-foo');
    expect(FormatString(1, 'snakecase').resolve('bar-foo'), 'bar_foo');
    expect(FormatString(1, 'snakecase').resolve('bar-42-foo'), 'bar_42_foo');
    expect(
      FormatString(1, 'snakecase').resolve('snake_AndPascalCase'),
      'snake_and_pascal_case',
    );
    expect(
      FormatString(1, 'snakecase').resolve('kebab-AndPascalCase'),
      'kebab_and_pascal_case',
    );
    expect(
      FormatString(1, 'snakecase').resolve('_justPascalCase'),
      '_just_pascal_case',
    );
    expect(FormatString(1, 'notKnown').resolve('input'), 'input');

    // if
    expect(FormatString(1, null, 'foo', null).resolve(null), '');
    expect(FormatString(1, null, 'foo', null).resolve(''), '');
    expect(FormatString(1, null, 'foo', null).resolve('bar'), 'foo');

    // else
    expect(FormatString(1, null, null, 'foo').resolve(null), 'foo');
    expect(FormatString(1, null, null, 'foo').resolve(''), 'foo');
    expect(FormatString(1, null, null, 'foo').resolve('bar'), 'bar');

    // if-else
    expect(FormatString(1, null, 'bar', 'foo').resolve(null), 'foo');
    expect(FormatString(1, null, 'bar', 'foo').resolve(''), 'foo');
    expect(FormatString(1, null, 'bar', 'foo').resolve('baz'), 'bar');
  });

  test('Unicode Variable Transformations', () {
    final resolver = _MapResolver(const {
      'RUSSIAN': 'одинДва',
      'GREEK': 'έναςΔύο',
      'TURKISH': 'istanbulLı',
      'JAPANESE': 'こんにちは',
    });

    void assertTransform(
      String transformName,
      String varName,
      String expected,
    ) {
      final snippet = SnippetParser().parse(
        '\${$varName/(.*)/\${1:/$transformName}/}',
      );
      final variable = snippet.children[0] as Variable;
      variable.resolve(resolver);
      expect(
        variable.toString(),
        expected,
        reason: '$transformName failed for $varName',
      );
    }

    assertTransform('kebabcase', 'RUSSIAN', 'один-два');
    assertTransform('kebabcase', 'GREEK', 'ένας-δύο');
    assertTransform('snakecase', 'RUSSIAN', 'один_два');
    assertTransform('snakecase', 'GREEK', 'ένας_δύο');
    assertTransform('camelcase', 'RUSSIAN', 'одинДва');
    assertTransform('camelcase', 'GREEK', 'έναςΔύο');
    assertTransform('pascalcase', 'RUSSIAN', 'ОдинДва');
    assertTransform('pascalcase', 'GREEK', 'ΈναςΔύο');
    assertTransform('upcase', 'RUSSIAN', 'ОДИНДВА');
    assertTransform('downcase', 'RUSSIAN', 'одиндва');
    assertTransform('kebabcase', 'TURKISH', 'istanbul-lı');
    assertTransform('pascalcase', 'TURKISH', 'IstanbulLı');
    assertTransform('upcase', 'JAPANESE', 'こんにちは');
    assertTransform('kebabcase', 'JAPANESE', 'こんにちは');
  });

  test("Snippet variable transformation doesn't work if regex is complicated "
      r"and snippet body contains '$$' #55627", () {
    final snippet = SnippetParser().parse(
      r'const fileName = "${TM_FILENAME/(.*)\..+$/$1/}"',
    );
    expect(
      snippet.toTextmateString(),
      r'const fileName = "${TM_FILENAME/(.*)\..+$/${1}/}"',
    );
  });

  test('[BUG] HTML attribute suggestions: Snippet session does not have '
      'end-position set, #33147', () {
    final placeholders = SnippetParser().parse(r'src="$1"', true).placeholders;
    expect(placeholders.length, 2);
    expect(placeholders[0].index, 1);
    expect(placeholders[1].index, 0);
  });

  test('Snippet optional transforms are not applied correctly when reusing the '
      'same variable, #37702', () {
    final transform = Transform();
    transform.appendChild(FormatString(1, 'upcase'));
    transform.appendChild(FormatString(2, 'upcase'));
    transform.regexp = SnippetRegExp(r'^(.)|-(.)', 'g');

    expect(transform.resolve('my-file-name'), 'MyFileName');

    final clone = transform.clone();
    expect(clone.resolve('my-file-name'), 'MyFileName');
  });

  test('problem with snippets regex #40570', () {
    final snippet = SnippetParser().parse(r'${TM_DIRECTORY/.*src[\/](.*)/$1/}');
    _assertMarker(snippet, [_variable]);
  });

  test(
    "Variable transformation doesn't work if undefined variables are used in "
    'the same snippet #51769',
    () {
      final transform = Transform();
      transform.appendChild(Text('bar'));
      transform.regexp = SnippetRegExp('foo', 'gi');
      expect(transform.toTextmateString(), '/foo/bar/ig');
    },
  );

  test('transform serialization joins children without comma', () {
    final transform = Transform();
    transform.appendChild(FormatString(1, 'upcase'));
    transform.appendChild(Text('_'));
    transform.regexp = SnippetRegExp('foo', 'g');
    final serialized = transform.toTextmateString();
    expect(serialized, r'/foo/${1:/upcase}_/g');

    final snippet = SnippetParser().parse('\${TM_FILENAME$serialized}');
    expect(snippet.toTextmateString(), '\${TM_FILENAME$serialized}');
  });

  test('Snippet parser freeze #53144', () {
    final snippet = SnippetParser().parse(
      '\${1/(void\$)|(.+)/\${1:?-\treturn nil;}/}',
    );
    _assertMarker(snippet, [_placeholder]);
  });

  test('snippets variable not resolved in JSON proposal #52931', () {
    _assertTextAndMarker(r'FOO${1:/bin/bash}', 'FOO/bin/bash', [
      _text,
      _placeholder,
    ]);
  });

  test('Mirroring sequence of nested placeholders not selected properly on '
      'backjumping #58736', () {
    final snippet = SnippetParser().parse(
      r'${3:nest1 ${1:nest2 ${2:nest3}}} $3',
    );
    expect(snippet.children.length, 3);
    expect(snippet.children[0], _placeholder);
    expect(snippet.children[1], _text);
    expect(snippet.children[2], _placeholder);

    void assertParent(Marker marker) {
      marker.children.forEach(assertParent);
      if (marker is! Placeholder) return;
      var found = false;
      Marker? m = marker;
      while (m != null && !found) {
        if (identical(m.parent, snippet)) found = true;
        m = m.parent;
      }
      expect(found, isTrue);
    }

    assertParent(snippet.children[2]);
  });

  test("Backspace can't be escaped in snippet variable transforms #65412", () {
    final snippet = SnippetParser().parse(
      r'namespace ${TM_DIRECTORY/[\/]/\\/g};',
    );
    _assertMarker(snippet, [_text, _variable, _text]);
  });

  test('Snippet cannot escape closing bracket inside conditional insertion '
      'variable replacement #78883', () {
    final snippet = SnippetParser().parse(
      r'${TM_DIRECTORY/(.+)/${1:+import { hello \} from world}/}',
    );
    final variable = snippet.children[0] as Variable;
    expect(snippet.children.length, 1);
    expect(variable.transform, isNotNull);
    expect(variable.transform!.children.length, 1);
    final format = variable.transform!.children[0] as FormatString;
    expect(format.ifValue, 'import { hello } from world');
    expect(format.elseValue, isNull);
  });

  test('Snippet escape backslashes inside conditional insertion variable '
      'replacement #80394', () {
    final snippet = SnippetParser().parse(r'${CURRENT_YEAR/(.+)/${1:+\\}/}');
    final variable = snippet.children[0] as Variable;
    expect(snippet.children.length, 1);
    expect(variable.transform, isNotNull);
    expect(variable.transform!.children.length, 1);
    final format = variable.transform!.children[0] as FormatString;
    expect(format.ifValue, r'\');
    expect(format.elseValue, isNull);
  });

  test('Snippet placeholder empty right after expansion #152553', () {
    expect(
      SnippetParser().parse(r'${1:prog}: ${2:$1.cc} - $2').toString(),
      'prog: prog.cc - prog.cc',
    );
    expect(
      SnippetParser()
          .parse(r'${1:prog}: ${3:${2:$1.cc}.33} - $2 $3')
          .toString(),
      'prog: prog.cc.33 - prog.cc prog.cc.33',
    );
    // cyclic references of placeholders
    expect(
      SnippetParser().parse(r'${1:$2.one} <> ${2:$1.two}').toString(),
      '.two.one.two.one <> .one.two.one.two',
    );
  });

  test('Snippet choices are incorrectly escaped/applied #180132', () {
    _assertTextAndMarker(r'${1|aaa$aaa|}bbb\$bbb', r'aaa$aaabbb$bbb', [
      _placeholder,
      _text,
    ]);
  });
}

class _MapResolver implements VariableResolver {
  const _MapResolver(this.values);

  final Map<String, String> values;

  @override
  String? resolve(Variable variable) => values[variable.name];
}
