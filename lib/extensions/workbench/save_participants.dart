/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What runs before a file is written, in upstream's order: trailing
// whitespace trimmed, code actions on save, format on save, a final
// newline inserted, final newlines trimmed, then the extensions'
// `onWillSaveTextDocument` listeners.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/codeEditor/browser/saveParticipants.ts
// (`TrimWhitespaceParticipant`, `CodeActionOnSaveParticipant`,
// `FormatOnSaveParticipant`, `FinalNewLineParticipant`,
// `TrimFinalNewLinesParticipant`, registered in that order),
// src/vs/workbench/api/browser/mainThreadSaveParticipant.ts
// (`ExtHostSaveParticipant`, registered as the extension host starts, so
// last) and src/vs/workbench/services/textfile/common/
// textFileSaveParticipant.ts (one after the other; an error is logged and
// the rest run).
//
// Deviations: `editor.formatOnSaveMode` `modifications` formats the whole
// file (BaoCode has no SCM diff of a file's lines to format only those;
// `modificationsIfAvailable` does the same upstream without one);
// `files.trimTrailingWhitespaceInRegexAndStrings: false` trims anyway (it
// needs the language's tokens); the "Running Code Actions and Formatters"
// progress and its Skip are not shown; BaoCode never auto-saves, so the
// reasons other than an explicit save only come from extensions.

import 'dart:async';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/model/indentation_guesser.dart';
import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/ide_workspace.dart';
import '../configuration/configuration_service.dart';
import '../language/language_dto.dart' as dto;
import '../language/language_feature_document.dart';
import '../language/language_types.dart';
import '../language/registry_language_features.dart';
import '../main_thread/main_thread_bulk_edits.dart';
import '../main_thread/main_thread_context.dart';
import 'ide_documents.dart';

/// `CodeActionKind.SourceFixAll`.
const _sourceFixAll = HierarchicalKind('source.fixAll');

final class ExtensionSaveParticipants {
  ExtensionSaveParticipants({
    required this.configuration,
    required this.languages,
    required this.edits,
    required this.executeCommand,
    required this.languageIdFor,
    this.editorOptions,
    this.log,
  });

  final ConfigurationService configuration;
  final RegistryLanguageFeatures languages;

  /// Applies the participants' edits (the on-screen editor's carets kept).
  final IdeWorkspaceEditApplier edits;

  /// Runs a code action's command.
  final Future<Object?> Function(String id, List<Object?> args) executeCommand;

  /// The language id of the file at a path.
  final String Function(String path) languageIdFor;

  /// The tab size and spaces of the editor showing a model, if one does.
  final ({int tabSize, bool insertSpaces})? Function(EditorDocumentModel)?
  editorOptions;

  /// Where a participant's failure is reported.
  final void Function(String message)? log;

  /// The extension host's `$participateInSave`, while one runs.
  ExtHostDocumentSaveParticipantProxy? _extHost;

  /// Connects to a session's extension host ([MainThreadContext]): its
  /// `onWillSaveTextDocument` listeners run on each save until it ends.
  void connect(MainThreadContext context) {
    final proxy = ExtHostDocumentSaveParticipantProxy(context.rpc);
    _extHost = proxy;
    context.onDispose(() {
      if (identical(_extHost, proxy)) _extHost = null;
    });
  }

  /// Every participant, in order ([IdeSaveParticipant]).
  Future<void> participate(
    String path,
    EditorDocumentModel model,
    IdeSaveReason reason,
  ) async {
    final steps = <(String, Future<void> Function())>[
      ('trimTrailingWhitespace', () async => _trimWhitespace(path, model)),
      ('codeActionsOnSave', () => _codeActionsOnSave(path, reason)),
      ('formatOnSave', () => _formatOnSave(path, model, reason)),
      ('insertFinalNewline', () async => _finalNewLine(path, model)),
      ('trimFinalNewlines', () async => _trimFinalNewLines(path, model)),
      ('onWillSaveTextDocument', () => _extHostParticipant(path, reason)),
    ];
    for (final (name, step) in steps) {
      try {
        await step();
      } catch (error) {
        log?.call('Save participant $name failed for $path: $error');
      }
    }
  }

  Object? _setting(String key, String path) => configuration.getValue(
    key,
    resource: VsUri.file(path),
    languageId: languageIdFor(path),
  );

  // --- TrimWhitespaceParticipant ----------------------------------------

