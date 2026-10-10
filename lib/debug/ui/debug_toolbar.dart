// The floating debug toolbar: continue or pause, step over, into and out,
// step back and reverse where the adapter can, restart, stop or
// disconnect, hot reload where it applies, and the session picker when
// several run.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/debugToolBar.ts and the actions
// of debugCommands.ts (`continue`, `pause`, `stepOver`…, `restart`,
// `stop`/`disconnect`, `focusSession`).
//
// Deviations: hot reload is BaoCode's: a custom request where a debug type
// has one ([DebugHotReload]), else the adapter's `restart` request.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_menu.dart';
import '../../theme/codicons.dart';
import '../common/debug_model.dart';
import '../common/debug_types.dart';
import '../common/debug_view_model.dart';
import '../service/debug_service.dart';
import '../session/debug_session.dart';
import 'debug_icons.dart';
import 'debug_strings.dart';

/// How a session hot reloads, if it can.
typedef DebugHotReload = Future<void> Function(DebugSession session)?;

/// The custom hot reload requests of debug types (Dart-Code's adapter).
const defaultHotReloadRequests = <String, String>{'dart': 'hotReload', 'flutter': 'hotReload'};

/// Hot reload for [session]: its type's custom request, else the adapter's
/// `restart` request; null when neither applies.
DebugHotReload defaultHotReload(DebugSession session) {
  final custom = defaultHotReloadRequests[session.configuration.str('type')];
  if (custom != null) return (s) async => s.customRequest(custom, const {});
  if (session.capabilities.flag('supportsRestartRequest')) return (s) => s.restart();
  return null;
}

/// The thread the step actions act on: the focused one, else the first
/// stopped one of the focused session.
Thread? debugActionThread(DebugService service) {
  final vm = service.viewModel;
  final thread = vm.focusedThread;
  if (thread != null) return thread;
  return vm.focusedSession?.getAllThreads().where((t) => t.stopped).firstOrNull;
}

/// Whether the toolbar shows.
bool debugToolbarVisible(DebugService service) {
  final session = service.viewModel.focusedSession;
  if (session != null && session.suppressDebugToolbar) return false;
  return service.state != DebugState.inactive;
}

class DebugToolbar extends StatelessWidget {
  const DebugToolbar({super.key, required this.service, this.hotReload = defaultHotReload, this.dragHandle});

  final DebugService service;

  /// How the focused session hot reloads (null hides the button).
  final DebugHotReload Function(DebugSession session) hotReload;

  /// Drawn at the start; the floating toolbar moves by it.
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([service, service.viewModel]),
    builder: (context, _) {
      final s = DebugStrings.of(context);
      final vm = service.viewModel;
      final state = service.state;
      final session = vm.focusedSession;
      final thread = debugActionThread(service);
      final stopped = state == DebugState.stopped;
      final running = state == DebugState.running;
      final attach = vm.focusedSessionIsAttach;
      final reload = session != null && state != DebugState.inactive ? hotReload(session) : null;
      final sessions = service.model.getSessions();
      final shown = service.settings().showSubSessionsInToolBar
          ? sessions
          : sessions.where((s) => s.parentSession == null).toList();

      Widget button(IconData icon, String tooltip, String color, VoidCallback? onPressed) => IdeActionButton(
        icon: icon,
        tooltip: tooltip,
        size: 26,
        iconSize: 16,
        color: onPressed == null ? null : debugColor(color),
        onPressed: onPressed,
      );

      return Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: debugColor('debugToolBar.background'),
          border: Border.all(color: debugColor('debugToolBar.border')),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [BoxShadow(color: debugColor('widget.shadow'), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?dragHandle,
            if (stopped)
              button(Codicons.debugContinue, '${s.continue_} (F5)', 'debugIcon.continueForeground', () {
                unawaited(thread?.continue_());
              })
            else
              button(
                Codicons.debugPause,
                '${s.pause} (F6)',
                'debugIcon.pauseForeground',
                running && thread != null ? () => unawaited(thread.pause()) : null,
              ),
            button(
              Codicons.debugStepOver,
              '${s.stepOver} (F10)',
              'debugIcon.stepOverForeground',
              stopped && thread != null ? () => unawaited(thread.next()) : null,
            ),
            button(
              Codicons.debugStepInto,
              '${s.stepInto} (F11)',
              'debugIcon.stepIntoForeground',
              stopped && thread != null ? () => unawaited(thread.stepIn()) : null,
            ),
            button(
              Codicons.debugStepOut,
              '${s.stepOut} (⇧F11)',
              'debugIcon.stepOutForeground',
              stopped && thread != null ? () => unawaited(thread.stepOut()) : null,
            ),
            if (vm.stepBackSupported) ...[
              button(
                Codicons.debugStepBack,
                s.stepBack,
                'debugIcon.stepBackForeground',
                stopped && thread != null ? () => unawaited(thread.stepBack()) : null,
              ),
              button(
                Codicons.debugReverseContinue,
                s.reverseContinue,
                'debugIcon.reverseContinueForeground',
                stopped && thread != null ? () => unawaited(thread.reverseContinue()) : null,
              ),
            ],
            if (reload != null)
              button(Codicons.zap, s.hotReload, 'debugIcon.startForeground', () => unawaited(reload(session!))),
            button(
              Codicons.debugRestart,
              '${s.restart} (⇧⌘F5)',
              'debugIcon.restartForeground',
              session != null ? () => unawaited(service.restartSession(session)) : null,
            ),
            if (attach)
              button(
                Codicons.debugDisconnect,
                '${s.disconnect} (⇧F5)',
                'debugIcon.disconnectForeground',
                () => unawaited(service.stopSession(session, disconnect: true)),
              )
            else
              button(
                Codicons.debugStop,
                '${s.stop} (⇧F5)',
                'debugIcon.stopForeground',
                () => unawaited(service.stopSession(session)),
              ),
            if (shown.length > 1 && session != null) _SessionPicker(service: service, sessions: shown),
          ],
        ),
      );
    },
  );
}

