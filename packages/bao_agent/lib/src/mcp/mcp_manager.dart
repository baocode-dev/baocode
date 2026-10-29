import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/settings.dart';
import '../engine/session.dart';
import '../hooks/hooks.dart';
import '../util/cancel.dart';
import '../util/json.dart';
import 'jsonrpc.dart';
import 'oauth.dart';
import 'transports.dart';

/// The MCP protocol version asked for.
const mcpProtocolVersion = '2025-06-18';

/// [name] as it may be part of a tool's name: what is not a letter, a
/// digit, `_` or `-` made `_`.
String mcpNormalize(String name) =>
    name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

/// The name the model calls [tool] of [server] by.
String mcpToolName(String server, String tool) =>
    'mcp__${mcpNormalize(server)}__${mcpNormalize(tool)}';

/// One MCP server: how it is set up, and where its connection stands.
class McpServer {
  McpServer({required this.name, required this.scope, required this.config});

  final String name;

  /// `user`, `project`, `local`, `plugin`, `sdk`, `managed`.
  final String scope;
  final Map<String, Object?> config;

  /// `pending`, `connected`, `failed`, `needs-auth`, `disabled`.
  String status = 'pending';
  String? error;
  Map<String, Object?> serverInfo = const {};
  Map<String, Object?> capabilities = const {};
  String? instructions;
  List<Map<String, Object?>> tools = const [];
  List<Map<String, Object?>> resources = const [];
  List<Map<String, Object?>> prompts = const [];

  McpTransport? transport;
  JsonRpcPeer? peer;
  Uri? resourceMetadata;

  String get type =>
      asString(config['type']) ?? (config['url'] != null ? 'http' : 'stdio');

  /// Its URL, its `${VAR}`s filled in from [env].
  Uri? urlIn(Map<String, String> env) => switch (asString(config['url'])) {
    final url? => Uri.tryParse(McpManager.expandEnv(url, env)),
    null => null,
  };

  bool get connected => status == 'connected';

  Map<String, Object?> toStatus() => {
    'name': name,
    'status': status,
    'scope': scope,
    if (serverInfo.isNotEmpty)
      'serverInfo': {
        'name': serverInfo['name'],
        'version': serverInfo['version'],
      },
    'tools': [
      for (final tool in tools)
        {
          'name': tool['name'],
          if (tool['annotations'] != null) 'annotations': tool['annotations'],
        },
    ],
    'error': ?error,
    // As configured: no variable's value (a token) shown.
    'config': {'type': type, 'url': ?asString(config['url'])},
  };
}

/// The session's MCP servers: read from where Claude Code keeps them,
/// connected, their tools offered to the model, and switched off, on and
/// signed in to as the host asks.
class McpManager {
  McpManager(this.session)
    : oauth = McpOAuth(
        storeFile: p.join(session.paths.configDir, '.baocode-mcp-oauth.json'),
        environment: session.environment,
      );

  final AgentSession session;
  final McpOAuth oauth;
  final Map<String, McpServer> servers = {};

  /// Told when the tools on offer change.
  void Function()? onToolsChanged;

  static Duration _timeout(
    Map<String, String> env,
    String name,
    int fallbackMs,
  ) => Duration(milliseconds: asInt(env[name]) ?? fallbackMs);

