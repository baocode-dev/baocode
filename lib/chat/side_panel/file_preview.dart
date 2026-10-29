import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/language_overrides.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:path/path.dart' as p;

import '../../base/shown_when_ready.dart';
import '../../base/smooth_scroll.dart';
import '../../ide/file_service.dart';
import '../../ide/ide_agent_edits.dart';
import '../../ide/ide_code_diff.dart';
import '../../ide/ide_code_editor.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_image_preview.dart';
import '../../ide/ide_status_bar.dart' show IdeLanguageNames;
import '../../ide/language_mode.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_editor_placeholder.dart' show ideFormatSize;
import '../../ide/markdown/markdown_paste.dart';
import '../../ide/markdown/markdown_preview.dart';
import '../../l10n/l10n.dart';
import '../../platform/app_platform.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/editor_launcher.dart' show openExternal;
import '../../workspace/window_controls.dart';
import '../composer/composer_files.dart' show ComposerFile, CopiedCode;
import '../composer/file_drop.dart';
import '../widgets/code_citation.dart' show CodeColorizer;
import '../widgets/hover_builder.dart';
import '../widgets/hover_scrollbar.dart';
import 'file_edit.dart';
import 'file_link.dart';
import 'file_open.dart';
import 'line_diff.dart';
import '../../base/safe_selection_indexes.dart';

/// A file in the side panel: its text in the IDE's editor, to edit, search
/// and save (Cmd+S, Ctrl+S), the lines asked for marked and scrolled to,
/// the agent's change pending in it ([agentEdit]) shown as the IDE shows it,
/// each part to keep or undo; its changes against the text before the
/// agent changed it, read only; a markdown file rendered (or its text); an
/// image. A bar over it names it, with [actions] (Open in Fast Ide) at its
/// end, after the agent's change's own (see [IdeAgentEditActions]).
class FilePreview extends StatefulWidget {
  const FilePreview({
    super.key,
    required this.request,
    required this.files,
    this.root,
    this.readBytes,
    this.paths,
    this.colorize,
    this.reveal = 0,
    this.onOpenFile,
    this.actions = const [],
    this.language = true,
    this.edit,
    this.onEdit,
    this.highlights,
    this.formatter,
    this.agentEdit,
    this.onOpenAgentChange,
  });

  final FileOpenRequest request;

  /// The agent's change pending in the file, shown in its text where it is
  /// edited here.
  final IdeAgentEdit? agentEdit;

  /// Opens the next file whose agent change is pending, at it, once this
  /// one's is all kept or undone (see [IdeAgentHunks.open]).
  final ValueChanged<String>? onOpenAgentChange;

  /// The file's text as edited already (its tab's), to go on with: read
  /// anew in it where it is not changed.
  final SidePanelFileEdit? edit;

  /// Takes the edit made once the file is read, to keep past the preview;
  /// the preview's own, gone with it, when null.
  final ValueChanged<SidePanelFileEdit>? onEdit;

  /// Where the editor's highlighting is kept past the preview, for its tab
  /// shown again to be colored at once; the editor's own when null.
  final IdeCodeHighlights? highlights;

  /// Formats the file with the project's language servers.
  final IdeTextFormatter? formatter;

  /// Reads it, on the project's host.
  final IdeFileService files;

  /// Where the agent works: the bar names the file from there.
  final String? root;

  /// Reads an image's bytes; this machine's [readFileBytes] when null.
  final Future<Uint8List> Function(String path)? readBytes;

  /// How the host spells paths; this machine's when null.
  final p.Context? paths;
  final CodeColorizer? colorize;

  /// Goes up as the same file is asked for again: scrolls back to the
  /// lines asked for.
  final int reveal;

  /// Opens a file a markdown file's link goes to.
  final ValueChanged<FileOpenRequest>? onOpenFile;

  /// At the end of its bar.
  final List<Widget> actions;

  /// Whether its bar names the file's language, to change it.
  final bool language;

