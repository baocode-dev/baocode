import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';

void main() {
  test("the changes the log came back over show again on the mouse's "
      'forward button, while nothing else came in front', () {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final conversation = Object();
    final tabs = panel.tabsOf(conversation);
    panel.open(conversation, const FileOpenRequest('/p/a.dart', diff: true));
    final diff = tabs.activeDiff;
    expect(diff, isNotNull);

    expect(panel.reopenDiff(conversation), isFalse);
    panel.showLog(conversation);
    expect(tabs.activeDiff, isNull);
    expect(panel.reopenDiff(conversation), isTrue);
    expect(tabs.activeDiff, same(diff));
    // Once.
    panel.showLog(conversation);
    panel.reopenDiff(conversation);
    panel.showLog(conversation);
    panel.close(conversation, diff!);
    expect(panel.reopenDiff(conversation), isFalse);
  });
}
