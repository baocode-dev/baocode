import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/search/text_search.dart';
import 'package:path/path.dart' as p;

void main() {
  group('globs', () {
    bool matches(String patterns, String path) =>
        ideSearchPathGlobs(patterns).any((glob) => glob.hasMatch(path));

    test('match anywhere, or under the root with ./', () {
      expect(matches('*.ts', 'a.ts'), isTrue);
      expect(matches('*.ts', 'src/deep/a.ts'), isTrue);
      expect(matches('*.ts', 'a.tsx'), isFalse);
      expect(matches('src', 'src/a.ts'), isTrue);
      expect(matches('src', 'lib/src/a.ts'), isTrue);
      expect(matches('./src', 'lib/src/a.ts'), isFalse);
      expect(matches('./src', 'src/deep/a.ts'), isTrue);
      expect(matches('src/**/include', 'src/a/b/include/x.ts'), isTrue);
      expect(matches('src/**/include', 'src/include/x.ts'), isTrue);
    });

    test('braces, sets and several patterns', () {
      expect(matches('*.{ts,js}', 'a.js'), isTrue);
      expect(matches('*.{ts,js}', 'a.css'), isFalse);
      expect(matches('file[0-9].txt', 'file3.txt'), isTrue);
      expect(matches('file[!0-9].txt', 'file3.txt'), isFalse);
      expect(matches('*.md, lib', 'lib/a.dart'), isTrue);
      expect(matches('*.md, lib', 'README.md'), isTrue);
      expect(matches('*.md, lib', 'test/a.dart'), isFalse);
      expect(matches('a?.txt', 'ab.txt'), isTrue);
      expect(matches('a?.txt', 'a/.txt'), isFalse);
    });

    test('default excludes', () {
      final query = const IdeTextQuery('x');
      final accept = query.pathFilter();
      expect(accept('node_modules/a/index.js'), isFalse);
      expect(accept('pkg/node_modules/a.js'), isFalse);
      expect(accept('.git/config'), isFalse);
      expect(accept('lib/a.dart'), isTrue);
      final all = const IdeTextQuery(
        'x',
        useExcludesAndIgnoreFiles: false,
      ).pathFilter();
      expect(all('node_modules/a/index.js'), isTrue);
    });
  });

  group('patterns', () {
    test('whole words, case and regular expressions', () {
      final word = ideCreateRegExp('foo', isRegExp: false, wholeWord: true);
      expect(word.hasMatch('a foo b'), isTrue);
      expect(word.hasMatch('food'), isFalse);
      expect(ideCreateRegExp('a.b', isRegExp: false).hasMatch('axb'), isFalse);
      expect(ideCreateRegExp('a.b', isRegExp: true).hasMatch('axb'), isTrue);
      expect(
        ideCreateRegExp(
          'FOO',
          isRegExp: false,
          matchCase: true,
        ).hasMatch('foo'),
        isFalse,
      );
      expect(() => ideCreateRegExp('(', isRegExp: true), throwsFormatException);
    });

    test('matches are per occurrence, per line, without CRs', () {
      final matches = ideMatchLines(
        'one two one\r\nthree\r\none',
        RegExp('one'),
      );
      expect(
        [for (final m in matches) (m.line, m.start, m.end)],
        [(0, 0, 3), (0, 8, 11), (2, 0, 3)],
      );
      expect(matches.first.text, 'one two one');
      expect(ideMatchLines('a\na', RegExp('a'), limit: 1), hasLength(1));
    });

    test('the preview cuts what comes before at a word', () {
      const line =
          '        final someVeryLongVariableName = anotherLongName + target;';
      final start = line.indexOf('target');
      final preview = ideMatchPreview(IdeTextMatch(0, start, start + 6, line));
      expect(preview.inside, 'target');
      expect(preview.after, ';');
      // The last word boundary leaving 26 or more characters.
      expect(preview.before, '…someVeryLongVariableName = anotherLongName + ');
      expect(ideLcut('  short', 26), 'short');
    });

    test('replace strings: groups, escapes and preserved case', () {
      final regExp = RegExp(r'(\w+)=(\w+)');
      const line = 'key=value';
      const match = IdeTextMatch(0, 0, 9, line);
      expect(
        ideReplaceString(match, r'$2=$1\n$&', regExp: regExp, isRegExp: true),
        'value=key\nkey=value',
      );
      expect(
        ideReplaceString(match, r'$1', regExp: regExp, isRegExp: false),
        r'$1',
      );
      expect(ideReplaceCasePreserved('FOO', 'bar'), 'BAR');
      expect(ideReplaceCasePreserved('foo', 'Bar'), 'bar');
      expect(ideReplaceCasePreserved('Foo', 'bar'), 'Bar');
    });
  });

  group('across lines', () {
    List<IdeTextMatch> find(String text, IdeTextQuery query) =>
        ideMatchLines(text, query.toRegExp(), multiline: query.isMultiline);

    test('text pasted with its line breaks matches across lines, LF or '
        'CRLF either way', () {
      const pasted = '  b();\r\n  return true;';
      final query = const IdeTextQuery(pasted);
      expect(query.isMultiline, isTrue);
      for (final text in [
        'a {\n  b();\n  return true;\n}',
        'a {\r\n  b();\r\n  return true;\r\n}',
      ]) {
        final match = find(text, query).single;
        expect(match.line, 1);
        expect(match.endLine, 2);
        expect(match.start, 0);
        expect(match.endColumn, '  return true;'.length);
        expect(match.matched.replaceAll('\r', ''), '  b();\n  return true;');
        // Its lines, the end's line break not.
        expect(match.text.endsWith('return true;'), isTrue);
        final preview = ideMatchPreview(match);
        expect(preview.inside, '  b();⏎  return true;');
        expect(preview.after, '');
      }
      // Within a line, as before.
      expect(const IdeTextQuery('b();').isMultiline, isFalse);
    });

    test('an expression with \\n matches across lines; one in a class '
        'or after \\r as it is', () {
      final query = const IdeTextQuery(r'one\n\s*two', isRegExp: true);
      expect(query.isMultiline, isTrue);
      final match = find('x one\r\n  two y', query).single;
      expect((match.line, match.start), (0, 2));
      expect((match.endLine, match.endColumn), (1, 5));
      expect(
        find('one\r\ntwo', const IdeTextQuery(r'one\r\ntwo', isRegExp: true)),
        hasLength(1),
      );
      expect(
        find('ab', const IdeTextQuery(r'a[^\n]', isRegExp: true)),
        hasLength(1),
      );
      expect(const IdeTextQuery(r'a\\n', isRegExp: true).isMultiline, isFalse);
    });

    test('ending on a line break: at the next line\'s start', () {
      final match = find('one\ntwo', const IdeTextQuery('one\n')).single;
      expect((match.endLine, match.endColumn), (1, 0));
    });

    test('replaced across lines', () {
      final query = const IdeTextQuery(r'(\w+)\n(\w+)', isRegExp: true);
      final regExp = query.toRegExp();
      final match = find('x\none\ntwo', query).first;
      expect(
        ideReplaceString(match, r'$2 $1', regExp: regExp, isRegExp: true),
        'one x',
      );
    });
  });

  group('engine', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('ide_search_');
      void write(String path, List<int> bytes) {
        final file = File(p.joinAll([root.path, ...path.split('/')]));
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
      }

      write('lib/a.dart', 'needle one\nno\nneedle two'.codeUnits);
      write('lib/b.txt', 'nothing'.codeUnits);
      write('node_modules/x/index.js', 'needle'.codeUnits);
      write('bin/data.bin', [110, 101, 101, 100, 108, 101, 0, 1]);
      write('ignored/c.dart', 'needle'.codeUnits);
      write('.gitignore', 'ignored/\n'.codeUnits);
    });
    tearDown(() => root.deleteSync(recursive: true));

    Future<(Map<String, int>, bool)> run(IdeTextQuery query) async {
      final files = <String, int>{};
      var limitHit = false;
      await for (final event in ideSearchText(root.path, query)) {
        switch (event) {
          case IdeFileMatches(:final path, :final matches):
            files[p.relative(path, from: root.path).replaceAll(r'\', '/')] =
                matches.length;
          case IdeTextSearchComplete():
            limitHit = event.limitHit;
        }
      }
      return (files, limitHit);
    }

    test('outside Git: skips binaries and the default excludes', () async {
      final (files, limitHit) = await run(const IdeTextQuery('needle'));
      expect(files, {'lib/a.dart': 2, 'ignored/c.dart': 1});
      expect(limitHit, isFalse);

      final (all, _) = await run(
        const IdeTextQuery('needle', useExcludesAndIgnoreFiles: false),
      );
      expect(all.keys, contains('node_modules/x/index.js'));
      expect(all.keys, isNot(contains('bin/data.bin')));
    });

    test('includes, excludes and the result limit', () async {
      final (included, _) = await run(
        const IdeTextQuery('needle', includes: './lib'),
      );
      expect(included, {'lib/a.dart': 2});
      final (excluded, _) = await run(
        const IdeTextQuery('needle', excludes: '*.dart'),
      );
      expect(excluded, isEmpty);
      final (limited, limitHit) = await run(
        const IdeTextQuery('needle', maxResults: 1),
      );
      expect(limited.values.single, 1);
      expect(limitHit, isTrue);
    });

    test('in a Git repository: respects .gitignore', () async {
      final init = Process.runSync('git', [
        'init',
        '-q',
      ], workingDirectory: root.path);
      if (init.exitCode != 0) return;
      final (files, _) = await run(const IdeTextQuery('needle'));
      expect(files, {'lib/a.dart': 2});
    });

    test('across lines', () async {
      final (files, _) = await run(const IdeTextQuery('one\nno'));
      expect(files, {'lib/a.dart': 1});
    });

    test('an invalid expression is an error', () async {
      await expectLater(
        ideSearchText(root.path, const IdeTextQuery('(', isRegExp: true)),
        emitsError(isA<FileSystemException>()),
      );
    });
  });
}
