// The Extensions view's state, kept across switches to other views: the
// installed extensions (from the [ExtensionManagementBackend]), an Open VSX
// search, the recommended ones, what is being installed, updates, and each
// extension's capability analysis.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show CancellationTokenSource;
import 'package:flutter/foundation.dart';

import '../capabilities/capability_analysis.dart';
import '../gallery/extension_management_backend.dart';
import '../gallery/gallery_models.dart';
import '../gallery/open_vsx_client.dart';
import '../vsix/extension_manifest.dart';
import '../vsix/semver.dart';
import '../vsix/vsix_reader.dart';

/// What an extension is doing.
enum ExtensionBusy { installing, uninstalling, updating }

/// What a search asks for: `@installed`, `@builtin`, `@recommended`,
/// `@updates`, or words to look for on Open VSX (in the installed ones'
/// names with a filter).
class ExtensionsQuery {
  const ExtensionsQuery({this.filter, this.text = ''});

  factory ExtensionsQuery.parse(String input) {
    String? filter;
    final words = <String>[];
    for (final word in input.trim().split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      switch (word.toLowerCase()) {
        case '@installed' || '@builtin' || '@recommended' || '@updates':
          filter = word.substring(1).toLowerCase();
        default:
          words.add(word);
      }
    }
    return ExtensionsQuery(filter: filter, text: words.join(' '));
  }

  /// `installed`, `builtin`, `recommended`, `updates`; null for Open VSX.
  final String? filter;
  final String text;

  bool get isEmpty => filter == null && text.isEmpty;
}

/// An extension the view shows: installed, found on Open VSX, or both.
class ExtensionEntry {
  const ExtensionEntry({this.installed, this.gallery});

  final InstalledExtension? installed;
  final GalleryExtensionSummary? gallery;

  String get id => installed?.id ?? gallery!.id;
  String get key => id.toLowerCase();
  String get label =>
      installed?.manifest.label ?? gallery?.label ?? id;
  String? get description =>
      installed?.manifest.description ?? gallery?.description;
  String get publisher => id.split('.').first;
  String get version => installed?.version ?? gallery!.version;
}

/// The view's model.
class ExtensionsModel extends ChangeNotifier {
  ExtensionsModel({
    required this.backend,
    required this.gallery,
    this.locale,
    this.searchDelay = const Duration(milliseconds: 300),
    this.pendingRestart,
    this.restartExtensions,
  }) {
    _changes = backend.onDidChange.listen((_) => unawaited(refreshInstalled()));
  }

  final ExtensionManagementBackend backend;
  final OpenVsxClient gallery;

  /// The extensions (keys) that run another version, or were removed or
  /// disabled, until the extensions restart (upstream's runtime state).
  final Set<String> Function()? pendingRestart;

  /// Restarts the extensions (Restart Extensions).
  final Future<void> Function()? restartExtensions;

  bool needsRestart(String key) => pendingRestart?.call().contains(key) ?? false;

  /// What runs changed ([needsRestart]).
  void runtimeChanged() => _notify();

  /// For localized manifests (`zh-cn`).
  final String? locale;
  final Duration searchDelay;

  late final StreamSubscription<ExtensionManagementEvent> _changes;

  /// Null until listed.
  List<InstalledExtension>? installed;
  Object? installedError;

  String _queryText = '';
  ExtensionsQuery query = const ExtensionsQuery();

  /// Open VSX's results for [query].
  List<GalleryExtensionSummary> results = const [];
  int resultsTotal = 0;
  bool searching = false;
  Object? searchError;

  /// The ids to recommend (see recommendations.dart) and what Open VSX
  /// says of them.
  List<String> recommendedIds = const [];
  final Map<String, GalleryExtensionSummary> _recommended = {};

  final Map<String, ExtensionBusy> busy = {};

  /// Newer compatible versions of installed extensions, by key.
  final Map<String, GalleryExtension> updates = {};

  /// Capability reports of installed extensions, by key.
  final Map<String, CapabilityReport> capabilities = {};
  final Map<String, String> _analyzed = {};

  /// The selected row's key.
  String? selected;

  /// The panes open (`installed`, `recommended`).
  final Set<String> expanded = {'installed', 'recommended'};

  Timer? _searchTimer;
  CancellationTokenSource? _search;
  int _searchGeneration = 0;
  bool _disposed = false;

