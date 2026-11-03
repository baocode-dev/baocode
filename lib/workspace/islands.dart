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

  /// The row under a conversation's card (its branch, its account's
  /// quota), at the least: what beside it is ends where the card does,
  /// over the same row left empty.
  static const belowHeight = 26.0;

  /// A card's outline: [AppColors.partBorder], the line the parts had
  /// between them, which stands out on either color.
  static Color get border => AppColors.partBorder;

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
    required this.child,
  });

  final Color color;

  /// Its outline: [Islands.border] by default.
  final Color? borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(Islands.radius));
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
/// over its outline.
class IslandTabbedCard extends StatelessWidget {
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
  /// first along its top under the tabs).
  final bool card;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        top: tabsHeight,
        child: card ? Island(color: color, child: body) : body,
      ),
      // After the card: the tab in front covers its outline.
      Positioned(left: 0, right: 0, top: 0, height: tabsHeight, child: tabs),
    ],
  );
}

/// A tab of an [IslandTabbedCard]'s: in front ([active]), of the card's
/// [color], its top corners rounded and its foot flaring into the card's
/// edge; else nothing behind it but the hover's.
class IslandTab extends StatefulWidget {
  const IslandTab({
    super.key,
    required this.active,
    required this.color,
    required this.onTap,
    required this.child,
  });

  final bool active;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  /// How far its foot flares out on either side, past its box.
  static const flare = 10.0;

  /// Its top corners.
  static const radius = 10.0;

  /// How high it is, at the foot of a taller row (the title bar's).
  static const height = 30.0;

  @override
  State<IslandTab> createState() => _IslandTabState();
}

class _IslandTabState extends State<IslandTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(height: IslandTab.height, child: _tab()),
  );

  Widget _tab() => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: CustomPaint(
        painter: widget.active
            ? IslandTabShape(fill: widget.color, line: Islands.border)
            : null,
        child: Padding(
          // The hover's, inset from the foot.
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: !widget.active && _hovered
                  ? AppColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: widget.child,
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
  IslandTabShape({required this.fill, required this.line, this.overhang = 1});

  final Color fill;
  final Color line;
  final double overhang;

  @override
  void paint(Canvas canvas, Size size) {
    const r = IslandTab.radius;
    const f = IslandTab.flare;
    final w = size.width;
    final h = size.height;
    final outline = Path()
      ..moveTo(-f, h)
      ..arcToPoint(
        Offset(0, h - f),
        radius: const Radius.circular(f),
        clockwise: false,
      )
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
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
      ..lineTo(-f, h + overhang)
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
      old.fill != fill || old.line != line || old.overhang != overhang;
}

/// A segment of a segmented control on a card (a panel's views): the one
/// [selected] raised, outlined; the others the hover's alone.
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
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.selected
                ? themeColors['input.background']
                : _hovered
                ? AppColors.hover
                : Colors.transparent,
            border: Border.all(
              color: widget.selected ? AppColors.border : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}

/// Between two tabs over a card, [width] wide: a short line where neither
/// is in front ([shown]), as a browser's between its tabs behind.
class IslandTabSeparator extends StatelessWidget {
  const IslandTabSeparator({
    super.key,
    required this.shown,
    this.width = 2,
    this.alignment = Alignment.center,
  });

  final bool shown;
  final double width;

  /// Where along the row the tabs' middle is: lower where they are at the
  /// foot of a taller one.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: shown
        ? FractionallySizedBox(
            heightFactor: .4,
            alignment: alignment,
            child: Center(child: Container(width: 1, color: AppColors.border)),
          )
        : null,
  );
}

/// What is under it is on a card of [color] (see [HeadedIsland]): its
/// lists on the card's color rather than the side bar's, its tabs as a
/// browser's ([IslandTab]'s look), its strip on the window's color.
class IslandSurface extends InheritedWidget {
  const IslandSurface({super.key, required this.color, required super.child});

  final Color color;

  /// The card's color, where there is one.
  static Color? colorOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IslandSurface>()?.color;

  @override
  bool updateShouldNotify(IslandSurface old) => old.color != color;
}

/// [child] on a card of [color], all but its first [header] high on the
/// window's color: a part's title or tabs over its card, the tab in front
/// one with the card (an [IslandSurface] under it). The card's outline
/// along the header's last row, which the tab in front covers.
class HeadedIsland extends StatelessWidget {
  const HeadedIsland({
    super.key,
    required this.header,
    required this.color,
    required this.child,
  });

  final double header;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => IslandSurface(
    color: color,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          top: math.max(0.0, header - 1),
          child: Island(color: color, child: const SizedBox.expand()),
        ),
        // Inside the outline, with its corners; the header as it is.
        ClipPath(clipper: _HeadedClip(header), child: child),
      ],
    ),
  );
}

class _HeadedClip extends CustomClipper<Path> {
  _HeadedClip(this.header);

  final double header;

  @override
  Path getClip(Size size) {
    final top = math.max(0.0, header - 1);
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, header))
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(1, top + 1, size.width - 1, size.height - 1),
          const Radius.circular(Islands.radius - 1),
        ),
      );
  }

  @override
  bool shouldReclip(_HeadedClip old) => old.header != header;
}
