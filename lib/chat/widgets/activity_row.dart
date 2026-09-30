import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import 'thinking_spark.dart';

/// What the agent is busy with out of sight, after Claude's spark, dots
/// counting up behind it: "Compacting conversation..". [whimsical] (a wait
/// with nothing to name, the model yet to answer), it muses instead, a
/// passing phrase at a time.
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
              child: _Musing(whimsical ? musings : [label], random: random),
            ),
          ],
        ),
      ),
    );
  }
}

/// [phrases], one at a time from any, dots counting up to three behind each,
/// twice; then a terminal's block cursor types the next over it, cell by
/// cell. One phrase only counts its dots. Still where motion is turned down.
class _Musing extends StatefulWidget {
  const _Musing(this.phrases, {this.random});

  final List<String> phrases;
  final math.Random? random;

  @override
  State<_Musing> createState() => _MusingState();
}

class _MusingState extends State<_Musing> with SingleTickerProviderStateMixin {
  /// Up to three dots, from none.
  static const _dots = 4;

  /// How long each count of dots shows.
  static const _dot = Duration(milliseconds: 400);

  /// Times the dots count up behind each phrase.
  static const _rounds = 2;

  /// The cursor's time on a cell.
  static const _cell = Duration(milliseconds: 35);

  /// Cells' worth of time the cursor rests at the end, before it goes.
  static const _rest = 4;

  static const _style = TextStyle(fontSize: 13, color: CursorColors.textMuted);

  late final math.Random _random = widget.random ?? math.Random();
  late int _shown;
  late int _next;
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_advance);

  List<String> get _phrases => widget.phrases;
  bool get _rolls => _phrases.length > 1;

  /// What the cursor types over: the phrase, its dots all out.
  String get _from => '${_phrases[_shown]}${'.' * (_dots - 1)}';
  String get _to => _phrases[_next];

  /// Cells the cursor crosses: the longer text's.
  int get _cells => math.max(_from.length, _to.length);

  Duration get _counting => _dot * (_dots * _rounds);

  /// A phrase's time: its dots, then the cursor's pass to the end (one cell
  /// past its last) and rest there.
  Duration get _cycle =>
      _rolls ? _counting + _cell * (_cells + 1 + _rest) : _counting;

  @override
  void initState() {
    super.initState();
    _pick();
  }

  @override
  void didUpdateWidget(_Musing old) {
    super.didUpdateWidget(old);
    if (listEquals(old.phrases, _phrases)) return;
    _pick();
    if (_controller.isAnimating) _start();
  }

  void _pick() {
    _shown = _random.nextInt(_phrases.length);
    _next = _rolls ? _other(_shown) : _shown;
  }

  int _other(int index) {
    final pick = _random.nextInt(_phrases.length - 1);
    return pick < index ? pick : pick + 1;
  }

  void _start() {
    _controller
      ..duration = _cycle
      ..forward(from: 0);
  }

  void _advance(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_rolls) {
      setState(() {
        _shown = _next;
        _next = _other(_shown);
      });
    }
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _start();
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
      builder: (context, _) {
        final elapsed = _cycle * _controller.value;
        if (elapsed < _counting || !_rolls) {
          final dots = elapsed.inMicroseconds ~/ _dot.inMicroseconds % _dots;
          return Text(
            '${_phrases[_shown]}${'.' * dots}',
            style: _style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
        // Behind the cursor the next phrase, ahead of it what is left of
        // this one, the cell under it hidden.
        final at = math.min(
          (elapsed - _counting).inMicroseconds ~/ _cell.inMicroseconds,
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
          style: _style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
