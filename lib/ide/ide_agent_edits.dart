import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bao_editor/monaco/flutter/diff_editor.dart';
import 'package:bao_editor/monaco/flutter/diff_editor_model.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/range_mapping.dart';

import '../chat/chat_models.dart' show FileChangeKind;
import '../chat/chat_session.dart';
import '../chat/review/change_reviews.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_hover.dart';
import 'ide_menu.dart';
import 'ide_original_diff.dart';
import 'ide_workspace.dart' show IdeDiffOriginal;

/// A file's change pending in an agent's conversation, as the editor shows
/// it in the file (Cursor's inline Keep and Undo): held against [base], the
/// text before the agent changed it with what was kept of it since.
class IdeAgentEdit {
  IdeAgentEdit._(this.session, this._review, this.path, this.base);

  /// [session]'s change pending in the file at [path]; null when none can
  /// be undone there.
  static IdeAgentEdit? inSession(ChatSession session, String path) {
    final review = session.changeReview;
    if (review?.baseOf(path) case final base?) {
      return IdeAgentEdit._(session, review!, path, base);
    }
    return null;
  }

  final ChatSession session;
  final ChangeReviews _review;
  final String path;

  /// Which text it is held against, anew as part of it is kept (see
  /// [ChangeReviews.baseOf]); empty for a file the agent created.
  final String base;

  /// The text it is held against.
  Future<String> readBase() =>
      _review.original(path)?.call() ?? Future.value('');

  /// Keeps part of it: [base] is what the rest is held against from now.
  Future<void> keepPart(String base) => _review.keepPart(path, base);

  /// Looks at the file again, part of the change undone and saved.
  Future<void> settle() => _review.settle([path]);

  /// Keeps the whole change to the file.
  void keepFile() => unawaited(_review.keep([path]));

  /// Puts the whole file back as it was before the agent changed it.
  void undoFile() => unawaited(_review.undo([path]));

  /// The file after this one (after the last, the first) whose change in
  /// the conversation is still pending, in the order its changes list
  /// them; null when there is none but this one.
  String? nextPending() {
    final pending = [
      for (final change in _review.changes)
        if (change.kind != FileChangeKind.deleted &&
            (change.path == path || _review.baseOf(change.path) != null))
          change.path,
    ];
    final at = pending.indexOf(path);
    for (var i = 1; i <= pending.length; i++) {
      final next = pending[(at + i) % pending.length];
      if (next != path) return next;
    }
    return null;
  }
}

/// The agents' changes pending in the files an IDE shows: those of
/// [sessions]' reviews (the IDE's chat first), for its editor to show in
/// each file and keep or undo part by part.
class IdeAgentEdits extends ChangeNotifier {
  List<ChatSession> _sessions = const [];

  /// The reviews listened to, by session: one opens after its session.
  final Map<ChatSession, ChangeReviews?> _reviews = {};
  bool _disposed = false;

  List<ChatSession> get sessions => _sessions;
  set sessions(List<ChatSession> sessions) {
    if (_sameSessions(sessions)) return;
    for (final session in _sessions) {
      if (!sessions.contains(session)) {
        session.removeListener(_sessionChanged);
        _reviews.remove(session)?.removeListener(_changed);
      }
    }
    for (final session in sessions) {
      if (!_sessions.contains(session)) {
        session.addListener(_sessionChanged);
        _reviews[session] = session.changeReview?..addListener(_changed);
      }
    }
    _sessions = List.unmodifiable(sessions);
    // Set as the IDE builds: its listeners hear of it after.
    scheduleMicrotask(_changed);
  }

  bool _sameSessions(List<ChatSession> sessions) {
    if (sessions.length != _sessions.length) return false;
    for (var i = 0; i < sessions.length; i++) {
      if (!identical(sessions[i], _sessions[i])) return false;
    }
    return true;
  }

