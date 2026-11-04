// Run as a desktop app, not with flutter test. See ssh_windows.md.
// The production app on a real SSH host (a Windows one): its files,
// terminal, Git, search and an agent there; the tools for this machine
// the agent has; ports forwarded both ways.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_remote/client.dart' show SshAuth, SshServer;
import 'package:baocode/browser/browser_bridge.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart' show LspPosition;
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_panel.dart';
import 'package:baocode/kernel/agent_kernel.dart' show KernelChoiceKind;
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/main.dart' as app;
import 'package:baocode/remote/port_forwards.dart';
import 'package:baocode/remote/remote_host_settings.dart';
import 'package:baocode/remote/remote_location.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../perf/perf_input.dart';

/// What each step showed, in order.
final _results = <Map<String, Object?>>[];
final _input = PerfInput();
late Directory _out;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final directory = env['BAOCODE_E2E_OUT'];
  final host = env['BAOCODE_E2E_HOST'];
  final root = env['BAOCODE_E2E_ROOT'];
  if (directory == null || host == null || root == null) {
    stderr.writeln(
      'Set BAOCODE_E2E_OUT, BAOCODE_E2E_HOST (user@host) and '
      'BAOCODE_E2E_ROOT (a Git repository there).',
    );
    exit(2);
  }
  final phase = env['BAOCODE_E2E_PHASE'] ?? 'main';
  _out = Directory(directory)..createSync(recursive: true);
  // A browser of the run's own, its host finding this app here: not the
  // user's, whose extension speaks to the BaoCode they run.
  final sockets = Directory(p.join(_out.path, 'sockets'))
    ..createSync(recursive: true);
  BrowserBridge.socketFolder = sockets.path;

  // The app as it starts for the user (its data folder a copy:
  // BAOCODE_DATA_DIR), the project then opened in it.
  await app.main(const []);
  final errors = <String>[];
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    presentError?.call(details);
  };
  final timeout = Timer(const Duration(minutes: 25), () {
    stderr.writeln('SSH E2E timed out.');
    _write(phase, failed: true, errors: errors);
    exit(1);
  });

  final location = RemoteLocation.of(host, root);
  var failed = false;
  try {
    await _until(() => _find<app.BaoCodeApp>() != null, 'the app');
    final workspace =
        (_find<app.BaoCodeApp>()!.widget as app.BaoCodeApp).workspace!;
    if (phase == 'windows') {
      // Added as the user adds one in the app: a saved server, its key.
      workspace.saveSshServer(
        host,
        SshServer(
          hostName: env['BAOCODE_E2E_SSH_HOST'] ?? '127.0.0.1',
          user: env['BAOCODE_E2E_SSH_USER'],
          auth: SshAuth.key,
          identityFile: env['BAOCODE_E2E_KEY'],
        ),
      );
    }
    await workspace.openFolder(location);
    final project = workspace.projectAt(location);
    workspace
      ..keepIdeView(location, {'chat': false})
      ..openIdeFolder(location)
      ..layout = WorkspaceLayout.ide;
    await _until(() => _find<IdeWorkbench>() != null, 'the IDE');
    try {
      await const MethodChannel('baocode/windows').invokeMethod(
        'focus',
        WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
      );
    } on MissingPluginException {
      // A platform whose app has one window.
    }
    final run = _Run(
      workspace: workspace,
      project: project,
      host: host,
      root: root,
      location: location,
      sockets: sockets,
    );
    if (phase == 'restart') {
      await run.restarted();
    } else if (phase == 'windows') {
      await run.windowsClient();
    } else if (phase == 'lsp') {
      await run.languageServers();
    } else {
      await run.everything();
    }
    failed = _results.any((result) => result['passed'] == false);
  } catch (error, stack) {
    failed = true;
    stderr.writeln('$error\n$stack');
    _results.add({'step': 'run', 'passed': false, 'error': '$error'});
    try {
      await _shot('failure');
    } catch (_) {}
  } finally {
    timeout.cancel();
    if (errors.isNotEmpty) {
      _results.add({'step': 'flutter errors', 'passed': false});
      failed = true;
    }
    _write(phase, failed: failed, errors: errors);
  }
  exit(failed ? 1 : 0);
}

void _write(
  String phase, {
  required bool failed,
  required List<String> errors,
}) {
  final file = File(p.join(_out.path, 'result-$phase.json'));
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'passed': !failed,
      'phase': phase,
      'platform': Platform.operatingSystem,
      'steps': _results,
      'flutterErrors': errors,
    }),
  );
  stdout.writeln('BAOCODE_E2E_RESULT ${file.path}');
}

class _Run {
  _Run({
    required this.workspace,
    required this.project,
    required this.host,
    required this.root,
    required this.location,
    required this.sockets,
  });

  final Workspace workspace;
  final Project project;
  final String host;
  final String root;
  final String location;
  final Directory sockets;

  p.Context get paths => p.windows;
  String at(String relative) => paths.join(root, relative);

  IdeWorkbenchState get ide =>
      (_find<IdeWorkbench>()! as StatefulElement).state as IdeWorkbenchState;

