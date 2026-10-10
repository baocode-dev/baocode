// Importing the extensions of VS Code, Cursor, Windsurf and VSCodium: a
// plan ([ImportPlan], what to do with each, shown for the user to pick
// from), then running it ([ExtensionImporter.run]) into a report
// ([ImportReport]).
//
// Each extension found ([ExternalExtensionScanner]) is:
// - skipped when it is another editor's own (`anysphere.*`) or installed
//   here already (the same version or newer);
// - reinstalled from Open VSX when it is there in a version compatible
//   with the extension host (its pre-release channel kept);
// - else, when it is a proprietary Microsoft one
//   ([proprietaryExtensionRules]), reported with its license and the Open
//   VSX alternatives there are;
// - else offered as a copy of its folder, only with the user's consent
//   (not selected by default): it is not on Open VSX, or not in a version
//   for this VS Code or platform.
// The settings of the extensions imported come along
// ([collectExtensionSettings]), without replacing ours.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart'
    show CancellationException, CancellationToken;

import '../../keybindings/vscode_import.dart'
    show VsCodeInstalls, VsCodeProduct;
import '../capabilities/capability_analysis.dart';
import '../gallery/extension_management_backend.dart';
import '../gallery/gallery_http.dart';
import '../gallery/gallery_models.dart';
import '../gallery/open_vsx_client.dart';
import '../vsix/semver.dart';
import '../vsix/vsix_reader.dart';
import 'external_extensions.dart';
import 'proprietary_extensions.dart';
import 'settings_import.dart';

/// What to do with an extension.
enum ImportAction {
  /// Install it from Open VSX.
  reinstall,

  /// Proprietary: not installed; [ImportPlanItem.alternatives] may be.
  proprietary,

  /// Copy its folder (asks for consent).
  copyLocal,

  /// Nothing: see [ImportPlanItem.skipReason].
  skip,

  /// Open VSX could not be asked (offline): nothing, for now.
  unavailable,
}

enum ImportSkipReason {
  /// Another editor's own extension (`anysphere.*`).
  editorSpecific,

  /// Installed here already, at this version or a newer one.
  alreadyInstalled,
}

/// Why an extension found is not on Open VSX in a version that works here.
enum ImportGalleryProblem { notFound, incompatibleEngine, noCompatiblePlatform }

/// An Open VSX alternative to a proprietary extension.
class ImportAlternative {
  const ImportAlternative(this.id, {this.gallery, this.installed = false});

  final String id;

  /// Its version to install; null when it is not on Open VSX (in a
  /// compatible version).
  final GalleryExtension? gallery;

  /// Installed here already.
  final bool installed;

  bool get available => gallery != null && !installed;
}

/// One extension of the plan.
class ImportPlanItem {
  const ImportPlanItem({
    required this.source,
    required this.action,
    this.gallery,
    this.preReleaseFallback = false,
    this.rule,
    this.alternatives = const [],
    this.skipReason,
    this.galleryProblem,
    this.error,
    this.capability,
  });

  final ExternalExtension source;
  final ImportAction action;

  /// For [ImportAction.reinstall]: the version to install.
  final GalleryExtension? gallery;
  final bool preReleaseFallback;

  /// For [ImportAction.proprietary].
  final ProprietaryExtensionRule? rule;
  final List<ImportAlternative> alternatives;
  final ImportSkipReason? skipReason;

  /// For [ImportAction.copyLocal]: why Open VSX will not do.
  final ImportGalleryProblem? galleryProblem;

  /// For [ImportAction.unavailable]: what went wrong.
  final String? error;

  /// The local copy's capability (for [ImportAction.copyLocal] and
  /// [ImportAction.reinstall], when analyzed).
  final CapabilityReport? capability;

  String get id => source.id;
  String get key => source.key;

  /// Whether it can be selected at all.
  bool get selectable =>
      action == ImportAction.reinstall ||
      action == ImportAction.copyLocal ||
      (action == ImportAction.proprietary &&
          alternatives.any((alternative) => alternative.available));

