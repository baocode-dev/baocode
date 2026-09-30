import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import 'shimmer_text.dart';
import 'thinking_spark.dart';

/// What the agent is busy with out of sight, after Claude's spark:
/// "Compacting conversation". [whimsical] (a wait with nothing to name, the
/// model yet to answer), it muses instead, a passing phrase at a time.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.label,
    this.whimsical = false,
    this.random,
  });

  final String label;
  final bool whimsical;

  /// Picks the phrases; tests seed it.
  final math.Random? random;

  /// What it muses, in no order.
  static const musings = [
    'Pondering',
    'Noodling',
    'Percolating',
    'Cogitating',
    'Simmering',
    'Marinating',
    'Tinkering',
    'Grokking',
    'Mulling it over',
    'Connecting the dots',
    'Chasing a hunch',
    'Brewing a plan',
    'Hatching a plan',
    'Weighing the options',
    'Untangling threads',
    'Herding tokens',
    'Summoning context',
    'Reticulating splines',
    'Asking the rubber duck',
    'Reading the tea leaves',
    'Sketching on a napkin',
    'Doodling in the margins',
    'Squinting at the diff',
    'Counting parentheses',
    'Befriending the compiler',
    'Negotiating with types',
    'Wrangling edge cases',
    'Tracing the stack',
    'Flipping through the docs',
    'Spelunking the codebase',
    'Lining up the ducks',
    'Shaking the magic 8-ball',
    'Warming up the neurons',
    'Folding thoughts',
    'Tuning the vibes',
    'Binding the monad',
    'Lifting into the monad',
    'Asking the oracle',
    'Stirring the pot',
    'Polishing the plan',
  ];

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      // Lined up with the steps around it.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SelectionContainer.disabled(child: ThinkingSpark()),
            const SizedBox(width: 6),
            Flexible(
              child: whimsical
                  ? _Musing(random: random)
                  : ShimmerText(
                      label,
                      ellipsis: false,
                      padding: EdgeInsets.zero,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [ActivityRow.musings], one at a time from any: each swept twice by the
/// shimmer, then typed over, cell by cell, by a terminal's block cursor with
/// the next. Still where motion is turned down.
class _Musing extends StatefulWidget {
  const _Musing({this.random});

  final math.Random? random;

  @override
  State<_Musing> createState() => _MusingState();
}

class _MusingState extends State<_Musing> with SingleTickerProviderStateMixin {
  /// Sweeps of the shimmer over each phrase.
  static const _sweeps = 2;

  /// The cursor's time on a cell.
  static const _cell = Duration(milliseconds: 35);

  /// Cells' worth of time the cursor rests at the end, before it goes.
  static const _rest = 4;

  static const _style = TextStyle(fontSize: 13);

  late final math.Random _random = widget.random ?? math.Random();
  late int _shown = _random.nextInt(ActivityRow.musings.length);
  late int _next = _other(_shown);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  )..addStatusListener(_advance);

  String get _from => ActivityRow.musings[_shown];
  String get _to => ActivityRow.musings[_next];

  /// Cells the cursor crosses: the longer phrase's.
  int get _cells => math.max(_from.length, _to.length);

  Duration get _sweeping => ShimmerText.period * _sweeps;

  /// A phrase's time: its sweeps, then the cursor's pass to the end (one
  /// cell past its last) and rest there.
  Duration get _cycle => _sweeping + _cell * (_cells + 1 + _rest);

  int _other(int index) {
    final pick = _random.nextInt(ActivityRow.musings.length - 1);
    return pick < index ? pick : pick + 1;
  }

  void _advance(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      _shown = _next;
      _next = _other(_shown);
    });
    _controller
      ..duration = _cycle
      ..forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.reset();
    } else if (!_controller.isAnimating) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, shown) {
        final elapsed = _cycle * _controller.value;
        if (elapsed < _sweeping) {
          const period = ShimmerText.period;
          final sweep =
              elapsed.inMicroseconds %
              period.inMicroseconds /
              period.inMicroseconds;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => shimmerShader(bounds, sweep),
            child: shown,
          );
        }
        // Behind the cursor the next phrase, ahead of it what is left of
        // this one, the cell under it hidden.
        final at = math.min(
          (elapsed - _sweeping).inMicroseconds ~/ _cell.inMicroseconds,
          _cells,
        );
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: _to.substring(0, math.min(at, _to.length))),
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(
                  key: ValueKey('cursor'),
                  width: 7,
                  height: 14,
                  child: ColoredBox(color: CursorColors.textMuted),
                ),
              ),
              TextSpan(text: _from.substring(math.min(at + 1, _from.length))),
            ],
          ),
          style: _style.copyWith(color: CursorColors.textFaint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
      child: Text(
        _from,
        style: _style.copyWith(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
