/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The editor's [LanguageFeatures], answered from the provider registries the
// way VS Code's editor contributions query and merge them.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/contrib/suggest/browser/suggest.ts (`provideSuggestionItems`,
//   `defaultComparator`) and suggestModel.ts (trigger-character provider
//   filter, `TriggerForIncompleteCompletions`),
// src/vs/editor/contrib/hover/browser/getHover.ts (`getHoversPromise`,
//   `isValid`),
// src/vs/editor/contrib/gotoSymbol/browser/goToSymbol.ts (`getLocationLinks`,
//   `shouldIncludeLocationLink`) and referencesModel.ts (sort and dedupe),
// src/vs/editor/contrib/format/browser/format.ts
//   (`getRealAndSyntheticDocumentFormattersOrdered`, `FormattingConflicts`,
//   `getOnTypeFormattingEdits`) and
//   src/vs/workbench/contrib/format/browser/formatActionsMultiple.ts
//   (`DefaultFormatter._analyzeFormatter`),
// src/vs/editor/contrib/codeAction/browser/codeAction.ts (`getCodeActions`,
//   `ManagedCodeActionSet.codeActionsComparator`) and common/types.ts
//   (`mayIncludeActionsOfKind`, `filtersAction`), base/common/
//   hierarchicalKind.ts,
// src/vs/editor/contrib/parameterHints/browser/provideSignatureHelp.ts,
// src/vs/editor/contrib/rename/browser/rename.ts (`RenameSkeleton`),
// src/vs/editor/contrib/documentSymbols/browser/outlineModel.ts
//   (`OutlineModel.create`, `getTopLevelSymbols`),
// src/vs/editor/contrib/semanticTokens/common/getSemanticTokens.ts,
// src/vs/editor/contrib/codelens/browser/codelens.ts (`getCodeLensModel`),
// src/vs/editor/contrib/inlayHints/browser/inlayHints.ts
//   (`InlayHintsFragments.create`),
// src/vs/editor/contrib/links/browser/getLinks.ts (`getLinks`,
//   `LinksList._union`),
// src/vs/editor/contrib/colorPicker/browser/color.ts (`getColors`),
// src/vs/editor/contrib/folding/browser/syntaxRangeProvider.ts
//   (`collectSyntaxRanges`),
// src/vs/editor/contrib/smartSelect/browser/smartSelect.ts
//   (`provideSelectionRanges`),
// src/vs/editor/contrib/wordHighlighter/browser/wordHighlighter.ts
//   (`getOccurrencesAtPosition`),
// src/vs/editor/contrib/linkedEditing/browser/linkedEditing.ts
//   (`getLinkedEditingRanges`),
// src/vs/workbench/contrib/search/common/search.ts (`getWorkspaceSymbols`).
//
// Deviations:
// - The [LanguageFeatures] methods speak zero-based raw editor coordinates
//   (LSP shapes); the extra methods speak one-based editor coordinates
//   (bao_editor `Position`/`Range` over the raw text). Providers always get
//   and return model coordinates; documents BaoCode has not opened are
//   assumed to have no BOM.
// - No snippet provider, no word-based or bracket selection ranges, no
//   `computeMoreMinimalEdits` (formatting edits are returned as given), no
//   inline-completion grouping (`yieldsToGroupIds`) or debouncing.
// - Results that hold provider resources are kept until the next request of
//   the same kind for the same document (completion, code actions, code
//   lenses, inlay hints, links, signature help), then disposed.
// - Provider errors read as "no result" (`onUnexpectedExternalError`), and
//   are reported to [RegistryLanguageFeatures.onProviderError].

import 'dart:async';
import 'dart:typed_data';

import 'package:bao_editor/monaco/vs/base/common/platform.dart' as platform;
import 'package:bao_exthost/bao_exthost.dart' show CancellationToken, VsUri;
import 'package:flutter/foundation.dart';

import '../../ide/lsp/language_features.dart';
import '../../ide/lsp/lsp_protocol.dart';
import 'language_feature_document.dart';
import 'language_feature_registry.dart';
import 'language_features_service.dart';
import 'language_providers.dart';
import 'language_types.dart';
import 'marker_service.dart';
import 'word_helper.dart';

/// How [RegistryLanguageFeatures] finds documents and names files.
abstract interface class LanguageFeatureDocuments {
  /// The synchronized document of an absolute [path], if it is open.
  LanguageFeatureDocument? documentForPath(String path);

  /// The open document with [uri], if any.
  LanguageFeatureDocument? documentForUri(VsUri uri);

  VsUri uriForPath(String path);

  /// The absolute path [uri] names in the editor's file system; null for
  /// other schemes.
  String? pathForUri(VsUri uri);
}

/// [LanguageFeatureDocuments] over local `file:` URIs and a path map.
class LocalLanguageFeatureDocuments implements LanguageFeatureDocuments {
  final Map<String, LanguageFeatureDocument> _byPath = {};

  void add(String path, LanguageFeatureDocument document) =>
      _byPath[path] = document;

  void remove(String path) => _byPath.remove(path);

  @override
  LanguageFeatureDocument? documentForPath(String path) => _byPath[path];

  @override
  LanguageFeatureDocument? documentForUri(VsUri uri) {
    final path = pathForUri(uri);
    return path == null ? null : _byPath[path];
  }

  @override
  VsUri uriForPath(String path) =>
      VsUri.file(path, windows: platform.isWindows);

  @override
  String? pathForUri(VsUri uri) =>
      uri.scheme == 'file' ? uri.fsPath(windows: platform.isWindows) : null;
}

/// Picks the formatter among several for [document] (`FormattingConflicts`):
/// returns an index into [formatters], or null to not format.
typedef FormatterConflictResolver = Future<int?> Function(
  String message,
  List<LanguageFeatureProvider> formatters,
  LanguageFeatureDocument document,
  FormattingMode mode,
);

/// `HierarchicalKind`.
class HierarchicalKind {
  const HierarchicalKind(this.value);

  static const sep = '.';
  static const empty = HierarchicalKind('');
  static const source = HierarchicalKind('source');
  static const quickFix = HierarchicalKind('quickfix');
  static const notebook = HierarchicalKind('notebook');

  final String value;

  bool contains(HierarchicalKind other) =>
      value == other.value ||
      value.isEmpty ||
      other.value.startsWith('$value$sep');

  bool intersects(HierarchicalKind other) =>
      contains(other) || other.contains(this);
}

/// `CodeActionFilter`.
class CodeActionFilter {
  const CodeActionFilter({
    this.include,
    this.excludes = const [],
    this.includeSourceActions = false,
    this.onlyIncludePreferredActions = false,
  });

  final HierarchicalKind? include;
  final List<HierarchicalKind> excludes;
  final bool includeSourceActions;
  final bool onlyIncludePreferredActions;
}

bool _excludesAction(
  HierarchicalKind providedKind,
  HierarchicalKind exclude,
  HierarchicalKind? include,
) {
  if (!exclude.contains(providedKind)) return false;
  if (include != null && exclude.contains(include)) {
    // The include is more specific, don't filter out
    return false;
  }
  return true;
}

/// `mayIncludeActionsOfKind`.
bool mayIncludeActionsOfKind(
  CodeActionFilter filter,
  HierarchicalKind providedKind,
) {
  // A provided kind may be a subset or superset of our filtered kind.
  if (filter.include != null && !filter.include!.intersects(providedKind)) {
    return false;
  }
  if (filter.excludes.any(
    (exclude) => _excludesAction(providedKind, exclude, filter.include),
  )) {
    return false;
  }
  // Don't return source actions unless they are explicitly requested
  if (!filter.includeSourceActions &&
      HierarchicalKind.source.contains(providedKind)) {
    return false;
  }
  return true;
}

/// `filtersAction`.
bool filtersAction(CodeActionFilter filter, CodeAction action) {
  final actionKind = action.kind == null
      ? null
      : HierarchicalKind(action.kind!);

  // Filter out actions by kind
  if (filter.include != null) {
    if (actionKind == null || !filter.include!.contains(actionKind)) {
      return false;
    }
  }
  if (actionKind != null &&
      filter.excludes.any(
        (exclude) => _excludesAction(actionKind, exclude, filter.include),
      )) {
    return false;
  }
  // Don't return source actions unless they are explicitly requested
  if (!filter.includeSourceActions &&
      actionKind != null &&
      HierarchicalKind.source.contains(actionKind)) {
    return false;
  }
  if (filter.onlyIncludePreferredActions && !action.isPreferred) {
    return false;
  }
  return true;
}

/// `ManagedCodeActionSet.codeActionsComparator`.
int codeActionsComparator(CodeAction a, CodeAction b) {
  int preferred(CodeAction a, CodeAction b) {
    if (a.isPreferred && !b.isPreferred) return -1;
    if (!a.isPreferred && b.isPreferred) return 1;
    return 0;
  }

  if (a.isAI && !b.isAI) return 1;
  if (!a.isAI && b.isAI) return -1;
  final aHas = a.diagnostics?.isNotEmpty ?? false;
  final bHas = b.diagnostics?.isNotEmpty ?? false;
  if (aHas) return bHas ? preferred(a, b) : -1;
  if (bHas) return 1;
  return preferred(a, b); // both have no diagnostics
}

/// A completion item as `provideSuggestionItems` collects it.
class SuggestItem {
  SuggestItem(this.completion, this.container, this.provider)
    : textLabel = completion.label.label,
      sortTextLow = completion.sortText?.toLowerCase();

  final CompletionItem completion;
  final CompletionList container;
  final CompletionItemProvider provider;
  final String textLabel;
  final String? sortTextLow;
}

