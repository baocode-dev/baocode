/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What runs around the app's own file operations (the explorer's new
// file, rename, paste and delete): participants before (extensions'
// `onWillCreateFiles`/`onWillRenameFiles`/`onWillDeleteFiles`, which may
// return edits, such as TypeScript's import updates) and listeners after
// (`onDidCreateFiles`…).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/workingCopy/common/
// workingCopyFileOperationParticipant.ts (`participate`: each participant
// in turn, `files.participants.timeout`), workingCopyFileService.ts
// (`addFileOperationParticipant`, `onDidRunWorkingCopyFileOperation`).
//
// Deviations: no undo/redo groups (the app's file operations have no
// undo).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import 'file_types.dart';

/// Applies a workspace edit extensions return (`IWorkspaceEditDto`, as
/// `$tryApplyWorkspaceEdit` receives it): implemented by the documents
/// area (`bulkEditService.apply`). [showPreview] asks to review the edit
/// first. Completes with whether it was applied.
abstract interface class WorkspaceEditApplier {
  Future<bool> applyWorkspaceEdit(
    Map<String, Object?> edit, {
    bool showPreview = false,
  });
}

/// `IWorkingCopyFileOperationParticipant.participate`.
typedef FileOperationParticipant = Future<void> Function(
  List<SourceTargetPair> files,
  FileOperation operation,
  Duration timeout,
  CancellationToken token,
);

/// A file operation done (`WorkingCopyFileEvent`).
typedef FileOperationEvent = ({
  FileOperation operation,
  List<SourceTargetPair> files,
});

/// The hooks the app's file operations call.
final class FileOperationParticipants {
  FileOperationParticipants({
    this.timeout = _defaultTimeout,
    this.showPreviewChoice,
    this.onShowPreviewChoice,
  });

  static Duration _defaultTimeout() => const Duration(milliseconds: 60000);

  /// `files.participants.timeout` (zero or less: no participants).
  final Duration Function() timeout;

  /// The remembered answer to "extensions want to make refactoring
  /// changes" (`file.particpants.additionalEdits`): true preview, false
  /// apply, null ask.
  bool? showPreviewChoice;

  /// Keeps [showPreviewChoice] when the user asks to.
  final void Function(bool? choice)? onShowPreviewChoice;

  final _participants = <FileOperationParticipant>[];
  final _didRun = StreamController<FileOperationEvent>.broadcast(sync: true);

  /// `onDidRunWorkingCopyFileOperation`.
  Stream<FileOperationEvent> get onDidRunFileOperation => _didRun.stream;

  /// `addFileOperationParticipant`; the returned function removes it.
  void Function() addParticipant(FileOperationParticipant participant) {
    _participants.add(participant);
    return () => _participants.remove(participant);
  }

  /// Before [operation] on [files]: each participant in turn (a failing
  /// one is skipped). Cancelling [token] stops waiting.
  Future<void> participate(
    FileOperation operation,
    List<SourceTargetPair> files, [
    CancellationToken token = CancellationToken.none,
  ]) async {
    final limit = timeout();
    if (limit <= Duration.zero) return;
    for (final participant in [..._participants]) {
      if (token.isCancellationRequested) return;
      try {
        await participant(files, operation, limit, token);
      } on Object {
        // Upstream logs and goes on.
      }
    }
  }

  /// After [operation] on [files].
  void didRun(FileOperation operation, List<SourceTargetPair> files) {
    if (!_didRun.isClosed) _didRun.add((operation: operation, files: files));
  }

  // --- the explorer's calls, by path

  static List<SourceTargetPair> _targets(Iterable<VsUri> uris) => [
    for (final uri in uris) (source: null, target: uri),
  ];

  static List<SourceTargetPair> _pairs(Iterable<(VsUri, VsUri)> moves) => [
    for (final (from, to) in moves) (source: from, target: to),
  ];

  Future<void> willCreate(Iterable<VsUri> files) =>
      participate(FileOperation.create, _targets(files));
  void didCreate(Iterable<VsUri> files) =>
      didRun(FileOperation.create, _targets(files));

  Future<void> willMove(Iterable<(VsUri, VsUri)> moves) =>
      participate(FileOperation.move, _pairs(moves));
  void didMove(Iterable<(VsUri, VsUri)> moves) =>
      didRun(FileOperation.move, _pairs(moves));

  Future<void> willCopy(Iterable<(VsUri, VsUri)> copies) =>
      participate(FileOperation.copy, _pairs(copies));
  void didCopy(Iterable<(VsUri, VsUri)> copies) =>
      didRun(FileOperation.copy, _pairs(copies));

  Future<void> willDelete(Iterable<VsUri> files) =>
      participate(FileOperation.delete, _targets(files));
  void didDelete(Iterable<VsUri> files) =>
      didRun(FileOperation.delete, _targets(files));

  void dispose() => unawaited(_didRun.close());
}
