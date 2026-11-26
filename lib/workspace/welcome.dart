import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../chat/chat_session.dart';
import '../kernel/agent_kernel.dart';
import '../kernel/kernel_types.dart';
import '../kernel/claude_code/claude_code_kernel.dart';
import '../kernel/claude_code/claude_code_transport.dart';
import '../kernel/claude_code/claude_core_setting.dart';
import '../kernel/claude_code/mock_claude_code_transport.dart';
import '../models/model_providers.dart';
import '../platform/app_paths.dart';
import '../platform/data_dir.dart';
import '../remote/remote_claude.dart';

/// The conversation a new user first sees, played as it shows: the turns
/// recorded from scripts of the showcase's kind (tool/welcome_demo/), what
/// Claude Code printed for each, through the app's own Claude Code adapter
/// over [WelcomeTransport]. Nothing in it runs. In [Welcome.folder], a
/// project made for them; what they send there starts a conversation of
/// their own.
abstract final class WelcomeDemo {
  /// Where its turns were played: put in place of, as it is set up, the
  /// folder the user has it in.
  static const folder = '/BAOCODE_WELCOME';

  /// Its id: not one Claude Code keeps, so never resumed nor deleted there.
  static const sessionId = 'baocode-welcome-demo';

  /// The languages it is written in, the first the one for any other.
  static const locales = ['en', 'zh'];

  static String asset(String locale) => 'assets/welcome/demo.$locale.json';

  /// [localeName]'s, else the first of [locales].
  static String localeFor(String localeName) {
    final language = localeName.split(RegExp('[_-]')).first;
    return locales.contains(language) ? language : locales.first;
  }

  /// [text], as exported, with [folder] in place of [WelcomeDemo.folder]:
  /// within JSON strings, so spelled as one (a Windows path's backslashes).
  static String place(String text, String folder) {
    final spelled = jsonEncode(folder);
    return text.replaceAll(
      WelcomeDemo.folder,
      spelled.substring(1, spelled.length - 1),
    );
  }
}

/// What the demo plays: the note it starts with, and its turns, each the
/// prompt sent and what came back, at what time into the turn.
class WelcomeRecording {
  const WelcomeRecording({
    required this.notice,
    required this.turns,
    this.ending,
  });

  /// As exported ([WelcomeDemo.place]d already).
  factory WelcomeRecording.fromJson(Map<String, Object?> json) =>
      WelcomeRecording(
        notice: json['notice'] as String? ?? '',
        ending: json['ending'] as String?,
        turns: [
          for (final turn in (json['turns'] as List?) ?? const [])
            if (turn case {
              'prompt': final String prompt,
              'messages': final List<Object?> messages,
            })
              WelcomeTurn(prompt, [
                for (final entry in messages)
                  if (entry case [
                    final int at,
                    final Map<String, Object?> message,
                  ])
                    (at: at, message: message),
              ]),
        ],
      );

  /// Shown before anything plays: that it is a demo.
  final String notice;

  /// Shown once it is all played: that what they send starts their own.
  final String? ending;

  final List<WelcomeTurn> turns;

  List<String> get prompts => [for (final turn in turns) turn.prompt];

  /// The session the demo is read from before it plays: only [notice], as
  /// Claude Code keeps a line (see ClaudeCodeTranslator's informational).
  String keptLines(String cwd) =>
      '${jsonEncode({'type': 'system', 'subtype': 'informational', 'level': 'notice', 'content': notice, 'uuid': '00000000-0000-4000-a000-000000000000', 'parentUuid': null, 'isSidechain': false, 'sessionId': WelcomeDemo.sessionId, 'cwd': cwd, 'timestamp': DateTime.utc(2026, 11, 20, 9).toIso8601String()})}\n';
}

class WelcomeTurn {
  const WelcomeTurn(this.prompt, this.messages);

  final String prompt;

  /// The lines Claude Code printed, [at] milliseconds into the turn.
  final List<({int at, Map<String, Object?> message})> messages;
}

/// Sets up what a new user first sees: a folder to work in, and the demo.
abstract class Welcome {
  const Welcome();

