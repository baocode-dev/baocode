// Makes the website's pictures and videos of the app (see README.md):
// sets up a made-up developer's machine for each language, builds the
// showcase app, runs its scenes, and turns what they took into the site's
// WebP and MP4 files.
//
//   dart run tool/showcase/run.dart                 all scenes, en and zh
//   dart run tool/showcase/run.dart main ide        some scenes
//   dart run tool/showcase/run.dart --locale zh     one language
//   dart run tool/showcase/run.dart --no-build      the app as last built
//   dart run tool/showcase/run.dart --no-video      pictures only
//   dart run tool/showcase/run.dart --publish       into site/shots/<lang>/
//   dart run tool/showcase/run.dart --convert-only  the last run's, made again
//
// macOS only: the pictures are of the macOS window.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'code.dart';
import 'story.dart';

/// Where the made-up machines are: outside the user's home, so that no
/// path of theirs shows in a picture.
const _machines = '/Users/Shared/bao-showcase';

/// The well-known repositories the projects are, cloned once.
const _repositories = {'hono': 'https://github.com/honojs/hono.git'};

Future<void> main(List<String> args) async {
  if (!Platform.isMacOS) {
    stderr.writeln('The showcase runs on macOS.');
    exit(2);
  }
  final repo = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..', '..'),
  );
  var locales = ['en', 'zh'];
  var build = true, video = true, publish = false, play = true;
  final scenes = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--locale':
        locales = args[++i].split(',');
      case '--no-build':
        build = false;
      case '--no-video':
        video = false;
      case '--publish':
        publish = true;
      case '--convert-only':
        build = false;
        play = false;
      case final scene:
        scenes.add(scene);
    }
  }
  final cache = p.join(repo, 'build', 'showcase');
  await _cloneRepositories(p.join(cache, 'repos'));
  // Built in a copy of the sources, run from a copy of its own: the perf
  // app builds into the same place, maybe at the same time.
  final bundle = p.join(cache, 'app', 'BaoCode.app');
  final sources = p.join(cache, 'src');
  if (build) {
    await _run('rsync', [
      '-a',
      '--delete',
      for (final excluded in _notBuilt) '--exclude=$excluded',
      '$repo/',
      '$sources/',
    ]);
    if (!await _build(sources)) exit(1);
    if (Directory(bundle).existsSync()) {
      Directory(bundle).deleteSync(recursive: true);
    }
    Directory(p.dirname(bundle)).createSync(recursive: true);
    await _run('cp', [
      '-cR',
      p.join(sources, 'build/macos/Build/Products/Profile/BaoCode.app'),
      bundle,
    ]);
  }
  final app = p.join(bundle, 'Contents', 'MacOS', 'BaoCode');
  var failed = false;
  for (final locale in locales) {
    Story.locale = locale;
    final machine = p.join(_machines, locale);
    final home = p.join(machine, 'home');
    final data = p.join(machine, 'data');
    final out = p.join(cache, 'out');
    if (!play) {
      await _convert(
        p.join(out, locale),
        publish ? p.join(repo, 'site', 'shots', locale) : null,
      );
      continue;
    }
    print('[$locale] setting up $machine');
    await _setUpMachine(machine, home, data, p.join(cache, 'repos'));
    print(
      '[$locale] running ${scenes.isEmpty ? 'all scenes' : scenes.join(', ')}',
    );
    final code = await _runApp(
      app,
      home: home,
      data: data,
      out: out,
      locale: locale,
      scenes: scenes,
      video: video,
      log: p.join(cache, 'showcase-$locale.log'),
    );
    if (code != 0) {
      failed = true;
      stderr.writeln(
        '[$locale] the app exited with $code; see build/showcase/showcase-$locale.log',
      );
    }
    await _convert(
      p.join(out, locale),
      publish ? p.join(repo, 'site', 'shots', locale) : null,
    );
  }
  exit(failed ? 1 : 0);
}

/// What the build needs not: kept out of the copy of the sources.
const _notBuilt = [
  '/build',
  '/.git',
  '/site',
  '/site-worker',
  '/docs',
  '/test',
  '/release-notes',
  '/.wrangler',
  '.dart_tool',
  'target',
];