  /// The servers set up for the session, as Claude Code finds them: the
  /// user's, the project's (`.mcp.json`), this folder's own in
  /// `~/.claude.json`, the plugins', the host's.
  Map<String, McpServer> configured() {
    final found = <String, McpServer>{};
    final claudeJson = AgentSettings.readJson(session.paths.claudeJson);
    final project = asMap(asMap(claudeJson['projects'])[session.cwd]);
    void add(String scope, Map<String, Object?> servers) {
      for (final MapEntry(key: name, value: config) in servers.entries) {
        if (config is! Map) continue;
        found[name] = McpServer(
          name: name,
          scope: scope,
          config: config.cast<String, Object?>(),
        );
      }
    }

    if (session.options.strictMcpConfig) {
      add(
        'flag',
        asMap(session.settings.layer(SettingsSource.flag)['mcpServers']),
      );
      for (final name in session.sdkServers) {
        found[name] = McpServer(
          name: name,
          scope: 'sdk',
          config: {'type': 'sdk', 'name': name},
        );
      }
      return found;
    }
    add('user', asMap(claudeJson['mcpServers']));
    final mcpJson = AgentSettings.readJson(p.join(session.cwd, '.mcp.json'));
    final rejected = {
      ...asList(project['disabledMcpjsonServers']).whereType<String>(),
      ...asList(session.settings['disabledMcpjsonServers']).whereType<String>(),
    };
    add('project', {
      for (final MapEntry(:key, :value) in asMap(mcpJson['mcpServers']).entries)
        if (!rejected.contains(key)) key: value,
    });
    add('local', asMap(project['mcpServers']));
    add(
      'flag',
      asMap(session.settings.layer(SettingsSource.flag)['mcpServers']),
    );
    for (final plugin in session.plugins) {
      add('plugin', {
        for (final MapEntry(:key, :value) in plugin.mcpServers.entries)
          'plugin:${plugin.name}:$key': value,
      });
    }
    for (final name in session.sdkServers) {
      found[name] = McpServer(
        name: name,
        scope: 'sdk',
        config: {'type': 'sdk', 'name': name},
      );
    }
    return found;
  }

  Set<String> get _disabled {
    final claudeJson = AgentSettings.readJson(session.paths.claudeJson);
    final project = asMap(asMap(claudeJson['projects'])[session.cwd]);
    return {...asList(project['disabledMcpServers']).whereType<String>()};
  }

  /// Connects every server set up, at once; returns when each has
  /// connected or failed.
  Future<void> start() async {
    final disabled = _disabled;
    for (final server in configured().values) {
      servers[server.name] = server;
      if (disabled.contains(server.name)) server.status = 'disabled';
    }
    await Future.wait([
      for (final server in servers.values)
        if (server.status != 'disabled') connect(server),
    ]);
  }

  /// Connects the servers set up since the session began (a plugin's,
  /// installed meanwhile).
  Future<void> connectNew() async {
    final disabled = _disabled;
    final added = [
      for (final server in configured().values)
        if (!servers.containsKey(server.name)) server,
    ];
    for (final server in added) {
      servers[server.name] = server;
      if (disabled.contains(server.name)) server.status = 'disabled';
    }
    await Future.wait([
      for (final server in added)
        if (server.status != 'disabled') connect(server),
    ]);
  }

  /// Connects [server] (again).
  Future<void> connect(McpServer server) async {
    await _disconnect(server);
    server
      ..status = 'pending'
      ..error = null;
    final env = session.environment;
    try {
      final transport = server.transport = _transport(server);
      final peer = server.peer = JsonRpcPeer(transport.send);
      peer.onRequest = (method, params) =>
          _serverRequest(server, method, params);
      peer.onNotification = (method, params) =>
          _notified(server, method, params);
      transport.messages.listen(
        peer.receive,
        onDone: () {
          peer.close('the server closed the connection');
          if (server.status == 'connected') {
            server
              ..status = 'failed'
              ..error = transport.detail ?? 'The connection closed';
            onToolsChanged?.call();
          }
        },
      );
      await transport.start();
      final init = await peer.request('initialize', {
        'protocolVersion': mcpProtocolVersion,
        'capabilities': {
          'roots': {'listChanged': true},
          'elicitation': <String, Object?>{},
        },
        'clientInfo': {'name': 'baocode-agent', 'version': '1.0.0'},
      }, _timeout(env, 'MCP_TIMEOUT', 30000));
      if (transport case final StreamableHttpTransport http) {
        http.protocolVersion =
            asString(init['protocolVersion']) ?? mcpProtocolVersion;
      }
      server
        ..serverInfo = asMap(init['serverInfo'])
        ..capabilities = asMap(init['capabilities'])
        ..instructions = asText(init['instructions']);
      await peer.notify('notifications/initialized');
      await _list(server);
      server.status = 'connected';
    } on McpUnauthorized catch (error) {
      server
        ..status = 'needs-auth'
        ..resourceMetadata = error.resourceMetadata
        ..error = null;
      await _disconnect(server, keepStatus: true);
    } on Object catch (error) {
      server
        ..status = 'failed'
        ..error = ['$error', ?server.transport?.detail].join('\n');
      await _disconnect(server, keepStatus: true);
    }
    onToolsChanged?.call();
  }

