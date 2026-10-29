// JetBrains IDEs' merge dialog for a conflicted file: the current side
// (ours) on the left, the result in the middle, the incoming side (theirs)
// on the right, scrolled together; each side's changes joined to the
// result's lines between them, with an arrow that applies them (after the
// other side's, where it was applied) and a cross that ignores them. The
// changes only one side made are applied at once; a conflict keeps the
// common ancestor's lines until a side is applied or they are typed over,
// or a model merges it (BaoCode's own). Apply writes the result and marks
// the file resolved; Accept Current or Accept Incoming takes one side's
// file whole.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/language_configuration_assets.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' hide ColorScheme;
import '../ide_button.dart';
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_notifications.dart';
import 'commit_message.dart';
import 'git_merge_model.dart';
import 'git_model.dart';
import 'git_repository.dart';
import 'scm_host.dart';

/// Whether [resource]'s conflict can be merged in the dialog: both sides
/// have the file.
bool ideGitMergeable(IdeGitResource resource) => switch (resource.status) {
  IdeGitStatus.bothModified || IdeGitStatus.bothAdded => true,
  _ => false,
};

/// Opens [resource]'s merge in [git], written through [host]; what goes
/// wrong is told in [notifications]. With [ai], a conflict can be merged by
/// a model.
Future<void> showIdeGitMergeDialog(
  BuildContext context, {
  required IdeGitRepository git,
  required IdeGitResource resource,
  required IdeScmHost host,
  required IdeNotifications notifications,
  IdeCommitMessageModel? ai,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: false,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => IdeGitMergeDialog(
    git: git,
    resource: resource,
    host: host,
    notifications: notifications,
    ai: ai,
  ),
);

class IdeGitMergeDialog extends StatefulWidget {
  const IdeGitMergeDialog({
    super.key,
    required this.git,
    required this.resource,
    required this.host,
    required this.notifications,
    this.ai,
  });

  final IdeGitRepository git;
  final IdeGitResource resource;
  final IdeScmHost host;
  final IdeNotifications notifications;
  final IdeCommitMessageModel? ai;

  /// The gutter between two editors, with the arrows.
  static const gutterWidth = 44.0;

  @override
  State<IdeGitMergeDialog> createState() => IdeGitMergeDialogState();
}

/// One of the three editors.
enum _Pane { ours, result, theirs }

class IdeGitMergeDialogState extends State<IdeGitMergeDialog> {
  final WorkbenchThemeService _themes = WorkbenchThemeService.instance;
  late final TextMateSyntax _textMate = TextMateSyntax(themes: _themes);
  final Map<_Pane, GlobalKey> _keys = {
    for (final pane in _Pane.values) pane: GlobalKey(),
  };
  final Map<_Pane, ValueNotifier<Offset>> _scrolls = {
    for (final pane in _Pane.values) pane: ValueNotifier(Offset.zero),
  };
  final Map<_Pane, EditorSurfaceController> _controllers = {};
  final Map<_Pane, TextMateDocument> _highlights = {};
  final FocusNode _resultFocus = FocusNode(debugLabel: 'merge result');

  /// Ticks as an editor scrolls or the chunks change: the gutters follow.
  final ValueNotifier<int> _tick = ValueNotifier(0);

  IdeGitMerge? _merge;
  Object? _error;
  StreamSubscription<Object?>? _edits;

  /// The result's lines as the chunks know them.
  List<String> _resultLines = const [];

  /// Typed in, or a side applied, since it opened.
  bool _changed = false;

  /// The conflict last stepped to.
  int _current = -1;

  /// The chunks a model is merging.
  final Set<IdeGitMergeChunk> _merging = {};
  bool _saving = false;
  bool _syncing = false;

  String get _path => widget.resource.path;

  String get _relative => widget.git.service.pathContext.relative(
    _path,
    from: widget.git.service.root,
  );

  @override
  void initState() {
    super.initState();
    _themes.addListener(_repaint);
    for (final MapEntry(key: pane, value: scroll) in _scrolls.entries) {
      scroll.addListener(() => _scrolled(pane));
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _themes.removeListener(_repaint);
    unawaited(_edits?.cancel());
    for (final highlight in _highlights.values) {
      highlight
        ..removeListener(_repaint)
        ..dispose();
    }
    for (final controller in _controllers.values) {
      final document = controller.document;
      controller.dispose();
      document.dispose();
    }
    _textMate.dispose();
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    _tick.dispose();
    _resultFocus.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  // --- Loading ---------------------------------------------------------------

  Future<void> _load() async {
    final service = widget.git.service;
    Future<String> stage(int number) =>
        service.show(':$number', _path).catchError((Object _) => '');
    try {
      final (base, ours, theirs) = await (stage(1), stage(2), stage(3)).wait;
      final merge = await IdeGitMerge.compare(
        base: base,
        ours: ours,
        theirs: theirs,
      );
      if (!mounted) return;
      final result = merge.initialResult().replaceAll('\r\n', '\n');
      _resultLines = result.split('\n');
      _controllers[_Pane.ours] = _controller(merge.ours.join('\n'));
      _controllers[_Pane.theirs] = _controller(merge.theirs.join('\n'));
      final resultController = _controller(result);
      _controllers[_Pane.result] = resultController;
      _edits = resultController.document.changes.listen((_) => _typed());
      setState(() => _merge = merge);
      unawaited(_highlight());
      WidgetsBinding.instance.addPostFrameCallback((_) => _step(1));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  static EditorSurfaceController _controller(String text) =>
      EditorSurfaceController(document: EditorDocumentModel(text));

  Future<void> _highlight() async {
    final result = _controllers[_Pane.result]!;
    final text = result.document.text;
    final end = text.indexOf('\n');
    final firstLine = end < 0 ? text : text.substring(0, end);
    try {
      final configuration = await languageConfigurationForPath(
        _path,
        firstLine: firstLine,
      );
      if (!mounted) return;
      if (configuration != null) {
        for (final controller in _controllers.values) {
          controller.languageConfiguration = configuration;
        }
      }
      final languageId = await _textMate.languageIdForPath(
        _path,
        firstLine: firstLine,
      );
      if (!mounted || languageId == null) return;
      for (final MapEntry(key: pane, value: controller)
          in _controllers.entries) {
        final highlight = _textMate.open(
          languageId,
          controller.document.snapshot,
        );
        if (highlight != null) {
          _highlights[pane] = highlight..addListener(_repaint);
        }
      }
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final pane in _Pane.values) {
          _viewChanged(pane);
        }
      });
    } on Object {
      // Plain text, then.
    }
  }

  // --- The result ------------------------------------------------------------

  /// The result's lines as typed: the chunks the edit touches are edited,
  /// those after it follow.
  void _typed() {
    final merge = _merge;
    final document = _controllers[_Pane.result]?.document;
    if (merge == null || document == null) return;
    final highlight = _highlights[_Pane.result];
    if (highlight != null &&
        !identical(highlight.snapshot, document.snapshot)) {
      highlight.update(document.snapshot);
    }
    final lines = document.text.replaceAll('\r\n', '\n').split('\n');
    final old = _resultLines;
    _resultLines = lines;
    var start = 0;
    final shortest = math.min(old.length, lines.length);
    while (start < shortest && old[start] == lines[start]) {
      start++;
    }
    if (start == old.length && start == lines.length) return;
    var oldEnd = old.length;
    var newEnd = lines.length;
    while (oldEnd > start &&
        newEnd > start &&
        old[oldEnd - 1] == lines[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    merge.edited(start, oldEnd, newEnd);
    _changed = true;
    _chunksChanged();
  }

  /// The result's lines [start] to [end] replaced with [lines]; told
  /// [_typed] as nothing new.
  void _replaceLines(int start, int end, List<String> lines) {
    final controller = _controllers[_Pane.result]!;
    final next = [
      ..._resultLines.sublist(0, start),
      ...lines,
      ..._resultLines.sublist(end),
    ];
    final old = controller.document.text;
    final text = next.join('\n');
    _resultLines = next;
    // The one span that differs.
    var prefix = 0;
    final shortest = math.min(old.length, text.length);
    while (prefix < shortest &&
        old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        old.codeUnitAt(old.length - 1 - suffix) ==
            text.codeUnitAt(text.length - 1 - suffix)) {
      suffix++;
    }
    controller.applyEdits([
      EditorOffsetEdit(
        prefix,
        old.length - suffix,
        text.substring(prefix, text.length - suffix),
      ),
    ]);
    _changed = true;
    _chunksChanged();
  }

  void _apply(IdeGitMergeChunk chunk, IdeGitMergeSide side) {
    final edit = _merge!.apply(chunk, side);
    _replaceLines(edit.start, edit.end, edit.lines);
  }

  void _ignore(IdeGitMergeChunk chunk, IdeGitMergeSide side) {
    _merge!.ignore(chunk, side);
    _changed = true;
    _chunksChanged();
  }

  void _chunksChanged() {
    if (!mounted) return;
    setState(() {});
    _tick.value++;
  }

  // --- AI --------------------------------------------------------------------

  /// [chunk] merged by the model, its lines in the result its reply's.
  Future<void> _mergeWithAi(IdeGitMergeChunk chunk) async {
    final ai = widget.ai;
    final merge = _merge;
    if (ai == null || merge == null || !_merging.add(chunk)) return;
    _chunksChanged();
    final l10n = context.l10n;
    try {
      final prompt = ideGitMergePrompt(merge, chunk, path: _relative);
      final reply = await ai(
        IdeCommitMessagePrompt(prompt.system, prompt.user),
      );
      if (!mounted) return;
      final lines = ideGitMergedLines(reply);
      if (lines == null) {
        throw IdeCommitMessageException(l10n.gitMergeAiNoAnswer);
      }
      final edit = merge.replace(chunk, lines);
      _replaceLines(edit.start, edit.end, edit.lines);
    } on IdeCommitMessageCancelled {
      // Stopped.
    } catch (error) {
      if (mounted) {
        widget.notifications.notify(
          IdeSeverity.error,
          l10n.gitMergeAiFailed('$error'),
        );
      }
    } finally {
      _merging.remove(chunk);
      _chunksChanged();
    }
  }

  /// Each conflict not resolved, merged by the model at once.
  Future<void> _mergeAllWithAi() async {
    final merge = _merge;
    if (merge == null) return;
    await [
      for (final chunk in merge.chunks)
        if (chunk.isConflict && !chunk.resolved) _mergeWithAi(chunk),
    ].wait;
  }

  // --- Stepping and scrolling ------------------------------------------------

  List<IdeGitMergeChunk> get _conflicts => [
    for (final chunk in _merge?.chunks ?? const <IdeGitMergeChunk>[])
      if (chunk.isConflict) chunk,
  ];

  /// The next conflict ([delta] 1) or the one before (-1) not resolved,
  /// shown in the result; any conflict where all are.
  void _step(int delta) {
    final conflicts = _conflicts;
    if (conflicts.isEmpty) return;
    final open = [
      for (var i = 0; i < conflicts.length; i++)
        if (!conflicts[i].resolved) i,
    ];
    final candidates = open.isEmpty
        ? [for (var i = 0; i < conflicts.length; i++) i]
        : open;
    final next = delta > 0
        ? candidates.firstWhere(
            (i) => i > _current,
            orElse: () => candidates.first,
          )
        : candidates.lastWhere(
            (i) => i < _current,
            orElse: () => candidates.last,
          );
    _current = next;
    _reveal(conflicts[next]);
  }

  void _reveal(IdeGitMergeChunk chunk) {
    final view = _view(_Pane.result);
    final controller = _controllers[_Pane.result];
    if (view == null || controller == null) return;
    final snapshot = controller.document.snapshot;
    final line = chunk.resultStart.clamp(0, snapshot.lineCount - 1);
    final offset = snapshot.lineStarts[line];
    view.revealRange(offset, offset, center: true);
    controller.select(offset, offset);
    _resultFocus.requestFocus();
    _tick.value++;
  }

  EditorSurfaceView? _view(_Pane pane) => switch (_keys[pane]!.currentState) {
    final EditorSurfaceView view => view,
    _ => null,
  };

  /// [chunk]'s lines in [pane].
  static IdeGitMergeLines _linesIn(IdeGitMergeChunk chunk, _Pane pane) =>
      switch (pane) {
        _Pane.ours => chunk.ours,
        _Pane.theirs => chunk.theirs,
        _Pane.result => (start: chunk.resultStart, end: chunk.resultEnd),
      };

  /// [line] of [from] (fractional) where it is in [to]: the same distance
  /// from a chunk outside them, in proportion inside.
  double _mapLine(double line, _Pane from, _Pane to) {
    final chunks = _merge?.chunks ?? const <IdeGitMergeChunk>[];
    for (final chunk in chunks) {
      final a = _linesIn(chunk, from);
      final b = _linesIn(chunk, to);
      if (line < a.start) return b.start - (a.start - line);
      if (line < a.end) {
        return b.start +
            (line - a.start) * (b.end - b.start) / (a.end - a.start);
      }
    }
    if (chunks.isEmpty) return line;
    return _linesIn(chunks.last, to).end +
        (line - _linesIn(chunks.last, from).end);
  }

  /// [pane] scrolled: the others to the lines its middle line goes with.
  void _scrolled(_Pane pane) {
    if (_syncing) return;
    final view = _view(pane);
    final area = view?.textArea;
    if (view == null || area == null || view.lineHeight == 0) return;
    _syncing = true;
    try {
      final height = view.lineHeight;
      final position = _scrolls[pane]!.value;
      final middle = (position.dy + area.height / 2) / height;
      for (final other in _Pane.values) {
        if (other == pane) continue;
        final top = _mapLine(middle, pane, other) * height - area.height / 2;
        _scrolls[other]!.value = Offset(
          _scrolls[other]!.value.dx,
          math.max(0, top),
        );
      }
    } finally {
      _syncing = false;
    }
    _tick.value++;
  }

  void _viewChanged(_Pane pane) {
    if (!mounted) return;
    if (_view(pane)?.visibleLineRange case final range?) {
      _highlights[pane]?.setViewport(range.first, range.last);
    }
    _tick.value++;
  }

  // --- Closing ---------------------------------------------------------------

  /// The result written and the file marked resolved; asked first where
  /// conflicts are left.
  Future<void> _save() async {
    final merge = _merge;
    if (merge == null || _saving) return;
    final l10n = context.l10n;
    if (merge.unresolved > 0) {
      final choice = await showIdeDialog(
        context,
        message: l10n.gitMergeUnresolved(merge.unresolved),
        detail: l10n.gitMergeUnresolvedDetail,
        buttons: [l10n.gitMergeSaveAnyway],
      );
      if (choice != 0 || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final text = _resultLines.join(merge.eol);
      final files = widget.host.files;
      final current = await files.read(_path, force: true);
      await files.write(_path, text, expectedText: current);
      await widget.host.reload([_path]);
      await widget.git.stage([widget.resource]);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        widget.notifications.notify(IdeSeverity.error, '$error');
      }
    }
  }

  /// One side's file whole, as the conflict menu's Accept Current and
  /// Accept Incoming take it.
  Future<void> _accept({required bool ours}) async {
    try {
      await widget.git.acceptSide([widget.resource], ours: ours);
      await widget.host.reload([_path]);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) widget.notifications.notify(IdeSeverity.error, '$error');
    }
  }

  /// Closed; asked first where something was applied or typed.
  Future<void> _cancel() async {
    if (_changed) {
      final l10n = context.l10n;
      final choice = await showIdeDialog(
        context,
        message: l10n.gitMergeDiscard,
        buttons: [l10n.gitMergeDiscardButton],
      );
      if (choice != 0 || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  // --- Building --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final border = colors.get('widget.border');
    final size = MediaQuery.sizeOf(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            unawaited(_cancel()),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.f7): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.f7, shift: true): () =>
            _step(-1),
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: math.max(600, size.width - 48),
              height: math.max(400, size.height - 48),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: border == null ? null : Border.all(color: border),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x26000000), blurRadius: 20),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 13,
                  color: colors['editorWidget.foreground'],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _titleBar(l10n),
                    Container(height: 1, color: border ?? Colors.transparent),
                    if (_merge != null) _toolbar(l10n),
                    Expanded(child: _body(l10n)),
                    Container(height: 1, color: border ?? Colors.transparent),
                    _buttons(l10n),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _titleBar(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            l10n.gitMergeTitle(_relative),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        IdeActionButton(
          icon: Codicons.close,
          tooltip: l10n.dialogCloseDialog,
          onPressed: () => unawaited(_cancel()),
        ),
      ],
    ),
  );

  /// Stepping through the conflicts, how many are left, and the model's
  /// merge of them all.
  Widget _toolbar(AppLocalizations l10n) {
    final merge = _merge!;
    final description = themeColors['descriptionForeground'];
    final changes = merge.chunks.where((chunk) => !chunk.isConflict).length;
    final unresolved = merge.unresolved;
    return Container(
      height: 34,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      child: Row(
        children: [
          IdeActionButton(
            icon: Codicons.arrowUp,
            tooltip: l10n.gitMergePrevious,
            onPressed: merge.conflicts == 0 ? null : () => _step(-1),
          ),
          IdeActionButton(
            icon: Codicons.arrowDown,
            tooltip: l10n.gitMergeNext,
            onPressed: merge.conflicts == 0 ? null : () => _step(1),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.gitMergeConflictsLeft(unresolved),
            style: TextStyle(
              color: unresolved > 0
                  ? themeColors['gitDecoration.conflictingResourceForeground']
                  : null,
            ),
          ),
          if (changes > 0) ...[
            Text('  ·  ', style: TextStyle(color: description)),
            Flexible(
              child: Text(
                l10n.gitMergeChangesApplied(changes),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: description),
              ),
            ),
          ],
          const Spacer(),
          if (widget.ai != null && unresolved > 0)
            IdeButton(
              label: l10n.gitMergeAiAll,
              icon: Codicons.sparkle,
              secondary: true,
              spinning: _merging.isNotEmpty,
              onPressed: _merging.isNotEmpty
                  ? null
                  : () => unawaited(_mergeAllWithAi()),
            ),
        ],
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    final merge = _merge;
    if (merge == null) {
      return Center(
        child: _error == null
            ? const SizedBox.shrink()
            : Text(
                '$_error',
                style: TextStyle(color: themeColors['errorForeground']),
              ),
      );
    }
    final branch = widget.git.state?.head.branch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 26,
          child: Row(
            children: [
              Expanded(
                child: _header(
                  branch == null
                      ? l10n.gitMergeOurs
                      : '${l10n.gitMergeOurs} · $branch',
                ),
              ),
              const SizedBox(width: IdeGitMergeDialog.gutterWidth),
              Expanded(child: _header(l10n.gitMergeResult)),
              const SizedBox(width: IdeGitMergeDialog.gutterWidth),
              Expanded(child: _header(l10n.gitMergeTheirs)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _pane(_Pane.ours)),
              _gutter(IdeGitMergeSide.ours),
              Expanded(child: _resultPane()),
              _gutter(IdeGitMergeSide.theirs),
              Expanded(child: _pane(_Pane.theirs)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: themeColors['descriptionForeground'],
        ),
      ),
    ),
  );

  Color _kindColor(IdeGitMergeChunk chunk, IdeGitMergeSide? side) {
    final colors = themeColors;
    if (chunk.isConflict) {
      return colors['gitDecoration.conflictingResourceForeground'];
    }
    final lines = side == null ? null : chunk.lines(side);
    if (chunk.base.start == chunk.base.end) {
      return colors['editorGutter.addedBackground'];
    }
    if (lines != null && lines.start == lines.end) {
      return colors['editorGutter.deletedBackground'];
    }
    return colors['editorGutter.modifiedBackground'];
  }

  /// Whole lines [lines] of [snapshot] tinted [color]; [faint] for a
  /// change applied already.
  static EditorDecoration? _tint(
    DocumentSnapshot snapshot,
    IdeGitMergeLines lines,
    Color color, {
    bool faint = false,
  }) {
    if (lines.end <= lines.start || lines.start >= snapshot.lineCount) {
      return null;
    }
    final last = math.min(lines.end, snapshot.lineCount) - 1;
    return EditorDecoration(
      start: snapshot.lineStarts[lines.start],
      end: snapshot.contentEnds[last],
      isWholeLine: true,
      backgroundColor: color.withValues(alpha: faint ? .07 : .16),
    );
  }

  /// A side's lines that can still go to the result, tinted; those it
  /// gave the result, faintly.
  Widget _pane(_Pane pane) {
    final side = pane == _Pane.ours
        ? IdeGitMergeSide.ours
        : IdeGitMergeSide.theirs;
    final controller = _controllers[pane]!;
    final snapshot = controller.document.snapshot;
    return _surface(
      pane,
      readOnly: true,
      decorations: [
        for (final chunk in _merge!.chunks)
          if (chunk.canApply(side))
            ?_tint(snapshot, chunk.lines(side), _kindColor(chunk, side))
          else if (chunk.applied.contains(side))
            ?_tint(
              snapshot,
              chunk.lines(side),
              _kindColor(chunk, side),
              faint: true,
            ),
      ],
    );
  }

  /// The result, its conflicts left tinted, a model's merges too, what
  /// was applied faintly; the model's button by each conflict left.
  Widget _resultPane() {
    final controller = _controllers[_Pane.result]!;
    final snapshot = controller.document.snapshot;
    final surface = _surface(
      _Pane.result,
      readOnly: false,
      decorations: [
        for (final chunk in _merge!.chunks)
          if (chunk.isConflict && !chunk.resolved)
            ?_tint(snapshot, (
              start: chunk.resultStart,
              end: chunk.resultEnd,
            ), _kindColor(chunk, null))
          else if (chunk.merged)
            ?_tint(snapshot, (
              start: chunk.resultStart,
              end: chunk.resultEnd,
            ), themeColors['textLink.foreground'])
          else if (chunk.applied.isNotEmpty)
            ?_tint(
              snapshot,
              (start: chunk.resultStart, end: chunk.resultEnd),
              _kindColor(chunk, null),
              faint: true,
            ),
      ],
    );
    if (widget.ai == null) return surface;
    return Stack(
      children: [
        Positioned.fill(child: surface),
        Positioned.fill(
          child: ListenableBuilder(
            listenable: _tick,
            builder: (context, _) => _aiButtons(),
          ),
        ),
      ],
    );
  }

  /// A Merge with AI button at the right of each conflict left.
  Widget _aiButtons() {
    final view = _view(_Pane.result);
    final area = view?.textArea;
    if (view == null || area == null) return const SizedBox.shrink();
    final top = view.caretRectAt(0)?.top;
    if (top == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Stack(
      children: [
        for (final chunk in _merge!.chunks)
          if (chunk.isConflict && !chunk.resolved)
            if (top + chunk.resultStart * view.lineHeight case final y
                when y >= area.top - 2 && y + 20 <= area.bottom)
              Positioned(
                key: ObjectKey(chunk),
                right: 16,
                top: y,
                height: 20,
                child: _ChunkButton(
                  icon: Codicons.sparkle,
                  label: l10n.gitMergeAi,
                  tooltip: l10n.gitMergeAi,
                  busy: _merging.contains(chunk),
                  onTap: () => unawaited(_mergeWithAi(chunk)),
                ),
              ),
      ],
    );
  }

  Widget _surface(
    _Pane pane, {
    required bool readOnly,
    required List<EditorDecoration> decorations,
  }) {
    final colors = _themes.colors;
    return EditorSurface(
      key: _keys[pane],
      controller: _controllers[pane]!,
      focusNode: pane == _Pane.result ? _resultFocus : null,
      readOnly: readOnly,
      backgroundColor: colors['editor.background'],
      selectionColor: colors['editor.selectionBackground'],
      caretColor: colors['editorCursor.foreground'],
      theme: EditorViewTheme.fromColors(colors.get),
      styledLines: _highlights[pane]?.styledLines,
      decorations: decorations,
      scrollPosition: _scrolls[pane],
      glyphMargin: false,
      folding: false,
      showMinimap: false,
      onViewChanged: () => _viewChanged(pane),
      style: AppFonts.codeStyle(13)
          .copyWith(color: colors['editor.foreground'], height: 1.45),
    );
  }

  /// Between [side]'s editor and the result: each of its changes joined to
  /// the result's lines, with its arrow and its cross.
  Widget _gutter(IdeGitMergeSide side) => SizedBox(
    width: IdeGitMergeDialog.gutterWidth,
    child: ListenableBuilder(
      listenable: _tick,
      builder: (context, _) {
        final pane = side == IdeGitMergeSide.ours ? _Pane.ours : _Pane.theirs;
        final sideView = _view(pane);
        final resultView = _view(_Pane.result);
        final sideTop = sideView?.caretRectAt(0)?.top;
        final resultTop = resultView?.caretRectAt(0)?.top;
        if (sideView == null ||
            resultView == null ||
            sideTop == null ||
            resultTop == null) {
          return const SizedBox.expand();
        }
        final height = sideView.lineHeight;
        final ribbons = <_Ribbon>[];
        final buttons = <Widget>[];
        final l10n = context.l10n;
        final area = sideView.textArea!;
        for (final chunk in _merge!.chunks) {
          if (!chunk.canApply(side)) continue;
          final lines = chunk.lines(side);
          final result = _linesIn(chunk, _Pane.result);
          final color = _kindColor(chunk, side);
          ribbons.add(
            _Ribbon(
              sideTop + lines.start * height,
              sideTop + lines.end * height,
              resultTop + result.start * height,
              resultTop + result.end * height,
              color,
            ),
          );
          final y = sideTop + lines.start * height;
          if (y < area.top - 2 || y + 16 > area.bottom) continue;
          final append = chunk.applied.isNotEmpty || chunk.edited;
          final ours = side == IdeGitMergeSide.ours;
          buttons
            ..add(
              Positioned(
                key: ObjectKey((chunk, 'apply')),
                left: ours ? 2 : null,
                right: ours ? null : 2,
                top: y + (height - 16) / 2,
                width: 16,
                height: 16,
                child: _GutterButton(
                  icon: append
                      ? Codicons.add
                      : ours
                      ? Codicons.arrowRight
                      : Codicons.arrowLeft,
                  tooltip: append ? l10n.gitMergeAppend : l10n.gitMergeApply,
                  onTap: () => _apply(chunk, side),
                ),
              ),
            )
            ..add(
              Positioned(
                key: ObjectKey((chunk, 'ignore')),
                left: ours ? 20 : null,
                right: ours ? null : 20,
                top: y + (height - 16) / 2,
                width: 16,
                height: 16,
                child: _GutterButton(
                  icon: Codicons.close,
                  tooltip: l10n.gitMergeIgnore,
                  onTap: () => _ignore(chunk, side),
                ),
              ),
            );
        }
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RibbonPainter(
                    ribbons,
                    flipped: side == IdeGitMergeSide.theirs,
                  ),
                ),
              ),
              ...buttons,
            ],
          ),
        );
      },
    ),
  );

  Widget _buttons(AppLocalizations l10n) {
    final ready = _merge != null && !_saving;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IdeButton(
            label: l10n.gitMergeAcceptOurs,
            secondary: true,
            onPressed: ready ? () => unawaited(_accept(ours: true)) : null,
          ),
          const SizedBox(width: 8),
          IdeButton(
            label: l10n.gitMergeAcceptTheirs,
            secondary: true,
            onPressed: ready ? () => unawaited(_accept(ours: false)) : null,
          ),
          const Spacer(),
          IdeButton(
            label: l10n.commonCancel,
            secondary: true,
            onPressed: () => unawaited(_cancel()),
          ),
          const SizedBox(width: 8),
          IdeButton(
            label: l10n.gitMergeApply,
            spinning: _saving,
            onPressed: ready ? () => unawaited(_save()) : null,
          ),
        ],
      ),
    );
  }
}

