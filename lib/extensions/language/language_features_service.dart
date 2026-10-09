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

import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import 'language_feature_registry.dart';
import 'language_providers.dart';

class LanguageFeaturesService {
  NotebookInfoResolver? _notebookTypeResolver;

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
    return FeatureRegistration(
      () => _workspaceSymbolProviders.remove(provider),
    );
  }

  /// Every registry, for change listening.
  List<LanguageFeatureRegistry<Object?>> get registries => [
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

  void dispose() {
    for (final registry in registries) {
      registry.dispose();
    }
  }
}