  String get queryText => _queryText;

  bool get loading => searching || (installed == null && installedError == null);

  InstalledExtension? installedFor(String id) {
    final key = id.toLowerCase();
    for (final extension in installed ?? const <InstalledExtension>[]) {
      if (extension.key == key) return extension;
    }
    return null;
  }

  /// Lists the installed extensions again, analyzing those not analyzed.
  Future<void> refreshInstalled() async {
    try {
      final list = await backend.getInstalled();
      list.sort(
        (a, b) => a.manifest.label.toLowerCase().compareTo(
          b.manifest.label.toLowerCase(),
        ),
      );
      installed = list;
      installedError = null;
    } catch (error) {
      installedError = error;
    }
    _notify();
    for (final extension in installed ?? const <InstalledExtension>[]) {
      unawaited(_analyze(extension));
    }
  }

  Future<void> _analyze(InstalledExtension extension) async {
    final version = '${extension.location}@${extension.version}';
    if (_analyzed[extension.key] == version) return;
    _analyzed[extension.key] = version;
    CapabilityReport report;
    try {
      final package = await ExtensionPackage.openFolder(
        extension.location,
        locale: locale,
      );
      try {
        report = await analyzeExtensionPackage(package);
      } finally {
        await package.close();
      }
    } on Object {
      // Not readable here (a remote one): from the manifest alone.
      report = await analyzeExtensionCapabilities(extension.manifest);
    }
    capabilities[extension.key] = report;
    _notify();
  }

  /// Sets what is searched for; Open VSX is asked after [searchDelay].
  void setQuery(String text) {
    _queryText = text;
    query = ExtensionsQuery.parse(text);
    _searchTimer?.cancel();
    _search?.cancel();
    if (query.filter != null || query.text.isEmpty) {
      results = const [];
      resultsTotal = 0;
      searching = false;
      searchError = null;
      _notify();
      return;
    }
    searching = true;
    _notify();
    _searchTimer = Timer(searchDelay, () => unawaited(search()));
  }

  /// Asks Open VSX for [query] now; [more] for the next page.
  Future<void> search({bool more = false}) async {
    _searchTimer?.cancel();
    _search?.cancel();
    final cancel = _search = CancellationTokenSource();
    final generation = ++_searchGeneration;
    searching = true;
    _notify();
    try {
      final result = await gallery.search(
        GallerySearchQuery(text: query.text, offset: more ? results.length : 0),
        cancel: cancel.token,
      );
      if (generation != _searchGeneration) return;
      results = more ? [...results, ...result.extensions] : result.extensions;
      resultsTotal = result.totalSize;
      searchError = null;
    } catch (error) {
      if (generation != _searchGeneration || cancel.isCancellationRequested) {
        return;
      }
      searchError = error;
    } finally {
      if (generation == _searchGeneration) {
        searching = false;
        _notify();
      }
    }
  }

  /// Sets the recommended ids, then asks Open VSX about them.
  Future<void> setRecommendations(List<String> ids) async {
    recommendedIds = ids;
    _notify();
    await Future.wait([
      for (final id in ids)
        if (!_recommended.containsKey(id.toLowerCase()))
          gallery.findExtension(id).then((extension) {
            if (extension == null) return;
            _recommended[id.toLowerCase()] = GalleryExtensionSummary(
              namespace: extension.namespace,
              name: extension.name,
              version: extension.version,
              displayName: extension.displayName,
              description: extension.description,
              iconUrl: extension.files.icon,
              downloadCount: extension.downloadCount,
              averageRating: extension.averageRating,
              reviewCount: extension.reviewCount,
              verified: extension.verified,
            );
          }, onError: (_) {}),
    ]);
    _notify();
  }

  /// The installed extensions [query]'s words match: as upstream's
  /// `filterInstalledExtensions`, not the built-in ones unless they have an
  /// update or wait for the extensions to restart (`@builtin` lists those).
  List<ExtensionEntry> get installedEntries => [
    for (final extension in _matching())
      if (extension.kind != InstalledExtensionKind.builtin ||
          updates.containsKey(extension.id.toLowerCase()) ||
          needsRestart(extension.id.toLowerCase()))
        ExtensionEntry(installed: extension),
  ];

