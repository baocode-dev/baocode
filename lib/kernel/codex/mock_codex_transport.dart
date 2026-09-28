import 'dart:async';

import '../mock/mock_script.dart';
import 'codex_transport.dart';

/// Plays [MockScript] as `codex app-server` would: a thread, turns, items
/// that start, stream and complete, and an approval before running a
/// command. Not the server: shapes follow its protocol closely enough to
/// drive the adapter.
class MockCodexTransport implements CodexTransport {
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast(sync: true);

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  static const _threadId = 'thr_mock';
  static const _contextWindow = 272000;

  int _items = 0;
  int _turns = 0;
  int _serverRequests = 0;
  int _tokens = 18400;

  Object? _run;
  String? _turnId;
  final Map<String, Completer<String>> _approvals = {};

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add(message);
  }

  void _notify(String method, Map<String, Object?> params) =>
      _emit({'method': method, 'params': params});

  void _respond(Object? id, Map<String, Object?> result) =>
      _emit({'id': id, 'result': result});

  @override
  void write(Map<String, Object?> message) {
    final id = message['id'];
    final method = message['method'] as String?;
    if (method == null) {
      // The client's answer to one of our requests.
      final decision = (message['result'] as Map?)?['decision'] as String?;
      _approvals.remove('$id')?.complete(decision ?? 'decline');
      return;
    }
    final params = (message['params'] as Map?) ?? const {};
    switch (method) {
      case 'initialize':
        _respond(id, {'userAgent': 'codex-mock'});
      case 'thread/start':
        _respond(id, {
          'thread': {'id': _threadId},
        });
      case 'thread/rollback':
        _respond(id, {
          'thread': {'id': _threadId},
        });
      case 'turn/start':
        final turnId = 'turn_${++_turns}';
        _respond(id, {
          'turn': {'id': turnId, 'status': 'inProgress'},
        });
        final input = (params['input'] as List).first as Map;
        final readOnly =
            (params['sandboxPolicy'] as Map?)?['type'] == 'readOnly';
        final run = Object();
        _run = run;
        _turnId = turnId;
        unawaited(_script(run, turnId, input['text'] as String, readOnly));
      case 'turn/interrupt':
        _respond(id, {});
        if (_turnId case final turnId? when _run != null) {
          _run = null;
          _approvals.clear();
          _completeTurn(turnId, 'interrupted');
        }
    }
  }

  Future<bool> _wait(Object run, int milliseconds) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    return identical(_run, run);
  }

  String _itemId() => 'item_${++_items}';

  Future<bool> _reasoning(Object run, String text) async {
    final id = _itemId();
    _notify('item/started', {
      'item': {'type': 'reasoning', 'id': id, 'summary': <String>[]},
    });
    if (!await _wait(run, MockScript.thinkingDelay)) return false;
    for (var start = 0; start < text.length;) {
      final end = (start + MockScript.thinkingChunk).clamp(0, text.length);
      _notify('item/reasoning/summaryTextDelta', {
        'itemId': id,
        'delta': text.substring(start, end),
      });
      _tokens += 2;
      start = end;
      if (!await _wait(run, MockScript.thinkingChunkMs)) return false;
    }
    _notify('item/completed', {
      'item': {
        'type': 'reasoning',
        'id': id,
        'summary': [text],
      },
    });
    return true;
  }

  Future<bool> _message(Object run, String text) async {
    final id = _itemId();
    _notify('item/started', {
      'item': {'type': 'agentMessage', 'id': id, 'text': ''},
    });
    for (var start = 0; start < text.length;) {
      final end = (start + MockScript.textChunk).clamp(0, text.length);
      _notify('item/agentMessage/delta', {
        'itemId': id,
        'delta': text.substring(start, end),
      });
      _tokens += 2;
      start = end;
      if (!await _wait(run, MockScript.textChunkMs)) return false;
    }
    _notify('item/completed', {
      'item': {'type': 'agentMessage', 'id': id, 'text': text},
    });
    return true;
  }

  void _command(
    String command,
    List<Map<String, Object?>> actions,
    String output, {
    int exitCode = 0,
  }) {
    final id = _itemId();
    final item = {
      'type': 'commandExecution',
      'id': id,
      'command': command,
      'cwd': '.',
      'commandActions': actions,
    };
    _notify('item/started', {
      'item': {...item, 'status': 'inProgress'},
    });
    _notify('item/completed', {
      'item': {
        ...item,
        'status': 'completed',
        'aggregatedOutput': output,
        'exitCode': exitCode,
      },
    });
    _tokens += 40 + output.length ~/ 2;
  }

  void _tokenUsage() {
    _notify('thread/tokenUsage/updated', {
      'threadId': _threadId,
      'tokenUsage': {
        'total': {'totalTokens': _tokens},
        'modelContextWindow': _contextWindow,
      },
    });
  }

  void _completeTurn(String turnId, String status) {
    _tokenUsage();
    _notify('turn/completed', {
      'threadId': _threadId,
      'turn': {'id': turnId, 'status': status},
    });
  }

  Future<void> _script(
    Object run,
    String turnId,
    String prompt,
    bool readOnly,
  ) async {
    _notify('turn/started', {
      'threadId': _threadId,
      'turn': {'id': turnId, 'status': 'inProgress'},
    });
    _tokens += 60 + prompt.length * 2;
    final target =
        RegExp(r'@(\S+)').firstMatch(prompt)?.group(1) ??
        'lib/chat/chat_screen.dart';
    if (!await _reasoning(run, MockScript.thoughtFor(target))) return;
    if (!await _wait(run, 500)) return;
    _command("sed -n '1,200p' $target", [
      {'type': 'read', 'name': target.split('/').last, 'path': target},
    ], "import 'package:flutter/material.dart';\n…");
    if (!await _wait(run, 350)) return;
    _command('rg -n ${MockScript.searchPattern} lib test', [
      {'type': 'search', 'query': MockScript.searchPattern, 'path': 'lib'},
    ], MockScript.searchMatches.join('\n'));
    if (!await _wait(run, 400)) return;

    if (readOnly) {
      if (!await _message(run, MockScript.askAnswer)) return;
      _finish(run, turnId);
      return;
    }

    if (!await _message(run, '先把输入框改成随内容增高，最多 8 行：')) return;
    if (!await _wait(run, 700)) return;
    final changeId = _itemId();
    final changes = [
      for (final edit in MockScript.edits)
        {
          'path': edit.path,
          'kind': {'type': 'update'},
          'diff':
              '@@ -${edit.start} +${edit.start} @@\n${edit.lines.join('\n')}',
        },
    ];
    _notify('item/started', {
      'item': {
        'type': 'fileChange',
        'id': changeId,
        'changes': changes,
        'status': 'inProgress',
      },
    });
    _notify('item/completed', {
      'item': {
        'type': 'fileChange',
        'id': changeId,
        'changes': changes,
        'status': 'completed',
      },
    });

    // Running the tests needs leave: the server asks, and waits.
    final approvalId = 'srv_${++_serverRequests}';
    final approval = Completer<String>();
    _approvals[approvalId] = approval;
    final commandItem = _itemId();
    _emit({
      'id': approvalId,
      'method': 'item/commandExecution/requestApproval',
      'params': {
        'threadId': _threadId,
        'turnId': turnId,
        'itemId': commandItem,
        'command': MockScript.testCommand,
        'reason': 'Run the tests to check the change',
      },
    });
    final decision = await approval.future;
    if (!identical(_run, run)) return;
    if (decision == 'decline') {
      if (!await _message(run, MockScript.codexDeclined)) return;
      _finish(run, turnId);
      return;
    }
    final item = {
      'type': 'commandExecution',
      'id': commandItem,
      'command': MockScript.testCommand,
      'cwd': '.',
      'commandActions': [
        {'type': 'unknown', 'command': MockScript.testCommand},
      ],
    };
    _notify('item/started', {
      'item': {...item, 'status': 'inProgress'},
    });
    if (!await _wait(run, 1500)) return;
    _notify('item/completed', {
      'item': {
        ...item,
        'status': 'completed',
        'aggregatedOutput': MockScript.testOutput,
        'exitCode': 0,
      },
    });
    if (!await _wait(run, 300)) return;
    if (!await _message(run, MockScript.codexSummary)) return;
    _finish(run, turnId);
  }

  void _finish(Object run, String turnId) {
    if (!identical(_run, run)) return;
    _run = null;
    _completeTurn(turnId, 'completed');
  }

  @override
  void close() {
    _run = null;
    _approvals.clear();
    _out.close();
  }
}
