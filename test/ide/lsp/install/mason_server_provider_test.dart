import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/lsp/install/archive.dart';
import 'package:monad/ide/lsp/install/install_io.dart';
import 'package:monad/ide/lsp/install/mason_platform.dart';
import 'package:monad/ide/lsp/install/mason_registry.dart';
import 'package:monad/ide/lsp/install/mason_server_provider.dart';
import 'package:monad/ide/lsp/lsp_server_definition.dart';
import 'package:path/path.dart' as p;

const fixtures = 'test/fixtures/lsp/mason';
const mac = MasonPlatform('darwin', 'arm64');

/// Serves fixture files for URLs by their last path segment; never the
/// network.
class FakeDownloader implements Downloader {
  FakeDownloader(this.files);

  final Map<String, String> files;
  final requested = <Uri>[];

  @override
  Future<void> download(
    Uri url,
    String destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    requested.add(url);
    final fixture = files[url.pathSegments.last];
    if (fixture == null) throw HttpException('HTTP 404', uri: url);
    final bytes = await File(p.join(fixtures, fixture)).readAsBytes();
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    onProgress?.call(bytes.length, bytes.length);
    await File(destination).writeAsBytes(bytes);
  }
}

/// Records commands and acts out what each installer would leave behind;
/// `chmod` really runs (a local file mode change).
class FakeRunner implements CommandRunner {
  FakeRunner({this.exitCode = 0});

  final int exitCode;
  final calls = <(String, List<String>, Map<String, String>?)>[];

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (executable == 'chmod') {
      final result = await Process.run('chmod', arguments);
      return CommandResult(result.exitCode, stderr: '${result.stderr}');
    }
    calls.add((p.basename(executable), arguments, environment));
    if (exitCode != 0) {
      return CommandResult(
        exitCode,
        stderr: 'boom from ${p.basename(executable)}',
      );
    }
    Future<void> touch(String path) async {
      await File(path).create(recursive: true);
      await File(path).writeAsString('#!/bin/sh\n');
      await Process.run('chmod', ['+x', path]);
    }

    switch (p.basename(executable)) {
      case 'npm':
        final prefix = arguments[arguments.indexOf('--prefix') + 1];
        await touch(p.join(prefix, 'node_modules', '.bin', 'fake-npm-ls'));
      case 'python3' when arguments.contains('venv'):
        await touch(p.join(arguments.last, 'bin', 'python'));
      case 'python':
        await touch(p.join(p.dirname(executable), 'fake-py-ls'));
      case 'go':
        await touch(p.join(environment!['GOBIN']!, 'fake-go-ls'));
      case 'cargo':
        final root = arguments[arguments.indexOf('--root') + 1];
        await touch(p.join(root, 'bin', 'fake-cargo-ls'));
    }
    return const CommandResult(0);
  }
}

