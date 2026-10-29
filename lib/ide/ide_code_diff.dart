import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bao_editor/monaco/flutter/diff_editor.dart';
import 'package:bao_editor/monaco/flutter/diff_editor_model.dart';
import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/flutter/language_configuration_assets.dart';
import 'package:bao_editor/monaco/flutter/lines_diff.dart'
    show isSmallLinesDiff;
import 'package:bao_editor/monaco/vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/range_mapping.dart';
import 'package:bao_editor/textmate/textmate_syntax.dart';

import '../base/shown_when_ready.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' hide ColorScheme;
import 'git/git_partial.dart' show ideGitHunkKeys, ideGitLineKey;
import 'ide_agent_edits.dart' show agentHunkSpans;
import 'ide_code_editor.dart' show IdeCodeHighlights;
import 'ide_diff_options.dart';
import 'ide_hover.dart';
import 'ide_original_diff.dart';
import 'ide_workspace.dart' show IdeDiffOriginal;

/// Where a diff opens: at its first change, or (stepped back into from the
/// next file) at its last.
enum IdeDiffStart { first, last }

/// What an agent changed in a file and is not yet kept: the text before it
/// ([base]) and what the turns that changed it were asked, the latest
/// last. A diff's changes the agent's lines are in are marked with them.
class IdeDiffAgentMarks {
  const IdeDiffAgentMarks(this.base, this.turns);

  final String base;
  final List<String> turns;
}

/// The check boxes by a diff's changes (JetBrains' partial commit): whether
/// each, by its key ([ideGitHunkKeys]), goes in the commit.
abstract interface class IdeDiffChecks implements Listenable {
  bool isIncluded(String key);
  void setIncluded(String key, bool included);
}

/// A change, [original] against [modified], in the IDE's diff editor
/// ([DiffEditor]), as JetBrains IDEs' diff viewer shows one: side by side
/// or unified as [IdeDiffOptions] says, both highlighted as the language of
/// [path], scrolled to [line] of [modified] (from 1) or to its first change
/// ([start]: its last). With [onEdit], the modified side is the file's and
/// can be edited, each change with a revert arrow beside it; what is
/// typed and reverted goes to [onEdit]. Copied, the modified's lines are
/// told [onCopy] (from 1).
class IdeCodeDiff extends StatefulWidget {
  const IdeCodeDiff({
    super.key,
    required this.path,
    required this.original,
    required this.modified,
    this.line,
    this.start = IdeDiffStart.first,
    this.highlights,
    this.onCopy,
    this.onEdit,
    this.position,
    this.checks,
    this.agent,
    this.onAsk,
  });

  final String path;
  final String original;
  final String modified;
  final int? line;
  final IdeDiffStart start;

  /// Whose TextMate worker highlights it; its own when null.
  final IdeCodeHighlights? highlights;
  final void Function(String text, int start, int end)? onCopy;

  /// Writes the modified side once edited; read only when null.
  final Future<void> Function(String text)? onEdit;

  /// Told the change stepped to (-1 before any) and how many there are,
  /// for a toolbar to show.
  final ValueNotifier<({int current, int count})>? position;

  /// A check box by each change, where the changes can be left out of a
  /// commit; whitespace then counts, as it does for the commit.
  final IdeDiffChecks? checks;

  /// The agent's change in the file, its parts in the diff marked.
  final IdeDiffAgentMarks? agent;

  /// Asks the AI about a change: its lines as a diff writes them (`-`
  /// taken out, `+` put in), and where it starts in [modified].
  final void Function(String change, int line)? onAsk;

  /// How long typing goes on before what is typed is written.
  static const writeDelay = Duration(milliseconds: 400);

  @override
  State<IdeCodeDiff> createState() => IdeCodeDiffState();
}

class IdeCodeDiffState extends State<IdeCodeDiff> {
  final WorkbenchThemeService _themes = WorkbenchThemeService.instance;
  final IdeDiffOptions _options = IdeDiffOptions.instance;
  final GlobalKey _modifiedKey = GlobalKey();
  late EditorSurfaceController _modified;
  late IdeDiffOriginal _original;
  late IdeOriginalDiff _diff;
  TextMateDocument? _highlight;
  TextMateSyntax? _ownTextMate;
  IdeDiffWhitespace _whitespace = IdeDiffWhitespace.trim;

