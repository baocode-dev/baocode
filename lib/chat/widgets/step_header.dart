import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../base/smooth_scroll.dart';
import '../../theme/app_theme.dart';
import 'finite_selection_edges.dart';
import 'hover_builder.dart';
import 'hover_scrollbar.dart';
import 'image_thumbnails.dart' show PreviewClick, PreviewPressScope;
import 'scroll_edge_fade.dart';
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
    this.trailingGap = 6,
    this.action,
    this.spans,
    this.bold = false,
  });

  final String verb;
  final String object;

  /// A last word, fainter still (e.g. "L1-40", "+12 -3").
  final String? detail;
  final bool running;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Opens the file it is about (in the side panel, say): its click,
  /// unless it opens to more ([onToggle]).
  final VoidCallback? onOpen;

  /// What [onOpen] does, for assistive technologies and the hover.
  final String? openTooltip;

  /// Before the line, e.g. a message's arrows.
  final Widget? icon;

  /// After the line, e.g. an edit's "+12 -3".
  final Widget? trailing;

  /// Between the line and [trailing]: none for one that keeps its own, to
  /// go with it (a [StepThumbnails]'s).
  final double trailingGap;

  /// A button after it all, apart from the click that opens it.
  final Widget? action;

  /// The line in parts, in place of [verb], [object] and [detail]: e.g. a
  /// fold's counts, standing out of its words.
  final List<InlineSpan>? spans;

  /// The line in bold, as a title (a summarized thought's, say).
  final bool bold;

  /// Its text's size, as steps read.
  static const fontSize = 13.0;

  /// The line as text, e.g. for copying.
  static String text(String verb, String object, [String? detail]) =>
      [verb, object, ?detail].where((part) => part.isNotEmpty).join(' ');

  @override
  Widget build(BuildContext context) {
    final toggle = onToggle;
    final weight = bold ? FontWeight.w600 : null;
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
            style: TextStyle(fontWeight: weight),
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: verb,
                  style: TextStyle(color: AppColors.text),
                ),
                if (object.isNotEmpty)
                  TextSpan(text: verb.isEmpty ? object : ' $object'),
                if (detail case final detail? when detail.isNotEmpty)
                  TextSpan(
                    text: ' $detail',
                    style: TextStyle(color: AppColors.textFaint),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: fontSize,
              fontWeight: weight,
            ),
          );
    // One that opens to more toggles on its click: the file it is about
    // opens from its right click then (see FileLinkMenuRegion).
    final open = toggle == null ? onOpen : null;
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
              SizedBox(width: trailingGap),
              trailing,
            ],
            if (open != null && hovered) ...[
              const SizedBox(width: 2),
              SelectionContainer.disabled(
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.text,
                ),
              ),
            ],
            if (toggle != null && (hovered || expanded)) ...[
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
      clickable = Semantics(button: true, label: openTooltip, child: clickable);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: clickable),
        if (action case final action?) ...[const SizedBox(width: 10), action],
      ],
    );
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

  /// Whether the press going down is on a picture in it, which a click
  /// shows whole (see [PreviewClick]): heard before the line's.
  bool _onPicture = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        final onPicture = _onPicture;
        _onPicture = false;
        _down =
            !onPicture &&
                event.buttons == kPrimaryButton &&
                !HardwareKeyboard.instance.isShiftPressed
            ? event.position
            : null;
      },
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
      child: PreviewPressScope(
        onPress: () => _onPicture = true,
        child: widget.child,
      ),
    );
  }
}

/// What a step opens to: a dark framed box under its header, scrolling
/// past [maxHeight].
class StepBody extends StatefulWidget {
  const StepBody({
    super.key,
    required this.child,
    this.maxHeight = 240,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
    this.followEnd = false,
    this.overlay,
    this.header,
    this.fadeEdges = false,
    this.scrollbar = false,
    this.codeBlock = false,
    this.keepWheel = false,
    this.bottom,
  });

  final Widget child;
  final double maxHeight;
  final EdgeInsetsGeometry padding;

  /// Shows the end rather than the start while it grows (live output).
  final bool followEnd;

  /// Over its top right corner, e.g. a menu button.
  final Widget? overlay;

  /// Above [child], a line under it, staying while [child] scrolls.
  final Widget? header;

  /// No background of its own: a frame on the conversation; else a dark
  /// box.
  final bool codeBlock;

  /// Whether [child] fades out towards an edge more of it is scrolled past
  /// ([ScrollEdgeFade]), as the conversation does; not with [followEnd].
  final bool fadeEdges;

  /// Whether a scrollbar shows while the mouse is over it ([HoverScrollbar]).
  final bool scrollbar;

  /// Whether a wheel over it, once it scrolls at all, is its own at its ends
  /// too ([WheelLatch.keep]).
  final bool keepWheel;

  /// Along the bottom of what scrolls, over [child]: scrollbars across it,
  /// say, shown while the mouse is over it ([hovered]).
  final Widget Function(BuildContext context, bool hovered)? bottom;

  @override
  State<StepBody> createState() => _StepBodyState();
}

class _StepBodyState extends State<StepBody> {
  final _controller = SmoothScrollController();

  @override
  void didUpdateWidget(StepBody old) {
    super.didUpdateWidget(old);
    if (old.followEnd != widget.followEnd && _controller.hasClients) {
      _keepInView(_controller.position);
    }
  }

  /// [StepBody.followEnd] turns the view round (the command ended, or went
  /// to the background), its offset now counted from the other end: what
  /// was in view stays, rather than the view jumping to the far end.
  void _keepInView(ScrollPosition position) {
    // How far it is from the end its offset counted from, which is now the
    // far end.
    final held = position.pixels - position.minScrollExtent;
    // Before this frame's layout, so the far end never shows.
    position.correctPixels(position.maxScrollExtent - held);
    // At that end (following the output), it stays there, though the
    // output grew as it ended; scrolled off it, nothing in view moves.
    if (held > 0.5) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final now = _controller.position;
      if (now.pixels != now.maxScrollExtent) now.jumpTo(now.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final StepBody(:child, :maxHeight, :padding, :overlay, :header) = widget;
    // The line between the sidebar and the conversation.
    final line = AppColors.partBorder;
    Widget scroll = SingleChildScrollView(
      controller: _controller,
      reverse: widget.followEnd,
      padding: padding,
      child: FiniteSelectionEdges(
        child: WheelLatch(
          keep: widget.keepWheel,
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
    if (widget.fadeEdges) {
      scroll = ScrollEdgeFade(fadeLength: 12, child: scroll);
    }
    Widget stack(bool hovered) => Stack(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: widget.scrollbar
              ? Scrollbar(
                  controller: _controller,
                  thumbVisibility: hovered,
                  child: scroll,
                )
              : scroll,
        ),
        if (widget.bottom case final bottom?)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: bottom(context, hovered),
          ),
        if (overlay case final overlay?)
          Positioned(top: 6, right: 6, child: overlay),
      ],
    );
    // Its scrollbars show while the mouse is over it ([HoverScrollbar]).
    Widget body = widget.scrollbar || widget.bottom != null
        ? HoverBuilder(builder: (context, hovered) => stack(hovered))
        : stack(false);
    if (header case final header?) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          Divider(height: 1, thickness: 1, color: line),
          body,
        ],
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      decoration: BoxDecoration(
        // A code block's lies on the conversation itself.
        color: widget.codeBlock ? null : AppColors.code,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}

/// Monospaced text as steps show it: commands, output, matches.
TextStyle get stepMono =>
    AppFonts.uiCodeStyle(12).copyWith(height: 1.5, color: AppColors.textMuted);
