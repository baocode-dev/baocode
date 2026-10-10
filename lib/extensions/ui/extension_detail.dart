/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// An extension's page, shown as an editor: its header (icon, name,
// publisher, installs, rating, description, the actions, the version and
// the pre-release choice), then Details (its README), Features (what it
// contributes) and Changelog, beside what is known of it and its
// capability in BaoCode.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/extensions/browser/extensionEditor.ts and
// media/extensionEditor.css.
//
// Deviations: the README is rendered by the app's markdown widgets (no
// webview); the capability section is BaoCode's; Features lists the
// contribution points with their items instead of a table per kind.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../chat/widgets/markdown_view.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../capabilities/capability_analysis.dart';
import '../gallery/extension_management_backend.dart';
import '../gallery/gallery_models.dart';
import '../gallery/open_vsx_client.dart';
import '../vsix/extension_files.dart';
import '../vsix/extension_manifest.dart';
import '../vsix/vsix_reader.dart' show parseManifestJson;
import '../vsix/zip_reader.dart' show decodeText;
import 'extension_widgets.dart';
import 'extensions_model.dart';

enum ExtensionDetailTab { details, features, changelog }

class ExtensionDetailPage extends StatefulWidget {
  const ExtensionDetailPage({
    super.key,
    required this.model,
    required this.id,
    this.initialTab = ExtensionDetailTab.details,
    this.onError,
  });

  final ExtensionsModel model;

  /// `publisher.name`.
  final String id;
  final ExtensionDetailTab initialTab;
  final ValueChanged<String>? onError;

  @override
  State<ExtensionDetailPage> createState() => _ExtensionDetailPageState();
}

class _ExtensionDetailPageState extends State<ExtensionDetailPage> {
  late ExtensionDetailTab _tab = widget.initialTab;

  /// What Open VSX says; null when it has no such extension.
  GalleryExtension? _galleryValue;
  Object? _galleryError;

  /// The pre-release channel is shown.
  bool _preRelease = false;

  /// The version picked in the versions menu; null for the newest.
  String? _version;

  Future<String?>? _readme;
  Future<String?>? _changelog;
  Future<ExtensionManifestInfo?>? _manifest;
  Future<CapabilityReport?>? _galleryCapability;

  ExtensionsModel get _model => widget.model;
  OpenVsxClient get _client => _model.gallery;
  InstalledExtension? get _installed => _model.installedFor(widget.id);

  @override
  void initState() {
    super.initState();
    _preRelease = _installed?.preRelease ?? false;
    _model.addListener(_changed);
    // Opened without going through the view (a link, a restart): the
    // installed list is what says whether it is installed.
    if (_model.installed == null) {
      unawaited(_model.refreshInstalled());
    }
    _load();
  }

  @override
  void didUpdateWidget(ExtensionDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(_changed);
      widget.model.addListener(_changed);
    }
    if (oldWidget.id != widget.id) {
      _version = null;
      _load();
    }
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _load() {
    final installed = _installed;
    final gallery = _fetchGallery();
    // Not on Open VSX, or offline: an installed extension's own files.
    final listed = gallery.then<GalleryExtension?>(
      (extension) => extension,
      onError: (Object _) => null,
    );
    _readme = listed.then((extension) async {
      if (extension?.files.readme case final url?) {
        return _client.fetchText(url);
      }
      return _readInstalled(installed, const ['README.md', 'readme.md']);
    });
    _changelog = listed.then((extension) async {
      if (extension?.files.changelog case final url?) {
        return _client.fetchText(url);
      }
      return _readInstalled(installed, const ['CHANGELOG.md', 'changelog.md']);
    });
    _manifest = installed != null
        ? Future.value(installed.manifest)
        : gallery.then((extension) async {
            final url = extension?.files.manifest;
            if (url == null) return null;
            final json = parseManifestJson(await _client.fetchText(url));
            return json == null
                ? null
                : ExtensionManifestInfo.fromSource(
                    ExtensionManifestSource(manifest: json),
                  );
          });
    _galleryCapability = installed != null
        ? null
        : _manifest!.then(
            (manifest) => manifest == null
                ? null
                : analyzeExtensionCapabilities(manifest),
          );
  }