  /// Selected unless it needs consent ([ImportAction.copyLocal]) or picks
  /// something else in its place (an alternative).
  bool get selectedByDefault => action == ImportAction.reinstall;

  bool get requiresConsent => action == ImportAction.copyLocal;
}

/// What importing from [products] would do.
class ImportPlan {
  const ImportPlan({
    required this.products,
    required this.items,
    this.settings = const SettingsImport(),
  });

  final List<VsCodeProduct> products;
  final List<ImportPlanItem> items;

  /// The settings of every extension found; [ExtensionImporter.run]
  /// imports those of the extensions it installs.
  final SettingsImport settings;

  Iterable<ImportPlanItem> withAction(ImportAction action) =>
      items.where((item) => item.action == action);

  /// The keys of the items selected by default.
  Set<String> get defaultSelection => {
    for (final item in items)
      if (item.selectedByDefault) item.key,
  };
}

/// Makes [ImportPlan]s.
class ExtensionImportPlanner {
  ExtensionImportPlanner({
    required this.installs,
    required this.gallery,
    this.locale,
    this.concurrency = 6,
    this.analyzeLocalCopies = true,
  });

  final VsCodeInstalls installs;
  final OpenVsxClient gallery;
  final String? locale;

  /// How many extensions are looked up on Open VSX at once.
  final int concurrency;

  /// Whether to run the capability analysis on the folders offered for
  /// copying.
  final bool analyzeLocalCopies;

  /// The editors with extensions, and how many each has.
  Future<Map<VsCodeProduct, int>> detectProducts() =>
      ExternalExtensionScanner(installs, locale: locale).detectProducts();

  /// The plan for [products]' extensions; [installed] are ours (to skip).
  Future<ImportPlan> plan(
    List<VsCodeProduct> products, {
    List<InstalledExtension> installed = const [],
    CancellationToken cancel = CancellationToken.none,
    void Function(int done, int total)? onProgress,
  }) async {
    final found = await ExternalExtensionScanner(
      installs,
      locale: locale,
    ).scan(products: products);
    final ours = {for (final extension in installed) extension.key: extension};
    final items = List<ImportPlanItem?>.filled(found.length, null);
    var next = 0;
    var done = 0;
    Future<void> worker() async {
      while (next < found.length) {
        if (cancel.isCancellationRequested) {
          throw const CancellationException();
        }
        final index = next++;
        items[index] = await _item(found[index], ours, cancel);
        onProgress?.call(++done, found.length);
      }
    }

    await Future.wait([
      for (var i = 0; i < concurrency && i < found.length; i++) worker(),
    ]);
    final settings = await collectExtensionSettings(installs, products, {
      for (final extension in found)
        extension.id: extension.manifest.configurationKeys,
    });
    return ImportPlan(
      products: products,
      items: [for (final item in items) item!],
      settings: settings,
    );
  }

