import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/ide/ide_layout.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart' show IdePanelTab;
import 'package:baocode/ide/services/debug_view.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/context_keys.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/debug.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/statusbar.dart';
import 'package:baocode/l10n/app_localizations.dart';

import '../../../debug/support/fake_debug_adapter.dart';
import 'fake_host.dart';

/// The debugger as the workbench shows it, alone: the one given followed,
/// its console toggled, and its context key and status bar mark.
void main() {
  testWidgets('follows the debugger given: its sessions, its mark', (
    tester,
  ) async {
    late DebugService service;
    await tester.runAsync(() async {
      service = (await createFakeDebugService()).service;
    });
    addTearDown(service.dispose);
    final host = FakeWorkbenchHost();
    final layout = IdeLayout();
    DebugService? given = service;
    final debug = DebugViewService(
      host: host,
      given: () => given,
      layout: () => layout,
      selection: () => null,
    );
    final services = WorkbenchServices()
      ..add(ActionRegistry())
      ..add(ContextKeyService())
      ..add(StatusbarService())
      ..add<WorkbenchHost>(host)
      ..add(debug);
    final contribution = DebugContribution(services);
    addTearDown(() {
      contribution.dispose();
      services.dispose();
    });
    var changes = 0;
    debug.addListener(() => changes++);
    debug.givenChanged();
    expect(debug.service, same(service));
    expect(debug.inDebugMode, isFalse);
    final keys = services.get<ContextKeyService>();
    expect(keys.getValue('inDebugMode'), isFalse);

    // The status bar: no mark until a session is debugged.
    late BuildContext context;
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    final statusbar = services.get<StatusbarService>();
    expect(statusbar.items(context, StatusbarAlignment.left), isEmpty);

    changes = 0;
    await tester.runAsync(
      () => service.startDebugging(
        service.configurationManager.getLaunches().first,
        {
          'type': 'fake',
          'request': 'launch',
          'name': 'Launch main.js',
          'program': r'${workspaceFolder}/main.js',
        },
      ),
    );
    expect(changes, greaterThan(0));
    expect(debug.inDebugMode, isTrue);
    expect(keys.getValue('inDebugMode'), isTrue);
    expect(
      statusbar.items(context, StatusbarAlignment.left).single.text,
      'Launch main.js',
    );

    // None given: none followed.
    given = null;
    debug.givenChanged();
    expect(debug.service, isNull);
    expect(debug.inDebugMode, isFalse);
  });

  test('Toggle Debug Console: the panel on it, focused, or hidden', () {
    final host = FakeWorkbenchHost();
    final layout = IdeLayout();
    final debug = DebugViewService(
      host: host,
      given: () => null,
      layout: () => layout,
      selection: () => null,
    );
    addTearDown(debug.dispose);
    debug.toggleRepl();
    expect(layout.panel, IdePanelTab.debugConsole);
    expect(host.calls, ['focusPanel']);
    debug.toggleRepl();
    expect(layout.panel, isNull);
    expect(host.calls, ['focusPanel']);
  });
}