  Future<String> readThere(String relative) async {
    final client = await SshHosts.instance[host].ready;
    return client.read(root, at(relative), force: true);
  }

  Future<IdeGitOutputLike> runThere(String script) async {
    final client = await SshHosts.instance[host].ready;
    final output = await client.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    return IdeGitOutputLike(output.exitCode, output.stdout, output.stderr);
  }

  /// Runs [body] as step [name]: its result kept, and a screenshot; a
  /// failure kept too, and the next steps run.
  Future<void> step(
    String name,
    Future<Map<String, Object?>> Function() body,
  ) async {
    stdout.writeln('== $name');
    final watch = Stopwatch()..start();
    try {
      final result = await body();
      await _settle();
      await _shot(name);
      _results.add({
        'step': name,
        'passed': true,
        'ms': watch.elapsedMilliseconds,
        ...result,
      });
      stdout.writeln('   ok ${jsonEncode(result)}');
    } catch (error, stack) {
      stderr.writeln('   FAILED $error\n$stack');
      try {
        await _settle();
        await _shot('$name-failed');
      } catch (_) {}
      _results.add({
        'step': name,
        'passed': false,
        'ms': watch.elapsedMilliseconds,
        'error': '$error',
      });
    }
  }

  // --- The IDE ---------------------------------------------------------------

  Future<void> everything() async {
    await ideSteps();

    // --- An agent there ------------------------------------------------------

    final thread = workspace.startAgent(project);
    workspace
      ..select(thread)
      ..layout = WorkspaceLayout.chat;
    await _settle(frames: 20);

    await step('06-agent', () async {
      final session = thread.session;
      await _prepare(session);
      await _send(
        session,
        'In this project, read src/a.txt, then append a new line '
        '"agent-was-here" to it, then run `git status --short` and tell me '
        'its output.',
      );
      await _turnDone(session, seconds: 300);
      final there = await readThere(r'src\a.txt');
      if (!there.contains('agent-was-here')) {
        throw StateError('The file there was not changed: $there');
      }
      return {'there': there, 'transcript': _transcript(session)};
    });

    // --- The connection lost -------------------------------------------------

    await reconnect();

    // --- This machine's tools ------------------------------------------------

    await step('08-tools-off', () async {
      final names = await _tools();
      if (names.contains('local_run')) {
        throw StateError('local_run offered with the switch off');
      }
      return {'localTools': names.where((n) => n.startsWith('local')).toList()};
    });

    RemoteHostSettings.instance.setLocalAccess(host, true);
    final pushed = File(p.join(_out.path, 'push-me.txt'))
      ..writeAsStringSync('pushed from the Mac ${DateTime.now()}\n');
    final pulledInto = Directory(p.join(_out.path, 'pulled'))..createSync();
    // What only a command run on this machine leaves.
    final marker = p.join(_out.path, 'ran-here');
    final tools = workspace.startAgent(project);
    workspace
      ..select(tools)
      ..layout = WorkspaceLayout.chat;
    await _settle(frames: 20);

    await step('09-local-run-card', () async {
      final names = await _tools();
      if (!names.contains('local_run')) throw StateError('No local_run');
      final session = tools.session;
      await _prepare(session);
      await _send(
        session,
        'Use your tools for my computer, one after another: '
        '1) local_run the command `uname -s; sw_vers -productVersion; '
        'echo "home=\$HOME"; touch $marker` on my computer; '
        '2) local_push the local file ${pushed.path} to the remote path '
        'pushed.txt; '
        '3) local_pull the remote file src/a.txt into the local folder '
        '${pulledInto.path}. Then tell me what each returned.',
      );
      await _until(
        () => session.pendingInteraction != null,
        'the card asking to run here',
        seconds: 240,
      );
      final request = session.pendingInteraction! as ApprovalRequest;
      await _settle(frames: 20);
      return {
        'title': request.title,
        'reason': request.reason,
        'always': request.alwaysAllowLabel,
        'permissionMode': session.selected(KernelChoiceKind.permission),
      };
    });

    await step('10-local-tools', () async {
      final session = tools.session;
      final allow = _textElement('允许一次');
      if (allow == null) throw StateError('No allow button');
      await _clickElement(allow);
      await _turnDone(session, seconds: 300);
      final there = await readThere('pushed.txt');
      final pulled = File(p.join(pulledInto.path, 'a.txt'));
      final transcript = _transcript(session);
      if (!there.startsWith('pushed from the Mac')) {
        throw StateError('Not pushed: $there');
      }
      if (!pulled.existsSync()) throw StateError('Not pulled');
      if (!File(marker).existsSync()) {
        throw StateError('local_run did not run here: $transcript');
      }
      return {
        'ranHere': marker,
        'pushedThere': there,
        'pulledHere': pulled.readAsStringSync(),
        'transcript': transcript,
      };
    });

    // --- Ports ---------------------------------------------------------------

    await ports(tools, browser: true);
  }

