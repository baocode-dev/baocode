import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';

const _codeStyle = TextStyle(
  color: CursorColors.inlineCode,
  fontFamily: CursorFonts.mono,
  fontSize: 12.5,
  backgroundColor: Color(0xFF2A2A2A),
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

/// Assistant prose with `inline code` spans and `- ` bullet lines.
class AssistantText extends StatelessWidget {
  const AssistantText(this.text, {super.key});

  final String text;

  static const _baseStyle = TextStyle(
    color: CursorColors.text,
    fontSize: 13.5,
    height: 1.6,
  );

  static TextSpan _inline(String line) {
    final parts = line.split('`');
    return TextSpan(
      style: _baseStyle,
      children: [
        for (var i = 0; i < parts.length; i++)
          if (parts[i].isNotEmpty)
            TextSpan(
              text: i.isOdd ? ' ${parts[i]} ' : parts[i],
              style: i.isOdd ? _codeStyle : null,
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          if (line.isEmpty)
            const SizedBox(height: 8)
          else if (line.startsWith('- '))
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 16,
                    child: Text(
                      '•',
                      style: TextStyle(
                        color: CursorColors.textMuted,
                        fontSize: 13.5,
                        height: 1.6,
                      ),
                    ),
                  ),
                  Expanded(child: Text.rich(_inline(line.substring(2)))),
                ],
              ),
            )
          else
            Text.rich(_inline(line)),
      ],
    );
  }
}
