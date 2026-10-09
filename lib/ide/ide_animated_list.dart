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
///
/// [IdeAnimatedList.builder] builds only the rows shown, as they scroll in:
/// a list of thousands of rows costs its keys. With an [itemExtent], where
/// a row is is worked out rather than laid out: a jump to the middle of
/// thousands (a dragged scrollbar) builds the rows there alone.
class IdeAnimatedList extends StatefulWidget {
  IdeAnimatedList({
    super.key,
    required List<Widget> children,
    this.controller,
    this.duration = const Duration(milliseconds: 150),
  }) : keys = [for (final child in children) child.key!],
       itemBuilder = ((context, index) => children[index]),
       header = null,
       itemExtent = null;

  /// The rows of [keys], [itemBuilder] building the one at an index when
  /// it shows; under [header], if any, which scrolls with them.
  const IdeAnimatedList.builder({
    super.key,
    required this.keys,
    required this.itemBuilder,
    this.header,
    this.itemExtent,
    this.controller,
    this.duration = const Duration(milliseconds: 150),
  });

  final List<Key> keys;
  final IndexedWidgetBuilder itemBuilder;

  /// Above the rows, of its own height, not animated.
  final Widget? header;

  /// Every row's height (at rest), if they all have the same.
  final double? itemExtent;
  final ScrollController? controller;

  /// How long a row takes to grow in or shrink out (the panes' 0.15s).
  final Duration duration;

  @override
  State<IdeAnimatedList> createState() => _IdeAnimatedListState();
}

class _Row {
  _Row(this.key, this.builder, this.index);

  final Key key;

  /// What builds it: the list's builder at its index there (the last one it
  /// was in, for a row leaving).
  IndexedWidgetBuilder builder;
  int index;

  /// Its height's share while it grows in or shrinks out; null at rest.
  AnimationController? animation;
  bool leaving = false;
}

class _IdeAnimatedListState extends State<IdeAnimatedList>
    with TickerProviderStateMixin {
  List<_Row> _rows = [];

  /// The rows' indices by key; null when they changed.
  Map<Key, int>? _indices;

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final (index, key) in widget.keys.indexed)
        _Row(key, widget.itemBuilder, index),
    ];
  }

  @override
  void didUpdateWidget(IdeAnimatedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update(widget.keys, widget.itemBuilder);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.animation?.dispose();
    }
    super.dispose();
  }

  /// Whether [keys] are the rows', in their order, none of them moving: what
  /// most builds are (a selection, a hover), told in one pass.
  bool _same(List<Key> keys) {
    if (keys.length != _rows.length) return false;
    for (var i = 0; i < keys.length; i++) {
      final row = _rows[i];
      if (row.animation != null || keys[i] != row.key) return false;
    }
    return true;
  }

  void _update(List<Key> keys, IndexedWidgetBuilder builder) {
    if (_same(keys)) {
      for (final row in _rows) {
        row.builder = builder;
      }
      return;
    }
    _indices = null;
    final previous = {
      for (final (index, row) in _rows.indexed) row.key: (index, row),
    };
    final next = keys.toSet();
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

    for (final (index, key) in keys.indexed) {
      if (previous[key] case (final at, final row)) {
        leaveBefore(at + 1);
        row
          ..builder = builder
          ..index = index;
        if (row.leaving) _enter(row);
        rows.add(row);
      } else {
        final row = _Row(key, builder, index);
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
      setState(() {
        _rows.remove(row);
        _indices = null;
      });
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

  /// The rows at [extent] each (their share of it while they move), under
  /// the header.
  Widget _fixedExtent(
    BuildContext context,
    double extent,
    Map<Key, int> indices,
  ) {
    Widget rows(BuildContext context) => SliverVariedExtentList(
      itemExtentBuilder: (index, _) {
        if (index >= _rows.length) return null;
        final animation = _rows[index].animation;
        return animation == null
            ? extent
            : extent * Curves.easeOut.transform(animation.value);
      },
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final row = _rows[index];
          return _AnimatedRow(
            key: row.key,
            animation: row.animation,
            leaving: row.leaving,
            child: row.builder(context, row.index),
          );
        },
        childCount: _rows.length,
        findChildIndexCallback: (key) => indices[key],
      ),
    );
    final moving = [for (final row in _rows) ?row.animation];
    return CustomScrollView(
      controller: widget.controller,
      slivers: [
        if (widget.header case final header?) SliverToBoxAdapter(child: header),
        // Laid out again as rows grow and shrink: their heights are its.
        if (moving.isEmpty)
          rows(context)
        else
          ListenableBuilder(
            listenable: Listenable.merge(moving),
            builder: (context, _) => rows(context),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final indices = _indices ??= {
      for (final (index, row) in _rows.indexed) row.key: index,
    };
    if (widget.itemExtent case final extent?) {
      return _fixedExtent(context, extent, indices);
    }
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
          child: row.builder(context, row.index),
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
