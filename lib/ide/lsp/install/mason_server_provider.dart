import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../kernel/claude_code/claude_environment.dart';
import '../lsp_server_definition.dart';
import 'archive.dart';
import 'install_io.dart';
import 'mason_install_plan.dart';
import 'mason_platform.dart';
import 'mason_registry.dart';

/// Finds language servers on the login shell's PATH or among those it
/// installed, and installs mason-registry packages into
/// `<installRoot>/<package>/` (by default `DataDirectory.serversDir`).
///
/// Supported sources: GitHub release assets and generic downloads
/// (unpacked in Dart), npm, PyPI (a venv), Go and Cargo. Each install is
/// built in a staging folder and swapped in whole; a PyPI venv, which
/// cannot move, is built in place with the previous install kept aside
/// until it succeeds. Every network and process call goes through
/// [Downloader] and [CommandRunner].
class MasonServerProvider implements LspServerProvider {
  MasonServerProvider({
    required this.registry,
    required this.installRoot,
    Downloader? downloader,
    CommandRunner? runner,
    Future<Map<String, String>> Function()? environment,
    MasonPlatform? platform,
  }) : _downloader = downloader ?? HttpDownloader(),
       _runner = runner ?? const ProcessCommandRunner(),
       _environment = environment ?? ClaudeEnvironment.of,
       platform = platform ?? currentPlatform();

  static const folderName = 'servers';
  static const _staging = '.staging';
  static const _wrappers = 'mason-bin';

  final MasonRegistry registry;
  final String installRoot;
  final MasonPlatform platform;
  final Downloader _downloader;
  final CommandRunner _runner;
  final Future<Map<String, String>> Function() _environment;
  final Map<String, Future<void>> _installs = {};

  /// This machine, as mason names it.
  static MasonPlatform currentPlatform() {
    final (os, arch) = switch (Abi.current()) {
      Abi.macosArm64 => ('darwin', 'arm64'),
      Abi.macosX64 => ('darwin', 'x64'),
      Abi.linuxArm64 => ('linux', 'arm64'),
      Abi.linuxX64 => ('linux', 'x64'),
      Abi.linuxIA32 => ('linux', 'x86'),
      Abi.linuxArm => ('linux', 'arm'),
      Abi.windowsArm64 => ('win', 'arm64'),
      Abi.windowsIA32 => ('win', 'x86'),
      Abi.windowsX64 => ('win', 'x64'),
      final abi => (Platform.operatingSystem, abi.toString()),
    };
    String? libc;
    if (os == 'linux') {
      try {
        libc =
            Directory('/lib')
                .listSync()
                .any((entry) => p.basename(entry.path).startsWith('ld-musl-'))
            ? 'musl'
            : 'gnu';
      } on FileSystemException {
        libc = 'gnu';
      }
    }
    return MasonPlatform(os, arch, libc: libc);
  }

  String packageDirectory(String package) => p.join(installRoot, package);