  /// Past this many lines, the text is not colored.
  static const maxColoredLines = 5000;

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

sealed class _Loaded {
  const _Loaded();
}

final class _Text extends _Loaded {
  const _Text(this.lines, {this.noOriginal = false});

  final List<String> lines;

  /// Its changes were asked for, but the text before is not known.
  final bool noOriginal;
}

final class _Diff extends _Loaded {
  const _Diff(this.original, this.modified, {this.deleted = false});

  final String original;
  final String modified;
  final bool deleted;
}

final class _Failed extends _Loaded {
  const _Failed(this.error);

  final Object error;
}

class _FilePreviewState extends State<FilePreview> {
  _Loaded? _loaded;

  /// By line (or row, for a diff), in the editor's colors once colored.
  List<List<TextSpan>?> _colors = const [];

  /// A markdown file's text rather than it rendered.
  bool _source = false;

  /// A markdown file's text, rendered: its edit's, as it is edited.
  EditorDocumentModel? _markdown;
  int _load = 0;

  /// Lets it be shown in place of the file before (see [ShownWhenReady]):
  /// once read.
  VoidCallback? _release;

  /// The file's text in the editor, once read; none for changes.
  SidePanelFileEdit? _edit;

  /// The text the lines asked for were marked in: unmarked once edited.
  Object? _markedIn;
  final _editor = GlobalKey<IdeCodeEditorState>();

  /// [FilePreview.agentEdit] in the editor, and where it is among its parts.
  IdeAgentDiff? _agent;
  late final _hunks = IdeAgentHunks(
    open: (path) => widget.onOpenAgentChange?.call(path),
  );

  FileOpenRequest get _request => widget.request;

  /// An image shows as it is, its changes too: there is no text to compare.
  bool get _image => ideIsImagePath(_request.path);

  /// A markdown file rendered: its changes too, as the file is after them
  /// (its changes a click away), unless it was deleted.
  bool get _isMarkdown =>
      isMarkdownPath(_request.path) &&
      switch (_loaded) {
        _ when !_request.diff => true,
        _Text() || _Diff(deleted: false) => true,
        _ => false,
      };

  /// The file's own text shows, to edit: not its changes, nor the index's,
  /// nor what is only shown ([FileOpenRequest.readOnly]).
  bool get _editable =>
      !_request.diff && _request.modified == null && !_request.readOnly;

  @override
  void initState() {
    super.initState();
    if (widget.edit case final edit? when _editable) _attach(edit);
    EditorLanguageOverrides.instance.addListener(_languageModesChanged);
    IdeLanguageNames.ensureLoaded(() {
      if (mounted) setState(() {});
    });
    _start();
  }

  /// A language picked for a file (Change Language Mode): its lines
  /// colored again; the editor colors its own.
  void _languageModesChanged() {
    if (!mounted) return;
    setState(() {});
    if (_edit == null && !_image) unawaited(_read(++_load));
  }

  void _attach(SidePanelFileEdit edit) {
    _edit = edit..addListener(_editChanged);
  }

  /// Lets go of the edit; disposes it unless its tab keeps it.
  void _detach() {
    _dropAgent();
    final edit = _edit;
    _edit = null;
    if (edit == null) return;
    edit.removeListener(_editChanged);
    if (widget.onEdit == null && !identical(edit, widget.edit)) edit.dispose();
  }

  void _editChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(FilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.request;
    if (old.path != _request.path ||
        old.diff != _request.diff ||
        old.original != _request.original ||
        old.modified != _request.modified ||
        oldWidget.files != widget.files) {
      _dropMarkdown();
      _detach();
      if (widget.edit case final edit? when _editable) _attach(edit);
      _start();
    } else if (oldWidget.reveal != widget.reveal && !_image) {
      // Asked for again (the agent wrote it again, say): read anew, what
      // shows kept until then.
      unawaited(_read(++_load));
    }
  }

