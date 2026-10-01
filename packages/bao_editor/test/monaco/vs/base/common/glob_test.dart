// Port of VS Code src/vs/base/test/common/glob.test.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. Upstream runs the suite on the
// host platform; here it runs once per operating system through
// debugOperatingSystemOverride (platform-specific branches follow it).
// Upstream's `parse`/`match` of an expression are `parseExpression` and
// `matchExpression`; `glob.parse(expr)(path, undefined, hasSibling)` becomes
// `parseExpression(expr)(path, null, hasSibling)`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart' hide isLinux, isWindows;
import 'package:bao_editor/monaco/vs/base/common/glob.dart' as glob;
import 'package:bao_editor/monaco/vs/base/common/path.dart' as paths;
import 'package:bao_editor/monaco/vs/base/common/platform.dart';
import 'package:bao_editor/monaco/vs/base/common/uri.dart';

String _describe(Object pattern) => pattern is glob.IRelativePattern
    ? jsonEncode({'base': pattern.base, 'pattern': pattern.pattern})
    : jsonEncode(pattern);

String nativeSep(String slashPath) => slashPath.replaceAll('/', paths.sep);

void assertGlobMatch(Object pattern, String input, [bool? ignoreCase]) {
  final options = glob.IGlobOptions(ignoreCase: ignoreCase);
  expect(
    glob.match(pattern, input, options),
    isTrue,
    reason: '${_describe(pattern)} should match $input',
  );
  expect(
    glob.match(pattern, nativeSep(input), options),
    isTrue,
    reason: '${_describe(pattern)} should match ${nativeSep(input)}',
  );
}

void assertNoGlobMatch(Object pattern, String input, [bool? ignoreCase]) {
  final options = glob.IGlobOptions(ignoreCase: ignoreCase);
  expect(
    glob.match(pattern, input, options),
    isFalse,
    reason: '${_describe(pattern)} should not match $input',
  );
  expect(
    glob.match(pattern, nativeSep(input), options),
    isFalse,
    reason: '${_describe(pattern)} should not match ${nativeSep(input)}',
  );
}

void testOptimizationForBasenames(
  Object pattern,
  List<String> basenameTerms,
  List<(String, Object?)> matches, [
  List<glob.SiblingPredicate?> siblingsFns = const [],
]) {
  const options = glob.IGlobOptions(trimForExclusions: true);
  if (pattern is String) {
    final parsed = glob.parse(pattern, options);
    expect(glob.getBasenameTerms(parsed), basenameTerms);
    for (final (text, result) in matches) {
      expect(parsed(text, null), result);
    }
  } else {
    final parsed = glob.parseExpression(pattern as glob.IExpression, options);
    expect(glob.getBasenameTerms(parsed), basenameTerms);
    for (final (i, (text, result)) in matches.indexed) {
      expect(
        parsed(text, null, i < siblingsFns.length ? siblingsFns[i] : null),
        result,
      );
    }
  }
}

void testOptimizationForPaths(
  Object pattern,
  List<String> pathTerms,
  List<(String, Object?)> matches, [
  List<glob.SiblingPredicate?> siblingsFns = const [],
]) {
  const options = glob.IGlobOptions(trimForExclusions: true);
  if (pattern is String) {
    final parsed = glob.parse(pattern, options);
    expect(glob.getPathTerms(parsed), pathTerms);
    for (final (text, result) in matches) {
      expect(parsed(text, null), result);
    }
  } else {
    final parsed = glob.parseExpression(pattern as glob.IExpression, options);
    expect(glob.getPathTerms(parsed), pathTerms);
    for (final (i, (text, result)) in matches.indexed) {
      expect(
        parsed(text, null, i < siblingsFns.length ? siblingsFns[i] : null),
        result,
      );
    }
  }
}

void main() {
  for (final os in OperatingSystem.values) {
    group('Glob (${os.name})', () {
      setUp(() => debugOperatingSystemOverride = os);
      tearDown(() => debugOperatingSystemOverride = null);
      _suite();
    });
  }
}

