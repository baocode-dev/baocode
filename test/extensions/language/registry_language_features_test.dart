import 'dart:async';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart' show CancellationToken, VsUri;
import 'package:baocode/extensions/documents/ext_host_document_mirror.dart';
import 'package:baocode/extensions/language/language_feature_document.dart';
import 'package:baocode/extensions/language/language_features_service.dart';
import 'package:baocode/extensions/language/language_providers.dart';
import 'package:baocode/extensions/language/language_selector.dart';
import 'package:baocode/extensions/language/language_types.dart';
import 'package:baocode/extensions/language/marker_service.dart';
import 'package:baocode/extensions/language/registry_language_features.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

LanguageSelector sel(Object json) => LanguageSelector.parse(json)!;

const path = '/w/a.ts';

// --- providers

class Completions extends CompletionItemProvider {
  Completions(this.items, {this.triggerCharacters = const [], this.incomplete = false});

  final List<CompletionItem> Function() items;
  @override
  final List<String> triggerCharacters;
  final bool incomplete;
  final contexts = <CompletionContext>[];
  var disposed = 0;
  CompletionItem? Function(CompletionItem)? resolver;

  @override
  FutureOr<CompletionList?> provideCompletionItems(
    LanguageFeatureDocument model,
    Position position,
    CompletionContext context,
    CancellationToken token,
  ) {
    contexts.add(context);
    return CompletionList(items(), incomplete: incomplete, onDispose: () => disposed++);
  }

  @override
  bool get canResolveCompletionItem => resolver != null;

  @override
  FutureOr<CompletionItem?> resolveCompletionItem(
    CompletionItem item,
    CancellationToken token,
  ) => resolver!(item);
}

CompletionItem item(String label, {String? sortText, CompletionItemKind kind = CompletionItemKind.text}) =>
    CompletionItem(
      label: CompletionItemLabel(label),
      kind: kind,
      insertText: label,
      sortText: sortText,
    );

class Hovers extends HoverProvider {
  Hovers(this.hover);
  final Hover? hover;
  @override
  FutureOr<Hover?> provideHover(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token, [
    HoverContext? context,
  ]) => hover;
}

class Definitions extends DefinitionProvider {
  Definitions(this.links);
  final List<LocationLink> links;
  @override
  FutureOr<List<LocationLink>?> provideDefinition(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) => links;
}

class Actions extends CodeActionProvider {
  Actions(this.actions, {this.kinds});
  final List<CodeAction> actions;
  final List<String>? kinds;
  var calls = 0;
  @override
  List<String>? get providedCodeActionKinds => kinds;
  @override
  FutureOr<CodeActionList?> provideCodeActions(
    LanguageFeatureDocument model,
    Range range,
    CodeActionContext context,
    CancellationToken token,
  ) {
    calls++;
    return CodeActionList(actions);
  }
}

class Signatures extends SignatureHelpProvider {
  Signatures(this.label);
  final String? label;
  @override
  FutureOr<SignatureHelpResult?> provideSignatureHelp(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
    SignatureHelpContext context,
  ) => label == null
      ? null
      : SignatureHelpResult(
          SignatureHelp(
            signatures: [
              SignatureInformation(
                label: label!,
                parameters: const [ParameterInformation(labelOffsets: (2, 3))],
              ),
            ],
          ),
        );
}

class Renamer extends RenameProvider {
  Renamer({this.location, this.edits, this.resolves = true});
  final RenameLocation? location;
  final WorkspaceEdit? edits;
  final bool resolves;
  var editCalls = 0;
  @override
  bool get canResolveRenameLocation => resolves;
  @override
  FutureOr<RenameLocation?> resolveRenameLocation(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) => location;
  @override
  FutureOr<WorkspaceEdit?> provideRenameEdits(
    LanguageFeatureDocument model,
    Position position,
    String newName,
    CancellationToken token,
  ) {
    editCalls++;
    return edits;
  }
}

class Formatter extends DocumentFormattingEditProvider {
  Formatter(this.id, this.text);
  final String id;
  final String text;
  @override
  String? get extensionId => id;
  @override
  FutureOr<List<TextEdit>?> provideDocumentFormattingEdits(
    LanguageFeatureDocument model,
    FormattingOptions options,
    CancellationToken token,
  ) => [TextEdit(Range(1, 1, 1, 1), text)];
}

