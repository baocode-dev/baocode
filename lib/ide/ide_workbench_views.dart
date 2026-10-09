part of 'ide_workbench.dart';

// The extensions' views in the workbench (lib/extensions/views/): their
// view containers in the activity bar and the side bar, their views as
// panes there and in the Explorer, which of them show, opening one, and
// their commands (`workbench.view.extension.<id>`, `<viewId>.focus`).

extension _ViewsPart on IdeWorkbenchState {
  ContextKeyService? get _viewContext => widget.extensions?.contextKeys;

  void _attachViews(WorkspaceExtensions extensions) {
    extensions.views
      ..addListener(_extensionsUiChanged)
      ..opener = _openExtensionView;
    // Extensions run the workbench's commands too
    // (`CommandsRegistry`), but not their own palette entries again.
    extensions.commands.appCommands = _commandsForExtensions;
  }

  void _detachViews(WorkspaceExtensions extensions) {
    final views = extensions.views..removeListener(_extensionsUiChanged);
    if (views.opener == _openExtensionView) views.opener = null;
    views.setVisibleViews(const {});
    if (extensions.commands.appCommands == _commandsForExtensions) {
      extensions.commands.appCommands = null;
    }
  }

  /// The workbench's commands extensions may run, kept until the frame
  /// ends (menus ask for them at each row). Asked again while making them
  /// (the palette's extension commands ask), none.
  Map<String, IdeCommand> _commandsForExtensions() {
    if (_makingAppCommands) return const {};
    final cached = _appCommandsCache;
    if (cached != null) return cached;
    _makingAppCommands = true;
    try {
      final registry = widget.extensions?.commands;
      final commands = {
        for (final MapEntry(:key, :value) in _commandsById().entries)
          if (registry == null ||
              (registry.contribution(key) == null &&
                  !registry.isExtensionCommand(key)))
            key: value,
      };
      _appCommandsCache = commands;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _appCommandsCache = null,
      );
      SchedulerBinding.instance.scheduleFrame();
      return commands;
    } finally {
      _makingAppCommands = false;
    }
  }

  /// `IViewsService.openView`: shows [viewId]'s container with its pane
  /// expanded.
  Future<void> _openExtensionView(String viewId, {required bool focus}) async {
    final views = widget.extensions?.views;
    final view = views?.contributions.view(viewId);
    if (!mounted || views == null || view == null) return;
    _refresh(() {
      if (view.containerId == BuiltinViewContainers.explorer) {
        _view = IdeSideView.explorer;
        _explorerPanes.add(view.id);
      } else {
        _view = IdeSideView.container;
        _viewContainer = view.containerId;
        _expandedContainerPanes(view.containerId).add(view.id);
      }
      _layout.showSidebar();
    });
    await WidgetsBinding.instance.endOfFrame;
  }

  Set<String> _expandedContainerPanes(String containerId) =>
      _containerPanes.putIfAbsent(containerId, () {
        final views = widget.extensions?.views;
        return {
          for (final view
              in views?.contributions.viewsIn(containerId) ?? const [])
            if (!view.collapsed) view.id,
        };
      });

  /// The extension views on screen: the Explorer's expanded ones, or
  /// those of the container showing; none with the side bar hidden.
  void _syncExtensionViews({required bool sidebarVisible}) {
    final extensions = widget.extensions;
    final context = _viewContext;
    if (extensions == null || context == null) return;
    final views = extensions.views;
    final shown = <String>{};
    if (sidebarVisible && widget.visible) {
      switch (_view) {
        case IdeSideView.explorer:
          for (final view in views.visibleViewsIn(
            BuiltinViewContainers.explorer,
            context,
          )) {
            if (_explorerPanes.contains(view.id)) shown.add(view.id);
          }
        case IdeSideView.container:
          final id = _viewContainer;
          if (id != null) {
            final visible = views.visibleViewsIn(id, context);
            final expanded = _expandedContainerPanes(id);
            for (final view in visible) {
              if (visible.length == 1 || expanded.contains(view.id)) {
                shown.add(view.id);
              }
            }
          }
        default:
      }
    }
    if (setEquals(shown, {
      for (final view in views.contributions.views)
        if (views.isVisible(view.id)) view.id,
    })) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(widget.extensions, extensions)) {
        views.setVisibleViews(shown);
      }
    });
  }

  /// The activity bar's entries of the extensions' containers that have a
  /// view to show.
  List<Widget> _extensionActivityItems({required bool joined}) {
    final extensions = widget.extensions;
    final context = _viewContext;
    if (extensions == null || context == null) return const [];
    final views = extensions.views;
    final keys = KeybindingService.instance;
    return [
      for (final container in [
        ...views.containersAt(ViewContainerLocation.sidebar, context),
        ...views.containersAt(ViewContainerLocation.auxiliaryBar, context),
      ])
        _ActivityItem(
          key: ValueKey('activity-${container.id}'),
          icon: switch (container.icon) {
            final ThemeIconRef ref => Codicons.byName[ref.id],
            ImageIcon() => null,
            null => Codicons.extensions,
          },
          iconBuilder: switch (container.icon) {
            // Image icons are masks in the activity bar's color.
            final ImageIcon image => (color) => ColorFiltered(
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              child: extensionIconWidget(
                image,
                size: IdeModernUI.activityIconSize,
              ),
            ),
            final ThemeIconRef ref when !Codicons.byName.containsKey(ref.id) =>
              (color) => Icon(
                Codicons.extensions,
                size: IdeModernUI.activityIconSize,
                color: color,
              ),
            _ => null,
          },
          label: keys.titleWithKeybinding(container.title, container.id),
          badge: _containerBadge(container.id),
          selected:
              joined &&
              _view == IdeSideView.container &&
              _viewContainer == container.id,
          onTap: () => _refresh(() {
            if (joined &&
                _view == IdeSideView.container &&
                _viewContainer == container.id) {
              _sidebarShown = false;
            } else {
              _view = IdeSideView.container;
              _viewContainer = container.id;
              _layout.showSidebar();
            }
          }),
        ),
    ];
  }

  /// The sum of [containerId]'s views' badges.
  int? _containerBadge(String containerId) {
    final views = widget.extensions?.views;
    if (views == null) return null;
    var total = 0;
    for (final view in views.contributions.viewsIn(containerId)) {
      total += views.treeView(view.id)?.badge?.value ?? 0;
    }
    return total == 0 ? null : total;
  }

  /// The side bar showing an extension's container: its views as panes,
  /// or its one view under the container's title.
  Widget _extensionContainerView() {
    final extensions = widget.extensions;
    final context = _viewContext;
    final id = _viewContainer;
    final container = id == null
        ? null
        : extensions?.views.contributions.container(id);
    final views = container == null || context == null
        ? const <ExtensionViewDescriptor>[]
        : extensions!.views.visibleViewsIn(container.id, context);
    Widget body;
    String title = container?.title ?? '';
    List<Widget> actions = const [];
    if (views.length == 1) {
      // `mergeViewWithContainerWhenSingleView`.
      final view = views.single;
      final pane = _extensionPane(view);
      title = pane.title == title || pane.title.isEmpty
          ? title
          : '$title: ${pane.title}';
      actions = pane.actions;
      body = pane.body;
    } else if (views.isEmpty) {
      body = const SizedBox.shrink();
    } else {
      final expanded = _expandedContainerPanes(container!.id);
      body = IdePaneContainer(
        expanded: expanded,
        onToggle: (id) => _refresh(() {
          if (!expanded.remove(id)) expanded.add(id);
        }),
        panes: [for (final view in views) _extensionPane(view)],
      );
    }
    return ColoredBox(
      color: themeColors['sideBar.background'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeViewTitle(title, actions: actions),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// The extensions' panes in one of the workbench's containers.
  List<IdePane> _extensionPanes(String containerId) {
    final extensions = widget.extensions;
    final context = _viewContext;
    if (extensions == null || context == null) return const [];
    return [
      for (final view in extensions.views.visibleViewsIn(containerId, context))
        _extensionPane(view),
    ];
  }

  IdePane _extensionPane(ExtensionViewDescriptor view) {
    final extensions = widget.extensions!;
    final tree = view.type == ExtensionViewType.tree
        ? extensions.views.treeView(view.id)
        : null;
    return IdePane(
      id: view.id,
      title: tree?.title ?? view.name,
      description: tree?.description,
      weight: view.weight ?? 1,
      actions: [
        ExtensionViewTitleActions(
          key: ValueKey('title-${view.id}'),
          viewId: view.id,
          menus: extensions.menus,
          contextKeys: extensions.contextKeys,
          treeView: tree,
        ),
      ],
      badge: extensionViewBadge(tree),
      body: tree == null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Text(
                context.l10n.extViewWebviewUnsupported,
                style: TextStyle(
                  fontSize: 13,
                  color: themeColors['descriptionForeground'],
                ),
              ),
            )
          : ExtensionTreeViewBody(
              key: ValueKey('tree-${view.id}'),
              treeView: tree,
              menus: extensions.menus,
              contextKeys: extensions.contextKeys,
              executeCommand: extensions.commands.executeCommand,
              welcome: extensions.views.contributions.welcomeFor(view.id),
              openLink: (href) =>
                  unawaited(extensions.app.openExternal?.call(href)),
              relativePath: _relative,
              onFocusChange: (focused) {
                if (focused) {
                  extensions.views.setFocusedView(view.id);
                } else if (extensions.views.focusedView == view.id) {
                  extensions.views.setFocusedView(null);
                }
              },
              onError: _reportMessage,
            ),
    );
  }

  /// `workbench.view.extension.<id>` for each container, `<viewId>.focus`
  /// and Collapse All for each view.
  List<IdeCommand> _viewCommands() {
    final extensions = widget.extensions;
    if (extensions == null) return const [];
    final views = extensions.views;
    final contributions = views.contributions;
    return [
      for (final container in contributions.containers)
        IdeCommand(
          id: container.id,
          category: 'View',
          label: 'Show ${container.title}',
          run: () => unawaited(views.openViewContainer(container.id)),
        ),
      for (final view in contributions.views)
        IdeCommand(
          id: '${view.id}.focus',
          category: 'View',
          label: 'Focus on ${view.name} View',
          run: () => unawaited(views.openView(view.id, focus: true)),
        ),
    ];
  }

  /// The views' Collapse All: for menus and keybindings, not the palette.
  List<IdeCommand> _viewKeyboardCommands() {
    final views = widget.extensions?.views;
    if (views == null) return const [];
    return [
      for (final view in views.contributions.views)
        if (view.type == ExtensionViewType.tree)
          IdeCommand(
            id: 'workbench.actions.treeView.${view.id}.collapseAll',
            label: 'Collapse All',
            run: () => views.treeView(view.id)?.collapseAll(),
          ),
    ];
  }
}
