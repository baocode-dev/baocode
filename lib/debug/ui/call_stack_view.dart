// The Call Stack view: sessions (child sessions under their parent), their
// threads with why they paused, and the threads' frames; focusing a frame
// opens its source; frames can restart; more frames load on demand.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/callStackView.ts.
//
// Deviations: deemphasized frames are dimmed rather than folded into a
// "show more" row; no disassembly or "open to the side".

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_panes.dart';
import '../../theme/codicons.dart';
import '../base/event.dart';
import '../common/debug_model.dart';
import '../common/debug_types.dart';
import '../service/debug_service.dart';
import '../session/debug_session.dart';
import 'debug_icons.dart';
import 'debug_strings.dart';
import 'debug_tree.dart';
import 'debug_widgets.dart';

/// "Load more stack frames" of a thread.
final class LoadMoreFrames implements DebugTreeElement {
  const LoadMoreFrames(this.thread);

  final Thread thread;

  @override
  String getId() => 'loadMore:${thread.getId()}';
}

/// The roots of the call stack: sessions, else the only session's
/// threads, else the only thread's frames (`CallStackDataSource`).
List<Object> callStackRoots(DebugService service) {
  final sessions = service.model.getSessions();
  final topLevel = sessions.where((s) => s.parentSession == null || !sessions.contains(s.parentSession)).toList();
  if (topLevel.length == 1 && sessions.length == 1) {
    final threads = topLevel.single.getAllThreads();
    if (threads.length == 1) return _framesOf(threads.single);
    return threads;
  }
  return topLevel;
}

List<Object> _framesOf(Thread thread) {
  final frames = thread.getCallStack();
  final total = thread.stoppedDetails?.totalFrames;
  final more = !thread.reachedEndOfCallStack && thread.stopped && (total == null || total > frames.length) && frames.isNotEmpty;
  return [...frames, if (more) LoadMoreFrames(thread)];
}

class _CallStackDataSource extends DebugTreeDataSource<Object> {
  _CallStackDataSource(this.service);

  final DebugService service;

  @override
  String idOf(Object element) => (element as DebugTreeElement).getId();

  @override
  bool hasChildren(Object element) => element is DebugSession || (element is Thread && element.stopped);

  @override
  Future<List<Object>> getChildren(Object element) async {
    if (element is DebugSession) {
      final children = service.model.getSessions().where((s) => s.parentSession == element).toList();
      final threads = element.getAllThreads();
      // A session with one thread and no children shows its frames.
      if (children.isEmpty && threads.length == 1) return _framesOf(threads.single);
      return [...threads, ...children];
    }
    if (element is Thread) return _framesOf(element);
    return const [];
  }

  @override
  bool initiallyExpanded(Object element) =>
      element is DebugSession || (element is Thread && element.stopped);
}

/// The paused reason, or running (`getThreadLabel`/`stateLabel`).
String threadStateLabel(Thread thread, DebugStrings s) {
  if (thread.stopped) {
    final details = thread.stoppedDetails;
    final reason = details?.description ?? details?.reason;
    return reason != null && reason.isNotEmpty ? s.pausedOn(reason) : s.paused;
  }
  return s.running;
}

String _sessionStateLabel(DebugSession session, DebugStrings s) => switch (session.state) {
  DebugState.stopped => s.paused,
  DebugState.running => s.running,
  DebugState.initializing => '…',
  DebugState.inactive => '',
};

class CallStackView extends StatefulWidget {
  const CallStackView({super.key, required this.service, this.collapseAll});

  final DebugService service;
  final Listenable? collapseAll;

  @override
  State<CallStackView> createState() => _CallStackViewState();
}

class _CallStackViewState extends State<CallStackView> {
  late final DebugTreeController<Object> _controller = DebugTreeController(_CallStackDataSource(widget.service));
  final DisposableStore _listeners = DisposableStore();

