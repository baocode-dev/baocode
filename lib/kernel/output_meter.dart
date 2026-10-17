import '../chat/chat_models.dart';

/// Meters what a turn's model writes as it streams: how much so far, how
/// fast it writes now, and how fast it wrote on average.
///
/// Its tokens are known as each message ends; until then they are guessed
/// from the text, and the guess is kept in line with the counts of the
/// messages before.
///
/// The speed is the tokens of the last [window] over the time they took,
/// within a message. Not the first of its deltas: the upstream holds back
/// what the model writes until it sends anything (a tool call's input, a
/// thought), and those tokens came out of no time we see. Nor before it
/// has written for [warmUp]: a message as short as that says nothing of the
/// pace. Thoughts do not count, their text being but a summary, if any.
class OutputMeter {
  OutputMeter({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  static const window = Duration(seconds: 2);
  static const warmUp = Duration(seconds: 1);

  /// Deltas closer than this came together: one burst.
  static const _burst = Duration(milliseconds: 50);

  /// Tokens [text] is likely to be: a third of its ASCII characters, and
  /// more than one each for the others (Han, mostly), as Claude's tokenizer
  /// cuts them.
  static double estimateTokens(String text) {
    var ascii = 0;
    var other = 0;
    for (final rune in text.runes) {
      rune < 0x80 ? ascii++ : other++;
    }
    return ascii / 3 + other * 1.3;
  }

  /// Tokens of the messages ended, as counted.
  int _counted = 0;

  /// The message under way's, guessed: all of it, and what is timed.
  double _guessed = 0;
  double _timed = 0;

  /// The counts of the timed tokens to their guesses, the turn so far.
  double _countedTimed = 0;
  double _guessedTimed = 0;

  /// When the message's timed tokens came, and how many by then; the
  /// first is the latest before [window], or the message's first.
  final List<(DateTime, double)> _samples = [];

  /// The speed now, and since when, while there is one.
  double? _speed;
  DateTime? _speedSince;

  /// The speeds shown, each by how long, for the average.
  double _speedSum = 0;
  Duration _speedTime = Duration.zero;
  double? _lastSpeed;

  /// The guess's correction: counted over guessed, within reason.
  double get _ratio => _guessedTimed < 50
      ? 1
      : (_countedTimed / _guessedTimed).clamp(0.5, 2).toDouble();

  /// A turn begins: nothing written yet.
  void begin() {
    _startMessage();
    _counted = 0;
    _countedTimed = _guessedTimed = 0;
    _speedSum = 0;
    _speedTime = Duration.zero;
    _lastSpeed = null;
  }

  /// A message begins (any it did not end gave way).
  void startMessage() => _startMessage();

  void _startMessage() {
    _stopSpeed();
    _guessed = _timed = 0;
    _samples.clear();
  }

  /// [text] came, of the text or a tool call's input; or, not [timed], of a
  /// thought.
  void streamed(String text, {bool timed = true}) {
    final tokens = estimateTokens(text);
    _guessed += tokens;
    if (!timed || tokens == 0) return;
    _timed += tokens;
    final now = _clock();
    if (_samples case [..., (final at, _)] when now.difference(at) < _burst) {
      _samples.last = (at, _timed);
    } else {
      _samples.add((now, _timed));
    }
    while (_samples.length > 1 && now.difference(_samples[1].$1) >= window) {
      _samples.removeAt(0);
    }
    final (from, before) = _samples.first;
    final (to, after) = _samples.last;
    final span = to.difference(from);
    _setSpeed(
      span < warmUp
          ? null
          : (after - before) * _ratio / (span.inMicroseconds / 1e6),
      now,
    );
  }

  void _setSpeed(double? speed, DateTime now) {
    if ((_speed, _speedSince) case (final shown?, final since?)
        when now.isAfter(since)) {
      final time = now.difference(since);
      _speedSum += shown * (time.inMicroseconds / 1e6);
      _speedTime += time;
    }
    _speed = speed;
    _speedSince = speed == null ? null : now;
    if (speed != null) _lastSpeed = speed;
  }

  /// No speed from here: the last held until the last delta, not since.
  void _stopSpeed() {
    if (_speed == null) return;
    _setSpeed(null, _samples.lastOrNull?.$1 ?? _clock());
  }

  /// The message ended, having written [tokens] in all as counted (null:
  /// not counted), [written] of them its text and tool calls (null: not
  /// told apart from its thoughts).
  void endMessage({int? tokens, int? written}) {
    _counted += tokens ?? (_guessed * _ratio).round();
    if (written != null && _timed > 0) {
      _countedTimed += written;
      _guessedTimed += _timed;
    }
    _startMessage();
  }

  /// What is written so far, and how fast now.
  TurnOutput get output => TurnOutput(
    tokens: _counted + (_guessed * _ratio).round(),
    tokensPerSecond: _speed,
  );

  /// The speed shown, on average over the time it was; null if it never
  /// was.
  double? get averageSpeed => _speedTime > Duration.zero
      ? _speedSum / (_speedTime.inMicroseconds / 1e6)
      : _lastSpeed;
}