/// `defaultComparator` (suggest.ts).
int _defaultComparator(SuggestItem a, SuggestItem b) {
  // check with 'sortText'
  if (a.sortTextLow != null && b.sortTextLow != null) {
    final order = a.sortTextLow!.compareTo(b.sortTextLow!);
    if (order != 0) return order;
  }
  // check with 'label'
  final label = a.textLabel.compareTo(b.textLabel);
  if (label != 0) return label;
  // check with 'type'
  return a.completion.kind.index - b.completion.kind.index;
}

class _Origin<P> {
  const _Origin(this.provider, this.value, this.uri);

  final P provider;
  final Object value;
  final VsUri uri;
}

/// `RenameSkeleton`.
class _RenameSkeleton {
  _RenameSkeleton(this.model, this.position, this.providers);

  final LanguageFeatureDocument model;
  final Position position;
  final List<RenameProvider> providers;
  int _providerRenameIdx = 0;

  bool hasProvider() => providers.isNotEmpty;

  Future<RenameLocation?> resolveRenameLocation(CancellationToken token) async {
    final rejects = <String>[];
    for (
      _providerRenameIdx = 0;
      _providerRenameIdx < providers.length;
      _providerRenameIdx++
    ) {
      final provider = providers[_providerRenameIdx];
      if (!provider.canResolveRenameLocation) break;
      final res = await provider.resolveRenameLocation(model, position, token);
      if (res == null) continue;
      if (res.rejectReason != null) {
        rejects.add(res.rejectReason!);
        continue;
      }
      return res;
    }

    // we are here when no provider prepared a location which means we can
    // just rely on the word under cursor and start with the first provider
    _providerRenameIdx = 0;

    final word = getWordAtText(
      position.column,
      model.getLineContent(position.lineNumber),
    );
    final reject = rejects.isNotEmpty ? rejects.join('\n') : null;
    if (word == null) {
      return RenameLocation(
        Range.fromPositions(position),
        '',
        rejectReason: reject,
      );
    }
    return RenameLocation(
      Range(
        position.lineNumber,
        word.startColumn,
        position.lineNumber,
        word.endColumn,
      ),
      word.word,
      rejectReason: reject,
    );
  }

  Future<WorkspaceEdit> provideRenameEdits(
    String newName,
    CancellationToken token,
  ) => _provideRenameEdits(newName, _providerRenameIdx, [], token);

  Future<WorkspaceEdit> _provideRenameEdits(
    String newName,
    int i,
    List<String> rejects,
    CancellationToken token,
  ) async {
    if (i >= providers.length) {
      return WorkspaceEdit(const [], rejectReason: rejects.join('\n'));
    }
    final result = await providers[i].provideRenameEdits(
      model,
      position,
      newName,
      token,
    );
    if (result == null) {
      return _provideRenameEdits(newName, i + 1, [
        ...rejects,
        'No result.',
      ], token);
    } else if (result.rejectReason != null) {
      return _provideRenameEdits(newName, i + 1, [
        ...rejects,
        result.rejectReason!,
      ], token);
    }
    return result;
  }
}

/// A document formatter made of a range formatter (format.ts).
class _SyntheticDocumentFormatter extends DocumentFormattingEditProvider {
  _SyntheticDocumentFormatter(this.formatter);

  final DocumentRangeFormattingEditProvider formatter;

  @override
  String? get extensionId => formatter.extensionId;

  @override
  String? get displayName => formatter.displayName;

  @override
  FutureOr<List<TextEdit>?> provideDocumentFormattingEdits(
    LanguageFeatureDocument model,
    FormattingOptions options,
    CancellationToken token,
  ) => formatter.provideDocumentRangeFormattingEdits(
    model,
    _fullModelRange(model),
    options,
    token,
  );
}

Range _fullModelRange(LanguageFeatureDocument model) => Range(
  1,
  1,
  model.lineCount,
  model.getLineContent(model.lineCount).length + 1,
);

/// Inline completions from one provider, in editor coordinates; dispose
/// when done with them.
class InlineCompletionsResult {
  InlineCompletionsResult(this.provider, this.completions, this.items);

  final InlineCompletionsProvider provider;

  /// As the provider returned them (model coordinates), for its callbacks.
  final InlineCompletions completions;

  /// [completions]' items in editor coordinates.
  final List<InlineCompletion> items;

  void dispose([
    InlineCompletionsDisposeReason reason =
        InlineCompletionsDisposeReason.other,
  ]) => provider.disposeInlineCompletions(completions, reason);
}

