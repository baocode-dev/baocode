/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Extensions view, listing language servers: a search box, then the
// Installed and Recommended panes, or one list of what a search found.
// Each is a 72px row: icon, name, description, publisher, and Install or
// the Manage menu.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/extensions/browser/extensionsViewlet.ts,
// extensionsViews.ts, extensionsList.ts, extensionsActions.ts and their
// media/extensionsViewlet.css, extension.css, extensionActions.css and
// extensionsWidgets.css.
//
// Deviations: a language server's name is its id; the version shows where
// the install count would; there is no extension editor, so a click only
// selects.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/codicons.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/material_file_icons.dart';
import '../ide_button.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import '../ide_panes.dart';
import 'ide_extensions.dart';

/// The view's state across switches to other views: the search, the list
/// and what is installing.
class IdeExtensionsSession extends ChangeNotifier {
  IdeExtensionsSession(this.service);

  final IdeExtensions service;
  final TextEditingController query = TextEditingController();

  /// Null until listed.
  List<IdeExtension>? extensions;
  bool loading = false;
  Object? error;

  /// What an extension is doing: `Installing` or `Uninstalling`.
  final Map<String, String> busy = {};
  final Set<String> expanded = {'installed', 'recommended'};
  String? selected;

  Future<void>? _listing;

  /// Lists the extensions again.
  Future<void> refresh() => _listing ??= _list().whenComplete(() {
    _listing = null;
  });

  Future<void> _list() async {
    loading = true;
    notifyListeners();
    try {
      extensions = await service.list();
      error = null;
    } catch (caught) {
      error = caught;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Installs [extension], then lists again; throws what installing threw.
  Future<void> install(IdeExtension extension) =>
      _run(extension, 'Installing', () => service.install(extension));

  Future<void> uninstall(IdeExtension extension) =>
      _run(extension, 'Uninstalling', () => service.uninstall(extension));

  Future<void> _run(
    IdeExtension extension,
    String label,
    Future<void> Function() action,
  ) async {
    if (busy.containsKey(extension.id)) return;
    busy[extension.id] = label;
    notifyListeners();
    try {
      await action();
    } finally {
      busy.remove(extension.id);
      notifyListeners();
    }
    await refresh();
  }

  void notify() => notifyListeners();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }
}

/// What a search asks for: `@installed` or `@recommended`, and words each
/// found in the name, languages or publisher.
({String? filter, List<String> words}) ideParseExtensionsQuery(String text) {
  String? filter;
  final words = <String>[];
  for (final word in text.toLowerCase().split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    if (word == '@installed' || word == '@recommended') {
      filter = word.substring(1);
    } else {
      words.add(word);
    }
  }
  return (filter: filter, words: words);
}

class IdeExtensionsView extends StatefulWidget {
  const IdeExtensionsView({
    super.key,
    required this.session,
    this.recommended = const {},
    this.onInstalled,
    this.onError,
  });

  final IdeExtensionsSession session;

  /// Servers the open files want and do not have.
  final Set<String> recommended;

  /// An extension installed: its server can start now.
  final ValueChanged<String>? onInstalled;
  final ValueChanged<String>? onError;

  @override
  State<IdeExtensionsView> createState() => _IdeExtensionsViewState();
}

class _IdeExtensionsViewState extends State<IdeExtensionsView> {
  final FocusNode _listFocus = FocusNode(debugLabel: 'Extensions list');
  final FocusNode _queryFocus = FocusNode(debugLabel: 'Extensions search');

  IdeExtensionsSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
    _listFocus.addListener(_changed);
    if (_session.extensions == null) unawaited(_session.refresh());
  }

  @override
  void didUpdateWidget(IdeExtensionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_changed);
      widget.session.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _listFocus.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool _isRecommended(IdeExtension extension) =>
      !extension.installed && widget.recommended.contains(extension.id);

  Future<void> _install(IdeExtension extension) async {
    try {
      await _session.install(extension);
      widget.onInstalled?.call(extension.id);
    } catch (error) {
      widget.onError?.call(
        "Error while installing '${extension.id}' extension. $error",
      );
    }
  }

  Future<void> _uninstall(IdeExtension extension) async {
    try {
      await _session.uninstall(extension);
    } catch (error) {
      widget.onError?.call(
        "Error while uninstalling '${extension.id}' extension. $error",
      );
    }
  }

