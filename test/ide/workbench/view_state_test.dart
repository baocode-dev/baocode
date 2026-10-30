import 'dart:io';

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:flutter/services.dart' show TextSelection;
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

  testWidgets('each editor\'s carets, scroll and folds come back, and are '
      'kept a moment after it comes to rest', (tester) async {
    final kept = <Map<String, Object?>>[];
    final text = List.generate(300, (i) => 'line ${i + 1}').join('\n');
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': text},
      nativeEditor: true,
      viewState: {
        'editors': [inRoot('a.txt')],
        'active': inRoot('a.txt'),
        'editorViews': [
          {
            'key': inRoot('a.txt'),
            'selections': [
              [21, 21],
            ],
            'editor': {'line': 150},
          },
        ],
      },
      onViewState: kept.add,
    );
    await tester.pump(const Duration(milliseconds: 400));
    final surface =
        tester.state(find.byType(EditorSurface)) as EditorSurfaceView;
    expect(surface.visibleLineRange!.first, 150);
    expect(
      tester
          .widget<EditorSurface>(find.byType(EditorSurface))
          .controller
          .selections,
      [const TextSelection.collapsed(offset: 21)],
    );
    expect(workspace.viewStateOf(workspace.active!).editor?.firstLine, 150);

    final offset = workspace.active!.model.snapshot.lineStarts[39];
    surface.revealRange(offset, offset, center: true);
    await tester.pump();
    final top = surface.visibleLineRange!.first;
    await tester.pump(const Duration(milliseconds: 1400));
    final views = kept.last['editorViews']! as List<Object?>;
    expect(views.single, containsPair('key', inRoot('a.txt')));
    expect((views.single! as Map)['editor'], containsPair('line', top));
  });

  testWidgets('the search\'s files to include and exclude and its options '
      'come back, and are kept as they change (#268)', (tester) async {
    final kept = <Map<String, Object?>>[];
    await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      viewState: {
        'view': 'search',
        'search': {'excludes': '**/gen', 'matchCase': true},
      },
      onViewState: kept.add,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('**/gen'), findsOneWidget);
    // The files to include and exclude show, one of them set (#377).
    expect(kept.last['search'], {
      'excludes': '**/gen',
      'matchCase': true,
      'detailsShown': true,
    });

    await tester.enterText(find.text('**/gen'), '**/gen, build');
    await tester.pump(const Duration(milliseconds: 400));
    expect(kept.last['search'], {
      'excludes': '**/gen, build',
      'matchCase': true,
      'detailsShown': true,
    });
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
