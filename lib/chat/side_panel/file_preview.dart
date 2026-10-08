import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_image_preview.dart';
import '../../ide/markdown/markdown_preview.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/editor_launcher.dart' show openExternal;
import '../chat_models.dart' show DiffLineType;
import '../composer/composer_files.dart' show CopiedCode;
import '../widgets/code_citation.dart' show CodeColorizer;
import 'file_link.dart';
import 'file_open.dart';
import 'line_diff.dart';

/// A file in the side panel, read only: its text with the lines asked for
/// marked and scrolled to, its changes against the text before the agent
/// changed it, a markdown file rendered (or its text), an image. A bar
/// over it names it, with [actions] (Open in Fast Ide) at its end.
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
  });

  final FileOpenRequest request;

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

  /// A line's height, as the editor's at its size.
  static const lineHeight = 18.0;

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
  const _Diff(this.rows, {this.deleted = false});

  final List<FileDiffRow> rows;
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
  EditorDocumentModel? _markdown;
  int _load = 0;

  FileOpenRequest get _request => widget.request;
  bool get _image => !_request.diff && ideIsImagePath(_request.path);
  bool get _isMarkdown => !_request.diff && isMarkdownPath(_request.path);

  @override
  void initState() {
    super.initState();
    _start();
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
      _start();
    } else if (oldWidget.reveal != widget.reveal && !_image) {
      // Asked for again (the agent wrote it again, say): read anew, what
      // shows kept until then.
      unawaited(_read(++_load));
    }
  }

  @override
  void dispose() {
    _markdown?.dispose();
    super.dispose();
  }

  void _start() {
    final load = ++_load;
    _loaded = null;
    _colors = const [];
    _markdown?.dispose();
    _markdown = null;
    if (_image) return;
    unawaited(_read(load));
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
    final _Loaded loaded;
    if (request.diff && original != null) {
      if (text == null && error is! IdeFileNotFoundException) {
        loaded = _Failed(error!);
      } else {
        loaded = _Diff(fileDiff(original, text ?? ''), deleted: text == null);
      }
    } else if (text == null) {
      loaded = _Failed(error!);
    } else {
      loaded = _Text(diffLines(text), noOriginal: request.diff);
    }
    setState(() {
      _loaded = loaded;
      if (_isMarkdown && text != null) {
        _markdown?.dispose();
        _markdown = EditorDocumentModel(text);
      }
    });
    unawaited(_colorize(load, loaded, original, text));
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
      case _Diff(:final rows):
        final before = await colors(original);
        final now = await colors(text);
        if (before == null && now == null) return;
        byRow = [
          for (final row in rows)
            row.type == DiffLineType.removed
                ? before?.elementAtOrNull(row.original! - 1)
                : now?.elementAtOrNull(row.modified! - 1),
        ];
      case _Failed():
        return;
    }
    if (!mounted || load != _load) return;
    setState(() => _colors = byRow);
  }

  @override
  Widget build(BuildContext context) {
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
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          FileIcon(path, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: shown),
                  if (range != null && !_request.diff)
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
          if (_isMarkdown && _markdown != null)
            IdeActionButton(
              icon: _source ? Codicons.openPreview : Codicons.code,
              tooltip: _source ? l10n.sidePanelPreview : l10n.sidePanelSource,
              onPressed: () => setState(() => _source = !_source),
            ),
          ...widget.actions,
        ],
      ),
    );
  }

  Widget? _notice(BuildContext context) {
    final l10n = context.l10n;
    final text = switch (_loaded) {
      _Text(noOriginal: true) => l10n.sidePanelNoOriginal,
      _Diff(deleted: true) => l10n.sidePanelDeleted,
      _Diff(:final rows)
          when rows.every((row) => row.type == DiffLineType.context) =>
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
      case _Diff(:final rows):
        return _Lines(
          key: ValueKey(('diff', _request.path)),
          count: rows.length,
          reveal: widget.reveal,
          target: _diffTarget(rows),
          width: _width(rows.map((row) => row.text)),
          // Lines of the file as it is now, none taken out.
          onCopy: (first, last, text) {
            final copied = rows.sublist(first, last + 1);
            if (copied.any((row) => row.modified == null)) return;
            _copied(copied.first.modified!, copied.last.modified!, text);
          },
          row: (context, i) => _LineRow(
            numbers: (rows[i].original, rows[i].modified),
            type: rows[i].type,
            text: rows[i].text,
            colors: _colors.elementAtOrNull(i),
            gutter: _gutter(rows.length),
          ),
        );
      case _Text(:final lines):
        if (_markdown case final model? when !_source) {
          return IdeMarkdownPreview(
            key: ValueKey((_request.path, widget.reveal)),
            path: _request.path,
            model: model,
            readBytes: widget.readBytes ?? readFileBytes,
            pathContext: widget.paths,
            readOnly: true,
            initialLine: _request.range?.start,
            onOpenFile: _openLinked,
            onOpenExternal: (uri) => unawaited(openExternal(uri.toString())),
          );
        }
        final range = _request.range;
        return _Lines(
          key: ValueKey(('text', _request.path)),
          count: lines.length,
          reveal: widget.reveal,
          target: range == null ? null : range.start - 1,
          width: _width(lines),
          onCopy: (first, last, text) => _copied(first + 1, last + 1, text),
          row: (context, i) => _LineRow(
            numbers: (null, i + 1),
            type: DiffLineType.context,
            text: lines[i],
            colors: _colors.elementAtOrNull(i),
            gutter: _gutter(lines.length),
            marked: range != null && i + 1 >= range.start && i + 1 <= range.end,
          ),
        );
    }
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

  /// A link in a markdown file: to a file beside it.
  void _openLinked(String path, String? fragment) {
    final range = fragment == null
        ? null
        : FileLink.parseHref('x#$fragment')?.range;
    widget.onOpenFile?.call(FileOpenRequest(path, range: range));
  }

  /// The row of the line asked for (as it is now), else the first change.
  int? _diffTarget(List<FileDiffRow> rows) {
    if (_request.range?.start case final line?) {
      final at = rows.indexWhere(
        (row) =>
            row.type != DiffLineType.context && row.modified == line ||
            row.type == DiffLineType.removed && (row.original ?? 0) >= line,
      );
      if (at >= 0) return at;
    }
    final first = rows.indexWhere((row) => row.type != DiffLineType.context);
    return first < 0 ? null : first;
  }

  /// The line numbers' width, for [count] lines.
  static double _gutter(int count) => '$count'.length * 7.5 + 16;

  /// As wide as the longest line, at about a monospaced character's width.
  static double _width(Iterable<String> lines) {
    var longest = 0;
    for (final line in lines) {
      longest = math.max(longest, line.replaceAll('\t', '    ').length);
    }
    return longest * 7.3;
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
    this.target,
    this.reveal = 0,
    this.onCopy,
  });

  final int count;
  final IndexedWidgetBuilder row;
  final double width;
  final int? target;
  final int reveal;
  final void Function(int first, int last, String text)? onCopy;

  @override
  State<_Lines> createState() => _LinesState();
}

