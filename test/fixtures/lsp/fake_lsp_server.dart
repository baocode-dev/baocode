// A scriptable language server for tests, run as a real process:
// `dart test/fixtures/lsp/fake_lsp_server.dart`. It speaks the base
// protocol itself (no code shared with the client under test) and is set
// up by the client's `initializationOptions`:
//
//   name                   answers and diagnostics say it (default `fake`)
//   sync                   textDocumentSync change kind (default 2)
//   saveText               didSave carries the text (default false)
//   capabilities           merged over the defaults (null removes one)
//   watchers               registered for didChangeWatchedFiles once
//                          initialized (`FileSystemWatcher` JSON)
//   registerHover          hover only by dynamic registration
//   configSections         asked by workspace/configuration once initialized
//   progress               reports `Indexing` progress until a didSave
//   crashAfterInitialized  exits (code 5) once initialized
//   crashOnInitialize      exits (code 4) instead of answering initialize
//   stubborn               ignores shutdown, exit, stdin's end and SIGTERM
//
// A didChange inserting `CRASH` makes it exit with code 3. Lines holding
// `ERROR` get an error diagnostic. `fake/state` answers what it knows.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _docs = <String, String>{};
final _versions = <String, int>{};
final _notifications = <String>[];
final _saves = <Map<String, Object?>>[];
final _watched = <Object?>[];
Object? _configuration;
Map<String, Object?> _options = {};
Map<String, Object?> _clientCapabilities = {};
Map<String, Object?> _initializeParams = {};
var _nextId = 0;
final _pending = <int, Completer<Object?>>{};

String get _name => _options['name'] as String? ?? 'fake';
bool get _stubborn => _options['stubborn'] == true;

void main() {
  var pending = <int>[];
  stdin.listen(
    (chunk) {
      pending = [...pending, ...chunk];
      while (true) {
        final headerEnd = _find(pending, const [13, 10, 13, 10]);
        if (headerEnd < 0) return;
        final header = ascii.decode(pending.sublist(0, headerEnd));
        final match = RegExp(
          r'Content-Length:\s*(\d+)',
          caseSensitive: false,
        ).firstMatch(header);
        final length = int.parse(match!.group(1)!);
        final start = headerEnd + 4;
        if (pending.length < start + length) return;
        final body = utf8.decode(pending.sublist(start, start + length));
        pending = pending.sublist(start + length);
        unawaited(_handle(jsonDecode(body) as Map<String, Object?>));
      }
    },
    onDone: () {
      if (!_stubborn) exit(0);
    },
  );
}

