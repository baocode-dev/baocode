import 'package:baocode/chat/composer/composer_picker.dart';
import 'package:baocode/chat/floating/floating_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
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
                selected: options.first,
                focusNode: focus,
                searchPlaceholder: 'Search models',
                footer: footer
                    ? (
                        label: 'Manage Models…',
                        icon: Icons.tune_rounded,
                        onTap: () => managed++,
                      )
                    : null,
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
