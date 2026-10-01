import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/git/ide_scm_view.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:path/path.dart' as p;

/// The choices made in Source Control's dialogs, kept in settings.json as
/// VS Code keeps them: asked once, not again after a restart.
void main() {
  late Directory temp;
  late String path;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('baocode-scm-session');
    path = p.join(temp.path, 'User', 'settings.json');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<UserSettings> load() async {
    final settings = UserSettings(path, debounce: Duration.zero);
    addTearDown(settings.dispose);
    await settings.load();
    return settings;
  }

  test('asks, unset, as VS Code does', () async {
    final session = IdeScmSession(settings: await load());
    addTearDown(session.dispose);
    expect(session.confirmSync, isTrue);
    expect(session.enableSmartCommit, isFalse);
    expect(session.suggestSmartCommit, isTrue);
  });

  test('Don\'t Show Again, Always and Never are written to settings.json '
      'and kept by the next run', () async {
    final settings = await load();
    final session = IdeScmSession(settings: settings);
    addTearDown(session.dispose);
    session
      ..confirmSync = false
      ..enableSmartCommit = true
      ..suggestSmartCommit = false;
    expect(session.confirmSync, isFalse);
    // Written once the edits queued are.
    await settings.load();
    expect(jsonDecode(await File(path).readAsString()), {
      'git.confirmSync': false,
      'git.enableSmartCommit': true,
      'git.suggestSmartCommit': false,
    });

    final next = IdeScmSession(settings: await load());
    addTearDown(next.dispose);
    expect(next.confirmSync, isFalse);
    expect(next.enableSmartCommit, isTrue);
    expect(next.suggestSmartCommit, isFalse);
  });

  test('a choice set in the file by hand is followed', () async {
    await File(path).parent.create(recursive: true);
    await File(path)
        .writeAsString('{\n  // mine\n  "git.confirmSync": false\n}\n');
    final session = IdeScmSession(settings: await load());
    addTearDown(session.dispose);
    expect(session.confirmSync, isFalse);
  });

  test('with no settings file, a choice lasts the session', () {
    final session = IdeScmSession();
    addTearDown(session.dispose);
    session.confirmSync = false;
    expect(session.confirmSync, isFalse);
  });
}
