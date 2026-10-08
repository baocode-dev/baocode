import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/claude_code/claude_onboarding.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory home;
  late File config;
  late Map<String, String> environment;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('baocode-onboarding-test-');
    home = Directory(p.join(temp.path, 'home'))..createSync();
    config = File(p.join(home.path, '.claude.json'));
    environment = {'HOME': home.path, 'USERPROFILE': home.path};
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<bool> prepare() => prepareClaudeOnboarding(environment: environment);
  Map<String, dynamic> read() =>
      jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;

  test(
    'creates the first-run flag in the home config, not settings.json',
    () async {
      expect(await prepare(), isTrue);
      expect(read(), {'hasCompletedOnboarding': true});
      expect(Directory(p.join(home.path, '.claude')).existsSync(), isFalse);
      expect(home.listSync().map((entity) => p.basename(entity.path)), [
        '.claude.json',
      ]);
    },
  );

  for (final initial in [
    <String, Object?>{},
    {'hasCompletedOnboarding': false},
  ]) {
    test('adds the flag to $initial without dropping other state', () async {
      final state = {
        ...initial,
        'oauthAccount': {'accountUuid': 'test-account'},
        'mcpServers': {
          'local': {
            'command': 'example',
            'args': ['--test'],
          },
        },
        'projects': {
          'example': {'hasTrustDialogAccepted': true},
        },
        'numStartups': 7,
      };
      config.writeAsStringSync(jsonEncode(state));
      expect(await prepare(), isTrue);
      expect(read(), {...state, 'hasCompletedOnboarding': true});
      expect(home.listSync(), hasLength(1));
    });
  }

  test(
    'true leaves bytes and modification time unchanged across startups',
    () async {
      const text = '{ "hasCompletedOnboarding": true, "numStartups": 1 }';
      config.writeAsStringSync(text);
      final modified = DateTime(2020);
      config.setLastModifiedSync(modified);
      for (var i = 0; i < 3; i++) {
        expect(await prepare(), isFalse);
      }
      expect(config.readAsStringSync(), text);
      expect(config.lastModifiedSync(), modified);
    },
  );

  for (final text in [
    '',
    '{broken',
    '[]',
    'null',
    '{"hasCompletedOnboarding":null}',
    '{"hasCompletedOnboarding":"false"}',
  ]) {
    test('invalid config is not overwritten: $text', () async {
      config.writeAsStringSync(text);
      expect(await prepare(), isFalse);
      expect(config.readAsStringSync(), text);
      expect(home.listSync(), hasLength(1));
    });
  }

  test('explicit default config folder still uses the home config', () async {
    environment['CLAUDE_CONFIG_DIR'] = p.join(home.path, '.claude');
    expect(await prepare(), isTrue);
    expect(read()['hasCompletedOnboarding'], isTrue);
  });

  test('a moved config folder holds its own root config', () async {
    final moved = p.join(temp.path, 'moved');
    environment['CLAUDE_CONFIG_DIR'] = moved;
    config = File(p.join(moved, '.claude.json'));
    expect(await prepare(), isTrue);
    expect(read()['hasCompletedOnboarding'], isTrue);
    expect(home.listSync(), isEmpty);
  });

  test('BaoCode config override takes precedence', () async {
    final moved = p.join(temp.path, 'baocode');
    environment[ClaudeEnvironment.dataPathVariable] = moved;
    environment['CLAUDE_CONFIG_DIR'] = p.join(temp.path, 'other');
    config = File(p.join(moved, '.claude.json'));
    expect(await prepare(), isTrue);
    expect(read()['hasCompletedOnboarding'], isTrue);
    expect(Directory(environment['CLAUDE_CONFIG_DIR']!).existsSync(), isFalse);
    expect(home.listSync(), isEmpty);
  });

  test('an absolute config folder works without a home', () async {
    final moved = p.join(temp.path, 'no-home');
    environment = {'CLAUDE_CONFIG_DIR': moved};
    config = File(p.join(moved, '.claude.json'));
    expect(await prepare(), isTrue);
    expect(read()['hasCompletedOnboarding'], isTrue);
  });

  test('missing home or relative directories never write to cwd', () async {
    for (final env in [
      <String, String>{},
      {'HOME': 'relative'},
      {'CLAUDE_CONFIG_DIR': 'relative'},
      {ClaudeEnvironment.dataPathVariable: 'relative', 'HOME': home.path},
    ]) {
      expect(await prepareClaudeOnboarding(environment: env), isFalse);
    }
    expect(home.listSync(), isEmpty);
  });

  test('a directory at the config path is left alone', () async {
    Directory(config.path).createSync();
    expect(await prepare(), isFalse);
    expect(Directory(config.path).existsSync(), isTrue);
    expect(home.listSync(), hasLength(1));
  });

  test(
    'keeps a symlink and updates its target',
    () async {
      final target = File(p.join(temp.path, 'linked.json'))
        ..writeAsStringSync('{"numStartups":9}');
      final link = Link(config.path)..createSync(target.path);
      expect(await prepare(), isTrue);
      expect(link.existsSync(), isTrue);
      expect(read(), {'numStartups': 9, 'hasCompletedOnboarding': true});
      expect(temp.listSync(), hasLength(2));
    },
    skip: Platform.isWindows
        ? 'Creating symlinks needs Windows privileges'
        : false,
  );

  test('JSON diagnostics never include credentials from the source', () async {
    const secret = 'example-secret-not-for-logs';
    config.writeAsStringSync('{"token":"$secret",broken}');
    final messages = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    try {
      expect(await prepare(), isFalse);
      expect(messages, isNotEmpty);
      expect(messages.join('\n'), isNot(contains(secret)));
      expect(config.readAsStringSync(), contains(secret));
    } finally {
      debugPrint = print;
    }
  });

  test(
    'a blocked custom directory does not overwrite the blocking file',
    () async {
      final blocker = File(p.join(temp.path, 'blocked'))
        ..writeAsStringSync('keep');
      environment['CLAUDE_CONFIG_DIR'] = blocker.path;
      expect(await prepare(), isFalse);
      expect(blocker.readAsStringSync(), 'keep');
      expect(temp.listSync(), hasLength(2));
    },
  );

  test(
    'a read-only directory leaves the config unchanged without temporary files',
    () async {
      const text = '{"hasCompletedOnboarding":false,"numStartups":3}';
      config.writeAsStringSync(text);
      final result = await Process.run('/bin/chmod', ['500', home.path]);
      expect(result.exitCode, 0);
      try {
        expect(await prepare(), isFalse);
        expect(config.readAsStringSync(), text);
        expect(home.listSync(), hasLength(1));
      } finally {
        await Process.run('/bin/chmod', ['700', home.path]);
      }
    },
    skip: Platform.isWindows ? 'POSIX permissions only' : false,
  );

  test(
    'preserves existing POSIX permissions and restricts a new file',
    () async {
      expect(await prepare(), isTrue);
      expect(config.statSync().mode & 0x1ff, 0x180);
      final result = await Process.run('/bin/chmod', ['640', config.path]);
      expect(result.exitCode, 0);
      config.writeAsStringSync('{"hasCompletedOnboarding":false}');
      expect(await prepare(), isTrue);
      expect(config.statSync().mode & 0x1ff, 0x1a0);
    },
    skip: Platform.isWindows ? 'POSIX permissions only' : false,
  );
}