  void _trimWhitespace(String path, EditorDocumentModel model) {
    if (_setting('files.trimTrailingWhitespace', path) != true) return;
    final snapshot = model.snapshot;
    final text = snapshot.text;
    final offsets = <EditorOffsetEdit>[];
    for (var line = 0; line < snapshot.lineStarts.length; line++) {
      final start = snapshot.lineStarts[line];
      final end = snapshot.contentEnds[line];
      var last = end;
      while (last > start &&
          (text.codeUnitAt(last - 1) == 0x20 ||
              text.codeUnitAt(last - 1) == 0x09)) {
        last--;
      }
      if (last < end) offsets.add(EditorOffsetEdit(last, end, ''));
    }
    if (offsets.isNotEmpty) edits.applyEditorEdits(path, model, offsets);
  }

  // --- FinalNewLineParticipant ------------------------------------------

  void _finalNewLine(String path, EditorDocumentModel model) {
    if (_setting('files.insertFinalNewline', path) != true) return;
    final snapshot = model.snapshot;
    final lines = snapshot.lineStarts.length;
    final last = snapshot.text.substring(
      snapshot.lineStarts[lines - 1],
      snapshot.contentEnds[lines - 1],
    );
    if (last.trim().isEmpty) return;
    final end = snapshot.text.length;
    edits.applyEditorEdits(path, model, [
      EditorOffsetEdit(end, end, _eol(snapshot)),
    ]);
  }

  // --- TrimFinalNewLinesParticipant -------------------------------------

  void _trimFinalNewLines(String path, EditorDocumentModel model) {
    if (_setting('files.trimFinalNewlines', path) != true) return;
    final snapshot = model.snapshot;
    final lines = snapshot.lineStarts.length;
    // Do not insert new line if file does not end with new line.
    if (lines == 1) return;
    var lastNonEmpty = 0;
    for (var line = lines; line >= 1; line--) {
      if (snapshot.contentEnds[line - 1] > snapshot.lineStarts[line - 1]) {
        lastNonEmpty = line;
        break;
      }
    }
    // `Range(lastNonEmpty + 1, 1, lineCount, max)`.
    final deleteFrom = lastNonEmpty + 1;
    if (deleteFrom > lines) return;
    final start = snapshot.lineStarts[deleteFrom - 1];
    final end = snapshot.text.length;
    if (start >= end) return;
    edits.applyEditorEdits(path, model, [EditorOffsetEdit(start, end, '')]);
  }

  static String _eol(DocumentSnapshot snapshot) =>
      snapshot.text.contains('\r\n') ? '\r\n' : '\n';

  // --- FormatOnSaveParticipant ------------------------------------------

  Future<void> _formatOnSave(
    String path,
    EditorDocumentModel model,
    IdeSaveReason reason,
  ) async {
    if (reason == IdeSaveReason.auto) return;
    if (_setting('editor.formatOnSave', path) != true) return;
    final doc = languages.documents.documentForPath(path);
    if (doc == null) return;
    final formatted = await languages.formatEdits(
      doc,
      options: _formattingOptions(path, model),
      mode: FormattingMode.silent,
    );
    if (formatted == null || formatted.isEmpty) return;
    await edits.apply(
      WorkspaceEditDataList([
        for (final edit in formatted)
          WorkspaceEditText(
            WorkspaceTextEditData(
              uri: doc.uri,
              range: Range.lift(edit.range)!,
              text: edit.text,
              versionId: doc.versionId,
            ),
          ),
      ]),
    );
  }

  /// The model's options: the editor's when one shows it, else
  /// `editor.tabSize`/`editor.insertSpaces`, guessed from the text with
  /// `editor.detectIndentation`.
  FormattingOptions _formattingOptions(String path, EditorDocumentModel model) {
    if (editorOptions?.call(model) case final options?) {
      return FormattingOptions(
        tabSize: options.tabSize,
        insertSpaces: options.insertSpaces,
      );
    }
    var tabSize = switch (_setting('editor.tabSize', path)) {
      final num n => n.toInt(),
      _ => 4,
    };
    var insertSpaces = _setting('editor.insertSpaces', path) != false;
    if (_setting('editor.detectIndentation', path) != false) {
      final cursor = DocumentCursorModel(model.snapshot);
      final guess = guessIndentation(
        cursor.getLineCount(),
        cursor.getLineContent,
        tabSize,
        insertSpaces,
      );
      tabSize = guess.tabSize;
      insertSpaces = guess.insertSpaces;
    }
    return FormattingOptions(tabSize: tabSize, insertSpaces: insertSpaces);
  }