  /// Bumped as the texts change: an older language pick is dropped.
  int _texts = 0;

  /// Scrolled to [IdeCodeDiff.line] or the first change, once compared.
  bool _revealed = false;

  /// The change stepped to (F7), its index in the diff; -1 before any.
  int _change = -1;

  final ValueNotifier<({int current, int count})> _ownPosition = ValueNotifier((
    current: -1,
    count: 0,
  ));

  ValueNotifier<({int current, int count})> get _position =>
      widget.position ?? _ownPosition;

  /// Ticks as the modified editor scrolls: the revert arrows follow.
  final ValueNotifier<int> _viewTick = ValueNotifier(0);

  /// The change the pointer is on: its lines' check boxes show.
  final ValueNotifier<int?> _hovered = ValueNotifier(null);

  /// The lines of the modified text the agent changed, for the text they
  /// were found in.
  (DocumentSnapshot, String, List<LineRange>)? _agentLines;

  /// The lines of [text] the agent changed since [IdeDiffAgentMarks.base];
  /// none where the texts are too long to compare here.
  List<LineRange> _agentLinesOf(DocumentSnapshot text, String base) {
    if (_agentLines case (final known, final from, final lines)
        when identical(known, text) && from == base) {
      return lines;
    }
    List<String> lines(DocumentSnapshot text) => [
      for (var i = 0; i < text.lineCount; i++)
        text.text.substring(text.lineStarts[i], text.contentEnds[i]),
    ];
    final before = lines(DocumentSnapshot(base));
    final after = lines(text);
    final ranges = isSmallLinesDiff(before, after)
        ? [
            for (final change
                in DefaultLinesDiffComputer()
                    .computeDiff(
                      before,
                      after,
                      const LinesDiffComputerOptions(
                        maxComputationTimeMs: 1000,
                      ),
                    )
                    .changes)
              change.modified,
          ]
        : const <LineRange>[];
    _agentLines = (text, base, ranges);
    return ranges;
  }

  Timer? _write;
  StreamSubscription<Object?>? _edits;

  /// Lets it be shown in place of what was before (see [ShownWhenReady]),
  /// once compared, scrolled to where it opens ([_placed]) and its lines
  /// colored ([_colored]): not each in turn.
  VoidCallback? _release;
  bool _placed = false;
  bool _colored = false;

  void _readyIf() {
    final release = _release;
    if (release == null || !_placed) return;
    if (!_colored) {
      // Colored once a language is picked, its lines on screen.
      if (_highlight != null) _firstColors();
      return;
    }
    _release = null;
    release();
  }

  /// The lines on screen colored, or none to be: once placed there.
  void _firstColors() {
    final highlight = _highlight;
    if (highlight != null) {
      final range = _view?.visibleLineRange;
      if (!_placed || range == null) return;
      final styled = highlight.styledLines;
      if (!styled.containsKey(range.first) && !styled.containsKey(range.last)) {
        return;
      }
      highlight.removeListener(_firstColors);
    }
    _colored = true;
    _readyIf();
  }

  TextMateSyntax get _textMate =>
      widget.highlights?.syntax ??
      (_ownTextMate ??= TextMateSyntax(themes: _themes));

  @override
  void initState() {
    super.initState();
    _themes.addListener(_changed);
    _options.addListener(_optionsChanged);
    widget.checks?.addListener(_changed);
    _whitespace = _ignoredWhitespace;
    _release = ShownWhenReady.hold(context);
    _open(widget.modified);
  }

  IdeDiffWhitespace get _ignoredWhitespace =>
      widget.checks == null ? _options.whitespace : IdeDiffWhitespace.none;

