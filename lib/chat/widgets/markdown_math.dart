import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../theme/app_theme.dart';

/// TeX in markdown, as `math` elements (their `display` attribute `block`
/// or `inline`), for [MathView] to render.
///
/// Blocks: `$$ … $$` or `\[ … \]`, on lines of their own (or one line).
class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^ {0,3}(\$\$|\\\[)(.*)$');

  @override
  md.Node parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content)!;
    final close = match[1] == r'$$' ? r'$$' : r'\]';
    final first = match[2]!.trimRight();
    parser.advance();
    final lines = <String>[];
    if (first.endsWith(close)) {
      lines.add(first.substring(0, first.length - close.length));
    } else {
      if (first.trim().isNotEmpty) lines.add(first);
      // Unclosed (still streaming): to the end.
      while (!parser.isDone) {
        final line = parser.current.content.trimRight();
        parser.advance();
        if (line.endsWith(close)) {
          lines.add(line.substring(0, line.length - close.length));
          break;
        }
        lines.add(line);
      }
    }
    return md.Element('math', [md.Text(lines.join('\n').trim())])
      ..attributes['display'] = 'block';
  }
}

/// Inline: `$ … $`, `\( … \)`, and `$$ … $$` within a line (displayed).
/// A `$` opens only before a non-space and closes only after one, and not
/// before a digit, so prices ("$5 and $10") stay text.
class InlineMathSyntax extends md.InlineSyntax {
  InlineMathSyntax()
    : super(
        r'\$\$([^$]+?)\$\$'
        r'|\\\((.+?)\\\)'
        r'|\$(?![\s$])([^$\n]+?)(?<!\s)\$(?!\d)',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    parser.addNode(
      md.Element.text('math', match[1] ?? match[2] ?? match[3]!)
        ..attributes['display'] = display ? 'block' : 'inline',
    );
    return true;
  }
}

/// [tex] typeset; as its source, monospaced, when it does not parse (e.g.
/// half streamed).
class MathView extends StatelessWidget {
  const MathView(this.tex, {super.key, this.display = false});

  final String tex;
  final bool display;

  static TextStyle get _style =>
      TextStyle(color: AppColors.textPrimary, fontSize: 14.5);

  @override
  Widget build(BuildContext context) {
    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: _style,
      onErrorFallback: (_) => Text(
        display ? tex : '\$$tex\$',
        style: AppFonts.codeStyle(12.5).copyWith(color: AppColors.inlineCode),
      ),
    );
    if (!display) return math;
    // Wide formulas scroll rather than overflow.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: math,
    );
  }
}
