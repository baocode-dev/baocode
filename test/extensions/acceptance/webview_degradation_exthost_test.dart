// 九.5: Webviews degrade, and notebooks the same way (五.15), in a real
// extension host running test/fixtures/extensions/degradation-fixture: a
// panel closes at once with one notice for its extension and a line in the
// Extension Host channel; a Webview view, a custom editor and a notebook
// type are recorded with their lines; opening a notebook fails with a
// notice; a language model tool registers and no chat lists it. None of it
// is answered as unsupported.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:convert';

import 'package:baocode/extensions/window/output/extension_output_service.dart';
import 'package:baocode/extensions/window/webview_placeholders.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'open_vsx_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '九.5: Webview and notebook degradation in a real extension host',
    _body,
    timeout: const Timeout(Duration(minutes: 4)),
    skip: openVsxSkip(),
  );
}

Future<void> _body() async {
  final w = await OpenVsxWorkspace.create(
    extensionIds: const [],
    files: {'a.fixturenb': '{}'},
    development: const ['test/fixtures/extensions/degradation-fixture'],
  );
  final extensions = w.extensions;
  await w.activated('baocode-test.degradation-fixture');
  final webviews = extensions.webviews;
  final commands = extensions.commands;
  final notifications = w.workspace.notifications;

  // Registered on activation: the view, the custom editor and the notebook
  // type, each with its line.
  await eventually(
    'the registrations',
    () => webviews.notebooks.isNotEmpty && webviews.customEditors.isNotEmpty
        ? true
        : null,
  );
  expect(webviews.viewOf('degradation.webviewView'), isNotNull);
  expect(webviews.customEditors.single.viewType, 'degradation.preview');
  final notebook = webviews.notebooks.single;
  expect(notebook.viewType, 'degradation-notebook');
  expect(notebook.kind, WebviewKind.notebook);
  expect(
    webviews.logLines,
    containsAll([
      // Named by the extension's display name (a custom editor is sent
      // only the extension's id).
      contains(
        'The Degradation Fixture extension\'s editor "degradation.preview" '
        '(degradation.preview) needs a Webview',
      ),
      contains('needs a notebook editor'),
    ]),
  );
  // No notice yet: nothing was opened.
  expect(notifications.notifications, isEmpty);

  // A panel: closed at once, one notice, its line in the Output panel.
  expect(await commands.executeCommand('degradation.panel', []), 'disposed');
  await commands.executeCommand('degradation.panel', []);
  final notices = notifications.notifications
      .where((n) => n.message.contains('Fixture Panel'))
      .toList();
  expect(notices, hasLength(1), reason: 'one notice per extension');
  expect(notices.single.severity, IdeSeverity.warning);
  expect(notices.single.message, contains('Webview'));
  expect(notices.single.primary.map((a) => a.label), contains('Show Output'));
  expect(
    extensions.output
        .channel(ExtensionOutputService.extensionHostChannelId)
        ?.text
        .text,
    contains('"Fixture Panel" (degradation.panel) needs a Webview'),
  );

  // A notebook: not opened, the extension told why, the user too.
  final error = await commands.executeCommand('degradation.openNotebook', [
    w.path('a.fixturenb'),
  ]);
  expect('$error', contains('Notebooks are not supported in BaoCode'));
  expect(
    notifications.notifications.map((n) => n.message),
    contains(contains("'a.fixturenb' was not opened as a notebook")),
  );

  // The language model tool registered; no chat lists it.
  final state = jsonDecode(
    '${await commands.executeCommand('degradation.state', [])}',
  ) as Map<String, Object?>;
  expect(state['panel'], 'disposed');
  expect(state['tools'], isEmpty);

  expect(
    w.unsupported,
    isEmpty,
    reason: 'everything degraded is accepted: ${w.report()}',
  );
}
