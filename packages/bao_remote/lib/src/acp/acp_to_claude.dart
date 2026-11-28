/// What `agy acp` reports of its tool calls, as Claude Code would have made
/// them: a conversation on Antigravity is kept as Claude Code keeps its own
/// (one jsonl), its calls as Claude Code's tools (`Bash`, `Edit`, `Read`…),
/// so that the chat shows them as it shows those, and a model of another
/// upstream reads them on as its own.
library;

import 'dart:convert';

/// A tool call as agy reported it so far: `tool_call`, then its updates.
class AcpToolCall {
  AcpToolCall(this.id);

  final String id;
  String? name;
  String? kind;
  String? title;
  String? status;
  Map<String, Object?> input = const {};
  Object? rawOutput;
  List<Object?> content = const [];
  String? location;

  bool get running =>
      status == null || status == 'pending' || status == 'in_progress';

  bool get failed => status == 'failed';

  void merge(Map<String, Object?> update) {
    if (update['name'] case final String value) name = value;
    if (update['kind'] case final String value) kind = value;
    if (update['title'] case final String value) title = value;
    if (update['status'] case final String value) status = value;
    if (update['rawInput'] case final Map<Object?, Object?> raw) {
      input = raw.cast<String, Object?>();
    } else if (update['args'] case final Map<Object?, Object?> raw) {
      input = raw.cast<String, Object?>();
    }
    if (update.containsKey('rawOutput')) rawOutput = update['rawOutput'];
    if (update['content'] case final List<Object?> content) {
      this.content = content;
    }
    if (update['locations'] case [{'path': final String path}, ...]) {
      location = path;
    }
  }

  /// What it returned: its text content, else its raw output's.
  String? get output {
    final texts = [
      for (final block in content)
        if (block case {'type': 'content', 'content': {'text': final String t}})
          t,
    ];
    if (texts.isNotEmpty) return texts.join('\n');
    return switch (rawOutput) {
      {'output': final String text} when text.isNotEmpty => text,
      {'result': final String text} when text.isNotEmpty => text,
      {'text': final String text} when text.isNotEmpty => text,
      {'message': final String text} when text.isNotEmpty => text,
      final String text when text.isNotEmpty => text,
      final Map<Object?, Object?> map when _hasMeaningfulOutputMap(map) =>
        const JsonEncoder.withIndent('  ').convert(map),
      final List<Object?> list when list.isNotEmpty =>
        const JsonEncoder.withIndent('  ').convert(list),
      _ => null,
    };
  }

  static bool _hasMeaningfulOutputMap(Map<Object?, Object?> map) {
    for (final entry in map.entries) {
      final key = '${entry.key}';
      if (key == 'exit_code' || key == 'exitCode') continue;
      if (entry.value != null && '${entry.value}'.isNotEmpty) return true;
    }
    return false;
  }

  /// Its edit, as reported: the file, what was there (none for a new
  /// file) and what is now.
  ({String path, String? oldText, String newText})? get diff {
    for (final block in content) {
      if (block case {
        'type': 'diff',
        'path': final String path,
        'newText': final String newText,
      }) {
        return (
          path: path,
          oldText: (block as Map)['oldText'] as String?,
          newText: newText,
        );
      }
    }
    return null;
  }

  /// The file it is about, as its input or its locations name it.
  String? get path =>
      _string(input['Path']) ??
      _string(input['AbsolutePath']) ??
      _string(input['File']) ??
      _string(input['TargetFile']) ??
      location;

  /// What agy said it does (`toolSummary`), if it did.
  String? get summary => _string(input['toolSummary']);
}

/// A call's id as Claude's API takes one (`toolu_…`, letters, digits, `_`
/// and `-`): agy's own, made to fit.
String claudeToolId(String acpId) =>
    'toolu_agy_${acpId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

