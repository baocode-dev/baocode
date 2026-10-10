/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The language feature provider contracts. Extension-host-backed providers
// (`MainThreadLanguageFeatures`) extend these and register in the
// [LanguageFeaturesService] registries; positions and ranges are one-based
// model coordinates.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/languages.ts (`HoverProvider`,
// `CompletionItemProvider`, `InlineCompletionsProvider`,
// `CodeActionProvider`, `SignatureHelpProvider`,
// `DocumentHighlightProvider`, `LinkedEditingRangeProvider`,
// `ReferenceProvider`, `DefinitionProvider`, `DeclarationProvider`,
// `ImplementationProvider`, `TypeDefinitionProvider`,
// `DocumentSymbolProvider`, `DocumentFormattingEditProvider`,
// `DocumentRangeFormattingEditProvider`, `OnTypeFormattingEditProvider`,
// `LinkProvider`, `DocumentColorProvider`, `SelectionRangeProvider`,
// `FoldingRangeProvider`, `RenameProvider`, `CodeLensProvider`,
// `InlayHintsProvider`, `DocumentSemanticTokensProvider`,
// `DocumentRangeSemanticTokensProvider`),
// src/vs/workbench/contrib/search/common/search.ts
// (`IWorkspaceSymbolProvider`), callHierarchy.ts, typeHierarchy.ts.
//
// Deviations:
// - Optional methods (`resolveCompletionItem?` …) have a default body and a
//   `canResolve…` flag the callers check instead of the method's presence.
// - `ProviderResult<T>` is `FutureOr<T?>`; `Event`s are nullable streams.
// - `_debugDisplayName`, `extensionId` and `displayName` are on
//   [LanguageFeatureProvider].

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show CancellationToken;

import 'language_feature_document.dart';
import 'language_types.dart';

/// What every provider may tell about itself.
abstract class LanguageFeatureProvider {
  /// The contributing extension (`publisher.name`), if any.
  String? get extensionId => null;

  /// A name for pickers and logs.
  String? get displayName => null;
}

abstract class HoverProvider extends LanguageFeatureProvider {
  FutureOr<Hover?> provideHover(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token, [
    HoverContext? context,
  ]);
}

abstract class CompletionItemProvider extends LanguageFeatureProvider {
  List<String> get triggerCharacters => const [];

  FutureOr<CompletionList?> provideCompletionItems(
    LanguageFeatureDocument model,
    Position position,
    CompletionContext context,
    CancellationToken token,
  );

  bool get canResolveCompletionItem => false;

  /// Fills in documentation/details; the editor resolves an item once.
  FutureOr<CompletionItem?> resolveCompletionItem(
    CompletionItem item,
    CancellationToken token,
  ) => item;
}

abstract class InlineCompletionsProvider extends LanguageFeatureProvider {
  FutureOr<InlineCompletions?> provideInlineCompletions(
    LanguageFeatureDocument model,
    Position position,
    InlineCompletionContext context,
    CancellationToken token,
  );

  void handleItemDidShow(
    InlineCompletions completions,
    InlineCompletion item,
    String updatedInsertText,
  ) {}

  void handlePartialAccept(
    InlineCompletions completions,
    InlineCompletion item,
    int acceptedCharacters,
  ) {}

  void handleRejection(InlineCompletions completions, InlineCompletion item) {}

  /// Releases [completions] (the extension host's cache).
  void disposeInlineCompletions(
    InlineCompletions completions,
    InlineCompletionsDisposeReason reason,
  );

  Stream<void>? get onDidChangeInlineCompletions => null;
  String? get groupId => null;
  List<String> get yieldsToGroupIds => const [];
  List<String> get excludesGroupIds => const [];
  int? get debounceDelayMs => null;
}

abstract class CodeActionProvider extends LanguageFeatureProvider {
  FutureOr<CodeActionList?> provideCodeActions(
    LanguageFeatureDocument model,
    Range range,
    CodeActionContext context,
    CancellationToken token,
  );

  bool get canResolveCodeAction => false;

  FutureOr<CodeAction?> resolveCodeAction(
    CodeAction codeAction,
    CancellationToken token,
  ) => codeAction;

