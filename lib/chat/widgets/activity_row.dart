import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import 'markdown_view.dart';
import 'thinking_spark.dart';

/// What the agent is busy with out of sight, after Claude's spark: typed
/// out, then dots counting up behind it ("Compacting conversation..").
/// [whimsical] (a wait with nothing to name, the model yet to answer), it
/// muses instead, a passing phrase at a time.
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
            const SelectionContainer.disabled(child: ThinkingSpark(size: 15)),
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

/// [phrases], one at a time from any: a terminal's block cursor types each
/// out from the start, then dots count up to three behind it, twice, and it
/// clears for the next. One phrase is typed once, then only counts its dots.
/// Still, and whole, where motion is turned down.
class _Musing extends StatefulWidget {
  const _Musing(this.phrases, {this.random});

  final List<String> phrases;
  final math.Random? random;

  @override
  State<_Musing> createState() => _MusingState();
}

class _MusingState extends State<_Musing> with SingleTickerProviderStateMixin {
  /// The cursor's time on a letter.
  static const _key = Duration(milliseconds: 45);

  /// Letters' worth of time the cursor rests at the end, before it goes.
  static const _rest = 6;

  /// Up to three dots, from none.
  static const _dots = 4;

  /// How long each count of dots shows.
  static const _dot = Duration(milliseconds: 400);

  /// Times the dots count up behind each phrase.
  static const _rounds = 2;

  /// As the agent's prose reads.
  static final _style = TextStyle(
    color: MarkdownView.baseStyle.color,
    fontSize: MarkdownView.baseStyle.fontSize,
  );

  late final math.Random _random = widget.random ?? math.Random();
  late int _shown;

  /// Whether [_shown] is yet to be typed out.
  bool _typing = true;
  bool _still = false;
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_advance);

  List<String> get _phrases => widget.phrases;
  String get _phrase => _phrases[_shown];

  /// Typing the phrase: a letter at a time, then one past its last, and
  /// rest there.
  Duration get _typingTime =>
      _typing ? _key * (_phrase.length + 1 + _rest) : Duration.zero;

  Duration get _cycle => _typingTime + _dot * (_dots * _rounds);

  @override
  void initState() {
    super.initState();
    _shown = _random.nextInt(_phrases.length);
  }

  @override
  void didUpdateWidget(_Musing old) {
    super.didUpdateWidget(old);
    if (listEquals(old.phrases, _phrases)) return;
    _shown = _random.nextInt(_phrases.length);
    _typing = true;
    if (_controller.isAnimating) _start();
  }

  void _start() {
    _controller
      ..duration = _cycle
      ..forward(from: 0);
  }

  void _advance(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      _typing = _phrases.length > 1;
      if (_typing) {
        final pick = _random.nextInt(_phrases.length - 1);
        _shown = pick < _shown ? pick : pick + 1;
      }
    });
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _controller.stop();
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
    if (_still) return _text(_phrase);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed = _cycle * _controller.value;
        final typing = _typingTime;
        if (elapsed >= typing) {
          final dots =
              (elapsed - typing).inMicroseconds ~/ _dot.inMicroseconds % _dots;
          return _text('$_phrase${'.' * dots}');
        }
        final typed = math.min(
          elapsed.inMicroseconds ~/ _key.inMicroseconds,
          _phrase.length,
        );
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: _phrase.substring(0, typed)),
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(
                  key: ValueKey('cursor'),
                  width: 7.5,
                  height: 15,
                  child: ColoredBox(color: CursorColors.text),
                ),
              ),
            ],
          ),
          style: _style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  Widget _text(String text) =>
      Text(text, style: _style, maxLines: 1, overflow: TextOverflow.ellipsis);
}