  @override
  void dispose() {
    EditorLanguageOverrides.instance.removeListener(_languageModesChanged);
    _dropMarkdown();
    _detach();
    _hunks.dispose();
    _ready();
    super.dispose();
  }

  /// [FilePreview.agentEdit] in the editor of the file's text, as long as
  /// both are there.
  IdeAgentDiff? _syncAgent() {
    final edit = _edit;
    final agentEdit = widget.agentEdit;
    if (edit == null || agentEdit == null || !_editable) {
      _dropAgent();
      return null;
    }
    if (_agent case final agent?
        when identical(agent.controller, edit.controller)) {
      return agent..edit = agentEdit;
    }
    _dropAgent();
    return _agent = IdeAgentDiff(
      agentEdit,
      edit.controller,
      onChanged: _agentChanged,
      save: () async {
        await edit.save();
        if (edit.dirty && edit.error != null) throw edit.error!;
      },
      view: () => _editor.currentState?.view,
      hunks: _hunks,
    );
  }

  void _dropAgent() {
    _agent?.dispose();
    _agent = null;
  }

  /// The change's diff computed anew, its original highlighted: shown,
  /// after the build if in one.
  void _agentChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// The rendered markdown's own text let go of; not its edit's.
  void _dropMarkdown() {
    if (!identical(_markdown, _edit?.controller.document)) {
      _markdown?.dispose();
    }
    _markdown = null;
  }

  void _start() {
    final load = ++_load;
    _loaded = null;
    _colors = const [];
    // The agent's change shows in the text.
    if (_request.agentChange && isMarkdownPath(_request.path)) _source = true;
    _dropMarkdown();
    if (_image) return;
    // Its tab's edit shows as it is while the file is read anew.
    if (_edit case final edit?) {
      _loaded = const _Text([]);
      if (_isMarkdown) _markdown = edit.controller.document;
    } else {
      _release ??= ShownWhenReady.hold(context);
    }
    unawaited(_read(load));
  }

  void _ready() {
    _release?.call();
    _release = null;
  }

  Future<void> _read(int load) async {
    final request = _request;
    String? text;
    Object? error;
    try {
      text =
          await (request.modified?.call() ?? widget.files.read(request.path));
    } catch (e) {
      error = e;
    }
    String? original;
    if (request.diff) {
      try {
        original = await request.original?.call();
      } catch (_) {
        original = null;
      }
    }
    if (!mounted || load != _load) return;
    // A diff holds it back itself, until compared and colored.
    _ready();
    final _Loaded loaded;
    if (request.diff && original != null) {
      if (text == null && error is! IdeFileNotFoundException) {
        loaded = _Failed(error!);
      } else {
        loaded = _Diff(original, text ?? '', deleted: text == null);
      }
    } else if (text == null) {
      loaded = _Failed(error!);
    } else {
      loaded = _Text(diffLines(text), noOriginal: request.diff);
    }
    setState(() {
      _loaded = loaded;
      if (_editable && text != null) _edited(text);
      if (_isMarkdown && text != null) {
        _dropMarkdown();
        _markdown = _edit?.controller.document ?? EditorDocumentModel(text);
      }
    });
    if (_edit != null) return _reveal();
    unawaited(_colorize(load, loaded, original, text));
  }

  /// The file's [text], read: in its edit, made now unless there is one.
  void _edited(String text) {
    if (_edit case final edit?) return edit.reload(text);
    final edit = SidePanelFileEdit(
      path: _request.path,
      files: widget.files,
      text: text,
    );
    _attach(edit);
    widget.onEdit?.call(edit);
  }

  /// The lines asked for, from their first's start to their last's end,
  /// in the edit's text; none when none were.
  (int, int)? get _range {
    final range = _request.range;
    final snapshot = _edit?.controller.document.snapshot;
    if (range == null || snapshot == null) return null;
    final count = snapshot.lineStarts.length;
    final first = (range.start - 1).clamp(0, count - 1);
    final last = (range.end - 1).clamp(first, count - 1);
    return (snapshot.lineStarts[first], snapshot.contentEnds[last]);
  }

