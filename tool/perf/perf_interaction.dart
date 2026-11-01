// The scenarios of the hands: the window's parts dragged wider and
// narrower (the sidebar, the side panel, the stash beside its cards, the
// grid's lines, the IDE's sashes), agents dragged into the grid, text
// selected in the chat and the editor, the caret moved, the composer typed
// into, lists scrolled, the app left idle, and the same work done over and
// over to see whether memory comes back.
//
// Each checks that what the hand did had its effect (`c.check`): a sash
// that lags the pointer, a selection that copies nothing or changes as the
// answer streams, a caret off screen, is the app failing the user whatever
// its frames.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:bao_markdown/bao_markdown.dart'
    show
        MarkdownEditor,
        MarkdownController,
        MarkdownEditorState,
        MarkdownEditing,
        RenderMdLine;
import 'package:baocode/chat/chat_history_view.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/stash/stash_controller.dart';
import 'package:baocode/stash/stash_editor.dart';
import 'package:baocode/stash/stash_view.dart';
import 'package:baocode/workspace/chat_drag.dart';
import 'package:baocode/workspace/chat_grid.dart';
import 'package:baocode/workspace/workspace.dart';

import 'perf_memory.dart';
import 'perf_probe.dart';
import 'perf_scenarios.dart';
import 'perf_transport.dart';

const _short = Duration(milliseconds: 150);

/// Drags a handle [by] and back, [times] over, at a mouse's pace (60 moves
/// 8ms apart, half a second), checking each way that what it moves
/// followed the pointer: [along] (by default, where the handle is) moved
/// as far as the pointer did, give or take [slack] pixels.
Future<void> _sweep(
  PerfContext c,
  String what,
  Rect Function() handle,
  Offset by, {
  int times = 3,
  double Function()? along,
  double slack = 2,
}) async {
  final horizontal = by.dy == 0;
  double at() =>
      along?.call() ?? (horizontal ? handle().center.dx : handle().center.dy);
  for (var i = 0; i < times; i++) {
    for (final move in [by, -by]) {
      final before = at();
      final from = handle().center;
      await c.input.drag(from, from + move, hold: _short);
      await c.settle(_short);
      final moved = at() - before;
      final wanted = horizontal ? move.dx : move.dy;
      c.check(
        (moved - wanted).abs() <= slack,
        '$what follows the pointer: moved ${moved.toStringAsFixed(1)}px of '
        '${wanted.toStringAsFixed(1)}',
      );
    }
  }
}

/// Waits [time], asking for no frame ([PerfContext.settle] does): what
/// the app draws meanwhile, it draws of itself.
Future<void> _rest(Duration time) => Future<void>.delayed(time);

/// The phase [name]'s figure [path] (keys, dot separated), once measured.
Object? _figure(PerfContext c, String name, String path) {
  Object? value = c.results[name];
  for (final key in path.split('.')) {
    value = value is Map ? value[key] : null;
  }
  return value;
}

/// Checks the phase [name] left the app at rest: at most [frames] frames a
/// second (a caret blinking draws two), at most [cpu]% of a core.
void _checkIdle(PerfContext c, String name, {int frames = 12, int cpu = 8}) {
  final perSecond = _figure(c, name, 'frames.perSecond');
  final pct = _figure(c, name, 'cpu.pctOfCore');
  c.check(
    perSecond is! num || perSecond <= frames,
    '$name: at rest, the app draws $perSecond frames a second',
  );
  c.check(
    pct is! num || pct <= cpu,
    '$name: at rest, the app takes $pct% of a core',
  );
}

/// The word of the text shown at [global] (a paragraph's, hit tested as
/// a click is), when a letter of one is there.
String? _wordAt(Offset global) {
  final result = HitTestResult();
  final binding = WidgetsBinding.instance;
  binding.hitTestInView(
    result,
    global,
    binding.platformDispatcher.implicitView!.viewId,
  );
  for (final entry in result.path) {
    final target = entry.target;
    if (target is! RenderParagraph) continue;
    final text = target.text.toPlainText(includeSemanticsLabels: false);
    final local = target.globalToLocal(global);
    // On the text, not beside it on the line.
    final boxes = target.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    if (!boxes.any((box) => box.toRect().contains(local))) return null;
    final offset = target.getPositionForOffset(local).offset;
    final word = RegExp(r'\w');
    if (offset >= text.length || !word.hasMatch(text[offset])) return null;
    var start = offset, end = offset;
    while (start > 0 && word.hasMatch(text[start - 1])) {
      start--;
    }
    while (end < text.length && word.hasMatch(text[end])) {
      end++;
    }
    return text.substring(start, end);
  }
  return null;
}

/// Points over the conversation [view] with a word under them, [count]
/// of them, from the top down.
List<(Offset, String)> _wordsIn(Rect view, int count) {
  final found = <(Offset, String)>[];
  for (var y = view.top + 60; y < view.bottom - 60; y += 37) {
    for (var x = view.left + 70; x < view.right - 100; x += 53) {
      if (_wordAt(Offset(x, y)) case final word? when word.length > 2) {
        found.add((Offset(x, y), word));
        break;
      }
    }
    if (found.length == count) break;
  }
  return found;
}

Rect _sidebarRect(PerfContext c) => c.rectOf(c.find<Sidebar>()!);

/// The sidebar's row of [thread].
Element? _rowOf(PerfContext c, AgentThread thread) =>
    c.find<ChatDragSource>(where: (w) => identical(w.thread, thread));

StashController get _stash => StashController.current!;

/// A stash's text in [element] (a [StashEditor]'s), as a hand works it.
class _StashHand {
  _StashHand(this.c, this.element);

  final PerfContext c;
  Element element;

  MarkdownController get controller => switch (element.widget) {
    StashEditor(:final controller) => controller,
    MarkdownEditor(:final controller) => controller,
    _ => throw StateError('no markdown editor'),
  };

  /// Its text, inside the padding (a stash's 20 at the sides, 12 at the
  /// top; a markdown preview's, as wide as a page).
  Rect get area {
    final rect = c.rectOf(element);
    if (element.widget case MarkdownEditor(:final padding)) {
      return Rect.fromLTRB(
        rect.left + padding.left,
        rect.top + 12,
        rect.right - padding.right,
        rect.bottom - 12,
      );
    }
    return rect.deflate(24);
  }

  /// What lays its text out, and where.
  MarkdownEditorState? get editor => switch (element) {
    StatefulElement(:final StashEditorState state) => state.markdownEditor,
    StatefulElement(:final MarkdownEditorState state) => state,
    _ => null,
  };

  /// A selection's bar shows over the text: put away before the next.
  /// Not by a click: one lands on the bar where it shows (its Polish
  /// opens the menu of models, over everything), or makes a double.
  Future<void> collapse() async {
    final selection = controller.selection;
    controller.selection = TextSelection.collapsed(
      offset: selection.extentOffset,
    );
    await c.settle(_short);
  }