/// The MCP tool [call] reaches through call_mcp_tool, if it is one.
({String server, String tool})? agyMcpCall(AcpToolCall call) {
  if (call.name != 'call_mcp_tool' &&
      !(call.title?.startsWith('MCP Tool ') ?? false)) {
    return null;
  }
  return switch (call.input) {
    {'ServerName': final String server, 'ToolName': final String tool}
        when server.isNotEmpty && tool.isNotEmpty =>
      (server: server, tool: tool),
    _ => null,
  };
}

/// update_steps' input as TodoWrite's.
Map<String, Object?> _steps(Map<String, Object?> input) => {
  'todos': [
    for (final step in input['steps'] as List? ?? const [])
      if (step case {'title': final String title})
        _todo(title, switch (step['status']) {
          'done' || 'completed' => 'completed',
          final String status => status,
          _ => null,
        }),
  ],
};

/// A todo of TodoWrite's: [status] one of its own, else pending.
Map<String, Object?> _todo(String content, Object? status) => {
  'content': content,
  'status': switch (status) {
    'in_progress' => 'in_progress',
    'completed' => 'completed',
    _ => 'pending',
  },
  'activeForm': content,
};

/// [call] as Claude Code's tool: its name and input. [servers] are the
/// app's own MCP servers agy was given, whose tools agy names
/// `mcp_<server>_<tool>` (Claude Code `mcp__<server>__<tool>`).
({String name, Map<String, Object?> input}) claudeToolUse(
  AcpToolCall call, {
  List<String> servers = const [],
}) {
  final input = call.input;
  final name = call.name ?? '';
  if (name == 'invoke_subagent' || name == 'start_subagent') {
    return (
      name: 'Agent',
      input: {
        'description': _string(input['Role']) ?? call.summary ?? 'Subagent',
        'prompt': _string(input['Prompt']) ?? '',
        if (_string(input['TypeName']) case final type? when type != 'self')
          'subagent_type': type,
      },
    );
  }
  if (name == 'swarm') {
    return (
      name: 'Swarm',
      input: {
        'action': ?_string(input['action']),
        'name': ?_string(input['name']),
        'title': ?_string(input['title']),
        'model': ?_string(input['model']),
        'workspace': ?_string(input['workspace']),
        'brief': ?_string(input['brief']),
        if (input['n'] != null) 'n': input['n'],
        if (input['tasks'] is List) 'tasks': input['tasks'],
        'channel': ?_string(input['channel']),
        'op': ?_string(input['op']),
      },
    );
  }
  if (name == 'post_message') {
    final text = _string(input['text']) ?? '';
    return (
      name: 'SendMessage',
      input: {
        'message': text,
        'channel': ?_string(input['channel']),
        'summary': call.summary ?? 'Post to swarm board',
      },
    );
  }
  if (name == 'send_message') {
    final text = _string(input['Message']) ?? _string(input['message']) ?? '';
    return (
      name: 'SendMessage',
      input: {
        'message': text,
        'recipient': ?_string(input['Recipient']),
        'summary': call.summary ?? 'Send message',
      },
    );
  }
  if (name == 'read_board' || name == 'swarm_wait') {
    return (
      name: 'SwarmBoard',
      input: {
        'action': name == 'read_board' ? 'read' : 'wait',
        if (input['since'] != null) 'since': input['since'],
        'channel': ?_string(input['channel']),
        if (input['mentions_only'] != null)
          'mentions_only': input['mentions_only'],
      },
    );
  }
  if (name == 'run_workflow') {
    final scriptPath = _string(input['ScriptPath']);
    return (
      name: 'Workflow',
      input: {
        'name': ?(_string(input['Description']) ?? _basename(scriptPath)),
        'script': ?(_string(input['Script']) ?? scriptPath),
        'cwd': ?_string(input['Cwd']),
      },
    );
  }
  if (name == 'manage_task') {
    final action = _string(input['Action']);
    return switch (action) {
      'status' => (
        name: 'TaskOutput',
        input: {'task_id': ?_string(input['TaskId'])},
      ),
      'kill' => (
        name: 'TaskStop',
        input: {'task_id': ?_string(input['TaskId'])},
      ),
      _ => (
        name: 'ManageTask',
        input: {
          'action': ?action,
          'task_id': ?_string(input['TaskId']),
          'input': ?_string(input['Input']),
        },
      ),
    };
  }
  if (name == 'schedule') {
    return (
      name: 'Schedule',
      input: {
        'cron': ?_string(input['CronExpression']),
        if (input['DurationSeconds'] != null)
          'duration_seconds': input['DurationSeconds'],
        'prompt': ?_string(input['Prompt']),
        if (input['IsDaemon'] == true) 'is_daemon': true,
        if (input['MaxIterations'] != null)
          'max_iterations': input['MaxIterations'],
        'timer_condition': ?_string(input['TimerCondition']),
      },
    );
  }
  if (name == 'manage_subagents') {
    return (
      name: 'ManageSubagents',
      input: {
        'action': ?_string(input['Action']),
        if (input['ConversationIds'] is List)
          'conversation_ids': input['ConversationIds'],
      },
    );
  }
  if (name == 'define_subagent') {
    return (
      name: 'DefineSubagent',
      input: {
        'name': ?_string(input['Name']),
        'description': ?_string(input['Description']),
      },
    );
  }
  if (name == 'list_resources') {
    return (
      name: 'McpResource',
      input: {'action': 'list', 'server': ?_string(input['ServerName'])},
    );
  }
  if (name == 'read_resource') {
    return (
      name: 'McpResource',
      input: {
        'action': 'read',
        'server': ?_string(input['ServerName']),
        'uri': ?_string(input['Uri']),
      },
    );
  }
  for (final server in servers) {
    final prefix = 'mcp_${server}_';
    if (name.startsWith(prefix)) {
      return (
        name: 'mcp__${server}__${name.substring(prefix.length)}',
        input: {...input}..remove('toolSummary'),
      );
    }
  }
  // An MCP tool reached through call_mcp_tool, as agy calls those its
  // context has no room to list: of kind `execute`, yet not a command.
  if (agyMcpCall(call) case (:final server, :final tool)) {
    return (
      name: 'mcp__${server}__$tool',
      input: switch (input['Arguments']) {
        final Map<Object?, Object?> arguments => arguments.cast(),
        _ => const {},
      },
    );
  }
  // Its steps, as Claude Code's todos.
  if (name == 'update_steps') {
    return (name: 'TodoWrite', input: _steps(input));
  }
  // A question to the user, as Claude Code asks one.
  if (name == 'ask_question') {
    return (
      name: 'AskUserQuestion',
      input: {
        'questions': [
          for (final question in input['questions'] as List? ?? const [])
            if (question case {'question': final String text})
              {
                'question': text,
                'header': '',
                'options': [
                  for (final option in question['options'] as List? ?? const [])
                    {'label': '$option', 'description': ''},
                ],
                'multiSelect': question['is_multi_select'] == true,
              },
        ],
      },
    );
  }
  // A search of the web is of kind `search` too.
  if (name == 'search_web') {
    return (
      name: 'WebSearch',
      input: {
        'query':
            _string(input['query']) ?? _string(input['Query']) ?? call.title,
      },
    );
  }
  switch (call.kind) {
    case 'execute':
      return (
        name: 'Bash',
        input: {
          'command':
              _string(input['CommandLine']) ??
              _string(input['command']) ??
              call.title ??
              '',
          'description': ?call.summary,
        },
      );
    case 'edit':
      if (call.diff case final diff?) {
        if (diff.oldText == null || diff.oldText!.isEmpty) {
          return (
            name: 'Write',
            input: {'file_path': diff.path, 'content': diff.newText},
          );
        }
        final hunk = _hunk(diff.oldText!, diff.newText, 0);
        return (
          name: 'Edit',
          input: {
            'file_path': diff.path,
            'old_string': hunk?.before ?? diff.oldText,
            'new_string': hunk?.after ?? diff.newText,
          },
        );
      }
      if (call.path case final path?) {
        final content =
            _string(input['Content']) ?? _string(input['CodeContent']);
        if (content != null) {
          return (
            name: 'Write',
            input: {'file_path': path, 'content': content},
          );
        }
        final oldText =
            _string(input['Target']) ?? _string(input['TargetContent']);
        if (oldText != null) {
          return (
            name: 'Edit',
            input: {
              'file_path': path,
              'old_string': oldText,
              'new_string':
                  '${input['Replacement'] ?? input['ReplacementContent'] ?? ''}',
            },
          );
        }
      }
    case 'read':
      if (call.path case final path?) {
        return (name: 'Read', input: {'file_path': path});
      }
    case 'search':
      return (
        name: 'Grep',
        input: {
          'pattern':
              _string(input['Query']) ??
              _string(input['Pattern']) ??
              _string(input['SearchPattern']) ??
              call.title ??
              '',
          'path':
              ?(_string(input['SearchPath']) ??
              _string(input['DirectoryPath'])),
        },
      );
    case 'fetch':
      if (_string(input['Url']) case final url?) {
        return (
          name: 'WebFetch',
          input: {'url': url, 'prompt': call.summary ?? ''},
        );
      }
      return (
        name: 'WebSearch',
        input: {'query': _string(input['Query']) ?? call.title ?? ''},
      );
  }
  return (
    name: name.isEmpty ? 'Tool' : name,
    input: {...input}..remove('toolSummary'),
  );
}

