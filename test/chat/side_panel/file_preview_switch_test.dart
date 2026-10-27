import 'package:baocode/base/shown_when_ready.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/file_preview.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_code_diff.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ide/workbench/fake_files.dart';

class _Files with ReadWriteOnlyFiles implements IdeFileService {
  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async => '';

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {}
}

/// A file's changes, each side read in a while (as `git show` takes).
FileOpenRequest _change(String path) {
  Future<String> later(String text) =>
      Future.delayed(const Duration(milliseconds: 40), () => text);
  final lines = [for (var i = 0; i < 400; i++) 'line $i of $path'];
  return FileOpenRequest(
    path,
    diff: true,
    readOnly: true,
    original: () => later(lines.join('\n')),
    modified: () =>
        later([...lines.take(300), 'changed', ...lines.skip(300)].join('\n')),
  );
}

/// The diffs drawn: those not hidden, by their file.
List<String> _seen(WidgetTester tester) => [
  for (final element in find.byType(IdeCodeDiff).evaluate())
    if (element.findAncestorWidgetOfExactType<Opacity>()?.opacity
        case null || 1.0)
      (element.widget as IdeCodeDiff).path,
];

void main() {
  testWidgets('another file\'s changes picked: the one before shows until '
      'they are read and compared, never nothing in between', (tester) async {
    final files = _Files();
    Widget preview(String path) => MaterialApp(
      home: Scaffold(
        body: ShownWhenReady(
          child: FilePreview(
            key: ValueKey(path),
            request: _change(path),
            files: files,
          ),
        ),
      ),
    );
    await tester.pumpWidget(preview('/p/a.txt'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_seen(tester), ['/p/a.txt']);

    await tester.pumpWidget(preview('/p/b.txt'));
    final frames = <List<String>>[];
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(_seen(tester));
    }
    // One of them each frame: a's, then b's, and b's from then on.
    expect(frames, everyElement(hasLength(1)));
    final first = frames.indexWhere((seen) => seen.single == '/p/b.txt');
    expect(first, greaterThan(0));
    expect(
      frames.skip(first).map((seen) => seen.single),
      everyElement('/p/b.txt'),
    );
  });
}
