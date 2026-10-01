@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/range.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_workspace.dart';
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

/// The manager over real server processes (the fake server), through the
/// workspace as the editor drives it.
void main() {
  late String root;
  final managers = <LspManager>[];
  final workspaces = <IdeWorkspace>[];

  setUp(() {
    root = Directory.systemTemp
        .createTempSync('baocode-lsp')
        .resolveSymbolicLinksSync();
    ClaudeEnvironment.use(Platform.environment);
    LspProcesses.registry = ChildProcessRegistry(
      file: File(p.join(root, '.lsp-processes.json')),
    );
  });

  tearDown(() async {
    for (final workspace in workspaces) {
      workspace.dispose();
    }
    workspaces.clear();
    await Future.wait([for (final manager in managers) manager.shutdown()]);
    managers.clear();
    await stopLspProcesses();
    Directory(root).deleteSync(recursive: true);
  });

  LspManager manager(
    List<LspServerDefinition> servers, {
    FakeProvider? provider,
    LspDirectoryWatcher? watch,
    Duration idleTimeout = const Duration(minutes: 5),
    Duration initialBackoff = const Duration(milliseconds: 50),
    int maxCrashes = 5,
    List<String> rootMarkers = const [],
  }) {
    final manager = LspManager(
      root,
      FakeCatalog(servers, rootMarkers: rootMarkers),
      provider ?? FakeProvider(),
      watchDirectory: watch,
      idleTimeout: idleTimeout,
      initialBackoff: initialBackoff,
      maxCrashes: maxCrashes,
      shutdownTimeout: const Duration(seconds: 2),
    );
    managers.add(manager);
    return manager;
  }

  Future<(IdeWorkspace, IdeDocument)> open(
    LspManager manager,
    String name,
    String text,
  ) async {
    final path = p.join(root, name);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    final workspace = workspaces.firstWhere(
      (w) => identical(w.languages, manager),
      orElse: () {
        final workspace = IdeWorkspace(
          root,
          files: IdeFileService(root),
          languages: manager,
        );
        workspaces.add(workspace);
        return workspace;
      },
    );
    await workspace.open(path);
    return (workspace, workspace.documents.firstWhere((d) => d.path == path));
  }

  LanguageServerStatus status(LspManager manager, String path, [int i = 0]) =>
      manager.statusFor(path)[i];

  Future<void> running(LspManager manager, String path, [int i = 0]) => until(
    () => status(manager, path, i).state == LanguageServerState.running,
    reason: 'server $i running',
  );

  Future<Map<String, Object?>> state(
    LspManager manager,
    String id,
    String path,
  ) async =>
      (await manager.clientFor(id, path: path)!.request('fake/state', {}))!
          as Map<String, Object?>;

  String uri(String path) => Uri.file(path).toString();

  test('incremental sync reproduces the editor text exactly', () async {
    final lsp = manager([fakeServer('fake')]);
    final (workspace, doc) = await open(
      lsp,
      'a.fake',
      'one\r\ntwo 😀\rthree\n\u{1F600}x\r\n',
    );
    await running(lsp, doc.path);
    Future<void> check(String reason) async {
      final server = await state(lsp, 'fake', doc.path);
      expect((server['docs']! as Map)[uri(doc.path)], doc.text, reason: reason);
      expect(
        (server['versions']! as Map)[uri(doc.path)],
        doc.model.version,
        reason: reason,
      );
    }

    await check('open');
    const pieces = ['a', '\r', '\n', '\r\n', '😀', '\uD83D', '\uDE00', 'é', ''];
    final random = Random(7);
    String piece() => [
      for (var i = random.nextInt(3); i >= 0; i--)
        pieces[random.nextInt(pieces.length)],
    ].join();
    for (var step = 0; step < 300; step++) {
      final roll = random.nextInt(12);
      if (roll == 0) {
        workspace.undo(doc.path);
      } else if (roll == 1) {
        workspace.redo(doc.path);
      } else if (roll == 2) {
        final text = doc.text;
        final at = random.nextInt(text.length + 1);
        workspace.edit(doc.path, text.replaceRange(at, at, piece()));
      } else {
        final length = doc.text.length;
        final cuts = {
          for (var i = random.nextInt(6); i >= 0; i--)
            random.nextInt(length + 1),
        }.toList()..sort();
        doc.model.applyOffsetEdits([
          for (var i = 0; i + 1 < cuts.length; i += 2)
            EditorOffsetEdit(cuts[i], cuts[i + 1], piece()),
        ], coalesce: random.nextBool());
      }
      if (step % 50 == 49) await check('step $step');
    }
    await check('end');
  });

  test('diagnostics follow the text', () async {
    final lsp = manager([fakeServer('fake')]);
    final (workspace, doc) = await open(lsp, 'a.fake', 'ok\nan ERROR here\n');
    await until(() => lsp.diagnosticsFor(doc.path).isNotEmpty);
    final diagnostic = lsp.diagnosticsFor(doc.path).single;
    expect(
      diagnostic.range,
      const LspRange(LspPosition(1, 3), LspPosition(1, 8)),
    );
    expect(diagnostic.message, 'ERROR found');
    expect(diagnostic.source, 'fake');
    expect(diagnostic.unnecessary, isTrue);
    expect(lsp.allDiagnostics.keys, [doc.path]);
    var notified = 0;
    lsp.addListener(() => notified++);
    workspace.edit(doc.path, 'ok\nan error here\n');
    await until(() => lsp.diagnosticsFor(doc.path).isEmpty);
    expect(notified, greaterThan(0));
    expect(lsp.allDiagnostics, isEmpty);
  });

  test('answers: hover, navigation, completion, rename, format, symbols, '
      'code actions, commands, semantic tokens', () async {
    final lsp = manager([fakeServer('fake')]);
    final (workspace, doc) = await open(
      lsp,
      'a.fake',
      'class Foo  \n  fun bar(Foo, x)\nFoo ERROR\n',
    );
    final path = doc.path;
    await running(lsp, path);
    expect(lsp.supports(path, LanguageRequest.hover), isTrue);
    expect(lsp.supports(path, LanguageRequest.implementation), isFalse);
    expect(lsp.completionTriggerCharacters(path), {'.'});
    expect(lsp.signatureHelpTriggerCharacters(path), {'(', ','});
    expect(lsp.signatureHelpRetriggerCharacters(path), {')'});

    final hover = await lsp.hover(path, const LspPosition(0, 7));
    expect(hover!.markdown, '**fake** `Foo`');
    expect(hover.range, const LspRange(LspPosition(0, 6), LspPosition(0, 9)));
    expect(await lsp.hover(path, const LspPosition(0, 10)), isNull);

    final definition = await lsp.definition(path, const LspPosition(2, 1));
    expect(definition.single.uri, uri(path));
    expect(definition.single.range.start, const LspPosition(0, 6));
    final type = await lsp.typeDefinition(path, const LspPosition(2, 1));
    expect(type.single.revealRange.start, const LspPosition(0, 6));
    expect(await lsp.implementation(path, const LspPosition(2, 1)), isEmpty);
    final references = await lsp.references(path, const LspPosition(2, 1));
    expect(references.map((l) => l.range.start.line), [0, 1, 2]);

    final completion = await lsp.completion(
      path,
      const LspPosition(2, 3),
      triggerCharacter: '.',
    );
    expect(completion.items.map((i) => i.label), ['fake_item', 'snip']);
    expect(completion.items.first.serverId, 'fake');
    expect(completion.items.first.detail, 'trigger 2.');
    expect(completion.items.last.isSnippet, isTrue);
    final invoked = await lsp.completion(
      path,
      const LspPosition(2, 3),
      triggerCharacter: 'x',
    );
    expect(invoked.items.first.detail, 'trigger 1');
    final resolved = await lsp.resolveCompletion(path, completion.items.first);
    expect(resolved.documentation, 'docs from fake');
    expect(resolved.serverId, 'fake');

    final help = await lsp.signatureHelp(
      path,
      const LspPosition(1, 14),
      triggerCharacter: ',',
    );
    expect(help!.signatures.single.label, 'call(a, b)');
    expect(help.activeParameter, 1);
    expect(help.signatures.single.parameters.map((p) => p.label), ['a', 'b']);

    final prepared = await lsp.prepareRename(path, const LspPosition(0, 7));
    expect(prepared!.placeholder, 'Foo');
    expect(await lsp.prepareRename(path, const LspPosition(0, 10)), isNull);
    final rename = await lsp.rename(path, const LspPosition(0, 7), 'Baz');
    expect(rename!.changes[uri(path)], hasLength(3));
    expect(rename.changes[uri(path)]!.map((e) => e.newText).toSet(), {'Baz'});

    final formatting = await lsp.format(path, tabSize: 2, insertSpaces: true);
    expect(
      formatting.single.range,
      const LspRange(LspPosition(0, 9), LspPosition(0, 11)),
    );
    final ranged = await lsp.format(
      path,
      range: const LspRange(LspPosition(1, 0), LspPosition(2, 0)),
      tabSize: 2,
      insertSpaces: true,
    );
    expect(ranged, isEmpty);

    final symbols = await lsp.documentSymbols(path);
    expect(symbols.single.name, 'Foo');
    expect(symbols.single.kind, LspSymbolKind.klass);
    expect(symbols.single.children.single.name, 'bar');

    await until(() => lsp.diagnosticsFor(path).isNotEmpty);
    final actions = await lsp.codeActions(
      path,
      const LspRange(LspPosition(2, 4), LspPosition(2, 9)),
      diagnostics: lsp.diagnosticsFor(path),
    );
    expect(actions.map((a) => a.title), [
      'Replace ERROR',
      'Add header (fake)',
      'Insert header by command',
    ]);
    expect(actions.first.isQuickFix, isTrue);
    expect(actions.first.isPreferred, isTrue);
    expect(actions.first.edit!.changes[uri(path)]!.single.newText, 'OK');
    final header = await lsp.resolveCodeAction(path, actions[1]);
    expect(header.edit!.changes[uri(path)]!.single.newText, '// fake header\n');

    final requests = <LspApplyEditRequest>[];
    final subscription = lsp.workspaceEdits.listen((request) {
      requests.add(request);
      final edits = request.edit.changes[uri(path)]!;
      workspace.applyEdits(path, [
        for (final edit in edits)
          EditorDocumentEdit(
            // One-based editor coordinates.
            Range(
              edit.range.start.line + 1,
              edit.range.start.character + 1,
              edit.range.end.line + 1,
              edit.range.end.character + 1,
            ),
            edit.newText,
          ),
      ]);
      request.complete(true);
    });
    addTearDown(subscription.cancel);
    await lsp.executeCommand(path, actions[2].command!, serverId: 'fake');
    expect(requests.single.label, 'Insert header');
    expect(doc.text, startsWith('// header\nclass Foo'));
    final server = await state(lsp, 'fake', path);
    expect((server['docs']! as Map)[uri(path)], doc.text);

    final tokens = await lsp.semanticTokens(path);
    expect(
      [
        for (final t in tokens!)
          (t.line, t.character, t.length, t.type, t.modifiers.join()),
      ],
      [(1, 0, 5, 'keyword', ''), (2, 2, 3, 'keyword', 'declaration')],
    );
  });

  test('full sync, save with text, settings, progress and log', () async {
    final lsp = manager([
      fakeServer(
        'fake',
        options: {
          'sync': 1,
          'saveText': true,
          'progress': true,
          'configSections': ['fake', 'fake.nested.value', 'other', null],
        },
        settings: {
          'fake': {
            'nested': {'value': 42},
          },
        },
      ),
    ]);
    final (workspace, doc) = await open(lsp, 'a.fake', 'one\r\n');
    await running(lsp, doc.path);
    await until(() => status(lsp, doc.path).progress == 'Indexing: 1/2 (50%)');
    workspace.edit(doc.path, 'one\r\ntwo\r\n');
    await workspace.save(doc);
    await until(() => status(lsp, doc.path).progress == null);
    final server = await state(lsp, 'fake', doc.path);
    expect((server['docs']! as Map)[uri(doc.path)], 'one\r\ntwo\r\n');
    expect(server['saves'], [
      {'uri': uri(doc.path), 'text': 'one\r\ntwo\r\n'},
    ]);
    expect(server['configuration'], [
      {
        'nested': {'value': 42},
      },
      42,
      null,
      {
        'fake': {
          'nested': {'value': 42},
        },
      },
    ]);
    expect(
      server['notifications'],
      containsAllInOrder([
        'initialized',
        'workspace/didChangeConfiguration',
        'textDocument/didOpen',
        'textDocument/didChange',
        'textDocument/didSave',
      ]),
    );
    final initialize = server['initializeParams']! as Map;
    expect(initialize['rootUri'], Uri.directory(root).toString());
    expect(initialize['processId'], pid);
    final capabilities = initialize['capabilities']! as Map;
    expect((capabilities['general']! as Map)['positionEncodings'], ['utf-16']);
    expect(lsp.logFor('fake'), contains('[info] fake ready'));
  });

  test('dynamic registration, and watched files by glob', () async {
    final events = StreamController<LspFileEvent>.broadcast();
    addTearDown(events.close);
    final watchedRoots = <String>[];
    final lsp = manager(
      [
        fakeServer(
          'fake',
          options: {
            'registerHover': true,
            'watchers': [
              {'globPattern': '**/*.txt'},
              {
                'globPattern': {
                  'baseUri': Uri.directory(root).toString(),
                  'pattern': 'conf/*.json',
                },
                'kind': 4,
              },
            ],
          },
        ),
      ],
      watch: (dir) {
        watchedRoots.add(dir);
        return events.stream;
      },
    );
    final (_, doc) = await open(lsp, 'a.fake', 'word\n');
    await running(lsp, doc.path);
    await until(() => lsp.supports(doc.path, LanguageRequest.hover));
    expect(
      (await lsp.hover(doc.path, const LspPosition(0, 1)))!.markdown,
      '**fake** `word`',
    );
    await until(() => watchedRoots.isNotEmpty);
    expect(watchedRoots, [root]);
    events
      ..add(LspFileEvent(p.join(root, 'notes.txt'), LspFileChangeType.created))
      ..add(LspFileEvent(p.join(root, 'notes.txt'), LspFileChangeType.changed))
      ..add(LspFileEvent(p.join(root, 'x.dart'), LspFileChangeType.changed))
      ..add(
        LspFileEvent(p.join(root, 'conf', 'a.json'), LspFileChangeType.changed),
      )
      ..add(
        LspFileEvent(p.join(root, 'conf', 'b.json'), LspFileChangeType.deleted),
      );
    await until(() async {
      final server = await state(lsp, 'fake', doc.path);
      return (server['watched']! as List).length >= 2;
    });
    final server = await state(lsp, 'fake', doc.path);
    expect(server['watched'], [
      {'uri': uri(p.join(root, 'notes.txt')), 'type': 1},
      {'uri': uri(p.join(root, 'conf', 'b.json')), 'type': 3},
    ]);
  });

  test('several servers: answers merge in the language order', () async {
    final lsp = manager([
      fakeServer('a'),
      fakeServer('b', exceptFeatures: {LspFeature.hover, LspFeature.format}),
    ]);
    final (_, doc) = await open(lsp, 'a.fake', 'Foo ERROR Foo\n');
    final path = doc.path;
    await running(lsp, path, 0);
    await running(lsp, path, 1);
    expect(lsp.statusFor(path).map((s) => s.serverId), ['a', 'b']);
    expect(
      (await lsp.hover(path, const LspPosition(0, 1)))!.markdown,
      '**a** `Foo`',
    );
    final completion = await lsp.completion(path, const LspPosition(0, 1));
    expect(
      [for (final item in completion.items) '${item.serverId}:${item.label}'],
      ['a:a_item', 'a:snip', 'b:b_item', 'b:snip'],
    );
    final resolved = await lsp.resolveCompletion(path, completion.items[2]);
    expect(resolved.documentation, 'docs from b');
    expect(await lsp.definition(path, const LspPosition(0, 1)), hasLength(1));
    expect(await lsp.references(path, const LspPosition(0, 1)), hasLength(2));
    await until(() => lsp.diagnosticsFor(path).length == 2);
    expect(lsp.diagnosticsFor(path).map((d) => d.source), ['a', 'b']);
    final actions = await lsp.codeActions(
      path,
      const LspRange(LspPosition(0, 0), LspPosition(0, 0)),
    );
    expect([
      for (final a in actions) '${a.serverId}:${a.title}',
    ], containsAll(['a:Add header (a)', 'b:Add header (b)']));
  });

  test('workspace folders by root markers share one server each', () async {
    final lsp = manager([
      fakeServer('fake', rootMarkers: ['fake.toml']),
      fakeServer('strict', rootMarkers: ['strict.toml'], requiredRoot: true),
    ]);
    File(p.join(root, 'one', 'fake.toml')).createSync(recursive: true);
    File(p.join(root, 'two', 'fake.toml')).createSync(recursive: true);
    final (_, first) = await open(lsp, p.join('one', 'src', 'a.fake'), 'a');
    final (_, second) = await open(lsp, p.join('one', 'b.fake'), 'b');
    final (_, third) = await open(lsp, p.join('two', 'c.fake'), 'c');
    final (_, loose) = await open(lsp, 'd.fake', 'd');
    for (final doc in [first, second, third, loose]) {
      await running(lsp, doc.path);
      // No strict.toml anywhere: the strict server serves none of them.
      expect(lsp.statusFor(doc.path), hasLength(1));
    }
    Future<String> rootOf(IdeDocument doc) async =>
        ((await state(lsp, 'fake', doc.path))['initializeParams']!
                as Map)['rootUri']
            as String;
    expect(await rootOf(first), Uri.directory(p.join(root, 'one')).toString());
    expect(await rootOf(second), await rootOf(first));
    expect(await rootOf(third), Uri.directory(p.join(root, 'two')).toString());
    expect(await rootOf(loose), Uri.directory(root).toString());
    expect(
      lsp.clientFor('fake', path: first.path)!.process.pid,
      lsp.clientFor('fake', path: second.path)!.process.pid,
    );
  });

  test('documents opened before the catalog loads get servers after', () async {
    final catalog = _LateCatalog();
    final lsp = LspManager(root, catalog, FakeProvider());
    managers.add(lsp);
    final (_, doc) = await open(lsp, 'a.fake', 'x\n');
    expect(lsp.statusFor(doc.path), isEmpty);
    catalog.loaded = FakeCatalog([fakeServer('fake')]);
    lsp.reloadCatalog();
    await running(lsp, doc.path);
    final server = await state(lsp, 'fake', doc.path);
    expect((server['docs']! as Map)[uri(doc.path)], 'x\n');
  });

  test('a server with no open document stops after the idle timeout', () async {
    final lsp = manager([
      fakeServer('fake'),
    ], idleTimeout: const Duration(milliseconds: 300));
    final (workspace, doc) = await open(lsp, 'a.fake', 'x');
    await running(lsp, doc.path);
    final pid = lsp.clientFor('fake')!.process.pid;
    workspace.close(doc);
    // The process may be gone a moment before the manager hears it exit.
    await until(
      () => !processRunning(pid) && lsp.clientFor('fake') == null,
      reason: 'idle server gone',
    );
    final (_, again) = await open(lsp, 'a.fake', 'x');
    await running(lsp, again.path);
    expect(lsp.clientFor('fake')!.process.pid, isNot(pid));
  });

  test(
    'a crash restarts the server after a backoff and reopens documents',
    () async {
      final lsp = manager([fakeServer('fake')]);
      final (workspace, doc) = await open(lsp, 'a.fake', 'ERROR\n');
      await running(lsp, doc.path);
      await until(() => lsp.diagnosticsFor(doc.path).isNotEmpty);
      final pid = lsp.clientFor('fake')!.process.pid;
      final states = <LanguageServerState>[];
      void listener() {
        if (lsp.statusFor(doc.path).isNotEmpty) {
          states.add(status(lsp, doc.path).state);
        }
      }

      lsp.addListener(listener);
      addTearDown(() => lsp.removeListener(listener));
      workspace.edit(doc.path, 'CRASH ERROR\n');
      await until(() => states.contains(LanguageServerState.restarting));
      await running(lsp, doc.path);
      expect(lsp.clientFor('fake')!.process.pid, isNot(pid));
      final server = await state(lsp, 'fake', doc.path);
      expect((server['docs']! as Map)[uri(doc.path)], 'CRASH ERROR\n');
      await until(() => lsp.diagnosticsFor(doc.path).isNotEmpty);
    },
  );

  test('repeated crashes back off, then give up until retried', () async {
    final lsp = manager(
      [
        fakeServer('fake', options: {'crashAfterInitialized': true}),
      ],
      initialBackoff: const Duration(milliseconds: 40),
      maxCrashes: 3,
    );
    final (_, doc) = await open(lsp, 'a.fake', 'x');
    // Each restart's delay, when first announced.
    final retryDelays = <DateTime, Duration>{};
    void listener() {
      if (lsp.statusFor(doc.path).isEmpty) return;
      final retryAt = status(lsp, doc.path).retryAt;
      if (retryAt != null) {
        retryDelays.putIfAbsent(
          retryAt,
          () => retryAt.difference(DateTime.now()),
        );
      }
    }

    lsp.addListener(listener);
    addTearDown(() => lsp.removeListener(listener));
    await until(
      () => status(lsp, doc.path).state == LanguageServerState.failed,
    );
    // 40ms, then 80ms: the third crash gives up.
    final delays = retryDelays.values.toList();
    expect(delays, hasLength(2));
    expect(delays.first, lessThanOrEqualTo(const Duration(milliseconds: 40)));
    expect(delays.last, greaterThan(const Duration(milliseconds: 40)));
    expect(status(lsp, doc.path).message, contains('crashed 3 times'));
    expect(
      status(lsp, doc.path).message,
      contains('crashing after initialized'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(status(lsp, doc.path).state, LanguageServerState.failed);

    lsp.retry('fake', path: doc.path);
    expect(status(lsp, doc.path).state, isNot(LanguageServerState.failed));
    await until(
      () => status(lsp, doc.path).state == LanguageServerState.failed,
    );
  });

  test('a missing server installs, then starts', () async {
    final provider = FakeProvider(missing: {'fake'})..installGate = Completer();
    final lsp = manager([
      fakeServer('fake', masonPackage: 'fake-pkg'),
    ], provider: provider);
    final (_, doc) = await open(lsp, 'a.fake', 'x');
    await until(
      () => status(lsp, doc.path).state == LanguageServerState.missing,
    );
    expect(status(lsp, doc.path).installable, isTrue);
    final install = lsp.install('fake', path: doc.path);
    await until(() => status(lsp, doc.path).message == 'Downloading fake-pkg');
    expect(status(lsp, doc.path).state, LanguageServerState.installing);
    provider.installGate!.complete();
    await install;
    expect(provider.installs, ['fake-pkg']);
    await running(lsp, doc.path);
  });

  test('install failures and missing runtimes say so', () async {
    final provider = FakeProvider(missing: {'fake'}, failInstall: 'npm failed');
    final lsp = manager([
      fakeServer('fake', masonPackage: 'fake-pkg'),
    ], provider: provider);
    final (_, doc) = await open(lsp, 'a.fake', 'x');
    await until(
      () => status(lsp, doc.path).state == LanguageServerState.missing,
    );
    await lsp.install('fake');
    expect(status(lsp, doc.path).state, LanguageServerState.missing);
    expect(status(lsp, doc.path).message, 'npm failed\nexit 1');

    final noNode = manager([
      fakeServer('fake', masonPackage: 'fake-pkg'),
    ], provider: FakeProvider(missing: {'fake'}, missingRuntime: 'node'));
    final (_, other) = await open(noNode, 'b.fake', 'x');
    await until(
      () => status(noNode, other.path).state == LanguageServerState.missing,
    );
    expect(status(noNode, other.path).installable, isFalse);
    expect(status(noNode, other.path).missingRuntime, 'node');
  });

  test('stopping every server as the app quits is no crash', () async {
    final lsp = manager([
      fakeServer('fake', options: {'stubborn': true}),
    ]);
    final (_, doc) = await open(lsp, 'a.fake', 'x');
    await running(lsp, doc.path);
    final pid = lsp.clientFor('fake')!.process.pid;
    await stopLspProcesses();
    await until(() => !processRunning(pid));
    await until(
      () => status(lsp, doc.path).state == LanguageServerState.stopped,
    );
    // A request starts it again.
    expect(await lsp.hover(doc.path, const LspPosition(0, 0)), isNotNull);
  });

  test('disposing the workspace shuts its servers down', () async {
    final lsp = manager([
      fakeServer('fake'),
      fakeServer('stubborn', options: {'stubborn': true}),
    ]);
    final (workspace, doc) = await open(lsp, 'a.fake', 'x');
    await running(lsp, doc.path, 0);
    await running(lsp, doc.path, 1);
    final pids = [
      lsp.clientFor('fake')!.process.pid,
      lsp.clientFor('stubborn')!.process.pid,
    ];
    workspaces.remove(workspace);
    workspace.dispose();
    await lsp.shutdown();
    for (final pid in pids) {
      await until(() => !processRunning(pid), reason: 'pid $pid gone');
    }
  });
}

class _LateCatalog implements LspCatalog {
  LspCatalog? loaded;

  @override
  LspLanguage? languageFor(String path, {String? firstLine}) =>
      loaded?.languageFor(path, firstLine: firstLine);

  @override
  LspServerDefinition? server(String id) => loaded?.server(id);
}
