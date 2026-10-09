/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// `Terminal.shellIntegration` for extensions: which terminals have shell
// integration, their cwd and environment, the commands run in them
// (`onDidStartTerminalShellExecution`, `onDidEndTerminalShellExecution`,
// `TerminalShellExecution.read()`) and `shellIntegration.executeCommand`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadTerminalShellIntegration.ts.
//
// Deviation: no shell type is known, so only
// `onTerminalShellIntegration:*` is activated.

import 'dart:async';
import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/terminal/shell_integration/capabilities/capabilities.dart';
import '../../ide/terminal/shell_integration/capabilities/command_detection/terminal_command.dart';
import '../../ide/terminal/terminal_instance.dart';
import '../../ide/terminal/terminal_service.dart';
import '../commands/extension_command_registry.dart';
import 'main_thread_context.dart';
import 'main_thread_terminal_service.dart';

final class MainThreadTerminalShellIntegration
    extends MainThreadTerminalShellIntegrationUnsupported {
  MainThreadTerminalShellIntegration(
    this._terminals,
    RpcProtocol rpc, {
    this._activation,
  }) : _proxy = ExtHostTerminalShellIntegrationProxy(rpc) {
    _terminals.allInstances.forEach(_watch);
    _created = _terminals.onDidCreate.listen(_watch);
    _disposed = _terminals.onDidDispose.listen((instance) {
      _unwatch(instance);
      _send(_proxy.$closeTerminal(instance.id));
    });
  }

  final TerminalService _terminals;
  final ExtHostTerminalShellIntegrationProxy _proxy;
  final CommandActivation? _activation;
  late final StreamSubscription<TerminalInstance> _created;
  late final StreamSubscription<TerminalInstance> _disposed;
  final _watched = <TerminalInstance, List<void Function()>>{};

  static RpcActor customer(MainThreadContext context) {
    final actor = MainThreadTerminalShellIntegration(
      context.service<ExtensionTerminals>().service,
      context.rpc,
      activation: context.maybeService<CommandActivation>(),
    );
    context.onDispose(actor.dispose);
    return MainThreadTerminalShellIntegrationActor(actor);
  }

  void _send(Future<void> call) => unawaited(call.catchError((Object _) {}));

  void _watch(TerminalInstance instance) {
    if (_watched.containsKey(instance)) return;
    final stops = _watched[instance] = [];
    if (instance.shellIntegration != null) {
      _attach(instance, stops);
    } else {
      final ready = instance.onShellIntegrationReady.listen(
        (_) => _attach(instance, stops),
      );
      stops.add(() => unawaited(ready.cancel()));
    }
  }

  void _unwatch(TerminalInstance instance) {
    for (final stop in _watched.remove(instance) ?? const []) {
      stop();
    }
  }

  void _attach(TerminalInstance instance, List<void Function()> stops) {
    final integration = instance.shellIntegration!;
    final capabilities = integration.capabilities;
    final id = instance.id;
    final supportsExecuteCommand = instance.config?.type != 'Task';

    void enable() {
      unawaited(
        _activation
            ?.activateByEvent('onTerminalShellIntegration:*')
            .catchError((Object _) {}),
      );
      _send(_proxy.$shellIntegrationChange(id, supportsExecuteCommand));
      final cwd = capabilities.get(TerminalCapability.cwdDetection)?.getCwd();
      if (cwd != null) _send(_proxy.$cwdChange(id, cwd));
    }

    // The commands' events, once there is command detection; their
    // output from the process's data, between the command's executed and
    // finished sequences.
    final capture = ShellExecutionCapture();
    var started = false;
    Timer? flush;
    void flushData() {
      flush?.cancel();
      flush = null;
      final data = capture.take();
      if (data.isNotEmpty) _send(_proxy.$shellExecutionData(id, data));
    }

    final output = const Utf8Decoder(allowMalformed: true)
        .bind(instance.output)
        .listen((chunk) {
          capture.add(chunk);
          // `TerminalShellExecution.read()`: the output, every 50ms.
          if (started && capture.hasData) {
            flush ??= Timer(const Duration(milliseconds: 50), flushData);
          }
        });
    stops.add(() {
      flush?.cancel();
      unawaited(output.cancel());
    });

    PartialTerminalCommand? current;
    void attachCommandDetection(ICommandDetectionCapability detection) {
      enable();
      final executed = detection.onCommandExecuted((command) {
        // Command detection may fire twice for one command.
        if (identical(command, current)) return;
        current = command;
        started = true;
        _send(
          _proxy.$shellExecutionStart(
            id,
            supportsExecuteCommand,
            command.command ?? '',
            _confidence(command.commandLineConfidence),
            command.isTrusted ?? false,
            command.cwd,
          ),
        );
      });
      final finished = detection.onCommandFinished((command) {
        current = null;
        // Once the data parsed with the finish is out.
        Timer.run(() {
          if (started) flushData();
          started = false;
          capture.take();
          _send(
            _proxy.$shellExecutionEnd(
              id,
              command.command,
              _confidence(command.commandLineConfidence),
              command.isTrusted,
              command.exitCode,
            ),
          );
        });
      });
      stops
        ..add(executed.dispose)
        ..add(finished.dispose);
    }

    if (capabilities.get(TerminalCapability.commandDetection)
        case final detection?) {
      attachCommandDetection(detection);
    }
    final added = capabilities.onDidAddCommandDetectionCapability(
      attachCommandDetection,
    );
    final cwd = integration.onDidChangeCwd(
      (cwd) => _send(_proxy.$cwdChange(id, cwd)),
    );
    void attachEnv(IShellEnvDetectionCapability capability) {
      final listener = capability.onDidChangeEnv((env) {
        final value = env.value;
        if (value == null) return;
        _send(
          _proxy.$shellEnvChange(id, value.keys.toList(), [
            for (final v in value.values) v ?? '',
          ], env.isTrusted),
        );
      });
      stops.add(listener.dispose);
    }

    if (capabilities.get(TerminalCapability.shellEnvDetection)
        case final env?) {
      attachEnv(env);
    }
    final envAdded = capabilities.createOnDidAddCapabilityOfTypeEvent(
      TerminalCapability.shellEnvDetection,
    )(attachEnv);
    stops.addAll([added.dispose, cwd.dispose, envAdded.dispose]);
  }

  /// `TerminalShellExecutionCommandLineConfidence`.
  static int _confidence(String? confidence) => switch (confidence) {
    'high' => 2,
    'medium' => 1,
    _ => 0,
  };

  @override
  Future<void> $executeCommand(num terminalId, String commandLine) async =>
      _terminals.instanceFromId(terminalId.toInt())?.runCommand(commandLine);

  void dispose() {
    unawaited(_created.cancel());
    unawaited(_disposed.cancel());
    for (final instance in [..._watched.keys]) {
      _unwatch(instance);
    }
  }
}

