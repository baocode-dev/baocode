import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_agent/bao_agent.dart' show AgentPaths;
// ignore: implementation_imports
import 'package:bao_agent/src/config/extensions.dart' show loadPromptCommands;
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:bao_remote/server.dart';
import 'package:baocode/remote/remote_skills.dart';
import 'package:baocode/stash/stash_skill.dart';
import 'package:baocode/usage/usage_skill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

void main() {
  late Directory tempDir;
  late Directory localConfig;
  late Directory remoteConfig;
  late bool Function() previousSetting;

  void writeFile(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('baocode-remote-skills-');
    localConfig = Directory(p.join(tempDir.path, 'local-claude'))
      ..createSync(recursive: true);
    remoteConfig = Directory(p.join(tempDir.path, 'remote-claude'))
      ..createSync(recursive: true);
    previousSetting = RemoteSkillsSetting.current;
    RemoteSkillsSetting.current = () => true;
    ClaudeEnvironment.use({
      ...Platform.environment,
      'CLAUDE_CONFIG_DIR': remoteConfig.path,
    });
  });

  tearDown(() {
    RemoteSkillsSetting.current = previousSetting;
    ClaudeEnvironment.use(null);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('collects local skills, follows symlinks, skips stash and ignored files',
      () async {
    // Regular skill with nested files and ignored directories.
    writeFile(
      p.join(localConfig.path, 'skills', 'deploy', 'SKILL.md'),
      '---\nname: smart-deploy\ndescription: Deploy helper\n---\nRun deploy.\n',
    );
    writeFile(
      p.join(localConfig.path, 'skills', 'deploy', 'references', 'guide.md'),
      '# Guide\n',
    );
    final scriptPath = p.join(
      localConfig.path,
      'skills',
      'deploy',
      'scripts',
      'run.sh',
    );
    writeFile(scriptPath, '#!/bin/sh\necho ok\n');
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['+x', scriptPath]);
    }
    writeFile(
      p.join(localConfig.path, 'skills', 'deploy', '.git', 'HEAD'),
      'ref: refs/heads/main\n',
    );
    writeFile(
      p.join(localConfig.path, 'skills', 'deploy', 'node_modules', 'a.js'),
      'module.exports = 1;\n',
    );

    // BaoCode Stash skill (local path hardcoded) must be skipped.
    writeFile(
      p.join(localConfig.path, 'skills', StashSkill.name, 'SKILL.md'),
      StashSkill.text('/Users/me/stash'),
    );

    // BaoCode Usage skill (uses SDK MCP tools) is kept.
    writeFile(
      p.join(localConfig.path, 'skills', UsageSkill.name, 'SKILL.md'),
      UsageSkill.text(),
    );

    // Symlinked skill directory.
    final linkedTarget = Directory(p.join(tempDir.path, 'external-skill'))
      ..createSync();
    writeFile(
      p.join(linkedTarget.path, 'SKILL.md'),
      '---\nname: linked-skill\ndescription: From symlink\n---\nBody.\n',
    );
    Link(
      p.join(localConfig.path, 'skills', 'linked-skill'),
    ).createSync(linkedTarget.path);

    // Broken symlink must not throw.
    Link(
      p.join(localConfig.path, 'skills', 'broken-skill'),
    ).createSync(p.join(tempDir.path, 'does-not-exist'));

    final bundle = await RemoteSkills.collectLocal(configDir: localConfig.path);
    expect(bundle.hash, isNotEmpty);
    expect(
      bundle.skills.map((s) => s.directory).toList(),
      [UsageSkill.name, 'deploy', 'linked-skill'],
    );

    final deploy = bundle.skills.firstWhere((s) => s.directory == 'deploy');
    expect(deploy.name, 'smart-deploy');
    expect(
      deploy.files.map((f) => f.path).toList(),
      ['SKILL.md', 'references/guide.md', 'scripts/run.sh'],
    );
    if (!Platform.isWindows) {
      expect(
        deploy.files.firstWhere((f) => f.path == 'scripts/run.sh').executable,
        isTrue,
      );
    }

    // Deterministic hash changes when content changes.
    final same = await RemoteSkills.collectLocal(configDir: localConfig.path);
    expect(same.hash, bundle.hash);
    writeFile(
      p.join(localConfig.path, 'skills', 'deploy', 'references', 'guide.md'),
      '# Updated Guide\n',
    );
    final changed = await RemoteSkills.collectLocal(configDir: localConfig.path);
    expect(changed.hash, isNot(bundle.hash));
  });

  test('stages skills over RPC, caches by hash, respects remote conflicts, '
      'and cleans up on shutdown', () async {
    writeFile(
      p.join(localConfig.path, 'skills', 'local-only', 'SKILL.md'),
      '---\nname: local-only\ndescription: Local skill\n---\nUse local.\n',
    );
    final localScript = p.join(
      localConfig.path,
      'skills',
      'local-only',
      'scripts',
      'hello.sh',
    );
    writeFile(localScript, '#!/bin/sh\necho hi\n');
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['+x', localScript]);
    }

    // Same folder name as a remote skill -> remote must win.
    writeFile(
      p.join(localConfig.path, 'skills', 'shared-dir', 'SKILL.md'),
      '---\nname: shared-dir\ndescription: Local version\n---\nLocal.\n',
    );
    writeFile(
      p.join(remoteConfig.path, 'skills', 'shared-dir', 'SKILL.md'),
      '---\nname: shared-dir\ndescription: Remote version\n---\nRemote.\n',
    );

    // Different folder name, same frontmatter `name` as remote -> remote wins.
    writeFile(
      p.join(localConfig.path, 'skills', 'local-alias', 'SKILL.md'),
      '---\nname: custom-review\ndescription: Local review\n---\nLocal.\n',
    );
    writeFile(
      p.join(remoteConfig.path, 'skills', 'host-review', 'SKILL.md'),
      '---\nname: custom-review\ndescription: Remote review\n---\nRemote.\n',
    );

    final harness = await RemoteHarness.start();
    try {
      final root1 = await RemoteSkills.stageFor(
        harness.client,
        configDir: localConfig.path,
      );
      expect(root1, isNotNull);
      expect(
        File(p.join(root1!, '.claude', 'skills', 'local-only', 'SKILL.md'))
            .existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(root1, '.claude', 'skills', 'shared-dir'))
            .existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(root1, '.claude', 'skills', 'local-alias'))
            .existsSync(),
        isFalse,
      );
      if (!Platform.isWindows) {
        final stagedScript = File(
          p.join(root1, '.claude', 'skills', 'local-only', 'scripts', 'hello.sh'),
        );
        expect(stagedScript.statSync().mode & 0x49, isNonZero);
      }

      // Built-in core discovers the staged skill via --add-dir while keeping
      // the remote host's own skills on conflict.
      final projectDir = Directory(p.join(tempDir.path, 'project'))
        ..createSync();
      final commands = loadPromptCommands(
        paths: AgentPaths(home: tempDir.path, configDir: remoteConfig.path),
        cwd: projectDir.path,
        plugins: const [],
        additional: [root1],
      );
      final byName = {for (final c in commands) c.name: c};
      expect(byName['local-only']?.description, 'Local skill');
      expect(byName['shared-dir']?.description, 'Remote version');
      expect(byName['custom-review']?.description, 'Remote review');

      // Second call hits cache (only 1 check request, no re-upload).
      final sentBefore = harness.sent.length;
      final root2 = await RemoteSkills.stageFor(
        harness.client,
        configDir: localConfig.path,
      );
      expect(root2, root1);
      expect(harness.sent.length - sentBefore, 1);

      // Turning the setting off returns null without touching the server.
      RemoteSkillsSetting.current = () => false;
      final disabled = await RemoteSkills.stageFor(
        harness.client,
        configDir: localConfig.path,
      );
      expect(disabled, isNull);

      // Shutdown deletes every staged directory on the remote host.
      await harness.close();
      expect(Directory(root1).existsSync(), isFalse);
    } finally {
      await harness.close();
    }
  });

  test('ServerSkills rejects unsafe paths and returns null when all conflict',
      () async {
    writeFile(
      p.join(remoteConfig.path, 'skills', 'only-one', 'SKILL.md'),
      '---\nname: only-one\n---\nRemote.\n',
    );
    final serverSkills = ServerSkills(
      configDir: () async => remoteConfig.path,
      parent: () => tempDir,
    );
    try {
      final result = await serverSkills.stage({
        'hash': 'abc',
        'skills': [
          StagedSkill(
            directory: '../escape',
            name: 'escape',
            files: [
              StagedSkillFile(
                path: 'SKILL.md',
                bytes: Uint8List.fromList(utf8.encode('bad')),
              ),
            ],
          ).toJson(),
          StagedSkill(
            directory: 'only-one',
            name: 'only-one',
            files: [
              StagedSkillFile(
                path: 'SKILL.md',
                bytes: Uint8List.fromList(utf8.encode('conflict')),
              ),
            ],
          ).toJson(),
        ],
      });
      expect(result['root'], isNull);

      // Cached empty state answers `{root: null}` on check-only too.
      final check = await serverSkills.stage({'hash': 'abc'});
      expect(check['missing'], isNot(true));
      expect(check['root'], isNull);
    } finally {
      await serverSkills.dispose();
    }
  });
}