  McpTransport _transport(McpServer server) {
    final config = server.config;
    final env = session.environment;
    Map<String, String> strings(Object? map) => {
      for (final MapEntry(:key, :value) in asMap(map).entries)
        if (value != null) key: expandEnv('$value', env),
    };
    switch (server.type) {
      case 'sdk':
        return SdkTransport(
          asString(config['name']) ?? server.name,
          session.hostRequest,
        );
      case 'http' || 'streamable-http':
        final url = server.urlIn(env)!;
        return StreamableHttpTransport(
          url,
          headers: strings(config['headers']),
          environment: env,
          auth: () => oauth.headers(McpOAuth.keyOf(server.name, url)),
        );
      case 'sse':
        final url = server.urlIn(env)!;
        return SseTransport(
          url,
          headers: strings(config['headers']),
          environment: env,
          auth: () => oauth.headers(McpOAuth.keyOf(server.name, url)),
        );
      default:
        final command = asString(config['command']);
        if (command == null) throw const JsonRpcError('No command to run');
        return StdioTransport(
          command: expandEnv(command, env),
          arguments: [
            for (final arg in asList(config['args'])) expandEnv('$arg', env),
          ],
          environment: {
            ...session.commandEnvironment,
            ...strings(config['env']),
          },
          workingDirectory: session.cwd,
        );
    }
  }

