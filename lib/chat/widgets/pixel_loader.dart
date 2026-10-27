import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../base/step_clock.dart';
import '../../theme/app_theme.dart';

/// Something running, as a 3×3 grid of square pixels played frame by
/// frame, in the style Settings → Appearance sets for its [role]: an agent
/// at work ([PixelLoader.agent]), a subagent ([PixelLoader.subagent]). Still
/// where motion is turned down.
class PixelLoader extends StatelessWidget {
  /// An agent at work, or something it started still running: in the
  /// chats' lists, tabs and the like.
  const PixelLoader.agent({super.key, this.size = 14, this.color})
    : role = PixelLoaderRole.agent,
      style = null;

  /// A subagent running: on its card and its row above the composer.
  const PixelLoader.subagent({super.key, this.size = 14, this.color})
    : role = PixelLoaderRole.subagent,
      style = null;

  /// [style] as [role] would play it, whatever is set: a choice's preview.
  const PixelLoader.preview(
    PixelLoaderStyle this.style, {
    super.key,
    required this.role,
    this.size = 14,
    this.color,
  });

  final PixelLoaderRole role;

  /// Null: [role]'s, as set.
  final PixelLoaderStyle? style;

  /// The square it takes; the grid is drawn a little inside it, its pixels
  /// and gaps to half pixels (at 14: pixels of 3, gaps of 2).
  final double size;

  /// [defaultColor] when null.
  final Color? color;

  /// [AppColors.textMuted] with a touch of the theme's accent: a gray that
  /// leans, barely, to the app's own color.
  static Color get defaultColor =>
      Color.lerp(AppColors.textMuted, AppColors.accent, 0.2)!;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([role.style, role.speed]),
    builder: (context, _) => _play(context, style ?? role.style.value),
  );

  Widget _play(BuildContext context, PixelLoaderStyle style) =>
      style == PixelLoaderStyle.circle
      // As it was: a ring three quarters of the square across.
      ? SizedBox.square(
          dimension: size,
          child: Padding(
            padding: EdgeInsets.all(size / 8),
            child: CircularProgressIndicator(
              // Still, as the pixels are, where motion is turned down.
              value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
              strokeWidth: 1.5,
              color: color ?? AppColors.textMuted,
            ),
          ),
        )
      : _PixelAnimation(
          style: style,
          speed: role.speed.value,
          size: size,
          color: color ?? defaultColor,
        );
}

/// What a [PixelLoader] shows, each with its own style and pace
/// (settings.json's [styleKey] and [speedKey]).
enum PixelLoaderRole {
  agent('chat.agentLoadingStyle', 'chat.agentLoadingSpeed', 1.5),
  subagent('chat.subagentLoadingStyle', 'chat.subagentLoadingSpeed', 1.3);

  const PixelLoaderRole(this.styleKey, this.speedKey, this.defaultSpeed);

  final String styleKey;
  final String speedKey;

  /// Unset, how much faster than its [PixelLoaderStyle.frameMs] it plays.
  final double defaultSpeed;

  /// The paces offered, each role's default among them.
  static const speeds = [0.5, 0.8, 1.0, 1.3, 1.5, 2.0, 2.5, 3.0];

  static final _styles = {
    for (final role in values)
      role: ValueNotifier<PixelLoaderStyle>(PixelLoaderStyle.fill),
  };
  static final _speeds = {
    for (final role in values) role: ValueNotifier<double>(role.defaultSpeed),
  };

  /// The style it shows now; main() keeps it to settings.json ([follow]).
  ValueNotifier<PixelLoaderStyle> get style => _styles[this]!;

  /// How much faster than its style's [PixelLoaderStyle.frameMs] it plays
  /// now; main() keeps it to settings.json ([follow]).
  ValueNotifier<double> get speed => _speeds[this]!;

  /// [value] as settings.json has it: the nearest of [speeds]; unset or not
  /// a number, [defaultSpeed].
  double parseSpeed(Object? value) => switch (value) {
    final num speed => speeds.reduce(
      (a, b) => (a - speed).abs() <= (b - speed).abs() ? a : b,
    ),
    _ => defaultSpeed,
  };

  /// [value] as settings.json keeps it; null (not written) for
  /// [defaultSpeed].
  Object? speedSetting(double value) => value == defaultSpeed ? null : value;

