import 'dart:async';
import 'dart:convert';

import 'json_rpc.dart';
import 'language_features.dart';
import 'lsp_glob.dart';
import 'lsp_process.dart';
import 'lsp_protocol.dart';
import 'lsp_server_definition.dart';

/// A `workspace/didChangeWatchedFiles` watcher a server registered.
class LspFileWatcher {
  LspFileWatcher(this.glob, {this.basePath, this.kind = 7});

  final LspGlob glob;

  /// A relative pattern's base folder; null for a pattern matched against
  /// the whole path.
  final String? basePath;

  /// `WatchKind` bits: 1 create, 2 change, 4 delete.
  final int kind;

  bool matches(String path, LspFileChangeType type) {
    final bit = switch (type) {
      LspFileChangeType.created => 1,
      LspFileChangeType.changed => 2,
      LspFileChangeType.deleted => 4,
    };
    if (kind & bit == 0) return false;
    final normalized = path.replaceAll(r'\', '/');
    if (basePath case final base?) {
      final prefix = base.replaceAll(r'\', '/');
      final withSlash = prefix.endsWith('/') ? prefix : '$prefix/';
      if (!normalized.startsWith(withSlash)) return false;
      return glob.matches(normalized.substring(withSlash.length));
    }
    return glob.matches(normalized);
  }
}

class _Registration {
  const _Registration(this.method, this.options);

  final String method;
  final JsonMap options;
}

class _Progress {
  _Progress(this.title);

  String title;
  String? message;
  int? percentage;

  @override
  String toString() {
    final text = [
      if (title.isNotEmpty) title,
      if (message case final message? when message.isNotEmpty) message,
    ].join(': ');
    return percentage == null ? text : '$text ($percentage%)';
  }
}

/// How a server wants documents synchronized.
typedef LspSyncOptions = ({int change, bool save, bool saveText});

/// One connection to a running language server: the protocol's lifecycle,
/// document synchronization, and the requests servers make of the client.
class LspClient {
  LspClient({
    required this.definition,
    required this.rootPath,
    required this.process,
    this.requestTimeout = const Duration(seconds: 30),
    this.onDiagnostics,
    this.onChanged,
    this.onApplyEdit,
    this.onExit,
    this.logLimit = 200,
  }) {
    _rpc = JsonRpcConnection(
      process.stdout,
      process.write,
      onProtocolError: (message) => _log('[protocol] $message'),
    );
    _registerHandlers();
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            _stderr.add(line);
            if (_stderr.length > 30) _stderr.removeAt(0);
            _log('[stderr] $line');
          },
          onError: (Object _) {},
          cancelOnError: false,
        );
    unawaited(process.exitCode.then(_exited));
  }

  final LspServerDefinition definition;

  /// The workspace folder the server was started for.
  final String rootPath;
  final LspProcess process;
  final Duration requestTimeout;

  /// `textDocument/publishDiagnostics`, by document URI.
  final void Function(String uri, List<LspDiagnostic> diagnostics)?
  onDiagnostics;

  /// Capabilities, progress or the log changed.
  final void Function()? onChanged;

  /// `workspace/applyEdit`: completes with whether the edit was applied.
  final Future<bool> Function(LspWorkspaceEdit edit, String? label)?
  onApplyEdit;

  /// The process ended; [crashed] unless it was asked to stop.
  final void Function(int exitCode, {required bool crashed})? onExit;

  /// How many log lines ([log]) are kept.
  final int logLimit;

  late final JsonRpcConnection _rpc;
  JsonMap _capabilities = const {};
  JsonMap? _serverInfo;
  final _registrations = <String, _Registration>{};
  final _progress = <Object, _Progress>{};
  Object? _latestProgress;
  final _logLines = <String>[];
  final _stderr = <String>[];
  final _open = <String, int>{};
  bool _initialized = false;
  bool _stopping = false;
  int? _exitCode;
  final _exit = Completer<int>();

  String get serverId => definition.id;
  JsonMap get capabilities => _capabilities;

  /// `serverInfo` from the initialize answer.
  String? get serverName => _serverInfo?['name'] as String?;
  bool get isInitialized => _initialized && _exitCode == null;
  bool get isRunning => _exitCode == null;
  int? get exitCode => _exitCode;
  Future<int> get exited => _exit.future;