Future<void> _cloneRepositories(String into) async {
  for (final MapEntry(key: name, value: url) in _repositories.entries) {
    final path = p.join(into, name);
    if (Directory(path).existsSync()) continue;
    print('Cloning $url...');
    final result = await Process.run('git', [
      'clone',
      '--quiet',
      '--depth',
      '120',
      '--no-single-branch',
      url,
      path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('git clone failed: ${result.stderr}');
    }
  }
}

Future<bool> _build(String repo) async {
  print('Building the showcase app (flutter build macos --profile)...');
  final process = await Process.start(
    'flutter',
    ['build', 'macos', '--profile', '-t', 'tool/showcase/showcase_app.dart'],
    workingDirectory: repo,
    mode: ProcessStartMode.inheritStdio,
  );
  return await process.exitCode == 0;
}

// --- The machine ------------------------------------------------------------------

Future<void> _setUpMachine(
  String machine,
  String home,
  String data,
  String repos,
) async {
  final root = Directory(machine);
  if (root.existsSync()) root.deleteSync(recursive: true);
  Directory(home).createSync(recursive: true);
  void write(String path, String text) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  // Git and the shell.
  write(p.join(home, '.gitconfig'), '''[user]
\tname = ${Story.author}
\temail = ${Story.email}
[init]
\tdefaultBranch = main
[color]
\tui = auto
[advice]
\tdetachedHead = false
''');
  write(p.join(home, '.zshrc'), r'''autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' %F{blue}git:(%F{red}%b%F{blue})%f'
setopt PROMPT_SUBST
PROMPT='%F{green}➜%f  %F{cyan}%1~%f${vcs_info_msg_0_} '
export PATH="$HOME/.local/bin:$PATH"
export LANG=en_US.UTF-8
''');
  final bun = p.join(home, '.local', 'bin', 'bun');
  write(bun, _bunScript);
  await Process.run('chmod', ['+x', bun]);

  // The projects: hono a clone of the real one, the others small.
  final code = p.join(home, 'code');
  Directory(code).createSync(recursive: true);
  await _run('cp', ['-cR', p.join(repos, 'hono'), p.join(code, 'hono')]);
  await _commitRateLimiter(p.join(code, 'hono'), home);
  for (final project in Story.projects) {
    final path = p.join(code, project.name);
    if (Directory(path).existsSync()) continue;
    write(p.join(path, 'README.md'), '# ${project.name}\n');
    await _run('git', ['init', '-q'], path, home);
    await _run('git', ['add', '.'], path, home);
    await _run('git', ['commit', '-qm', 'Initial commit'], path, home);
  }

  // Claude Code's sessions and skills.
  final claude = p.join(home, '.claude');
  final random = Random(11);
  String uuid() {
    String hex(int n) =>
        [for (var i = 0; i < n; i++) random.nextInt(16).toRadixString(16)]
            .join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  final now = DateTime.now().toUtc();
  for (final project in Story.projects) {
    final cwd = p.join(code, project.name);
    final dir = p.join(
      claude,
      'projects',
      cwd.replaceAll(RegExp('[^a-zA-Z0-9]'), '-'),
    );
    for (final session in project.sessions) {
      final id = uuid();
      final asked = now.subtract(
        Duration(minutes: session.minutes, seconds: 40),
      );
      final answered = now.subtract(Duration(minutes: session.minutes));
      final user = uuid(), assistant = uuid();
      final common = {
        'isSidechain': false,
        'userType': 'external',
        'cwd': cwd,
        'sessionId': id,
        'version': '2.1.0',
        'gitBranch': 'main',
      };
      final lines = [
        {
          'parentUuid': null,
          ...common,
          'type': 'user',
          'message': {'role': 'user', 'content': session.prompt},
          'uuid': user,
          'timestamp': asked.toIso8601String(),
        },
        {
          'parentUuid': user,
          ...common,
          'type': 'assistant',
          'message': {
            'id': 'msg_${id.substring(0, 8)}',
            'type': 'message',
            'role': 'assistant',
            'model': 'claude-opus-5-5',
            'content': [
              {'type': 'text', 'text': session.answer},
            ],
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 4, 'output_tokens': 210},
          },
          'uuid': assistant,
          'timestamp': answered.toIso8601String(),
        },
        {'type': 'ai-title', 'aiTitle': session.title, 'sessionId': id},
      ];
      write(p.join(dir, '$id.jsonl'), '${lines.map(jsonEncode).join('\n')}\n');
    }
  }
  void skill(String folder, String name, String description) =>
      write(p.join(folder, 'skills', name, 'SKILL.md'), '''---
name: $name
description: $description
---

# $name

$description
''');
  for (final (name, description) in Story.skills) {
    skill(claude, name, description);
  }
  // hono's own, out of Git's sight: the scenes put its files back with
  // `git clean`.
  final hono = p.join(code, 'hono');
  for (final (name, description) in Story.honoSkills) {
    skill(p.join(hono, '.claude'), name, description);
  }
  File(p.join(hono, '.git', 'info', 'exclude'))
      .writeAsStringSync('.claude/\n', mode: FileMode.append);

  // The emoji pictures the app would fetch: the installed app's, if it
  // has them.
  final emoji = p.join(
    Platform.environment['HOME']!,
    'Library/Application Support/baocode/cache/emoji',
  );
  if (Directory(emoji).existsSync()) {
    Directory(p.join(data, 'cache')).createSync(recursive: true);
    await _run('cp', ['-cR', emoji, p.join(data, 'cache', 'emoji')]);
  }

  // The app's data folder: its settings.
  write(
    p.join(data, 'User', 'settings.json'),
    const JsonEncoder.withIndent('  ').convert({
      'workbench.colorTheme': 'Bao Dark',
      'update.mode': 'none',
      'telemetry.telemetryLevel': 'off',
      // No tip or ask (a star on GitHub) over a scene.
      'workbench.tips.enabled': false,
    }),
  );
}

Future<void> _run(
  String executable,
  List<String> args, [
  String? cwd,
  String? home,
]) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: cwd,
    environment: {'HOME': ?home},
  );
  if (result.exitCode != 0) {
    throw StateError('$executable ${args.join(' ')}: ${result.stderr}');
  }
}