class RangeFormatter extends DocumentRangeFormattingEditProvider {
  RangeFormatter(this.id);
  final String id;
  final ranges = <Range>[];
  @override
  String? get extensionId => id;
  @override
  FutureOr<List<TextEdit>?> provideDocumentRangeFormattingEdits(
    LanguageFeatureDocument model,
    Range range,
    FormattingOptions options,
    CancellationToken token,
  ) {
    ranges.add(range);
    return [TextEdit(range, 'R:$id')];
  }
}

class Symbols extends DocumentSymbolProvider {
  Symbols(this.symbols);
  final List<DocumentSymbol> symbols;
  @override
  FutureOr<List<DocumentSymbol>?> provideDocumentSymbols(
    LanguageFeatureDocument model,
    CancellationToken token,
  ) => symbols;
}

class Tokens extends DocumentSemanticTokensProvider {
  final results = <SemanticTokensResult>[];
  final lastIds = <String?>[];
  final released = <String?>[];
  @override
  SemanticTokensLegend getLegend() =>
      const SemanticTokensLegend(['variable', 'function'], ['readonly']);
  @override
  FutureOr<SemanticTokensResult?> provideDocumentSemanticTokens(
    LanguageFeatureDocument model,
    String? lastResultId,
    CancellationToken token,
  ) {
    lastIds.add(lastResultId);
    return results.removeAt(0);
  }

  @override
  void releaseDocumentSemanticTokens(String? resultId) => released.add(resultId);
}

DocumentSymbol symbol(String name, int line) => DocumentSymbol(
  name: name,
  kind: SymbolKind.function,
  range: Range(line, 1, line, 5),
  selectionRange: Range(line, 1, line, 2),
);

// --- fixture

late LanguageFeaturesService service;
late MarkerService markers;
late LocalLanguageFeatureDocuments documents;
late RegistryLanguageFeatures features;
late ExtHostDocumentMirror doc;
String? defaultFormatter;
List<String> conflicts = [];
int? conflictPick;

void open(String text) {
  doc = ExtHostDocumentMirror(
    uri: VsUri.file(path),
    languageId: 'typescript',
    text: text,
  );
  documents.add(path, doc);
}

