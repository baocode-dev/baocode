// Ported from CLIProxyAPI's internal/thinking (MIT License; see NOTICE.md
// beside this file): what the translators use of it.

import 'json_value.dart';

/// The thinking levels.
abstract final class ThinkingLevel {
  static const none = 'none';
  static const auto = 'auto';
  static const minimal = 'minimal';
  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';
  static const xhigh = 'xhigh';
}

/// The level nearest a thinking budget: -1 is auto, 0 none, then minimal
/// up to 512 tokens, low to 1024, medium to 8192, high to 24576, and xhigh
/// past it. Null for a budget below -1.
String? convertBudgetToLevel(int budget) => switch (budget) {
  < -1 => null,
  -1 => ThinkingLevel.auto,
  0 => ThinkingLevel.none,
  <= 512 => ThinkingLevel.minimal,
  <= 1024 => ThinkingLevel.low,
  <= 8192 => ThinkingLevel.medium,
  <= 24576 => ThinkingLevel.high,
  _ => ThinkingLevel.xhigh,
};

/// A thinking part's text, however it is held: `text` (Gemini's),
/// `thinking` as a string, or an object with `text` or `thinking` in it.
String thinkingText(JsonValue part) {
  final text = part.get('text');
  if (text.isString) return text.string;
  final thinking = part.get('thinking');
  if (!thinking.exists) return '';
  if (thinking.isString) return thinking.string;
  if (thinking.isObject) {
    for (final key in const ['text', 'thinking']) {
      final inner = thinking.get(key);
      if (inner.isString) return inner.string;
    }
  }
  return '';
}

/// A model name and the thinking setting after it in parentheses, as in
/// `gpt-5(high)` or `claude-sonnet-4-5(16384)`.
typedef ModelSuffix = ({String modelName, bool hasSuffix, String rawSuffix});

/// Splits [model] into its name and suffix, as [ModelSuffix].
ModelSuffix parseSuffix(String model) {
  final open = model.lastIndexOf('(');
  if (open == -1 || !model.endsWith(')')) {
    return (modelName: model, hasSuffix: false, rawSuffix: '');
  }
  return (
    modelName: model.substring(0, open),
    hasSuffix: true,
    rawSuffix: model.substring(open + 1, model.length - 1),
  );
}
