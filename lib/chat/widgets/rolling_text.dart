import 'package:flutter/material.dart';

import '../../base/step_clock.dart';

/// [text] whose digits roll as they change, as an odometer's: the new one
/// up from below, the old one up and away. Its places are counted from
/// its end, where a number's ones are, so a digit gained in front leaves
/// the rest where they were. All at once where motion is turned down.
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  static const duration = Duration(milliseconds: 220);

  /// [text] in runs: each digit alone, what is between them together.
  static List<String> runsOf(String text) {
    final runs = <String>[];
    final other = StringBuffer();
    for (final char in text.characters) {
      if (_isDigit(char)) {
        if (other.isNotEmpty) runs.add(other.toString());
        other.clear();
        runs.add(char);
      } else {
        other.write(char);
      }
    }
    if (other.isNotEmpty) runs.add(other.toString());
    return runs;
  }

  static bool _isDigit(String char) =>
      char.length == 1 &&
      char.codeUnitAt(0) >= 0x30 &&
      char.codeUnitAt(0) <= 0x39;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(text, style: style);
    }
    final runs = runsOf(text);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, run) in runs.indexed)
            KeyedSubtree(
              key: ValueKey(runs.length - index),
              child: _isDigit(run)
                  ? _Digit(run, style: style)
                  : Text(run, style: style),
            ),
        ],
      ),
    );
  }
}

class _Digit extends StatefulWidget {
  const _Digit(this.digit, {required this.style});

  final String digit;
  final TextStyle style;

  @override
  State<_Digit> createState() => _DigitState();
}

class _DigitState extends State<_Digit> {
  // A step each of the shared clock's frames while it rolls, not every
  // vsync: the time rolls on each second, the speed with near each word,
  // and at 144Hz each roll would draw the window 30 times.
  final StepClock _clock = StepClock(StepClock.frame);

  /// The digit going, while it goes; the clock's time it began.
  String? _going;
  Duration _since = Duration.zero;

  /// Each change's own: a digit back before the last has gone out is
  /// another child than that.
  int _change = 0;

  @override
  void initState() {
    super.initState();
    _clock.addListener(_tick);
  }

  @override
  void didUpdateWidget(_Digit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.digit == oldWidget.digit) return;
    _change++;
    _going = oldWidget.digit;
    // Not where tickers are off: at once.
    if (_clock.keepTo(context) || !_clock.isRunning) {
      _going = null;
      return;
    }
    _since = _clock.time;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Its tickers turned off as it rolls: done at once.
    if (_going != null && (_clock.keepTo(context) || !_clock.isRunning)) {
      _clock.stop();
      _going = null;
    }
  }

  double get _rolled =>
      ((_clock.time - _since).inMicroseconds /
              RollingText.duration.inMicroseconds)
          .clamp(0.0, 1.0);

  void _tick() {
    if (_rolled < 1) {
      setState(() {});
      return;
    }
    _clock.stop();
    setState(() => _going = null);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  /// [digit] at [shown] of the way in: up from below as it comes, up and
  /// away as it goes.
  Widget _at(String digit, double shown, {required bool coming, Key? key}) =>
      Opacity(
        key: key,
        opacity: shown,
        child: FractionalTranslation(
          translation: Offset(0, (coming ? 0.8 : -0.8) * (1 - shown)),
          child: Text(digit, style: widget.style),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final going = _going;
    final key = ValueKey(_change);
    if (going == null) {
      return ClipRect(
        child: Text(widget.digit, key: key, style: widget.style),
      );
    }
    final rolled = _rolled;
    return ClipRect(
      child: Stack(
        alignment: Alignment.center,
        children: [
          _at(
            going,
            Curves.easeInCubic.transform(1 - rolled),
            coming: false,
            key: ValueKey(_change - 1),
          ),
          _at(
            widget.digit,
            Curves.easeOutCubic.transform(rolled),
            coming: true,
            key: key,
          ),
        ],
      ),
    );
  }
}