  /// `~/BaoCode`, on this machine.
  factory Welcome.io() = _IoWelcome;

  /// The folder new users start in, made if it was not.
  Future<String> folder();

  /// The demo for [folder] in [localeName]'s language, and the file of the
  /// session it is read from before it plays ([WelcomeRecording.keptLines]);
  /// null where it could not be.
  Future<({WelcomeRecording recording, String path})?> demo(
    String folder,
    String localeName,
  );

  /// The demo's recording in [locale], as [Welcome.demo] reads it from
  /// [text] and writes its session in [dir].
  static Future<({WelcomeRecording recording, String path})> keep(
    String text,
    String folder,
    String locale,
    String dir,
  ) async {
    final recording = WelcomeRecording.fromJson(
      (jsonDecode(WelcomeDemo.place(text, folder)) as Map)
          .cast<String, Object?>(),
    );
    final file = File(p.join(dir, 'demo.$locale.jsonl'));
    await file.parent.create(recursive: true);
    await file.writeAsString(recording.keptLines(folder));
    return (recording: recording, path: file.path);
  }
}

class _IoWelcome extends Welcome {
  _IoWelcome();

  @override
  Future<String> folder() async {
    final dir = Directory(
      p.join(AppPaths.home(Platform.environment), 'BaoCode'),
    );
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<({WelcomeRecording recording, String path})?> demo(
    String folder,
    String localeName,
  ) async {
    try {
      final locale = WelcomeDemo.localeFor(localeName);
      return await Welcome.keep(
        await rootBundle.loadString(WelcomeDemo.asset(locale)),
        folder,
        locale,
        p.join(DataDirectory.current.stateDir, 'welcome'),
      );
    } on Object {
      return null;
    }
  }
}

/// Claude Code's adapter, as [base] is, over a [WelcomeTransport] playing
/// [recording]: the demo's kernel.
KernelDescriptor welcomeKernel(
  KernelDescriptor base,
  WelcomeRecording recording,
) {
  late final KernelDescriptor descriptor;
  descriptor = KernelDescriptor(
    id: base.id,
    label: base.label,
    icon: base.icon,
    description: base.description,
    create: (context) => ClaudeCodeKernel(
      descriptor,
      context,
      start: (launch) async => WelcomeTransport(recording, launch),
      readHistoryPage: readClaudeHistoryPage,
    ),
  );
  return descriptor;
}

/// [health] as the demo shows it: with no model to run on, as a new
/// conversation would have (BaoCode's own core, no upstream turned on), so
/// that the user is offered setting one up; the demo plays all the same.
KernelHealth welcomeHealth(KernelHealth health) =>
    health.status != KernelHealthStatus.failed &&
        ClaudeCore.current() == ClaudeCore.builtin &&
        ModelProviders.current.firstModel == null
    ? const KernelHealth(
        KernelHealthStatus.failed,
        message: ClaudeCore.noModel,
        noModel: true,
      )
    : health;

/// A Claude Code CLI that answers each of the demo's prompts with what was
/// recorded for it, at its pace; control requests as
/// [MockClaudeCodeTransport] answers them. Anything else sent ends at once.
class WelcomeTransport implements ClaudeCodeTransport {
  WelcomeTransport(this.recording, ClaudeLaunch launch)
    : _control = MockClaudeCodeTransport(launch) {
    _control.messages.listen(_fromControl, onDone: _out.close);
  }

  final WelcomeRecording recording;
  final MockClaudeCodeTransport _control;
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();

