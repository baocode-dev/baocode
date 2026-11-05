import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/services/editors.dart';
import 'package:baocode/ide/workbench/editor_panes.dart';
import 'package:baocode/ide/workbench/storage.dart';

import '../fake_files.dart';
import 'fake_host.dart';

/// The window kept without the workbench: a moment after a change, once
/// for what did not change, not while the editors kept are opened again;
/// the editors' own keys.
void main() {
  testWidgets('kept a moment after a change, not again unchanged', (
    tester,
  ) async {
    final saved = <Map<String, Object?>>[];
    final participant = _Participant();
    final storage = WorkbenchStorage(save: () => saved.add)
      ..register(participant);
    addTearDown(storage.dispose);
    expect(storage.keeps, isTrue);

    participant.value = 1;
    storage
      ..changed()
      ..changed();
    expect(saved, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved, [
      {'value': 1},
    ]);

    // Nothing new: not told again.
    storage.keep();
    expect(saved, hasLength(1));

    // Held while restoring, kept once it is done.
    final restoring = Completer<void>();
    storage.holdWhile(restoring.future);
    participant.value = 2;
    storage.keep();
    expect(saved, hasLength(1));
    restoring.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(saved.last, {'value': 2});

    // Nowhere to keep it: nothing scheduled.
    final none = WorkbenchStorage();
    expect(none.keeps, isFalse);
    none.changed();
    none.dispose();
  });

  testWidgets('the editors: those of files kept, opened again in front as '
      'they were', (tester) async {
    final workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({inRoot('a.txt'): 'a', inRoot('b.txt'): 'b'}),
    );
    addTearDown(workspace.dispose);
    final saved = <Map<String, Object?>>[];
    final storage = WorkbenchStorage(save: () => saved.add);
    addTearDown(storage.dispose);
    EditorService editors(IdeWorkspace workspace) => EditorService(
      host: FakeWorkbenchHost(),
      panes: EditorPaneRegistry(),
      workspace: () => workspace,
      layout: () => workspace.layout,
      history: () => null,
      focusWorkbench: () {},
      storage: storage,
    );
    final service = editors(workspace);
    addTearDown(service.dispose);
    storage.register(service);
    await service.open(inRoot('a.txt'));
    await service.open(inRoot('b.txt'));
    await service.open(inRoot('a.txt'));
    storage.keep();
    expect(saved.last['editors'], [inRoot('a.txt'), inRoot('b.txt')]);
    expect(saved.last['active'], inRoot('a.txt'));

    // Another window's, restored.
    final again = IdeWorkspace(
      testRoot,
      files: TreeFiles({inRoot('a.txt'): 'a', inRoot('b.txt'): 'b'}),
    );
    addTearDown(again.dispose);
    final restored = editors(again);
    addTearDown(restored.dispose);
    WorkbenchStorage()
      ..register(restored)
      ..restore(saved.last);
    await tester.pumpAndSettle();
    expect(
      [for (final doc in again.documents) doc.path],
      [inRoot('a.txt'), inRoot('b.txt')],
    );
    expect(again.active?.path, inRoot('a.txt'));
    // The caret's move, kept once it has come to rest.
    await tester.pump(const Duration(seconds: 2));
  });
}

class _Participant implements WorkbenchStorageParticipant {
  int value = 0;

  @override
  void restoreState(Map<String, Object?> kept) =>
      value = kept['value'] as int? ?? 0;

  @override
  void saveState(Map<String, Object?> into) => into['value'] = value;
}
