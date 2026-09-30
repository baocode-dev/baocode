import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:monad/ide/terminal/pty.dart';

/// A [Pty] for widget tests: records what the terminal sends it, and lets
/// the test play the process ([emit], [emitText], [exit]).
class FakePty extends Pty {
  FakePty({this.launch, this.pid = 4242});

  /// A [PtyStarter] that records each fake it starts in [started].
  static PtyStarter starter(List<FakePty> started) => (launch) async {
    final pty = FakePty(launch: launch);
    started.add(pty);
    return pty;
  };

  /// What it was started with, when by [starter].
  final PtyLaunch? launch;

  @override
  final int pid;

  /// Each [write], as it came.
  final List<Uint8List> writes = [];
  final List<({int columns, int rows})> resizes = [];
  final List<PtySignal> kills = [];

  final _output = StreamController<Uint8List>();
  final _exitCode = Completer<int>();

  /// Everything written, decoded.
  String get written =>
      utf8.decode([for (final chunk in writes) ...chunk], allowMalformed: true);

  bool get exited => _exited;
  bool _exited = false;

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  void write(Uint8List data) {
    if (!exited) writes.add(Uint8List.fromList(data));
  }

  @override
  void resize(int columns, int rows) =>
      resizes.add((columns: columns, rows: rows));

  @override
  void kill([PtySignal signal = PtySignal.hangup]) => kills.add(signal);

  /// Prints [bytes] as the process would.
  void emit(List<int> bytes) => _output.add(Uint8List.fromList(bytes));

  /// Prints [text] in UTF-8.
  void emitText(String text) => _output.add(utf8.encode(text));

  /// Ends the process with [code]. As with a real one, [exitCode] comes
  /// once a listener has had the end of the output.
  void exit([int code = 0]) {
    if (_exited) return;
    _exited = true;
    final closed = _output.close();
    if (_output.hasListener) {
      unawaited(closed.then((_) => _exitCode.complete(code)));
    } else {
      _exitCode.complete(code);
    }
  }
}