  /// Whether [at] is over its text: a click there goes to the editor, no
  /// tag's or block's own region (a picture's, a table's) on the way.
  static bool onText(Offset at) {
    final hit = HitTestResult();
    final binding = WidgetsBinding.instance;
    binding.hitTestInView(
      hit,
      at,
      binding.platformDispatcher.implicitView!.viewId,
    );
    for (final entry in hit.path) {
      switch (entry.target) {
        case RenderMdLine(:final isText):
          return isText;
        case RenderPointerListener() ||
            RenderMouseRegion() ||
            RenderSemanticsGestureHandler():
          return false;
      }
    }
    return false;
  }

  /// [count] drags over the text, 40 moves each: what each copies, and
  /// whether the selection kept up with the pointer: after each move, it
  /// ends at the character under it.
  Future<List<int>> drags(int count, PerfRecording r) async {
    final editor = this.editor;
    final copies = <int>[];
    var moves = 0;
    final behind = <int>[];
    for (var i = 0; i < count; i++) {
      final at = area;
      var top = at.top + 30 + i * 22.0;
      // From a line of text, not a block (a code block, a table) of its
      // own that takes the press.
      while (!onText(Offset(at.left + 10, top)) && top < at.center.dy) {
        top += 6;
      }
      await c.input.drag(
        Offset(at.left + 10, top),
        Offset(at.left + min(320, at.width - 20), top + 180),
        steps: 40,
        moved: (point) {
          final selection = controller.selection;
          final under = editor!.offsetAt(point);
          // A drag only begins past a few pixels: from then on.
          if (selection.isCollapsed || under == null) return;
          moves++;
          if (selection.extentOffset != under) {
            behind.add(under - selection.extentOffset);
          }
        },
      );
      await c.settle(_short);
      final copied = controller.selection.isCollapsed ? '' : await c.copy();
      copies.add(copied?.length ?? 0);
      // Too little copied (see the check below): what was, in the log.
      if ((copied?.length ?? 0) <= 40) {
        final selection = controller.selection;
        PerfContext.log(
          'drag $i copied ${jsonEncode(copied)}, selected '
          '${jsonEncode(controller.substring(selection.start, selection.end))}',
        );
      }
      await collapse();
    }
    r.extra['selectionBehind'] = '${behind.length} of $moves moves';
    c.check(
      editor != null && moves > count * 30 && behind.isEmpty,
      'the selection follows the pointer, each move: behind it after '
      '${behind.length} of $moves (by ${behind.take(8).toList()} chars)',
    );
    return copies;
  }
}

/// Shows the stashes' page, and [id] beside its cards if given.
Future<void> _showStash(PerfContext c, [int? id]) async {
  // The page first: what shows a stash is built with it.
  _stash.showPage!(id ?? _stash.store.notes.first.id);
  await c.settle();
  if (id != null) {
    _stash.showPage!(id);
    await c.settle();
  }
}