  /// What the server said (`window/showMessage`, `window/logMessage`) and
  /// printed on stderr, newest last.
  List<String> get log => List.unmodifiable(_logLines);

  /// The server's last lines on stderr, to say why it failed.
  String get stderrTail => _stderr.join('\n');

  /// The work in progress the server reported last (e.g. indexing), as
  /// `title: message (percentage%)`; null when none is under way.
  String? get progress => _progress[_latestProgress]?.toString();

  /// URIs of the documents open on the server.
  Iterable<String> get openDocuments => _open.keys;
  bool isOpen(String uri) => _open.containsKey(uri);

  /// The client's capabilities, sent in `initialize`.
  static JsonMap clientCapabilities() => {
    'general': {
      'positionEncodings': ['utf-16'],
      'markdown': {'parser': 'marked', 'version': '1.1.0'},
    },
    'workspace': {
      'applyEdit': true,
      'workspaceEdit': {
        'documentChanges': true,
        'normalizesLineEndings': false,
      },
      'didChangeConfiguration': {'dynamicRegistration': false},
      'didChangeWatchedFiles': {
        'dynamicRegistration': true,
        'relativePatternSupport': true,
      },
      'executeCommand': {'dynamicRegistration': true},
      'configuration': true,
      'workspaceFolders': true,
      'semanticTokens': {'refreshSupport': true},
    },
    'textDocument': {
      'synchronization': {
        'dynamicRegistration': false,
        'willSave': false,
        'willSaveWaitUntil': false,
        'didSave': true,
      },
      'completion': {
        'dynamicRegistration': true,
        'contextSupport': true,
        'completionItem': {
          'snippetSupport': true,
          'commitCharactersSupport': true,
          'documentationFormat': ['markdown', 'plaintext'],
          'deprecatedSupport': true,
          'preselectSupport': true,
          'tagSupport': {
            'valueSet': [1],
          },
          'insertReplaceSupport': true,
          'resolveSupport': {
            'properties': ['documentation', 'detail', 'additionalTextEdits'],
          },
          'insertTextModeSupport': {
            'valueSet': [1],
          },
          'labelDetailsSupport': true,
        },
        'completionItemKind': {
          'valueSet': [for (var i = 1; i <= 25; i++) i],
        },
        'completionList': {
          'itemDefaults': ['editRange', 'insertTextFormat'],
        },
      },
      'hover': {
        'dynamicRegistration': true,
        'contentFormat': ['markdown', 'plaintext'],
      },
      'signatureHelp': {
        'dynamicRegistration': true,
        'contextSupport': true,
        'signatureInformation': {
          'documentationFormat': ['markdown', 'plaintext'],
          'parameterInformation': {'labelOffsetSupport': true},
          'activeParameterSupport': true,
        },
      },
      'definition': {'dynamicRegistration': true, 'linkSupport': true},
      'typeDefinition': {'dynamicRegistration': true, 'linkSupport': true},
      'implementation': {'dynamicRegistration': true, 'linkSupport': true},
      'references': {'dynamicRegistration': true},
      'documentSymbol': {
        'dynamicRegistration': true,
        'hierarchicalDocumentSymbolSupport': true,
        'symbolKind': {
          'valueSet': [for (var i = 1; i <= 26; i++) i],
        },
      },
      'codeAction': {
        'dynamicRegistration': true,
        'codeActionLiteralSupport': {
          'codeActionKind': {
            'valueSet': [
              '',
              'quickfix',
              'refactor',
              'refactor.extract',
              'refactor.inline',
              'refactor.rewrite',
              'source',
              'source.organizeImports',
              'source.fixAll',
            ],
          },
        },
        'isPreferredSupport': true,
        'disabledSupport': true,
        'dataSupport': true,
        'resolveSupport': {
          'properties': ['edit', 'command'],
        },
      },
      'formatting': {'dynamicRegistration': true},
      'rangeFormatting': {'dynamicRegistration': true},
      'rename': {
        'dynamicRegistration': true,
        'prepareSupport': true,
        'prepareSupportDefaultBehavior': 1,
      },
      'publishDiagnostics': {
        'relatedInformation': false,
        'tagSupport': {
          'valueSet': [1, 2],
        },
        'versionSupport': true,
        'codeDescriptionSupport': true,
        'dataSupport': true,
      },
      'semanticTokens': {
        'dynamicRegistration': true,
        'requests': {'full': true, 'range': false},
        'tokenTypes': _semanticTokenTypes,
        'tokenModifiers': _semanticTokenModifiers,
        'formats': ['relative'],
        'overlappingTokenSupport': false,
        'multilineTokenSupport': false,
        'augmentsSyntaxTokens': true,
      },
    },
    'window': {
      'workDoneProgress': true,
      'showMessage': {
        'messageActionItem': {'additionalPropertiesSupport': false},
      },
      'showDocument': {'support': false},
    },
  };

