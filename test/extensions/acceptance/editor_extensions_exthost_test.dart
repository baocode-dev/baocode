// 九.2: real Open VSX extensions that work on the editor, each in a fresh
// data folder, installed through the workspace's management: GitLens
// (current line blame, CodeLens, hover, its views), Error Lens with Code
// Spell Checker's and TypeScript's diagnostics, and Todo Tree (its tree
// and its highlights), and VSCodeVim (its modes, editing through the
// `type` command and its cursor). The editor is a widgetless view, the extensions'
// `activeTextEditor`.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:bao_editor/monaco/flutter/editor_view_styles.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:baocode/extensions/views/tree_view.dart';
import 'package:baocode/ide/ide_editor_views.dart';
import 'package:baocode/ide/language/language_types.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../host/exthost_runtime.dart';
import 'open_vsx_workspace.dart';

const _greet = [
  'export function greet(name: string): string {',
  '  return "hi " + name;',
  '}',
  '',
  'export const answer: number = 42;',
  '',
];

/// [project] as a Git repository with one commit of everything in it, by
/// someone other than its user.
void _commit(String project) {
  void git(List<String> args) {
    final result = Process.runSync(
      'git',
      args,
      workingDirectory: project,
      environment: const {
        'GIT_AUTHOR_NAME': 'Accept Author',
        'GIT_AUTHOR_EMAIL': 'accept@example.com',
      },
    );
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')}: ${result.stderr}');
    }
  }

  git(['init', '-q', '-b', 'main']);
  git(['config', 'user.name', 'The User']);
  git(['config', 'user.email', 'user@example.com']);
  git(['config', 'commit.gpgsign', 'false']);
  git(['add', '.']);
  git(['commit', '-q', '-m', 'Add the greeting']);
}

/// The text decorations put after lines of [view], with their lines.
List<({int line, String text})> _afterTexts(IdeEditorView view) {
  final snapshot = view.document.model.snapshot;
  return [
    for (final EditorDecoration d
        in view.features.decorations.decorations.items)
      if (d.after?.text case final text? when text.trim().isNotEmpty)
        (line: snapshot.positionAtOffset(d.start).lineNumber, text: text),
  ];
}

/// Puts the caret on one-based [line] (an extension sees the selection).
void _caretAt(IdeEditorView view, int line) {
  final offset = view.document.model.snapshot.offsetAtPosition(
    Position(line, 1),
  );
  view.controller.setSelections([TextSelection.collapsed(offset: offset)]);
}

