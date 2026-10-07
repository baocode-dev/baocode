import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ssh_launcher.dart' show SshTarget;

/// What `ssh` asks while signing in to [target]: a password, a key's
/// passphrase, a code. [text] is its own prompt (`me@host's password: `);
/// [retry] when it asked the same just before in that `ssh`, the answer
/// given then refused.
class SshPrompt {
  const SshPrompt(this.target, this.text, {this.retry = false});

  final SshTarget target;
  final String text;
  final bool retry;

  /// Whether `ssh` asks to accept a host key it does not know (`yes/no`):
  /// not a sign-in, and not left to the user here (see [SshLauncher]).
  bool get isHostKey =>
      text.contains('continue connecting') || text.contains('(yes/no');
}

/// Answers [prompt]; null when the user would not (cancelled).
typedef SshPrompter = Future<String?> Function(SshPrompt prompt);

/// Relays what `ssh` asks to [SshPrompter]s: `ssh` runs a script as its
/// `SSH_ASKPASS`, which leaves the prompt in a folder of the `ssh` run
/// and waits for the answer there. Files, in a folder only the user
/// reads, rather than a socket: the script needs nothing but `sh`.
class SshAskpass {
  SshAskpass({this.pollInterval = const Duration(milliseconds: 100)});

  final Duration pollInterval;

  Future<Directory>? _root;
  int _runs = 0;

  /// The script `ssh` runs: the prompt to `prompt.<pid>` (by way of a
  /// temporary file, so that it is never read half written), then waits
  /// for `answer.<pid>`: `1` and the answer, or `0` for none (`ssh` then
  /// takes it as refused). Gives up after ten minutes.
  static const script = r'''#!/bin/sh
d="$BAOCODE_ASKPASS_DIR"
[ -d "$d" ] || exit 1
umask 077
printf '%s' "$1" > "$d/prompt.$$.tmp" && mv -f "$d/prompt.$$.tmp" "$d/prompt.$$" || exit 1
i=0
while [ ! -f "$d/answer.$$" ]; do
  i=$((i + 1))
  [ "$i" -gt 6000 ] && exit 1
  sleep 0.1
done
a=$(cat "$d/answer.$$")
rm -f "$d/answer.$$"
case "$a" in
  1*) printf '%s\n' "${a#1}" ;;
  *) exit 1 ;;
esac
''';

  /// The folder of the script and the runs' folders: made once, only the
  /// user's (`mkdtemp`).
  Future<Directory> get _folder => _root ??= () async {
    final root = await Directory.systemTemp.createTemp('baocode-askpass-');
    final file = File(p.join(root.path, 'askpass.sh'));
    await file.writeAsString(script, flush: true);
    await Process.run('chmod', ['700', root.path, file.path]);
    return root;
  }();

  /// A run of `ssh` for [target], its prompts answered by [prompter]
  /// until it is [AskpassRun.close]d.
  Future<AskpassRun> start(SshTarget target, SshPrompter prompter) async {
    final root = await _folder;
    final folder = await Directory(p.join(root.path, '${_runs++}')).create();
    return AskpassRun._(
      target,
      prompter,
      folder,
      p.join(root.path, 'askpass.sh'),
      pollInterval,
    );
  }
}

/// One `ssh` run's prompts, answered while it signs in.
class AskpassRun {
  AskpassRun._(
    this.target,
    this._prompter,
    this._folder,
    String script,
    Duration interval,
  ) : environment = {
        'SSH_ASKPASS': script,
        // Even with no display (OpenSSH 8.4 and later).
        'SSH_ASKPASS_REQUIRE': 'force',
        'BAOCODE_ASKPASS_DIR': _folder.path,
      } {
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  final SshTarget target;
  final SshPrompter _prompter;
  final Directory _folder;

  /// For `ssh`'s environment.
  final Map<String, String> environment;

  late final Timer _timer;
  final Set<String> _answering = {};
  String? _last;
  bool _closed = false;

  /// Whether a prompt went unanswered: the user cancelled.
  bool get cancelled => _cancelled;
  bool _cancelled = false;

  /// Whether the user is being asked, or answered in the last [within]:
  /// `ssh` is signing in, not stuck.
  bool busy(Duration within) =>
      _answering.isNotEmpty ||
      (_answered != null && DateTime.now().difference(_answered!) < within);
  DateTime? _answered;

  void _poll() {
    if (_closed) return;
    final List<FileSystemEntity> entries;
    try {
      entries = _folder.listSync();
    } on FileSystemException {
      return;
    }
    for (final entry in entries) {
      final name = p.basename(entry.path);
      final match = RegExp(r'^prompt\.(\d+)$').firstMatch(name);
      if (match == null || !_answering.add(name)) continue;
      unawaited(_answer(File(entry.path), match[1]!));
    }
  }

  Future<void> _answer(File prompt, String pid) async {
    String? answer;
    try {
      final text = await prompt.readAsString();
      await prompt.delete();
      final asked = SshPrompt(target, text, retry: text == _last);
      _last = text;
      // A host key is not accepted here: refused, as BatchMode would.
      answer = asked.isHostKey ? 'no' : await _prompter(asked);
    } on Object {
      answer = null;
    } finally {
      _answering.remove(p.basename(prompt.path));
      _answered = DateTime.now();
    }
    if (answer == null) _cancelled = true;
    if (_closed) return;
    try {
      final file = File(p.join(_folder.path, 'answer.$pid'));
      final part = File('${file.path}.tmp');
      await part.writeAsString(answer == null ? '0' : '1$answer', flush: true);
      await part.rename(file.path);
    } on FileSystemException {
      // The run is gone.
    }
  }

  /// Stops answering, and removes what is left of the run.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    try {
      await _folder.delete(recursive: true);
    } on FileSystemException {
      // Gone already.
    }
  }
}
