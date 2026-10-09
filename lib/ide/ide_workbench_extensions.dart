part of 'ide_workbench.dart';

// The workbench's VS Code extensions (lib/extensions/workbench/): the
// Extensions view and an extension's page, the extensions' status bar
// entries, quick inputs, output channels, Command Palette commands and
// keybindings, the runtime's download, recommendations for the files
// opened, and .vsix files dropped on the window.

extension _ExtensionsPart on IdeWorkbenchState {
  WorkspaceExtensions? get _workspaceExtensions => widget.extensions;

  /// Follows [extensions]' UI state: what the status bar and the panel
  /// show of them, and the window dialogs are shown in.
  void _attachExtensions(WorkspaceExtensions? extensions) {
    if (extensions == null) return;
    extensions.dialogContext = () => mounted ? context : null;
    extensions.contextKeys.fallback = keyContext;
    extensions.statusBar.addListener(_extensionsUiChanged);
    extensions.output
      ..addListener(_extensionsUiChanged)
      // `OutputChannel.show()`: the OUTPUT tab, focused unless asked not.
      ..onRevealPanel = (preserveFocus) {
        if (!mounted) return;
        _selectPanel(IdePanelTab.output);
        if (!preserveFocus) _focusPanel();
      };
    extensions.addListener(_extensionsUiChanged);
    ExtensionRuntimeService.instance.addListener(_extensionsUiChanged);
    _syncExtensionKeybindings();
  }

  void _detachExtensions(WorkspaceExtensions? extensions) {
    if (extensions == null) return;
    if (extensions.contextKeys.fallback == keyContext) {
      extensions.contextKeys.fallback = null;
    }
    extensions.dialogContext = null;
    extensions.statusBar.removeListener(_extensionsUiChanged);
    extensions.output
      ..removeListener(_extensionsUiChanged)
      ..onRevealPanel = null
      ..panelVisible.value = false;
    extensions.removeListener(_extensionsUiChanged);
    ExtensionRuntimeService.instance.removeListener(_extensionsUiChanged);
    _extensionKeys?.dispose();
    _extensionKeys = null;
  }

  void _extensionsUiChanged() {
    if (mounted) _refresh(() {});
  }

  /// The keybinding service has the extensions' keybindings of the
  /// workbench showing (it holds one set: the window's).
  void _syncExtensionKeybindings() {
    final extensions = _workspaceExtensions;
    if (extensions == null || !widget.visible) {
      _extensionKeys?.dispose();
      _extensionKeys = null;
      return;
    }
    _extensionKeys ??= ExtensionKeybindingsBridge(
      registry: extensions.commands,
      contextKeys: extensions.contextKeys,
    );
  }

