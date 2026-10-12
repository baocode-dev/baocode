// Create Project: a name and its source folder; on this computer more
// folders can be added, which makes the project a workspace.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/create_project_dialog.dart';
import 'package:baocode/workspace/workspace.dart';

import 'project_workspace_test.dart' show FakeWorkspaceDirectories;

const _window = MethodChannel('baocode/window');

Future<Workspace> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _window,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _window,
      null,
    ),
  );
  final hosts = CreateProjectDialog.hosts;
  CreateProjectDialog.hosts = () async => const [];
  addTearDown(() => CreateProjectDialog.hosts = hosts);
  final workspace = Workspace(
    projects: const [Project('site', '/code/site')],
    kernels: [MockKernels.claudeCode],
    workspaceDirectories: FakeWorkspaceDirectories(),
  );
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.pump();
  return workspace;
}

Future<Project?> Function() _show(
  WidgetTester tester,
  Workspace workspace,
  List<String> picks,
) {
  final queue = [...picks];
  final shown = showCreateProjectDialog(
    tester.element(find.byType(Sidebar)),
    workspace: workspace,
    pickLocal: () async => queue.removeAt(0),
    pickRemote: (_) async => null,
  );
  return () => shown;
}

Finder get _dialog => find.byType(CreateProjectDialog);

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.descendant(of: _dialog, matching: find.text(text)));
  await tester.pumpAndSettle();
}

/// The button; the title says the same.
Future<void> _create(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: _dialog, matching: find.text('Create Project')).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one folder makes a project of it, named as asked', (
    tester,
  ) async {
    final workspace = await _pump(tester);
    final shown = _show(tester, workspace, ['/code/api']);
    await tester.pumpAndSettle();

    // A folder is needed.
    await _create(tester);
    expect(find.text("Pick the project's folder."), findsOneWidget);

    await _tap(tester, 'Add a folder on ');
    expect(find.text('/code/api'), findsOneWidget);
    await tester.enterText(
      find.descendant(of: _dialog, matching: find.byType(EditableText)),
      'Backend',
    );
    await _create(tester);

    // Closed, so what it made is in: never awaited while it is open.
    expect(_dialog, findsNothing);
    final project = (await shown())!;
    expect(project.path, '/code/api');
    expect(project.name, 'Backend');
    expect(workspace.workspaces, isEmpty);
  });

  testWidgets('a second folder on this computer makes a workspace of both', (
    tester,
  ) async {
    final workspace = await _pump(tester);
    final shown = _show(tester, workspace, ['/code/api', '/code/web']);
    await tester.pumpAndSettle();

    await _tap(tester, 'Add a folder on ');
    expect(
      find.text(
        'Several folders make one project: its agents work '
        'across them.',
      ),
      findsNothing,
    );
    await _tap(tester, 'Add another folder');
    expect(find.text('/code/web'), findsOneWidget);
    expect(
      find.text(
        'Several folders make one project: its agents work '
        'across them.',
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.descendant(of: _dialog, matching: find.byType(EditableText)),
      'Full stack',
    );
    await _create(tester);

    // Closed, so what it made is in: never awaited while it is open.
    expect(_dialog, findsNothing);
    final project = (await shown())!;
    final made = workspace.workspaces.single;
    expect(made.name, 'Full stack');
    expect(made.folders, ['/code/api', '/code/web']);
    expect(project.path, made.path);
  });
}
