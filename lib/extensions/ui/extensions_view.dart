/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Extensions view: a search box, then the Installed and Popular Themes
// panes, or the themes a search found on Open VSX (`@installed` and
// `@updates` filter instead). Each extension is a 72px
// row: icon, name and version, description, publisher, its capability,
// and Install, Update or the Manage menu.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/extensions/browser/extensionsViewlet.ts,
// extensionsViews.ts, extensionsList.ts, extensionsActions.ts and their
// media/extensionsViewlet.css, extension.css and extensionActions.css.
//
// Deviations: the gallery is Open VSX, searched for themes (BaoCode runs no
// extension code: only their color and file icon themes apply); a row shows
// the capability badge; a click opens the extension's page through
// [ExtensionsView.onOpen], which the workbench shows as an editor.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_input.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_panes.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../capabilities/capability_analysis.dart';
import 'extension_widgets.dart';
import 'extensions_model.dart';

class ExtensionsView extends StatefulWidget {
  const ExtensionsView({
    super.key,
    required this.model,
    this.onOpen,
    this.onInstallFromVsix,
    this.onError,
  });

  final ExtensionsModel model;

  /// Opens an extension's page.
  final ValueChanged<ExtensionEntry>? onOpen;

  /// Picks a .vsix to install (then [showVsixInstallSheet]).
  final VoidCallback? onInstallFromVsix;
  final ValueChanged<String>? onError;

  @override
  State<ExtensionsView> createState() => _ExtensionsViewState();
}

class _ExtensionsViewState extends State<ExtensionsView> {
  final FocusNode _listFocus = FocusNode(debugLabel: 'Extensions list');
  final FocusNode _queryFocus = FocusNode(debugLabel: 'Extensions search');
  late final TextEditingController _query = TextEditingController(
    text: widget.model.queryText,
  );

  ExtensionsModel get _model => widget.model;

  @override
  void initState() {
    super.initState();
    _model.addListener(_changed);
    _listFocus.addListener(_changed);
    if (_model.installed == null) unawaited(_model.refreshInstalled());
    unawaited(_model.loadPopular());
  }