final registry = MasonRegistry.fromJson({
  'packages': [
    {
      'name': 'fake-zip',
      'categories': ['LSP'],
      'source': {
        'id': 'pkg:github/example/fake-ls@v1.0.0',
        'asset': [
          {
            'target': 'darwin_arm64',
            'file': 'fake-ls-{{ version | strip_prefix "v" }}.zip',
            'bin': 'fake-ls/bin/fake-ls',
          },
        ],
      },
      'bin': {'fake-ls': '{{source.asset.bin}}'},
    },
    {
      'name': 'fake-tar',
      'source': {
        'id': 'pkg:github/example/fake-ls@1.0',
        'asset': {
          'file': 'fake-ls.tar.gz:libexec/',
          'bin': 'exec:libexec/fake-ls-1.0/bin/fake-ls',
        },
      },
      'bin': {
        'fake-tar-ls': '{{source.asset.bin}}',
        'fake-tar-node': 'node:libexec/fake-ls-1.0/bin/fake-ls',
      },
    },
    {
      'name': 'fake-gz',
      'source': {
        'id': 'pkg:github/example/fake-ls@1.0',
        'asset': {'target': 'unix', 'file': 'fake-ls.gz'},
      },
      'bin': {'fake-gz-ls': 'fake-ls'},
    },
    {
      'name': 'fake-npm',
      'categories': ['LSP'],
      'source': {
        'id': 'pkg:npm/%40example/fake-npm-ls@2.0.0',
        'extra_packages': ['typescript@5.9.3'],
      },
      'bin': {'fake-npm-ls': 'npm:fake-npm-ls'},
    },
    {
      'name': 'fake-pypi',
      'source': {'id': 'pkg:pypi/fake-py-ls@0.5?extra=all'},
      'bin': {'fake-py-ls': 'pypi:fake-py-ls'},
    },
    {
      'name': 'fake-go',
      'source': {
        'id': 'pkg:golang/example.com/tools/fake@v0.1.0#cmd/fake-go-ls',
      },
      'bin': {'fake-go-ls': 'golang:fake-go-ls'},
    },
    {
      'name': 'fake-cargo',
      'source': {
        'id': 'pkg:cargo/fake-cargo-ls@1.2.3?repository_url=https://github.com/example/fake&features=lsp&locked=true',
      },
      'bin': {'fake-cargo-ls': 'cargo:fake-cargo-ls'},
    },
    {
      'name': 'fake-opam',
      'source': {'id': 'pkg:opam/fake-opam-ls@1'},
      'bin': {'fake-opam-ls': 'opam:fake-opam-ls'},
    },
  ],
});

