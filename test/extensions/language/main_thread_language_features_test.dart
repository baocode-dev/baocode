/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The provider round-trips of `MainThreadLanguageFeatures`: an in-memory
// RPC pair drives the actor with the exact JSON the extension host sends and
// answers the `$provideXxx` calls the providers make back.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadLanguageFeatures.ts and the
// extension host's adapters in src/vs/workbench/api/common/
// extHostLanguageFeatures.ts (what each `$provideXxx` is answered with, and
// what its caller then expects back).
//
// Deviations: the extension host is a fake that answers from a table, so the
// tests pin the wire shapes rather than a real extension's behavior (the
// `exthost` test does that).

import 'dart:async';
import 'dart:typed_data';

import 'package:bao_editor/monaco/vs/editor/common/languages/language_configuration.dart'
    show IndentAction;
import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/documents/ext_host_document_mirror.dart';
import 'package:baocode/extensions/language/language_customers.dart';
import 'package:baocode/extensions/language/language_dto.dart' show hoverIdOf;
import 'package:baocode/extensions/language/language_feature_document.dart';
import 'package:baocode/extensions/language/language_selector.dart';
import 'package:baocode/extensions/language/language_types.dart';
import 'package:baocode/extensions/language/marker_service.dart';
import 'package:baocode/extensions/language/registry_language_features.dart';
import 'package:baocode/extensions/main_thread/main_thread_diagnostics.dart';
import 'package:baocode/extensions/main_thread/main_thread_language_features.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two ends of an in-memory message channel.
final class _Pipe implements MessagePassingProtocol {
  late _Pipe other;
  void Function(Uint8List)? _listener;

  @override
  set onMessage(void Function(Uint8List message)? listener) =>
      _listener = listener;

  @override
  void send(Uint8List message) =>
      scheduleMicrotask(() => other._listener?.call(message));

  static (_Pipe, _Pipe) pair() {
    final a = _Pipe();
    final b = _Pipe();
    a.other = b;
    b.other = a;
    return (a, b);
  }
}

/// The fake extension host: answers `$provideXxx` from [answers] and records
/// every call.
final class _FakeExtHost implements RpcActor {
  final calls = <String, List<List<Object?>>>{};

  /// Keyed `$method`; the answer, or a function of the arguments.
  final answers = <String, Object? Function(List<Object?> args)>{};

  @override
  FutureOr<Object?> invoke(String method, List<Object?> args) {
    calls.putIfAbsent(method, () => []).add(args);
    final answer = answers[method];
    if (answer == null) return null;
    return answer(args);
  }
}

/// Monaco's ranges and positions compare with `equalsRange`, not `==`.
Matcher _sameRange(Range expected) => predicate<IRange?>(
  (actual) => Range.equalsRanges(actual, expected),
  'a range equal to $expected',
);

Matcher _samePosition(Position expected) => predicate<IPosition?>(
  (actual) => Position.equalsPositions(actual, expected),
  'a position equal to $expected',
);

/// A document with BOM-free text, so model and raw coordinates agree.
LanguageFeatureDocument _document(String text) => ExtHostDocumentMirror(
  uri: VsUri.file('/w/a.ts'),
  languageId: 'typescript',
  text: text,
);