  Future<ImportPlanItem> _item(
    ExternalExtension source,
    Map<String, InstalledExtension> ours,
    CancellationToken cancel,
  ) async {
    if (isSkippedExtension(source.id)) {
      return ImportPlanItem(
        source: source,
        action: ImportAction.skip,
        skipReason: ImportSkipReason.editorSpecific,
      );
    }
    final mine = ours[source.key];
    if (mine != null &&
        compareExtensionVersions(mine.version, source.version) >= 0) {
      return ImportPlanItem(
        source: source,
        action: ImportAction.skip,
        skipReason: ImportSkipReason.alreadyInstalled,
      );
    }
    ResolvedGalleryExtension? resolved;
    ImportGalleryProblem? problem;
    try {
      resolved = await gallery.resolveCompatible(
        source.id,
        includePreRelease: source.preRelease,
        cancel: cancel,
      );
    } on GalleryException catch (error) {
      switch (error.kind) {
        case GalleryErrorKind.notFound:
          problem = ImportGalleryProblem.notFound;
        case GalleryErrorKind.incompatibleEngine:
          problem = ImportGalleryProblem.incompatibleEngine;
        case GalleryErrorKind.noCompatiblePlatform:
          problem = ImportGalleryProblem.noCompatiblePlatform;
        default:
          return ImportPlanItem(
            source: source,
            action: ImportAction.unavailable,
            error: error.message,
          );
      }
    } on GalleryNetworkException catch (error) {
      return ImportPlanItem(
        source: source,
        action: ImportAction.unavailable,
        error: error.message,
      );
    }
    if (resolved != null) {
      return ImportPlanItem(
        source: source,
        action: ImportAction.reinstall,
        gallery: resolved.extension,
        preReleaseFallback: resolved.preReleaseFallback,
      );
    }
    final rule = proprietaryRuleFor(source.id);
    if (rule != null) {
      return ImportPlanItem(
        source: source,
        action: ImportAction.proprietary,
        rule: rule,
        galleryProblem: problem,
        alternatives: [
          for (final id in rule.alternatives)
            await _alternative(id, ours, cancel),
        ],
      );
    }
    CapabilityReport? capability;
    if (analyzeLocalCopies) {
      try {
        final package = await ExtensionPackage.openFolder(source.path);
        try {
          capability = await analyzeExtensionPackage(package);
        } finally {
          await package.close();
        }
      } on Exception {
        // Offered all the same.
      }
    }
    return ImportPlanItem(
      source: source,
      action: ImportAction.copyLocal,
      galleryProblem: problem,
      capability: capability,
    );
  }

  Future<ImportAlternative> _alternative(
    String id,
    Map<String, InstalledExtension> ours,
    CancellationToken cancel,
  ) async {
    if (ours.containsKey(id.toLowerCase())) {
      return ImportAlternative(id, installed: true);
    }
    try {
      final resolved = await gallery.resolveCompatible(id, cancel: cancel);
      return ImportAlternative(id, gallery: resolved.extension);
    } on GalleryException {
      return ImportAlternative(id);
    } on GalleryNetworkException {
      return ImportAlternative(id);
    }
  }
}

/// What happened to an extension.
enum ImportOutcome {
  /// Installed from Open VSX.
  installed,

  /// An alternative to it was installed from Open VSX.
  alternativeInstalled,

  /// Its folder was copied.
  copied,

  /// Not imported: skipped, proprietary, not selected.
  notImported,

  failed,
}

/// A line of the report.
class ImportReportEntry {
  const ImportReportEntry({
    required this.id,
    required this.label,
    required this.outcome,
    this.version,
    this.alternativeId,
    this.item,
    this.error,
  });

  /// The extension found (for an alternative, the one it replaces).
  final String id;
  final String label;
  final ImportOutcome outcome;

  /// The version installed.
  final String? version;

  /// For [ImportOutcome.alternativeInstalled].
  final String? alternativeId;
  final ImportPlanItem? item;
  final String? error;
}

/// What [ExtensionImporter.run] did.
class ImportReport {
  const ImportReport({
    this.entries = const [],
    this.settingsAdded = const [],
    this.settingsKept = const [],
    this.settingsPath,
    this.settingsError,
  });

  final List<ImportReportEntry> entries;
  final List<ImportedSetting> settingsAdded;

  /// Settings ours had already.
  final List<ImportedSetting> settingsKept;
  final String? settingsPath;
  final String? settingsError;

  Iterable<ImportReportEntry> withOutcome(ImportOutcome outcome) =>
      entries.where((entry) => entry.outcome == outcome);

  int count(ImportOutcome outcome) => withOutcome(outcome).length;
}

/// Runs an [ImportPlan].
class ExtensionImporter {
  ExtensionImporter({required this.backend, required this.gallery});

  final ExtensionManagementBackend backend;
  final OpenVsxClient gallery;

