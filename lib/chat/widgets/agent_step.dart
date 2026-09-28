import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import 'hover_builder.dart';
import 'orbit_indicator.dart';
import 'shimmer_text.dart';

/// A subagent as a card: what it was given to do, and the tools it has
/// used. A click, or Enter once focused, opens its own conversation
/// ([onOpen]), where the rest is.
class AgentStep extends StatefulWidget {
  const AgentStep({
    super.key,
    required this.item,
    this.onOpen,
    this.onStop,
    this.onMoveToBackground,
  });

  final AgentItem item;
  final VoidCallback? onOpen;

  /// Stops it while it runs.
  final VoidCallback? onStop;

  /// Lets the turn go on while the subagent keeps working.
  final VoidCallback? onMoveToBackground;

  /// Its kind and progress, e.g. "Explore · 69s · 12 tools · 8.2k tokens".
  static String meta(AgentItem item, {DateTime? now}) => [
    ?item.agentType,
    if (elapsed(item, now: now) case final time?) formatDuration(time),
    if (item.toolUses case final uses? when uses > 0)
      '$uses ${uses == 1 ? 'tool' : 'tools'}',
    if (item.tokens case final tokens? when tokens > 0)
      '${formatTokens(tokens)} tokens',
  ].join(' · ');

  /// How long it ran, or has been running.
  static Duration? elapsed(AgentItem item, {DateTime? now}) =>
      item.duration ??
      switch ((item.status, item.startedAt)) {
        (CommandStatus.running, final start?) =>
          (now ?? DateTime.now()).difference(start),
        _ => null,
      };

  /// "46s", "2m 14s", "1h 5m".
  static String formatDuration(Duration time) {
    final seconds = time.inSeconds;
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
    return '${seconds ~/ 3600}h ${seconds % 3600 ~/ 60}m';
  }

  /// "950", "8.2k", "1.4M".
  static String formatTokens(int tokens) => switch (tokens) {
    < 1000 => '$tokens',
    < 1000000 => '${(tokens / 1000).toStringAsFixed(1)}k',
    _ => '${(tokens / 1000000).toStringAsFixed(1)}M',
  };

  /// The tools it has used, e.g. "12 tools"; null before the first.
  static String? tools(AgentItem item) => switch (item.toolUses) {
    final uses? when uses > 0 => '$uses ${uses == 1 ? 'tool' : 'tools'}',
    _ => null,
  };

  /// The card as text, for copying: as it reads.
  static String plainText(AgentItem item) =>
      [item.description, ?tools(item)].join(' ');

  @override
  State<AgentStep> createState() => _AgentStepState();
}

const _titleStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);

class _AgentStepState extends State<AgentStep> {
  bool _focused = false;

  /// A press that may open it: plain, and not on one of its buttons.
  Offset? _down;

  /// The press under way began on one of its buttons (which hear it
  /// first, being deeper).
  bool _onButton = false;

  void _open() => widget.onOpen?.call();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final running = item.status == CommandStatus.running;
    final tools = AgentStep.tools(item);
    final open = widget.onOpen;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      child: Row(
        children: [
          AgentStatusIcon(item.status, background: item.background),
          const SizedBox(width: 8),
          Expanded(
            // Shimmers while it works.
            child: running
                ? ShimmerText(
                    item.description,
                    ellipsis: false,
                    padding: EdgeInsets.zero,
                    style: _titleStyle,
                  )
                : Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle.copyWith(
                      color: CursorColors.textPrimary,
                    ),
                  ),
          ),
          if (tools != null)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                tools,
                style: const TextStyle(
                  color: CursorColors.textFaint,
                  fontSize: 12,
                ),
              ),
            ),
          // Its buttons take their own presses (see _down).
          Listener(
            onPointerDown: (_) => _onButton = true,
            child: _Actions(
              onMoveToBackground: running ? widget.onMoveToBackground : null,
              onStop: running ? widget.onStop : null,
            ),
          ),
          if (open != null)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: CursorColors.textMuted,
              ),
            ),
        ],
      ),
    );
    final status = switch (item.status) {
      CommandStatus.running when item.background => 'running in the background',
      CommandStatus.running => 'running',
      CommandStatus.succeeded => 'done',
      CommandStatus.failed => 'failed',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Semantics(
        container: true,
        button: open != null,
        label: 'Subagent ${item.description}, $status',
        hint: open == null ? null : 'Opens its conversation',
        child: FocusableActionDetector(
          enabled: open != null,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) => _open(),
            ),
          },
          child: Listener(
            // Listens rather than joins the gesture arena, so selecting its
            // text still works: a plain click opens it, a drag does not.
            onPointerDown: (event) {
              _down =
                  open != null &&
                      !_onButton &&
                      event.buttons == kPrimaryButton &&
                      !HardwareKeyboard.instance.isShiftPressed
                  ? event.position
                  : null;
              _onButton = false;
            },
            onPointerMove: (event) {
              final down = _down;
              if (down != null && (event.position - down).distance > 4) {
                _down = null;
              }
            },
            onPointerUp: (_) {
              if (_down == null) return;
              _down = null;
              _open();
            },
            onPointerCancel: (_) => _down = null,
            child: HoverBuilder(
              cursor: open == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              // The content is built once: hovering must not rebuild its
              // text, or a selection in it would be lost.
              builder: (context, hovered) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: hovered && open != null
                      ? CursorColors.surfaceRaised
                      : CursorColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _focused
                        ? CursorColors.accent
                        : hovered && open != null
                        ? CursorColors.borderStrong
                        : CursorColors.border,
                  ),
                ),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Running, done or failed, as a 14 px mark; running in the background as
/// an orbit.
class AgentStatusIcon extends StatelessWidget {
  const AgentStatusIcon(this.status, {super.key, this.background = false});

  final CommandStatus status;
  final bool background;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 14,
      child: switch (status) {
        CommandStatus.running when background => const Tooltip(
          message: 'Running in the background',
          waitDuration: Duration(milliseconds: 500),
          child: OrbitIndicator(),
        ),
        CommandStatus.running => const Padding(
          padding: EdgeInsets.all(1.5),
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: CursorColors.textMuted,
          ),
        ),
        CommandStatus.succeeded => const Icon(
          Icons.check_circle_outline_rounded,
          size: 14,
          color: CursorColors.added,
        ),
        CommandStatus.failed => const Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: CursorColors.removed,
        ),
      },
    );
  }
}

/// Background and Stop, while it runs and they can be done.
class _Actions extends StatelessWidget {
  const _Actions({this.onMoveToBackground, this.onStop});

  final VoidCallback? onMoveToBackground;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onMoveToBackground case final move?) ...[
            const SizedBox(width: 8),
            BackgroundButton(onTap: move),
          ],
          if (onStop case final stop?) ...[
            const SizedBox(width: 10),
            StopButton(onTap: stop),
          ],
        ],
      ),
    );
  }
}

/// Stops a running subagent.
class StopButton extends StatelessWidget {
  const StopButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Stop',
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        label: 'Stop',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onTap,
            child: Icon(
              Icons.stop_rounded,
              size: 15,
              color: hovered ? CursorColors.text : CursorColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves a running command or subagent to the background, as Ctrl+B does
/// in a terminal.
class BackgroundButton extends StatelessWidget {
  const BackgroundButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Keep it running and let the agent go on',
      waitDuration: const Duration(milliseconds: 500),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.move_down_rounded,
                size: 13,
                color: hovered ? CursorColors.text : CursorColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Background',
                style: TextStyle(
                  color: hovered ? CursorColors.text : CursorColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
