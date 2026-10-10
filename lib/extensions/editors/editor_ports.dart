/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the main-thread document/editor actors need from the app: the UI an
// editor is shown in, how a resource is opened as a tab, who reads a
// resource the editor has not opened, the confirmation a refactoring asks,
// and how a document's language id is chosen and changed.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// the services mainThreadDocumentsAndEditors.ts, mainThreadDocuments.ts,
// mainThreadEditors.ts, mainThreadBulkEdits.ts and mainThreadLanguages.ts
// take (`IEditorService`, `ICodeEditorService`, `ITextFileService`,
// `IFileService`, `ITextModelService`, `ILanguageService`).
//
// Deviations:
// - One port per concern, implemented on the app's objects by this area's
//   adapters (`IdeTextEditorHost`, `IdeDocumentOpener`, …) rather than a
//   dependency-injection container.

import 'dart:typed_data';

import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart'
    show EditorDecorationsController;
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/foundation.dart' show Listenable;

/// `RenderLineNumbersType`: what an editor's gutter shows.
abstract final class EditorLineNumbers {
  static const int off = 0;
  static const int on = 1;
  static const int relative = 2;
  static const int interval = 3;
}

/// `TextEditorCursorStyle`.
abstract final class EditorCursorStyle {
  static const int line = 1;
  static const int block = 2;
  static const int underline = 3;
  static const int lineThin = 4;
  static const int blockOutline = 5;
  static const int underlineThin = 6;
}

/// One selection of an editor, in editor coordinates (one-based over the
/// raw text, which keeps a leading U+FEFF).
class EditorSelectionValue {
  const EditorSelectionValue({
    required this.anchorLine,
    required this.anchorColumn,
    required this.activeLine,
    required this.activeColumn,
  });

  EditorSelectionValue.fromJson(Map<String, Object?> json)
    : anchorLine = json['selectionStartLineNumber']! as int,
      anchorColumn = json['selectionStartColumn']! as int,
      activeLine = json['positionLineNumber']! as int,
      activeColumn = json['positionColumn']! as int;

  final int anchorLine;
  final int anchorColumn;
  final int activeLine;
  final int activeColumn;

  Range get anchorRange => Range(anchorLine, anchorColumn, activeLine, activeColumn);

  bool equals(EditorSelectionValue other) =>
      anchorLine == other.anchorLine &&
      anchorColumn == other.anchorColumn &&
      activeLine == other.activeLine &&
      activeColumn == other.activeColumn;

  Map<String, Object?> toJson() => {
    'selectionStartLineNumber': anchorLine,
    'selectionStartColumn': anchorColumn,
    'positionLineNumber': activeLine,
    'positionColumn': activeColumn,
  };

  @override
  String toString() =>
      'EditorSelectionValue($anchorLine:$anchorColumn-$activeLine:$activeColumn)';
}

/// `IResolvedTextEditorConfiguration`: what an extension reads as
/// `TextEditor.options`.
class EditorOptions {
  const EditorOptions({
    required this.tabSize,
    required this.indentSize,
    required this.insertSpaces,
    required this.cursorStyle,
    required this.lineNumbers,
    this.originalIndentSize,
  });

  factory EditorOptions.fromJson(Map<String, Object?> json) => EditorOptions(
    tabSize: (json['tabSize']! as num).toInt(),
    indentSize: (json['indentSize']! as num).toInt(),
    insertSpaces: json['insertSpaces']! as bool,
    cursorStyle: (json['cursorStyle']! as num).toInt(),
    lineNumbers: (json['lineNumbers']! as num).toInt(),
    originalIndentSize: (json['originalIndentSize'] as num?)?.toInt(),
  );

  final int tabSize;
  final int indentSize;
  final bool insertSpaces;
  final int cursorStyle;
  final int lineNumbers;
  final int? originalIndentSize;

  bool equals(EditorOptions other) =>
      tabSize == other.tabSize &&
      indentSize == other.indentSize &&
      insertSpaces == other.insertSpaces &&
      cursorStyle == other.cursorStyle &&
      lineNumbers == other.lineNumbers;