  /// Sets each role's [style] and [speed] from [read] now and whenever
  /// [changes] notifies.
  static void follow(Listenable changes, Object? Function(String key) read) {
    void update() {
      for (final role in values) {
        role.style.value = PixelLoaderStyle.parse(read(role.styleKey));
        role.speed.value = role.parseSpeed(read(role.speedKey));
      }
    }

    update();
    changes.addListener(update);
  }
}

/// The animations a [PixelLoader] plays: each frame a 3×3 grid as rows
/// split by `/`, `#` lit, `+` half, `-` faint, `.` empty. Those made to
/// tell of work going on ([forSubagents]) first, then the plainer ones,
/// then the ring there was before ([circle]).
enum PixelLoaderStyle {
  snake(
    [
      '#+-/.../...',
      '+#./.../...',
      '-+#/.../...',
      '.-+/..#/...',
      '..-/.#+/...',
      '.../#+-/...',
      '.../+-./#..',
      '.../-../+#.',
      '.../.../-+#',
      '.../.../.#+',
      '.../.../#+-',
      '.../#../+-.',
      '.../+#./-..',
      '.../-+#/...',
      '..#/.-+/...',
      '.#+/..-/...',
    ],
    100,
    0,
  ),
  stack(
    [
      '.#./.../...',
      '.../.#./...',
      '.../.../.#.',
      '#../.../.+.',
      '.../#../.+.',
      '.../.../++.',
      '..#/.../++.',
      '.../..#/++.',
      '.../.../###',
      '.../.../---',
      '.../.../###',
      '.../.../---',
    ],
    90,
    8,
  ),
  twinkle(
    [
      '.++/.##/-.-',
      '#--/.++/.#.',
      '+../.##/.+.',
      '-../#++/.#.',
      '.#./+--/#+.',
      '.+#/#../+-.',
      '.#+/+.#/-..',
      '.+-/#.+/.#.',
      '.-#/+.-/#+.',
      '#.+/-.#/+-.',
      '+.-/..+/#.#',
      '-##/..-/+.+',
    ],
    110,
    0,
  ),
  fill(
    [
      '#../.../...',
      '+#./.../...',
      '++./..#/...',
      '++./..+/..#',
      '++./..+/#.+',
      '++./..+/+#+',
      '++./#.+/+++',
      '++#/+.+/+++',
      '+++/+#+/+++',
      '###/###/###',
      '###/###/###',
      '-++/+++/+++',
      '.-+/+++/+++',
      '..+/++-/+++',
      '..+/++./++-',
      '..+/++./-+.',
      '..+/++./.-.',
      '..+/-+./...',
      '..-/.+./...',
    ],
    80,
    9,
  ),
  pulse(['.../.#./...', '###/#+#/###', '+++/+-+/+++', '---/-.-/---'], 150, 1),
  ripple(
    ['.../.#./...', '.#./#+#/.#.', '#+#/+-+/#+#', '+-+/-.-/+-+', '-.-/.../-.-'],
    120,
    2,
  ),
  sweep(
    [
      '#+-/+-./-..',
      '+#./#../...',
      '-+#/+#./#..',
      '.-+/-+#/+#.',
      '..-/.-+/-+#',
      '.../..#/.#+',
      '..#/.#+/#+-',
      '.#+/#+-/+-.',
    ],
    100,
    2,
  ),
  rain(
    ['#.+/.-#/.+.', '+.-/#.+/.-#', '-#./+.-/#.+', '.+./-#./+.-', '.-#/.+./-#.'],
    110,
    1,
  ),
  checker(['#.#/.#./#.#', '+-+/-+-/+-+', '.#./#.#/.#.', '-+-/+-+/-+-'], 200, 0),
  spinner(
    [
      '#../+../-..',
      '+#./-../...',
      '-+#/.../...',
      '.-+/..#/...',
      '..-/..+/..#',
      '.../..-/.#+',
      '.../.../#+-',
      '.../#../+-.',
    ],
    80,
    0,
  ),
  twinSpinner(
    [
      '#.-/+.+/-.#',
      '+#./-.-/.#+',
      '-+#/.../#+-',
      '.-+/#.#/+-.',
      '#.-/+.+/-.#',
      '+#./-.-/.#+',
      '-+#/.../#+-',
      '.-+/#.#/+-.',
    ],
    100,
    0,
  ),
  corners(['#../.+./-..', '-.#/.+./...', '..-/.+./..#', '.../.+./#.-'], 150, 0),
  dots(
    [
      '.../+++/...',
      '#../.++/...',
      '.#./+.+/...',
      '..#/++./...',
      '.../+++/...',
      '.../+++/...',
    ],
    100,
    1,
  ),
  equalizer(
    [
      '.#./#+./++#',
      '#../+.#/+#+',
      '..#/.#+/#++',
      '.#./#+#/+++',
      '#../+#./++#',
      '.../..#/##+',
    ],
    120,
    3,
  ),
  bar(['.../#--/...', '.../+#-/...', '.../-+#/...', '.../--+/...'], 120, 1),
  scan(['###/---/...', '---/###/...', '.../---/###', '.../###/---'], 120, 0),
  hourglass(
    [
      '+++/.../...',
      '++./.#./...',
      '++./.../.#.',
      '+../.#./.+.',
      '+../.../#+.',
      '.../.#./++.',
      '.../.../++#',
      '.../.../+++',
      '.../+++/...',
    ],
    100,
    1,
  ),
  breathe(['---/---/---', '+++/+++/+++', '###/###/###', '+++/+++/+++'], 200, 2),

