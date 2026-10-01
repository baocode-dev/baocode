import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/install/mason_install_plan.dart';
import 'package:baocode/ide/lsp/install/mason_platform.dart';
import 'package:baocode/ide/lsp/install/mason_purl.dart';
import 'package:baocode/ide/lsp/install/mason_registry.dart';
import 'package:baocode/ide/lsp/install/mason_template.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';

const macArm = MasonPlatform('darwin', 'arm64');
const macIntel = MasonPlatform('darwin', 'x64');
const linuxGnu = MasonPlatform('linux', 'x64', libc: 'gnu');
const linuxMusl = MasonPlatform('linux', 'arm64', libc: 'musl');
const windows = MasonPlatform('win', 'x64');
const windowsArm = MasonPlatform('win', 'arm64');

MasonPackage package(Map<String, Object?> json) =>
    MasonPackage.fromJson({'name': 'pkg', ...json});

void main() {
  group('package URLs', () {
    test('parse the source types mason uses', () {
      final github = MasonPurl.parse(
        'pkg:github/rust-lang/rust-analyzer@2026-09-28',
      );
      expect(github.type, 'github');
      expect(github.namespace, 'rust-lang');
      expect(github.name, 'rust-analyzer');
      expect(github.fullName, 'rust-lang/rust-analyzer');
      expect(github.version, '2026-09-28');

      final npm = MasonPurl.parse('pkg:npm/%40vue/language-server@3.1.0');
      expect(npm.namespace, '@vue');
      expect(npm.fullName, '@vue/language-server');
      expect(npm.version, '3.1.0');

      final pypi = MasonPurl.parse(
        'pkg:pypi/python-lsp-server@1.13.1?extra=all',
      );
      expect(pypi.fullName, 'python-lsp-server');
      expect(pypi.qualifiers, {'extra': 'all'});

      final golang = MasonPurl.parse(
        'pkg:golang/github.com/googleapis/api-linter/v2@v2.4.0#cmd/api-linter',
      );
      expect(golang.fullName, 'github.com/googleapis/api-linter/v2');
      expect(golang.subpath, 'cmd/api-linter');
      expect(golang.version, 'v2.4.0');

      final cargo = MasonPurl.parse(
        'pkg:cargo/cqlls@4.1.0?repository_url=https://github.com/a/b&rev=true',
      );
      expect(cargo.name, 'cqlls');
      expect(cargo.qualifiers['repository_url'], 'https://github.com/a/b');
      expect(cargo.qualifiers['rev'], 'true');

      expect(MasonPurl.parse('pkg:npm/pyright').version, isNull);
      expect(
        MasonPurl.parse('pkg:npm/%40a/b@1?x=y#p').toString(),
        'pkg:npm/@a/b@1?x=y#p',
      );
    });

    test('reject what is not one', () {
      expect(() => MasonPurl.parse('npm/pyright@1'), throwsFormatException);
      expect(() => MasonPurl.parse('pkg:npm'), throwsFormatException);
      expect(() => MasonPurl.parse('pkg:npm/a@1?bad'), throwsFormatException);
    });
  });

  group('platform targets', () {
    test('prefer exact targets, then fallbacks', () {
      expect(macArm.targets, ['darwin_arm64', 'darwin', 'unix']);
      expect(macArm.fallbackTargets, ['darwin_x64']);
      expect(linuxGnu.targets, ['linux_x64_gnu', 'linux_x64', 'linux', 'unix']);
      expect(linuxGnu.fallbackTargets, ['linux_x64_musl']);
      expect(linuxMusl.targets.first, 'linux_arm64_musl');
      expect(linuxMusl.fallbackTargets, isEmpty);
      expect(windows.targets, ['win_x64', 'win']);
      expect(windowsArm.fallbackTargets, ['win_x64']);
    });

    test('select the most specific fitting asset', () {
      final assets = [
        {'target': 'linux_x64', 'file': 'generic'},
        {'target': 'linux_x64_gnu', 'file': 'gnu'},
        {
          'target': ['darwin_x64', 'darwin_arm64'],
          'file': 'mac',
        },
        {'target': 'win_x64', 'file': 'win'},
        {'target': 'linux_arm64_musl', 'file': 'musl-arm'},
      ];
      expect(linuxGnu.select(assets)?['file'], 'gnu');
      expect(macArm.select(assets)?['file'], 'mac');
      expect(windowsArm.select(assets)?['file'], 'win');
      expect(linuxMusl.select(assets)?['file'], 'musl-arm');
      expect(const MasonPlatform('win', 'x86').select(assets), isNull);
      // A glibc machine may run a static musl build; Apple silicon an x64 one.
      expect(
        linuxGnu.select([
          {'target': 'linux_x64_musl', 'file': 'musl'},
        ])?['file'],
        'musl',
      );
      expect(
        macArm.select([
          {'target': 'darwin_x64', 'file': 'x64'},
        ])?['file'],
        'x64',
      );
      expect(
        macIntel.select([
          {'target': 'darwin_arm64', 'file': 'arm'},
        ]),
        isNull,
      );
      expect(macArm.select({'file': 'any'})?['file'], 'any');
      expect(
        macArm.select([
          {'target': 'unix', 'file': 'unix'},
        ])?['file'],
        'unix',
      );
    });
  });

  group('templates', () {
    String expand(String template, [MasonPlatform platform = macArm]) =>
        expandMasonTemplate(template, {
          'version': 'v1.2.3',
          'source': {
            'asset': {
              'bin': {'lsp': 'server.sh'},
              'file': 'x.zip',
            },
          },
        }, platform);

    test('expand values, filters and platform conditions', () {
      expect(expand('a-{{version}}-b'), 'a-v1.2.3-b');
      expect(expand('a-{{ version | strip_prefix "v" }}.tgz'), 'a-1.2.3.tgz');
      expect(expand("{{ version | strip_suffix '.3' }}"), 'v1.2');
      expect(expand('{{source.asset.bin.lsp}}'), 'server.sh');
      expect(
        expand('bin/x{{ take_if_not(is_platform("win"), ".py") }}'),
        'bin/x.py',
      );
      expect(
        expand('bin/x{{ take_if_not(is_platform("win"), ".py") }}', windows),
        'bin/x',
      );
      expect(expand("{{ 'yq.1' | take_if_not(is_platform('win')) }}"), 'yq.1');
      expect(expand("{{ '.exe' | take_if(is_platform('win')) }}"), '');
      expect(expand('no templates'), 'no templates');
    });

    test('reject unknown values and functions', () {
      expect(() => expand('{{nope}}'), throwsFormatException);
      expect(() => expand('{{ version | shout }}'), throwsFormatException);
      expect(
        () => expand('{{ version || strip_prefix "v" }}'),
        throwsFormatException,
      );
      expect(() => expand('{{source.asset}}'), throwsFormatException);
    });
  });

  group('install plans', () {
    test('a GitHub release asset per platform, with templated names', () {
      final clangd = package({
        'source': {
          'id': 'pkg:github/clangd/clangd@23.1.0',
          'asset': [
            {
              'target': ['darwin_x64', 'darwin_arm64'],
              'file': 'clangd-mac-{{version}}.zip',
              'bin': 'clangd_{{version}}/bin/clangd',
            },
            {
              'target': 'linux_x64_gnu',
              'file': 'clangd-linux-{{version}}.zip',
              'bin': 'clangd_{{version}}/bin/clangd',
            },
            {
              'target': 'win_x64',
              'file': 'clangd-windows-{{version}}.zip',
              'bin': 'clangd_{{version}}/bin/clangd.exe',
            },
          ],
        },
        'bin': {'clangd': '{{source.asset.bin}}'},
      });
      final plan = MasonInstallPlan.of(clangd, macArm);
      expect(plan.kind, MasonSourceKind.github);
      expect(plan.version, '23.1.0');
      expect(
        plan.downloads.single.url.toString(),
        'https://github.com/clangd/clangd/releases/download/23.1.0/clangd-mac-23.1.0.zip',
      );
      expect(plan.downloads.single.path, 'clangd-mac-23.1.0.zip');
      expect(plan.bins['clangd']!.path, 'clangd_23.1.0/bin/clangd');
      expect(plan.bins['clangd']!.kind, MasonBinKind.executable);
      expect(plan.runtimes, isEmpty);
      expect(
        MasonInstallPlan.of(clangd, windows).bins['clangd']!.path,
        'clangd_23.1.0/bin/clangd.exe',
      );
      expect(
        () => MasonInstallPlan.of(clangd, linuxMusl),
        throwsA(isA<LspInstallException>()),
      );
    });

    test('asset destinations, exec bins, bin maps and file lists', () {
      final lua = package({
        'source': {
          'id': 'pkg:github/LuaLS/lua-language-server@3.19.1',
          'asset': [
            {
              'target': 'darwin_arm64',
              'file': 'lua-language-server-{{version}}-darwin-arm64.tar.gz:libexec/',
              'bin': 'exec:libexec/bin/lua-language-server',
            },
          ],
        },
        'bin': {'lua-language-server': '{{source.asset.bin}}'},
      });
      final plan = MasonInstallPlan.of(lua, macArm);
      expect(
        plan.downloads.single.path,
        'libexec/lua-language-server-3.19.1-darwin-arm64.tar.gz',
      );
      expect(
        plan.bins['lua-language-server']!.path,
        'libexec/bin/lua-language-server',
      );

      final elixir = package({
        'source': {
          'id': 'pkg:github/elixir-lsp/elixir-ls@v0.31.1',
          'asset': [
            {
              'target': 'unix',
              'file': 'elixir-ls-{{version}}.zip',
              'bin': {'lsp': 'language_server.sh', 'dap': 'debug_adapter.sh'},
            },
          ],
        },
        'bin': {
          'elixir-ls': '{{source.asset.bin.lsp}}',
          'elixir-ls-debugger': '{{source.asset.bin.dap}}',
        },
      });
      final elixirPlan = MasonInstallPlan.of(elixir, linuxGnu);
      expect(elixirPlan.bins['elixir-ls']!.path, 'language_server.sh');
      expect(
        elixirPlan.downloads.single.url.path,
        '/elixir-lsp/elixir-ls/releases/download/v0.31.1/elixir-ls-v0.31.1.zip',
      );

      final many = package({
        'source': {
          'id': 'pkg:github/o/r@1.0',
          'asset': {
            'file': [
              'tool-{{ version }}',
              'tool.1:man1/',
              'data.json:share/x.json',
            ],
          },
        },
        'bin': {'tool': 'tool-{{version}}'},
      });
      expect(MasonInstallPlan.of(many, macArm).downloads.map((d) => d.path), [
        'tool-1.0',
        'man1/tool.1',
        'share/x.json',
      ]);
    });

    test('package managers, extras and wrapped runtimes', () {
      final ts = MasonInstallPlan.of(
        package({
          'source': {
            'id': 'pkg:npm/typescript-language-server@6.0.1',
            'extra_packages': ['typescript@6.0.3'],
          },
          'bin': {
            'typescript-language-server': 'npm:typescript-language-server',
          },
        }),
        macArm,
      );
      expect(ts.kind, MasonSourceKind.npm);
      expect(ts.extraPackages, ['typescript@6.0.3']);
      expect(
        ts.bins.values.single.path,
        'node_modules/.bin/typescript-language-server',
      );
      expect(ts.runtimes, ['npm']);
      final tsWindows = MasonInstallPlan.of(ts.package, windows);
      expect(
        tsWindows.bins.values.single.path,
        'node_modules/.bin/typescript-language-server.cmd',
      );

      final pylsp = MasonInstallPlan.of(
        package({
          'source': {'id': 'pkg:pypi/python-lsp-server@1.13.1?extra=all'},
          'bin': {'pylsp': 'pypi:pylsp'},
        }),
        linuxGnu,
      );
      expect(pylsp.kind, MasonSourceKind.pypi);
      expect(pylsp.bins['pylsp']!.path, 'venv/bin/pylsp');
      expect(
        MasonInstallPlan.of(pylsp.package, windows).bins['pylsp']!.path,
        'venv/Scripts/pylsp.exe',
      );

      final gopls = MasonInstallPlan.of(
        package({
          'source': {'id': 'pkg:golang/golang.org/x/tools/gopls@v0.23.0'},
          'bin': {'gopls': 'golang:gopls'},
        }),
        windows,
      );
      expect(gopls.bins['gopls']!.path, 'gopls.exe');
      expect(gopls.runtimes, ['go']);

      final cargo = MasonInstallPlan.of(
        package({
          'source': {'id': 'pkg:cargo/asm-lsp@0.10.1'},
          'bin': {'asm-lsp': 'cargo:asm-lsp'},
        }),
        macArm,
      );
      expect(cargo.bins['asm-lsp']!.path, 'bin/asm-lsp');

      final wrapped = MasonInstallPlan.of(
        package({
          'source': {'id': 'pkg:npm/azure-pipelines-language-server@0.9.3'},
          'bin': {
            'azure': 'node:node_modules/azure/out/server.js',
            'jar': 'java-jar:server.jar',
            'mod': 'pyvenv:some_module',
          },
        }),
        macArm,
      );
      expect(wrapped.bins['azure']!.kind, MasonBinKind.wrapped);
      expect(wrapped.bins['azure']!.runtime, 'node');
      expect(wrapped.bins['jar']!.runtimeArgs, ['-jar']);
      expect(wrapped.bins['mod']!.runtime, './venv/bin/python');
      expect(wrapped.bins['mod']!.runtimeArgs, ['-m', 'some_module']);
      expect(wrapped.runtimes, ['npm', 'node', 'java']);
    });

    test('generic downloads by target', () {
      final plan = MasonInstallPlan.of(
        package({
          'source': {
            'id': 'pkg:generic/eclipse/eclipse.jdt.ls@v1.61.0',
            'download': [
              {
                'target': ['darwin_x64', 'darwin_arm64'],
                'files': {
                  'jdtls.tar.gz': 'https://download.eclipse.org/jdt-language-server-{{ version | strip_prefix "v" }}.tar.gz',
                },
                'config': 'config_mac/',
              },
            ],
          },
          'bin': {'jdtls': 'python:bin/jdtls'},
        }),
        macArm,
      );
      expect(plan.kind, MasonSourceKind.generic);
      expect(
        plan.downloads.single.url.toString(),
        'https://download.eclipse.org/jdt-language-server-1.61.0.tar.gz',
      );
      expect(plan.downloads.single.path, 'jdtls.tar.gz');
      expect(plan.bins['jdtls']!.runtime, 'python3');
    });

    test('unsupported sources and platforms say why', () {
      void rejects(
        Map<String, Object?> json,
        MasonPlatform platform,
        String why,
      ) {
        expect(
          () => MasonInstallPlan.of(package(json), platform),
          throwsA(
            isA<LspInstallException>().having(
              (e) => e.toString(),
              'message',
              contains(why),
            ),
          ),
        );
      }

      rejects(
        {
          'source': {'id': 'pkg:opam/ocaml-lsp-server@1.0'},
          'bin': {'x': 'opam:x'},
        },
        macArm,
        'is a opam package',
      );
      rejects(
        {
          'source': {
            'id': 'pkg:github/o/r@1',
            'build': {'run': 'make'},
          },
          'bin': {},
        },
        macArm,
        'builds from source',
      );
      rejects(
        {
          'source': {
            'id': 'pkg:pypi/ansible-lint@26.9.0',
            'supported_platforms': ['unix'],
          },
          'bin': {},
        },
        windows,
        'not available for win_x64',
      );
      rejects(
        {
          'source': {'id': 'pkg:npm/x'},
          'bin': {},
        },
        macArm,
        'names no version',
      );
      rejects(
        {
          'source': {
            'id': 'pkg:github/o/r@1',
            'asset': {'file': '../../etc/passwd:../'},
          },
          'bin': {},
        },
        macArm,
        'outside the package',
      );
      rejects(
        {
          'source': {'id': 'pkg:npm/x@1'},
          'bin': {'x': 'gem:x'},
        },
        macArm,
        'cannot run',
      );
    });
  });
}
