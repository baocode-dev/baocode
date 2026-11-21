import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/file_service.dart' show localizedFileError;
import 'package:baocode/l10n/app_localizations_zh.dart';
import 'package:baocode/ide/lsp/json_rpc.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/lsp_process.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:baocode/ide/lsp_ui/lsp_convert.dart';
import 'package:path/path.dart' as p;

import '../../workbench/fake_files.dart';

const _java = LspServerDefinition(id: 'jdtls', command: 'jdtls');
const _binary =
    'jdt://contents/java.base/java.math/BigDecimal.class?=project/%3Cjava.base%7Bjava.math%28BigDecimal.class';
const _range = LspRange(LspPosition(2, 13), LspPosition(2, 23));

class _Catalog implements LspCatalog {
  @override
  LspLanguage? languageFor(String path, {String? firstLine}) =>
      path.endsWith('.java')
      ? const LspLanguage(
          id: 'java',
          fileTypes: ['java'],
          servers: ['jdtls'],
          rootMarkers: ['pom.xml'],
        )
      : null;

  @override
  LspServerDefinition? server(String id) => id == 'jdtls' ? _java : null;
}

class _Provider implements LspServerProvider {
  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      const LspServerFound('jdtls');

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) async {}
}

class _Process implements LspProcess {
  _Process(this.root) {
    rpc = JsonRpcConnection(_stdin.stream, _stdout.add)
      ..onRequest(
        'initialize',
        (_) => {
          'capabilities': {
            'textDocumentSync': 2,
            'definitionProvider': true,
            'hoverProvider': true,
            'renameProvider': true,
            'completionProvider': <String, Object?>{},
            'documentFormattingProvider': true,
            'documentSymbolProvider': true,
          },
        },
      )
      ..onRequest('textDocument/definition', (params) {
        definitions.add(params);
        return definition;
      })
      ..onRequest('java/classFileContents', (params) {
        reads.add(params);
        return read?.call() ?? text;
      })
      ..onRequest('textDocument/hover', (params) {
        hovers.add(params);
        return {'contents': 'Java documentation'};
      })
      ..onRequest('textDocument/documentSymbol', (_) => <Object?>[])
      ..onRequest('shutdown', (_) => null)
      ..onNotification('textDocument/didOpen', opens.add)
      ..onNotification('textDocument/didClose', closes.add)
      ..onNotification('textDocument/didChange', changes.add)
      ..onNotification('textDocument/didSave', saves.add)
      ..onNotification('exit', (_) => kill());
    definition = {
      'targetUri': _binary,
      'targetRange': const LspRange(
        LspPosition(0, 0),
        LspPosition(5, 0),
      ).toJson(),
      'targetSelectionRange': _range.toJson(),
    };
  }

  final String root;
  late final JsonRpcConnection rpc;
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  bool _stopped = false;
  Object? definition;
  String text = 'package java.math;\r\n\r\npublic class BigDecimal {}\r\n';
  FutureOr<Object?> Function()? read;
  final reads = <Object?>[];
  final definitions = <Object?>[];
  final hovers = <Object?>[];
  final opens = <Object?>[];
  final closes = <Object?>[];
  final changes = <Object?>[];
  final saves = <Object?>[];

  void invalidate(bool automatic) => rpc.notify('language/eventNotification', {
    'eventType': 500,
    'data': {
      'affectedRootPaths': {'/jdk/java.base': automatic},
    },
  });

  @override
  int get pid => 42;
  @override
  Stream<List<int>> get stdout => _stdout.stream;
  @override
  Stream<List<int>> get stderr => _stderr.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool get stopRequested => _stopped;
  @override
  void write(List<int> bytes) => _stdin.add(bytes);
  @override
  Future<void> closeStdin() => _stdin.close();
  @override
  void kill({bool force = false}) {
    if (_stopped) return;
    _stopped = true;
    rpc.close();
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exit.complete(0);
  }
}

class _Files extends TreeFiles {
  _Files(super.contents);
  final reads = <String>[];
  final writes = <String>[];
  @override
  Future<String> read(String path, {bool force = false}) {
    reads.add(path);
    return super.read(path, force: force);
  }

