// How much of an extension works in BaoCode, which has no webviews (nor
// notebooks): told from its manifest and a scan of its code, before it is
// installed (a .vsix, a folder) or after (its folder).
//
// - Fully usable: nothing of it needs a webview.
// - Partially usable: some of it shows in a webview (a panel, a view, a
//   custom editor), the rest (language features, tree views, debugging…)
//   works.
// - Needs a webview: what it does is show webviews; nothing else of note is
//   left (commands, settings and keybindings that open them do not count).
//
// Heuristics, so each finding is kept as a reason to show the user:
// - Webview use is found in the manifest (`views` of type `webview`,
//   `customEditors`, `notebooks`, `notebookRenderer`; `walkthroughs` are
//   fine) and in the code: the `main` and `browser` entries, then the other
//   `.js` files outside `node_modules` (split bundles), as the limits allow.
// - What still works is found in the manifest's contributions and in the
//   entries' code only: other files may be libraries bundled for a webview
//   (an editor component registers completions of its own).

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../vsix/extension_files.dart';
import '../vsix/extension_manifest.dart';
import '../vsix/vsix_reader.dart';

/// The verdict.
enum ExtensionCapabilityLevel { full, partial, needsWebview }

/// What was found.
enum CapabilityFindingKind {
  /// `contributes.views[*]` of `"type": "webview"`.
  webviewView,

  /// `contributes.customEditors`.
  customEditor,

  /// `contributes.notebooks`.
  notebook,

  /// `contributes.notebookRenderer`.
  notebookRenderer,

  /// Its code calls `window.createWebviewPanel` or
  /// `registerWebviewPanelSerializer`.
  webviewPanelCode,

  /// Its code calls `registerWebviewViewProvider`.
  webviewViewCode,

  /// Its code calls `registerCustomEditorProvider`.
  customEditorCode,

  /// Its code calls `createNotebookController` or
  /// `registerNotebookSerializer`.
  notebookCode,

  /// It has a `browser` entry only: its code runs in a web worker
  /// extension host, which BaoCode does not have.
  browserOnly,

  /// Its code is larger than what was scanned: a webview may have been
  /// missed.
  scanIncomplete,
}

/// What of an extension works without webviews.
enum CoreFeature {
  /// Completion, hover, definitions, formatting… (registered in code).
  languageFeatures,

  /// A language client (`vscode-languageclient`).
  languageServer,

  /// TextMate grammars.
  syntaxHighlighting,
  snippets,
  debugging,

  /// Color, file icon and product icon themes.
  themes,

  /// Task definitions, problem matchers, task providers.
  tasks,

  /// Tree views (`contributes.views` that are not webviews).
  treeViews,
  sourceControl,
  testing,

  /// `jsonValidation`.
  jsonSchemas,

  /// Terminal profiles.
  terminal,
  authentication,

  /// Language packs.
  localization,
}

/// One reason for the verdict: its [kind] and what it is about ([detail]:
/// a view's name, a file).
class CapabilityFinding {
  const CapabilityFinding(this.kind, [this.detail]);

  final CapabilityFindingKind kind;
  final String? detail;

  /// Whether it means some UI needs a webview.
  bool get isWebview => switch (kind) {
    CapabilityFindingKind.browserOnly ||
    CapabilityFindingKind.scanIncomplete => false,
    _ => true,
  };

  @override
  bool operator ==(Object other) =>
      other is CapabilityFinding &&
      other.kind == kind &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, detail);

  @override
  String toString() =>
      'CapabilityFinding(${kind.name}${detail == null ? '' : ', $detail'})';
}

/// The verdict and its reasons; [coreFeatures] are what works without a
/// webview.
class CapabilityReport {
  const CapabilityReport({
    required this.level,
    this.findings = const [],
    this.coreFeatures = const {},
    this.scannedFiles = const [],
  });

  static const fullyUsable = CapabilityReport(
    level: ExtensionCapabilityLevel.full,
  );

  final ExtensionCapabilityLevel level;
  final List<CapabilityFinding> findings;
  final Set<CoreFeature> coreFeatures;

  /// The code files read.
  final List<String> scannedFiles;

  /// [findings] that are about webviews.
  Iterable<CapabilityFinding> get webviewFindings =>
      findings.where((finding) => finding.isWebview);

  @override
  String toString() =>
      'CapabilityReport(${level.name}, $findings, core: $coreFeatures)';
}

/// How much code [analyzeExtensionCapabilities] reads.
class CapabilityScanLimits {
  const CapabilityScanLimits({
    this.maxFileBytes = 32 * 1024 * 1024,
    this.maxTotalBytes = 64 * 1024 * 1024,
    this.maxFiles = 200,
  });

  final int maxFileBytes;
  final int maxTotalBytes;
  final int maxFiles;
}

