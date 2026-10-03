import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:baocode/customize/customization_store.dart';
import 'package:baocode/customize/customizations.dart';

void main() {
  late Directory temp;
  late String config;
  late String project;
  late CustomizationStore store;

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('customize');
    config = p.join(temp.path, 'home', '.claude');
    project = p.join(temp.path, 'app');
    store = CustomizationStore(
      configDir: config,
      homeDir: p.join(temp.path, 'home'),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('reads front matter, block scalars and quotes included', () {
    const text =
        '---\n'
        'name: "pdf"\n'
        'description: >-\n'
        '  Reads PDFs\n'
        '  and fills forms.\n'
        'tools: Read\n'
        '---\n'
        '\n'
        '# PDF\n';
    expect(parseFrontMatter(text), {
      'name': 'pdf',
      'description': 'Reads PDFs and fills forms.',
      'tools': 'Read',
    });
    expect(describeMarkdown('# Title\n\nFirst line.\n'), 'First line.');
    expect(bodyOf(text), '\n# PDF\n');
  });

  test('lists the user\'s and the project\'s skills, agents, commands '
      'and rules', () async {
    write(
      p.join(config, 'skills', 'pdf', 'SKILL.md'),
      '---\nname: pdf\ndescription: Reads PDFs\n---\n',
    );
    write(p.join(config, 'skills', 'empty', 'notes.txt'), 'no SKILL.md');
    // Synced from claude.ai, under a bucket: shown, not edited.
    write(
      p.join(config, 'skills', 'synced', 'bucket-1', 'docx', 'SKILL.md'),
      '---\nname: docx\ndescription: Word files\n---\n',
    );
    write(
      p.join(config, 'skills', 'synced', '.bucket-1', 'stale', 'SKILL.md'),
      '---\nname: stale\n---\n',
    );
    write(
      p.join(project, '.claude', 'skills', 'deploy', 'SKILL.md'),
      '# Deploy\n\nShips it.\n',
    );
    write(
      p.join(config, 'agents', 'reviewer.md'),
      '---\nname: code-reviewer\ndescription: Reviews diffs\n---\n',
    );
    write(
      p.join(project, '.claude', 'commands', 'git', 'ship.md'),
      '---\ndescription: Commit and push\n---\n',
    );
    write(p.join(config, 'CLAUDE.md'), '# Me\n\nBe brief.\n');
    write(p.join(project, 'CLAUDE.md'), 'Use Dart.\n');
    write(p.join(project, '.claude', 'rules', 'tests.md'), 'Test it.\n');

    final skills = await store.list(CustomizationKind.skills, project: project);
    expect(
      [for (final s in skills) (s.scope, s.name, s.description)],
      [
        (CustomizationScope.user, 'pdf', 'Reads PDFs'),
        (CustomizationScope.synced, 'docx', 'Word files'),
        (CustomizationScope.project, 'deploy', 'Ships it.'),
      ],
    );
    expect(skills.first.removePath, p.join(config, 'skills', 'pdf'));
    expect(skills[1].editable, isFalse);
    expect(skills[1].removePath, isNull);

    final agents = await store.list(CustomizationKind.subagents);
    expect(agents.single.name, 'code-reviewer');

    final commands = await store.list(
      CustomizationKind.commands,
      project: project,
    );
    expect(commands.single.name, '/ship');
    expect(commands.single.description, 'Commit and push');

    final rules = await store.list(CustomizationKind.rules, project: project);
    expect(
      [for (final r in rules) (r.scope, r.name, r.removePath != null)],
      [
        (CustomizationScope.user, 'CLAUDE.md', false),
        (
          CustomizationScope.project,
          p.join('.claude', 'rules', 'tests.md'),
          true,
        ),
        (CustomizationScope.project, 'CLAUDE.md', false),
      ],
    );
  });

  test('lists servers, hooks and plugins from their JSON files', () async {
    write(
      p.join(temp.path, 'home', '.claude.json'),
      jsonEncode({
        'mcpServers': {
          'github': {'type': 'http', 'url': 'https://example.com/mcp'},
        },
        'projects': {
          project: {
            'mcpServers': {
              'db': {
                'command': 'npx',
                'args': ['db-mcp', '--ro'],
              },
            },
          },
        },
      }),
    );
    write(
      p.join(project, '.mcp.json'),
      jsonEncode({
        'mcpServers': {
          'docs': {'command': 'docs-mcp'},
        },
      }),
    );
    write(
      p.join(config, 'settings.json'),
      jsonEncode({
        'hooks': {
          'PostToolUse': [
            {
              'matcher': 'Edit',
              'hooks': [
                {'type': 'command', 'command': 'dart format .'},
              ],
            },
          ],
        },
        'enabledPlugins': {'review@market': true},
      }),
    );
    final installRoot = p.join(config, 'plugins', 'cache', 'review');
    write(
      p.join(config, 'plugins', 'installed_plugins.json'),
      jsonEncode({
        'version': 2,
        'plugins': {
          'review@market': [
            {'scope': 'user', 'installPath': installRoot, 'version': '1.2.0'},
          ],
          'other@market': [
            {'scope': 'user', 'installPath': '/nowhere', 'version': '0.1.0'},
          ],
        },
      }),
    );
    write(
      p.join(installRoot, '.claude-plugin', 'plugin.json'),
      jsonEncode({'name': 'review', 'description': 'Reviews code'}),
    );

    final servers = await store.list(CustomizationKind.mcps, project: project);
    expect(
      [for (final s in servers) (s.scope, s.name, s.description, s.editable)],
      [
        (
          CustomizationScope.user,
          'github',
          'http · https://example.com/mcp',
          false,
        ),
        (CustomizationScope.project, 'docs', 'docs-mcp', true),
        (CustomizationScope.local, 'db', 'npx db-mcp --ro', false),
      ],
    );
    expect(servers.first.detail, contains('"url"'));

    final hooks = await store.list(CustomizationKind.hooks);
    expect(hooks.single.name, 'PostToolUse · Edit');
    expect(hooks.single.description, 'dart format .');
    expect(hooks.single.path, p.join(config, 'settings.json'));

    final plugins = await store.list(CustomizationKind.plugins);
    expect(
      [for (final x in plugins) (x.name, x.description, x.enabled)],
      [('other', 'market · 0.1.0', false), ('review', 'Reviews code', true)],
    );
  });

  test('lists none of each where there are none', () async {
    for (final kind in CustomizationKind.values) {
      expect(await store.list(kind, project: project), isEmpty);
    }
  });

  test('makes new ones from templates, edits and deletes them', () async {
    final skill = await store.create(
      CustomizationKind.skills,
      CustomizationScope.user,
      'release-notes',
    );
    expect(skill, p.join(config, 'skills', 'release-notes', 'SKILL.md'));
    expect(parseFrontMatter(await store.read(skill))['name'], 'release-notes');
    await expectLater(
      store.create(
        CustomizationKind.skills,
        CustomizationScope.user,
        'release-notes',
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      () => store.create(
        CustomizationKind.skills,
        CustomizationScope.user,
        '../escape',
      ),
      throwsArgumentError,
    );

    final rule = await store.create(
      CustomizationKind.rules,
      CustomizationScope.project,
      'style',
      project: project,
    );
    expect(rule, p.join(project, '.claude', 'rules', 'style.md'));

    await store.write(skill, '---\nname: notes\ndescription: Edited\n---\n');
    final listed = await store.list(CustomizationKind.skills);
    expect(listed.single.description, 'Edited');

    await store.delete(listed.single);
    expect(Directory(p.dirname(skill)).existsSync(), isFalse);
    expect(await store.list(CustomizationKind.skills), isEmpty);
  });
}
