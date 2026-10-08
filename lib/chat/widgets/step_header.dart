import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import 'hover_builder.dart';
import 'shimmer_text.dart';
import 'wheel_latch.dart';

/// Header of a step the agent took, e.g. "Ran  Check the Flutter version":
/// what it did, then what on, muted. While it is [running] the whole line
/// shimmers. With [onToggle] it opens and closes on a tap; a chevron shows
/// while hovered or open. With [onOpen] a tap opens its file instead (an
/// icon says so while hovered), and the chevron alone opens and closes it.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.verb,
    this.object = '',
    this.detail,
    this.running = false,
    this.expanded = false,
    this.onToggle,
    this.onOpen,
    this.openTooltip,
    this.icon,
    this.trailing,
    this.action,
    this.spans,
  });

  final String verb;
  final String object;

  /// A last word, fainter still (e.g. "L1-40", "+12 -3").
  final String? detail;
  final bool running;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Opens the file it is about (in the side panel, say).
  final VoidCallback? onOpen;

  /// What [onOpen] does, for assistive technologies and the hover.
  final String? openTooltip;

  /// Before the line, e.g. a message's arrows.
  final Widget? icon;

  /// After the line, e.g. an edit's "+12 -3".
  final Widget? trailing;

  /// A button after it all, apart from the click that opens it.
  final Widget? action;

  /// The line in parts, in place of [verb], [object] and [detail]: e.g. a
  /// fold's counts, standing out of its words.
  final List<InlineSpan>? spans;

  /// Its text's size, as steps read.
  static const fontSize = 13.0;

  /// The line as text, e.g. for copying.
  static String text(String verb, String object, [String? detail]) =>
      [verb, object, ?detail].where((part) => part.isNotEmpty).join(' ');

  @override
  Widget build(BuildContext context) {
    final toggle = onToggle;
    // Built once: hovering must not rebuild the text, or a selection in it
    // would be lost.
    final line = spans != null
        ? Text.rich(
            TextSpan(children: spans),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, fontSize: fontSize),
          )
        : running
        ? ShimmerText(
            text(verb, object, detail),
            ellipsis: false,
            padding: EdgeInsets.zero,
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: verb,
                  style: TextStyle(color: AppColors.text),
                ),
                if (object.isNotEmpty) TextSpan(text: ' $object'),
                if (detail case final detail? when detail.isNotEmpty)
                  TextSpan(
                    text: ' $detail',
                    style: TextStyle(color: AppColors.textFaint),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, fontSize: fontSize),
          );
    final open = onOpen;
    // Opening the file, the line's click; the chevron alone toggles.
    final click = open ?? toggle;
    final header = HoverBuilder(
      cursor: click == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final icon?) ...[
              SelectionContainer.disabled(child: icon),
              const SizedBox(width: 5),
            ],
            // Shrinks in a narrow window rather than overflow.
            Flexible(child: line),
            if (trailing case final trailing?) ...[
              const SizedBox(width: 6),
              trailing,
            ],
            if (open != null && hovered) ...[
              const SizedBox(width: 5),
              SelectionContainer.disabled(
                child: Icon(Codicons.goToFile, size: 13, color: AppColors.text),
              ),
            ],
            if (toggle != null && open == null && (hovered || expanded)) ...[
              const SizedBox(width: 2),
              // Comes and goes with the hover: kept out of the selection,
              // which would otherwise re-resolve its edges each time.
              SelectionContainer.disabled(child: _chevron(hovered)),
            ],
          ],
        ),
      ),
    );
    Widget clickable = click == null
        ? header
        : _ClickListener(onClick: click, child: header);
    if (open != null) {
      clickable = Semantics(
        button: true,
        label: openTooltip,
        child: clickable,
      );
    }
    Widget row(bool rowHovered) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: clickable),
        // Its own target: the line's click opens the file. Shown as the
        // chevron of a step that only toggles is, kept in place between.
        if (open != null && toggle != null)
          SelectionContainer.disabled(
            child: Opacity(
              opacity: rowHovered || expanded ? 1 : 0,
              child: HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: toggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 3,
                    ),
                    child: _chevron(hovered),
                  ),
                ),
              ),
            ),
          ),
        if (action case final action?) ...[const SizedBox(width: 10), action],
      ],
    );
    if (open == null || toggle == null) return row(false);
    return HoverBuilder(builder: (context, hovered) => row(hovered));
  }

  Widget _chevron(bool hovered) => AnimatedRotation(
    turns: expanded ? 0.25 : 0,
    duration: const Duration(milliseconds: 150),
    child: Icon(
      Icons.chevron_right_rounded,
      size: 16,
      color: hovered ? AppColors.text : AppColors.textMuted,
    ),
  );
}

/// Calls [onClick] on a plain click: not a drag, not with Shift (which
/// extends a selection). Listens rather than joins the gesture arena, so
/// selecting the text still works.
class _ClickListener extends StatefulWidget {
  const _ClickListener({required this.onClick, required this.child});

  final VoidCallback onClick;
  final Widget child;

  @override
  State<_ClickListener> createState() => _ClickListenerState();
}

class _ClickListenerState extends State<_ClickListener> {
  Offset? _down;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _down =
          event.buttons == kPrimaryButton &&
              !HardwareKeyboard.instance.isShiftPressed
          ? event.position
          : null,
      onPointerMove: (event) {
        final down = _down;
        if (down != null && (event.position - down).distance > 4) _down = null;
      },
      onPointerUp: (_) {
        if (_down == null) return;
        _down = null;
        widget.onClick();
      },
      onPointerCancel: (_) => _down = null,
      child: widget.child,
    );
  }
}

/// What a step opens to: a dark framed box under its header, scrolling
/// past [maxHeight].
class StepBody extends StatelessWidget {
  const StepBody({
    super.key,
    required this.child,
    this.maxHeight = 240,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
    this.followEnd = false,
    this.overlay,
  });

  final Widget child;
  final double maxHeight;
  final EdgeInsetsGeometry padding;

  /// Shows the end rather than the start while it grows (live output).
  final bool followEnd;

  /// Over its top right corner, e.g. a menu button.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.code,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              reverse: followEnd,
              padding: padding,
              child: WheelLatch(
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
          ),
          if (overlay case final overlay?)
            Positioned(top: 6, right: 6, child: overlay),
        ],
      ),
    );
  }
}

/// Monospaced text as steps show it: commands, output, matches.
TextStyle get stepMono => TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: 12,
  height: 1.5,
  color: AppColors.textMuted,
);