/// The contributions that are features of their own, not a way to open a
/// webview (commands, settings, keybindings and menus are not: a preview
/// extension has them all; nor is `languages` alone: a custom editor
/// declares its file type with it).
const _coreContributions = <String, CoreFeature>{
  'grammars': CoreFeature.syntaxHighlighting,
  'snippets': CoreFeature.snippets,
  'debuggers': CoreFeature.debugging,
  'breakpoints': CoreFeature.debugging,
  'themes': CoreFeature.themes,
  'iconThemes': CoreFeature.themes,
  'productIconThemes': CoreFeature.themes,
  'taskDefinitions': CoreFeature.tasks,
  'problemMatchers': CoreFeature.tasks,
  'jsonValidation': CoreFeature.jsonSchemas,
  'terminal': CoreFeature.terminal,
  'authentication': CoreFeature.authentication,
  'localizations': CoreFeature.localization,
  'typescriptServerPlugins': CoreFeature.languageFeatures,
};

/// Language feature APIs: each counts on its own, but for completion and
/// hover, which a preview extension registers for links and images: those
/// count when both are there with a third.
const _languageApis = {
  'registerDefinitionProvider': true,
  'registerCodeActionsProvider': true,
  'registerDocumentFormattingEditProvider': true,
  'registerDocumentRangeFormattingEditProvider': true,
  'registerCodeLensProvider': true,
  'registerInlayHintsProvider': true,
  'registerDocumentSymbolProvider': true,
  'registerRenameProvider': true,
  'registerReferenceProvider': true,
  'registerDocumentSemanticTokensProvider': true,
  'createDiagnosticCollection': true,
  'registerSignatureHelpProvider': true,
  'registerInlineCompletionItemProvider': false,
  'registerCompletionItemProvider': false,
  'registerHoverProvider': false,
};

/// API calls (and module names) that are features of their own.
const _coreApis = <String, CoreFeature>{
  'vscode-languageclient': CoreFeature.languageServer,
  'textDocument/publishDiagnostics': CoreFeature.languageServer,
  'registerTreeDataProvider': CoreFeature.treeViews,
  'createTreeView': CoreFeature.treeViews,
  'registerDebugAdapterDescriptorFactory': CoreFeature.debugging,
  'registerDebugConfigurationProvider': CoreFeature.debugging,
  'registerTaskProvider': CoreFeature.tasks,
  'createSourceControl': CoreFeature.sourceControl,
  'createTestController': CoreFeature.testing,
  'registerTerminalProfileProvider': CoreFeature.terminal,
  'registerAuthenticationProvider': CoreFeature.authentication,
};

/// API calls that show a webview (or a notebook).
const _webviewApis = <String, CapabilityFindingKind>{
  'createWebviewPanel': CapabilityFindingKind.webviewPanelCode,
  'registerWebviewPanelSerializer': CapabilityFindingKind.webviewPanelCode,
  'registerWebviewViewProvider': CapabilityFindingKind.webviewViewCode,
  'registerCustomEditorProvider': CapabilityFindingKind.customEditorCode,
  'createNotebookController': CapabilityFindingKind.notebookCode,
  'registerNotebookSerializer': CapabilityFindingKind.notebookCode,
};