  /// The kinds it may return; null when unknown.
  List<String>? get providedCodeActionKinds => null;

  /// Documentation commands by kind.
  List<({String kind, Command command})> get documentation => const [];
}

abstract class SignatureHelpProvider extends LanguageFeatureProvider {
  List<String> get signatureHelpTriggerCharacters => const [];
  List<String> get signatureHelpRetriggerCharacters => const [];

  FutureOr<SignatureHelpResult?> provideSignatureHelp(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
    SignatureHelpContext context,
  );
}

abstract class DocumentHighlightProvider extends LanguageFeatureProvider {
  FutureOr<List<DocumentHighlight>?> provideDocumentHighlights(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  );
}

abstract class LinkedEditingRangeProvider extends LanguageFeatureProvider {
  FutureOr<LinkedEditingRanges?> provideLinkedEditingRanges(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  );
}

abstract class ReferenceProvider extends LanguageFeatureProvider {
  FutureOr<List<Location>?> provideReferences(
    LanguageFeatureDocument model,
    Position position,
    ReferenceContext context,
    CancellationToken token,
  );
}

/// `DefinitionProvider`: a `Definition` (`Location | Location[]`) is a list
/// of plain links.
abstract class DefinitionProvider extends LanguageFeatureProvider {
  FutureOr<List<LocationLink>?> provideDefinition(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  );
}

abstract class DeclarationProvider extends LanguageFeatureProvider {
  FutureOr<List<LocationLink>?> provideDeclaration(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  );
}

abstract class ImplementationProvider extends LanguageFeatureProvider {
  FutureOr<List<LocationLink>?> provideImplementation(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  );
}

abstract class TypeDefinitionProvider extends LanguageFeatureProvider {
  FutureOr<List<LocationLink>?> provideTypeDefinition(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  );
}

abstract class DocumentSymbolProvider extends LanguageFeatureProvider {
  FutureOr<List<DocumentSymbol>?> provideDocumentSymbols(
    LanguageFeatureDocument model,
    CancellationToken token,
  );
}

abstract class WorkspaceSymbolProvider extends LanguageFeatureProvider {
  FutureOr<List<WorkspaceSymbol>?> provideWorkspaceSymbols(
    String search,
    CancellationToken token,
  );

  bool get canResolveWorkspaceSymbol => false;

  FutureOr<WorkspaceSymbol?> resolveWorkspaceSymbol(
    WorkspaceSymbol item,
    CancellationToken token,
  ) => item;
}

abstract class DocumentFormattingEditProvider extends LanguageFeatureProvider {
  FutureOr<List<TextEdit>?> provideDocumentFormattingEdits(
    LanguageFeatureDocument model,
    FormattingOptions options,
    CancellationToken token,
  );
}

abstract class DocumentRangeFormattingEditProvider
    extends LanguageFeatureProvider {
  FutureOr<List<TextEdit>?> provideDocumentRangeFormattingEdits(
    LanguageFeatureDocument model,
    Range range,
    FormattingOptions options,
    CancellationToken token,
  );

  bool get canFormatRanges => false;

  FutureOr<List<TextEdit>?> provideDocumentRangesFormattingEdits(
    LanguageFeatureDocument model,
    List<Range> ranges,
    FormattingOptions options,
    CancellationToken token,
  ) => null;
}

abstract class OnTypeFormattingEditProvider extends LanguageFeatureProvider {
  List<String> get autoFormatTriggerCharacters;

  FutureOr<List<TextEdit>?> provideOnTypeFormattingEdits(
    LanguageFeatureDocument model,
    Position position,
    String ch,
    FormattingOptions options,
    CancellationToken token,
  );
}

abstract class LinkProvider extends LanguageFeatureProvider {
  FutureOr<LinksList?> provideLinks(
    LanguageFeatureDocument model,
    CancellationToken token,
  );

  bool get canResolveLink => false;

  FutureOr<Link?> resolveLink(Link link, CancellationToken token) => link;
}

