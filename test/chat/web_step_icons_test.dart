import 'dart:convert';
import 'dart:typed_data';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/step_folds.dart';
import 'package:baocode/chat/widgets/content_image.dart';
import 'package:baocode/chat/widgets/fold_line.dart';
import 'package:baocode/chat/widgets/tool_call_row.dart';
import 'package:baocode/chat/widgets/web_step_icons.dart';
import 'package:baocode/icons/icon_library.dart';
import 'package:baocode/icons/site_icons.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+'
    'ip1sAAAAASUVORK5CYII=';

final _pngBytes = Uint8List.fromList(base64Decode(_pixel));

Uint8List _svgBytes(String color) => Uint8List.fromList(
  utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">'
    '<circle cx="8" cy="8" r="7" fill="$color"/></svg>',
  ),
);

Future<SiteIcons> _siteIconsWith(
  WidgetTester tester,
  Iterable<String> hosts,
) async => (await tester.runAsync(() async {
  final library = IconLibrary();
  var i = 0;
  for (final host in hosts) {
    final color =
        '#${(0x336699 + i * 0x112233).toRadixString(16).substring(0, 6)}';
    await library.add(_svgBytes(color), name: host);
    i++;
  }
  return SiteIcons(library: library, fetch: (_, _) async => null);
}))!;

