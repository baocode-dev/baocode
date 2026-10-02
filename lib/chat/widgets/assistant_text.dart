import 'package:flutter/material.dart';

import 'inline_code.dart';
import 'markdown_view.dart';

/// Splits [text] on backticks, rendering odd segments as inline code (on
/// their background in an [InlineCodeText]).
TextSpan inlineCodeSpan(String text, TextStyle style) {
  final parts = text.split('`');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          i.isOdd
              ? InlineCodeSpan(
                  text: ' ${parts[i]} ',
                  style: MarkdownView.codeStyle,
                )
              : TextSpan(text: parts[i]),
    ],
  );
}

/// Assistant prose, as markdown.
class AssistantText extends StatelessWidget {
  const AssistantText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => MarkdownView(text);
}
