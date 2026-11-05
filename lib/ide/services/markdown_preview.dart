// Markdown files shown as their preview, in the editor's place (after
// VS Code's markdown-language-features `preview`, here the editor's own
// pane: markdown_preview.dart), or as their source where switched to it,
// which the window keeps; and the files pasted or dropped into a markdown
// document, put beside it and linked to (markdown_paste.dart).

import 'dart:async';
import 'dart:collection';

import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart'
    show EditorSurfaceController;
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../chat/composer/composer_files.dart' show ComposerFile;
import '../../chat/composer/file_drop.dart';
import '../../l10n/l10n.dart';
import '../../workspace/editor_launcher.dart';
import '../../workspace/window_controls.dart';
import '../file_service.dart';
import '../host_paths.dart';
import '../ide_dialog.dart';
import '../ide_editor_placeholder.dart' show ideFormatSize;
import '../ide_notifications.dart';
import '../ide_workspace.dart';
import '../markdown/markdown_paste.dart';
import '../markdown/markdown_preview.dart';
import '../workbench/contributions.dart';
import '../workbench/storage.dart';

class MarkdownPreviewService extends ChangeNotifier
    implements WorkbenchStorageParticipant {
  MarkdownPreviewService({
    required this.host,
    required this.storage,
    required this._workspace,
    required this._caret,
    required this._clipboard,
    required this._insertInEditor,
  });

  final WorkbenchHost host;
  final WorkbenchStorage storage;

  /// The window's workspace (another after one is swapped).
  final IdeWorkspace Function() _workspace;

  /// Where the active editor's caret is.
  final Position Function() _caret;

  /// What a paste reads (tests replace it).
  final MarkdownClipboard Function() _clipboard;

  /// Inserts text at the active editor's caret.
  final void Function(String text) _insertInEditor;

  IdeWorkspace get _ws => _workspace();

  /// The markdown files shown as their source rather than their preview,
  /// the last switched last (a few hundred kept, with the window's state).
  final LinkedHashSet<String> _sources = LinkedHashSet();
  static const _keptSources = 300;

  /// Whether [doc] can show as a markdown preview: a markdown file's own
  /// tab (or a revision's), not its diff.
  bool hasPreview(IdeDocument doc) =>
      isMarkdownPath(doc.path) &&
      doc.diff == null &&
      !doc.isMedia &&
      doc.openError == null;

  /// Whether [doc] shows as its preview: markdown files do, unless switched
  /// to their source.
  bool previewing(IdeDocument? doc) =>
      doc != null && hasPreview(doc) && !_sources.contains(doc.path);

  /// The active document's preview, while it shows.
  IdeMarkdownPreviewState? get preview => switch (_ws.active) {
    final active? => previewOf(active),
    null => null,
  };

  /// [doc]'s preview, while it shows.
  IdeMarkdownPreviewState? previewOf(IdeDocument doc) =>
      GlobalObjectKey<IdeMarkdownPreviewState>(doc).currentState;

  /// Whether the project's files are this machine's (not a remote
  /// host's).
  bool get _local => _ws.files is! IdeHostFiles;

  /// Shows the active markdown document's preview, or its source: in
  /// either, where the other's caret was (or about where it was scrolled
  /// to), or the source at [at] (a line and column, one-based).
  Future<void> setPreview(bool on, {({int line, int column})? at}) async {
    final workspace = _ws;
    final doc = workspace.active;
    if (doc == null || !hasPreview(doc) || previewing(doc) == on) return;
    int? line;
    var column = 1;
    if (on) {
      await host.flushEditor();
      // The preview shows first the caret's line in its source.
      workspace.keepViewState(
        doc,
        (kept) => kept.copyWith(previewLine: _caret().lineNumber),
      );
      _sources.remove(doc.path);
    } else {
      // The preview's caret, where it was put; else the line at its top.
      final caret = at ?? preview?.caret;
      line = caret?.line ?? preview?.topLine;
      column = caret?.column ?? 1;
      _sources
        ..remove(doc.path)
        ..add(doc.path);
      while (_sources.length > _keptSources) {
        _sources.remove(_sources.first);
      }
    }
    if (host.context == null) return;
    notifyListeners();
    storage.changed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.context == null || !identical(_ws.active, doc)) return;
      if (line != null) host.revealLine(line, column);
      if (at != null || line == null) host.focusEditor();
    });
  }

  /// Opens the file a markdown preview's link goes to: at its line for
  /// `#L12`, at its heading for a markdown file's `#anchor`.
  Future<void> openLinked(String path, String? fragment) async {
    final line = switch (RegExp(r'^L(\d+)').firstMatch(fragment ?? '')) {
      final match? => int.parse(match[1]!),
      null => null,
    };
    await host.openFile(path, line: line, focusEditor: true);
    if (host.context == null || line != null || fragment == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.context != null) preview?.revealAnchor(fragment);
    });
  }

  /// [doc]'s preview.
  Widget build(IdeDocument doc) {
    final workspace = _ws;
    final files = workspace.files;
    return IdeMarkdownPreview(
      key: GlobalObjectKey<IdeMarkdownPreviewState>(doc),
      path: doc.path,
      model: doc.model,
      readOnly: doc.readOnly,
      readBytes: switch (files) {
        final IdeHostFiles files => files.readBytes,
        _ => readFileBytes,
      },
      // A remote project's paths are its host's.
      pathContext: _local ? p.context : hostPathsFor(doc.path),
      // Where it was.
      initialLine: workspace.viewStateOf(doc).previewLine,
      onLeave: (line) {
        if (line == null) return;
        workspace.keepViewState(
          doc,
          (kept) => kept.copyWith(previewLine: line),
        );
      },
      onEdited: () => workspace.notifyDocumentChanged(doc),
      // Pasted in while it shows, so while the window does.
      onPaste: doc.readOnly ? null : () => _paste()!.paste(doc.path),
      onOpenFile: (path, fragment) => unawaited(openLinked(path, fragment)),
      onOpenExternal: (uri) => unawaited(openExternal(uri.toString())),
      onReveal: _local && WindowControls.canRevealInFileManager
          ? (path) => unawaited(WindowControls.revealInFileManager(path))
          : null,
    );
  }

  /// Pastes and drops of files into the project's markdown documents.
  MarkdownPaste? _paste() {
    final context = host.context;
    if (context == null) return null;
    final l10n = context.l10n;
    final workspace = _ws;
    return MarkdownPaste(
      files: workspace.files,
      l10n: l10n,
      root: workspace.hasFolder ? workspace.root : null,
      // A remote project's paths are its host's; the clipboard's files
      // are this machine's, uploaded there.
      context: _local
          ? p.context
          : hostPathsFor(workspace.hasFolder ? workspace.root : ''),
      remote: !_local,
      clipboard: _clipboard(),
      confirmLarge: (name, size) async {
        final context = host.context;
        if (context == null) return false;
        final pick = await showIdeDialog(
          context,
          type: IdeDialogType.question,
          message: l10n.markdownPasteLargeTitle,
          detail: l10n.markdownPasteLargeMessage(name, ideFormatSize(size)),
          buttons: [l10n.markdownPasteLargeConfirm],
        );
        return pick == 0;
      },
      report: (message) {
        if (host.context != null) {
          workspace.notifications.notify(IdeSeverity.error, message);
        }
      },
    );
  }

  /// A paste in [doc]'s source: a markdown document's files and pictures
  /// put beside it and linked to (see [pasteMarkdownLinks]).
  Future<bool> pasteInEditor(
    IdeDocument doc,
    EditorSurfaceController editor,
  ) async {
    final paste = _paste();
    if (!isMarkdownPath(doc.path) || doc.readOnly || paste == null) {
      return false;
    }
    final workspace = _ws;
    final version = doc.model.version;
    final pasted = await pasteMarkdownLinks(
      editor,
      () => paste.paste(doc.path),
      onMoved: () {
        if (host.context case final context?) {
          workspace.notifications.notify(
            IdeSeverity.info,
            context.l10n.markdownPasteMoved,
          );
        }
      },
    );
    if (doc.model.version != version) workspace.notifyDocumentChanged(doc);
    return pasted;
  }

  /// [editor], taking the files other apps drop on it when it is a
  /// markdown document's (see [dropOn]).
  Widget drops(IdeDocument? active, Widget editor) {
    if (active == null ||
        !isMarkdownPath(active.path) ||
        active.readOnly ||
        active.diff != null ||
        active.openError != null) {
      return editor;
    }
    return FileDropRegion(delegate: _drop, child: editor);
  }

  late final _drop = _MarkdownDrop(
    (position, files) => unawaited(dropOn(position, files)),
  );

  /// Files dropped from other apps on the active markdown document: put
  /// beside it and linked to, at the caret, or after the block they were
  /// dropped on.
  Future<void> dropOn(Offset position, List<ComposerFile> files) async {
    final workspace = _ws;
    final doc = workspace.active;
    final paste = _paste();
    if (doc == null ||
        !isMarkdownPath(doc.path) ||
        doc.readOnly ||
        paste == null) {
      return;
    }
    final outcome = await paste.drop(doc.path, files);
    if (host.context == null || outcome is! MarkdownPasteLinks) return;
    if (!identical(workspace.active, doc)) {
      insertMarkdownAtEnd(doc.model, outcome.text);
      workspace.notifyDocumentChanged(doc);
    } else if (preview case final preview?) {
      preview.insert(outcome.text, position: position);
    } else {
      _insertInEditor(outcome.text);
    }
  }

  @override
  void restoreState(Map<String, Object?> kept) {
    if (kept['markdownSource'] case final List<Object?> paths) {
      _sources.addAll(paths.whereType<String>());
    }
  }

  @override
  void saveState(Map<String, Object?> into) {
    if (_sources.isNotEmpty) into['markdownSource'] = [..._sources];
  }
}

/// What a markdown document's editor does with files other apps drop on
/// it: [onDrop].
class _MarkdownDrop implements FileDropDelegate {
  _MarkdownDrop(this.onDrop);

  final void Function(Offset position, List<ComposerFile> files) onDrop;

  @override
  void fileDragOver(Offset position, List<ComposerFile> files) {}

  @override
  void fileDragLeave() {}

  @override
  void fileDrop(Offset position, List<ComposerFile> files) =>
      onDrop(position, files);
}
