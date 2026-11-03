import 'package:baocode/theme/theme_transition.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fade = find.byWidgetPredicate(
    (widget) => widget is FadeTransition && widget.child is Material,
  );
  final half = Duration(
    microseconds: kThemeAnimationDuration.inMicroseconds ~/ 2,
  );

  testWidgets('低透明度处交换一次，同一输入树保留文本和焦点', (tester) async {
    final transition = ColorThemeTransition(vsync: tester);
    addTearDown(transition.dispose);
    final text = TextEditingController(text: '保留文本');
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: transition.wrap(
          Material(
            type: MaterialType.transparency,
            child: TextField(controller: text, focusNode: focus),
          ),
          canvas: Colors.black,
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final input = tester.element(find.byType(TextField));
    var applied = 0;
    transition.change(
      from: Colors.black,
      to: Colors.white,
      apply: () => applied++,
    );
    await tester.pump();
    await tester.pump(half);
    expect(applied, 1);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
    expect(focus.hasFocus, isTrue);
    expect(text.text, '保留文本');
    expect(tester.element(find.byType(TextField)), same(input));
    await tester.pump(half);
    expect(applied, 1);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('新目标从当前颜色与透明度接续，不交换过期目标', (tester) async {
    final transition = ColorThemeTransition(vsync: tester);
    addTearDown(transition.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: transition.wrap(
          const Material(type: MaterialType.transparency, child: Text('内容')),
          canvas: Colors.black,
        ),
      ),
    );
    var old = 0;
    var latest = 0;
    transition.change(from: Colors.black, to: Colors.white, apply: () => old++);
    await tester.pump();
    await tester.pump(half ~/ 2);
    final opacity = tester.widget<FadeTransition>(fade).opacity.value;
    final background = tester
        .widget<ColoredBox>(find.byType(ColoredBox).first)
        .color;
    transition.change(
      from: Colors.black,
      to: Colors.red,
      apply: () => latest++,
    );
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade).opacity.value, opacity);
    expect(
      tester.widget<ColoredBox>(find.byType(ColoredBox).first).color,
      background,
    );
    await tester.pump(half);
    await tester.pump(half);
    expect(old, 0);
    expect(latest, 1);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    // 框架在到达终点后的下一帧停止 ticker，不留下运行中的动画。
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('系统过渡中切回原亮度，停止旧底色动画并保留偏好', (tester) async {
    final themes = WorkbenchThemeService()
      ..restore(
        setting: 'Kimbie Dark',
        autoDetectColorScheme: true,
        brightness: Brightness.dark,
      );
    addTearDown(themes.dispose);
    await tester.runAsync(themes.initialize);
    final transition = ColorThemeTransition(vsync: tester);
    addTearDown(transition.dispose);
    final shown = <String>[];
    themes.addListener(() => shown.add(themes.colorTheme.settingsId));
    themes.transition = (colors, apply) => transition.change(
      from: themes.colors.dark ? Colors.black : Colors.white,
      to: colors.dark ? Colors.black : Colors.white,
      apply: apply,
      animate: !identical(colors.theme, themes.colorTheme),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: themes,
          builder: (context, child) => transition.wrap(
            const Material(type: MaterialType.transparency, child: Text('内容')),
            canvas: themes.colors.dark ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
    await tester.runAsync(() => themes.setPlatformBrightness(Brightness.light));
    await tester.pump();
    await tester.pump(half ~/ 2);
    expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
    await tester.runAsync(() => themes.setPlatformBrightness(Brightness.dark));
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(
      tester
          .widget<ColoredBox>(
            find.ancestor(of: fade, matching: find.byType(ColoredBox)).first,
          )
          .color,
      Colors.black,
    );
    await tester.pump(kThemeAnimationDuration);
    expect(shown, isNot(contains('Bao Light')));
    expect(themes.colorTheme.settingsId, 'Bao Dark');
    expect(themes.colorThemeSetting, 'Kimbie Dark');
    expect(themes.autoDetectColorScheme, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('跨过中点的跳帧仍在零透明度交接一次', (tester) async {
    final transition = ColorThemeTransition(vsync: tester);
    addTearDown(transition.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: transition.wrap(
          const Material(type: MaterialType.transparency, child: Text('内容')),
          canvas: Colors.black,
        ),
      ),
    );
    var applied = 0;
    transition.change(
      from: Colors.black,
      to: Colors.white,
      apply: () {
        expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
        applied++;
      },
    );
    await tester.pump();
    await tester.pump(kThemeAnimationDuration * 2);
    expect(applied, 1);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
    await tester.pump(kThemeAnimationDuration);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(applied, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('减少动态效果、结束与销毁不留下运行中的动画', (tester) async {
    final transition = ColorThemeTransition(vsync: tester);
    await tester.pumpWidget(
      MaterialApp(
        home: transition.wrap(
          const Material(type: MaterialType.transparency, child: Text('内容')),
          canvas: Colors.transparent,
        ),
      ),
    );
    var applied = 0;
    transition.change(
      from: Colors.black,
      to: Colors.white,
      apply: () => applied++,
      animate: false,
    );
    await tester.pump();
    expect(applied, 1);
    expect(
      tester.widget<ColoredBox>(find.byType(ColoredBox).first).color,
      Colors.transparent,
    );
    transition.change(
      from: Colors.black,
      to: Colors.white,
      apply: () => applied++,
    );
    await tester.pump();
    transition.finish();
    await tester.pump();
    expect(applied, 2);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    transition.change(
      from: Colors.black,
      to: Colors.white,
      apply: () => applied++,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    transition.dispose();
    await tester.pump(kThemeAnimationDuration);
    expect(applied, 2);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