void main() {
  setUp(() {
    service = LanguageFeaturesService();
    markers = MarkerService();
    documents = LocalLanguageFeatureDocuments();
    defaultFormatter = null;
    conflicts = [];
    conflictPick = null;
    features = RegistryLanguageFeatures(
      service: service,
      markers: markers,
      documents: documents,
      defaultFormatterId: (_) => defaultFormatter,
      onFormatterConflict: (message, formatters, doc, mode) async {
        conflicts.add(message);
        return conflictPick;
      },
    );
    open('foo.bar\nbaz qux\n');
  });

  tearDown(() {
    features.dispose();
    markers.dispose();
    service.dispose();
  });

  group('completion', () {
    test('stops at the first provider group with results', () async {
      final empty = Completions(() => []);
      final best = Completions(() => [item('b'), item('a')]);
      final any = Completions(() => [item('z')]);
      service.completionProvider.register(sel('typescript'), empty);
      service.completionProvider.register(sel('typescript'), best);
      service.completionProvider.register(sel('*'), any);

      final list = await features.completion(path, const LspPosition(1, 2));
      expect([for (final i in list.items) i.label], ['a', 'b']);
      expect(empty.contexts.single.triggerKind, CompletionTriggerKind.invoke);
      expect(any.contexts, isEmpty);

      // An empty first group falls through to the next.
      service.completionProvider.register(sel('python'), Completions(() => []));
      best.contexts.clear();
      final only = Completions(() => []);
      final s2 = LanguageFeaturesService();
      s2.completionProvider.register(sel('typescript'), only);
      s2.completionProvider.register(sel('*'), any);
      final f2 = RegistryLanguageFeatures(service: s2, markers: markers, documents: documents);
      final fallback = await f2.completion(path, const LspPosition(1, 2));
      expect([for (final i in fallback.items) i.label], ['z']);
      f2.dispose();
    });

    test('fills default ranges and sort texts, sorts like defaultComparator', () async {
      service.completionProvider.register(
        sel('typescript'),
        Completions(
          () => [
            item('Beta', sortText: '1'),
            item('alpha', sortText: '1'),
            item('gamma', sortText: '0'),
            item('same', kind: CompletionItemKind.keyword),
            item('same', kind: CompletionItemKind.method),
          ],
        ),
      );
      // Line 2 'baz qux', cursor after 'q' (0-based char 5): word 'qux'.
      final list = await features.completion(path, const LspPosition(1, 5));
      expect([for (final i in list.items) '${i.label}:${i.kind.name}'], [
        'gamma:text',
        // Labels compare by code unit, as JavaScript's `<` does.
        'Beta:text',
        'alpha:text',
        'same:method',
        'same:keyword',
      ]);
      final first = list.items.first;
      expect(first.sortText, '0');
      expect(first.textEdit!.range, const LspRange(LspPosition(1, 4), LspPosition(1, 7)));
      expect(first.insertRange, const LspRange(LspPosition(1, 4), LspPosition(1, 5)));
      expect(list.items[3].sortText, 'same');
    });

    test('trigger characters only ask providers they trigger', () async {
      final dot = Completions(() => [item('member')], triggerCharacters: ['.']);
      final plain = Completions(() => [item('word')]);
      service.completionProvider.register(sel('typescript'), dot);
      service.completionProvider.register(sel('typescript'), plain);

      expect(features.completionTriggerCharacters(path), {'.'});
      final list = await features.completion(path, const LspPosition(0, 4), triggerCharacter: '.');
      expect([for (final i in list.items) i.label], ['member']);
      expect(dot.contexts.single.triggerKind, CompletionTriggerKind.triggerCharacter);
      expect(dot.contexts.single.triggerCharacter, '.');
      expect(plain.contexts, isEmpty);

      final none = await features.completion(path, const LspPosition(0, 4), triggerCharacter: '(');
      expect(none.items, isEmpty);
    });

    test('retrigger, isIncomplete, resolve and disposal', () async {
      final provider = Completions(() => [item('x')], incomplete: true)
        ..resolver = (i) => CompletionItem(
          label: i.label,
          kind: i.kind,
          insertText: i.insertText,
          detail: 'resolved',
        );
      service.completionProvider.register(sel('typescript'), provider);

      final first = await features.completion(path, const LspPosition(0, 1));
      expect(first.isIncomplete, isTrue);
      final resolved = await features.resolveCompletion(path, first.items.single);
      expect(resolved.detail, 'resolved');
      expect(resolved.textEdit!.range, first.items.single.textEdit!.range);

      expect(provider.disposed, 0);
      await features.completion(path, const LspPosition(0, 1), retrigger: true);
      expect(provider.contexts.last.triggerKind, CompletionTriggerKind.triggerForIncompleteCompletions);
      expect(provider.disposed, 1); // the previous list
    });
  });

  test('hover: valid hovers of every provider, in order', () async {
    service.hoverProvider.register(
      sel('typescript'),
      Hovers(Hover(const [MarkdownString('second')], range: Range(1, 1, 1, 4))),
    );
    service.hoverProvider.register(sel('typescript'), Hovers(const Hover([MarkdownString('no range')])));
    service.hoverProvider.register(sel('typescript'), Hovers(Hover(const [], range: Range(1, 1, 1, 2))));
    service.hoverProvider.register(
      sel('typescript'),
      Hovers(Hover(const [MarkdownString('first')], range: Range(1, 5, 1, 8))),
    );
    final hover = await features.hover(path, const LspPosition(0, 5));
    expect(hover!.markdown, 'first\n\n---\n\nsecond');
    expect(hover.range, const LspRange(LspPosition(0, 4), LspPosition(0, 7)));
  });

  test('definition: merged, sorted, deduped, internal schemes dropped', () async {
    final other = VsUri.file('/w/b.ts');
    service.definitionProvider.register(
      sel('typescript'),
      Definitions([
        LocationLink(uri: other, range: Range(3, 1, 3, 2)),
        LocationLink(uri: VsUri.file(path), range: Range(2, 1, 2, 4)),
      ]),
    );
    service.definitionProvider.register(
      sel('typescript'),
      Definitions([
        LocationLink(uri: other, range: Range(3, 1, 3, 2)),
        LocationLink(uri: other, range: Range(1, 1, 1, 2), targetSelectionRange: Range(1, 1, 1, 2)),
        LocationLink(uri: VsUri.parse('walkThroughSnippet:/x'), range: Range(1, 1, 1, 1)),
      ]),
    );
    final locations = await features.definition(path, const LspPosition(0, 0));
    expect([for (final l in locations) '${l.uri}@${l.range.start.line}'], [
      'file:///w/a.ts@1',
      'file:///w/b.ts@0',
      'file:///w/b.ts@2',
    ]);
    expect(locations[1].selectionRange, isNotNull);
  });

  test('BOM documents: LSP coordinates are raw, providers see the model', () async {
    open('﻿foo bar');
    Position? seen;
    service.hoverProvider.register(sel('typescript'), _PositionHover((p) => seen = p));
    final hover = await features.hover(path, const LspPosition(0, 5));
    // Raw column 6 (one-based) is model column 5 behind the BOM.
    expect((seen!.lineNumber, seen!.column), (1, 5));
    // The model range 1..4 is raw 1..4 shifted by the BOM.
    expect(hover!.range, const LspRange(LspPosition(0, 1), LspPosition(0, 4)));

    markers.changeOne('ts', VsUri.file(path), [
      MarkerData(
        severity: MarkerSeverity.warning,
        message: 'w',
        startLineNumber: 1,
        startColumn: 5,
        endLineNumber: 1,
        endColumn: 8,
        tags: [MarkerTag.unnecessary],
      ),
    ]);
    final diagnostic = features.diagnosticsFor(path).single;
    expect(diagnostic.range, const LspRange(LspPosition(0, 5), LspPosition(0, 8)));
    expect(diagnostic.severity, LspDiagnosticSeverity.warning);
    expect(diagnostic.unnecessary, isTrue);
    expect(features.allDiagnostics.keys, [path]);
  });

  test('markers and registry changes notify listeners', () async {
    var notified = 0;
    features.addListener(() => notified++);
    final registration = service.hoverProvider.register(sel('typescript'), Hovers(null));
    expect(notified, 1);
    registration.dispose();
    expect(notified, 2);
    markers.changeOne('o', VsUri.file(path), [
      MarkerData(
        severity: MarkerSeverity.error,
        message: 'e',
        startLineNumber: 1,
        startColumn: 1,
        endLineNumber: 1,
        endColumn: 2,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 3);
  });

  group('code actions', () {
    final diag = MarkerData(
      severity: MarkerSeverity.error,
      message: 'e',
      startLineNumber: 1,
      startColumn: 1,
      endLineNumber: 1,
      endColumn: 2,
    );

    test('sorted: diagnostics first, preferred first, AI last', () async {
      service.codeActionProvider.register(
        sel('typescript'),
        Actions([
          CodeAction(title: 'ai', kind: 'quickfix', isAI: true, diagnostics: [diag]),
          CodeAction(title: 'plain', kind: 'refactor'),
          CodeAction(title: 'preferred', kind: 'refactor', isPreferred: true),
          CodeAction(title: 'fix', kind: 'quickfix', diagnostics: [diag]),
          CodeAction(title: 'preferred fix', kind: 'quickfix', isPreferred: true, diagnostics: [diag]),
        ]),
      );
      final actions = await features.codeActions(
        path,
        const LspRange(LspPosition(0, 0), LspPosition(0, 1)),
      );
      expect([for (final a in actions) a.title], ['preferred fix', 'fix', 'preferred', 'plain', 'ai']);
      expect(actions.first.diagnostics.single.message, 'e');
    });

    test('only: providers and actions filtered by kind', () async {
      final refactor = Actions(const [
        CodeAction(title: 'extract', kind: 'refactor.extract'),
        CodeAction(title: 'inline', kind: 'refactor.inline'),
      ], kinds: ['refactor']);
      final quickfix = Actions(const [CodeAction(title: 'fix', kind: 'quickfix')], kinds: ['quickfix']);
      final source = Actions(const [CodeAction(title: 'organize', kind: 'source.organizeImports')]);
      service.codeActionProvider.register(sel('typescript'), refactor);
      service.codeActionProvider.register(sel('typescript'), quickfix);
      service.codeActionProvider.register(sel('typescript'), source);
      const range = LspRange(LspPosition(0, 0), LspPosition(0, 0));

      final extract = await features.codeActions(path, range, only: ['refactor.extract']);
      expect([for (final a in extract) a.title], ['extract']);
      expect(quickfix.calls, 0); // its kinds cannot include refactor.extract
      expect(refactor.calls, 1);

      final organize = await features.codeActions(path, range, only: ['source']);
      expect([for (final a in organize) a.title], ['organize']);

      final both = await features.codeActions(path, range, only: ['quickfix', 'source']);
      expect([for (final a in both) a.title]..sort(), ['fix', 'organize']);
    });

    test('filtersAction and mayIncludeActionsOfKind', () {
      const filter = CodeActionFilter(include: HierarchicalKind('refactor'));
      expect(mayIncludeActionsOfKind(filter, const HierarchicalKind('refactor.extract')), isTrue);
      expect(mayIncludeActionsOfKind(filter, const HierarchicalKind('')), isTrue);
      expect(mayIncludeActionsOfKind(filter, const HierarchicalKind('quickfix')), isFalse);
      expect(mayIncludeActionsOfKind(const CodeActionFilter(), HierarchicalKind.source), isFalse);
      expect(filtersAction(filter, const CodeAction(title: 'x')), isFalse);
      expect(filtersAction(filter, const CodeAction(title: 'x', kind: 'refactor.move')), isTrue);
      expect(
        filtersAction(
          const CodeActionFilter(onlyIncludePreferredActions: true),
          const CodeAction(title: 'x'),
        ),
        isFalse,
      );
    });
  });

  test('signature help: the first provider with an answer', () async {
    service.signatureHelpProvider.register(sel('typescript'), Signatures('second(a)'));
    service.signatureHelpProvider.register(sel('typescript'), Signatures(null));
    final help = await features.signatureHelp(path, const LspPosition(0, 0));
    expect(help!.signatures.single.label, 'second(a)');
    expect(help.signatures.single.parameters.single.label, 'c');
  });

  group('rename', () {
    test('resolve skips rejects, edits start at the resolving provider', () async {
      final resolving = Renamer(
        location: RenameLocation(Range(1, 1, 1, 4), 'foo'),
        edits: WorkspaceEdit([
          WorkspaceTextEdit(resource: VsUri.file(path), textEdit: TextEdit(Range(1, 1, 1, 4), 'x')),
        ]),
      );
      final rejecting = Renamer(location: RenameLocation(Range(1, 1, 1, 1), '', rejectReason: 'no'));
      service.renameProvider.register(sel('typescript'), resolving);
      service.renameProvider.register(sel('typescript'), rejecting); // newest first

      final prepared = await features.prepareRename(path, const LspPosition(0, 1));
      expect(prepared!.placeholder, 'foo');
      expect(prepared.range, const LspRange(LspPosition(0, 0), LspPosition(0, 3)));

      final edit = await features.rename(path, const LspPosition(0, 1), 'x');
      expect(edit!.changes['file:///w/a.ts']!.single.newText, 'x');
      expect(rejecting.editCalls, 0);
    });

    test('word fallback and next provider on no result', () async {
      final empty = Renamer(resolves: false);
      final fallback = Renamer(
        resolves: false,
        edits: WorkspaceEdit([
          WorkspaceTextEdit(resource: VsUri.file(path), textEdit: TextEdit(Range(2, 5, 2, 8), 'y')),
        ]),
      );
      service.renameProvider.register(sel('typescript'), fallback);
      service.renameProvider.register(sel('typescript'), empty);

      final prepared = await features.prepareRename(path, const LspPosition(1, 5));
      expect(prepared!.placeholder, 'qux');
      final edit = await features.rename(path, const LspPosition(1, 5), 'y');
      expect(edit!.changes.values.single.single.range.start, const LspPosition(1, 4));
      expect((empty.editCalls, fallback.editCalls), (1, 1));
    });
  });

  group('format', () {
    Future<List<String>> format({LspRange? range}) async => [
      for (final edit in await features.format(path, range: range, tabSize: 2, insertSpaces: true))
        edit.newText,
    ];

    test('one formatter is used; several need a default or a pick', () async {
      service.documentFormattingEditProvider.register(sel('typescript'), Formatter('a.fmt', 'A'));
      expect(await format(), ['A']);

      service.documentFormattingEditProvider.register(sel('typescript'), Formatter('b.fmt', 'B'));
      expect(await format(), isEmpty);
      expect(conflicts.single, contains('multiple formatters'));

      conflictPick = 1;
      expect(await format(), ['A']); // ordered: b.fmt (newest), a.fmt

      defaultFormatter = 'B.FMT';
      expect(await format(), ['B']);
    });

    test('range formatters stand in for document formatters', () async {
      final range = RangeFormatter('r.fmt');
      service.documentRangeFormattingEditProvider.register(sel('typescript'), range);
      expect(features.supports(path, LanguageRequest.format), isTrue);
      expect(await format(), ['R:r.fmt']);
      final full = range.ranges.single;
      expect((full.startLineNumber, full.startColumn, full.endLineNumber, full.endColumn), (1, 1, 3, 1));

      // The same extension's document formatter hides its range formatter.
      service.documentFormattingEditProvider.register(sel('typescript'), Formatter('r.fmt', 'D'));
      expect(await format(), ['D']);

      expect(
        await format(range: const LspRange(LspPosition(1, 0), LspPosition(1, 3))),
        ['R:r.fmt'],
      );
      expect(range.ranges.last.startLineNumber, 2);
    });
  });

  test('document symbols: every provider, roots sorted by start', () async {
    service.documentSymbolProvider.register(sel('typescript'), Symbols([symbol('b', 2)]));
    service.documentSymbolProvider.register(sel('typescript'), Symbols([symbol('c', 3), symbol('a', 1)]));
    final symbols = await features.documentSymbols(path);
    expect([for (final s in symbols) s.name], ['a', 'b', 'c']);
    expect(symbols.first.kind, LspSymbolKind.function);
  });

  test('semantic tokens: full, then edits against the last result', () async {
    final tokens = Tokens()
      ..results.addAll([
        SemanticTokens(Uint32List.fromList([0, 0, 3, 0, 0, 1, 4, 3, 1, 1]), resultId: '1'),
        SemanticTokensEdits([SemanticTokensEdit(5, 5, Uint32List.fromList([0, 4, 3, 0, 0]))], resultId: '2'),
      ]);
    service.documentSemanticTokensProvider.register(sel('typescript'), tokens);
    final first = await features.semanticTokens(path);
    expect([for (final t in first!) (t.line, t.character, t.length, t.type, t.modifiers.join(','))], [
      (0, 0, 3, 'variable', ''),
      (1, 4, 3, 'function', 'readonly'),
    ]);
    final second = await features.semanticTokens(path);
    expect(tokens.lastIds, [null, '1']);
    expect(tokens.released, ['1']);
    expect([for (final t in second!) (t.line, t.character, t.type)], [
      (0, 0, 'variable'),
      (0, 4, 'variable'),
    ]);
  });

  test('applySemanticTokensEdits', () {
    final data = Uint32List.fromList([1, 2, 3, 4, 5]);
    final result = RegistryLanguageFeatures.applySemanticTokensEdits(data, [
      SemanticTokensEdit(1, 2, Uint32List.fromList([9])),
      SemanticTokensEdit(5, 0, Uint32List.fromList([7, 7])),
    ]);
    expect(result, [1, 9, 4, 5, 7, 7]);
  });

  test('requestApplyEdit goes to the editor and completes', () async {
    expect(await features.requestApplyEdit(const WorkspaceEdit([])), isFalse);
    features.workspaceEdits.listen((request) => request.complete(true));
    final applied = await features.requestApplyEdit(
      WorkspaceEdit([
        WorkspaceTextEdit(resource: VsUri.file(path), textEdit: TextEdit(Range(1, 1, 1, 1), 'x')),
        WorkspaceFileEdit(newResource: VsUri.file('/w/new.ts')),
      ]),
    );
    expect(applied, isTrue);
  });
}

class _PositionHover extends HoverProvider {
  _PositionHover(this.onPosition);
  final void Function(Position) onPosition;
  @override
  FutureOr<Hover?> provideHover(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token, [
    HoverContext? context,
  ]) {
    onPosition(position);
    return Hover(const [MarkdownString('h')], range: Range(1, 1, 1, 4));
  }
}