  void _search(String text) {
    _session.query.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _session.notify();
    _queryFocus.requestFocus();
  }

  /// The Manage menu, and a row's context menu: install or uninstall,
  /// then copy.
  List<IdeMenuEntry> _menu(IdeExtension extension) {
    final busy = _session.busy.containsKey(extension.id);
    return [
      if (extension.state == IdeExtensionState.installable)
        IdeMenuAction(
          'Install',
          enabled: !busy,
          onSelected: () => unawaited(_install(extension)),
        ),
      if (extension.managed)
        IdeMenuAction(
          'Uninstall',
          enabled: !busy,
          onSelected: () => unawaited(_uninstall(extension)),
        ),
      if (extension.state == IdeExtensionState.installable || extension.managed)
        const IdeMenuSeparator(),
      IdeMenuAction(
        'Copy',
        onSelected: () =>
            unawaited(Clipboard.setData(ClipboardData(text: extension.info))),
      ),
      IdeMenuAction(
        'Copy Extension ID',
        onSelected: () =>
            unawaited(Clipboard.setData(ClipboardData(text: extension.id))),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final query = ideParseExtensionsQuery(session.query.text);
    final searching = session.query.text.trim().isNotEmpty;
    final title = !searching
        ? 'Extensions'
        : switch (query.filter) {
            'installed' => 'Extensions: Installed',
            'recommended' => 'Extensions: Recommended',
            _ => 'Extensions: Marketplace',
          };
    return ColoredBox(
      color: CursorColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeViewTitle(
            title,
            actions: [
              IdeMenuButton(
                icon: Codicons.filter,
                tooltip: 'Filter Extensions...',
                entries: () => [
                  IdeMenuAction(
                    'Installed',
                    onSelected: () => _search('@installed '),
                  ),
                  IdeMenuAction(
                    'Recommended',
                    onSelected: () => _search('@recommended '),
                  ),
                ],
              ),
              IdePaneAction(
                icon: Codicons.refresh,
                tooltip: 'Refresh',
                onPressed: session.loading
                    ? null
                    : () => unawaited(session.refresh()),
              ),
              IdePaneAction(
                icon: Codicons.clearAll,
                tooltip: 'Clear Extensions Search Results',
                onPressed: searching ? () => _search('') : null,
              ),
            ],
          ),
          SizedBox(
            height: 2,
            child: session.loading || session.busy.isNotEmpty
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: Color(0xFF878889),
                  )
                : null,
          ),
          // `.extensions-viewlet > .header`: 41px, padded 5 12 6 20.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 12, 6),
            child: IdeInputBox(
              controller: session.query,
              focusNode: _queryFocus,
              placeholder: 'Search Extensions in Marketplace',
              semanticsLabel: 'Search Extensions in Marketplace',
              onChanged: (_) => session.notify(),
            ),
          ),
          Expanded(
            child: Focus(focusNode: _listFocus, child: _body(query, searching)),
          ),
        ],
      ),
    );
  }

  Widget _body(({String? filter, List<String> words}) query, bool searching) {
    final session = _session;
    final extensions = session.extensions;
    if (extensions == null) {
      final error = session.error;
      return error == null ? const SizedBox.shrink() : _message('$error');
    }
    if (searching) {
      final found = [
        for (final extension in extensions)
          if (_matches(extension, query)) extension,
      ];
      return _list(found);
    }
    final installed = [
      for (final extension in extensions)
        if (extension.installed) extension,
    ];
    final recommended = [
      for (final extension in extensions)
        if (_isRecommended(extension)) extension,
    ];
    return IdePaneContainer(
      panes: [
        IdePane(
          id: 'installed',
          title: 'Installed',
          weight: 100,
          badge: IdeCountBadge(installed.length),
          body: _list(installed),
        ),
        IdePane(
          id: 'recommended',
          title: 'Recommended',
          weight: 40,
          badge: IdeCountBadge(recommended.length),
          body: _list(recommended),
        ),
      ],
      expanded: session.expanded,
      onToggle: (id) {
        if (!session.expanded.remove(id)) session.expanded.add(id);
        session.notify();
      },
    );
  }

  bool _matches(
    IdeExtension extension,
    ({String? filter, List<String> words}) query,
  ) {
    switch (query.filter) {
      case 'installed' when !extension.installed:
      case 'recommended' when !_isRecommended(extension):
        return false;
    }
    final text = [
      extension.id,
      ...extension.languages,
      ?extension.publisher,
    ].join(' ').toLowerCase();
    return query.words.every(text.contains);
  }

  /// `.message-container`: padded 5 9 5 20.
  Widget _message(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 5, 9, 5),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: IdeListColors.foreground),
    ),
  );

  Widget _list(List<IdeExtension> extensions) {
    if (extensions.isEmpty) return _message('No extensions found.');
    return ListView.builder(
      itemExtent: IdeExtensionRow.height,
      itemCount: extensions.length,
      itemBuilder: (context, index) {
        final extension = extensions[index];
        return IdeExtensionRow(
          extension: extension,
          busy: _session.busy[extension.id],
          selected: _session.selected == extension.id,
          focused: _listFocus.hasFocus,
          onTap: () {
            _session.selected = extension.id;
            _listFocus.requestFocus();
            _session.notify();
          },
          onInstall: () => unawaited(_install(extension)),
          menu: () => _menu(extension),
        );
      },
    );
  }
}