  @override
  void didUpdateWidget(ExtensionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      oldWidget.model.removeListener(_changed);
      widget.model.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _model.removeListener(_changed);
    _listFocus.dispose();
    _queryFocus.dispose();
    _query.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _search(String text) {
    _query.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _model.setQuery(text);
    _queryFocus.requestFocus();
  }

  Future<void> _guard(String id, Future<void> Function() action) async {
    final l10n = context.l10n;
    try {
      await action();
    } catch (error) {
      widget.onError?.call(l10n.extInstallError(id, '$error'));
    }
  }

  List<IdeMenuEntry> _menu(ExtensionEntry entry) {
    final l10n = context.l10n;
    final installed = entry.installed;
    final busy = _model.busy.containsKey(entry.key);
    final update = _model.updates[entry.key];
    return [
      if (installed == null)
        IdeMenuAction(
          l10n.extInstall,
          enabled: !busy,
          onSelected: () =>
              unawaited(_guard(entry.id, () => _model.install(entry.id))),
        )
      else ...[
        if (update != null)
          IdeMenuAction(
            l10n.extsUpdateTo(update.version),
            enabled: !busy,
            onSelected: () =>
                unawaited(_guard(entry.id, () => _model.update(entry.id))),
          ),
        IdeMenuAction(
          installed.enabled ? l10n.extsDisable : l10n.extsEnable,
          onSelected: () =>
              unawaited(_model.setEnabled(entry.id, !installed.enabled)),
        ),
        if (installed.fromGallery)
          IdeMenuAction(
            installed.preRelease
                ? l10n.extsSwitchToRelease
                : l10n.extsSwitchToPreRelease,
            enabled: !busy,
            onSelected: () => unawaited(
              _guard(
                entry.id,
                () =>
                    _model.install(entry.id, preRelease: !installed.preRelease),
              ),
            ),
          ),
        IdeMenuAction(
          l10n.extUninstall,
          enabled: !busy,
          onSelected: () =>
              unawaited(_guard(entry.id, () => _model.uninstall(entry.id))),
        ),
      ],
      const IdeMenuSeparator(),
      IdeMenuAction(
        l10n.extCopyId,
        onSelected: () =>
            unawaited(Clipboard.setData(ClipboardData(text: entry.id))),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    final l10n = context.l10n;
    final query = model.query;
    final title = query.isEmpty
        ? l10n.extTitle
        : switch (query.filter) {
            'installed' => l10n.extTitleInstalled,
            'updates' => l10n.extsTitleUpdates,
            _ => l10n.extsTitleOpenVsx,
          };
    return ColoredBox(
      color: AppColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeViewTitle(
            title,
            actions: [
              IdeMenuButton(
                icon: Codicons.filter,
                tooltip: l10n.extFilter,
                entries: () => [
                  IdeMenuAction(
                    l10n.extInstalled,
                    onSelected: () => _search('@installed '),
                  ),
                  IdeMenuAction(
                    l10n.extsUpdates,
                    onSelected: () => _search('@updates '),
                  ),
                ],
              ),
              IdePaneAction(
                icon: Codicons.refresh,
                tooltip: l10n.extsCheckForUpdates,
                onPressed: () => unawaited(
                  model.refreshInstalled().then((_) => model.checkUpdates()),
                ),
              ),
              IdePaneAction(
                icon: Codicons.clearAll,
                tooltip: l10n.extClearSearch,
                onPressed: query.isEmpty ? null : () => _search(''),
              ),
              IdeMenuButton(
                icon: Codicons.ellipsis,
                tooltip: l10n.extsMoreActions,
                entries: () => [
                  IdeMenuAction(
                    l10n.extsInstallFromVsix,
                    enabled: widget.onInstallFromVsix != null,
                    onSelected: widget.onInstallFromVsix,
                  ),
                  const IdeMenuSeparator(),
                  IdeMenuAction(
                    l10n.extsCheckForUpdates,
                    onSelected: () => unawaited(model.checkUpdates()),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(
            height: 2,
            child: model.loading || model.busy.isNotEmpty
                ? LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: themeColors['progressBar.background'],
                  )
                : null,
          ),
          // `.extensions-viewlet > .header`: padded 5 12 6 20.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 12, 6),
            child: IdeInputBox(
              controller: _query,
              focusNode: _queryFocus,
              placeholder: l10n.extsSearchPlaceholder,
              semanticsLabel: l10n.extsSearchPlaceholder,
              onChanged: model.setQuery,
              onSubmitted: (_) => unawaited(model.search()),
            ),
          ),
          Expanded(
            child: Focus(focusNode: _listFocus, child: _body()),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final model = _model;
    final l10n = context.l10n;
    final query = model.query;
    if (model.installed == null && model.installedError != null) {
      return _message('${model.installedError}');
    }
    switch (query.filter) {
      case 'installed':
        return _list(model.installedEntries);
      case 'updates':
        return _list(model.updateEntries);
    }
    if (query.text.isNotEmpty) {
      if (model.searchError case final error?) {
        return _message(l10n.extsSearchFailed('$error'));
      }
      if (model.searching && model.results.isEmpty) {
        return const SizedBox.shrink();
      }
      return _list(
        model.resultEntries,
        more: model.results.length < model.resultsTotal,
      );
    }
    final installed = model.installedEntries;
    final popular = model.popularEntries;
    return IdePaneContainer(
      panes: [
        IdePane(
          id: 'installed',
          title: l10n.extInstalled,
          weight: 100,
          badge: IdeCountBadge(installed.length),
          body: _list(installed),
        ),
        IdePane(
          id: 'popular',
          title: l10n.extsPopularThemes,
          weight: 100,
          body: model.popularError != null && model.popular == null
              ? _message(l10n.extsSearchFailed('${model.popularError}'))
              : model.popular == null
              ? const SizedBox.shrink()
              : _list(popular),
        ),
      ],
      expanded: model.expanded,
      onToggle: model.toggle,
    );
  }

  /// `.message-container`: padded 5 9 5 20.
  Widget _message(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 5, 9, 5),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: themeColors['sideBar.foreground']),
    ),
  );

  Widget _list(List<ExtensionEntry> entries, {bool more = false}) {
    if (entries.isEmpty) return _message(context.l10n.extNoneFound);
    return ListView.builder(
      itemExtent: ExtensionRow.height,
      itemCount: entries.length + (more ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return Center(
            child: ExtensionActionButton(
              label: context.l10n.extsLoadMore,
              prominent: false,
              large: true,
              onPressed: _model.searching
                  ? null
                  : () => unawaited(_model.search(more: true)),
            ),
          );
        }
        final entry = entries[index];
        return ExtensionRow(
          entry: entry,
          model: _model,
          selected: _model.selected == entry.key,
          focused: _listFocus.hasFocus,
          onTap: () {
            _model.select(entry.key);
            _listFocus.requestFocus();
            widget.onOpen?.call(entry);
          },
          onInstall: () =>
              unawaited(_guard(entry.id, () => _model.install(entry.id))),
          onUpdate: () =>
              unawaited(_guard(entry.id, () => _model.update(entry.id))),
          menu: () => _menu(entry),
        );
      },
    );
  }
}

/// An extension's row (`.extension-list-item`).
class ExtensionRow extends StatelessWidget {
  const ExtensionRow({
    super.key,
    required this.entry,
    required this.model,
    required this.menu,
    this.selected = false,
    this.focused = false,
    this.onTap,
    this.onInstall,
    this.onUpdate,
  });

  /// `EXTENSION_LIST_ELEMENT_HEIGHT`.
  static const height = 72.0;

  final ExtensionEntry entry;
  final ExtensionsModel model;
  final List<IdeMenuEntry> Function() menu;
  final bool selected;
  final bool focused;
  final VoidCallback? onTap;
  final VoidCallback? onInstall;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final installed = entry.installed;
    final gallery = entry.gallery;
    final busy = model.busy[entry.key];
    final update = model.updates[entry.key];
    final capability = model.capabilities[entry.key];
    final colors = themeColors;
    final foreground =
        (selected
            ? colors.get(
                focused
                    ? 'list.activeSelectionForeground'
                    : 'list.inactiveSelectionForeground',
              )
            : null) ??
        colors['sideBar.foreground'];
    final description = selected || colors.highContrast
        ? foreground
        : colors['descriptionForeground'];
    final disabled = installed != null && !installed.enabled;
    final version = entry.version;
    return IdeListRow(
      height: height,
      selected: selected,
      focused: focused,
      onTap: onTap,
      onContextMenu: (position) =>
          showIdeMenu(context, position: position, entries: menu()),
      builder: (context, hovered) => Opacity(
        opacity: disabled ? .6 : 1,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              // `.extension-icon .icon`: 36px, 16px before the details.
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ExtensionIcon(
                  bytes: installed?.manifest.iconBytes,
                  url: gallery?.iconUrl,
                  gallery: model.gallery,
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 20,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Row(
                          children: [
                            // The name and version take the row; the rest
                            // stays at its end (a Spacer took half of it).
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      entry.label,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: foreground,
                                        decoration: gallery?.deprecated ?? false
                                            ? TextDecoration.lineThrough
                                            : null,
                                        decorationColor: foreground,
                                      ),
                                    ),
                                  ),
                                  if (version.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 6),
                                      child: Text(
                                        version,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: description,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (gallery != null && gallery.downloadCount > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Codicons.cloudDownload,
                                      size: 14,
                                      color: description,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      formatInstallCount(gallery.downloadCount),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: description,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        entry.description ?? '',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: description),
                      ),
                    ),
                    Container(
                      height: 24,
                      padding: const EdgeInsets.only(top: 2, right: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    entry.publisher,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? foreground
                                          : description,
                                    ),
                                  ),
                                ),
                                if (gallery?.verified ?? false)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 3),
                                    child: Icon(
                                      Codicons.verifiedFilled,
                                      size: 13,
                                      color:
                                          colors.get(
                                            'extensionIcon.verifiedForeground',
                                          ) ??
                                          colors['textLink.foreground'],
                                    ),
                                  ),
                                if (disabled)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                      l10n.extsDisabled,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: description,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (capability != null &&
                              capability.level != ExtensionCapabilityLevel.full)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: CapabilityBadge(
                                capability.level,
                                compact: true,
                              ),
                            ),
                          if (busy != null)
                            ExtensionActionButton(
                              label: switch (busy) {
                                ExtensionBusy.installing => l10n.extInstalling,
                                ExtensionBusy.uninstalling =>
                                  l10n.extUninstalling,
                                ExtensionBusy.updating => l10n.extsUpdating,
                              },
                            )
                          else if (installed == null)
                            ExtensionActionButton(
                              label: l10n.extInstall,
                              onPressed: onInstall,
                            )
                          else if (update != null)
                            ExtensionActionButton(
                              label: l10n.extsUpdateTo(update.version),
                              onPressed: onUpdate,
                            ),
                          if (installed != null)
                            IdeMenuButton(
                              icon: Codicons.gear,
                              tooltip: l10n.extManage,
                              entries: menu,
                            ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
