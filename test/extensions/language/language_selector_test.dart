// Mirrors src/vs/editor/test/common/modes/languageSelector.test.ts
// (VS Code 1.135.0).

import 'package:bao_editor/monaco/vs/base/common/glob.dart' as glob;
import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/extensions/language/language_selector.dart';
import 'package:flutter_test/flutter_test.dart';

LanguageSelector? sel(Object? json) => LanguageSelector.parse(json);

void main() {
  final modelUri = VsUri.parse('file:///testbed/file.fb');
  const modelLanguage = 'farboo';

  int s(Object? selector, [VsUri? uri, String? language, bool sync = true]) =>
      score(
        selector is LanguageSelector ? selector : sel(selector),
        uri ?? modelUri,
        language ?? modelLanguage,
        sync,
        null,
        null,
      );

  test('score, invalid selector', () {
    expect(s(<String, Object?>{}), 0);
    expect(s(null), 0);
    expect(s(''), 0);
  });

  test('score, any language', () {
    expect(s({'language': '*'}), 5);
    expect(s('*'), 5);
    expect(s('*', VsUri.parse('foo:bar')), 5);
    expect(s('farboo', VsUri.parse('foo:bar')), 10);
  });

  test('score, default schemes', () {
    final uri = VsUri.parse('git:foo/file.txt');
    expect(s('*', uri), 5);
    expect(s('farboo', uri), 10);
    expect(s({'language': 'farboo', 'scheme': ''}, uri), 10);
    expect(s({'language': 'farboo', 'scheme': 'git'}, uri), 10);
    expect(s({'language': 'farboo', 'scheme': '*'}, uri), 10);
    expect(s({'language': 'farboo'}, uri), 10);
    expect(s({'language': '*'}, uri), 5);
    expect(s({'scheme': '*'}, uri), 5);
    expect(s({'scheme': 'git'}, uri), 10);
  });

  test('score, filter', () {
    expect(s('farboo'), 10);
    expect(s({'language': 'farboo'}), 10);
    expect(s({'language': 'farboo', 'scheme': 'file'}), 10);
    expect(s({'language': 'farboo', 'scheme': 'http'}), 0);

    expect(s({'pattern': '**/*.fb'}), 10);
    expect(s({'pattern': '**/*.fb', 'scheme': 'file'}), 10);
    expect(s({'pattern': '**/*.fb'}, VsUri.parse('foo:bar')), 0);
    expect(s({'pattern': '**/*.fb', 'scheme': 'foo'}, VsUri.parse('foo:bar')), 0);

    final docUri = VsUri.parse('git:/my/file.js');
    expect(s('javascript', docUri, 'javascript'), 10);
    expect(
      s({'language': 'javascript', 'scheme': 'git'}, docUri, 'javascript'),
      10,
    );
    expect(s('*', docUri, 'javascript'), 5);
    expect(s('fooLang', docUri, 'javascript'), 0);
    expect(s(['fooLang', '*'], docUri, 'javascript'), 5);
  });

  test('score, max(filters)', () {
    final match = {'language': 'farboo', 'scheme': 'file'};
    final fail = {'language': 'farboo', 'scheme': 'http'};
    expect(s(match), 10);
    expect(s(fail), 0);
    expect(s([match, fail]), 10);
    expect(s([fail, fail]), 0);
    expect(s(['farboo', '*']), 10);
    expect(s(['*', 'farboo']), 10);
  });

  test('score hasAccessToAllModels', () {
    final uri = VsUri.parse('file:/my/file.js');
    expect(s('javascript', uri, 'javascript', false), 0);
    expect(
      s({'language': 'javascript', 'scheme': 'file'}, uri, 'javascript', false),
      0,
    );
    expect(s('*', uri, 'javascript', false), 0);
    expect(s('fooLang', uri, 'javascript', false), 0);
    expect(s(['fooLang', '*'], uri, 'javascript', false), 0);

    expect(
      s(
        {
          'language': 'javascript',
          'scheme': 'file',
          'hasAccessToAllModels': true,
        },
        uri,
        'javascript',
        false,
      ),
      10,
    );
    expect(
      s(
        [
          'fooLang',
          '*',
          {'language': '*', 'hasAccessToAllModels': true},
        ],
        uri,
        'javascript',
        false,
      ),
      5,
    );
  });

  test('score, notebookType', () {
    final uri = VsUri.parse('vscode-notebook-cell:///my/file.js#blabla');
    const langId = 'javascript';
    const notebookType = 'fooBook';
    final notebookUri = VsUri.parse('file:///my/file.js');

    int nb(Object selector) =>
        score(sel(selector), uri, langId, true, notebookUri, notebookType);

    expect(score(sel('javascript'), uri, langId, true, null, null), 10);
    expect(nb('javascript'), 10);
    expect(nb({'notebookType': 'fooBook'}), 10);
    expect(
      nb({'notebookType': 'fooBook', 'language': 'javascript', 'scheme': 'file'}),
      10,
    );
    expect(nb({'notebookType': 'fooBook', 'language': '*'}), 10);
    expect(nb({'notebookType': '*', 'language': '*'}), 5);
    expect(nb({'notebookType': '*', 'language': 'javascript'}), 10);
  });

  test('Snippet choices lost #149363', () {
    final selector = {
      'scheme': 'vscode-notebook-cell',
      'pattern': '/some/path/file.py',
      'language': 'python',
    };
    final modelUri = VsUri.parse('vscode-notebook-cell:///some/path/file.py');
    final nbUri = VsUri.parse('file:///some/path/file.py');
    expect(score(sel(selector), modelUri, 'python', true, nbUri, 'jupyter'), 10);

    final selector2 = {...selector, 'notebookType': 'jupyter'};
    expect(score(sel(selector2), modelUri, 'python', true, nbUri, 'jupyter'), 0);
  });

  test('Document selector match - unexpected result value #60232', () {
    final value = s(
      {'language': 'json', 'scheme': 'file', 'pattern': '**/*.interface.json'},
      VsUri.parse('file:///C:/Users/zlhe/Desktop/test.interface.json'),
      'json',
    );
    expect(value, 10);
  });

  test('Document selector match - platform paths #99938', () {
    final selector = LanguageFilter(
      pattern: glob.IRelativePattern(
        base: '/home/user/Desktop',
        pattern: '*.json',
      ),
    );
    final value = s(
      selector,
      VsUri.file('/home/user/Desktop/test.json'),
      'json',
    );
    expect(value, 10);
    // The JSON form of the same selector.
    expect(
      s(
        {
          'pattern': {'base': '/home/user/Desktop', 'pattern': '*.json'},
        },
        VsUri.file('/home/user/Desktop/test.json'),
        'json',
      ),
      10,
    );
  });

  test('NotebookType without notebook', () {
    final uri = VsUri.parse('file:///my/file.bat');
    expect(s({'language': 'bat', 'notebookType': 'xxx'}, uri, 'bat'), 0);
    expect(s({'language': 'bat', 'notebookType': '*'}, uri, 'bat'), 0);
  });

  test('selectLanguageIds', () {
    final result = <String>{};

    selectLanguageIds(sel('typescript')!, result);
    expect(result.toList(), ['typescript']);

    result.clear();
    selectLanguageIds(sel({'language': 'python', 'scheme': 'file'})!, result);
    expect(result.toList(), ['python']);

    result.clear();
    selectLanguageIds(sel({'scheme': 'file'})!, result);
    expect(result.toList(), isEmpty);

    result.clear();
    selectLanguageIds(
      sel([
        'javascript',
        {'language': 'css'},
        {'scheme': 'untitled'},
      ])!,
      result,
    );
    expect(result.toList()..sort(), ['css', 'javascript']);

    result.clear();
    selectLanguageIds(sel('*')!, result);
    expect(result.toList(), ['*']);
  });

  test('targetsNotebooks, exclusive, builtin', () {
    expect(targetsNotebooks(sel('python')!), isFalse);
    expect(targetsNotebooks(sel(['python', {'notebookType': 'jupyter'}])!), isTrue);
    expect(isExclusiveSelector(sel({'language': 'a', 'exclusive': true})!), isTrue);
    expect(
      isExclusiveSelector(
        sel([
          {'language': 'a', 'exclusive': true},
          'b',
        ])!,
      ),
      isFalse,
    );
    expect(
      isBuiltinSelector(
        sel([
          {'language': 'a', 'isBuiltin': true},
          'b',
        ])!,
      ),
      isTrue,
    );
  });
}
