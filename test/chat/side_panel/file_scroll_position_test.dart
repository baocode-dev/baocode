import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_view_state.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/side_panel/file_edit.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/file_preview.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_view_state.dart';

import '../../ide/workbench/fake_files.dart';

void main() {
  group('File reader scroll position per session', () {
    test('keeps view state per session and file', () {
      final panel = AgentSidePanel();
      final sessionA = ChatSession(historyCount: 0);
      final sessionB = ChatSession(historyCount: 0);

      const pathA = '/project/lib/a.dart';
      const pathB = '/project/lib/b.dart';

      final viewStateA1 = const IdeViewState(
        editor: EditorViewState(firstLine: 120, firstLineOffset: 15.0),
      );
      final viewStateB1 = const IdeViewState(
        editor: EditorViewState(firstLine: 45, firstLineOffset: 0.0),
      );
      final viewStateA2 = const IdeViewState(
        editor: EditorViewState(firstLine: 250, firstLineOffset: 8.0),
      );

      // 1. Session A 记录 pathA 的滚动位置
      panel.keepViewState(sessionA, pathA, viewStateA1);
      expect(panel.viewStateOf(sessionA, pathA).editor?.firstLine, equals(120));
      expect(panel.viewStateOf(sessionA, pathA).editor?.firstLineOffset, equals(15.0));

      // 2. Session A 记录 pathB 的滚动位置
      panel.keepViewState(sessionA, pathB, viewStateB1);
      expect(panel.viewStateOf(sessionA, pathB).editor?.firstLine, equals(45));

      // 3. Session B 也打开同一个文件 pathA，记录不同滚动位置
      panel.keepViewState(sessionB, pathA, viewStateA2);
      expect(panel.viewStateOf(sessionB, pathA).editor?.firstLine, equals(250));

      // 4. 验证互不覆盖：Session A 的 pathA 依然是 120，Session B 的 pathA 是 250
      expect(panel.viewStateOf(sessionA, pathA).editor?.firstLine, equals(120));
      expect(panel.viewStateOf(sessionB, pathA).editor?.firstLine, equals(250));
    });

    test('persists view states across app restarts via toJson and restore', () {
      final panel1 = AgentSidePanel();
      final session = ChatSession(historyCount: 0);
      const path = '/project/lib/main.dart';

      final originalState = const IdeViewState(
        editor: EditorViewState(firstLine: 88, firstLineOffset: 12.5),
        previewLine: 35,
      );

      panel1.keepViewState(session, path, originalState);

      // 模拟保存到 JSON
      final savedJson = panel1.toJson();
      expect(savedJson['viewStates'], isNotNull);

      // 模拟重启应用：创建新的 panel 并恢复状态
      final panel2 = AgentSidePanel(state: savedJson);

      // 查询恢复后的 viewState
      final restored = panel2.viewStateOf(session, path);
      expect(restored.editor?.firstLine, equals(88));
      expect(restored.editor?.firstLineOffset, equals(12.5));
      expect(restored.previewLine, equals(35));
    });

    test('reopening closed tab restores last view state', () {
      final panel = AgentSidePanel();
      final session = ChatSession(historyCount: 0);
      const path = '/project/lib/test.dart';

      final tab = SidePanelTab(FileOpenRequest(path));
      panel.open(session, FileOpenRequest(path));

      // 模拟用户在该 tab 滚动
      const scrolledState = IdeViewState(
        editor: EditorViewState(firstLine: 77, firstLineOffset: 4.0),
      );
      panel.keepViewState(session, path, scrolledState);

      // 关掉 tab
      panel.close(session, tab);

      // 验证关掉后再读取，滚动位置依然存在
      final reloaded = panel.viewStateOf(session, path);
      expect(reloaded.editor?.firstLine, equals(77));
      expect(reloaded.editor?.firstLineOffset, equals(4.0));
    });

    testWidgets('FilePreview restores viewState on load and saves on dispose', (tester) async {
      const path = '/project/lib/code.dart';
      final files = _MockFiles({
        path: List.generate(200, (i) => 'line $i').join('\n'),
      });

      IdeViewState? savedState;
      const initialViewState = IdeViewState(
        editor: EditorViewState(firstLine: 65, firstLineOffset: 12.0),
      );

      SidePanelFileEdit? capturedEdit;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilePreview(
              request: FileOpenRequest(path),
              files: files,
              viewState: initialViewState,
              onEdit: (edit) => capturedEdit = edit,
              onViewStateChanged: (state) => savedState = state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证初次加载时成功应用了 initialViewState
      expect(capturedEdit, isNotNull);
      expect(capturedEdit?.controller.viewState?.firstLine, equals(65));
      expect(capturedEdit?.controller.viewState?.firstLineOffset, equals(12.0));

      // 卸载 Widget（触发 dispose）
      await tester.pumpWidget(const SizedBox.shrink());

      // 验证 dispose 时触发了 onViewStateChanged 并回传了 viewState
      expect(savedState, isNotNull);
      expect(savedState?.editor?.firstLine, equals(65));
      expect(savedState?.editor?.firstLineOffset, equals(12.0));
    });
  });
}

class _MockFiles with ReadWriteOnlyFiles implements IdeFileService {
  _MockFiles(this._contents);
  final Map<String, String> _contents;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      _contents[path] ?? '';

  @override
  Future<void> write(String path, String text, {String? expectedText}) async {}
}