  Future<GalleryExtension?> _fetchGallery() {
    final future = () async {
      final version =
          _version ??
          (_preRelease ? 'pre-release' : null);
      try {
        return await _client.findExtension(
              widget.id,
              version: version,
              platform: _client.targetPlatform,
            ) ??
            await _client.findExtension(widget.id, version: version);
      } on GalleryException {
        if (version == 'pre-release') {
          return _client.findExtension(widget.id);
        }
        rethrow;
      }
    }();
    future.then(
      (value) {
        if (!mounted) return;
        setState(() {
          _galleryValue = value;
          _galleryError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _galleryError = error);
      },
    );
    return future;
  }

  Future<String?> _readInstalled(
    InstalledExtension? installed,
    List<String> names,
  ) async {
    if (installed == null) return null;
    final files = FolderExtensionFiles(installed.location);
    for (final name in names) {
      final bytes = await files.read(name);
      if (bytes != null) return decodeText(bytes);
    }
    return null;
  }

  Future<void> _guard(Future<void> Function() action) async {
    final l10n = context.l10n;
    try {
      await action();
    } catch (error) {
      widget.onError?.call(l10n.extInstallError(widget.id, '$error'));
    }
  }

  void _setPreRelease(bool value) {
    setState(() {
      _preRelease = value;
      _version = null;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return ColoredBox(
      color: colors['editor.background'],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              _navbar(context),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _body(context)),
                          SizedBox(width: 280, child: _sidebar(context)),
                        ],
                      )
                    : _body(context, withSidebar: true),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final installed = _installed;
    final gallery = _galleryValue;
    final manifest = installed?.manifest;
    final foreground = colors['foreground'];
    final muted = colors['descriptionForeground'];
    final name = manifest?.label ?? gallery?.label ?? widget.id;
    final description = manifest?.description ?? gallery?.description ?? '';
    final publisher = gallery?.publisherLabel ?? widget.id.split('.').first;
    final capability = installed != null
        ? _model.capabilities[installed.key]
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExtensionIcon(
            bytes: manifest?.iconBytes,
            url: gallery?.files.icon,
            gallery: _client,
            size: 96,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    _pill(widget.id),
                    if ((installed?.preRelease ?? false) ||
                        (gallery?.preRelease ?? false))
                      _pill(l10n.extsPreRelease, accent: true),
                    if (installed?.kind == InstalledExtensionKind.builtin)
                      _pill(l10n.extsBuiltin),
                    if (installed?.kind == InstalledExtensionKind.development)
                      _pill(l10n.extsDevelopment),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          publisher,
                          style: TextStyle(fontSize: 14, color: foreground),
                        ),
                        if (gallery?.verified ?? false)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Tooltip(
                              message: l10n.extsVerifiedPublisher,
                              child: Icon(
                                Codicons.verifiedFilled,
                                size: 15,
                                color:
                                    colors.get(
                                      'extensionIcon.verifiedForeground',
                                    ) ??
                                    colors['textLink.foreground'],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (gallery != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Codicons.cloudDownload, size: 15, color: muted),
                          const SizedBox(width: 4),
                          Text(
                            l10n.extsDownloads(
                              formatInstallCount(gallery.downloadCount),
                            ),
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                    if (gallery?.averageRating case final rating?)
                      ExtensionRating(
                        rating: rating,
                        count: gallery!.reviewCount,
                      ),
                    if (capability != null) CapabilityBadge(capability.level)
                    else
                      FutureBuilder<CapabilityReport?>(
                        future: _galleryCapability,
                        builder: (context, snapshot) => snapshot.data == null
                            ? const SizedBox.shrink()
                            : CapabilityBadge(snapshot.data!.level),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: foreground),
                ),
                const SizedBox(height: 10),
                _actions(context),
                if (manifest != null && !manifest.engineCompatible)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _warning(
                      manifest.engineNotices
                          .map((notice) => engineNoticeText(l10n, notice))
                          .join(' '),
                    ),
                  ),
                if (_galleryError case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _warning(l10n.extsLoadFailed('$error')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _warning(String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Codicons.warning,
        size: 14,
        color: themeColors['editorWarning.foreground'],
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: themeColors['foreground']),
        ),
      ),
    ],
  );

  Widget _pill(String text, {bool accent = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: accent
          ? themeColors['extensionBadge.remoteBackground']
          : themeColors['badge.background'],
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: accent
            ? themeColors['extensionBadge.remoteForeground']
            : themeColors['badge.foreground'],
      ),
    ),
  );

