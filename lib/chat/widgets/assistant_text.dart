import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'markdown_view.dart';

TextStyle get _codeStyle => TextStyle(
  color: AppColors.inlineCode,
  fontFamily: AppFonts.mono,
  fontSize: 12.5,
  backgroundColor: AppColors.inlineCodeBackground,
);

/// Splits [text] on backticks, rendering odd segments as inline code.
TextSpan inlineCodeSpan(String text, TextStyle style) {
  final parts = text.split('`');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty)
          TextSpan(
            text: i.isOdd ? ' ${parts[i]} ' : parts[i],
            style: i.isOdd ? _codeStyle : null,
          ),
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
