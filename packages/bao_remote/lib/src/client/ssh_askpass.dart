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
/// reads, rather than a socket: the script needs nothing but `sh` (on
/// Windows, `cmd` and PowerShell).
class SshAskpass {
  SshAskpass({
    this.pollInterval = const Duration(milliseconds: 100),
    bool? windows,
  }) : windows = windows ?? Platform.isWindows;

  /// Whether the scripts are Windows' ([windowsScript]) rather than `sh`'s.
  final bool windows;

  final Duration pollInterval;

  Future<Directory>? _root;
  int _runs = 0;

  /// The script `ssh` runs: the prompt to `prompt.<pid>` (by way of a
  /// temporary file, so that it is never read half written), then waits
  /// for `answer.<pid>`: `1` and the answer, or `0` for none (`ssh` then
  /// takes it as refused). Gives up after ten minutes, or once the run's
  /// folder is gone (its `ssh` ended).
  static const script = r'''#!/bin/sh
d="$BAOCODE_ASKPASS_DIR"
[ -d "$d" ] || exit 1
umask 077
printf '%s' "$1" > "$d/prompt.$$.tmp" && mv -f "$d/prompt.$$.tmp" "$d/prompt.$$" || exit 1
i=0
while [ ! -f "$d/answer.$$" ]; do
  i=$((i + 1))
  [ "$i" -gt 6000 ] && exit 1
  [ -d "$d" ] || exit 1
  sleep 0.1
done
a=$(cat "$d/answer.$$")
rm -f "$d/answer.$$"
case "$a" in
  1*) printf '%s\n' "${a#1}" ;;
  *) exit 1 ;;
esac
''';

  /// [script] on Windows: `ssh` runs `askpass.cmd`, which hands the prompt
  /// to [powershellScript] (no `sh` there). Windows PowerShell by its full
  /// path where it is there: a `powershell.exe` before it on the PATH may
  /// be an alias that no longer opens (6FMBDDY1).
  static const windowsScript =
      '@echo off\r\n'
      'set "ps=%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"\r\n'
      'if not exist "%ps%" set "ps=powershell.exe"\r\n'
      '"%ps%" -NoProfile -NonInteractive -ExecutionPolicy Bypass '
      '-File "%~dp0askpass.ps1" %*\r\n'
      'exit /b %ERRORLEVEL%\r\n';

  /// What [script] does, in PowerShell: the prompt is its arguments, the
  /// answer written to stdout as UTF-8.
  static const powershellScript = r'''
$d = $env:BAOCODE_ASKPASS_DIR
if (-not $d -or -not (Test-Path -LiteralPath $d -PathType Container)) { exit 1 }
$utf8 = New-Object System.Text.UTF8Encoding $false
$prompt = $args -join ' '
$file = Join-Path $d "prompt.$PID"
$answer = Join-Path $d "answer.$PID"
try {
  [IO.File]::WriteAllText("$file.tmp", $prompt, $utf8)
  [IO.File]::Move("$file.tmp", $file)
} catch { exit 1 }
$i = 0
while (-not (Test-Path -LiteralPath $answer)) {
  $i++
  if ($i -gt 6000) { exit 1 }
  if (-not (Test-Path -LiteralPath $d -PathType Container)) { exit 1 }
  Start-Sleep -Milliseconds 100
}
$a = [IO.File]::ReadAllText($answer, $utf8)
Remove-Item -LiteralPath $answer -Force
if (-not $a.StartsWith('1')) { exit 1 }
$bytes = $utf8.GetBytes($a.Substring(1) + "`n")
$out = [Console]::OpenStandardOutput()
$out.Write($bytes, 0, $bytes.Length)
$out.Flush()
exit 0
''';

  /// The script `ssh` is given, in [_folder].
  String get _scriptName => windows ? 'askpass.cmd' : 'askpass.sh';

  /// The folder of the script and the runs' folders: made once, only the
  /// user's (`mkdtemp`; on Windows, the user's own temporary folder).
  Future<Directory> get _folder => _root ??= () async {
    final root = await Directory.systemTemp.createTemp('baocode-askpass-');
    final file = File(p.join(root.path, _scriptName));
    if (windows) {
      await file.writeAsString(windowsScript, flush: true);
      await File(p.join(root.path, 'askpass.ps1'))
          .writeAsString(powershellScript, flush: true);
    } else {
      await file.writeAsString(script, flush: true);
      await Process.run('chmod', ['700', root.path, file.path]);
    }
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
      p.join(root.path, _scriptName),
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

  /// Whether `ssh` asked a sign-in question (not a host key) during this run.
  bool get prompted => _prompted;
  bool _prompted = false;

  /// Whether a sign-in prompt is still waiting for an answer.
  bool get waiting => _answering.isNotEmpty;

  /// Told once, when the user cancels: `ssh` would take the cancel as a
  /// wrong answer and ask again, so its run is ended (see SshLauncher).
  void Function()? onCancelled;

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
      // Cancelled once, the user is not asked again in this run; a host
      // key is not accepted here: refused, as BatchMode would.
      if (_cancelled) {
        answer = null;
      } else if (asked.isHostKey) {
        answer = 'no';
      } else {
        _prompted = true;
        answer = await _prompter(asked);
      }
    } on Object {
      answer = null;
    } finally {
      _answering.remove(p.basename(prompt.path));
      _answered = DateTime.now();
    }
    final cancelling = answer == null && !_cancelled;
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
    // Once the script has its answer, so that it does not go on waiting.
    if (cancelling && !_closed) onCancelled?.call();
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