void main() {
  late LanguageFeatureRoot root;
  late _FakeExtHost host;
  late RpcProtocol extHostRpc;
  late RpcProtocol mainRpc;
  late LanguageFeatureDocument document;

  /// Sets the registries up with a session and a document.
  void open([String text = 'const x = 1;\nconsole.log(x);\n']) {
    document = _document(text);
    root = LanguageFeatureRoot(languageIds: const ['typescript']);
    root.documents = LocalLanguageFeatureDocuments()
      ..add('/w/a.ts', document);
    final (a, b) = _Pipe.pair();
    mainRpc = RpcProtocol(a, actorNames: proxyIdentifierNames);
    extHostRpc = RpcProtocol(b, actorNames: proxyIdentifierNames);
    host = _FakeExtHost();
    extHostRpc.set(ExtHostContext.extHostLanguageFeatures.nid, host);
    mainRpc.set(
      MainContext.mainThreadLanguageFeatures.nid,
      MainThreadLanguageFeaturesActor(
        MainThreadLanguageFeatures(root: root, proxy: mainRpc),
      ),
    );
    mainRpc.set(
      MainContext.mainThreadDiagnostics.nid,
      MainThreadDiagnosticsActor(
        MainThreadDiagnostics(
          markers: root.markers,
          proxy: mainRpc,
          extensionHostId: 'local',
        ),
      ),
    );
  }

  /// Calls the actor the way the extension host does.
  Future<Object?> call(String method, List<Object?> args) =>
      extHostRpc.call(
        MainContext.mainThreadLanguageFeatures.nid,
        method,
        args,
      );

  /// A `hint`-style model position/range.
  Map<String, Object?> position(int line, int column) => {
    'lineNumber': line,
    'column': column,
  };
  Map<String, Object?> range(
    int sl,
    int sc,
    int el,
    int ec,
  ) => {
    'startLineNumber': sl,
    'startColumn': sc,
    'endLineNumber': el,
    'endColumn': ec,
  };

  setUp(open);
  tearDown(() {
    root.dispose();
  });

  group('hover', () {
    test('round-trips the DTO and keeps the extension hover id', () async {
      host.answers[r'$provideHover'] = (args) => {
        'id': 7,
        'contents': [
          {'value': '**const x**: number'},
        ],
        'range': range(1, 7, 1, 8),
      };
      await call(r'$registerHoverProvider', [
        1,
        [
          {'language': 'typescript'},
        ],
      ]);
      final provider = root.service.hoverProvider.allNoModel().single;
      final hover = await provider.provideHover(
        document,
        Position(1, 7),
        CancellationToken.none,
      );
      expect(hover!.contents.single.value, '**const x**: number');
      expect(hover.range, _sameRange(Range(1, 7, 1, 8)));
      // The extension host sees model coordinates, not the editor's.
      expect(host.calls[r'$provideHover']!.single[2], position(1, 7));
      expect(hoverIdOf(hover), 7);
    });
  });

  group('completion', () {
    test('inflates the compact ISuggestDataDto and resolves by cache id',
        () async {
      host.answers[r'$provideCompletionItems'] = (args) => {
        'a': {
          'insert': range(1, 7, 1, 7),
          'replace': range(1, 7, 1, 8),
        },
        'b': [
          {
            'a': 'x',
            'b': 3, // languages.CompletionItemKind.Field
            'c': 'const x',
            'h': 'x',
            'i': 4,
            'k': r'$',
            'm': [1],
            'o': 'my.command',
            'x': [11, 0],
          },
        ],
        'x': 11,
      };
      host.answers[r'$resolveCompletionItem'] = (args) => {
        'a': 'x',
        'd': {'value': 'the *x*'},
        'h': 'x',
        'c': 'const x: number',
      };
      await call(r'$registerCompletionsProvider', [
        2,
        [
          {'language': 'typescript'},
        ],
        const [r'$'],
        true,
        {'value': 'fake.ts'},
      ]);
      final provider = root.service.completionProvider.allNoModel().single;
      expect(provider.triggerCharacters, [r'$']);
      expect(provider.canResolveCompletionItem, isTrue);
      final list = await provider.provideCompletionItems(
        document,
        Position(1, 7),
        CompletionContext(CompletionTriggerKind.invoke),
        CancellationToken.none,
      );
      final item = list!.suggestions.single;
      expect(item.label.label, 'x');
      expect(item.kind, CompletionItemKind.field);
      expect(item.detail, 'const x');
      expect(item.insertText, 'x');
      expect(item.isSnippet, isTrue);
      expect(item.commitCharacters, [r'$']);
      expect(item.isDeprecated, isTrue);
      expect(item.command!.id, 'my.command');
      expect(item.range!.replace, _sameRange(Range(1, 7, 1, 8)));

      final resolved = await provider.resolveCompletionItem(
        item,
        CancellationToken.none,
      );
      expect(resolved!.documentation!.value, 'the *x*');
      expect(resolved.detail, 'const x: number');
      // The cache id of the item went back, not the whole item.
      expect(host.calls[r'$resolveCompletionItem']!.single[1], [11, 0]);

      // Disposing the list releases the extension's cache.
      list.dispose();
      await pumpEventQueue();
      expect(host.calls[r'$releaseCompletionItems']!.single, [2, 11]);
    });
  });

  group('code lens', () {
    test('forwards the cache id, resolves through it, emits change events',
        () async {
      host.answers[r'$provideCodeLenses'] = (args) => {
        'cacheId': 3,
        'lenses': [
          {
            'cacheId': [3, 0],
            'range': range(1, 1, 1, 7),
          },
        ],
      };
      host.answers[r'$resolveCodeLens'] = (args) => {
        'cacheId': [3, 0],
        'range': range(1, 1, 1, 7),
        'command': {'id': 'editor.action.showReferences', 'title': '2 refs'},
      };
      await call(r'$registerCodeLensSupport', [
        4,
        [
          {'language': 'typescript'},
        ],
        40,
      ]);
      final provider = root.service.codeLensProvider.allNoModel().single;
      var changed = 0;
      provider.onDidChange!.listen((_) => changed++);
      await call(r'$emitCodeLensEvent', [40, null]);
      expect(changed, 1);

      final list = await provider.provideCodeLenses(
        document,
        CancellationToken.none,
      );
      final lens = list!.lenses.single;
      expect(lens.command, isNull);
      final resolved = await provider.resolveCodeLens(
        document,
        lens,
        CancellationToken.none,
      );
      expect(resolved!.command!.title, '2 refs');
      expect(host.calls[r'$resolveCodeLens']!.single[1], {
        'cacheId': [3, 0],
        'range': range(1, 1, 1, 7),
      });
    });
  });

  group('inlay hints', () {
    test('round-trips label parts, positions and text edits', () async {
      host.answers[r'$provideInlayHints'] = (args) => {
        'cacheId': 5,
        'hints': [
          {
            'cacheId': [5, 0],
            'label': [
              {'label': ': '},
              {
                'label': 'number',
                'location': {
                  'uri': VsUri.file('/w/b.ts').toJson(),
                  'range': range(2, 1, 2, 3),
                },
              },
            ],
            'position': position(1, 12),
            'kind': 1,
            'paddingLeft': true,
            'tooltip': {'value': 'inferred'},
          },
        ],
      };
      await call(r'$registerInlayHintsProvider', [
        6,
        [
          {'language': 'typescript'},
        ],
        true,
        60,
        'fake hints',
      ]);
      final provider = root.service.inlayHintsProvider.allNoModel().single;
      expect(provider.displayName, 'fake hints');
      final list = await provider.provideInlayHints(
        document,
        Range(1, 1, 2, 1),
        CancellationToken.none,
      );
      final hint = list!.hints.single;
      expect(hint.text, ': number');
      expect(hint.kind, InlayHintKind.type);
      expect(hint.paddingLeft, isTrue);
      expect(hint.tooltip!.value, 'inferred');
      expect(hint.label[1].location!.uri.fsPath(), '/w/b.ts');
      expect(hint.position, _samePosition(Position(1, 12)));
      expect(host.calls[r'$provideInlayHints']!.single[2], range(1, 1, 2, 1));
    });
  });

  group('diagnostics', () {
    test(r'$changeMany fills the owner and the host id, $clear removes it',
        () async {
      final uri = VsUri.file('/w/a.ts');
      await extHostRpc.call(
        MainContext.mainThreadDiagnostics.nid,
        r'$changeMany',
        [
          'ts',
          [
            [
              uri.toJson(),
              [
                {
                  'startLineNumber': 2,
                  'startColumn': 1,
                  'endLineNumber': 2,
                  'endColumn': 6,
                  'message': 'undefined name',
                  'severity': 8,
                  'source': 'ts',
                  'code': '2304',
                  'tags': [1],
                },
              ],
            ],
          ],
        ],
      );
      final markers = root.markers.read();
      expect(markers, hasLength(1));
      expect(markers.single.message, 'undefined name');
      expect(markers.single.severity, MarkerSeverity.error);
      expect(markers.single.code!.value, '2304');
      expect(markers.single.tags, [MarkerTag.unnecessary]);
      expect(markers.single.owner, 'ts');
      expect(markers.single.origin, isNotNull);

      await extHostRpc.call(MainContext.mainThreadDiagnostics.nid, r'$clear', [
        'ts',
      ]);
      expect(root.markers.read(), isEmpty);
    });
  });

  group('registration', () {
    test('two hosts (a remote project\'s and this machine\'s) keep their '
        'handles apart, and each session ends alone', () async {
      // The second host, with handles of its own.
      final (a, b) = _Pipe.pair();
      final otherMain = RpcProtocol(a, actorNames: proxyIdentifierNames);
      final otherHost = RpcProtocol(b, actorNames: proxyIdentifierNames)
        ..set(ExtHostContext.extHostLanguageFeatures.nid, _FakeExtHost());
      root.beginSession(mainRpc);
      root.beginSession(otherMain);
      otherMain.set(
        MainContext.mainThreadLanguageFeatures.nid,
        MainThreadLanguageFeaturesActor(
          MainThreadLanguageFeatures(root: root, proxy: otherMain),
        ),
      );
      final selector = [
        {'language': 'typescript'},
      ];
      await call(r'$registerHoverProvider', [1, selector]);
      await otherHost.call(
        MainContext.mainThreadLanguageFeatures.nid,
        r'$registerHoverProvider',
        [1, selector],
      );
      expect(root.service.hoverProvider.allNoModel(), hasLength(2));
      await call(r'$unregister', [1]);
      expect(root.service.hoverProvider.allNoModel(), hasLength(1));
      await call(r'$registerHoverProvider', [1, selector]);
      root.endSession(otherMain);
      expect(root.service.hoverProvider.allNoModel(), hasLength(1));
      expect(root.hasSession, isTrue);
      root.endSession(mainRpc);
      expect(root.service.hoverProvider.allNoModel(), isEmpty);
      expect(root.hasSession, isFalse);
    });

    test('a selector activates its languages once, and registers', () async {
      final activated = <String>[];
      root.activation = (selector) async {
        activated.add((selector as LanguageIdSelector).languageId);
        return;
      };
      await call(r'$registerDefinitionSupport', [
        7,
        [
          {'language': 'typescript'},
          {'language': 'javascript'},
        ],
      ]);
      expect(activated, ['typescript', 'javascript']);
      expect(root.service.definitionProvider.allNoModel(), hasLength(1));

      // A second call with the same languages activates nothing new.
      await call(r'$registerReferenceSupport', [
        8,
        [
          {'language': 'typescript'},
        ],
      ]);
      expect(activated, ['typescript', 'javascript']);

      // $unregister removes it; the editor no longer sees a provider.
      await call(r'$unregister', [7]);
      expect(root.service.definitionProvider.allNoModel(), isEmpty);
    });

    test('the capability gate drops a blocked provider', () async {
      final blocked = <String>[];
      root.gate =
          ({required extensionId, required languageId, required feature}) =>
              languageId != 'typescript';
      root.onBlocked = (feature, extensionId, languageId) =>
          blocked.add('$feature/$languageId');
      // The gate is per extension: an actor that knows its extension.
      mainRpc.set(
        MainContext.mainThreadLanguageFeatures.nid,
        MainThreadLanguageFeaturesActor(
          MainThreadLanguageFeatures(
            root: root,
            proxy: mainRpc,
            extensionId: 'acme.ext',
          ),
        ),
      );
      await call(r'$registerHoverProvider', [
        9,
        [
          {'language': 'typescript'},
        ],
      ]);
      expect(root.service.hoverProvider.allNoModel(), isEmpty);
      expect(blocked, ['hoverProvider/typescript']);
    });
  });

  group('semantic tokens', () {
    test('decodes the encoded full result and releases by id', () async {
      // encodeSemanticTokensDto({id: 4, type: 'full', data: [1,2,3]}).
      final bytes = ByteData(24);
      for (final (index, value) in [4, 1, 3, 1, 2, 3].indexed) {
        bytes.setUint32(index * 4, value, Endian.little);
      }
      host.answers[r'$provideDocumentSemanticTokens'] = (args) =>
          RpcBuffer(bytes.buffer.asUint8List());
      await call(r'$registerDocumentSemanticTokensProvider', [
        10,
        [
          {'language': 'typescript'},
        ],
        {
          'tokenTypes': ['variable', 'function'],
          'tokenModifiers': ['declaration'],
        },
        null,
      ]);
      final provider =
          root.service.documentSemanticTokensProvider.allNoModel().single;
      expect(provider.getLegend().tokenTypes, ['variable', 'function']);
      final result = await provider.provideDocumentSemanticTokens(
        document,
        null,
        CancellationToken.none,
      );
      final tokens = result! as SemanticTokens;
      expect(tokens.resultId, '4');
      expect(tokens.data, Uint32List.fromList([1, 2, 3]));
      provider.releaseDocumentSemanticTokens(tokens.resultId);
      await pumpEventQueue();
      expect(host.calls[r'$releaseDocumentSemanticTokens']!.single, [10, 4]);
    });
  });

  group('language configuration', () {
    test('revives the DTO into this app\'s configuration', () async {
      await call(r'$setLanguageConfiguration', [
        12,
        'typescript',
        {
          'comments': {
            'lineComment': '//',
            'blockComment': {'open': '/*', 'close': '*/'},
          },
          'brackets': [
            ['{', '}'],
          ],
          'wordPattern': {'pattern': '[a-zA-Z]+', 'flags': 'i'},
          'indentationRules': {
            'increaseIndentPattern': r'\{$',
            'decreaseIndentPattern': r'^\}',
          },
          'autoClosingPairs': [
            {'open': '"', 'close': '"', 'notIn': ['string']},
          ],
          'onEnterRules': [
            {
              'beforeText': r'\{$',
              'action': {'indentAction': 'indent'},
            },
          ],
        },
      ]);
      final configuration = root.languageConfigurationOf('typescript')!;
      expect(configuration.comments!.lineComment!.comment, '//');
      expect(configuration.comments!.blockComment, ('/*', '*/'));
      expect(configuration.brackets, [('{', '}')]);
      expect(configuration.wordPattern!.pattern, '[a-zA-Z]+');
      expect(configuration.indentationRules!.increaseIndentPattern.pattern, r'\{$');
      expect(configuration.autoClosingPairs!.single.notIn, ['string']);
      expect(
        configuration.onEnterRules!.single.action.indentAction.index,
        IndentAction.indent.index,
      );

      // $unregister drops it again.
      await call(r'$unregister', [12]);
      expect(root.languageConfigurationOf('typescript'), isNull);
    });
  });

}
