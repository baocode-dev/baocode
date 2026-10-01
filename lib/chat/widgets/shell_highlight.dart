import 'package:flutter/painting.dart';

import '../../theme/app_theme.dart';

/// [command] colored as a shell reads it: the program each pipeline stage
/// runs, quoted strings, options. A light tokenizer, not a parser: anything
/// it does not know stays plain.
List<TextSpan> highlightShell(String command) {
  final plain = TextStyle(color: AppColors.textPrimary);
  final program = TextStyle(color: AppColors.syntaxCommand);
  final string = TextStyle(color: AppColors.syntaxString);
  final option = TextStyle(color: AppColors.syntaxOption);

  final spans = <TextSpan>[];
  void add(String text, TextStyle style) {
    if (text.isEmpty) return;
    // Merge runs of one style, for fewer spans.
    if (spans.isNotEmpty && spans.last.style == style) {
      spans[spans.length - 1] = TextSpan(
        text: spans.last.text! + text,
        style: style,
      );
    } else {
      spans.add(TextSpan(text: text, style: style));
    }
  }

  // Whether the next word starts a command (after `&&`, `|`, `;`, `(`…).
  var commandNext = true;
  var i = 0;
  while (i < command.length) {
    final char = command[i];
    if (char == ' ' || char == '\t' || char == '\n') {
      if (char == '\n') commandNext = true;
      add(char, plain);
      i++;
      continue;
    }
    if (char == '"' || char == "'") {
      var end = i + 1;
      while (end < command.length && command[end] != char) {
        if (char == '"' && command[end] == r'\') end++;
        end++;
      }
      end = end < command.length ? end + 1 : command.length;
      add(command.substring(i, end), string);
      commandNext = false;
      i = end;
      continue;
    }
    const operators = ['&&', '||', '|', ';', '(', ')', '{', '}'];
    final operator = operators
        .where((operator) => command.startsWith(operator, i))
        .firstOrNull;
    if (operator != null) {
      add(operator, plain);
      commandNext = operator != ')' && operator != '}';
      i += operator.length;
      continue;
    }
    // A word: up to a space, a quote or an operator.
    var end = i;
    while (end < command.length && !' \t\n"\';|&(){}'.contains(command[end])) {
      end++;
    }
    if (end == i) {
      // A lone `&` (e.g. `2>&1`, a background job).
      add(char, plain);
      i++;
      continue;
    }
    final word = command.substring(i, end);
    final assignment = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(word);
    if (commandNext && !assignment) {
      add(word, program);
      commandNext = false;
    } else if (word.startsWith('-')) {
      add(word, option);
    } else {
      add(word, plain);
    }
    i = end;
  }
  return spans;
}
