import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../chat_models.dart';
import 'markdown_view.dart';
import 'step_header.dart';
import 'thinking_spark.dart';
import 'turn_footer.dart';

/// What the agent is busy with out of sight, after Claude's spark: typed
/// out, then dots counting up behind it ("Compacting conversation..").
/// [whimsical] (a wait with nothing to name, the model yet to answer), it
/// muses instead, a passing phrase at a time: mostly on the step just done,
/// if [cue] says what that was, else on anything.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.label,
    this.whimsical = false,
    this.visible = true,
    this.output,
    this.cue,
    this.random,
  });

  final String label;
  final bool whimsical;

  /// Whether it shows: it opens and fades in, or folds and fades out.
  final bool visible;

  /// What the model has written so far: under it, shown or not.
  final TurnOutput? output;

  /// The step just done, to muse on.
  final MusingCue? cue;

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
    'Binding the monad',
    'Asking the oracle',
    'Stirring the pot',
    'Polishing the plan',
  ];

  /// [musings] in [l10n]'s language.
  static List<String> musingsFor(AppLocalizations l10n) =>
      l10n.activityMusings.split('\n');

  /// What it muses on [cue], in [l10n]'s language.
  static List<String> cuedMusingsFor(MusingCue cue, AppLocalizations l10n) {
    final name = cue.name;
    return switch (cue.topic) {
      MusingTopic.command => l10n.activityMusingsCommand(name),
      MusingTopic.commandFailed => l10n.activityMusingsCommandFailed(name),
      MusingTopic.read => l10n.activityMusingsRead(name),
      MusingTopic.edit => l10n.activityMusingsEdit(name),
      MusingTopic.search => l10n.activityMusingsSearch(name),
      MusingTopic.folder => l10n.activityMusingsFolder(name),
      MusingTopic.web => l10n.activityMusingsWeb(name),
      MusingTopic.agent => l10n.activityMusingsAgent(name),
      MusingTopic.mcp => l10n.activityMusingsMcp(name),
      MusingTopic.browser => l10n.activityMusingsBrowser,
      MusingTopic.image => l10n.activityMusingsImage,
      MusingTopic.denied => l10n.activityMusingsDenied,
    }.split('\n');
  }

  @override
  Widget build(BuildContext context) {
    final output = this.output;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Reveal(visible: visible, child: _row(context.l10n)),
        if (output != null && output.tokens > 0) LiveTurnStats(output: output),
      ],
    );
  }

  Widget _row(AppLocalizations l10n) {
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
              child: _Musing(
                whimsical
                    ? musingsFor(l10n)
                    : [localizedActivityLabel(label, l10n)],
                cued: switch (cue) {
                  final cue? when whimsical => cuedMusingsFor(cue, l10n),
                  _ => const [],
                },
                // Folding away, it goes on as it was.
                frozen: !visible,
                random: random,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child] opening and fading in while [visible], folding and fading out
/// while not; not built at all once folded, so it begins anew each time it
/// shows. At once where motion is turned down.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(_Reveal old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _follow();
  }

  void _follow() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
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
      builder: (context, child) => _controller.isDismissed
          ? const SizedBox(width: double.infinity)
          : SizeTransition(
              sizeFactor: _eased,
              alignment: Alignment.topLeft,
              child: FadeTransition(opacity: _eased, child: child),
            ),
      child: widget.child,
    );
  }
}

/// [phrases], one at a time from any (or from [cued], [cuedShare] of the
/// time, when there are any): a caret types each out from the
/// start, a letter fading in at a time, unevenly, as a hand would; then dots
/// fade in behind it, up to three, twice; then it fades for the next. One
/// phrase is typed once, then only counts its dots. Still, and whole, where
/// motion is turned down.
///
/// The phrase and its dots are laid out whole from the start, what is yet to
/// show see-through: the line keeps its width, and the caret its places.
class _Musing extends StatefulWidget {
  const _Musing(
    this.phrases, {
    this.cued = const [],
    this.frozen = false,
    this.random,
  });

  final List<String> phrases;

  /// Phrases on the step just done.
  final List<String> cued;

  /// Whether it keeps to the phrases it has, whatever it is given.
  final bool frozen;

  final math.Random? random;

  /// How often it picks from [cued].
  static const cuedShare = 0.7;

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
  static TextStyle get _style => TextStyle(
    color: MarkdownView.baseStyle.color,
    fontSize: StepHeader.fontSize,
  );

  late final math.Random _random = widget.random ?? math.Random();
  late List<String> _phrases = widget.phrases;
  late List<String> _cued = widget.cued;
  late String _phrase;

  /// When each letter of the phrase is typed; empty once it has been, for a
  /// phrase that stays.
  List<int> _typed = const [];
  bool _still = false;
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_advance);

  bool get _rolls => _phrases.length + _cued.length > 1;
  bool get _typing => _typed.isNotEmpty;

  /// When the caret is gone and the dots begin.
  int get _dotsAt => _typing ? _typed.last + _glide + _rest : 0;
  int get _clearAt => _dotsAt + _round * _rounds;
  int get _cycle => _clearAt + (_rolls ? _clear : 0);

  @override
  void initState() {
    super.initState();
    _pick(_draw());
  }

  @override
  void didUpdateWidget(_Musing old) {
    super.didUpdateWidget(old);
    if (widget.frozen ||
        (listEquals(widget.phrases, _phrases) &&
            listEquals(widget.cued, _cued))) {
      return;
    }
    _phrases = widget.phrases;
    _cued = widget.cued;
    // Said on to its end while it still holds.
    if (_phrases.contains(_phrase) || _cued.contains(_phrase)) return;
    _pick(_draw());
    if (_controller.isAnimating) _start();
  }

  /// A phrase to say: from [_Musing.cued] as often as it says, if any; not
  /// [not] where there are others.
  String _draw({String? not}) {
    final from = _cued.isNotEmpty && _random.nextDouble() < _Musing.cuedShare
        ? _cued
        : _phrases;
    final avoid = not == null ? -1 : from.indexOf(not);
    if (avoid < 0 || from.length < 2) return from[_random.nextInt(from.length)];
    final pick = _random.nextInt(from.length - 1);
    return from[pick < avoid ? pick : pick + 1];
  }

  /// Shows [phrase] next, typed out: a letter every 12 to 28ms, a beat
  /// longer after a space.
  void _pick(String phrase) {
    _phrase = phrase;
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
        _pick(_draw(not: _phrase));
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
    final color = style.color ?? AppColors.text;
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

/// A session's activity label (chat_session.dart names them in English) in
/// [l10n]'s language; others as given.
String localizedActivityLabel(String label, AppLocalizations l10n) =>
    switch (label) {
      'Compacting conversation' => l10n.activityCompacting,
      'Planning next move' => l10n.activityPlanning,
      _ => label,
    };
