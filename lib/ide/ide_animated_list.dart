import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A scrolling list whose rows grow in and shrink out as they come and go
/// between builds, the others moving along with them, instead of jumping:
/// a commit's files opening in the graph, a refresh adding a commit, a file
/// moving to Staged Changes. Rows are told apart by their keys, which every
/// child must have; a row that stays keeps its state.
///
/// The first build and changes to most of the rows at once (a view mode
/// switch) show without moving; so does everything when the platform asks
/// for reduced motion.
class IdeAnimatedList extends StatefulWidget {
  const IdeAnimatedList({
    super.key,
    required this.children,
    this.controller,
    this.duration = const Duration(milliseconds: 150),
  });

  final List<Widget> children;
  final ScrollController? controller;

  /// How long a row takes to grow in or shrink out (the panes' 0.15s).
  final Duration duration;

  @override
  State<IdeAnimatedList> createState() => _IdeAnimatedListState();
}

class _Row {
  _Row(this.key, this.child);

  final Key key;
  Widget child;

  /// Its height's share while it grows in or shrinks out; null at rest.
  AnimationController? animation;
  bool leaving = false;
}

class _IdeAnimatedListState extends State<IdeAnimatedList>
    with TickerProviderStateMixin {
  List<_Row> _rows = [];

  @override
  void initState() {
    super.initState();
    _rows = [for (final child in widget.children) _Row(child.key!, child)];
  }

  @override
  void didUpdateWidget(IdeAnimatedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update(widget.children);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.animation?.dispose();
    }
    super.dispose();
  }

  void _update(List<Widget> children) {
    final previous = {
      for (final (index, row) in _rows.indexed) row.key: (index, row),
    };
    final next = {for (final child in children) child.key!};
    final added = next.where((key) => !previous.containsKey(key)).length;
    final removed = previous.keys.where((key) => !next.contains(key)).length;
    final animate =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        added + removed <= math.max(10, next.length ~/ 3);

    final rows = <_Row>[];
    var old = 0;
    // The rows gone from before [end], where they were.
    void leaveBefore(int end) {
      for (; old < end; old++) {
        final row = _rows[old];
        if (next.contains(row.key)) continue;
        if (animate) {
          if (!row.leaving) _leave(row);
          rows.add(row);
        } else if (row.animation case final animation?) {
          _dispose(animation);
        }
      }
    }

    for (final child in children) {
      final key = child.key!;
      if (previous[key] case (final index, final row)) {
        leaveBefore(index + 1);
        row.child = child;
        if (row.leaving) _enter(row);
        rows.add(row);
      } else {
        final row = _Row(key, child);
        if (animate) _enter(row);
        rows.add(row);
      }
    }
    leaveBefore(_rows.length);
    _rows = rows;
  }

  AnimationController _animation(_Row row, {required double from}) =>
      row.animation ??= AnimationController(
        vsync: this,
        duration: widget.duration,
        value: from,
      );

  void _enter(_Row row) {
    row.leaving = false;
    final animation = _animation(row, from: 0);
    // Not when stopped for another direction: only once it got there.
    animation.forward().then((_) {
      if (!mounted || row.leaving || row.animation != animation) return;
      _rest(row);
    });
  }

  void _leave(_Row row) {
    row.leaving = true;
    final animation = _animation(row, from: 1);
    animation.reverse().then((_) {
      if (!mounted || !row.leaving || row.animation != animation) return;
      setState(() => _rows.remove(row));
      _dispose(animation);
    });
  }

  /// Done moving: shown whole, without its animation.
  void _rest(_Row row) {
    final animation = row.animation;
    if (animation == null) return;
    setState(() => row.animation = null);
    _dispose(animation);
  }

  /// Disposed once the frame no longer listens to it.
  void _dispose(AnimationController animation) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => animation.dispose());

  @override
  Widget build(BuildContext context) {
    final indices = {for (final (index, row) in _rows.indexed) row.key: index};
    return ListView.builder(
      controller: widget.controller,
      padding: EdgeInsets.zero,
      itemCount: _rows.length,
      findChildIndexCallback: (key) => indices[key],
      itemBuilder: (context, index) {
        final row = _rows[index];
        return _AnimatedRow(
          key: row.key,
          animation: row.animation,
          leaving: row.leaving,
          child: row.child,
        );
      },
    );
  }
}

/// A row at its share of its height, clipped, while it moves; the same
/// widgets at rest, so that it keeps its state when it stops.
class _AnimatedRow extends StatelessWidget {
  const _AnimatedRow({
    super.key,
    required this.animation,
    required this.leaving,
    required this.child,
  });

  final Animation<double>? animation;
  final bool leaving;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: animation ?? kAlwaysCompleteAnimation,
    builder: (context, child) {
      final value = Curves.easeOut.transform(animation?.value ?? 1);
      return IgnorePointer(
        ignoring: leaving,
        child: ClipRect(
          clipBehavior: value < 1 ? Clip.hardEdge : Clip.none,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: Opacity(opacity: value, child: child),
          ),
        ),
      );
    },
    child: child,
  );
}