final List<PerfScenario> interactionScenarios = [
  // --- Dragging ----------------------------------------------------------------
  PerfScenario(
    'drag.sidebar',
    'The sidebar\'s edge dragged 150px wider and back, three times, beside a '
        'conversation of 20 turns: each time, the sidebar as wide as the '
        'pointer took it.',
    (c) async {
      await c.agents(6);
      await c.history(c.agent, 20);
      await c.settle();
      await c.phase('sweep', (r) async {
        Rect handle() {
          final sidebar = _sidebarRect(c);
          return Rect.fromLTWH(sidebar.right, sidebar.top + 200, 5, 40);
        }

        await _sweep(
          c,
          'the sidebar',
          handle,
          const Offset(150, 0),
          along: () => _sidebarRect(c).width,
        );
      });
    },
  ),
  PerfScenario(
    'drag.side_panel',
    'The side panel\'s edge dragged 100px across and back, three times, '
        'beside a conversation of 20 turns.',
    (c) async {
      await c.history(c.agent, 20);
      final area = c.find<AgentSidePanelArea>();
      c.check(area != null, 'the side panel is there');
      if (area == null) return;
      final panel = (area.widget as AgentSidePanelArea).panel..show();
      await c.settle(const Duration(seconds: 1));
      Rect handle() => c.rectKeyed('side-panel-sash')!;
      c.check(c.rectKeyed('side-panel-sash') != null, 'the side panel shows');
      if (c.rectKeyed('side-panel-sash') == null) return;
      await c.phase('sweep', (r) async {
        r.extra['storedWidth'] = panel.width;
        r.extra['shownWidth'] = c.rectOf(area).right - handle().center.dx;
        // Narrower first: it opens as wide as the room lets it.
        await _sweep(c, 'the side panel', handle, const Offset(100, 0));
        r.extra['panelWidth'] = panel.width;
      });
    },
  ),
  PerfScenario(
    'drag.stash',
    'On the stashes\' page, a stash shown beside the cards: the line between '
        'them dragged across and back, three times.',
    (c) async {
      await c.history(c.agent, 2);
      await _showStash(c, _stash.store.notes[3].id);
      Rect handle() => c.rectKeyed('stash-sash')!;
      c.check(c.rectKeyed('stash-sash') != null, 'the stash shows');
      if (c.rectKeyed('stash-sash') == null) return;
      await c.phase('sweep', (r) async {
        // Its room beside the cards in 1024px is narrow: 380 to 440px.
        await _sweep(c, 'the stash', handle, const Offset(-50, 0));
      });
    },
  ),
  PerfScenario(
    'drag.grid',
    'Four agents side by side (2×2): the line between the columns dragged, '
        'then the one between the rows, then both while the four answer.',
    (c) async {
      final agents = await c.agents(4, history: 6);
      final [a, b, d, e] = agents;
      c.workspace
        ..select(a)
        ..openBeside(b, a, PaneSide.right)
        ..openBeside(d, a, PaneSide.bottom)
        ..openBeside(e, b, PaneSide.bottom);
      await c.settle();
      // Away from where the two lines cross, which the row line takes.
      Rect columns() {
        final line = c.rectKeyed('column sash')!;
        return Rect.fromCenter(
          center: Offset(line.center.dx, line.top + line.height / 4),
          width: line.width,
          height: 20,
        );
      }

      Rect rows() {
        final line = c.rectKeyed('row sash 0')!;
        return Rect.fromCenter(
          center: Offset(line.left + line.width / 4, line.center.dy),
          width: 20,
          height: line.height,
        );
      }

      // Two panes at their least (360×300) are most of the room in 1024px:
      // the lines move 20px (columns) and 45px (rows) either way.
      const across = Offset(15, 0), down = Offset(0, 40);
      c.check(
        c.rectKeyed('column sash') != null && c.rectKeyed('row sash 0') != null,
        'the grid has its lines',
      );
      if (c.rectKeyed('row sash 0') == null) return;
      await c.phase('columns', (r) async {
        await _sweep(c, 'the columns\' line', columns, across);
      });
      await c.phase('rows', (r) async {
        await _sweep(c, 'the rows\' line', rows, down);
      });
      await c.phase('while_streaming', (r) async {
        final ends = [for (final t in agents) t.session.lastTurnEndSeq];
        for (final thread in agents) {
          await c.start(thread, c.reply(6000, PerfPace.fast, heavy: true));
        }
        await _sweep(c, 'the columns\' line', columns, across);
        await _sweep(c, 'the rows\' line', rows, down);
        await c.until(
          () => [
            for (final (i, t) in agents.indexed)
              t.session.lastTurnEndSeq > ends[i] && !t.session.isStreaming,
          ].every((ended) => ended),
          'the four turns',
        );
      });
    },
  ),
  PerfScenario(
    'drag.agent_into_grid',
    'Three agents dragged from the sidebar onto the conversation, one '
        'beside it, then below each: the grid as they were dropped.',
    (c) async {
      final first = c.agent;
      await c.history(first, 6);
      final others = await c.agents(3, history: 6);
      c.workspace.select(first);
      await c.settle();
      await c.phase('drops', (r) async {
        Rect chat() => c.rectOf(c.find<ChatHistoryView>()!);
        // Where each goes: the right edge of the first, then the bottom
        // edges of the two columns.
        final targets = <Offset Function()>[
          () => Offset(chat().right - 30, chat().center.dy),
          () {
            final rect = c.rectOf(c.findNamed('ChatHistoryView').first);
            return Offset(rect.center.dx, rect.bottom - 20);
          },
          () {
            final rect = c.rectOf(c.findNamed('ChatHistoryView')[1]);
            return Offset(rect.center.dx, rect.bottom - 20);
          },
        ];
        for (final (i, thread) in others.indexed) {
          final row = _rowOf(c, thread);
          c.check(row != null, 'agent ${i + 2} has a row in the sidebar');
          if (row == null) return;
          final from = c.rectOf(row).center;
          await c.input.drag(
            from,
            targets[i](),
            steps: 80,
            hold: const Duration(milliseconds: 300),
          );
          await c.settle(const Duration(milliseconds: 500));
          c.check(
            c.workspace.grid.panes.contains(thread),
            'agent ${i + 2}, dropped, shows in the grid '
            '(${c.workspace.grid.panes.length} panes)',
          );
        }
      });
      c.check(
        c.workspace.grid.panes.length == 4,
        'four agents in the grid, not ${c.workspace.grid.panes.length}',
      );
    },
  ),
  PerfScenario(
    'drag.ide',
    'Fast Ide on the 9,000-line file: the side bar\'s edge dragged across '
        'and back, then the chat\'s, three times each.',
    (c) async {
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.bigFile);
      await c.settle(const Duration(seconds: 1));
      Rect sidebar() => c.rectKeyed('ide-sidebar-sash')!;
      Rect chat() => c.rectKeyed('ide-chat-sash')!;
      c.check(
        c.rectKeyed('ide-sidebar-sash') != null &&
            c.rectKeyed('ide-chat-sash') != null,
        'the IDE has its sashes',
      );
      if (c.rectKeyed('ide-chat-sash') == null) return;
      await c.phase('sidebar', (r) async {
        // The editor at its least beside them: the side bar grows by what
        // the chat has over its least, 60px.
        await _sweep(c, 'the IDE\'s side bar', sidebar, const Offset(50, 0));
      });
      await c.phase('chat', (r) async {
        await _sweep(c, 'the IDE\'s chat', chat, const Offset(-100, 0));
      });
    },
  ),

  // --- Selecting ---------------------------------------------------------------
  PerfScenario(
    'select.chat',
    'In a conversation of 20 turns: text dragged over and copied, a drag '
        'held past the top (the list scrolling with it), words and '
        'paragraphs by double and triple clicks, text scrolled to by the '
        'wheel, all of it by Cmd+A, then text selected and kept while an '
        'answer streams below it.',
    (c) async {
      await c.history(c.agent, 20);
      await c.settle(const Duration(seconds: 1));
      final history = c.find<ChatHistoryView>()!;
      final view = c.rectOf(history);
      final left = view.left + 60;
      await c.phase('drag', (r) async {
        final copies = <int>[];
        for (var i = 0; i < 6; i++) {
          final top = view.top + 80 + i * 30.0;
          await c.input.drag(
            Offset(left, top),
            Offset(left + 300, top + 220),
            steps: 40,
          );
          await c.settle(_short);
          copies.add((await c.copy())?.length ?? 0);
        }
        r.extra['copiedChars'] = copies;
        c.check(
          copies.every((n) => n > 40),
          'a drag over the conversation copies its text: $copies chars',
        );
      });
      await c.phase('autoscroll', (r) async {
        final before = c.scrolledIn(history);
        await c.input.drag(
          Offset(left, view.bottom - 60),
          Offset(left + 200, view.top - 20),
          steps: 30,
          hold: const Duration(seconds: 2),
        );
        await c.settle(_short);
        final scrolled = (c.scrolledIn(history) - before).abs();
        final copied = (await c.copy())?.length ?? 0;
        r.extra['scrolledPx'] = scrolled.round();
        r.extra['copiedChars'] = copied;
        c.check(
          scrolled > view.height,
          'a selection held past the top scrolls the list: '
          '${scrolled.round()}px',
        );
        final dragged = _figure(c, 'drag', 'copiedChars') as List<int>;
        c.check(
          copied > dragged.reduce(max),
          'what it selected while scrolling copies: $copied chars, more '
          'than the screenful a drag does',
        );
      });
      await c.phase('clicks', (r) async {
        final spots = _wordsIn(view, 8);
        c.check(spots.length == 8, 'words to click: ${spots.length} of 8');
        final wrong = <String>[];
        var paragraphs = 0;
        for (final (at, word) in spots) {
          await c.input.clicks(at, 2);
          await c.settle(_short);
          final copied = await c.copy() ?? '';
          if (copied.trim() != word) wrong.add('$word → "$copied"');
          // Long enough apart not to be the double click's third.
          await c.settle(const Duration(milliseconds: 600));
          await c.input.clicks(at, 3);
          await c.settle(_short);
          final paragraph = await c.copy() ?? '';
          if (paragraph.contains(word) && paragraph.length > word.length) {
            paragraphs++;
          }
          await c.settle(const Duration(milliseconds: 600));
        }
        c.check(
          wrong.isEmpty,
          'a double click selects the word clicked: ${wrong.join(', ')}',
        );
        c.check(
          paragraphs == spots.length,
          'a triple click selects the word\'s paragraph: $paragraphs of '
          '${spots.length}',
        );
      });
      await c.phase('after_wheel', (r) async {
        // Text scrolled to by the wheel, then dragged over.
        await c.input.spin(view.center, -120, 4);
        await c.settle(const Duration(seconds: 1));
        final top = view.top + 100;
        await c.input.drag(
          Offset(left, top),
          Offset(left + 300, top + 160),
          steps: 30,
        );
        await c.settle(_short);
        final copied = (await c.copy())?.length ?? 0;
        c.check(
          copied > 20,
          'text scrolled to by the wheel can be selected: $copied chars '
          'copied',
        );
      });
      await c.phase('select_all', (r) async {
        await c.input.click(Offset(left, view.center.dy));
        await c.settle(_short);
        PerfProbe.instance.mark(PerfMark.action);
        c.input.press(LogicalKeyboardKey.keyA, meta: true);
        await c.settle(const Duration(milliseconds: 300));
        final copied = (await c.copy())?.length ?? 0;
        r.extra['copiedChars'] = copied;
        c.check(
          copied > 30000,
          'Cmd+A copies the whole conversation: $copied chars',
        );
      });
      // Right after Cmd+A, as an answer comes in: what is above it,
      // scrolled back to and selected.
      await c.phase('while_streaming', (r) async {
        final ended = c.agent.session.lastTurnEndSeq;
        await c.start(c.agent, c.reply(14000, PerfPace.fast, heavy: true));
        // What is above the answer, scrolled back to and selected while it
        // streams.
        await c.settle(const Duration(seconds: 1));
        await c.input.spin(view.center, -120, 4);
        // Past the wheel's glide: a press while it glides stops it.
        await c.settle(const Duration(seconds: 1));
        final top = view.top + 100;
        await c.input.drag(
          Offset(left, top),
          Offset(left + 300, top + 160),
          steps: 30,
        );
        await c.settle(_short);
        final selected = await c.copy();
        c.check(
          selected != null && selected.length > 20,
          'text is selected as the answer streams: '
          '${selected?.length ?? 0} chars copied',
        );
        var kept = 0, copies = 0;
        while (c.agent.session.lastTurnEndSeq == ended ||
            c.agent.session.isStreaming) {
          await c.settle(const Duration(seconds: 1));
          copies++;
          final now = await c.copy();
          if (now == selected) {
            kept++;
          } else {
            PerfContext.log(
              'selection changed: "${selected?.replaceAll('\n', '⏎')}" → '
              '"${now?.replaceAll('\n', '⏎')}"',
            );
          }
        }
        r.extra['keptCopies'] = '$kept/$copies';
        c.check(
          kept == copies,
          'the selection stays as the answer streams: $kept of $copies '
          'copies the same',
        );
      });
    },
  ),
  PerfScenario(
    'select.editor',
    'Fast Ide on the 9,000-line file: text dragged over, a drag held past '
        'the bottom (the editor scrolling with it), words and lines by '
        'double and triple clicks, Shift+Down held for 150 lines.',
    (c) async {
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.bigFile);
      await c.settle(const Duration(seconds: 1));
      await c.focusEditor(400);
      c.jumpTo(400);
      await c.settle();
      final area = c.editorView.textArea!.shift(c.editorRect.topLeft);
      final lineHeight = c.editorView.lineHeight;
      await c.phase('drag', (r) async {
        var exact = 0;
        for (var i = 0; i < 6; i++) {
          final from = Offset(area.left + 60, area.top + 40 + i * lineHeight);
          final to = Offset(area.left + 260, area.top + 300 + i * lineHeight);
          final base = c.editorOffsetAt(from);
          final extent = c.editorOffsetAt(to);
          await c.input.drag(from, to, steps: 40);
          await c.settle(_short);
          final selection = c.editorSelection;
          if (base == null || extent == null) {
            // Past a line's end: from the line's end on.
            if (!selection.isCollapsed) exact++;
          } else if (selection.baseOffset == base &&
              selection.extentOffset == extent) {
            exact++;
          }
        }
        c.check(
          exact == 6,
          'a drag selects from where it was pressed to where it was '
          'released: $exact of 6',
        );
      });
      await c.phase('autoscroll', (r) async {
        final shown = c.editorView.visibleLineRange!;
        await c.input.drag(
          Offset(area.left + 60, area.center.dy),
          Offset(area.left + 120, area.bottom + 30),
          steps: 30,
          hold: const Duration(seconds: 2),
        );
        await c.settle(_short);
        final now = c.editorView.visibleLineRange!;
        final to = c.lineAt(c.editorSelection.extentOffset);
        r.extra['scrolledLines'] = now.first - shown.first;
        c.check(
          now.first - shown.first > shown.last - shown.first,
          'a selection held past the bottom scrolls the editor: '
          '${now.first - shown.first} lines',
        );
        c.check(
          to > shown.last && c.caretShown,
          'the selection follows it there (line $to, ${now.first}–'
          '${now.last} shown)',
        );
      });
      await c.phase('clicks', (r) async {
        var words = 0, lines = 0;
        final text = c.editor!.controller.value.text;
        for (var i = 0; i < 10; i++) {
          final at = Offset(
            area.left + 80 + i * 13,
            area.top + 30 + i * 3 * lineHeight + lineHeight / 2,
          );
          final offset = c.editorOffsetAt(at);
          await c.input.clicks(at, 2);
          await c.settle(_short);
          final word = c.editorSelection.textInside(text);
          if (offset != null &&
              RegExp(r'\w').hasMatch(text[offset]) &&
              RegExp(r'^\w+$').hasMatch(word)) {
            words++;
          } else if (offset == null || !RegExp(r'\w').hasMatch(text[offset])) {
            words++; // Not on a word: nothing to check.
          }
          await c.settle(const Duration(milliseconds: 600));
          await c.input.clicks(at, 3);
          await c.settle(_short);
          final selection = c.editorSelection;
          final lineStart = text.lastIndexOf('\n', selection.start - 1) + 1;
          if (selection.start == lineStart &&
              !selection.isCollapsed &&
              !selection.textInside(text).trimRight().contains('\n')) {
            lines++;
          }
        }
        c.check(words == 10, 'double clicks select words: $words of 10');
        c.check(lines == 10, 'triple clicks select lines: $lines of 10');
      });
      await c.phase('shift_down', (r) async {
        await c.input.click(Offset(area.left + 4, area.top + lineHeight / 2));
        await c.settle(_short);
        final start = c.lineAt(c.editorSelection.baseOffset);
        await c.input.repeat(LogicalKeyboardKey.arrowDown, 150, shift: true);
        await c.settle(_short);
        final selection = c.editorSelection;
        final to = c.lineAt(selection.extentOffset);
        c.check(
          to - start == 150 && c.lineAt(selection.baseOffset) == start,
          'Shift+Down 150 times selects 150 lines: ${to - start}',
        );
        c.check(c.caretShown, 'the editor follows the selection\'s end');
      });
    },
  ),
  PerfScenario(
    'select.huge_file',
    'The 90,000-line file: all of it selected by Cmd+A and copied, then '
        'Shift+Page Down held for 60 pages.',
    (c) async {
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.hugeFile);
      await c.settle(const Duration(seconds: 1));
      await c.focusEditor(1);
      final length = c.editor!.controller.value.text.length;
      await c.phase('select_all', (r) async {
        PerfProbe.instance.mark(PerfMark.action);
        c.input.press(LogicalKeyboardKey.keyA, meta: true);
        await c.settle(const Duration(milliseconds: 500));
        final selection = c.editorSelection;
        c.check(
          selection.start == 0 && selection.end == length,
          'Cmd+A selects the whole file: ${selection.start}–'
          '${selection.end} of $length',
        );
        final watch = Stopwatch()..start();
        final copied = await c.copy();
        r.extra['copyMs'] = watch.elapsedMilliseconds;
        c.check(
          copied?.length == length,
          'Cmd+C copies it all: ${copied?.length} of $length chars',
        );
      });
      await c.phase('shift_page_down', (r) async {
        c.input.press(LogicalKeyboardKey.arrowUp, meta: true);
        await c.settle(_short);
        await c.input.repeat(LogicalKeyboardKey.pageDown, 60, shift: true);
        await c.settle(const Duration(milliseconds: 300));
        final selection = c.editorSelection;
        final to = c.lineAt(selection.extentOffset);
        r.extra['selectedLines'] = to;
        c.check(
          selection.baseOffset == 0 && to > 60 * 20,
          'Shift+Page Down 60 times selects 60 pages: to line $to',
        );
        c.check(c.caretShown, 'the editor follows the selection\'s end');
      });
    },
  ),

  PerfScenario(
    'select.stash',
    'A stash of 2,000 characters (as long as most are) beside the cards: text '
        'dragged over, words and paragraphs by double and triple clicks, '
        'Shift+Down held; then a stash of 12,000 '
        'characters dragged over and held past the bottom.',
    (c) async {
      await c.history(c.agent, 2);
      final short = await _stash.store.create(
        body: '# ${c.content.identifier()}\n\n${c.content.reply(2000)}',
      );
      final long = await _stash.store.create(
        body: '# ${c.content.identifier()}\n\n${c.content.reply(12000)}',
      );
      await _showStash(c, short.id);
      await c.settle(const Duration(seconds: 1));
      final found = c.find<StashEditor>();
      c.check(found != null, 'the stash\'s editor shows');
      if (found == null) return;
      final hand = _StashHand(c, found);
      MarkdownController controller() => hand.controller;
      Rect area() => hand.area;
      MarkdownEditorState? editorIn() => hand.editor;
      Future<void> collapse() => hand.collapse();
      bool onText(Offset at) => _StashHand.onText(at);
      Future<List<int>> drags(int count, PerfRecording r) =>
          hand.drags(count, r);

      // Points on words of its text, [count] of them from the top down: the
      // word and its paragraph (its line's text, after its marks), the
      // point inside the word, not at its edge.
      List<(Offset, String, String)> wordSpots(int count) {
        final editor = editorIn();
        if (editor == null) return const [];
        final markdown = controller();
        final text = markdown.text;
        final letter = RegExp(r'\w');
        final found = <(Offset, String, String)>[];
        final at = area();
        for (var y = at.top + 40; y < at.bottom - 40; y += 44) {
          for (var x = at.left + 40; x < at.right - 60; x += 23) {
            final near = editor.offsetAt(Offset(x, y));
            // On the middle of the line nearest (a caret's height of it:
            // its glyphs'), not between lines nor in a block's padding.
            final line = near == null ? null : editor.caretRect(near);
            if (line == null) continue;
            final point = Offset(x, line.center.dy);
            final offset = editor.offsetAt(point);
            if (offset == null ||
                !onText(point) ||
                offset < 1 ||
                offset >= text.length ||
                !letter.hasMatch(text[offset]) ||
                !letter.hasMatch(text[offset - 1])) {
              continue;
            }
            var start = offset, end = offset;
            while (start > 0 && letter.hasMatch(text[start - 1])) {
              start--;
            }
            while (end < text.length && letter.hasMatch(text[end])) {
              end++;
            }
            if (end - start < 3) continue;
            final index = markdown.lineAt(offset);
            final paragraph = markdown.substring(
              markdown.lineStart(index) + markdown.textStartOf(index),
              markdown.lineEnd(index),
            );
            found.add((point, text.substring(start, end), paragraph));
            break;
          }
          if (found.length == count) break;
        }
        return found;
      }

      await c.phase('drag', (r) async {
        final copies = await drags(6, r);
        r.extra['copiedChars'] = copies;
        c.check(
          copies.every((n) => n > 40),
          'a drag over the stash selects and copies its text: $copies chars',
        );
      });
      await c.phase('clicks', (r) async {
        var words = 0, lines = 0;
        final picked = <String>[];
        String selected() => controller().selectedText;

        final spots = wordSpots(5);
        c.check(spots.length == 5, 'words to click: ${spots.length} of 5');
        for (final (spot, word, paragraph) in spots) {
          await c.input.clicks(spot, 2);
          await c.settle(_short);
          if (selected() == word) words++;
          await c.settle(const Duration(milliseconds: 600));
          await c.input.clicks(spot, 3);
          await c.settle(_short);
          final line = selected();
          if (line == paragraph) lines++;
          picked.add('$word: ${line.length} of ${paragraph.length} chars');
          await collapse();
          await c.settle(const Duration(milliseconds: 600));
        }
        r.extra['picked'] = picked;
        c.check(
          words == spots.length,
          'double clicks select the word: $words of ${spots.length}',
        );
        c.check(
          lines == spots.length,
          'triple clicks select the word\'s paragraph: $lines of '
          '${spots.length} ($picked)',
        );
      });
      await c.phase('shift_keys', (r) async {
        final at = area();
        await c.input.click(Offset(at.left + 4, at.top + 30));
        await c.settle(const Duration(milliseconds: 600));
        final base = controller().selection.baseOffset;
        final top =
            editorIn()!.caretRect(base)!.top + c.scrolledIn(hand.element);
        // Not Shift+Right: on macOS the input method moves the caret
        // sideways (moveRight:), which these keys do not go through.
        await c.input.repeat(LogicalKeyboardKey.arrowDown, 30, shift: true);
        await c.settle(_short);
        final selection = controller().selection;
        r.extra['selectedChars'] = selection.end - selection.start;
        // Down a line for each press: as many lines as the window is wide
        // wraps them into, whatever characters they hold. Measured in the
        // text, as far as it scrolled; its lines 14px at 1.55.
        final editor = editorIn()!;
        final line = editor.caretRect(selection.extentOffset)!;
        final lines =
            (line.top + c.scrolledIn(hand.element) - top) / (14 * 1.55);
        r.extra['selectedLines'] = lines.round();
        c.check(
          selection.baseOffset == base && lines >= 25,
          'Shift+Down held 30 times selects on from the caret: '
          '${lines.round()} lines down',
        );
        await collapse();
      });
      // Not Cmd+A: on macOS it comes by the menu's selectAll:, which these
      // keys do not go through.

      await _showStash(c, long.id);
      await c.settle(const Duration(seconds: 1));
      hand.element = c.find<StashEditor>()!;
      c.check(
        controller().length > 10000,
        'the long stash shows: ${controller().length} chars',
      );
      // Opened at its end (where its caret is): from its top, as one reads
      // it, room below to scroll into.
      c.scrollableIn(hand.element)?.position.jumpTo(0);
      await c.settle(_short);
      await c.phase('drag_long', (r) async {
        final copies = await drags(6, r);
        r.extra['copiedChars'] = copies;
        c.check(
          copies.every((n) => n > 40),
          'a drag over the long stash copies its text: $copies chars',
        );
      });
      await c.phase('autoscroll', (r) async {
        final before = c.scrolledIn(hand.element);
        final at = area();
        await c.input.drag(
          Offset(at.left + 10, at.center.dy),
          Offset(at.left + 200, at.bottom + 40),
          steps: 30,
          hold: const Duration(seconds: 2),
        );
        await c.settle(_short);
        final scrolled = c.scrolledIn(hand.element) - before;
        r.extra['scrolledPx'] = scrolled.round();
        c.check(
          scrolled > at.height / 2,
          'a selection held past the bottom scrolls the stash: '
          '${scrolled.round()}px',
        );
        await collapse();
      });
    },
  ),

  PerfScenario(
    'select.stash_huge',
    'A stash of 50,000 characters beside the cards, dragged over from its '
        'top, the middle and its end; one of 2,000 dragged over first, as '
        'what to compare with: a drag builds no more in the long one.',
    (c) async {
      final short = await _stash.store.create(
        body: '# ${c.content.identifier()}\n\n${c.content.reply(2000)}',
      );
      final huge = await _stash.store.create(
        body: '# ${c.content.identifier()}\n\n${c.content.reply(50000)}',
      );
      await _showStash(c, short.id);
      await c.settle(const Duration(seconds: 1));
      final found = c.find<StashEditor>();
      c.check(found != null, 'the stash\'s editor shows');
      if (found == null) return;
      final hand = _StashHand(c, found);
      c.scrollableIn(hand.element)?.position.jumpTo(0);
      await c.settle(_short);
      await c.phase('drag_short', (r) async {
        final copies = await hand.drags(6, r);
        r.extra['copiedChars'] = copies;
        c.check(
          copies.every((n) => n > 40),
          'a drag over the stash copies its text: $copies chars',
        );
      });

      await _showStash(c, huge.id);
      await c.settle(const Duration(seconds: 1));
      hand.element = c.find<StashEditor>()!;
      c.check(
        hand.controller.length > 45000,
        'the long stash shows: ${hand.controller.length} chars',
      );
      final position = c.scrollableIn(hand.element)!.position;
      await c.phase('drag_huge', (r) async {
        final copies = <int>[];
        // At its top, its middle and its end: as cheap wherever it is.
        for (final at in [0.0, 0.5, 1.0]) {
          // Its length as laid out so far (rows not yet seen are
          // reckoned): once there, as far again as it really goes.
          for (var i = 0; i < 2; i++) {
            position.jumpTo(position.maxScrollExtent * at);
            await c.settle(_short);
          }
          copies.addAll(await hand.drags(2, r));
        }
        r.extra['copiedChars'] = copies;
        c.check(
          copies.every((n) => n > 40),
          'a drag over the long stash copies its text: $copies chars',
        );
      });
      final shortP90 = _figure(c, 'drag_short', 'frames.buildMs.p90');
      final hugeP90 = _figure(c, 'drag_huge', 'frames.buildMs.p90');
      if (shortP90 is num && hugeP90 is num) {
        c.check(
          hugeP90 < 2,
          'a drag over 50,000 characters builds its frames in under 2ms '
          '(p90): ${hugeP90}ms',
        );
        // As long as what a drag shows changes, not the text.
        c.check(
          hugeP90 <= shortP90 * 1.25 + 0.3,
          'a drag builds as much in a long stash as in a short one (p90): '
          '${hugeP90}ms, against ${shortP90}ms',
        );
      }
    },
  ),

  PerfScenario(
    'select.markdown_huge',
    'Fast Ide on a markdown file of 50,000 characters, edited in its '
        'preview: dragged over from its top, the middle and its end, then '
        'the wheel spun through it and trackpad flings; one of 2,000 '
        'dragged over first, as what to compare with.',
    (c) async {
      final short = '${c.project.root}/docs/short.md';
      final huge = '${c.project.root}/docs/huge.md';
      Directory('${c.project.root}/docs').createSync(recursive: true);
      for (final (path, length) in [(short, 2000), (huge, 50000)]) {
        File(path).writeAsStringSync(
          '# ${c.content.identifier()}\n\n${c.content.reply(length)}',
        );
      }
      final workbench = await c.openIde();
      Future<_StashHand?> open(String path) async {
        unawaited(workbench.workspace.open(path));
        final length = File(path).readAsStringSync().length;
        await c.until(
          () =>
              c.find<MarkdownEditor>(
                where: (editor) => editor.controller.length == length,
              ) !=
              null,
          'the preview of $path',
        );
        await c.settle(const Duration(seconds: 1));
        final found = c.find<MarkdownEditor>();
        return found == null ? null : _StashHand(c, found);
      }

      final hand = await open(short);
      c.check(hand != null, 'the markdown file shows as its preview');
      if (hand == null) return;
      await c.phase('drag_short', (r) async {
        final copies = await hand.drags(6, r);
        r.extra['copiedChars'] = copies;
        c.check(
          copies.every((n) => n > 40),
          'a drag over the preview copies its text: $copies chars',
        );
      });

      final long = await open(huge);
      if (long == null) return;
      c.check(
        long.controller.length > 45000,
        'the long file shows: ${long.controller.length} chars',
      );
      final position = c.scrollableIn(long.element)!.position;
      await c.phase('drag_huge', (r) async {
        final copies = <int>[];
        // At its top, its middle and its end: as cheap wherever it is.
        for (final at in [0.0, 0.5, 1.0]) {
          // Its length as laid out so far (lines not yet seen are
          // reckoned): once there, as far again as it really goes.
          for (var i = 0; i < 2; i++) {
            position.jumpTo(position.maxScrollExtent * at);
            await c.settle(_short);
          }
          copies.addAll(await long.drags(2, r));
        }
        r.extra['copiedChars'] = copies;
        c.check(
          copies.every((n) => n > 40),
          'a drag over the long file copies its text: $copies chars',
        );
      });
      final at = c.rectOf(long.element).center;
      position.jumpTo(0);
      await c.settle(_short);
      await c.phase('spin', (r) async {
        await c.input.spin(at, 60, 40, every: const Duration(milliseconds: 16));
        await c.settle(const Duration(milliseconds: 500));
        final down = position.pixels;
        await c.input.spin(
          at,
          -60,
          40,
          every: const Duration(milliseconds: 16),
        );
        await c.settle(const Duration(milliseconds: 500));
        r.extra['scrolledPx'] = down.round();
        c.check(down > 300, 'the wheel scrolls the preview: ${down.round()}px');
      });
      await c.phase('fling', (r) async {
        for (var i = 0; i < 4; i++) {
          await c.input.swipe(at, List.filled(20, i.isEven ? -40 : 40));
          await c.settle(const Duration(milliseconds: 900));
        }
      });
      final shortP90 = _figure(c, 'drag_short', 'frames.buildMs.p90');
      final hugeP90 = _figure(c, 'drag_huge', 'frames.buildMs.p90');
      if (shortP90 is num && hugeP90 is num) {
        c.check(
          hugeP90 < 2,
          'a drag over 50,000 characters builds its frames in under 2ms '
          '(p90): ${hugeP90}ms',
        );
        c.check(
          hugeP90 <= shortP90 * 1.25 + 0.3,
          'a drag builds as much in a long file as in a short one (p90): '
          '${hugeP90}ms, against ${shortP90}ms',
        );
      }
    },
  ),

  // --- The caret ---------------------------------------------------------------
  PerfScenario(
    'caret.editor',
    'Fast Ide on the 9,000-line file: the caret moved by the arrows (held), '
        'by pages, to the end and the start of the file; then the editor '
        'left alone, its caret blinking.',
    (c) async {
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.bigFile);
      await c.settle(const Duration(seconds: 1));
      await c.focusEditor(100);
      c.jumpTo(100);
      await c.settle();
      await c.phase('arrows', (r) async {
        await c.input.repeat(LogicalKeyboardKey.arrowDown, 200);
        await c.input.repeat(LogicalKeyboardKey.arrowRight, 60);
        await c.input.repeat(LogicalKeyboardKey.arrowUp, 100);
        await c.settle(_short);
        final line = c.lineAt(c.editorSelection.extentOffset);
        // Right past a line's end goes on to the next.
        c.check(
          line >= 200 && line <= 260,
          'the arrows take the caret 100 lines down: at $line, from 100',
        );
        c.check(c.caretShown, 'the editor follows the caret');
      });
      await c.phase('pages', (r) async {
        await c.input.repeat(LogicalKeyboardKey.pageDown, 40);
        await c.settle(_short);
        final down = c.lineAt(c.editorSelection.extentOffset);
        c.check(c.caretShown, 'the editor follows the caret down the pages');
        await c.input.repeat(LogicalKeyboardKey.pageUp, 20);
        await c.settle(_short);
        final up = c.lineAt(c.editorSelection.extentOffset);
        c.check(
          down > 40 * 20 && up < down,
          'pages move the caret: down to $down, back to $up',
        );
        c.check(c.caretShown, 'the editor follows the caret up the pages');
      });
      await c.phase('ends', (r) async {
        final length = c.editor!.controller.value.text.length;
        for (var i = 0; i < 6; i++) {
          c.input.press(LogicalKeyboardKey.arrowDown, meta: true);
          await c.settle(const Duration(milliseconds: 300));
          c.check(
            c.editorSelection.extentOffset == length && c.caretShown,
            'Cmd+Down goes to the end, shown',
          );
          c.input.press(LogicalKeyboardKey.arrowUp, meta: true);
          await c.settle(const Duration(milliseconds: 300));
          c.check(
            c.editorSelection.extentOffset == 0 && c.caretShown,
            'Cmd+Up goes to the start, shown',
          );
        }
      });
      await c.phase('idle', (r) => _rest(const Duration(seconds: 4)));
      _checkIdle(c, 'idle');
    },
  ),
  PerfScenario(
    'caret.composer',
    'The chat\'s input: a paragraph typed (a fast typist\'s pace), then '
        'again while the agent answers fast above it; then left alone, '
        'focused.',
    (c) async {
      await c.history(c.agent, 10);
      await c.settle();
      // The input's editor, not another's (a stash's, a preview's).
      Element? editor() {
        Element? found;
        void visit(Element element) {
          if (found != null) return;
          if (element.widget is MarkdownEditor) {
            found = element;
            return;
          }
          element.visitChildren(visit);
        }

        c.find<ChatComposer>()?.visitChildren(visit);
        return found;
      }

      String typed() =>
          (editor()?.widget as MarkdownEditor?)?.controller.text ?? '';
      final composer = c.find<ChatComposer>();
      c.check(composer != null && editor() != null, 'the chat has an input');
      if (editor() == null) return;
      await c.input.click(c.rectOf(editor()!).center);
      await c.settle();
      c.check(c.input.canType, 'a click puts the caret in the input');
      if (!c.input.canType) return;
      final text = c.content.paragraph().replaceAll('\n', ' ');
      await c.phase('idle_empty', (r) => _rest(const Duration(seconds: 4)));
      _checkIdle(c, 'idle_empty');
      await c.phase('typing', (r) async {
        await c.input.type(text, every: const Duration(milliseconds: 80));
        await c.settle(_short);
        c.check(
          typed().contains(text),
          'the input has what was typed (${typed().length} chars of '
          '${text.length})',
        );
      });
      await c.phase('idle', (r) => _rest(const Duration(seconds: 4)));
      _checkIdle(c, 'idle');
      await c.phase('while_streaming', (r) async {
        final before = typed().length;
        final ended = c.agent.session.lastTurnEndSeq;
        await c.start(c.agent, c.reply(14000, PerfPace.fast, heavy: true));
        // Back in the input, as the user would be after sending.
        await c.input.click(c.rectOf(editor()!).center);
        await c.settle(_short);
        await c.input.type(' $text', every: const Duration(milliseconds: 80));
        await c.until(
          () =>
              c.agent.session.lastTurnEndSeq > ended &&
              !c.agent.session.isStreaming,
          'the answer',
        );
        c.check(
          typed().length >= before + text.length,
          'typing while the agent answers keeps every key: '
          '${typed().length - before} of ${text.length + 1}',
        );
      });
      await c.phase('idle_after', (r) => _rest(const Duration(seconds: 4)));
      _checkIdle(c, 'idle_after');
    },
  ),

  // --- At work ------------------------------------------------------------------
  PerfScenario(
    'ui.working',
    'An agent at work out of sight of its model (a subagent it started, '
        'running), looked at from all over the app: its conversation (the '
        'subagent\'s step, edits\' cards), with the side panel open, the '
        'IDE, the stashes\' page. Whatever shows, it should draw no more '
        'than the shared clock\'s frames, not at every vsync.',
    (c) async {
      const look = Duration(seconds: 5);
      await c.history(c.agent, 3);
      await c.start(
        c.agent,
        PerfTurn([
          PerfTool(
            'Task',
            const {
              'description': 'Explore the rate limiter',
              'prompt': 'Find where requests are counted.',
              'subagent_type': 'Explore',
            },
            result: 'Requests are counted in the middleware.',
            took: const Duration(seconds: 60),
          ),
          PerfSay(c.content.paragraph()),
        ]),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      Future<void> phase(String name) async {
        await c.settle(const Duration(milliseconds: 1500));
        await c.phase(name, (r) => _rest(look));
        final perSecond = _figure(c, name, 'frames.perSecond');
        c.check(
          perSecond is! num || perSecond <= 40,
          '$name: an agent at work, the app draws $perSecond frames a second',
        );
      }

      await phase('chat');
      final area = c.find<AgentSidePanelArea>();
      c.check(area != null, 'the side panel is there');
      if (area != null) {
        (area.widget as AgentSidePanelArea).panel.show();
        await phase('side_panel');
      }
      await c.openIde();
      FocusManager.instance.primaryFocus?.unfocus();
      await phase('ide');
      await _showStash(c);
      await phase('stash');
    },
  ),

  // --- At rest -----------------------------------------------------------------
  PerfScenario(
    'idle.app',
    'The app left alone, nothing focused: on a conversation of 10 turns, '
        'then on Fast Ide with a file open. It should draw nothing, or '
        'next to nothing.',
    (c) async {
      await c.history(c.agent, 10);
      FocusManager.instance.primaryFocus?.unfocus();
      await c.settle(const Duration(seconds: 2));
      await c.phase('chat', (r) => _rest(const Duration(seconds: 4)));
      _checkIdle(c, 'chat', frames: 4, cpu: 5);
      final workbench = await c.openIde();
      await c.openFile(workbench, c.project.bigFile);
      FocusManager.instance.primaryFocus?.unfocus();
      await c.settle(const Duration(seconds: 2));
      await c.phase('ide', (r) => _rest(const Duration(seconds: 4)));
      _checkIdle(c, 'ide', frames: 4, cpu: 5);
    },
  ),

  // --- Scrolling ---------------------------------------------------------------
  PerfScenario(
    'scroll.sidebar',
    'A sidebar of 60 agents: the wheel spun down and up through it, then '
        'trackpad flings.',
    (c) async {
      await c.agents(60);
      await c.settle(const Duration(seconds: 1));
      // The project lists its latest five: all of them, by Show More.
      final more = c.findNamed('_MoreRow');
      c.check(more.isNotEmpty, 'the sidebar has its Show More');
      if (more.isNotEmpty) await c.input.click(c.rectOf(more.first).center);
      await c.settle();
      final sidebar = c.find<Sidebar>()!;
      final at = c.rectOf(sidebar).center;
      await c.phase('spin', (r) async {
        await c.input.spin(at, 60, 40, every: const Duration(milliseconds: 16));
        await c.settle(const Duration(milliseconds: 500));
        final down = c.scrolledIn(sidebar);
        await c.input.spin(
          at,
          -60,
          40,
          every: const Duration(milliseconds: 16),
        );
        await c.settle(const Duration(milliseconds: 500));
        c.check(down > 300, 'the wheel scrolls the sidebar: ${down.round()}px');
        c.check(
          c.scrolledIn(sidebar) < 1,
          'and back to its top: ${c.scrolledIn(sidebar).round()}px',
        );
      });
      await c.phase('fling', (r) async {
        for (var i = 0; i < 4; i++) {
          await c.input.swipe(at, List.filled(20, i.isEven ? -40 : 40));
          await c.settle(const Duration(milliseconds: 900));
        }
      });
    },
  ),
  PerfScenario(
    'scroll.stash',
    'The stashes\' page, 24 cards: the wheel spun down and up through them, '
        'then trackpad flings.',
    (c) async {
      await _showStash(c);
      final page = c.find<StashView>();
      c.check(page != null, 'the stashes\' page shows');
      if (page == null) return;
      final rect = c.rectOf(page);
      final at = Offset(rect.left + rect.width * .25, rect.center.dy);
      await c.phase('spin', (r) async {
        await c.input.spin(at, 60, 40, every: const Duration(milliseconds: 16));
        await c.settle(const Duration(milliseconds: 500));
        final down = c.scrolledIn(page);
        await c.input.spin(
          at,
          -60,
          40,
          every: const Duration(milliseconds: 16),
        );
        await c.settle(const Duration(milliseconds: 500));
        c.check(down > 300, 'the wheel scrolls the cards: ${down.round()}px');
      });
      await c.phase('fling', (r) async {
        for (var i = 0; i < 4; i++) {
          await c.input.swipe(at, List.filled(20, i.isEven ? -40 : 40));
          await c.settle(const Duration(milliseconds: 900));
        }
      });
    },
  ),
  PerfScenario(
    'scroll.stash_note',
    'A stash of 12,000 characters beside the cards: the wheel spun down and '
        'up through it, then trackpad flings.',
    (c) async {
      final note = await _stash.store.create(
        body: '# ${c.content.identifier()}\n\n${c.content.reply(12000)}',
      );
      await _showStash(c, note.id);
      await c.settle(const Duration(seconds: 1));
      final editor = c.find<StashEditor>();
      c.check(editor != null, 'the stash\'s editor shows');
      if (editor == null) return;
      final at = c.rectOf(editor).center;
      await c.phase('spin', (r) async {
        await c.input.spin(at, 60, 40, every: const Duration(milliseconds: 16));
        await c.settle(const Duration(milliseconds: 500));
        final down = c.scrolledIn(editor);
        await c.input.spin(
          at,
          -60,
          40,
          every: const Duration(milliseconds: 16),
        );
        await c.settle(const Duration(milliseconds: 500));
        r.extra['scrolledPx'] = down.round();
        c.check(down > 300, 'the wheel scrolls the stash: ${down.round()}px');
      });
      await c.phase('fling', (r) async {
        for (var i = 0; i < 4; i++) {
          await c.input.swipe(at, List.filled(20, i.isEven ? -40 : 40));
          await c.settle(const Duration(milliseconds: 900));
        }
      });
    },
  ),

  // --- Memory ------------------------------------------------------------------
  PerfScenario(
    'memory.soak',
    'Six rounds of a session\'s work: a new agent answers 12k characters, '
        'the IDE opens four files and is typed into, the stashes\' page '
        'opens, then the chat again. The footprint after each: whether what '
        'a round took comes back.',
    (c) async {
      await c.history(c.agent, 4);
      await c.settle();
      final rounds = <int>[];
      final gpu = <int>[];
      await c.phase('rounds', (r) async {
        for (var round = 0; round < 6; round++) {
          final thread = c.workspace.create(
            project: c.workspace.projects.first,
          );
          c.workspace.select(thread);
          await c.run(thread, c.reply(12000, PerfPace.flood, heavy: true));
          final workbench = await c.openIde();
          for (var i = 0; i < 4; i++) {
            await c.openFile(
              workbench,
              c.project.manyFiles[(round * 4 + i) % c.project.manyFiles.length],
            );
          }
          await c.focusEditor(600);
          await c.input.type('const soak$round = $round;\n');
          await _showStash(c, _stash.store.notes[round].id);
          c.workspace.layout = WorkspaceLayout.chat;
          await c.settle();
          // Back to the agent, by its row, which closes the stashes.
          if (_rowOf(c, thread) case final row?) {
            await c.input.click(c.rectOf(row).center);
          }
          await c.settle(const Duration(seconds: 2));
          rounds.add((PerfProcess.footprint() / 1048576).round());
          if (await PerfProcess.parts() case {'gpu': final bytes}) {
            gpu.add((bytes / 1048576).round());
          }
          PerfContext.log('round $round: ${rounds.last}MB ${treeCounts()}');
        }
        r.extra['roundsMb'] = rounds;
        if (gpu.isNotEmpty) r.extra['roundsGpuMb'] = gpu;
        // Over the last five (the first takes what is made once).
        final slope = (rounds.last - rounds[1]) / (rounds.length - 2);
        r.extra['mbPerRound'] = (slope * 10).round() / 10;
      });
      final growth = rounds.last - rounds[1];
      c.check(
        growth < 120,
        'memory comes back after each round: ${rounds.join(' → ')}MB',
      );
      c.check(
        c.workspace.layout == WorkspaceLayout.chat &&
            c.find<ChatHistoryView>() != null,
        'the agent\'s row brings back the conversation',
      );
    },
  ),
];
