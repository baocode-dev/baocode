import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/lsp_process.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:path/path.dart' as p;

class _StaticCatalog implements LspCatalog {
  _StaticCatalog(this.definition, {this.languageRoots = const []});

  final LspServerDefinition definition;
  final List<String> languageRoots;

  @override
  LspLanguage? languageFor(String path, {String? firstLine}) => LspLanguage(
    id: 'java',
    fileTypes: const ['java'],
    rootMarkers: languageRoots,
    servers: [definition.id],
  );

  @override
  LspServerDefinition? server(String id) =>
      id == definition.id ? definition : null;
}

class _FoundProvider implements LspServerProvider {
  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      const LspServerFound('jdtls');

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) async {}
}

class _SilentProcess implements LspProcess {
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  bool _stopped = false;

  @override
  int get pid => 1;

  @override
  bool get stopRequested => _stopped;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(List<int> bytes) {}

  @override
  Future<void> closeStdin() async {}

  @override
  void kill({bool force = false}) {
    _stopped = true;
    if (!_exit.isCompleted) _exit.complete(0);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }
}

void main() {
  Future<List<LspLaunch>> captureLaunches({
    required String root,
    required p.Context paths,
    required Set<String> existingPaths,
    required List<String> openPaths,
    List<String> rootMarkers = const ['pom.xml'],
    bool asyncExists = false,
    List<String>? checked,
  }) async {
    final launches = <LspLaunch>[];
    final normalizedExisting = existingPaths.map(paths.normalize).toSet();
    final manager = LspManager(
      root,
      _StaticCatalog(
        const LspServerDefinition(id: 'jdtls', command: 'jdtls'),
        languageRoots: rootMarkers,
      ),
      _FoundProvider(),
      paths: paths,
      pathExists: (path) {
        final normalized = paths.normalize(path);
        checked?.add(normalized);
        final exists = normalizedExisting.any(
          (candidate) => paths.equals(candidate, normalized),
        );
        return asyncExists ? Future.value(exists) : exists;
      },
      startProcess: (launch) async {
        launches.add(launch);
        return _SilentProcess();
      },
      initializeTimeout: const Duration(milliseconds: 50),
      shutdownTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(() async {
      await manager.shutdown();
      manager.dispose();
    });
    for (final file in openPaths) {
      manager.openDocument(file, 'class A {}');
    }
    // Let locate() + _startProcess() complete.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return launches;
  }

  test(
    'multi-module Maven project shares one server at workspace root',
    () async {
      final paths = p.Context(style: p.Style.windows);
      const root = r'E:\project\yidian-service-cms.agent';
      final launches = await captureLaunches(
        root: root,
        paths: paths,
        existingPaths: {
          r'E:\project\yidian-service-cms.agent\pom.xml',
          r'E:\project\yidian-service-cms.agent\cms.agent-service\pom.xml',
          r'E:\project\yidian-service-cms.agent\cms.agent-common\pom.xml',
        },
        openPaths: const [
          r'E:\project\yidian-service-cms.agent\cms.agent-service\src\main\java\A.java',
          r'E:\project\yidian-service-cms.agent\cms.agent-common\src\main\java\B.java',
        ],
      );
      expect(launches, hasLength(1));
      expect(launches.single.workingDirectory, root);
    },
  );

  test(
    'nested multi-module project uses outermost marker within workspace',
    () async {
      final paths = p.Context(style: p.Style.posix);
      const root = '/workspace/monorepo';
      final launches = await captureLaunches(
        root: root,
        paths: paths,
        existingPaths: {
          '/workspace/monorepo/backend/pom.xml',
          '/workspace/monorepo/backend/mod-a/pom.xml',
          '/workspace/monorepo/backend/mod-b/pom.xml',
        },
        openPaths: const [
          '/workspace/monorepo/backend/mod-a/src/A.java',
          '/workspace/monorepo/backend/mod-b/src/B.java',
        ],
      );
      expect(launches, hasLength(1));
      expect(launches.single.workingDirectory, '/workspace/monorepo/backend');
    },
  );

  test('a crate in a subfolder of another keeps its own server', () async {
    final paths = p.Context(style: p.Style.posix);
    const root = '/workspace';
    final launches = await captureLaunches(
      root: root,
      paths: paths,
      rootMarkers: const ['Cargo.toml'],
      existingPaths: {
        '/workspace/Cargo.toml',
        '/workspace/tools/gen/Cargo.toml',
      },
      openPaths: const ['/workspace/tools/gen/src/main.rs'],
    );
    expect(launches.single.workingDirectory, '/workspace/tools/gen');
  });

  test('independent sibling projects each keep their own server', () async {
    final paths = p.Context(style: p.Style.posix);
    const root = '/workspace';
    final launches = await captureLaunches(
      root: root,
      paths: paths,
      existingPaths: {'/workspace/one/pom.xml', '/workspace/two/pom.xml'},
      openPaths: const [
        '/workspace/one/src/A.java',
        '/workspace/two/src/B.java',
      ],
    );
    expect(launches.map((l) => l.workingDirectory), [
      '/workspace/one',
      '/workspace/two',
    ]);
  });

  test('Gradle multi-module project roots at settings.gradle without root build.gradle', () async {
    final paths = p.Context(style: p.Style.posix);
    const root = '/workspace/gradle-app';
    final launches = await captureLaunches(
      root: root,
      paths: paths,
      rootMarkers: const [
        'pom.xml',
        'settings.gradle',
        'settings.gradle.kts',
        'build.gradle',
        'build.gradle.kts',
      ],
      existingPaths: {
        '/workspace/gradle-app/settings.gradle.kts',
        '/workspace/gradle-app/service/build.gradle.kts',
      },
      openPaths: const ['/workspace/gradle-app/service/src/main/java/App.java'],
    );
    expect(launches, hasLength(1));
    expect(launches.single.workingDirectory, root);
  });

  test('async remote root lookup stops at outermost marker without probing submodules', () async {
    final paths = p.Context(style: p.Style.posix);
    const root = '/workspace/repo';
    final checked = <String>[];
    final launches = await captureLaunches(
      root: root,
      paths: paths,
      asyncExists: true,
      checked: checked,
      existingPaths: {
        '/workspace/repo/pom.xml',
        '/workspace/repo/mod-a/pom.xml',
      },
      openPaths: const ['/workspace/repo/mod-a/src/main/java/A.java'],
    );
    expect(launches, hasLength(1));
    expect(launches.single.workingDirectory, root);
    expect(checked, ['/workspace/repo/pom.xml']);
  });

  test('files outside workspace still stop at their nearest marker', () async {
    final paths = p.Context(style: p.Style.posix);
    const root = '/workspace/project-a';
    final launches = await captureLaunches(
      root: root,
      paths: paths,
      existingPaths: {'/other/pom.xml', '/other/sub/pom.xml'},
      openPaths: const ['/other/sub/src/A.java'],
    );
    expect(launches, hasLength(1));
    expect(launches.single.workingDirectory, '/other/sub');
  });
}