/// A side's change's lines ([sideTop] to [sideBottom]) and the result's
/// ([resultTop] to [resultBottom]), in their editors.
class _Ribbon {
  const _Ribbon(
    this.sideTop,
    this.sideBottom,
    this.resultTop,
    this.resultBottom,
    this.color,
  );

  final double sideTop;
  final double sideBottom;
  final double resultTop;
  final double resultBottom;
  final Color color;
}

/// JetBrains' curved bands from a side's change to the result's lines: the
/// side on the left, unless [flipped].
class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.ribbons, {required this.flipped});

  final List<_Ribbon> ribbons;
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    for (final ribbon in ribbons) {
      final (leftTop, leftBottom, rightTop, rightBottom) = flipped
          ? (
              ribbon.resultTop,
              ribbon.resultBottom,
              ribbon.sideTop,
              ribbon.sideBottom,
            )
          : (
              ribbon.sideTop,
              ribbon.sideBottom,
              ribbon.resultTop,
              ribbon.resultBottom,
            );
      if (math.max(leftBottom, rightBottom) < 0 ||
          math.min(leftTop, rightTop) > size.height) {
        continue;
      }
      final middle = width / 2;
      final path = Path()
        ..moveTo(0, leftTop)
        ..cubicTo(middle, leftTop, middle, rightTop, width, rightTop)
        ..lineTo(width, rightBottom)
        ..cubicTo(middle, rightBottom, middle, leftBottom, 0, leftBottom)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = ribbon.color.withValues(alpha: .16),
      );
      final edge = Paint()
        ..color = ribbon.color.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas
        ..drawPath(
          Path()
            ..moveTo(0, leftTop)
            ..cubicTo(middle, leftTop, middle, rightTop, width, rightTop),
          edge,
        )
        ..drawPath(
          Path()
            ..moveTo(0, leftBottom)
            ..cubicTo(
              middle,
              leftBottom,
              middle,
              rightBottom,
              width,
              rightBottom,
            ),
          edge,
        );
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => true;
}

/// An arrow or a cross in a gutter.
class _GutterButton extends StatefulWidget {
  const _GutterButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_GutterButton> createState() => _GutterButtonState();
}

class _GutterButtonState extends State<_GutterButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _hover
                  ? colors['toolbar.hoverBackground']
                  : colors['editor.background'],
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(
              widget.icon,
              size: 13,
              color: _hover
                  ? colors['editor.foreground']
                  : colors['editorLineNumber.foreground'],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small labelled button over the result's lines.
class _ChunkButton extends StatefulWidget {
  const _ChunkButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_ChunkButton> createState() => _ChunkButtonState();
}

class _ChunkButtonState extends State<_ChunkButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final border = colors.get('widget.border');
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.busy
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.busy ? null : widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _hover
                  ? colors['toolbar.hoverBackground']
                  : colors['editorWidget.background'],
              border: border == null ? null : Border.all(color: border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.busy ? Codicons.loading : widget.icon,
                  size: 12,
                  color: colors['textLink.foreground'],
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors['editorWidget.foreground'],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
