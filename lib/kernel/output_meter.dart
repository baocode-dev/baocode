import '../chat/chat_models.dart';

/// Meters what a turn's model writes as it streams: how much so far, how
/// fast it writes now (as last sampled), and how fast it wrote on average.
///
/// Its tokens are known as each message ends; until then they are guessed
/// from the text, and the guess is kept in line with the counts of the
/// messages before.
///
/// The speed is the tokens of the last [window] of writing over the time
/// they took, on a clock that runs only while a message writes: from the
/// start of its first block of text or tool call ([startBlock]; else its
/// first delta) to its last delta, the turn's messages one after another,
/// the waits between them (a tool running, a request) left out. A turn of
/// short messages, a line and a tool call each, is timed all the same; so
/// is a tool call whose input comes all at once as it ends, as BaoCode's
/// proxy sends an OpenAI upstream's. Not the deltas that came with that
/// start: the upstream holds back what the model writes until it sends
/// anything (a tool call's input, a thought), and those tokens came out of
/// no time we see. Nor before it has written for
/// [warmUp] in all: as short as that says nothing of the pace. Thoughts do
/// not count, their text being but a summary, if any.
class OutputMeter {
  OutputMeter({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  static const window = Duration(seconds: 2);
  static const warmUp = Duration(seconds: 1);

  /// Deltas this close to a message's first came with it: what the
  /// upstream held back.
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

  /// The time written, on the clock that runs only while a message writes:
  /// of the messages ended.
  Duration _written = Duration.zero;

  /// When the message under way began to write, and its last delta,
  /// while it has.
  DateTime? _first;
  DateTime? _last;

  /// The tokens timed, the turn so far, the bursts left out.
  double _sampled = 0;

  /// When, on that clock, the timed tokens came, and how many by then; the
  /// first is the latest before [window], or the turn's first.
  final List<(Duration, double)> _samples = [];

  /// The speed as last sampled; none before [warmUp].
  double? _speed;

  /// Active writing clock and non-burst tokens across *all* streamed deltas
  /// (including thoughts), for [estimatedSpeed] before [_speed] is sampled.
  DateTime? _turnStartedAt;
  Duration _anyWritten = Duration.zero;
  DateTime? _anyFirst;
  DateTime? _anyLast;
  double _anySampled = 0;

  /// Minimum active streaming span before estimating from active pace.
  static const _estimateWarmUp = Duration(milliseconds: 300);

  /// The guess's correction: counted over guessed, within reason.
  double get _ratio => _guessedTimed < 50
      ? 1
      : (_countedTimed / _guessedTimed).clamp(0.5, 2).toDouble();

  /// A turn begins: nothing written yet.
  void begin() {
    _startMessage();
    _samples.clear();
    _written = Duration.zero;
    _sampled = 0;
    _counted = 0;
    _countedTimed = _guessedTimed = 0;
    _speed = null;
    _turnStartedAt = _clock();
    _anyWritten = Duration.zero;
    _anyFirst = _anyLast = null;
    _anySampled = 0;
  }

  /// A message begins (any it did not end gave way).
  void startMessage() => _startMessage();

  /// A block of text or a tool call begins: the message writes from here,
  /// whenever its deltas come.
  void startBlock() {
    if (_first != null) return;
    _first = _last = _clock();
    _sample(_written);
  }

  void _startMessage() {
    if ((_first, _last) case (final first?, final last?)) {
      _written += last.difference(first);
    }
    _first = _last = null;
    if ((_anyFirst, _anyLast) case (final first?, final last?)) {
      _anyWritten += last.difference(first);
    }
    _anyFirst = _anyLast = null;
    _guessed = _timed = 0;
  }

  /// [text] came, of the text or a tool call's input; or, not [timed], of a
  /// thought.
  void streamed(String text, {bool timed = true}) {
    final tokens = estimateTokens(text);
    _guessed += tokens;
    if (tokens == 0) return;
    final now = _clock();
    final anyFirst = _anyFirst ??= now;
    _anyLast = now;
    if (now.difference(anyFirst) >= _burst) _anySampled += tokens;
    if (!timed) return;
    _timed += tokens;
    final first = _first ??= now;
    _last = now;
    final at = _written + now.difference(first);
    // Within [_burst] of its start: of what was held back. Only there:
    // deltas as close all along are the model writing fast.
    if (now.difference(first) >= _burst) _sampled += tokens;
    _sample(at);
    while (_samples.length > 1 && at - _samples[1].$1 >= window) {
      _samples.removeAt(0);
    }
    final (from, before) = _samples.first;
    final (to, after) = _samples.last;
    final span = to - from;
    if (span >= warmUp) _speed = (after - before) * _ratio / _seconds(span);
  }

  /// The tokens timed by [at], on the clock that runs while it writes.
  void _sample(Duration at) {
    if (_samples.lastOrNull case (final last, _) when last == at) {
      _samples.last = (at, _sampled);
    } else {
      _samples.add((at, _sampled));
    }
  }

  static double _seconds(Duration time) => time.inMicroseconds / 1e6;

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

  /// Fallback estimated speed (tok/s) when [_speed] has not been sampled yet
  /// (e.g. while only thoughts or short bursts have arrived): prefers active
  /// streaming pace excluding tool waits once >= 300 ms, else falls back to
  /// total tokens over turn elapsed time once >= 1 s.
  double? get estimatedSpeed {
    if (_speed != null) return null;
    final total = _counted + (_guessed * _ratio).round();
    if (total < 10) return null;
    var active = _anyWritten;
    if ((_anyFirst, _anyLast) case (final first?, final last?)) {
      active += last.difference(first);
    }
    if (active >= _estimateWarmUp && _anySampled >= 10) {
      return _anySampled * _ratio / _seconds(active);
    }
    if (_turnStartedAt case final started?) {
      final elapsed = _clock().difference(started);
      if (elapsed >= warmUp) return total / _seconds(elapsed);
    }
    return null;
  }

  /// What is written so far, and how fast, as last sampled: between its
  /// messages too.
  TurnOutput get output => TurnOutput(
    tokens: _counted + (_guessed * _ratio).round(),
    tokensPerSecond: _speed,
    estimatedTokensPerSecond: _speed == null ? estimatedSpeed : null,
  );

  /// The tokens timed over all the time written, the turn so far; null
  /// before [warmUp] of it.
  double? get averageSpeed {
    var time = _written;
    if ((_first, _last) case (final first?, final last?)) {
      time += last.difference(first);
    }
    return time < warmUp ? null : _sampled * _ratio / _seconds(time);
  }
}