  /// [text] with `${VAR}` and `${VAR:-default}` filled in from [env].
  static String expandEnv(String text, Map<String, String> env) =>
      text.replaceAllMapped(
        RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}'),
        (m) {
          final value = env[m[1]!] ?? Platform.environment[m[1]!];
          return value != null && value.isNotEmpty ? value : (m[2] ?? '');
        },
      );

  Future<void> _list(McpServer server) async {
    final peer = server.peer!;
    final timeout = _timeout(session.environment, 'MCP_TIMEOUT', 30000);
    Future<List<Map<String, Object?>>> all(String method, String key) async {
      final out = <Map<String, Object?>>[];
      String? cursor;
      for (var page = 0; page < 20; page++) {
        final result = await peer.request(method, {'cursor': ?cursor}, timeout);
        out.addAll([for (final item in asList(result[key])) asMap(item)]);
        cursor = asString(result['nextCursor']);
        if (cursor == null) break;
      }
      return out;
    }

    final caps = server.capabilities;
    server.tools = caps.containsKey('tools') || caps.isEmpty
        ? await all(
            'tools/list',
            'tools',
          ).catchError((_) => <Map<String, Object?>>[])
        : const [];
    server.resources = caps.containsKey('resources')
        ? await all(
            'resources/list',
            'resources',
          ).catchError((_) => <Map<String, Object?>>[])
        : const [];
    server.prompts = caps.containsKey('prompts')
        ? await all(
            'prompts/list',
            'prompts',
          ).catchError((_) => <Map<String, Object?>>[])
        : const [];
  }

  Future<Object?> _serverRequest(
    McpServer server,
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'ping':
        return <String, Object?>{};
      case 'roots/list':
        return {
          'roots': [
            for (final dir in session.workingDirectories)
              {'uri': Uri.directory(dir).toString(), 'name': p.basename(dir)},
          ],
        };
      case 'elicitation/create':
        final asked = {
          'mcp_server_name': server.name,
          'message': params['message'],
          'mode': params['mode'] ?? (params['url'] != null ? 'url' : 'form'),
          'requested_schema': ?params['requestedSchema'],
          'url': ?params['url'],
        };
        if (session.hooks.has(HookEvent.elicitation)) {
          final hook = await session.hooks.run(
            HookEvent.elicitation,
            asked,
            query: server.name,
          );
          if (hook.blocked) return {'action': 'decline'};
        }
        final answer = await session.hostRequest('elicitation', {
          'mcp_server_name': server.name,
          'message': params['message'],
          'mode': params['mode'] ?? (params['url'] != null ? 'url' : 'form'),
          'requested_schema': ?params['requestedSchema'],
          'url': ?params['url'],
          'elicitation_id': ?params['elicitationId'],
        });
        session.hooks.notify(HookEvent.elicitationResult, {
          'mcp_server_name': server.name,
          'action': answer['action'] ?? 'cancel',
          'content': ?answer['content'],
        }, query: server.name);
        return {
          'action': answer['action'] ?? 'cancel',
          if (answer['content'] != null) 'content': answer['content'],
        };
    }
    throw JsonRpcError('Method not found: $method', code: -32601);
  }

  void _notified(McpServer server, String method, Map<String, Object?> params) {
    switch (method) {
      case 'notifications/tools/list_changed' ||
          'notifications/resources/list_changed' ||
          'notifications/prompts/list_changed':
        unawaited(
          _list(server).then((_) => onToolsChanged?.call()).catchError((_) {}),
        );
    }
  }

  Future<void> _disconnect(McpServer server, {bool keepStatus = false}) async {
    final transport = server.transport;
    server.peer?.close();
    server.peer = null;
    server.transport = null;
    if (!keepStatus) {
      server.tools = const [];
      server.resources = const [];
      server.prompts = const [];
    }
    if (transport != null) {
      try {
        await transport.close();
      } on Object {
        // Gone already.
      }
    }
  }

  /// `mcp_status`'s answer.
  Map<String, Object?> status() => {
    'mcpServers': [for (final server in servers.values) server.toStatus()],
  };

  /// Switches [name] off or on, for this folder from now on.
  Future<void> toggle(String name, bool enabled) async {
    final server = servers[name];
    if (server == null) throw StateError('No MCP server named $name');
    AgentSettings.editJson(session.paths.claudeJson, (json) {
      final projects = {...asMap(json['projects'])};
      final project = {...asMap(projects[session.cwd])};
      final disabled = [
        ...asList(project['disabledMcpServers']).whereType<String>(),
      ];
      disabled.remove(name);
      if (!enabled) disabled.add(name);
      project['disabledMcpServers'] = disabled;
      projects[session.cwd] = project;
      json['projects'] = projects;
    });
    if (enabled) {
      await connect(server);
    } else {
      await _disconnect(server);
      server
        ..status = 'disabled'
        ..error = null;
      onToolsChanged?.call();
    }
  }

  Future<void> reconnect(String name) async {
    final server = servers[name];
    if (server == null) throw StateError('No MCP server named $name');
    await connect(server);
  }

  /// Begins signing in to [name]: the page the user is to open, or null
  /// when it needs no sign-in.
  Future<Uri?> authenticate(String name) async {
    final server = servers[name];
    final url = server?.urlIn(session.environment);
    if (server == null || url == null) return null;
    return oauth.begin(
      name,
      url,
      resourceMetadata: server.resourceMetadata,
      onSignedIn: (error) {
        if (error == null) unawaited(connect(server));
      },
    );
  }

  /// Calls [tool] of [server] with [arguments].
  Future<Map<String, Object?>> callTool(
    McpServer server,
    String tool,
    Map<String, Object?> arguments, {
    String? toolUseId,
    CancelToken? cancel,
  }) async {
    final peer = server.peer;
    if (peer == null || !server.connected) {
      throw JsonRpcError('MCP server "${server.name}" is not connected');
    }
    try {
      return await peer.request(
        'tools/call',
        {
          'name': tool,
          'arguments': arguments,
          if (toolUseId != null) '_meta': {'claudecode/toolUseId': toolUseId},
        },
        _timeout(session.environment, 'MCP_TOOL_TIMEOUT', 100000000),
        cancel,
      );
    } on McpUnauthorized catch (error) {
      server
        ..status = 'needs-auth'
        ..resourceMetadata = error.resourceMetadata;
      onToolsChanged?.call();
      rethrow;
    }
  }

  Future<Map<String, Object?>> readResource(
    McpServer server,
    String uri,
  ) async {
    final peer = server.peer;
    if (peer == null) {
      throw JsonRpcError('MCP server "${server.name}" is not connected');
    }
    return peer.request('resources/read', {
      'uri': uri,
    }, const Duration(seconds: 60));
  }

  Future<Map<String, Object?>> getPrompt(
    McpServer server,
    String prompt,
    Map<String, String> arguments,
  ) async {
    final peer = server.peer;
    if (peer == null) {
      throw JsonRpcError('MCP server "${server.name}" is not connected');
    }
    return peer.request('prompts/get', {
      'name': prompt,
      'arguments': arguments,
    }, const Duration(seconds: 60));
  }

  /// The server and tool [toolName] (`mcp__server__tool`) names.
  (McpServer, Map<String, Object?>)? find(String toolName) {
    for (final server in servers.values) {
      if (!server.connected) continue;
      for (final tool in server.tools) {
        if (mcpToolName(server.name, '${tool['name']}') == toolName) {
          return (server, tool);
        }
      }
    }
    return null;
  }

  Future<void> close() async {
    await Future.wait([
      for (final server in servers.values) _disconnect(server),
    ]);
  }

  /// What the servers say of themselves, for the system prompt.
  String? get instructions {
    final parts = [
      for (final server in servers.values)
        if (server.connected && server.instructions != null)
          '## ${server.name}\n${server.instructions}',
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }
}