  static const _semanticTokenTypes = [
    'namespace',
    'type',
    'class',
    'enum',
    'interface',
    'struct',
    'typeParameter',
    'parameter',
    'variable',
    'property',
    'enumMember',
    'event',
    'function',
    'method',
    'macro',
    'keyword',
    'modifier',
    'comment',
    'string',
    'number',
    'regexp',
    'operator',
    'decorator',
  ];

  static const _semanticTokenModifiers = [
    'declaration',
    'definition',
    'readonly',
    'static',
    'deprecated',
    'abstract',
    'async',
    'modification',
    'documentation',
    'defaultLibrary',
  ];

  String get _rootUri => Uri.directory(rootPath).toString();

  String get _rootName => rootPath
      .split(RegExp(r'[/\\]'))
      .lastWhere((part) => part.isNotEmpty, orElse: () => rootPath);

  /// `initialize`, then `initialized` (and the settings, if any).
  Future<void> initialize({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final result = await _rpc.request('initialize', {
      'processId': lspClientProcessId,
      'clientInfo': {'name': 'BaoCode', 'version': '1.0.0'},
      'locale': 'en',
      'rootPath': rootPath,
      'rootUri': _rootUri,
      'workspaceFolders': [
        {'uri': _rootUri, 'name': _rootName},
      ],
      'initializationOptions': ?definition.initializationOptions,
      'capabilities': clientCapabilities(),
      'trace': 'off',
    }, timeout);
    if (result is Map) {
      _capabilities = _asMap(result['capabilities']) ?? const {};
      _serverInfo = _asMap(result['serverInfo']);
    }
    _rpc.notify('initialized', <String, Object?>{});
    if (definition.settings case final settings?) {
      _rpc.notify('workspace/didChangeConfiguration', {'settings': settings});
    }
    _initialized = true;
    onChanged?.call();
  }

  /// Sends a request; see [JsonRpcConnection.request]. [timeout] defaults
  /// to [requestTimeout].
  Future<Object?> request(
    String method,
    Object? params, {
    Duration? timeout,
    JsonRpcCancelToken? cancel,
  }) => _rpc.request(method, params, timeout ?? requestTimeout, cancel);

  void notify(String method, Object? params) => _rpc.notify(method, params);

  // Document synchronization.

  LspSyncOptions get syncOptions {
    final sync = _capabilities['textDocumentSync'];
    if (sync is num) return (change: sync.toInt(), save: true, saveText: false);
    final options = _asMap(sync);
    if (options == null) return (change: 0, save: false, saveText: false);
    final save = options['save'];
    return (
      change: (options['change'] as num?)?.toInt() ?? 0,
      save: save == true || save is Map,
      saveText: save is Map && save['includeText'] == true,
    );
  }

  void didOpen(String uri, String languageId, int version, String text) {
    if (!isInitialized || _open.containsKey(uri)) return;
    _open[uri] = version;
    _rpc.notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': languageId,
        'version': version,
        'text': text,
      },
    });
  }

  /// Incremental when the server syncs so and [changes] are known; the
  /// whole [text] otherwise.
  void didChange(
    String uri,
    int version,
    String text, {
    List<LspTextDocumentContentChange>? changes,
  }) {
    if (!isInitialized || !_open.containsKey(uri)) return;
    final kind = syncOptions.change;
    if (kind == 0) return;
    _open[uri] = version;
    _rpc.notify('textDocument/didChange', {
      'textDocument': {'uri': uri, 'version': version},
      'contentChanges': kind == 2 && changes != null
          ? [for (final change in changes) change.toJson()]
          : [
              {'text': text},
            ],
    });
  }

  void didSave(String uri, String text) {
    if (!isInitialized || !_open.containsKey(uri)) return;
    final sync = syncOptions;
    if (!sync.save) return;
    _rpc.notify('textDocument/didSave', {
      'textDocument': {'uri': uri},
      if (sync.saveText) 'text': text,
    });
  }

  void didClose(String uri) {
    if (_open.remove(uri) == null || !isInitialized) return;
    _rpc.notify('textDocument/didClose', {
      'textDocument': {'uri': uri},
    });
  }

  void didChangeWatchedFiles(List<LspFileEvent> events) {
    if (!isInitialized || events.isEmpty) return;
    _rpc.notify('workspace/didChangeWatchedFiles', {
      'changes': [
        for (final event in events)
          {
            'uri': Uri.file(event.path).toString(),
            'type': event.type.protocolValue,
          },
      ],
    });
  }

  // Capabilities.

  static const _requests = {
    LanguageRequest.hover: ('textDocument/hover', 'hoverProvider'),
    LanguageRequest.definition: (
      'textDocument/definition',
      'definitionProvider',
    ),
    LanguageRequest.typeDefinition: (
      'textDocument/typeDefinition',
      'typeDefinitionProvider',
    ),
    LanguageRequest.implementation: (
      'textDocument/implementation',
      'implementationProvider',
    ),
    LanguageRequest.references: (
      'textDocument/references',
      'referencesProvider',
    ),
    LanguageRequest.completion: (
      'textDocument/completion',
      'completionProvider',
    ),
    LanguageRequest.signatureHelp: (
      'textDocument/signatureHelp',
      'signatureHelpProvider',
    ),
    LanguageRequest.rename: ('textDocument/rename', 'renameProvider'),
    LanguageRequest.format: (
      'textDocument/formatting',
      'documentFormattingProvider',
    ),
    LanguageRequest.rangeFormat: (
      'textDocument/rangeFormatting',
      'documentRangeFormattingProvider',
    ),
    LanguageRequest.documentSymbols: (
      'textDocument/documentSymbol',
      'documentSymbolProvider',
    ),
    LanguageRequest.codeActions: (
      'textDocument/codeAction',
      'codeActionProvider',
    ),
    LanguageRequest.semanticTokens: (
      'textDocument/semanticTokens',
      'semanticTokensProvider',
    ),
  };

  /// The options the server gave for [request] on the document at [path]
  /// (statically, or by a registration whose selector matches); `{}` for a
  /// bare `true`, null when it does not support it.
  JsonMap? optionsFor(
    LanguageRequest request, {
    required String path,
    required String languageId,
  }) {
    final (method, key) = _requests[request]!;
    final value = _capabilities[key];
    JsonMap? options = value == true ? const {} : _asMap(value);
    if (options != null && _accepts(request, options)) return options;
    for (final registration in _registrations.values) {
      if (registration.method != method) continue;
      if (!_selects(
        registration.options['documentSelector'],
        path,
        languageId,
      )) {
        continue;
      }
      options = registration.options;
      if (_accepts(request, options)) return options;
    }
    return null;
  }

  bool supports(
    LanguageRequest request, {
    required String path,
    required String languageId,
  }) => optionsFor(request, path: path, languageId: languageId) != null;

  static bool _accepts(LanguageRequest request, JsonMap options) =>
      switch (request) {
        LanguageRequest.semanticTokens =>
          options['full'] == true || options['full'] is Map,
        _ => true,
      };

  bool _selects(Object? selector, String path, String languageId) {
    if (selector is! List) return true;
    for (final filter in selector) {
      if (filter is String) {
        if (filter == languageId) return true;
        continue;
      }
      if (filter is! Map) continue;
      final language = filter['language'];
      final scheme = filter['scheme'];
      final pattern = filter['pattern'];
      if (language is String && language != languageId) continue;
      if (scheme is String && scheme != 'file') continue;
      if (pattern is String && !_patternMatches(pattern, path)) continue;
      return true;
    }
    return false;
  }

  bool _patternMatches(String pattern, String path) {
    final glob = LspGlob(pattern);
    final normalized = path.replaceAll(r'\', '/');
    if (glob.matches(normalized)) return true;
    final root = rootPath.replaceAll(r'\', '/');
    final prefix = root.endsWith('/') ? root : '$root/';
    return normalized.startsWith(prefix) &&
        glob.matches(normalized.substring(prefix.length));
  }

  /// Characters in [key] (`triggerCharacters`, `retriggerCharacters`) of
  /// [request]'s options for a document.
  Set<String> characters(
    LanguageRequest request,
    String key, {
    required String path,
    required String languageId,
  }) {
    final options = optionsFor(request, path: path, languageId: languageId);
    return {
      if (options?[key] case final List chars)
        for (final c in chars)
          if (c is String && c.isNotEmpty) c,
    };
  }

  /// The commands `workspace/executeCommand` runs.
  Set<String> get commands => {
    if (_asMap(_capabilities['executeCommandProvider'])?['commands']
        case final List list)
      for (final c in list)
        if (c is String) c,
    for (final registration in _registrations.values)
      if (registration.method == 'workspace/executeCommand' &&
          registration.options['commands'] is List)
        for (final c in registration.options['commands']! as List)
          if (c is String) c,
  };

  /// What the server registered to hear about through
  /// `workspace/didChangeWatchedFiles`.
  List<LspFileWatcher> get fileWatchers => [
    for (final registration in _registrations.values)
      if (registration.method == 'workspace/didChangeWatchedFiles')
        for (final watcher in _maps(registration.options['watchers']))
          ?_watcher(watcher),
  ];

  LspFileWatcher? _watcher(JsonMap watcher) {
    final kind = (watcher['kind'] as num?)?.toInt() ?? 7;
    switch (watcher['globPattern']) {
      case final String pattern:
        return LspFileWatcher(LspGlob(pattern), kind: kind);
      case final Map relative:
        final pattern = relative['pattern'];
        final base = switch (relative['baseUri']) {
          final String uri => uri,
          final Map folder => folder['uri'],
          _ => null,
        };
        if (pattern is! String || base is! String) return null;
        final basePath = _pathOf(base);
        if (basePath == null) return null;
        return LspFileWatcher(LspGlob(pattern), basePath: basePath, kind: kind);
    }
    return null;
  }

  /// The legend semantic tokens decode against, for a document.
  LspSemanticTokensLegend? semanticTokensLegend({
    required String path,
    required String languageId,
  }) {
    final options = optionsFor(
      LanguageRequest.semanticTokens,
      path: path,
      languageId: languageId,
    );
    final legend = _asMap(options?['legend']);
    return legend == null ? null : LspSemanticTokensLegend.fromJson(legend);
  }

  // Server-to-client traffic.

  void _registerHandlers() {
    _rpc
      ..onRequest('window/workDoneProgress/create', (params) {
        final token = _asMap(params)?['token'];
        if (token != null) _progress.remove(token);
        return null;
      })
      ..onNotification(r'$/progress', _onProgress)
      ..onNotification('window/showMessage', (params) {
        _logMessage(params);
      })
      ..onNotification('window/logMessage', (params) {
        _logMessage(params);
      })
      ..onRequest('window/showMessageRequest', (params) {
        _logMessage(params);
        return null;
      })
      ..onRequest('window/showDocument', (_) => {'success': false})
      ..onRequest('client/registerCapability', (params) {
        for (final registration in _maps(_asMap(params)?['registrations'])) {
          final id = registration['id'];
          final method = registration['method'];
          if (id is! String || method is! String) continue;
          _registrations[id] = _Registration(
            method,
            _asMap(registration['registerOptions']) ?? const {},
          );
        }
        onChanged?.call();
        return null;
      })
      ..onRequest('client/unregisterCapability', (params) {
        final map = _asMap(params);
        // The protocol spells it `unregisterations`.
        for (final registration in _maps(
          map?['unregisterations'] ?? map?['unregistrations'],
        )) {
          _registrations.remove(registration['id']);
        }
        onChanged?.call();
        return null;
      })
      ..onRequest('workspace/configuration', (params) {
        return [
          for (final item in _maps(_asMap(params)?['items']))
            configuration(item['section'] as String?),
        ];
      })
      ..onRequest(
        'workspace/workspaceFolders',
        (_) => [
          {'uri': _rootUri, 'name': _rootName},
        ],
      )
      ..onRequest('workspace/applyEdit', (params) async {
        final map = _asMap(params) ?? const {};
        final edit = LspWorkspaceEdit.fromJson(_asMap(map['edit']) ?? const {});
        final apply = onApplyEdit;
        final applied = apply == null
            ? false
            : await apply(edit, map['label'] as String?);
        return {
          'applied': applied,
          if (!applied) 'failureReason': 'The editor did not apply the edit',
        };
      })
      ..onNotification('textDocument/publishDiagnostics', (params) {
        final map = _asMap(params);
        final uri = map?['uri'];
        if (uri is! String) return;
        onDiagnostics?.call(uri, [
          for (final d in _maps(map?['diagnostics'])) LspDiagnostic.fromJson(d),
        ]);
      });
    for (final refresh in const [
      'workspace/semanticTokens/refresh',
      'workspace/inlayHint/refresh',
      'workspace/codeLens/refresh',
      'workspace/diagnostic/refresh',
      'workspace/foldingRange/refresh',
      'workspace/inlineValue/refresh',
    ]) {
      _rpc.onRequest(refresh, (_) {
        onChanged?.call();
        return null;
      });
    }
  }

  /// What `workspace/configuration` answers for [section]: the settings,
  /// the value at a dotted path in them, or null.
  Object? configuration(String? section) {
    final settings = definition.settings;
    if (section == null || section.isEmpty) return settings;
    if (settings == null) return null;
    if (settings.containsKey(section)) return settings[section];
    Object? value = settings;
    for (final part in section.split('.')) {
      if (value is Map && value.containsKey(part)) {
        value = value[part];
      } else {
        return null;
      }
    }
    return value;
  }

  void _onProgress(Object? params) {
    final map = _asMap(params);
    final token = map?['token'];
    final value = _asMap(map?['value']);
    if (token == null || value == null) return;
    switch (value['kind']) {
      case 'begin':
        _progress[token] = _Progress(value['title'] as String? ?? '')
          ..message = value['message'] as String?
          ..percentage = (value['percentage'] as num?)?.toInt();
        _latestProgress = token;
      case 'report':
        final progress = _progress[token];
        if (progress == null) return;
        if (value['message'] case final String message) {
          progress.message = message;
        }
        if (value['percentage'] case final num percentage) {
          progress.percentage = percentage.toInt();
        }
        _latestProgress = token;
      case 'end':
        _progress.remove(token);
        if (_latestProgress == token) {
          _latestProgress = _progress.keys.lastOrNull;
        }
      default:
        return;
    }
    onChanged?.call();
  }

  void _logMessage(Object? params) {
    final map = _asMap(params);
    final message = map?['message'];
    if (message is! String) return;
    final level = switch ((map?['type'] as num?)?.toInt()) {
      1 => 'error',
      2 => 'warning',
      3 => 'info',
      _ => 'log',
    };
    for (final line in const LineSplitter().convert(message)) {
      _log('[$level] $line');
    }
    onChanged?.call();
  }

  void _log(String line) {
    _logLines.add(line);
    if (_logLines.length > logLimit) _logLines.removeAt(0);
  }

  // Lifecycle.

  void _exited(int code) {
    _exitCode = code;
    _rpc.close();
    _open.clear();
    _progress.clear();
    if (!_exit.isCompleted) _exit.complete(code);
    onExit?.call(code, crashed: !_stopping && !process.stopRequested);
  }

  /// `shutdown` and `exit`; killed when it does not end within [timeout].
  Future<void> shutdown({Duration timeout = const Duration(seconds: 3)}) async {
    if (_stopping || _exitCode != null) {
      await exited;
      return;
    }
    _stopping = true;
    try {
      if (_initialized) await _rpc.request('shutdown', null, timeout);
      _rpc.notify('exit');
    } on Object {
      // Not answering: it is killed below.
    }
    await process.closeStdin();
    try {
      await exited.timeout(timeout);
    } on TimeoutException {
      process.kill();
      try {
        await exited.timeout(timeout);
      } on TimeoutException {
        process.kill(force: true);
        await exited;
      }
    }
  }

  /// Ends the process at once.
  void kill() {
    _stopping = true;
    process.kill(force: true);
  }
}

JsonMap? _asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

List<JsonMap> _maps(Object? value) => [
  if (value is List)
    for (final item in value) ?_asMap(item),
];

/// The file path of a `file:` [uri]; null for another scheme.
String? _pathOf(String uri) {
  try {
    final parsed = Uri.parse(uri);
    return parsed.scheme == 'file' ? parsed.toFilePath() : null;
  } on Object {
    return null;
  }
}
