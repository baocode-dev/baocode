import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/src/config/frontmatter.dart';
import 'package:bao_agent/src/config/memory.dart';
import 'package:bao_agent/src/config/paths.dart';
import 'package:bao_agent/src/config/settings.dart';
import 'package:bao_agent/src/tools/diff.dart';
import 'package:bao_agent/src/tools/glob_pattern.dart';
import 'package:bao_agent/src/util/cancel.dart';
import 'package:bao_agent/src/util/html_markdown.dart';
import 'package:bao_agent/src/engine/transcript.dart';
import 'package:bao_agent/src/util/json.dart';
import 'package:bao_agent/src/util/processes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('GlobPattern', () {
    test('stars, double stars, sets, groups', () {
      bool m(String glob, String path) => GlobPattern(glob).matches(path);
      expect(m('*.dart', 'a.dart'), isTrue);
      expect(m('*.dart', 'lib/a.dart'), isFalse);
      expect(m('**/*.dart', 'lib/src/a.dart'), isTrue);
      expect(m('**/*.dart', 'a.dart'), isTrue);
      expect(m('lib/**', 'lib/a/b/c'), isTrue);
      expect(m('a?c', 'abc'), isTrue);
      expect(m('a?c', 'a/c'), isFalse);
      expect(m('[ab].txt', 'b.txt'), isTrue);
      expect(m('[!ab].txt', 'c.txt'), isTrue);
      expect(m('*.{js,ts}', 'x.ts'), isTrue);
      expect(m('*.{js,ts}', 'x.rs'), isFalse);
      expect(m('a.b', 'aXb'), isFalse);
      expect(m('lib/*.dart', r'lib\a.dart'), isTrue);
      expect(
        GlobPattern('*.MD', caseSensitive: false).matches('read.md'),
        isTrue,
      );
      expect(GlobPattern.isGlob('src/a.dart'), isFalse);
      expect(GlobPattern.isGlob('src/*.dart'), isTrue);
      expect(GlobPattern.base('src/lib/**/*.dart'), 'src/lib');
      expect(GlobPattern.base('a.dart'), '');
    });
  });

  group('Frontmatter', () {
    test('YAML, or a line at a time when it is not quite', () {
      final yaml = Frontmatter.parse(
        '---\nname: x\ntools: [Read, Grep]\nflag: true\nn: 3\n---\nBody\n',
      );
      expect(yaml.string('name'), 'x');
      expect(yaml.list('tools'), ['Read', 'Grep']);
      expect(yaml.flag('flag'), isTrue);
      expect(yaml.body, 'Body\n');
      final loose = Frontmatter.parse(
        '---\ndescription: Use it: when "needed"\ntools: Read, Grep\n---\n',
      );
      expect(loose.string('description'), 'Use it: when "needed"');
      expect(loose.list('tools'), ['Read', 'Grep']);
      final none = Frontmatter.parse('No header\n---\n');
      expect(none.fields, isEmpty);
      expect(none.body, 'No header\n---\n');
      expect(Frontmatter.parse('---\nunclosed: 1\n').fields, isEmpty);
      expect(Frontmatter.parse('---\r\na: "q"\r\n---\r\nB').string('a'), 'q');
      expect(Frontmatter.parse('---\nflag: "yes"\n---\n').flag('flag'), isNull);
    });
  });

  group('htmlToMarkdown', () {
    test('a page as Markdown: headings, links, lists, code, tables', () {
      const html = '''
<html><head><title>The Title</title><style>.x{}</style><script>alert(1)</script></head>
<body>
<nav>menu</nav>
<h1>Main</h1>
<p>Some <strong>bold</strong> and <em>italic</em> with <a href="/docs">a link</a> and <code>code()</code>.</p>
<ul><li>one</li><li>two<ul><li>nested</li></ul></li></ul>
<ol><li>first</li><li>second</li></ol>
<pre><code class="language-dart">void main() {}
</code></pre>
<blockquote>quoted</blockquote>
<img src="pic.png" alt="A picture">
<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
<hr>
<p>a&amp;b &lt;tag&gt;</p>
</body></html>''';
      final md = htmlToMarkdown(html, base: Uri.parse('https://site.dev/page'));
      expect(htmlTitle(html), 'The Title');
      expect(md, contains('# Main'));
      expect(md, contains('**bold**'));
      expect(md, contains('*italic*'));
      expect(md, contains('[a link](https://site.dev/docs)'));
      expect(md, contains('`code()`'));
      expect(md, contains('- one'));
      expect(md, contains('nested'));
      expect(md, contains('1. first'));
      expect(md, contains('```dart\nvoid main() {}'));
      expect(md, contains('> quoted'));
      expect(md, contains('![A picture](https://site.dev/pic.png)'));
      expect(md, contains('| A | B |'));
      expect(md, contains('| 1 | 2 |'));
      expect(md, contains('a&b <tag>'));
      expect(md, isNot(contains('alert')));
      expect(md, isNot(contains('.x{}')));
      expect(md, startsWith('The Title\n\n# Main'));
    });

    test('the title once, when the page opens with it', () {
      expect(
        htmlToMarkdown(
          '<head><title>Docs</title></head><body><h1>Docs</h1><p>x</p></body>',
        ),
        '# Docs\n\nx',
      );
      expect(
        htmlToMarkdown('<head><title>Only</title></head><body></body>'),
        'Only',
      );
    });
  });

  group('diffLines', () {
    test('hunks with context; added and removed', () {
      final before = [for (var i = 1; i <= 20; i++) 'line $i'].join('\n');
      final after = before
          .replaceFirst('line 10', 'changed')
          .replaceFirst('line 20', 'line 20\nadded');
      final hunks = diffLines(before, after);
      expect(hunks, hasLength(2));
      expect(hunks.first.oldStart, 7);
      expect(hunks.first.lines, contains('-line 10'));
      expect(hunks.first.lines, contains('+changed'));
      expect(hunks.first.added, 1);
      expect(hunks.first.removed, 1);
      expect(hunks.last.lines.last, '+added');
      expect(patchJson(hunks).first, containsPair('oldLines', 7));
      expect(diffLines('same', 'same'), isEmpty);
      expect(diffLines('', 'new\n').single.lines, ['+new']);
      expect(diffLines('gone\n', '').single.lines, ['-gone']);
    });
  });

  group('MemoryLoader', () {
    late Directory root;
    late AgentPaths paths;

    setUp(() {
      root = Directory.systemTemp.createTempSync('memory_');
      paths = AgentPaths(
        home: p.join(root.path, 'home'),
        configDir: p.join(root.path, 'home', '.claude'),
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    void write(String path, String text) {
      final file = File(p.join(root.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text);
    }

    test('user, project up the tree, rules, local; imports after', () {
      write('home/.claude/CLAUDE.md', 'User memory.');
      write('home/.claude/rules/style.md', 'User rule.');
      write('work/CLAUDE.md', 'Workspace memory.');
      write(
        'work/app/CLAUDE.md',
        'App memory. See @docs/more.md and `@not/this.md`.',
      );
      write('work/app/docs/more.md', 'More, with @deeper.md');
      write('work/app/docs/deeper.md', 'Deepest.');
      write(
        'work/app/.claude/rules/dart.md',
        '---\npaths:\n  - "lib/**/*.dart"\n---\nDart rule.',
      );
      write('work/app/CLAUDE.local.md', 'Local memory.');
      write('work/app/lib/CLAUDE.md', 'Nested memory.');
      write('work/app/self.md', 'Loops @self.md');
      final files = MemoryLoader(paths).load(p.join(root.path, 'work', 'app'));
      final byName = {
        for (final f in files) p.relative(f.path, from: root.path): f,
      };
      expect(byName.keys, [
        'home/.claude/CLAUDE.md',
        'home/.claude/rules/style.md',
        'work/CLAUDE.md',
        'work/app/CLAUDE.md',
        // What a file imports comes after it, a file of its own.
        'work/app/docs/more.md',
        'work/app/docs/deeper.md',
        'work/app/.claude/rules/dart.md',
        'work/app/CLAUDE.local.md',
      ]);
      expect(byName['home/.claude/CLAUDE.md']!.type, MemoryType.user);
      expect(byName['work/app/CLAUDE.local.md']!.type, MemoryType.local);
      final app = byName['work/app/CLAUDE.md']!.content;
      expect(app, contains('See @docs/more.md'));
      expect(app, contains('`@not/this.md`'));
      expect(byName['work/app/docs/deeper.md']!.content, 'Deepest.');
      final rule = byName['work/app/.claude/rules/dart.md']!;
      expect(rule.conditional, isTrue);
      final cwd = p.join(root.path, 'work', 'app');
      expect(MemoryLoader.rulesFor(files, p.join(cwd, 'lib', 'a.dart'), cwd), [
        rule,
      ]);
      expect(
        MemoryLoader.rulesFor(files, p.join(cwd, 'test', 'a.dart'), cwd),
        isEmpty,
      );
      final nested = MemoryLoader(paths).nested(p.join(cwd, 'lib'), {});
      expect(nested.single.content, 'Nested memory.');
      for (final type in MemoryType.values) {
        expect(MemoryFile('x', type, 'y').description, isNotEmpty);
      }
    });
  });

  group('settings', () {
    late Directory root;
    late AgentPaths paths;

    setUp(() {
      root = Directory.systemTemp.createTempSync('settings_');
      paths = AgentPaths(
        home: root.path,
        configDir: p.join(root.path, '.claude'),
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    void write(String path, Map<String, Object?> json) {
      final file = File(p.join(root.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(json));
    }

    test('layered: user, project, local, flag; rules from all', () {
      write('.claude/settings.json', {
        'model': 'opus',
        'permissions': {
          'allow': ['Read'],
        },
        'env': {'A': '1'},
      });
      write('app/.claude/settings.json', {
        'model': 'sonnet',
        'permissions': {
          'deny': ['WebFetch'],
          'additionalDirectories': ['../shared', '~/notes'],
        },
        'attribution': {'commit': '', 'pr': 'PR line'},
      });
      write('app/.claude/settings.local.json', {
        'permissions': {
          'allow': ['Bash(ls:*)'],
        },
        'env': {'B': '2'},
      });
      final settings = AgentSettings(
        paths: paths,
        cwd: p.join(root.path, 'app'),
        flag: {'effortLevel': 'high', 'alwaysThinkingEnabled': true},
      );
      expect(settings.model, 'sonnet');
      expect(settings['env'], {'A': '1', 'B': '2'});
      expect(settings.alwaysThinkingEnabled, isTrue);
      expect(
        settings.rules.map((r) => '${r.behavior}:${r.rule}'),
        containsAll(['allow:Read', 'deny:WebFetch', 'allow:Bash(ls:*)']),
      );
      expect(settings.additionalDirectories, [
        p.join(root.path, 'shared'),
        p.join(root.path, 'notes'),
      ]);
      expect(settings.attribution, (commit: '', pr: 'PR line'));
      settings.addRules(['Bash(make:*)'], 'allow', SettingsSource.local);
      expect(settings.rules.map((r) => r.rule), contains('Bash(make:*)'));
      settings.addRules(['Edit'], 'allow', SettingsSource.session);
      expect(settings.rules.last.source, SettingsSource.session);
      settings.applyFlag({'model': 'haiku'});
      expect(settings.model, 'haiku');
      settings.addDirectories(['/extra'], SettingsSource.local);
      settings.reload();
      expect(settings.additionalDirectories, contains('/extra'));
      expect(SettingsSource.parse('localSettings'), SettingsSource.local);
      expect(SettingsSource.parse('nope'), isNull);
    });

    test('mergeSettings and the JSON helpers', () {
      expect(
        mergeSettings(
          {
            'a': {'x': 1},
            'l': [1, 2],
            's': 'old',
          },
          {
            'a': {'y': 2},
            'l': [2, 3],
            's': 'new',
          },
        ),
        {
          'a': {'x': 1, 'y': 2},
          'l': [1, 2, 3],
          's': 'new',
        },
      );
      expect(asInt('12'), 12);
      expect(asInt(3.0), 3);
      expect(asInt('x'), isNull);
      expect(asBool('true'), isTrue);
      expect(asBool('no'), isNull);
      expect(asText('  '), isNull);
      expect(asMap('x'), isEmpty);
      expect(asList(null), isEmpty);
      final original = {
        'a': [
          {'b': 1},
        ],
      };
      final copy = deepCopy(original) as Map;
      ((copy['a'] as List).first as Map)['b'] = 2;
      expect(original['a']!.first['b'], 1);
    });
  });

  group('CancelToken', () {
    test('cancelled once, told, guarded', () async {
      final token = CancelToken();
      expect(token.isCancelled, isFalse);
      token.check();
      final told = token.whenCancelled;
      token.cancel('why');
      token.cancel('again');
      await told;
      expect(token.reason, 'why');
      expect(token.check, throwsA(isA<Cancelled>()));
      await expectLater(
        token.guard(Future<void>.delayed(const Duration(seconds: 5))),
        throwsA(isA<Cancelled>()),
      );
      expect('${const Cancelled('x')}', contains('x'));
    });

    test('guarded: its value, its error, or cancelled', () async {
      final token = CancelToken();
      expect(await token.guard(Future.value(1)), 1);
      await expectLater(
        token.guard(Future<int>.error(StateError('no'))),
        throwsStateError,
      );
      token.cancel('stop');
      await expectLater(
        token.guard(Future.value(1)),
        throwsA(isA<Cancelled>()),
      );
    });
  });

  group('Shell', () {
    Shell windows(Map<String, String> env, Set<String> files) =>
        Shell.find(env, windows: true, exists: files.contains);

    test('on Windows: Git\'s bash, as set, by the git on the PATH, where '
        'installed; else cmd', () {
      expect(
        windows(
          {'CLAUDE_CODE_GIT_BASH_PATH': r'D:\git\bash.exe'},
          {r'D:\git\bash.exe'},
        ).executable,
        r'D:\git\bash.exe',
      );
      expect(
        windows(
          {'Path': r'C:\Windows;D:\Tools\Git\cmd'},
          {r'D:\Tools\Git\cmd\git.exe', r'D:\Tools\Git\bin\bash.exe'},
        ).executable,
        r'D:\Tools\Git\bin\bash.exe',
      );
      expect(
        windows({}, {r'C:\Program Files\Git\bin\bash.exe'}).executable,
        r'C:\Program Files\Git\bin\bash.exe',
      );
      expect(
        windows(
          {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'},
          {r'C:\Users\me\AppData\Local\Programs\Git\bin\bash.exe'},
        ).executable,
        r'C:\Users\me\AppData\Local\Programs\Git\bin\bash.exe',
      );
      final cmd = windows({'COMSPEC': r'C:\Windows\system32\cmd.exe'}, {});
      expect(
        (cmd.executable, cmd.posix),
        (r'C:\Windows\system32\cmd.exe', false),
      );
      expect(cmd.arguments('dir', 'x'), ['/d', '/s', '/c', 'dir']);
      expect(windows({}, {}).executable, 'cmd.exe');
    });

    test('elsewhere: the user\'s bash or zsh, else bash, else sh', () {
      Shell find(Map<String, String> env, Set<String> files) =>
          Shell.find(env, windows: false, exists: files.contains);
      expect(find({'SHELL': '/opt/zsh'}, {'/opt/zsh'}).executable, '/opt/zsh');
      expect(
        find(
          {'SHELL': '/usr/bin/fish'},
          {'/usr/bin/fish', '/bin/bash'},
        ).executable,
        '/bin/bash',
      );
      expect(find({}, {}).executable, '/bin/sh');
      final bash = find({}, {'/bin/bash'});
      expect(bash.arguments('ls', '/tmp/cwd'), [
        '-c',
        isA<String>(),
        'bash',
        'ls',
        '/tmp/cwd',
      ]);
    });
  });

  group('killTree', () {
    test('a command and what it started, ended', () async {
      final process = await Process.start('/bin/sh', [
        '-c',
        'sleep 30 & sleep 30; wait',
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await killTree(process.pid);
      expect(
        await process.exitCode.timeout(const Duration(seconds: 5)),
        isNot(0),
      );
    });

    test('Windows\' way, where there is no taskkill: the process', () async {
      final process = await Process.start('sleep', ['30']);
      await killTree(process.pid, windows: true);
      expect(
        await process.exitCode.timeout(const Duration(seconds: 5)),
        isNot(0),
      );
    });
  }, skip: Platform.isWindows);

  test('a conversation told as text: tools, pictures, notes left out', () {
    final text = transcriptText([
      {'role': 'user', 'content': 'Fix it'},
      {'role': 'user', 'content': '<system-reminder>x</system-reminder>'},
      {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'Looking'},
          {
            'type': 'tool_use',
            'name': 'Read',
            'input': {'file_path': 'a'},
          },
        ],
      },
      {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'is_error': true,
            'content': [
              {'type': 'text', 'text': 'gone'},
              {'type': 'image', 'source': {}},
            ],
          },
        ],
      },
    ]);
    expect(text, contains('User: Fix it'));
    expect(text, isNot(contains('system-reminder')));
    expect(text, contains('Assistant called Read: {"file_path":"a"}'));
    expect(text, contains('Tool result (error): gone\n[image]'));
    expect(
      transcriptText([
        {'role': 'user', 'content': 'x' * 50},
      ], maxChars: 10),
      '…${'x' * 10}',
    );
  });
}