  /// Marks the lines asked for and scrolls to them, the caret at their
  /// start; the agent's change's part asked for, unmarked.
  void _reveal() {
    final edit = _edit;
    if (edit != null && _request.agentChange) {
      _markedIn = null;
      if (_isMarkdown && !_source) setState(() => _source = true);
      _hunks.reveal(line: _request.range?.start);
      return;
    }
    final range = _range;
    if (edit == null || range == null) return;
    final (start, end) = range;
    _markedIn = edit.controller.document.snapshot;
    edit.controller.select(start, start);
    // Once built, the first time.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _editor.currentState?.revealRange(start, end),
    );
  }

  Future<void> _colorize(
    int load,
    _Loaded loaded,
    String? original,
    String? text,
  ) async {
    final colorize = widget.colorize;
    if (colorize == null) return;
    final path = _request.path;
    Future<List<List<TextSpan>>?> colors(String? code) async {
      if (code == null || code.isEmpty) return null;
      if (diffLines(code).length > FilePreview.maxColoredLines) return null;
      try {
        return await colorize(path, code);
      } catch (_) {
        return null;
      }
    }

    final List<List<TextSpan>?> byRow;
    switch (loaded) {
      case _Text(:final lines):
        final now = await colors(text);
        if (now == null) return;
        byRow = [for (var i = 0; i < lines.length; i++) now.elementAtOrNull(i)];
      // The diff editor highlights its own.
      case _Diff() || _Failed():
        return;
    }
    if (!mounted || load != _load) return;
    setState(() => _colors = byRow);
  }

