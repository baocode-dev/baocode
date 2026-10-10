/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the workbench hands the extension host's language area and what it
// gets back: one [LanguageFeatureRoot] per workspace (the registries the
// editor reads through `LanguageFeatures`, the markers, the open documents
// and the running session's providers), plus the `customers` entries for the
// language and diagnostics actors.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/services/languageFeatures.ts (the registries and their
// lifetime) and src/vs/workbench/api/browser/mainThreadLanguageFeatures.ts
// (`DisposableMap<number>`: a registration lives until the extension host
// unregisters it or the session ends).
//
// Deviations:
// - VS Code's registries are process-wide; here they live in a
//   [LanguageFeatureRoot] the workbench owns, so a workspace's providers go
//   when the session ends ([endSession]) and the extension host's handles
//   start over. A remote project's two hosts (its own and this machine's)
//   have a session each, their handles apart.
// - [gate] and [onBlocked] are BaoCode's: the installed extensions'
//   capability scan (`lib/extensions/capabilities/`) decides whether an
//   extension's language feature may run for a language. VS Code has nothing
//   like it.
// - A blocked extension's providers are not asked at all (`LanguageGate`
//   answers per language), and [notifyCapabilityChanged] tells the editor to
//   re-read what is left.

import 'dart:async';

import 'package:bao_editor/monaco/vs/editor/common/languages/language_configuration.dart'
    show LanguageConfiguration;
import 'package:bao_exthost/bao_exthost.dart'
    show
        MainContext,
        MainThreadDiagnosticsActor,
        MainThreadLanguageFeaturesActor,
        RpcActor,
        RpcProtocol,
        VsUri;

import '../main_thread/main_thread_context.dart';
import '../commands/builtin_commands.dart';
import '../main_thread/main_thread_diagnostics.dart';
import '../main_thread/main_thread_language_features.dart';
import 'language_commands.dart';
import 'language_feature_registry.dart';
import 'language_features_service.dart';
import 'language_selector.dart';
import 'marker_service.dart';
import 'registry_language_features.dart';

/// Activates the extensions that could answer [selector]'s languages
/// (`onLanguage:<id>`, as upstream's `ILanguageFeatureInstantiationService`
/// does before the first request for a document). Null when the app does not
/// activate yet.
typedef ProviderActivation = Future<void>? Function(LanguageSelector selector);

/// Whether [extensionId]'s language [feature] may run for [languageId] (the
/// App's capability scan). [languageId] is one of the selector's languages
/// at registration, or the document's for a request.
typedef LanguageGate =
    bool Function({
      required String extensionId,
      required String languageId,
      required String feature,
    });

/// A session's handle: the host's rpc and the handle it gave.
typedef _SessionHandle = (Object?, num);

/// One workspace's language features: the registries the editor reads, the
/// markers, the open documents and the running session.
final class LanguageFeatureRoot {
  LanguageFeatureRoot({
    this.extensionHostId,
    LanguageFeaturesService? service,
    this.languageIds,
  }) : service = service ?? LanguageFeaturesService();

  /// The running extension host, for logs and diagnostics.
  final String? extensionHostId;

  /// The registries every provider registers into.
  final LanguageFeaturesService service;

  /// All registered language ids (a newly registered provider's languages
  /// are activated); null when unknown.
  final List<String>? languageIds;

  /// The App's capability scan; null when nothing is blocked.
  LanguageGate? gate;

  /// Called when [gate] blocks a provider.
  void Function(String feature, String extensionId, String? languageId)?
  onBlocked;

  /// `contributes.language.configuration` and `$setLanguageConfiguration`:
  /// the language configurations extensions register, by language id. The
  /// editor asks [languageConfigurationOf] when it opens a document, so a
  /// configuration that arrives later applies to the next one (as
  /// upstream's registry applies it to open models).
  final Map<String, LanguageConfiguration> languageConfigurations = {};