  Widget _actions(BuildContext context) {
    final l10n = context.l10n;
    final installed = _installed;
    final gallery = _galleryValue;
    final busy = _model.busy[widget.id.toLowerCase()];
    final update = _model.updates[widget.id.toLowerCase()];
    final buttons = <Widget>[];
    if (busy != null) {
      buttons.add(
        ExtensionActionButton(
          large: true,
          label: switch (busy) {
            ExtensionBusy.installing => l10n.extInstalling,
            ExtensionBusy.uninstalling => l10n.extUninstalling,
            ExtensionBusy.updating => l10n.extsUpdating,
          },
        ),
      );
    } else if (installed == null) {
      buttons.add(
        ExtensionActionButton(
          large: true,
          label: _preRelease ? l10n.extsInstallPreRelease : l10n.extInstall,
          onPressed: gallery == null
              ? null
              : () => unawaited(
                  _guard(
                    () => _model.install(
                      widget.id,
                      version: _version,
                      preRelease: _preRelease,
                    ),
                  ),
                ),
        ),
      );
    } else {
      if (_model.needsRestart(widget.id.toLowerCase())) {
        buttons.add(
          ExtensionActionButton(
            large: true,
            label: l10n.extRestartExtensions,
            onPressed: _model.restartExtensions == null
                ? null
                : () => unawaited(_model.restartExtensions!()),
          ),
        );
      }
      if (update != null) {
        buttons.add(
          ExtensionActionButton(
            large: true,
            label: l10n.extsUpdateTo(update.version),
            onPressed: () => unawaited(_guard(() => _model.update(widget.id))),
          ),
        );
      }
      if (_version != null && _version != installed.version) {
        buttons.add(
          ExtensionActionButton(
            large: true,
            label: l10n.extsInstallVersion(_version!),
            onPressed: () => unawaited(
              _guard(
                () => _model.install(
                  widget.id,
                  version: _version,
                  preRelease: _preRelease,
                ),
              ),
            ),
          ),
        );
      }
      buttons.add(
        ExtensionActionButton(
          large: true,
          prominent: false,
          label: installed.enabledGlobally ? l10n.extsDisable : l10n.extsEnable,
          onPressed: () => unawaited(
            _model.setEnabled(
              widget.id,
              !installed.enabledGlobally,
              EnablementScope.global,
            ),
          ),
        ),
      );
      buttons.add(
        ExtensionActionButton(
          large: true,
          prominent: false,
          label: installed.enabled
              ? l10n.extsDisableWorkspace
              : l10n.extsEnableWorkspace,
          onPressed: () => unawaited(
            _model.setEnabled(
              widget.id,
              !installed.enabled,
              EnablementScope.workspace,
            ),
          ),
        ),
      );
      if (installed.canUninstall) {
        buttons.add(
          ExtensionActionButton(
            large: true,
            prominent: false,
            label: l10n.extUninstall,
            onPressed: () =>
                unawaited(_guard(() => _model.uninstall(widget.id))),
          ),
        );
      }
    }
    final version = _version ?? gallery?.version ?? installed?.version;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: [
        ...buttons,
        if (gallery != null) ...[
          const SizedBox(width: 8),
          _VersionButton(
            label: version == null ? l10n.extsVersion : 'v$version',
            entries: () => _versionEntries(context),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            child: ExtensionCheckbox(
              checked: _preRelease,
              label: l10n.extsPreReleaseToggle,
              onChanged: gallery.hasPreRelease || _preRelease
                  ? _setPreRelease
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  Future<List<IdeMenuEntry>> _versionEntries(BuildContext context) async {
    final l10n = context.l10n;
    List<GalleryVersion> versions;
    try {
      versions = await _client.listVersions(widget.id, limit: 50);
    } catch (error) {
      return [IdeMenuAction(l10n.extsLoadFailed('$error'), enabled: false)];
    }
    final installed = _installed?.version;
    return [
      IdeMenuAction(
        l10n.extsLatestVersion,
        checked: _version == null,
        onSelected: () => setState(() {
          _version = null;
          _load();
        }),
      ),
      const IdeMenuSeparator(),
      for (final version in versions)
        if (_preRelease || version.preRelease != true)
          IdeMenuAction(
            [
              version.version,
              if (version.preRelease == true) l10n.extsPreRelease,
              if (version.version == installed) l10n.extInstalled,
            ].join(' · '),
            checked: version.version == _version,
            onSelected: () => setState(() {
              _version = version.version;
              _load();
            }),
          ),
    ];
  }

  Widget _navbar(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    Widget tab(ExtensionDetailTab tab, String label) {
      final active = _tab == tab;
      return Semantics(
        button: true,
        selected: active,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = tab),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              margin: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 1,
                    color: active
                        ? colors['panelTitle.activeBorder']
                        : Colors.transparent,
                  ),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: active
                      ? colors['panelTitle.activeForeground']
                      : colors['panelTitle.inactiveForeground'],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(left: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.get('panelSection.border') ?? colors['panel.border'],
          ),
        ),
      ),
      child: Row(
        children: [
          tab(ExtensionDetailTab.details, l10n.extsTabDetails),
          tab(ExtensionDetailTab.features, l10n.extsTabFeatures),
          tab(ExtensionDetailTab.changelog, l10n.extsTabChangelog),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, {bool withSidebar = false}) {
    final l10n = context.l10n;
    final Widget content = switch (_tab) {
      ExtensionDetailTab.details => _markdown(_readme, l10n.extsNoReadme),
      ExtensionDetailTab.changelog => _markdown(
        _changelog,
        l10n.extsNoChangelog,
      ),
      ExtensionDetailTab.features => _features(context),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (withSidebar) ...[
            const SizedBox(height: 24),
            _sidebarContent(context),
          ],
        ],
      ),
    );
  }

  Widget _markdown(Future<String?>? text, String empty) =>
      FutureBuilder<String?>(
        future: text,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(height: 40);
          }
          final data = snapshot.data;
          if (snapshot.hasError || data == null || data.trim().isEmpty) {
            return _muted(
              snapshot.hasError
                  ? context.l10n.extsLoadFailed('${snapshot.error}')
                  : empty,
            );
          }
          final readmeUrl = _galleryValue?.files.readme;
          return SelectionArea(
            child: MarkdownBlocks(
              nodes: MarkdownView.document().parse(data),
              style: MarkdownView.baseStyle,
              options: MarkdownOptions(
                headingRules: true,
                image: (src, alt, title) =>
                    _MarkdownImage(src: src, alt: alt, base: readmeUrl, client: _client),
              ),
            ),
          );
        },
      );

  Widget _muted(String text) => Text(
    text,
    style: TextStyle(fontSize: 13, color: themeColors['descriptionForeground']),
  );

  Widget _features(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    return FutureBuilder<ExtensionManifestInfo?>(
      future: _manifest,
      builder: (context, snapshot) {
        final manifest = snapshot.data;
        if (manifest == null) {
          return snapshot.connectionState == ConnectionState.done
              ? _muted(l10n.extsNoContributions)
              : const SizedBox(height: 40);
        }
        final contributions = manifest.contributions;
        final heading = TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors['foreground'],
        );
        final body = TextStyle(fontSize: 13, color: colors['foreground']);
        final muted = TextStyle(
          fontSize: 12,
          color: colors['descriptionForeground'],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.extsContributions, style: heading),
            const SizedBox(height: 8),
            if (contributions.isEmpty) _muted(l10n.extsNoContributions),
            for (final entry in contributions.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${entry.kind} (${entry.count})', style: body),
                    if (entry.items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 2),
                        child: Text(
                          entry.items.take(12).join(', ') +
                              (entry.items.length > 12 ? ', …' : ''),
                          style: muted,
                        ),
                      ),
                  ],
                ),
              ),
            if (manifest.activationEvents.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.extsActivationEvents, style: heading),
              const SizedBox(height: 4),
              Text(manifest.activationEvents.join(', '), style: muted),
            ],
            if (manifest.enabledApiProposals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(l10n.extsApiProposals, style: heading),
              const SizedBox(height: 4),
              Text(manifest.enabledApiProposals.join(', '), style: muted),
            ],
          ],
        );
      },
    );
  }

  Widget _sidebar(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: themeColors.get('panelSection.border') ??
              themeColors['panel.border'],
        ),
      ),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: _sidebarContent(context),
    ),
  );

  Widget _sidebarContent(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final installed = _installed;
    final gallery = _galleryValue;
    final manifest = installed?.manifest;
    final heading = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colors['foreground'],
    );
    Widget row(String label, String? value) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors['descriptionForeground'],
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: TextStyle(fontSize: 12, color: colors['foreground']),
                  ),
                ),
              ],
            ),
          );
    final capability = installed == null
        ? null
        : _model.capabilities[installed.key];
    final timestamp = gallery?.timestamp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.extsCompatibility, style: heading),
        const SizedBox(height: 8),
        if (capability != null)
          CapabilitySummary(capability)
        else
          FutureBuilder<CapabilityReport?>(
            future: _galleryCapability,
            builder: (context, snapshot) => snapshot.data == null
                ? const SizedBox(height: 20)
                : CapabilitySummary(snapshot.data!, fromManifest: true),
          ),
        const SizedBox(height: 20),
        Text(l10n.extsInformation, style: heading),
        const SizedBox(height: 8),
        row(l10n.extsInfoIdentifier, widget.id),
        row(l10n.extsInfoVersion, installed?.version ?? gallery?.version),
        if (installed != null && gallery != null &&
            gallery.version != installed.version)
          row(l10n.extsInfoLatest, gallery.version),
        row(
          l10n.extsInfoLastUpdated,
          timestamp == null
              ? null
              : '${timestamp.year}-${_two(timestamp.month)}-${_two(timestamp.day)}',
        ),
        row(l10n.extsInfoEngine, manifest?.engine ?? gallery?.engine),
        row(
          l10n.extsInfoPlatform,
          (manifest?.targetPlatform.isSpecific ?? false)
              ? manifest!.targetPlatform.label
              : gallery?.targetPlatform.label,
        ),
        row(l10n.extsInfoLicense, manifest?.license ?? gallery?.license),
        row(
          l10n.extsInfoRepository,
          manifest?.repository ?? gallery?.repository,
        ),
        row(
          l10n.extsInfoCategories,
          (manifest?.categories ?? gallery?.categories ?? const []).join(', '),
        ),
        if (installed != null) row(l10n.extsInfoLocation, installed.location),
      ],
    );
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

