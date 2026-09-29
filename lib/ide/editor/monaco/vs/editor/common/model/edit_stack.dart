/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Single-model subset of VS Code src/vs/editor/common/model/editStack.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. TextModel owns edits and
// restorations; multi-model elements, serialization and detachment are omitted.
// Unlike upstream's open-entry EOL append, EOL forms a separate entry here:
// compressed TextChange offsets cannot span a change of line-ending width.
// Empty/no-op pushes and failed validation do not create history entries here.

import '../core/selection.dart';
import '../core/text_change.dart';
import 'text_model.dart';
import '../../../platform/undo_redo/common/undo_redo_service.dart';

typedef CursorStateComputer = List<Selection>? Function(
  List<ValidEditOperation> inverseEdits,
);

class SingleModelEditStackData {
  SingleModelEditStackData(TextModel model, List<Selection>? before)
    : beforeVersionId = model.getAlternativeVersionId(),
      afterVersionId = model.getAlternativeVersionId(),
      beforeEOL = model.getEOL(),
      afterEOL = model.getEOL(),
      beforeCursorState = before == null ? null : List.unmodifiable(before),
      afterCursorState = before == null ? null : List.unmodifiable(before);

  final int beforeVersionId;
  int afterVersionId;
  final String beforeEOL;
  String afterEOL;
  final List<Selection>? beforeCursorState;
  List<Selection>? afterCursorState;
  List<TextChange> changes = [];

  void append(
    List<TextChange> next,
    String eol,
    int version,
    List<Selection>? selections,
  ) {
    if (next.isNotEmpty) {
      changes = compressConsecutiveTextChanges(changes, next);
    }
    afterEOL = eol;
    afterVersionId = version;
    afterCursorState = selections == null
        ? null
        : List.unmodifiable(selections);
  }
}

class SingleModelEditStackElement implements UndoRedoResourceElement {
  SingleModelEditStackElement(
    this.model,
    this.resource,
    List<Selection>? beforeCursorState, {
    this.label = 'Typing',
  }) : data = SingleModelEditStackData(model, beforeCursorState);

  final TextModel model;
  @override
  final Uri resource;
  final SingleModelEditStackData data;
  @override
  final String label;
  bool _open = true;

  bool canAppend(TextModel candidate) =>
      identical(model, candidate) &&
      _open &&
      model.getAlternativeVersionId() == data.afterVersionId &&
      model.getEOL() == data.afterEOL;
  void close() => _open = false;
  void open() => _open = true;

  void append(List<TextChange> changes, List<Selection>? cursorState) =>
      data.append(
        changes,
        model.getEOL(),
        model.getAlternativeVersionId(),
        cursorState,
      );

  @override
  void undo() {
    if (model.getAlternativeVersionId() != data.afterVersionId) {
      throw StateError('Edit version does not match undo history');
    }
    model.restoreEditStack(
      data.changes,
      undoing: true,
      eol: data.beforeEOL,
      version: data.beforeVersionId,
      selections: data.beforeCursorState,
    );
    close();
  }

  @override
  void redo() {
    if (model.getAlternativeVersionId() != data.beforeVersionId) {
      throw StateError('Edit version does not match redo history');
    }
    model.restoreEditStack(
      data.changes,
      undoing: false,
      eol: data.afterEOL,
      version: data.afterVersionId,
      selections: data.afterCursorState,
    );
  }
}

/// Bound to a TextModel by [TextModel.bindUndoRedo]. Forward and reverse edits
/// must go through that model, never through its underlying piece tree.
class EditStack {
  EditStack(this.model, this.undoRedoService, this.resource);

  final TextModel model;
  final UndoRedoService undoRedoService;
  final Uri resource;

  SingleModelEditStackElement? get _last {
    final last = undoRedoService.getLastElement(resource);
    return last is SingleModelEditStackElement && identical(last.model, model)
        ? last
        : null;
  }

  void pushStackElement() => _last?.close();
  void popStackElement() => _last?.open();
  void clear() => undoRedoService.removeElements(resource);

  /// EOL conversion forms its own batch: positional changes are compressed
  /// only within an EOL epoch.
  void pushEOL(EndOfLineSequence sequence) {
    if (sequence == model.getEndOfLineSequence()) return;
    pushStackElement();
    final entry = SingleModelEditStackElement(model, resource, null);
    model.setEOL(sequence);
    entry.append(const [], null);
    entry.close();
    undoRedoService.pushElement(entry, owner: model);
  }

  List<Selection>? pushEditOperation(
    List<Selection>? beforeCursorState,
    List<TextModelEditOperation> operations, {
    CursorStateComputer? cursorStateComputer,
    UndoRedoGroup? group,
  }) {
    if (operations.isEmpty) return beforeCursorState;
    final previous = _last;
    final entry = previous != null && previous.canAppend(model)
        ? previous
        : SingleModelEditStackElement(model, resource, beforeCursorState);
    final beforeVersion = model.getVersionId();
    final inverse = model.applyEdits(operations, computeUndoEdits: true);
    if (model.getVersionId() == beforeVersion) return beforeCursorState;
    List<Selection>? after;
    if (cursorStateComputer != null) {
      try {
        after = cursorStateComputer(inverse!);
      } catch (_) {
        // Upstream records null selections when a cursor computer fails.
        after = null;
      }
    }
    final ordered = inverse!.indexed.toList()
      ..sort((a, b) {
        final position = a.$2.textChange.oldPosition.compareTo(
          b.$2.textChange.oldPosition,
        );
        return position != 0 ? position : a.$1.compareTo(b.$1);
      });
    entry.append([for (final item in ordered) item.$2.textChange], after);
    model.setEditStackCursorState(after);
    if (!identical(entry, previous)) {
      undoRedoService.pushElement(entry, group: group, owner: model);
    }
    return after;
  }
}
