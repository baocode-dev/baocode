import 'package:baocode/extensions/main_thread/main_thread_editor_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_rpc.dart';
import 'fake_editor_host.dart';

void main() {
  test('an empty editor group is announced before any tab operation', () async {
    final rpc = ScriptedRpc();
    final workbench = FakeWorkbench();
    final tabs = MainThreadEditorTabs(tabs: workbench, rpc: rpc.protocol)
      ..start();
    addTearDown(() {
      tabs.dispose();
      workbench.dispose();
      rpc.dispose();
    });

    await Future<void>.delayed(Duration.zero);
    expect(rpc.callsTo(r'ExtHostEditorTabs.$acceptEditorTabModel'), [
      [
        [
          {'groupId': 0, 'isActive': true, 'viewColumn': 1, 'tabs': []},
        ],
      ],
    ]);
  });
}