  /// A session tells of every token: only a review opening or going
  /// matters here.
  void _sessionChanged() {
    var changed = false;
    for (final session in _sessions) {
      final review = session.changeReview;
      if (identical(review, _reviews[session])) continue;
      _reviews[session]?.removeListener(_changed);
      _reviews[session] = review?..addListener(_changed);
      changed = true;
    }
    if (changed) _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// The change pending in the file at [path]; null when none can be
  /// undone there.
  IdeAgentEdit? of(String path) {
    for (final session in _sessions) {
      final review = _reviews[session];
      if (review == null) continue;
      if (review.baseOf(path) case final base?) {
        return IdeAgentEdit._(session, review, path, base);
      }
    }
    return null;
  }

  /// The agents' changes still pending, each with its turn and what that
  /// turn was asked (see [ChatSession.turnEdits]).
  Iterable<({String turn, String request, String path})> get turnEdits =>
      _sessions.expand((session) => session.turnEdits);

  final Map<String, IdeAgentHunks> _hunks = {};

  /// Where the editor of the file at [path] is among its change's parts:
  /// the same for the editor and the bar over it, whichever comes first.
  IdeAgentHunks hunksOf(String path) =>
      _hunks.putIfAbsent(path, () => IdeAgentHunks(open: _openPending));

  /// Opens a file in the IDE's editor (see [IdeAgentHunks.open]).
  ValueChanged<String>? open;

  /// The next file with a change pending, opened at its first part.
  void _openPending(String path) {
    hunksOf(path).reveal();
    open?.call(path);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final hunks in _hunks.values) {
      hunks.dispose();
    }
    for (final session in _sessions) {
      session.removeListener(_sessionChanged);
    }
    for (final review in _reviews.values) {
      review?.removeListener(_changed);
    }
    super.dispose();
  }
}

/// Where a change between [original] (what the file is held against) and
/// [modified] (its text) is in each, as offsets: replacing one span by the
/// other takes the change out (Undo) or puts it in what the file is held
/// against (Keep). Whole lines with their line breaks; at the end of the
/// texts, the line break before them instead (upstream's
/// `DetailedLineRangeMapping.toRangeMapping2`).
({int originalStart, int originalEnd, int modifiedStart, int modifiedEnd})
agentHunkSpans(
  LineRangeMapping change,
  DocumentSnapshot original,
  DocumentSnapshot modified,
) {
  final o = change.original;
  final m = change.modified;
  int lineStart(DocumentSnapshot text, int line) =>
      line > text.lineCount ? text.text.length : text.lineStarts[line - 1];
  int contentEnd(DocumentSnapshot text, int line) =>
      text.contentEnds[(line - 1).clamp(0, text.lineCount - 1)];
  if (m.endLineNumberExclusive <= modified.lineCount &&
      o.endLineNumberExclusive <= original.lineCount) {
    return (
      originalStart: lineStart(original, o.startLineNumber),
      originalEnd: lineStart(original, o.endLineNumberExclusive),
      modifiedStart: lineStart(modified, m.startLineNumber),
      modifiedEnd: lineStart(modified, m.endLineNumberExclusive),
    );
  }
  if (o.startLineNumber > 1 && m.startLineNumber > 1) {
    return (
      originalStart: contentEnd(original, o.startLineNumber - 1),
      originalEnd: contentEnd(original, o.endLineNumberExclusive - 1),
      modifiedStart: contentEnd(modified, m.startLineNumber - 1),
      modifiedEnd: contentEnd(modified, m.endLineNumberExclusive - 1),
    );
  }
  return (
    originalStart: lineStart(original, o.startLineNumber),
    originalEnd: lineStart(original, o.endLineNumberExclusive),
    modifiedStart: lineStart(modified, m.startLineNumber),
    modifiedEnd: lineStart(modified, m.endLineNumberExclusive),
  );
}

/// [original] with [change] in it: what the file is held against once that
/// part of the change is kept.
String agentHunkKept(
  LineRangeMapping change,
  DocumentSnapshot original,
  DocumentSnapshot modified,
) {
  final s = agentHunkSpans(change, original, modified);
  return original.text.substring(0, s.originalStart) +
      modified.text.substring(s.modifiedStart, s.modifiedEnd) +
      original.text.substring(s.originalEnd);
}

/// The parts of a file's agent change its editor shows ([IdeAgentDiff]),
/// which of them the caret is in, and the way from one to the next: for
/// the bar over the editor to count and step through them. After a part is
/// kept or undone, the caret goes on to the next; after a file's last, the
/// next file with a change pending opens ([open]).
class IdeAgentHunks extends ChangeNotifier {
  IdeAgentHunks({this.open});

