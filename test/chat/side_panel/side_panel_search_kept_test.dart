import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// The files page's search of each project, as it was left: its files to
/// include and exclude and its options come back on the next run (#268).
void main() {
  test('a project\'s search is kept between runs, each project\'s own', () {
    var saves = 0;
    final panel = AgentSidePanel(onSave: () => saves++);
    addTearDown(panel.dispose);
    Stream<Object> none(String root, Object query) => const Stream.empty();
    final search = panel.searchOf('/p', none);
    search.excludes.text = '**/gen';
    search.matchCase = true;
    search.includes.text = 'lib';
    expect(saves, greaterThan(0));
    // Another project's, untouched, is not kept.
    panel.searchOf('/q', none);
    expect(panel.toJson()['searches'], {
      '/p': {'includes': 'lib', 'excludes': '**/gen', 'matchCase': true},
    });

    final next = AgentSidePanel(state: panel.toJson());
    addTearDown(next.dispose);
    final again = next.searchOf('/p', none);
    expect(again.excludes.text, '**/gen');
    expect(again.includes.text, 'lib');
    expect(again.matchCase, isTrue);
    expect(next.searchOf('/q', none).excludes.text, isEmpty);
  });
}
