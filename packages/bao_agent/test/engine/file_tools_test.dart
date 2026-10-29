import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// A ripgrep on this machine, if there is one (on `PATH`, or the one
/// BaoCode's extension host brings).

void main() {
  late Harness h;

  tearDown(() => h.dispose());

  group('Read', () {
    test('lines, offsets, limits, long lines, empty and short files', () async {
      final long = 'x' * 2500;
      h = await Harness.start(
        files: {
          'many.txt': [for (var i = 1; i <= 2100; i++) 'line $i'].join('\n'),
          'long.txt': '$long\n',
          'empty.txt': '',
          'crlf.txt': 'a\r\nb\r\n',
        },
      );
      String path(String name) => p.join(h.cwd, name);
      h.model.script.addAll([
        Reply.tools([
          ('Read', {'file_path': path('many.txt')}),
          ('Read', {'file_path': path('many.txt'), 'offset': 2099, 'limit': 5}),
          ('Read', {'file_path': path('long.txt')}),
          ('Read', {'file_path': path('empty.txt')}),
          ('Read', {'file_path': path('many.txt'), 'offset': 5000}),
          ('Read', {'file_path': path('crlf.txt')}),
          ('Read', {'file_path': 'many.txt', 'limit': 1}),
        ]),
        Reply.text('ok'),
      ]);
      await h.turn('read');
      final [whole, tail, longLine, empty, beyond, crlf, relative] = [
        for (final r in h.toolResults) '${r['content']}',
      ];
      expect(whole, contains('2000\tline 2000'));
      expect(whole, isNot(contains('line 2001')));
      expect(whole, contains('The file has 2100 lines'));
      expect(tail.split('\n').map((l) => l.trimLeft()), [
        '2099\tline 2099',
        '2100\tline 2100',
      ]);
      expect(longLine, contains('[line truncated]'));
      expect(empty, contains('but empty'));
      expect(beyond, contains('nothing starts at line'));
      // A final line break leaves an empty line after it, as the CLI shows.
      expect(crlf.split('\n').map((l) => l.trimLeft()), [
        '1\ta',
        '2\tb',
        '3\t',
      ]);
      expect(relative.trimLeft(), '1\tline 1');
      final file = (h.toolResults[1]['tool_use_result'] as Map)['file'] as Map;
      expect(
        file,
        allOf(
          containsPair('startLine', 2099),
          containsPair('numLines', 2),
          containsPair('totalLines', 2100),
        ),
      );
    });

    test('images, binaries, folders, files not there, too big', () async {
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );
      h = await Harness.start(files: {'readme.md': 'x', 'sub/a.txt': 'a'});
      File(p.join(h.cwd, 'dot.png')).writeAsBytesSync(png);
      File(p.join(h.cwd, 'blob.bin')).writeAsBytesSync([0, 1, 2, 0, 255, 0]);
      File(p.join(h.cwd, 'huge.txt')).writeAsStringSync('y' * (300 * 1024));
      String path(String name) => p.join(h.cwd, name);
      h.model.script.addAll([
        Reply.tools([
          ('Read', {'file_path': path('dot.png')}),
          ('Read', {'file_path': path('blob.bin')}),
          ('Read', {'file_path': path('sub')}),
          ('Read', {'file_path': path('README.txt')}),
          ('Read', {'file_path': path('huge.txt')}),
          ('Read', {'file_path': path('readme.md'), 'limit': 0}),
        ]),
        Reply.text('ok'),
      ]);
      await h.turn('read');
      final [image, binary, folder, missing, huge, invalid] = h.toolResults;
      expect(jsonEncode(image['content']), contains('"type":"image"'));
      expect((image['tool_use_result'] as Map)['type'], 'image');
      expect(
        jsonEncode(h.model.turns.last.body['messages']),
        contains('image/png'),
      );
      expect('${binary['content']}', contains('binary'));
      expect('${folder['content']}', contains('EISDIR'));
      expect('${missing['content']}', contains('Perhaps'));
      expect('${huge['content']}', contains('can be read at once'));
      expect(invalid['is_error'], isTrue);
    });

    test(
      "a file's nested CLAUDE.md and the rules for its path come with it",
      () async {
        h = await Harness.start(
          files: {
            'lib/CLAUDE.md': 'Library notes.',
            'lib/a.dart': 'void main() {}',
            '.claude/rules/dart.md':
                '---\npaths: ["lib/**/*.dart"]\n---\nUse four spaces.',
          },
        );
        h.model.script.addAll([
          Reply.tool('Read', {'file_path': p.join(h.cwd, 'lib', 'a.dart')}),
          Reply.text('ok'),
        ]);
        await h.turn('read');
        final content = '${h.toolResults.single['content']}';
        expect(
          content,
          allOf(contains('Library notes.'), contains('Use four spaces.')),
        );
        expect(
          jsonEncode(h.model.turns.first.body['messages']),
          isNot(contains('Use four spaces.')),
        );
      },
    );
  });

  group('Edit and Write', () {
    test(
      'replace_all, matches not unique, nothing to change, curly quotes',
      () async {
        h = await Harness.start(files: {'a.txt': 'foo foo\nsay “hi”\n'});
        final path = p.join(h.cwd, 'a.txt');
        h.model.script.addAll([
          Reply.tool('Read', {'file_path': path}),
          Reply.tools([
            (
              'Edit',
              {'file_path': path, 'old_string': 'foo', 'new_string': 'bar'},
            ),
            ('Edit', {'file_path': path, 'old_string': 'x', 'new_string': 'x'}),
            (
              'Edit',
              {'file_path': path, 'old_string': 'missing', 'new_string': 'y'},
            ),
          ]),
          Reply.tool('Edit', {
            'file_path': path,
            'old_string': 'foo',
            'new_string': 'bar',
            'replace_all': true,
          }),
          Reply.tool('Edit', {
            'file_path': path,
            'old_string': 'say "hi"',
            'new_string': 'say "bye"',
          }),
          Reply.text('ok'),
        ]);
        await h.turn('edit');
        final results = h.toolResults.map((r) => '${r['content']}').toList();
        expect(results[1], contains('in the file 2 times'));
        expect(results[2], contains('Nothing would change'));
        expect(results[3], contains('old_string is not in the file'));
        expect(h.file('a.txt'), 'bar bar\nsay “bye”\n');
      },
    );

    test('Write keeps line endings; Edit creates with an empty old_string; notebooks refused', () async {
      h = await Harness.start(
        files: {'win.txt': 'a\r\nb\r\n', 'n.ipynb': '{"cells": []}'},
      );
      final win = p.join(h.cwd, 'win.txt');
      h.model.script.addAll([
        Reply.tools([
          ('Read', {'file_path': win}),
          ('Read', {'file_path': p.join(h.cwd, 'n.ipynb')}),
        ]),
        Reply.tools([
          ('Edit', {'file_path': win, 'old_string': 'b', 'new_string': 'c'}),
          (
            'Edit',
            {
              'file_path': p.join(h.cwd, 'made', 'new.txt'),
              'old_string': '',
              'new_string': 'fresh',
            },
          ),
          (
            'Edit',
            {
              'file_path': p.join(h.cwd, 'n.ipynb'),
              'old_string': 'cells',
              'new_string': 'x',
            },
          ),
          (
            'Write',
            {
              'file_path': p.join(h.cwd, 'nested', 'deep', 'w.txt'),
              'content': 'deep',
            },
          ),
        ]),
        Reply.text('ok'),
      ]);
      await h.turn('edit');
      expect(h.file('win.txt'), 'a\r\nc\r\n');
      expect(h.file('made/new.txt'), 'fresh');
      expect('${h.toolResults[4]['content']}', contains('NotebookEdit'));
      expect(h.file('nested/deep/w.txt'), 'deep');
    });
  });
}