  @override
  Widget build(BuildContext context) {
    _syncAgent();
    return ColoredBox(
      color: AppColors.code,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(context),
          ?_notice(context),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final l10n = context.l10n;
    final paths = widget.paths ?? p.context;
    final root = widget.root;
    final path = _request.path;
    final shown = root != null && paths.isWithin(root, path)
        ? paths.relative(path, from: root)
        : path;
    final range = _request.range;
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.partBorder)),
      ),
      child: Row(
        children: [
          FileIcon(path, size: 14),
          const SizedBox(width: 6),
          Expanded(
            // The whole path, which the bar may cut short.
            child: IdeHover(
              message: path,
              followMouse: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: shown),
                    if (range != null &&
                        !_request.diff &&
                        !_request.agentChange)
                      TextSpan(
                        text: '  ${range.label}',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          ),
          if (!_image && widget.language)
            _TextButton(
              label: IdeLanguageNames.forPath(path),
              tooltip: l10n.languageModeChange,
              onPressed: () => unawaited(changeLanguageMode(context, path)),
            ),
          if (_isMarkdown && _markdown != null)
            _TextButton(
              label: _source
                  ? l10n.sidePanelPreview
                  : _loaded is _Diff
                  ? l10n.sidePanelChanges
                  : l10n.sidePanelSource,
              onPressed: () => setState(() => _source = !_source),
            ),
          if ((widget.agentEdit, _agent) case (final edit?, _?)
              when !_isMarkdown || _source)
            IdeAgentEditActions(edit: edit, hunks: _hunks),
          ...widget.actions,
        ],
      ),
    );
  }

  Widget? _notice(BuildContext context) {
    final l10n = context.l10n;
    final text = switch (_loaded) {
      _ when _edit?.error != null => localizedFileError(l10n, _edit!.error!),
      _Text(noOriginal: true) => l10n.sidePanelNoOriginal,
      _Diff(deleted: true) => l10n.sidePanelDeleted,
      _Diff(:final original, :final modified) when original == modified =>
        l10n.sidePanelUnchanged,
      _ => null,
    };
    if (text == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.surface,
      child: Text(
        text,
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_image) {
      return IdeImagePreview(path: _request.path, read: widget.readBytes);
    }
    switch (_loaded) {
      case null:
        return const SizedBox.shrink();
      case _Failed(:final error):
        return _Message(
          icon: error is IdeFileNotFoundException
              ? Codicons.warning
              : Codicons.error,
          text: localizedFileError(context.l10n, error),
        );
      case _Text() || _Diff() when _markdown != null && !_source:
        return _markdownPreview(_markdown!);
      case _Diff(:final original, :final modified, :final deleted):
        return IdeCodeDiff(
          // Asked for again: scrolled back to the lines asked for.
          key: ValueKey(('diff', _request.path, widget.reveal)),
          path: _request.path,
          original: original,
          modified: modified,
          line: _request.range?.start,
          highlights: widget.highlights,
          // Lines of the file as it is now.
          onCopy: deleted
              ? null
              : (text, start, end) => _copied(start, end, text),
        );
      case _Text(:final lines):
        if (_edit case final edit?) return _editing(edit);
        final range = _request.range;
        final gutter = _gutter(context, lines.length);
        return _Lines(
          key: ValueKey(('text', _request.path)),
          count: lines.length,
          lineHeight: _lineHeight(context),
          reveal: widget.reveal,
          target: range == null ? null : range.start - 1,
          width: _widthOf(context, lines, () => lines) + gutter + 20,
          onCopy: (first, last, text) => _copied(first + 1, last + 1, text),
          row: (context, i, sideways) => _LineRow(
            number: i + 1,
            text: lines[i],
            colors: _colors.elementAtOrNull(i),
            gutter: gutter,
            sideways: sideways,
            marked: range != null && i + 1 >= range.start && i + 1 <= range.end,
          ),
        );
    }
  }

  /// A markdown file rendered: its own text, edited here as in its source;
  /// its changes', as it is after them, only shown.
  Widget _markdownPreview(EditorDocumentModel model) {
    // The file's own text, its edit's: edited here, as in its source.
    final edit = _edit;
    final editable =
        edit != null &&
        !_request.agentChange &&
        identical(model, edit.controller.document);
    final preview = IdeMarkdownPreview(
      key: _previewKey,
      path: _request.path,
      model: model,
      readBytes: widget.readBytes ?? readFileBytes,
      pathContext: widget.paths,
      readOnly: !editable,
      // Its source's editor told, which keeps whether it is saved.
      onEdited: edit?.controller.syncFromDocument,
      // Pictures and files pasted: copied beside it, linked to.
      onPaste: editable ? () => _markdownPaste().paste(_request.path) : null,
      initialLine: _request.range?.start,
      onOpenFile: _openLinked,
      onOpenExternal: (uri) => unawaited(openExternal(uri.toString())),
      // This machine's files only, not a remote project's host's.
      onReveal:
          widget.files is! IdeHostFiles && WindowControls.canRevealInFileManager
          ? (path) => unawaited(WindowControls.revealInFileManager(path))
          : null,
    );
    if (!editable) return preview;
    // Files dropped on it from other apps: as pasted, where they are
    // let go.
    return _saved(
      edit,
      FileDropRegion(delegate: _markdownDrop, child: preview),
    );
  }

  /// [child], where [edit] is edited, saving it with the IDE's keys.
  Widget _saved(SidePanelFileEdit edit, Widget child) => CallbackShortcuts(
    bindings: {
      AppPlatform.isMacOS
          ? const SingleActivator(LogicalKeyboardKey.keyS, meta: true)
          : const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          unawaited(edit.save()),
    },
    child: child,
  );

  /// The file's text in the IDE's editor, the lines asked for marked until
  /// it is edited; saved with the IDE's keys.
  Widget _editing(SidePanelFileEdit edit) {
    final range = _range;
    final marked =
        range != null &&
        !_request.agentChange &&
        identical(_markedIn, edit.controller.document.snapshot);
    return _saved(
      edit,
      IdeCodeEditor(
        key: _editor,
        controller: edit.controller,
        path: _request.path,
        highlights: widget.highlights,
        interfaceSized: false,
        formatter: widget.formatter,
        agent: _agent,
        decorations: [
          if (marked)
            EditorDecoration(
              start: range.$1,
              end: range.$2,
              isWholeLine: true,
              backgroundColor: themeColors['editor.rangeHighlightBackground'],
            ),
        ],
      ),
    );
  }

  /// Lines [start] to [end] copied, as [text]: pasted into the chat's
  /// composer, they go in as a reference to those lines of the file, as
  /// the IDE's editor's do.
  void _copied(int start, int end, String text) => CopiedCode.record(
    path: _request.path,
    start: start,
    end: end,
    code: text,
  );

  // --- A markdown file's pastes and drops ------------------------------------------

  /// Its preview: a new one for another file, or the same asked for again
  /// (scrolled back to the lines asked for).
  GlobalKey<IdeMarkdownPreviewState> get _previewKey {
    final shows = (_request.path, widget.reveal);
    if (shows != _previewShows) {
      _previewShows = shows;
      _previewKeyNow = GlobalKey();
    }
    return _previewKeyNow;
  }

  (String, int)? _previewShows;
  GlobalKey<IdeMarkdownPreviewState> _previewKeyNow = GlobalKey();

  /// Pastes and drops of pictures and files: copied beside the file (to
  /// the project's host, a remote one), as the IDE's preview does.
  MarkdownPaste _markdownPaste() {
    final l10n = context.l10n;
    final files = widget.files;
    final remote = files is IdeHostFiles;
    return MarkdownPaste(
      files: files,
      l10n: l10n,
      root: widget.root,
      context: widget.paths ?? (remote ? p.posix : p.context),
      remote: remote,
      confirmLarge: (name, size) async {
        if (!mounted) return false;
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
        if (!mounted) return;
        unawaited(
          showIdeDialog(
            context,
            type: IdeDialogType.error,
            message: message,
            buttons: const [],
            cancel: l10n.commonOk,
          ),
        );
      },
    );
  }

  late final _markdownDrop = _MarkdownDrop((position, files) async {
    final path = _request.path;
    final outcome = await _markdownPaste().drop(path, files);
    if (!mounted || outcome is! MarkdownPasteLinks) return;
    if (_previewKeyNow.currentState case final preview?
        when _request.path == path) {
      preview.insert(outcome.text, position: position);
    }
  });

  /// A link in a markdown file: to a file beside it.
  void _openLinked(String path, String? fragment) {
    final range = fragment == null
        ? null
        : FileLink.parseHref('x#$fragment')?.range;
    widget.onOpenFile?.call(FileOpenRequest(path, range: range));
  }

  static TextStyle _codeStyle(BuildContext context) =>
      AppFonts.codeStyle(12).copyWith(height: 1.5);

  static TextScaler _codeScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context);

  /// The actual height of one source line, including the configured scaler.
  static double _lineHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _codeStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: _codeScaler(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// The line numbers' width, for [count] lines.
  static double _gutter(BuildContext context, int count) {
    final painter = TextPainter(
      text: TextSpan(text: '$count', style: _codeStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: _codeScaler(context),
    )..layout();
    final width = painter.width + 16;
    painter.dispose();
    return width;
  }

  /// [_width] of [shown]'s lines, kept while they, the font and its scale
  /// are the same: laying out every line of a long file again on each
  /// build (the chat beside it streaming) made it crawl.
  double _widthOf(
    BuildContext context,
    Object shown,
    Iterable<String> Function() lines,
  ) {
    final key = (shown, _codeStyle(context), _codeScaler(context));
    if (_measured case (final kept, final width) when kept == key) {
      return width;
    }
    final width = _width(context, lines());
    _measured = (key, width);
    return width;
  }

  ((Object, TextStyle, TextScaler), double)? _measured;

  /// As wide as the widest rendered line, including wide fallback glyphs.
  /// Only those that may be the widest are laid out: a line's width, in
  /// the code font's columns, is at least its characters and at most a
  /// wide glyph two columns, so no line under half the longest's estimate
  /// can be wider than it.
  static double _width(BuildContext context, Iterable<String> lines) {
    final style = _codeStyle(context);
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: _codeScaler(context),
    );
    int columns(String line) {
      var n = 0;
      for (final unit in line.codeUnits) {
        n += unit == 0x09 ? 4 : (unit < 0x80 ? 1 : 2);
      }
      return n;
    }

    final estimates = [for (final line in lines) (line, columns(line))];
    final most = estimates.fold(0, (most, e) => math.max(most, e.$2));
    var width = 0.0;
    for (final (line, estimate) in estimates) {
      if (line.isEmpty || estimate * 2 < most) continue;
      painter.text = TextSpan(
        text: line.replaceAll('\t', '    '),
        style: style,
      );
      painter.layout();
      width = math.max(width, painter.width);
    }
    painter.dispose();
    return width;
  }
}

