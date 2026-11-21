import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/lsp/json_rpc.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_client.dart';
import 'package:baocode/ide/lsp/lsp_process.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';

class _TestProcess implements LspProcess {
  _TestProcess(JsonMap capabilities) {
    server = JsonRpcConnection(_stdin.stream, _stdout.add)
      ..onRequest('initialize', (params) {
        initializeParams = (params! as Map).cast<String, Object?>();
        return {'capabilities': capabilities};
      })
      ..onRequest('shutdown', (_) => null)
      ..onNotification('exit', (_) => kill());
  }

  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _exit = Completer<int>();
  late final JsonRpcConnection server;
  late final JsonMap initializeParams;
  bool _stopped = false;

  Future<void> register(
    String method,
    JsonMap options, {
    String id = 'test',
  }) async {
    await server.request('client/registerCapability', {
      'registrations': [
        {'id': id, 'method': method, 'registerOptions': options},
      ],
    }, const Duration(seconds: 2));
  }

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
    server.close();
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _exit.complete(0);
  }
}

void main() {
  Future<(LspClient, _TestProcess)> start({
    LspServerDefinition definition = const LspServerDefinition(
      id: 'test',
      command: 'test',
    ),
    JsonMap capabilities = const {},
    String root = '/workspace',
    bool windowsPaths = false,
  }) async {
    final process = _TestProcess(capabilities);
    final client = LspClient(
      definition: definition,
      rootPath: root,
      process: process,
      windowsPaths: windowsPaths,
    );
    addTearDown(client.shutdown);
    await client.initialize();
    return (client, process);
  }

  test('initialize sends merged JDT class-file capabilities', () async {
    const options = {
      'bundles': ['debug.jar'],
      'extendedClientCapabilities': {
        'classFileContentsSupport': false,
        'progressReportProvider': true,
      },
    };
    final (_, process) = await start(
      definition: const LspServerDefinition(
        id: 'jdtls#project',
        command: 'java',
        initializationOptions: options,
      ),
    );
    expect(process.initializeParams['initializationOptions'], {
      'bundles': ['debug.jar'],
      'extendedClientCapabilities': {
        'classFileContentsSupport': true,
        'progressReportProvider': true,
      },
    });
    expect(
      (options['extendedClientCapabilities']!
          as Map)['classFileContentsSupport'],
      isFalse,
    );
  });

  test('initialize adds JDT options even when none were configured', () async {
    final (_, process) = await start(
      definition: const LspServerDefinition(id: 'jdtls', command: 'java'),
    );
    expect(process.initializeParams['initializationOptions'], {
      'extendedClientCapabilities': {'classFileContentsSupport': true},
    });
  });

  test('initialize leaves non-JDT options unchanged or absent', () async {
    const options = {
      'hostInfo': 'custom',
      'extendedClientCapabilities': {'classFileContentsSupport': false},
    };
    final (_, configured) = await start(
      definition: const LspServerDefinition(
        id: 'other',
        command: 'other',
        initializationOptions: options,
      ),
    );
    expect(configured.initializeParams['initializationOptions'], options);
    final (_, unconfigured) = await start();
    expect(
      unconfigured.initializeParams.containsKey('initializationOptions'),
      isFalse,
    );
  });

  const virtualUri =
      'jdt://contents/java.base/java/lang/String.class?jar=rt.jar#source';
  const virtualPath = '/java.base/java/lang/String.class';

  test('dynamic options, support and characters use the virtual URI', () async {
    final (client, process) = await start();
    const options = {
      'documentSelector': [
        {'language': 'java', 'scheme': 'jdt', 'pattern': virtualPath},
      ],
      'triggerCharacters': ['.', '@'],
    };
    await process.register('textDocument/completion', options);
    expect(
      client.optionsFor(
        LanguageRequest.completion,
        path: virtualUri,
        languageId: 'java',
        uri: virtualUri,
      ),
      options,
    );
    expect(
      client.supports(
        LanguageRequest.completion,
        path: virtualUri,
        languageId: 'java',
        uri: virtualUri,
      ),
      isTrue,
    );
    expect(
      client.characters(
        LanguageRequest.completion,
        'triggerCharacters',
        path: virtualUri,
        languageId: 'java',
        uri: virtualUri,
      ),
      {'.', '@'},
    );
    for (final uri in [null, 'file:///workspace/Main.java']) {
      expect(
        client.supports(
          LanguageRequest.completion,
          path: virtualUri,
          languageId: 'java',
          uri: uri,
        ),
        isFalse,
      );
      expect(
        client.characters(
          LanguageRequest.completion,
          'triggerCharacters',
          path: virtualUri,
          languageId: 'java',
          uri: uri,
        ),
        isEmpty,
      );
    }
    expect(
      client.supports(
        LanguageRequest.completion,
        path: virtualUri,
        languageId: 'kotlin',
        uri: virtualUri,
      ),
      isFalse,
    );
  });

  test('virtual selectors use any actual scheme, not just JDT', () async {
    final (client, process) = await start();
    await process.register('textDocument/hover', {
      'documentSelector': [
        {'scheme': 'untitled', 'pattern': '/Scratch.java'},
      ],
    });
    expect(
      client.supports(
        LanguageRequest.hover,
        path: '/workspace/Other.java',
        languageId: 'java',
        uri: 'untitled:/Scratch.java',
      ),
      isTrue,
    );
    expect(
      client.supports(
        LanguageRequest.hover,
        path: '/workspace/Other.java',
        languageId: 'java',
        uri: 'jdt:/Scratch.java',
      ),
      isFalse,
    );
  });

  test('scheme-less selectors still match virtual language and path', () async {
    final (client, process) = await start();
    await process.register('textDocument/hover', {
      'documentSelector': [
        {'language': 'java', 'pattern': virtualPath},
      ],
    });
    expect(
      client.supports(
        LanguageRequest.hover,
        path: '/workspace/Other.java',
        languageId: 'java',
        uri: virtualUri,
      ),
      isTrue,
    );
    expect(
      client.supports(
        LanguageRequest.hover,
        path: virtualPath,
        languageId: 'java',
        uri: 'jdt://contents/java.base/java/lang/Other.class',
      ),
      isFalse,
    );
  });

  test(
    'file selectors retain absolute and workspace-relative matching',
    () async {
      for (final (root, path, uri, absolute, windows) in [
        (
          '/workspace',
          '/workspace/src/Main.java',
          'file:///workspace/src/Main.java',
          '/workspace/src/*.java',
          false,
        ),
        (
          r'C:\workspace',
          r'C:\workspace\src\Main.java',
          'file:///C:/workspace/src/Main.java',
          'C:/workspace/src/*.java',
          true,
        ),
      ]) {
        final (client, process) = await start(
          root: root,
          windowsPaths: windows,
        );
        for (final pattern in [absolute, 'src/*.java']) {
          await process.register('textDocument/hover', {
            'documentSelector': [
              {'language': 'java', 'scheme': 'file', 'pattern': pattern},
            ],
          });
          for (final fileUri in [null, uri]) {
            expect(
              client.supports(
                LanguageRequest.hover,
                path: path,
                languageId: 'java',
                uri: fileUri,
              ),
              isTrue,
              reason: '$pattern on $fileUri',
            );
          }
          expect(
            client.supports(
              LanguageRequest.hover,
              path: path,
              languageId: 'java',
              uri: virtualUri,
            ),
            isFalse,
          );
        }
      }
    },
  );

  test('dynamic semantic-token legend uses the virtual URI selector', () async {
    final (client, process) = await start();
    await process.register('textDocument/semanticTokens', {
      'documentSelector': [
        {'language': 'java', 'scheme': 'jdt', 'pattern': '**/*.class'},
      ],
      'full': true,
      'legend': {
        'tokenTypes': ['class', 'method'],
        'tokenModifiers': ['readonly'],
      },
    });
    final legend = client.semanticTokensLegend(
      path: virtualUri,
      languageId: 'java',
      uri: virtualUri,
    );
    expect(legend?.tokenTypes, ['class', 'method']);
    expect(legend?.tokenModifiers, ['readonly']);
    expect(
      client.semanticTokensLegend(path: virtualUri, languageId: 'java'),
      isNull,
    );
  });

  test('static capabilities remain available for virtual documents', () async {
    final (client, _) = await start(
      capabilities: {
        'hoverProvider': true,
        'completionProvider': {
          'triggerCharacters': ['.'],
        },
        'semanticTokensProvider': {
          'full': true,
          'legend': {
            'tokenTypes': ['class'],
            'tokenModifiers': <String>[],
          },
        },
      },
    );
    expect(
      client.optionsFor(
        LanguageRequest.hover,
        path: virtualUri,
        languageId: 'java',
        uri: virtualUri,
      ),
      isEmpty,
    );
    expect(
      client.characters(
        LanguageRequest.completion,
        'triggerCharacters',
        path: virtualUri,
        languageId: 'java',
        uri: virtualUri,
      ),
      {'.'},
    );
    expect(
      client
          .semanticTokensLegend(
            path: virtualUri,
            languageId: 'java',
            uri: virtualUri,
          )
          ?.tokenTypes,
      ['class'],
    );
  });
}