void main() {
  late SiteIcons previous;

  setUp(() {
    previous = SiteIcons.current;
  });

  tearDown(() {
    SiteIcons.current = previous;
  });

  group('webSearchResultSites', () {
    test('parses Results: and Links: JSON lines and deduplicates by host', () {
      final resultsOutput =
          'Search results for "flutter":\n\n'
          'Results: ${jsonEncode([
            {'title': 'Dart', 'url': 'https://dart.dev/docs'},
            {'title': 'Dart guides', 'url': 'https://DART.DEV/guides'},
            {'title': 'Flutter', 'url': 'https://flutter.dev/'},
          ])}\n\nSummary text.';
      expect(webSearchResultSites(resultsOutput).map((u) => u.host).toList(), [
        'dart.dev',
        'flutter.dev',
      ]);

      final linksOutput =
          'Web search results for query: "pub"\n\n'
          'Links: ${jsonEncode([
            {'title': 'Pub', 'url': 'https://pub.dev/packages'},
            {'title': 'Invalid', 'url': 'not a url'},
          ])}';
      expect(webSearchResultSites(linksOutput).map((u) => u.host).toList(), [
        'pub.dev',
      ]);
    });

    test('resolves Google Grounding redirect URLs from domain titles only', () {
      final output =
          'Results: ${jsonEncode([
            {'title': 'huggingface.co', 'url': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/AAA'},
            {'title': 'Q2BStudio.com', 'url': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/BBB'},
            {'title': 'Not a domain title', 'url': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/CCC'},
            {'title': 'localhost', 'url': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/DDD'},
            {'title': 'huggingface.co', 'url': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/EEE'},
          ])}';
      expect(webSearchResultSites(output), [
        Uri.parse('https://huggingface.co'),
        Uri.parse('https://q2bstudio.com'),
      ]);
    });

    test('returns empty for null, empty, or malformed output', () {
      expect(webSearchResultSites(null), isEmpty);
      expect(webSearchResultSites(''), isEmpty);
      expect(webSearchResultSites('Results: [not json'), isEmpty);
      expect(webSearchResultSites('No links here'), isEmpty);
    });
  });

  group('foldWebIcons', () {
    test('deduplicates searches to one globe and fetches by host', () {
      final icons = foldWebIcons([
        const ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebSearch',
          target: 'first query',
        ),
        const ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebFetch',
          target: 'https://dart.dev/docs',
        ),
        const ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebSearch',
          target: 'second query',
        ),
        const ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebFetch',
          target: 'https://DART.DEV/guides',
        ),
        const ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebFetch',
          target: 'https://flutter.dev',
          status: ToolStatus.failed,
        ),
        const ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebFetch',
          target: 'https://pub.dev',
        ),
      ]);
      expect(icons, [
        const FoldWebSearchIcon(),
        FoldWebSiteIcon(Uri.parse('https://dart.dev/docs')),
        FoldWebSiteIcon(Uri.parse('https://pub.dev')),
      ]);
    });

    test('uses WebSearch result sites and deduplicates with WebFetch', () {
      final output =
          'Results: ${jsonEncode([
            {'title': 'huggingface.co', 'url': 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/1'},
            {'title': 'Dart', 'url': 'https://dart.dev/docs'},
          ])}';
      final icons = foldWebIcons([
        ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebSearch',
          target: 'query',
          output: output,
        ),
        const ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebFetch',
          target: 'https://dart.dev/guides',
        ),
        const ToolCallItem(
          kind: ToolKind.web,
          tool: 'WebFetch',
          target: 'https://pub.dev',
        ),
      ]);
      expect(icons, [
        FoldWebSiteIcon(Uri.parse('https://huggingface.co')),
        FoldWebSiteIcon(Uri.parse('https://dart.dev/docs')),
        FoldWebSiteIcon(Uri.parse('https://pub.dev')),
      ]);
    });
  });

  group('ToolCallRow web icons', () {
    testWidgets(
      'WebSearch shows globe icon; WebFetch shows favicon only if present',
      (tester) async {
        SiteIcons.current = await _siteIconsWith(tester, ['dart.dev']);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ToolCallRow(
                    kind: ToolKind.web,
                    tool: 'WebSearch',
                    label: 'Searched the web',
                    target: 'Flutter 2026',
                  ),
                  ToolCallRow(
                    kind: ToolKind.web,
                    tool: 'WebFetch',
                    target: 'https://dart.dev',
                  ),
                  ToolCallRow(
                    kind: ToolKind.web,
                    tool: 'WebFetch',
                    target: 'https://no-icon.example',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        final rows = find.byType(ToolCallRow);
        expect(
          find.descendant(of: rows.at(0), matching: find.byType(SvgPicture)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rows.at(1), matching: find.byType(SvgPicture)),
          findsOneWidget,
        );
        // Without a site favicon, falls back to the globe icon.
        expect(
          find.descendant(of: rows.at(2), matching: find.byType(SvgPicture)),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'WebSearch row shows stacked result site icons when collapsed and hides when expanded',
      (tester) async {
        SiteIcons.current = await _siteIconsWith(tester, [
          'a.example',
          'b.example',
          'c.example',
          'd.example',
          'e.example',
          'f.example',
        ]);
        final output =
            'Results: ${jsonEncode([
              for (final host in ['a.example', 'b.example', 'c.example', 'd.example', 'e.example', 'f.example']) {'title': host, 'url': 'https://$host/article'},
            ])}';

        Widget buildRow({required bool expanded}) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ToolCallRow(
              kind: ToolKind.web,
              tool: 'WebSearch',
              label: 'Searched the web',
              target: 'latest models',
              output: output,
              expanded: expanded,
              onToggle: () {},
            ),
          ),
        );

        await tester.pumpWidget(buildRow(expanded: false));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(StepWebIcons),
            matching: find.byType(Positioned),
          ),
          findsNWidgets(5),
        );
        expect(find.text('+1'), findsOneWidget);

        await tester.pumpWidget(buildRow(expanded: true));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(StepWebIcons),
            matching: find.byType(Positioned),
          ),
          findsNothing,
        );
      },
    );
  });

  group('folded web icons', () {
    final image = ImageAttachment(bytes: _pngBytes, mediaType: 'image/png');

    testWidgets('stacks up to 5 badges with +n and renders before images', (
      tester,
    ) async {
      SiteIcons.current = await _siteIconsWith(tester, [
        'a.example',
        'b.example',
        'c.example',
        'd.example',
        'e.example',
        'f.example',
      ]);

      final webIcons = <FoldWebIcon>[
        const FoldWebSearchIcon(),
        FoldWebSiteIcon(Uri.parse('https://a.example')),
        FoldWebSiteIcon(Uri.parse('https://missing.example')),
        FoldWebSiteIcon(Uri.parse('https://b.example')),
        FoldWebSiteIcon(Uri.parse('https://c.example')),
        FoldWebSiteIcon(Uri.parse('https://d.example')),
        FoldWebSiteIcon(Uri.parse('https://e.example')),
        FoldWebSiteIcon(Uri.parse('https://f.example')),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: WorkFoldLine(
              worked: const Duration(seconds: 41),
              edits: (files: 0, added: 0, removed: 0),
              webIcons: webIcons,
              images: [(image: image, file: null)],
              expanded: false,
              onToggle: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // 1 globe + 6 sites with favicons + 1 missing-favicon fallback = 8 badges
      // -> 5 stacked + "+3".
      final stack = find.descendant(
        of: find.byType(StepWebIcons),
        matching: find.byType(Positioned),
      );
      expect(stack, findsNWidgets(5));
      expect(find.text('+3'), findsOneWidget);

      // Stacked web icons appear before image thumbnails.
      final webRect = tester.getRect(find.byType(StepWebIcons));
      final thumbRect = tester.getRect(find.byType(StepThumbnails));
      expect(webRect.right, lessThanOrEqualTo(thumbRect.left));
    });

    testWidgets('hides stacked badges when expanded', (tester) async {
      SiteIcons.current = await _siteIconsWith(tester, ['dart.dev']);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: StepsFoldLine(
              tally: StepTally(const [
                ToolCallItem(
                  kind: ToolKind.web,
                  tool: 'WebSearch',
                  target: 'dart',
                ),
                ToolCallItem(
                  kind: ToolKind.web,
                  tool: 'WebFetch',
                  target: 'https://dart.dev',
                ),
              ]),
              webIcons: [
                const FoldWebSearchIcon(),
                FoldWebSiteIcon(Uri.parse('https://dart.dev')),
              ],
              expanded: true,
              onToggle: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(StepWebIcons),
          matching: find.byType(Positioned),
        ),
        findsNothing,
      );
    });
  });
}
