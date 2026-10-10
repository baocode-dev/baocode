/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// One registry per language feature.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/services/languageFeaturesService.ts
// (`LanguageFeaturesService`), `WorkspaceSymbolProviderRegistry`
// (src/vs/workbench/contrib/search/common/search.ts),
// `CallHierarchyProviderRegistry`/`TypeHierarchyProviderRegistry`.
//
// Deviations:
// - No registries for features BaoCode does not host (multi-document
//   highlights, new symbol names, inline values, evaluatable expressions,
//   drop/paste edits); workspace symbols and call/type hierarchy live here
//   instead of in global namespaces.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import 'language_feature_registry.dart';
import 'language_providers.dart';

/// Which registry changed, and how many providers it has now.
class LanguageFeatureChange {
  const LanguageFeatureChange(this.name, this.count);

  /// The feature's name, as a provider kind (`hover`, `completion`…).
  final String name;
  final int count;
}

class LanguageFeaturesService {
  NotebookInfoResolver? _notebookTypeResolver;

  final _onDidChangeProviders =
      StreamController<LanguageFeatureChange>.broadcast(sync: true);

  /// A provider was registered or unregistered (`onDidChange` of every
  /// registry, merged).
  Stream<LanguageFeatureChange> get onDidChangeProviders =>
      _onDidChangeProviders.stream;

  final _subscriptions = <StreamSubscription<int>>[];
  bool _listening = false;

  void _listen() {
    if (_listening) return;
    _listening = true;
    for (final (name, registry) in _namedRegistries) {
      _subscriptions.add(
        registry.onDidChange.listen(
          (count) => _onDidChangeProviders.add(
            LanguageFeatureChange(name, count),
          ),
        ),
      );
    }
  }

  List<(String, LanguageFeatureRegistry<Object?>)> get _namedRegistries => [
    ('reference', referenceProvider),
    ('rename', renameProvider),
    ('codeAction', codeActionProvider),
    ('definition', definitionProvider),
    ('typeDefinition', typeDefinitionProvider),
    ('declaration', declarationProvider),
    ('implementation', implementationProvider),
    ('documentSymbol', documentSymbolProvider),
    ('inlayHints', inlayHintsProvider),
    ('color', colorProvider),
    ('codeLens', codeLensProvider),
    ('documentFormattingEdit', documentFormattingEditProvider),
    ('documentRangeFormattingEdit', documentRangeFormattingEditProvider),
    ('onTypeFormattingEdit', onTypeFormattingEditProvider),
    ('signatureHelp', signatureHelpProvider),
    ('hover', hoverProvider),
    ('documentHighlight', documentHighlightProvider),
    ('selectionRange', selectionRangeProvider),
    ('foldingRange', foldingRangeProvider),
    ('link', linkProvider),
    ('inlineCompletions', inlineCompletionsProvider),
    ('completion', completionProvider),
    ('linkedEditingRange', linkedEditingRangeProvider),
    ('documentRangeSemanticTokens', documentRangeSemanticTokensProvider),
    ('documentSemanticTokens', documentSemanticTokensProvider),
    ('callHierarchy', callHierarchyProvider),
    ('typeHierarchy', typeHierarchyProvider),
  ];

  void setNotebookTypeResolver(NotebookInfoResolver? resolver) =>
      _notebookTypeResolver = resolver;

  NotebookInfo? _score(VsUri uri) => _notebookTypeResolver?.call(uri);

  LanguageFeatureRegistry<T> _registry<T>() =>
      LanguageFeatureRegistry<T>(_score);

