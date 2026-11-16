import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../platform/event_log.dart';

/// What the chat history's selection went through, kept in memory, for when
/// a drag on its text goes wrong: then written out for a diagnostics upload
/// to send ([dump]), the moment it went wrong and every step before it.
///
/// Kinds and places only (positions, list indexes, item indexes, results),
/// none of the text. Bounded: [size] steps, [listSize] changes of the list
/// of text, the oldest dropped; files not more than [most] a run nor one
/// each [gap], and only the [kept] newest stay.
class SelectionRecorder {
  SelectionRecorder({
    this.size = 400,
    this.listSize = 60,
    DateTime Function()? clock,
    String? Function()? folder,
  }) : _clock = clock ?? DateTime.now,
       _folder = folder ?? (() => EventLog.current?.directory),
       _steps = List.filled(size, null),
       _changes = List.filled(listSize, null);

  final int size;
  final int listSize;
  static int most = 3;
  static Duration gap = const Duration(minutes: 1);
  static int kept = 5;

  final DateTime Function() _clock;
  final String? Function() _folder;
  final Stopwatch _watch = Stopwatch()..start();

  final List<(int, String)?> _steps;
  int _nextStep = 0;
  final List<(int, String)?> _changes;
  int _nextChange = 0;

  /// When the list of text was first found off since it was last whole,
  /// what was off, and the list's changes up to then.
  (int, String, List<String>)? _broken;

  static int _written = 0;
  static DateTime? _last;

  /// Something the selection did or was told.
  void step(String what) {
    _steps[_nextStep] = (_watch.elapsedMicroseconds, what);
    _nextStep = (_nextStep + 1) % size;
  }

  /// The list of text changed.
  void listChanged(String what) {
    _changes[_nextChange] = (_watch.elapsedMicroseconds, what);
    _nextChange = (_nextChange + 1) % listSize;
  }

  /// The list of text is found off ([what]); kept from the first time
  /// until [listWhole].
  void listOff(String what) {
    if (_broken != null) return;
    final now = _watch.elapsedMicroseconds;
    _broken = (now, what, _lines(_changes, _nextChange, now));
    step('list off: $what');
  }

  /// The list of text is whole again.
  void listWhole() {
    if (_broken == null) return;
    _broken = null;
    step('list whole again');
  }

  bool get listIsOff => _broken != null;

  List<String> _lines(List<(int, String)?> ring, int next, int now) => [
    for (var i = 0; i < ring.length; i++)
      if (ring[(next + i) % ring.length] case (final at, final what))
        '${_ago(now - at)} $what',
  ];

  static String _ago(int micros) =>
      '-${(micros / 1000).toStringAsFixed(1).padLeft(8)} ms';

  /// Writes what was recorded, under [headline] and the [state] now, to
  /// `hangs/selection-<YYYYMMDD-HHMMSS>-<pid>.txt` of the logs folder, in
  /// the background: the file's name there, or null when not written (no
  /// logs folder, written enough already).
  String? dump(String headline, List<String> state) {
    final folder = _folder();
    if (folder == null || _written >= most) return null;
    final now = _clock();
    if (_last case final last? when now.difference(last) < gap) return null;
    _written++;
    _last = now;
    String two(int n) => '$n'.padLeft(2, '0');
    final name =
        'selection-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}-$pid.txt';
    final at = _watch.elapsedMicroseconds;
    final broken = _broken;
    final text = [
      '${now.toIso8601String()} $headline',
      '',
      '== Now',
      ...state,
      '',
      '== The list of text',
      if (broken == null)
        'whole'
      else ...[
        'off since ${_ago(at - broken.$1)}: ${broken.$2}',
        'its changes up to then:',
        ...broken.$3,
      ],
      'its latest changes:',
      ..._lines(_changes, _nextChange, at),
      '',
      '== Steps, the newest last',
      ..._lines(_steps, _nextStep, at),
      '',
    ].join('\n');
    unawaited(write(p.join(folder, 'hangs'), name, text));
    return 'hangs/$name';
  }

  /// How a file is written: into the folder [hangs], named [name].
  static Future<void> Function(String hangs, String name, String text) write =
      _write;

  static Future<void> _write(String hangs, String name, String text) async {
    try {
      final folder = Directory(hangs);
      await folder.create(recursive: true);
      _prune(folder);
      await File(p.join(hangs, name)).writeAsString(text);
    } on Object {
      // Not written: the event log still says what happened.
    }
  }

  /// Leaves room for one more: the oldest go past [kept].
  static void _prune(Directory hangs) {
    final files = [
      for (final entity in hangs.listSync(followLinks: false))
        if (entity is File && p.basename(entity.path).startsWith('selection-'))
          entity,
    ]..sort((a, b) => b.path.compareTo(a.path));
    for (final old in files.skip(kept - 1)) {
      try {
        old.deleteSync();
      } on FileSystemException {
        // Gone already.
      }
    }
  }

  /// For tests: as at the start of a run.
  static void debugReset() {
    _written = 0;
    _last = null;
    write = _write;
  }
}
