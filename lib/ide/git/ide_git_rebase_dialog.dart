// JetBrains IDEs' interactive rebase dialog (Interactively Rebase from
// Here): the commits from one on, newest first as in the log, each picked,
// reworded, stopped at to be edited, squashed or fixed up into the one
// below it, or dropped; put in another order by dragging them or with
// Alt+Up and Alt+Down. The message of the commit selected is under the
// list: edited, the commit is reworded. BaoCode's own: Clean Up with AI,
// the model's plan (what to fix up, squash, reword) put in the list for
// the user to look over before the rebase starts.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../ide_button.dart';
import '../ide_dates.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_notifications.dart';
import 'commit_message.dart';
import 'git_model.dart';
import 'git_repository.dart';

/// Interactively Rebase from Here on [from], in [git]'s current branch:
/// the dialog, then the rebase; what goes wrong told in [notifications].
Future<void> showIdeGitRebaseDialog(
  BuildContext context, {
  required IdeGitRepository git,
  required IdeGitCommit from,
  required IdeNotifications notifications,
  IdeCommitMessageModel? ai,
}) async {
  final List<IdeGitCommit> commits;
  try {
    commits = await git.service.log(
      refs: [if (from.parentIds.isEmpty) 'HEAD' else '${from.id}^..HEAD'],
      limit: 1000,
    );
  } catch (error) {
    notifications.notify(IdeSeverity.error, '$error');
    return;
  }
  if (!context.mounted || commits.isEmpty) return;
  final steps = await showGeneralDialog<List<IdeGitRebaseStep>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.commonDismiss,
    barrierColor: const Color(0x80000000),
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) => IdeGitRebaseDialog(
      commits: commits,
      notifications: notifications,
      ai: ai,
    ),
  );
  if (steps == null || !context.mounted) return;
  final l10n = context.l10n;
  try {
    if (await git.interactiveRebase(from, steps)) {
      notifications.notify(IdeSeverity.info, l10n.gitRebaseStopped);
    }
  } catch (error) {
    notifications.notify(IdeSeverity.error, '$error');
  }
}

/// A commit of the list and what is to be done with it.
class _Entry {
  _Entry(this.commit);

  final IdeGitCommit commit;
  IdeGitRebaseAction action = IdeGitRebaseAction.pick;

  /// Its new message, reworded.
  String? message;

  String get subject => switch (message) {
    final message? => message.split('\n').first,
    null => commit.subject,
  };
}

/// The dialog itself: pops with the rebase's steps (oldest first), or with
/// nothing where it was cancelled.
class IdeGitRebaseDialog extends StatefulWidget {
  const IdeGitRebaseDialog({
    super.key,
    required this.commits,
    required this.notifications,
    this.ai,
  });

  /// Newest first; the last is the one the rebase starts from.
  final List<IdeGitCommit> commits;
  final IdeNotifications notifications;
  final IdeCommitMessageModel? ai;

  static const rowHeight = 24.0;

  @override
  State<IdeGitRebaseDialog> createState() => _IdeGitRebaseDialogState();
}

class _IdeGitRebaseDialogState extends State<IdeGitRebaseDialog> {
  late final List<_Entry> _entries = [
    for (final commit in widget.commits) _Entry(commit),
  ];

  /// The entries selected, and the one the message shows (focused).
  final Set<_Entry> _selection = {};
  _Entry? _focused;
  _Entry? _anchor;

  final FocusNode _listFocus = FocusNode(debugLabel: 'rebase list');
  final TextEditingController _message = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// The model planning, cancelled when completed.
  Completer<void>? _planning;

