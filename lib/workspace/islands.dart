import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ide/ide_modern_ui.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart';

/// The window's parts as islands: cards of the editor's color on the
/// window's own (`sideBar.background`), apart by a gap rather than a line.
/// What is about a part (its title, its pages' tabs, the branches under a
/// conversation) is on the window's color, outside its card.
abstract final class Islands {
  /// Between two cards, and between a card and the window's edge.
  static const gap = 8.0;

  /// A card's corners.
  static const radius = 12.0;

  /// What is on a card from its edges: its toolbar, its input, its
  /// buttons; the composer from the conversation's.
  static const inset = 12.0;

  /// The rows of a list on a card from its edges, the row's own padding
  /// inside that (a tree's, a picker's).
  static const listInset = 4.0;

  /// A list's row: its corners, in from the card's edges by [listInset].
  static const rowRadius = 6.0;

  /// An input, a button on a card: as high, their corners.
  static const controlHeight = 30.0;
  static const controlRadius = 8.0;

  /// What is raised on a card (an input, the composer, the segment picked):
  /// `input.background`.
  static Color get raised => themeColors['input.background'];

  /// A line on a card (between its parts, about what is raised on it):
  /// `panel.border`, lighter than the card's own outline.
  static Color get line => AppColors.border;

  /// The row along the window's foot, under the cards: a conversation's
  /// branch and its account's quota under its card, the IDE's status bar
  /// under the rest; as high in the agents' window and the IDE.
  static const belowHeight = 28.0;

  /// A card's outline: [AppColors.partBorder], the line the parts had
  /// between them, which stands out on either color.
  static Color get border => AppColors.partBorder;

  /// A segment's fill (a segmented control's, a card's flat tabs', List
  /// and Tree's): the one selected a list's inactive selection's, a hovered
  /// one a toolbar button's hover; no outline.
  static Color? segmentFill({required bool selected, required bool hovered}) =>
      selected
      ? themeColors['list.inactiveSelectionBackground']
      : hovered
      ? themeColors['toolbar.hoverBackground']
      : null;

  /// What a view paints behind it: nothing on a card (an [IslandSurface]
  /// over it: the card's color under it, the window's under its title),
  /// else [color].
  static Color underOr(BuildContext context, Color color) =>
      IslandSurface.colorOf(context) == null ? color : Colors.transparent;

  /// A sash in a gap: nothing at rest, the gap's middle the IDE's
  /// `sash.hoverBorder` while dragged.
  static Widget sashLine({
    required bool dragging,
    required Axis axis,
  }) => Center(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: axis == Axis.horizontal ? (dragging ? IdeModernUI.gap : 0) : null,
      height: axis == Axis.vertical ? (dragging ? IdeModernUI.gap : 0) : null,
      color: dragging ? IdeModernUI.sashHover : Colors.transparent,
    ),
  );
}

/// [child] on a card of [color], its corners rounded and cut: nothing of
/// it shows past them.
class Island extends StatelessWidget {
  const Island({
    super.key,
    required this.color,
    this.borderColor,
    this.squareTopLeft = false,
    required this.child,
  });

  final Color color;

  /// Its outline: [Islands.border] by default.
  final Color? borderColor;

  /// Its top left corner square: under tabs flush with its left edge, the
  /// first of which goes straight down into it (see [IslandTab.atStart]).
  final bool squareTopLeft;
  final Widget child;

  static BorderRadius radiusOf({required bool squareTopLeft}) => squareTopLeft
      ? const BorderRadius.only(
          topRight: Radius.circular(Islands.radius),
          bottomLeft: Radius.circular(Islands.radius),
          bottomRight: Radius.circular(Islands.radius),
        )
      : const BorderRadius.all(Radius.circular(Islands.radius));

  @override
  Widget build(BuildContext context) {
    final radius = radiusOf(squareTopLeft: squareTopLeft);
    return DecoratedBox(
      // The outline over what is in it, at its edge.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: borderColor ?? Islands.border),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(color: color, child: child),
      ),
    );
  }
}