/// [call]'s result as Claude Code's: what the model reads of it, whether
/// it failed, and its `tool_use_result` (an edit's patch, a command's
/// output) for the chat to show. [fileText] is the file's text as it stands
/// after an edit (null where it could not be read), to number the patch's
/// lines as in it. [answers] are what the user answered to a question it
/// asked, by the question. [mcpResult] is what one of the app's MCP
/// servers answered it (agy tells none of it): its content Claude's
/// blocks, or text alone.
({Object content, bool isError, Map<String, Object?>? structured})
claudeToolResult(
  AcpToolCall call,
  String name, {
  String? fileText,
  Map<String, String>? answers,
  Map<String, Object?>? mcpResult,
  String? fallbackOutput,
}) {
  final raw = call.output ?? '';
  final output = raw.isNotEmpty ? raw : (fallbackOutput ?? '');
  final content = _cut(output.isEmpty ? '(no output)' : output);
  if (mcpResult != null) {
    return (
      content: _mcpContent(mcpResult['content']),
      isError: mcpResult['isError'] == true || call.failed,
      structured: null,
    );
  }
  switch (name) {
    case 'TodoWrite':
      return (
        content: 'Todos have been modified successfully.',
        isError: false,
        structured: {'newTodos': _steps(call.input)['todos']},
      );
    case 'AskUserQuestion' when answers != null:
      final said = [
        for (final MapEntry(:key, :value) in answers.entries) '"$key"="$value"',
      ].join(', ');
      return (
        content:
            'User has answered your questions: $said. You can now continue '
            'with the user\'s answers in mind.',
        isError: false,
        structured: {'answers': answers},
      );
    // agy keeps a search's results to itself: nothing to show.
    case 'WebSearch' when output.isEmpty && !call.failed:
      return (content: '', isError: false, structured: null);
    case 'Bash':
      final text = _commandOutput(output);
      final exit = switch (call.rawOutput) {
        {'exit_code': final int code} => code,
        _ => null,
      };
      final failed = call.failed || (exit != null && exit != 0);
      final shown = [
        if (exit != null && exit != 0) 'Exit code $exit',
        text,
      ].where((part) => part.isNotEmpty).join('\n');
      return (
        // A failed result must say something: the API refuses an empty one.
        content: _cut(shown.isEmpty && failed ? '(no output)' : shown),
        isError: failed,
        structured: {'stdout': _cut(text), 'stderr': '', 'interrupted': false},
      );
    case 'Write' || 'Edit' when !call.failed:
      final diff = call.diff;
      if (diff == null) break;
      final before = diff.oldText ?? '';
      if (before.isEmpty) {
        return (
          content: 'File created successfully at: ${diff.path}',
          isError: false,
          structured: {
            'type': 'create',
            'filePath': diff.path,
            'content': diff.newText,
          },
        );
      }
      // agy tells the region it changed, or the whole file: where in the
      // file it is, from the file as it now stands.
      final at = fileText == null ? -1 : fileText.indexOf(diff.newText);
      final offset = at <= 0
          ? 0
          : '\n'.allMatches(fileText!.substring(0, at)).length;
      final hunk = _hunk(before, diff.newText, offset);
      return (
        content: 'The file ${diff.path} has been updated successfully.',
        isError: false,
        structured: {
          'filePath': diff.path,
          'oldString': hunk?.before ?? before,
          'newString': hunk?.after ?? diff.newText,
          if (fileText == diff.newText) 'originalFile': before,
          'structuredPatch': [?hunk?.patch],
        },
      );
  }
  return (content: content, isError: call.failed, structured: null);
}