  /// The project's files, edited and saved; a PowerShell terminal; Git;
  /// search.
  Future<void> ideSteps() async {
    await step('01-explorer', () async {
      await _until(
        () => _text('new.txt') != null && _text('src') != null,
        'the project files listed',
        seconds: 120,
      );
      final client = await SshHosts.instance[host].ready;
      return {
        'host': client.hello?.platform.os,
        'arch': client.hello?.platform.arch,
        'home': client.hello?.home,
      };
    });

    await step('02-edit-save', () async {
      await ide.openFile(at(r'src\a.txt'));
      await _until(() => _find<EditorSurface>() != null, 'the editor');
      await _settle();
      final surface = _find<EditorSurface>()!.widget as EditorSurface;
      final text = surface.controller.document.snapshot.text;
      final end = text.indexOf('hello world') + 'hello world'.length;
      await _input.click(_pointAt(end - 1));
      _input.press(LogicalKeyboardKey.end, physical: PhysicalKeyboardKey.end);
      await _input.type(' edited-in-e2e');
      await _settle();
      _save();
      String? saved;
      await _until(() {
        unawaited(readThere(r'src\a.txt').then((text) => saved = text));
        return saved?.contains('hello world edited-in-e2e') ?? false;
      }, 'the edit saved there');
      return {'there': saved};
    });

    await step('03-terminal', () async {
      ide.runCommand('workbench.action.terminal.new');
      final terminal = await _terminal();
      await _until(
        () => _screen(terminal).contains(r'PS C:\'),
        'PowerShell prompt',
        seconds: 60,
      );
      terminal.focus();
      await _settle();
      await _typeInTerminal(
        r'Write-Output "sum=$(20+22) $($PSVersionTable.PSEdition)"; '
        'Get-Location\n',
      );
      await _until(
        () => _screen(terminal).contains('sum=42'),
        'the command run',
      );
      return {'screen': _lastLines(terminal, 8)};
    });

    await step('04-git', () async {
      ide.runCommand('workbench.view.scm');
      await _until(
        () => _text('a.txt', inside: 'scm') != null || _text('a.txt') != null,
        'the change listed',
        seconds: 60,
      );
      await _settle();
      final row = _textElement('new.txt');
      final changed = _textElements('a.txt');
      // The changed file's row in the view, its diff opened.
      final target = changed.lastOrNull;
      if (target != null) await _clickElement(target);
      await _settle(frames: 30);
      final status = await (await SshHosts.instance[host].ready).git([
        'status',
        '--porcelain=v1',
      ], cwd: root);
      return {'untrackedListed': row != null, 'status': status.stdout};
    });

    await step('05-search', () async {
      ide.runCommand('workbench.action.findInFiles');
      await _settle();
      await _input.type('needle');
      _input.press(LogicalKeyboardKey.enter);
      await _until(
        () => _textElements('new.txt').length > 1 || _richContains('needle'),
        'search results',
        seconds: 60,
      );
      return {};
    });
  }

  /// The ssh under the session killed, as when the network drops: back at
  /// once, the terminal carrying on.
  Future<void> reconnect() async {
    await step('07-reconnect', () async {
      workspace.layout = WorkspaceLayout.ide;
      await _settle(frames: 20);
      final terminal = await _terminal();
      // The ssh forwarding the session's port (`-W 127.0.0.1:…`).
      Future<Set<String>> sshes() async {
        final found = Platform.isWindows
            ? await Process.run('powershell', [
                '-NoProfile',
                '-Command',
                r"""Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" | """
                    r"Where-Object { $_.CommandLine -like '*-W 127.0.0.1:*' } | "
                    r'ForEach-Object { $_.ProcessId }',
              ])
            : await Process.run('pgrep', ['-f', 'W 127[.]0[.]0[.]1:']);
        return {
          for (final line in (found.stdout as String).split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        };
      }

      final before = await sshes();
      // Its ssh gone, as when the network drops.
      final killed = Platform.isWindows
          ? await Process.run('taskkill', [
              '/F',
              for (final id in before) ...['/PID', id],
            ])
          : await Process.run('pkill', ['-f', 'W 127[.]0[.]0[.]1:']);
      var after = <String>{};
      var lost = false;
      final watch = Stopwatch()..start();
      void seen() {
        if (SshHosts.instance[host].state != SshHostState.connected) {
          lost = true;
        }
      }

      SshHosts.instance[host].addListener(seen);
      try {
        await _until(
          () {
            unawaited(sshes().then((now) => after = now));
            return SshHosts.instance[host].state == SshHostState.connected &&
                after.isNotEmpty &&
                after.intersection(before).isEmpty;
          },
          'connected again',
          seconds: 120,
        );
      } finally {
        SshHosts.instance[host].removeListener(seen);
      }
      final reconnectedMs = watch.elapsedMilliseconds;
      terminal.focus();
      await _settle();
      await _typeInTerminal(
        r'Write-Output "after=$(6*7)"'
        '\n',
      );
      await _until(
        () => _screen(terminal).contains('after=42'),
        'the terminal carried on',
        seconds: 60,
      );
      return {
        'pkill': killed.exitCode,
        'sshBefore': before.toList(),
        'sshAfter': after.toList(),
        'stateLeftConnected': lost,
        'reconnectedMs': reconnectedMs,
        'earlierKept': _screen(terminal).contains('sum=42'),
        'screen': _lastLines(terminal, 12),
      };
    });
  }

  /// A server there forwarded here as its address is printed, on the ports
  /// page; opened by the browser tool ([browser]); one here forwarded
  /// there by hand on the page, reached by curl there.
  Future<void> ports(AgentThread thread, {required bool browser}) async {
    // Another than the Mac's run's, where both are the same machine.
    final served = Platform.isWindows ? 8766 : 8765;
    workspace.layout = WorkspaceLayout.ide;
    await _settle(frames: 20);

    await step('11-auto-forward', () async {
      final terminal = await _terminal();
      terminal.focus();
      await _settle();
      await _typeInTerminal(
        r'Set-Content -Path served.html -Value "<title>From Windows</title>'
        r'<h1>Served on $env:COMPUTERNAME</h1>"; '
        'python -m http.server $served --bind 127.0.0.1\n',
      );
      await _until(
        () => PortForwards.instance
            .of(host)
            .any((forward) => forward.spec.port == served && forward.active),
        'port $served forwarded here',
        seconds: 60,
      );
      final forward = PortForwards.instance
          .of(host)
          .firstWhere((forward) => forward.spec.port == served);
      final body = await _get(forward.localPort!, '/served.html');
      if (!body.contains('From Windows')) throw StateError('Got: $body');
      return {
        'localUrl': forward.localUrl,
        'auto': forward.spec.auto,
        'body': body,
      };
    });

    await step('12-ports-page', () async {
      workspace
        ..select(thread)
        ..layout = WorkspaceLayout.chat;
      await _settle(frames: 10);
      final area = _find<AgentSidePanelArea>()!.widget as AgentSidePanelArea;
      area.panel.showSection(thread.session, SidePanelSection.ports);
      await _until(
        () =>
            _find<Widget>(
              where: (w) => w.key == const ValueKey('ports-page'),
            ) !=
            null,
        'the ports page',
      );
      await _settle(frames: 20);
      return {
        'forwards': [
          for (final forward in PortForwards.instance.of(host))
            {
              'port': forward.spec.port,
              'direction': forward.direction.name,
              'local': forward.localPort,
              'remote': forward.remotePort,
            },
        ],
      };
    });

    if (browser) {
      await step('13-browser-tool', () async {
        final chrome = Platform.environment['BAOCODE_E2E_CHROME'];
        if (chrome == null) throw StateError('BAOCODE_E2E_CHROME not set');
        await _startChrome(chrome);
        final bridge = BrowserBridge.instance;
        await _until(
          () => bridge.browsers.isNotEmpty,
          'the browser connected',
          seconds: 60,
        );
        final opened = await _callTool('browser_open', {
          'url': 'http://localhost:$served/served.html',
        });
        await Future<void>.delayed(const Duration(seconds: 2));
        final shot = p.join(_out.path, '13-browser-screen.png');
        await Process.run('screencapture', ['-x', shot]);
        final tab = RegExp(r'Tab \[(\d+)\]').firstMatch(opened)?[1];
        if (tab == null) throw StateError('No tab: $opened');
        final snapshot = await _callTool('browser_snapshot', {
          'tabId': int.parse(tab),
        });
        if (!snapshot.contains('Served on')) {
          throw StateError('The page there was not opened: $snapshot');
        }
        return {
          'open': opened,
          'snapshot': snapshot.length > 600
              ? snapshot.substring(0, 600)
              : snapshot,
          'screen': shot,
        };
      });
    }

    await step('14-here-to-there', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..write('hello from here ${request.uri.path}')
          ..close();
      });
      _keep.add(server);
      await _clickKey(const ValueKey('ports-add'));
      await _settle();
      await _clickElement(
        _textElement('本机 → ${RemoteLocation.hostName(host)}')!,
      );
      await _clickKey(const ValueKey('ports-port'));
      await _input.type('${server.port}');
      await _clickKey(const ValueKey('ports-forward'));
      await _until(
        () => PortForwards.instance
            .of(host)
            .any(
              (forward) =>
                  forward.direction == ForwardDirection.toRemote &&
                  forward.active,
            ),
        'forwarded there',
      );
      final forward = PortForwards.instance
          .of(host)
          .firstWhere(
            (forward) => forward.direction == ForwardDirection.toRemote,
          );
      final curl = await runThere(
        'curl.exe -s http://127.0.0.1:${forward.remotePort}/from-windows',
      );
      if (!curl.stdout.contains('hello from here /from-windows')) {
        throw StateError('curl there: ${curl.stdout} ${curl.stderr}');
      }
      return {
        'localPort': server.port,
        'remotePort': forward.remotePort,
        'curlThere': curl.stdout,
      };
    });
  }

  /// The app on Windows, the host a Windows one too (this machine, over
  /// its own sshd): no agent (no model's key here), the tools for this
  /// machine called as an agent calls them.
  Future<void> windowsClient() async {
    await ideSteps();
    await reconnect();
    await windowsTools();
    final thread = workspace.startAgent(project);
    await ports(thread, browser: false);
  }

  Future<void> windowsTools() async {
    await step('w08-tools-off', () async {
      final names = await _tools();
      if (names.contains('local_run')) {
        throw StateError('local_run offered with the switch off');
      }
      return {'localTools': names.where((n) => n.startsWith('local')).toList()};
    });
    RemoteHostSettings.instance.setLocalAccess(host, true);
    final marker = p.join(_out.path, 'ran-here');
    await step('w09-local-run', () async {
      final names = await _tools();
      if (!names.contains('local_run')) throw StateError('No local_run');
      final asked = <ApprovalRequest>[];
      final output = await _callTool(
        'local_run',
        {
          'command':
              r'$PSVersionTable.PSEdition; $env:COMPUTERNAME; '
              "Set-Content -Path '$marker' -Value ran-here",
        },
        ask: (request) async {
          asked.add(request);
          return ApprovalDecision.allowOnce;
        },
      );
      if (!File(marker).existsSync()) {
        throw StateError('Not run here: $output');
      }
      return {
        'card': {
          'title': asked.single.title,
          'reason': asked.single.reason,
          'always': asked.single.alwaysAllowLabel,
        },
        'output': output,
      };
    });
    await step('w10-push-pull', () async {
      final pushed = File(p.join(_out.path, 'push-me.txt'))
        ..writeAsStringSync('pushed from here ${DateTime.now()}\n');
      final into = Directory(p.join(_out.path, 'pulled'))..createSync();
      final push = await _callTool('local_push', {
        'local_path': pushed.path,
        'remote_path': 'pushed.txt',
      });
      final pull = await _callTool('local_pull', {
        'remote_path': r'src\a.txt',
        'local_path': into.path,
      });
      final there = await readThere('pushed.txt');
      final pulled = File(p.join(into.path, 'a.txt'));
      if (!there.startsWith('pushed from here')) {
        throw StateError('Not pushed: $there');
      }
      if (!pulled.existsSync()) throw StateError('Not pulled: $pull');
      return {
        'push': push,
        'pull': pull,
        'there': there,
        'pulled': pulled.readAsStringSync(),
      };
    });
  }

  /// After the app was quit and started again: the forwards made again as
  /// it connects; one stopped on the ports page; adb reached there.
  Future<void> restarted() async {
    final thread = workspace.startAgent(project);
    workspace
      ..select(thread)
      ..layout = WorkspaceLayout.chat;
    await step('20-restored', () async {
      await SshHosts.instance[host].ready;
      await _until(
        () => PortForwards.instance
            .of(host)
            .any((forward) => forward.spec.port == 8765 && forward.active),
        'port 8765 forwarded again',
        seconds: 90,
      );
      await _settle(frames: 10);
      final area = _find<AgentSidePanelArea>()!.widget as AgentSidePanelArea;
      area.panel.showSection(thread.session, SidePanelSection.ports);
      await _settle(frames: 20);
      final forward = PortForwards.instance
          .of(host)
          .firstWhere((forward) => forward.spec.port == 8765);
      final body = await _get(forward.localPort!, '/served.html');
      return {
        'kept': [
          for (final spec in RemoteHostSettings.instance.forwards(host))
            spec.toJson(),
        ],
        'body': body,
      };
    });

    await step('21-stopped', () async {
      await _clickKey(const ValueKey(('port-stop', 8765)));
      await _until(
        () => !PortForwards.instance
            .of(host)
            .any((forward) => forward.spec.port == 8765),
        'stopped',
      );
      return {
        'kept': [
          for (final spec in RemoteHostSettings.instance.forwards(host))
            spec.toJson(),
        ],
      };
    });

    await step('22-adb-there', () async {
      final client = await SshHosts.instance[host].ready;
      final environment = await PortForwards.instance.remoteEnvironment(host);
      final socket = environment['ADB_SERVER_SOCKET'];
      if (socket == null) throw StateError('No ADB_SERVER_SOCKET');
      final port = socket.split(':').last;
      // adb's own protocol, as `adb version` asks: the server here answers.
      final asked = await client.run('powershell', [
        '-NoProfile',
        '-Command',
        '\$c = New-Object Net.Sockets.TcpClient("127.0.0.1", $port); '
            '\$s = \$c.GetStream(); '
            '\$m = [Text.Encoding]::ASCII.GetBytes("000chost:version"); '
            '\$s.Write(\$m, 0, \$m.Length); Start-Sleep -Milliseconds 500; '
            '\$b = New-Object byte[] 64; \$n = \$s.Read(\$b, 0, 64); '
            '[Text.Encoding]::ASCII.GetString(\$b, 0, \$n)',
      ]);
      if (!asked.stdout.startsWith('OKAY')) {
        throw StateError('adb there: ${asked.stdout} ${asked.stderr}');
      }
      return {'ADB_SERVER_SOCKET': socket, 'answer': asked.stdout.trim()};
    });
  }

  // --- The host's system, its language servers -----------------------------

  /// The status bar's entry naming the host's system on hover; language
  /// servers installed there as the app offers (an npm one, a PyPI one),
  /// then a file's errors, hover and a definition in another file.
  Future<void> languageServers() async {
    await step('30-system', () async {
      await _until(
        () => SshHosts.instance[host].state == SshHostState.connected,
        'connected',
        seconds: 120,
      );
      await _settle(frames: 20);
      final entry = _textElements(
        '',
        where: (text) => text.startsWith('SSH: '),
      ).firstOrNull;
      if (entry == null) throw StateError('No SSH entry in the status bar');
      final box = entry.findRenderObject()! as RenderBox;
      _input.hover(box.localToGlobal(box.size.center(Offset.zero)));
      await _until(
        () => _richContains('Windows x64') || _richContains('Windows arm64'),
        'the system in its tooltip',
        seconds: 10,
      );
      return {'platform': SshHosts.instance[host].hello?.platform.toString()};
    });

    final client = await SshHosts.instance[host].ready;
    for (final (file, text) in [
      (
        r'src\lib.ts',
        'export function helper(n: number): number {\n  return n * 2;\n}\n',
      ),
      (
        r'src\main.ts',
        "import { helper } from './lib';\n"
            "const wrong: number = 'text';\n"
            'console.log(helper(wrong));\n',
      ),
      (
        r'src\main.py',
        'def twice(n: int) -> int:\n'
            '    return n * 2\n'
            '\n'
            'wrong: int = "text"\n'
            'print(twice(wrong))\n',
      ),
    ]) {
      await client.writeBytes(root, at(file), utf8.encode(text));
    }

    Future<Map<String, Object?>> serve(
      String file, {
      required LspPosition hoverAt,
      required LspPosition definitionAt,
      required String definedIn,
      String? goTo,
    }) async {
      _input.leave();
      final path = at(file);
      await ide.openFile(path);
      await _until(() => _find<EditorSurface>() != null, 'the editor');
      final languages = ide.widget.workspace.languages;
      if (languages == null) throw StateError('No language features');
      await _until(
        () => languages.statusFor(path).isNotEmpty,
        'a server for it',
        seconds: 60,
      );
      // Not there yet: installed there, as the notification's Install does.
      await _until(
        () => languages
            .statusFor(path)
            .every((s) => s.state != LanguageServerState.starting),
        'the server looked for',
        seconds: 60,
      );
      final first = languages.statusFor(path).first;
      final installed = first.state == LanguageServerState.missing;
      if (installed) {
        if (!first.installable) {
          throw StateError(
            '${first.serverId} missing, not installable '
            '(${first.missingRuntime ?? first.message})',
          );
        }
        await languages.install(first.serverId, path: path);
      }
      await _until(
        () => languages.diagnosticsFor(path).isNotEmpty,
        'its errors',
        seconds: 300,
      );
      final hover = await languages.hover(path, hoverAt);
      final definition = await languages.definition(path, definitionAt);
      final target = [
        for (final location in definition)
          Uri.parse(location.uri).toFilePath(windows: true),
      ];
      final expected = at(definedIn).toLowerCase();
      if (!target.any((path) => path.toLowerCase() == expected)) {
        throw StateError('Definition at $target, not $expected');
      }
      if (hover == null) throw StateError('No hover');
      String? opened;
      if (goTo != null) {
        // Go to Definition from the editor: the file there opened once,
        // spelled as the explorer spells it.
        final surface = _find<EditorSurface>()!.widget as EditorSurface;
        final text = surface.controller.document.snapshot.text;
        await _input.click(_pointAt(text.indexOf(goTo) + 2));
        ide.runCommand('editor.action.revealDefinition');
        final want = at(definedIn);
        await _until(
          () => ide.widget.workspace.active?.path == want,
          'the definition opened',
          seconds: 30,
        );
        opened = ide.widget.workspace.active?.path;
        final copies = ide.widget.workspace.documents
            .where((doc) => doc.path.toLowerCase() == want.toLowerCase())
            .length;
        if (copies != 1) throw StateError('$want open $copies times');
      }
      ide.runCommand('workbench.actions.view.problems');
      await _settle(frames: 20);
      return {
        'server': first.serverId,
        'installedNow': installed,
        'diagnostics': [
          for (final diagnostic in languages.diagnosticsFor(path))
            diagnostic.message,
        ],
        'hover': hover.markdown,
        'definition': target,
        'opened': ?opened,
      };
    }

    await step(
      '31-lsp-typescript',
      () => serve(
        r'src\main.ts',
        hoverAt: const LspPosition(1, 8),
        definitionAt: const LspPosition(2, 14),
        definedIn: r'src\lib.ts',
        goTo: 'helper(wrong)',
      ),
    );
    await step(
      '32-lsp-python',
      () => serve(
        r'src\main.py',
        hoverAt: const LspPosition(4, 8),
        definitionAt: const LspPosition(4, 8),
        definedIn: r'src\main.py',
      ),
    );
  }

  // --- Helpers ---------------------------------------------------------------

  final List<Object> _keep = [];

  Future<TerminalInstance> _terminal() async {
    await _until(() => _find<TerminalPanel>() != null, 'the terminal panel');
    final panel = _find<TerminalPanel>()!.widget as TerminalPanel;
    await _until(() => panel.terminals.active != null, 'a terminal');
    return panel.terminals.active!;
  }

  /// The model and the permissions of an agent here: OpenCode's, full
  /// access (which local_run asks under all the same).
  Future<void> _prepare(ChatSession session) async {
    await _until(() => session.models != null, 'the models', seconds: 60);
    final model =
        Platform.environment['BAOCODE_E2E_MODEL'] ?? '@provider-3/glm-5.3';
    final models = session.models!;
    final option = models.options.where((o) => o.id == model).firstOrNull;
    if (option == null) {
      throw StateError(
        'No $model among ${models.options.map((o) => o.id).toList()}',
      );
    }
    models.onSelected(option);
    if (session.permissions case final permissions?) {
      final bypass = permissions.options
          .where((o) => o.id == 'bypassPermissions')
          .firstOrNull;
      if (bypass != null) permissions.onSelected(bypass);
    }
    await _settle(frames: 10);
  }

  /// Types [text] in [session]'s composer and sends it with Enter.
  Future<void> _send(ChatSession session, String text) async {
    await _until(
      () =>
          _find<ChatComposer>(where: (c) => identical(c.session, session)) !=
          null,
      'the composer',
    );
    final composer = _find<ChatComposer>(
      where: (c) => identical(c.session, session),
    )!;
    final box = composer.findRenderObject()! as RenderBox;
    await _input.click(box.localToGlobal(box.size.center(Offset.zero)));
    await _settle();
    await _input.type(text, every: const Duration(milliseconds: 4));
    await _settle();
    _input.press(LogicalKeyboardKey.enter);
    await _until(() => session.isStreaming, 'the turn started', seconds: 60);
  }

  Future<void> _turnDone(ChatSession session, {int seconds = 240}) async {
    await _until(
      () => !session.isStreaming && session.pendingInteraction == null,
      'the turn done',
      seconds: seconds,
    );
  }

  Future<List<String>> _tools() async {
    final response = await ClaudeSdkTools.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    }, ClaudeSdkCall(cwd: location));
    return [
      for (final tool in ((response['result']! as Map)['tools']! as List))
        (tool as Map)['name'] as String,
    ];
  }

  Future<String> _callTool(
    String name,
    Map<String, Object?> input, {
    ClaudeSdkAsk? ask,
  }) async {
    final response = await ClaudeSdkTools.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': input},
    }, ClaudeSdkCall(cwd: location, ask: ask));
    final result = response['result']! as Map;
    final text = [
      for (final part in result['content']! as List)
        if ((part as Map)['text'] case final String text) text,
    ].join('\n');
    if (result['isError'] == true) throw StateError('$name: $text');
    return text;
  }

  Future<void> _startChrome(String wrapper) async {
    final profile = Directory(p.join(_out.path, 'chrome-profile'))
      ..createSync(recursive: true);
    final hosts = Directory(p.join(profile.path, 'NativeMessagingHosts'))
      ..createSync(recursive: true);
    final hostBinary = p.join(
      p.dirname(Platform.resolvedExecutable),
      'baocode-browser-host',
    );
    File(p.join(hosts.path, '${BrowserBridge.hostName}.json'))
        .writeAsStringSync(
          jsonEncode({
            'name': BrowserBridge.hostName,
            'description': 'BaoCode',
            'path': hostBinary,
            'type': 'stdio',
            'allowed_origins': [
              for (final id in BrowserBridge.extensionIds)
                'chrome-extension://$id/',
            ],
          }),
        );
    final extension = Platform.environment['BAOCODE_E2E_EXTENSION']!;
    final chrome = await Process.start(
      wrapper,
      [
        '--user-data-dir=${profile.path}',
        '--load-extension=$extension',
        '--no-first-run',
        '--no-default-browser-check',
        '--window-size=1100,750',
        'about:blank',
      ],
      environment: {'TMPDIR': sockets.path, 'XDG_RUNTIME_DIR': sockets.path},
    );
    _keep.add(chrome);
    unawaited(chrome.stdout.drain<void>());
    unawaited(chrome.stderr.drain<void>());
  }

  Future<void> _clickKey(Key key) async {
    await _until(
      () => _find<Widget>(where: (w) => w.key == key) != null,
      'the control $key',
    );
    await _clickElement(_find<Widget>(where: (w) => w.key == key)!);
  }
}