class _LinesState extends State<_Lines> {
  final _scroll = ScrollController();
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
        oldWidget.target != widget.target) {
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
      final offset = (target - 3) * FilePreview.lineHeight;
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
        // Room for the line numbers and the markers besides the text.
        final width = math.max(constraints.maxWidth, widget.width + 120);
        return SelectionArea(
          child: SelectionContainer(
            delegate: _selection,
            child: Scrollbar(
              controller: _sideways,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _sideways,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemExtent: FilePreview.lineHeight,
                      itemCount: widget.count,
                      itemBuilder: (context, index) => _SelectableRow(
                        index: index,
                        lines: _selection,
                        child: widget.row(context, index),
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
}

/// The selection of [_Lines]: what is selected of each row, one to a line
/// (each row's text is a selection of its own, which the list would run
/// together), and which rows, told as it is copied.
class _LinesSelection extends StaticSelectionContainerDelegate {
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
    final text = [for (final (_, text) in rows) text].join('\n');
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

class _RowSelection extends StaticSelectionContainerDelegate {
  _RowSelection(this.row);

  _SelectableRow row;

  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content != null) row.lines._rows.add((row.index, content.plainText));
    return content;
  }
}

/// One line: its numbers (before and now, for a diff), a `+` or `-`, its
/// text; on the diff's colors, or the editor's range highlight where it
/// is among the lines asked for.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.numbers,
    required this.type,
    required this.text,
    required this.gutter,
    this.colors,
    this.marked = false,
  });

  /// Before and now; the first null outside a diff.
  final (int?, int?) numbers;
  final DiffLineType type;
  final String text;
  final double gutter;
  final List<TextSpan>? colors;
  final bool marked;

  static const _style = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 12,
    height: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    final (before, now) = numbers;
    final diff = before != null || type != DiffLineType.context;
    final (marker, markerColor, background) = switch (type) {
      DiffLineType.added => ('+', AppColors.added, AppColors.addedBackground),
      DiffLineType.removed => (
        '-',
        AppColors.removed,
        AppColors.removedBackground,
      ),
      DiffLineType.context => (
        ' ',
        AppColors.textFaint,
        marked
            ? themeColors['editor.rangeHighlightBackground']
            : Colors.transparent,
      ),
    };
    final numberStyle = _style.copyWith(
      color: marked
          ? themeColors['editorLineNumber.activeForeground']
          : themeColors['editorLineNumber.foreground'],
    );
    Widget number(int? n) => SizedBox(
      width: gutter,
      child: Text(
        n == null ? '' : '$n',
        textAlign: TextAlign.right,
        style: numberStyle,
      ),
    );
    final shown = text.replaceAll('\t', '    ');
    return ColoredBox(
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line numbers and markers are not copied with the code.
          SelectionContainer.disabled(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (diff) number(before),
                number(now),
                SizedBox(
                  width: 20,
                  child: Text(
                    diff ? marker : '',
                    textAlign: TextAlign.center,
                    style: _style.copyWith(color: markerColor),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: colors, text: colors == null ? shown : null),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: _style.copyWith(color: themeColors['editor.foreground']),
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