/// The lines [before] and [after] differ by, with up to three alike on
/// either side, as a patch's hunk, its first line [offset] lines into the
/// file; null when they do not differ.
({String before, String after, Map<String, Object?> patch})? _hunk(
  String before,
  String after,
  int offset,
) {
  final a = before.split('\n');
  final b = after.split('\n');
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  if (start == a.length && start == b.length) return null;
  var end = 0;
  while (end < a.length - start &&
      end < b.length - start &&
      a[a.length - 1 - end] == b[b.length - 1 - end]) {
    end++;
  }
  const context = 3;
  final from = start < context ? 0 : start - context;
  final tail = end < context ? end : context;
  final oldLines = a.sublist(from, a.length - end + tail);
  final newLines = b.sublist(from, b.length - end + tail);
  return (
    before: oldLines.join('\n'),
    after: newLines.join('\n'),
    patch: {
      'oldStart': offset + from + 1,
      'oldLines': oldLines.length,
      'newStart': offset + from + 1,
      'newLines': newLines.length,
      'lines': [
        for (final line in a.sublist(from, start)) ' $line',
        for (final line in a.sublist(start, a.length - end)) '-$line',
        for (final line in b.sublist(start, b.length - end)) '+$line',
        for (final line in a.sublist(a.length - end, a.length - end + tail))
          ' $line',
      ],
    },
  );
}

