// JetBrains IDEs' Manage Remotes, and a tag pushed to a remote or deleted
// there: in a real repository, and the dialog over a fake one.

import 'dart:io';

import 'package:baocode/ide/git/git_service.dart';
import 'package:baocode/ide/git/ide_git_remotes_dialog.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../workbench/fake_files.dart';
import 'fake_git.dart';

void main() {
  test(
    'remotes added, renamed, removed; a tag pushed and deleted there',
    () async {
      if ((await Process.run('git', ['--version'])).exitCode != 0) return;
      final folder = await Directory.systemTemp.createTemp('remotes');
      addTearDown(() => folder.delete(recursive: true));
      final root = folder.resolveSymbolicLinksSync();
      final repo = '$root/repo';
      final server = '$root/server.git';
      Future<String> git(List<String> arguments, String where) async {
        final result = await Process.run(
          'git',
          arguments,
          workingDirectory: where,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return result.stdout as String;
      }

      Directory(repo).createSync();
      await git(['init', '-q', '--bare', server], root);
      await git(['init', '-q'], repo);
      await git(['config', 'user.email', 'a@b.c'], repo);
      await git(['config', 'user.name', 'A'], repo);
      await git(['commit', '-q', '--allow-empty', '-m', 'first'], repo);
      await git(['tag', 'v1'], repo);

      final service = IdeGitService(repo);
      await service.addRemote('origin', server);
      expect(await service.remoteUrls(), {'origin': server});
      await service.editRemote('origin', to: 'upstream', url: server);
      expect(await service.remoteUrls(), {'upstream': server});

      await service.pushTag('upstream', 'v1');
      expect(await git(['tag'], server), 'v1\n');
      await service.deleteRemoteTag('upstream', 'v1');
      expect(await git(['tag'], server), '');

      await service.removeRemote('upstream');
      expect(await service.remoteUrls(), isEmpty);
    },
  );

  testWidgets('the dialog lists the remotes; one added', (tester) async {
    final fake = FakeGit(testRoot)..remoteUrls['origin'] = 'git@x:a/b.git';
    final git = fake.repository();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => GestureDetector(
            onTap: () => showIdeGitRemotesDialog(
              context,
              git: git,
              notifications: IdeNotifications(),
            ),
            child: const SizedBox.expand(child: Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('git@x:a/b.git'), findsOneWidget);

    await tester.tap(find.byTooltip('Add Remote'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'fork');
    await tester.enterText(fields.at(1), 'git@x:me/b.git');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      fake.callsTo('remote'),
      anyElement(equals(['remote', 'add', '--', 'fork', 'git@x:me/b.git'])),
    );
  });
}
