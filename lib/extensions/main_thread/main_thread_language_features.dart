/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The language features an extension host registers: every `$registerXxx` of
// `MainThreadLanguageFeatures` becomes a provider object in this app's
// registries (`lib/extensions/language/`), which asks the extension back
// through `ExtHostLanguageFeatures.$provideXxx` and revives its answer.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadLanguageFeatures.ts
// (`MainThreadLanguageFeatures` and its `_revive*`, `_inflateSuggestDto`,
// `MainThreadDocumentSemanticTokensProvider`,
// `MainThreadDocumentRangeSemanticTokensProvider`,
// `ExtensionBackedInlineCompletionsProvider`, the `Emitter` registrations for
// `$emitXxxEvent`, `$setLanguageConfiguration`).
//
// Deviations:
// - Providers are plain Dart objects in this app's registries rather than
//   upstream's `ILanguageFeaturesService` registrations; the registries live
//   in a `LanguageFeatureRoot` (see `language_customers.dart`).
// - Everything the app does not host is answered as unsupported by the port
//   (see the report): drop/paste edits, inline values, evaluatable
//   expressions, multi-document highlights, new symbol names, and the
//   inline-completion model-picker/option methods. Their registration calls
//   still register a provider where the editor can use one.
// - A request's `CancellationToken` is the RPC's (`RpcProtocol` appends one),
//   so a cancelled request does not reach the extension host.
// - `$registerXxx` names come from the generated actor; the handle space is
//   the root's, so a session's handles start over after a restart.

import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/languages/language_configuration.dart'
    show
        AutoClosingPair,
        AutoClosingPairConditional,
        CharacterPair,
        CommentRule,
        DocComment,
        EnterAction,
        IndentAction,
        IndentationRule,
        LanguageConfiguration,
        LineCommentConfig,
        OnEnterRule;
import 'package:bao_exthost/bao_exthost.dart';

import '../language/language_customers.dart';
import '../language/language_dto.dart' as dto;
import '../language/language_dto.dart'
    show CacheId, DeltaSemanticTokensDto, FullSemanticTokensDto;
import '../language/language_feature_document.dart';
import '../language/language_feature_registry.dart';
import '../language/language_providers.dart';
import '../language/language_selector.dart';
import '../language/language_types.dart';

/// One extension's language feature provider, as upstream's
/// `MainThreadLanguageFeatures` registers it.
final class MainThreadLanguageFeatures extends MainThreadLanguageFeaturesUnsupported {
  MainThreadLanguageFeatures({
    required this.root,
    required RpcProtocol proxy,
    this.activation,
    this.displayName,
    this.extensionId,
  }) : _rpc = proxy,
       _proxy = ExtHostLanguageFeaturesProxy(proxy);

  final LanguageFeatureRoot root;
  final ExtHostLanguageFeaturesProxy _proxy;

  /// The host's rpc: its session in [root].
  final RpcProtocol _rpc;

  /// Activates `onLanguage:<id>` for a newly registered selector.
  final ProviderActivation? activation;

  final String? displayName;
  final String? extensionId;

  /// The handles this actor answered for, so a re-registration of one is
  /// dropped (as upstream's `DisposableMap.set`).
  final _handles = <num>{};

  /// The emitters of `$emitXxxEvent`, by event handle.
  final _events = <num, StreamController<Object?>>{};

  /// The languages already activated, so a selector activates each once.
  final _activatedLanguages = <String>{};

  /// The registered providers by handle, so `$emitXxx` and `$resolveXxx`
  /// reach them (upstream's `_registrations`).
  final _providers = <num, Object>{};


  /// The selector of [selector], with upstream's `DocumentSelector.from`
  /// reading of the DTOs.
  LanguageSelector? _selector(List<Map<String, Object?>> selector) =>
      LanguageSelector.parse([
        for (final filter in selector)
          {
            'language': filter['language'],
            'scheme': filter['scheme'],
            'pattern': _pattern(filter['pattern']),
            'exclusive': filter['exclusive'] == true,
            'notebookType': filter['notebookType'],
            'isBuiltin': filter['isBuiltin'] == true,
          },
      ]);

  /// `IRelativePatternDto` to the glob's relative pattern (`base`/`pattern`),
  /// or the plain string.
  Object? _pattern(Object? value) => switch (value) {
    final String glob => glob,
    final Map<Object?, Object?> map when map['base'] is String =>
      (base: '${map['base']}', pattern: '${map['pattern']}'),
    final Map<Object?, Object?> map when map['baseUri'] is Map =>
      (
        base: _uriBase(map['baseUri']),
        pattern: '${map['pattern']}',
      ),
    _ => null,
  };

  String _uriBase(Object? value) {
    final uri = VsUri.tryRevive(value);
    return uri?.fsPath() ?? '';
  }

  /// The languages a selector's registration activates.
  void _activate(List<Map<String, Object?>> selector) {
    final activate = activation ?? root.activation;
    if (activate == null) return;
    final parsed = _selector(selector);
    if (parsed == null) return;
    final languages = <String>{};
    selectLanguageIds(parsed, languages);
    for (final languageId in languages) {
      if (languageId.isEmpty || !_activatedLanguages.add(languageId)) continue;
      unawaited(activate(LanguageIdSelector(languageId)));
    }
  }

  /// Whether [extensionId] may serve [selector]'s languages
  /// ([LanguageFeatureRoot.permits]): also activates them (upstream
  /// instantiates providers of the requested languages).
  bool _allow(String feature, List<Map<String, Object?>> selector) {
    final parsed = _selector(selector);
    final languages = <String>{};
    if (parsed != null) selectLanguageIds(parsed, languages);
    final id = extensionId;
    if (id == null || id.isEmpty) return true;
    if (root.gate == null) return true;
    return root.permits(id, feature, languages, displayName: displayName);
  }

  /// Registers [provider] under [handle] (which upstream's
  /// `DisposableMap.set` replaces, closing the old registration).
  void _set<T>(num handle, LanguageFeatureRegistry<T> registry,
      LanguageSelector selector, T provider) {
    _providers[handle] = provider as Object;
    root.track(
      handle,
      registry.register(selector, provider),
      session: _rpc,
    );
  }

  /// The provider registered under [handle], if any.
  T? providerOf<T extends Object>(num handle) {
    final value = _providers[handle];
    return value is T ? value : null;
  }

  /// The event stream of [handle], if any.
  StreamController<Object?>? eventStream(num handle) => _events[handle];

  /// The stream of `$emitXxxEvent(eventHandle)`, or null when there is none.
  Stream<Object?>? _eventStream(num? eventHandle) {
    if (eventHandle == null) return null;
    final controller = StreamController<Object?>.broadcast(sync: true);
    _events[eventHandle] = controller;
    return controller.stream;
  }

  /// What the app does not host: the registration succeeds (upstream's would
  /// too), but nothing answers its requests. The report lists each one.
  void _unsupportedFeature(String what) {}

  // =========================================================================
  // $unregister
  // =========================================================================

  @override
  void $unregister(num handle) {
    _handles.remove(handle);
    _providers.remove(handle);
    root.untrack(handle, session: _rpc);
    final event = _events.remove(handle);
    unawaited(event?.close());
  }

  // --- registration bookkeeping

  void _registered(num handle) => _handles.add(handle);

  // =========================================================================
  // outline, code lens
  // =========================================================================

  @override
  void $registerDocumentSymbolProvider(
    num handle,
    List<Map<String, Object?>> selector,
    String label,
  ) {
    if (!_allow('documentSymbolProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.documentSymbolProvider,
      _selector(selector)!,
      _ExtensionDocumentSymbolProvider(this, handle.toInt(), label),
    );
  }

  @override
  void $registerCodeLensSupport(
    num handle,
    List<Map<String, Object?>> selector,
    num? eventHandle,
  ) {
    if (!_allow('codeLensProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.codeLensProvider,
      _selector(selector)!,
      _ExtensionCodeLensProvider(this, handle.toInt(), _eventStream(eventHandle)),
    );
  }

  @override
  void $emitCodeLensEvent(num eventHandle, Object? event) =>
      _fireEvent(eventHandle, event);

  void _fireEvent(num eventHandle, [Object? value]) {
    final controller = _events[eventHandle];
    if (controller != null && !controller.isClosed) controller.add(value);
  }

  // =========================================================================
  // declarations, definitions, type definitions, implementations
  // =========================================================================

  @override
  void $registerDefinitionSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('definitionProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.definitionProvider,
      _selector(selector)!,
      _ExtensionDefinitionProvider(this, handle.toInt()),
    );
  }

  @override
  void $registerDeclarationSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('declarationProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.declarationProvider,
      _selector(selector)!,
      _ExtensionDeclarationProvider(this, handle.toInt()),
    );
  }