/// What agy prints before a command's output (when it ran, its exit code)
/// left out: the output alone.
String _commandOutput(String output) {
  const marker = 'Command output:\n';
  final at = output.indexOf(marker);
  if (at >= 0) return output.substring(at + marker.length).trimRight();
  return output
      .split('\n')
      .where(
        (line) =>
            !line.startsWith('Created At: ') &&
            !line.startsWith('Completed At: '),
      )
      .join('\n')
      .trim();
}

/// An MCP result's content as a tool result's: its text alone, or
/// Claude's blocks where it holds images.
Object _mcpContent(Object? content) {
  final blocks = <Map<String, Object?>>[
    for (final block in content is List ? content : const [])
      switch (block) {
        {'type': 'text', 'text': final String text} => {
          'type': 'text',
          'text': _cut(text),
        },
        {
          'type': 'image',
          'data': final String data,
          'mimeType': final String type,
        } =>
          {
            'type': 'image',
            'source': {'type': 'base64', 'media_type': type, 'data': data},
          },
        _ => {'type': 'text', 'text': _cut(jsonEncode(block))},
      },
  ];
  if (blocks.any((block) => block['type'] == 'image')) return blocks;
  final text = blocks.map((block) => block['text']).join('\n');
  return text.isEmpty ? '(no output)' : _cut(text);
}

/// An `update` of `plan` as Claude Code's `TodoWrite` input.
Map<String, Object?> claudeTodos(Map<String, Object?> update) => {
  'todos': [
    for (final entry in update['entries'] as List? ?? const [])
      if (entry is Map) _todo('${entry['content'] ?? ''}', entry['status']),
  ],
};