  /// The turn playing: stopped by bumping it.
  int _playing = 0;
  bool _busy = false;
  final _queued = <Map<String, Object?>>[];

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) {
      _out.add({...message, 'session_id': WelcomeDemo.sessionId});
    }
  }

  void _fromControl(Map<String, Object?> message) {
    if (message['type'] == 'control_response' ||
        message['type'] == 'control_request') {
      _emit(message);
    }
  }

  @override
  void write(Map<String, Object?> message) {
    switch (message['type']) {
      case 'user' when _busy:
        _queued.add(message);
      case 'user':
        unawaited(_play(message));
      case 'control_request'
          when (message['request'] as Map?)?['subtype'] == 'interrupt':
        if (_busy) {
          _playing++;
          _busy = false;
          _emit(_result(error: true));
        }
        _control.write(message);
      default:
        _control.write(message);
    }
  }

  static String _text(Map<String, Object?> message) =>
      switch ((message['message'] as Map?)?['content']) {
        final String text => text,
        final List<Object?> blocks =>
          blocks
              .whereType<Map<Object?, Object?>>()
              .where((block) => block['type'] == 'text')
              .map((block) => block['text'])
              .join('\n'),
        _ => '',
      };

  Future<void> _play(Map<String, Object?> sent) async {
    final prompt = _text(sent).trim();
    final turn = recording.turns
        .where((turn) => turn.prompt.trim() == prompt)
        .firstOrNull;
    final playing = ++_playing;
    _busy = true;
    if (turn == null) {
      _emit({...sent, 'isReplay': true});
      _emit(_result());
    } else {
      final clock = Stopwatch()..start();
      for (final (:at, :message) in turn.messages) {
        final wait = at - clock.elapsedMilliseconds;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
        if (playing != _playing || _out.isClosed) return;
        _emit(
          message['type'] == 'user' && message['isReplay'] == true
              // The prompt as the kernel sent it, its id with it.
              ? {...sent, 'isReplay': true}
              : message,
        );
      }
      if (identical(turn, recording.turns.last)) {
        if (recording.ending case final ending?) {
          _emit({
            'type': 'system',
            'subtype': 'informational',
            'level': 'notice',
            'content': ending,
          });
        }
      }
    }
    if (playing != _playing) return;
    _busy = false;
    if (_queued.isNotEmpty) unawaited(_play(_queued.removeAt(0)));
  }

  static Map<String, Object?> _result({bool error = false}) => {
    'type': 'result',
    'subtype': error ? 'error_during_execution' : 'success',
    'is_error': false,
    'total_cost_usd': 0,
    'duration_ms': 0,
    'usage': {'input_tokens': 0, 'output_tokens': 0},
  };

  @override
  Future<void> get exited => _out.done;

  @override
  void close() {
    _playing++;
    _control.close();
  }
}

/// Plays the demo in [session] once the user sees it, nothing over it
/// ([ChatSession.seen]): its prompts sent one after the other, each once
/// the turn before is over and the demo shows again.
class WelcomePlayer {
  WelcomePlayer(this.session, this.prompts) {
    session.seen.addListener(_seenChanged);
    _seenChanged();
  }

  final ChatSession session;
  final List<String> prompts;

  /// How long it shows before it plays: a dialog that opens with it (the
  /// welcome to models, say) comes over it first.
  static const settle = Duration(milliseconds: 800);

  /// Between one turn's end and the next prompt.
  static const between = Duration(milliseconds: 1500);

  var _next = 0;
  Timer? _timer;
  bool _stopped = false;

  /// Whether all its prompts were sent.
  bool get done => _next >= prompts.length;

  void _seenChanged() {
    _timer?.cancel();
    if (_stopped ||
        done ||
        session.disposed ||
        !session.seen.value ||
        session.isStreaming) {
      return;
    }
    _timer = Timer(_next == 0 ? settle : between, _send);
  }

  void _send() {
    if (_stopped ||
        done ||
        session.disposed ||
        !session.seen.value ||
        session.isStreaming) {
      return;
    }
    final prompt = prompts[_next++];
    // Its own, sent as is: not the user's, which start a conversation of
    // their own.
    final instead = session.sendInstead;
    session.sendInstead = null;
    session.send(ComposerMessage(text: prompt));
    session.sendInstead = instead;
    if (!done) session.addListener(_turnEnded);
  }

  var _started = false;

  void _turnEnded() {
    if (session.isStreaming) {
      _started = true;
      return;
    }
    if (!_started) return;
    _started = false;
    session.removeListener(_turnEnded);
    _seenChanged();
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    session.seen.removeListener(_seenChanged);
    session.removeListener(_turnEnded);
  }
}
