/// An MCP server asking the user for input (an elicitation), as the CLI
/// passes it on: its form as questions, and the answers as what the server
/// takes back.
library;

import '../kernel_types.dart';

/// What a field of an elicitation's form takes.
enum ElicitationKind { text, number, integer, boolean, choice, choices }

/// A field of an elicitation's form (its `requested_schema`, a flat object
/// of primitive properties, as MCP allows).
class ElicitationField {
  const ElicitationField({
    required this.name,
    required this.kind,
    this.title,
    this.description,
    this.required = false,
    this.options = const [],
  });

  final String name;
  final ElicitationKind kind;
  final String? title;
  final String? description;
  final bool required;

  /// For a choice: each value, and what it shows as.
  final List<({Object value, String label})> options;

  String get label => title ?? name;
}

/// The label of a field left blank.
const elicitationBlank = 'Leave blank';

/// What is typed into a field that takes words.
const elicitationTypeHere = 'Type here';

const _yes = 'Yes';
const _no = 'No';
const _accept = 'Accept';
const _decline = 'Decline';

/// The fields of [schema]; empty when it asks for none (a confirmation).
List<ElicitationField> elicitationFields(Object? schema) {
  if (schema is! Map) return const [];
  final properties = schema['properties'];
  if (properties is! Map) return const [];
  final required = {...?(schema['required'] as List?)?.map((e) => '$e')};
  String? text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };
  List<({Object value, String label})> optionsOf(Map property) {
    if (property['enum'] case final List values) {
      final names = property['enumNames'] as List?;
      return [
        for (final (i, value) in values.indexed)
          if (value != null)
            (
              value: value as Object,
              label: names != null && i < names.length
                  ? '${names[i]}'
                  : '$value',
            ),
      ];
    }
    final variants = property['oneOf'] ?? property['anyOf'];
    if (variants is List) {
      return [
        for (final variant in variants)
          if (variant is Map && variant['const'] != null)
            (
              value: variant['const'] as Object,
              label: text(variant['title']) ?? '${variant['const']}',
            ),
      ];
    }
    return const [];
  }

  return [
    for (final MapEntry(:key, :value) in properties.entries)
      if (value is Map)
        () {
          final type = value['type'];
          final items = value['items'];
          final options = type == 'array' && items is Map
              ? optionsOf(items)
              : optionsOf(value);
          final kind = switch (type) {
            'array' => ElicitationKind.choices,
            _ when options.isNotEmpty => ElicitationKind.choice,
            'boolean' => ElicitationKind.boolean,
            'number' => ElicitationKind.number,
            'integer' => ElicitationKind.integer,
            _ => ElicitationKind.text,
          };
          return ElicitationField(
            name: '$key',
            kind: kind,
            title: text(value['title']),
            description: text(value['description']),
            required: required.contains('$key'),
            options: kind == ElicitationKind.boolean
                ? const [(value: true, label: _yes), (value: false, label: _no)]
                : options,
          );
        }(),
  ];
}

/// [fields] as questions, the first under [message]; a confirmation (no
/// fields) as one to accept or decline.
List<Question> elicitationQuestions(
  String message,
  List<ElicitationField> fields,
) {
  if (fields.isEmpty) {
    return [
      Question(
        prompt: message,
        options: const [QuestionOption(_accept), QuestionOption(_decline)],
        allowOther: false,
      ),
    ];
  }
  return [
    for (final (i, field) in fields.indexed)
      () {
        final about = [
          if (field.title != null && field.description == null) field.title!,
          ?field.description,
        ].join('\n');
        final prompt = [
          if (i == 0 && message.isNotEmpty) message,
          if (about.isNotEmpty) about,
        ].join('\n\n');
        final words = switch (field.kind) {
          ElicitationKind.text ||
          ElicitationKind.number ||
          ElicitationKind.integer => true,
          _ => false,
        };
        return Question(
          prompt: prompt.isEmpty ? field.label : prompt,
          header: field.required ? '${field.label} *' : field.label,
          allowMultiple: field.kind == ElicitationKind.choices,
          allowOther: words,
          otherLabel: words ? elicitationTypeHere : null,
          options: [
            for (final option in field.options) QuestionOption(option.label),
            if (!field.required && !words)
              const QuestionOption(elicitationBlank),
          ],
        );
      }(),
  ];
}

/// What the server takes back for [answer] to [fields]: `accept` with the
/// values given, `decline`, or `cancel` (dismissed, or a value it would
/// refuse).
Map<String, Object?> elicitationResult(
  List<ElicitationField> fields,
  QuestionAnswer answer,
) {
  if (answer.skipped) return {'action': 'cancel'};
  if (fields.isEmpty) {
    final pick = answer.picks.firstOrNull?.firstOrNull;
    return {'action': pick == _accept ? 'accept' : 'decline'};
  }
  final content = <String, Object?>{};
  for (final (i, field) in fields.indexed) {
    final picks = <String>[
      for (final pick
          in i < answer.picks.length ? answer.picks[i] : const <String>[])
        if (pick != elicitationBlank && pick != elicitationTypeHere) pick,
    ];
    final value = _value(field, picks);
    if (value == null) {
      if (field.required) return {'action': 'cancel'};
      continue;
    }
    content[field.name] = value;
  }
  return {'action': 'accept', 'content': content};
}

Object? _value(ElicitationField field, List<String> picks) {
  Object? valueOf(String label) =>
      field.options.where((o) => o.label == label).firstOrNull?.value;
  switch (field.kind) {
    case ElicitationKind.choices:
      final values = [for (final pick in picks) ?valueOf(pick)];
      return values.isEmpty && !field.required ? null : values;
    case ElicitationKind.choice || ElicitationKind.boolean:
      return picks.isEmpty ? null : valueOf(picks.first);
    case ElicitationKind.text:
      final text = picks.firstOrNull?.trim() ?? '';
      return text.isEmpty ? null : text;
    case ElicitationKind.number:
      return num.tryParse(picks.firstOrNull?.trim() ?? '');
    case ElicitationKind.integer:
      return int.tryParse(picks.firstOrNull?.trim() ?? '');
  }
}