class _SessionPicker extends StatelessWidget {
  const _SessionPicker({required this.service, required this.sessions});

  final DebugService service;
  final List<DebugSession> sessions;

  @override
  Widget build(BuildContext context) {
    final focused = service.viewModel.focusedSession;
    return Builder(
      builder: (context) => GestureDetector(
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          unawaited(
            showIdeMenu(
              context,
              anchor: rect,
              entries: [
                for (final s in sessions)
                  IdeMenuAction(
                    s.getLabel(),
                    checked: s == focused,
                    onSelected: () => unawaited(service.focusStackFrame(null, session: s, explicit: true)),
                  ),
              ],
            ),
          );
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  focused?.getLabel() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: debugColor('foreground')),
                ),
              ),
              Icon(Codicons.chevronDown, size: 14, color: debugColor('foreground')),
            ],
          ),
        ),
      ),
    );
  }
}

/// The toolbar over [child], movable along the top by its grip
/// (`debug.toolBarLocation: floating`).
class FloatingDebugToolbar extends StatefulWidget {
  const FloatingDebugToolbar({super.key, required this.service, required this.child, this.hotReload = defaultHotReload});

  final DebugService service;
  final Widget child;
  final DebugHotReload Function(DebugSession session) hotReload;

  @override
  State<FloatingDebugToolbar> createState() => _FloatingDebugToolbarState();
}

class _FloatingDebugToolbarState extends State<FloatingDebugToolbar> {
  /// Where the bar is, as a fraction of the free width (0.5: centered).
  double _x = 0.5;
  double _y = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      children: [
        Positioned.fill(child: widget.child),
        ListenableBuilder(
          listenable: Listenable.merge([widget.service, widget.service.viewModel]),
          builder: (context, _) {
            if (!debugToolbarVisible(widget.service)) return const SizedBox.shrink();
            return Positioned(
              top: _y,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment(_x * 2 - 1, -1),
                child: DebugToolbar(
                  service: widget.service,
                  hotReload: widget.hotReload,
                  dragHandle: GestureDetector(
                    onPanUpdate: (d) => setState(() {
                      _x = (_x + d.delta.dx / (constraints.maxWidth - 260).clamp(1, double.infinity)).clamp(0, 1);
                      _y = (_y + d.delta.dy).clamp(0, (constraints.maxHeight - 30).clamp(0, double.infinity));
                    }),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: SizedBox(
                        width: 10,
                        height: 26,
                        child: Icon(Codicons.gripper, size: 14, color: debugColor('foreground').withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}

/// [isSessionAttach], for hosts.
bool debugSessionIsAttach(DebugSession session) => isSessionAttach(session);
