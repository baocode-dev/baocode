import 'package:baocode/platform/context_menu.dart';
import 'package:baocode/settings/pages/general_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings → General's context menu row: what it shows of the menu, and
/// what its buttons ask.
class _Menu implements ContextMenuInstaller {
  _Menu({this.status_ = ContextMenuStatus.off, this.failure});

  ContextMenuStatus status_;
  final String? failure;
  final List<Object> calls = [];

  @override
  Future<ContextMenuStatus> status() async => status_;

  @override
  Future<void> install(ContextMenuLabels labels) async {
    calls.add(labels);
    if (failure case final failure?) throw ContextMenuException(failure);
    status_ = ContextMenuStatus.on;
  }

  @override
  Future<void> uninstall() async {
    calls.add('uninstall');
    status_ = ContextMenuStatus.off;
  }

  @override
  Future<void> Function()? get openSystemSettings =>
      () async => calls.add('settings');
}

Future<_Menu> _pump(WidgetTester tester, _Menu menu) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  ContextMenu.debugInstaller = menu;
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: GeneralSettingsPage())),
  );
  await tester.pumpAndSettle();
  return menu;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
}

void main() {
  final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets('macOS: Finder\'s, turned on with its items named, off, and '
      'System Settings\' extensions a button away', (tester) async {
    final menu = await _pump(tester, _Menu());
    expect(find.text('Finder Context Menu'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);

    await _tap(tester, 'Turn On');
    await tester.pumpAndSettle();
    expect(menu.calls, [
      (agent: 'Open with BaoCode', ide: 'Open with Fast Ide'),
    ]);
    expect(find.text('On'), findsOneWidget);

    await _tap(tester, 'Turn Off');
    await tester.pumpAndSettle();
    expect(menu.calls.last, 'uninstall');
    expect(find.text('Off'), findsOneWidget);

    await _tap(tester, 'System Settings…');
    await tester.pump();
    expect(menu.calls.last, 'settings');
  }, variant: mac);

  testWidgets('Windows: Explorer\'s; what failed is told under it', (
    tester,
  ) async {
    await _pump(tester, _Menu(failure: 'Access is denied.'));
    expect(find.text('Explorer Context Menu'), findsOneWidget);
    await _tap(tester, 'Turn On');
    await tester.pumpAndSettle();
    expect(
      find.text('Could not change the context menu: Access is denied.'),
      findsOneWidget,
    );
    expect(find.text('Off'), findsOneWidget);
  }, variant: windows);

  testWidgets('a build without the Finder extension says so, its buttons '
      'off', (tester) async {
    await _pump(tester, _Menu(status_: ContextMenuStatus.unsupported));
    expect(
      find.text('This build of the app has no Finder extension.'),
      findsOneWidget,
    );
    await _tap(tester, 'Turn On');
    await tester.pumpAndSettle();
    expect(find.text('On'), findsNothing);
  }, variant: mac);
}