/// A form agy asks the user to fill in (`elicitation/create`), as its
/// ask_question sends one: each question a field, its title the question,
/// its choices numbered (`oneOf`; `items.anyOf` for a pick of several),
/// and beside it `<field>_other` for an answer in the user's words.
class AgyQuestionForm {
  AgyQuestionForm._(this._fields);

  final List<_FormField> _fields;

  /// [schema] (its `requestedSchema`) as questions; null for a form that
  /// is not all questions with choices.
  static AgyQuestionForm? of(Object? schema) {
    if (schema case {'properties': final Map<Object?, Object?> properties}) {
      final fields = <_FormField>[];
      for (final MapEntry(:key, :value) in properties.entries) {
        if (key is! String || value is! Map) return null;
        if (key.endsWith('_other') &&
            properties.containsKey(key.substring(0, key.length - 6))) {
          continue;
        }
        final items = value['items'];
        final many = value['type'] == 'array';
        final choices = <(String, String)>[
          for (final choice in [
            ...?value['oneOf'] as List?,
            if (items is Map) ...?(items['anyOf'] ?? items['oneOf']) as List?,
          ])
            if (choice case {'const': final Object id})
              ('$id', '${choice['title'] ?? id}'),
          for (final id in [
            ...?value['enum'] as List?,
            if (items is Map) ...?items['enum'] as List?,
          ])
            ('$id', '$id'),
        ];
        if (choices.isEmpty) return null;
        fields.add(
          _FormField(
            key,
            '${value['title'] ?? key}',
            choices,
            many: many,
            other: properties.containsKey('${key}_other')
                ? '${key}_other'
                : null,
          ),
        );
      }
      if (fields.isNotEmpty) return AgyQuestionForm._(fields);
    }
    return null;
  }

  /// The questions, as AskUserQuestion's input has them.
  List<Map<String, Object?>> get questions => [
    for (final field in _fields)
      {
        'question': field.title,
        'header': '',
        'options': [
          for (final (_, label) in field.choices)
            {'label': label, 'description': ''},
        ],
        'multiSelect': field.many,
      },
  ];

  /// The form filled in with [answers] (AskUserQuestion's: by question,
  /// the choices picked joined by `, `): the choices as their numbers,
  /// what matches none in the user's words.
  Map<String, Object?> content(Map<String, String> answers) {
    final content = <String, Object?>{};
    for (final field in _fields) {
      final answer = answers[field.title];
      if (answer == null) continue;
      final picked = <String>[];
      var rest = answer.trim();
      // Labels may hold `, `: the longest that fits is taken first.
      final byLength = [...field.choices]
        ..sort((a, b) => b.$2.length.compareTo(a.$2.length));
      while (rest.isNotEmpty) {
        final match = byLength
            .where((c) => rest == c.$2 || rest.startsWith('${c.$2}, '))
            .firstOrNull;
        if (match == null || !field.many && picked.isNotEmpty) break;
        picked.add(match.$1);
        rest = rest.substring(match.$2.length);
        if (rest.startsWith(', ')) rest = rest.substring(2);
      }
      if (picked.isNotEmpty) {
        content[field.key] = field.many ? picked : picked.first;
      }
      if (rest.isNotEmpty && field.other != null) content[field.other!] = rest;
    }
    return content;
  }
}

class _FormField {
  _FormField(
    this.key,
    this.title,
    this.choices, {
    this.many = false,
    this.other,
  });

  final String key;
  final String title;

  /// Each choice's id and label.
  final List<(String, String)> choices;
  final bool many;

  /// The field for an answer in the user's words.
  final String? other;
}

/// What a tool's output keeps in the conversation, at most.
const maxResultChars = 30000;

String _cut(String text) => text.length <= maxResultChars
    ? text
    : '${text.substring(0, maxResultChars)}\n… (${text.length - maxResultChars} more characters)';

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String? _basename(String? path) {
  if (path == null) return null;
  final parts = path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? null : parts.last;
}
