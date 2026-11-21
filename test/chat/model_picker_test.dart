import 'package:baocode/chat/chat_session.dart' show ModelSettingChoice;
import 'package:baocode/chat/composer/composer_picker.dart';
import 'package:baocode/chat/floating/floating_registry.dart';
import 'package:baocode/ide/ide_switch.dart';
import 'package:baocode/kernel/agent_kernel.dart' show KernelChoiceKind;
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _builtin = KernelOptionGroup('claude-code', 'Claude Code');
const _gateway = KernelOptionGroup(
  'gw',
  'Gateway',
  warning: 'HTTP 401: bad key',
);

KernelOption _option(String id, String label, KernelOptionGroup group) =>
    KernelOption(
      id,
      label,
      Icons.hub_outlined,
      '${id.split('/').last} · 128K',
      group: group,
    );

void main() {
  final picked = <String>[];
  var managed = 0;

  Future<void> pump(
    WidgetTester tester,
    List<KernelOption> options, {
    bool footer = true,
    KernelOption? selected,
    List<ModelSettingChoice> Function(KernelOption option)? settingsOf,
  }) async {
    picked.clear();
    managed = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: Focus(
              focusNode: focus,
              // As the composer's input passes its keys on.
              onKeyEvent: (_, event) =>
                  FloatingRegistry.handleKey(event) ?? KeyEventResult.ignored,
              child: ComposerPicker(
                options: options,
                selected: selected ?? options.first,
                focusNode: focus,
                searchPlaceholder: 'Search models',
                settingsOf: settingsOf,
                footers: [
                  if (footer)
                    (
                      label: 'Manage Models…',
                      icon: Icons.tune_rounded,
                      onTap: () => managed++,
                    ),
                ],
                onSelected: (option) => picked.add(option.id),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('one group: no headings; several: each headed, a warning '
      'marked', (tester) async {
    await pump(tester, [
      _option('default', 'Default', _builtin),
      _option('opus', 'Opus', _builtin),
    ]);
    await open(tester, 'Default');
    expect(find.text('Claude Code'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await pump(tester, [
      _option('default', 'Default', _builtin),
      _option('@gw/gpt-5', 'GPT-5', _gateway),
    ]);
    await open(tester, 'Default');
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.text('Gateway'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    // The id and window under the name.
    expect(find.text('gpt-5 · 128K'), findsOneWidget);
  });

  testWidgets('many options are filtered as one types; Enter picks the '
      'first left', (tester) async {
    await pump(tester, [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 12; i++) _option('@gw/m$i', 'Model $i', _gateway),
      _option('@gw/glm-4.6', 'GLM 4.6', _gateway),
    ]);
    await open(tester, 'Default');
    expect(find.text('Search models'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(find.text('gl'), findsOneWidget);
    expect(find.text('Model 3'), findsNothing);
    expect(find.text('GLM 4.6'), findsOneWidget);

    // Escape clears the search before it closes.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Model 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['@gw/glm-4.6']);
  });

  testWidgets('the search line takes the keys once clicked: the menu\'s '
      'go on working, and Escape gives them back', (tester) async {
    await pump(tester, [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 12; i++) _option('@gw/m$i', 'Model $i', _gateway),
      _option('@gw/m1x', 'Model 1x', _gateway),
    ]);
    await open(tester, 'Default');
    final input = FocusManager.instance.primaryFocus;
    await tester.tap(find.text('Search models'));
    await tester.pump();
    final search = find.byType(EditableText);
    expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);

    await tester.enterText(search, 'model 1');
    await tester.pump();
    expect(find.text('Model 3'), findsNothing);
    expect(find.text('Model 10'), findsOneWidget);

    // Escape clears it, then closes the menu, the input focused again.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Model 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Model 3'), findsNothing);
    expect(FocusManager.instance.primaryFocus, input);

    // Enter in it picks.
    await open(tester, 'Default');
    await tester.tap(find.text('Search models'));
    await tester.enterText(find.byType(EditableText), '1x');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['@gw/m1x']);
  });

  testWidgets('an input method composing ignores Enter; submitting picks', (
    tester,
  ) async {
    await pump(tester, [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 12; i++) _option('@gw/m$i', 'Model $i', _gateway),
    ]);
    await open(tester, 'Default');
    await tester.tap(find.text('Search models'));
    await tester.pump();

    // Composing text: Enter is ignored by the menu, nothing is picked.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'model 1',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 0, end: 7),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, isEmpty);
    expect(find.text('Model 1'), findsOneWidget);

    // Submitting (e.g. from an IME action) picks.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(picked, ['@gw/m1']);
  });

  testWidgets('a hover redraws the rows it moves between, not the menu; '
      'each option\'s settings are asked for once', (tester) async {
    var drawn = 0;
    final asked = <String>[];
    const effort = [
      KernelOption('low', 'Low', Icons.speed, ''),
      KernelOption('high', 'High', Icons.speed, ''),
    ];
    await pump(
      tester,
      [
        for (var i = 0; i < 6; i++)
          KernelOption(
            'm$i',
            'Model $i',
            Icons.hub_outlined,
            '',
            iconBuilder: (size, color) {
              drawn++;
              return SizedBox.square(dimension: size);
            },
          ),
      ],
      settingsOf: (option) {
        asked.add(option.id);
        return [
          ModelSettingChoice(
            kind: KernelChoiceKind.effort,
            options: effort,
            selected: effort.first,
            onSelected: (_) {},
          ),
        ];
      },
    );
    await open(tester, 'Model 0');
    drawn = 0;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    for (final i in [1, 2, 3, 2, 1, 4]) {
      await mouse.moveTo(tester.getCenter(find.text('Model $i').last));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('High'), findsOneWidget);
    expect(drawn, 0);
    expect(asked.toSet().length, asked.length);
  });

  testWidgets('Fast appears as a switch at the end of model settings, and '
      'picking it leaves the menu open', (tester) async {
    const fastOption = KernelOption('fast', 'Fast', Icons.bolt, '');
    const effort = KernelOption('high', 'High', Icons.speed, '');
    var enabled = false;
    await pump(
      tester,
      [_option('@gw/gpt-5', 'GPT-5', _gateway)],
      settingsOf: (_) => [
        ModelSettingChoice(
          kind: KernelChoiceKind.effort,
          options: const [effort],
          selected: effort,
          onSelected: (_) {},
        ),
        ModelSettingChoice(
          kind: KernelChoiceKind.fast,
          options: const [fastOption],
          selected: enabled ? fastOption : null,
          toggle: true,
          onSelected: (_) => enabled = !enabled,
        ),
      ],
    );
    await open(tester, 'GPT-5');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('GPT-5').last));
    await tester.pumpAndSettle();
    expect(find.text('Fast'), findsOneWidget);
    // The app's own switch, not Flutter's.
    expect(find.byType(IdeSwitch), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(tester.widget<IdeSwitch>(find.byType(IdeSwitch)).value, isFalse);

    // Picked: on, and both menus stay where they are.
    await tester.tap(find.text('Fast'));
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(find.text('Fast'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);

    // Toggled off again from the switch itself, the menu still open.
    await tester.tap(find.byType(IdeSwitch));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(find.text('Fast'), findsOneWidget);

    // From the keyboard too: → into the setting, ↓ onto the switch,
    // Enter flips it, and the menu stays.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(find.text('Fast'), findsOneWidget);
  });

  testWidgets('the switch turns over where it stands, the menu rebuilt '
      'around it as the kernel reports it', (tester) async {
    // The menues are rebuilt from outside on every kernel report
    // (emitInfoChanged); the switch that was picked must show what the
    // kernel now says, with no reopen.
    const fastOption = KernelOption('fast', 'Fast', Icons.bolt, '');
    var fast = false;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Future<void> host() => tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: Focus(
              focusNode: focus,
              onKeyEvent: (_, event) =>
                  FloatingRegistry.handleKey(event) ?? KeyEventResult.ignored,
              child: StatefulBuilder(
                builder: (context, setState) => ComposerPicker(
                  options: [_option('@gw/gpt-5', 'GPT-5', _gateway)],
                  selected: _option('@gw/gpt-5', 'GPT-5', _gateway),
                  focusNode: focus,
                  settingsOf: (_) => [
                    ModelSettingChoice(
                      kind: KernelChoiceKind.fast,
                      options: const [fastOption],
                      // As the kernel now reports it.
                      selected: fast ? fastOption : null,
                      toggle: true,
                      onSelected: (_) => setState(() => fast = !fast),
                    ),
                  ],
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await host();
    await open(tester, 'GPT-5');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('GPT-5').last));
    await tester.pumpAndSettle();
    expect(tester.widget<IdeSwitch>(find.byType(IdeSwitch)).value, isFalse);

    await tester.tap(find.byType(IdeSwitch));
    await tester.pumpAndSettle();
    expect(fast, isTrue);
    expect(find.text('Fast'), findsOneWidget);
    expect(tester.widget<IdeSwitch>(find.byType(IdeSwitch)).value, isTrue);

    await tester.tap(find.byType(IdeSwitch));
    await tester.pumpAndSettle();
    expect(fast, isFalse);
    expect(find.text('Fast'), findsOneWidget);
    expect(tester.widget<IdeSwitch>(find.byType(IdeSwitch)).value, isFalse);
  });

  testWidgets('a setting that is a choice closes the menu, as before', (
    tester,
  ) async {
    const effort = KernelOption('high', 'High', Icons.speed, '');
    await pump(
      tester,
      [_option('@gw/gpt-5', 'GPT-5', _gateway)],
      settingsOf: (_) => [
        ModelSettingChoice(
          kind: KernelChoiceKind.effort,
          options: const [effort],
          selected: effort,
          onSelected: (_) {},
        ),
      ],
    );
    await open(tester, 'GPT-5');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('GPT-5').last));
    await tester.pumpAndSettle();
    expect(find.text('High'), findsOneWidget);

    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    expect(find.text('High'), findsNothing);
  });

  testWidgets(
    'short viewport keeps the scrollable list and footer in the menu',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 360);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await pump(tester, [
        _option('default', 'Default', _builtin),
        for (var i = 0; i < 15; i++) _option('@gw/m$i', 'Model $i', _gateway),
      ]);
      await open(tester, 'Default');

      final list = find.byType(SingleChildScrollView);
      final footer = find.text('Manage Models…');
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomLeft(list).dy,
        lessThan(tester.getTopLeft(footer).dy),
      );
      expect(tester.getBottomLeft(footer).dy, lessThan(350));

      await tester.drag(list, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Model 14'), findsOneWidget);
      expect(tester.getBottomLeft(footer).dy, lessThan(350));
      await tester.tap(footer);
      await tester.pumpAndSettle();
      expect(managed, 1);
    },
  );

  testWidgets('long model list stays capped and scrolls internally', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await pump(tester, [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 24; i++) _option('@gw/m$i', 'Model $i', _gateway),
    ]);
    await open(tester, 'Default');

    final list = find.byType(SingleChildScrollView);
    final footer = find.text('Manage Models…');
    final footerTop = tester.getTopLeft(footer).dy;
    expect(tester.getSize(list).height, lessThanOrEqualTo(380));
    expect(tester.getBottomLeft(list).dy, lessThan(footerTop));

    await tester.drag(list, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Model 23'), findsOneWidget);
    expect(tester.getTopLeft(footer).dy, footerTop);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the menu opens scrolled to the option checked', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final options = [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 24; i++) _option('@gw/m$i', 'Model $i', _gateway),
    ];
    await pump(tester, options, selected: options.last);
    await open(tester, 'Model 23');

    final list = find.byType(SingleChildScrollView);
    final row = find.descendant(of: list, matching: find.text('Model 23'));
    expect(row, findsOneWidget);
    final view = tester.getRect(list);
    final at = tester.getRect(row);
    expect(at.top, greaterThanOrEqualTo(view.top));
    expect(at.bottom, lessThanOrEqualTo(view.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the heading of the group scrolled into stays at the top, '
      'pushed up by the next one\'s', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await pump(tester, [
      for (var i = 0; i < 8; i++) _option('c$i', 'Claude $i', _builtin),
      for (var i = 0; i < 24; i++) _option('@gw/m$i', 'Model $i', _gateway),
    ]);
    await open(tester, 'Claude 0');
    final list = find.byType(SingleChildScrollView);
    final top = tester.getTopLeft(list).dy;
    // Unscrolled: only the list's own headings.
    expect(find.text('Claude Code'), findsOneWidget);

    await tester.drag(list, const Offset(0, -60));
    await tester.pumpAndSettle();
    final stuck = find.text('Claude Code');
    expect(stuck, findsNWidgets(2));
    final stuckTop = tester.getTopLeft(stuck.last).dy;
    expect(stuckTop, greaterThanOrEqualTo(top));
    expect(stuckTop, lessThan(top + 12));

    // The next heading, coming up under it, pushes it out.
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    final gateway = tester.getTopLeft(find.text('Gateway')).dy;
    // Its label 12 under the list's top, the stuck one's 4 + 22 high.
    position.jumpTo(position.pixels + gateway - top - 12);
    await tester.pump();
    expect(tester.getTopLeft(find.text('Claude Code').last).dy, lessThan(top));

    await tester.drag(list, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('Gateway'), findsNWidgets(2));
    expect(find.text('Claude Code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab goes into the search line and out again; it is ringed '
      'while in it, and named for a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 12; i++) _option('@gw/m$i', 'Model $i', _gateway),
    ]);
    await open(tester, 'Default');
    final input = FocusManager.instance.primaryFocus;
    final search = find.byType(EditableText);
    Color ring() {
      final box = tester
          .widgetList<Container>(
            find.ancestor(of: search, matching: find.byType(Container)),
          )
          .firstWhere(
            (box) => (box.decoration as BoxDecoration?)?.border != null,
          );
      return ((box.decoration! as BoxDecoration).border! as Border).top.color;
    }

    expect(ring(), Colors.transparent);
    expect(
      tester.getSemantics(search),
      isSemantics(label: 'Search models', isTextField: true),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
    expect(ring(), isNot(Colors.transparent));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, input);
    expect(ring(), Colors.transparent);
    // Still open.
    expect(find.text('Model 3'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('typing over the menu goes into its search line: focused, '
      'its caret after what was typed; Escape twice back to the input', (
    tester,
  ) async {
    await pump(tester, [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 12; i++) _option('@gw/m$i', 'Model $i', _gateway),
    ]);
    await open(tester, 'Default');
    final input = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
    await tester.pump();
    final search = tester.widget<EditableText>(find.byType(EditableText));
    expect(search.focusNode.hasFocus, isTrue);
    expect(search.controller.value.text, '1');
    expect(
      search.controller.selection,
      const TextSelection.collapsed(offset: 1),
    );

    // On in it, as one types there.
    await tester.enterText(find.byType(EditableText), '11');
    await tester.pump();
    expect(find.text('Model 11'), findsOneWidget);
    expect(find.text('Model 1'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, input);
  });

  testWidgets('searching away the option whose settings show: they fade '
      'out by the menu, nothing thrown, the search line kept', (tester) async {
    const effort = [KernelOption('high', 'High', Icons.speed, '')];
    await pump(
      tester,
      [
        _option('default', 'Default', _builtin),
        for (var i = 0; i < 12; i++) _option('@gw/m$i', 'Model $i', _gateway),
      ],
      settingsOf: (_) => [
        ModelSettingChoice(
          kind: KernelChoiceKind.effort,
          options: effort,
          selected: effort.first,
          onSelected: (_) {},
        ),
      ],
    );
    await open(tester, 'Default');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Model 3')));
    await mouse.moveTo(tester.getCenter(find.text('Model 3')));
    await tester.pumpAndSettle();
    expect(find.text('High'), findsOneWidget);

    final search = find.byType(EditableText);
    tester.widget<EditableText>(search).focusNode.requestFocus();
    await tester.pump();
    await tester.enterText(search, 'nothing');
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('High'), findsNothing);
    expect(tester.widget<EditableText>(search).focusNode.hasFocus, isTrue);
  });

  testWidgets('a click on a heading collapses its group, the keys going '
      'past it; another opens it; searching, none is', (tester) async {
    await pump(tester, [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 12; i++) _option('@gw/m$i', 'Model $i', _gateway),
    ]);
    await open(tester, 'Default');
    await tester.tap(find.text('Gateway'));
    await tester.pump();
    expect(find.text('Gateway'), findsOneWidget);
    expect(find.text('Model 0'), findsNothing);
    // Default highlighted: ↓ goes round to it, past the collapsed.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['default']);

    await open(tester, 'Default');
    expect(find.text('Model 0'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM, character: 'm');
    await tester.pump();
    expect(find.text('Model 0'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tap(find.text('Gateway'));
    await tester.pump();
    expect(find.text('Model 0'), findsOneWidget);
  });

  testWidgets('what was searched is marked in the names', (tester) async {
    await pump(tester, [
      _option('default', 'Default', _builtin),
      for (var i = 0; i < 12; i++) _option('@gw/m$i', 'GPT-$i', _gateway),
    ]);
    await open(tester, 'Default');
    for (final key in [LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyT]) {
      await tester.sendKeyEvent(key, character: key.keyLabel.toLowerCase());
    }
    await tester.pump();
    final name = tester.widget<RichText>(
      find.descendant(
        of: find.byType(Text),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == 'GPT-0',
        ),
      ),
    );
    // Text.rich's span, in the style's.
    final spans = ((name.text as TextSpan).children!.single as TextSpan)
        .children!
        .cast<TextSpan>();
    expect([for (final span in spans) span.text], ['G', 'PT', '-0']);
    expect(spans[1].style?.fontWeight, FontWeight.w600);
    expect(spans[0].style?.fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('few options are not searched', (tester) async {
    await pump(tester, [
      _option('default', 'Default', _builtin),
      _option('opus', 'Opus', _builtin),
    ]);
    await open(tester, 'Default');
    expect(find.text('Search models'), findsNothing);
  });

  testWidgets('Manage Models… closes the menu and opens the settings', (
    tester,
  ) async {
    await pump(tester, [_option('default', 'Default', _builtin)]);
    await open(tester, 'Default');
    await tester.tap(find.text('Manage Models…'));
    await tester.pumpAndSettle();
    expect(managed, 1);
    expect(find.text('Manage Models…'), findsNothing);
    expect(picked, isEmpty);
  });
}