/// [content] (an MCP tool's result content) as the API's content blocks.
List<Map<String, Object?>> mcpContentBlocks(Object? content) {
  final blocks = <Map<String, Object?>>[];
  for (final raw in asList(content)) {
    final item = asMap(raw);
    switch (item['type']) {
      case 'text':
        blocks.add({'type': 'text', 'text': '${item['text'] ?? ''}'});
      case 'image':
        final mime = asString(item['mimeType']) ?? 'image/png';
        if (const {
          'image/png',
          'image/jpeg',
          'image/gif',
          'image/webp',
        }.contains(mime)) {
          blocks.add({
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': mime,
              'data': '${item['data'] ?? ''}',
            },
          });
        } else {
          blocks.add({'type': 'text', 'text': '[Image of type $mime]'});
        }
      case 'resource':
        final resource = asMap(item['resource']);
        if (resource['text'] case final String text) {
          blocks.add({'type': 'text', 'text': text});
        } else {
          blocks.add({
            'type': 'text',
            'text':
                '[Resource ${resource['uri']} (${resource['mimeType'] ?? 'binary'})]',
          });
        }
      case 'resource_link':
        blocks.add({
          'type': 'text',
          'text': '[Resource link: ${item['name'] ?? ''} ${item['uri'] ?? ''}]',
        });
      case 'audio':
        blocks.add({
          'type': 'text',
          'text': '[Audio of type ${item['mimeType']}]',
        });
      default:
        blocks.add({'type': 'text', 'text': jsonEncode(item)});
    }
  }
  return blocks;
}
