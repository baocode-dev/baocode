import 'package:flutter/widgets.dart';

/// How the popups under it come and go: still, as VS Code's (the IDE's,
/// by default), or [lively]: dialogs and menus grow in from a little
/// smaller, fading, and fade out (the stash's panel).
class IdeMotion extends InheritedWidget {
  const IdeMotion({super.key, required this.lively, required super.child});

  final bool lively;

  static bool livelyOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IdeMotion>()?.lively ?? false;

  /// A dialog's or a menu's coming in: [animation] from 0 to 1.
  static Widget enter(
    Animation<double> animation,
    Widget child, {
    Alignment alignment = Alignment.center,
    double from = 0.96,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        alignment: alignment,
        scale: Tween(begin: from, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }

  static const enterDuration = Duration(milliseconds: 180);
  static const exitDuration = Duration(milliseconds: 110);

  @override
  bool updateShouldNotify(IdeMotion oldWidget) => lively != oldWidget.lively;
}

/// [child] while there is one, and fading out once it is gone (null): the
/// last one kept meanwhile, taking no presses. A floating bar's going, as
/// [PopIn] is its coming; back before it is gone, it fades in again from
/// where it was, and once gone, it comes in anew.
class FadeAway extends StatefulWidget {
  const FadeAway({
    super.key,
    this.child,
    this.duration = const Duration(milliseconds: 120),
  });

  final Widget? child;
  final Duration duration;

  @override
  State<FadeAway> createState() => _FadeAwayState();
}

class _FadeAwayState extends State<FadeAway>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  )..addStatusListener(_statusChanged);

  /// What shows: [FadeAway.child], or the last one while it fades out.
  late Widget? _last = widget.child;

  @override
  void didUpdateWidget(FadeAway oldWidget) {
    super.didUpdateWidget(oldWidget);
    _shown.duration = widget.duration;
    if (widget.child case final child?) {
      if (_last == null) {
        _shown.value = 1;
      } else if (_shown.value < 1) {
        _shown.forward();
      }
      _last = child;
    } else if (_last != null && _shown.status != AnimationStatus.reverse) {
      _shown.reverse();
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && widget.child == null) {
      setState(() => _last = null);
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _last;
    if (child == null) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: widget.child == null,
      child: FadeTransition(opacity: _shown, child: child),
    );
  }
}

/// [child] coming in as it is first built: fading, from a little smaller
/// and a few pixels [offset] off, settling where it is. A floating bar's
/// or menu's showing; keyed anew, it comes in again.
class PopIn extends StatelessWidget {
  const PopIn({
    super.key,
    required this.child,
    this.alignment = Alignment.bottomCenter,
    this.offset = const Offset(0, 4),
    this.duration = const Duration(milliseconds: 160),
  });

  final Widget child;

  /// Where it grows from.
  final Alignment alignment;
  final Offset offset;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: duration,
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, t, child) => Opacity(
      opacity: t.clamp(0, 1),
      child: Transform.translate(
        offset: offset * (1 - t),
        child: Transform.scale(
          alignment: alignment,
          scale: 0.96 + 0.04 * t,
          child: child,
        ),
      ),
    ),
  );
}