/// An extension's row (`.extension-list-item`).
class IdeExtensionRow extends StatelessWidget {
  const IdeExtensionRow({
    super.key,
    required this.extension,
    required this.menu,
    this.busy,
    this.selected = false,
    this.focused = false,
    this.onTap,
    this.onInstall,
  });

  /// `EXTENSION_LIST_ELEMENT_HEIGHT`.
  static const height = 72.0;

  /// `descriptionForeground`.
  static const _description = Color(0xFF8C8C8C);

  /// `editorWarning.foreground`.
  static const _warning = Color(0xFFCCA700);

  final IdeExtension extension;
  final List<IdeMenuEntry> Function() menu;

  /// What it is doing (`Installing`), if anything.
  final String? busy;
  final bool selected;
  final bool focused;
  final VoidCallback? onTap;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final extension = this.extension;
    final fileType = extension.fileType;
    final status = extension.status;
    final version = extension.version;
    return IdeListRow(
      height: height,
      selected: selected,
      focused: focused,
      onTap: onTap,
      onContextMenu: (position) =>
          showIdeMenu(context, position: position, entries: menu()),
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            // `.extension-icon .icon`: 36px, 16px before the details.
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox.square(
                dimension: 36,
                child: fileType == null
                    ? const Icon(
                        Codicons.extensions,
                        size: 36,
                        color: IdeListColors.foreground,
                      )
                    : FileIcon('language.$fileType', size: 36),
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
                          Expanded(
                            child: Text(
                              extension.id,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: IdeListColors.foreground,
                                decoration: extension.deprecated
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: IdeListColors.foreground,
                              ),
                            ),
                          ),
                          if (version != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                version,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _description,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      extension.description,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? IdeListColors.foreground
                            : _description,
                      ),
                    ),
                  ),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.only(top: 2, right: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            extension.publisher ?? '',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? IdeListColors.foreground
                                  : _description,
                            ),
                          ),
                        ),
                        if (status != null)
                          IdeHover(
                            message: status,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3),
                              child: Icon(
                                Codicons.warning,
                                size: 16,
                                color: _warning,
                              ),
                            ),
                          ),
                        if (busy case final busy?)
                          _ExtensionButton(label: busy)
                        else if (extension.state ==
                            IdeExtensionState.installable)
                          _ExtensionButton(
                            label: 'Install',
                            onPressed: onInstall,
                          ),
                        if (extension.installed)
                          IdeMenuButton(
                            icon: Codicons.gear,
                            tooltip: 'Manage',
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
    );
  }
}

/// `.extension-action.label.prominent`: 11px, padded 0 5px, 14px high
/// within a 1px border.
class _ExtensionButton extends StatefulWidget {
  const _ExtensionButton({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_ExtensionButton> createState() => _ExtensionButtonState();
}

class _ExtensionButtonState extends State<_ExtensionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 150),
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: enabled && _hover
                  ? IdeButtonColors.hoverBackground
                  : IdeButtonColors.background,
              border: Border.all(color: IdeButtonColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                height: 14 / 11,
                color: IdeButtonColors.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
