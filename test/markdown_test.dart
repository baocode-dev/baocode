import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/chat/widgets/markdown_view.dart';

Future<void> pumpMarkdown(WidgetTester tester, String data) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: MarkdownView(data))));

/// The leaf spans of the text shown, with their recognizers.
List<TextSpan> leaves(WidgetTester tester) {
  final spans = <TextSpan>[];
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    text.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.isNotEmpty ?? false)) {
        spans.add(span);
      }
      return true;
    });
  }
  return spans;
}

void main() {
  group('links', () {
    testWidgets('every word of a web link is tappable', (tester) async {
      await pumpMarkdown(
        tester,
        'See [the **Flutter** docs](https://docs.flutter.dev) or '
        'https://dart.dev.',
      );
      final linked = {
        for (final span in leaves(tester))
          if (span.recognizer is TapGestureRecognizer) span.text,
      };
      expect(linked, containsAll(['the ', 'Flutter', ' docs']));
      expect(linked, contains('https://dart.dev'));
      expect(linked, isNot(contains('See ')));
    });

    testWidgets('a link to anything but the web or mail opens nothing', (
      tester,
    ) async {
      await pumpMarkdown(
        tester,
        '[a file](file:///etc/hosts) [an app](/Applications/Calculator.app) '
        '[mail](mailto:a@b.c)',
      );
      final linked = {
        for (final span in leaves(tester))
          if (span.recognizer != null) span.text,
      };
      expect(linked, {'mail'});
    });
  });

  group('math', () {
    testWidgets('inline and display TeX is typeset', (tester) async {
      await pumpMarkdown(
        tester,
        r'Euler: $e^{i\pi} + 1 = 0$, and \(x^2\).'
        '\n\n'
        r'$$'
        '\n'
        r'\int_0^1 x\,dx = \frac{1}{2}'
        '\n'
        r'$$',
      );
      final formulas = tester.widgetList<Math>(find.byType(Math)).toList();
      expect(formulas.map((math) => math.parseError), everyElement(isNull));
      expect(formulas, hasLength(3));
      expect(find.textContaining('Euler:', findRichText: true), findsOne);
    });

    testWidgets('prices stay text', (tester) async {
      await pumpMarkdown(tester, r'It costs $5 and $10, not $ 3 $.');
      expect(find.byType(Math), findsNothing);
      expect(
        find.textContaining(r'It costs $5 and $10', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a half-streamed formula shows its source', (tester) async {
      await pumpMarkdown(tester, r'$$\frac{1}{$$');
      expect(find.textContaining(r'\frac{1}{'), findsOneWidget);
    });
  });
}