  /// Where an entry is dragged: its row's top, from the list's.
  _Entry? _dragged;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _focus(_entries.first);
    _message.addListener(_messageEdited);
  }

  @override
  void dispose() {
    _planning?.complete();
    _listFocus.dispose();
    _messageFocus.dispose();
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _focus(_Entry entry, {bool extend = false, bool toggle = false}) {
    setState(() {
      if (extend && _anchor != null) {
        final a = _entries.indexOf(_anchor!);
        final b = _entries.indexOf(entry);
        _selection
          ..clear()
          ..addAll(_entries.sublist(math.min(a, b), math.max(a, b) + 1));
      } else if (toggle) {
        if (!_selection.remove(entry)) _selection.add(entry);
        _anchor = entry;
      } else {
        _selection
          ..clear()
          ..add(entry);
        _anchor = entry;
      }
      _focused = entry;
    });
    final text = entry.message ?? entry.commit.message;
    if (_message.text != text) {
      _message.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  /// The message edited: the commit reworded (picked again where it is
  /// back as it was).
  void _messageEdited() {
    final entry = _focused;
    if (entry == null) return;
    final text = _message.text;
    if (text == (entry.message ?? entry.commit.message)) return;
    setState(() {
      if (text.trim() == entry.commit.message.trim()) {
        entry.message = null;
        if (entry.action == IdeGitRebaseAction.reword) {
          entry.action = IdeGitRebaseAction.pick;
        }
      } else {
        entry.message = text;
        if (entry.action == IdeGitRebaseAction.pick) {
          entry.action = IdeGitRebaseAction.reword;
        }
      }
    });
  }

  void _setAction(IdeGitRebaseAction action) {
    setState(() {
      for (final entry in _selection) {
        entry.action = action;
        if (action != IdeGitRebaseAction.reword) entry.message = null;
      }
    });
    if (action == IdeGitRebaseAction.reword) {
      // The message to edit.
      if (_focused case final entry?) _focus(entry);
      _messageFocus.requestFocus();
    } else if (_focused case final entry?) {
      _focus(entry, toggle: false);
    }
  }

  final FocusNode _messageFocus = FocusNode(debugLabel: 'rebase message');

  /// The selection moved one row up (toward the newest) or down.
  void _move(int by) {
    if (_selection.isEmpty) return;
    final indices = [for (final entry in _selection) _entries.indexOf(entry)]
      ..sort();
    if (by < 0 && indices.first == 0) return;
    if (by > 0 && indices.last == _entries.length - 1) return;
    setState(() {
      final moved = [for (final i in indices) _entries[i]];
      for (final i in indices.reversed) {
        _entries.removeAt(i);
      }
      final at = indices.first + by;
      _entries.insertAll(at, moved);
    });
  }

  /// The rebase's steps, oldest first.
  List<IdeGitRebaseStep> get _steps => [
    for (final entry in _entries.reversed)
      IdeGitRebaseStep(
        entry.commit.id,
        entry.action,
        message: entry.action == IdeGitRebaseAction.reword
            ? entry.message ?? entry.commit.message
            : null,
      ),
  ];

  /// Why the rebase cannot start: a squash or fixup with nothing below it.
  String? get _problem {
    for (final entry in _entries.reversed) {
      if (entry.action == IdeGitRebaseAction.drop) continue;
      if (entry.action.unites) return context.l10n.gitRebaseNothingBelow;
      return null;
    }
    return null;
  }

  bool get _changed {
    for (final (index, entry) in _entries.indexed) {
      if (entry.action != IdeGitRebaseAction.pick) return true;
      if (!identical(entry.commit, widget.commits[index])) return true;
    }
    return false;
  }

  void _start() {
    if (_problem != null || !_changed) return;
    Navigator.of(context).pop(_steps);
  }

  // --- AI --------------------------------------------------------------------

  Future<void> _cleanUpWithAi() async {
    final ai = widget.ai;
    if (ai == null) return;
    if (_planning case final running?) {
      running.complete();
      return;
    }
    final cancel = _planning = Completer<void>();
    setState(() {});
    final l10n = context.l10n;
    try {
      final prompt = ideGitRebasePrompt(widget.commits.reversed.toList());
      final reply = await ai(
        IdeCommitMessagePrompt(prompt.system, prompt.user),
        cancel: cancel.future,
      );
      if (!mounted || cancel.isCompleted) return;
      final plan = ideGitRebasePlan(reply, widget.commits);
      if (plan == null) throw IdeCommitMessageException(l10n.gitRebaseAiNoPlan);
      final byId = {for (final entry in _entries) entry.commit.id: entry};
      setState(() {
        _entries
          ..clear()
          ..addAll([
            for (final step in plan.reversed)
              byId[step.commit]!
                ..action = step.action
                ..message = step.message,
          ]);
      });
      if (_focused case final entry?) _focus(entry);
    } on IdeCommitMessageCancelled {
      // Stopped.
    } catch (error) {
      if (mounted) {
        widget.notifications.notify(
          IdeSeverity.error,
          l10n.gitRebaseAiFailed('$error'),
        );
      }
    } finally {
      if (identical(_planning, cancel)) _planning = null;
      if (mounted) setState(() {});
    }
  }

  // --- Keys ------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final focused = _focused;
    final index = focused == null ? -1 : _entries.indexOf(focused);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp when keys.isAltPressed:
        _move(-1);
      case LogicalKeyboardKey.arrowDown when keys.isAltPressed:
        _move(1);
      case LogicalKeyboardKey.arrowUp when index > 0:
        _focus(_entries[index - 1], extend: keys.isShiftPressed);
      case LogicalKeyboardKey.arrowDown when index < _entries.length - 1:
        _focus(_entries[index + 1], extend: keys.isShiftPressed);
      case LogicalKeyboardKey.keyP:
        _setAction(IdeGitRebaseAction.pick);
      case LogicalKeyboardKey.keyR:
        _setAction(IdeGitRebaseAction.reword);
      case LogicalKeyboardKey.keyE:
        _setAction(IdeGitRebaseAction.edit);
      case LogicalKeyboardKey.keyS:
        _setAction(IdeGitRebaseAction.squash);
      case LogicalKeyboardKey.keyF:
        _setAction(IdeGitRebaseAction.fixup);
      case LogicalKeyboardKey.keyD ||
          LogicalKeyboardKey.delete ||
          LogicalKeyboardKey.backspace:
        _setAction(IdeGitRebaseAction.drop);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- The view --------------------------------------------------------------

  String _actionLabel(IdeGitRebaseAction action) {
    final l10n = context.l10n;
    return switch (action) {
      IdeGitRebaseAction.pick => l10n.gitRebasePick,
      IdeGitRebaseAction.reword => l10n.gitRebaseReword,
      IdeGitRebaseAction.edit => l10n.gitRebaseEdit,
      IdeGitRebaseAction.squash => l10n.gitRebaseSquash,
      IdeGitRebaseAction.fixup => l10n.gitRebaseFixup,
      IdeGitRebaseAction.drop => l10n.gitRebaseDrop,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final foreground = colors['editorWidget.foreground'];
    final border = colors.get('widget.border') ?? Colors.transparent;
    final size = MediaQuery.sizeOf(context);
    final problem = _problem;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _start,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _start,
      },
      child: Align(
        alignment: const Alignment(0, -0.4),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: math.min(900.0, size.width * .9),
            height: math.min(620.0, size.height * .85),
            decoration: BoxDecoration(
              color: colors['editorWidget.background'],
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Color(0x26000000), blurRadius: 20),
              ],
            ),
            child: DefaultTextStyle(
              style: TextStyle(fontSize: 13, color: foreground),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.gitRebaseTitle(
                              widget.commits.length,
                              widget.commits.last.shortId,
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IdeActionButton(
                          icon: Codicons.close,
                          tooltip: l10n.dialogCloseDialog,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  _toolbar(context),
                  Container(height: 1, color: border),
                  Expanded(flex: 3, child: _list(context)),
                  Container(height: 1, color: border),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _messageEditor(context),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            problem ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors['errorForeground'],
                            ),
                          ),
                        ),
                        IdeButton(
                          label: l10n.gitRebaseStart,
                          onPressed: problem == null && _changed
                              ? _start
                              : null,
                        ),
                        const SizedBox(width: 8),
                        IdeButton(
                          label: l10n.commonCancel,
                          secondary: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final l10n = context.l10n;
    final none = _selection.isEmpty;
    Widget action(IdeGitRebaseAction action, String key) => _TextButton(
      label: _actionLabel(action),
      tooltip: '${_actionLabel(action)} ($key)',
      onPressed: none ? null : () => _setAction(action),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          action(IdeGitRebaseAction.pick, 'P'),
          action(IdeGitRebaseAction.reword, 'R'),
          action(IdeGitRebaseAction.edit, 'E'),
          action(IdeGitRebaseAction.squash, 'S'),
          action(IdeGitRebaseAction.fixup, 'F'),
          action(IdeGitRebaseAction.drop, 'D'),
          const SizedBox(width: 8),
          IdeActionButton(
            icon: Codicons.arrowUp,
            tooltip: l10n.gitRebaseMoveUp,
            onPressed: none ? null : () => _move(-1),
          ),
          IdeActionButton(
            icon: Codicons.arrowDown,
            tooltip: l10n.gitRebaseMoveDown,
            onPressed: none ? null : () => _move(1),
          ),
          const Spacer(),
          if (widget.ai != null)
            _TextButton(
              icon: _planning == null ? Codicons.sparkle : Codicons.debugStop,
              label: _planning == null
                  ? l10n.gitRebaseCleanUpWithAi
                  : l10n.gitRebaseAiPlanning,
              tooltip: l10n.gitRebaseCleanUpWithAiDetail,
              onPressed: () => unawaited(_cleanUpWithAi()),
            ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) => Focus(
    focusNode: _listFocus,
    autofocus: true,
    onKeyEvent: _onKey,
    child: ListenableBuilder(
      listenable: _listFocus,
      builder: (context, _) => ListView.builder(
        controller: _scroll,
        itemExtent: IdeGitRebaseDialog.rowHeight,
        itemCount: _entries.length,
        itemBuilder: (context, index) => _row(context, _entries[index]),
      ),
    ),
  );

  Widget _row(BuildContext context, _Entry entry) {
    final l10n = context.l10n;
    final colors = themeColors;
    final action = entry.action;
    final dropped = action == IdeGitRebaseAction.drop;
    final description = IdeListColors.description;
    final actionColor = switch (action) {
      IdeGitRebaseAction.pick => description,
      IdeGitRebaseAction.drop => colors['errorForeground'],
      IdeGitRebaseAction.reword ||
      IdeGitRebaseAction.edit => colors['textLink.foreground'],
      _ => colors['editorWarning.foreground'],
    };
    final row = IdeListRow(
      key: ValueKey(entry.commit.id),
      height: IdeGitRebaseDialog.rowHeight,
      selected: _selection.contains(entry),
      focused: _listFocus.hasFocus,
      onTap: () {
        _listFocus.requestFocus();
        final keys = HardwareKeyboard.instance;
        _focus(
          entry,
          extend: keys.isShiftPressed,
          toggle: keys.isMetaPressed || keys.isControlPressed,
        );
      },
      builder: (context, hovered) => Row(
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(
              _actionLabel(action),
              style: TextStyle(fontSize: 12, color: actionColor),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              entry.commit.shortId,
              style: TextStyle(
                fontSize: 12,
                color: description,
              ),
            ),
          ),
          // A commit that goes into the one below it, under it.
          if (action.unites) ...[
            Icon(Codicons.foldDown, size: 14, color: actionColor),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: IdeHover(
              message: entry.message ?? entry.commit.message,
              child: Text(
                entry.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: dropped
                      ? description
                      : entry.message != null
                      ? colors['textLink.foreground']
                      : null,
                  decoration: dropped ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(
              entry.commit.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: description),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              ideFromNow(entry.commit.date, ago: true, l10n: l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: description),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
    // Dragged up or down: the commit put there.
    return GestureDetector(
      key: ValueKey('drag:${entry.commit.id}'),
      onVerticalDragStart: (_) {
        _dragged = entry;
        _dragDy = 0;
        if (!_selection.contains(entry)) _focus(entry);
      },
      onVerticalDragUpdate: (details) {
        if (_dragged == null) return;
        _dragDy += details.delta.dy;
        while (_dragDy <= -IdeGitRebaseDialog.rowHeight / 2) {
          _dragDy += IdeGitRebaseDialog.rowHeight;
          _move(-1);
        }
        while (_dragDy >= IdeGitRebaseDialog.rowHeight / 2) {
          _dragDy -= IdeGitRebaseDialog.rowHeight;
          _move(1);
        }
      },
      onVerticalDragEnd: (_) => _dragged = null,
      child: row,
    );
  }

  Widget _messageEditor(BuildContext context) {
    final l10n = context.l10n;
    final entry = _focused;
    final editable =
        entry != null &&
        entry.action != IdeGitRebaseAction.drop &&
        entry.action != IdeGitRebaseAction.fixup;
    return LayoutBuilder(
      builder: (context, constraints) {
        final lines = math.max(1, ((constraints.maxHeight - 8) / 20).floor());
        return IgnorePointer(
          ignoring: !editable,
          child: Opacity(
            opacity: editable ? 1 : .5,
            child: IdeInputBox(
              controller: _message,
              focusNode: _messageFocus,
              placeholder: l10n.gitRebaseMessage,
              semanticsLabel: l10n.gitRebaseMessage,
              minLines: lines,
              maxLines: lines,
              lineHeight: 20,
            ),
          ),
        );
      },
    );
  }
}

/// A toolbar button with its label written (an action of the list's).
class _TextButton extends StatefulWidget {
  const _TextButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  State<_TextButton> createState() => _TextButtonState();
}

class _TextButtonState extends State<_TextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = enabled
        ? IdeListColors.foreground
        : IdeListColors.description.withValues(alpha: .5);
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: _hovered && enabled
                  ? themeColors.get('toolbar.hoverBackground')
                  : null,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon case final icon?) ...[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.label,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the model is asked, to clean up [commits] (oldest first) before
/// they are pushed: which to fix up into another, squash, reword or drop.
({String system, String user}) ideGitRebasePrompt(List<IdeGitCommit> commits) {
  const system =
      'You clean up a Git branch before it is pushed, as an interactive '
      'rebase does. You are given its commits, oldest first. Answer with '
      'the rebase list only, oldest first, one line per commit: an action '
      '(pick, reword, squash, fixup or drop), a space and the commit\'s '
      'short hash, every commit exactly once. Fix up commits that only '
      'finish, fix or tidy the one before them ("wip", "fix typo", '
      '"address review"); squash ones that belong with the one before and '
      'have something of their own to say; reword a commit whose message '
      'says little, its new message after its line between <<<MESSAGE and '
      'MESSAGE>>> lines (a subject of at most 72 characters, a blank line '
      'and a body where it helps, in the language the other messages are '
      'in). Keep the order unless two commits that belong together are '
      'apart. Drop nothing unless a commit is undone by a later one. When '
      'nothing needs to change, pick every commit.';
  final user = StringBuffer('Commits, oldest first:\n\n');
  for (final commit in commits) {
    user
      ..writeln('${commit.shortId} by ${commit.author}')
      ..writeln(commit.message.trim())
      ..writeln();
  }
  return (system: system, user: user.toString());
}

/// The model's [reply] as the rebase's steps (oldest first), each of
/// [commits] once; null where it is not that.
List<IdeGitRebaseStep>? ideGitRebasePlan(
  String reply,
  List<IdeGitCommit> commits,
) {
  final byShort = <String, IdeGitCommit?>{};
  final steps = <IdeGitRebaseStep>[];
  final seen = <String>{};
  final lines = reply.split('\n');
  final line = RegExp(
    r'^\s*(pick|reword|edit|squash|fixup|drop)\s+([0-9a-f]{4,40})\b',
  );
  for (var i = 0; i < lines.length; i++) {
    final match = line.firstMatch(lines[i]);
    if (match == null) continue;
    final hash = match[2]!;
    final commit = byShort[hash] ??= commits
        .where((commit) => commit.id.startsWith(hash))
        .firstOrNull;
    if (commit == null || !seen.add(commit.id)) return null;
    var action = IdeGitRebaseAction.values.byName(match[1]!);
    String? message;
    if (action == IdeGitRebaseAction.reword) {
      // Its message, on the lines after it.
      final start = i + 1 < lines.length && lines[i + 1].trim() == '<<<MESSAGE'
          ? i + 2
          : -1;
      final end = start < 0
          ? -1
          : lines.indexWhere((line) => line.trim() == 'MESSAGE>>>', start);
      if (end < 0) {
        action = IdeGitRebaseAction.pick;
      } else {
        message = lines.sublist(start, end).join('\n').trim();
        i = end;
        if (message.isEmpty) action = IdeGitRebaseAction.pick;
      }
    }
    // Edit is the user's to choose.
    if (action == IdeGitRebaseAction.edit) action = IdeGitRebaseAction.pick;
    steps.add(
      IdeGitRebaseStep(
        commit.id,
        action,
        message: action == IdeGitRebaseAction.reword ? message : null,
      ),
    );
  }
  if (steps.length != commits.length) return null;
  return steps;
}