/// Classifies the extension whose manifest is [manifest] and files
/// [files] (null: from the manifest alone).
Future<CapabilityReport> analyzeExtensionCapabilities(
  ExtensionManifestInfo manifest, {
  ExtensionFiles? files,
  CapabilityScanLimits limits = const CapabilityScanLimits(),
}) async {
  final findings = <CapabilityFinding>[];
  final core = <CoreFeature>{};
  void find(CapabilityFindingKind kind, [String? detail]) {
    final finding = CapabilityFinding(kind, detail);
    if (!findings.contains(finding)) findings.add(finding);
  }

  // The manifest.
  final contributes = manifest.manifest['contributes'];
  if (contributes is Map) {
    final views = contributes['views'];
    if (views is Map) {
      for (final list in views.values) {
        if (list is! List) continue;
        for (final view in list) {
          if (view is! Map) continue;
          if (view['type'] == 'webview') {
            find(
              CapabilityFindingKind.webviewView,
              _string(view['name']) ?? _string(view['id']),
            );
          } else {
            core.add(CoreFeature.treeViews);
          }
        }
      }
    }
    for (final (key, kind, labelKeys) in const [
      (
        'customEditors',
        CapabilityFindingKind.customEditor,
        ['displayName', 'viewType'],
      ),
      ('notebooks', CapabilityFindingKind.notebook, ['displayName', 'type']),
      (
        'notebookRenderer',
        CapabilityFindingKind.notebookRenderer,
        ['displayName', 'id'],
      ),
    ]) {
      final list = contributes[key];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        find(
          kind,
          labelKeys.map((key) => _string(item[key])).nonNulls.firstOrNull,
        );
      }
    }
    for (final MapEntry(:key, :value) in _coreContributions.entries) {
      if (_present(contributes[key])) core.add(value);
    }
  }
  if (manifest.browserOnly) find(CapabilityFindingKind.browserOnly);

  // The code.
  final scanned = <String>[];
  final languageApis = <String>{};
  if (files != null && manifest.hasCode) {
    final code = await _codeFiles(manifest, files, limits);
    if (code.languageClient) core.add(CoreFeature.languageServer);
    var total = 0;
    var truncated = code.truncated;
    for (final file in code.files) {
      if (total >= limits.maxTotalBytes) {
        truncated = true;
        break;
      }
      final remaining = limits.maxTotalBytes - total;
      final maxBytes = limits.maxFileBytes < remaining
          ? limits.maxFileBytes
          : remaining;
      final bytes = await files.read(file.path, maxBytes: maxBytes);
      if (bytes == null) continue;
      if (file.size > bytes.length) truncated = true;
      total += bytes.length;
      scanned.add(file.path);
      // A large bundle is searched off the UI's isolate.
      final found = bytes.length > 512 * 1024
          ? await Isolate.run(() => _scanCode(bytes))
          : _scanCode(bytes);
      final entry = code.entries.contains(file.path);
      for (final api in found) {
        if (_webviewApis[api] case final kind?) find(kind, file.path);
        if (!entry) continue;
        if (_coreApis[api] case final feature?) core.add(feature);
        if (_languageApis.containsKey(api)) languageApis.add(api);
      }
    }
    if (truncated) find(CapabilityFindingKind.scanIncomplete);
  }
  if (languageApis.any((api) => _languageApis[api]!) ||
      languageApis.length >= 3) {
    core.add(CoreFeature.languageFeatures);
  }

  final webview = findings.any((finding) => finding.isWebview);
  final ExtensionCapabilityLevel level;
  if (!webview) {
    level = manifest.browserOnly
        ? ExtensionCapabilityLevel.partial
        : ExtensionCapabilityLevel.full;
  } else if (core.isNotEmpty) {
    level = ExtensionCapabilityLevel.partial;
  } else {
    level = ExtensionCapabilityLevel.needsWebview;
  }
  return CapabilityReport(
    level: level,
    findings: List.unmodifiable(findings),
    coreFeatures: Set.unmodifiable(CoreFeature.values.where(core.contains)),
    scannedFiles: List.unmodifiable(scanned),
  );
}

/// [analyzeExtensionCapabilities] of an open package.
Future<CapabilityReport> analyzeExtensionPackage(
  ExtensionPackage package, {
  CapabilityScanLimits limits = const CapabilityScanLimits(),
}) => analyzeExtensionCapabilities(
  package.manifest,
  files: package.files,
  limits: limits,
);

/// The code to scan, the entries first; whether a language client is
/// bundled as a module.
Future<
  ({
    List<ExtensionFileInfo> files,
    Set<String> entries,
    bool truncated,
    bool languageClient,
  })
>
_codeFiles(
  ExtensionManifestInfo manifest,
  ExtensionFiles files,
  CapabilityScanLimits limits,
) async {
  final all = await files.list();
  final byPath = {for (final file in all) file.path: file};
  ExtensionFileInfo? resolve(String? entry) {
    if (entry == null) return null;
    var path = entry.replaceAll('\\', '/');
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    return [
      path,
      '$path.js',
      '$path/index.js',
    ].map((path) => byPath[path]).nonNulls.firstOrNull;
  }

  bool isCode(String path) =>
      path.endsWith('.js') || path.endsWith('.cjs') || path.endsWith('.mjs');
  bool inNodeModules(String path) =>
      path.startsWith('node_modules/') || path.contains('/node_modules/');
  final entries = [?resolve(manifest.main), ?resolve(manifest.browser)];
  final ordered = <ExtensionFileInfo>[
    ...entries.toSet(),
    for (final file in all)
      if (!entries.contains(file) &&
          isCode(file.path) &&
          !inNodeModules(file.path))
        file,
  ];
  final truncated = ordered.length > limits.maxFiles;
  return (
    files: truncated ? ordered.sublist(0, limits.maxFiles) : ordered,
    entries: {for (final file in entries) file.path},
    truncated: truncated,
    languageClient: all.any(
      (file) => file.path.contains('node_modules/vscode-languageclient/'),
    ),
  );
}

/// The APIs of [_webviewApis], [_coreApis] and [_languageApis] that
/// [bytes] mention.
Set<String> _scanCode(Uint8List bytes) {
  // Identifiers are ASCII: latin1 keeps them and never fails.
  final text = latin1.decode(bytes);
  return {
    for (final api in [
      ..._webviewApis.keys,
      ..._coreApis.keys,
      ..._languageApis.keys,
    ])
      if (text.contains(api)) api,
  };
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

bool _present(Object? value) => switch (value) {
  null => false,
  final List list => list.isNotEmpty,
  final Map map => map.isNotEmpty,
  _ => true,
};