/// [LanguageFeatures] over a [LanguageFeaturesService]'s registries and a
/// [MarkerService]'s diagnostics.
class RegistryLanguageFeatures extends ChangeNotifier
    implements LanguageFeatures {
  RegistryLanguageFeatures({
    required this.service,
    required this.markers,
    required this.documents,
    this.commandExecutor,
    this.defaultFormatterId,
    this.onFormatterConflict,
    this.statusProvider,
    this.onProviderError,
  }) {
    markers.addListener(notifyListeners);
    for (final registry in service.registries) {
      _subscriptions.add(registry.onDidChange.listen((_) => notifyListeners()));
    }
  }

  final LanguageFeaturesService service;
  final MarkerService markers;

  /// The open documents' models; the workbench swaps the object in when the
  /// document area replaces what it mirrors.
  LanguageFeatureDocuments documents;

  /// Runs a command a provider attached to a result.
  final Future<void> Function(Command command)? commandExecutor;

  /// The configured `editor.defaultFormatter` for a document (the
  /// workbench sets it once it has its configuration).
  String? Function(LanguageFeatureDocument document)? defaultFormatterId;

  /// Asks the user to pick a formatter; formats nothing when absent.
  FormatterConflictResolver? onFormatterConflict;
  final List<LanguageServerStatus> Function(String path)? statusProvider;
  final void Function(Object error, StackTrace stack)? onProviderError;

  final _subscriptions = <StreamSubscription<Object?>>[];
  final _workspaceEdits = StreamController<LspApplyEditRequest>.broadcast();
  final _origins = Expando<_Origin<Object>>();
  final _retained = <String, List<DisposableResult>>{};
  _RenameSkeleton? _lastRename;
  ({String path, int version, Position position})? _lastRenameKey;
  final _semanticTokens =
      <
        String,
        ({
          DocumentSemanticTokensProvider provider,
          String? resultId,
          Uint32List data,
        })
      >{};

  // --- helpers

  Future<T?> _safe<T>(FutureOr<T?> Function() call) async {
    try {
      return await call();
    } catch (error, stack) {
      onProviderError?.call(error, stack);
      return null;
    }
  }

  void _retain(String key, List<DisposableResult> results) {
    final previous = _retained.remove(key);
    if (previous != null) {
      for (final result in previous) {
        result.dispose();
      }
    }
    if (results.isNotEmpty) _retained[key] = results;
  }

  Position _modelPosition(LanguageFeatureDocument doc, LspPosition position) =>
      doc.toModelPosition(Position(position.line + 1, position.character + 1));

  Range _modelRangeOf(LanguageFeatureDocument doc, LspRange range) =>
      Range.fromPositions(
        _modelPosition(doc, range.start),
        _modelPosition(doc, range.end),
      );

  /// Model position of [uri]'s document to editor coordinates.
  Position _editorPosition(VsUri uri, IPosition position) =>
      documents.documentForUri(uri)?.toEditorPosition(position) ??
      Position(position.lineNumber, position.column);

  Range _editorRange(VsUri uri, IRange range) => Range.fromPositions(
    _editorPosition(uri, Range.startPositionOf(range)),
    _editorPosition(uri, Range.endPositionOf(range)),
  );

  LspPosition _lspPosition(VsUri uri, IPosition position) {
    final editor = _editorPosition(uri, position);
    return LspPosition(editor.lineNumber - 1, editor.column - 1);
  }

  LspRange _lspRange(VsUri uri, IRange range) => LspRange(
    _lspPosition(uri, Range.startPositionOf(range)),
    _lspPosition(uri, Range.endPositionOf(range)),
  );

  String _lspUri(VsUri uri) {
    final path = documents.pathForUri(uri);
    return path != null ? Uri.file(path).toString() : uri.toString();
  }

  LspCommand? _lspCommand(Command? command) => command == null
      ? null
      : LspCommand(command.title, command.id, command.arguments);

  LspTextEdit _lspTextEdit(VsUri uri, IRange range, String text) =>
      LspTextEdit(_lspRange(uri, range), text);

  TextEdit _editorTextEdit(VsUri uri, TextEdit edit) =>
      TextEdit(_editorRange(uri, edit.range), edit.text, eol: edit.eol);

  // --- diagnostics

  LspDiagnostic _lspDiagnostic(VsUri uri, MarkerData marker) {
    final range = _lspRange(
      uri,
      Range(
        marker.startLineNumber,
        marker.startColumn,
        marker.endLineNumber,
        marker.endColumn,
      ),
    );
    final severity = switch (marker.severity) {
      MarkerSeverity.error => LspDiagnosticSeverity.error,
      MarkerSeverity.warning => LspDiagnosticSeverity.warning,
      MarkerSeverity.info => LspDiagnosticSeverity.information,
      MarkerSeverity.hint => LspDiagnosticSeverity.hint,
    };
    final tags = marker.tags ?? const [];
    return LspDiagnostic(
      range: range,
      message: marker.message,
      severity: severity,
      code: marker.code?.value,
      source: marker.source,
      unnecessary: tags.contains(MarkerTag.unnecessary),
      deprecated: tags.contains(MarkerTag.deprecated),
      json: {
        'range': range.toJson(),
        'message': marker.message,
        'severity': severity.index + 1,
        if (marker.code != null) 'code': marker.code!.value,
        if (marker.source != null) 'source': marker.source,
      },
    );
  }

  @override
  List<LspDiagnostic> diagnosticsFor(String path) {
    final uri = documents.uriForPath(path);
    return [
      for (final marker in markers.read(MarkerReadOptions(resource: uri)))
        _lspDiagnostic(uri, marker),
    ];
  }

  @override
  Map<String, List<LspDiagnostic>> get allDiagnostics {
    final result = <String, List<LspDiagnostic>>{};
    for (final marker in markers.read()) {
      final path = documents.pathForUri(marker.resource);
      if (path == null) continue;
      result
          .putIfAbsent(path, () => [])
          .add(_lspDiagnostic(marker.resource, marker));
    }
    return result;
  }

  // --- capabilities

  @override
  bool supports(String path, LanguageRequest request) {
    final doc = documents.documentForPath(path);
    if (doc == null) return false;
    return switch (request) {
      LanguageRequest.hover => service.hoverProvider.has(doc),
      LanguageRequest.definition => service.definitionProvider.has(doc),
      LanguageRequest.typeDefinition => service.typeDefinitionProvider.has(doc),
      LanguageRequest.implementation => service.implementationProvider.has(doc),
      LanguageRequest.references => service.referenceProvider.has(doc),
      LanguageRequest.completion => service.completionProvider.has(doc),
      LanguageRequest.signatureHelp => service.signatureHelpProvider.has(doc),
      LanguageRequest.rename => service.renameProvider.has(doc),
      LanguageRequest.format =>
        service.documentFormattingEditProvider.has(doc) ||
            service.documentRangeFormattingEditProvider.has(doc),
      LanguageRequest.rangeFormat =>
        service.documentRangeFormattingEditProvider.has(doc),
      LanguageRequest.documentSymbols => service.documentSymbolProvider.has(
        doc,
      ),
      LanguageRequest.codeActions => service.codeActionProvider.has(doc),
      LanguageRequest.semanticTokens =>
        service.documentSemanticTokensProvider.has(doc),
    };
  }

  @override
  Set<String> completionTriggerCharacters(String path) {
    final doc = documents.documentForPath(path);
    if (doc == null) return const {};
    return {
      for (final provider in service.completionProvider.all(doc))
        ...provider.triggerCharacters,
    };
  }

  @override
  Set<String> signatureHelpTriggerCharacters(String path) {
    final doc = documents.documentForPath(path);
    if (doc == null) return const {};
    return {
      for (final provider in service.signatureHelpProvider.ordered(doc))
        ...provider.signatureHelpTriggerCharacters,
    };
  }

  @override
  Set<String> signatureHelpRetriggerCharacters(String path) {
    final doc = documents.documentForPath(path);
    if (doc == null) return const {};
    return {
      for (final provider in service.signatureHelpProvider.ordered(doc))
        ...provider.signatureHelpRetriggerCharacters,
    };
  }

  // --- hover

  /// `getHoversPromise`: every provider's valid hover, in provider order.
  Future<List<Hover>> hovers(
    LanguageFeatureDocument doc,
    Position modelPosition, [
    CancellationToken token = CancellationToken.none,
  ]) => hoversFor(doc, modelPosition, token);

  /// [hovers] with the recursive flag the `vscode.experimental.*` commands
  /// pass (`LanguageFeatureRegistry.ordered`).
  Future<List<Hover>> hoversFor(
    LanguageFeatureDocument doc,
    Position modelPosition, [
    CancellationToken token = CancellationToken.none,
    bool recursive = false,
  ]) async {
    final results = await Future.wait([
      for (final provider in service.hoverProvider.ordered(
        doc,
        recursive: recursive,
      ))
        _safe(() => provider.provideHover(doc, modelPosition, token)),
    ]);
    return [
      for (final hover in results)
        if (hover != null && hover.range != null && hover.contents.isNotEmpty)
          hover,
    ];
  }

  @override
  Future<LspHover?> hover(String path, LspPosition position) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final results = await hovers(doc, _modelPosition(doc, position));
    final markdown = [
      for (final hover in results)
        for (final content in hover.contents)
          if (content.value.trim().isNotEmpty) content.value,
    ].join('\n\n---\n\n');
    if (markdown.isEmpty) return null;
    return LspHover(markdown, range: _lspRange(doc.uri, results.first.range!));
  }

  // --- go to symbol

  static const _internalSchemes = {
    'walkThroughSnippet',
    'vscode-chat-code-block',
    'vscode-chat-code-compare-block',
  };

  /// `getLocationLinks`: every provider's links, flattened and filtered.
  Future<List<LocationLink>> _locationLinks<T>(
    LanguageFeatureDocument doc,
    LanguageFeatureRegistry<T> registry,
    FutureOr<List<LocationLink>?> Function(T provider) provide, {
    bool recursive = false,
  }) async {
    final values = await Future.wait([
      for (final provider in registry.ordered(doc, recursive: recursive))
        _safe(() => provide(provider)),
    ]);
    return [
      for (final links in values)
        for (final link in links ?? const <LocationLink>[])
          if (link.uri.scheme == doc.uri.scheme ||
              !_internalSchemes.contains(link.uri.scheme))
            link,
    ];
  }

  /// `ReferencesModel`'s grouping: by URI, then range start; duplicates
  /// dropped.
  static List<LocationLink> sortedAndDeduped(List<LocationLink> links) {
    int compare(LocationLink a, LocationLink b) {
      final uri = a.uri.toString().compareTo(b.uri.toString());
      return uri != 0 ? uri : Range.compareRangesUsingStarts(a.range, b.range);
    }

    final sorted = [...links];
    stableSort(sorted, compare);
    final result = <LocationLink>[];
    for (final link in sorted) {
      if (result.isEmpty || compare(link, result.last) != 0) result.add(link);
    }
    return result;
  }

  Future<List<LspLocation>> _lspLocations<T>(
    String path,
    LspPosition position,
    LanguageFeatureRegistry<T> registry,
    FutureOr<List<LocationLink>?> Function(
      T provider,
      LanguageFeatureDocument doc,
      Position position,
    )
    provide,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final modelPosition = _modelPosition(doc, position);
    final links = await _locationLinks(
      doc,
      registry,
      (provider) => provide(provider, doc, modelPosition),
    );
    return [
      for (final link in sortedAndDeduped(links))
        LspLocation(
          _lspUri(link.uri),
          _lspRange(link.uri, link.range),
          selectionRange: link.targetSelectionRange == null
              ? null
              : _lspRange(link.uri, link.targetSelectionRange!),
        ),
    ];
  }

  @override
  Future<List<LspLocation>> definition(String path, LspPosition position) =>
      _lspLocations(
        path,
        position,
        service.definitionProvider,
        (p, doc, pos) => p.provideDefinition(doc, pos, CancellationToken.none),
      );

  @override
  Future<List<LspLocation>> typeDefinition(String path, LspPosition position) =>
      _lspLocations(
        path,
        position,
        service.typeDefinitionProvider,
        (p, doc, pos) =>
            p.provideTypeDefinition(doc, pos, CancellationToken.none),
      );

  @override
  Future<List<LspLocation>> implementation(String path, LspPosition position) =>
      _lspLocations(
        path,
        position,
        service.implementationProvider,
        (p, doc, pos) =>
            p.provideImplementation(doc, pos, CancellationToken.none),
      );

  /// Go to declaration.
  Future<List<LspLocation>> declaration(String path, LspPosition position) =>
      _lspLocations(
        path,
        position,
        service.declarationProvider,
        (p, doc, pos) => p.provideDeclaration(doc, pos, CancellationToken.none),
      );

  @override
  Future<List<LspLocation>> references(
    String path,
    LspPosition position, {
    bool includeDeclaration = true,
  }) => _lspLocations(
    path,
    position,
    service.referenceProvider,
    (p, doc, pos) async => [
      for (final location
          in await p.provideReferences(
                doc,
                pos,
                ReferenceContext(includeDeclaration: includeDeclaration),
                CancellationToken.none,
              ) ??
              const <Location>[])
        LocationLink.fromLocation(location),
    ],
  );

  // --- completion

  @override
  Future<LspCompletionList> completion(
    String path,
    LspPosition position, {
    String? triggerCharacter,
    bool retrigger = false,
  }) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return LspCompletionList.empty;
    final modelPosition = _modelPosition(doc, position);
    final context = triggerCharacter != null
        ? CompletionContext(
            CompletionTriggerKind.triggerCharacter,
            triggerCharacter: triggerCharacter,
          )
        : CompletionContext(
            retrigger
                ? CompletionTriggerKind.triggerForIncompleteCompletions
                : CompletionTriggerKind.invoke,
          );
    // Typing a trigger character asks only the providers it triggers.
    final providerFilter = triggerCharacter == null
        ? null
        : {
            for (final provider in service.completionProvider.all(doc))
              if (provider.triggerCharacters.contains(triggerCharacter))
                provider,
          };
    if (providerFilter != null && providerFilter.isEmpty) {
      _retain('completion:$path', const []);
      return LspCompletionList.empty;
    }

    final items = await provideSuggestionItems(
      doc,
      modelPosition,
      context,
      providerFilter: providerFilter,
    );
    final lists = <CompletionList>{for (final item in items) item.container};
    _retain('completion:$path', lists.toList());
    return LspCompletionList([
      for (final item in items)
        _lspCompletionItem(doc.uri, item.completion, item.provider),
    ], isIncomplete: lists.any((list) => list.incomplete));
  }

  /// `provideSuggestionItems`: provider groups by score, all of a group in
  /// parallel, stopping at the first group that produced items; default
  /// ranges and sort texts filled in; sorted by `defaultComparator`.
  Future<List<SuggestItem>> provideSuggestionItems(
    LanguageFeatureDocument doc,
    Position position,
    CompletionContext context, {
    Set<CompletionItemProvider>? providerFilter,
    CancellationToken token = CancellationToken.none,
  }) async {
    final word = getWordAtText(
      position.column,
      doc.getLineContent(position.lineNumber),
    );
    final defaultReplaceRange = word != null
        ? Range(
            position.lineNumber,
            word.startColumn,
            position.lineNumber,
            word.endColumn,
          )
        : Range.fromPositions(position);
    final defaultRange = CompletionItemRanges(
      replace: defaultReplaceRange,
      insert: Range(
        defaultReplaceRange.startLineNumber,
        defaultReplaceRange.startColumn,
        position.lineNumber,
        position.column,
      ),
    );

    final result = <SuggestItem>[];
    bool onCompletionList(
      CompletionItemProvider provider,
      CompletionList? container,
    ) {
      if (container == null) return false;
      var didAddResult = false;
      for (final suggestion in container.suggestions) {
        // fill in default range when missing
        suggestion.range ??= defaultRange;
        // fill in default sortText when missing
        if (suggestion.sortText == null || suggestion.sortText!.isEmpty) {
          suggestion.sortText = suggestion.label.label;
        }
        result.add(SuggestItem(suggestion, container, provider));
        didAddResult = true;
      }
      return didAddResult;
    }

    for (final group in service.completionProvider.orderedGroups(doc)) {
      var didAddResult = false;
      await Future.wait([
        for (final provider in group)
          if (providerFilter == null || providerFilter.contains(provider))
            () async {
              final list = await _safe(
                () => provider.provideCompletionItems(
                  doc,
                  position,
                  context,
                  token,
                ),
              );
              didAddResult = onCompletionList(provider, list) || didAddResult;
            }(),
      ]);
      if (didAddResult || token.isCancellationRequested) break;
    }
    stableSort(result, _defaultComparator);
    return result;
  }

  static LspCompletionKind _lspCompletionKind(CompletionItemKind kind) =>
      switch (kind) {
        CompletionItemKind.method => LspCompletionKind.method,
        CompletionItemKind.function => LspCompletionKind.function,
        CompletionItemKind.constructor => LspCompletionKind.constructor,
        CompletionItemKind.field => LspCompletionKind.field,
        CompletionItemKind.variable => LspCompletionKind.variable,
        CompletionItemKind.klass => LspCompletionKind.klass,
        CompletionItemKind.struct => LspCompletionKind.struct,
        CompletionItemKind.interface => LspCompletionKind.interface,
        CompletionItemKind.module => LspCompletionKind.module,
        CompletionItemKind.property => LspCompletionKind.property,
        CompletionItemKind.event => LspCompletionKind.event,
        CompletionItemKind.operator => LspCompletionKind.operator,
        CompletionItemKind.unit => LspCompletionKind.unit,
        CompletionItemKind.value => LspCompletionKind.value,
        CompletionItemKind.constant => LspCompletionKind.constant,
        CompletionItemKind.enumeration => LspCompletionKind.enumeration,
        CompletionItemKind.enumMember => LspCompletionKind.enumMember,
        CompletionItemKind.keyword => LspCompletionKind.keyword,
        CompletionItemKind.text => LspCompletionKind.text,
        CompletionItemKind.color ||
        CompletionItemKind.customcolor => LspCompletionKind.color,
        CompletionItemKind.file => LspCompletionKind.file,
        CompletionItemKind.reference => LspCompletionKind.reference,
        CompletionItemKind.folder => LspCompletionKind.folder,
        CompletionItemKind.typeParameter => LspCompletionKind.typeParameter,
        CompletionItemKind.snippet => LspCompletionKind.snippet,
        CompletionItemKind.tool => LspCompletionKind.function,
        CompletionItemKind.user ||
        CompletionItemKind.issue => LspCompletionKind.text,
      };

  LspCompletionItem _lspCompletionItem(
    VsUri uri,
    CompletionItem item,
    CompletionItemProvider provider,
  ) {
    final range = item.range!;
    final replace = _lspRange(uri, range.replace);
    final insert = _lspRange(uri, range.insert);
    final lsp = LspCompletionItem(
      label: item.label.label,
      kind: _lspCompletionKind(item.kind),
      detail: item.detail,
      documentation: item.documentation?.value,
      insertText: item.insertText,
      isSnippet: item.isSnippet,
      textEdit: LspTextEdit(replace, item.insertText),
      insertRange: insert == replace ? null : insert,
      additionalTextEdits: [
        for (final edit in item.additionalTextEdits ?? const [])
          _lspTextEdit(uri, edit.range, edit.text ?? ''),
      ],
      sortText: item.sortText,
      filterText: item.filterText,
      preselect: item.preselect,
      deprecated: item.isDeprecated,
      commitCharacters: item.commitCharacters ?? const [],
      command: _lspCommand(item.command),
      labelDetail: item.label.detail,
      labelDescription: item.label.description,
      serverId: provider.extensionId,
    );
    _origins[lsp] = _Origin(provider, item, uri);
    return lsp;
  }

  @override
  Future<LspCompletionItem> resolveCompletion(
    String path,
    LspCompletionItem item,
  ) async {
    final origin = _origins[item];
    if (origin == null) return item;
    final provider = origin.provider as CompletionItemProvider;
    final original = origin.value as CompletionItem;
    if (!provider.canResolveCompletionItem) return item;
    final resolved = await _safe(
      () => provider.resolveCompletionItem(original, CancellationToken.none),
    );
    if (resolved == null) return item;
    resolved.range ??= original.range;
    resolved.sortText ??= original.sortText;
    return _lspCompletionItem(origin.uri, resolved, provider);
  }

  // --- signature help

  /// `provideSignatureHelp`: the first provider in order with an answer.
  Future<SignatureHelpResult?> provideSignatureHelp(
    LanguageFeatureDocument doc,
    Position position,
    SignatureHelpContext context, [
    CancellationToken token = CancellationToken.none,
  ]) async {
    for (final support in service.signatureHelpProvider.ordered(doc)) {
      final result = await _safe(
        () => support.provideSignatureHelp(doc, position, token, context),
      );
      if (result != null) return result;
    }
    return null;
  }

  @override
  Future<LspSignatureHelp?> signatureHelp(
    String path,
    LspPosition position, {
    String? triggerCharacter,
    bool retrigger = false,
  }) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final result = await provideSignatureHelp(
      doc,
      _modelPosition(doc, position),
      SignatureHelpContext(
        triggerKind: triggerCharacter != null
            ? SignatureHelpTriggerKind.triggerCharacter
            : retrigger
            ? SignatureHelpTriggerKind.contentChange
            : SignatureHelpTriggerKind.invoke,
        triggerCharacter: triggerCharacter,
        isRetrigger: retrigger,
      ),
    );
    _retain('signatureHelp:$path', [?result]);
    final help = result?.value;
    if (help == null || help.signatures.isEmpty) return null;
    return LspSignatureHelp(
      [
        for (final signature in help.signatures)
          LspSignature(
            signature.label,
            documentation: signature.documentation?.value,
            activeParameter: signature.activeParameter,
            parameters: [
              for (final parameter in signature.parameters)
                if (parameter.labelOffsets case (final from, final to))
                  LspParameterInformation(
                    signature.label.substring(
                      from.clamp(0, signature.label.length),
                      to.clamp(0, signature.label.length),
                    ),
                    labelRange: (from, to),
                    documentation: parameter.documentation?.value,
                  )
                else
                  LspParameterInformation(
                    parameter.label ?? '',
                    documentation: parameter.documentation?.value,
                  ),
            ],
          ),
      ],
      activeSignature: help.activeSignature,
      activeParameter: help.activeParameter,
    );
  }

  // --- rename

  _RenameSkeleton _renameSkeleton(
    String path,
    LanguageFeatureDocument doc,
    Position position,
  ) {
    final key = (path: path, version: doc.versionId, position: position);
    final last = _lastRenameKey;
    if (_lastRename != null &&
        last != null &&
        last.path == key.path &&
        last.version == key.version &&
        last.position.equals(position)) {
      return _lastRename!;
    }
    _lastRenameKey = key;
    return _lastRename = _RenameSkeleton(
      doc,
      position,
      service.renameProvider.ordered(doc),
    );
  }

  @override
  Future<({LspRange range, String placeholder})?> prepareRename(
    String path,
    LspPosition position,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final skeleton = _renameSkeleton(path, doc, _modelPosition(doc, position));
    if (!skeleton.hasProvider()) return null;
    final location = await _safe(
      () => skeleton.resolveRenameLocation(CancellationToken.none),
    );
    if (location == null || location.rejectReason != null) return null;
    return (
      range: _lspRange(doc.uri, location.range),
      placeholder: location.text,
    );
  }

  @override
  Future<LspWorkspaceEdit?> rename(
    String path,
    LspPosition position,
    String newName,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final modelPosition = _modelPosition(doc, position);
    final cached = _lastRename;
    final skeleton = _renameSkeleton(path, doc, modelPosition);
    if (!skeleton.hasProvider()) return null;
    if (!identical(cached, skeleton)) {
      // As the rename command does: resolve first, which picks the provider.
      await _safe(() => skeleton.resolveRenameLocation(CancellationToken.none));
    }
    final edit = await _safe(
      () => skeleton.provideRenameEdits(newName, CancellationToken.none),
    );
    _lastRename = null;
    _lastRenameKey = null;
    if (edit == null || edit.rejectReason != null) return null;
    return toLspWorkspaceEdit(edit);
  }

  /// A provider's [WorkspaceEdit] as the editor applies it.
  LspWorkspaceEdit toLspWorkspaceEdit(WorkspaceEdit edit) {
    final changes = <String, List<LspTextEdit>>{};
    final operations = <JsonMap>[];
    for (final entry in edit.edits) {
      switch (entry) {
        case WorkspaceTextEdit(:final resource, :final textEdit):
          changes
              .putIfAbsent(_lspUri(resource), () => [])
              .add(_lspTextEdit(resource, textEdit.range, textEdit.text));
        case WorkspaceFileEdit(:final oldResource, :final newResource):
          final options = entry.options;
          final lspOptions = <String, Object?>{
            if (options?.overwrite != null) 'overwrite': options!.overwrite,
            if (options?.ignoreIfExists != null)
              'ignoreIfExists': options!.ignoreIfExists,
            if (options?.ignoreIfNotExists != null)
              'ignoreIfNotExists': options!.ignoreIfNotExists,
            if (options?.recursive != null) 'recursive': options!.recursive,
          };
          if (oldResource != null && newResource != null) {
            operations.add({
              'kind': 'rename',
              'oldUri': _lspUri(oldResource),
              'newUri': _lspUri(newResource),
              if (lspOptions.isNotEmpty) 'options': lspOptions,
            });
          } else if (newResource != null) {
            operations.add({
              'kind': 'create',
              'uri': _lspUri(newResource),
              if (lspOptions.isNotEmpty) 'options': lspOptions,
            });
          } else if (oldResource != null) {
            operations.add({
              'kind': 'delete',
              'uri': _lspUri(oldResource),
              if (lspOptions.isNotEmpty) 'options': lspOptions,
            });
          }
      }
    }
    return LspWorkspaceEdit(changes, resourceOperations: operations);
  }

  // --- formatting

  /// `getRealAndSyntheticDocumentFormattersOrdered`.
  List<DocumentFormattingEditProvider> documentFormatters(
    LanguageFeatureDocument doc,
  ) {
    final result = <DocumentFormattingEditProvider>[];
    final seen = <String>{};
    // (1) add all document formatter
    for (final formatter in service.documentFormattingEditProvider.ordered(
      doc,
    )) {
      result.add(formatter);
      if (formatter.extensionId != null) {
        seen.add(formatter.extensionId!.toLowerCase());
      }
    }
    // (2) add all range formatter as document formatter (unless the same
    // extension already did that)
    for (final formatter in service.documentRangeFormattingEditProvider.ordered(
      doc,
    )) {
      final id = formatter.extensionId?.toLowerCase();
      if (id != null) {
        if (seen.contains(id)) continue;
        seen.add(id);
      }
      result.add(_SyntheticDocumentFormatter(formatter));
    }
    return result;
  }

  /// `FormattingConflicts.select` with `DefaultFormatter`'s rules: the
  /// configured default formatter, the only one, or the user's pick.
  Future<T?> selectFormatter<T extends LanguageFeatureProvider>(
    List<T> formatters,
    LanguageFeatureDocument doc,
    FormattingMode mode,
    FormattingKind kind,
  ) async {
    if (formatters.isEmpty) return null;
    final defaultId = defaultFormatterId?.call(doc);
    if (defaultId != null && defaultId.isNotEmpty) {
      // good -> formatter configured
      for (final formatter in formatters) {
        if (formatter.extensionId?.toLowerCase() == defaultId.toLowerCase()) {
          return formatter;
        }
      }
    } else if (formatters.length == 1) {
      // ok -> nothing configured but only one formatter available
      return formatters[0];
    }
    final message = defaultId == null || defaultId.isEmpty
        ? "There are multiple formatters for '${doc.languageId}' files. One "
              'of them should be configured as default formatter.'
        : kind == FormattingKind.file
        ? "Extension '$defaultId' is configured as formatter but it cannot "
              "format '${doc.languageId}'-files"
        : "Extension '$defaultId' is configured as formatter but it can only "
              "format '${doc.languageId}'-files as a whole, not selections or "
              'parts of it.';
    final index = await onFormatterConflict?.call(
      message,
      formatters,
      doc,
      mode,
    );
    return index != null && index >= 0 && index < formatters.length
        ? formatters[index]
        : null;
  }

  @override
  Future<List<LspTextEdit>> format(
    String path, {
    LspRange? range,
    required int tabSize,
    required bool insertSpaces,
  }) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final edits = await formatEdits(
      doc,
      range: range == null ? null : _modelRangeOf(doc, range),
      options: FormattingOptions(tabSize: tabSize, insertSpaces: insertSpaces),
    );
    return [
      for (final edit in edits ?? const <TextEdit>[])
        _lspTextEdit(doc.uri, edit.range, edit.text),
    ];
  }

  /// Formatting edits (model coordinates) from the selected formatter of
  /// [doc], or of [range] of it.
  Future<List<TextEdit>?> formatEdits(
    LanguageFeatureDocument doc, {
    Range? range,
    required FormattingOptions options,
    FormattingMode mode = FormattingMode.explicit,
    CancellationToken token = CancellationToken.none,
  }) async {
    if (range == null) {
      final selected = await selectFormatter(
        documentFormatters(doc),
        doc,
        mode,
        FormattingKind.file,
      );
      if (selected == null) return null;
      return _safe(
        () => selected.provideDocumentFormattingEdits(doc, options, token),
      );
    }
    final selected = await selectFormatter(
      service.documentRangeFormattingEditProvider.ordered(doc),
      doc,
      mode,
      FormattingKind.selection,
    );
    if (selected == null) return null;
    return _safe(
      () => selected.provideDocumentRangeFormattingEdits(
        doc,
        range,
        options,
        token,
      ),
    );
  }

  /// `getOnTypeFormattingEdits`: the first provider only, if [ch] triggers
  /// it. Editor coordinates.
  Future<List<TextEdit>?> onTypeFormat(
    String path,
    Position position,
    String ch,
    FormattingOptions options,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final providers = service.onTypeFormattingEditProvider.ordered(doc);
    if (providers.isEmpty ||
        !providers[0].autoFormatTriggerCharacters.contains(ch)) {
      return null;
    }
    final edits = await _safe(
      () => providers[0].provideOnTypeFormattingEdits(
        doc,
        doc.toModelPosition(position),
        ch,
        options,
        CancellationToken.none,
      ),
    );
    return edits == null
        ? null
        : [for (final edit in edits) _editorTextEdit(doc.uri, edit)];
  }

  /// [onTypeFormat] for a document already in hand (model coordinates).
  Future<List<TextEdit>?> onTypeFormatDocument(
    LanguageFeatureDocument doc,
    Position modelPosition,
    String ch,
    FormattingOptions options,
    CancellationToken token,
  ) async {
    final providers = service.onTypeFormattingEditProvider.ordered(doc);
    if (providers.isEmpty ||
        !providers[0].autoFormatTriggerCharacters.contains(ch)) {
      return null;
    }
    return _safe(
      () => providers[0].provideOnTypeFormattingEdits(
        doc,
        modelPosition,
        ch,
        options,
        token,
      ),
    );
  }

  /// Characters that trigger on-type formatting in [path].
  Set<String> onTypeFormattingTriggerCharacters(String path) {
    final doc = documents.documentForPath(path);
    if (doc == null) return const {};
    final providers = service.onTypeFormattingEditProvider.ordered(doc);
    return providers.isEmpty
        ? const {}
        : providers[0].autoFormatTriggerCharacters.toSet();
  }

  // --- document symbols

  /// `OutlineModel.create(...).getTopLevelSymbols()`: every provider's
  /// symbols, roots sorted by range start (model coordinates).
  Future<List<DocumentSymbol>> provideDocumentSymbols(
    LanguageFeatureDocument doc, [
    CancellationToken token = CancellationToken.none,
  ]) async {
    final results = await Future.wait([
      for (final provider in service.documentSymbolProvider.ordered(doc))
        _safe(() => provider.provideDocumentSymbols(doc, token)),
    ]);
    final roots = [for (final symbols in results) ...?symbols];
    stableSort(
      roots,
      (a, b) => Range.compareRangesUsingStarts(a.range, b.range),
    );
    return roots;
  }

  @override
  Future<List<LspDocumentSymbol>> documentSymbols(String path) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    LspDocumentSymbol convert(DocumentSymbol symbol) => LspDocumentSymbol(
      name: symbol.name,
      kind: LspSymbolKind.values[symbol.kind.index],
      range: _lspRange(doc.uri, symbol.range),
      selectionRange: _lspRange(doc.uri, symbol.selectionRange),
      detail: symbol.detail.isEmpty ? null : symbol.detail,
      children: [
        for (final child in symbol.children ?? const []) convert(child),
      ],
    );
    return [
      for (final symbol in await provideDocumentSymbols(doc)) convert(symbol),
    ];
  }

  // --- code actions

  /// `getCodeActions`: every provider that may return actions of interest,
  /// actions filtered and sorted (model coordinates).
  Future<List<({CodeAction action, CodeActionProvider provider})>>
  provideCodeActions(
    LanguageFeatureDocument doc,
    Range range,
    CodeActionFilter filter, {
    CodeActionTriggerType trigger = CodeActionTriggerType.invoke,
    CancellationToken token = CancellationToken.none,
    String? retainKey,
  }) async {
    final effective = trigger == CodeActionTriggerType.auto
        ? CodeActionFilter(
            include: filter.include,
            excludes: [...filter.excludes, HierarchicalKind.notebook],
            includeSourceActions: filter.includeSourceActions,
            onlyIncludePreferredActions: filter.onlyIncludePreferredActions,
          )
        : filter;
    final context = CodeActionContext(
      only: filter.include?.value,
      trigger: trigger,
    );
    final providers = [
      for (final provider in service.codeActionProvider.all(doc))
        if (provider.providedCodeActionKinds == null ||
            provider.providedCodeActionKinds!.any(
              (kind) =>
                  mayIncludeActionsOfKind(effective, HierarchicalKind(kind)),
            ))
          provider,
    ];
    final lists = await Future.wait([
      for (final provider in providers)
        _safe(() => provider.provideCodeActions(doc, range, context, token))
            .then((list) => (provider: provider, list: list)),
    ]);
    if (retainKey != null) {
      _retain(retainKey, [for (final entry in lists) ?entry.list]);
    }
    final actions = [
      for (final entry in lists)
        for (final action in entry.list?.actions ?? const <CodeAction>[])
          if (filtersAction(filter, action))
            (action: action, provider: entry.provider),
    ];
    stableSort(actions, (a, b) => codeActionsComparator(a.action, b.action));
    return actions;
  }

  @override
  Future<List<LspCodeAction>> codeActions(
    String path,
    LspRange range, {
    List<LspDiagnostic> diagnostics = const [],
    List<String>? only,
  }) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    // Extension providers find the diagnostics in range themselves.
    final kinds = [
      for (final kind in only ?? const <String>[]) HierarchicalKind(kind),
    ];
    final filter = CodeActionFilter(
      include: kinds.length == 1 ? kinds.single : null,
      includeSourceActions: true,
    );
    final actions = await provideCodeActions(
      doc,
      _modelRangeOf(doc, range),
      filter,
      retainKey: 'codeActions:$path',
    );
    return [
      for (final (:action, :provider) in actions)
        if (kinds.length < 2 ||
            (action.kind != null &&
                kinds.any((k) => k.contains(HierarchicalKind(action.kind!)))))
          _lspCodeAction(doc.uri, action, provider),
    ];
  }

  LspCodeAction _lspCodeAction(
    VsUri uri,
    CodeAction action,
    CodeActionProvider provider,
  ) {
    final lsp = LspCodeAction(
      title: action.title,
      kind: action.kind,
      isPreferred: action.isPreferred,
      diagnostics: [
        for (final marker in action.diagnostics ?? const <MarkerData>[])
          _lspDiagnostic(uri, marker),
      ],
      edit: action.edit == null ? null : toLspWorkspaceEdit(action.edit!),
      command: _lspCommand(action.command),
      disabledReason: action.disabled,
      serverId: provider.extensionId,
    );
    _origins[lsp] = _Origin(provider, action, uri);
    return lsp;
  }

  @override
  Future<LspCodeAction> resolveCodeAction(
    String path,
    LspCodeAction action,
  ) async {
    final origin = _origins[action];
    if (origin == null) return action;
    final provider = origin.provider as CodeActionProvider;
    if (!provider.canResolveCodeAction) return action;
    final resolved = await _safe(
      () => provider.resolveCodeAction(
        origin.value as CodeAction,
        CancellationToken.none,
      ),
    );
    return resolved == null
        ? action
        : _lspCodeAction(origin.uri, resolved, provider);
  }

  @override
  Future<void> executeCommand(
    String path,
    LspCommand command, {
    String? serverId,
  }) async {
    await commandExecutor?.call(
      Command(
        id: command.command,
        title: command.title,
        arguments: command.arguments,
      ),
    );
  }

  // --- semantic tokens

  @override
  Future<List<LspSemanticToken>?> semanticTokens(String path) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final groups = service.documentSemanticTokensProvider.orderedGroups(doc);
    if (groups.isEmpty) return null;
    final last = _semanticTokens[path];
    final results = await Future.wait([
      for (final provider in groups.first)
        _safe(
          () => provider.provideDocumentSemanticTokens(
            doc,
            identical(last?.provider, provider) ? last?.resultId : null,
            CancellationToken.none,
          ),
        ).then((result) => (provider: provider, result: result)),
    ]);
    // The first result with tokens, else the first.
    final chosen = results.firstWhere(
      (r) => r.result != null,
      orElse: () => results.first,
    );
    final result = chosen.result;
    if (result == null) return null;
    final Uint32List data;
    switch (result) {
      case SemanticTokens(data: final full):
        data = full;
      case SemanticTokensEdits(:final edits):
        if (last == null || !identical(last.provider, chosen.provider)) {
          return null;
        }
        data = applySemanticTokensEdits(last.data, edits);
    }
    if (last != null && last.resultId != result.resultId) {
      last.provider.releaseDocumentSemanticTokens(last.resultId);
    }
    _semanticTokens[path] = (
      provider: chosen.provider,
      resultId: result.resultId,
      data: data,
    );
    return _decodeSemanticTokens(doc, chosen.provider.getLegend(), data);
  }

  /// Semantic tokens of [range] (editor coordinates) from the best range
  /// provider.
  Future<List<LspSemanticToken>?> semanticTokensRange(
    String path,
    Range range,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final groups = service.documentRangeSemanticTokensProvider.orderedGroups(
      doc,
    );
    if (groups.isEmpty) return null;
    final modelRange = Range.fromPositions(
      doc.toModelPosition(range.getStartPosition()),
      doc.toModelPosition(range.getEndPosition()),
    );
    final results = await Future.wait([
      for (final provider in groups.first)
        _safe(
          () => provider.provideDocumentRangeSemanticTokens(
            doc,
            modelRange,
            CancellationToken.none,
          ),
        ).then((result) => (provider: provider, result: result)),
    ]);
    final chosen = results.firstWhere(
      (r) => r.result != null,
      orElse: () => results.first,
    );
    if (chosen.result == null) return null;
    return _decodeSemanticTokens(
      doc,
      chosen.provider.getLegend(),
      chosen.result!.data,
    );
  }

  /// Applies [edits] (offsets into [data]) to a copy of [data].
  static Uint32List applySemanticTokensEdits(
    Uint32List data,
    List<SemanticTokensEdit> edits,
  ) {
    final sorted = [...edits]..sort((a, b) => b.start.compareTo(a.start));
    final result = data.toList();
    for (final edit in sorted) {
      final start = edit.start.clamp(0, result.length);
      final end = (start + edit.deleteCount).clamp(start, result.length);
      result.replaceRange(start, end, edit.data ?? const <int>[]);
    }
    return Uint32List.fromList(result);
  }

  List<LspSemanticToken> _decodeSemanticTokens(
    LanguageFeatureDocument doc,
    SemanticTokensLegend legend,
    Uint32List data,
  ) => [
    for (final token in LspSemanticTokensLegend(
      legend.tokenTypes,
      legend.tokenModifiers,
    ).decode(data))
      if (token.line != 0)
        token
      else
        LspSemanticToken(
          0,
          doc.toEditorPosition(Position(1, token.character + 1)).column - 1,
          token.length,
          token.type,
          token.modifiers,
        ),
  ];

  // --- workspace edits, status

  @override
  Stream<LspApplyEditRequest> get workspaceEdits => _workspaceEdits.stream;

  /// Asks the editor to apply [edit] (an extension's
  /// `$tryApplyWorkspaceEdit`); completes with whether it did (false when
  /// nothing listens).
  Future<bool> requestApplyEdit(WorkspaceEdit edit, {String? label}) {
    if (!_workspaceEdits.hasListener) return Future.value(false);
    final request = LspApplyEditRequest(toLspWorkspaceEdit(edit), label: label);
    final completer = Completer<bool>();
    request.onComplete(completer.complete);
    _workspaceEdits.add(request);
    return completer.future;
  }

  @override
  List<LanguageServerStatus> statusFor(String path) =>
      statusProvider?.call(path) ?? const [];

  @override
  void retry(String serverId, {String? path}) {}

  @override
  Future<void> install(String serverId, {String? path}) async {}

  // --- features beyond LanguageFeatures (editor coordinates)

  /// `getOccurrencesAtPosition`: the first provider in order with a non-null
  /// answer (an empty list is an answer).
  Future<List<DocumentHighlight>?> documentHighlights(
    String path,
    Position position,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final modelPosition = doc.toModelPosition(position);
    for (final provider in service.documentHighlightProvider.ordered(doc)) {
      final result = await _safe(
        () => provider.provideDocumentHighlights(
          doc,
          modelPosition,
          CancellationToken.none,
        ),
      );
      if (result != null) {
        return [
          for (final highlight in result)
            DocumentHighlight(
              _editorRange(doc.uri, highlight.range),
              kind: highlight.kind,
            ),
        ];
      }
    }
    return null;
  }

  /// `getLinkedEditingRanges`: the first provider with non-empty ranges.
  Future<LinkedEditingRanges?> linkedEditingRanges(
    String path,
    Position position,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final modelPosition = doc.toModelPosition(position);
    for (final provider in service.linkedEditingRangeProvider.ordered(doc)) {
      final result = await _safe(
        () => provider.provideLinkedEditingRanges(
          doc,
          modelPosition,
          CancellationToken.none,
        ),
      );
      if (result != null && result.ranges.isNotEmpty) {
        return LinkedEditingRanges([
          for (final range in result.ranges) _editorRange(doc.uri, range),
        ], wordPattern: result.wordPattern);
      }
    }
    return null;
  }

  /// `getCodeLensModel`: every provider's lenses, sorted by line, provider
  /// rank, column. Resolve each with [resolveCodeLens].
  Future<List<CodeLens>> codeLenses(String path) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final providers = service.codeLensProvider.ordered(doc);
    final lists = await Future.wait([
      for (final provider in providers)
        _safe(() => provider.provideCodeLenses(doc, CancellationToken.none)),
    ]);
    _retain('codeLens:$path', [for (final list in lists) ?list]);
    final lenses = <({CodeLens lens, int rank})>[
      for (var i = 0; i < lists.length; i++)
        for (final lens in lists[i]?.lenses ?? const <CodeLens>[])
          (lens: lens, rank: i),
    ];
    stableSort(lenses, (a, b) {
      final line = a.lens.range.startLineNumber.compareTo(
        b.lens.range.startLineNumber,
      );
      if (line != 0) return line;
      final rank = a.rank.compareTo(b.rank);
      if (rank != 0) return rank;
      return a.lens.range.startColumn.compareTo(b.lens.range.startColumn);
    });
    return [
      for (final (:lens, :rank) in lenses)
        _withOrigin(
          CodeLens(
            _editorRange(doc.uri, lens.range),
            id: lens.id,
            command: lens.command,
          ),
          providers[rank],
          lens,
          doc.uri,
        ),
    ];
  }

  T _withOrigin<T extends Object>(
    T value,
    Object provider,
    Object original,
    VsUri uri,
  ) {
    _origins[value] = _Origin(provider, original, uri);
    return value;
  }

  /// Fills in [lens]'s command.
  Future<CodeLens> resolveCodeLens(String path, CodeLens lens) async {
    final origin = _origins[lens];
    final doc = documents.documentForPath(path);
    if (origin == null || doc == null) return lens;
    final provider = origin.provider as CodeLensProvider;
    if (!provider.canResolveCodeLens) return lens;
    final resolved = await _safe(
      () => provider.resolveCodeLens(
        doc,
        origin.value as CodeLens,
        CancellationToken.none,
      ),
    );
    if (resolved == null) return lens;
    return _withOrigin(
      CodeLens(
        _editorRange(origin.uri, resolved.range),
        id: resolved.id,
        command: resolved.command,
      ),
      provider,
      resolved,
      origin.uri,
    );
  }

  InlayHint _editorInlayHint(VsUri uri, InlayHint hint) => InlayHint(
    label: [
      for (final part in hint.label)
        InlayHintLabelPart(
          part.label,
          tooltip: part.tooltip,
          command: part.command,
          location: part.location == null
              ? null
              : Location(
                  part.location!.uri,
                  _editorRange(part.location!.uri, part.location!.range),
                ),
        ),
    ],
    position: _editorPosition(uri, hint.position),
    tooltip: hint.tooltip,
    textEdits: hint.textEdits == null
        ? null
        : [for (final edit in hint.textEdits!) _editorTextEdit(uri, edit)],
    kind: hint.kind,
    paddingLeft: hint.paddingLeft,
    paddingRight: hint.paddingRight,
    data: hint.data,
  );

  /// `InlayHintsFragments.create`: every provider's hints in [range],
  /// sorted by position.
  Future<List<InlayHint>> inlayHints(String path, Range range) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final providers = service.inlayHintsProvider.ordered(doc).reversed.toList();
    final modelRange = Range.fromPositions(
      doc.toModelPosition(range.getStartPosition()),
      doc.toModelPosition(range.getEndPosition()),
    );
    final lists = await Future.wait([
      for (final provider in providers)
        _safe(
          () => provider.provideInlayHints(
            doc,
            modelRange,
            CancellationToken.none,
          ),
        ),
    ]);
    _retain('inlayHints:$path', [for (final list in lists) ?list]);
    final hints = [
      for (var i = 0; i < lists.length; i++)
        for (final hint in lists[i]?.hints ?? const <InlayHint>[])
          _withOrigin(
            _editorInlayHint(doc.uri, hint),
            providers[i],
            hint,
            doc.uri,
          ),
    ];
    stableSort(hints, (a, b) => Position.compare(a.position, b.position));
    return hints;
  }

  Future<InlayHint> resolveInlayHint(InlayHint hint) async {
    final origin = _origins[hint];
    if (origin == null) return hint;
    final provider = origin.provider as InlayHintsProvider;
    if (!provider.canResolveInlayHint) return hint;
    final resolved = await _safe(
      () => provider.resolveInlayHint(
        origin.value as InlayHint,
        CancellationToken.none,
      ),
    );
    if (resolved == null) return hint;
    return _withOrigin(
      _editorInlayHint(origin.uri, resolved),
      provider,
      resolved,
      origin.uri,
    );
  }

  /// `getLinks`: every provider's links; overlapping links from a
  /// lower-ranked provider give way (`LinksList._union`).
  Future<List<Link>> documentLinks(String path) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final providers = service.linkProvider.ordered(doc).reversed.toList();
    final lists = await Future.wait([
      for (final provider in providers)
        _safe(() => provider.provideLinks(doc, CancellationToken.none)),
    ]);
    _retain('links:$path', [for (final list in lists) ?list]);
    var links = <({Link link, LinkProvider provider})>[];
    for (var i = 0; i < lists.length; i++) {
      final list = lists[i];
      if (list == null) continue;
      links = _unionLinks(links, [
        for (final link in list.links) (link: link, provider: providers[i]),
      ]);
    }
    return [
      for (final (:link, :provider) in links)
        _withOrigin(
          Link(
            _editorRange(doc.uri, link.range),
            url: link.url,
            tooltip: link.tooltip,
            data: link.data,
          ),
          provider,
          link,
          doc.uri,
        ),
    ];
  }

  static List<({Link link, LinkProvider provider})> _unionLinks(
    List<({Link link, LinkProvider provider})> oldLinks,
    List<({Link link, LinkProvider provider})> newLinks,
  ) {
    // reunite oldLinks with newLinks and remove duplicates
    final result = <({Link link, LinkProvider provider})>[];
    var oldIndex = 0;
    var newIndex = 0;
    while (oldIndex < oldLinks.length && newIndex < newLinks.length) {
      final oldLink = oldLinks[oldIndex];
      final newLink = newLinks[newIndex];
      if (Range.areIntersectingOrTouching(
        oldLink.link.range,
        newLink.link.range,
      )) {
        // Remove the oldLink
        oldIndex++;
        continue;
      }
      if (Range.compareRangesUsingStarts(
            oldLink.link.range,
            newLink.link.range,
          ) <
          0) {
        // oldLink is before
        result.add(oldLink);
        oldIndex++;
      } else {
        // newLink is before
        result.add(newLink);
        newIndex++;
      }
    }
    result
      ..addAll(oldLinks.skip(oldIndex))
      ..addAll(newLinks.skip(newIndex));
    return result;
  }

  Future<Link> resolveLink(Link link) async {
    final origin = _origins[link];
    if (origin == null) return link;
    final provider = origin.provider as LinkProvider;
    if (!provider.canResolveLink) return link;
    final resolved = await _safe(
      () => provider.resolveLink(origin.value as Link, CancellationToken.none),
    );
    if (resolved == null) return link;
    return _withOrigin(
      Link(
        _editorRange(origin.uri, resolved.range),
        url: resolved.url,
        tooltip: resolved.tooltip,
        data: resolved.data,
      ),
      provider,
      resolved,
      origin.uri,
    );
  }

  /// `getColors`: every provider's colors (last provider first, as
  /// `_findColorData` walks them).
  Future<List<ColorInformation>> documentColors(String path) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final providers = service.colorProvider.ordered(doc).reversed.toList();
    final results = await Future.wait([
      for (final provider in providers)
        _safe(
          () => provider.provideDocumentColors(doc, CancellationToken.none),
        ),
    ]);
    return [
      for (var i = 0; i < results.length; i++)
        for (final info in results[i] ?? const <ColorInformation>[])
          _withOrigin(
            ColorInformation(
              _editorRange(doc.uri, info.range),
              info.color,
              data: info.data,
            ),
            providers[i],
            info,
            doc.uri,
          ),
    ];
  }

  /// `getColorPresentations` from the provider of [color]: of [preview]
  /// (the picked color; [color]'s own by default) at [range] (editor
  /// coordinates of the color's text now; where the provider found it by
  /// default).
  Future<List<ColorPresentation>> colorPresentations(
    String path,
    ColorInformation color, {
    Color? preview,
    IRange? range,
  }) async {
    final origin = _origins[color];
    final doc = documents.documentForPath(path);
    if (origin == null || doc == null) return const [];
    final original = origin.value as ColorInformation;
    final modelRange = range == null
        ? original.range
        : Range.fromPositions(
            doc.toModelPosition(Range.startPositionOf(range)),
            doc.toModelPosition(Range.endPositionOf(range)),
          );
    final result = await _safe(
      () =>
          (origin.provider as DocumentColorProvider).provideColorPresentations(
            doc,
            ColorInformation(
              modelRange,
              preview ?? color.color,
              data: original.data,
            ),
            CancellationToken.none,
          ),
    );
    return [
      for (final presentation in result ?? const <ColorPresentation>[])
        ColorPresentation(
          presentation.label,
          textEdit: presentation.textEdit == null
              ? null
              : _editorTextEdit(doc.uri, presentation.textEdit!),
          additionalTextEdits: presentation.additionalTextEdits == null
              ? null
              : [
                  for (final edit in presentation.additionalTextEdits!)
                    _editorTextEdit(doc.uri, edit),
                ],
        ),
    ];
  }

  /// `collectSyntaxRanges`: every provider's valid ranges, with the
  /// provider's rank; null when no provider answered.
  Future<List<({FoldingRange range, int rank})>?> foldingRanges(
    String path,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return null;
    final providers = service.foldingRangeProvider.ordered(doc);
    final results = await Future.wait([
      for (final provider in providers)
        _safe(
          () => provider.provideFoldingRanges(
            doc,
            const FoldingContext(),
            CancellationToken.none,
          ),
        ),
    ]);
    List<({FoldingRange range, int rank})>? rangeData;
    final nLines = doc.lineCount;
    for (var i = 0; i < results.length; i++) {
      final ranges = results[i];
      if (ranges == null) continue;
      rangeData ??= [];
      for (final r in ranges) {
        if (r.start > 0 && r.end > r.start && r.end <= nLines) {
          rangeData.add((range: r, rank: i));
        }
      }
    }
    return rangeData;
  }

  /// `provideSelectionRanges` (providers only): for each position, the
  /// ranges containing it, innermost first.
  Future<List<List<Range>>> selectionRanges(
    String path,
    List<Position> positions,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    return selectionRangesForDocument(doc, positions);
  }

  /// [selectionRanges] for a document already in hand; [positions] are
  /// model coordinates.
  Future<List<List<Range>>> selectionRangesForDocument(
    LanguageFeatureDocument doc,
    List<Position> positions,
  ) async {
    final modelPositions = [
      for (final position in positions) doc.toModelPosition(position),
    ];
    final all = List.generate(positions.length, (_) => <Range>[]);
    await Future.wait([
      for (final provider in service.selectionRangeProvider.all(doc))
        _safe(
          () => provider.provideSelectionRanges(
            doc,
            modelPositions,
            CancellationToken.none,
          ),
        ).then((allProviderRanges) {
          if (allProviderRanges == null ||
              allProviderRanges.length != positions.length) {
            return;
          }
          for (var i = 0; i < positions.length; i++) {
            for (final one in allProviderRanges[i]) {
              if (Range.containsPositionInRange(one.range, modelPositions[i])) {
                all[i].add(Range.lift(one.range)!);
              }
            }
          }
        }),
    ]);
    return [
      for (final ranges in all)
        () {
          // sort all by start/end position
          stableSort(ranges, (a, b) {
            if (Position.isBeforePositions(
              a.getStartPosition(),
              b.getStartPosition(),
            )) {
              return 1;
            } else if (Position.isBeforePositions(
              b.getStartPosition(),
              a.getStartPosition(),
            )) {
              return -1;
            } else if (Position.isBeforePositions(
              a.getEndPosition(),
              b.getEndPosition(),
            )) {
              return -1;
            } else if (Position.isBeforePositions(
              b.getEndPosition(),
              a.getEndPosition(),
            )) {
              return 1;
            }
            return 0;
          });
          final result = <Range>[];
          for (final range in ranges) {
            if (result.isEmpty ||
                (Range.containsRangeInRange(range, result.last) &&
                    !range.equalsRange(result.last))) {
              result.add(range);
            }
          }
          return [for (final range in result) _editorRange(doc.uri, range)];
        }(),
    ];
  }

  WorkspaceSymbol _editorWorkspaceSymbol(WorkspaceSymbol symbol) =>
      WorkspaceSymbol(
        name: symbol.name,
        kind: symbol.kind,
        containerName: symbol.containerName,
        tags: symbol.tags,
        data: symbol.data,
        location: Location(
          symbol.location.uri,
          _editorRange(symbol.location.uri, symbol.location.range),
        ),
      );

  /// `getWorkspaceSymbols`: every provider's symbols; resolvable providers'
  /// symbols first.
  Future<List<WorkspaceSymbol>> workspaceSymbols(String query) async {
    final providers = service.workspaceSymbolProviders;
    final results = await Future.wait([
      for (final provider in providers)
        _safe(
          () => provider.provideWorkspaceSymbols(query, CancellationToken.none),
        ),
    ]);
    final all = [
      for (var i = 0; i < results.length; i++)
        for (final symbol in results[i] ?? const <WorkspaceSymbol>[])
          (symbol: symbol, provider: providers[i]),
    ];
    stableSort(all, (a, b) {
      final aResolve = a.provider.canResolveWorkspaceSymbol;
      final bResolve = b.provider.canResolveWorkspaceSymbol;
      if (aResolve && !bResolve) return -1;
      if (!aResolve && bResolve) return 1;
      return 0;
    });
    return [
      for (final (:symbol, :provider) in all)
        _withOrigin(
          _editorWorkspaceSymbol(symbol),
          provider,
          symbol,
          symbol.location.uri,
        ),
    ];
  }

  Future<WorkspaceSymbol> resolveWorkspaceSymbol(WorkspaceSymbol symbol) async {
    final origin = _origins[symbol];
    if (origin == null) return symbol;
    final provider = origin.provider as WorkspaceSymbolProvider;
    if (!provider.canResolveWorkspaceSymbol) return symbol;
    final resolved = await _safe(
      () => provider.resolveWorkspaceSymbol(
        origin.value as WorkspaceSymbol,
        CancellationToken.none,
      ),
    );
    if (resolved == null) return symbol;
    return _withOrigin(
      _editorWorkspaceSymbol(resolved),
      provider,
      resolved,
      resolved.location.uri,
    );
  }

  HierarchyItem _editorHierarchyItem(HierarchyItem item) => HierarchyItem(
    sessionId: item.sessionId,
    itemId: item.itemId,
    kind: item.kind,
    name: item.name,
    detail: item.detail,
    uri: item.uri,
    range: _editorRange(item.uri, item.range),
    selectionRange: _editorRange(item.uri, item.selectionRange),
    tags: item.tags,
  );

  HierarchyItem _hierarchyItem(Object provider, HierarchyItem item) =>
      _withOrigin(_editorHierarchyItem(item), provider, item, item.uri);

  final _hierarchySessions = <String, HierarchySession>{};

  /// `CallHierarchyModel.create`: the first provider's roots.
  Future<List<CallHierarchyItem>> prepareCallHierarchy(
    String path,
    Position position,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final providers = service.callHierarchyProvider.ordered(doc);
    if (providers.isEmpty) return const [];
    final session = await _safe(
      () => providers.first.prepareCallHierarchy(
        doc,
        doc.toModelPosition(position),
        CancellationToken.none,
      ),
    );
    _hierarchySessions.remove('call:$path')?.dispose();
    if (session == null) return const [];
    _hierarchySessions['call:$path'] = session;
    return [
      for (final root in session.roots) _hierarchyItem(providers.first, root),
    ];
  }

  Future<List<({CallHierarchyItem from, List<Range> fromRanges})>>
  incomingCalls(CallHierarchyItem item) async {
    final origin = _origins[item];
    if (origin == null) return const [];
    final provider = origin.provider as CallHierarchyProvider;
    final calls = await _safe(
      () => provider.provideIncomingCalls(
        origin.value as HierarchyItem,
        CancellationToken.none,
      ),
    );
    return [
      for (final call in calls ?? const <IncomingCall>[])
        (
          from: _hierarchyItem(provider, call.from),
          fromRanges: [
            for (final range in call.fromRanges)
              _editorRange(call.from.uri, range),
          ],
        ),
    ];
  }

  Future<List<({CallHierarchyItem to, List<Range> fromRanges})>> outgoingCalls(
    CallHierarchyItem item,
  ) async {
    final origin = _origins[item];
    if (origin == null) return const [];
    final provider = origin.provider as CallHierarchyProvider;
    final original = origin.value as HierarchyItem;
    final calls = await _safe(
      () => provider.provideOutgoingCalls(original, CancellationToken.none),
    );
    return [
      for (final call in calls ?? const <OutgoingCall>[])
        (
          to: _hierarchyItem(provider, call.to),
          fromRanges: [
            for (final range in call.fromRanges)
              _editorRange(original.uri, range),
          ],
        ),
    ];
  }

  /// `TypeHierarchyModel.create`: the first provider's roots.
  Future<List<TypeHierarchyItem>> prepareTypeHierarchy(
    String path,
    Position position,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final providers = service.typeHierarchyProvider.ordered(doc);
    if (providers.isEmpty) return const [];
    final session = await _safe(
      () => providers.first.prepareTypeHierarchy(
        doc,
        doc.toModelPosition(position),
        CancellationToken.none,
      ),
    );
    _hierarchySessions.remove('type:$path')?.dispose();
    if (session == null) return const [];
    _hierarchySessions['type:$path'] = session;
    return [
      for (final root in session.roots) _hierarchyItem(providers.first, root),
    ];
  }

  Future<List<TypeHierarchyItem>> supertypes(TypeHierarchyItem item) =>
      _typeHierarchy(item, supertypes: true);

  Future<List<TypeHierarchyItem>> subtypes(TypeHierarchyItem item) =>
      _typeHierarchy(item, supertypes: false);

  Future<List<TypeHierarchyItem>> _typeHierarchy(
    TypeHierarchyItem item, {
    required bool supertypes,
  }) async {
    final origin = _origins[item];
    if (origin == null) return const [];
    final provider = origin.provider as TypeHierarchyProvider;
    final original = origin.value as HierarchyItem;
    final items = await _safe(
      () => supertypes
          ? provider.provideSupertypes(original, CancellationToken.none)
          : provider.provideSubtypes(original, CancellationToken.none),
    );
    return [
      for (final item in items ?? const <HierarchyItem>[])
        _hierarchyItem(provider, item),
    ];
  }

  InlineCompletion _editorInlineCompletion(VsUri uri, InlineCompletion item) =>
      InlineCompletion(
        insertText: item.insertText,
        snippet: item.snippet,
        range: item.range == null ? null : _editorRange(uri, item.range!),
        additionalTextEdits: item.additionalTextEdits == null
            ? null
            : [
                for (final edit in item.additionalTextEdits!)
                  SingleEditOperation(
                    _editorRange(uri, edit.range),
                    edit.text,
                    forceMoveMarkers: edit.forceMoveMarkers,
                  ),
              ],
        command: item.command,
        completeBracketPairs: item.completeBracketPairs,
        isInlineEdit: item.isInlineEdit,
        showRange: item.showRange == null
            ? null
            : _editorRange(uri, item.showRange!),
        correlationId: item.correlationId,
      );

  /// Every inline completion provider's answer at [position], in provider
  /// order. Dispose each result when done.
  Future<List<InlineCompletionsResult>> inlineCompletions(
    String path,
    Position position,
    InlineCompletionContext context,
  ) async {
    final doc = documents.documentForPath(path);
    if (doc == null) return const [];
    final providers = service.inlineCompletionsProvider.ordered(doc);
    final results = await Future.wait([
      for (final provider in providers)
        _safe(
          () => provider.provideInlineCompletions(
            doc,
            doc.toModelPosition(position),
            context,
            CancellationToken.none,
          ),
        ),
    ]);
    return [
      for (var i = 0; i < results.length; i++)
        if (results[i] case final completions?)
          InlineCompletionsResult(providers[i], completions, [
            for (final item in completions.items)
              _editorInlineCompletion(doc.uri, item),
          ]),
    ];
  }

  @override
  void dispose() {
    markers.removeListener(notifyListeners);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    for (final results in _retained.values) {
      for (final result in results) {
        result.dispose();
      }
    }
    _retained.clear();
    for (final session in _hierarchySessions.values) {
      session.dispose();
    }
    for (final entry in _semanticTokens.values) {
      entry.provider.releaseDocumentSemanticTokens(entry.resultId);
    }
    _workspaceEdits.close();
    super.dispose();
  }
}