  Map<String, Object?> toJson() => {
    'tabSize': tabSize,
    'indentSize': indentSize,
    'insertSpaces': insertSpaces,
    'cursorStyle': cursorStyle,
    'lineNumbers': lineNumbers,
    if (originalIndentSize != null) 'originalIndentSize': originalIndentSize,
  };
}

/// One editor as the UI shows it: the state the actors read and the edits
/// they ask for. An implementation is a live widget (the app's adapter) or
/// an in-memory fake (tests).
abstract interface class TextEditorUi {
  /// The app's document this editor shows.
  EditorDocumentModel get document;

  /// The editor's text, in editor coordinates.
  List<EditorSelectionValue> get selections;

  /// The one-based lines on screen.
  List<Range> get visibleRanges;

  /// The tab size, indentation and cursor style the document is edited
  /// with.
  EditorOptions get options;

  /// Whether the editor's text has the focus.
  bool get isFocused;

  /// Puts the carets at [selections] (editor coordinates).
  void setSelections(List<EditorSelectionValue> selections);

  /// Applies [edits] (editor coordinates, applied simultaneously, like
  /// `executeEdits`) as one undo step; [undoStopBefore]/[undoStopAfter]
  /// close the undo step before and after them; [eol] sets the document's
  /// end-of-line first (`pushEOL`).
  void applyEdits(
    List<({Range range, String? text})> edits, {
    required bool undoStopBefore,
    required bool undoStopAfter,
    String? eol,
  });

  /// Inserts the snippet [text] (TextMate snippet syntax, as
  /// `SnippetController2.insert` takes it) in place of each of [ranges]
  /// (editor coordinates), its tab stops then active.
  void insertAtRanges(
    String text,
    List<Range> ranges, {
    required bool undoStopBefore,
    required bool undoStopAfter,
  });

  /// Scrolls [range] into view as [revealType] asks (`TextEditorRevealType`).
  void revealRange(Range range, int revealType);

  /// Changes the document's indentation and the editor's own options
  /// (cursor style, line numbers). [detectIndentation] seeds the value
  /// from the text (`tabSize: 'auto'`).
  void updateOptions({
    int? tabSize,
    int? indentSize,
    bool? insertSpaces,
    int? cursorStyle,
    int? lineNumbers,
    bool detectIndentation,
  });

  void focus();

  /// The editor's decorations by type, when it can paint them.
  EditorDecorationsController? get decorations;

  /// Lets this editor go: the app's controller is kept by the app.
  void release();
}

/// The workbench's editors: which exist, which is active, and how one is
/// shown, hidden, moved or closed. Ported from the parts of `IEditorService`,
/// `ICodeEditorService` and `IEditorGroupsService` the document/editor
/// actors use.
abstract interface class TextEditorHost implements Listenable {
  /// The document an editor shows, by the app's path (null for an editor
  /// with no text: a media preview).
  String? pathOfEditor(String editorId);

  /// The ids of the editors in the order they were added.
  List<String> get editorIds;

  /// The active editor's id, or null.
  String? get activeEditorId;

  /// The editor's state, or null once it is gone.
  TextEditorUi? uiOf(String editorId);

  /// The editor's column (`EditorGroupColumn`, one-based); null when it is
  /// not in a group the tab model has.
  int? columnOf(String editorId);

  /// Shows/creates the editor of [path]; the editor's id, when it shows
  /// the text. [column] is an `EditorGroupColumn`.
  Future<String?> showTextDocument(
    String path, {
    int? column,
    bool preserveFocus = false,
    bool preview = false,
    EditorSelectionValue? selection,
  });

  /// Brings the existing editor [editorId] forward.
  Future<void> showEditor(String editorId, {int? column});

  /// Closes [editorId]'s tab.
  Future<void> hideEditor(String editorId);
}