  DebugService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _listeners
      ..add(_service.model.onDidChangeCallStack(_changed))
      ..add(_service.viewModel.onDidFocusStackFrame((_) => _changed()))
      ..add(_service.viewModel.onDidFocusThread((_) => _changed()))
      ..add(_service.onDidChangeState((_) => _changed()));
    widget.collapseAll?.addListener(_controller.collapseAll);
  }

  @override
  void dispose() {
    widget.collapseAll?.removeListener(_controller.collapseAll);
    _listeners.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    _controller.refresh();
    final frame = _service.viewModel.focusedStackFrame;
    _controller.selectedId = frame?.getId() ?? _service.viewModel.focusedThread?.getId();
    setState(() {});
  }

  void _activate(Object element) {
    switch (element) {
      case StackFrame():
        unawaited(_service.focusStackFrame(element, explicit: true, preserveFocus: false));
      case Thread():
        unawaited(_service.focusStackFrame(null, thread: element, explicit: true));
      case DebugSession():
        unawaited(_service.focusStackFrame(null, session: element, explicit: true));
      case LoadMoreFrames(:final thread):
        unawaited(_service.model.fetchCallstack(thread));
    }
  }

  String _copyCallStack(Thread thread) => [for (final f in thread.getCallStack()) f.toString()].join('\n');

  void _contextMenu(Object element, Offset position) {
    final s = DebugStrings.of(context);
    final thread = switch (element) {
      StackFrame(:final thread) => thread,
      Thread() => element,
      _ => null,
    };
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          [
            if (element is StackFrame)
              IdeMenuAction(
                s.restartFrame,
                enabled: element.canRestart && element.thread.session.capabilities.flag('supportsRestartFrame'),
                onSelected: () => unawaited(element.restart()),
              ),
            if (thread != null) IdeMenuAction(s.copyCallStack, onSelected: () => unawaited(debugCopy(_copyCallStack(thread)))),
          ],
          [
            if (thread != null && thread.session.capabilities.flag('supportsTerminateThreadsRequest'))
              IdeMenuAction(s.terminateThread, onSelected: () => unawaited(thread.terminate())),
            if (element is DebugSession) ...[
              IdeMenuAction(s.restart, onSelected: () => unawaited(_service.restartSession(element))),
              IdeMenuAction(s.stop, onSelected: () => unawaited(_service.stopSession(element))),
            ],
          ],
          [IdeMenuAction(s.collapseAll, onSelected: _controller.collapseAll)],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    final roots = callStackRoots(_service);
    return DebugTreeView<Object>(
      controller: _controller,
      roots: roots,
      toggleOnTap: false,
      onActivate: _activate,
      onContextMenu: _contextMenu,
      itemBuilder: (context, row, hovered) => switch (row.element) {
        final DebugSession session => _LabelRow(
          icon: Codicons.debugAltSmall,
          label: session.getLabel(),
          state: _sessionStateLabel(session, s),
        ),
        final Thread thread => _LabelRow(
          icon: null,
          label: thread.name,
          state: threadStateLabel(thread, s),
        ),
        final StackFrame frame => _FrameRow(
          frame: frame,
          focused: _service.viewModel.focusedStackFrame == frame,
          hovered: hovered,
          s: s,
        ),
        LoadMoreFrames() => Align(
          alignment: Alignment.centerLeft,
          child: Text(s.loadMoreStackFrames, style: TextStyle(fontSize: 13, color: IdeListColors.highlight)),
        ),
        final other => Text('$other'),
      },
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.icon, required this.label, required this.state});

  final IconData? icon;
  final String label;
  final String state;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[Icon(icon, size: 16, color: IdeListColors.foreground), const SizedBox(width: 4)],
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: IdeListColors.foreground),
        ),
      ),
      if (state.isNotEmpty) ...[const SizedBox(width: 6), Flexible(child: DebugStateLabel(state))],
      const SizedBox(width: 4),
    ],
  );
}

class _FrameRow extends StatelessWidget {
  const _FrameRow({required this.frame, required this.focused, required this.hovered, required this.s});

  final StackFrame frame;
  final bool focused;
  final bool hovered;
  final DebugStrings s;

  @override
  Widget build(BuildContext context) {
    final source = frame.source;
    final location = source.available
        ? '${source.name}  ${frame.range.startLineNumber}:${frame.range.startColumn}'
        : s.unknownSource;
    final top = frame.thread.getTopStackFrame() == frame;
    final dim = frame.deemphasized || !source.available;
    final canRestart = frame.canRestart && frame.thread.session.capabilities.flag('supportsRestartFrame');
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: focused || top
                ? Icon(
                    top ? Codicons.debugStackframe : Codicons.debugStackframeFocused,
                    size: 14,
                    color: debugColor(
                      top ? 'debugIcon.breakpointCurrentStackframeForeground' : 'debugIcon.breakpointStackframeForeground',
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              frame.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: IdeListColors.foreground),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: IdeHover(
              message: source.uri.path,
              child: Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: IdeListColors.description),
              ),
            ),
          ),
          if (hovered && canRestart)
            IdeActionButton(
              icon: Codicons.debugRestartFrame,
              tooltip: s.restartFrame,
              size: 20,
              onPressed: () => unawaited(frame.restart()),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// The Call Stack pane's title actions.
List<Widget> callStackViewActions(BuildContext context, {required VoidCallback onCollapseAll}) => [
  IdePaneAction(icon: Codicons.collapseAll, tooltip: DebugStrings.of(context).collapseAll, onPressed: onCollapseAll),
];