  /// The built-in extensions [query]'s words match (`@builtin`).
  List<ExtensionEntry> get builtinEntries => [
    for (final extension in _matching())
      if (extension.kind == InstalledExtensionKind.builtin)
        ExtensionEntry(installed: extension),
  ];

  Iterable<InstalledExtension> _matching() {
    final words = query.text.toLowerCase().split(' ').where((w) => w.isNotEmpty);
    return (installed ?? const <InstalledExtension>[]).where(
      (extension) => words.every(
        (word) => '${extension.id} ${extension.manifest.label} '
                '${extension.manifest.description ?? ''}'
            .toLowerCase()
            .contains(word),
      ),
    );
  }

  /// The recommended extensions not installed.
  List<ExtensionEntry> get recommendedEntries => [
    for (final id in recommendedIds)
      if (installedFor(id) == null)
        ExtensionEntry(
          gallery:
              _recommended[id.toLowerCase()] ??
              GalleryExtensionSummary(
                namespace: id.split('.').first,
                name: id.substring(id.indexOf('.') + 1),
                version: '',
              ),
        ),
  ];

  List<ExtensionEntry> get updateEntries => [
    for (final entry in installedEntries)
      if (updates.containsKey(entry.key)) entry,
  ];

  /// Open VSX's results, with what is installed of them.
  List<ExtensionEntry> get resultEntries => [
    for (final result in results)
      ExtensionEntry(installed: installedFor(result.id), gallery: result),
  ];

  /// Installs [id] from Open VSX ([version], else the newest compatible).
  Future<void> install(String id, {String? version, bool preRelease = false}) =>
      _run(
        id,
        ExtensionBusy.installing,
        () => backend.installFromGallery(
          id,
          version: version,
          preRelease: preRelease,
        ),
      );

  Future<void> uninstall(String id) =>
      _run(id, ExtensionBusy.uninstalling, () => backend.uninstall(id));

  /// Installs the update found for [id].
  Future<void> update(String id) {
    final update = updates[id.toLowerCase()];
    final current = installedFor(id);
    return _run(
      id,
      ExtensionBusy.updating,
      () => backend.installFromGallery(
        id,
        version: update?.version,
        preRelease: current?.preRelease ?? false,
      ),
    );
  }

  Future<void> setEnabled(String id, bool enabled, EnablementScope scope) async {
    await backend.setEnabled(id, enabled, scope: scope);
    await refreshInstalled();
  }

  /// Looks for newer compatible versions of the installed extensions that
  /// came from Open VSX.
  Future<void> checkUpdates() async {
    for (final extension in installed ?? const <InstalledExtension>[]) {
      if (!extension.fromGallery ||
          extension.kind != InstalledExtensionKind.user) {
        continue;
      }
      try {
        final resolved = await gallery.resolveCompatible(
          extension.id,
          includePreRelease: extension.preRelease,
        );
        if (compareExtensionVersions(
              resolved.extension.version,
              extension.version,
            ) >
            0) {
          updates[extension.key] = resolved.extension;
        } else {
          updates.remove(extension.key);
        }
      } on Object {
        // Not on Open VSX (any more), or offline.
      }
    }
    _notify();
  }

  Future<void> _run(
    String id,
    ExtensionBusy what,
    Future<void> Function() action,
  ) async {
    final key = id.toLowerCase();
    if (busy.containsKey(key)) return;
    busy[key] = what;
    _notify();
    try {
      await action();
      if (what != ExtensionBusy.uninstalling) updates.remove(key);
    } finally {
      busy.remove(key);
      _notify();
    }
    await refreshInstalled();
  }

  /// A capability analysis of a gallery extension, from its manifest
  /// (`package.json`; its code is not downloaded).
  Future<CapabilityReport?> galleryCapability(GalleryExtension extension) async {
    final url = extension.files.manifest;
    if (url == null) return null;
    final text = await gallery.fetchText(url);
    final manifest = ExtensionManifestInfo.fromSource(
      ExtensionManifestSource(manifest: _decode(text)),
    );
    return analyzeExtensionCapabilities(manifest);
  }

  void select(String? key) {
    selected = key;
    _notify();
  }

  void toggle(String pane) {
    if (!expanded.remove(pane)) expanded.add(pane);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _search?.cancel();
    unawaited(_changes.cancel());
    super.dispose();
  }
}

Map<String, Object?> _decode(String text) {
  final json = parseManifestJson(text);
  return json ?? const {};
}
