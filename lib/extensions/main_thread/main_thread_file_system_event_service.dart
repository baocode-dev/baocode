/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadFileSystemEventService.ts
// (`MainThreadFileSystemEventService`: file events, the file operation
// participant with its progress, prompt and edit, `$watch`, `$unwatch`).
//
// Deviations:
// - The progress, the prompt and applying the edit are the app's
//   ([FileParticipantUi], [WorkspaceEditApplier]); without a UI the edit
//   is applied without asking, without an applier it is dropped.
// - The "Do not ask me again" answer is [FileOperationParticipants.
//   showPreviewChoice] (the app keeps it).

import 'dart:async';
import 'dart:math';

import 'package:bao_exthost/bao_exthost.dart';

import '../files/file_operation_participants.dart';
import '../files/file_service.dart';
import '../files/file_types.dart';
import 'main_thread_context.dart';

/// What the user chose when extensions want to edit along a file
/// operation.
enum FileParticipantChoice { ok, preview, cancel }

/// The UI of file operation participants.
abstract interface class FileParticipantUi {
  /// Shows that [operation]'s participants run ("Running 'File Rename'
  /// participants..."), cancellable ([onCancel]); returns what hides it.
  void Function() showProgress(FileOperation operation, void Function() onCancel);

  /// Asks whether to apply the edits of [extensionNames] (`ask.1.move`…):
  /// with [needsConfirmation] only Show Preview or Skip Changes.
  Future<({FileParticipantChoice choice, bool remember})> ask(
    FileOperation operation,
    List<String> extensionNames, {
    required bool needsConfirmation,
  });
}

final class MainThreadFileSystemEventService
    extends MainThreadFileSystemEventServiceUnsupported {
  MainThreadFileSystemEventService({
    required RpcProtocol rpc,
    required this.files,
    this.participants,
    this.ui,
    this.applier,
  }) : _proxy = ExtHostFileSystemEventServiceProxy(rpc) {
    _changes = files.onDidFilesChange.listen((changes) {
      _send(_proxy.$onFileEvent(fileEventsJson(changes)));
    });
    final p = participants;
    if (p != null) {
      _removeParticipant = p.addParticipant(_participate);
      _didRun = p.onDidRunFileOperation.listen((e) {
        _send(
          _proxy.$onDidRunFileOperation(e.operation.index, [
            for (final f in e.files) sourceTargetPairToJson(f),
          ]),
        );
      });
    }
  }

  static RpcActor customer(MainThreadContext c) {
    final actor = MainThreadFileSystemEventService(
      rpc: c.rpc,
      files: c.service<FileService>(),
      participants: c.maybeService<FileOperationParticipants>(),
      ui: c.maybeService<FileParticipantUi>(),
      applier: c.maybeService<WorkspaceEditApplier>(),
    );
    c.onDispose(actor.dispose);
    return MainThreadFileSystemEventServiceActor(actor);
  }

  final ExtHostFileSystemEventServiceProxy _proxy;
  final FileService files;
  final FileOperationParticipants? participants;
  final FileParticipantUi? ui;
  final WorkspaceEditApplier? applier;

  late final StreamSubscription<void> _changes;
  StreamSubscription<void>? _didRun;
  void Function()? _removeParticipant;
  final _watches = <num, void Function()>{};

  static void _send(Future<void> call) =>
      unawaited(call.catchError((Object _) {}));

  /// `FileSystemEvents`: the URIs created, changed and deleted.
  static Map<String, Object?> fileEventsJson(
    List<FileChange> changes, {
    num? session,
  }) => {
    'session': ?session,
    'created': [
      for (final c in changes)
        if (c.type == FileChangeType.added) c.resource.toJson(),
    ],
    'changed': [
      for (final c in changes)
        if (c.type == FileChangeType.updated) c.resource.toJson(),
    ],
    'deleted': [
      for (final c in changes)
        if (c.type == FileChangeType.deleted) c.resource.toJson(),
    ],
  };

  void dispose() {
    unawaited(_changes.cancel());
    unawaited(_didRun?.cancel());
    _removeParticipant?.call();
    for (final stop in _watches.values) {
      stop();
    }
    _watches.clear();
  }

  // --- the participant

  Future<void> _participate(
    List<SourceTargetPair> pairs,
    FileOperation operation,
    Duration timeout,
    CancellationToken token,
  ) async {
    final cts = CancellationTokenSource();
    unawaited(token.whenCancelled.then((_) => cts.cancel()));
    final timer = Timer(timeout, cts.cancel);
    void Function()? hideProgress;
    final delay = Duration(
      milliseconds: min(timeout.inMilliseconds ~/ 2, 3000),
    );
    final showProgress = Timer(delay, () {
      hideProgress = ui?.showProgress(operation, cts.cancel);
    });
    Map<String, Object?>? data;
    try {
      data = await Future.any([
        _proxy.$onWillRunFileOperation(
          operation.index,
          [for (final f in pairs) sourceTargetPairToJson(f)],
          timeout.inMilliseconds,
          token: cts,
        ),
        cts.whenCancelled.then((_) => null),
      ]);
    } on Object {
      data = null;
    } finally {
      timer.cancel();
      showProgress.cancel();
      hideProgress?.call();
    }
    if (cts.isCancellationRequested) data = null;
    final edit = (data?['edit'] as Map?)?.cast<String, Object?>();
    final edits = (edit?['edits'] as List?) ?? const [];
    if (data == null || edit == null || edits.isEmpty) return;
    final needsConfirmation = edits.any(
      (e) => e is Map && (e['metadata'] as Map?)?['needsConfirmation'] == true,
    );
    var showPreview = participants?.showPreviewChoice;
    final names = [
      for (final n in (data['extensionNames'] as List?) ?? const []) '$n',
    ];
    final prompt = ui;
    if (showPreview == null && prompt != null) {
      final answer = await prompt.ask(
        operation,
        names,
        needsConfirmation: needsConfirmation,
      );
      if (needsConfirmation) {
        if (answer.choice == FileParticipantChoice.cancel) return;
        showPreview = true;
      } else {
        if (answer.choice == FileParticipantChoice.cancel) return;
        showPreview = answer.choice == FileParticipantChoice.preview;
        if (answer.remember) {
          participants?.showPreviewChoice = showPreview;
          participants?.onShowPreviewChoice?.call(showPreview);
        }
      }
    }
    await applier?.applyWorkspaceEdit(edit, showPreview: showPreview ?? false);
  }

  // --- watching

  @override
  Future<void> $watch(
    String extensionId,
    num session,
    VsUri resource,
    Map<String, Object?> opts,
    bool correlate,
  ) async {
    await files.canHandleResource(resource);
    var options = WatchOptions.fromJson(opts);
    // Only a folder can be watched recursively.
    if (options.recursive) {
      try {
        final stat = await files.stat(resource);
        if (!stat.isDirectory) options = options.copyWith(recursive: false);
      } on Object {
        // Ignored.
      }
    }
    _watches.remove(session)?.call();
    if (correlate && !options.recursive) {
      _watches[session] = files.createWatcher(
        resource,
        options.copyWith(recursive: false),
        (changes) => _send(
          _proxy.$onFileEvent(fileEventsJson(changes, session: session)),
        ),
      );
    } else {
      _watches[session] = files.watch(resource, options);
    }
  }

  @override
  void $unwatch(num session) => _watches.remove(session)?.call();
}