class IdeGitOutputLike {
  IdeGitOutputLike(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

List<ChatItem> _items(ChatSession session) => [
  for (var i = 0; i < session.itemCount; i++) session.itemAt(i),
];

List<Map<String, Object?>> _transcript(ChatSession session) => [
  for (final item in _items(session))
    switch (item) {
      UserMessageItem() => {'user': _cut(item.text)},
      AssistantTextItem(:final text) => {'assistant': _cut(text)},
      ToolCallItem() => {
        'tool': item.tool ?? item.kind.name,
        'target': _cut(item.target),
        'status': item.status.name,
        if (item.output case final output?) 'output': _cut(output),
      },
      NoticeItem(:final text) => {'notice': _cut(text)},
      _ => {'item': item.runtimeType.toString()},
    },
];

String _cut(String text, [int most = 800]) =>
    text.length <= most ? text : '${text.substring(0, most)}…';

/// [path] of a server here on [port], over a socket.
Future<String> _get(int port, String path) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.write('GET $path HTTP/1.0\r\nHost: localhost\r\n\r\n');
  await socket.flush();
  final response = await utf8.decoder.bind(socket).join();
  socket.destroy();
  final body = response.indexOf('\r\n\r\n');
  return body < 0 ? response : response.substring(body + 4);
}

/// The terminal's lines, as on its screen and above.
String _screen(TerminalInstance terminal) {
  final lines = terminal.terminal.buffer.lines;
  return [
    for (var i = 0; i < lines.length; i++)
      lines.get(i)?.translateToString(true) ?? '',
  ].join('\n');
}

String _lastLines(TerminalInstance terminal, int count) {
  final lines = _screen(terminal)
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
  return lines.skip(lines.length > count ? lines.length - count : 0).join('\n');
}

Element? _find<T extends Widget>({bool Function(T widget)? where}) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (element.widget case final T widget when where?.call(widget) ?? true) {
      found = element;
    } else {
      element.visitChildren(visit);
    }
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

/// Every [RichText] element showing [text] exactly (or text [where]
/// accepts), on screen.
List<Element> _textElements(String text, {bool Function(String text)? where}) {
  final found = <Element>[];
  void visit(Element element) {
    if (element.widget case final RichText rich
        when (where ?? (shown) => shown == text)(rich.text.toPlainText())) {
      final box = element.findRenderObject();
      if (box is RenderBox && box.hasSize && box.attached) found.add(element);
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Element? _textElement(String text) => _textElements(text).firstOrNull;

Element? _text(String text, {String? inside}) => _textElement(text);

bool _richContains(String text) {
  var found = false;
  void visit(Element element) {
    if (found) return;
    if (element.widget case final RichText rich
        when rich.text.toPlainText().contains(text)) {
      found = true;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

Future<void> _clickElement(Element element) async {
  final box = element.findRenderObject()! as RenderBox;
  await _input.click(box.localToGlobal(box.size.center(Offset.zero)));
  await _settle();
}

Offset _pointAt(int offset) {
  final element = _find<EditorSurface>()! as StatefulElement;
  final rect = (element.state as EditorSurfaceView).rangeRectAt(
    offset,
    offset + 1,
  );
  if (rect == null) throw StateError('Code at $offset is not visible');
  return (element.findRenderObject()! as RenderBox).localToGlobal(rect.center);
}

Future<void> _until(
  bool Function() ready,
  String description, {
  int seconds = 45,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(description);
    }
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _settle({int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<void> _shot(String name) async {
  final view = RendererBinding.instance.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  // The root layer scales to the display's pixels: all of them.
  final image = await layer.toImage(
    Offset.zero & view.flutterView.physicalSize,
    pixelRatio: 1,
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('No screenshot bytes');
  File(p.join(_out.path, '$name.png'))
      .writeAsBytesSync(bytes.buffer.asUint8List());
}

/// Types [text] into the terminal that has the focus, as the input method
/// commits what is typed (the terminal's keys alone write no text); a new
/// line is Enter.
Future<void> _typeInTerminal(String text) async {
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    if (character == '\n') {
      _input.press(LogicalKeyboardKey.enter);
    } else {
      final client = _focusedClient();
      if (client == null) throw StateError('No terminal has the focus');
      final value = client.currentTextEditingValue ?? TextEditingValue.empty;
      final typed = value.text + character;
      TextInput.updateEditingValue(
        TextEditingValue(
          text: typed,
          selection: TextSelection.collapsed(offset: typed.length),
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 4));
  }
}

TextInputClient? _focusedClient() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  if (context case StatefulElement(:final TextInputClient state)) return state;
  TextInputClient? found;
  context.visitAncestorElements((element) {
    if (element case StatefulElement(:final TextInputClient state)) {
      found = state;
      return false;
    }
    return true;
  });
  return found;
}

/// Save: Cmd+S on macOS, Ctrl+S elsewhere.
void _save() {
  if (!Platform.isWindows && !Platform.isLinux) {
    _input.press(
      LogicalKeyboardKey.keyS,
      physical: PhysicalKeyboardKey.keyS,
      meta: true,
    );
    return;
  }
  _control(down: true);
  try {
    _input.press(LogicalKeyboardKey.keyS, physical: PhysicalKeyboardKey.keyS);
  } finally {
    _control(down: false);
  }
}

/// Control held ([down]) or let go, where the engine's keys go.
void _control({required bool down}) {
  final event = down
      ? KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        )
      : KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        );
  HardwareKeyboard.instance.handleKeyEvent(event);
  // ignore: deprecated_member_use
  ServicesBinding.instance.keyEventManager.keyMessageHandler?.call(
    // ignore: deprecated_member_use
    KeyMessage([event], null),
  );
}
