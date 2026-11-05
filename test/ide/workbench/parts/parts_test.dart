import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/services/layout.dart';
import 'package:baocode/ide/workbench/options.dart';
import 'package:baocode/ide/workbench/parts/sash.dart';
import 'package:baocode/ide/workbench/parts/status_bar.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/statusbar.dart';
import 'package:baocode/ide/workbench/storage.dart';
import 'package:baocode/ide/workbench/style.dart';
import 'package:baocode/l10n/app_localizations.dart';

import '../fake_files.dart';
import '../services/fake_host.dart';

/// The parts alone, without the workbench: a sash dragged and reset, the
/// status bar's items in their order, the layout's sizes kept.
void main() {
  testWidgets('a sash: dragged from where it began, reset by a double click', (
    tester,
  ) async {
    final drags = <double>[];
    var (starts, ends, resets) = (0, 0, 0);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            positionedSash(
              -10,
              400,
              WorkbenchSash(
                key: const ValueKey('sash'),
                onStart: () => starts++,
                onDrag: drags.add,
                onEnd: () => ends++,
                onReset: () => resets++,
              ),
            ),
          ],
        ),
      ),
    );
    // Over the row's edge, it is kept inside the row.
    final sash = find.byKey(const ValueKey('sash'));
    expect(tester.getTopLeft(sash).dx, 0);
    expect(tester.getSize(sash).width, WorkbenchStyle.sashWidth);

    final gesture = await tester.startGesture(
      tester.getCenter(sash),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(ends, 1);
    expect(drags.last, closeTo(50, 0.01));

    await tester.tap(sash, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(sash, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(resets, 1);
  });

  testWidgets('the status bar: the remote first, the message after the '
      'entries above it, the bell last', (tester) async {
    final workspace = IdeWorkspace(testRoot, files: TreeFiles({}));
    addTearDown(workspace.dispose);
    final statusbar = StatusbarService();
    addTearDown(statusbar.dispose);
    final services = WorkbenchServices()..add(statusbar);
    final options = _Options(workspace, _Remote());
    statusbar
      ..addEntry(
        'scm',
        StatusbarAlignment.left,
        (_) => const IdeStatusBarItem('main'),
        priority: 80,
      )
      ..addEntry(
        'problems',
        StatusbarAlignment.left,
        (_) => const IdeStatusBarItem('0 problems'),
        priority: 40,
      )
      ..addEntry(
        'selection',
        StatusbarAlignment.right,
        (_) => const IdeStatusBarItem('Ln 1, Col 1'),
        priority: 100,
      );
    late IdeStatusBar bar;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            bar = workbenchStatusBar(context, services, options);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      [for (final item in bar.left) item.text],
      ['remote', 'main', '0 problems'],
    );
    expect(bar.right.first.text, 'Ln 1, Col 1');
    expect(bar.right, hasLength(2));

    statusbar.setMessage('Running…');
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            bar = workbenchStatusBar(context, services, options);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      [for (final item in bar.left) item.text],
      ['remote', 'main', 'Running…', '0 problems'],
    );
    services.remove<StatusbarService>(owned: false);
    services.dispose();
  });

  test('the layout\'s sizes, resized, are kept', () {
    final workspace = IdeWorkspace(testRoot, files: TreeFiles({}));
    addTearDown(workspace.dispose);
    final layout = LayoutService(
      host: FakeWorkbenchHost(),
      layout: () => workspace.layout,
    );
    addTearDown(layout.dispose);
    var kept = 0;
    final storage = WorkbenchStorage(onChanged: () => kept++)..register(layout);
    layout.addListener(storage.changed);
    layout
      ..sidebarWidth = 333
      ..resized();
    expect(kept, 1);
    final saved = storage.collect();
    final restored = LayoutService(
      host: FakeWorkbenchHost(),
      layout: () => workspace.layout,
    );
    addTearDown(restored.dispose);
    WorkbenchStorage()
      ..register(restored)
      ..restore(saved);
    expect(restored.sidebarWidth, 333);
  });
}

class _Remote extends ChangeNotifier implements IdeRemoteIndicator {
  @override
  IdeStatusBarItem item(BuildContext context) =>
      const IdeStatusBarItem('remote');
}

class _Options implements WorkbenchOptions {
  _Options(this.workspace, this.remote);

  @override
  final IdeWorkspace workspace;

  @override
  final IdeRemoteIndicator remote;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
