import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';
import 'chat_item_view.dart' show chatItemPlainText;
import 'flip_switcher.dart';
import 'hover_builder.dart';
import 'orbit_indicator.dart';
import 'shimmer_text.dart';
import '../../ide/ide_hover.dart';

/// A subagent as a card, a line: what it was given to do, then what it did
/// last, flipping up to the next as it goes on, and once done to how it
/// went ("Explore · 55s · 5 tools · 8.2k tokens"). A click, or Enter once
/// focused, opens its own conversation ([onOpen]), where the rest is.
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

  /// Its kind and progress, e.g. "Explore · 69s · 12 tools · 8.2k tokens";
  /// in [l10n]'s language (English when null).
  static String meta(AgentItem item, {DateTime? now, AppLocalizations? l10n}) {
    final strings = l10n ?? englishLocalizations;
    return [
      ?item.agentType,
      if (elapsed(item, now: now) case final time?)
        formatDuration(time, l10n: strings),
      ?tools(item, l10n: strings),
      if (item.tokens case final tokens? when tokens > 0)
        strings.chatTokens(formatTokens(tokens)),
    ].join(' · ');
  }

  /// How long it ran, or has been running.
  static Duration? elapsed(AgentItem item, {DateTime? now}) =>
      item.duration ??
      switch ((item.status, item.startedAt)) {
        (CommandStatus.running, final start?) =>
          (now ?? DateTime.now()).difference(start),
        _ => null,
      };

  /// "46s", "2m 14s", "1h 5m"; in [l10n]'s language (English when null).
  static String formatDuration(Duration time, {AppLocalizations? l10n}) {
    final strings = l10n ?? englishLocalizations;
    final seconds = time.inSeconds;
    if (seconds < 60) return strings.durationSeconds(seconds);
    if (seconds < 3600) {
      return strings.durationMinutesSeconds(seconds ~/ 60, seconds % 60);
    }
    return strings.durationHoursMinutes(seconds ~/ 3600, seconds % 3600 ~/ 60);
  }

  /// "950", "8.2k", "1.4M".
  static String formatTokens(int tokens) => switch (tokens) {
    < 1000 => '$tokens',
    < 1000000 => '${(tokens / 1000).toStringAsFixed(1)}k',
    _ => '${(tokens / 1000000).toStringAsFixed(1)}M',
  };

  /// The tools it has used, e.g. "12 tools"; null before the first. In
  /// [l10n]'s language (English when null).
  static String? tools(AgentItem item, {AppLocalizations? l10n}) =>
      switch (item.toolUses) {
        final uses? when uses > 0 =>
          (l10n ?? englishLocalizations).chatToolCount(uses),
        _ => null,
      };

  /// What it did last, in a line, e.g. "Ran Find reusable helpers"; what
  /// it was asked before it does anything. Null with nothing to say.
  static String? latest(AgentItem item, {AppLocalizations? l10n}) {
    for (final child in item.children.reversed) {
      if (_firstLine(chatItemPlainText(child, l10n: l10n)) case final line?) {
        return line;
      }
    }
    return _firstLine(item.activity) ?? _firstLine(item.prompt);
  }

  /// What follows its description: while it runs, what it did last; once
  /// done, how it went. Null with nothing to say.
  static String? trailing(AgentItem item, {AppLocalizations? l10n}) =>
      switch (item.status) {
        CommandStatus.running => latest(item, l10n: l10n),
        _ => switch (meta(item, l10n: l10n)) {
          '' => null,
          final meta => meta,
        },
      };

  /// The first line of [text] with anything in it, out of its markdown's
  /// heading and emphasis marks.
  static String? _firstLine(String? text) {
    if (text == null) return null;
    for (final line in text.split('\n')) {
      final plain = line
          .replaceFirst(RegExp(r'^\s*(#+|[-*•]|>)\s+'), '')
          .replaceAll('**', '')
          .trim();
      if (plain.isNotEmpty) return plain;
    }
    return null;
  }

  /// The card as text, for copying: as it reads.
  static String plainText(AgentItem item, {AppLocalizations? l10n}) => [
    item.description,
    if (trailing(item, l10n: l10n) case final trailing?) '· $trailing',
  ].join(' ');

  @override
  State<AgentStep> createState() => _AgentStepState();
}

const _titleStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);

/// Its line's height, whatever fonts its text falls back on (CJK's run
/// taller than Latin's): it keeps its height as what follows changes.
const _lineStrut = StrutStyle(
  fontSize: 13,
  height: 1.4,
  forceStrutHeight: true,
);

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
    final l10n = context.l10n;
    final trailing = AgentStep.trailing(item, l10n: l10n);
    final open = widget.onOpen;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      child: Row(
        children: [
          AgentStatusIcon(item.status, background: item.background),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  // Shimmers while it works.
                  Flexible(
                    child: running
                        ? ShimmerText(
                            item.description,
                            ellipsis: false,
                            padding: EdgeInsets.zero,
                            style: _titleStyle,
                            strutStyle: _lineStrut,
                          )
                        : Text(
                            item.description,
                            strutStyle: _lineStrut,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _titleStyle.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                  ),
                  if (trailing != null)
                    // At most half the line, the description having the
                    // rest.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth / 2,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: FlipSwitcher(
                          child: Text(
                            '· $trailing',
                            key: ValueKey(trailing),
                            strutStyle: _lineStrut,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textFaint,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
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
            Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
    final status = switch (item.status) {
      CommandStatus.running when item.background =>
        l10n.agentStateRunningInBackground,
      CommandStatus.running => l10n.agentStateRunning,
      CommandStatus.succeeded => l10n.agentStateDone,
      CommandStatus.failed => l10n.agentStateFailed,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Semantics(
        container: true,
        button: open != null,
        label: l10n.chatSubagentSemantics(item.description, status),
        hint: open == null ? null : l10n.chatOpensItsConversation,
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
                      ? AppColors.surfaceRaised
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _focused
                        ? themeColors['focusBorder']
                        : hovered && open != null
                        ? AppColors.borderStrong
                        : AppColors.border,
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
        CommandStatus.running when background => IdeHover(
          message: context.l10n.statusRunningInBackground,
          child: const OrbitIndicator(),
        ),
        CommandStatus.running => Padding(
          padding: EdgeInsets.all(1.5),
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AppColors.textMuted,
          ),
        ),
        // As upstream's session status.
        CommandStatus.succeeded => Icon(
          Icons.check_circle_outline_rounded,
          size: 14,
          color: themeColors['testing.iconPassed'],
        ),
        CommandStatus.failed => Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: themeColors['testing.iconFailed'],
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
    return IdeHover(
      message: context.l10n.chatStop,
      child: Semantics(
        button: true,
        label: context.l10n.chatStop,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onTap,
            child: Icon(
              Icons.stop_rounded,
              size: 15,
              color: hovered ? AppColors.text : AppColors.textMuted,
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
    return IdeHover(
      message: context.l10n.chatKeepRunningHint,
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
                color: hovered ? AppColors.text : AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                context.l10n.chatBackground,
                style: TextStyle(
                  color: hovered ? AppColors.text : AppColors.textMuted,
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
