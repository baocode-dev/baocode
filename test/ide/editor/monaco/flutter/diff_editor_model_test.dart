import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/diff_editor_model.dart';
import 'package:monad/ide/editor/monaco/flutter/document_snapshot.dart';
import 'package:monad/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/diff/range_mapping.dart';

/// A diff editor's model: the diff, and the alignments, zones and
/// decorations each editor gets from it.
void main() {
  // `b` changed to `B`, and `x` and `y` inserted before `d`.
  const originalText = 'a\nb\nc\nd\n';
  const modifiedText = 'a\nB\nc\nx\ny\nd\n';

  String lines(LineRange range) => range.toString();

  const colors = DiffEditorColors(
    insertedLine: Color(0xff000001),
    removedLine: Color(0xff000002),
    insertedText: Color(0xff000003),
    removedText: Color(0xff000004),
    insertedGutter: Color(0xff000005),
    removedGutter: Color(0xff000006),
    diagonalFill: Color(0xff000007),
    overviewInserted: Color(0xff000008),
    overviewRemoved: Color(0xff000009),
    signForeground: Color(0xff00000a),
  );

  late ValueNotifier<String?> original;
  late EditorDocumentModel modified;
  late DiffEditorModel model;

  setUp(() {
    original = ValueNotifier(originalText);
    modified = EditorDocumentModel(modifiedText);
    model = DiffEditorModel(original: original, modified: modified);
  });

  tearDown(() {
    model.dispose();
    modified.dispose();
    original.dispose();
  });

  test('computes the changes of the two sides', () {
    final mappings = model.mappings!;
    expect(mappings, hasLength(2));
    expect(lines(mappings[0].original), '[2,3)');
    expect(lines(mappings[0].modified), '[2,3)');
    expect(lines(mappings[1].original), '[4,4)');
    expect(lines(mappings[1].modified), '[4,6)');
    expect(model.hitTimeout, isFalse);
  });

  test('waits for the original, and follows it', () {
    original.value = null;
    final loading = DiffEditorModel(original: original, modified: modified);
    addTearDown(loading.dispose);
    expect(loading.mappings, isNull);
    original.value = modifiedText;
    expect(loading.mappings, isEmpty);
  });

  testWidgets('computes again 200ms after an edit', (tester) async {
    // Its timer in the test's clock.
    final edited = EditorDocumentModel(modifiedText);
    final diff = DiffEditorModel(original: original, modified: edited);
    addTearDown(() {
      diff.dispose();
      edited.dispose();
    });
    edited.replaceText(originalText);
    await tester.pump(const Duration(milliseconds: 100));
    expect(diff.mappings, hasLength(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(diff.mappings, isEmpty);
  });

  test('side by side, the side with fewer lines is filled up', () {
    final snapshot = DocumentSnapshot(originalText);
    final alignments = computeDiffAlignments(
      model.mappings!,
      snapshot,
      innerHunkAlignment: true,
    );
    expect(
      [
        for (final a in alignments)
          '${lines(a.originalRange)} ${lines(a.modifiedRange)}',
      ],
      ['[2,3) [2,3)', '[4,4) [4,6)'],
    );
    final zones = computeDiffZones(alignments, sideBySide: true);
    expect(zones.modified, isEmpty);
    expect(zones.original, hasLength(1));
    expect(zones.original.single.afterLineNumber, 3);
    expect(zones.original.single.heightInLines, 2);
    expect(zones.original.single.kind, DiffZoneKind.fill);
    expect(zones.original.single.gutterDelete, isFalse);
  });

  test('inline, the modified shows the deleted code above each change, and '
      'the original makes room beside it', () {
    final alignments = computeDiffAlignments(
      model.mappings!,
      DocumentSnapshot(originalText),
      innerHunkAlignment: false,
    );
    final zones = computeDiffZones(alignments, sideBySide: false);
    expect(zones.modified, hasLength(1));
    final deleted = zones.modified.single;
    expect(deleted.kind, DiffZoneKind.deletedCode);
    expect(deleted.afterLineNumber, 1);
    expect(deleted.heightInLines, 1);
    expect(lines(deleted.deleted!), '[2,3)');

    expect(
      [
        for (final zone in zones.original)
          (zone.afterLineNumber, zone.heightInLines, zone.gutterDelete),
      ],
      [(2, 1.0, true), (3, 2.0, true)],
    );
  });

  test('decorates changed lines, their signs and the changed text', () {
    final decorations = computeDiffDecorations(
      model.mappings!,
      DocumentSnapshot(originalText),
      modified.snapshot,
      colors,
    );
    // `b`: the whole line, then its text, which fills the line break.
    final removed = decorations.original;
    expect(removed, hasLength(2));
    expect((removed[0].start, removed[0].end), (2, 3));
    expect(removed[0].isWholeLine, isTrue);
    expect(removed[0].backgroundColor, colors.removedLine);
    expect(removed[0].marginColor, colors.removedGutter);
    expect(removed[0].lineDecorationIcon, diffRemoveIcon);
    expect(removed[0].overviewRulerColor, colors.overviewRemoved);
    expect((removed[1].start, removed[1].end), (2, 3));
    expect(removed[1].isWholeLine, isFalse);
    expect(removed[1].backgroundColor, colors.removedText);
    expect(removed[1].fillsLineOnLineBreak, isTrue);

    // `B`, then the inserted lines, whose text is all inserted.
    final inserted = decorations.modified;
    expect(inserted, hasLength(4));
    expect(inserted[0].lineDecorationIcon, diffInsertIcon);
    expect((inserted[2].start, inserted[2].end), (6, 9));
    expect(inserted[2].backgroundColor, colors.insertedLine);
    expect((inserted[3].start, inserted[3].end), (6, 9));
    expect(inserted[3].isWholeLine, isTrue);
    expect(inserted[3].backgroundColor, colors.insertedText);
  });
}
