// JetBrains IDEs' Get from Version Control: the folder named after the
// URL, and a real clone; the dialog's folder following the URL until it
// is named, and Git's error shown in it.

import 'dart:io';

import 'package:baocode/ide/git/git_model.dart';
import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/ide/git/ide_git_clone_dialog.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the folder a clone goes in', () {
    expect(ideGitCloneFolder('https://github.com/a/b.git'), 'b');
    expect(ideGitCloneFolder('git@github.com:a/b.git'), 'b');
    expect(ideGitCloneFolder('https://example.com/a/repo/'), 'repo');
    expect(ideGitCloneFolder('git@host:repo'), 'repo');
    expect(ideGitCloneFolder(''), '');
  });

  test('a real clone', () async {
    if ((await Process.run('git', ['--version'])).exitCode != 0) return;
    final folder = await Directory.systemTemp.createTemp('clone');
    addTearDown(() => folder.delete(recursive: true));
    final root = folder.resolveSymbolicLinksSync();
    final source = p.join(root, 'source');
    Directory(source).createSync();
    for (final arguments in [
      ['init', '-q'],
      [
        '-c',
        'user.email=a@b.c',
        '-c',
        'user.name=A',
        'commit',
        '-q',
        '--allow-empty',
        '-m',
        'first',
      ],
    ]) {
      final result = await Process.run(
        'git',
        arguments,
        workingDirectory: source,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    final target = p.join(root, 'copy');
    await IdeGitService.clone(source, target);
    expect(Directory(p.join(target, '.git')).existsSync(), isTrue);
    await expectLater(
      IdeGitService.clone(p.join(root, 'missing'), p.join(root, 'other')),
      throwsA(isA<IdeGitException>()),
    );
  });

  testWidgets("the folder follows the URL until named; Git's error shown", (
    tester,
  ) async {
    final calls = <List<String>>[];
    String? cloned;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () async => cloned = await showIdeGitCloneDialog(
              context,
              parent: '/work',
              runner:
                  (
                    arguments, {
                    required workingDirectory,
                    limit,
                    stdin,
                    environment,
                  }) async {
                    calls.add(arguments);
                    return calls.length == 1
                        ? const IdeGitOutput(128, '', 'fatal: no access')
                        : const IdeGitOutput(0, '');
                  },
            ),
            child: const SizedBox.expand(child: Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'git@github.com:a/tool.git');
    await tester.pump();
    TextField field(int index) => tester.widget<TextField>(fields.at(index));
    expect(field(1).controller!.text, p.join('/work', 'tool'));

    await tester.tap(find.text('Clone'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fatal: no access'), findsOneWidget);
    expect(cloned, isNull);

    await tester.enterText(fields.at(1), '/work/mine');
    await tester.enterText(fields.at(0), 'git@github.com:a/other.git');
    await tester.pump();
    expect(field(1).controller!.text, '/work/mine');
    await tester.tap(find.text('Clone'));
    await tester.pumpAndSettle();
    expect(calls.last, [
      'clone',
      '--',
      'git@github.com:a/other.git',
      '/work/mine',
    ]);
    expect(cloned, '/work/mine');
  });
}