/// The version menu's button: the version and a chevron.
class _VersionButton extends StatelessWidget {
  const _VersionButton({required this.label, required this.entries});

  final String label;
  final FutureOr<List<IdeMenuEntry>> Function() entries;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 13, color: themeColors['foreground']),
      ),
      IdeMenuButton(
        icon: Codicons.chevronDown,
        tooltip: context.l10n.extsVersion,
        entries: entries,
      ),
    ],
  );
}

/// A README's image: fetched from the registry (relative to the README),
/// SVG or bitmap; its alt text while loading or when it cannot be.
class _MarkdownImage extends StatefulWidget {
  const _MarkdownImage({
    required this.src,
    required this.alt,
    required this.base,
    required this.client,
  });

  final String src;
  final String alt;
  final String? base;
  final OpenVsxClient client;

  @override
  State<_MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends State<_MarkdownImage> {
  late final Future<Uint8List>? _bytes = () {
    final base = widget.base == null ? null : Uri.tryParse(widget.base!);
    final uri = base == null
        ? Uri.tryParse(widget.src)
        : base.resolve(widget.src);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return widget.client.fetchBytes(uri.toString());
  }();

  @override
  Widget build(BuildContext context) {
    final alt = Text(
      widget.alt.isEmpty ? '' : '[${widget.alt}]',
      style: TextStyle(
        fontSize: 12,
        color: themeColors['descriptionForeground'],
      ),
    );
    final bytes = _bytes;
    if (bytes == null) return alt;
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return alt;
        final svg = String.fromCharCodes(data.take(256)).contains('<svg');
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480, maxWidth: 900),
          child: svg
              ? SvgPicture.memory(data, height: 20)
              : Image.memory(data, errorBuilder: (_, _, _) => alt),
        );
      },
    );
  }
}
