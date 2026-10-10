/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// `workspace.applyEdit`: text edits (with version checks), snippet edits,
// and file creates, renames and deletes with their options; a refactoring
// preview (`isRefactoring`) lists the changes and asks first.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadBulkEdits.ts
// (`$tryApplyWorkspaceEdit`, `reviveWorkspaceEditDto`),
// src/vs/workbench/contrib/bulkEdit/browser/bulkEditService.ts
// (`BulkEditService.apply`), `bulkFileEdits.ts` (`BulkFileEdits`:
// overwrite/ignoreIfExists/ignoreIfNotExists/recursive, trash, contents)
// and `bulkTextEdits.ts` (`BulkTextEdits`: the version check and the
// out-of-sync warning).
//
// Deviations:
// - There is no bulk-edit service in the app: the edits go through
//   [WorkspaceEditApplier], which the app implements (the workspace area
//   defines this port too; this is the same shape, in one file).
// - Snippet edits are inserted as text with their tab stops removed when
//   the app's editor cannot run a snippet; a text edit whose document's
//   version does not match is dropped (upstream asks the user whether to
//   apply it anyway; BaoCode has no such prompt yet) and reported through
//   the actor's log.
// - A file edit's `contents` (base64 or a data-transfer file) is decoded
//   and written; `mustBeMet` metadatas, cell edits and notebook edits are
//   not applied.
// - `isRefactoring` preview lists the changes and asks
//   ([WorkspaceEditConfirmer]); with no confirmer, a refactoring is
//   applied without asking, as upstream does when nothing listens.

import 'dart:async';
import 'dart:convert';

import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../editors/document_registry.dart';
import 'main_thread_context.dart';

/// One text edit of a workspace edit, as it comes over the wire.
class WorkspaceTextEditData {
  const WorkspaceTextEditData({
    required this.uri,
    required this.range,
    required this.text,
    this.versionId,
    this.insertAsSnippet = false,
    this.keepWhitespace = false,
    this.metadata,
  });

  final VsUri uri;
  final Range range;
  final String text;
  final int? versionId;
  final bool insertAsSnippet;
  final bool keepWhitespace;
  final WorkspaceEditEntryMetadata? metadata;
}

/// One file operation of a workspace edit.
class WorkspaceFileEditData {
  const WorkspaceFileEditData({
    this.oldResource,
    this.newResource,
    this.overwrite = false,
    this.ignoreIfExists = false,
    this.ignoreIfNotExists = false,
    this.recursive = false,
    this.copy = false,
    this.folder = false,
    this.skipTrashBin = false,
    this.contents,
    this.metadata,
  });

  final VsUri? oldResource;
  final VsUri? newResource;
  final bool overwrite;
  final bool ignoreIfExists;
  final bool ignoreIfNotExists;
  final bool recursive;
  final bool copy;
  final bool folder;
  final bool skipTrashBin;

  /// The text to write, when the edit creates or overwrites a file with
  /// given contents (upstream's `options.contents`, a `Promise<VSBuffer>`).
  final Uint8List? contents;
  final WorkspaceEditEntryMetadata? metadata;

  bool get isCreate => oldResource == null && newResource != null;
  bool get isRename => oldResource != null && newResource != null;
  bool get isDelete => oldResource != null && newResource == null;
}

/// `IWorkspaceEditEntryMetadataDto`: what an edit asks the UI to say.
class WorkspaceEditEntryMetadata {
  const WorkspaceEditEntryMetadata({
    required this.needsConfirmation,
    required this.label,
    this.description,
  });

  final bool needsConfirmation;
  final String label;
  final String? description;
}

/// One edit of a workspace edit, in the order it was sent.
sealed class WorkspaceEditData {
  const WorkspaceEditData();
}

class WorkspaceEditText extends WorkspaceEditData {
  const WorkspaceEditText(this.edit);

  final WorkspaceTextEditData edit;
}

class WorkspaceEditFile extends WorkspaceEditData {
  const WorkspaceEditFile(this.edit);

  final WorkspaceFileEditData edit;
}

/// A whole `workspace.applyEdit` request.
class WorkspaceEditDataList {
  const WorkspaceEditDataList(this.edits);

  final List<WorkspaceEditData> edits;

  bool get isEmpty => edits.isEmpty;
}

/// Applies a workspace edit the extension host asked for.
///
/// This is the port the workspace area defines (and the one its own
/// `workspace.applyEdit` implementation uses), so both go through one
/// implementation of "apply these edits and their file operations".
abstract interface class WorkspaceEditApplier {
  /// Applies [edit]: text edits to open documents (and to files the app
  /// opens on demand), then the file operations, in the order they were
  /// sent. [isRefactoring] is `undefined` for `WorkspaceEdit.apply` and
  /// `true` for a refactoring's edits. Whether everything was applied.
  Future<bool> apply(
    WorkspaceEditDataList edit, {
    int? undoRedoGroupId,
    bool? isRefactoring,
  });
}

/// A [WorkspaceEditApplier] that reports it applied nothing: the actor's
/// default before the app gives one.
final class NoWorkspaceEditApplier implements WorkspaceEditApplier {
  const NoWorkspaceEditApplier();

  @override
  Future<bool> apply(
    WorkspaceEditDataList edit, {
    int? undoRedoGroupId,
    bool? isRefactoring,
  }) async => false;
}

