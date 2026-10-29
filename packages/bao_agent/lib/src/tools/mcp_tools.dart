import 'dart:convert';

import '../engine/session.dart';
import '../mcp/jsonrpc.dart';
import '../mcp/mcp_manager.dart';
import '../permissions/decision.dart';
import '../util/json.dart';
import 'tool.dart';

/// A tool of an MCP server, as the model calls it (`mcp__server__tool`).
class McpTool extends Tool {
  McpTool(this.server, this.definition)
    : name = mcpToolName(server.name, '${definition['name']}');

  final McpServer server;
  final Map<String, Object?> definition;

  @override
  final String name;

  String get toolName => '${definition['name']}';

  /// The most an answer may be, in tokens (about 4 characters each).
  static const defaultMaxTokens = 25000;

  @override
  String get description {
    final text = asText(definition['description']) ?? toolName;
    // Long descriptions cost every request.
    return text.length > 2048 ? '${text.substring(0, 2048)}…' : text;
  }

  @override
  Map<String, Object?> get inputSchema {
    final schema = asMap(definition['inputSchema']);
    return schema.isEmpty
        ? const {'type': 'object', 'properties': <String, Object?>{}}
        : {...schema, 'type': 'object'};
  }

  /// As the server gave it.
  @override
  Map<String, Object?> toApi(AgentSession session) => {
    'name': name,
    'description': promptFor(session),
    'input_schema': inputSchema,
  };

  Map<String, Object?> get _annotations => asMap(definition['annotations']);

  @override
  bool isReadOnly(Map<String, Object?> input) =>
      _annotations['readOnlyHint'] == true;

  @override
  bool isConcurrencySafe(Map<String, Object?> input) => isReadOnly(input);

  @override
  String? describe(Map<String, Object?> input) =>
      asText(_annotations['title']) ?? asText(definition['title']);

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    // The host's own servers do only what the app does.
    if (server.scope == 'sdk') return const PermissionAllow(reason: 'sdk');
    return PermissionPassthrough(
      suggestions: [
        addRulesSuggestion([name]),
      ],
    );
  }

  @override
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async => null;

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    Map<String, Object?> result;
    try {
      result = await context.session.mcp.callTool(
        server,
        toolName,
        input,
        toolUseId: context.toolUseId,
        cancel: context.cancel,
      );
    } on JsonRpcError catch (error) {
      return ToolOutput.error('MCP error: ${error.message}');
    }
    var blocks = mcpContentBlocks(result['content']);
    if (blocks.isEmpty && result['structuredContent'] != null) {
      blocks = [
        {'type': 'text', 'text': jsonEncode(result['structuredContent'])},
      ];
    }
    final maxTokens =
        asInt(context.session.environment['MAX_MCP_OUTPUT_TOKENS']) ??
        defaultMaxTokens;
    blocks = _limited(blocks, maxTokens * 4);
    final isError = result['isError'] == true;
    return ToolOutput(
      blocks.isEmpty ? '(no content)' : blocks,
      isError: isError,
      result: blocks,
    );
  }

  /// [blocks] cut to [maxChars] of text in all.
  static List<Map<String, Object?>> _limited(
    List<Map<String, Object?>> blocks,
    int maxChars,
  ) {
    var used = 0;
    final out = <Map<String, Object?>>[];
    for (final block in blocks) {
      if (block['type'] != 'text') {
        out.add(block);
        continue;
      }
      final text = '${block['text']}';
      if (used + text.length <= maxChars) {
        used += text.length;
        out.add(block);
        continue;
      }
      final room = maxChars - used;
      if (room > 0) {
        out.add({'type': 'text', 'text': text.substring(0, room)});
      }
      out.add({
        'type': 'text',
        'text':
            '\n\n[Output truncated: the tool returned more than the '
            '${maxChars ~/ 4} tokens allowed (MAX_MCP_OUTPUT_TOKENS). Ask '
            'it for less, e.g. with a narrower query or pagination.]',
      });
      break;
    }
    return out;
  }
}

/// Lists the resources the MCP servers offer.
class ListMcpResourcesTool extends Tool {
  const ListMcpResourcesTool();

  @override
  String get name => 'ListMcpResourcesTool';

  @override
  String get description =>
      'Lists what resources the connected MCP servers offer, each with the '
      'server it is on (its server field). Give server for one server\'s '
      'alone.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'server': {'type': 'string', 'description': 'Only this server\'s'},
    },
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  @override
  bool isEnabled(session) => session.mcp.servers.values.any(
    (s) => s.connected && s.resources.isNotEmpty,
  );

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final only = asText(input['server']);
    final servers = context.session.mcp.servers.values.where(
      (s) => s.connected && (only == null || s.name == only),
    );
    if (only != null && servers.isEmpty) {
      return ToolOutput.error('No server "$only" is connected.');
    }
    final resources = [
      for (final server in servers)
        for (final resource in server.resources)
          {...resource, 'server': server.name},
    ];
    return ToolOutput(
      resources.isEmpty
          ? 'No server has resources (a server may still have tools).'
          : jsonEncode(resources),
      result: resources,
    );
  }
}

/// Reads a resource of an MCP server.
class ReadMcpResourceTool extends Tool {
  const ReadMcpResourceTool();

  @override
  String get name => 'ReadMcpResourceTool';

  @override
  String get description =>
      'Reads one resource of an MCP server, by the server\'s name and the '
      'resource\'s URI.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'server': {'type': 'string', 'description': 'The server, by name'},
      'uri': {'type': 'string', 'description': 'The resource, by URI'},
    },
    'required': ['server', 'uri'],
    'additionalProperties': false,
  };

  @override
  bool isReadOnly(Map<String, Object?> input) => true;

  @override
  bool isEnabled(session) => session.mcp.servers.values.any(
    (s) => s.connected && s.resources.isNotEmpty,
  );

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionAllow();

  @override
  Future<ToolOutput> call(
    Map<String, Object?> input,
    ToolContext context,
  ) async {
    final name = '${input['server']}';
    final server = context.session.mcp.servers[name];
    if (server == null || !server.connected) {
      return ToolOutput.error('No server "$name" is connected.');
    }
    try {
      final result = await context.session.mcp.readResource(
        server,
        '${input['uri']}',
      );
      final contents = [
        for (final raw in asList(result['contents']))
          if (asMap(raw)['text'] case final String text)
            {
              'uri': asMap(raw)['uri'],
              'mimeType': asMap(raw)['mimeType'],
              'text': text,
            }
          else
            {
              'uri': asMap(raw)['uri'],
              'mimeType': asMap(raw)['mimeType'],
              'text':
                  '[binary content, ${'${asMap(raw)['blob'] ?? ''}'.length * 3 ~/ 4} bytes]',
            },
      ];
      return ToolOutput(
        jsonEncode({'contents': contents}),
        result: {'contents': contents},
      );
    } on JsonRpcError catch (error) {
      return ToolOutput.error('MCP error: ${error.message}');
    }
  }
}