  /// Every registration of a language's configuration, oldest first: the
  /// newest is in effect (upstream's registry ranks equal priorities by
  /// registration order).
  final Map<String, List<(_SessionHandle, LanguageConfiguration)>>
  _languageConfigurationEntries = {};

  /// Registers [configuration] for [languageId] under [session]'s
  /// [handle] (`$setLanguageConfiguration`); [untrack] of [handle] removes
  /// it.
  void setLanguageConfiguration(
    String languageId,
    LanguageConfiguration configuration,
    num handle, {
    Object? session,
  }) {
    final key = (session, handle);
    _removeLanguageConfiguration((e) => e == key, notify: false);
    (_languageConfigurationEntries[languageId] ??= []).add((
      key,
      configuration,
    ));
    languageConfigurations[languageId] = configuration;
    languageConfigurationChanged?.call(languageId);
  }

  void _removeLanguageConfiguration(
    bool Function(_SessionHandle key) which, {
    bool notify = true,
  }) {
    for (final MapEntry(key: languageId, value: entries)
        in _languageConfigurationEntries.entries.toList()) {
      final before = entries.length;
      entries.removeWhere((entry) => which(entry.$1));
      if (entries.length == before) continue;
      if (entries.isEmpty) {
        _languageConfigurationEntries.remove(languageId);
        languageConfigurations.remove(languageId);
      } else {
        languageConfigurations[languageId] = entries.last.$2;
      }
      if (notify) languageConfigurationChanged?.call(languageId);
    }
  }

  /// Called when a language configuration is registered or removed.
  void Function(String languageId)? languageConfigurationChanged;

  /// The configuration of [languageId], if one is registered.
  LanguageConfiguration? languageConfigurationOf(String languageId) =>
      languageConfigurations[languageId];

  /// A registered language id (`ILanguageService.isRegisteredLanguageId`),
  /// for `$setLanguageConfiguration`'s check.
  bool isRegisteredLanguageId(String languageId) =>
      languageIds?.contains(languageId) ?? true;

  /// The App's markers, fed by `MainThreadDiagnostics` and read by the
  /// problems panel and the editor.
  final MarkerService markers = MarkerService();

  /// The open documents' models; the workbench sets it before the root is
  /// used ([language] needs it).
  LanguageFeatureDocuments? get documents => _documents;
  LanguageFeatureDocuments? _documents;
  set documents(LanguageFeatureDocuments value) {
    if (identical(_documents, value)) return;
    _documents = value;
    _language?.documents = value;
  }

  /// Runs a command a provider attached to a result.
  Future<void> Function(Object command)? commandExecutor;

  /// The latest session's `rpc`; null when no host runs.
  RpcProtocol? get session => _sessions.lastOrNull;
  final _sessions = <RpcProtocol>[];

  /// The running session's id (the handle space of its registrations).
  String? get sessionId => _sessionId;
  String? _sessionId;

  /// Activates the extensions that could answer a selector.
  ProviderActivation? activation;

  final _providerRegistrations = <FeatureRegistration>[];

  /// Every session's registrations, by session and handle.
  final Map<_SessionHandle, FeatureRegistration> _registrations = {};
  final _capabilityChanges = StreamController<void>.broadcast(sync: true);
  RegistryLanguageFeatures? _language;
  bool _disposed = false;

  /// `LanguageFeatures` over this root's registries, documents and markers:
  /// what `IdeWorkspace.languages` is.
  RegistryLanguageFeatures get language => _language ??= _createLanguage();

  /// The registrations of the latest session, by the handle the extension
  /// host gave them.
  Map<num, FeatureRegistration> get registrations => {
    for (final MapEntry(:key, :value) in _registrations.entries)
      if (identical(key.$1, session)) key.$2: value,
  };

  RegistryLanguageFeatures _createLanguage() {
    final documents = _documents;
    if (documents == null) {
      throw StateError('Set LanguageFeatureRoot.documents before using it');
    }
    return RegistryLanguageFeatures(
      service: service,
      markers: markers,
      documents: documents,
      commandExecutor: _executeCommand,
      onProviderError: onProviderError,
    );
  }

