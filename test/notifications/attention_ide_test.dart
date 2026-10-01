import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/workspace/workspace.dart';

/// What the IDE's chat shows counts as in view, as the chat's panes do: no
/// notification for it while the window is in front, and its turn's end is
/// seen.
void main() {
  testWidgets('the IDE\'s chat is in view while the IDE shows', (tester) async {
    final workspace = Workspace.mock();
    final inPane = workspace.selected;
    final background = workspace.threads.firstWhere(
      (thread) => thread.title == 'Rate limit per API key',
    );
    final folder = background.project.path;
    workspace
      ..openIdeFolder(folder)
      ..openIdeChat(folder, background);
    expect(workspace.isShown(inPane), isTrue);
    expect(workspace.isShown(background), isFalse);

    workspace.layout = WorkspaceLayout.ide;
    expect(workspace.isShown(inPane), isFalse);
    expect(workspace.isShown(background), isTrue);

    background.session.send(const ComposerMessage(text: '加一个限流'));
    for (
      var i = 0;
      i < 400 && background.session.pendingInteraction == null;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    background.session.stop();
    for (var i = 0; i < 50 && background.session.isStreaming; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Ended in view: seen.
    expect(background.status, ThreadStatus.idle);
    await tester.pump(const Duration(seconds: 5));
    workspace.dispose();
  });
}