  /// The ring the app turned before the pixels: no frames of its own.
  circle([], 0, 0);

  const PixelLoaderStyle(this.frames, this.frameMs, this.rest);

  final List<String> frames;

  /// How long each frame shows, before [PixelLoaderRole.speed].
  final int frameMs;

  /// The frame shown where motion is turned down: its fullest.
  final int rest;

  /// Unset: [fill], for both roles.
  static PixelLoaderStyle parse(Object? value) =>
      values.where((style) => style.name == value).firstOrNull ?? fill;

  /// As settings.json keeps it; null (not written) for [fill].
  Object? get setting => this == fill ? null : name;

  /// Made to tell of work going on; the rest are plainer.
  static const forSubagents = [
    snake,
    stack,
    twinkle,
    fill,
    pulse,
    ripple,
    sweep,
    rain,
    checker,
  ];

  static const _levels = {'#': 1.0, '+': 0.55, '-': 0.25, '.': 0.0};

  /// [frame]'s pixels, row by row, as how lit they are.
  List<double> alphas(int frame) => [
    for (final ch in frames[frame].replaceAll('/', '').split('')) _levels[ch]!,
  ];
}

class _PixelAnimation extends StatefulWidget {
  const _PixelAnimation({
    required this.style,
    required this.speed,
    required this.size,
    required this.color,
  });

  final PixelLoaderStyle style;
  final double speed;
  final double size;
  final Color color;

  @override
  State<_PixelAnimation> createState() => _PixelAnimationState();
}

class _PixelAnimationState extends State<_PixelAnimation> {
  // Drawn only as its frame changes, not at every vsync.
  late final StepClock _clock = StepClock(_frameTime);

  Duration get _frameTime => Duration(
    microseconds: (widget.style.frameMs * 1000 / widget.speed).round(),
  );

  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = _clock.keepTo(context);
  }

  @override
  void didUpdateWidget(_PixelAnimation old) {
    super.didUpdateWidget(old);
    if (old.style != widget.style || old.speed != widget.speed) {
      _clock.step = _frameTime;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _PixelPainter(
          _clock,
          widget.style,
          widget.color,
          still: _still,
        ),
      ),
    );
  }
}

class _PixelPainter extends CustomPainter {
  _PixelPainter(this.clock, this.style, this.color, {required this.still})
    : super(repaint: clock);

  final StepClock clock;
  final PixelLoaderStyle style;
  final Color color;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final count = style.frames.length;
    final frame = still ? style.rest : clock.ticks % count;
    final side = size.shortestSide;
    // As drawn at 14: pixels of 3, gaps of 2, the grid of 13 in the
    // middle. Each to the nearest half pixel, so as sharp at 2×.
    double half(double value) => (value * 2).round() / 2;
    final cell = math.max(1.0, half(side * 3 / 14));
    final gap = math.max(0.5, half(side * 2 / 14));
    final inset = half((side - 3 * cell - 2 * gap) / 2);
    final origin =
        Offset((size.width - side) / 2, (size.height - side) / 2) +
        Offset(inset, inset);
    final alphas = style.alphas(frame);
    for (var i = 0; i < 9; i++) {
      final alpha = alphas[i];
      if (alpha == 0) continue;
      canvas.drawRect(
        origin + Offset(i % 3 * (cell + gap), i ~/ 3 * (cell + gap)) &
            Size.square(cell),
        Paint()..color = color.withValues(alpha: color.a * alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_PixelPainter old) =>
      old.color != color || old.style != style || old.still != still;
}
