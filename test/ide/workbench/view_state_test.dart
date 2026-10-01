import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_layout.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:path/path.dart' as p;

import '../git/fake_git.dart';
import '../lsp_ui/fake_language_features.dart';
import 'fake_files.dart';

/// What the IDE window was is kept between runs: the parts that show, the
/// widths, the side view and the editors (by the host, [IdeWorkbench.
/// viewState]); Format on Save and Git Blame, in settings.json.
void main() {
  test('the parts that show are kept and given back', () {
    final layout = IdeLayout()
      ..sidebar = false
      ..panel = IdePanelTab.problems;
    final kept = layout.toJson();
    expect(kept, {'sidebar': false, 'chat': true, 'panel': 'problems'});

    final again = IdeLayout()..restore(kept);
    expect(again.sidebar, isFalse);
    expect(again.chat, isTrue);
    expect(again.panel, IdePanelTab.problems);
    // A terminal comes back only where there are terminals.
    expect(
      (IdeLayout()..restore({'panel': 'terminal'})).panel,
      IdePanelTab.terminal,
    );
    expect(
      (IdeLayout()
            ..terminals = false
            ..restore({'panel': 'terminal'}))
          .panel,
      isNull,
    );
  });

  testWidgets('the widths, the view and the editors come back, the active '
      'one shown; a change is kept a moment later', (tester) async {
    final kept = <Map<String, Object?>>[];
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a', 'b.txt': 'b'},
      viewState: {
        'sidebarWidth': 333.0,
        'chatWidth': 444.0,
        'panelHeight': 222.0,
        'view': 'search',
        'editors': [inRoot('a.txt'), inRoot('gone.txt'), inRoot('b.txt')],
        'active': inRoot('b.txt'),
      },
      onViewState: kept.add,
    );
    await tester.pump(const Duration(milliseconds: 400));

    // One that is no more is left out.
    expect(
      [for (final doc in workspace.documents) doc.path],
      [inRoot('a.txt'), inRoot('b.txt')],
    );
    expect(workspace.active?.path, inRoot('b.txt'));
    expect(kept.last, {
      'sidebarWidth': 333.0,
      'chatWidth': 444.0,
      'panelHeight': 222.0,
      'sidebar': true,
      'chat': true,
      'view': 'search',
      'editors': [inRoot('a.txt'), inRoot('b.txt')],
      'active': inRoot('b.txt'),
    });

    final told = kept.length;
    workspace.layout.sidebar = false;
    workspace.select(inRoot('a.txt'));
    await tester.pump();
    expect(kept, hasLength(told));
    await tester.pump(const Duration(milliseconds: 400));
    expect(kept, hasLength(told + 1));
    expect(kept.last['sidebar'], isFalse);
    expect(kept.last['active'], inRoot('a.txt'));
  });

  testWidgets('Format on Save and Git Blame are kept in settings.json', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('baocode-ide-toggles');
    addTearDown(() => temp.deleteSync(recursive: true));
    final settings = UserSettings(
      p.join(temp.path, 'User', 'settings.json'),
      debounce: Duration.zero,
    );
    addTearDown(settings.dispose);
    File(settings.path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{\n  // mine\n}\n');
    settings.loadSync();
    await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      languages: FakeLanguageFeatures(),
      git: FakeGit(testRoot).repository(),
      settings: settings,
    );
    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

    expect(state.runCommand('baocode.ide.toggleFormatOnSave'), isTrue);
    expect(state.runCommand('git.blame.toggleEditorDecoration'), isTrue);
    for (var i = 0; i < 100; i++) {
      if (settings['git.blame.editorDecoration.enabled'] != null) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(settings['editor.formatOnSave'], isTrue);
    expect(settings['git.blame.editorDecoration.enabled'], isFalse);
    expect(File(settings.path).readAsStringSync(), contains('// mine'));

    // Turned back by hand in the file, the window follows.
    File(settings.path).writeAsStringSync('{"editor.formatOnSave": false}');
    await tester.runAsync(settings.load);
    await tester.pump();
    expect(state.runCommand('baocode.ide.toggleFormatOnSave'), isTrue);
    for (var i = 0; i < 100; i++) {
      if (settings['editor.formatOnSave'] == true) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(settings['editor.formatOnSave'], isTrue);
  });
}