void _suite() {
  test('simple', () {
    var p = 'node_modules';

    assertGlobMatch(p, 'node_modules');
    assertNoGlobMatch(p, 'node_module');
    assertNoGlobMatch(p, '/node_modules');
    assertNoGlobMatch(p, 'test/node_modules');

    p = 'test.txt';
    assertGlobMatch(p, 'test.txt');
    assertNoGlobMatch(p, 'test?txt');
    assertNoGlobMatch(p, '/text.txt');
    assertNoGlobMatch(p, 'test/test.txt');

    p = 'test(.txt';
    assertGlobMatch(p, 'test(.txt');
    assertNoGlobMatch(p, 'test?txt');

    p = 'qunit';

    assertGlobMatch(p, 'qunit');
    assertNoGlobMatch(p, 'qunit.css');
    assertNoGlobMatch(p, 'test/qunit');

    // Absolute

    p = '/DNXConsoleApp/**/*.cs';
    assertGlobMatch(p, '/DNXConsoleApp/Program.cs');
    assertGlobMatch(p, '/DNXConsoleApp/foo/Program.cs');

    p = 'C:/DNXConsoleApp/**/*.cs';
    assertGlobMatch(p, 'C:\\DNXConsoleApp\\Program.cs');
    assertGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\Program.cs');

    p = '*';
    assertGlobMatch(p, '');
  });

  test('dot hidden', () {
    var p = '.*';

    assertGlobMatch(p, '.git');
    assertGlobMatch(p, '.hidden.txt');
    assertNoGlobMatch(p, 'git');
    assertNoGlobMatch(p, 'hidden.txt');
    assertNoGlobMatch(p, 'path/.git');
    assertNoGlobMatch(p, 'path/.hidden.txt');

    p = '**/.*';
    assertGlobMatch(p, '.git');
    assertGlobMatch(p, '/.git');
    assertGlobMatch(p, '.hidden.txt');
    assertNoGlobMatch(p, 'git');
    assertNoGlobMatch(p, 'hidden.txt');
    assertGlobMatch(p, 'path/.git');
    assertGlobMatch(p, 'path/.hidden.txt');
    assertGlobMatch(p, '/path/.git');
    assertGlobMatch(p, '/path/.hidden.txt');
    assertNoGlobMatch(p, 'path/git');
    assertNoGlobMatch(p, 'pat.h/hidden.txt');

    p = '._*';

    assertGlobMatch(p, '._git');
    assertGlobMatch(p, '._hidden.txt');
    assertNoGlobMatch(p, 'git');
    assertNoGlobMatch(p, 'hidden.txt');
    assertNoGlobMatch(p, 'path/._git');
    assertNoGlobMatch(p, 'path/._hidden.txt');

    p = '**/._*';
    assertGlobMatch(p, '._git');
    assertGlobMatch(p, '._hidden.txt');
    assertNoGlobMatch(p, 'git');
    assertNoGlobMatch(p, 'hidden._txt');
    assertGlobMatch(p, 'path/._git');
    assertGlobMatch(p, 'path/._hidden.txt');
    assertGlobMatch(p, '/path/._git');
    assertGlobMatch(p, '/path/._hidden.txt');
    assertNoGlobMatch(p, 'path/git');
    assertNoGlobMatch(p, 'pat.h/hidden._txt');
  });

  test('file pattern', () {
    var p = '*.js';

    assertGlobMatch(p, 'foo.js');
    assertNoGlobMatch(p, 'folder/foo.js');
    assertNoGlobMatch(p, '/node_modules/foo.js');
    assertNoGlobMatch(p, 'foo.jss');
    assertNoGlobMatch(p, 'some.js/test');

    p = 'html.*';
    assertGlobMatch(p, 'html.js');
    assertGlobMatch(p, 'html.txt');
    assertNoGlobMatch(p, 'htm.txt');

    p = '*.*';
    assertGlobMatch(p, 'html.js');
    assertGlobMatch(p, 'html.txt');
    assertGlobMatch(p, 'htm.txt');
    assertNoGlobMatch(p, 'folder/foo.js');
    assertNoGlobMatch(p, '/node_modules/foo.js');

    p = 'node_modules/test/*.js';
    assertGlobMatch(p, 'node_modules/test/foo.js');
    assertNoGlobMatch(p, 'folder/foo.js');
    assertNoGlobMatch(p, '/node_module/test/foo.js');
    assertNoGlobMatch(p, 'foo.jss');
    assertNoGlobMatch(p, 'some.js/test');
  });

  test('star', () {
    var p = 'node*modules';

    assertGlobMatch(p, 'node_modules');
    assertGlobMatch(p, 'node_super_modules');
    assertNoGlobMatch(p, 'node_module');
    assertNoGlobMatch(p, '/node_modules');
    assertNoGlobMatch(p, 'test/node_modules');

    p = '*';
    assertGlobMatch(p, 'html.js');
    assertGlobMatch(p, 'html.txt');
    assertGlobMatch(p, 'htm.txt');
    assertNoGlobMatch(p, 'folder/foo.js');
    assertNoGlobMatch(p, '/node_modules/foo.js');
  });

  test('file / folder match', () {
    const p = '**/node_modules/**';

    assertGlobMatch(p, 'node_modules');
    assertGlobMatch(p, 'node_modules/');
    assertGlobMatch(p, 'a/node_modules');
    assertGlobMatch(p, 'a/node_modules/');
    assertGlobMatch(p, 'node_modules/foo');
    assertGlobMatch(p, 'foo/node_modules/foo/bar');

    assertGlobMatch(p, '/node_modules');
    assertGlobMatch(p, '/node_modules/');
    assertGlobMatch(p, '/a/node_modules');
    assertGlobMatch(p, '/a/node_modules/');
    assertGlobMatch(p, '/node_modules/foo');
    assertGlobMatch(p, '/foo/node_modules/foo/bar');
  });

  test('questionmark', () {
    var p = 'node?modules';

    assertGlobMatch(p, 'node_modules');
    assertNoGlobMatch(p, 'node_super_modules');
    assertNoGlobMatch(p, 'node_module');
    assertNoGlobMatch(p, '/node_modules');
    assertNoGlobMatch(p, 'test/node_modules');

    p = '?';
    assertGlobMatch(p, 'h');
    assertNoGlobMatch(p, 'html.txt');
    assertNoGlobMatch(p, 'htm.txt');
    assertNoGlobMatch(p, 'folder/foo.js');
    assertNoGlobMatch(p, '/node_modules/foo.js');
  });

  test('globstar', () {
    var p = '**/*.js';

    assertGlobMatch(p, 'foo.js');
    assertGlobMatch(p, '/foo.js');
    assertGlobMatch(p, 'folder/foo.js');
    assertGlobMatch(p, '/node_modules/foo.js');
    assertNoGlobMatch(p, 'foo.jss');
    assertNoGlobMatch(p, 'some.js/test');
    assertNoGlobMatch(p, '/some.js/test');
    assertNoGlobMatch(p, '\\some.js\\test');

    p = '**/project.json';

    assertGlobMatch(p, 'project.json');
    assertGlobMatch(p, '/project.json');
    assertGlobMatch(p, 'some/folder/project.json');
    assertGlobMatch(p, '/some/folder/project.json');
    assertNoGlobMatch(p, 'some/folder/file_project.json');
    assertNoGlobMatch(p, 'some/folder/fileproject.json');
    assertNoGlobMatch(p, 'some/rrproject.json');
    assertNoGlobMatch(p, 'some\\rrproject.json');

    p = 'test/**';
    assertGlobMatch(p, 'test');
    assertGlobMatch(p, 'test/foo');
    assertGlobMatch(p, 'test/foo/');
    assertGlobMatch(p, 'test/foo.js');
    assertGlobMatch(p, 'test/other/foo.js');
    assertNoGlobMatch(p, 'est/other/foo.js');

    p = '**';
    assertGlobMatch(p, '/');
    assertGlobMatch(p, 'foo.js');
    assertGlobMatch(p, 'folder/foo.js');
    assertGlobMatch(p, 'folder/foo/');
    assertGlobMatch(p, '/node_modules/foo.js');
    assertGlobMatch(p, 'foo.jss');
    assertGlobMatch(p, 'some.js/test');

    p = 'test/**/*.js';
    assertGlobMatch(p, 'test/foo.js');
    assertGlobMatch(p, 'test/other/foo.js');
    assertGlobMatch(p, 'test/other/more/foo.js');
    assertNoGlobMatch(p, 'test/foo.ts');
    assertNoGlobMatch(p, 'test/other/foo.ts');
    assertNoGlobMatch(p, 'test/other/more/foo.ts');

    p = '**/**/*.js';

    assertGlobMatch(p, 'foo.js');
    assertGlobMatch(p, '/foo.js');
    assertGlobMatch(p, 'folder/foo.js');
    assertGlobMatch(p, '/node_modules/foo.js');
    assertNoGlobMatch(p, 'foo.jss');
    assertNoGlobMatch(p, 'some.js/test');

    p = '**/node_modules/**/*.js';

    assertNoGlobMatch(p, 'foo.js');
    assertNoGlobMatch(p, 'folder/foo.js');
    assertGlobMatch(p, 'node_modules/foo.js');
    assertGlobMatch(p, '/node_modules/foo.js');
    assertGlobMatch(p, 'node_modules/some/folder/foo.js');
    assertGlobMatch(p, '/node_modules/some/folder/foo.js');
    assertNoGlobMatch(p, 'node_modules/some/folder/foo.ts');
    assertNoGlobMatch(p, 'foo.jss');
    assertNoGlobMatch(p, 'some.js/test');

    p = '{**/node_modules/**,**/.git/**,**/bower_components/**}';

    assertGlobMatch(p, 'node_modules');
    assertGlobMatch(p, '/node_modules');
    assertGlobMatch(p, '/node_modules/more');
    assertGlobMatch(p, 'some/test/node_modules');
    assertGlobMatch(p, 'some\\test\\node_modules');
    assertGlobMatch(p, '/some/test/node_modules');
    assertGlobMatch(p, '\\some\\test\\node_modules');
    assertGlobMatch(p, 'C:\\\\some\\test\\node_modules');
    assertGlobMatch(p, 'C:\\\\some\\test\\node_modules\\more');

    assertGlobMatch(p, 'bower_components');
    assertGlobMatch(p, 'bower_components/more');
    assertGlobMatch(p, '/bower_components');
    assertGlobMatch(p, 'some/test/bower_components');
    assertGlobMatch(p, 'some\\test\\bower_components');
    assertGlobMatch(p, '/some/test/bower_components');
    assertGlobMatch(p, '\\some\\test\\bower_components');
    assertGlobMatch(p, 'C:\\\\some\\test\\bower_components');
    assertGlobMatch(p, 'C:\\\\some\\test\\bower_components\\more');

    assertGlobMatch(p, '.git');
    assertGlobMatch(p, '/.git');
    assertGlobMatch(p, 'some/test/.git');
    assertGlobMatch(p, 'some\\test\\.git');
    assertGlobMatch(p, '/some/test/.git');
    assertGlobMatch(p, '\\some\\test\\.git');
    assertGlobMatch(p, 'C:\\\\some\\test\\.git');

    assertNoGlobMatch(p, 'tempting');
    assertNoGlobMatch(p, '/tempting');
    assertNoGlobMatch(p, 'some/test/tempting');
    assertNoGlobMatch(p, 'some\\test\\tempting');
    assertNoGlobMatch(p, '/some/test/tempting');
    assertNoGlobMatch(p, '\\some\\test\\tempting');
    assertNoGlobMatch(p, 'C:\\\\some\\test\\tempting');

    p = '{**/package.json,**/project.json}';
    assertGlobMatch(p, 'package.json');
    assertGlobMatch(p, '/package.json');
    assertNoGlobMatch(p, 'xpackage.json');
    assertNoGlobMatch(p, '/xpackage.json');
  });

  test('issue 41724', () {
    var p = 'some/**/*.js';

    assertGlobMatch(p, 'some/foo.js');
    assertGlobMatch(p, 'some/folder/foo.js');
    assertNoGlobMatch(p, 'something/foo.js');
    assertNoGlobMatch(p, 'something/folder/foo.js');

    p = 'some/**/*';

    assertGlobMatch(p, 'some/foo.js');
    assertGlobMatch(p, 'some/folder/foo.js');
    assertNoGlobMatch(p, 'something/foo.js');
    assertNoGlobMatch(p, 'something/folder/foo.js');
  });

  test('brace expansion', () {
    var p = '*.{html,js}';

    assertGlobMatch(p, 'foo.js');
    assertGlobMatch(p, 'foo.html');
    assertNoGlobMatch(p, 'folder/foo.js');
    assertNoGlobMatch(p, '/node_modules/foo.js');
    assertNoGlobMatch(p, 'foo.jss');
    assertNoGlobMatch(p, 'some.js/test');

    p = '*.{html}';

    assertGlobMatch(p, 'foo.html');
    assertNoGlobMatch(p, 'foo.js');
    assertNoGlobMatch(p, 'folder/foo.js');
    assertNoGlobMatch(p, '/node_modules/foo.js');
    assertNoGlobMatch(p, 'foo.jss');
    assertNoGlobMatch(p, 'some.js/test');

    p = '{node_modules,testing}';
    assertGlobMatch(p, 'node_modules');
    assertGlobMatch(p, 'testing');
    assertNoGlobMatch(p, 'node_module');
    assertNoGlobMatch(p, 'dtesting');

    p = '**/{foo,bar}';
    assertGlobMatch(p, 'foo');
    assertGlobMatch(p, 'bar');
    assertGlobMatch(p, 'test/foo');
    assertGlobMatch(p, 'test/bar');
    assertGlobMatch(p, 'other/more/foo');
    assertGlobMatch(p, 'other/more/bar');
    assertGlobMatch(p, '/foo');
    assertGlobMatch(p, '/bar');
    assertGlobMatch(p, '/test/foo');
    assertGlobMatch(p, '/test/bar');
    assertGlobMatch(p, '/other/more/foo');
    assertGlobMatch(p, '/other/more/bar');

    p = '{foo,bar}/**';
    assertGlobMatch(p, 'foo');
    assertGlobMatch(p, 'bar');
    assertGlobMatch(p, 'bar/');
    assertGlobMatch(p, 'foo/test');
    assertGlobMatch(p, 'bar/test');
    assertGlobMatch(p, 'bar/test/');
    assertGlobMatch(p, 'foo/other/more');
    assertGlobMatch(p, 'bar/other/more');
    assertGlobMatch(p, 'bar/other/more/');

    p = '{**/*.d.ts,**/*.js}';

    assertGlobMatch(p, 'foo.js');
    assertGlobMatch(p, 'testing/foo.js');
    assertGlobMatch(p, 'testing\\foo.js');
    assertGlobMatch(p, '/testing/foo.js');
    assertGlobMatch(p, '\\testing\\foo.js');
    assertGlobMatch(p, 'C:\\testing\\foo.js');

    assertGlobMatch(p, 'foo.d.ts');
    assertGlobMatch(p, 'testing/foo.d.ts');
    assertGlobMatch(p, 'testing\\foo.d.ts');
    assertGlobMatch(p, '/testing/foo.d.ts');
    assertGlobMatch(p, '\\testing\\foo.d.ts');
    assertGlobMatch(p, 'C:\\testing\\foo.d.ts');

    assertNoGlobMatch(p, 'foo.d');
    assertNoGlobMatch(p, 'testing/foo.d');
    assertNoGlobMatch(p, 'testing\\foo.d');
    assertNoGlobMatch(p, '/testing/foo.d');
    assertNoGlobMatch(p, '\\testing\\foo.d');
    assertNoGlobMatch(p, 'C:\\testing\\foo.d');

    p = '{**/*.d.ts,**/*.js,path/simple.jgs}';

    assertGlobMatch(p, 'foo.js');
    assertGlobMatch(p, 'testing/foo.js');
    assertGlobMatch(p, 'testing\\foo.js');
    assertGlobMatch(p, '/testing/foo.js');
    assertGlobMatch(p, 'path/simple.jgs');
    assertNoGlobMatch(p, '/path/simple.jgs');
    assertGlobMatch(p, '\\testing\\foo.js');
    assertGlobMatch(p, 'C:\\testing\\foo.js');

    p = '{**/*.d.ts,**/*.js,foo.[0-9]}';

    assertGlobMatch(p, 'foo.5');
    assertGlobMatch(p, 'foo.8');
    assertNoGlobMatch(p, 'bar.5');
    assertNoGlobMatch(p, 'foo.f');
    assertGlobMatch(p, 'foo.js');

    p = 'prefix/{**/*.d.ts,**/*.js,foo.[0-9]}';

    assertGlobMatch(p, 'prefix/foo.5');
    assertGlobMatch(p, 'prefix/foo.8');
    assertNoGlobMatch(p, 'prefix/bar.5');
    assertNoGlobMatch(p, 'prefix/foo.f');
    assertGlobMatch(p, 'prefix/foo.js');
  });

  test('expression support (single)', () {
    const siblings = ['test.html', 'test.txt', 'test.ts', 'test.js'];
    bool hasSibling(String name) => siblings.contains(name);

    // { "**/*.js": { "when": "$(basename).ts" } }
    glob.IExpression expression = {
      '**/*.js': const glob.SiblingClause(when: r'$(basename).ts'),
    };

    expect(
      glob.parseExpression(expression)('test.js', null, hasSibling),
      '**/*.js',
    );
    expect(
      glob.parseExpression(expression)('test.js', null, (_) => false),
      isNull,
    );
    expect(
      glob.parseExpression(expression)(
        'test.js',
        null,
        (name) => name == 'te.ts',
      ),
      isNull,
    );
    expect(glob.parseExpression(expression)('test.js', null), isNull);

    expression = {'**/*.js': const glob.SiblingClause(when: '')};

    expect(
      glob.parseExpression(expression)('test.js', null, hasSibling),
      isNull,
    );

    expression = {'**/*.js': <String, Object?>{}};

    expect(
      glob.parseExpression(expression)('test.js', null, hasSibling),
      '**/*.js',
    );

    expression = {};

    expect(
      glob.parseExpression(expression)('test.js', null, hasSibling),
      isNull,
    );
  });

  test('expression support (multiple)', () {
    const siblings = ['test.html', 'test.txt', 'test.ts', 'test.js'];
    bool hasSibling(String name) => siblings.contains(name);

    // { "**/*.js": { "when": "$(basename).ts" } }
    final glob.IExpression expression = {
      '**/*.js': const glob.SiblingClause(when: r'$(basename).ts'),
      '**/*.as': true,
      '**/*.foo': false,
      '**/*.bananas': {'bananas': true},
    };

    expect(
      glob.parseExpression(expression)('test.js', null, hasSibling),
      '**/*.js',
    );
    expect(
      glob.parseExpression(expression)('test.as', null, hasSibling),
      '**/*.as',
    );
    expect(
      glob.parseExpression(expression)('test.bananas', null, hasSibling),
      '**/*.bananas',
    );
    expect(
      glob.parseExpression(expression)('test.bananas', null),
      '**/*.bananas',
    );
    expect(
      glob.parseExpression(expression)('test.foo', null, hasSibling),
      isNull,
    );
  });

  test('brackets', () {
    var p = 'foo.[0-9]';

    assertGlobMatch(p, 'foo.5');
    assertGlobMatch(p, 'foo.8');
    assertNoGlobMatch(p, 'bar.5');
    assertNoGlobMatch(p, 'foo.f');

    p = 'foo.[^0-9]';

    assertNoGlobMatch(p, 'foo.5');
    assertNoGlobMatch(p, 'foo.8');
    assertNoGlobMatch(p, 'bar.5');
    assertGlobMatch(p, 'foo.f');

    p = 'foo.[!0-9]';

    assertNoGlobMatch(p, 'foo.5');
    assertNoGlobMatch(p, 'foo.8');
    assertNoGlobMatch(p, 'bar.5');
    assertGlobMatch(p, 'foo.f');

    p = 'foo.[0!^*?]';

    assertNoGlobMatch(p, 'foo.5');
    assertNoGlobMatch(p, 'foo.8');
    assertGlobMatch(p, 'foo.0');
    assertGlobMatch(p, 'foo.!');
    assertGlobMatch(p, 'foo.^');
    assertGlobMatch(p, 'foo.*');
    assertGlobMatch(p, 'foo.?');

    p = 'foo[/]bar';

    assertNoGlobMatch(p, 'foo/bar');

    p = 'foo.[[]';

    assertGlobMatch(p, 'foo.[');

    p = 'foo.[]]';

    assertGlobMatch(p, 'foo.]');

    p = 'foo.[][!]';

    assertGlobMatch(p, 'foo.]');
    assertGlobMatch(p, 'foo.[');
    assertGlobMatch(p, 'foo.!');

    p = 'foo.[]-]';

    assertGlobMatch(p, 'foo.]');
    assertGlobMatch(p, 'foo.-');
  });

  test('full path', () {
    assertGlobMatch('testing/this/foo.txt', 'testing/this/foo.txt');
  });

  test('ending path', () {
    assertGlobMatch(
      '**/testing/this/foo.txt',
      'some/path/testing/this/foo.txt',
    );
  });

  test('prefix agnostic', () {
    var p = '**/*.js';

    assertGlobMatch(p, 'foo.js');
    assertGlobMatch(p, '/foo.js');
    assertGlobMatch(p, '\\foo.js');
    assertGlobMatch(p, 'testing/foo.js');
    assertGlobMatch(p, 'testing\\foo.js');
    assertGlobMatch(p, '/testing/foo.js');
    assertGlobMatch(p, '\\testing\\foo.js');
    assertGlobMatch(p, 'C:\\testing\\foo.js');

    assertNoGlobMatch(p, 'foo.ts');
    assertNoGlobMatch(p, 'testing/foo.ts');
    assertNoGlobMatch(p, 'testing\\foo.ts');
    assertNoGlobMatch(p, '/testing/foo.ts');
    assertNoGlobMatch(p, '\\testing\\foo.ts');
    assertNoGlobMatch(p, 'C:\\testing\\foo.ts');

    assertNoGlobMatch(p, 'foo.js.txt');
    assertNoGlobMatch(p, 'testing/foo.js.txt');
    assertNoGlobMatch(p, 'testing\\foo.js.txt');
    assertNoGlobMatch(p, '/testing/foo.js.txt');
    assertNoGlobMatch(p, '\\testing\\foo.js.txt');
    assertNoGlobMatch(p, 'C:\\testing\\foo.js.txt');

    assertNoGlobMatch(p, 'testing.js/foo');
    assertNoGlobMatch(p, 'testing.js\\foo');
    assertNoGlobMatch(p, '/testing.js/foo');
    assertNoGlobMatch(p, '\\testing.js\\foo');
    assertNoGlobMatch(p, 'C:\\testing.js\\foo');

    p = '**/foo.js';

    assertGlobMatch(p, 'foo.js');
    assertGlobMatch(p, '/foo.js');
    assertGlobMatch(p, '\\foo.js');
    assertGlobMatch(p, 'testing/foo.js');
    assertGlobMatch(p, 'testing\\foo.js');
    assertGlobMatch(p, '/testing/foo.js');
    assertGlobMatch(p, '\\testing\\foo.js');
    assertGlobMatch(p, 'C:\\testing\\foo.js');
  });

  test('cached properly', () {
    const p = '**/*.js';

    for (var run = 0; run < 2; run++) {
      // The second run makes sure the expressions are properly reused.
      assertGlobMatch(p, 'foo.js');
      assertGlobMatch(p, 'testing/foo.js');
      assertGlobMatch(p, 'testing\\foo.js');
      assertGlobMatch(p, '/testing/foo.js');
      assertGlobMatch(p, '\\testing\\foo.js');
      assertGlobMatch(p, 'C:\\testing\\foo.js');

      assertNoGlobMatch(p, 'foo.ts');
      assertNoGlobMatch(p, 'testing/foo.ts');
      assertNoGlobMatch(p, 'testing\\foo.ts');
      assertNoGlobMatch(p, '/testing/foo.ts');
      assertNoGlobMatch(p, '\\testing\\foo.ts');
      assertNoGlobMatch(p, 'C:\\testing\\foo.ts');

      assertNoGlobMatch(p, 'foo.js.txt');
      assertNoGlobMatch(p, 'testing/foo.js.txt');
      assertNoGlobMatch(p, 'testing\\foo.js.txt');
      assertNoGlobMatch(p, '/testing/foo.js.txt');
      assertNoGlobMatch(p, '\\testing\\foo.js.txt');
      assertNoGlobMatch(p, 'C:\\testing\\foo.js.txt');

      assertNoGlobMatch(p, 'testing.js/foo');
      assertNoGlobMatch(p, 'testing.js\\foo');
      assertNoGlobMatch(p, '/testing.js/foo');
      assertNoGlobMatch(p, '\\testing.js\\foo');
      assertNoGlobMatch(p, 'C:\\testing.js\\foo');
    }
  });

  test('invalid glob', () {
    const p = '**/*(.js';

    assertNoGlobMatch(p, 'foo.js');
  });

  test('split glob aware', () {
    expect(glob.splitGlobAware('foo,bar', ','), ['foo', 'bar']);
    expect(glob.splitGlobAware('foo', ','), ['foo']);
    expect(glob.splitGlobAware('{foo,bar}', ','), ['{foo,bar}']);
    expect(glob.splitGlobAware('foo,bar,{foo,bar}', ','), [
      'foo',
      'bar',
      '{foo,bar}',
    ]);
    expect(glob.splitGlobAware('{foo,bar},foo,bar,{foo,bar}', ','), [
      '{foo,bar}',
      'foo',
      'bar',
      '{foo,bar}',
    ]);

    expect(glob.splitGlobAware('[foo,bar]', ','), ['[foo,bar]']);
    expect(glob.splitGlobAware('foo,bar,[foo,bar]', ','), [
      'foo',
      'bar',
      '[foo,bar]',
    ]);
    expect(glob.splitGlobAware('[foo,bar],foo,bar,[foo,bar]', ','), [
      '[foo,bar]',
      'foo',
      'bar',
      '[foo,bar]',
    ]);
  });

  test('expression with disabled glob', () {
    final expr = {'**/*.js': false};

    expect(glob.matchExpression(expr, 'foo.js'), isNull);
  });

  test('expression with two non-trivia globs', () {
    final expr = {'**/*.j?': true, '**/*.t?': true};

    expect(glob.matchExpression(expr, 'foo.js'), '**/*.j?');
    expect(glob.matchExpression(expr, 'foo.as'), isNull);
  });

  test('expression with non-trivia glob (issue 144458)', () {
    const pattern = '**/p*';

    expect(glob.match(pattern, 'foo/barp'), isFalse);
    expect(glob.match(pattern, 'foo/bar/ap'), isFalse);
    expect(glob.match(pattern, 'ap'), isFalse);

    expect(glob.match(pattern, 'foo/barp1'), isFalse);
    expect(glob.match(pattern, 'foo/bar/ap1'), isFalse);
    expect(glob.match(pattern, 'ap1'), isFalse);

    expect(glob.match(pattern, '/foo/barp'), isFalse);
    expect(glob.match(pattern, '/foo/bar/ap'), isFalse);
    expect(glob.match(pattern, '/ap'), isFalse);

    expect(glob.match(pattern, '/foo/barp1'), isFalse);
    expect(glob.match(pattern, '/foo/bar/ap1'), isFalse);
    expect(glob.match(pattern, '/ap1'), isFalse);

    expect(glob.match(pattern, 'foo/pbar'), isTrue);
    expect(glob.match(pattern, '/foo/pbar'), isTrue);
    expect(glob.match(pattern, 'foo/bar/pa'), isTrue);
    expect(glob.match(pattern, '/p'), isTrue);
  });

  test('expression with empty glob', () {
    final expr = {'': true};

    expect(glob.matchExpression(expr, 'foo.js'), isNull);
  });

  test('expression with other falsy value', () {
    final expr = <String, Object?>{'**/*.js': 0};

    expect(glob.matchExpression(expr, 'foo.js'), '**/*.js');
  });

  test('expression with two basename globs', () {
    final expr = {'**/bar': true, '**/baz': true};

    expect(glob.matchExpression(expr, 'bar'), '**/bar');
    expect(glob.matchExpression(expr, 'foo'), isNull);
    expect(glob.matchExpression(expr, 'foo/bar'), '**/bar');
    expect(glob.matchExpression(expr, 'foo\\bar'), '**/bar');
    expect(glob.matchExpression(expr, 'foo/foo'), isNull);
  });

  test('expression with two basename globs ignores case', () {
    final expr = {'**/BAR': true, '**/BAZ': true};
    const ignoreCase = glob.IGlobOptions(ignoreCase: true);

    expect(glob.matchExpression(expr, 'bar', ignoreCase), '**/BAR');
    expect(glob.matchExpression(expr, 'baz', ignoreCase), '**/BAZ');
    expect(glob.matchExpression(expr, 'src/bar', ignoreCase), '**/BAR');
    expect(glob.matchExpression(expr, 'bar'), isNull);
  });

  test('expression with cached basename globs ignores case', () {
    glob.parse('**/bar', const glob.IGlobOptions(ignoreCase: true));

    final expr = {'**/BAR': true, '**/BAZ': true};

    expect(
      glob.matchExpression(
        expr,
        'BaR',
        const glob.IGlobOptions(ignoreCase: true),
      ),
      '**/BAR',
    );
  });

  test('expression cache does not collide with string pattern cache', () {
    glob.parse('**/BAR', const glob.IGlobOptions(ignoreCase: true));

    final expr = {'**/bar': true, '**/baz': true};

    expect(
      glob.matchExpression(
        expr,
        'bar',
        const glob.IGlobOptions(ignoreCase: true),
      ),
      '**/bar',
    );
  });

  test('expression with two basename globs and a siblings expression', () {
    final expr = <String, Object?>{
      '**/bar': true,
      '**/baz': true,
      '**/*.js': const glob.SiblingClause(when: r'$(basename).ts'),
    };

    const siblings = ['foo.ts', 'foo.js', 'foo', 'bar'];
    bool hasSibling(String name) => siblings.contains(name);

    expect(glob.parseExpression(expr)('bar', null, hasSibling), '**/bar');
    expect(glob.parseExpression(expr)('foo', null, hasSibling), isNull);
    expect(glob.parseExpression(expr)('foo/bar', null, hasSibling), '**/bar');
    if (isWindows) {
      // backslash is a valid file name character on posix
      expect(
        glob.parseExpression(expr)('foo\\bar', null, hasSibling),
        '**/bar',
      );
    }
    expect(glob.parseExpression(expr)('foo/foo', null, hasSibling), isNull);
    expect(glob.parseExpression(expr)('foo.js', null, hasSibling), '**/*.js');
    expect(glob.parseExpression(expr)('bar.js', null, hasSibling), isNull);
  });

  test('expression with multipe basename globs', () {
    final expr = {'**/bar': true, '{**/baz,**/foo}': true};

    expect(glob.matchExpression(expr, 'bar'), '**/bar');
    expect(glob.matchExpression(expr, 'foo'), '{**/baz,**/foo}');
    expect(glob.matchExpression(expr, 'baz'), '{**/baz,**/foo}');
    expect(glob.matchExpression(expr, 'abc'), isNull);
  });

  test('falsy expression/pattern', () {
    expect(glob.match(null, 'foo'), isFalse);
    expect(glob.match('', 'foo'), isFalse);
    expect(glob.parse(null)('foo'), isFalse);
    expect(glob.parse('')('foo'), isFalse);
  });

  test('falsy path', () {
    expect(glob.parse('foo')(null), isFalse);
    expect(glob.parse('foo')(''), isFalse);
    expect(glob.parse('**/*.j?')(null), isFalse);
    expect(glob.parse('**/*.j?')(''), isFalse);
    expect(glob.parse('**/*.foo')(null), isFalse);
    expect(glob.parse('**/*.foo')(''), isFalse);
    expect(glob.parse('**/foo')(null), isFalse);
    expect(glob.parse('**/foo')(''), isFalse);
    expect(glob.parse('{**/baz,**/foo}')(null), isFalse);
    expect(glob.parse('{**/baz,**/foo}')(''), isFalse);
    expect(glob.parse('{**/*.baz,**/*.foo}')(null), isFalse);
    expect(glob.parse('{**/*.baz,**/*.foo}')(''), isFalse);
  });

  test('expression/pattern basename', () {
    expect(glob.parse('**/foo')('bar/baz', 'baz'), isFalse);
    expect(glob.parse('**/foo')('bar/foo', 'foo'), isTrue);

    expect(glob.parse('{**/baz,**/foo}')('baz/bar', 'bar'), isFalse);
    expect(glob.parse('{**/baz,**/foo}')('baz/foo', 'foo'), isTrue);

    final expr = {'**/*.js': const glob.SiblingClause(when: r'$(basename).ts')};
    const siblings = ['foo.ts', 'foo.js'];
    bool hasSibling(String name) => siblings.contains(name);

    expect(
      glob.parseExpression(expr)('bar/baz.js', 'baz.js', hasSibling),
      isNull,
    );
    expect(
      glob.parseExpression(expr)('bar/foo.js', 'foo.js', hasSibling),
      '**/*.js',
    );
  });

  test('expression/pattern basename terms', () {
    expect(glob.getBasenameTerms(glob.parse('**/*.foo')), <String>[]);
    expect(glob.getBasenameTerms(glob.parse('**/foo')), ['foo']);
    expect(glob.getBasenameTerms(glob.parse('**/foo/')), ['foo']);
    expect(glob.getBasenameTerms(glob.parse('{**/baz,**/foo}')), [
      'baz',
      'foo',
    ]);
    expect(glob.getBasenameTerms(glob.parse('{**/baz/,**/foo/}')), [
      'baz',
      'foo',
    ]);

    expect(
      glob.getBasenameTerms(
        glob.parseExpression({
          '**/foo': true,
          '{**/bar,**/baz}': true,
          '{**/bar2/,**/baz2/}': true,
          '**/bulb': false,
        }),
      ),
      ['foo', 'bar', 'baz', 'bar2', 'baz2'],
    );
    expect(
      glob.getBasenameTerms(
        glob.parseExpression({
          '**/foo': const glob.SiblingClause(when: r'$(basename).zip'),
          '**/bar': true,
        }),
      ),
      ['bar'],
    );
  });

  test('expression/pattern optimization for basenames', () {
    expect(glob.getBasenameTerms(glob.parse('**/foo/**')), <String>[]);
    expect(
      glob.getBasenameTerms(
        glob.parse(
          '**/foo/**',
          const glob.IGlobOptions(trimForExclusions: true),
        ),
      ),
      ['foo'],
    );

    testOptimizationForBasenames('**/*.foo/**', [], [
      ('baz/bar.foo/bar/baz', true),
    ]);
    testOptimizationForBasenames(
      '**/foo/**',
      ['foo'],
      [('bar/foo', true), ('bar/foo/baz', false)],
    );
    testOptimizationForBasenames(
      '{**/baz/**,**/foo/**}',
      ['baz', 'foo'],
      [('bar/baz', true), ('bar/foo', true)],
    );

    testOptimizationForBasenames(
      <String, Object?>{
        '**/foo/**': true,
        '{**/bar/**,**/baz/**}': true,
        '**/bulb/**': false,
      },
      ['foo', 'bar', 'baz'],
      [
        ('bar/foo', '**/foo/**'),
        ('foo/bar', '{**/bar/**,**/baz/**}'),
        ('bar/nope', null),
      ],
    );

    const siblings = ['baz', 'baz.zip', 'nope'];
    bool hasSibling(String name) => siblings.contains(name);
    testOptimizationForBasenames(
      <String, Object?>{
        '**/foo/**': const glob.SiblingClause(when: r'$(basename).zip'),
        '**/bar/**': true,
      },
      ['bar'],
      [
        ('bar/foo', null),
        ('bar/foo/baz', null),
        ('bar/foo/nope', null),
        ('foo/bar', '**/bar/**'),
      ],
      [null, hasSibling, hasSibling],
    );
  });

  test('trailing slash', () {
    // Testing existing (more or less intuitive) behavior
    expect(glob.parse('**/foo/')('bar/baz', 'baz'), isFalse);
    expect(glob.parse('**/foo/')('bar/foo', 'foo'), isTrue);
    expect(glob.parse('**/*.foo/')('bar/file.baz', 'file.baz'), isFalse);
    expect(glob.parse('**/*.foo/')('bar/file.foo', 'file.foo'), isTrue);
    expect(glob.parse('{**/foo/,**/abc/}')('bar/baz', 'baz'), isFalse);
    expect(glob.parse('{**/foo/,**/abc/}')('bar/foo', 'foo'), isTrue);
    expect(glob.parse('{**/foo/,**/abc/}')('bar/abc', 'abc'), isTrue);
    const trim = glob.IGlobOptions(trimForExclusions: true);
    expect(glob.parse('{**/foo/,**/abc/}', trim)('bar/baz', 'baz'), isFalse);
    expect(glob.parse('{**/foo/,**/abc/}', trim)('bar/foo', 'foo'), isTrue);
    expect(glob.parse('{**/foo/,**/abc/}', trim)('bar/abc', 'abc'), isTrue);
  });

  test('expression/pattern path', () {
    const trim = glob.IGlobOptions(trimForExclusions: true);
    expect(glob.parse('**/foo/bar')(nativeSep('foo/baz'), 'baz'), isFalse);
    expect(glob.parse('**/foo/bar')(nativeSep('foo/bar'), 'bar'), isTrue);
    expect(glob.parse('**/foo/bar')(nativeSep('bar/foo/bar'), 'bar'), isTrue);
    expect(
      glob.parse('**/foo/bar/**')(nativeSep('bar/foo/bar'), 'bar'),
      isTrue,
    );
    expect(
      glob.parse('**/foo/bar/**')(nativeSep('bar/foo/bar/baz'), 'baz'),
      isTrue,
    );
    expect(
      glob.parse('**/foo/bar/**', trim)(nativeSep('bar/foo/bar'), 'bar'),
      isTrue,
    );
    expect(
      glob.parse('**/foo/bar/**', trim)(nativeSep('bar/foo/bar/baz'), 'baz'),
      isFalse,
    );

    expect(glob.parse('foo/bar')(nativeSep('foo/baz'), 'baz'), isFalse);
    expect(glob.parse('foo/bar')(nativeSep('foo/bar'), 'bar'), isTrue);
    expect(
      glob.parse('foo/bar/baz')(nativeSep('foo/bar/baz'), 'baz'),
      isTrue,
    ); // #15424
    expect(glob.parse('foo/bar')(nativeSep('bar/foo/bar'), 'bar'), isFalse);
    expect(glob.parse('foo/bar/**')(nativeSep('foo/bar/baz'), 'baz'), isTrue);
    expect(glob.parse('foo/bar/**', trim)(nativeSep('foo/bar'), 'bar'), isTrue);
    expect(
      glob.parse('foo/bar/**', trim)(nativeSep('foo/bar/baz'), 'baz'),
      isFalse,
    );
  });

  test('expression/pattern paths', () {
    expect(glob.getPathTerms(glob.parse('**/*.foo')), <String>[]);
    expect(glob.getPathTerms(glob.parse('**/foo')), <String>[]);
    expect(glob.getPathTerms(glob.parse('**/foo/bar')), ['*/foo/bar']);
    expect(glob.getPathTerms(glob.parse('**/foo/bar/')), ['*/foo/bar']);
    // Not supported
    // expect(glob.getPathTerms(glob.parse('{**/baz/bar,**/foo/bar,**/bar}')), ['*/baz/bar', '*/foo/bar']);
    // expect(glob.getPathTerms(glob.parse('{**/baz/bar/,**/foo/bar/,**/bar/}')), ['*/baz/bar', '*/foo/bar']);

    final parsed = glob.parseExpression({
      '**/foo/bar': true,
      '**/foo2/bar2': true,
      // Not supported
      // '{**/bar/foo,**/baz/foo}': true,
      // '{**/bar2/foo/,**/baz2/foo/}': true,
      '**/bulb': true,
      '**/bulb2': true,
      '**/bulb/foo': false,
    });
    expect(glob.getPathTerms(parsed), ['*/foo/bar', '*/foo2/bar2']);
    expect(glob.getBasenameTerms(parsed), ['bulb', 'bulb2']);
    expect(
      glob.getPathTerms(
        glob.parseExpression({
          '**/foo/bar': const glob.SiblingClause(when: r'$(basename).zip'),
          '**/bar/foo': true,
          '**/bar2/foo2': true,
        }),
      ),
      ['*/bar/foo', '*/bar2/foo2'],
    );
  });

  test('expression/pattern optimization for paths', () {
    expect(glob.getPathTerms(glob.parse('**/foo/bar/**')), <String>[]);
    expect(
      glob.getPathTerms(
        glob.parse(
          '**/foo/bar/**',
          const glob.IGlobOptions(trimForExclusions: true),
        ),
      ),
      ['*/foo/bar'],
    );

    testOptimizationForPaths('**/*.foo/bar/**', [], [
      (nativeSep('baz/bar.foo/bar/baz'), true),
    ]);
    testOptimizationForPaths(
      '**/foo/bar/**',
      ['*/foo/bar'],
      [(nativeSep('bar/foo/bar'), true), (nativeSep('bar/foo/bar/baz'), false)],
    );
    // Not supported
    // testOptimizationForPaths('{**/baz/bar/**,**/foo/bar/**}', ['*/baz/bar', '*/foo/bar'], [[nativeSep('bar/baz/bar'), true], [nativeSep('bar/foo/bar'), true]]);

    testOptimizationForPaths(
      <String, Object?>{
        '**/foo/bar/**': true,
        // Not supported
        // '{**/bar/bar/**,**/baz/bar/**}': true,
        '**/bulb/bar/**': false,
      },
      ['*/foo/bar'],
      [
        (nativeSep('bar/foo/bar'), '**/foo/bar/**'),
        // Not supported
        // [nativeSep('foo/bar/bar'), '{**/bar/bar/**,**/baz/bar/**}'],
        (nativeSep('/foo/bar/nope'), null),
      ],
    );

    const siblings = ['baz', 'baz.zip', 'nope'];
    bool hasSibling(String name) => siblings.contains(name);
    testOptimizationForPaths(
      <String, Object?>{
        '**/foo/123/**': const glob.SiblingClause(when: r'$(basename).zip'),
        '**/bar/123/**': true,
      },
      ['*/bar/123'],
      [
        (nativeSep('bar/foo/123'), null),
        (nativeSep('bar/foo/123/baz'), null),
        (nativeSep('bar/foo/123/nope'), null),
        (nativeSep('foo/bar/123'), '**/bar/123/**'),
      ],
      [null, hasSibling, hasSibling],
    );
  });

  test('relative pattern - glob star', () {
    if (isWindows) {
      const p = glob.IRelativePattern(
        base: 'C:\\DNXConsoleApp\\foo',
        pattern: '**/*.cs',
      );
      assertGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\Program.cs');
      assertGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\bar\\Program.cs');
      assertNoGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\Program.ts');
      assertNoGlobMatch(p, 'C:\\DNXConsoleApp\\Program.cs');
      assertNoGlobMatch(p, 'C:\\other\\DNXConsoleApp\\foo\\Program.ts');
    } else {
      const p = glob.IRelativePattern(
        base: '/DNXConsoleApp/foo',
        pattern: '**/*.cs',
      );
      assertGlobMatch(p, '/DNXConsoleApp/foo/Program.cs');
      assertGlobMatch(p, '/DNXConsoleApp/foo/bar/Program.cs');
      assertNoGlobMatch(p, '/DNXConsoleApp/foo/Program.ts');
      assertNoGlobMatch(p, '/DNXConsoleApp/Program.cs');
      assertNoGlobMatch(p, '/other/DNXConsoleApp/foo/Program.ts');
    }
  });

  test('relative pattern - single star', () {
    if (isWindows) {
      const p = glob.IRelativePattern(
        base: 'C:\\DNXConsoleApp\\foo',
        pattern: '*.cs',
      );
      assertGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\Program.cs');
      assertNoGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\bar\\Program.cs');
      assertNoGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\Program.ts');
      assertNoGlobMatch(p, 'C:\\DNXConsoleApp\\Program.cs');
      assertNoGlobMatch(p, 'C:\\other\\DNXConsoleApp\\foo\\Program.ts');
    } else {
      const p = glob.IRelativePattern(
        base: '/DNXConsoleApp/foo',
        pattern: '*.cs',
      );
      assertGlobMatch(p, '/DNXConsoleApp/foo/Program.cs');
      assertNoGlobMatch(p, '/DNXConsoleApp/foo/bar/Program.cs');
      assertNoGlobMatch(p, '/DNXConsoleApp/foo/Program.ts');
      assertNoGlobMatch(p, '/DNXConsoleApp/Program.cs');
      assertNoGlobMatch(p, '/other/DNXConsoleApp/foo/Program.ts');
    }
  });

  test('relative pattern - single star with path', () {
    if (isWindows) {
      const p = glob.IRelativePattern(
        base: 'C:\\DNXConsoleApp\\foo',
        pattern: 'something/*.cs',
      );
      assertGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\something\\Program.cs');
      assertNoGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\Program.cs');
    } else {
      const p = glob.IRelativePattern(
        base: '/DNXConsoleApp/foo',
        pattern: 'something/*.cs',
      );
      assertGlobMatch(p, '/DNXConsoleApp/foo/something/Program.cs');
      assertNoGlobMatch(p, '/DNXConsoleApp/foo/Program.cs');
    }
  });

  test('relative pattern - single star alone', () {
    if (isWindows) {
      const p = glob.IRelativePattern(
        base: 'C:\\DNXConsoleApp\\foo\\something\\Program.cs',
        pattern: '*',
      );
      assertGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\something\\Program.cs');
      assertNoGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\Program.cs');
    } else {
      const p = glob.IRelativePattern(
        base: '/DNXConsoleApp/foo/something/Program.cs',
        pattern: '*',
      );
      assertGlobMatch(p, '/DNXConsoleApp/foo/something/Program.cs');
      assertNoGlobMatch(p, '/DNXConsoleApp/foo/Program.cs');
    }
  });

  test('relative pattern - ignores case on macOS/Windows', () {
    if (isWindows) {
      const p = glob.IRelativePattern(
        base: 'C:\\DNXConsoleApp\\foo',
        pattern: 'something/*.cs',
      );
      assertGlobMatch(
        p,
        'C:\\DNXConsoleApp\\foo\\something\\Program.cs'.toLowerCase(),
      );
    } else if (isMacintosh) {
      const p = glob.IRelativePattern(
        base: '/DNXConsoleApp/foo',
        pattern: 'something/*.cs',
      );
      assertGlobMatch(
        p,
        '/DNXConsoleApp/foo/something/Program.cs'.toLowerCase(),
      );
    } else if (isLinux) {
      const p = glob.IRelativePattern(
        base: '/DNXConsoleApp/foo',
        pattern: 'something/*.cs',
      );
      assertNoGlobMatch(
        p,
        '/DNXConsoleApp/foo/something/Program.cs'.toLowerCase(),
      );
    }
  });

  test('relative pattern - trailing slash / backslash (#162498)', () {
    if (isWindows) {
      var p = const glob.IRelativePattern(base: 'C:\\', pattern: 'foo.cs');
      assertGlobMatch(p, 'C:\\foo.cs');

      p = const glob.IRelativePattern(base: 'C:\\bar\\', pattern: 'foo.cs');
      assertGlobMatch(p, 'C:\\bar\\foo.cs');
    } else {
      var p = const glob.IRelativePattern(base: '/', pattern: 'foo.cs');
      assertGlobMatch(p, '/foo.cs');

      p = const glob.IRelativePattern(base: '/bar/', pattern: 'foo.cs');
      assertGlobMatch(p, '/bar/foo.cs');
    }
  });

  test('pattern with "base" does not explode - #36081', () {
    expect(glob.matchExpression({'base': true}, 'base'), isNotNull);
  });

  test('relative pattern - #57475', () {
    if (isWindows) {
      const p = glob.IRelativePattern(
        base: 'C:\\DNXConsoleApp\\foo',
        pattern: 'styles/style.css',
      );
      assertGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\styles\\style.css');
      assertNoGlobMatch(p, 'C:\\DNXConsoleApp\\foo\\Program.cs');
    } else {
      const p = glob.IRelativePattern(
        base: '/DNXConsoleApp/foo',
        pattern: 'styles/style.css',
      );
      assertGlobMatch(p, '/DNXConsoleApp/foo/styles/style.css');
      assertNoGlobMatch(p, '/DNXConsoleApp/foo/Program.cs');
    }
  });

  test('URI match', () {
    const p = 'scheme:/**/*.md';
    assertGlobMatch(
      p,
      URI
          .file('super/duper/long/some/file.md')
          .withComponents(scheme: 'scheme')
          .toString(),
    );
  });

  test('expression fails when siblings use promises (https://github.com/microsoft/vscode/issues/146294)', () async {
    const siblings = ['test.html', 'test.txt', 'test.ts'];
    Future<bool> hasSibling(String name) =>
        Future.value(siblings.contains(name));

    // { "**/*.js": { "when": "$(basename).ts" } }
    final glob.IExpression expression = {
      '**/test.js': const glob.SiblingClause(when: r'$(basename).js'),
      '**/*.js': const glob.SiblingClause(when: r'$(basename).ts'),
    };

    final parsedExpression = glob.parseExpression(expression);

    expect(await parsedExpression('test.js', null, hasSibling), '**/*.js');
  });

  test('patternsEquals', () {
    expect(glob.patternsEquals(['a'], ['a']), isTrue);
    expect(glob.patternsEquals(['a'], ['b']), isFalse);

    expect(glob.patternsEquals(['a', 'b', 'c'], ['a', 'b', 'c']), isTrue);
    expect(glob.patternsEquals(['1', '2'], ['1', '3']), isFalse);

    expect(
      glob.patternsEquals(
        [const glob.IRelativePattern(base: 'a', pattern: '*'), 'b', 'c'],
        [const glob.IRelativePattern(base: 'a', pattern: '*'), 'b', 'c'],
      ),
      isTrue,
    );

    expect(glob.patternsEquals(null, null), isTrue);
    expect(glob.patternsEquals(null, ['b']), isFalse);
    expect(glob.patternsEquals(['a'], null), isFalse);
  });

  test('isEmptyPattern', () {
    expect(glob.isEmptyPattern(glob.parse('')), isTrue);
    expect(glob.isEmptyPattern(glob.parse(null)), isTrue);

    expect(glob.isEmptyPattern(glob.parseExpression({})), isTrue);
    expect(glob.isEmptyPattern(glob.parseExpression({'': true})), isTrue);
    expect(
      glob.isEmptyPattern(glob.parseExpression({'**/*.js': false})),
      isTrue,
    );
  });

  test('caseInsensitiveMatch', () {
    assertNoGlobMatch('PATH/FOO.js', 'path/foo.js');
    assertGlobMatch('PATH/FOO.js', 'path/foo.js', true);
    // T1
    assertNoGlobMatch('**/*.JS', 'bar/foo.js');
    assertGlobMatch('**/*.JS', 'bar/foo.js', true);
    // T2
    assertNoGlobMatch('**/package', 'bar/Package');
    assertGlobMatch('**/package', 'bar/Package', true);
    // T3
    assertNoGlobMatch('{**/*.JS,**/*.TS}', 'bar/foo.ts');
    assertNoGlobMatch('{**/*.JS,**/*.TS}', 'bar/foo.js');
    assertGlobMatch('{**/*.JS,**/*.TS}', 'bar/foo.ts', true);
    assertGlobMatch('{**/*.JS,**/*.TS}', 'bar/foo.js', true);
    assertNoGlobMatch('{**/BAR,**/BAZ}', 'bar');
    assertGlobMatch('{**/BAR,**/BAZ}', 'bar', true);
    // T4
    assertNoGlobMatch('**/FOO/Bar', 'bar/foo/bar');
    assertGlobMatch('**/FOO/Bar', 'bar/foo/bar', true);
    // T5
    assertNoGlobMatch('FOO/Bar', 'foo/bar');
    assertGlobMatch('FOO/Bar', 'foo/bar', true);
    // Other
    assertNoGlobMatch(
      'some/*/Random/*/Path.FILE',
      'some/very/random/unusual/path.file',
    );
    assertGlobMatch(
      'some/*/Random/*/Path.FILE',
      'some/very/random/unusual/path.file',
      true,
    );
  });

  // Dart-specific: the parse cache follows the operating system override,
  // since trivial path patterns capture the native separator.
  test('cache is per operating system', () {
    const p = '**/foo/bar';
    final previous = debugOperatingSystemOverride;
    debugOperatingSystemOverride = OperatingSystem.linux;
    expect(glob.match(p, 'x\\foo\\bar'), isFalse);
    debugOperatingSystemOverride = OperatingSystem.windows;
    expect(glob.match(p, 'x\\foo\\bar'), isTrue);
    debugOperatingSystemOverride = previous;
  });
}
