import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:path/path.dart' as p;

import '../ide/file_service_io.dart';
import '../kernel/claude_code/claude_sdk_tools.dart';
import '../kernel/kernel_types.dart';
import '../l10n/app_localizations.dart';
import 'port_forwards.dart';
import 'remote_host_settings.dart';
import 'remote_location.dart';
import 'remote_services.dart';
import 'ssh_host.dart';

/// The tools an agent on an SSH host has for the user's own computer, this
/// machine: running a command here (`local_run`, asking the user each
/// time), copying files here and there (`local_push`, `local_pull`) and
/// forwarding ports either way (`port_forward`), over the host's
/// connection. Only an agent of an SSH project is offered them, and only
/// while the user lets that host act on this machine
/// ([RemoteHostSettings.localAccess], on until turned off in Settings →
/// SSH Servers). Turned off, its agents are told where to turn it on.
abstract final class LocalTools {
  static const run = 'local_run';
  static const push = 'local_push';
  static const pull = 'local_pull';
  static const forward = 'port_forward';

  /// What the instructions are kept as ([ClaudeSdkTools.instructFor]).
  static const feature = 'local';

  /// How long a command runs at most, by default and at all.
  static const defaultTimeout = Duration(minutes: 2);
  static const maxTimeout = Duration(minutes: 30);

  /// What a command's output is cut to, its end kept.
  static const maxOutput = 30000;

  static RemoteHostSettings get _settings => RemoteHostSettings.instance;

  /// The host of an agent working in [cwd] offered the tools, if it is.
  static String? hostOffered(String cwd) {
    final host = RemoteLocation.hostOf(cwd);
    if (host == null || RemoteLocation.isWsl(host)) return null;
    return _settings.localAccess(host) ? host : null;
  }

  /// This machine for the agent: `macOS`, `Windows`, `Linux`.
  static String get thisSystem => Platform.isMacOS
      ? 'macOS'
      : Platform.isWindows
      ? 'Windows'
      : 'Linux';

  static String _hostSystem(String host) =>
      switch (SshHosts.instance[host].hello?.platform.os) {
        'win' => 'Windows',
        'darwin' => 'macOS',
        'linux' => 'Linux',
        _ => 'a remote machine',
      };

  /// Registers the tools; [l10n] says the cards' words.
  static void start({required AppLocalizations Function() l10n}) {
    for (final tool in [
      _runTool(l10n),
      _pushTool(),
      _pullTool(),
      _forwardTool(),
    ]) {
      ClaudeSdkTools.register(tool);
    }
    ClaudeSdkTools.instructFor(feature, instructions);
  }

  /// What an agent working in [cwd] is told of the tools, where it is
  /// offered them; where its host's user turned them off, where to turn
  /// them on.
  static String? instructions(String cwd) {
    final host = RemoteLocation.hostOf(cwd);
    if (host == null || RemoteLocation.isWsl(host)) return null;
    final name = RemoteLocation.hostName(host);
    if (!_settings.localAccess(host)) {
      return 'You work on $name over SSH; the user sits at their own '
          'computer ($thisSystem), not on $name. They have turned off '
          'agents on $name acting on their computer: asked to run '
          'something or copy files there, tell them they can turn it on '
          'in BaoCode\'s Settings → SSH Servers.';
    }
    return 'You work on $name (${_hostSystem(host)}) over SSH: your files, '
        'commands and tools are all there. The user sits at their own '
        'computer ($thisSystem), not on $name. To act on their computer '
        'use these tools: $run runs a command on it (the user approves '
        'each one; ${Platform.isWindows ? 'PowerShell' : 'their shell'}), '
        '$push copies a file or folder from it to $name, $pull copies one '
        'from $name to it (their Downloads folder unless you say where), '
        'and $forward forwards a port either way: a server you run on '
        '$name opened in their browser, or a server on their computer '
        'reached from $name. A server you start on $name that prints its '
        'http://localhost:<port> address is forwarded to their computer on '
        'its own. Where ADB_SERVER_SOCKET is set on $name, adb there uses '
        'the phones plugged into their computer.';
  }

  static bool _offered(String cwd) => hostOffered(cwd) != null;

  static String _hostOf(ClaudeSdkCall call) =>
      hostOffered(call.cwd) ??
      (throw const LocalToolException(
        'The user has not let this host act on their computer.',
      ));

  // --- local_run -------------------------------------------------------------