  /// Opens the next file with a change pending (see
  /// [IdeAgentEdit.nextPending]) once this one's is all kept or undone, at
  /// its first part.
  final ValueChanged<String>? open;

  IdeAgentDiff? _agent;
  List<LineRangeMapping> _changes = const [];
  int _current = -1;

  /// The part just kept or undone: once the diff no longer has it, the
  /// caret goes to the one after it.
  LineRangeMapping? _acted;

  /// The line whose part is to be shown once the diff is known (0 for the
  /// first part).
  int? _revealAt;

  (int, int) _told = (0, -1);
  bool _telling = false;
  bool _disposed = false;

  /// How many parts the change has, as shown.
  int get count => _changes.length;

  /// Which of them (from 0) the caret is in; -1 when in none.
  int get current => _current;

  void _attach(IdeAgentDiff agent) {
    if (identical(_agent, agent)) return;
    _agent?._unlisten(this);
    _agent = agent;
    agent.diff.model.addListener(_update);
    agent.controller.addListener(_caretMoved);
    _update();
  }

  void _detach(IdeAgentDiff agent) {
    if (!identical(_agent, agent)) return;
    agent._unlisten(this);
    _agent = null;
    _changes = const [];
    _current = -1;
    _tell();
  }

  /// Shows the part at [line] (from 1; the next after it where it is in
  /// none), else the first: once the diff is known, and the editor is there.
  void reveal({int? line}) {
    _revealAt = line ?? 0;
    _update();
  }

  /// Opens the file after [edit]'s with a change pending, if there is one;
  /// after what opens it now is done.
  void openNext(IdeAgentEdit edit) {
    final open = this.open;
    if (open == null) return;
    final next = edit.nextPending();
    if (next == null) return;
    scheduleMicrotask(() {
      if (!_disposed) open(next);
    });
  }

  /// Goes to the next part, after the last back to the first.
  void next() => _step(forward: true);

  /// Goes to the previous part, before the first on to the last.
  void previous() => _step(forward: false);

  void _update() {
    final agent = _agent;
    if (agent == null) return;
    final mappings = agent.diff.model.mappings;
    final changes = mappings ?? const <LineRangeMapping>[];
    if (!identical(changes, _changes)) {
      _changes = changes;
      if (_acted case final acted? when !changes.any((c) => _same(c, acted))) {
        _acted = null;
        final line = acted.modified.startLineNumber;
        final next = changes.indexWhere(
          (c) => c.modified.startLineNumber >= line,
        );
        if (changes.isNotEmpty) {
          _goTo(changes[next < 0 ? 0 : next]);
        } else {
          // The file's last part: on to the next file.
          openNext(agent.edit);
        }
      }
    }
    if (_revealAt case final line? when mappings != null) {
      _revealAt = null;
      if (changes.isNotEmpty) {
        final at = line < 1
            ? 0
            : changes.indexWhere(
                (c) => _contains(c, line) || c.modified.startLineNumber >= line,
              );
        _goTo(changes[at < 0 ? 0 : at]);
      }
    }
    _caretMoved();
  }

  static bool _same(LineRangeMapping a, LineRangeMapping b) =>
      a.original.startLineNumber == b.original.startLineNumber &&
      a.original.endLineNumberExclusive == b.original.endLineNumberExclusive &&
      a.modified.startLineNumber == b.modified.startLineNumber &&
      a.modified.endLineNumberExclusive == b.modified.endLineNumberExclusive;

  /// Whether [line] is among [change]'s lines; the line after lines
  /// taken out, for a part that only takes some out.
  static bool _contains(LineRangeMapping change, int line) {
    final m = change.modified;
    return m.isEmpty
        ? line == m.startLineNumber
        : m.startLineNumber <= line && line < m.endLineNumberExclusive;
  }

  /// The caret's line, from 1; null without an editor.
  int? get _caretLine {
    final controller = _agent?.controller;
    if (controller == null) return null;
    final selection = controller.value.selection;
    if (!selection.isValid) return null;
    final text = controller.document.snapshot;
    return text
        .positionAtOffset(selection.extentOffset.clamp(0, text.text.length))
        .lineNumber;
  }

