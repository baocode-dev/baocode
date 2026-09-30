import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import 'markdown_view.dart';
import 'step_header.dart';
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
        padding: const EdgeInsets.only(top: 9, bottom: 3),
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

/// [phrases], one at a time from any: a caret types each out from the
/// start, a letter fading in at a time, unevenly, as a hand would; then dots
/// fade in behind it, up to three, twice; then it fades for the next. One
/// phrase is typed once, then only counts its dots. Still, and whole, where
/// motion is turned down.
///
/// The phrase and its dots are laid out whole from the start, what is yet to
/// show see-through: the line keeps its width, and the caret its places.
class _Musing extends StatefulWidget {
  const _Musing(this.phrases, {this.random});

  final List<String> phrases;
  final math.Random? random;

  @override
  State<_Musing> createState() => _MusingState();
}

class _MusingState extends State<_Musing> with SingleTickerProviderStateMixin {
  // Times in milliseconds.

  /// The caret alone at the start, before the first letter.
  static const _lead = 60;

  /// A letter's time to fade in, and the caret's to glide past it.
  static const _fadeIn = 70;
  static const _glide = 40;

  /// The caret at the end of the phrase: it blinks twice, and is gone.
  static const _blink = 500;
  static const _rest = _blink * 3 ~/ 2;

  /// A dot every step, three to a round, faded out at its end.
  static const _dotStep = 400;
  static const _dotFade = 140;
  static const _round = _dotStep * 4;
  static const _rounds = 2;

  /// The phrase fading for the next.
  static const _clear = 240;

  static const _dots = '...';

  /// The agent's prose's color, at the size of the steps (e.g. Thinking).
  static final _style = TextStyle(
    color: MarkdownView.baseStyle.color,
    fontSize: StepHeader.fontSize,
  );

  late final math.Random _random = widget.random ?? math.Random();
  late int _shown;

  /// When each letter of the phrase is typed; empty once it has been, for a
  /// phrase that stays.
  List<int> _typed = const [];
  bool _still = false;
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_advance);

  List<String> get _phrases => widget.phrases;
  String get _phrase => _phrases[_shown];
  bool get _rolls => _phrases.length > 1;
  bool get _typing => _typed.isNotEmpty;

  /// When the caret is gone and the dots begin.
  int get _dotsAt => _typing ? _typed.last + _glide + _rest : 0;
  int get _clearAt => _dotsAt + _round * _rounds;
  int get _cycle => _clearAt + (_rolls ? _clear : 0);

  @override
  void initState() {
    super.initState();
    _pick(_random.nextInt(_phrases.length));
  }

  @override
  void didUpdateWidget(_Musing old) {
    super.didUpdateWidget(old);
    if (listEquals(old.phrases, _phrases)) return;
    _pick(_random.nextInt(_phrases.length));
    if (_controller.isAnimating) _start();
  }

  /// Shows [index] next, typed out: a letter every 12 to 28ms, a beat longer
  /// after a space.
  void _pick(int index) {
    _shown = index;
    final typed = <int>[];
    var at = _lead;
    for (var i = 0; i < _phrase.length; i++) {
      typed.add(at);
      at += 12 + _random.nextInt(16) + (_phrase[i] == ' ' ? 25 : 0);
    }
    _typed = typed;
  }

  void _start() {
    _controller
      ..duration = Duration(milliseconds: _cycle)
      ..forward(from: 0);
  }

  void _advance(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      if (_rolls) {
        final pick = _random.nextInt(_phrases.length - 1);
        _pick(pick < _shown ? pick : pick + 1);
      } else {
        _typed = const [];
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

  // Where the caret goes after each letter, and its line: laid out again
  // only when the phrase, its style or its room change.
  (String, TextStyle, TextScaler, double)? _laidOutFor;
  List<double> _carets = const [];
  double _baseline = 0;
  double _fontSize = 0;

  void _layOut(String text, TextStyle style, TextScaler scaler, double width) {
    final key = (text, style, scaler, width);
    if (key == _laidOutFor) return;
    _laidOutFor = key;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout(maxWidth: width);
    _carets = [
      for (var i = 0; i <= _phrase.length; i++)
        painter.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx,
    ];
    _baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    _fontSize = scaler.scale(style.fontSize ?? StepHeader.fontSize);
    painter.dispose();
  }

  static double _unit(num value) => value.clamp(0, 1).toDouble();

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(_style);
    if (_still) {
      return Text(
        _phrase,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    final color = style.color ?? CursorColors.text;
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = '$_phrase$_dots';
        _layOut(text, style, scaler, constraints.maxWidth);
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * _cycle;
            final fade = _rolls ? 1 - _unit((t - _clearAt) / _clear) : 1.0;
            // The dots in the round under way; none before, and gone after.
            final round = t - _dotsAt;
            final inRound = round < 0 || round >= _round * _rounds
                ? -1.0
                : round % _round;
            double dot(int k) => inRound < 0
                ? 0
                : _unit((inRound - (k + 1) * _dotStep) / _dotFade) *
                      _unit((_round - inRound) / 100);
            final spans = [
              for (var i = 0; i < _phrase.length; i++)
                TextSpan(
                  text: _phrase[i],
                  style: TextStyle(
                    color: color.withValues(
                      alpha:
                          color.a *
                          fade *
                          (_typing ? _unit((t - _typed[i]) / _fadeIn) : 1),
                    ),
                  ),
                ),
              for (var k = 0; k < _dots.length; k++)
                TextSpan(
                  text: _dots[k],
                  style: TextStyle(
                    color: color.withValues(alpha: color.a * fade * dot(k)),
                  ),
                ),
            ];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Text.rich(
                  TextSpan(children: spans),
                  style: style,
                  textScaler: scaler,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_typing && t < _dotsAt) _caret(t),
              ],
            );
          },
        );
      },
    );
  }

  /// The caret after the last letter typed, gliding on from the one before;
  /// fading in at the start, then steady while it types, then blinking at
  /// its rest. As tall as the letters and centered on them, from the
  /// baseline: the line's box has room below them (and more, falling back
  /// on a font for Han).
  Widget _caret(double t) {
    final last = _typed.lastIndexWhere((at) => at <= t);
    final x = last < 0
        ? _carets.first
        : _carets[last] +
              (_carets[last + 1] - _carets[last]) *
                  Curves.easeOutCubic.transform(
                    _unit((t - _typed[last]) / _glide),
                  );
    // On for half of each blink, its edges soft.
    final resting = t - (_dotsAt - _rest);
    final blink = resting % _blink;
    final opacity =
        _unit(t / 80) *
        (resting < 0
            ? 1
            : blink < _blink / 2
            ? _unit((_blink / 2 - blink) / 60)
            : _unit((blink - (_blink - 60)) / 60));
    final height = _fontSize;
    return Positioned(
      key: const ValueKey('cursor'),
      left: x + 3,
      top: _baseline - _fontSize * 0.35 - height / 2,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 2,
          height: height,
          decoration: BoxDecoration(
            color: _style.color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
