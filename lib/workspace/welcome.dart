import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

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

/// The conversation a new user first sees: a reply Claude Code printed
/// (its stream-json, recorded from a script of the showcase's kind,
/// tool/welcome_demo/), played again through the app's own Claude Code
/// adapter over [WelcomeTransport] to whatever is sent there. Nothing in
/// it runs. In [Welcome.folder], a project made for them.
abstract final class WelcomeDemo {
  /// Where it was played: put in place of, as it is set up, the folder the
  /// user has it in.
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

/// What the demo plays: the note it starts with, the prompt it is first
/// sent, and the reply to it, each line at what time into it.
class WelcomeRecording {
  const WelcomeRecording({
    required this.notice,
    required this.prompt,
    required this.messages,
  });

  /// As exported ([WelcomeDemo.place]d already).
  factory WelcomeRecording.fromJson(Map<String, Object?> json) =>
      WelcomeRecording(
        notice: json['notice'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        messages: [
          for (final entry in (json['messages'] as List?) ?? const [])
            if (entry case [final int at, final Map<String, Object?> message])
              (at: at, message: message),
        ],
      );

  /// Shown before anything plays: that it is a demo.
  final String notice;

  /// Sent as it opens.
  final String prompt;

  /// The lines Claude Code printed, [at] milliseconds into the reply.
  final List<({int at, Map<String, Object?> message})> messages;

  /// The session the demo is read from before it plays: only [notice], as
  /// Claude Code keeps a line (see ClaudeCodeTranslator's informational).
  String keptLines(String cwd) =>
      '${jsonEncode({'type': 'system', 'subtype': 'informational', 'level': 'notice', 'content': notice, 'uuid': '00000000-0000-4000-a000-000000000000', 'parentUuid': null, 'isSidechain': false, 'sessionId': WelcomeDemo.sessionId, 'cwd': cwd, 'timestamp': DateTime.utc(2026, 11, 20, 9).toIso8601String()})}\n';
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

/// A Claude Code CLI that answers whatever is sent with the demo's reply,
/// at its pace; control requests as [MockClaudeCodeTransport] answers them.
class WelcomeTransport implements ClaudeCodeTransport {
  WelcomeTransport(this.recording, ClaudeLaunch launch)
    : _control = MockClaudeCodeTransport(launch) {
    _control.messages.listen(_fromControl, onDone: _out.close);
  }

  final WelcomeRecording recording;
  final MockClaudeCodeTransport _control;
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();

  /// The reply playing: stopped by bumping it.
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
          _emit(_stopped);
        }
        _control.write(message);
      default:
        _control.write(message);
    }
  }

  /// How many times each recording was played, in any transport.
  static final _plays = Expando<int>();

  /// The key the showcase's ids were made with (`msg_<key>_1`).
  late final String? _key = recording.messages
      .map((line) => (line.message['message'] as Map?)?['id'])
      .whereType<String>()
      .map((id) => RegExp(r'^msg_([0-9a-f]{8})_').firstMatch(id)?[1])
      .nonNulls
      .firstOrNull;

  /// [message] with ids of its own for each time it is played: not the
  /// same messages, tools and subagents again, but more.
  Map<String, Object?> _anew(Map<String, Object?> message, int play) =>
      switch (_key) {
        final key? when play > 1 => (jsonDecode(
          jsonEncode(message).replaceAll(key, '${key}r$play'),
        ) as Map).cast<String, Object?>(),
        _ => message,
      };

  Future<void> _play(Map<String, Object?> sent) async {
    final playing = ++_playing;
    final play = _plays[recording] = (_plays[recording] ?? 0) + 1;
    _busy = true;
    final clock = Stopwatch()..start();
    for (final (:at, :message) in recording.messages) {
      final wait = at - clock.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      if (playing != _playing || _out.isClosed) return;
      _emit(
        message['type'] == 'user' && message['isReplay'] == true
            // What was sent, as the kernel sent it, its id with it.
            ? {...sent, 'isReplay': true}
            : _anew(message, play),
      );
    }
    _busy = false;
    if (_queued.isNotEmpty) unawaited(_play(_queued.removeAt(0)));
  }

  static const _stopped = {
    'type': 'result',
    'subtype': 'error_during_execution',
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