/// The lines, built as they come into view, scrolled to [target] (a
/// row, from 0) first and as [reveal] goes up; sideways, as wide as
/// [width] needs.
///
/// Copied, the lines selected go one to a line, and [onCopy] hears which
/// rows (from 0, the first and the last) they are.
class _Lines extends StatefulWidget {
  const _Lines({
    super.key,
    required this.count,
    required this.row,
    required this.width,
    required this.lineHeight,
    this.target,
    this.reveal = 0,
    this.onCopy,
  });

  final int count;
  final Widget Function(
    BuildContext context,
    int index,
    ScrollController sideways,
  )
  row;
  final double width;
  final double lineHeight;
  final int? target;
  final int reveal;
  final void Function(int first, int last, String text)? onCopy;

  @override
  State<_Lines> createState() => _LinesState();
}

class _LinesState extends State<_Lines> {
  final _scroll = SmoothScrollController();
  final _sideways = ScrollController();
  late final _selection = _LinesSelection(
    (first, last, text) => widget.onCopy?.call(first, last, text),
  );

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_Lines oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reveal != widget.reveal ||
        oldWidget.target != widget.target ||
        oldWidget.lineHeight != widget.lineHeight) {
      _reveal();
    }
  }

  /// A few lines over the target, once laid out.
  void _reveal() {
    final target = widget.target;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final offset = (target - 3) * widget.lineHeight;
      _scroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sideways.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The measured width already includes gutters and change markers.
        final width = math.max(constraints.maxWidth, widget.width + 24);
        // Both scrollbars at the edges of the view, not of the lines as
        // wide as the longest; drawn as the editor's are.
        return SelectionArea(
          child: SelectionContainer(
            delegate: _selection,
            child: ScrollbarTheme(
              data: _editorScrollbars(context),
              child: HoverScrollbar(
                controller: _scroll,
                thickness: 14,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.vertical,
                child: HoverScrollbar(
                  controller: _sideways,
                  thickness: 12,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _sideways,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      height: constraints.maxHeight,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemExtent: widget.lineHeight,
                        itemCount: widget.count,
                        itemBuilder: (context, index) => _SelectableRow(
                          index: index,
                          lines: _selection,
                          child: widget.row(context, index, _sideways),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The editor's sliders (`EditorScrollbarPainter`): square, edge to edge,
  /// at least 20 long, in `scrollbarSlider.*` as hovered and dragged.
  static ScrollbarThemeData _editorScrollbars(BuildContext context) =>
      ScrollbarTheme.of(context).copyWith(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              themeColors[states.contains(WidgetState.dragged)
                  ? 'scrollbarSlider.activeBackground'
                  : states.contains(WidgetState.hovered)
                  ? 'scrollbarSlider.hoverBackground'
                  : 'scrollbarSlider.background'],
        ),
        radius: Radius.zero,
        crossAxisMargin: 0,
        mainAxisMargin: 0,
        minThumbLength: 20,
      );
}

/// The selection of [_Lines]: what is selected of each row, one to a line
/// (each row's text is a selection of its own, which the list would run
/// together), and which rows, told as it is copied.
class _LinesSelection extends StaticSelectionContainerDelegate
    with SafeSelectionIndexes {
  _LinesSelection(this.onCopy);

  final void Function(int first, int last, String text) onCopy;

  /// The rows' selected text, as each row gives it while it is asked for.
  final List<(int, String)> _rows = [];

  @override
  SelectedContent? getSelectedContent() {
    _rows.clear();
    final content = super.getSelectedContent();
    if (content == null || _rows.isEmpty) return content;
    final rows = [..._rows]..sort((a, b) => a.$1.compareTo(b.$1));
    _rows.clear();
    // An empty line selects nothing of its own: kept, between the others.
    final byRow = {for (final (row, text) in rows) row: text};
    final text = [
      for (var row = rows.first.$1; row <= rows.last.$1; row++)
        byRow[row] ?? '',
    ].join('\n');
    onCopy(rows.first.$1, rows.last.$1, text);
    return SelectedContent(plainText: text);
  }
}

/// The row [index] of [_Lines], whose selected text it tells [lines].
class _SelectableRow extends StatefulWidget {
  const _SelectableRow({
    required this.index,
    required this.lines,
    required this.child,
  });

  final int index;
  final _LinesSelection lines;
  final Widget child;

  @override
  State<_SelectableRow> createState() => _SelectableRowState();
}

class _SelectableRowState extends State<_SelectableRow> {
  late final _selection = _RowSelection(widget);

  @override
  void didUpdateWidget(_SelectableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selection.row = widget;
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _selection, child: widget.child);
}

class _RowSelection extends StaticSelectionContainerDelegate
    with SafeSelectionIndexes {
  _RowSelection(this.row);

  _SelectableRow row;

  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content != null) row.lines._rows.add((row.index, content.plainText));
    return content;
  }
}

/// One line: its number and its text, on the editor's range highlight
/// where it is among the lines asked for.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.number,
    required this.text,
    required this.gutter,
    required this.sideways,
    this.colors,
    this.marked = false,
  });

  final int number;
  final String text;
  final double gutter;
  final ScrollController sideways;
  final List<TextSpan>? colors;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final style = AppFonts.codeStyle(12).copyWith(height: 1.5);
    final background = marked
        ? themeColors['editor.rangeHighlightBackground']
        : Colors.transparent;
    final shown = text.replaceAll('\t', '    ');
    return ColoredBox(
      color: background,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: gutter + 20),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: colors,
                    text: colors == null ? shown : null,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: style.copyWith(
                    color: themeColors['editor.foreground'],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: sideways,
              builder: (context, child) => Transform.translate(
                offset: Offset(sideways.hasClients ? sideways.offset : 0, 0),
                child: child,
              ),
              // Keep the line numbers visible while the source scrolls
              // underneath them.
              child: ColoredBox(
                color: Color.alphaBlend(background, AppColors.code),
                child: SelectionContainer.disabled(
                  child: SizedBox(
                    width: gutter + 20,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: Text(
                        '$number',
                        textAlign: TextAlign.right,
                        style: style.copyWith(
                          color: marked
                              ? themeColors['editorLineNumber.activeForeground']
                              : themeColors['editorLineNumber.foreground'],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// In place of what cannot be shown: why.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: AppColors.textFaint),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// A button in the bar named by its [label], as the IDE's status bar's:
/// the file's language (a click changes it), a markdown file's Edit or
/// Preview. [tooltip] over it when given.
class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final String label;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? themeColors['toolbar.hoverBackground'] : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      ),
    );
    if (tooltip case final message?) {
      return IdeHover(message: message, child: button);
    }
    return button;
  }
}

/// Files dropped on a markdown file's preview (see
/// [_FilePreviewState._markdownDrop]).
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