  /// What is installed of [package]; null when it is not.
  Future<MasonInstallManifest?> installed(String package) async {
    final file = File(
      p.join(packageDirectory(package), MasonInstallManifest.fileName),
    );
    try {
      return MasonInstallManifest.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, Object?>,
      );
    } on PathNotFoundException {
      return null;
    } on Object {
      return null;
    }
  }

  /// The installed packages, by name.
  Future<List<String>> installedPackages() async {
    final root = Directory(installRoot);
    if (!await root.exists()) return const [];
    return [
      await for (final entity in root.list())
        if (entity is Directory && !p.basename(entity.path).startsWith('.'))
          p.basename(entity.path),
    ]..sort();
  }

  Future<void> uninstall(String package) async {
    final directory = Directory(packageDirectory(package));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// An absolute command if it exists; a bare one on the login shell's
  /// PATH, then among installed packages ([LspServerDefinition.masonPackage]
  /// first). Missing: the package that would install it, if it installs
  /// here, and a runtime that is not on PATH.
  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async {
    final command = server.command;
    if (p.isAbsolute(command) || command.contains('/')) {
      return await _isExecutable(command)
          ? LspServerFound(command)
          : const LspServerMissing();
    }
    final environment = await _environment();
    if (await which(command, environment) case final path?) {
      return LspServerFound(path);
    }
    final packages = [
      ?server.masonPackage,
      for (final package in await installedPackages())
        if (package != server.masonPackage) package,
    ];
    for (final package in packages) {
      final manifest = await installed(package);
      final relative = manifest?.bin[command];
      if (relative == null) continue;
      final path = p.join(packageDirectory(package), relative);
      if (await _isExecutable(path)) return LspServerFound(path);
    }
    final package =
        registry[server.masonPackage ?? ''] ?? registry.providing(command);
    if (package == null) return const LspServerMissing();
    final MasonInstallPlan plan;
    try {
      plan = MasonInstallPlan.of(package, platform);
    } on LspInstallException {
      return const LspServerMissing();
    }
    String? missing;
    for (final runtime in _runtimes(plan, installing: false)) {
      if (await which(runtime, environment) == null) {
        missing = runtime;
        break;
      }
    }
    return LspServerMissing(package: package.name, missingRuntime: missing);
  }

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) => _installs[package] ??= _install(package, onProgress ?? (_) {})
      .whenComplete(() {
        // Not `=>`: returning the removed future would wait on itself.
        _installs.remove(package);
      });

  Future<void> _install(String name, void Function(String) progress) async {
    final package = registry[name];
    if (package == null) {
      throw LspInstallException('Unknown language server package "$name"');
    }
    final plan = MasonInstallPlan.of(package, platform);
    final environment = await _environment();
    final tools = <String, String>{};
    for (final runtime in _runtimes(plan, installing: true)) {
      final path = await which(runtime, environment);
      if (path == null) {
        throw LspInstallException(
          'Installing $name needs $runtime, which is not on PATH',
        );
      }
      tools[runtime] = path;
    }
    for (final runtime in _runtimes(plan, installing: false)) {
      if (!tools.containsKey(runtime) &&
          await which(runtime, environment) == null) {
        progress('Note: $name runs with $runtime, which is not on PATH');
      }
    }

    final target = packageDirectory(name);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stagingRoot = p.join(installRoot, _staging);
    final inPlace = plan.kind == MasonSourceKind.pypi;
    final work = inPlace ? target : p.join(stagingRoot, '$name-$stamp');
    final backup = p.join(stagingRoot, '$name-$stamp.previous');
    await Directory(stagingRoot).create(recursive: true);
    var movedAside = false;
    try {
      if (inPlace && await Directory(target).exists()) {
        await Directory(target).rename(backup);
        movedAside = true;
      }
      await Directory(work).create(recursive: true);
      progress('Installing $name ${plan.version}');
      await _fetch(plan, work, tools, environment, progress);
      final bins = await _link(plan, work);
      await File(p.join(work, MasonInstallManifest.fileName)).writeAsString(
        jsonEncode(
          MasonInstallManifest(
            package: name,
            version: plan.version,
            source: plan.purl.toString(),
            bin: bins,
          ).toJson(),
        ),
      );
      if (!inPlace) {
        if (await Directory(target).exists()) {
          await Directory(target).rename(backup);
          movedAside = true;
        }
        await Directory(work).rename(target);
      }
      if (movedAside) await Directory(backup).delete(recursive: true);
      progress('Installed $name ${plan.version}');
    } on Object catch (error) {
      if (await Directory(work).exists()) {
        await Directory(work).delete(recursive: true);
      }
      if (movedAside && await Directory(backup).exists()) {
        if (await Directory(target).exists()) {
          await Directory(target).delete(recursive: true);
        }
        await Directory(backup).rename(target);
      }
      if (error is LspInstallException) rethrow;
      throw LspInstallException('Installing $name failed', detail: '$error');
    }
  }

  /// Runtimes to install with ([installing]) or to run the bins with.
  List<String> _runtimes(MasonInstallPlan plan, {required bool installing}) {
    String named(String runtime) =>
        platform.isWindows && runtime == 'python3' ? 'python' : runtime;
    if (installing) {
      return [
        if (plan.kind == MasonSourceKind.npm) 'node',
        if (plan.kind.runtime case final runtime?) named(runtime),
      ];
    }
    return {
      if (plan.kind == MasonSourceKind.npm) 'node',
      for (final runtime in plan.runtimes) named(runtime),
    }.toList();
  }

  Future<void> _fetch(
    MasonInstallPlan plan,
    String directory,
    Map<String, String> tools,
    Map<String, String> environment,
    void Function(String) progress,
  ) async {
    final purl = plan.purl;
    switch (plan.kind) {
      case MasonSourceKind.github || MasonSourceKind.generic:
        final executables = <String>[];
        for (final download in plan.downloads) {
          final path = p.join(directory, download.path);
          await Directory(p.dirname(path)).create(recursive: true);
          final label = p.basename(download.path);
          var reported = -1;
          progress('Downloading $label');
          try {
            await _downloader.download(
              download.url,
              path,
              onProgress: (received, total) {
                if (total == null || total <= 0) return;
                final tenth = received * 10 ~/ total;
                if (tenth != reported) {
                  reported = tenth;
                  progress('Downloading $label (${tenth * 10}%)');
                }
              },
            );
          } on Object catch (error) {
            throw LspInstallException(
              'Could not download $label',
              detail: '${download.url}\n$error',
            );
          }
          executables.addAll(await unpackDownload(path, runner: _runner));
        }
        await makeExecutable(
          executables,
          runner: _runner,
          windows: platform.isWindows,
        );
      case MasonSourceKind.npm:
        await File(p.join(directory, 'package.json')).writeAsString(
          jsonEncode({
            'name':
                'monad-${plan.package.name.replaceAll(RegExp(r'[^a-z0-9-]'), '-')}',
            'version': '0.0.0',
            'private': true,
          }),
        );
        await _command(
          'npm install',
          tools['npm']!,
          [
            'install',
            '--prefix',
            directory,
            '--no-audit',
            '--no-fund',
            '--loglevel=error',
            '${purl.fullName}@${plan.version}',
            ...plan.extraPackages,
          ],
          directory,
          environment,
        );
      case MasonSourceKind.pypi:
        final python = tools[platform.isWindows ? 'python' : 'python3']!;
        final venv = p.join(directory, 'venv');
        await _command(
          'python -m venv',
          python,
          ['-m', 'venv', venv],
          directory,
          environment,
        );
        final extra = purl.qualifiers['extra'];
        await _command(
          'pip install',
          platform.isWindows
              ? p.join(venv, 'Scripts', 'python.exe')
              : p.join(venv, 'bin', 'python'),
          [
            '-m',
            'pip',
            'install',
            '--disable-pip-version-check',
            '--no-input',
            '-U',
            '${purl.name}${extra == null ? '' : '[$extra]'}==${plan.version}',
            ...plan.extraPackages,
          ],
          directory,
          environment,
        );
      case MasonSourceKind.golang:
        final module = purl.subpath == null
            ? purl.fullName
            : '${purl.fullName}/${purl.subpath}';
        for (final target in [
          '$module@${plan.version}',
          ...plan.extraPackages,
        ]) {
          await _command(
            'go install',
            tools['go']!,
            ['install', target],
            directory,
            {...environment, 'GOBIN': directory},
          );
        }
      case MasonSourceKind.cargo:
        final repository = purl.qualifiers['repository_url'];
        final features = purl.qualifiers['features'];
        await _command(
          'cargo install',
          tools['cargo']!,
          [
            'install',
            '--root',
            directory,
            if (repository != null) ...[
              '--git',
              repository,
              purl.qualifiers['rev'] == 'true' ? '--rev' : '--tag',
              plan.version,
              purl.name,
            ] else ...[
              purl.name,
              '--version',
              plan.version,
            ],
            if (features != null) ...['--features', features],
            if (purl.qualifiers['locked'] == 'true') '--locked',
          ],
          directory,
          environment,
        );
    }
  }

  Future<void> _command(
    String what,
    String executable,
    List<String> arguments,
    String directory,
    Map<String, String> environment,
  ) async {
    final result = await _runner.run(
      executable,
      arguments,
      workingDirectory: directory,
      environment: environment,
    );
    if (result.exitCode != 0) {
      final output = '${result.stderr}\n${result.stdout}'.trim();
      throw LspInstallException(
        '$what failed (exit ${result.exitCode})',
        detail: output.length > 4000
            ? output.substring(output.length - 4000)
            : output,
      );
    }
  }

  /// Checks each bin exists, makes the plain ones executable and writes
  /// wrappers for the ones a runtime runs; returns name → relative path.
  Future<Map<String, String>> _link(
    MasonInstallPlan plan,
    String directory,
  ) async {
    final bins = <String, String>{};
    final executables = <String>[];
    for (final MapEntry(key: name, value: bin) in plan.bins.entries) {
      if (bin.path.isNotEmpty) {
        final path = p.join(directory, bin.path);
        if (!await File(path).exists()) {
          throw LspInstallException(
            '${plan.package.name} installed no "$name"',
            detail: 'Expected ${bin.path}',
          );
        }
        if (bin.kind == MasonBinKind.executable) executables.add(path);
      }
      if (bin.kind != MasonBinKind.wrapped) {
        bins[name] = bin.path;
        continue;
      }
      final wrapper = p.join(
        _wrappers,
        platform.isWindows ? '$name.cmd' : name,
      );
      await Directory(p.join(directory, _wrappers)).create(recursive: true);
      await File(p.join(directory, wrapper)).writeAsString(_wrapper(bin));
      executables.add(p.join(directory, wrapper));
      bins[name] = wrapper;
    }
    await makeExecutable(
      executables,
      runner: _runner,
      windows: platform.isWindows,
    );
    return bins;
  }

  /// A script that runs [bin] with its runtime, finding the package folder
  /// from its own location so the install can move.
  String _wrapper(MasonBin bin) {
    final runtime = bin.runtime!;
    final args = bin.runtimeArgs ?? const [];
    if (platform.isWindows) {
      String win(String relative) =>
          '"%~dp0..\\${relative.replaceAll('/', '\\')}"';
      return [
        '@echo off',
        [
          runtime.startsWith('./') ? win(runtime.substring(2)) : runtime,
          ...args,
          if (bin.path.isNotEmpty) win(bin.path),
          '%*',
        ].join(' '),
        '',
      ].join('\r\n');
    }
    String sh(String relative) => '"\$dir/$relative"';
    return [
      '#!/bin/sh',
      r'dir="$(cd "$(dirname "$0")/.." && pwd)"',
      [
        'exec',
        runtime.startsWith('./') ? sh(runtime.substring(2)) : runtime,
        ...args,
        if (bin.path.isNotEmpty) sh(bin.path),
        r'"$@"',
      ].join(' '),
      '',
    ].join('\n');
  }

  /// [command] on [environment]'s PATH (with `PATHEXT` on Windows).
  Future<String?> which(String command, Map<String, String> environment) async {
    final path = environment['PATH'] ?? environment['Path'] ?? '';
    final extensions = platform.isWindows
        ? [
            '',
            ...(environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD')
                .split(';')
                .where((extension) => extension.isNotEmpty),
          ]
        : const [''];
    for (final directory in path.split(platform.isWindows ? ';' : ':')) {
      if (directory.isEmpty) continue;
      for (final extension in extensions) {
        final candidate = p.join(directory, '$command$extension');
        if (await _isExecutable(candidate)) return candidate;
      }
    }
    return null;
  }

  Future<bool> _isExecutable(String path) async {
    final stat = await FileStat.stat(path);
    if (stat.type != FileSystemEntityType.file) return false;
    return platform.isWindows || stat.mode & 0x49 != 0;
  }
}

/// What an install left in its package folder (`monad-install.json`).
class MasonInstallManifest {
  const MasonInstallManifest({
    required this.package,
    required this.version,
    required this.source,
    required this.bin,
  });

  factory MasonInstallManifest.fromJson(Map<String, Object?> json) =>
      MasonInstallManifest(
        package: json['package'] as String,
        version: json['version'] as String,
        source: json['source'] as String? ?? '',
        bin: (json['bin'] as Map).cast<String, String>(),
      );

  static const fileName = 'monad-install.json';

  final String package;
  final String version;

  /// The package URL installed.
  final String source;

  /// Executable name → path relative to the package folder.
  final Map<String, String> bin;

  Map<String, Object?> toJson() => {
    'package': package,
    'version': version,
    'source': source,
    'bin': bin,
  };
}