  void _caretMoved() {
    final line = _caretLine;
    _current = line == null
        ? -1
        : _changes.indexWhere((change) => _contains(change, line));
    _tell();
  }

  void _step({required bool forward}) {
    final changes = _changes;
    final line = _caretLine;
    if (changes.isEmpty || line == null) return;
    final at = changes.indexWhere((change) => _contains(change, line));
    var index = forward
        ? at >= 0
              ? at + 1
              : changes.indexWhere((c) => c.modified.startLineNumber > line)
        : at >= 0
        ? at - 1
        : changes.lastIndexWhere((c) => c.modified.startLineNumber < line);
    if (index < 0 || index >= changes.length) {
      index = forward ? 0 : changes.length - 1;
    }
    _goTo(changes[index]);
  }

  /// The caret at the start of [change], its lines scrolled to the middle
  /// where out of view; once the editor is laid out (a tab just opened, a
  /// few frames on).
  void _goTo(LineRangeMapping change, {int tries = 8}) {
    void go() {
      final agent = _agent;
      if (agent == null) return;
      final text = agent.controller.document.snapshot;
      int start(int line) =>
          line > text.lineCount ? text.text.length : text.lineStarts[line - 1];
      final m = change.modified;
      final from = start(m.startLineNumber);
      final last = math.max(m.startLineNumber, m.endLineNumberExclusive - 1);
      final to = last > text.lineCount
          ? text.text.length
          : text.contentEnds[last - 1];
      // Before the caret moves, which would only scroll to the edge.
      agent.view()?.revealRange(from, to);
      agent.controller.select(from, from);
    }

    if (tries == 0 || _agent?.view()?.textArea != null) return go();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) _goTo(change, tries: tries - 1);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Tells of a count or a part changed, after the build that changed it.
  void _tell() {
    if (_telling) return;
    _telling = true;
    scheduleMicrotask(() {
      _telling = false;
      if (_disposed || _told == (count, _current)) return;
      _told = (count, _current);
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _agent?._unlisten(this);
    _agent = null;
    super.dispose();
  }
}

/// A file's agent change shown in its editor: the diff of its text (that of
/// [controller]) against what it is held against ([IdeAgentEdit.base]),
/// read anew as part of the change is kept (the last text shown until
/// then); its parts kept or undone one by one, [hunks] stepping through
/// them.
class IdeAgentDiff {
  IdeAgentDiff(
    IdeAgentEdit edit,
    this.controller, {
    required VoidCallback onChanged,
    required this.save,
    required this.view,
    required this.hunks,
  }) : _edit = edit,
       _base = edit.base {
    original = IdeDiffOriginal(() => _edit.readBase());
    // Every change counts: one hidden could be neither kept nor undone.
    diff = IdeOriginalDiff(
      original,
      controller.document,
      onChanged: onChanged,
      ignoreTrimWhitespace: false,
    );
    // Shown anew as it is computed again (an edit, a part kept).
    diff.model.addListener(onChanged);
    hunks._attach(this);
    unawaited(_read());
  }

  /// The file's text, in the editor.
  final EditorSurfaceController controller;

  /// Saves the file's text where it is changed.
  final Future<void> Function() save;

  /// The editor showing it, for [hunks] to scroll; null while there is none.
  final EditorSurfaceView? Function() view;
  final IdeAgentHunks hunks;

  IdeAgentEdit _edit;
  String _base;
  bool _disposed = false;
  late final IdeDiffOriginal original;
  late final IdeOriginalDiff diff;

  IdeAgentEdit get edit => _edit;
  set edit(IdeAgentEdit edit) {
    _edit = edit;
    if (edit.base == _base) return;
    _base = edit.base;
    unawaited(_read());
  }

  /// Shows the change held against [text], before the review has it.
  void show(String text) => original.text.value = text;

  /// Shows it against what the review holds it against (what [show] showed
  /// did not take).
  void reread() => unawaited(_read());

  Future<void> _read() async {
    final base = _base;
    try {
      final text = await _edit.readBase();
      if (!_disposed && base == _base) original.text.value = text;
    } on Object {
      // Shown as it was; read again as it changes.
    }
  }

  /// Keeps [change]: what the file is held against takes it in. Saved
  /// first, as [undo] saves; shown kept at once, the review taking it in
  /// after.
  Future<void> keep(LineRangeMapping change) async {
    final original = diff.model.originalSnapshot;
    if (original == null) return;
    final base = agentHunkKept(change, original, controller.document.snapshot);
    hunks._acted = change;
    show(base);
    try {
      await save();
      await _edit.keepPart(base);
    } catch (_) {
      reread();
      rethrow;
    }
  }

  /// Undoes [change] in the text (an undo step of its own), and saves it.
  Future<void> undo(LineRangeMapping change) async {
    final original = diff.model.originalSnapshot;
    if (original == null) return;
    final modified = controller.document.snapshot;
    final spans = agentHunkSpans(change, original, modified);
    final text = original.text.substring(
      spans.originalStart,
      spans.originalEnd,
    );
    // A file the agent made, with nothing of it left: gone, as it was.
    if (_edit.base.isEmpty &&
        spans.modifiedEnd - spans.modifiedStart == modified.text.length &&
        text.isEmpty) {
      _edit.undoFile();
      hunks.openNext(_edit);
      return;
    }
    hunks._acted = change;
    controller.applyEdits([
      EditorOffsetEdit(spans.modifiedStart, spans.modifiedEnd, text),
    ]);
    // Shown undone at once, not after the edit's debounce.
    diff.model.refresh();
    await save();
    await _edit.settle();
  }

  Object? _key;
  ({List<EditorViewZone> zones, List<EditorDecoration> decorations})? _parts;

  /// What the editor shows of it (see [inlineDiffParts]), the same while
  /// the diff is.
  ({List<EditorViewZone> zones, List<EditorDecoration> decorations}) parts({
    required DiffEditorColors colors,
    required TextStyle style,
    required TextScaler textScaler,
  }) {
    final model = diff.model;
    final styledLines = diff.textMate?.styledLines;
    final key = (
      model.mappings,
      model.originalSnapshot,
      model.modified.snapshot,
      styledLines,
      colors,
      style,
      textScaler,
    );
    if (_parts case final parts? when key == _key) return parts;
    _key = key;
    return _parts = inlineDiffParts(
      model,
      colors: colors,
      style: style,
      textScaler: textScaler,
      originalStyledLines: styledLines,
    );
  }

  void _unlisten(IdeAgentHunks hunks) {
    diff.model.removeListener(hunks._update);
    controller.removeListener(hunks._caretMoved);
  }

  void dispose() {
    _disposed = true;
    hunks._detach(this);
    diff.dispose();
    original.dispose();
  }
}

/// Undo and Keep by each change in the editor's text, at the right of the
/// line after it, kept there as the text scrolls ([repaint]).
class IdeAgentHunkActions extends StatelessWidget {
  const IdeAgentHunkActions({
    super.key,
    required this.changes,
    required this.snapshot,
    required this.view,
    required this.repaint,
    required this.onUndo,
    required this.onKeep,
  });

  final List<LineRangeMapping> changes;

  /// The text the changes are of.
  final DocumentSnapshot snapshot;
  final EditorSurfaceView? Function() view;
  final Listenable repaint;
  final ValueChanged<LineRangeMapping> onUndo;
  final ValueChanged<LineRangeMapping> onKeep;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListenableBuilder(
      listenable: repaint,
      builder: (context, _) {
        final view = this.view();
        final area = view?.textArea;
        if (view == null || area == null) return const SizedBox.shrink();
        final text = snapshot;
        final height = view.lineHeight;
        return Stack(
          children: [
            for (final change in changes)
              if (_topOf(view, text, change) case final top?
                  when top >= area.top && top + height <= area.bottom)
                Positioned(
                  key: ObjectKey(change),
                  top: top,
                  right: constraints.maxWidth - area.right + 14,
                  height: height,
                  child: _HunkButtons(
                    onUndo: () => onUndo(change),
                    onKeep: () => onKeep(change),
                  ),
                ),
          ],
        );
      },
    ),
  );

  /// The top of the line after [change] (the bottom of the last, at the
  /// end of the text).
  static double? _topOf(
    EditorSurfaceView view,
    DocumentSnapshot text,
    LineRangeMapping change,
  ) {
    final after = change.modified.endLineNumberExclusive;
    if (after <= text.lineCount) {
      return view.caretRectAt(text.lineStarts[after - 1])?.top;
    }
    return view.caretRectAt(text.text.length)?.bottom;
  }
}

class _HunkButtons extends StatelessWidget {
  const _HunkButtons({required this.onUndo, required this.onKeep});