  @override
  void $registerImplementationSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('implementationProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.implementationProvider,
      _selector(selector)!,
      _ExtensionImplementationProvider(this, handle.toInt()),
    );
  }

  @override
  void $registerTypeDefinitionSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('typeDefinitionProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.typeDefinitionProvider,
      _selector(selector)!,
      _ExtensionTypeDefinitionProvider(this, handle.toInt()),
    );
  }

  // =========================================================================
  // hover
  // =========================================================================

  @override
  void $registerHoverProvider(num handle, List<Map<String, Object?>> selector) {
    if (!_allow('hoverProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.hoverProvider,
      _selector(selector)!,
      _ExtensionHoverProvider(this, handle.toInt()),
    );
  }

  // =========================================================================
  // occurrences, linked editing
  // =========================================================================

  @override
  void $registerDocumentHighlightProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('documentHighlightProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.documentHighlightProvider,
      _selector(selector)!,
      _ExtensionDocumentHighlightProvider(this, handle.toInt()),
    );
  }

  @override
  void $registerLinkedEditingRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('linkedEditingRangeProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.linkedEditingRangeProvider,
      _selector(selector)!,
      _ExtensionLinkedEditingProvider(this, handle.toInt()),
    );
  }

  @override
  void $registerReferenceSupport(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('referenceProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.referenceProvider,
      _selector(selector)!,
      _ExtensionReferenceProvider(this, handle.toInt()),
    );
  }

  // =========================================================================
  // code actions
  // =========================================================================

  @override
  void $registerCodeActionSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
    String displayName,
    String extensionID,
    bool supportsResolve,
  ) {
    if (!_allow('codeActionProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    final providedKinds = [
      for (final kind in dto.asList(metadata['providedKinds'])) '$kind',
    ];
    final documentation = <({String kind, Command command})>[
      for (final entry in dto.asList(metadata['documentation']))
        if (dto.decodeCommandOrNull(dto.asMap(entry)['command'])
            case final command?)
          (kind: '${dto.asMap(entry)['kind'] ?? ''}', command: command),
    ];
    _set(
      handle.toInt(),
      root.service.codeActionProvider,
      _selector(selector)!,
      _ExtensionCodeActionProvider(
        this,
        handle.toInt(),
        supportsResolve: supportsResolve,
        metadata: (
          providedKinds: providedKinds.isEmpty ? null : providedKinds,
          documentation: documentation,
        ),
        displayName: displayName,
        extensionId: extensionID,
      ),
    );
  }

  // =========================================================================
  // formatting
  // =========================================================================

  @override
  void $registerDocumentFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    String displayName,
  ) {
    if (!_allow('documentFormattingEditProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.documentFormattingEditProvider,
      _selector(selector)!,
      _ExtensionFormattingProvider(
        this,
        handle.toInt(),
        extensionId: '${extensionId['value'] ?? ''}',
        displayName: displayName,
      ),
    );
  }

  @override
  void $registerRangeFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    String displayName,
    bool supportRanges,
  ) {
    if (!_allow('documentRangeFormattingEditProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.documentRangeFormattingEditProvider,
      _selector(selector)!,
      _ExtensionRangeFormattingProvider(
        this,
        handle.toInt(),
        extensionId: '${extensionId['value'] ?? ''}',
        displayName: displayName,
        supportsRanges: supportRanges,
      ),
    );
  }

  @override
  void $registerOnTypeFormattingSupport(
    num handle,
    List<Map<String, Object?>> selector,
    List<String> autoFormatTriggerCharacters,
    Map<String, Object?> extensionId,
  ) {
    if (!_allow('onTypeFormattingEditProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.onTypeFormattingEditProvider,
      _selector(selector)!,
      _ExtensionOnTypeFormattingProvider(
        this,
        handle.toInt(),
        autoFormatTriggerCharacters,
        extensionId: '${extensionId['value'] ?? ''}',
      ),
    );
  }

  // =========================================================================
  // workspace symbols, rename
  // =========================================================================

  @override
  void $registerNavigateTypeSupport(num handle, bool supportsResolve) {
    _registered(handle);
    root.track(
      handle,
      root.service.registerWorkspaceSymbolProvider(
        _ExtensionWorkspaceSymbolProvider(
          this,
          handle.toInt(),
          supportsResolve: supportsResolve,
        ),
      ),
      session: _rpc,
    );
  }

  @override
  void $registerRenameSupport(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolveInitialValues,
  ) {
    if (!_allow('renameProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.renameProvider,
      _selector(selector)!,
      _ExtensionRenameProvider(
        this,
        handle.toInt(),
        supportsResolve: supportsResolveInitialValues,
      ),
    );
  }

  // =========================================================================
  // semantic tokens
  // =========================================================================

  @override
  void $registerDocumentSemanticTokensProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> legend,
    num? eventHandle,
  ) {
    if (!_allow('documentSemanticTokensProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.documentSemanticTokensProvider,
      _selector(selector)!,
      _ExtensionDocumentSemanticTokensProvider(
        this,
        handle.toInt(),
        dto.decodeSemanticTokensLegend(legend),
        _eventStream(eventHandle),
      ),
    );
  }

  @override
  void $emitDocumentSemanticTokensEvent(num eventHandle) =>
      _fireEvent(eventHandle);

  @override
  void $registerDocumentRangeSemanticTokensProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> legend,
    num? eventHandle,
  ) {
    if (!_allow('documentRangeSemanticTokensProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.documentRangeSemanticTokensProvider,
      _selector(selector)!,
      _ExtensionDocumentRangeSemanticTokensProvider(
        this,
        handle.toInt(),
        dto.decodeSemanticTokensLegend(legend),
        _eventStream(eventHandle),
      ),
    );
  }

  @override
  void $emitDocumentRangeSemanticTokensEvent(num eventHandle) =>
      _fireEvent(eventHandle);

  // =========================================================================
  // completion
  // =========================================================================

  @override
  void $registerCompletionsProvider(
    num handle,
    List<Map<String, Object?>> selector,
    List<String> triggerCharacters,
    bool supportsResolveDetails,
    Map<String, Object?> extensionId,
  ) {
    if (!_allow('completionProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.completionProvider,
      _selector(selector)!,
      _ExtensionCompletionProvider(
        this,
        handle.toInt(),
        triggerCharacters,
        supportsResolve: supportsResolveDetails,
        extensionId: '${extensionId['value'] ?? ''}',
      ),
    );
  }

  // =========================================================================
  // inline completions
  // =========================================================================

  @override
  void $registerInlineCompletionsSupport(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsHandleEvents,
    String extensionId,
    String extensionVersion,
    String? groupId,
    List<String> yieldsToExtensionIds,
    String? displayName,
    num? debounceDelayMs,
    List<String> excludesExtensionIds,
    bool supportsSetModelId,
    bool supportsOnDidChange,
    Map<String, Object?>? initialModelInfo,
    bool supportsOnDidChangeModelInfo,
    bool supportsSetProviderOption,
    List<Map<String, Object?>>? initialProviderOptions,
    bool supportsOnDidChangeProviderOptions,
  ) {
    if (!_allow('inlineCompletionsProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.inlineCompletionsProvider,
      _selector(selector)!,
      _ExtensionInlineCompletionsProvider(
        this,
        handle.toInt(),
        supportsHandleEvents: supportsHandleEvents,
        supportsSetModelId: supportsSetModelId,
        supportsOnDidChange: supportsOnDidChange,
        supportsSetProviderOption: supportsSetProviderOption,
        groupIdValue: groupId ?? extensionId,
        displayName: displayName,
        debounceDelayMs: debounceDelayMs?.toInt(),
        yieldsToExtensionIds: yieldsToExtensionIds,
        excludesExtensionIds: excludesExtensionIds,
        extensionId: extensionId,
        extensionVersion: extensionVersion,
      ),
    );
  }

  @override
  void $emitInlineCompletionsChange(
    num handle,
    Map<String, Object?>? changeHint,
  ) {
    providerOf<_ExtensionInlineCompletionsProvider>(
      handle,
    )?.emitDidChange(changeHint);
  }

  // The model-picker API the unified inline-completion service uses is not
  // hosted (see the report); the events are dropped.
  @override
  void $emitInlineCompletionModelInfoChange(
    num handle,
    Map<String, Object?>? data,
  ) {}

  @override
  void $emitInlineCompletionProviderOptionsChange(
    num handle,
    List<Map<String, Object?>>? data,
  ) {}

  // =========================================================================
  // signature help, inlay hints
  // =========================================================================

  @override
  void $registerSignatureHelpProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
  ) {
    if (!_allow('signatureHelpProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.signatureHelpProvider,
      _selector(selector)!,
      _ExtensionSignatureHelpProvider(
        this,
        handle.toInt(),
        triggerCharacters: [
          for (final c in dto.asList(metadata['triggerCharacters'])) '$c',
        ],
        retriggerCharacters: [
          for (final c in dto.asList(metadata['retriggerCharacters'])) '$c',
        ],
      ),
    );
  }

  @override
  void $registerInlayHintsProvider(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolve,
    num? eventHandle,
    String? displayName,
  ) {
    if (!_allow('inlayHintsProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.inlayHintsProvider,
      _selector(selector)!,
      _ExtensionInlayHintsProvider(
        this,
        handle.toInt(),
        supportsResolve: supportsResolve,
        events: _eventStream(eventHandle),
        displayName: displayName,
      ),
    );
  }

  @override
  void $emitInlayHintsEvent(num eventHandle) => _fireEvent(eventHandle);

  // =========================================================================
  // links, colors, folding, selection ranges
  // =========================================================================

  @override
  void $registerDocumentLinkProvider(
    num handle,
    List<Map<String, Object?>> selector,
    bool supportsResolve,
  ) {
    if (!_allow('linkProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.linkProvider,
      _selector(selector)!,
      _ExtensionLinkProvider(
        this,
        handle.toInt(),
        supportsResolve: supportsResolve,
      ),
    );
  }

  @override
  void $registerDocumentColorProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('colorProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.colorProvider,
      _selector(selector)!,
      _ExtensionColorProvider(this, handle.toInt()),
    );
  }

  @override
  void $registerFoldingRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> extensionId,
    num? eventHandle,
  ) {
    if (!_allow('foldingRangeProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.foldingRangeProvider,
      _selector(selector)!,
      _ExtensionFoldingRangeProvider(
        this,
        handle.toInt(),
        events: _eventStream(eventHandle),
        extensionId: '${extensionId['value'] ?? ''}',
      ),
    );
  }

  @override
  void $emitFoldingRangeEvent(num eventHandle, Object? event) =>
      _fireEvent(eventHandle, event);

  @override
  void $registerSelectionRangeProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('selectionRangeProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.selectionRangeProvider,
      _selector(selector)!,
      _ExtensionSelectionRangeProvider(this, handle.toInt()),
    );
  }

  // =========================================================================
  // call and type hierarchy
  // =========================================================================

  @override
  void $registerCallHierarchyProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('callHierarchyProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.callHierarchyProvider,
      _selector(selector)!,
      _ExtensionCallHierarchyProvider(this, handle.toInt()),
    );
  }

  @override
  void $registerTypeHierarchyProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) {
    if (!_allow('typeHierarchyProvider', selector)) return;
    _activate(selector);
    _registered(handle);
    _set(
      handle.toInt(),
      root.service.typeHierarchyProvider,
      _selector(selector)!,
      _ExtensionTypeHierarchyProvider(this, handle.toInt()),
    );
  }

  // =========================================================================
  // language configuration
  // =========================================================================

  @override
  void $setLanguageConfiguration(
    num handle,
    String languageId,
    Map<String, Object?> configuration,
  ) {
    _registered(handle);
    final parsed = _parseLanguageConfiguration(languageId, configuration);
    if (parsed == null) return;
    root.setLanguageConfiguration(
      languageId,
      parsed,
      handle,
      session: _rpc,
    );
  }

  LanguageConfiguration? _parseLanguageConfiguration(
    String languageId,
    Map<String, Object?> configuration,
  ) {
    final comments = dto.asMap(configuration['comments']);
    final indentation = dto.asMap(configuration['indentationRules']);
    final lineComment = comments['lineComment'];
    final blockComment = comments['blockComment'];
    final pairs = <CharacterPair>[];
    for (final bracket in dto.asList(configuration['brackets'])) {
      final pair = dto.asList(bracket);
      if (pair.length >= 2 && pair[0] is String && pair[1] is String) {
        pairs.add((pair[0] as String, pair[1] as String));
      }
    }
    final autoClosing = <AutoClosingPairConditional>[];
    for (final pair in dto.asList(configuration['autoClosingPairs'])) {
      final map = dto.asMap(pair);
      final open = map['open'];
      final close = map['close'];
      if (open is! String || close is! String) continue;
      autoClosing.add(
        AutoClosingPairConditional(
          open,
          close,
          notIn: [
            for (final item in dto.asList(map['notIn'])) '$item',
          ],
        ),
      );
    }
    final surrounding = <AutoClosingPair>[];
    for (final pair in dto.asList(configuration['surroundingPairs'])) {
      final map = dto.asMap(pair);
      final open = map['open'];
      final close = map['close'];
      if (open is! String || close is! String) continue;
      surrounding.add(AutoClosingPair(open, close));
    }
    final onEnterRules = <OnEnterRule>[
      for (final rule in dto.asList(configuration['onEnterRules']))
        ?_onEnterRule(dto.asMap(rule)),
    ];
    return LanguageConfiguration(
      comments: comments.isEmpty
          ? null
          : CommentRule(
              lineComment: switch (lineComment) {
                final String text => LineCommentConfig(text),
                final Map<Object?, Object?> map when map['comment'] is String =>
                  LineCommentConfig(
                    '${map['comment']}',
                    noIndent: map['noIndent'] == true,
                  ),
                _ => null,
              },
              blockComment: switch (blockComment) {
                final List pair when pair.length >= 2 =>
                  ('${pair[0]}', '${pair[1]}'),
                final Map<Object?, Object?> map
                    when map['open'] is String && map['close'] is String =>
                  ('${map['open']}', '${map['close']}'),
                _ => null,
              },
            ),
      brackets: pairs.isEmpty ? null : pairs,
      wordPattern: _regExp(configuration['wordPattern']),
      indentationRules: indentation.isEmpty
          ? null
          : _indentationRule(indentation),
      onEnterRules: onEnterRules.isEmpty ? null : onEnterRules,
      autoClosingPairs: autoClosing.isEmpty ? null : autoClosing,
      surroundingPairs: surrounding.isEmpty ? null : surrounding,
      autoCloseBefore: configuration['autoCloseBefore'] as String?,
      docComment: switch (configuration['__electricCharacterSupport']) {
        final Map<Object?, Object?> support
            when support['docComment'] is Map<Object?, Object?> =>
          DocComment(
            '${dto.asMap(support['docComment'])['open'] ?? ''}',
            close: '${dto.asMap(support['docComment'])['close'] ?? ''}',
          ),
        _ => null,
      },
    );
  }

  /// `MainThreadLanguageFeatures._reviveRegExp`; a string pattern is the
  /// older `wordPattern` form (`languageConfiguration.ts`).
  RegExp? _regExp(Object? value) => switch (value) {
    final Map<Object?, Object?> map => RegExp(
      '${map['pattern'] ?? ''}',
      multiLine: '${map['flags'] ?? ''}'.contains('m'),
      caseSensitive: !'${map['flags'] ?? ''}'.contains('i'),
      unicode: '${map['flags'] ?? ''}'.contains('u'),
    ),
    final String pattern => RegExp(pattern),
    _ => null,
  };

  IndentationRule? _indentationRule(Map<String, Object?> map) {
    final decrease = _regExp(map['decreaseIndentPattern']);
    final increase = _regExp(map['increaseIndentPattern']);
    if (decrease == null || increase == null) return null;
    return IndentationRule(
      decreaseIndentPattern: decrease,
      increaseIndentPattern: increase,
      indentNextLinePattern: _regExp(map['indentNextLinePattern']),
      unIndentedLinePattern: _regExp(map['unIndentedLinePattern']),
    );
  }

  OnEnterRule? _onEnterRule(Map<String, Object?> map) {
    final before = _regExp(map['beforeText']);
    final action = dto.asMap(map['action']);
    if (before == null) return null;
    return OnEnterRule(
      beforeText: before,
      afterText: _regExp(map['afterText']),
      previousLineText: _regExp(map['previousLineText']),
      action: EnterAction(
        switch (action['indentAction']) {
          'indent' => IndentAction.indent,
          'indentOutdent' => IndentAction.indentOutdent,
          'outdent' => IndentAction.outdent,
          _ => IndentAction.none,
        },
        appendText: action['appendText'] as String?,
        removeText: action['removeText'] is num
            ? dto.asInt(action['removeText'])
            : null,
      ),
    );
  }

  // =========================================================================
  // what the app does not host
  // =========================================================================

  @override
  void $registerEvaluatableExpressionProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupportedFeature('evaluatableExpression');

  @override
  void $registerInlineValuesProvider(
    num handle,
    List<Map<String, Object?>> selector,
    num? eventHandle,
  ) => _unsupportedFeature('inlineValues');

  @override
  void $emitInlineValuesEvent(num eventHandle, Object? event) {}

  @override
  void $registerMultiDocumentHighlightProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupportedFeature('multiDocumentHighlight');

  @override
  void $registerNewSymbolNamesProvider(
    num handle,
    List<Map<String, Object?>> selector,
  ) => _unsupportedFeature('newSymbolNames');

  @override
  void $registerPasteEditProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?> metadata,
  ) => _unsupportedFeature('pasteEdits');

  @override
  Future<RpcBuffer> $resolvePasteFileData(
    num handle,
    num requestId,
    String dataId,
  ) => throw UnsupportedError('No paste edit provider');

  @override
  void $registerDocumentOnDropEditProvider(
    num handle,
    List<Map<String, Object?>> selector,
    Map<String, Object?>? metadata,
  ) => _unsupportedFeature('dropEdits');

  @override
  Future<RpcBuffer> $resolveDocumentOnDropFileData(
    num handle,
    num requestId,
    String dataId,
  ) => throw UnsupportedError('No drop edit provider');

  // =========================================================================
  // asking the extension host
  // =========================================================================

  ExtHostLanguageFeaturesProxy get proxy => _proxy;
  LanguageFeatureRoot get languageRoot => root;
}

// ---------------------------------------------------------------------------
// The provider objects.
// ---------------------------------------------------------------------------

/// Base of the extension-host-backed providers: holds the handle and the
/// actor that asks (and is what [LanguageFeatureProvider] sees).
abstract class _ExtensionProvider extends LanguageFeatureProvider {
  _ExtensionProvider(this.actor, this.handle);

  final MainThreadLanguageFeatures actor;
  final int handle;

  ExtHostLanguageFeaturesProxy get proxy => actor.proxy;
  LanguageFeatureRoot get root => actor.root;

  @override
  String? get extensionId => actor.extensionId;

  @override
  String? get displayName => actor.displayName;
}

// --- outline

final class _ExtensionDocumentSymbolProvider extends _ExtensionProvider
    implements DocumentSymbolProvider {
  _ExtensionDocumentSymbolProvider(super.actor, super.handle, this.label);

  final String label;

  @override
  FutureOr<List<DocumentSymbol>?> provideDocumentSymbols(
    LanguageFeatureDocument model,
    CancellationToken token,
  ) async {
    final symbols = await proxy.$provideDocumentSymbols(
      handle,
      model.uri,
      token: token,
    );
    if (symbols == null) return null;
    return [for (final symbol in symbols) dto.decodeDocumentSymbol(symbol)];
  }
}

// --- code lens

final class _ExtensionCodeLensProvider extends _ExtensionProvider
    implements CodeLensProvider {
  _ExtensionCodeLensProvider(super.actor, super.handle, this.events);

  final Stream<Object?>? events;

  @override
  Stream<void>? get onDidChange => events;

  @override
  bool get canResolveCodeLens => true;

  @override
  FutureOr<CodeLensList?> provideCodeLenses(
    LanguageFeatureDocument model,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideCodeLenses(
      handle,
      model.uri,
      token: token,
    );
    if (result == null) return null;
    final decoded = dto.decodeCodeLensList(result);
    if (decoded == null) return null;
    return CodeLensList(
      decoded.list.lenses,
      onDispose: () => unawaited(proxy.$releaseCodeLenses(handle, decoded.cacheId)),
    );
  }

  @override
  FutureOr<CodeLens?> resolveCodeLens(
    LanguageFeatureDocument model,
    CodeLens codeLens,
    CancellationToken token,
  ) async {
    final cacheId = _inlayCacheIdOf(codeLens.data);
    if (cacheId == null) return codeLens;
    final result = await proxy.$resolveCodeLens(
      handle,
      dto.asMap({
        'cacheId': dto.encodeCacheId(cacheId),
        'range': dto.encodeRange(codeLens.range),
        if (codeLens.command case final command?)
          'command': dto.encodeCommandDto(command),
      }),
      token: token,
    );
    if (result == null || token.isCancellationRequested) return null;
    final resolved = dto.decodeCodeLens(result);
    if (resolved == null) return codeLens;
    return resolved;
  }
}

// --- definitions and friends

enum _LocationKind { definition, declaration, implementation, typeDefinition }

/// The four "go to" providers: `$provideDefinition` and its siblings all
/// answer `ILocationLinkDto[]`.
final class _ExtensionLocationProvider extends _ExtensionProvider {
  _ExtensionLocationProvider(super.actor, super.handle, this.kind);

  final _LocationKind kind;

  Future<List<Map<String, Object?>>?> _provide(
    VsUri uri,
    Position position,
    CancellationToken token,
  ) => switch (kind) {
    _LocationKind.definition => proxy.$provideDefinition(
      handle,
      uri,
      dto.encodePosition(position),
      token: token,
    ),
    _LocationKind.declaration => proxy.$provideDeclaration(
      handle,
      uri,
      dto.encodePosition(position),
      token: token,
    ),
    _LocationKind.implementation => proxy.$provideImplementation(
      handle,
      uri,
      dto.encodePosition(position),
      token: token,
    ),
    _LocationKind.typeDefinition => proxy.$provideTypeDefinition(
      handle,
      uri,
      dto.encodePosition(position),
      token: token,
    ),
  };
}

final class _ExtensionDefinitionProvider extends _ExtensionLocationProvider
    implements DefinitionProvider {
  _ExtensionDefinitionProvider(MainThreadLanguageFeatures actor, int handle)
    : super(actor, handle, _LocationKind.definition);

  @override
  FutureOr<List<LocationLink>?> provideDefinition(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) async => [
    for (final link
        in await _provide(model.uri, position, token) ?? const [])
      ?dto.decodeLocationLink(link),
  ];
}

final class _ExtensionDeclarationProvider extends _ExtensionLocationProvider
    implements DeclarationProvider {
  _ExtensionDeclarationProvider(MainThreadLanguageFeatures actor, int handle)
    : super(actor, handle, _LocationKind.declaration);

  @override
  FutureOr<List<LocationLink>?> provideDeclaration(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) async => [
    for (final link
        in await _provide(model.uri, position, token) ?? const [])
      ?dto.decodeLocationLink(link),
  ];
}

final class _ExtensionImplementationProvider extends _ExtensionLocationProvider
    implements ImplementationProvider {
  _ExtensionImplementationProvider(MainThreadLanguageFeatures actor, int handle)
    : super(actor, handle, _LocationKind.implementation);

  @override
  FutureOr<List<LocationLink>?> provideImplementation(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) async => [
    for (final link
        in await _provide(model.uri, position, token) ?? const [])
      ?dto.decodeLocationLink(link),
  ];
}

final class _ExtensionTypeDefinitionProvider extends _ExtensionLocationProvider
    implements TypeDefinitionProvider {
  _ExtensionTypeDefinitionProvider(MainThreadLanguageFeatures actor, int handle)
    : super(actor, handle, _LocationKind.typeDefinition);

  @override
  FutureOr<List<LocationLink>?> provideTypeDefinition(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) async => [
    for (final link
        in await _provide(model.uri, position, token) ?? const [])
      ?dto.decodeLocationLink(link),
  ];
}

// --- hover

final class _ExtensionHoverProvider extends _ExtensionProvider
    implements HoverProvider {
  _ExtensionHoverProvider(super.actor, super.handle);

  @override
  FutureOr<Hover?> provideHover(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token, [
    HoverContext? context,
  ]) async {
    final result = await proxy.$provideHover(
      handle,
      model.uri,
      dto.encodePosition(position),
      context == null ||
              context.verbosityDelta == null ||
              context.previousHover == null
          ? null
          : {
              'verbosityRequest': {
                'verbosityDelta': context.verbosityDelta,
                'previousHover': {
                  'id': dto.hoverIdOf(context.previousHover!) ?? 0,
                },
              },
            },
      token: token,
    );
    final hover = dto.decodeHover(result);
    if (hover == null) return null;
    dto.hoverIds[hover.hover] = hover.id;
    return hover.hover;
  }
}

// --- highlights, linked editing

final class _ExtensionDocumentHighlightProvider extends _ExtensionProvider
    implements DocumentHighlightProvider {
  _ExtensionDocumentHighlightProvider(super.actor, super.handle);

  @override
  FutureOr<List<DocumentHighlight>?> provideDocumentHighlights(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideDocumentHighlights(
      handle,
      model.uri,
      dto.encodePosition(position),
      token: token,
    );
    if (result == null) return null;
    return [for (final item in result) dto.decodeDocumentHighlight(item)];
  }
}

final class _ExtensionLinkedEditingProvider extends _ExtensionProvider
    implements LinkedEditingRangeProvider {
  _ExtensionLinkedEditingProvider(super.actor, super.handle);

  @override
  FutureOr<LinkedEditingRanges?> provideLinkedEditingRanges(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideLinkedEditingRanges(
      handle,
      model.uri,
      dto.encodePosition(position),
      token: token,
    );
    return dto.decodeLinkedEditingRanges(result);
  }
}

final class _ExtensionReferenceProvider extends _ExtensionProvider
    implements ReferenceProvider {
  _ExtensionReferenceProvider(super.actor, super.handle);

  @override
  FutureOr<List<Location>?> provideReferences(
    LanguageFeatureDocument model,
    Position position,
    ReferenceContext context,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideReferences(
      handle,
      model.uri,
      dto.encodePosition(position),
      {'includeDeclaration': context.includeDeclaration},
      token: token,
    );
    if (result == null) return null;
    return [for (final location in result) ?dto.decodeLocation(location)];
  }
}

// --- code actions

final class _ExtensionCodeActionProvider extends _ExtensionProvider
    implements CodeActionProvider {
  _ExtensionCodeActionProvider(
    super.actor,
    super.handle, {
    required this.supportsResolve,
    required this.metadata,
    required this._displayName,
    required this._extensionId,
  });

  final bool supportsResolve;
  final ({
    List<String>? providedKinds,
    List<({String kind, Command command})> documentation,
  })
  metadata;
  final String _displayName;
  final String _extensionId;

  @override
  String? get displayName => _displayName;

  @override
  String? get extensionId => _extensionId;

  @override
  List<String>? get providedCodeActionKinds => metadata.providedKinds;

  @override
  List<({String kind, Command command})> get documentation =>
      metadata.documentation;

  @override
  bool get canResolveCodeAction => supportsResolve;

  @override
  FutureOr<CodeActionList?> provideCodeActions(
    LanguageFeatureDocument model,
    Range range,
    CodeActionContext context,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideCodeActions(
      handle,
      model.uri,
      dto.encodeRange(range),
      {
        'only': context.only,
        'trigger': context.trigger.value,
      },
      token: token,
    );
    if (result == null) return null;
    final decoded = dto.decodeCodeActionList(result);
    if (decoded == null) return null;
    return CodeActionList(
      decoded.list.actions,
      onDispose: () =>
          unawaited(proxy.$releaseCodeActions(handle, decoded.cacheId)),
    );
  }

  @override
  FutureOr<CodeAction?> resolveCodeAction(
    CodeAction codeAction,
    CancellationToken token,
  ) async {
    final cacheId = _inlayCacheIdOf(codeAction.data);
    if (cacheId == null) return codeAction;
    final result = await proxy.$resolveCodeAction(
      handle,
      dto.encodeCacheId(cacheId),
      token: token,
    );
    final map = dto.asMap(result);
    return CodeAction(
      title: codeAction.title,
      command: dto.decodeCommandOrNull(map['command']),
      edit: dto.decodeWorkspaceEdit(map['edit']),
      diagnostics: codeAction.diagnostics,
      kind: codeAction.kind,
      isPreferred: codeAction.isPreferred,
      isAI: codeAction.isAI,
      disabled: codeAction.disabled,
      ranges: codeAction.ranges,
      data: codeAction.data,
    );
  }
}

// --- formatting

class _ExtensionFormattingProvider extends _ExtensionProvider
    implements DocumentFormattingEditProvider {
  _ExtensionFormattingProvider(
    super.actor,
    super.handle, {
    required this._extensionId,
    required this._displayName,
  });

  final String _extensionId;
  final String _displayName;

  @override
  String? get extensionId => _extensionId;

  @override
  String? get displayName => _displayName;

  @override
  FutureOr<List<TextEdit>?> provideDocumentFormattingEdits(
    LanguageFeatureDocument model,
    FormattingOptions options,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideDocumentFormattingEdits(
      handle,
      model.uri,
      {'tabSize': options.tabSize, 'insertSpaces': options.insertSpaces},
      token: token,
    );
    if (result == null) return null;
    return [for (final edit in result) dto.decodeTextEdit(edit)];
  }
}

final class _ExtensionRangeFormattingProvider extends _ExtensionProvider
    implements DocumentRangeFormattingEditProvider {
  _ExtensionRangeFormattingProvider(
    super.actor,
    super.handle, {
    required this._extensionId,
    required this._displayName,
    required this.supportsRanges,
  });

  final String _extensionId;
  final String _displayName;
  final bool supportsRanges;

  @override
  String? get extensionId => _extensionId;

  @override
  String? get displayName => _displayName;

  @override
  bool get canFormatRanges => supportsRanges;

  @override
  FutureOr<List<TextEdit>?> provideDocumentRangeFormattingEdits(
    LanguageFeatureDocument model,
    Range range,
    FormattingOptions options,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideDocumentRangeFormattingEdits(
      handle,
      model.uri,
      dto.encodeRange(range),
      {'tabSize': options.tabSize, 'insertSpaces': options.insertSpaces},
      token: token,
    );
    if (result == null) return null;
    return [for (final edit in result) dto.decodeTextEdit(edit)];
  }

  @override
  FutureOr<List<TextEdit>?> provideDocumentRangesFormattingEdits(
    LanguageFeatureDocument model,
    List<Range> ranges,
    FormattingOptions options,
    CancellationToken token,
  ) async {
    if (!supportsRanges) return null;
    final result = await proxy.$provideDocumentRangesFormattingEdits(
      handle,
      model.uri,
      [for (final range in ranges) dto.encodeRange(range)],
      {'tabSize': options.tabSize, 'insertSpaces': options.insertSpaces},
      token: token,
    );
    if (result == null) return null;
    return [for (final edit in result) dto.decodeTextEdit(edit)];
  }
}

final class _ExtensionOnTypeFormattingProvider extends _ExtensionProvider
    implements OnTypeFormattingEditProvider {
  _ExtensionOnTypeFormattingProvider(
    super.actor,
    super.handle,
    this.autoFormatTriggerCharacters, {
    required this._extensionId,
  });

  @override
  final List<String> autoFormatTriggerCharacters;
  final String _extensionId;

  @override
  String? get extensionId => _extensionId;

  @override
  FutureOr<List<TextEdit>?> provideOnTypeFormattingEdits(
    LanguageFeatureDocument model,
    Position position,
    String ch,
    FormattingOptions options,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideOnTypeFormattingEdits(
      handle,
      model.uri,
      dto.encodePosition(position),
      ch,
      {'tabSize': options.tabSize, 'insertSpaces': options.insertSpaces},
      token: token,
    );
    if (result == null) return null;
    return [for (final edit in result) dto.decodeTextEdit(edit)];
  }
}

// --- workspace symbols

final class _ExtensionWorkspaceSymbolProvider extends _ExtensionProvider
    implements WorkspaceSymbolProvider {
  _ExtensionWorkspaceSymbolProvider(
    super.actor,
    super.handle, {
    required this.supportsResolve,
  });

  final bool supportsResolve;
  int? _lastResultId;

  @override
  bool get canResolveWorkspaceSymbol => supportsResolve;

  @override
  FutureOr<List<WorkspaceSymbol>?> provideWorkspaceSymbols(
    String search,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideWorkspaceSymbols(
      handle,
      search,
      token: token,
    );
    final decoded = dto.asMap(result);
    final previous = _lastResultId;
    if (previous != null) {
      unawaited(proxy.$releaseWorkspaceSymbols(handle, previous));
    }
    _lastResultId = decoded['cacheId'] is num
        ? dto.asInt(decoded['cacheId'])
        : null;
    if (decoded['symbols'] == null) return null;
    return [
      for (final symbol in dto.asList(decoded['symbols']))
        dto.decodeWorkspaceSymbol(symbol),
    ];
  }

  @override
  FutureOr<WorkspaceSymbol?> resolveWorkspaceSymbol(
    WorkspaceSymbol item,
    CancellationToken token,
  ) async {
    if (!supportsResolve) return item;
    final result = await proxy.$resolveWorkspaceSymbol(
      handle,
      dto.encodeWorkspaceSymbol(item),
      token: token,
    );
    return result == null ? item : dto.decodeWorkspaceSymbol(result);
  }
}

// --- rename

final class _ExtensionRenameProvider extends _ExtensionProvider
    implements RenameProvider {
  _ExtensionRenameProvider(
    super.actor,
    super.handle, {
    required this.supportsResolve,
  });

  final bool supportsResolve;

  @override
  bool get canResolveRenameLocation => supportsResolve;

  @override
  FutureOr<WorkspaceEdit?> provideRenameEdits(
    LanguageFeatureDocument model,
    Position position,
    String newName,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideRenameEdits(
      handle,
      model.uri,
      dto.encodePosition(position),
      newName,
      token: token,
    );
    return dto.decodeWorkspaceEdit(result);
  }

  @override
  FutureOr<RenameLocation?> resolveRenameLocation(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
  ) async {
    if (!supportsResolve) return null;
    final result = await proxy.$resolveRenameLocation(
      handle,
      model.uri,
      dto.encodePosition(position),
      token: token,
    );
    return dto.decodeRenameLocation(result);
  }
}

// --- semantic tokens

/// `MainThreadDocumentSemanticTokensProvider`.
final class _ExtensionDocumentSemanticTokensProvider extends _ExtensionProvider
    implements DocumentSemanticTokensProvider {
  _ExtensionDocumentSemanticTokensProvider(
    super.actor,
    super.handle,
    this.legend,
    this.events,
  );

  final SemanticTokensLegend legend;
  final Stream<Object?>? events;

  @override
  Stream<void>? get onDidChange => events;

  @override
  SemanticTokensLegend getLegend() => legend;

  @override
  FutureOr<SemanticTokensResult?> provideDocumentSemanticTokens(
    LanguageFeatureDocument model,
    String? lastResultId,
    CancellationToken token,
  ) async {
    final previous = int.tryParse(lastResultId ?? '') ?? 0;
    final encoded = await proxy.$provideDocumentSemanticTokens(
      handle,
      model.uri,
      previous,
      token: token,
    );
    if (token.isCancellationRequested) return null;
    final decoded = dto.decodeSemanticTokensDto(encoded);
    if (decoded == null) return null;
    return switch (decoded) {
      FullSemanticTokensDto(:final id, :final data) => SemanticTokens(
        data,
        resultId: '$id',
      ),
      DeltaSemanticTokensDto(:final id, :final deltas) => SemanticTokensEdits(
        deltas,
        resultId: '$id',
      ),
    };
  }

  @override
  void releaseDocumentSemanticTokens(String? resultId) {
    final id = int.tryParse(resultId ?? '');
    if (id == null) return;
    unawaited(proxy.$releaseDocumentSemanticTokens(handle, id));
  }
}

/// `MainThreadDocumentRangeSemanticTokensProvider`.
final class _ExtensionDocumentRangeSemanticTokensProvider
    extends _ExtensionProvider
    implements DocumentRangeSemanticTokensProvider {
  _ExtensionDocumentRangeSemanticTokensProvider(
    super.actor,
    super.handle,
    this.legend,
    this.events,
  );

  final SemanticTokensLegend legend;
  final Stream<Object?>? events;

  @override
  Stream<void>? get onDidChange => events;

  @override
  SemanticTokensLegend getLegend() => legend;

  @override
  FutureOr<SemanticTokens?> provideDocumentRangeSemanticTokens(
    LanguageFeatureDocument model,
    Range range,
    CancellationToken token,
  ) async {
    final encoded = await proxy.$provideDocumentRangeSemanticTokens(
      handle,
      model.uri,
      dto.encodeRange(range),
      token: token,
    );
    if (token.isCancellationRequested) return null;
    final decoded = dto.decodeSemanticTokensDto(encoded);
    return switch (decoded) {
      FullSemanticTokensDto(:final id, :final data) => SemanticTokens(
        data,
        resultId: '$id',
      ),
      _ => null,
    };
  }
}

// --- completion

final class _ExtensionCompletionProvider extends _ExtensionProvider
    implements CompletionItemProvider {
  _ExtensionCompletionProvider(
    super.actor,
    super.handle,
    this.triggerCharacters, {
    required this.supportsResolve,
    required this._extensionId,
  });

  @override
  final List<String> triggerCharacters;
  final bool supportsResolve;
  final String _extensionId;

  @override
  String? get extensionId => _extensionId;

  @override
  bool get canResolveCompletionItem => supportsResolve;

  /// The extension host's ids of the items [provideCompletionItems] returned,
  /// by item (a resolved item is asked for by its id).
  final _ids = <CompletionItem, CacheId>{};

  @override
  FutureOr<CompletionList?> provideCompletionItems(
    LanguageFeatureDocument model,
    Position position,
    CompletionContext context,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideCompletionItems(
      handle,
      model.uri,
      dto.encodePosition(position),
      {
        'triggerKind': context.triggerKind.index + 1,
        if (context.triggerCharacter != null)
          'triggerCharacter': context.triggerCharacter,
      },
      token: token,
    );
    if (token.isCancellationRequested) return null;
    final decoded = dto.decodeSuggestResult(result);
    if (decoded == null) return null;
    for (final item in decoded.list.suggestions) {
      final id = _inlayCacheIdOf(item.data);
      if (id != null) _ids[item] = id;
    }
    return CompletionList(
      decoded.list.suggestions,
      incomplete: decoded.list.incomplete,
      onDispose: () =>
          unawaited(proxy.$releaseCompletionItems(handle, decoded.cacheId)),
    );
  }

  @override
  FutureOr<CompletionItem?> resolveCompletionItem(
    CompletionItem item,
    CancellationToken token,
  ) async {
    if (!supportsResolve) return item;
    final id = _ids[item];
    if (id == null) return item;
    final result = await proxy.$resolveCompletionItem(
      handle,
      dto.encodeCacheId(id),
      token: token,
    );
    if (result == null) return item;
    final resolved = dto.decodeSuggestData(
      dto.asMap(result),
      item.range ?? CompletionItemRanges.single(Range(1, 1, 1, 1)),
    );
    if (resolved == null) return item;
    // `mixin(suggestion, newSuggestion, true)`: what the resolve filled in
    // replaces the item's, everything else stays.
    return CompletionItem(
      label: resolved.label,
      kind: resolved.kind,
      tags: resolved.tags,
      detail: resolved.detail ?? item.detail,
      documentation: resolved.documentation ?? item.documentation,
      sortText: resolved.sortText ?? item.sortText,
      filterText: resolved.filterText ?? item.filterText,
      preselect: resolved.preselect || item.preselect,
      insertText: resolved.insertText,
      insertTextRules: resolved.insertTextRules,
      range: resolved.range ?? item.range,
      commitCharacters: resolved.commitCharacters ?? item.commitCharacters,
      additionalTextEdits:
          resolved.additionalTextEdits ?? item.additionalTextEdits,
      command: resolved.command ?? item.command,
      action: item.action,
    );
  }
}

// --- inline completions

/// `ExtensionBackedInlineCompletionsProvider`.
final class _ExtensionInlineCompletionsProvider extends _ExtensionProvider
    implements InlineCompletionsProvider {
  _ExtensionInlineCompletionsProvider(
    super.actor,
    super.handle, {
    required this.supportsHandleEvents,
    required this.supportsSetModelId,
    required this.supportsOnDidChange,
    required this.supportsSetProviderOption,
    required int? debounceDelayMs,
    required List<String> yieldsToExtensionIds,
    required List<String> excludesExtensionIds,
    required this.groupIdValue,
    required String? displayName,
    required String extensionId,
    required this.extensionVersion,
  }) : debounceDelayMsValue = debounceDelayMs,
       yieldsToGroupIdsValue = yieldsToExtensionIds,
       excludesGroupIdsValue = excludesExtensionIds,
       displayNameOverride = displayName,
       extensionIdOverride = extensionId;

  final bool supportsHandleEvents;
  final bool supportsSetModelId;
  final bool supportsOnDidChange;
  final bool supportsSetProviderOption;
  final String groupIdValue;
  final String? displayNameOverride;
  final int? debounceDelayMsValue;
  final List<String> yieldsToGroupIdsValue;
  final List<String> excludesGroupIdsValue;
  final String extensionIdOverride;
  final String extensionVersion;

  final _onDidChange = StreamController<Object?>.broadcast(sync: true);

  @override
  String? get extensionId => extensionIdOverride;

  @override
  String? get displayName => displayNameOverride;

  @override
  String? get groupId => groupIdValue;

  @override
  List<String> get yieldsToGroupIds => yieldsToGroupIdsValue;

  @override
  List<String> get excludesGroupIds => excludesGroupIdsValue;

  @override
  int? get debounceDelayMs => debounceDelayMsValue;

  @override
  Stream<void>? get onDidChangeInlineCompletions =>
      supportsOnDidChange ? _onDidChange.stream : null;

  void emitDidChange(Map<String, Object?>? changeHint) {
    if (!_onDidChange.isClosed) _onDidChange.add(changeHint);
  }

  /// The extension host's pids of the lists it sent, by list.
  final _pids = <InlineCompletions, int>{};

  @override
  FutureOr<InlineCompletions?> provideInlineCompletions(
    LanguageFeatureDocument model,
    Position position,
    InlineCompletionContext context,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideInlineCompletions(
      handle,
      model.uri,
      dto.encodePosition(position),
      dto.encodeInlineCompletionContext(context),
      token: token,
    );
    final decoded = dto.decodeInlineCompletions(result);
    if (decoded == null) return null;
    _pids[decoded.completions] = decoded.pid;
    return decoded.completions;
  }

  @override
  void handleItemDidShow(
    InlineCompletions completions,
    InlineCompletion item,
    String updatedInsertText,
  ) {
    if (!supportsHandleEvents) return;
    final pid = _pids[completions];
    final index = _indexOf(completions, item);
    if (pid == null || index == null) return;
    unawaited(
      proxy.$handleInlineCompletionDidShow(handle, pid, index, updatedInsertText),
    );
  }

  @override
  void handlePartialAccept(
    InlineCompletions completions,
    InlineCompletion item,
    int acceptedCharacters,
  ) {
    if (!supportsHandleEvents) return;
    final pid = _pids[completions];
    final index = _indexOf(completions, item);
    if (pid == null || index == null) return;
    unawaited(
      proxy.$handleInlineCompletionPartialAccept(
        handle,
        pid,
        index,
        acceptedCharacters,
        const {'acceptedCharacters': 0, 'acceptedLength': 0},
      ),
    );
  }

  @override
  void handleRejection(InlineCompletions completions, InlineCompletion item) {
    if (!supportsHandleEvents) return;
    final pid = _pids[completions];
    final index = _indexOf(completions, item);
    if (pid == null || index == null) return;
    unawaited(
      proxy.$handleInlineCompletionRejection(handle, pid, index),
    );
  }

  @override
  void disposeInlineCompletions(
    InlineCompletions completions,
    InlineCompletionsDisposeReason reason,
  ) {
    final pid = _pids.remove(completions);
    if (pid == null) return;
    unawaited(
      proxy.$freeInlineCompletionsList(
        handle,
        pid,
        dto.encodeInlineCompletionsDisposeReason(reason),
      ),
    );
  }

  static int? _indexOf(InlineCompletions completions, InlineCompletion item) {
    final index = completions.items.indexOf(item);
    return index < 0 ? null : index;
  }

  /// Sets the model (the extension's `setCurrentModelId`).
  Future<void> setModelId(String modelId) async {
    if (!supportsSetModelId) return;
    await proxy.$handleInlineCompletionSetCurrentModelId(handle, modelId);
  }

  /// Sets a provider option (the extension's `setProviderOptionValue`).
  Future<void> setProviderOption(String optionId, String valueId) async {
    if (!supportsSetProviderOption) return;
    await proxy.$handleInlineCompletionSetProviderOption(
      handle,
      optionId,
      valueId,
    );
  }

  void dispose() => unawaited(_onDidChange.close());
}

// --- signature help, inlay hints

final class _ExtensionSignatureHelpProvider extends _ExtensionProvider
    implements SignatureHelpProvider {
  _ExtensionSignatureHelpProvider(
    super.actor,
    super.handle, {
    required List<String> triggerCharacters,
    required List<String> retriggerCharacters,
  }) : signatureHelpTriggerCharacters = triggerCharacters,
       signatureHelpRetriggerCharacters = retriggerCharacters;

  @override
  final List<String> signatureHelpTriggerCharacters;
  @override
  final List<String> signatureHelpRetriggerCharacters;

  @override
  FutureOr<SignatureHelpResult?> provideSignatureHelp(
    LanguageFeatureDocument model,
    Position position,
    CancellationToken token,
    SignatureHelpContext context,
  ) async {
    final result = await proxy.$provideSignatureHelp(
      handle,
      model.uri,
      dto.encodePosition(position),
      dto.encodeSignatureHelpContext(context),
      token: token,
    );
    final decoded = dto.decodeSignatureHelp(result);
    if (decoded == null) return null;
    return SignatureHelpResult(
      decoded.help,
      onDispose: () =>
          unawaited(proxy.$releaseSignatureHelp(handle, decoded.id)),
    );
  }
}

final class _ExtensionInlayHintsProvider extends _ExtensionProvider
    implements InlayHintsProvider {
  _ExtensionInlayHintsProvider(
    super.actor,
    super.handle, {
    required this.supportsResolve,
    required this.events,
    required String? displayName,
  }) : displayNameOverride = displayName;

  final bool supportsResolve;
  final Stream<Object?>? events;
  final String? displayNameOverride;

  @override
  String? get displayName => displayNameOverride;

  @override
  Stream<void>? get onDidChangeInlayHints => events;

  @override
  bool get canResolveInlayHint => supportsResolve;

  @override
  FutureOr<InlayHintList?> provideInlayHints(
    LanguageFeatureDocument model,
    Range range,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideInlayHints(
      handle,
      model.uri,
      dto.encodeRange(range),
      token: token,
    );
    if (token.isCancellationRequested) return null;
    final decoded = dto.decodeInlayHintList(result);
    if (decoded == null) return null;
    return InlayHintList(
      decoded.list.hints,
      onDispose: () =>
          unawaited(proxy.$releaseInlayHints(handle, decoded.cacheId)),
    );
  }

  @override
  FutureOr<InlayHint?> resolveInlayHint(
    InlayHint hint,
    CancellationToken token,
  ) async {
    if (!supportsResolve) return hint;
    final cacheId = _inlayCacheIdOf(hint.data);
    if (cacheId == null) return hint;
    final result = await proxy.$resolveInlayHint(
      handle,
      dto.encodeCacheId(cacheId),
      token: token,
    );
    if (result == null) return hint;
    final resolved = dto.decodeInlayHint(dto.asMap(result));
    if (resolved == null) return hint;
    return InlayHint(
      label: resolved.label,
      position: resolved.position,
      tooltip: resolved.tooltip ?? hint.tooltip,
      textEdits: resolved.textEdits ?? hint.textEdits,
      kind: resolved.kind ?? hint.kind,
      paddingLeft: resolved.paddingLeft || hint.paddingLeft,
      paddingRight: resolved.paddingRight || hint.paddingRight,
      data: hint.data,
    );
  }
}

// --- links, colors, folding, selection ranges

final class _ExtensionLinkProvider extends _ExtensionProvider
    implements LinkProvider {
  _ExtensionLinkProvider(
    super.actor,
    super.handle, {
    required this.supportsResolve,
  });

  final bool supportsResolve;

  @override
  bool get canResolveLink => supportsResolve;

  @override
  FutureOr<LinksList?> provideLinks(
    LanguageFeatureDocument model,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideDocumentLinks(
      handle,
      model.uri,
      token: token,
    );
    if (token.isCancellationRequested) return null;
    final decoded = dto.decodeLinksList(result);
    if (decoded == null) return null;
    return LinksList(
      decoded.list.links,
      onDispose: () => unawaited(
        proxy.$releaseDocumentLinks(handle, decoded.cacheId),
      ),
    );
  }

  @override
  FutureOr<Link?> resolveLink(Link link, CancellationToken token) async {
    final cacheId = _inlayCacheIdOf(link.data);
    if (cacheId == null) return link;
    final result = await proxy.$resolveDocumentLink(
      handle,
      dto.encodeCacheId(cacheId),
      token: token,
    );
    if (result == null) return link;
    return dto.decodeLink(dto.asMap(result));
  }
}

final class _ExtensionColorProvider extends _ExtensionProvider
    implements DocumentColorProvider {
  _ExtensionColorProvider(super.actor, super.handle);

  @override
  FutureOr<List<ColorInformation>?> provideDocumentColors(
    LanguageFeatureDocument model,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideDocumentColors(
      handle,
      model.uri,
      token: token,
    );
    return [
      for (final info in result) dto.decodeRawColorInfo(info),
    ];
  }

  @override
  FutureOr<List<ColorPresentation>?> provideColorPresentations(
    LanguageFeatureDocument model,
    ColorInformation colorInfo,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideColorPresentations(
      handle,
      model.uri,
      {
        'color': dto.encodeColor(colorInfo.color),
        'range': dto.encodeRange(colorInfo.range),
      },
      token: token,
    );
    if (result == null) return null;
    return [for (final item in result) dto.decodeColorPresentation(item)];
  }
}

final class _ExtensionFoldingRangeProvider extends _ExtensionProvider
    implements FoldingRangeProvider {
  _ExtensionFoldingRangeProvider(
    super.actor,
    super.handle, {
    required this.events,
    required String extensionId,
  }) : extensionIdOverride = extensionId;

  final Stream<Object?>? events;
  final String extensionIdOverride;

  @override
  String? get extensionId => extensionIdOverride;

  @override
  Stream<void>? get onDidChange => events;

  @override
  FutureOr<List<FoldingRange>?> provideFoldingRanges(
    LanguageFeatureDocument model,
    FoldingContext context,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideFoldingRanges(
      handle,
      model.uri,
      const {},
      token: token,
    );
    if (result == null) return null;
    return [for (final range in result) dto.decodeFoldingRange(range)];
  }
}

final class _ExtensionSelectionRangeProvider extends _ExtensionProvider
    implements SelectionRangeProvider {
  _ExtensionSelectionRangeProvider(super.actor, super.handle);

  @override
  FutureOr<List<List<SelectionRange>>?> provideSelectionRanges(
    LanguageFeatureDocument model,
    List<Position> positions,
    CancellationToken token,
  ) async {
    // The editor passes model coordinates already
    // (`RegistryLanguageFeatures.selectionRanges`).
    final result = await proxy.$provideSelectionRanges(
      handle,
      model.uri,
      [for (final position in positions) dto.encodePosition(position)],
      token: token,
    );
    return dto.decodeSelectionRanges(result);
  }
}

// --- hierarchy

final class _ExtensionCallHierarchyProvider extends _ExtensionProvider
    implements CallHierarchyProvider {
  _ExtensionCallHierarchyProvider(super.actor, super.handle);

  @override
  FutureOr<HierarchySession?> prepareCallHierarchy(
    LanguageFeatureDocument document,
    Position position,
    CancellationToken token,
  ) async {
    final items = await proxy.$prepareCallHierarchy(
      handle,
      document.uri,
      dto.encodePosition(position),
      token: token,
    );
    if (items == null || items.isEmpty) return null;
    return HierarchySession(
      [for (final item in items) dto.decodeHierarchyItem(item)],
      onDispose: () {
        for (final item in items) {
          unawaited(
            proxy.$releaseCallHierarchy(handle, '${item[r'_sessionId']}'),
          );
        }
      },
    );
  }

  @override
  FutureOr<List<IncomingCall>?> provideIncomingCalls(
    CallHierarchyItem item,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideCallHierarchyIncomingCalls(
      handle,
      item.sessionId,
      item.itemId,
      token: token,
    );
    if (result == null) return null;
    return [
      for (final call in result)
        IncomingCall(
          dto.decodeHierarchyItem(call['from']),
          [for (final range in dto.asList(call['fromRanges'])) dto.decodeRange(range)],
        ),
    ];
  }

  @override
  FutureOr<List<OutgoingCall>?> provideOutgoingCalls(
    CallHierarchyItem item,
    CancellationToken token,
  ) async {
    final result = await proxy.$provideCallHierarchyOutgoingCalls(
      handle,
      item.sessionId,
      item.itemId,
      token: token,
    );
    if (result == null) return null;
    return [
      for (final call in result)
        OutgoingCall(
          dto.decodeHierarchyItem(call['to']),
          [for (final range in dto.asList(call['fromRanges'])) dto.decodeRange(range)],
        ),
    ];
  }
}

final class _ExtensionTypeHierarchyProvider extends _ExtensionProvider
    implements TypeHierarchyProvider {
  _ExtensionTypeHierarchyProvider(super.actor, super.handle);

  @override
  FutureOr<HierarchySession?> prepareTypeHierarchy(
    LanguageFeatureDocument document,
    Position position,
    CancellationToken token,
  ) async {
    final items = await proxy.$prepareTypeHierarchy(
      handle,
      document.uri,
      dto.encodePosition(position),
      token: token,
    );
    if (items == null || items.isEmpty) return null;
    return HierarchySession(
      [for (final item in items) dto.decodeHierarchyItem(item)],
      onDispose: () {
        for (final item in items) {
          unawaited(
            proxy.$releaseTypeHierarchy(handle, '${item[r'_sessionId']}'),
          );
        }
      },
    );
  }

  @override
  FutureOr<List<TypeHierarchyItem>?> provideSupertypes(
    TypeHierarchyItem item,
    CancellationToken token,
  ) => _provide(proxy.$provideTypeHierarchySupertypes, item, token);

  @override
  FutureOr<List<TypeHierarchyItem>?> provideSubtypes(
    TypeHierarchyItem item,
    CancellationToken token,
  ) => _provide(proxy.$provideTypeHierarchySubtypes, item, token);

  Future<List<TypeHierarchyItem>?> _provide(
    Future<List<Map<String, Object?>>?> Function(
      num handle,
      String sessionId,
      String itemId, {
      CancellationToken? token,
    })
    call,
    HierarchyItem item,
    CancellationToken token,
  ) async {
    final result = await call(handle, item.sessionId, item.itemId, token: token);
    if (result == null) return null;
    return [for (final entry in result) dto.decodeHierarchyItem(entry)];
  }
}

/// The `ChainedCacheId` a decoded item carries in its `data`.
CacheId? _inlayCacheIdOf(Object? data) =>
    data is CacheId ? data : dto.decodeCacheId(data);