  late final referenceProvider = _registry<ReferenceProvider>();
  late final renameProvider = _registry<RenameProvider>();
  late final codeActionProvider = _registry<CodeActionProvider>();
  late final definitionProvider = _registry<DefinitionProvider>();
  late final typeDefinitionProvider = _registry<TypeDefinitionProvider>();
  late final declarationProvider = _registry<DeclarationProvider>();
  late final implementationProvider = _registry<ImplementationProvider>();
  late final documentSymbolProvider = _registry<DocumentSymbolProvider>();
  late final inlayHintsProvider = _registry<InlayHintsProvider>();
  late final colorProvider = _registry<DocumentColorProvider>();
  late final codeLensProvider = _registry<CodeLensProvider>();
  late final documentFormattingEditProvider =
      _registry<DocumentFormattingEditProvider>();
  late final documentRangeFormattingEditProvider =
      _registry<DocumentRangeFormattingEditProvider>();
  late final onTypeFormattingEditProvider =
      _registry<OnTypeFormattingEditProvider>();
  late final signatureHelpProvider = _registry<SignatureHelpProvider>();
  late final hoverProvider = _registry<HoverProvider>();
  late final documentHighlightProvider = _registry<DocumentHighlightProvider>();
  late final selectionRangeProvider = _registry<SelectionRangeProvider>();
  late final foldingRangeProvider = _registry<FoldingRangeProvider>();
  late final linkProvider = _registry<LinkProvider>();
  late final inlineCompletionsProvider = _registry<InlineCompletionsProvider>();
  late final completionProvider = _registry<CompletionItemProvider>();
  late final linkedEditingRangeProvider =
      _registry<LinkedEditingRangeProvider>();
  late final documentRangeSemanticTokensProvider =
      _registry<DocumentRangeSemanticTokensProvider>();
  late final documentSemanticTokensProvider =
      _registry<DocumentSemanticTokensProvider>();
  late final callHierarchyProvider = _registry<CallHierarchyProvider>();
  late final typeHierarchyProvider = _registry<TypeHierarchyProvider>();

  /// `WorkspaceSymbolProviderRegistry`: not per document.
  final List<WorkspaceSymbolProvider> _workspaceSymbolProviders = [];

  List<WorkspaceSymbolProvider> get workspaceSymbolProviders =>
      List.unmodifiable(_workspaceSymbolProviders);

  FeatureRegistration registerWorkspaceSymbolProvider(
    WorkspaceSymbolProvider provider,
  ) {
    _workspaceSymbolProviders.add(provider);
    _onDidChangeProviders.add(
      LanguageFeatureChange('workspaceSymbol', _workspaceSymbolProviders.length),
    );
    return FeatureRegistration(() {
      _workspaceSymbolProviders.remove(provider);
      _onDidChangeProviders.add(
        LanguageFeatureChange(
          'workspaceSymbol',
          _workspaceSymbolProviders.length,
        ),
      );
    });
  }

  /// Every registry, for change listening.
  List<LanguageFeatureRegistry<Object?>> get registries {
    _listen();
    return _registryList;
  }

  List<LanguageFeatureRegistry<Object?>> get _registryList => [
    referenceProvider,
    renameProvider,
    codeActionProvider,
    definitionProvider,
    typeDefinitionProvider,
    declarationProvider,
    implementationProvider,
    documentSymbolProvider,
    inlayHintsProvider,
    colorProvider,
    codeLensProvider,
    documentFormattingEditProvider,
    documentRangeFormattingEditProvider,
    onTypeFormattingEditProvider,
    signatureHelpProvider,
    hoverProvider,
    documentHighlightProvider,
    selectionRangeProvider,
    foldingRangeProvider,
    linkProvider,
    inlineCompletionsProvider,
    completionProvider,
    linkedEditingRangeProvider,
    documentRangeSemanticTokensProvider,
    documentSemanticTokensProvider,
    callHierarchyProvider,
    typeHierarchyProvider,
  ];

  /// Whether [name]'s registry has at least one provider now.
  bool hasAny(String name) => switch (name) {
    'workspaceSymbol' => _workspaceSymbolProviders.isNotEmpty,
    _ => _namedRegistries
        .where((entry) => entry.$1 == name)
        .any((entry) => entry.$2.allNoModel().isNotEmpty),
  };

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_onDidChangeProviders.close());
    for (final registry in registries) {
      registry.dispose();
    }
  }
}