abstract class DocumentColorProvider extends LanguageFeatureProvider {
  FutureOr<List<ColorInformation>?> provideDocumentColors(
    LanguageFeatureDocument model,
    CancellationToken token,
  );

  FutureOr<List<ColorPresentation>?> provideColorPresentations(
    LanguageFeatureDocument model,
    ColorInformation colorInfo,
    CancellationToken token,
  );
}

abstract class SelectionRangeProvider extends LanguageFeatureProvider {
  /// One list of ranges (innermost first) per position.
  FutureOr<List<List<SelectionRange>>?> provideSelectionRanges(
    LanguageFeatureDocument model,
    List<Position> positions,
    CancellationToken token,
  );
}

abstract class FoldingRangeProvider extends LanguageFeatureProvider {
  Stream<void>? get onDidChange => null;

  FutureOr<List<FoldingRange>?> provideFoldingRanges(
    LanguageFeatureDocument model,
    FoldingContext context,
    CancellationToken token,
  );
}

abstract class RenameProvider extends LanguageFeatureProvider {
  FutureOr<WorkspaceEdit?> provideRenameEdits(
    LanguageFeatureDocument model,
    Position position,
    String newName,
    CancellationToken token,
  );

  bool get canResolveRenameLocation => false;

  FutureOr<RenameLocation?> resolveRenameLocation(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) => null;
}

abstract class CodeLensProvider extends LanguageFeatureProvider {
  Stream<void>? get onDidChange => null;

  FutureOr<CodeLensList?> provideCodeLenses(
    LanguageFeatureDocument model,
    CancellationToken token,
  );

  bool get canResolveCodeLens => false;

  FutureOr<CodeLens?> resolveCodeLens(
    LanguageFeatureDocument model,
    CodeLens codeLens,
    CancellationToken token,
  ) => codeLens;
}

abstract class InlayHintsProvider extends LanguageFeatureProvider {
  Stream<void>? get onDidChangeInlayHints => null;

  FutureOr<InlayHintList?> provideInlayHints(
    LanguageFeatureDocument model,
    Range range,
    CancellationToken token,
  );

  bool get canResolveInlayHint => false;

  FutureOr<InlayHint?> resolveInlayHint(
    InlayHint hint,
    CancellationToken token,
  ) => hint;
}

abstract class DocumentSemanticTokensProvider extends LanguageFeatureProvider {
  Stream<void>? get onDidChange => null;

  SemanticTokensLegend getLegend();

  /// Full tokens, or edits to the result [lastResultId] named.
  FutureOr<SemanticTokensResult?> provideDocumentSemanticTokens(
    LanguageFeatureDocument model,
    String? lastResultId,
    CancellationToken token,
  );

  void releaseDocumentSemanticTokens(String? resultId);
}

abstract class DocumentRangeSemanticTokensProvider
    extends LanguageFeatureProvider {
  Stream<void>? get onDidChange => null;

  SemanticTokensLegend getLegend();

  FutureOr<SemanticTokens?> provideDocumentRangeSemanticTokens(
    LanguageFeatureDocument model,
    Range range,
    CancellationToken token,
  );
}

abstract class CallHierarchyProvider extends LanguageFeatureProvider {
  FutureOr<HierarchySession?> prepareCallHierarchy(
    LanguageFeatureDocument document,
    Position position,
    CancellationToken token,
  );

  FutureOr<List<IncomingCall>?> provideIncomingCalls(
    CallHierarchyItem item,
    CancellationToken token,
  );

  FutureOr<List<OutgoingCall>?> provideOutgoingCalls(
    CallHierarchyItem item,
    CancellationToken token,
  );
}

abstract class TypeHierarchyProvider extends LanguageFeatureProvider {
  FutureOr<HierarchySession?> prepareTypeHierarchy(
    LanguageFeatureDocument document,
    Position position,
    CancellationToken token,
  );

  FutureOr<List<TypeHierarchyItem>?> provideSupertypes(
    TypeHierarchyItem item,
    CancellationToken token,
  );

  FutureOr<List<TypeHierarchyItem>?> provideSubtypes(
    TypeHierarchyItem item,
    CancellationToken token,
  );
}