/// A command's output in a terminal's data: what comes between the shell
/// integration's "executed" and "finished" sequences (OSC 633 or 133, `C`
/// and `D`), sequences in it included, whichever chunks they come in.
final class ShellExecutionCapture {
  final _buffer = StringBuffer();
  String _carry = '';
  bool _capturing = false;

  /// Whether a command's output is being read.
  bool get capturing => _capturing;

  bool get hasData => _buffer.isNotEmpty;

  /// What was read since the last [take].
  String take() {
    final data = _buffer.toString();
    _buffer.clear();
    return data;
  }

  void add(String chunk) {
    final text = _carry + chunk;
    _carry = '';
    var i = 0;
    while (i < text.length) {
      final escape = text.indexOf('\x1b', i);
      if (escape < 0 || escape == text.length - 1) {
        // A lone ESC at the end may start a sequence.
        final until = escape < 0 ? text.length : escape;
        if (_capturing) _buffer.write(text.substring(i, until));
        if (escape >= 0) _carry = '\x1b';
        return;
      }
      if (text[escape + 1] != ']') {
        if (_capturing) _buffer.write(text.substring(i, escape + 2));
        i = escape + 2;
        continue;
      }
      final (end, length) = _terminator(text, escape + 2);
      if (end < 0) {
        if (_capturing) _buffer.write(text.substring(i, escape));
        // An unfinished sequence waits for the next chunk; a runaway one is
        // text.
        final rest = text.substring(escape);
        if (rest.length < 4096) {
          _carry = rest;
        } else if (_capturing) {
          _buffer.write(rest);
        }
        return;
      }
      final body = text.substring(escape + 2, end);
      final after = end + length;
      if (_capturing) {
        if (_isFinished(body)) {
          _buffer.write(text.substring(i, escape));
          _capturing = false;
        } else {
          _buffer.write(text.substring(i, after));
        }
      } else if (_isExecuted(body)) {
        _capturing = true;
      }
      i = after;
    }
  }

  /// Where the OSC sequence from [from] ends (BEL or ST), and the
  /// terminator's length; -1 when not in [text].
  static (int, int) _terminator(String text, int from) {
    final bel = text.indexOf('\x07', from);
    final st = text.indexOf('\x1b\\', from);
    if (bel < 0 && st < 0) return (-1, 0);
    if (st < 0 || (bel >= 0 && bel < st)) return (bel, 1);
    return (st, 2);
  }

  static bool _isExecuted(String body) =>
      body == '633;C' || body == '133;C' || body.startsWith('133;C;');

  static bool _isFinished(String body) =>
      body == '633;D' ||
      body.startsWith('633;D;') ||
      body == '133;D' ||
      body.startsWith('133;D;');
}
