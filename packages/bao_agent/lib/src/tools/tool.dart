import 'dart:async';

import '../engine/agent_run.dart';
import '../engine/session.dart';
import '../permissions/decision.dart';
import '../util/cancel.dart';

/// What a tool call comes to: what the model is told ([content], text or
/// content blocks), whether it failed, and what the host is told of it
/// ([result], the message's `tool_use_result`).
class ToolOutput {
  const ToolOutput(
    this.content, {
    this.isError = false,
    this.result,
    this.followUp = const [],
  });

  /// A failure, told the model as it is.
  factory ToolOutput.error(String message, {Object? result}) =>
      ToolOutput(message, isError: true, result: result ?? message);

  /// A string, or a list of `text`/`image`/`document` blocks.
  final Object content;
  final bool isError;
  final Object? result;

  /// Messages for the model after the result (a skill's instructions), as
  /// `{content, isMeta}` user messages.
  final List<Map<String, Object?>> followUp;

  /// [content] as text: its text blocks joined.
  String get text => switch (content) {
    final String text => text,
    final List<Object?> blocks => [
      for (final block in blocks)
        if (block is Map && block['type'] == 'text') '${block['text']}',
    ].join('\n'),
    _ => '$content',
  };
}

/// A call the tool will not take, told the model as an error.
class ToolFailure implements Exception {
  const ToolFailure(this.message, {this.result});

  final String message;
  final Object? result;

  @override
  String toString() => message;
}

/// What a tool works with: the session, the agent calling it, the call.
class ToolContext {
  ToolContext({
    required this.session,
    required this.run,
    required this.toolUseId,
    required this.cancel,
  });

  final AgentSession session;
  final AgentRun run;
  final String toolUseId;
  final CancelToken cancel;

  /// The folder relative paths are taken from.
  String get cwd => run.cwd;
}

/// A tool the model may call.
abstract class Tool {
  const Tool();

  /// As the model calls it.
  String get name;

  /// Other names it answers to (an older one).
  List<String> get aliases => const [];

  /// What the model is told of it.
  String get description;

  /// Its input, as a JSON Schema object.
  Map<String, Object?> get inputSchema;

  /// Whether it only reads: run without asking in plan mode, and alongside
  /// other such calls.
  bool isReadOnly(Map<String, Object?> input) => false;

  /// Whether calls of it may run at once with other such calls.
  bool isConcurrencySafe(Map<String, Object?> input) => isReadOnly(input);

  /// Whether the model is offered it at all.
  bool isEnabled(AgentSession session) => true;

  /// Whether a call of it is one only the user can answer (a question).
  bool get requiresUserInteraction => false;

  /// Whether a call of it should wait for a turn of its own: it changes
  /// the session's mode.
  bool get changesMode => false;

  /// What is wrong with [input] beyond its schema; null when nothing.
  Future<String?> validate(
    Map<String, Object?> input,
    ToolContext context,
  ) async => null;

  /// The tool's own view of whether [input] may run (paths in the working
  /// folders, commands allowed by a rule…). The rules for the tool as a
  /// whole and the mode are weighed by the permission engine.
  Future<PermissionDecision> checkPermissions(
    Map<String, Object?> input,
    ToolContext context,
  ) async => const PermissionPassthrough();

  /// Runs it.
  Future<ToolOutput> call(Map<String, Object?> input, ToolContext context);

  /// What the permission question names: the file, the URL.
  String? describe(Map<String, Object?> input) => null;

  /// The content a permission rule for it is matched on: the command, the
  /// path, the domain.
  String? ruleContent(Map<String, Object?> input) => null;

  /// [input] as the host is shown it, and the call is weighed and run
  /// with: what the tool fills in (the plan [ExitPlanModeTool] puts to the
  /// user). What the model sent is kept as it sent it.
  Map<String, Object?> observableInput(
    Map<String, Object?> input,
    AgentSession session,
  ) => input;

  /// What the model is told of it in [session]: [description], unless
  /// the session changes it.
  String promptFor(AgentSession session) => description;

  /// The JSON Schema dialect the tools' input is written in.
  static const schemaDialect = 'https://json-schema.org/draft/2020-12/schema';

  /// As the model is offered it.
  Map<String, Object?> toApi(AgentSession session) => {
    'name': name,
    'description': promptFor(session),
    'input_schema': {r'$schema': schemaDialect, ...inputSchema},
  };
}

/// Checks [input] against the subset of JSON Schema the tools use: the
/// type of each property, the required ones, enums. Returns what is wrong,
/// or null.
String? validateSchema(
  Map<String, Object?> schema,
  Object? input, [
  String path = '',
]) {
  final type = schema['type'];
  final at = path.isEmpty ? 'input' : path;
  switch (type) {
    case 'object':
      if (input is! Map) return 'The $at must be an object';
      final properties =
          (schema['properties'] as Map?)?.cast<String, Object?>() ?? const {};
      for (final name in (schema['required'] as List?) ?? const []) {
        if (input[name] == null) {
          return 'The required parameter `${path.isEmpty ? name : '$path.$name'}` is missing';
        }
      }
      for (final MapEntry(:key, :value) in input.entries) {
        final property = properties[key];
        if (property is! Map || value == null) continue;
        final error = validateSchema(
          property.cast<String, Object?>(),
          value,
          path.isEmpty ? '$key' : '$path.$key',
        );
        if (error != null) return error;
      }
    case 'array':
      if (input is! List) return 'The parameter `$at` must be an array';
      final items = schema['items'];
      if (items is Map) {
        for (final (i, item) in input.indexed) {
          final error = validateSchema(
            items.cast<String, Object?>(),
            item,
            '$at[$i]',
          );
          if (error != null) return error;
        }
      }
      if (schema['minItems'] case final int min when input.length < min) {
        return 'The parameter `$at` must have at least $min items';
      }
      if (schema['maxItems'] case final int max when input.length > max) {
        return 'The parameter `$at` must have at most $max items';
      }
    case 'string':
      if (input is! String) return 'The parameter `$at` must be a string';
      if (schema['enum'] case final List<Object?> values
          when !values.contains(input)) {
        return 'The parameter `$at` must be one of ${values.join(', ')}';
      }
    case 'integer':
      if (input is! int &&
          !(input is double && input == input.roundToDouble())) {
        return 'The parameter `$at` must be an integer';
      }
    case 'number':
      if (input is! num) return 'The parameter `$at` must be a number';
    case 'boolean':
      if (input is! bool) return 'The parameter `$at` must be a boolean';
  }
  return null;
}

/// [input] with what the model commonly gets wrong set right: numbers and
/// booleans sent as strings, where the schema wants them.
Map<String, Object?> coerceInput(
  Map<String, Object?> schema,
  Map<String, Object?> input,
) {
  final properties =
      (schema['properties'] as Map?)?.cast<String, Object?>() ?? const {};
  final out = <String, Object?>{...input};
  for (final MapEntry(:key, :value) in input.entries) {
    final property = properties[key];
    if (property is! Map) continue;
    switch ((property['type'], value)) {
      case ('integer', final String text)
          when int.tryParse(text.trim()) != null:
        out[key] = int.parse(text.trim());
      case ('integer', final double number)
          when number == number.roundToDouble():
        out[key] = number.toInt();
      case ('number', final String text) when num.tryParse(text.trim()) != null:
        out[key] = num.parse(text.trim());
      case ('boolean', 'true'):
        out[key] = true;
      case ('boolean', 'false'):
        out[key] = false;
    }
  }
  return out;
}