  // --- CodeActionOnSaveParticipant --------------------------------------

  Future<void> _codeActionsOnSave(String path, IdeSaveReason reason) async {
    final setting = _setting('editor.codeActionsOnSave', path);
    if (setting == null) return;
    if (reason == IdeSaveReason.auto) return;
    if (reason != IdeSaveReason.explicit && setting is List) return;
    final List<String> items;
    if (setting is List) {
      items = [for (final item in setting) '$item'];
    } else if (setting is Map) {
      items = [
        for (final MapEntry(:key, :value) in setting.entries)
          if (value != null && value != false && value != 'never') '$key',
      ];
    } else {
      return;
    }
    // Without the kinds another one contains.
    final all = [for (final item in items) HierarchicalKind(item)];
    final kinds = [
      for (final kind in all)
        if (all.every(
          (other) => other.value == kind.value || !other.contains(kind),
        ))
          kind,
    ];
    if (setting is Map) {
      // Fix-alls first.
      mergeSortKinds(kinds);
    }
    if (kinds.isEmpty) return;
    final excludes = setting is Map
        ? [
            for (final MapEntry(:key, :value) in setting.entries)
              if (value == 'never') HierarchicalKind('$key'),
          ]
        : const <HierarchicalKind>[];
    final toRun = setting is Map
        ? [
            for (final kind in kinds)
              if (setting[kind.value] == 'always' ||
                  ((setting[kind.value] == 'explicit' ||
                          setting[kind.value] == true) &&
                      reason == IdeSaveReason.explicit))
                kind,
          ]
        : kinds;
    final doc = languages.documents.documentForPath(path);
    if (doc == null) return;
    for (final kind in toRun) {
      await _applyActionsOfKind(doc, kind, excludes);
    }
  }

  /// Fix-alls before the other kinds, the rest in their order.
  static void mergeSortKinds(List<HierarchicalKind> kinds) {
    final fixAll = [
      for (final kind in kinds)
        if (_sourceFixAll.contains(kind)) kind,
    ];
    final rest = [
      for (final kind in kinds)
        if (!_sourceFixAll.contains(kind)) kind,
    ];
    kinds
      ..clear()
      ..addAll([...fixAll, ...rest]);
  }

  Future<void> _applyActionsOfKind(
    LanguageFeatureDocument doc,
    HierarchicalKind kind,
    List<HierarchicalKind> excludes,
  ) async {
    final lines = doc.lineCount;
    final actions = await languages.provideCodeActions(
      doc,
      Range(1, 1, lines, doc.getLineContent(lines).length + 1),
      CodeActionFilter(
        include: kind,
        excludes: excludes,
        includeSourceActions: true,
      ),
      trigger: CodeActionTriggerType.auto,
    );
    for (final (:action, :provider) in actions) {
      if (action.disabled != null) continue;
      try {
        // `applyCodeAction`: resolved first when it has no edit yet.
        var resolved = action;
        if (resolved.edit == null && provider.canResolveCodeAction) {
          resolved =
              await provider.resolveCodeAction(
                action,
                CancellationToken.none,
              ) ??
              action;
        }
        if (resolved.edit case final edit?) {
          final data = parseWorkspaceEditData(dto.encodeWorkspaceEdit(edit));
          if (data != null && !data.isEmpty) await edits.apply(data);
        }
        if (resolved.command case final command?) {
          await executeCommand(command.id, command.arguments ?? const []);
        }
      } catch (error) {
        // A failing action does not block the others.
        log?.call('Code action "${action.title}" on save failed: $error');
      }
    }
  }

  // --- ExtHostSaveParticipant -------------------------------------------

  Future<void> _extHostParticipant(String path, IdeSaveReason reason) async {
    final proxy = _extHost;
    if (proxy == null) return;
    final doc = languages.documents.documentForPath(path);
    // The model never made it to the extension host.
    if (doc == null || !doc.isSynchronized) return;
    final values = await proxy
        .$participateInSave(doc.uri, reason.value)
        .timeout(
          const Duration(milliseconds: 1750),
          onTimeout: () => throw TimeoutException(
            'Aborted onWillSaveTextDocument-event after 1750ms',
          ),
        );
    if (!values.every((ok) => ok)) throw StateError('listener failed');
  }
}
