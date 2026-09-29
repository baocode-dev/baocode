import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/flutter/document_snapshot.dart';
import 'package:monad/ide/editor/monaco/flutter/viewport_layout.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/core/range.dart';

const style = TextStyle(
  fontFamily: 'ViewportRoboto',
  fontSize: 20,
  color: Color(0xff000000),
);

ViewportLayout layout(
  String text, {
  Size viewport = const Size(200, 100),
  bool wrap = false,
  TextScaler scaler = TextScaler.noScaling,
  double horizontal = 0,
  double vertical = 0,
  ViewportLayout? previous,
  Map<int, List<TextSpan>>? styledLines,
  TextDirection direction = TextDirection.ltr,
}) => ViewportLayout(
  snapshot: DocumentSnapshot(text),
  style: style,
  viewportSize: viewport,
  wrap: wrap,
  textScaler: scaler,
  textDirection: direction,
  styledLines: styledLines,
  previousLayout: previous,
  horizontalScrollOffset: horizontal,
  verticalScrollOffset: vertical,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // flutter_test defaults to fixed-width Ahem; load the SDK's Roboto to
    // exercise proportional shaping rather than testing only a monospace font.
    final root = Platform.environment['FLUTTER_ROOT']!;
    final font = File(
      '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    final loader = FontLoader('ViewportRoboto')
      ..addFont(font.readAsBytes().then(ByteData.sublistView));
    await loader.load();
  });

  test(
    'shaped proportional glyphs, CJK and emoji drive caret and hit-test',
    () {
      final geometry = layout('iW中😀x');
      addTearDown(geometry.dispose);
      final xs = [
        0,
        1,
        2,
        3,
        5,
        6,
      ].map((offset) => geometry.caretRect(offset).left).toList();
      expect(xs[1] - xs[0], lessThan(xs[2] - xs[1]));
      expect(xs[3], greaterThan(xs[2]));
      expect(xs[4], greaterThan(xs[3]));
      expect(xs[5], greaterThan(xs[4]));

      final midY = geometry.rows.single.height / 2;
      for (final offset in [0, 1, 2, 3, 5, 6]) {
        expect(
          geometry.hitTest(Offset(geometry.caretRect(offset).left, midY)),
          offset,
          reason: 'UTF-16 insertion offset $offset',
        );
      }
      final emojiMiddle = (xs[3] + xs[4]) / 2;
      expect(geometry.hitTest(Offset(emojiMiddle - 2, midY)), 3);
      expect(geometry.hitTest(Offset(emojiMiddle + 2, midY)), 5);
      expect(geometry.hitTest(Offset(-100, midY)), 0);
      expect(geometry.hitTest(Offset(1000, midY)), 6);
    },
  );

  test(
    'empty document and mixed CRLF/blank/trailing lines have caret rows',
    () {
      final empty = layout('');
      addTearDown(empty.dispose);
      expect(empty.rows, hasLength(1));
      expect(empty.rows.single.startOffset, 0);
      expect(empty.rows.single.endOffset, 0);
      expect(empty.caretRect(0).height, greaterThan(0));
      expect(empty.hitTest(const Offset(40, 5)), 0);

      final geometry = layout('\r\n\nA\r');
      addTearDown(geometry.dispose);
      expect(geometry.rows, hasLength(4));
      expect(geometry.rows.map((row) => row.startOffset), [0, 2, 3, 5]);
      expect(geometry.rows.map((row) => row.endOffset), [0, 2, 4, 5]);
      expect(geometry.caretRect(1).top, geometry.caretRect(0).top);
      expect(geometry.caretRect(2).top, greaterThan(geometry.caretRect(0).top));
      expect(geometry.caretRect(5).top, greaterThan(geometry.caretRect(3).top));
      for (final row in geometry.rows) {
        expect(
          geometry.hitTest(Offset(0, row.top + row.height / 2)),
          row.startOffset,
        );
      }
      expect(geometry.hitTest(const Offset(0, -100)), 0);
      expect(geometry.hitTest(const Offset(1000, 1000)), 5);
    },
  );

  test(
    'vertical scrolling returns only intersecting rows and hit-tests them',
    () {
      final geometry = layout('a\nb\nc\nd', viewport: const Size(100, 35));
      addTearDown(geometry.dispose);
      final h = geometry.rows.first.height;
      expect(geometry.visibleRowRange.start, 0);
      expect(geometry.visibleRows.map((row) => row.lineNumber), [1, 2]);
      geometry.setScrollOffset(horizontal: 0, vertical: h);
      expect(geometry.visibleRowRange.start, 1);
      expect(geometry.visibleRows.first.lineNumber, 2);
      expect(geometry.hitTest(const Offset(0, 1)), 2);
      expect(geometry.rowRect(geometry.rows[1]).top, closeTo(0, 0.001));
      geometry.setScrollOffset(
        horizontal: 0,
        vertical: geometry.contentHeight + 10,
      );
      expect(geometry.visibleRowRange.isEmpty, isTrue);
      expect(geometry.hitTest(const Offset(100, 0)), 7);
    },
  );

  test(
    'horizontal scrolling shifts caret and selection, and hit-test inverts it',
    () {
      final geometry = layout('iWWW', viewport: const Size(25, 40));
      addTearDown(geometry.dispose);
      final initial = geometry.caretRect(2).left;
      final initialHit = geometry.hitTest(Offset(initial, 10));
      geometry.setScrollOffset(horizontal: 18, vertical: 0);
      expect(geometry.caretRect(2).left, closeTo(initial - 18, 0.001));
      expect(geometry.hitTest(Offset(initial - 18, 10)), initialHit);
      expect(geometry.rowRect(geometry.rows.first).left, -18);
      final rects = geometry.selectionRects(Range(1, 1, 1, 5));
      expect(rects, isNotEmpty);
      for (final rect in rects) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(25));
      }
    },
  );

  test(
    'soft wraps create independently hittable visual rows with affinity',
    () {
      final geometry = layout(
        'WW WW WW WW',
        viewport: const Size(45, 180),
        wrap: true,
      );
      addTearDown(geometry.dispose);
      expect(geometry.rows.length, greaterThan(1));
      expect(geometry.rows.first.lineNumber, 1);
      expect(geometry.rows.last.endOffset, geometry.snapshot.text.length);
      for (final row in geometry.rows) {
        final result = geometry.hitTest(Offset(1, row.top + row.height / 2));
        expect(result, inInclusiveRange(row.startOffset, row.endOffset));
      }
      final boundary = geometry.rows[1].startOffset;
      expect(
        geometry.caretRect(boundary, affinity: TextAffinity.downstream).top,
        greaterThan(
          geometry.caretRect(boundary, affinity: TextAffinity.upstream).top,
        ),
      );
      final rects = geometry.selectionRects(Range(1, 1, 1, 12));
      expect(rects.length, greaterThan(1));
      expect(rects.map((rect) => rect.top).toSet().length, greaterThan(1));
    },
  );

  test('tab advance and hit-testing follow TextPainter shaping', () {
    final geometry = layout('a\tb');
    addTearDown(geometry.dispose);
    final reference = TextPainter(
      text: const TextSpan(text: 'a\tb', style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    addTearDown(reference.dispose);
    for (final offset in [0, 1, 2, 3]) {
      expect(
        geometry.caretRect(offset).left,
        closeTo(
          reference
              .getOffsetForCaret(TextPosition(offset: offset), Rect.zero)
              .dx,
          0.001,
        ),
      );
    }
    final tabEnd = geometry.caretRect(2).left;
    expect(
      geometry.hitTest(Offset(tabEnd, geometry.rows.single.height / 2)),
      2,
    );
  });

  test('tabSize renders Monaco tab stops without changing offsets', () {
    ViewportLayout stops(String text, {Map<int, List<TextSpan>>? spans}) =>
        ViewportLayout(
          snapshot: DocumentSnapshot(text),
          style: style,
          viewportSize: const Size(400, 100),
          tabSize: 4,
          styledLines: spans,
        );
    final plain = layout('    x');
    final space = plain.caretRect(1).left;
    final geometry = stops('\tx\na\tb\n中\tc');
    addTearDown(() {
      plain.dispose();
      geometry.dispose();
    });
    // A leading tab reaches column 4; after one character it advances three
    // columns (tab stops count columns, like Monaco, even in this
    // proportional font).
    expect(geometry.caretRect(1).left, closeTo(4 * space, 0.01));
    expect(
      geometry.caretRect(5).left,
      closeTo(geometry.caretRect(4).left + 3 * space, 0.01),
    );
    // A full-width character counts two columns (as in Monaco's renderLine).
    final third = geometry.snapshot.lineStarts[2];
    expect(
      geometry.caretRect(third + 2).left,
      closeTo(geometry.caretRect(third + 1).left + 2 * space, 0.01),
    );
    // Offsets and hit testing still address the tab as one code unit.
    final rowY = geometry.rows.first.height / 2;
    expect(geometry.hitTest(Offset(4 * space - 1, rowY)), 1);
    expect(geometry.hitTest(Offset(space, rowY)), 0);
    expect(geometry.rows[1].endOffset - geometry.rows[1].startOffset, 3);
    // Styled spans keep their colors around placeholders.
    final styled = stops(
      'a\tb',
      spans: {
        1: const [
          TextSpan(
            text: 'a\t',
            style: TextStyle(color: Color(0xffff0000)),
          ),
          TextSpan(text: 'b'),
        ],
      },
    );
    addTearDown(styled.dispose);
    expect(
      styled.caretRect(2).left,
      closeTo(styled.caretRect(1).left + 3 * space, 0.01),
    );
    expect(
      styled.selectionRects(Range(1, 2, 1, 3)).single.width,
      closeTo(3 * space, 0.01),
    );
  });

  test('text scaling changes measured advances, heights and wrapping', () {
    final plain = layout('WW WW WW', viewport: const Size(80, 180), wrap: true);
    final scaled = layout(
      'WW WW WW',
      viewport: const Size(80, 180),
      wrap: true,
      scaler: TextScaler.linear(2),
    );
    addTearDown(plain.dispose);
    addTearDown(scaled.dispose);
    expect(scaled.caretRect(1).left, greaterThan(plain.caretRect(1).left));
    expect(scaled.rows.first.height, greaterThan(plain.rows.first.height));
    expect(scaled.rows.length, greaterThan(plain.rows.length));
  });

  test('multiline selections include CRLF and blank-line markers, clipped', () {
    final geometry = layout(
      'Wi\r\n\n中😀',
      viewport: const Size(35, 35),
      vertical: 8,
    );
    addTearDown(geometry.dispose);
    final rects = geometry.selectionRects(Range(1, 2, 3, 4));
    expect(rects, isNotEmpty);
    for (final rect in rects) {
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(35));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(35));
    }
    expect(geometry.selectionRects(Range(2, 1, 2, 1)), isEmpty);
    expect(geometry.selectionRects(Range(3, 1, 1, 2)), isNotEmpty);
    geometry.setScrollOffset(horizontal: 0, vertical: 500);
    expect(geometry.selectionRects(Range(1, 1, 3, 4)), isEmpty);
  });

  test('newline-only selections mark CRLF and empty lines', () {
    final geometry = layout('x\r\n\n');
    addTearDown(geometry.dispose);
    final first = geometry.selectionRects(Range(1, 2, 2, 1));
    expect(first, hasLength(1));
    expect(first.single.left, geometry.caretRect(1).left);
    final second = geometry.selectionRects(Range(2, 1, 3, 1));
    expect(second, hasLength(1));
    expect(second.single.top, geometry.rows[1].top);
  });

  test('zero-height viewport has no visible rows', () {
    final geometry = layout('abc', viewport: const Size(100, 0));
    addTearDown(geometry.dispose);
    expect(geometry.visibleRows, isEmpty);
    expect(geometry.selectionRects(Range(1, 1, 1, 4)), isEmpty);
    expect(geometry.caretRect(1).width, 1);
    expect(geometry.hitTest(const Offset(0, 0)), 0);
    expect(
      () => geometry.setScrollOffset(horizontal: -1, vertical: 0),
      throwsArgumentError,
    );
  });

  test('50k lines reuse exact shapes during random scrolling and edits', () {
    final random = math.Random(41);
    final lines = List<String>.generate(
      50001,
      (index) => index % 41 == 0 ? '' : 'iW中😀\t${index % 41}',
    );
    var current = layout(lines.join('\n'), viewport: const Size(110, 43));
    expect(current.rows, hasLength(lines.length));
    // Virtualized: only the visible rows are shaped, not all 41 variants.
    expect(current.shapedLineCount, lessThanOrEqualTo(3));
    var totalShaped = current.shapedLineCount;
    var nonDeletingEdits = 0;

    for (var edit = 0; edit < 16; edit++) {
      final index = random.nextInt(lines.length);
      if (edit % 4 == 0) {
        lines.insert(index, 'inserted $edit 中😀\tW');
      } else if (edit % 4 == 1) {
        lines.removeAt(index);
      } else {
        lines[index] = 'edited $edit 中😀\tW';
      }
      if (edit % 4 != 1) nonDeletingEdits++;
      final next = layout(
        lines.join('\n'),
        viewport: const Size(110, 43),
        previous: current,
      );
      current.dispose();
      current = next;
      expect(current.rows, hasLength(lines.length));
      final checkedIndex = index.clamp(0, lines.length - 1);
      final row = current.rows[checkedIndex];
      final local = layout(lines[checkedIndex]);
      expect(row.height, local.rows.single.height);
      expect(row.width, local.rows.single.width);
      expect(row.startOffset, current.snapshot.lineStarts[checkedIndex]);
      expect(row.endOffset, current.snapshot.contentEnds[checkedIndex]);
      final offset = row.startOffset + lines[checkedIndex].length;
      expect(
        current.caretRect(offset).left,
        local.caretRect(lines[checkedIndex].length).left,
      );
      local.dispose();

      for (var scroll = 0; scroll < 6; scroll++) {
        final target = random.nextInt(lines.length);
        current.setScrollOffset(
          horizontal: 3,
          vertical: current.rows[target].top,
        );
        expect(current.visibleRows.first.lineNumber, target + 1);
        expect(
          current.visibleRowRange.end - current.visibleRowRange.start,
          lessThanOrEqualTo(4),
        );
        expect(
          current.hitTest(const Offset(-100, 1)),
          current.snapshot.lineStarts[target],
        );
      }
      totalShaped += current.shapedLineCount;
      // Shapes survive edits: across all layouts, each distinct line text is
      // shaped at most once (41 original variants plus the edited lines).
      expect(totalShaped, lessThanOrEqualTo(41 + nonDeletingEdits));
    }
    current.dispose();
  });

  test('100k-line edits and scrolling shape only visible lines', () {
    final lines = List<String>.generate(100000, (index) => 'line $index;');
    final stopwatch = Stopwatch()..start();
    var current = layout(lines.join('\n'), viewport: const Size(300, 120));
    expect(current.rows, hasLength(100000));
    final visible = current.visibleRowRange;
    expect(current.shapedLineCount, visible.end - visible.start);
    expect(current.contentHeight, 100000 * current.lineHeight);
    for (var edit = 0; edit < 20; edit++) {
      lines[edit * 4999] = 'edited $edit';
      final next = layout(
        lines.join('\n'),
        viewport: const Size(300, 120),
        previous: current,
        vertical: current.lineHeight * edit * 4999,
      );
      current.dispose();
      current = next;
      // Only the edited line (visible at the top) needs a new paragraph.
      expect(current.shapedLineCount, lessThanOrEqualTo(visible.end));
      expect(current.visibleRows.first.lineNumber, edit * 4999 + 1);
      final recorder = ui.PictureRecorder();
      current.paintVisibleText(Canvas(recorder));
      recorder.endRecording().dispose();
      expect(current.shapedLineCount, lessThanOrEqualTo(visible.end + 1));
    }
    // Longest-line estimate covers unshaped lines for horizontal scrolling.
    expect(current.contentWidth, greaterThan(0));
    stopwatch.stop();
    // A generous bound: an eager layout of 100k lines is far slower.
    expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    current.dispose();
  });

  test('hidden lines map between model and view lines', () {
    final hidden = HiddenLineRanges([(3, 4), (8, 8), (5, 6)]);
    expect(hidden.ranges.toList(), [(3, 6), (8, 8)]);
    expect(hidden.hiddenLineCount, 5);
    expect(hidden.viewLineCount(10), 5);
    expect(
      [for (var view = 1; view <= 5; view++) hidden.viewToModel(view)],
      [1, 2, 7, 9, 10],
    );
    expect(
      [for (var line = 1; line <= 10; line++) hidden.modelToView(line)],
      [1, 2, 2, 2, 2, 2, 3, 3, 4, 5],
    );
    expect(hidden.isHidden(2), isFalse);
    expect(hidden.isHidden(6), isTrue);
    expect(hidden.rangeContaining(8), (8, 8));
    expect(hidden.clampTo(5).ranges.toList(), [(3, 5)]);

    final geometry = layout(
      List.generate(10, (index) => 'L${index + 1}').join('\n'),
      viewport: const Size(200, 500),
      previous: null,
    );
    addTearDown(geometry.dispose);
    final folded = ViewportLayout(
      snapshot: geometry.snapshot,
      style: style,
      viewportSize: const Size(200, 500),
      hiddenLines: hidden,
      previousLayout: geometry,
    );
    addTearDown(folded.dispose);
    expect(folded.rows.map((row) => row.lineNumber), [1, 2, 7, 9, 10]);
    expect(folded.contentHeight, 5 * folded.lineHeight);
    final h = folded.lineHeight;
    // Row 3 shows model line 7, whose text starts at offset 18.
    expect(folded.hitTest(Offset(0, 2 * h + 1)), folded.snapshot.lineStarts[6]);
    expect(folded.caretRect(folded.snapshot.lineStarts[6]).top, 2 * h);
    // A hidden offset maps to the header row.
    expect(folded.caretRect(folded.snapshot.lineStarts[3]).top, h);
    expect(folded.lineTop(9), 3 * h);
    // Selections spanning hidden lines only paint visible rows.
    final rects = folded.offsetRangeRects(0, folded.snapshot.text.length);
    expect(rects.map((rect) => rect.top).toSet(), hasLength(5));
  });

  test('reused rows match fresh shaping for wrap, RTL, scaling and styles', () {
    const small = TextStyle(fontSize: 8);
    const large = TextStyle(fontSize: 32);
    final original = layout(
      'שלום WW WW\nabc\nשלום WW WW',
      viewport: const Size(45, 140),
      wrap: true,
      direction: TextDirection.rtl,
      scaler: TextScaler.linear(1.5),
      styledLines: {
        2: [const TextSpan(text: 'abc', style: small)],
      },
    );
    final spans = <int, List<TextSpan>>{
      2: [const TextSpan(text: 'abc', style: large)],
    };
    final text = 'שלום WW WW\nabc\nשלום WW WW\n';
    final reused = layout(
      text,
      viewport: const Size(45, 140),
      wrap: true,
      direction: TextDirection.rtl,
      scaler: TextScaler.linear(1.5),
      styledLines: spans,
      previous: original,
    );
    final fresh = layout(
      text,
      viewport: const Size(45, 140),
      wrap: true,
      direction: TextDirection.rtl,
      scaler: TextScaler.linear(1.5),
      styledLines: spans,
    );
    expect(reused.shapedLineCount, 2); // new style and trailing blank
    original.dispose(); // shared paragraphs remain usable
    expect(reused.rows.length, fresh.rows.length);
    expect(reused.contentHeight, fresh.contentHeight);
    for (var i = 0; i < fresh.rows.length; i++) {
      final a = reused.rows[i];
      final b = fresh.rows[i];
      expect(
        [
          a.lineNumber,
          a.visualLineIndex,
          a.startOffset,
          a.endOffset,
          a.top,
          a.height,
          a.left,
          a.width,
        ],
        [
          b.lineNumber,
          b.visualLineIndex,
          b.startOffset,
          b.endOffset,
          b.top,
          b.height,
          b.left,
          b.width,
        ],
      );
    }
    for (var offset = 0; offset <= text.length; offset++) {
      expect(reused.caretRect(offset), fresh.caretRect(offset));
    }
    for (final row in fresh.rows) {
      final point = Offset(12, row.top + row.height / 2);
      expect(reused.hitTest(point), fresh.hitTest(point));
    }
    expect(
      reused.selectionRects(Range(1, 1, 4, 1)),
      fresh.selectionRects(Range(1, 1, 4, 1)),
    );
    reused.dispose();
    fresh.dispose();
  });

  test(
    'incompatible typography or wrap width reshapes instead of guessing',
    () {
      final original = layout('中😀\nWi\n中😀');
      final scaled = layout(
        '中😀\nWi\n中😀',
        previous: original,
        scaler: TextScaler.linear(2),
      );
      expect(scaled.shapedLineCount, 2);
      expect(scaled.contentHeight, greaterThan(original.contentHeight));
      final wrapped = layout(
        '中😀\nWi\n中😀',
        previous: original,
        wrap: true,
        viewport: const Size(31, 70),
      );
      expect(wrapped.shapedLineCount, 2);
      original.dispose();
      expect(wrapped.hitTest(const Offset(2, 2)), 0);
      scaled.dispose();
      wrapped.dispose();
    },
  );

  test('only visible text is painted with clipping on both axes', () async {
    final geometry = layout(
      'WWWWWW\nWWWWWW',
      viewport: const Size(30, 25),
      horizontal: 5,
      vertical: 4,
    );
    addTearDown(geometry.dispose);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    geometry.paintVisibleText(canvas, origin: const Offset(10, 10));
    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    final image = await picture.toImage(50, 50);
    addTearDown(image.dispose);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    bool hasInkAt(int x, int y) => bytes.getUint8((y * 50 + x) * 4 + 3) != 0;
    expect(hasInkAt(0, 0), isFalse);
    expect(hasInkAt(49, 49), isFalse);
    expect(
      [
        for (var y = 10; y < 35; y++)
          for (var x = 10; x < 40; x++) hasInkAt(x, y),
      ].any((pixel) => pixel),
      isTrue,
    );
  });
}
