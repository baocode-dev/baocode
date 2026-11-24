import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/src/tools/file_state.dart';
import 'package:bao_agent/src/tools/read_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
      'a read the same again, the file unchanged, is not repeated',
      () async {
        h = await Harness.start(files: {'a.txt': 'one\ntwo'});
        final path = p.join(h.cwd, 'a.txt');
        h.model.script.addAll([
          Reply.tool('Read', {'file_path': path}),
          Reply.tool('Read', {'file_path': path}),
          Reply.tool('Read', {'file_path': path, 'limit': 1}),
          Reply.text('ok'),
        ]);
        await h.turn('read');
        final [first, again, part] = h.toolResults;
        expect('${first['content']}', contains('1\tone'));
        expect('${again['content']}', ReadTool.unchanged);
        expect((again['tool_use_result'] as Map)['type'], 'file_unchanged');
        expect('${part['content']}', contains('1\tone'));
        // Changed on disk: given again.
        File(path).writeAsStringSync('three');
        File(path).setLastModifiedSync(DateTime(2030));
        h.model.script.addAll([
          Reply.tool('Read', {'file_path': path}),
          Reply.text('ok'),
        ]);
        await h.turn('again');
        expect('${h.toolResults.last['content']}', contains('1\tthree'));
      },
    );

    test('what was shown is forgotten once out of the conversation', () {
      final state = ReadFileState();
      state['/a'] = FileRecord(
        content: 'x',
        modified: DateTime(2020),
        shownBy: 'toolu_1',
      );
      expect(state.copy()['/a']!.shownBy, isNull);
      expect(state['/a']!.shownBy, 'toolu_1');
      state.forgetShown();
      expect(state['/a']!.shownBy, isNull);
      expect(state['/a']!.content, 'x');
    });

    test('images: typed by their bytes, large ones made smaller', () async {
      final wide = img.Image(width: 3000, height: 300)
        ..clear(img.ColorRgb8(200, 30, 30));
      h = await Harness.start();
      File(p.join(h.cwd, 'wide.png')).writeAsBytesSync(img.encodePng(wide));
      File(p.join(h.cwd, 'png.jpg'))
          .writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));
      h.model.script.addAll([
        Reply.tools([
          ('Read', {'file_path': p.join(h.cwd, 'wide.png')}),
          ('Read', {'file_path': p.join(h.cwd, 'png.jpg')}),
        ]),
        Reply.text('ok'),
      ]);
      await h.turn('look');
      final [large, misnamed] = h.toolResults;
      final blocks = large['content'] as List;
      final source = (blocks.first as Map)['source'] as Map;
      final shown = img.decodeImage(base64Decode('${source['data']}'))!;
      expect((shown.width, shown.height), (2000, 200));
      expect(
        (blocks.last as Map)['text'],
        '[Image: original 3000x300, displayed at 2000x200. Multiply '
        'coordinates by 1.50 to map to original image.]',
      );
      expect(
        ((misnamed['content'] as List).first as Map)['source'],
        containsPair('media_type', 'image/png'),
      );
    });

    test('PDFs: past ten pages only by pages, never whole then', () async {
      h = await Harness.start();
      File(p.join(h.cwd, 'long.pdf')).writeAsBytesSync(_pdf(12));
      File(p.join(h.cwd, 'packed.pdf'))
          .writeAsBytesSync(_pdf(30, packed: true));
      File(p.join(h.cwd, 'short.pdf')).writeAsBytesSync(_pdf(3));
      File(p.join(h.cwd, 'fake.pdf')).writeAsStringSync('not a pdf');
      String path(String name) => p.join(h.cwd, name);
      h.model.script.addAll([
        Reply.tools([
          ('Read', {'file_path': path('long.pdf')}),
          ('Read', {'file_path': path('packed.pdf')}),
          ('Read', {'file_path': path('short.pdf')}),
          ('Read', {'file_path': path('fake.pdf')}),
          ('Read', {'file_path': path('long.pdf'), 'pages': '1-25'}),
          ('Read', {'file_path': path('long.pdf'), 'pages': '2-3'}),
        ]),
        Reply.text('ok'),
      ]);
      await h.turn('read');
      final [long, packed, short, fake, tooMany, some] = h.toolResults;
      expect('${long['content']}', contains('This PDF has 12 pages'));
      expect('${packed['content']}', contains('This PDF has 30 pages'));
      expect(jsonEncode(short['content']), contains('"type":"document"'));
      expect('${fake['content']}', contains('missing %PDF- header'));
      expect('${tooMany['content']}', contains('at most 20'));
      expect(jsonEncode(some['content']), isNot(contains('"document"')));
      if (Process.runSync('which', ['pdftoppm']).exitCode != 0 &&
          Process.runSync('which', ['pdftotext']).exitCode != 0) {
        expect('${some['content']}', contains('pdftoppm is not installed'));
      }
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

/// A PDF of [pages] blank pages; its page tree in a compressed object
/// stream when [packed].
List<int> _pdf(int pages, {bool packed = false}) {
  final kids = [for (var i = 0; i < pages; i++) '${10 + i} 0 R'].join(' ');
  final tree = '<< /Type /Pages /Kids [$kids] /Count $pages >>';
  final out = StringBuffer(
    '%PDF-1.7\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n',
  );
  if (packed) {
    final body = zlib.encode(latin1.encode('2 0 $tree'));
    out.write(
      '3 0 obj << /Type /ObjStm /N 1 /First 4 /Filter /FlateDecode '
      '/Length ${body.length} >>\nstream\n${latin1.decode(body)}\nendstream\nendobj\n',
    );
  } else {
    out.write('2 0 obj $tree endobj\n');
  }
  for (var i = 0; i < pages; i++) {
    out.write('${10 + i} 0 obj << /Type /Page /Parent 2 0 R >> endobj\n');
  }
  out.write('trailer << /Root 1 0 R >>\n%%EOF\n');
  return latin1.encode(out.toString());
}
