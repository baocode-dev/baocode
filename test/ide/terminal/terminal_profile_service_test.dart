import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_quick_input.dart';
import 'package:monad/ide/terminal/terminal_instance.dart';
import 'package:monad/ide/terminal/terminal_profile_service.dart';
import 'package:monad/ide/terminal/terminal_profiles.dart';
import 'package:monad/ide/terminal/terminal_service.dart';
import 'package:monad/ide/terminal/terminal_shell.dart';
import 'package:monad/l10n/app_localizations_en.dart';
import 'package:monad/settings/user_settings.dart';
import 'package:path/path.dart' as p;

import 'fake_pty.dart';
import 'fake_terminal.dart';

void main() {
  late Directory temp;
  late UserSettings settings;
  late List<FakePty> started;
  late List<Object?> detections;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('monad-terminal-profiles');
    settings = UserSettings(
      p.join(temp.path, 'User', 'settings.json'),
      debounce: Duration.zero,
    );
    started = [];
    detections = [];
  });

  tearDown(() async {
    settings.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> write(String text) async {
    await File(settings.path).parent.create(recursive: true);
    await File(settings.path).writeAsString(text);
    await settings.load();
  }

  TerminalBackend backend({UserSettings? userSettings}) => TerminalBackend(
    launch: fakeTerminalLaunch,
    start: FakePty.starter(started),
    detectProfiles: ({Object? configured}) {
      detections.add(configured);
      return fakeTerminalProfiles(configured: configured);
    },
    settings: userSettings,
  );

  TerminalProfileService service({UserSettings? userSettings}) =>
      TerminalProfileService(
        backend(userSettings: userSettings),
        os: TerminalOs.macOS,
      );

  test('detects the profiles when first asked, once', () async {
    final profiles = service(userSettings: settings);
    addTearDown(profiles.dispose);
    expect(profiles.availableProfiles, isEmpty);
    expect(detections, isEmpty);

    await Future.wait([profiles.refresh(), profiles.refresh()]);
    await profiles.refresh();
    expect(detections, hasLength(1));
    expect(profiles.availableProfiles.map((profile) => profile.name), [
      'bash',
      'sh',
      'zsh',
      'fish',
    ]);
    // None set: the user's shell's.
    expect(profiles.defaultProfileSetting, isNull);
    expect(profiles.defaultProfileName, 'zsh');
  });

  test("detects them again after the user's profiles change, with them, "
      'not after another setting does', () async {
    await write('{}');
    final profiles = service(userSettings: settings);
    addTearDown(profiles.dispose);
    await profiles.refresh();

    await write('{"editor.fontSize": 14}');
    await profiles.refresh();
    expect(detections, hasLength(1));

    await write('''{
      // mine
      "terminal.integrated.profiles.osx": {
        "sh": null,
        "Login fish": { "path": "fish", "args": ["--login"] },
      },
    }''');
    await profiles.refresh();
    expect(detections, hasLength(2));
    expect(detections.last, isA<Map<String, Object?>>());
    expect(profiles.availableProfiles.map((profile) => profile.name), [
      'bash',
      'zsh',
      'fish',
      'Login fish',
    ]);
    expect(
      profiles.profileNamed('Login fish'),
      const TerminalProfile(
        name: 'Login fish',
        path: '/opt/homebrew/bin/fish',
        args: ['--login'],
      ),
    );
  });

  test('Select Default Profile writes it to settings.json; new terminals '
      'start it', () async {
    await write('{\n  // mine\n  "editor.fontSize": 14\n}\n');
    // The service's system is the app's.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final terminals = TerminalService(
      root: '/project',
      backend: backend(userSettings: settings),
    );
    addTearDown(terminals.dispose);
    final profiles = terminals.profiles;
    expect(profiles.canSetDefault, isTrue);
    // None set: the user's shell, not waiting for the profiles.
    expect(profiles.defaultShell(), isNull);

    await profiles.refresh();
    var changes = 0;
    profiles.addListener(() => changes++);
    await profiles.setDefaultProfile(profiles.profileNamed('bash')!);
    expect(changes, greaterThan(0));
    expect(settings['terminal.integrated.defaultProfile.osx'], 'bash');
    final text = await File(settings.path).readAsString();
    expect(text, contains('// mine'));
    expect(text, contains('"terminal.integrated.defaultProfile.osx": "bash"'));
    expect(profiles.defaultProfileName, 'bash');

    terminals.create();
    await pumpEventQueue();
    expect(started.last.launch!.executable, '/bin/bash');
    expect(started.last.launch!.arguments, ['-l']);

    // A profile given starts that one.
    terminals.create(profile: profiles.profileNamed('fish'));
    await pumpEventQueue();
    expect(started.last.launch!.executable, '/opt/homebrew/bin/fish');

    // A default that is not there: the user's shell.
    await settings.update('terminal.integrated.defaultProfile.osx', 'nu');
    expect(profiles.defaultProfileName, 'zsh');
    terminals.create();
    await pumpEventQueue();
    expect(started.last.launch!.executable, '/bin/zsh');
  });

  test('without settings.json no default can be set', () async {
    final profiles = service();
    addTearDown(profiles.dispose);
    expect(profiles.canSetDefault, isFalse);
    expect(profiles.defaultShell(), isNull);
    await profiles.refresh();
    expect(profiles.defaultProfileName, 'zsh');
  });

  test('a detection that fails leaves no profiles', () async {
    final profiles = TerminalProfileService(
      TerminalBackend(
        launch: fakeTerminalLaunch,
        start: FakePty.starter(started),
        detectProfiles: ({Object? configured}) async =>
            throw const FileSystemException('no /etc/shells'),
      ),
      os: TerminalOs.macOS,
    );
    addTearDown(profiles.dispose);
    await profiles.refresh();
    expect(profiles.availableProfiles, isEmpty);
    expect(profiles.defaultProfileName, isNull);
  });

  test("the dropdown's profiles: those of the settings, the default first, "
      'the others by name', () async {
    final found = (await fakeTerminalProfiles()).profiles;
    expect(
      terminalDropdownProfiles(found, 'zsh').map((profile) => profile.name),
      ['zsh', 'bash', 'fish'],
    );
    expect(
      terminalDropdownProfiles(found, 'sh').map((profile) => profile.name),
      ['bash', 'fish', 'zsh'],
    );
  });

  test('the quick pick: those of the settings, then those detected, each '
      "with its shell's command line; the default active", () async {
    final found = (await fakeTerminalProfiles(
      configured: {
        'Spaced': {
          'path': '/bin/zsh',
          'args': ['-c', 'echo "hi there"'],
        },
      },
    )).profiles;
    TerminalProfile? picked;
    final pick = terminalProfilePick(
      profiles: found,
      defaultName: 'zsh',
      placeholder: 'Pick one',
      onPick: (profile) => picked = profile,
      l10n: AppLocalizationsEn(),
    );
    expect(pick.placeholder, 'Pick one');
    expect(
      [
        for (final entry in pick.items)
          switch (entry) {
            IdeQuickPickSeparator(:final label) => '-- $label',
            IdeQuickPickItem(:final label, :final description) =>
              '$label: $description',
          },
      ],
      [
        '-- profiles',
        'bash: /bin/bash -l',
        'zsh: /bin/zsh -l',
        'fish: /opt/homebrew/bin/fish -l',
        r'Spaced: /bin/zsh -c "echo \"hi there\""',
        '-- detected',
        'sh: /bin/sh',
      ],
    );
    final zsh = pick.activeItems!.single;
    expect(zsh.label, 'zsh');
    pick.onDidAccept!(zsh);
    expect(picked?.name, 'zsh');
  });
}
