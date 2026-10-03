// Ported from CLIProxyAPI's internal/util (MIT License; see NOTICE.md beside
// this file): what the translators use of it.

import 'dart:convert';

import 'json_value.dart';

/// Leads the system block Claude Code adds for billing and prompt
/// fingerprints: not prompt text for another provider.
const _claudeCodeAttributionSystemPrefix = 'x-anthropic-billing-header:';

/// Whether [text] is Claude Code's attribution block.
bool isClaudeCodeAttributionSystemText(String text) =>
    text.trimLeft().startsWith(_claudeCodeAttributionSystemPrefix);

/// Whether a regular expression has what strict upstream JSON Schema
/// validators reject in a `pattern`, though Anthropic's API takes it: a
/// Unicode property escape (`\p{…}`, `\P{…}`) or the octal NUL escape
/// (`\0`). Dropping the pattern is safe: the client checks its own input.
bool hasUnsupportedUnicodePropertyEscape(String pattern) {
  for (var i = 0; i < pattern.length; i++) {
    if (pattern[i] != r'\') continue;
    if (i + 1 >= pattern.length) break;
    final next = pattern[i + 1];
    if ((next == 'p' || next == 'P') &&
        i + 2 < pattern.length &&
        pattern[i + 2] == '{') {
      return true;
    }
    if (next == '0') return true;
    i++; // The escaped character, an escaped backslash too.
  }
  return false;
}

/// JSON Schema keywords whose values are maps of subschemas.
const schemaMapKeywords = [
  'properties',
  r'$defs',
  'definitions',
  'patternProperties',
  'dependentSchemas',
  'dependencies',
];

/// JSON Schema keywords with one subschema, or a list of them.
const schemaValueKeywords = [
  'items',
  'prefixItems',
  'contains',
  'additionalProperties',
  'propertyNames',
  'unevaluatedProperties',
  'unevaluatedItems',
  'additionalItems',
  'contentSchema',
  'anyOf',
  'oneOf',
  'allOf',
  'not',
  'if',
  'then',
  'else',
];

/// Single-quoted strings in [input] as double-quoted ones, so that the
/// near-JSON some models write as tool arguments parses. Double-quoted
/// strings are kept as they are.
String fixJson(String input) {
  final out = StringBuffer();
  var inDouble = false;
  var inSingle = false;
  var escaped = false;
  final runes = input.runes.toList();
  bool isHex(int r) =>
      (r >= 0x30 && r <= 0x39) ||
      (r >= 0x61 && r <= 0x66) ||
      (r >= 0x41 && r <= 0x46);
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    final char = String.fromCharCode(r);
    if (inDouble) {
      out.write(char);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') inDouble = false;
      continue;
    }
    if (inSingle) {
      if (escaped) {
        escaped = false;
        switch (char) {
          case 'n' || 'r' || 't' || 'b' || 'f' || '/' || '"':
            out.write('\\$char');
          case r'\':
            out.write(r'\\');
          case "'":
            out.write("'");
          case 'u':
            out.write(r'\u');
            for (var k = 0; k < 4 && i + 1 < runes.length; k++) {
              if (!isHex(runes[i + 1])) break;
              out.writeCharCode(runes[++i]);
            }
          default:
            out.write('\\$char');
        }
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == "'") {
        out.write('"');
        inSingle = false;
        continue;
      }
      out.write(char == '"' ? r'\"' : char);
      continue;
    }
    if (char == '"') {
      inDouble = true;
      out.write(char);
      continue;
    }
    if (char == "'") {
      inSingle = true;
      out.write('"');
      continue;
    }
    out.write(char);
  }
  if (inSingle) out.write('"');
  return '$out';
}

/// Whether [text] is valid JSON.
bool isValidJson(String text) {
  try {
    jsonDecode(text);
    return true;
  } on FormatException {
    return false;
  }
}

final _toolIdSanitizer = RegExp(r'[^a-zA-Z0-9_-]');
var _toolIdCounter = 0;

/// [id] as Claude's `tool_use.id` must be (`^[a-zA-Z0-9_-]+$`): other
/// characters replaced with `_`, a fresh id for an empty one.
String sanitizeClaudeToolId(String id) {
  final sanitized = id.replaceAll(_toolIdSanitizer, '_');
  if (sanitized.isNotEmpty) return sanitized;
  final now = DateTime.now().microsecondsSinceEpoch * 1000;
  return 'toolu_${now}_${++_toolIdCounter}';
}

/// A tool's name as matched across providers: trimmed, without leading
/// underscores, lower case.
String canonicalToolName(String name) {
  var canonical = name.trim();
  while (canonical.startsWith('_')) {
    canonical = canonical.substring(1);
  }
  return canonical.toLowerCase();
}

/// The names of the tools a Claude request declares, by their
/// [canonicalToolName]; null when there are none.
Map<String, String>? toolNameMapFromClaudeRequest(JsonValue request) {
  final tools = request.get('tools');
  if (!tools.isArray) return null;
  final out = <String, String>{};
  for (final tool in tools.array) {
    var name = tool.get('name').string.trim();
    if (name.isEmpty) name = tool.get('function.name').string.trim();
    if (name.isEmpty) continue;
    final key = canonicalToolName(name);
    if (key.isEmpty) continue;
    out.putIfAbsent(key, () => name);
  }
  return out.isEmpty ? null : out;
}

/// [name] as the request declared it, when a model changed its case or
/// leading underscores.
String mapToolName(Map<String, String>? toolNameMap, String name) {
  if (name.isEmpty || toolNameMap == null) return name;
  final mapped = toolNameMap[canonicalToolName(name)];
  return mapped == null || mapped.isEmpty ? name : mapped;
}