  /// Imports the items of [plan] whose keys are in [selected] (a
  /// [ImportAction.copyLocal] one only when also in [consented]; a
  /// [ImportAction.proprietary] one by installing its first available
  /// alternative, or those in [alternatives] when given), then their
  /// settings into [settingsPath] when given.
  Future<ImportReport> run(
    ImportPlan plan, {
    required Set<String> selected,
    Set<String> consented = const {},
    Set<String>? alternatives,
    String? settingsPath,
    CancellationToken cancel = CancellationToken.none,
    void Function(ImportPlanItem item, int done, int total)? onProgress,
  }) async {
    final entries = <ImportReportEntry>[];
    final imported = <String>{};
    final chosen = [
      for (final item in plan.items)
        if (selected.contains(item.key) && item.selectable) item,
    ];
    var done = 0;
    for (final item in plan.items) {
      if (!chosen.contains(item)) {
        entries.add(_entry(item, ImportOutcome.notImported));
        continue;
      }
      if (cancel.isCancellationRequested) throw const CancellationException();
      onProgress?.call(item, done, chosen.length);
      try {
        switch (item.action) {
          case ImportAction.reinstall:
            final installed = await _installGallery(
              item.gallery!,
              preRelease: item.source.preRelease || item.preReleaseFallback,
              cancel: cancel,
            );
            imported.add(item.key);
            entries.add(
              _entry(item, ImportOutcome.installed, version: installed.version),
            );
          case ImportAction.copyLocal:
            if (!consented.contains(item.key)) {
              entries.add(_entry(item, ImportOutcome.notImported));
              break;
            }
            final installed = await backend.installFromFolder(item.source.path);
            imported.add(item.key);
            entries.add(
              _entry(item, ImportOutcome.copied, version: installed.version),
            );
          case ImportAction.proprietary:
            final picks = [
              for (final alternative in item.alternatives)
                if (alternative.available &&
                    (alternatives?.contains(alternative.id) ?? true))
                  alternative,
            ];
            final pick = alternatives == null ? picks.take(1) : picks;
            if (pick.isEmpty) {
              entries.add(_entry(item, ImportOutcome.notImported));
            }
            for (final alternative in pick) {
              final installed = await _installGallery(
                alternative.gallery!,
                cancel: cancel,
              );
              entries.add(
                _entry(
                  item,
                  ImportOutcome.alternativeInstalled,
                  version: installed.version,
                  alternativeId: alternative.id,
                ),
              );
            }
          case ImportAction.skip || ImportAction.unavailable:
            entries.add(_entry(item, ImportOutcome.notImported));
        }
      } on CancellationException {
        rethrow;
      } catch (error) {
        entries.add(_entry(item, ImportOutcome.failed, error: '$error'));
      }
      onProgress?.call(item, ++done, chosen.length);
    }

    var added = const <ImportedSetting>[];
    var kept = const <ImportedSetting>[];
    String? settingsError;
    final settings = plan.settings.only(imported).settings;
    if (settingsPath != null && settings.isNotEmpty) {
      try {
        final result = await mergeSettingsFile(settingsPath, settings);
        added = result.added;
        kept = result.kept;
      } on Exception catch (error) {
        settingsError = '$error';
      }
    }
    return ImportReport(
      entries: entries,
      settingsAdded: added,
      settingsKept: kept,
      settingsPath: settingsPath,
      settingsError: settingsError,
    );
  }

  Future<InstalledExtension> _installGallery(
    GalleryExtension extension, {
    bool preRelease = false,
    required CancellationToken cancel,
  }) async {
    final download = await gallery.download(extension, cancel: cancel);
    return backend.install(
      download.path,
      options: ExtensionInstallOptions(
        preRelease: preRelease || extension.preRelease,
        fromGallery: true,
      ),
    );
  }

  static ImportReportEntry _entry(
    ImportPlanItem item,
    ImportOutcome outcome, {
    String? version,
    String? alternativeId,
    String? error,
  }) => ImportReportEntry(
    id: item.id,
    label: item.source.manifest.label,
    outcome: outcome,
    version: version,
    alternativeId: alternativeId,
    item: item,
    error: error,
  );
}