  /// Called when a provider throws (the App logs it).
  void Function(Object error, StackTrace stack)? onProviderError;

  Future<void> _executeCommand(Object command) async {
    final executor = commandExecutor;
    if (executor != null) await executor(command);
  }

  /// Providers changed (registered, unregistered, gated out): the editor
  /// re-reads them.
  Stream<void> get onProvidersChanged => service.onDidChangeProviders;

  /// A blocked extension's features are usable again, or the other way.
  Stream<void> get capabilityChanged => _capabilityChanges.stream;

  /// A host answered; its providers are asked over [rpc]. A session of
  /// [rpc] already there ends first.
  void beginSession(
    RpcProtocol rpc, {
    String? sessionId,
    ProviderActivation? activation,
  }) {
    endSession(rpc);
    _sessions.add(rpc);
    _sessionId = sessionId;
    this.activation = activation;
  }

  /// [rpc]'s session ended (every session's when null): its registrations
  /// are gone.
  void endSession([RpcProtocol? rpc]) {
    bool ends(Object? session) => rpc == null || identical(session, rpc);
    _sessions.removeWhere(ends);
    if (_sessions.isEmpty) {
      _sessionId = null;
      activation = null;
    }
    for (final key in _registrations.keys.toList()) {
      if (!ends(key.$1)) continue;
      final registration = _registrations.remove(key)!;
      _providerRegistrations.remove(registration);
      registration.dispose();
    }
    _removeLanguageConfiguration((key) => ends(key.$1));
  }

  bool get hasSession => _sessions.isNotEmpty;

  /// Keeps [registration] until [endSession] or the extension host
  /// unregisters it; [session] is the host's rpc (the latest's when null).
  void track(
    num handle,
    FeatureRegistration registration, {
    Object? session,
  }) {
    final key = (session ?? this.session, handle);
    _registrations.remove(key)?.dispose();
    _registrations[key] = registration;
    _providerRegistrations.add(registration);
  }

  /// The extension host unregistered [handle] (`$unregister`).
  void untrack(num handle, {Object? session}) {
    final key = (session ?? this.session, handle);
    _removeLanguageConfiguration((e) => e == key);
    final registration = _registrations.remove(key);
    if (registration == null) return;
    _providerRegistrations.remove(registration);
    registration.dispose();
  }

  /// Whether [extensionId]'s language [feature] may run for any of
  /// [languages]; reports every blocked language once.
  bool permits(
    String? extensionId,
    String feature,
    Set<String> languages, {
    String? displayName,
  }) {
    final gate = this.gate;
    if (gate == null || extensionId == null || extensionId.isEmpty) {
      return true;
    }
    final candidates = languages.isEmpty ? const {'*'} : languages;
    var allowed = false;
    final blocked = <String>[];
    for (final languageId in candidates) {
      if (gate(
        extensionId: extensionId,
        languageId: languageId,
        feature: feature,
      )) {
        allowed = true;
      } else {
        blocked.add(languageId);
      }
    }
    if (!allowed) {
      for (final languageId in blocked) {
        onBlocked?.call(feature, extensionId, languageId);
      }
    }
    return allowed;
  }

  /// The capability scan's answer changed: the editor re-reads the providers
  /// (a request is gated per call, so nothing needs unregistering).
  void notifyCapabilityChanged() => _capabilityChanges.add(null);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    endSession();
    _language?.dispose();
    _language = null;
    unawaited(_capabilityChanges.close());
    markers.dispose();
    service.dispose();
  }
}

/// The `customers` entries of the language area: the provider registrations
/// and the markers. Pass them to `ExtensionHostService.customers`.
Map<int, MainThreadCustomer> languageCustomers(
  LanguageFeatureRoot root, {
  ProviderActivation? activation,
}) => {
  MainContext.mainThreadLanguageFeatures.nid: (context) =>
      languageFeaturesCustomer(root, context, activation: activation),
  MainContext.mainThreadDiagnostics.nid: (context) =>
      diagnosticsCustomer(root, context),
};

