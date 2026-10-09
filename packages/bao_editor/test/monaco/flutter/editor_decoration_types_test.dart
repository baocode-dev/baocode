import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_decoration_types.dart';
import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_tracked_decorations.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';

const _red = Color(0xffff0000);

EditorDecorationTheme _theme({bool dark = true}) => EditorDecorationTheme(
  isDark: dark,
  colors: (id) => switch (id) {
    'editor.foreground' => const Color(0xffd4d4d4),
    'editorError.foreground' => _red,
    _ => null,
  },
  key: dark,
);

EditorDocumentModel _document(String text) {
  final document = EditorDocumentModel(text);
  addTearDown(document.dispose);
  return document;
}

void main() {
  group('render options', () {
    test('fromJson reads the IDecorationRenderOptions wire shape', () {
      final options = DecorationRenderOptions.fromJson({
        'isWholeLine': true,
        'rangeBehavior': 1,
        'overviewRulerLane': 4,
        'backgroundColor': {'id': 'editorError.foreground'},
        'border': '1px dashed red',
        'borderRadius': '3px',
        'color': '#00ff00',
        'fontStyle': 'italic',
        'fontWeight': 'bold',
        'textDecoration': 'underline wavy red',
        'opacity': '0.5',
        'gutterIconPath': {
          'scheme': 'file',
          'path': '/tmp/icon.svg',
          'authority': '',
          'query': '',
          'fragment': '',
        },
        'gutterIconSize': 'contain',
        'overviewRulerColor': 'rgba(255, 0, 0, 0.5)',
        'after': {
          'contentText': ' // note',
          'color': {'id': 'editor.foreground'},
          'margin': '0 0 0 1em',
        },
        'light': {'color': '#000000'},
        'dark': {
          'before': {'contentText': '>'},
        },
      });
      expect(options.isWholeLine, isTrue);
      expect(options.rangeBehavior, 1);
      expect(options.overviewRulerLane, 4);
      expect(
        options.backgroundColor,
        const ThemeColorValue('editorError.foreground'),
      );
      expect(options.border, '1px dashed red');
      expect(options.gutterIconPath!.path, '/tmp/icon.svg');
      expect(options.after!.contentText, ' // note');
      expect(options.after!.color, const ThemeColorValue('editor.foreground'));
      expect(options.light!.color, const CssColor('#000000'));
      expect(options.dark!.before!.contentText, '>');
      // Round trip.
      final again = DecorationRenderOptions.fromJson(options.toJson());
      expect(again.toJson(), options.toJson());
    });

    test('decoration options: full and fast forms', () {
      final full = DecorationOptions.fromJson({
        'range': {
          'startLineNumber': 1,
          'startColumn': 2,
          'endLineNumber': 3,
          'endColumn': 4,
        },
        'hoverMessage': 'hi',
        'renderOptions': {
          'after': {'contentText': 'x'},
          'dark': {
            'after': {'color': 'red'},
          },
        },
      })!;
      expect(
        [
          full.range.startLineNumber,
          full.range.startColumn,
          full.range.endLineNumber,
          full.range.endColumn,
        ],
        [1, 2, 3, 4],
      );
      expect(full.hoverMessage, 'hi');
      expect(full.renderOptions!.after!.contentText, 'x');
      expect(full.renderOptions!.dark!.after!.color, const CssColor('red'));
      final fast = DecorationOptions.fromFastJson([1, 1, 1, 3, 2, 1, 2, 2]);
      expect(fast, hasLength(2));
      expect(fast[1].range.startLineNumber, 2);
      expect(fast[1].range.endColumn, 2);
    });

    test('CSS values', () {
      expect(parseCssColor('#f00'), _red);
      expect(parseCssColor('#ff000080'), const Color(0x80ff0000));
      expect(parseCssColor('rgba(255, 0, 0, 0.5)'), const Color(0x80ff0000));
      expect(parseCssColor('rgb(255 0 0 / 50%)'), const Color(0x80ff0000));
      expect(parseCssColor('hsl(120, 100%, 50%)'), const Color(0xff00ff00));
      expect(parseCssColor('red'), _red);
      expect(parseCssColor('transparent'), const Color(0x00000000));
      expect(parseCssColor('nonsense'), isNull);
      expect(parseCssLength('2px'), const EditorCssLength(2));
      expect(
        parseCssLength('1.5em'),
        const EditorCssLength(1.5, EditorCssUnit.em),
      );
      expect(parseCssLength('thin'), const EditorCssLength(1));
      final edges = parseCssEdges('1px 2px')!;
      expect(edges.top, const EditorCssLength(1));
      expect(edges.right, const EditorCssLength(2));
      expect(edges.left, const EditorCssLength(2));
      final border = parseCssBorder('dotted 2px #f00')!;
      expect(border.style, EditorBorderStyle.dotted);
      expect(border.width, const EditorCssLength(2));
      expect(border.color, _red);
      expect(parseCssFontWeight('bold'), FontWeight.bold);
      expect(parseCssFontWeight('300'), FontWeight.w300);
      expect(parseCssFontStyle('italic'), FontStyle.italic);
      expect(parseCssOpacity('0.4'), 0.4);
      expect(parseCssOpacity('40%'), closeTo(0.4, 1e-9));
    });
  });

  group('decoration types', () {
    test('resolve backgrounds, borders, text, ruler and content', () {
      final type = resolveDecorationType(
        DecorationRenderOptions.fromJson({
          'backgroundColor': {'id': 'editorError.foreground'},
          'border': '2px solid',
          'color': '#00ff00',
          'fontWeight': 'bold',
          'overviewRulerColor': 'red',
          'rangeBehavior': 1,
          'after': {'contentText': 'tail', 'color': 'red'},
          'dark': {'color': '#0000ff'},
        }),
        _theme(),
      );
      final decoration = type.decoration;
      expect(decoration.backgroundColor, _red);
      // The border's color is the text's (currentColor), dark wins.
      expect(decoration.borderColor, const Color(0xff0000ff));
      expect(decoration.borderWidth, 2);
      expect(decoration.textStyle!.color, const Color(0xff0000ff));
      expect(decoration.textStyle!.fontWeight, FontWeight.bold);
      expect(decoration.overviewRulerColor, _red);
      expect(decoration.resolvedOverviewRulerLane, OverviewRulerLane.center);
      expect(
        type.stickiness,
        TrackedRangeStickiness.neverGrowsWhenTypingAtEdges,
      );
      expect(type.after!.contentText, 'tail');

      final placed = decorationOfType(type, _theme(), start: 2, end: 5);
      expect(placed.start, 2);
      expect(placed.end, 5);
      expect(placed.after!.text, 'tail');
      expect(placed.after!.style!.color, _red);
      expect(placed.after!.cursorStops, InjectedTextCursorStops.left);
    });

    test('a border needs a style; a missing theme color is transparent', () {
      final type = resolveDecorationType(
        DecorationRenderOptions.fromJson({
          'borderColor': 'red',
          'backgroundColor': {'id': 'not.a.color'},
          'outline': '1px dotted red',
        }),
        _theme(),
      );
      expect(type.decoration.borderColor, isNull);
      expect(type.decoration.backgroundColor, const Color(0x00000000));
      expect(type.decoration.outlineColor, _red);
      expect(type.decoration.outlineStyle, EditorBorderStyle.dotted);
    });

    test('instances override the type\'s content', () {
      final registry = EditorDecorationTypeRegistry();
      addTearDown(registry.dispose);
      registry.registerDecorationType(
        'k',
        DecorationRenderOptions.fromJson({
          'before': {'contentText': 'type', 'color': 'red'},
        }),
      );
      final type = registry.resolve('k', _theme())!;
      final placed = decorationOfType(
        type,
        _theme(),
        start: 0,
        end: 0,
        instance: DecorationInstanceRenderOptions.fromJson({
          'before': {'contentText': 'mine'},
        }),
      );
      expect(placed.before!.text, 'mine');
      expect(placed.before!.style!.color, _red);
      expect(placed.before!.cursorStops, InjectedTextCursorStops.right);
    });

    test('controller sets, fast-sets, restyles and drops removed types', () {
      final document = _document('one\ntwo\nthree');
      final registry = EditorDecorationTypeRegistry();
      addTearDown(registry.dispose);
      registry.registerDecorationType(
        'err',
        DecorationRenderOptions.fromJson({
          'backgroundColor': {'id': 'editorError.foreground'},
        }),
      );
      final controller = EditorDecorationsController(
        document: document,
        types: registry,
        theme: _theme(),
      );
      addTearDown(controller.dispose);
      var notified = 0;
      controller.addListener(() => notified++);
      controller.setDecorations('err', [
        DecorationOptions(range: Range(2, 1, 2, 4), hoverMessage: 'bad'),
      ]);
      expect(notified, 1);
      var items = controller.decorations.items.toList();
      expect(items.single.start, 4);
      expect(items.single.end, 7);
      expect(items.single.hoverMessage, 'bad');
      expect(controller.decorations.intersecting(0, 2), isEmpty);

      controller.setDecorationsFast('err', [1, 1, 1, 2, 3, 1, 3, 6]);
      items = controller.decorations.items.toList();
      expect(items.map((d) => (d.start, d.end)), [(0, 1), (8, 13)]);

      controller.theme = EditorDecorationTheme(
        isDark: true,
        colors: (id) =>
            id == 'editorError.foreground' ? const Color(0xff00ff00) : null,
        key: 'green',
      );
      expect(
        controller.decorations.items.first.backgroundColor,
        const Color(0xff00ff00),
      );

      // Unknown types are ignored.
      controller.setDecorations('nope', [
        DecorationOptions(range: Range(1, 1, 1, 2)),
      ]);
      expect(controller.typeKeys, ['err']);

      registry.removeDecorationType('err');
      expect(controller.decorations.isEmpty, isTrue);
      expect(controller.typeKeys, isEmpty);
    });
  });

  group('tracked decorations', () {
    (int, int) track(
      TrackedRangeStickiness stickiness,
      int insertAt, {
      bool collapse = false,
      int deleteLength = 0,
    }) {
      final document = _document('0123456789');
      final tracked = EditorTrackedDecorations(document);
      addTearDown(tracked.dispose);
      tracked.set('o', [
        EditorTrackedDecoration(
          start: 3,
          end: 6,
          decoration: const EditorDecoration(start: 3, end: 6),
          stickiness: stickiness,
          collapseOnReplaceEdit: collapse,
        ),
      ]);
      document.applyOffsetEdits([
        EditorOffsetEdit(insertAt, insertAt + deleteLength, 'ab'),
      ]);
      final range = tracked.rangesOf('o').single;
      final item = tracked.decorations.items.single;
      expect((item.start, item.end), (range.start, range.end));
      return (range.start, range.end);
    }

    test('typing at the edges follows each stickiness', () {
      const always = TrackedRangeStickiness.alwaysGrowsWhenTypingAtEdges;
      const never = TrackedRangeStickiness.neverGrowsWhenTypingAtEdges;
      const before = TrackedRangeStickiness.growsOnlyWhenTypingBefore;
      const after = TrackedRangeStickiness.growsOnlyWhenTypingAfter;
      expect(track(always, 3), (3, 8));
      expect(track(always, 6), (3, 8));
      expect(track(never, 3), (5, 8));
      expect(track(never, 6), (3, 6));
      expect(track(before, 3), (3, 8));
      expect(track(before, 6), (3, 6));
      expect(track(after, 3), (5, 8));
      expect(track(after, 6), (3, 8));
      // Edits elsewhere move or leave it.
      expect(track(never, 0), (5, 8));
      expect(track(never, 9), (3, 6));
      expect(track(never, 4), (3, 8));
    });

    test('a replace over the whole range collapses it when asked', () {
      const never = TrackedRangeStickiness.neverGrowsWhenTypingAtEdges;
      expect(track(never, 3, deleteLength: 3, collapse: true), (3, 3));
      expect(track(never, 3, deleteLength: 3), (3, 5));
    });

    test('windows search the tree; owners replace and clear', () {
      final document = _document(List.filled(1000, 'line').join('\n'));
      final tracked = EditorTrackedDecorations(document);
      addTearDown(tracked.dispose);
      tracked.set('a', [
        for (var i = 0; i < 1000; i++)
          EditorTrackedDecoration(
            start: i * 5,
            end: i * 5 + 4,
            decoration: EditorDecoration(start: i * 5, end: i * 5 + 4),
          ),
      ]);
      expect(tracked.decorations.intersecting(49, 50).length, 2);
      expect(tracked.decorations.intersecting(51, 53).length, 1);
      final version = tracked.version;
      tracked.set('a', const []);
      expect(tracked.version, greaterThan(version));
      expect(tracked.decorations.isEmpty, isTrue);
    });
  });
}
