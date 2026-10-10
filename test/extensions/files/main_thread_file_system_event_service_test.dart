import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/files/file_operation_participants.dart';
import 'package:baocode/extensions/main_thread/main_thread_file_system_event_service.dart';
import 'package:baocode/extensions/files/file_types.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/main_thread_harness.dart';

void main() {
  late Directory temp;
  late MainThreadHarness harness;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bao-mt-fsevents');
  });

  tearDown(() async {
    await harness.dispose();
    await temp.delete(recursive: true);
  });

  test(r'workspace changes are sent as $onFileEvent', () async {
    harness = MainThreadHarness(folder: temp);
    harness.disk.fireChanges([
      FileChange(VsUri.file('${temp.path}/a.txt'), FileChangeType.added),
    ]);
    await pumpEventQueue();
    final events = harness.fileEvents();
    expect(events, isNotEmpty);
    final event = events.last;
    expect((event['created'] as List).single, isA<Map>());
    expect(event['changed'], isEmpty);
    expect(event['deleted'], isEmpty);
    expect(event['session'], isNull);
  });

  test(r'$watch of a folder prefix reports its changes', () async {
    harness = MainThreadHarness(folder: temp);
    await harness.call(
      MainContext.mainThreadFileSystemEventService,
      r'$watch',
      [
        'pub.ext',
        3.5,
        VsUri.file(temp.path).toJson(),
        {'recursive': true, 'excludes': <Object?>[], 'includes': <Object?>[]},
        false,
      ],
    );
    // The watch is registered through the file service once resolved.
    await pumpEventQueue();
    await File('${temp.path}/watched.txt').writeAsString('x');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await harness.files.flushChanges();
    await pumpEventQueue();
    final created = [
      for (final e in harness.fileEvents())
        for (final uri in (e['created'] as List))
          (uri as Map)['path'],
    ];
    expect(created, contains('${temp.path}/watched.txt'));

    // And it stops on `$unwatch`.
    await harness.call(
      MainContext.mainThreadFileSystemEventService,
      r'$unwatch',
      [3.5],
    );
  });

  test('a recursive watch of a file becomes a flat one', () async {
    harness = MainThreadHarness(folder: temp);
    await File('${temp.path}/a.txt').writeAsString('a');
    await harness.call(
      MainContext.mainThreadFileSystemEventService,
      r'$watch',
      [
        'pub.ext',
        1,
        VsUri.file('${temp.path}/a.txt').toJson(),
        {'recursive': true, 'excludes': <Object?>[]},
        false,
      ],
    );
    await pumpEventQueue();
    // Watching a file (not a folder) is not recursive: writing it is
    // reported, as the flat watch of its folder sees it.
    await File('${temp.path}/a.txt').writeAsString('ab');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await harness.files.flushChanges();
    await pumpEventQueue();
    expect(harness.fileEvents(), isNotEmpty);
  });
  test('a correlated watch only hears its own session', () async {
    harness = MainThreadHarness(folder: temp);
    await harness.call(
      MainContext.mainThreadFileSystemEventService,
      r'$watch',
      [
        'pub.ext',
        9,
        VsUri.file(temp.path).toJson(),
        {'recursive': false, 'excludes': <Object?>[], 'includes': <Object?>[]},
        true,
      ],
    );
    await pumpEventQueue();
    // Correlated watches are made through `createWatcher`: the file
    // service's correlated listener hears it and sends the session.
    harness.disk.correlatedListeners.first([
      FileChange(VsUri.file('${temp.path}/a.txt'), FileChangeType.updated),
    ]);
    await harness.files.flushChanges();
    await pumpEventQueue();
    final sessioned = [
      for (final e in harness.fileEvents())
        if (e['session'] != null) e,
    ];
    expect(sessioned, isNotEmpty);
    expect(sessioned.last['session'], 9);
    // Correlated changes never reach the workspace watchers.
    expect(
      harness.fileEvents().where((e) => e['session'] == null).length,
      0,
    );
  });

  test('file operation participants ask, and their edit is applied',
      () async {
    harness = MainThreadHarness(folder: temp);
    const operation = FileOperation.move;
    final seen = <List<SourceTargetPair>>[];
    harness.participants!.addParticipant((files, op, timeout, token) async {
      seen.add(files);
    });
    await harness.participants!.willMove([
      (VsUri.file('${temp.path}/a.txt'), VsUri.file('${temp.path}/b.txt')),
    ]);
    expect(seen.single.single.target.path, '${temp.path}/b.txt');

    // `$onWillRunFileOperation`'s edit: the applier gets it, with the
    // prompt's answer.
    final applied = <(Map<String, Object?>, bool)>[];
    final promptUi = _ParticipantUi();
    harness.answer(
      ExtHostContext.extHostFileSystemEventService,
      r'$onWillRunFileOperation',
      (args) async => {
        'edit': {
          'edits': [
            {'_type': 'workspaceEdit', 'edits': []},
          ],
        },
        'extensionNames': ['TypeScript'],
      },
    );
    harness.context.services[FileParticipantUi] = promptUi;
    harness.context.services[WorkspaceEditApplier] = _Applier(applied);
    // Rebuild the actor with the services in place (they are read when
    // it is made).
    harness.setActor(
      MainContext.mainThreadFileSystemEventService.nid,
      _withServices(harness),
    );
    await harness.participants!.participate(operation, [
      (source: VsUri.file('${temp.path}/a.txt'), target: VsUri.file('${temp.path}/b.txt')),
    ]);
    expect(promptUi.asked.single.$1, operation);
    expect(promptUi.asked.single.$2, ['TypeScript']);
    expect(applied.single.$2, isFalse);
    // Only one edit is applied even when several extensions return one.
    expect(applied.single.$1['edits'], isA<List>());
  });

  test('a participant keeps its answer when asked to remember it', () async {
    harness = MainThreadHarness(folder: temp);
    final applied = <(Map<String, Object?>, bool)>[];
    final ui = _ParticipantUi(remember: true, choice: FileParticipantChoice.preview);
    harness.context.services[FileParticipantUi] = ui;
    harness.context.services[WorkspaceEditApplier] = _Applier(applied);
    harness.answer(
      ExtHostContext.extHostFileSystemEventService,
      r'$onWillRunFileOperation',
      (args) async => {
        'edit': {
          'edits': [
            {'_type': 'workspaceEdit', 'edits': []},
          ],
        },
        'extensionNames': ['TypeScript'],
      },
    );
    harness.setActor(
      MainContext.mainThreadFileSystemEventService.nid,
      _withServices(harness),
    );
    await harness.participants!.participate(FileOperation.delete, [
      (source: null, target: VsUri.file('${temp.path}/a.txt')),
    ]);
    expect(ui.asked, hasLength(1));
    expect(applied.single.$2, isTrue, reason: 'Show Preview');
    expect(harness.participants!.showPreviewChoice, isTrue);
  });

  test('a cancelled participants call applies nothing', () async {
    harness = MainThreadHarness(folder: temp);
    final applied = <(Map<String, Object?>, bool)>[];
    harness.context.services[FileParticipantUi] = _ParticipantUi();
    harness.context.services[WorkspaceEditApplier] = _Applier(applied);
    // The extension host never answers: the timeout cancels the request.
    harness.answer(
      ExtHostContext.extHostFileSystemEventService,
      r'$onWillRunFileOperation',
      (args) async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return null;
      },
    );
    harness.setActor(
      MainContext.mainThreadFileSystemEventService.nid,
      _withServices(harness),
    );
    await harness.participants!.participate(
      FileOperation.create,
      [(source: null, target: VsUri.file('${temp.path}/new.txt'))],
      CancellationTokenSource().token,
    );
    expect(applied, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test(r'$onDidRunFileOperation tells the extension host', () async {
    harness = MainThreadHarness(folder: temp);
    harness.participants!.didDelete([VsUri.file('${temp.path}/a.txt')]);
    await pumpEventQueue();
    final calls = harness.callsTo(
      ExtHostContext.extHostFileSystemEventService.nid,
    );
    final didRun = calls.where((c) => c.$1 == r'$onDidRunFileOperation');
    expect(didRun, isNotEmpty);
    expect(didRun.last.$2[0], FileOperation.delete.index);
    final files = didRun.last.$2[1]! as List;
    expect((files.single as Map)['target'], isA<Map>());
  });
}

/// `MainThreadFileSystemEventService` with the harness's services, which
/// are read once when the actor is made.
MainThreadFileSystemEventServiceActor _withServices(MainThreadHarness h) =>
    MainThreadFileSystemEventServiceActor(
      MainThreadFileSystemEventService(
        rpc: h.app,
        files: h.files,
        participants: h.participants,
        ui: h.context.services[FileParticipantUi] as FileParticipantUi?,
        applier:
            h.context.services[WorkspaceEditApplier] as WorkspaceEditApplier?,
      ),
    );


final class _ParticipantUi implements FileParticipantUi {
  _ParticipantUi({
    this.choice = FileParticipantChoice.ok,
    this.remember = false,
  });

  final FileParticipantChoice choice;
  final bool remember;
  final asked = <(FileOperation, List<String>)>[];

  @override
  void Function() showProgress(FileOperation operation, void Function() onCancel) =>
      () {};

  @override
  Future<({FileParticipantChoice choice, bool remember})> ask(
    FileOperation operation,
    List<String> extensionNames, {
    required bool needsConfirmation,
  }) async {
    asked.add((operation, extensionNames));
    return (choice: choice, remember: remember);
  }
}

final class _Applier implements WorkspaceEditApplier {
  _Applier(this.applied);

  final List<(Map<String, Object?>, bool)> applied;

  @override
  Future<bool> applyWorkspaceEdit(
    Map<String, Object?> edit, {
    bool showPreview = false,
  }) async {
    applied.add((edit, showPreview));
    return true;
  }
}