int _find(List<int> bytes, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

void _write(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
  // Two writes, so the client sees a header and body apart at times.
  stdout.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
  stdout.add(body);
}

void _notify(String method, Object? params) =>
    _write({'method': method, 'params': params});

Future<Object?> _request(String method, Object? params) {
  final id = _nextId++;
  final completer = _pending[id] = Completer<Object?>();
  _write({'id': 'server-$id', 'method': method, 'params': params});
  return completer.future;
}

Future<void> _handle(Map<String, Object?> message) async {
  final method = message['method'] as String?;
  final id = message['id'];
  if (method == null) {
    // A response to one of our requests.
    final key = int.tryParse('$id'.replaceFirst('server-', ''));
    _pending.remove(key)?.complete(message['result'] ?? message['error']);
    return;
  }
  final params = (message['params'] as Map?)?.cast<String, Object?>() ?? {};
  if (id == null) {
    _notifications.add(method);
    await _notification(method, params);
    return;
  }
  try {
    final result = await _answer(method, params);
    _write({'id': id, 'result': result});
  } on _MethodNotFound {
    _write({
      'id': id,
      'error': {'code': -32601, 'message': 'Unknown $method'},
    });
  }
}

class _MethodNotFound implements Exception {}

Map<String, Object?> _capabilities() {
  final capabilities = <String, Object?>{
    'textDocumentSync': {
      'openClose': true,
      'change': _options['sync'] ?? 2,
      'save': {'includeText': _options['saveText'] == true},
    },
    if (_options['registerHover'] != true) 'hoverProvider': true,
    'definitionProvider': true,
    'typeDefinitionProvider': true,
    'referencesProvider': true,
    'completionProvider': {
      'triggerCharacters': ['.'],
      'resolveProvider': true,
    },
    'signatureHelpProvider': {
      'triggerCharacters': ['(', ','],
      'retriggerCharacters': [')'],
    },
    'renameProvider': {'prepareProvider': true},
    'documentFormattingProvider': true,
    'documentRangeFormattingProvider': true,
    'documentSymbolProvider': true,
    'codeActionProvider': {'resolveProvider': true},
    'executeCommandProvider': {
      'commands': ['fake.insertHeader'],
    },
    'semanticTokensProvider': {
      'legend': {
        'tokenTypes': ['keyword', 'function'],
        'tokenModifiers': ['declaration'],
      },
      'full': true,
    },
  };
  if (_options['capabilities'] case final Map overrides) {
    for (final MapEntry(:key, :value) in overrides.entries) {
      if (value == null) {
        capabilities.remove(key);
      } else {
        capabilities['$key'] = value;
      }
    }
  }
  return capabilities;
}

Future<Object?> _answer(String method, Map<String, Object?> params) async {
  switch (method) {
    case 'initialize':
      _initializeParams = params;
      _options =
          (params['initializationOptions'] as Map?)?.cast<String, Object?>() ??
          {};
      _clientCapabilities =
          (params['capabilities'] as Map?)?.cast<String, Object?>() ?? {};
      if (_stubborn) ProcessSignal.sigterm.watch().listen((_) {});
      if (_options['crashOnInitialize'] == true) {
        stderr.writeln('$_name: crashing on initialize');
        await stderr.flush();
        exit(4);
      }
      return {
        'capabilities': _capabilities(),
        'serverInfo': {'name': _name, 'version': '0.0.1'},
      };
    case 'shutdown':
      return null;
    case 'fake/state':
      return {
        'docs': _docs,
        'versions': _versions,
        'notifications': _notifications,
        'saves': _saves,
        'watched': _watched,
        'configuration': _configuration,
        'initializeParams': _initializeParams,
        'pid': pid,
      };
    case 'textDocument/hover':
      final (text, word, _) = _wordAt(params);
      if (word == null) return null;
      return {
        'contents': {'kind': 'markdown', 'value': '**$_name** `$word`'},
        'range': _wordRange(text, params),
      };
    case 'textDocument/definition' || 'textDocument/typeDefinition':
      final (text, word, uri) = _wordAt(params);
      if (word == null) return null;
      final first = _occurrences(text, word).first;
      final range = _rangeOf(text, first, first + word.length);
      final links =
          (_clientCapabilities['textDocument']
              as Map?)?['definition']?['linkSupport'] ==
          true;
      return method == 'textDocument/typeDefinition' && links
          ? [
              {
                'targetUri': uri,
                'targetRange': _rangeOf(text, 0, 0),
                'targetSelectionRange': range,
              },
            ]
          : {'uri': uri, 'range': range};
    case 'textDocument/references':
      final (text, word, uri) = _wordAt(params);
      if (word == null) return [];
      return [
        for (final offset in _occurrences(text, word))
          {'uri': uri, 'range': _rangeOf(text, offset, offset + word.length)},
      ];
    case 'textDocument/completion':
      final context = params['context'] as Map?;
      return {
        'isIncomplete': false,
        'items': [
          {
            'label': '${_name}_item',
            'kind': 3,
            'detail':
                'trigger ${context?['triggerKind']}'
                '${context?['triggerCharacter'] ?? ''}',
            'data': {'server': _name},
          },
          {'label': 'snip', 'insertTextFormat': 2, 'insertText': r'snip($1)'},
        ],
      };
    case 'completionItem/resolve':
      return {
        ...params,
        'documentation': {'kind': 'markdown', 'value': 'docs from $_name'},
      };
    case 'textDocument/signatureHelp':
      final uri = (params['textDocument'] as Map)['uri'] as String;
      final position = params['position'] as Map;
      final text = _docs[uri] ?? '';
      final offset = _offset(
        text,
        position['line'] as int,
        position['character'] as int,
      );
      final before = text.substring(0, offset);
      final open = before.lastIndexOf('(');
      if (open < 0) return null;
      return {
        'signatures': [
          {
            'label': 'call(a, b)',
            'parameters': [
              {
                'label': [5, 6],
              },
              {
                'label': [8, 9],
              },
            ],
          },
        ],
        'activeSignature': 0,
        'activeParameter': ','.allMatches(before.substring(open)).length,
      };
    case 'textDocument/prepareRename':
      final (text, word, _) = _wordAt(params);
      if (word == null) return null;
      return {'range': _wordRange(text, params), 'placeholder': word};
    case 'textDocument/rename':
      final (text, word, uri) = _wordAt(params);
      if (word == null) return null;
      return {
        'documentChanges': [
          {
            'textDocument': {'uri': uri, 'version': _versions[uri]},
            'edits': [
              for (final offset in _occurrences(text, word))
                {
                  'range': _rangeOf(text, offset, offset + word.length),
                  'newText': params['newName'],
                },
            ],
          },
        ],
      };
    case 'textDocument/formatting' || 'textDocument/rangeFormatting':
      final uri = (params['textDocument'] as Map)['uri'] as String;
      final text = _docs[uri] ?? '';
      final range = params['range'] as Map?;
      final edits = <Object?>[];
      final lines = _lines(text);
      for (var line = 0; line < lines.length; line++) {
        if (range != null &&
            (line < (range['start'] as Map)['line']! ||
                line > (range['end'] as Map)['line']!)) {
          continue;
        }
        final content = lines[line];
        final trimmed = content.trimRight();
        if (trimmed.length == content.length) continue;
        edits.add({
          'range': {
            'start': {'line': line, 'character': trimmed.length},
            'end': {'line': line, 'character': content.length},
          },
          'newText': '',
        });
      }
      return edits;
    case 'textDocument/documentSymbol':
      final uri = (params['textDocument'] as Map)['uri'] as String;
      final lines = _lines(_docs[uri] ?? '');
      final symbols = <Map<String, Object?>>[];
      for (var line = 0; line < lines.length; line++) {
        final match = RegExp(r'^(\s*)(class|fun) (\w+)')
            .firstMatch(lines[line]);
        if (match == null) continue;
        final name = match.group(3)!;
        final at = lines[line].indexOf(name);
        final symbol = <String, Object?>{
          'name': name,
          'kind': match.group(2) == 'class' ? 5 : 12,
          'range': {
            'start': {'line': line, 'character': 0},
            'end': {'line': line, 'character': lines[line].length},
          },
          'selectionRange': {
            'start': {'line': line, 'character': at},
            'end': {'line': line, 'character': at + name.length},
          },
          'children': <Object?>[],
        };
        if (match.group(1)!.isNotEmpty && symbols.isNotEmpty) {
          (symbols.last['children']! as List).add(symbol);
        } else {
          symbols.add(symbol);
        }
      }
      return symbols;
    case 'textDocument/codeAction':
      final uri = (params['textDocument'] as Map)['uri'] as String;
      final diagnostics =
          (params['context'] as Map?)?['diagnostics'] as List? ?? [];
      return [
        for (final diagnostic in diagnostics)
          if ((diagnostic as Map)['code'] == 'E1')
            {
              'title': 'Replace ERROR',
              'kind': 'quickfix',
              'isPreferred': true,
              'diagnostics': [diagnostic],
              'edit': {
                'changes': {
                  uri: [
                    {'range': diagnostic['range'], 'newText': 'OK'},
                  ],
                },
              },
            },
        {
          'title': 'Add header ($_name)',
          'kind': 'source',
          'data': {'uri': uri},
        },
        {
          'title': 'Insert header by command',
          'command': 'fake.insertHeader',
          'arguments': [uri],
        },
      ];
    case 'codeAction/resolve':
      final uri = (params['data'] as Map)['uri'];
      return {
        ...params,
        'edit': {
          'changes': {
            uri: [
              {'range': _rangeOf('', 0, 0), 'newText': '// $_name header\n'},
            ],
          },
        },
      };
    case 'workspace/executeCommand':
      if (params['command'] != 'fake.insertHeader') throw _MethodNotFound();
      final uri = (params['arguments'] as List).first as String;
      final answer = await _request('workspace/applyEdit', {
        'label': 'Insert header',
        'edit': {
          'changes': {
            uri: [
              {'range': _rangeOf('', 0, 0), 'newText': '// header\n'},
            ],
          },
        },
      });
      return (answer as Map?)?['applied'];
    case 'textDocument/semanticTokens/full':
      final uri = (params['textDocument'] as Map)['uri'] as String;
      final lines = _lines(_docs[uri] ?? '');
      final data = <int>[];
      var previousLine = 0;
      var previousStart = 0;
      for (var line = 0; line < lines.length; line++) {
        for (final match in RegExp(
          r'\b(class|fun)\b',
        ).allMatches(lines[line])) {
          final deltaLine = line - previousLine;
          data.addAll([
            deltaLine,
            deltaLine == 0 ? match.start - previousStart : match.start,
            match.end - match.start,
            0,
            match.group(1) == 'fun' ? 1 : 0,
          ]);
          previousLine = line;
          previousStart = match.start;
        }
      }
      return {'data': data};
  }
  throw _MethodNotFound();
}

Future<void> _notification(String method, Map<String, Object?> params) async {
  switch (method) {
    case 'initialized':
      if (_options['crashAfterInitialized'] == true) {
        stderr.writeln('$_name: crashing after initialized');
        await stderr.flush();
        exit(5);
      }
      if (_options['watchers'] case final List watchers) {
        await _request('client/registerCapability', {
          'registrations': [
            {
              'id': 'watch',
              'method': 'workspace/didChangeWatchedFiles',
              'registerOptions': {'watchers': watchers},
            },
          ],
        });
      }
      if (_options['registerHover'] == true) {
        await _request('client/registerCapability', {
          'registrations': [
            {
              'id': 'hover',
              'method': 'textDocument/hover',
              'registerOptions': {
                'documentSelector': [
                  {'language': 'fake'},
                ],
              },
            },
          ],
        });
      }
      if (_options['configSections'] case final List sections) {
        _configuration = await _request('workspace/configuration', {
          'items': [
            for (final section in sections) {'section': section},
          ],
        });
      }
      if (_options['progress'] == true) {
        await _request('window/workDoneProgress/create', {'token': 'index'});
        _notify(r'$/progress', {
          'token': 'index',
          'value': {
            'kind': 'begin',
            'title': 'Indexing',
            'message': '0/2',
            'percentage': 0,
          },
        });
        _notify(r'$/progress', {
          'token': 'index',
          'value': {'kind': 'report', 'message': '1/2', 'percentage': 50},
        });
      }
      _notify('window/logMessage', {'type': 3, 'message': '$_name ready'});
    case 'exit':
      if (!_stubborn) exit(0);
    case 'textDocument/didOpen':
      final document = params['textDocument'] as Map;
      final uri = document['uri'] as String;
      _docs[uri] = document['text'] as String;
      _versions[uri] = document['version'] as int;
      _publish(uri);
    case 'textDocument/didChange':
      final uri = (params['textDocument'] as Map)['uri'] as String;
      var text = _docs[uri]!;
      for (final change in params['contentChanges'] as List) {
        final replacement = (change as Map)['text'] as String;
        if (replacement.contains('CRASH')) {
          stderr.writeln('$_name: crashing on request');
          await stderr.flush();
          exit(3);
        }
        final range = change['range'] as Map?;
        if (range == null) {
          text = replacement;
          continue;
        }
        final start = range['start'] as Map;
        final end = range['end'] as Map;
        text = text.replaceRange(
          _offset(text, start['line'] as int, start['character'] as int),
          _offset(text, end['line'] as int, end['character'] as int),
          replacement,
        );
      }
      _docs[uri] = text;
      _versions[uri] = (params['textDocument'] as Map)['version'] as int;
      _publish(uri);
    case 'textDocument/didSave':
      _saves.add({
        'uri': (params['textDocument'] as Map)['uri'],
        'text': params['text'],
      });
      if (_options['progress'] == true) {
        _notify(r'$/progress', {
          'token': 'index',
          'value': {'kind': 'end'},
        });
      }
    case 'textDocument/didClose':
      final uri = (params['textDocument'] as Map)['uri'] as String;
      _docs.remove(uri);
      _notify('textDocument/publishDiagnostics', {
        'uri': uri,
        'diagnostics': <Object?>[],
      });
    case 'workspace/didChangeWatchedFiles':
      _watched.addAll(params['changes'] as List);
  }
}

void _publish(String uri) {
  final text = _docs[uri] ?? '';
  final diagnostics = <Object?>[];
  final lines = _lines(text);
  for (var line = 0; line < lines.length; line++) {
    for (final match in 'ERROR'.allMatches(lines[line])) {
      diagnostics.add({
        'range': {
          'start': {'line': line, 'character': match.start},
          'end': {'line': line, 'character': match.end},
        },
        'severity': 1,
        'code': 'E1',
        'source': _name,
        'message': 'ERROR found',
        'tags': [1],
      });
    }
  }
  _notify('textDocument/publishDiagnostics', {
    'uri': uri,
    'version': _versions[uri],
    'diagnostics': diagnostics,
  });
}

/// Line contents, broken at CRLF, CR and LF.
List<String> _lines(String text) => text.split(RegExp('\r\n|\r|\n'));

/// The offset of a protocol position; past a line's end means its end.
int _offset(String text, int line, int character) {
  var offset = 0;
  for (var i = 0; i < line; i++) {
    final next = text.indexOf(RegExp('\r\n|\r|\n'), offset);
    if (next < 0) return text.length;
    offset = next + (text.startsWith('\r\n', next) ? 2 : 1);
  }
  var end = text.indexOf(RegExp('[\r\n]'), offset);
  if (end < 0) end = text.length;
  return offset + character > end ? end : offset + character;
}

Map<String, Object?> _position(String text, int offset) {
  final before = text.substring(0, offset);
  final breaks = RegExp('\r\n|\r|\n').allMatches(before).toList();
  final lineStart = breaks.isEmpty ? 0 : breaks.last.end;
  return {'line': breaks.length, 'character': offset - lineStart};
}

Map<String, Object?> _rangeOf(String text, int start, int end) => {
  'start': _position(text, start),
  'end': _position(text, end),
};

final _wordChar = RegExp(r'\w');

(int, int)? _wordBounds(String text, int offset) {
  var start = offset;
  while (start > 0 && _wordChar.hasMatch(text[start - 1])) {
    start--;
  }
  var end = offset;
  while (end < text.length && _wordChar.hasMatch(text[end])) {
    end++;
  }
  return start == end ? null : (start, end);
}

/// The document's text, the word at the request's position, and its URI.
(String, String?, String) _wordAt(Map<String, Object?> params) {
  final uri = (params['textDocument'] as Map)['uri'] as String;
  final position = params['position'] as Map;
  final text = _docs[uri] ?? '';
  final offset = _offset(
    text,
    position['line'] as int,
    position['character'] as int,
  );
  final bounds = _wordBounds(text, offset);
  return (
    text,
    bounds == null ? null : text.substring(bounds.$1, bounds.$2),
    uri,
  );
}

Map<String, Object?> _wordRange(String text, Map<String, Object?> params) {
  final position = params['position'] as Map;
  final offset = _offset(
    text,
    position['line'] as int,
    position['character'] as int,
  );
  final (start, end) = _wordBounds(text, offset)!;
  return _rangeOf(text, start, end);
}

List<int> _occurrences(String text, String word) => [
  for (final match in RegExp('\\b${RegExp.escape(word)}\\b').allMatches(text))
    match.start,
];
