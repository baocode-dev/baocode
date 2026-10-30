import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_image_preview.dart';

void main() {
  testWidgets('the image preview shows the zoom it was left with, and tells '
      'it as it goes', (tester) async {
    final svg = Uint8List.fromList(
      utf8.encode(
        '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
        '<rect width="10" height="10"/></svg>',
      ),
    );
    final zoomed = (Matrix4.identity()
          ..scaleByDouble(3, 3, 1, 1)
          ..translateByDouble(-5, -7, 0, 1))
        .storage
        .toList();
    List<double>? left;
    await tester.pumpWidget(
      MaterialApp(
        home: IdeImagePreview(
          path: '/p/a.svg',
          read: (_) async => svg,
          initialTransform: zoomed,
          onLeave: (transform) => left = transform,
        ),
      ),
    );
    await tester.pump();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.transformationController!.value.storage.toList(), zoomed);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(left, zoomed);
  });
}
