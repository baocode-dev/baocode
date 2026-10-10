// The Extensions view's state, kept across switches to other views: the
// installed extensions (from the [ExtensionManagementBackend]), an Open VSX
// search of its themes, the popular ones, what is being installed, updates,
// and each extension's capability analysis.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../base/cancellation.dart' show CancellationTokenSource;
import '../capabilities/capability_analysis.dart';
import '../gallery/extension_management_backend.dart';
import '../gallery/gallery_models.dart';
import '../gallery/open_vsx_client.dart';
import '../vsix/semver.dart';

/// The Open VSX category searched: color and file icon themes.
const themesCategory = 'Themes';

/// What an extension is doing.
enum ExtensionBusy { installing, uninstalling, updating }

/// What a search asks for: `@installed`, `@updates`, or words to look for
/// among Open VSX's themes (in the installed ones' names with a filter).
class ExtensionsQuery {
  const ExtensionsQuery({this.filter, this.text = ''});

  factory ExtensionsQuery.parse(String input) {
    String? filter;
    final words = <String>[];
    for (final word in input.trim().split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      switch (word.toLowerCase()) {
        case '@installed' || '@updates':
          filter = word.substring(1).toLowerCase();
        default:
          words.add(word);
      }
    }
    return ExtensionsQuery(filter: filter, text: words.join(' '));
  }

  /// `installed`, `updates`; null for Open VSX.
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
  String get label => installed?.manifest.label ?? gallery?.label ?? id;
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
  }) {
    _changes = backend.onDidChange.listen((_) => unawaited(refreshInstalled()));
  }

  final ExtensionManagementBackend backend;
  final OpenVsxClient gallery;

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

  /// Open VSX's most downloaded themes, null until asked ([loadPopular]).
  List<GalleryExtensionSummary>? popular;
  Object? popularError;
  Future<void>? _popular;

  final Map<String, ExtensionBusy> busy = {};

  /// Newer compatible versions of installed extensions, by key.
  final Map<String, GalleryExtension> updates = {};

  /// Capability reports of installed extensions, by key.
  final Map<String, CapabilityReport> capabilities = {};
  final Map<String, String> _analyzed = {};

  /// The selected row's key.
  String? selected;

  /// The panes open (`installed`, `popular`).
  final Set<String> expanded = {'installed', 'popular'};

  Timer? _searchTimer;
  CancellationTokenSource? _search;
  int _searchGeneration = 0;
  bool _disposed = false;

  String get queryText => _queryText;

  bool get loading =>
      searching || (installed == null && installedError == null);

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
    for (final extension in installed ?? const <InstalledExtension>[]) {
      _analyze(extension);
    }
    _notify();
  }

  void _analyze(InstalledExtension extension) {
    final version = '${extension.location}@${extension.version}';
    if (_analyzed[extension.key] == version) return;
    _analyzed[extension.key] = version;
    capabilities[extension.key] = analyzeExtensionCapabilities(
      extension.manifest,
    );
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
        GallerySearchQuery(
          text: query.text,
          category: themesCategory,
          offset: more ? results.length : 0,
        ),
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

  /// Asks Open VSX for its most downloaded themes, once (again after a
  /// failure).
  Future<void> loadPopular() => _popular ??= () async {
    try {
      final result = await gallery.search(
        const GallerySearchQuery(
          category: themesCategory,
          sortBy: GallerySortBy.downloads,
          size: 30,
        ),
      );
      popular = result.extensions;
      popularError = null;
    } catch (error) {
      popularError = error;
      _popular = null;
    }
    _notify();
  }();

  /// The installed extensions [query]'s words match.
  List<ExtensionEntry> get installedEntries {
    final words = query.text
        .toLowerCase()
        .split(' ')
        .where((w) => w.isNotEmpty);
    return [
      for (final extension in installed ?? const <InstalledExtension>[])
        if (words.every(
          (word) =>
              '${extension.id} ${extension.manifest.label} '
                      '${extension.manifest.description ?? ''}'
                  .toLowerCase()
                  .contains(word),
        ))
          ExtensionEntry(installed: extension),
    ];
  }

  /// The popular themes not installed.
  List<ExtensionEntry> get popularEntries => [
    for (final result in popular ?? const <GalleryExtensionSummary>[])
      if (installedFor(result.id) == null) ExtensionEntry(gallery: result),
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

  Future<void> setEnabled(String id, bool enabled) async {
    await backend.setEnabled(id, enabled);
    await refreshInstalled();
  }

  /// Looks for newer compatible versions of the installed extensions that
  /// came from Open VSX.
  Future<void> checkUpdates() async {
    for (final extension in installed ?? const <InstalledExtension>[]) {
      if (!extension.fromGallery) continue;
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
