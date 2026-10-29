import 'package:baocode/diagnostics/frame_watch.dart';
import 'package:flutter_test/flutter_test.dart';

const _ms = 1000;

/// Frames every [every] ms from [from] for [seconds], each taking [ui] and
/// [raster] ms: the summaries the window gave.
List<String> _frames(
  JankWindow window, {
  int from = 0,
  required int seconds,
  int every = 16,
  required int ui,
  int raster = 4,
}) => [
  for (var at = from; at < from + seconds * 1000; at += every)
    ?window.add(at * _ms, ui: ui * _ms, raster: raster * _ms),
];

void main() {
  test('frames slow one after another are summed up each span', () {
    final window = JankWindow();
    final said = _frames(window, seconds: 11, every: 50, ui: 45);
    expect(said, hasLength(2));
    expect(said.first, startsWith('5 s: 101 frames, 101 over 32 ms'));
    expect(said.first, contains('ui avg 45 max 45 ms'));
    expect(said.first, contains('raster avg 4 max 4 ms'));
  });

  test('where the slow frames went on the UI thread', () {
    final window = JankWindow();
    String? said;
    for (var at = 0; at <= 5000 && said == null; at += 40) {
      window.addParts(
        took: 40 * _ms,
        animations: 1 * _ms,
        microtasks: 0,
        build: 36 * _ms,
        after: 3 * _ms,
      );
      said = window.add(at * _ms, ui: 40 * _ms, raster: 2 * _ms);
    }
    expect(
      said,
      contains(
        'slow ui frames avg: animations 1, microtasks 0, '
        'build to semantics 36, after 3',
      ),
    );
  });

  test('slow raster counts as much as a slow UI thread', () {
    final window = JankWindow();
    final said = _frames(window, seconds: 6, every: 50, ui: 3, raster: 60);
    expect(said.single, contains('raster avg 60 max 60 ms'));
  });

  test('smooth frames, or a few slow among them, say nothing', () {
    final window = JankWindow();
    expect(_frames(window, seconds: 20, ui: 8), isEmpty);
    // One slow in five: under a quarter.
    var at = 0;
    final said = <String>[];
    for (var i = 0; i < 600; i++, at += 16) {
      final ui = i % 5 == 0 ? 50 : 8;
      if (window.add(at * _ms, ui: ui * _ms, raster: 2 * _ms) case final s?) {
        said.add(s);
      }
    }
    expect(said, isEmpty);
  });

  test('a pause starts the span over: slow frames apart are not a stretch', () {
    final window = JankWindow();
    final said = <String>[];
    // A slow frame each 1.5 s, for a minute: never together.
    for (var at = 0; at < 60000; at += 1500) {
      if (window.add(at * _ms, ui: 200 * _ms, raster: 0) case final s?) {
        said.add(s);
      }
    }
    expect(said, isEmpty);
  });
}