/// The rate limiter the agents change (code.dart), committed in [hono] as
/// a fixed window, with its tests and exports: what the scenes put back.
Future<void> _commitRateLimiter(String hono, String home) async {
  void replace(String name, String from, String to) {
    final file = File(p.join(hono, name));
    final text = file.readAsStringSync();
    if (!text.contains(from)) throw StateError('$name: no "$from"');
    file.writeAsStringSync(text.replaceFirst(from, to));
  }

  for (final (path, text) in [
    (rateLimiterPath, rateLimiterFixedSource),
    (rateLimiterTestPath, rateLimiterFixedTestSource),
  ]) {
    File(p.join(hono, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }
  replace('package.json', packageJsonBefore, packageJsonAfter);
  replace('jsr.json', jsrJsonBefore, jsrJsonAfter);
  await _run('git', ['add', '.'], hono, home);
  await _run(
    'git',
    ['commit', '-qm', 'feat(rate-limiter): add a fixed-window rate limiter'],
    hono,
    home,
  );
}

/// `bun test`, as it prints for the rate limiter's tests: the projects have
/// no Bun.
final _bunScript =
    '''#!/bin/sh
g='\\033[32m'; d='\\033[2m'; b='\\033[1m'; r='\\033[0m'
printf "\${b}bun test\${r} \${d}v1.2.22 (6bafe260)\${r}\\n\\n"
printf "$rateLimiterTestPath:\\n"
for t in "lets requests under the limit through [0.41ms]" \\
  "answers 429 past the limit, with Retry-After [0.22ms]" \\
  "weights the previous window by how much of it is left [0.19ms]" \\
  "counts each client on its own [0.31ms]"; do
  printf "\${g}✓\${r} Rate Limiter Middleware \${d}>\${r} %s\\n" "\$t"
  sleep 0.12
done
printf "\\n \${g}4 pass\${r}\\n 0 fail\\n 9 expect() calls\\nRan 4 tests across 1 file. \${d}[38.00ms]\${r}\\n"
''';

// --- Running ----------------------------------------------------------------------

Future<int> _runApp(
  String app, {
  required String home,
  required String data,
  required String out,
  required String locale,
  required List<String> scenes,
  required bool video,
  required String log,
}) async {
  final sink = File(log).openWrite();
  final environment = {
    ..._launchEnvironment(app),
    'HOME': home,
    'SHELL': '/bin/zsh',
    'BAOCODE_SHOWCASE_HOME': home,
    'BAOCODE_SHOWCASE_DATA': data,
    'BAOCODE_SHOWCASE_OUT': out,
    'BAOCODE_SHOWCASE_LOCALE': locale,
    if (scenes.isNotEmpty) 'BAOCODE_SHOWCASE_SCENES': scenes.join(','),
    if (!video) 'BAOCODE_SHOWCASE_VIDEO': '0',
  };
  final process = await Process.start(app, const [], environment: environment);
  void line(String text) {
    sink.writeln(text);
    const tag = 'BAOCODE_SHOWCASE_LOG ';
    final at = text.indexOf(tag);
    if (at >= 0) print('[$locale] ${text.substring(at + tag.length)}');
  }

  final lines = [
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(line),
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(line),
  ];
  final code = await process.exitCode.timeout(
    const Duration(minutes: 45),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  await Future.wait(lines);
  await sink.close();
  return code;
}

/// The environment macOS gives the app as it is opened (its Info.plist's
/// LSEnvironment), which running its executable here does not.
Map<String, String> _launchEnvironment(String app) {
  final plist = File(app).parent.parent.uri.resolve('Info.plist').toFilePath();
  final result = Process.runSync('plutil', [
    '-extract',
    'LSEnvironment',
    'json',
    '-o',
    '-',
    plist,
  ]);
  if (result.exitCode != 0) return const {};
  return (jsonDecode(result.stdout as String) as Map).cast<String, String>();
}

/// The pictures as WebP, 1568 pixels wide (the page's 784, twice), the
/// bare windows as they were taken (their corners clear), and the videos
/// as they are, into [publish] if given.
Future<void> _convert(String from, String? publish) async {
  final dir = Directory(from);
  if (!dir.existsSync()) return;
  for (final file in dir.listSync().whereType<File>()) {
    final name = p.basenameWithoutExtension(file.path);
    switch (p.extension(file.path)) {
      case '.png':
        final webp = p.join(from, '$name.webp');
        await _run('cwebp', [
          '-quiet',
          '-q',
          '86',
          if (!name.endsWith('.window')) ...['-resize', '1568', '0'],
          file.path,
          '-o',
          webp,
        ]);
        if (publish != null) {
          Directory(publish).createSync(recursive: true);
          File(webp).copySync(p.join(publish, '$name.webp'));
        }
      case '.mp4':
        // Its poster: a frame from late on, the window busy.
        final probe = await Process.run('ffprobe', [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'csv=p=0',
          file.path,
        ]);
        final seconds = double.tryParse('${probe.stdout}'.trim()) ?? 0;
        final frame = p.join(Directory.systemTemp.path, 'showcase-$name.png');
        await _run('ffmpeg', [
          '-v',
          'error',
          '-y',
          '-ss',
          (seconds * .7).toStringAsFixed(2),
          '-i',
          file.path,
          '-frames:v',
          '1',
          frame,
        ]);
        final poster = p.join(from, '$name-poster.webp');
        await _run('cwebp', ['-quiet', '-q', '82', frame, '-o', poster]);
        File(frame).deleteSync();
        if (publish != null) {
          Directory(publish).createSync(recursive: true);
          file.copySync(p.join(publish, '$name.mp4'));
          File(poster).copySync(p.join(publish, '$name-poster.webp'));
        }
    }
  }
  // The home page's tiles: a part of a picture, closer.
  for (final MapEntry(key: name, value: (shot, crop)) in _tiles.entries) {
    final png = File(p.join(from, '$shot.png'));
    if (!png.existsSync()) continue;
    final webp = p.join(from, '$name.webp');
    final (x, y, w, h) = crop;
    await _run('cwebp', [
      '-quiet',
      '-q',
      '86',
      // The pictures are the window's at twice its size.
      '-crop',
      '${x * 2}',
      '${y * 2}',
      '${w * 2}',
      '${h * 2}',
      '-resize',
      '1200',
      '0',
      png.path,
      '-o',
      webp,
    ]);
    if (publish != null) {
      Directory(publish).createSync(recursive: true);
      File(webp).copySync(p.join(publish, '$name.webp'));
    }
  }
}

/// The home page's tiles: each a part of a picture, in the picture's
/// points (the window's, with the wallpaper around it): x, y, width,
/// height.
const _tiles = {
  'tile-review': ('review', (740, 330, 673, 432)),
  'tile-goal': ('goal', (494, 660, 760, 212)),
  'tile-composer': ('composer', (494, 660, 760, 212)),
  'tile-models': ('models', (482, 430, 762, 438)),
};
