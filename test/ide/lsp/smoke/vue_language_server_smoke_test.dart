// Reports what the real servers answered, for a person to read.
// ignore_for_file: avoid_print
@Tags(['lsp-smoke'])
@TestOn('mac-os || linux')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/lsp/catalog/bundled_lsp_catalog.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/lsp_process.dart';
import 'package:baocode/ide/lsp/lsp_process_io.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:baocode/platform/child_process_registry.dart';
import 'package:path/path.dart' as p;

import '../../../fixtures/lsp/fake_lsp.dart';

/// Finds the servers in `<modules>/node_modules/.bin`.
class _ModulesProvider implements LspServerProvider {
  _ModulesProvider(this.modules);

  final String modules;

  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async {
    final path = p.join(modules, 'node_modules', '.bin', server.command);
    return File(path).existsSync()
        ? LspServerFound(path)
        : const LspServerMissing();
  }

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) => throw const LspInstallException('Not installable');
}

/// vue-language-server and typescript-language-server, as the bundled
/// catalog pairs them for `.vue` files, through the manager: navigation
/// from a template into a child component's props and events, and from
/// the script into what it imports.
///
/// Needs a folder with `npm install @vue/language-server
/// typescript-language-server typescript vue` in `BAOCODE_VUE_SMOKE`; the
/// project is made inside it, so its `node_modules` resolve.
void main() {
  final modules = Platform.environment['BAOCODE_VUE_SMOKE'];

  test(
    'vue: template props, events and imports go to their definitions',
    () async {
      ClaudeEnvironment.use(Platform.environment);
      final root = Directory(modules!)
          .createTempSync('project-')
          .resolveSymbolicLinksSync();
      addTearDown(() => Directory(root).deleteSync(recursive: true));
      LspProcesses.registry = ChildProcessRegistry(
        file: File(p.join(root, '.lsp-processes.json')),
      );
      void write(String name, String text) => File(p.join(root, name))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
      write('package.json', '{"name":"smoke","private":true}');
      write(
        'tsconfig.json',
        '{"compilerOptions":{"target":"ESNext","module":"ESNext",'
            '"moduleResolution":"bundler","strict":true,"jsx":"preserve"},'
            '"include":["src/**/*.ts","src/**/*.vue"]}',
      );
      write(
        'src/tools.ts',
        'export function useTableHeight() {\n  return 1;\n}\n',
      );
      write(
        'src/Child.vue',
        '<script setup lang="ts">\n'
            'defineProps<{\n'
            '  rows: string[];\n'
            '  height: number;\n'
            '  caption?: string;\n'
            '}>();\n'
            'defineEmits<{\n'
            "  'toggle-title': [];\n"
            '}>();\n'
            '</script>\n'
            '<template><div>{{ rows.length }}</div></template>\n',
      );
      final path = p.join(root, 'src', 'App.vue');
      write(
        'src/App.vue',
        '<template>\n'
            '  <Child\n'
            '    :rows="visibleRows"\n'
            '    :height="useTableHeight()"\n'
            '    @toggle-title="toggle"\n'
            '  />\n'
            '</template>\n'
            '<script setup lang="ts">\n'
            "import Child from './Child.vue';\n"
            "import { useTableHeight } from './tools';\n"
            "const visibleRows = ['a'];\n"
            'function toggle() {}\n'
            '</script>\n',
      );

      final catalog = BundledLspCatalog(
        data: File('assets/lsp/languages.json').readAsStringSync(),
      );
      await catalog.load();
      final lsp = LspManager(root, catalog, _ModulesProvider(modules));
      final workspace = IdeWorkspace(
        root,
        files: IdeFileService(root),
        languages: lsp,
      );
      addTearDown(() async {
        workspace.dispose();
        await lsp.shutdown();
        await stopLspProcesses();
      });
      final watch = Stopwatch()..start();
      await workspace.open(path);
      expect(lsp.statusFor(path).map((s) => s.serverId), [
        'vuels',
        'typescript-language-server',
      ]);
      await until(
        () => lsp
            .statusFor(path)
            .every((s) => s.state == LanguageServerState.running),
        timeout: const Duration(seconds: 60),
        reason: 'both servers running',
      );
      print('running after ${watch.elapsedMilliseconds}ms');

      Future<List<String>> definition(int line, int character) async {
        final locations = await lsp.definition(
          path,
          LspPosition(line, character),
        );
        return [
          for (final l in locations)
            '${p.basename(Uri.parse(l.uri).toFilePath())}:'
                '${l.revealRange.start.line}',
        ];
      }

      // The first answers wait for tsserver to load the project.
      var rows = const <String>[];
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (!rows.contains('Child.vue:2') &&
          DateTime.now().isBefore(deadline)) {
        rows = await definition(2, 6);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      print('definition :rows -> $rows (${watch.elapsedMilliseconds}ms)');
      expect(rows, contains('Child.vue:2'));

      final value = await definition(2, 14);
      print('definition visibleRows -> $value');
      expect(value, contains('App.vue:10'));

      // An event goes nowhere but itself: Vue's tools (3.3) do not resolve
      // it to the child's emits. Its handler does go to its function.
      final handler = await definition(4, 21);
      print('definition toggle -> $handler');
      expect(handler, contains('App.vue:11'));

      final tag = await definition(1, 4);
      print('definition <Child -> $tag');
      expect(tag.any((l) => l.startsWith('Child.vue:')), isTrue);

      final imported = await definition(9, 12);
      print('definition import useTableHeight -> $imported');
      expect(imported, contains('tools.ts:0'));

      final called = await definition(3, 16);
      print('definition useTableHeight() in template -> $called');
      expect(called, contains('tools.ts:0'));

      final hover = await lsp.hover(path, const LspPosition(2, 14));
      print('hover visibleRows: ${hover?.markdown.split('\n').take(3)}');
      expect(hover?.markdown, contains('visibleRows'));

      final references = await lsp.references(path, const LspPosition(10, 8));
      print('references visibleRows: ${references.length}');
      expect(references.length, greaterThanOrEqualTo(2));

      final prepared = await lsp.prepareRename(path, const LspPosition(10, 8));
      final rename = await lsp.rename(
        path,
        const LspPosition(10, 8),
        'shownRows',
      );
      final edits = [...?rename?.changes.values.expand((e) => e)];
      print('rename ${prepared?.placeholder}: ${edits.length} edits');
      expect(prepared?.placeholder, 'visibleRows');
      expect(edits.length, greaterThanOrEqualTo(2));

      final symbols = await lsp.documentSymbols(path);
      print('symbols: ${symbols.map((s) => s.name)}');

      final completion = await lsp.completion(path, const LspPosition(2, 14));
      print('completion: ${completion.items.length} items');
      expect(completion.items.map((i) => i.label), contains('visibleRows'));

      // Vue's server knows the child's props only by asking tsserver
      // through the manager (`tsserver/request`).
      final props = await lsp.completion(path, const LspPosition(5, 2));
      final fromVue = [
        for (final item in props.items)
          if (item.serverId == 'vuels') item.label,
      ];
      print('vuels completion in <Child>: ${fromVue.take(6)}');
      expect(fromVue.any((label) => label.contains('caption')), isTrue);
    },
    skip: modules == null ? 'BAOCODE_VUE_SMOKE is not set' : false,
  );
}