/// [tabs] on the window's color over [body]'s card, as a browser's: the
/// tab in front (an [IslandTab] [IslandTab.active]) one with the card,
/// over its outline; the card's top left corner square while that tab is
/// the first, flush with its edge (see [IslandCorner]).
class IslandTabbedCard extends StatefulWidget {
  const IslandTabbedCard({
    super.key,
    required this.tabs,
    required this.tabsHeight,
    required this.color,
    required this.body,
    this.card = true,
  });

  final Widget tabs;
  final double tabsHeight;
  final Color color;
  final Widget body;

  /// Whether [body] is put on a card: not when it is cards itself (the
  /// first along its top under the tabs, see [IslandCorner.of]).
  final bool card;

  @override
  State<IslandTabbedCard> createState() => _IslandTabbedCardState();
}

class _IslandTabbedCardState extends State<IslandTabbedCard> {
  final _square = ValueNotifier(false);

  @override
  void dispose() {
    _square.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IslandCorner(
    square: _square,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          top: widget.tabsHeight,
          child: widget.card
              ? ValueListenableBuilder(
                  valueListenable: _square,
                  builder: (context, square, body) => Island(
                    color: widget.color,
                    squareTopLeft: square,
                    child: body!,
                  ),
                  child: widget.body,
                )
              : widget.body,
        ),
        // After the card: the tab in front covers its outline.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: widget.tabsHeight,
          child: widget.tabs,
        ),
      ],
    ),
  );
}

/// Whether the card under a strip of tabs has its top left corner square:
/// while the tab in front is the first, flush with the card's edge, its
/// side going straight down into the card's (see [IslandTab.atStart]).
/// That tab says so ([IslandCornerClaim]); the card listens.
class IslandCorner extends InheritedWidget {
  const IslandCorner({super.key, required this.square, required super.child});

  final ValueNotifier<bool> square;

  static ValueNotifier<bool>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<IslandCorner>()?.square;

  @override
  bool updateShouldNotify(IslandCorner old) => old.square != square;
}

/// Tells the card under it ([IslandCorner]) to square its top left corner
/// while [claim]s, after the frame (the card is built before it).
class IslandCornerClaim extends StatefulWidget {
  const IslandCornerClaim({
    super.key,
    required this.claim,
    required this.child,
  });

  final bool claim;
  final Widget child;

  @override
  State<IslandCornerClaim> createState() => _IslandCornerClaimState();
}

class _IslandCornerClaimState extends State<IslandCornerClaim> {
  ValueNotifier<bool>? _corner;
  bool _claimed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final corner = IslandCorner.of(context);
    if (!identical(corner, _corner)) {
      _release();
      _corner = corner;
    }
    _update();
  }

  @override
  void didUpdateWidget(IslandCornerClaim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.claim != widget.claim) _update();
  }

  void _update() {
    final corner = _corner;
    if (corner == null || _claimed == widget.claim) return;
    _claimed = widget.claim;
    final claim = widget.claim;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Another claim since: that one's stands.
      if (_claimed == claim && identical(_corner, corner)) {
        corner.value = claim;
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _release() {
    final corner = _corner;
    if (corner == null || !_claimed) return;
    _claimed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Disposed with it, unless another tab claimed it since.
      try {
        corner.value = false;
      } on FlutterError {
        // The card went with it.
      }
    });
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A tab of an [IslandTabbedCard]'s: in front ([active]), of the card's
/// [color], its top corners rounded and its foot flaring into the card's
/// edge; else on the window's color, its text lit while hovered. [builder]
/// has what is in it in [foreground]'s color.
class IslandTab extends StatefulWidget {
  const IslandTab({
    super.key,
    required this.active,
    required this.color,
    required this.onTap,
    required this.builder,
    this.atStart = false,
  });

  final bool active;

  /// Flush with the card's left edge: in front, its left side goes straight
  /// down into the card's, no foot flaring out there.
  final bool atStart;
  final Color color;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, Color foreground) builder;

  /// How far its foot flares out on either side, past its box.
  static const flare = 10.0;

  /// Its top corners.
  static const radius = 10.0;

  /// From the card's edge to the first tab: clear of the card's corner,
  /// its foot too.
  static const lead = 12.0;

  /// How high it is, at the foot of a taller row (the title bar's).
  static const height = 34.0;

  /// In front, or hovered: `tab.activeForeground`; else
  /// `tab.inactiveForeground`.
  static Color foreground({required bool active, required bool hovered}) =>
      active || hovered
      ? themeColors['tab.activeForeground']
      : themeColors['tab.inactiveForeground'];

  @override
  State<IslandTab> createState() => _IslandTabState();
}