/// The tabs the tab model is built from.
class EditorTabInfo {
  const EditorTabInfo({
    required this.tabId,
    required this.isActive,
    required this.isPinned,
    required this.isPreview,
    required this.isDirty,
    required this.label,
    this.path,
    this.uri,
    this.modifiedUri,
    this.originalUri,
    this.groupId = 0,
    this.viewColumn = 1,
  });

  final String tabId;
  final bool isActive;
  final bool isPinned;
  final bool isPreview;
  final bool isDirty;

  /// The tab's name (`Tab.label`).
  final String label;

  /// The document the tab shows, when it shows text.
  final String? path;

  /// The resource of the tab's input, for the tab model's DTO.
  final VsUri? uri;

  /// A diff tab's two sides, when it has them.
  final VsUri? modifiedUri;
  final VsUri? originalUri;

  /// The tab's editor group (BaoCode has one: 0).
  final int groupId;

  /// The group's `EditorGroupColumn` (one-based).
  final int viewColumn;

  bool get isDiff => modifiedUri != null && originalUri != null;
}

/// The tab strip as `MainThreadEditorTabs` sends it: the tabs and their
/// groups, the operations on them, and the three operations the extension
/// can ask for.
abstract interface class EditorTabsHost implements Listenable {
  /// Every tab, in order, with its group.
  List<EditorTabInfo> get tabs;

  /// The group ids present, in order (BaoCode has one: `0`); the active
  /// one first.
  List<int> get groupIds;

  /// The group that is active.
  int get activeGroupId;

  /// Fires the `TabOperation`s of the tab model (`$acceptTabOperation`).
  Stream<Map<String, Object?>> get tabOperations;

  /// Whether a tab with [tabId] exists.
  bool hasTab(String tabId);

  /// Moves [tabId] to [index] of [column]'s group (or of its own).
  void moveTab(String tabId, int index, {int? column, bool? preserveFocus});

  /// Closes [tabIds]' tabs; whether they all closed.
  Future<bool> closeTabs(List<String> tabIds, {bool? preserveFocus});

  /// Closes [column]'s editor group; whether it closed.
  Future<bool> closeGroup(int column, {bool? preserveFocus});
}

/// A resource the extension host asks to open (see
/// `MainThreadDocuments.$tryOpenDocument`).
abstract interface class DocumentOpener {
  /// Opens [path] (a `file:` resource) without showing it, and answers the
  /// path the editor really opened.
  Future<String> openPath(String path, {String? encoding});

  /// Opens a new, unsaved document ([`$tryCreateDocument`]): the URI it
  /// got. [name] is the untitled file's name (`Untitled-1`) when given.
  Future<VsUri> createUntitled({
    String? name,
    String? languageId,
    String? content,
    String? encoding,
  });
}

/// Reads a resource the editor has not opened, for `file:` and other
/// schemes (`MainThreadDocuments._handleAsResourceInput`).
abstract interface class ExtensionDocumentReader {
  /// The bytes of [uri]'s file.
  Future<Uint8List> readFile(VsUri uri);

  /// Whether [uri] exists.
  Future<bool> exists(VsUri uri);
}

/// `ILanguageService` as the document/editor actors use it.
abstract interface class DocumentLanguagePort implements Listenable {
  /// The VS Code language id `file:` [path] is opened as; [firstLine] when
  /// the file name is not enough.
  String languageIdFor(String path, {String? firstLine});

  /// Every registered language id.
  List<String> get languageIds;

  /// Whether [languageId] is registered.
  bool isRegistered(String languageId);

  /// The language id for a language's name or alias, ignoring case.
  String? languageIdByName(String name);

  /// Whether the user can pick a language for a document
  /// (`workbench.action.editor.changeLanguageMode`).
  bool get canPickLanguage;

  /// Asks the user for a language id for [path]; null when cancelled.
  Future<String?>? pickLanguage(String path, {String? current});
}

/// The user's answer to "apply this refactoring?".
abstract interface class WorkspaceEditConfirmer {
  /// Shows [message] and [detail] (`Window.showInformationMessage` with a
  /// Continue button); whether the user confirmed.
  Future<bool> confirm(String message, String detail);
}

