/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Where an extension runs for a remote project: `workspace` extensions on
// the remote host, `ui` ones on this machine.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/
// extensionManifestPropertiesService.ts (`getExtensionKind`,
// `deduceExtensionKind`, `getConfiguredExtensionKind`, `toArray`,
// `getSupportedExtensionKindsForExtensionPoint`), the extension points'
// `defaultExtensionKind`s, and extensionRunningLocationTracker.ts
// (`pickRunningLocation` for a desktop window with a remote).
//
// Deviations: desktop only (`isWeb` false: no `web` kind, no web worker
// host).

/// `ExtensionKind`.
enum ExtensionKind { ui, workspace, web }

/// The extension points VS Code knows, and the kinds they allow (empty:
/// all). Any other point allows `workspace` only.
const Map<String, List<ExtensionKind>> _extensionPointKinds = {
  'authentication': [],
  'breakpoints': [],
  'chatContext': [],
  'chatOutputRenderers': [],
  'chatParticipants': [],
  'chatPlugins': [],
  'chatSessions': [],
  'chatViewsWelcome': [],
  'colors': [],
  'commands': [],
  'configuration': [],
  'configurationDefaults': [],
  'continueEditSession': [],
  'css': [],
  'customEditors': [],
  'debugVisualizers': [],
  'debuggers': [ExtensionKind.workspace],
  'grammars': [],
  'iconThemes': [],
  'icons': [],
  'jsonValidation': [ExtensionKind.workspace, ExtensionKind.web],
  'jsonValidationRegistry': [ExtensionKind.workspace, ExtensionKind.web],
  'keybindings': [],
  'languageModelChatProviders': [],
  'languageModelToolSets': [],
  'languageModelTools': [],
  'languages': [],
  'linkPresentationProviders': [],
  'localizations': [ExtensionKind.ui, ExtensionKind.workspace],
  'mcpServerDefinitionProviders': [],
  'menus': [],
  'notebookPreload': [],
  'notebookRenderer': [],
  'notebooks': [],
  'problemMatchers': [],
  'problemPatterns': [],
  'productIconThemes': [],
  'remoteCodingAgents': [],
  'remoteHelp': [],
  'resourceLabelFormatters': [],
  'semanticTokenModifiers': [],
  'semanticTokenScopes': [],
  'semanticTokenTypes': [],
  'snippets': [],
  'speechProviders': [],
  'statusBarItems': [],
  'submenus': [],
  'taskDefinitions': [],
  'terminal': [ExtensionKind.workspace],
  'terminalQuickFixes': [ExtensionKind.workspace],
  'themes': [],
  'views': [],
  'viewsContainers': [],
  'viewsWelcome': [],
  'walkthroughs': [],
  'chatInstructions': [],
  'chatAgents': [],
  'chatPromptFiles': [],
};

ExtensionKind? _parse(Object? kind) => switch (kind) {
  'ui' => ExtensionKind.ui,
  'workspace' => ExtensionKind.workspace,
  'web' => ExtensionKind.web,
  _ => null,
};

/// `toArray`: a lone `ui` also allows `workspace`.
List<ExtensionKind> _toArray(Object? kind) {
  if (kind is List) return [for (final k in kind) ?_parse(k)];
  return kind == 'ui'
      ? const [ExtensionKind.ui, ExtensionKind.workspace]
      : [?_parse(kind)];
}

/// `getExtensionKind` for [manifest] (a `package.json`), given the user's
/// `remote.extensionKind` setting and the product's `extensionKind` and
/// `extensionPointExtensionKind`, all keyed by extension id.
List<ExtensionKind> extensionKindOf(
  Map<String, Object?> manifest, {
  Map<String, Object?> userConfigured = const {},
  Map<String, Object?> product = const {},
  Map<String, Object?> productExtensionPoints = const {},
}) {
  final id = '${manifest['publisher']}.${manifest['name']}'.toLowerCase();
  Object? lookup(Map<String, Object?> map) {
    for (final MapEntry(:key, :value) in map.entries) {
      if (key.toLowerCase() == id) return value;
    }
    return null;
  }

  // getConfiguredExtensionKind: settings, then product, then manifest.
  final configured = switch (lookup(userConfigured)) {
    final Object user => _toArray(user),
    null => switch (lookup(product)) {
      final List<Object?> kinds => [for (final k in kinds) ?_parse(k)],
      _ => switch (manifest['extensionKind']) {
        null => null,
        final Object kinds => _toArray(
          kinds,
        ).where((k) => k != ExtensionKind.web).toList(),
      },
    },
  };
  if (configured != null && configured.isNotEmpty) return configured;
  return _deduce(manifest, productExtensionPoints);
}

List<ExtensionKind> _deduce(
  Map<String, Object?> manifest,
  Map<String, Object?> productExtensionPoints,
) {
  if (manifest['main'] != null) return const [ExtensionKind.workspace];
  if (manifest['browser'] != null) return const [ExtensionKind.web];
  var result = ExtensionKind.values.toList();
  bool nonEmpty(Object? v) => v is List && v.isNotEmpty;
  if (nonEmpty(manifest['extensionPack']) ||
      nonEmpty(manifest['extensionDependencies'])) {
    result = [ExtensionKind.workspace];
  }
  final contributes = manifest['contributes'];
  if (contributes is Map) {
    for (final point in contributes.keys) {
      final supported =
          _extensionPointKinds[point] ??
          switch (productExtensionPoints[point]) {
            final List<Object?> kinds => [for (final k in kinds) ?_parse(k)],
            _ => const [ExtensionKind.workspace],
          };
      if (supported.isNotEmpty) {
        result = result.where(supported.contains).toList();
      }
    }
  }
  return result;
}

/// Where an extension runs (`ExtensionHostKind`; null: nowhere).
enum ExtensionRunningLocation { local, remote }

/// `ExtensionRunningPreference`.
enum ExtensionRunningPreference { none, local, remote }

/// `pickExtensionHostKind` (nativeExtensionService.ts), without the web
/// worker host.
ExtensionRunningLocation? pickRunningLocation(
  List<ExtensionKind> kinds, {
  required bool installedLocally,
  required bool installedRemotely,
  required bool hasRemoteHost,
  ExtensionRunningPreference preference = ExtensionRunningPreference.none,
}) {
  final result = <ExtensionRunningLocation>[];
  final wantsLocal =
      preference == ExtensionRunningPreference.none ||
      preference == ExtensionRunningPreference.local;
  final wantsRemote =
      preference == ExtensionRunningPreference.none ||
      preference == ExtensionRunningPreference.remote;
  for (final kind in kinds) {
    if (kind == ExtensionKind.ui && installedLocally) {
      if (wantsLocal) return ExtensionRunningLocation.local;
      result.add(ExtensionRunningLocation.local);
    }
    if (kind == ExtensionKind.workspace && installedRemotely) {
      if (wantsRemote) return ExtensionRunningLocation.remote;
      result.add(ExtensionRunningLocation.remote);
    }
    if (kind == ExtensionKind.workspace && !hasRemoteHost) {
      if (wantsLocal) return ExtensionRunningLocation.local;
      result.add(ExtensionRunningLocation.local);
    }
  }
  return result.firstOrNull;
}
