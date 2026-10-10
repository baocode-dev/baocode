part of 'ide_workbench.dart';

// The workbench's extensions: the Extensions view (the color and file icon
// theme extensions of lib/extensions/, and the language servers), a theme
// extension's page, .vsix files dropped on the window, and the debugger's
// listener.

/// What the Extensions view shows.
enum _ExtensionsTab { themes, languageServers }

extension _ExtensionsPart on IdeWorkbenchState {
  void _syncDebugListener() {
    final debug = _debug;
    if (identical(debug, _listenedDebug)) return;
    _listenedDebug?.removeListener(_debugChanged);
    _listenedDebug = debug?..addListener(_debugChanged);
  }

  void _debugChanged() {
    if (mounted) _refresh(() {});
  }

  /// The Extensions view: Themes and Language Servers, as tabs (the
  /// language servers alone without theme extensions).
  Widget _extensionsView() {
    final themes = widget.themeExtensions;
    final tab = themes == null
        ? _ExtensionsTab.languageServers
        : _extensionsTab;
    final l10n = context.l10n;
    // Under the tabs, on the editor's color as the tab in front is.
    final background = themes == null ? null : themeColors['editor.background'];
    final body = switch (tab) {
      _ExtensionsTab.themes => ExtensionsView(
        model: themes!.model,
        onOpen: _openExtensionPage,
        onInstallFromVsix: () => unawaited(_installFromVsix()),
        onError: _reportMessage,
        background: background,
      ),
      _ExtensionsTab.languageServers => IdeExtensionsView(
        session: _extensions ??= IdeExtensionsSession(
          widget.extensions ?? IdeLanguageServerExtensions(),
        ),
        recommended: _recommendedServers(),
        onInstalled: _startServer,
        onError: _report,
        background: background,
      ),
    };
    if (themes == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExtensionsTabs(
          tabs: [
            (_ExtensionsTab.themes, Codicons.symbolColor, l10n.extsTabThemes),
            (
              _ExtensionsTab.languageServers,
              Codicons.extensions,
              l10n.extsTabLanguageServers,
            ),
          ],
          selected: tab,
          onSelect: (value) => _refresh(() => _extensionsTab = value),
        ),
        Expanded(child: body),
      ],
    );
  }

  void _reportMessage(String message) =>
      _notifications.notify(IdeSeverity.error, message);

  /// Install from VSIX...: one picked in the open panel.
  Future<void> _installFromVsix() async {
    final themes = widget.themeExtensions;
    if (themes == null) return;
    final paths = await WindowControls.pickOpenFiles(multiple: false);
    if (paths.isEmpty || !mounted) return;
    await showVsixInstallSheet(
      context,
      paths.first,
      backend: themes,
      locale: themes.locale,
    );
  }

  /// Takes the .vsix files among [paths] dropped on the window: false when
  /// there are none (they open as files do).
  bool _dropExtensions(List<String> paths) {
    final themes = widget.themeExtensions;
    if (themes == null || !paths.any(isVsixDrop)) return false;
    unawaited(
      handleExtensionDrop(
        context,
        paths,
        backend: themes,
        locale: themes.locale,
      ),
    );
    return true;
  }

  /// Opens [entry]'s page as an editor, in place of the one open.
  void _openExtensionPage(ExtensionEntry entry) => _refresh(() {
    _extensionPage = entry;
    _extensionPageShown = true;
  });

  void _closeExtensionPage() => _refresh(() {
    _extensionPage = null;
    _extensionPageShown = false;
  });

  /// The extension page's tab, after the files'.
  Widget _extensionPageTab(ExtensionEntry entry) {
    final l10n = context.l10n;
    final key = entry.key;
    final installed = widget.themeExtensions!.model.installed
        ?.where((extension) => extension.key == key)
        .firstOrNull;
    final title = l10n.extsPageTitle(installed?.manifest.label ?? entry.label);
    final shown = _extensionPageShown;
    return IdeEditorTab(
      key: ValueKey(key),
      icon: const Icon(Codicons.extensions),
      label: title,
      active: shown,
      closeTooltip: shown
          ? KeybindingService.instance.titleWithKeybinding(
              l10n.tabCloseNamed(title),
              'workbench.action.closeActiveEditor',
            )
          : l10n.tabCloseNamed(title),
      onSelect: () => _refresh(() => _extensionPageShown = true),
      onClose: _closeExtensionPage,
    );
  }

  /// A theme extension's page, in the editors' place while its tab is
  /// the one in front.
  Widget _extensionPageView(ExtensionEntry entry) => ColoredBox(
    color: themeColors['editor.background'],
    child: ExtensionDetailPage(
      key: ValueKey(entry.key),
      model: widget.themeExtensions!.model,
      id: entry.id,
      onError: _reportMessage,
    ),
  );

  /// The Command Palette's extension commands.
  List<IdeCommand> _extensionCommands() => [
    if (widget.themeExtensions != null)
      IdeCommand(
        id: 'workbench.extensions.action.installVSIX',
        category: 'Extensions',
        label: 'Install from VSIX...',
        run: () => unawaited(_installFromVsix()),
      ),
    IdeCommand(
      id: 'workbench.action.selectIconTheme',
      category: 'Preferences',
      label: 'File Icon Theme',
      enabled: widget.settings != null,
      run: _selectIconTheme,
    ),
  ];

  /// Preferences: File Icon Theme: the bundled theme and the extensions';
  /// moving through them previews each, accepting keeps it in
  /// settings.json (`workbench.iconTheme`).
  void _selectIconTheme() {
    final service = FileIconThemeService.instance;
    final current = service.setting;
    final l10n = context.l10n;
    final ids = Map<IdeQuickPickItem, String?>.identity();
    IdeQuickPickItem item(String label, String? id, {String? description}) {
      final entry = IdeQuickPickItem(label: label, description: description);
      ids[entry] = id;
      return entry;
    }

    final bundled = item(
      'Material Icon Theme',
      null,
      description: l10n.themeIconThemeBuiltIn,
    );
    final themes = service.themes
      ..sort((a, b) => ideLocaleCompare(a.label, b.label));
    final items = [
      bundled,
      for (final theme in themes) item(theme.label, theme.id),
    ];
    var accepted = false;
    _showQuickModel(
      IdeQuickPick(
        items: items,
        placeholder: l10n.themeSelectIconThemePlaceholder,
        activeItems: [
          items.firstWhere(
            (candidate) => ids[candidate] == current,
            orElse: () => bundled,
          ),
        ],
        sortByLabel: false,
        onDidChangeActive: (item) {
          if (item != null) unawaited(service.select(ids[item]));
        },
        onDidAccept: (item) {
          if (item == null) return;
          accepted = true;
          final id = ids[item];
          unawaited(service.select(id));
          unawaited(
            widget.settings?.edit(
              const ['workbench.iconTheme'],
              id,
              remove: id == null,
            ),
          );
        },
        onDidHide: () {
          if (!accepted) unawaited(service.select(current));
        },
      ),
    );
  }
}

/// The Extensions view's header: its [tabs] as the editor's, scrolling
/// when the view is too narrow for them.
class _ExtensionsTabs extends StatefulWidget {
  const _ExtensionsTabs({
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<(_ExtensionsTab, IconData, String)> tabs;
  final _ExtensionsTab selected;
  final ValueChanged<_ExtensionsTab> onSelect;

  @override
  State<_ExtensionsTabs> createState() => _ExtensionsTabsState();
}

class _ExtensionsTabsState extends State<_ExtensionsTabs> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IdeTabStrip(
    child: TabStripScroll(
      controller: _scroll,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (value, icon, label) in widget.tabs)
            IdeEditorTab(
              key: ValueKey(value),
              icon: Icon(icon),
              label: label,
              active: widget.selected == value,
              minWidth: 0,
              onSelect: () => widget.onSelect(value),
            ),
        ],
      ),
    ),
  );
}