  @override
  void didUpdateWidget(IdeCodeDiff oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.checks, widget.checks)) {
      oldWidget.checks?.removeListener(_changed);
      widget.checks?.addListener(_changed);
    }
    if (oldWidget.original != widget.original ||
        oldWidget.modified != widget.modified ||
        oldWidget.path != widget.path) {
      _flush();
      _close();
      _open(widget.modified);
    } else if (oldWidget.line != widget.line) {
      _revealed = false;
      _reveal();
    }
  }

  @override
  void dispose() {
    _texts++;
    _flush();
    _release?.call();
    _themes.removeListener(_changed);
    _options.removeListener(_optionsChanged);
    widget.checks?.removeListener(_changed);
    _close();
    _ownTextMate?.dispose();
    _ownPosition.dispose();
    _viewTick.dispose();
    _hovered.dispose();
    super.dispose();
  }

  void _open(String text) {
    final texts = ++_texts;
    _revealed = false;
    _change = -1;
    final document = EditorDocumentModel(text);
    _modified = EditorSurfaceController(document: document)
      ..onCopy = widget.onCopy;
    _original = IdeDiffOriginal(() async => widget.original)
      ..text.value = widget.original;
    _diff = IdeOriginalDiff(
      _original,
      document,
      onChanged: _changed,
      ignoreTrimWhitespace: _whitespace != IdeDiffWhitespace.none,
      ignoreAllWhitespace: _whitespace == IdeDiffWhitespace.all,
    );
    _diff.model.addListener(_compared);
    // Small texts are compared at once, before there was a listener.
    if (_diff.model.mappings != null) {
      final diff = _diff;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(diff, _diff)) _compared();
      });
    }
    if (widget.onEdit != null) {
      _edits = document.changes.listen((_) => _edited());
    }
    unawaited(_pickLanguage(texts));
  }

  void _close() {
    unawaited(_edits?.cancel());
    _edits = null;
    _highlight?.removeListener(_changed);
    _highlight?.removeListener(_firstColors);
    _highlight?.dispose();
    _highlight = null;
    _diff.model.removeListener(_compared);
    _diff.dispose();
    _original.dispose();
    final document = _modified.document;
    _modified.dispose();
    document.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Whitespace ignored or not: compared again, the text as it is now.
  void _optionsChanged() {
    final ignore = _ignoredWhitespace;
    if (ignore != _whitespace) {
      _whitespace = ignore;
      final text = _modified.document.text;
      _flush();
      _close();
      _open(text);
    }
    _changed();
  }

  void _compared() {
    final count = _diff.model.mappings?.length ?? 0;
    if (_change >= count) _change = count - 1;
    _position.value = (current: _change, count: count);
    _changed();
    _reveal();
  }

  // --- Editing ---------------------------------------------------------------

  void _edited() {
    _write?.cancel();
    _write = Timer(IdeCodeDiff.writeDelay, _flush);
  }

  /// Writes what is pending now.
  void _flush() {
    final pending = _write;
    if (pending == null) return;
    pending.cancel();
    _write = null;
    final onEdit = widget.onEdit;
    if (onEdit == null) return;
    unawaited(onEdit(_modified.document.text));
  }

  /// [change] taken out of the modified side: its lines as the original
  /// has them (JetBrains' `>>`, or `×` for lines only added).
  void revert(LineRangeMapping change) {
    final original = _diff.model.originalSnapshot;
    if (original == null || widget.onEdit == null) return;
    _modified.applyEdits([
      ideDiffRevertEdit(change, original, _modified.document.snapshot),
    ]);
    // Shown reverted at once, not after the edit's debounce.
    _diff.model.refresh();
    _edited();
    _flush();
  }

  // --- Stepping --------------------------------------------------------------

  /// Steps [delta] changes on (F7, Shift+F7), and shows that one; false
  /// past the first or last, for the next file to be shown instead.
  bool step(int delta) {
    final mappings = _diff.model.mappings;
    if (mappings == null || mappings.isEmpty) return false;
    final next = _change < 0 && delta < 0
        ? mappings.length - 1
        : _change + delta;
    if (next < 0 || next >= mappings.length) return false;
    _showChange(next);
    return true;
  }

  void _showChange(int index) {
    final mappings = _diff.model.mappings;
    if (mappings == null || index < 0 || index >= mappings.length) return;
    _change = index;
    _position.value = (current: index, count: mappings.length);
    _revealLine(mappings[index].modified.startLineNumber);
  }

  // --- Language --------------------------------------------------------------

  Future<void> _pickLanguage(int texts) async {
    final path = widget.path;
    final text = _modified.document.text;
    final end = text.indexOf('\n');
    final firstLine = (end < 0 ? text : text.substring(0, end)).replaceFirst(
      '﻿',
      '',
    );
    try {
      final configuration = await languageConfigurationForPath(
        path,
        firstLine: firstLine,
      );
      if (!mounted || texts != _texts) return;
      if (configuration != null) {
        _modified.languageConfiguration = configuration;
      }
      final languageId = await _textMate.languageIdForPath(
        path,
        firstLine: firstLine,
      );
      if (!mounted || texts != _texts) return;
      if (languageId == null) return _firstColors();
      _highlight = _textMate.open(languageId, _modified.document.snapshot)
        ?..addListener(_changed)
        ..addListener(_firstColors);
      if (_highlight == null) _firstColors();
      _diff.highlight(_textMate, languageId);
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => _viewChanged());
    } on Object {
      // Plain text, then.
      if (mounted && texts == _texts) _firstColors();
    }
  }

  EditorSurfaceView? get _view => switch (_modifiedKey.currentState) {
    final EditorSurfaceView view => view,
    _ => null,
  };

  /// The lines on screen go to the TextMate worker first; the arrows
  /// follow the text.
  void _viewChanged() {
    if (!mounted) return;
    if (_view?.visibleLineRange case final range?) {
      _highlight?.setViewport(range.first, range.last);
    }
    _viewTick.value++;
  }

  /// A few lines over [IdeCodeDiff.line], else the first change (or the
  /// last, [IdeCodeDiff.start]), once the texts are compared and laid out.
  void _reveal() {
    final mappings = _diff.model.mappings;
    if (_revealed || mappings == null) return;
    _revealed = true;
    if (widget.line case final line?) {
      _revealLine(line);
      return;
    }
    if (mappings.isEmpty) {
      _placed = true;
      return _readyIf();
    }
    _showChange(widget.start == IdeDiffStart.last ? mappings.length - 1 : 0);
  }

  void _revealLine(int line) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final snapshot = _modified.document.snapshot;
      final at = (line - 1).clamp(0, snapshot.lineCount - 1);
      final offset = snapshot.lineStarts[at];
      _view?.revealRange(offset, offset, center: true);
      _viewTick.value++;
      _placed = true;
      _readyIf();
    });
  }

  // --- Building --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = _themes.colors;
    final theme = EditorViewTheme.fromColors(colors.get);
    final type = getThemeTypeSelector(_themes.colorTheme.type);
    final style = AppFonts.codeStyle(13)
        .copyWith(color: colors['editor.foreground'], height: 1.45);
    final editable = widget.onEdit != null;
    final overlay = editable || widget.checks != null || widget.onAsk != null;
    return DiffEditor(
      key: ObjectKey(_diff),
      model: _diff.model,
      style: style,
      theme: theme,
      colors: DiffEditorColors.from(colors.get),
      dark:
          type == ThemeTypeSelector.vsDark || type == ThemeTypeSelector.hcBlack,
      originalStyledLines: _diff.textMate?.styledLines,
      border: colors.get('diffEditor.border'),
      sashHover: colors.get('sash.hoverBorder'),
      sideBySide: _options.sideBySide,
      highlight: _options.highlight,
      hideUnchanged: _options.collapseUnchanged,
      unchangedLabel: context.l10n.diffUnchangedLines,
      keepVisible: widget.line,
      overlay: overlay ? _overlay : null,
      original: (context, side) {
        final controller = _diff.controller;
        if (controller == null) return const SizedBox.expand();
        return EditorSurface(
          // Found by it for its lines' check boxes.
          key: GlobalObjectKey(controller),
          controller: controller,
          readOnly: true,
          backgroundColor: colors['editor.background'],
          selectionColor: colors['editor.selectionBackground'],
          caretColor: colors['editorCursor.foreground'],
          theme: theme,
          styledLines: _diff.textMate?.styledLines,
          decorations: side.decorations,
          viewZones: side.zones,
          scrollPosition: side.scrollPosition,
          glyphMargin: side.sideBySide,
          folding: false,
          hiddenLines: side.hiddenLines,
          showMinimap: false,
          style: style,
        );
      },
      modified: (context, side) => EditorSurface(
        key: _modifiedKey,
        controller: _modified,
        readOnly: !editable,
        backgroundColor: colors['editor.background'],
        selectionColor: colors['editor.selectionBackground'],
        caretColor: colors['editorCursor.foreground'],
        theme: theme,
        styledLines: _highlight?.styledLines,
        decorations: side.decorations,
        viewZones: side.zones,
        scrollPosition: side.scrollPosition,
        folding: false,
        hiddenLines: side.hiddenLines,
        showMinimap: false,
        onViewChanged: _viewChanged,
        style: style,
      ),
    );
  }

  /// By each change, at its top: a revert arrow where the file can be
  /// edited (on the split side by side, at the modified editor's left edge
  /// inline), and a check box where it can be left out of a commit (at the
  /// modified editor's left edge, the arrow then after it inline).
  Widget _overlay(BuildContext context, DiffEditorLayout layout) =>
      ListenableBuilder(
        listenable: Listenable.merge([_viewTick, _hovered]),
        builder: (context, _) {
          final view = _view;
          final area = view?.textArea;
          final mappings = _diff.model.mappings;
          final original = _diff.model.originalSnapshot;
          if (view == null ||
              area == null ||
              mappings == null ||
              original == null) {
            return const SizedBox.shrink();
          }
          final snapshot = _modified.document.snapshot;
          const size = 16.0;
          const lineSize = 14.0;
          final checks = widget.checks;
          final mapped = _diff.model.mappedSnapshot;
          // Keyed by the text they were found in; none while it was edited
          // since.
          final keys = checks != null && identical(mapped, snapshot)
              ? ideGitHunkKeys(original, snapshot, mappings)
              : null;
          final arrowLeft = layout.sideBySide
              ? layout.splitLeft - size / 2
              : layout.modifiedLeft + (checks == null ? 2 : 22);
          final originalView = switch (_diff.controller) {
            final controller? when layout.sideBySide => switch (GlobalObjectKey(
              controller,
            ).currentState) {
              final EditorSurfaceView view => view,
              _ => null,
            },
            _ => null,
          };
          // A line's check box, at the right of its editor's gutter.
          Widget? lineCheck(
            EditorSurfaceView view,
            DocumentSnapshot text,
            double left,
            int line,
            String hunk,
            String key,
            List<String> lines,
          ) {
            final area = view.textArea;
            final rect = view.caretRectAt(text.lineStarts[line - 1]);
            if (area == null || rect == null) return null;
            if (rect.top < area.top - 2 || rect.bottom > area.bottom + 2) {
              return null;
            }
            final excluded = checks!.isIncluded(hunk) == false;
            final included = !excluded && checks.isIncluded(key);
            return Positioned(
              key: ValueKey(('line', key)),
              left: left + area.left - lineSize - 2,
              top: (rect.top + rect.bottom - lineSize) / 2,
              width: lineSize,
              height: lineSize,
              child: _HunkCheck(
                checked: included,
                line: true,
                onTap: () {
                  if (excluded) {
                    // Of a change left out, this line alone in.
                    checks.setIncluded(hunk, true);
                    for (final other in lines) {
                      if (other != key) checks.setIncluded(other, false);
                    }
                  } else {
                    checks.setIncluded(key, !included);
                  }
                },
              ),
            );
          }

          final children = <Widget>[];
          for (final (index, change) in mappings.indexed) {
            final top = ideDiffChangeTop(view, snapshot, change);
            if (top == null) continue;
            final shows = top >= area.top - 2 && top + size <= area.bottom;
            if (shows && widget.onEdit != null) {
              children.add(
                Positioned(
                  key: ObjectKey(change),
                  left: arrowLeft,
                  top: top + (view.lineHeight - size) / 2,
                  width: size,
                  height: size,
                  child: IdeDiffRevertArrow(
                    added: change.original.isEmpty,
                    onTap: () => revert(change),
                  ),
                ),
              );
            }
            if (widget.agent case final agent?
                when shows && agent.turns.isNotEmpty) {
              final m = change.modified;
              final mine = _agentLinesOf(snapshot, agent.base).any(
                (lines) => m.isEmpty || lines.isEmpty
                    ? lines.startLineNumber <= m.endLineNumberExclusive &&
                          m.startLineNumber <= lines.endLineNumberExclusive
                    : lines.startLineNumber < m.endLineNumberExclusive &&
                          m.startLineNumber < lines.endLineNumberExclusive,
              );
              if (mine) {
                children.add(
                  Positioned(
                    key: ObjectKey((change, 'agent')),
                    right: DiffEditor.overviewWidth + 34,
                    top: top + 1,
                    height: view.lineHeight - 2,
                    child: _AgentMark(turns: agent.turns),
                  ),
                );
              }
            }
            if (widget.onAsk case final ask?
                when shows && _hovered.value == index) {
              children.add(
                Positioned(
                  key: ObjectKey((change, 'ask')),
                  right: DiffEditor.overviewWidth + 10,
                  top: top + (view.lineHeight - size) / 2,
                  width: size + 2,
                  height: size + 2,
                  child: IdeActionButton(
                    icon: Codicons.sparkle,
                    tooltip: context.l10n.gitAskAiHunk,
                    onPressed: () => ask(
                      _changeText(original, snapshot, change),
                      change.modified.startLineNumber,
                    ),
                  ),
                ),
              );
            }
            if (keys == null) continue;
            final hunk = keys[index];
            final removed = [
              for (var n = 0; n < change.original.length; n++)
                ideGitLineKey(hunk, n, removed: true),
            ];
            final added = [
              for (var n = 0; n < change.modified.length; n++)
                ideGitLineKey(hunk, n, removed: false),
            ];
            final lines = [...removed, ...added];
            final out = lines.where((key) => !checks!.isIncluded(key)).length;
            final bool? state = !checks!.isIncluded(hunk) || out == lines.length
                ? false
                : out == 0
                ? true
                : null;
            if (shows) {
              children.add(
                Positioned(
                  key: ObjectKey((change, 'check')),
                  left: layout.modifiedLeft + 2,
                  top: top + (view.lineHeight - size) / 2,
                  width: size,
                  height: size,
                  child: _HunkCheck(
                    checked: state,
                    onTap: () => checks.setIncluded(hunk, state != true),
                  ),
                ),
              );
            }
            // Its lines' check boxes, while the pointer is on it or some of
            // them are left out; those of the lines taken out where the
            // original shows beside.
            if (_hovered.value != index && state != null) continue;
            if (lines.length < 2) continue;
            for (final (n, key) in added.indexed) {
              children.add(
                lineCheck(
                      view,
                      snapshot,
                      layout.modifiedLeft,
                      change.modified.startLineNumber + n,
                      hunk,
                      key,
                      lines,
                    ) ??
                    const SizedBox.shrink(),
              );
            }
            if (originalView != null) {
              for (final (n, key) in removed.indexed) {
                children.add(
                  lineCheck(
                        originalView,
                        original,
                        0,
                        change.original.startLineNumber + n,
                        hunk,
                        key,
                        lines,
                      ) ??
                      const SizedBox.shrink(),
                );
              }
            }
          }
          return MouseRegion(
            opaque: false,
            hitTestBehavior: HitTestBehavior.translucent,
            onHover: keys == null && widget.onAsk == null
                ? null
                : (event) => _hovered.value = _changeAt(
                    view,
                    snapshot,
                    mappings,
                    event.localPosition.dy,
                  ),
            onExit: (_) => _hovered.value = null,
            child: Stack(children: children),
          );
        },
      );

  /// [change]'s lines, `-` those [original] had, `+` those [modified] has.
  static String _changeText(
    DocumentSnapshot original,
    DocumentSnapshot modified,
    LineRangeMapping change,
  ) {
    String line(DocumentSnapshot text, int number) => text.text.substring(
      text.lineStarts[number - 1],
      text.contentEnds[number - 1],
    );
    return [
      for (
        var n = change.original.startLineNumber;
        n < change.original.endLineNumberExclusive;
        n++
      )
        '-${line(original, n)}',
      for (
        var n = change.modified.startLineNumber;
        n < change.modified.endLineNumberExclusive;
        n++
      )
        '+${line(modified, n)}',
    ].join('\n');
  }

  /// The change at [y], from its top to the line after it.
  static int? _changeAt(
    EditorSurfaceView view,
    DocumentSnapshot text,
    List<LineRangeMapping> mappings,
    double y,
  ) {
    for (final (index, change) in mappings.indexed) {
      final top = ideDiffChangeTop(view, text, change);
      if (top == null || y < top - 2) continue;
      final end = change.modified.endLineNumberExclusive;
      final bottom = end > text.lineCount
          ? view.caretRectAt(text.text.length)?.bottom
          : view.caretRectAt(text.lineStarts[end - 1])?.top;
      if (bottom != null && y <= bottom + 2) return index;
    }
    return null;
  }
}

