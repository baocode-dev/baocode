import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_document_model.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/editor/monaco/flutter/editor_surface_controller.dart';
import 'package:baocode/ide/editor/monaco/flutter/monaco_syntax.dart';

void main() {
  testWidgets(
    'painted surface accepts exact-text Monarch spans and updates them',
    (tester) async {
      final document = EditorDocumentModel('class A {}');
      final controller = EditorSurfaceController(document: document);
      addTearDown(() {
        controller.dispose();
        document.dispose();
      });
      final syntax = MonacoSyntaxService();
      final lines = await syntax.tokenize(document.snapshot, 'dart');
      final spans = syntax.styledLines(
        document.snapshot,
        lines,
        (token) => token.contains('keyword')
            ? const TextStyle(color: Color(0xffff0000))
            : null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 480,
              height: 120,
              child: EditorSurface(controller: controller, styledLines: spans),
            ),
          ),
        ),
      );
      expect(find.byType(EditorSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 480,
              height: 120,
              child: EditorSurface(
                controller: controller,
                styledLines: {
                  1: [const TextSpan(text: 'class A {}')],
                },
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