  @override
  Future<void> write(String path, String text, {String? expectedText}) {
    writes.add(path);
    return super.write(path, text, expectedText: expectedText);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<_Process> processes;
  late LspManager manager;
  late IdeWorkspace workspace;
  late _Files files;

  void start({p.Context? paths, String root = '/workspace'}) {
    processes = [];
    files = _Files({
      (paths ?? p.posix).join(root, 'src', 'Main.java'):
          'import java.math.BigDecimal;',
      '/other/src/Other.java': 'class Other {}',
    });
    manager = LspManager(
      root,
      _Catalog(),
      _Provider(),
      paths: paths ?? p.posix,
      pathExists: (path) => path.endsWith('pom.xml'),
      listDirectory: (_) => const [],
      startProcess: (launch) async {
        final process = _Process(launch.workingDirectory);
        processes.add(process);
        return process;
      },
      watchDirectory: (_) => const Stream.empty(),
      requestTimeout: const Duration(seconds: 2),
    );
    workspace = IdeWorkspace(
      root,
      files: files,
      languages: manager,
      paths: paths ?? p.posix,
      watch: (_) => const Stream.empty(),
    );
    addTearDown(() async {
      workspace.dispose();
      await manager.shutdown();
      manager.dispose();
    });
  }

  Future<LspLocation> target([String path = '/workspace/src/Main.java']) async {
    await workspace.open(path);
    return (await manager.definition(path, const LspPosition(0, 22))).single;
  }

  test(
    'opens JDK source with the exact URI and a read-only Java model',
    () async {
      start();
      final location = await target();
      final source = location.virtualDocument!;
      expect(source.uri, _binary);
      expect(source.name, 'BigDecimal.java');
      expect(source.languageId, 'java');
      expect(IdeLocation.of(location, paths: p.windows)!.range, _range);
      final ide = IdeLocation.of(location, paths: p.windows)!;
      expect(ide.path, source.path);
      expect(lspPathOfUri(_binary), isNull);

      await workspace.open(ide.path);
      final doc = workspace.active!;
      final process = processes.single;
      expect(doc.virtualDocument, same(source));
      expect(doc.name, 'BigDecimal.java');
      expect(doc.text, process.text);
      expect(doc.readOnly, isTrue);
      expect(doc.isFile, isFalse);
      expect(doc.dirty, isFalse);
      expect(process.reads, [
        {'uri': _binary},
      ]);
      expect(files.reads, ['/workspace/src/Main.java']);
      await _settle();
      expect((process.opens.last as Map)['textDocument'], {
        'uri': _binary,
        'languageId': 'java',
        'version': 0,
        'text': process.text,
      });

      await workspace.open(source.path);
      expect(workspace.active, same(doc));
      expect(process.reads, hasLength(1));
      await manager.hover(source.path, const LspPosition(2, 15));
      expect((process.hovers.single as Map)['textDocument'], {'uri': _binary});
      final nested = await manager.definition(
        source.path,
        const LspPosition(2, 15),
      );
      expect(nested.single.virtualDocument, same(source));
      expect((process.definitions.last as Map)['textDocument'], {
        'uri': _binary,
      });
      expect(manager.supports(source.path, LanguageRequest.definition), isTrue);
      expect(manager.supports(source.path, LanguageRequest.rename), isFalse);
      expect(
        manager.supports(source.path, LanguageRequest.completion),
        isFalse,
      );
      expect(
        await manager.format(source.path, tabSize: 2, insertSpaces: true),
        isEmpty,
      );
      workspace.edit(source.path, 'changed');
      expect(doc.text, process.text);
      await workspace.save(doc);
      expect(await workspace.saveAs(doc), isNull);
      manager.changeDocument(source.path, 'changed', version: 50);
      manager.saveDocument(source.path, 'changed');
      await _settle();
      expect(files.writes, isEmpty);
      expect(process.changes, isEmpty);
      expect(process.saves, isEmpty);
      workspace.close(doc);
      await _settle();
      expect(process.closes.last, {
        'textDocument': {'uri': _binary},
      });
    },
  );

  test(
    'identical URIs from different Java projects keep their owners',
    () async {
      start();
      final first = (await target()).virtualDocument!;
      final second = (await target('/other/src/Other.java')).virtualDocument!;
      expect(first.path, isNot(second.path));
      expect(first.uri, second.uri);
      processes[0].text = 'source from workspace';
      processes[1].text = 'source from other project';
      workspace.close(workspace.documents.first);
      expect(
        await workspace.readDocumentText(first.path),
        'source from workspace',
      );
      expect(
        await workspace.readDocumentText(second.path),
        'source from other project',
      );
      expect(processes[0].reads, [
        {'uri': _binary},
      ]);
      expect(processes[1].reads, [
        {'uri': _binary},
      ]);
    },
  );

  test(
    'coalesces reads and does not cache a failed source as an empty tab',
    () async {
      start();
      final source = (await target()).virtualDocument!;
      final process = processes.single;
      final gate = Completer<Object?>();
      process.read = () => gate.future;
      final one = manager.readVirtualDocument(source.path);
      final two = manager.readVirtualDocument(source.path);
      expect(two, same(one));
      await _settle();
      expect(process.reads, hasLength(1));
      gate.complete('decompiled source');
      expect((await one).text, 'decompiled source');
      expect((await two).text, 'decompiled source');

      process.read = () => '';
      final previous = workspace.active;
      await expectLater(
        workspace.open(source.path),
        throwsA(isA<LspSourceException>()),
      );
      expect(workspace.active, same(previous));
      expect(workspace.documents, hasLength(1));
      process.read = () => 'source is available now';
      await workspace.open(source.path);
      expect(workspace.active!.text, 'source is available now');
    },
  );

  test(
    'source invalidations refresh the same model for true and false',
    () async {
      start();
      final source = (await target()).virtualDocument!;
      await workspace.open(source.path);
      final doc = workspace.active!;
      final process = processes.single;
      for (final automatic in [true, false]) {
        process.text = 'updated source $automatic';
        process.invalidate(automatic);
        await _settle();
        expect(workspace.active, same(doc));
        expect(doc.text, process.text);
        expect(doc.savedText, process.text);
        expect(doc.dirty, isFalse);
      }
      expect(process.reads, hasLength(3));
      expect(process.changes, isEmpty);
      expect(process.saves, isEmpty);
    },
  );

  test(
    'a late response from an invalidated source is replaced, not published',
    () async {
      start();
      final source = (await target()).virtualDocument!;
      final process = processes.single;
      final gate = Completer<Object?>();
      process.read = () => gate.future;
      final reading = manager.readVirtualDocument(source.path);
      await _settle();
      process.read = () => 'new source attachment';
      process.invalidate(false);
      await _settle();
      gate.complete('old decompiled source');
      expect((await reading).text, 'new source attachment');
      expect(process.reads, hasLength(2));
    },
  );

  test('restart refreshes source before reopening the original URI', () async {
    start();
    final source = (await target()).virtualDocument!;
    await workspace.open(source.path);
    final doc = workspace.active!;
    manager.restartServers();
    await _settle();
    final restarted = processes.last;
    expect(processes, hasLength(2));
    expect(workspace.active, same(doc));
    expect(restarted.reads, [
      {'uri': _binary},
    ]);
    expect(
      (restarted.opens.last as Map)['textDocument'],
      containsPair('uri', _binary),
    );
    expect(doc.virtualVersion, manager.virtualDocumentVersion(source.path));
    expect((await target()).virtualDocument!.path, source.path);
  });

  test(
    'source refresh failures report the source and can be retried',
    () async {
      start();
      final source = (await target()).virtualDocument!;
      await workspace.open(source.path);
      final doc = workspace.active!;
      final errors = <Object>[];
      workspace.onSourceError = errors.add;
      processes.single.read = () => '';
      processes.single.invalidate(false);
      await _settle();
      expect(errors.single, isA<LspSourceException>());
      expect(doc.text, processes.single.text);
      expect(
        localizedFileError(AppLocalizationsZh(), errors.single),
        '无法获取“BigDecimal.java”的库源码。\n语言服务器未提供源码或反编译内容。',
      );
      processes.single.read = () => 'source now attached';
      await workspace.open(source.path);
      expect(workspace.active, same(doc));
      expect(doc.text, 'source now attached');
    },
  );

  test('closing a source during refresh does not reopen it', () async {
    start();
    final source = (await target()).virtualDocument!;
    await workspace.open(source.path);
    final doc = workspace.active!;
    final gate = Completer<Object?>();
    processes.single.read = () => gate.future;
    processes.single.invalidate(false);
    await _settle();
    workspace.close(doc);
    gate.complete('updated after close');
    await _settle();
    expect(workspace.documents.any((doc) => doc.path == source.path), isFalse);
    expect(workspace.active!.path, '/workspace/src/Main.java');
    expect(processes.single.opens, hasLength(2));
  });

  test('ordinary file and unsupported URI navigation stay unchanged', () async {
    start();
    await target();
    final process = processes.single;
    process.definition = {
      'uri': 'file:///workspace/src/Other.java',
      'range': _range.toJson(),
    };
    final locations = await manager.definition(
      '/workspace/src/Main.java',
      const LspPosition(0, 0),
    );
    expect(locations.single.virtualDocument, isNull);
    expect(
      IdeLocation.of(locations.single, paths: p.posix)!.path,
      '/workspace/src/Other.java',
    );
    process.definition = {
      'uri': 'unknown://contents/Other.java',
      'range': _range.toJson(),
    };
    final unknown = await manager.definition(
      '/workspace/src/Main.java',
      const LspPosition(0, 0),
    );
    expect(IdeLocation.of(unknown.single), isNull);
  });

  test(
    'virtual identities never pass through Windows path normalization',
    () async {
      const root = r'C:\project';
      start(root: root, paths: p.windows);
      final source = (await target(p.windows.join(root, 'src', 'Main.java')))
          .virtualDocument!;
      await workspace.open(source.path);
      expect(workspace.active!.path, source.path);
      expect(workspace.active!.name, 'BigDecimal.java');
      expect(processes.single.reads, [
        {'uri': _binary},
      ]);
      expect(
        await workspace.readDocumentText(source.path),
        processes.single.text,
      );
    },
  );
}
