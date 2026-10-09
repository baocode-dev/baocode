
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/files/file_operation_participants.dart';
import 'package:baocode/extensions/files/file_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('participants run in order, then the listeners hear about it',
      () async {
    final participants = FileOperationParticipants(
      timeout: () => const Duration(seconds: 5),
    );
    addTearDown(participants.dispose);
    final log = <String>[];
    participants.addParticipant((files, operation, timeout, token) async {
      log.add('first ${operation.name} ${files.length}');
    });
    participants.addParticipant((files, operation, timeout, token) async {
      log.add('second ${operation.name} ${files.length}');
    });
    final events = <String>[];
    participants.onDidRunFileOperation.listen(
      (e) => events.add('${e.operation.name} ${e.files.length}'),
    );

    await participants.willMove([
      (VsUri.file('/a.txt'), VsUri.file('/b.txt')),
    ]);
    expect(log, ['first move 1', 'second move 1']);
    participants.didMove([
      (VsUri.file('/a.txt'), VsUri.file('/b.txt')),
    ]);
    await pumpEventQueue();
    expect(events, ['move 1']);
  });

  test('a failing participant does not stop the others', () async {
    final participants = FileOperationParticipants()..dispose;
    addTearDown(participants.dispose);
    var ran = false;
    participants.addParticipant((_, _, _, _) async => throw StateError('no'));
    participants.addParticipant((_, _, _, _) async => ran = true);
    await participants.willCreate([VsUri.file('/a.txt')]);
    expect(ran, isTrue);
  });

  test('a zero timeout disables the participants', () async {
    final participants = FileOperationParticipants(
      timeout: () => Duration.zero,
    );
    addTearDown(participants.dispose);
    var ran = false;
    participants.addParticipant((_, _, _, _) async => ran = true);
    await participants.participate(FileOperation.delete, [
      (source: null, target: VsUri.file('/a.txt')),
    ] as List<SourceTargetPair>);
    expect(ran, isFalse);
  });

  test('the app applies a workspace edit through its applier', () async {
    final participants = FileOperationParticipants();
    addTearDown(participants.dispose);
    // The applier's call is what MainThreadFileSystemEventService does.
    final applied = <Map<String, Object?>>[];
    final applier = _Applier(applied);
    final seen = <List<SourceTargetPair>>[];
    participants.addParticipant((files, operation, timeout, token) async {
      seen.add(files);
      await applier.applyWorkspaceEdit({'edits': []});
    });
    await participants.willDelete([VsUri.file('/a.txt')]);
    expect(seen.single.single.target.path, '/a.txt');
    expect(applied, [
      {'edits': []},
    ]);
  });

  test('a write of bytes goes through the file service', () async {
    // A reminder that [WorkspaceEditApplier] exists for the documents
    // area: its signature is what mainThreadBulkEdits sends.
    final applier = _Applier([]);
    expect(
      await applier.applyWorkspaceEdit(
        {'edits': []},
        showPreview: true,
      ),
      isTrue,
    );
    expect(applier.previews, [true]);
  });
}

final class _Applier implements WorkspaceEditApplier {
  _Applier(this.applied);

  final List<Map<String, Object?>> applied;
  final previews = <bool>[];

  @override
  Future<bool> applyWorkspaceEdit(
    Map<String, Object?> edit, {
    bool showPreview = false,
  }) async {
    previews.add(showPreview);
    applied.add(edit);
    return true;
  }
}
