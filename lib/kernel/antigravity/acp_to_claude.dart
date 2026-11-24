/// What `agy acp` reports of its tool calls, as Claude Code would have made
/// them: a conversation on Antigravity is kept as Claude Code keeps its own
/// (one jsonl), its calls as Claude Code's tools (`Bash`, `Edit`, `Read`…),
/// so that the chat shows them as it shows those, and a model of another
/// upstream reads them on as its own.
library;

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
      {'output': final String text} => text,
      final String text when text.isNotEmpty => text,
      _ => null,
    };
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
  for (final server in servers) {
    final prefix = 'mcp_${server}_';
    if (name.startsWith(prefix)) {
      return (
        name: 'mcp__${server}__${name.substring(prefix.length)}',
        input: {...input}..remove('toolSummary'),
      );
    }
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
/// lines as in it.
({String content, bool isError, Map<String, Object?>? structured})
claudeToolResult(AcpToolCall call, String name, {String? fileText}) {
  final output = call.output ?? '';
  final content = _cut(output.isEmpty ? '(no output)' : output);
  switch (name) {
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

/// An `update` of `plan` as Claude Code's `TodoWrite` input.
Map<String, Object?> claudeTodos(Map<String, Object?> update) => {
  'todos': [
    for (final entry in update['entries'] as List? ?? const [])
      if (entry is Map)
        {
          'content': '${entry['content'] ?? ''}',
          'status': switch (entry['status']) {
            'in_progress' => 'in_progress',
            'completed' => 'completed',
            _ => 'pending',
          },
          'activeForm': '${entry['content'] ?? ''}',
        },
  ],
};

/// What a tool's output keeps in the conversation, at most.
const maxResultChars = 30000;

String _cut(String text) => text.length <= maxResultChars
    ? text
    : '${text.substring(0, maxResultChars)}\n… (${text.length - maxResultChars} more characters)';

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