class _IslandTabState extends State<IslandTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) =>
      IslandCornerClaim(claim: widget.atStart && widget.active, child: _tab());

  Widget _tab() => Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      height: IslandTab.height,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: CustomPaint(
            painter: widget.active
                ? IslandTabShape(
                    fill: widget.color,
                    line: Islands.border,
                    flareLeft: !widget.atStart,
                  )
                : null,
            child: widget.builder(
              context,
              IslandTab.foreground(active: widget.active, hovered: _hovered),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The tab in front: its box with rounded top corners, flaring at its foot
/// into the card under it; its outline along all but the foot, which
/// covers the card's own there ([overhang] under the box, where the card's
/// top is its foot; none where the card's outline is the box's last row).
class IslandTabShape extends CustomPainter {
  IslandTabShape({
    required this.fill,
    required this.line,
    this.overhang = 1,
    this.flareLeft = true,
  });

  final Color fill;
  final Color line;
  final double overhang;

  /// Whether its foot flares out at the left too: not where the tab is
  /// flush with the card's edge, its side the card's there.
  final bool flareLeft;

  @override
  void paint(Canvas canvas, Size size) {
    const r = IslandTab.radius;
    const f = IslandTab.flare;
    final w = size.width;
    final h = size.height;
    // Flush, its side half a pixel in: on the card's outline.
    final left = flareLeft ? 0.0 : .5;
    final outline = Path();
    if (flareLeft) {
      outline
        ..moveTo(-f, h)
        ..arcToPoint(
          Offset(0, h - f),
          radius: const Radius.circular(f),
          clockwise: false,
        );
    } else {
      outline.moveTo(left, h + overhang);
    }
    outline
      ..lineTo(left, r)
      ..arcToPoint(Offset(r, left), radius: Radius.circular(r - left))
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, h - f)
      ..arcToPoint(
        Offset(w + f, h),
        radius: const Radius.circular(f),
        clockwise: false,
      );
    // Down over the card's outline under it.
    final shape = Path.from(outline)
      ..lineTo(w + f, h + overhang)
      ..lineTo(flareLeft ? -f : 0, h + overhang)
      ..close();
    canvas.drawPath(shape, Paint()..color = fill);
    canvas.drawPath(
      outline,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(IslandTabShape old) =>
      old.fill != fill ||
      old.line != line ||
      old.overhang != overhang ||
      old.flareLeft != flareLeft;
}

/// A segment of a segmented control on a card (a panel's views): the one
/// [selected] filled, the others the hover's alone (see
/// [Islands.segmentFill]).
class IslandSegment extends StatefulWidget {
  const IslandSegment({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  /// Its height, in a row taller than it.
  static const height = 24.0;

  @override
  State<IslandSegment> createState() => _IslandSegmentState();
}

class _IslandSegmentState extends State<IslandSegment> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.selected) _reveal();
  }

  @override
  void didUpdateWidget(IslandSegment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  /// Picked in a row that scrolls (a narrow panel's): scrolled to, whole.
  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || Scrollable.maybeOf(context) == null) return;
    unawaited(Scrollable.ensureVisible(context));
  });

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Center(
        child: Container(
          height: IslandSegment.height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Islands.segmentFill(
              selected: widget.selected,
              hovered: _hovered,
            ),
            borderRadius: BorderRadius.circular(Islands.controlRadius),
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

/// Between two tabs over a card, [width] wide: a short line where neither
/// is in front ([shown]), as a browser's between its tabs behind; at the
/// foot of the row, level with the tabs.
class IslandTabSeparator extends StatelessWidget {
  const IslandTabSeparator({super.key, required this.shown, this.width = 2});

  final bool shown;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: shown
        ? Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: IslandTab.height,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(child: Container(width: 1, color: Islands.line)),
              ),
            ),
          )
        : null,
  );
}