/// The labels of [tree]'s roots once it has loaded some.
Future<List<ExtensionTreeItem>> _roots(
  ExtensionTreeView tree, {
  Duration timeout = const Duration(minutes: 2),
}) => eventually('${tree.id} items', () {
  final roots = tree.roots;
  return roots == null || roots.isEmpty || tree.isLoading ? null : roots;
}, timeout: timeout);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const timeout = Timeout(Duration(minutes: 8));

  test(
    '九.2: GitLens blame, CodeLens, hover and views',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['eamodio.gitlens'],
        files: {'greet.ts': _greet.join('\n')},
        settings: {
          // Over the whole line, so a hover anywhere on it shows the blame.
          'gitlens.hovers.currentLine.over': 'line',
          // A first install shows its welcome in the grouped view until
          // dismissed; the tree comes after.
          'gitlens.advanced.skipOnboarding': true,
        },
        prepare: _commit,
      );
      final view = await w.show('greet.ts');
      await w.activated('eamodio.gitlens');
      final file = w.path('greet.ts');

      // The current line's blame, after the line with the caret.
      _caretAt(view, 2);
      w.workspace.editorViews.changed(view);
      final blame = await eventually('the current line blame', () {
        final texts = _afterTexts(view);
        return texts.any((t) => t.text.contains('Accept Author'))
            ? texts
            : null;
      });
      final annotation = blame.singleWhere(
        (t) => t.text.contains('Accept Author'),
      );
      expect(annotation.line, 2);
      expect(annotation.text, contains('Add the greeting'));

      // Its CodeLenses: the authors and the recent change.
      final languages = w.extensions.languageRoot.language;
      final titles = await eventually('the CodeLenses', () async {
        final lenses = await languages.codeLenses(file);
        final titles = [
          for (final lens in lenses)
            (await languages.resolveCodeLens(file, lens)).command?.title ?? '',
        ];
        return titles.any((t) => t.contains('Accept Author')) ? titles : null;
      });
      expect(titles, contains(contains('author')));

      // A hover on the line: the commit.
      final hover = await eventually('the blame hover', () async {
        final found = await languages.hover(file, const LspPosition(1, 4));
        return found != null && found.markdown.contains('Add the greeting')
            ? found
            : null;
      });
      expect(hover.markdown, contains('Accept Author'));

      // Its views: the grouped Source Control view lists the commit.
      final views = w.extensions.views;
      views.setVisibleViews({'gitlens.views.scm.grouped'});
      final tree = views.treeView('gitlens.views.scm.grouped')!;
      final roots = await _roots(tree);
      expect(
        [for (final r in roots) r.displayLabel].join('\n'),
        contains('Add the greeting'),
        reason: w.report(),
      );
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: timeout,
    skip: openVsxSkip(),
  );

  test(
    '九.2: Error Lens with Code Spell Checker and TypeScript',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [
          'usernamehw.errorlens',
          'streetsidesoftware.code-spell-checker',
        ],
        files: {
          'notes.ts': [
            '// The recieved value.',
            'const total: number = "many";',
            '',
          ].join('\n'),
        },
      );
      final view = await w.show('notes.ts');
      await w.activated('usernamehw.errorlens');
      await w.activated('streetsidesoftware.code-spell-checker');
      final file = w.path('notes.ts');
      final languages = w.extensions.languageRoot.language;

      // Code Spell Checker's word, TypeScript's error.
      await eventually('the diagnostics', () {
        final found = languages.diagnosticsFor(file);
        return found.any((d) => d.message.contains('recieved')) &&
                found.any((d) => d.message.contains("'string'"))
            ? true
            : null;
      }, timeout: const Duration(minutes: 3));
      // Error Lens: each message after its line.
      final texts = await eventually('the Error Lens messages', () {
        final texts = _afterTexts(view);
        return texts.any((t) => t.text.contains('recieved')) &&
                texts.any((t) => t.text.contains("'string'"))
            ? texts
            : null;
      });
      expect(texts.firstWhere((t) => t.text.contains('recieved')).line, 1);
      expect(texts.firstWhere((t) => t.text.contains("'string'")).line, 2);
      // The spelling fix is a code action.
      final actions = await languages.codeActions(
        file,
        const LspRange(LspPosition(0, 7), LspPosition(0, 15)),
        diagnostics: [
          for (final d in languages.diagnosticsFor(file))
            if (d.message.contains('recieved')) d,
        ],
      );
      expect([
        for (final a in actions) a.title,
      ], contains(contains('received')));
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: timeout,
    skip: openVsxSkip(),
  );

  test(
    '九.2: Todo Tree',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['Gruntfuggly.todo-tree'],
        files: {
          'src/a.ts': 'const a = 1; // TODO: rename a\n',
          'src/b.py': '# FIXME: handle errors\nprint(1)\n',
        },
        settings: {
          // Upstream 1.135 ships ripgrep as @vscode/ripgrep-universal,
          // where Todo Tree does not look: as there, the user sets it.
          'todo-tree.ripgrep.ripgrep': _ripgrep(),
          // With no colors, its highlight calls `ThemeColor(...)` without
          // `new`, which throws in upstream 1.135 as here.
          'todo-tree.highlights.defaultHighlight': {
            'foreground': '#000000',
            'background': '#ffff00',
          },
        },
      );
      final view = await w.show('src/a.ts');
      await w.activated('Gruntfuggly.todo-tree');

      // The tree: both files' tags.
      final views = w.extensions.views;
      views.setVisibleViews({'todo-tree-view'});
      final tree = views.treeView('todo-tree-view')!;
      final labels = await eventually('the TODOs', () async {
        final labels = await _labels(tree);
        return labels.any((l) => l.contains('rename a')) &&
                labels.any((l) => l.contains('handle errors'))
            ? labels
            : null;
      });
      expect(labels, isNotEmpty, reason: w.report());

      // The open editor's tag highlighted.
      final text = view.document.text;
      final highlighted = await eventually('the TODO highlight', () {
        final items = view.features.decorations.decorations.items;
        return items.isEmpty ? null : items;
      });
      expect([
        for (final d in highlighted) text.substring(d.start, d.end),
      ], contains(startsWith('TODO')));
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: timeout,
    skip: openVsxSkip(),
  );

  test(
    '九.2: VSCodeVim modes, editing and its block cursor',
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const ['vscodevim.vim'],
        files: {'a.txt': 'alpha\nbeta\ngamma\n'},
      );
      final view = await w.show('a.txt');
      await w.activated('vscodevim.vim');
      final controller = view.controller;
      final contextKeys = w.extensions.contextKeys;
      String? mode() => contextKeys.getContextKeyValue('vim.mode') as String?;
      String status() => [
        for (final e in w.extensions.statusBar.entries)
          if (e.extensionId?.toLowerCase() == 'vscodevim.vim') e.text,
      ].join(' ');
      Future<void> keys(String typed) async {
        for (final key in typed.split('')) {
          controller.type(key);
        }
      }

      Future<void> text(String expected) async {
        try {
          await eventually(
            'the text',
            () => view.document.text == expected ? true : null,
            timeout: const Duration(seconds: 20),
          );
        } on TimeoutException {
          expect(view.document.text, expected, reason: w.report());
        }
      }

      // Normal mode: its context key, status and block cursor.
      await eventually('Normal mode', () {
        return mode() == 'Normal' &&
                controller.caretStyle == EditorCaretStyle.block
            ? true
            : null;
      });
      _caretAt(view, 1);
      w.workspace.editorViews.changed(view);

      // `x` deletes the character under the cursor; `j` `dd` the line.
      await keys('x');
      await text('lpha\nbeta\ngamma\n');
      await keys('jdd');
      await text('lpha\ngamma\n');

      // `i`: Insert mode; typing goes through `default:type`.
      await keys('i');
      await eventually('Insert mode', () {
        return mode() == 'Insert' &&
                controller.caretStyle == EditorCaretStyle.line &&
                status().contains('INSERT')
            ? true
            : null;
      });
      await keys('ok ');
      await text('lpha\nok gamma\n');

      // Escape (its keybinding's command): Normal again, `u` undoes.
      await w.extensions.commands.executeCommand('extension.vim_escape');
      await eventually('Normal mode again', () {
        return mode() == 'Normal' &&
                controller.caretStyle == EditorCaretStyle.block
            ? true
            : null;
      });
      await keys('u');
      await text('lpha\ngamma\n');
      expect(w.unsupported, isEmpty, reason: w.report());
      expect(w.extensions.running.withErrors, isEmpty, reason: w.report());
    },
    timeout: timeout,
    skip: openVsxSkip(),
  );
}

/// The labels of [tree] down to its leaves.
Future<List<String>> _labels(ExtensionTreeView tree) async {
  final labels = <String>[];
  Future<void> walk(List<ExtensionTreeItem> items, int depth) async {
    for (final item in items) {
      labels.add(item.displayLabel);
      if (!item.hasChildren || depth > 4) continue;
      if (!tree.isExpanded(item)) await tree.expand(item);
      await walk(tree.childrenOf(item) ?? const [], depth + 1);
    }
  }

  await walk(tree.roots ?? const [], 0);
  return labels;
}

/// The runtime's ripgrep.
String _ripgrep() {
  final arch = Process.runSync('uname', ['-m']).stdout.toString().trim();
  final platform =
      '${Platform.isMacOS ? 'darwin' : 'linux'}-${arch == 'x86_64' ? 'x64' : 'arm64'}';
  return '${exthostRuntimeDir()}/node_modules/@vscode/'
      'ripgrep-universal/bin/$platform/rg';
}