void main() {
  late Directory temp;
  late String root;
  late String toolsDir;
  late Map<String, String> environment;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mason_provider_test');
    root = p.join(temp.path, 'servers');
    toolsDir = p.join(temp.path, 'tools');
    await Directory(toolsDir).create();
    environment = {'PATH': toolsDir, 'HOME': temp.path};
  });

  tearDown(() => temp.delete(recursive: true));

  Future<void> tool(String name) async {
    final path = p.join(toolsDir, name);
    await File(path).writeAsString('#!/bin/sh\n');
    await Process.run('chmod', ['+x', path]);
  }

  MasonServerProvider provider({
    FakeDownloader? downloader,
    FakeRunner? runner,
  }) => MasonServerProvider(
    registry: registry,
    installRoot: root,
    downloader:
        downloader ??
        FakeDownloader({
          'fake-ls-1.0.0.zip': 'fake-ls.zip',
          'fake-ls.tar.gz': 'fake-ls.tar.gz',
          'fake-ls.gz': 'fake-ls.gz',
        }),
    runner: runner ?? FakeRunner(),
    environment: () async => environment,
    platform: mac,
  );

  LspServerDefinition server(String command, [String? package]) =>
      LspServerDefinition(id: command, command: command, masonPackage: package);

  group('archives', () {
    Future<List<String>> unpack(String fixture) async {
      final file = p.join(temp.path, fixture);
      await File(p.join(fixtures, fixture)).copy(file);
      final executables = await unpackDownload(file, runner: FakeRunner());
      expect(File(file).existsSync(), isFalse, reason: 'archive removed');
      return [for (final e in executables) p.relative(e, from: temp.path)];
    }

    test('zip: files, modes, directories and symlinks', () async {
      expect(await unpack('fake-ls.zip'), ['fake-ls/bin/fake-ls']);
      final dir = p.join(temp.path, 'fake-ls');
      expect(
        File(p.join(dir, 'bin', 'fake-ls')).readAsStringSync(),
        contains('echo fake-ls'),
      );
      expect(File(p.join(dir, 'share', 'readme.txt')).lengthSync(), 300);
      expect(Link(p.join(dir, 'bin', 'fake-link')).targetSync(), 'fake-ls');
    });

    test('tar.gz: GNU long names, symlinks and hard links', () async {
      expect(await unpack('fake-ls.tar.gz'), [
        'fake-ls-1.0/bin/fake-ls',
        'fake-ls-1.0/bin/fake-hard',
      ]);
      final dir = p.join(temp.path, 'fake-ls-1.0');
      expect(
        File(
          p.joinAll([
            dir,
            ...List.filled(6, 'long-directory-name'),
            'deep.txt',
          ]),
        ).readAsStringSync(),
        'deep',
      );
      expect(Link(p.join(dir, 'bin', 'fake-link')).targetSync(), 'fake-ls');
      expect(
        File(p.join(dir, 'bin', 'fake-hard')).readAsStringSync(),
        contains('echo fake-ls'),
      );
    });

    test('pax tar and single gzip files', () async {
      await unpack('fake-ls-pax.tar');
      expect(
        File(
          p.joinAll([
            temp.path,
            'fake-ls-1.0',
            ...List.filled(6, 'long-directory-name'),
            'deep.txt',
          ]),
        ).existsSync(),
        isTrue,
      );
      await unpack('fake-ls.gz');
      expect(
        File(p.join(temp.path, 'fake-ls')).readAsStringSync(),
        contains('echo fake-ls'),
      );
    });

    test('entries escaping the folder are refused', () async {
      await expectLater(
        unpack('escape.zip'),
        throwsA(isA<LspInstallException>()),
      );
      expect(
        File(p.join(p.dirname(temp.path), 'escaped.txt')).existsSync(),
        isFalse,
      );
    });

    test('other files are left as they are', () async {
      final file = p.join(temp.path, 'server.jar');
      await File(file).writeAsString('jar');
      expect(await unpackDownload(file, runner: FakeRunner()), isEmpty);
      expect(File(file).existsSync(), isTrue);
    });
  });

  group('install', () {
    test('GitHub zip asset: unpacked, executable, manifest, located', () async {
      final downloader = FakeDownloader({'fake-ls-1.0.0.zip': 'fake-ls.zip'});
      final messages = <String>[];
      final mason = provider(downloader: downloader);
      expect(
        await mason.locate(server('fake-ls', 'fake-zip')),
        isA<LspServerMissing>()
            .having((m) => m.package, 'package', 'fake-zip')
            .having((m) => m.missingRuntime, 'runtime', isNull),
      );
      await mason.install('fake-zip', onProgress: messages.add);
      expect(
        downloader.requested.single.toString(),
        'https://github.com/example/fake-ls/releases/download/v1.0.0/fake-ls-1.0.0.zip',
      );
      expect(messages, contains('Downloading fake-ls-1.0.0.zip (100%)'));
      expect(messages.last, 'Installed fake-zip v1.0.0');
      final manifest = (await mason.installed('fake-zip'))!;
      expect(manifest.version, 'v1.0.0');
      expect(manifest.source, 'pkg:github/example/fake-ls@v1.0.0');
      expect(manifest.bin, {'fake-ls': 'fake-ls/bin/fake-ls'});
      final location = await mason.locate(server('fake-ls', 'fake-zip'));
      expect(
        (location as LspServerFound).executable,
        p.join(root, 'fake-zip', 'fake-ls', 'bin', 'fake-ls'),
      );
      // Found among installed packages even when the definition names none.
      expect(await mason.locate(server('fake-ls')), isA<LspServerFound>());
      expect(Directory(p.join(root, '.staging')).listSync(), isEmpty);
      expect(await mason.installedPackages(), ['fake-zip']);
    });

    test('tar.gz into a destination folder, with a node wrapper', () async {
      final mason = provider();
      await mason.install('fake-tar');
      final dir = p.join(root, 'fake-tar');
      final manifest = (await mason.installed('fake-tar'))!;
      expect(manifest.bin, {
        'fake-tar-ls': 'libexec/fake-ls-1.0/bin/fake-ls',
        'fake-tar-node': 'mason-bin/fake-tar-node',
      });
      final wrapper = File(p.join(dir, 'mason-bin', 'fake-tar-node'));
      expect(
        wrapper.readAsStringSync(),
        contains(r'exec node "$dir/libexec/fake-ls-1.0/bin/fake-ls" "$@"'),
      );
      expect(wrapper.statSync().mode & 0x40, isNot(0));
      final location = await mason.locate(server('fake-tar-node', 'fake-tar'));
      expect((location as LspServerFound).executable, wrapper.path);
    });

    test('a raw gzip binary is unpacked and made executable', () async {
      final mason = provider();
      await mason.install('fake-gz');
      final bin = File(p.join(root, 'fake-gz', 'fake-ls'));
      expect(bin.statSync().mode & 0x40, isNot(0));
      expect(
        await mason.locate(server('fake-gz-ls', 'fake-gz')),
        isA<LspServerFound>(),
      );
    });

    test('npm: needs node and npm, installs with extras', () async {
      final runner = FakeRunner();
      final mason = provider(runner: runner);
      expect(
        await mason.locate(server('fake-npm-ls', 'fake-npm')),
        isA<LspServerMissing>()
            .having((m) => m.package, 'package', 'fake-npm')
            .having((m) => m.missingRuntime, 'runtime', 'node'),
      );
      await expectLater(
        mason.install('fake-npm'),
        throwsA(
          isA<LspInstallException>().having(
            (e) => e.message,
            'message',
            'Installing fake-npm needs node, which is not on PATH',
          ),
        ),
      );
      expect(Directory(p.join(root, 'fake-npm')).existsSync(), isFalse);
      await tool('node');
      expect(
        (await mason.locate(
          server('fake-npm-ls', 'fake-npm'),
        ) as LspServerMissing).missingRuntime,
        'npm',
      );
      await tool('npm');
      await mason.install('fake-npm');
      final (npm, arguments, env) = runner.calls.single;
      expect(npm, 'npm');
      expect(arguments, [
        'install',
        '--prefix',
        p.join(root, '.staging', arguments[2].split(p.separator).last),
        '--no-audit',
        '--no-fund',
        '--loglevel=error',
        '@example/fake-npm-ls@2.0.0',
        'typescript@5.9.3',
      ]);
      expect(env?['PATH'], toolsDir);
      final dir = p.join(root, 'fake-npm');
      expect(
        jsonDecode(File(p.join(dir, 'package.json')).readAsStringSync()),
        containsPair('private', true),
      );
      expect(
        (await mason.locate(
          server('fake-npm-ls', 'fake-npm'),
        ) as LspServerFound).executable,
        p.join(dir, 'node_modules', '.bin', 'fake-npm-ls'),
      );
    });

    test('pypi: a venv in place, with the extra', () async {
      await tool('python3');
      final runner = FakeRunner();
      final mason = provider(runner: runner);
      await mason.install('fake-pypi');
      final dir = p.join(root, 'fake-pypi');
      expect(runner.calls[0].$2, ['-m', 'venv', p.join(dir, 'venv')]);
      expect(runner.calls[1].$1, 'python');
      expect(runner.calls[1].$2, containsAllInOrder(['-m', 'pip', 'install']));
      expect(runner.calls[1].$2.last, 'fake-py-ls[all]==0.5');
      expect(
        (await mason.locate(
          server('fake-py-ls', 'fake-pypi'),
        ) as LspServerFound).executable,
        p.join(dir, 'venv', 'bin', 'fake-py-ls'),
      );
    });

    test('go: GOBIN is the package folder, subpath kept', () async {
      await tool('go');
      final runner = FakeRunner();
      final mason = provider(runner: runner);
      await mason.install('fake-go');
      final (_, arguments, env) = runner.calls.single;
      expect(arguments, [
        'install',
        'example.com/tools/fake/cmd/fake-go-ls@v0.1.0',
      ]);
      expect(env?['GOBIN'], startsWith(p.join(root, '.staging')));
      expect(
        await mason.locate(server('fake-go-ls', 'fake-go')),
        isA<LspServerFound>(),
      );
    });

    test('cargo: --root, git source, features and --locked', () async {
      await tool('cargo');
      final runner = FakeRunner();
      final mason = provider(runner: runner);
      await mason.install('fake-cargo');
      final arguments = runner.calls.single.$2;
      expect(arguments.sublist(3), [
        '--git',
        'https://github.com/example/fake',
        '--tag',
        '1.2.3',
        'fake-cargo-ls',
        '--features',
        'lsp',
        '--locked',
      ]);
      expect(
        (await mason.locate(
          server('fake-cargo-ls', 'fake-cargo'),
        ) as LspServerFound).executable,
        p.join(root, 'fake-cargo', 'bin', 'fake-cargo-ls'),
      );
    });

    test('a failed reinstall keeps the working install', () async {
      await tool('go');
      await provider().install('fake-go');
      final failing = provider(runner: FakeRunner(exitCode: 2));
      await expectLater(
        failing.install('fake-go'),
        throwsA(
          isA<LspInstallException>()
              .having((e) => e.message, 'message', 'go install failed (exit 2)')
              .having((e) => e.detail, 'detail', contains('boom')),
        ),
      );
      expect(
        await failing.locate(server('fake-go-ls', 'fake-go')),
        isA<LspServerFound>(),
      );
      expect(Directory(p.join(root, '.staging')).listSync(), isEmpty);

      await tool('python3');
      await provider().install('fake-pypi');
      await expectLater(
        failing.install('fake-pypi'),
        throwsA(isA<LspInstallException>()),
      );
      expect(
        await failing.locate(server('fake-py-ls', 'fake-pypi')),
        isA<LspServerFound>(),
      );
    });

    test('download failures and unknown packages throw', () async {
      final mason = provider(downloader: FakeDownloader({}));
      await expectLater(
        mason.install('fake-zip'),
        throwsA(
          isA<LspInstallException>().having(
            (e) => e.message,
            'message',
            'Could not download fake-ls-1.0.0.zip',
          ),
        ),
      );
      expect(Directory(p.join(root, 'fake-zip')).existsSync(), isFalse);
      await expectLater(
        mason.install('nope'),
        throwsA(isA<LspInstallException>()),
      );
      await expectLater(
        mason.install('fake-opam'),
        throwsA(isA<LspInstallException>()),
      );
    });

    test('concurrent installs of one package share the work', () async {
      final downloader = FakeDownloader({'fake-ls-1.0.0.zip': 'fake-ls.zip'});
      final mason = provider(downloader: downloader);
      await Future.wait([mason.install('fake-zip'), mason.install('fake-zip')]);
      expect(downloader.requested, hasLength(1));
    });
  });

  group('locate', () {
    test('PATH first, then installed servers', () async {
      final mason = provider();
      await mason.install('fake-zip');
      await tool('fake-ls');
      expect(
        (await mason.locate(
          server('fake-ls', 'fake-zip'),
        ) as LspServerFound).executable,
        p.join(toolsDir, 'fake-ls'),
      );
    });

    test('absolute commands must exist and be executable', () async {
      final mason = provider();
      await tool('abs-ls');
      final path = p.join(toolsDir, 'abs-ls');
      expect(
        (await mason.locate(server(path)) as LspServerFound).executable,
        path,
      );
      await File(p.join(toolsDir, 'plain')).writeAsString('');
      expect(
        await mason.locate(server(p.join(toolsDir, 'plain'))),
        isA<LspServerMissing>().having((m) => m.package, 'package', isNull),
      );
    });

    test(
      'suggests a package by command; none when it cannot install',
      () async {
        final mason = provider();
        expect(
          (await mason.locate(
            server('fake-npm-ls'),
          ) as LspServerMissing).package,
          'fake-npm',
        );
        final opam = await mason.locate(server('fake-opam-ls', 'fake-opam'));
        expect((opam as LspServerMissing).package, isNull);
        expect(
          (await mason.locate(
            server('unknown-ls'),
          ) as LspServerMissing).package,
          isNull,
        );
      },
    );

    test('uninstall removes the package', () async {
      final mason = provider();
      await mason.install('fake-gz');
      await mason.uninstall('fake-gz');
      expect(await mason.installed('fake-gz'), isNull);
      expect(
        await mason.locate(server('fake-gz-ls', 'fake-gz')),
        isA<LspServerMissing>(),
      );
    });
  });
}