  static ClaudeSdkTool _runTool(
    AppLocalizations Function() l10n,
  ) => ClaudeSdkTool(
    name: run,
    description:
        'Runs a shell command on the user\'s own computer ($thisSystem), '
        'not on the SSH host you work on: '
        '${Platform.isWindows ? 'in Windows PowerShell' : 'in their login shell'}. '
        'The user is asked to approve each command. Returns its exit code '
        'and output (stdout, then stderr; the end of it where long).',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'The command, as typed at a prompt.',
        },
        'cwd': {
          'type': 'string',
          'description':
              'The folder of the user\'s computer it runs in; their home '
              'folder by default.',
        },
        'timeout': {
          'type': 'number',
          'description':
              'Seconds it may run before it is stopped: 120 by default, '
              '1800 at most.',
        },
      },
      'required': ['command'],
    },
    offeredIn: _offered,
    asksItself: true,
    alwaysLoad: true,
    summary: (input, _) => '${input['command'] ?? ''}',
    run: (input, call) async {
      final host = _hostOf(call);
      final command = '${input['command'] ?? ''}'.trim();
      if (command.isEmpty) {
        throw const LocalToolException('No command given.');
      }
      final home = _home();
      final cwd = switch (input['cwd']) {
        final String dir when dir.trim().isNotEmpty => p.normalize(
          p.join(home, _expandHome(dir.trim(), home)),
        ),
        _ => home,
      };
      if (!Directory(cwd).existsSync()) {
        throw LocalToolException('No folder $cwd on the user\'s computer.');
      }
      if (!_settings.runsWithoutAsking(host)) {
        final words = l10n();
        final name = RemoteLocation.hostName(host);
        final decision = await call.ask?.call(
          ApprovalRequest(
            id: '',
            title: words.localRunTitle,
            toolName: 'mcp__${ClaudeSdkTools.server}__$run',
            reason: words.localRunReason(name, thisSystem),
            preview: CommandPreview(command, description: cwd),
            alwaysAllowLabel: words.localRunAlways(name),
          ),
        );
        switch (decision) {
          case ApprovalDecision.allowOnce:
            break;
          case ApprovalDecision.allowAlways:
            _settings.setRunsWithoutAsking(host, true);
          case ApprovalDecision.deny || null:
            throw const LocalToolException(
              'The user did not allow running it on their computer.',
            );
        }
      }
      final seconds = switch (input['timeout']) {
        final num n when n > 0 => n.toInt(),
        _ => defaultTimeout.inSeconds,
      };
      final timeout = Duration(seconds: seconds.clamp(1, maxTimeout.inSeconds));
      return runHere(
        command,
        cwd: cwd,
        timeout: timeout,
        cancelled: call.cancelled,
      );
    },
  );

  static String _home() =>
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ??
      Directory.current.path;

  static String _expandHome(String path, String home) => path == '~'
      ? home
      : path.startsWith('~/') || path.startsWith(r'~\')
      ? p.join(home, path.substring(2))
      : path;

  /// Runs [command] here, as `local_run` does: in PowerShell on Windows,
  /// the user's shell elsewhere (with the login shell's environment). Its
  /// exit code and output, the end of it where long.
  static Future<String> runHere(
    String command, {
    required String cwd,
    Duration timeout = defaultTimeout,
    Future<void>? cancelled,
  }) async {
    final environment = Platform.isWindows
        ? Platform.environment
        : await ClaudeEnvironment.of();
    final Process process;
    if (Platform.isWindows) {
      process = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          '[Console]::OutputEncoding = [Text.Encoding]::UTF8; $command',
        ],
        workingDirectory: cwd,
        environment: environment,
      );
    } else {
      final shell = environment['SHELL'] ?? '/bin/sh';
      process = await Process.start(
        File(shell).existsSync() ? shell : '/bin/sh',
        ['-c', command],
        workingDirectory: cwd,
        environment: environment,
      );
    }
    unawaited(process.stdin.close().catchError((Object _) {}));
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    String? stopped;
    void stop(String why) {
      if (stopped != null) return;
      stopped = why;
      _killTree(process);
    }

    final timer = Timer(
      timeout,
      () => stop('timed out after ${timeout.inSeconds}s'),
    );
    unawaited(cancelled?.then((_) => stop('stopped')));
    final code = await process.exitCode;
    timer.cancel();
    final out = (await stdout).trimRight();
    final err = (await stderr).trimRight();
    final text = [
      if (stopped != null) 'The command was $stopped.',
      'Exit code: $code',
      if (out.isNotEmpty) out,
      if (err.isNotEmpty) 'stderr:\n$err',
    ].join('\n');
    return text.length <= maxOutput
        ? text
        : '[the first ${text.length - maxOutput} characters left out]\n'
              '${text.substring(text.length - maxOutput)}';
  }

  static void _killTree(Process process) {
    if (Platform.isWindows) {
      unawaited(
        Process.run('taskkill', [
          '/pid',
          '${process.pid}',
          '/T',
          '/F',
        ]).then((_) {}, onError: (Object _) {}),
      );
    } else {
      process.kill(ProcessSignal.sigkill);
    }
  }

  // --- local_push, local_pull -----------------------------------------------

  static ClaudeSdkTool _pushTool() => ClaudeSdkTool(
    name: push,
    description:
        'Copies a file or folder of the user\'s own computer ($thisSystem) '
        'to the SSH host you work on. A folder is copied with all in it.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'local_path': {
          'type': 'string',
          'description':
              'The file or folder on the user\'s computer (absolute, or '
              'from their home folder; ~ for it).',
        },
        'remote_path': {
          'type': 'string',
          'description':
              'Where on the host: a folder there to copy it into, or the '
              'path it is to have. The project\'s folder by default; '
              'relative to it where not absolute.',
        },
      },
      'required': ['local_path'],
    },
    offeredIn: _offered,
    summary: (input, _) => '${input['local_path'] ?? ''}',
    run: (input, call) async {
      final host = _hostOf(call);
      final home = _home();
      final from = p.normalize(
        p.join(home, _expandHome('${input['local_path'] ?? ''}'.trim(), home)),
      );
      final type = await FileSystemEntity.type(from);
      if (type == FileSystemEntityType.notFound) {
        throw LocalToolException('No $from on the user\'s computer.');
      }
      final ssh = SshHosts.instance[host];
      final client = await ssh.ready;
      final root = RemoteLocation.pathOf(call.cwd);
      final paths = RemoteLocation.pathsFor(root);
      var to = switch (input['remote_path']) {
        final String path when path.trim().isNotEmpty => paths.normalize(
          paths.join(root, path.trim()),
        ),
        _ => root,
      };
      if (await client.stat(to) == 'directory') {
        to = paths.join(to, p.basename(from));
      }
      var files = 0;
      await uploadTo(RemoteIdeFileService(ssh, root), [
        (from: from, to: to),
      ], onProgress: (done, _) => files = done);
      return 'Copied ${type == FileSystemEntityType.directory ? 'the folder' : 'the file'} '
          '$from of the user\'s computer to $to on '
          '${RemoteLocation.hostName(host)} ($files file${files == 1 ? '' : 's'}).';
    },
  );

  static ClaudeSdkTool _pullTool() => ClaudeSdkTool(
    name: pull,
    description:
        'Copies a file or folder of the SSH host you work on to the user\'s '
        'own computer ($thisSystem): into their Downloads folder unless '
        'told where. A folder is copied with all in it.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'remote_path': {
          'type': 'string',
          'description':
              'The file or folder on the host: absolute, or relative to '
              'the project\'s folder.',
        },
        'local_path': {
          'type': 'string',
          'description':
              'Where on the user\'s computer: a folder to copy it into, or '
              'the path it is to have (absolute, or from their home '
              'folder). Their Downloads folder by default.',
        },
      },
      'required': ['remote_path'],
    },
    offeredIn: _offered,
    summary: (input, _) => '${input['remote_path'] ?? ''}',
    run: (input, call) async {
      final host = _hostOf(call);
      final ssh = SshHosts.instance[host];
      final client = await ssh.ready;
      final root = RemoteLocation.pathOf(call.cwd);
      final paths = RemoteLocation.pathsFor(root);
      final from = paths.normalize(
        paths.join(root, '${input['remote_path'] ?? ''}'.trim()),
      );
      final type = await client.stat(from);
      if (type != 'file' && type != 'directory') {
        throw LocalToolException(
          'No $from on ${RemoteLocation.hostName(host)}.',
        );
      }
      final home = _home();
      final name = paths.basename(from);
      var to = switch (input['local_path']) {
        final String path when path.trim().isNotEmpty => p.normalize(
          p.join(home, _expandHome(path.trim(), home)),
        ),
        _ => p.join(home, 'Downloads'),
      };
      if (Directory(to).existsSync()) {
        to = _free(p.join(to, name));
      }
      await Directory(p.dirname(to)).create(recursive: true);
      var files = 0;
      await downloadFrom(RemoteIdeFileService(ssh, root), [
        (from: from, to: to, directory: type == 'directory'),
      ], onProgress: (done, _) => files = done);
      return 'Copied the ${type == 'directory' ? 'folder' : 'file'} $from of '
          '${RemoteLocation.hostName(host)} to $to on the user\'s computer '
          '($files file${files == 1 ? '' : 's'}).';
    },
  );

  /// [path], or `name (2).ext` and so on beside it where it is taken.
  static String _free(String path) {
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      return path;
    }
    final dir = p.dirname(path);
    final stem = p.basenameWithoutExtension(path);
    final extension = p.extension(path);
    for (var n = 2; ; n++) {
      final next = p.join(dir, '$stem ($n)$extension');
      if (FileSystemEntity.typeSync(next) == FileSystemEntityType.notFound) {
        return next;
      }
    }
  }

  // --- port_forward ----------------------------------------------------------

  static ClaudeSdkTool _forwardTool() => ClaudeSdkTool(
    name: forward,
    description:
        'Forwards a port between the SSH host you work on and the user\'s '
        'own computer, lists the forwards, or stops one. remote_to_local: a '
        'server listening on the host\'s loopback opened on the user\'s '
        'computer (on the same port where free, else another: the answer '
        'says the address to open there). local_to_remote: a server of the '
        'user\'s computer reached on the host\'s 127.0.0.1. Forwards are kept '
        'for the host and made again as it reconnects.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'action': {
          'type': 'string',
          'enum': ['open', 'close', 'list'],
        },
        'direction': {
          'type': 'string',
          'enum': ['remote_to_local', 'local_to_remote'],
          'description': 'For open and close; remote_to_local by default.',
        },
        'port': {
          'type': 'integer',
          'description':
              'The port forwarded: the host\'s for remote_to_local, the '
              'user\'s computer\'s for local_to_remote.',
        },
        'listen_port': {
          'type': 'integer',
          'description':
              'The port to listen on at the other end; the same as port by '
              'default (another where it is taken, unless given).',
        },
      },
      'required': ['action'],
    },
    offeredIn: _offered,
    summary: (input, _) => switch (input['action']) {
      'list' => 'list',
      final action => '$action ${input['port'] ?? ''}',
    },
    run: (input, call) async {
      final host = _hostOf(call);
      final forwards = PortForwards.instance;
      String describe(PortForward forward) =>
          switch (forward.direction) {
            ForwardDirection.toLocal =>
              'remote_to_local: port ${forward.remotePort} of the host → '
                  '${forward.localUrl ?? 'not listening here'} on the user\'s computer',
            ForwardDirection.toRemote =>
              'local_to_remote: port ${forward.localPort} of the user\'s '
                  'computer → 127.0.0.1:${forward.remotePort ?? '?'} on the host',
          } +
          switch (forward.error) {
            final error? => ' ($error)',
            null => '',
          };
      final action = input['action'];
      if (action == 'list') {
        final all = forwards.of(host);
        return all.isEmpty
            ? 'No ports are forwarded for this host.'
            : all.map(describe).join('\n');
      }
      final port = switch (input['port']) {
        final num n when n > 0 && n < 65536 => n.toInt(),
        _ => throw const LocalToolException('No port given.'),
      };
      final direction = input['direction'] == 'local_to_remote'
          ? ForwardDirection.toRemote
          : ForwardDirection.toLocal;
      final spec = PortForwardSpec(
        direction: direction,
        port: port,
        listen: switch (input['listen_port']) {
          final num n when n > 0 && n < 65536 => n.toInt(),
          _ => null,
        },
      );
      switch (action) {
        case 'open':
          return 'Forwarded: ${describe(await forwards.open(host, spec))}';
        case 'close':
          final open = [
            for (final forward in forwards.of(host))
              if (forward.spec.same(spec)) forward,
          ];
          if (open.isEmpty) {
            throw LocalToolException('No such forward of port $port.');
          }
          for (final forward in open) {
            await forwards.close(forward);
          }
          return 'Stopped forwarding port $port.';
        default:
          throw LocalToolException('No action $action.');
      }
    },
  );
}

class LocalToolException implements Exception {
  const LocalToolException(this.message);

  final String message;

  @override
  String toString() => message;
}
