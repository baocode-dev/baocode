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
    final body = switch (tab) {
      _ExtensionsTab.themes => ExtensionsView(
        model: themes!.model,
        onOpen: (entry) => _refresh(() => _extensionPage = entry.id),
        onInstallFromVsix: () => unawaited(_installFromVsix()),
        onError: _reportMessage,
      ),
      _ExtensionsTab.languageServers => IdeExtensionsView(
        session: _extensions ??= IdeExtensionsSession(
          widget.extensions ?? IdeLanguageServerExtensions(),
        ),
        recommended: _recommendedServers(),
        onInstalled: _startServer,
        onError: _report,
      ),
    };
    if (themes == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 30,
          child: Row(
            children: [
              const SizedBox(width: 12),
              for (final (value, label) in [
                (_ExtensionsTab.themes, l10n.extsTabThemes),
                (_ExtensionsTab.languageServers, l10n.extsTabLanguageServers),
              ])
                _ExtensionsTabButton(
                  label: label,
                  selected: tab == value,
                  onTap: () => _refresh(() => _extensionsTab = value),
                ),
            ],
          ),
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

  /// A theme extension's page over the editors, with a bar to close it.
  Widget _extensionPageView(String id) {
    final model = widget.themeExtensions!.model;
    final l10n = context.l10n;
    final key = id.toLowerCase();
    final installed = model.installed
        ?.where((extension) => extension.key == key)
        .firstOrNull;
    return ColoredBox(
      color: themeColors['editor.background'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 35,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  Codicons.extensions,
                  size: 16,
                  color: themeColors['tab.activeForeground'],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.extsPageTitle(installed?.manifest.label ?? id),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: themeColors['tab.activeForeground'],
                    ),
                  ),
                ),
                IdeActionButton(
                  icon: Codicons.close,
                  tooltip: l10n.extsPageClose,
                  onPressed: () => _refresh(() => _extensionPage = null),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Expanded(
            child: ExtensionDetailPage(
              key: ValueKey(id),
              model: model,
              id: id,
              onError: _reportMessage,
            ),
          ),
        ],
      ),
    );
  }

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

/// A tab of the Extensions view's header.
class _ExtensionsTabButton extends StatelessWidget {
  const _ExtensionsTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? colors['panelTitle.activeBorder']
                    : Colors.transparent,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.3,
              color:
                  colors[selected
                      ? 'panelTitle.activeForeground'
                      : 'panelTitle.inactiveForeground'],
            ),
          ),
        ),
      ),
    );
  }
}
