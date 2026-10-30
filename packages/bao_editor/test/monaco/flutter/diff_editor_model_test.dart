import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/diff_editor_model.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/lines_diff.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/range_mapping.dart';

/// A diff editor's model: the diff, and the zones and decorations each
/// editor gets from it.
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
    overviewInserted: Color(0xff000008),
    overviewRemoved: Color(0xff000009),
    insertedBar: Color(0xff00000a),
    removedBar: Color(0xff00000b),
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

  test(
    'texts past a few thousand characters are compared off this '
    'isolate; edits while it runs are compared after it, the last text',
    () async {
      // Every line changed: on this isolate, longer than a frame.
      String text(String word) =>
          [for (var i = 0; i < 60; i++) '$word $i ${'z' * 50}'].join('\n');
      expect(
        isSmallLinesDiff(text('a').split('\n'), text('b').split('\n')),
        isFalse,
      );
      final before = ValueNotifier<String?>(text('before'));
      final after = EditorDocumentModel(text('after'));
      final diff = DiffEditorModel(original: before, modified: after);
      addTearDown(() {
        diff.dispose();
        after.dispose();
        before.dispose();
      });
      expect(diff.mappings, isNull);
      for (final word in ['one', 'two', 'three']) {
        after.replaceText(text(word));
      }
      before.value = text('three');
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (diff.mappings?.isEmpty != true) {
        expect(DateTime.now().isBefore(deadline), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    },
  );

  test('a few thousand characters at most are compared here', () {
    expect(isSmallLinesDiff(['a' * 999], ['b' * 999]), isTrue);
    expect(isSmallLinesDiff(['a' * 1000], ['b' * 1000]), isFalse);
  });

  test('inline, the deleted code goes above the lines put in its place; '
      'side by side, nothing is aligned with zones', () {
    final zones = computeDiffZones(model.mappings!);
    // `b` above `B`; nothing taken out where `x` and `y` were put in.
    expect(zones, hasLength(1));
    final deleted = zones.single;
    expect(deleted.afterLineNumber, 1);
    expect(deleted.heightInLines, 1);
    expect(lines(deleted.deleted), '[2,3)');
  });

  test('decorates changed lines, their margins and the changed text', () {
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
    expect(removed[0].lineDecorationIcon, isNull);
    expect(removed[0].overviewRulerColor, colors.overviewRemoved);
    expect((removed[1].start, removed[1].end), (2, 3));
    expect(removed[1].isWholeLine, isFalse);
    expect(removed[1].backgroundColor, colors.removedText);
    expect(removed[1].fillsLineOnLineBreak, isTrue);

    // `B`, then the inserted lines, whose text is all inserted.
    final inserted = decorations.modified;
    expect(inserted, hasLength(4));
    expect(inserted[0].lineDecorationIcon, isNull);
    // Side by side, no bar at the gutter's edge.
    expect(inserted[0].gutterBarColor, isNull);
    expect((inserted[2].start, inserted[2].end), (6, 9));
    expect(inserted[2].backgroundColor, colors.insertedLine);
    expect((inserted[3].start, inserted[3].end), (6, 9));
    expect(inserted[3].isWholeLine, isTrue);
    expect(inserted[3].backgroundColor, colors.insertedText);
  });

  test("inline, the inserted lines' margins have a bar at the edge", () {
    final inserted = computeDiffDecorations(
      model.mappings!,
      DocumentSnapshot(originalText),
      modified.snapshot,
      colors,
      gutterBars: true,
    ).modified;
    expect(
      [
        for (final d in inserted)
          if (d.marginColor != null) d.gutterBarColor,
      ],
      [colors.insertedBar, colors.insertedBar],
    );
  });

  test('a changed range grows to the words it touches', () {
    const text = 'let totals = 2;';
    // Inside a word, or an insertion point in one: the word.
    expect(diffWordRange(text, 9, 10), (4, 10));
    expect(diffWordRange(text, 6, 6), (4, 10));
    // Punctuation and spaces stay as they are.
    expect(diffWordRange(text, 13, 14), (13, 14));
    expect(diffWordRange(text, 10, 13), (10, 13));
  });

  group('highlighted by', () {
    late ValueNotifier<String?> before;
    late EditorDocumentModel after;
    late DiffEditorModel words;

    setUp(() {
      before = ValueNotifier('let total = 1;\n');
      after = EditorDocumentModel('let totals = 2;\n');
      words = DiffEditorModel(original: before, modified: after);
    });

    tearDown(() {
      words.dispose();
      after.dispose();
      before.dispose();
    });

    ({List<EditorDecoration> original, List<EditorDecoration> modified})
    decorate(DiffHighlight highlight) => computeDiffDecorations(
      words.mappings!,
      DocumentSnapshot(before.value!),
      after.snapshot,
      colors,
      highlight: highlight,
    );

    List<(int, int)> inner(List<EditorDecoration> decorations) => [
      for (final decoration in decorations)
        if (!decoration.isWholeLine) (decoration.start, decoration.end),
    ];

    test('character: just what changed', () {
      expect(inner(decorate(DiffHighlight.characters).modified), [
        (9, 10),
        (13, 14),
      ]);
    });

    test('word: the words it is in', () {
      expect(inner(decorate(DiffHighlight.words).modified), [
        (4, 10),
        (13, 14),
      ]);
    });

    test('line: the lines only', () {
      final decorations = decorate(DiffHighlight.lines);
      expect(inner(decorations.modified), isEmpty);
      expect(decorations.modified.single.backgroundColor, colors.insertedLine);
    });

    test('none: no colour behind, the margin kept', () {
      final decorations = decorate(DiffHighlight.none);
      expect(inner(decorations.modified), isEmpty);
      for (final decoration in [
        ...decorations.original,
        ...decorations.modified,
      ]) {
        expect(decoration.backgroundColor, isNull);
      }
      expect(decorations.modified.single.marginColor, colors.insertedGutter);
    });
  });
}