final class MainThreadBulkEdits extends MainThreadBulkEditsUnsupported {
  MainThreadBulkEdits({required this.applier, this.log});

  final WorkspaceEditApplier applier;

  /// Where a dropped edit is reported (`ILogService.warn` upstream).
  final void Function(String message)? log;

  @override
  Future<bool> $tryApplyWorkspaceEdit(
    Object? workspaceEditDto,
    num? undoRedoGroupId,
    bool? isRefactoring,
  ) async {
    final dto = switch (workspaceEditDto) {
      RpcObjectWithBuffers(:final value) => value,
      _ => workspaceEditDto,
    };
    final edit = parseWorkspaceEditData(dto);
    if (edit == null) return false;
    try {
      return await applier.apply(
        edit,
        undoRedoGroupId: undoRedoGroupId?.toInt(),
        isRefactoring: isRefactoring,
      );
    } on Object catch (error) {
      log?.call('IGNORING workspace edit: $error');
      return false;
    }
  }
}

/// `reviveWorkspaceEditDto`: the DTO's edits as typed data. Null when the
/// DTO is malformed.
WorkspaceEditDataList? parseWorkspaceEditData(Object? dto) {
  if (dto is! Map) return null;
  final edits = dto['edits'];
  if (edits is! List) return null;
  final result = <WorkspaceEditData>[];
  for (final entry in edits) {
    if (entry is! Map) continue;
    final map = entry.cast<String, Object?>();
    if (map['textEdit'] case final Map<Object?, Object?> textEdit) {
      final resource = map['resource'];
      if (resource is! Map) continue;
      final edit = textEdit.cast<String, Object?>();
      if (edit['range'] is! Map) continue;
      result.add(
        WorkspaceEditText(
          WorkspaceTextEditData(
            uri: VsUri.revive(resource.cast<String, Object?>()),
            range: _range(edit['range']! as Map),
            text: '${edit['text'] ?? ''}',
            versionId: (map['versionId'] as num?)?.toInt(),
            insertAsSnippet: edit['insertAsSnippet'] == true,
            keepWhitespace: edit['keepWhitespace'] == true,
            metadata: _metadata(map['metadata']),
          ),
        ),
      );
      continue;
    }
    // A file edit has `oldResource` and/or `newResource`.
    if (map.containsKey('oldResource') || map.containsKey('newResource')) {
      final options = switch (map['options']) {
        final Map<Object?, Object?> options => options.cast<String, Object?>(),
        _ => const <String, Object?>{},
      };
      result.add(
        WorkspaceEditFile(
          WorkspaceFileEditData(
            oldResource: _uri(map['oldResource']),
            newResource: _uri(map['newResource']),
            overwrite: options['overwrite'] == true,
            ignoreIfExists: options['ignoreIfExists'] == true,
            ignoreIfNotExists: options['ignoreIfNotExists'] == true,
            recursive: options['recursive'] == true,
            copy: options['copy'] == true,
            folder: options['folder'] == true,
            skipTrashBin: options['skipTrashBin'] == true,
            contents: _contents(options['contents']),
            metadata: _metadata(map['metadata']),
          ),
        ),
      );
    }
  }
  return WorkspaceEditDataList(result);
}

VsUri? _uri(Object? value) => value is Map
    ? VsUri.revive(value.cast<String, Object?>())
    : null;

WorkspaceEditEntryMetadata? _metadata(Object? value) {
  if (value is! Map) return null;
  return WorkspaceEditEntryMetadata(
    needsConfirmation: value['needsConfirmation'] == true,
    label: '${value['label'] ?? ''}',
    description: value['description'] as String?,
  );
}

/// `options.contents`: `{type: 'base64', value: …}` decoded, or a
/// data-transfer file, which BaoCode has no resolver for.
Uint8List? _contents(Object? value) {
  if (value is! Map) return null;
  if (value['type'] == 'base64' && value['value'] is String) {
    return base64.decode(value['value']! as String);
  }
  return null;
}

Range _range(Map<Object?, Object?> range) => Range(
  range['startLineNumber']! as int,
  range['startColumn']! as int,
  range['endLineNumber']! as int,
  range['endColumn']! as int,
);

/// The actor of `MainContext.mainThreadBulkEdits`.
RpcActor mainThreadBulkEditsActor(MainThreadContext context) =>
    MainThreadBulkEditsActor(
      MainThreadBulkEdits(
        applier:
            context.maybeService<WorkspaceEditApplier>() ??
            const NoWorkspaceEditApplier(),
        log: context.maybeService<ExtensionHostLog>()?.warn,
      ),
    );

/// Where messages for the extension host's log go (`ILogService`).
final class ExtensionHostLog {
  const ExtensionHostLog(this.warn);

  final void Function(String message) warn;
}

/// The same, as a list, for tests.
@visibleForTesting
void dumpWorkspaceEdit(WorkspaceEditDataList edit, void Function(String) out) {
  for (final entry in edit.edits) {
    switch (entry) {
      case WorkspaceEditText(:final edit):
        out('text ${edit.uri} ${edit.range} ${edit.text}');
      case WorkspaceEditFile(:final edit):
        out('file ${edit.oldResource} -> ${edit.newResource}');
    }
  }
}

/// The document registry's key for a URI; re-exported so an applier does
/// not have to import the registry.
String workspaceEditDocumentKey(VsUri uri) => documentKeyOf(uri);
