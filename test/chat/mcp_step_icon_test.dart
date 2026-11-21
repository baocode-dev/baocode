import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/tool_call_row.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MCP step row renders the official MCP SVG icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: ToolCallRow(
            kind: ToolKind.mcp,
            label: 'github · search_issues',
            target: 'query: mcp icon',
          ),
        ),
      ),
    );
    await tester.pump();

    final svgs = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .toList();
    expect(svgs, hasLength(1));
    final loader = svgs.single.bytesLoader;
    expect(loader, isA<SvgAssetLoader>());
    expect((loader as SvgAssetLoader).assetName, mcpIcon);
    expect(svgs.single.width, 13);
    expect(svgs.single.height, 13);
  });
}