/// The edit taking [change] out of [modified]: its lines as [original] has
/// them.
EditorOffsetEdit ideDiffRevertEdit(
  LineRangeMapping change,
  DocumentSnapshot original,
  DocumentSnapshot modified,
) {
  final spans = agentHunkSpans(change, original, modified);
  return EditorOffsetEdit(
    spans.modifiedStart,
    spans.modifiedEnd,
    original.text.substring(spans.originalStart, spans.originalEnd),
  );
}

/// Where [change] starts in the modified editor [view] of [text]: the
/// bottom of the line before it (the top of the deleted code over it,
/// inline).
double? ideDiffChangeTop(
  EditorSurfaceView view,
  DocumentSnapshot text,
  LineRangeMapping change,
) {
  final start = change.modified.startLineNumber;
  if (start <= 1) return view.caretRectAt(0)?.top;
  final line = (start - 2).clamp(0, text.lineCount - 1);
  return view.caretRectAt(text.lineStarts[line])?.bottom;
}

/// JetBrains' `>>` by a change (`×` for lines only added): reverts it.
class IdeDiffRevertArrow extends StatefulWidget {
  const IdeDiffRevertArrow({
    super.key,
    required this.added,
    required this.onTap,
  });

  final bool added;
  final VoidCallback onTap;