/// What is under it is on a card of [color] (see [HeadedIsland]): its
/// lists on the card's color rather than the side bar's, its tabs as a
/// browser's ([IslandTab]'s look), its strip on the window's color; its
/// last [footer] on the window's color too, under the card.
class IslandSurface extends InheritedWidget {
  const IslandSurface({
    super.key,
    required this.color,
    this.footer = 0,
    required super.child,
  });

  final Color color;
  final double footer;

  static IslandSurface? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IslandSurface>();

  /// The card's color, where there is one.
  static Color? colorOf(BuildContext context) => _of(context)?.color;

  /// How high the row under the card is, where there is one (see
  /// [Islands.belowHeight]); else 0.
  static double footerOf(BuildContext context) => _of(context)?.footer ?? 0;

  @override
  bool updateShouldNotify(IslandSurface old) =>
      old.color != color || old.footer != footer;
}

/// [child] on a card of [color], all but its first [header] and its last
/// [footer] high on the window's color: a part's title or tabs over its
/// card, the tab in front one with the card (an [IslandSurface] under it);
/// a conversation's branch under it. The card's outline along the header's
/// last row, which the tab in front covers.
class HeadedIsland extends StatefulWidget {
  const HeadedIsland({
    super.key,
    required this.header,
    this.footer = 0,
    required this.color,
    required this.child,
  });

  final double header;
  final double footer;
  final Color color;
  final Widget child;

  @override
  State<HeadedIsland> createState() => _HeadedIslandState();
}

class _HeadedIslandState extends State<HeadedIsland> {
  /// Its top left corner square (see [IslandCorner]).
  final _square = ValueNotifier(false);

  @override
  void dispose() {
    _square.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IslandCorner(
    square: _square,
    child: IslandSurface(
      color: widget.color,
      footer: widget.footer,
      child: ValueListenableBuilder(
        valueListenable: _square,
        builder: (context, square, child) => Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              top: math.max(0.0, widget.header - 1),
              bottom: widget.footer,
              child: Island(
                color: widget.color,
                squareTopLeft: square,
                child: const SizedBox.expand(),
              ),
            ),
            // Inside the outline, with its corners; the header and the
            // footer as they are.
            ClipPath(
              clipper: _HeadedClip(widget.header, widget.footer, square),
              child: child,
            ),
          ],
        ),
        child: widget.child,
      ),
    ),
  );
}

class _HeadedClip extends CustomClipper<Path> {
  _HeadedClip(this.header, this.footer, this.squareTopLeft);

  final double header;
  final double footer;
  final bool squareTopLeft;

  @override
  Path getClip(Size size) {
    final top = math.max(0.0, header - 1);
    final bottom = size.height - footer;
    const inner = Radius.circular(Islands.radius - 1);
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, header))
      ..addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(1, top + 1, size.width - 1, bottom - 1),
          topLeft: squareTopLeft ? Radius.zero : inner,
          topRight: inner,
          bottomLeft: inner,
          bottomRight: inner,
        ),
      )
      ..addRect(Rect.fromLTRB(0, bottom, size.width, size.height));
  }

  @override
  bool shouldReclip(_HeadedClip old) =>
      old.header != header ||
      old.footer != footer ||
      old.squareTopLeft != squareTopLeft;
}

/// Whether the row under a conversation's card (its branch, see
/// [Islands.belowHeight]) is shown by what is around it rather than under
/// the card: under the terminals' card below the conversation's, at the
/// window's foot.
class IslandFootHosted extends InheritedWidget {
  const IslandFootHosted({
    super.key,
    required this.hosted,
    required super.child,
  });

  final bool hosted;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IslandFootHosted>()?.hosted ??
      false;

  @override
  bool updateShouldNotify(IslandFootHosted old) => old.hosted != hosted;
}

/// What is under it is the first tab of a strip flush with its card's left
/// edge (see [IslandTab.atStart]), for the tabs that do not take that
/// themselves (the IDE's).
class IslandTabStart extends InheritedWidget {
  const IslandTabStart({super.key, this.atStart = true, required super.child});

  final bool atStart;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IslandTabStart>()?.atStart ??
      false;

  @override
  bool updateShouldNotify(IslandTabStart old) => old.atStart != atStart;
}