  final VoidCallback onUndo;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HunkButton(
          label: l10n.stripUndo,
          background: themeColors['button.secondaryBackground'],
          hover: themeColors['button.secondaryHoverBackground'],
          foreground: themeColors['button.secondaryForeground'],
          onTap: onUndo,
        ),
        const SizedBox(width: 4),
        _HunkButton(
          label: l10n.stripKeep,
          background: themeColors['button.background'],
          hover: themeColors['button.hoverBackground'],
          foreground: themeColors['button.foreground'],
          onTap: onKeep,
        ),
      ],
    );
  }
}

class _HunkButton extends StatefulWidget {
  const _HunkButton({
    required this.label,
    required this.background,
    required this.hover,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color hover;
  final Color foreground;
  final VoidCallback onTap;

  @override
  State<_HunkButton> createState() => _HunkButtonState();
}

class _HunkButtonState extends State<_HunkButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: _hovered ? widget.hover : widget.background,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11.5,
              height: 1,
              color: widget.foreground,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Over the editor of a file with an agent's change pending (the IDE's
/// tabs, the side panel's file): the way to the previous and the next of
/// its parts and which the caret is in ([hunks]), Undo and Keep of the
/// file's change (the next file with one pending opened after), and under
/// its arrow those of all the conversation's.
class IdeAgentEditActions extends StatelessWidget {
  const IdeAgentEditActions({
    super.key,
    required this.edit,
    required this.hunks,
  });

  final IdeAgentEdit edit;
  final IdeAgentHunks hunks;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: hunks,
      builder: (context, _) {
        final count = hunks.count;
        final current = hunks.current;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IdeActionButton(
                icon: Codicons.arrowUp,
                tooltip: l10n.agentPreviousChange,
                onPressed: count == 0 ? null : hunks.previous,
              ),
              IdeActionButton(
                icon: Codicons.arrowDown,
                tooltip: l10n.agentNextChange,
                onPressed: count == 0 ? null : hunks.next,
              ),
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 2),
                  child: Text(
                    '${current < 0 ? '–' : current + 1}/$count',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              _TitleAction(
                label: l10n.agentUndoFile,
                onTap: () {
                  edit.undoFile();
                  hunks.openNext(edit);
                },
                primary: false,
              ),
              const SizedBox(width: 4),
              _TitleAction(
                label: l10n.agentKeepFile,
                onTap: () {
                  edit.keepFile();
                  hunks.openNext(edit);
                },
                primary: true,
              ),
              Builder(
                builder: (context) => IdeActionButton(
                  icon: Codicons.chevronDown,
                  width: 18,
                  tooltip: l10n.agentMoreActions,
                  onPressed: () => _showMore(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Undo all and Keep all of the conversation's changes, under the arrow.
  void _showMore(BuildContext context) {
    final l10n = context.l10n;
    final session = edit.session;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final undoAll = session.undoAllChanges;
    unawaited(
      showIdeMenu(
        context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        alignRight: true,
        entries: [
          IdeMenuAction(l10n.stripKeepAll, onSelected: session.keepAllChanges),
          IdeMenuAction(
            l10n.stripUndoAll,
            enabled: undoAll != null,
            onSelected: undoAll,
          ),
        ],
      ),
    );
  }
}

class _TitleAction extends StatefulWidget {
  const _TitleAction({
    required this.label,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  State<_TitleAction> createState() => _TitleActionState();
}

class _TitleActionState extends State<_TitleAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final primary = widget.primary;
    final background = primary
        ? themeColors[_hovered ? 'button.hoverBackground' : 'button.background']
        : _hovered && onTap != null
        ? themeColors['toolbar.hoverBackground']
        : null;
    final foreground = primary
        ? themeColors['button.foreground']
        : themeColors[onTap == null ? 'disabledForeground' : 'foreground'];
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: widget.label,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 12, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