  @override
  State<IdeDiffRevertArrow> createState() => _IdeDiffRevertArrowState();
}

class _IdeDiffRevertArrowState extends State<IdeDiffRevertArrow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final l10n = context.l10n;
    return IdeHover(
      message: widget.added ? l10n.diffRemoveChange : l10n.diffRevertChange,
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
              widget.added ? Codicons.close : Codicons.arrowRight,
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

/// JetBrains' check box by a change: whether it goes in the commit.
class _HunkCheck extends StatelessWidget {
  const _HunkCheck({
    required this.checked,
    required this.onTap,
    this.line = false,
  });

  /// Null for a change some of whose lines are left out.
  final bool? checked;
  final VoidCallback onTap;

  /// A line's, smaller.
  final bool line;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final l10n = context.l10n;
    // As the commit panel's: checkbox.selectBackground is a gray.
    final accent = colors['button.background'];
    final on = checked != false;
    final box = line ? 11.0 : 13.0;
    return IdeHover(
      message: switch ((checked, line)) {
        (true, true) => l10n.gitDiffExcludeLine,
        (_, true) => l10n.gitDiffIncludeLine,
        (true, _) => l10n.gitDiffExcludeChange,
        _ => l10n.gitDiffIncludeChange,
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Center(
            child: Container(
              width: box,
              height: box,
              decoration: BoxDecoration(
                color: on ? accent : colors.get('checkbox.background'),
                border: Border.all(
                  color: on
                      ? accent
                      : colors.get('checkbox.border') ??
                            colors['editorLineNumber.foreground'],
                ),
                borderRadius: BorderRadius.circular(line ? 2 : 3),
              ),
              child: on
                  ? Icon(
                      checked == null ? Codicons.dash : Codicons.check,
                      size: box - 2,
                      color: colors['button.foreground'],
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Over a change the agent made: the turn's request, the start of it
/// (all the turns' in full, hovered).
class _AgentMark extends StatelessWidget {
  const _AgentMark({required this.turns});

  final List<String> turns;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final line = turns.last.trim().split('\n').first.trim();
    final title = line.length > 32 ? '${line.substring(0, 32)}…' : line;
    final foreground = colors['badge.foreground'];
    return IdeHover(
      message: [for (final turn in turns) turn.trim()].join('\n\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors['badge.background'],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Codicons.sparkle, size: 11, color: foreground),
            const SizedBox(width: 4),
            Text(
              title.isEmpty ? 'AI' : 'AI · $title',
              maxLines: 1,
              style: TextStyle(fontSize: 11, height: 1, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