  /// The Extensions view; a message where this folder has none (a remote
  /// one's, for now).
  Widget _extensionsView() {
    final extensions = _workspaceExtensions;
    if (extensions == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          context.l10n.extsNoHost,
          style: TextStyle(color: themeColors['descriptionForeground']),
        ),
      );
    }
    final model = extensions.extensionsModel;
    if (model.installed == null && model.installedError == null) {
      unawaited(model.refreshInstalled());
    }
    // The Recommended pane follows the files open (after this build: it
    // notifies the view).
    final recommended = extensions.recommendations(widget.workspace.documents);
    if (!listEquals(recommended, model.recommendedIds)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!listEquals(recommended, model.recommendedIds)) {
          unawaited(model.setRecommendations(recommended));
        }
      });
    }
    return ExtensionsView(
      model: model,
      onOpen: (entry) => _refresh(() => _extensionPage = entry.id),
      onInstallFromVsix: () => unawaited(_installFromVsix()),
      onImport: () => unawaited(_importExtensions()),
      onError: _reportMessage,
    );
  }

  void _reportMessage(String message) =>
      _notifications.notify(IdeSeverity.error, message);

  /// Install from VSIX...: one picked in the open panel.
  Future<void> _installFromVsix() async {
    final extensions = _workspaceExtensions;
    if (extensions == null) return;
    final paths = await WindowControls.pickOpenFiles(multiple: false);
    if (paths.isEmpty || !mounted) return;
    await showVsixInstallSheet(
      context,
      paths.first,
      backend: extensions.management,
      locale: extensions.app.language,
    );
  }

  /// Import from VS Code, Cursor, Windsurf or VSCodium.
  Future<void> _importExtensions() async {
    final extensions = _workspaceExtensions;
    if (extensions == null) return;
    final app = extensions.app;
    await showExtensionImportDialog(
      context,
      planner: ExtensionImportPlanner(
        installs: VsCodeInstalls.current(),
        gallery: app.gallery,
        locale: app.language,
      ),
      importer: ExtensionImporter(
        backend: extensions.management,
        gallery: app.gallery,
      ),
      backend: extensions.management,
      settingsPath: DataDirectory.current.settingsFile,
    );
  }

  /// Takes the .vsix files and extension folders among [paths] dropped on
  /// the window: false when there are none (they open as files do).
  bool _dropExtensions(List<String> paths) {
    final extensions = _workspaceExtensions;
    if (extensions == null || !paths.any(_isExtensionDrop)) return false;
    unawaited(
      handleExtensionDrop(
        context,
        paths,
        backend: extensions.management,
        locale: extensions.app.language,
        onLoadDevelopmentFolder: (folder) =>
            unawaited(extensions.loadDevelopmentExtension(folder)),
      ),
    );
    return true;
  }

  /// A .vsix, or a folder with an extension's package.json (what
  /// [classifyExtensionDrop] tells apart, as the drop must be taken or
  /// not at once).
  static bool _isExtensionDrop(String path) {
    if (path.toLowerCase().endsWith('.vsix')) return true;
    try {
      final manifest = File(p.join(path, 'package.json'));
      if (!manifest.existsSync()) return false;
      return switch (parseJsonc(manifest.readAsStringSync())) {
        {'engines': {'vscode': String _}} => true,
        _ => false,
      };
    } on Object {
      return false;
    }
  }

  /// An extension's page over the editors, with a bar to close it.
  Widget _extensionPageView(String id) {
    final extensions = _workspaceExtensions!;
    final l10n = context.l10n;
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
                    id,
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
              model: extensions.extensionsModel,
              id: id,
              onError: _reportMessage,
            ),
          ),
        ],
      ),
    );
  }

  /// The OUTPUT tab's content; none without extensions. The output
  /// service is told whether it shows ([shown]: the panel is up on it), as
  /// a channel shown reads its file only then.
  Widget? _extensionOutput({required bool shown}) {
    final extensions = _workspaceExtensions;
    if (extensions == null) return null;
    final visible = extensions.output.panelVisible;
    if (visible.value != shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(_workspaceExtensions, extensions)) visible.value = shown;
      });
    }
    return ExtensionOutputPanel(
      service: extensions.output,
      onOpenInEditor: (path) => unawaited(_open(path)),
    );
  }

  /// The extensions' status bar entries of a side, and on the left the
  /// runtime's download.
  List<IdeStatusBarItem> _extensionStatusItems({required bool left}) {
    final extensions = _workspaceExtensions;
    if (extensions == null) return const [];
    return [
      if (left)
        ?extensionRuntimeStatusItem(
          ExtensionRuntimeService.instance.state,
          l10n: context.l10n,
          onRetry: () => unawaited(_retryRuntime(extensions)),
        ),
      ...extensionStatusBarItems(
        extensions.statusBar,
        left: left,
        commands: WorkbenchCommandExecutor(extensions.commands),
        onContextMenu: (position, entry) => unawaited(
          showExtensionStatusBarMenu(
            context,
            position,
            extensions.statusBar,
            entry,
          ),
        ),
      ),
    ];
  }

  Future<void> _retryRuntime(WorkspaceExtensions extensions) async {
    try {
      await ExtensionRuntimeService.instance.ensureReady();
      await extensions.startHost();
    } on Object {
      // The status bar says it failed.
    }
  }

  /// The extensions' commands for the Command Palette, and the
  /// workbench's own over them.
  List<IdeCommand> _extensionCommands() {
    final extensions = _workspaceExtensions;
    if (extensions == null) return const [];
    return [
      IdeCommand(
        id: 'workbench.action.output.toggleOutput',
        category: 'View',
        label: 'Toggle Output',
        run: () => _togglePanel(IdePanelTab.output),
      ),
      IdeCommand(
        id: 'workbench.extensions.action.installVSIX',
        category: 'Extensions',
        label: 'Install from VSIX...',
        run: () => unawaited(_installFromVsix()),
      ),
      IdeCommand(
        id: 'baocode.extensions.import',
        category: 'Extensions',
        label: 'Import Extensions from Another Editor...',
        run: () => unawaited(_importExtensions()),
      ),
      IdeCommand(
        id: 'editor.action.inlineSuggest.trigger',
        label: 'Trigger Inline Suggestion',
        enabled: widget.workspace.active != null,
        run: () => unawaited(extensions.editorFeatures?.trigger()),
      ),
      IdeCommand(
        id: 'workbench.action.restartExtensionHost',
        category: 'Developer',
        label: 'Restart Extension Host',
        run: () => unawaited(extensions.host?.manager.restart()),
      ),
      ...extensions.palette.commands(),
    ];
  }

  /// Recommends the extensions of the active file's language when none
  /// installed provides it, once a session each, as upstream's
  /// `FileBasedRecommendations`: in the notification center, with Install.
  void _recommendExtensions() {
    final extensions = _workspaceExtensions;
    final active = widget.workspace.active;
    if (!_localized || extensions == null || active == null) return;
    if (!active.isFile) return;
    final installed = extensions.extensionsModel.installed;
    // Recommended once the installed ones are known.
    if (installed == null) {
      unawaited(
        extensions.extensionsModel.refreshInstalled().then((_) {
          if (mounted && extensions.extensionsModel.installed != null) {
            _recommendExtensions();
          }
        }),
      );
      return;
    }
    final ids = recommendationsFor(
      active.path,
      installed: {for (final extension in installed) extension.key},
      providesLanguage: extensions.languageRegistry.installed.containsKey,
    );
    final id = ids.firstOrNull;
    if (id == null ||
        widget.ignoredRecommendations.contains(id) ||
        !_recommendedExtensions.add(id)) {
      return;
    }
    final language =
        recommendationForPath(active.path)?.label ??
        IdeLanguageNames.forPath(active.path);
    final l10n = context.l10n;
    _notifications.notify(
      IdeSeverity.info,
      l10n.wbRecommendExtension(id, language),
      sticky: true,
      silent: true,
      primary: [
        IdeNotificationAction(
          l10n.extInstall,
          () => unawaited(extensions.extensionsModel.install(id)),
        ),
      ],
      secondary: [
        IdeNotificationAction(
          l10n.wbRecommendExtensionDontShow,
          () => widget.onIgnoreRecommendation?.call(id),
        ),
      ],
    );
  }
}