/// The `MainThreadLanguageFeatures` actor of [root]: the session starts when
/// the actor is made ([beginSession]).
RpcActor languageFeaturesCustomer(
  LanguageFeatureRoot root,
  MainThreadContext context, {
  ProviderActivation? activation,
}) {
  // The registries' handles are the session's, so a new host starts over.
  root.beginSession(context.rpc, activation: activation ?? root.activation);
  final actor = MainThreadLanguageFeatures(
    root: root,
    proxy: context.rpc,
    activation: activation ?? root.activation,
  );
  context.onDispose(() => root.endSession(context.rpc));
  return MainThreadLanguageFeaturesActor(actor);
}

/// Registers the `_execute*Provider` built-in commands of [root] on
/// [commands] (`vscode.executeHoverProvider`, …). Call once per workspace,
/// when the extension host's commands could run; returns what removes them.
void Function() registerLanguageCommands(
  LanguageFeatureRoot root,
  BuiltinCommands commands,
) => LanguageCommands(root).register(commands);

/// The `MainThreadDiagnostics` actor of [root]: markers come in from the
/// extension host and other owners' markers go back out
/// (`$acceptMarkersChange`).
RpcActor diagnosticsCustomer(
  LanguageFeatureRoot root,
  MainThreadContext context,
) {
  final actor = MainThreadDiagnostics(
    markers: root.markers,
    proxy: context.rpc,
    extensionHostId: root.extensionHostId,
  );
  context.onDispose(actor.dispose);
  return MainThreadDiagnosticsActor(actor);
}

/// Shows a hover/document the App asked for: the language features of one
/// document, in editor coordinates. Used by the App's own views (the
/// problems panel, the outline) through [LanguageFeatureRoot.language].
typedef FeatureDocuments = LanguageFeatureDocuments;

/// The providers one document has, for the App's per-document checks (the
/// editor lightbulb, the format action's enablement).
bool documentHasProvider(LanguageFeatureRoot root, VsUri uri, String feature) {
  final document = root.documents?.documentForUri(uri);
  if (document == null) return false;
  return switch (feature) {
    'hover' => root.service.hoverProvider.has(document),
    'completion' => root.service.completionProvider.has(document),
    'definition' => root.service.definitionProvider.has(document),
    'references' => root.service.referenceProvider.has(document),
    'rename' => root.service.renameProvider.has(document),
    'documentFormatting' =>
      root.service.documentFormattingEditProvider.has(document) ||
          root.service.documentRangeFormattingEditProvider.has(document),
    'codeAction' => root.service.codeActionProvider.has(document),
    'documentSymbol' => root.service.documentSymbolProvider.has(document),
    'codeLens' => root.service.codeLensProvider.has(document),
    'inlayHints' => root.service.inlayHintsProvider.has(document),
    'semanticTokens' =>
      root.service.documentSemanticTokensProvider.has(document) ||
          root.service.documentRangeSemanticTokensProvider.has(document),
    'foldingRange' => root.service.foldingRangeProvider.has(document),
    'selectionRange' => root.service.selectionRangeProvider.has(document),
    'documentHighlight' =>
      root.service.documentHighlightProvider.has(document),
    'linkedEditing' => root.service.linkedEditingRangeProvider.has(document),
    'documentLink' => root.service.linkProvider.has(document),
    'documentColor' => root.service.colorProvider.has(document),
    'inlineCompletions' =>
      root.service.inlineCompletionsProvider.has(document),
    'signatureHelp' => root.service.signatureHelpProvider.has(document),
    'onTypeFormatting' =>
      root.service.onTypeFormattingEditProvider.has(document),
    'callHierarchy' => root.service.callHierarchyProvider.has(document),
    'typeHierarchy' => root.service.typeHierarchyProvider.has(document),
    _ => false,
  };
}
