import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';

import '../chat/floating/floating_placement.dart';
import '../chat/widgets/hover_builder.dart';
import '../ide/ide_code_editor.dart';
import '../ide/ide_dialog.dart';
import '../ide/ide_hover.dart';
import '../l10n/l10n.dart';
import '../platform/app_platform.dart';
import '../remote/remote_location.dart';
import '../sidebar/sidebar.dart' show SidebarIconButton;
import '../sidebar/sidebar_menu.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/editor_launcher.dart';
import '../workspace/title_bar_double_click.dart';
import '../workspace/workspace.dart';
import 'customization_store.dart';
import 'customizations.dart';
import 'mcp_probe.dart';

extension CustomizationKindLabels on CustomizationKind {
  String label(AppLocalizations l10n) => switch (this) {
    CustomizationKind.plugins => l10n.customizeKindPlugins,
    CustomizationKind.mcps => l10n.customizeKindMcps,
    CustomizationKind.skills => l10n.customizeKindSkills,
    CustomizationKind.subagents => l10n.customizeKindSubagents,
    CustomizationKind.rules => l10n.customizeKindRules,
    CustomizationKind.commands => l10n.customizeKindCommands,
    CustomizationKind.hooks => l10n.customizeKindHooks,
  };

  IconData get icon => switch (this) {
    CustomizationKind.plugins => Codicons.package,
    CustomizationKind.mcps => Codicons.server,
    CustomizationKind.skills => Codicons.zap,
    CustomizationKind.subagents => Codicons.hubot,
    CustomizationKind.rules => Codicons.law,
    CustomizationKind.commands => Codicons.terminal,
    CustomizationKind.hooks => Codicons.link,
  };
}

extension on CustomizationScope {
  String label(AppLocalizations l10n) => switch (this) {
    CustomizationScope.user => l10n.customizeScopeUser,
    CustomizationScope.synced => l10n.customizeScopeSynced,
    CustomizationScope.project => l10n.customizeScopeProject,
    CustomizationScope.local => l10n.customizeScopeLocal,
    CustomizationScope.plugin => l10n.customizeScopePlugin,
  };
}

/// Claude Code's customizations, in place of the chat: a chip for each
/// kind (skills, subagents, commands, rules, MCP servers, hooks, plugins),
/// the user's and the project's of each; skills, subagents, commands and
/// rules made new, edited and deleted here, the others' files edited or
/// shown.
class CustomizeView extends StatefulWidget {
  const CustomizeView({
    super.key,
    required this.store,
    required this.projects,
    required this.onClose,
    this.project,
    this.kind = CustomizationKind.skills,
    this.leading,
    this.titleBarInset = 12,
    this.onOpenFile,
    this.host,
  });

  /// The customizations of the machine shown: this one's, or [host]'s.
  final CustomizationStore store;

  /// The remote host whose customizations these are, as the sidebar names
  /// it; null for this machine's.
  final String? host;

  /// The projects whose customizations can be shown beside the user's:
  /// those of the machine shown.
  final List<Project> projects;

  /// The one shown first; the user's alone when null.
  final Project? project;
  final CustomizationKind kind;
  final VoidCallback onClose;

  /// Before the title, by the traffic lights: the sidebar's toggle.
  final Widget? leading;
  final double titleBarInset;

  /// Opens a file in the IDE; none when null.
  final ValueChanged<String>? onOpenFile;

  /// Opens a folder in Finder; replaceable under test.
  @visibleForTesting
  static Future<bool> Function(Editor editor, String path) launch =
      openInEditor;

  /// Asks an MCP server whether it answers (this machine's servers alone);
  /// replaceable under test. None: no status shown.
  @visibleForTesting
  static McpProber? mcpProber = platformMcpProber;

  @override
  State<CustomizeView> createState() => CustomizeViewState();
}

class CustomizeViewState extends State<CustomizeView> {
  late CustomizationKind _kind = widget.kind;
  late Project? _project = widget.project;
  final TextEditingController _query = TextEditingController();

  List<Customization>? _items;
  Object? _error;
  int _generation = 0;

  /// The one being edited or looked at, in place of the list.
  Customization? _open;

  CustomizationKind get kind => _kind;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void didUpdateWidget(CustomizeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      // Another machine's: from its own projects, the list again.
      _project = widget.project;
      _open = null;
      _items = null;
      _error = null;
      if (oldWidget.kind != widget.kind) _kind = widget.kind;
      unawaited(_load());
    } else if (oldWidget.kind != widget.kind) {
      show(widget.kind);
    }
  }

  /// The project's folder on its machine (a remote one's path there).
  String? get _projectPath => switch (_project) {
    final project? => RemoteLocation.pathOf(project.path),
    null => null,
  };

  /// How paths are spelled where the customizations are.
  p.Context get _paths => widget.store.isLocal ? p.context : p.posix;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Shows [kind]'s list.
  void show(CustomizationKind kind) {
    setState(() {
      _kind = kind;
      _open = null;
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final items = await widget.store.list(_kind, project: _projectPath);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = items;
        _error = null;
      });
      _probeNew();
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = const [];
        _error = error;
      });
    }
  }

  void _setProject(Project? project) {
    setState(() => _project = project);
    unawaited(_load());
  }

  // --- MCP servers' status ------------------------------------------------

  /// What asking each MCP server found, by [_probeKey]: kept while the
  /// page is, so a server is asked again only when asked to or changed.
  final Map<String, McpProbeResult> _probes = {};

  /// The asking under way for each, the latest winning.
  final Map<String, int> _probing = {};
  int _probeCount = 0;

  /// A server as it is configured, for its project: changed, asked anew.
  String _probeKey(Customization item) =>
      jsonEncode([item.scope.name, item.name, item.server, _projectPath]);

  /// Whether [item], an MCP server, can be asked: one of this machine's
  /// with a command or URL (not a claude.ai connector), turned on.
  bool _probeable(Customization item) =>
      item.kind == CustomizationKind.mcps &&
      item.server != null &&
      item.enabled != false &&
      widget.store.isLocal &&
      CustomizeView.mcpProber != null;

  /// Where [item], an MCP server, stands; null for none to show.
  McpProbeResult? _statusOf(Customization item) {
    if (item.kind != CustomizationKind.mcps) return null;
    if (item.enabled == false) return McpProbeResult.disabled;
    if (!_probeable(item)) return null;
    return _probes[_probeKey(item)] ?? McpProbeResult.checking;
  }

  /// The servers listed not yet asked (new, or changed), asked.
  void _probeNew() {
    if (_kind != CustomizationKind.mcps) return;
    for (final item in _items ?? const <Customization>[]) {
      if (_probeable(item) && !_probing.containsKey(_probeKey(item))) {
        unawaited(_probe(item));
      }
    }
  }

  /// Asks [item], an MCP server (again, for Test connection).
  Future<void> _probe(Customization item) async {
    final prober = CustomizeView.mcpProber;
    if (prober == null || !_probeable(item)) return;
    final key = _probeKey(item);
    final count = _probing[key] = ++_probeCount;
    setState(() => _probes.remove(key));
    McpProbeResult result;
    try {
      result = await prober(item.server!, cwd: _projectPath);
    } on Object catch (error) {
      result = McpProbeResult(McpProbeStatus.failed, message: '$error');
    }
    if (!mounted || _probing[key] != count) return;
    setState(() => _probes[key] = result);
  }

  void _probeAll(Iterable<Customization> items) {
    for (final item in items) {
      unawaited(_probe(item));
    }
  }

  Future<void> _create(CustomizationScope scope) async {
    final l10n = context.l10n;
    final name = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (context) => _NameDialog(
        kind: _kind,
        title: l10n.customizeNewTitle(_kind.label(l10n)),
        taken: {
          for (final item in _items ?? const <Customization>[])
            if (item.scope == scope && item.removePath != null)
              p.basenameWithoutExtension(
                item.kind == CustomizationKind.skills
                    ? item.removePath!
                    : item.path,
              ),
        },
      ),
    );
    if (name == null || !mounted) return;
    try {
      final path = await widget.store.create(
        _kind,
        scope,
        name,
        project: _projectPath,
      );
      await _load();
      if (!mounted) return;
      final made = _items?.where((item) => item.path == path).firstOrNull;
      if (made != null) setState(() => _open = made);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _delete(Customization item) async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.customizeDeleteTitle(item.name),
      detail: l10n.customizeDeleteMessage(item.removePath!),
      buttons: [l10n.commonDelete],
    );
    if (choice != 0 || !mounted) return;
    try {
      await widget.store.delete(item);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
    if (mounted && identical(_open, item)) setState(() => _open = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitleBar(context.l10n),
        Expanded(
          child: open != null
              ? _CustomizationEditor(
                  key: ObjectKey(open),
                  item: open,
                  store: widget.store,
                  onBack: () {
                    setState(() => _open = null);
                    unawaited(_load());
                  },
                  onOpenFile: widget.store.isLocal ? widget.onOpenFile : null,
                  status: switch (_statusOf(open)) {
                    final status? => _McpStatusPanel(
                      status: status,
                      onTest: _probeable(open)
                          ? () => unawaited(_probe(open))
                          : null,
                    ),
                    null => null,
                  },
                )
              : _buildList(context.l10n),
        ),
      ],
    );
  }

  Widget _buildTitleBar(AppLocalizations l10n) {
    return TitleBarDoubleClick(
      child: SizedBox(
        height: AppMetrics.titleBarHeight,
        child: Row(
          children: [
            SizedBox(width: widget.leading == null ? widget.titleBarInset : 0),
            if (widget.leading case final leading?) ...[
              SizedBox(width: widget.titleBarInset - 34),
              leading,
              const SizedBox(width: 10),
            ],
            // Whose: a remote host's, named as the sidebar names it.
            if (widget.host case final host?) ...[
              Icon(Codicons.remote, size: 13, color: AppColors.textFaint),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
                ),
              ),
            ],
            const Spacer(),
            SidebarIconButton(
              icon: Codicons.close,
              tooltip: l10n.customizeClose,
              onTap: widget.onClose,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  List<Customization> get _shown {
    final query = _query.text.trim().toLowerCase();
    final items = _items ?? const <Customization>[];
    if (query.isEmpty) return items;
    return [
      for (final item in items)
        if (item.name.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query))
          item,
    ];
  }

  /// The kinds' scopes, in the order their groups show.
  List<CustomizationScope> get _scopes => [
    if (_kind == CustomizationKind.plugins)
      CustomizationScope.plugin
    else ...[
      CustomizationScope.user,
      if (_kind == CustomizationKind.skills || _kind == CustomizationKind.mcps)
        CustomizationScope.synced,
      if (_project != null) ...[
        CustomizationScope.project,
        if (_kind == CustomizationKind.rules ||
            _kind == CustomizationKind.mcps ||
            _kind == CustomizationKind.hooks)
          CustomizationScope.local,
      ],
    ],
  ];

  /// As Codex's plugins page: the kind's title and what it is for, search,
  /// whose, refresh and Add on the right; then each scope's, two columns.
  Widget _buildList(AppLocalizations l10n) {
    if (!widget.store.supported) {
      return Center(
        child: Text(
          l10n.customizeUnsupported,
          style: TextStyle(color: AppColors.textFaint, fontSize: 13),
        ),
      );
    }
    final items = _shown;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 2 : 1;
            return ListView(
              padding: const EdgeInsets.fromLTRB(40, 12, 40, 40),
              children: [
                _buildHeader(l10n),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.customizeLoadFailed('$error'),
                    style: TextStyle(
                      color: themeColors['errorForeground'],
                      fontSize: 12,
                    ),
                  ),
                ],
                if (_items != null)
                  for (final scope in _scopes)
                    ..._buildGroup(l10n, scope, [
                      for (final item in items)
                        if (item.scope == scope) item,
                    ], columns),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    final creatable = _kind.creatable;
    final configScope = _kind.configuredIn(CustomizationScope.user)
        ? CustomizationScope.user
        : _project != null && _kind.configuredIn(CustomizationScope.project)
        ? CustomizationScope.project
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                _kind.label(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              flex: 2,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(width: 220, child: _SearchBox(controller: _query)),
                  _buildScopePicker(l10n),
                  SidebarIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: l10n.customizeRefresh,
                    size: 30,
                    onTap: () => unawaited(_load()),
                  ),
                  if (creatable)
                    _PrimaryButton(
                      icon: Icons.add_rounded,
                      label: l10n.customizeNew,
                      onTap: () => unawaited(_create(CustomizationScope.user)),
                    )
                  else if (configScope != null)
                    _PrimaryButton(
                      icon: Codicons.edit,
                      label: l10n.customizeEditFile(_configName(configScope)),
                      onTap: () => unawaited(_openConfig(configScope)),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _kindDescription(l10n),
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 4,
            runSpacing: 6,
            children: [
              for (final kind in CustomizationKind.values)
                _Chip(
                  selected: kind == _kind,
                  onTap: () => show(kind),
                  child: Text(kind.label(l10n)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _kindDescription(AppLocalizations l10n) => switch (_kind) {
    CustomizationKind.plugins => l10n.customizeAboutPlugins,
    CustomizationKind.mcps => l10n.customizeAboutMcps,
    CustomizationKind.skills => l10n.customizeAboutSkills,
    CustomizationKind.subagents => l10n.customizeAboutSubagents,
    CustomizationKind.rules => l10n.customizeAboutRules,
    CustomizationKind.commands => l10n.customizeAboutCommands,
    CustomizationKind.hooks => l10n.customizeAboutHooks,
  };

  /// Whose are shown: the user's alone, or a project's too.
  Widget _buildScopePicker(AppLocalizations l10n) {
    final project = _project;
    return SidebarMenu(
      width: 220,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      items: () => [
        SidebarMenuItem(
          l10n.customizeUserOnly,
          icon: Icons.person_outline_rounded,
          checked: project == null,
          onSelected: () => _setProject(null),
        ),
        if (widget.projects.isNotEmpty)
          SidebarMenuItem.heading(l10n.sidebarProjects),
        for (final other in widget.projects)
          SidebarMenuItem(
            other.name,
            icon: Icons.folder_outlined,
            checked: other.path == project?.path,
            onSelected: () => _setProject(other),
          ),
      ],
      builder: (context, menu) => _Chip(
        selected: menu.isOpen,
        onTap: menu.open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              project == null
                  ? Icons.laptop_mac_rounded
                  : Icons.folder_outlined,
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                project == null ? l10n.customizeUserOnly : project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroup(
    AppLocalizations l10n,
    CustomizationScope scope,
    List<Customization> items,
    int columns,
  ) {
    final creatable =
        _kind.creatable &&
        (scope == CustomizationScope.user ||
            scope == CustomizationScope.project);
    final configurable = _kind.configuredIn(scope);
    // Where none are, what is said of adding some is shown: all but those
    // synced from claude.ai.
    final shownEmpty =
        creatable ||
        configurable ||
        _kind == CustomizationKind.plugins ||
        (_kind == CustomizationKind.mcps && scope != CustomizationScope.synced);
    final searching = _query.text.trim().isNotEmpty;
    if (items.isEmpty && (searching || !shownEmpty)) return const [];
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += columns) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const SizedBox(width: 24),
              Expanded(
                child: i + j < items.length
                    ? _ItemRow(
                        item: items[i + j],
                        status: _statusOf(items[i + j]),
                        onOpen: () => setState(() => _open = items[i + j]),
                        menu: () => _menu(items[i + j]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return [
      const SizedBox(height: 28),
      // As tall as its button, with one or not: the groups line up from
      // kind to kind.
      SizedBox(
        height: _Chip.height,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    scope.label(l10n),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${items.length}',
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12.5,
                    ),
                  ),
                  if (scope == CustomizationScope.project &&
                      _project != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _project!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (creatable)
              _TextAction(
                icon: Icons.add_rounded,
                label: l10n.customizeNew,
                onTap: () => unawaited(_create(scope)),
              ),
            if (items.where(_probeable).toList() case final probeable
                when probeable.isNotEmpty) ...[
              _Chip(
                outlined: true,
                onTap: () => _probeAll(probeable),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Codicons.refresh, size: 13, color: AppColors.text),
                    const SizedBox(width: 5),
                    Text(l10n.mcpTestAll),
                  ],
                ),
              ),
              if (configurable) const SizedBox(width: 6),
            ],
            if (configurable)
              _TextAction(
                icon: Codicons.edit,
                label: l10n.customizeEditFile(_configName(scope)),
                onTap: () => unawaited(_openConfig(scope)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      if (items.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.partBorder),
          ),
          child: SelectableText(
            _emptyText(l10n, scope),
            style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
          ),
        )
      else
        ...rows,
    ];
  }

  /// The name of the file [_kind] is kept in for [scope] (see
  /// [CustomizationKind.configuredIn]).
  String _configName(CustomizationScope scope) => switch ((_kind, scope)) {
    (CustomizationKind.mcps, _) => '.mcp.json',
    (_, CustomizationScope.local) => 'settings.local.json',
    _ => 'settings.json',
  };

  /// What a group with none says: where some come from.
  String _emptyText(AppLocalizations l10n, CustomizationScope scope) =>
      switch ((_kind, scope)) {
        (CustomizationKind.plugins, _) => l10n.customizeEmptyPlugins,
        (CustomizationKind.mcps, CustomizationScope.user) =>
          l10n.customizeEmptyMcpsUser,
        (CustomizationKind.mcps, CustomizationScope.local) =>
          l10n.customizeEmptyMcpsLocal,
        (CustomizationKind.mcps, _) => l10n.customizeEmptyMcpsProject,
        (CustomizationKind.hooks, _) => l10n.customizeEmptyHooks(
          _configName(scope),
        ),
        _ => l10n.customizeEmpty,
      };

  /// Opens the file [_kind] is kept in for [scope], as it is or, not there
  /// yet, as it would start.
  Future<void> _openConfig(CustomizationScope scope) async {
    final project = _projectPath;
    final path = await widget.store.configFile(_kind, scope, project: project);
    if (path == null || !mounted) return;
    setState(
      () => _open = Customization(
        kind: _kind,
        scope: scope,
        name: project == null || scope == CustomizationScope.user
            ? _paths.basename(path)
            : _paths.relative(path, from: project),
        path: path,
        detail: _kind.configTemplate,
      ),
    );
  }

  List<SidebarMenuItem> _menu(Customization item) {
    final l10n = context.l10n;
    // A remote host's files are neither opened nor shown here.
    final local = widget.store.isLocal;
    return [
      SidebarMenuItem(
        l10n.customizeEdit,
        icon: Icons.edit_outlined,
        onSelected: () => setState(() => _open = item),
      ),
      if (_probeable(item)) ...[
        SidebarMenuItem(
          l10n.mcpTest,
          icon: Icons.refresh_rounded,
          onSelected: () => unawaited(_probe(item)),
        ),
        SidebarMenuItem(
          l10n.mcpViewLog,
          icon: Icons.article_outlined,
          onSelected: () => setState(() => _open = item),
        ),
      ],
      if (widget.onOpenFile case final open? when item.editable && local)
        SidebarMenuItem(
          l10n.workspaceOpenIn(Editor.fastIde.localizedPlatformLabel(l10n)),
          icon: Editor.fastIde.icon,
          onSelected: () => open(item.path),
        ),
      if (local)
        SidebarMenuItem(
          l10n.revealInFileManager,
          icon: Editor.folder.icon,
          onSelected: () => unawaited(
            CustomizeView.launch(Editor.folder, p.dirname(item.path)),
          ),
        ),
      SidebarMenuItem(
        l10n.workspaceCopyPath,
        icon: Icons.content_copy_rounded,
        onSelected: () =>
            unawaited(Clipboard.setData(ClipboardData(text: item.path))),
      ),
      if (item.removePath != null)
        SidebarMenuItem(
          l10n.commonDelete,
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () => unawaited(_delete(item)),
        ),
    ];
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return SizedBox(
      height: 30,
      child: TextField(
        controller: controller,
        style: TextStyle(color: colors['input.foreground'], fontSize: 13),
        cursorColor: AppColors.text,
        cursorHeight: 15,
        decoration: InputDecoration(
          isDense: true,
          hintText: context.l10n.customizeSearchPlaceholder,
          hintStyle: TextStyle(
            color: colors['input.placeholderForeground'],
            fontSize: 13,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: AppColors.textFaint,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          filled: true,
          fillColor: colors['input.background'],
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.borderStrong),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: colors['focusBorder']),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.child,
    required this.onTap,
    this.selected = false,
    this.outlined = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool selected;

  /// Bordered, as a button among the tabs (Test all).
  final bool outlined;

  static const height = 26.0;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected
              ? themeColors['toolbar.activeBackground']
              : hovered
              ? AppColors.hover
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: outlined ? AppColors.borderStrong : Colors.transparent,
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.text,
            fontSize: 12.5,
          ),
          // As wide as what it says, in a Wrap or a ListView alike.
          child: Row(mainAxisSize: MainAxisSize.min, children: [child]),
        ),
      ),
    ),
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onOpen,
    required this.menu,
    this.status,
  });

  final Customization item;
  final VoidCallback onOpen;
  final List<SidebarMenuItem> Function() menu;

  /// An MCP server's: whether it answers.
  final McpProbeResult? status;

  /// A colour of its own from its name, as Codex's apps have a logo each.
  static const _tints = [
    Color(0xFF5B8DEF),
    Color(0xFF8E6CEF),
    Color(0xFFE0738A),
    Color(0xFFE8954A),
    Color(0xFF3FB28C),
    Color(0xFF3AA6C9),
    Color(0xFFC9A23A),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tint =
        _tints[item.name.codeUnits.fold(0, (a, b) => a + b) % _tints.length];
    return SidebarMenu(
      items: menu,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      builder: (context, menuState) => HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) {
          final active = hovered || menuState.isOpen;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            onSecondaryTapUp: (details) =>
                menuState.open(details.globalPosition),
            child: Container(
              // Taller for an MCP server's failure, its reason under it.
              constraints: const BoxConstraints(minHeight: 64),
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: active ? AppColors.hover : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: tint.withValues(alpha: 0.28)),
                    ),
                    child: Icon(item.kind.icon, size: 17, color: tint),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (status case final status?) ...[
                              const SizedBox(width: 8),
                              _McpStatusBadge(status),
                            ] else if (item.enabled case final enabled?) ...[
                              const SizedBox(width: 8),
                              _Badge(
                                label: enabled
                                    ? l10n.customizeEnabled
                                    : l10n.customizeDisabled,
                                color: enabled
                                    ? AppColors.added
                                    : AppColors.textFaint,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.description.isEmpty
                              ? p.basename(item.path)
                              : item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                        // Why it failed, at a glance: the whole in its log.
                        if (status?.reason(l10n) case final reason?) ...[
                          const SizedBox(height: 2),
                          Text(
                            reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: themeColors['errorForeground'],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: const Duration(milliseconds: 100),
                    child: SidebarIconButton(
                      icon: Icons.more_horiz_rounded,
                      tooltip: l10n.sidebarMoreActions,
                      size: 26,
                      onTap: menuState.open,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11)),
  );
}

/// The header's main action: filled, as Codex's Add.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color:
                colors[hovered
                    ? 'button.hoverBackground'
                    : 'button.background'],
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: colors['button.foreground']),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: colors['button.foreground'],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group's own action, as quiet text beside its heading.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: _Chip.height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hovered ? AppColors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One customization's file, edited as text (⌘S saves); or, where it is
/// not to be edited here, what it is.
class _CustomizationEditor extends StatefulWidget {
  const _CustomizationEditor({
    super.key,
    required this.item,
    required this.store,
    required this.onBack,
    this.onOpenFile,
    this.status,
  });

  final Customization item;
  final CustomizationStore store;
  final VoidCallback onBack;
  final ValueChanged<String>? onOpenFile;

  /// Above its text: an MCP server's status and log.
  final Widget? status;

  @override
  State<_CustomizationEditor> createState() => _CustomizationEditorState();
}

class _CustomizationEditorState extends State<_CustomizationEditor> {
  final EditorSurfaceController _text = EditorSurfaceController();
  final FocusNode _focus = FocusNode(debugLabel: 'customization editor');

  /// As last read or saved: the text differs from it while unsaved.
  String? _saved;
  Object? _error;
  bool _justSaved = false;

  /// Its file is not there yet: shown as it would start
  /// ([Customization.detail]), made when saved.
  bool _missing = false;

  Customization get _item => widget.item;
  bool get _dirty => _saved != null && _text.document.text != _saved;
  bool get _savable => _item.editable && (_dirty || _missing);

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      if (_justSaved && _dirty) _justSaved = false;
      setState(() {});
    });
    if (_item.detail case final detail? when !_item.editable) {
      _load(detail);
    } else {
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// [text] in the editor in place of what it had, not to be undone.
  void _load(String text) {
    _text.document.replaceText(text);
    _text.syncFromDocument();
    _text.detectIndentation();
  }

  Future<void> _read() async {
    try {
      if (_item.detail case final start?
          when !await widget.store.exists(_item.path)) {
        if (!mounted) return;
        setState(() {
          _missing = true;
          _saved = start;
          _load(start);
        });
        return;
      }
      final text = await widget.store.read(_item.path);
      if (!mounted) return;
      setState(() {
        _saved = text;
        _load(text);
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    if (!_savable) return;
    final text = _text.document.text;
    try {
      await widget.store.write(_item.path, text);
      if (!mounted) return;
      setState(() {
        _saved = text;
        _missing = false;
        _error = null;
        _justSaved = true;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _revert() {
    if (_saved case final saved?) _load(saved);
  }

  Future<void> _back() async {
    if (_dirty) {
      final l10n = context.l10n;
      final choice = await showIdeDialog(
        context,
        message: l10n.wbConfirmSave(p.basename(_item.path)),
        detail: l10n.explorerChangesLost,
        buttons: [l10n.commonSave, l10n.commonDontSave],
      );
      if (choice == null || choice > 1 || !mounted) return;
      if (choice == 0) {
        await _save();
        if (_dirty) return;
      }
    }
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final command = AppPlatform.isMacOS
        ? const SingleActivator(LogicalKeyboardKey.keyS, meta: true)
        : const SingleActivator(LogicalKeyboardKey.keyS, control: true);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SidebarIconButton(
                    icon: Codicons.arrowLeft,
                    tooltip: l10n.customizeBack,
                    onTap: () => unawaited(_back()),
                  ),
                  const SizedBox(width: 8),
                  Icon(_item.kind.icon, size: 15, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_item.editable)
                    Text(
                      _dirty
                          ? l10n.customizeUnsaved
                          : _justSaved
                          ? l10n.customizeSaved
                          : '',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  const Spacer(),
                  if (widget.onOpenFile case final open? when _item.editable)
                    SidebarIconButton(
                      icon: Codicons.goToFile,
                      tooltip: l10n.workspaceOpenIn(
                        Editor.fastIde.localizedPlatformLabel(l10n),
                      ),
                      onTap: () => open(_item.path),
                    ),
                  if (_item.editable) ...[
                    const SizedBox(width: 8),
                    _Button(
                      label: l10n.customizeRevert,
                      onTap: _dirty ? _revert : null,
                    ),
                    const SizedBox(width: 6),
                    _Button(
                      label: l10n.customizeSave,
                      primary: true,
                      onTap: _savable ? () => unawaited(_save()) : null,
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 2, bottom: 10),
                child: SelectableText(
                  _item.editable
                      ? _item.path
                      : _item.scope != CustomizationScope.synced
                      ? l10n.customizeReadOnly
                      : _item.kind == CustomizationKind.mcps
                      ? l10n.customizeConnectorReadOnly
                      : l10n.customizeSyncedReadOnly,
                  maxLines: 1,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
                ),
              ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 8),
                  child: Text(
                    _saved == null
                        ? l10n.customizeLoadFailed('$error')
                        : l10n.customizeSaveFailed('$error'),
                    style: TextStyle(
                      color: colors['errorForeground'],
                      fontSize: 12,
                    ),
                  ),
                ),
              if (widget.status case final status?)
                Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 10),
                  child: status,
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(left: 32),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.partBorder),
                  ),
                  child: CallbackShortcuts(
                    bindings: {command: () => unawaited(_save())},
                    child: IdeCodeEditor(
                      controller: _text,
                      path: _item.path,
                      focusNode: _focus,
                      readOnly: !_item.editable,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on McpProbeResult {
  String label(AppLocalizations l10n) => switch (status) {
    McpProbeStatus.checking => l10n.mcpConnecting,
    McpProbeStatus.connected => l10n.mcpConnected,
    McpProbeStatus.needsAuth => l10n.mcpNeedsSignIn,
    McpProbeStatus.failed => l10n.mcpFailed,
    McpProbeStatus.disabled => l10n.mcpDisabled,
  };

  /// As the chat's MCP servers panel colors them.
  Color get color => switch (status) {
    McpProbeStatus.connected => AppColors.added,
    McpProbeStatus.needsAuth => themeColors['list.warningForeground'],
    McpProbeStatus.failed => themeColors['errorForeground'],
    McpProbeStatus.checking || McpProbeStatus.disabled => AppColors.textFaint,
  };

  /// One line of why it failed (or what it wants); null otherwise.
  String? reason(AppLocalizations l10n) {
    if (status == McpProbeStatus.needsAuth) return null;
    if (status != McpProbeStatus.failed) return null;
    final last = log
        .split('\n')
        .map((line) => line.trim())
        .lastWhere((line) => line.isNotEmpty, orElse: () => '');
    final parts = [
      ?message,
      if (timedOut) l10n.mcpTimedOut(mcpProbeTimeout.inSeconds),
      if (exitCode case final code?) l10n.mcpExitCode(code),
      if (message == null && last.isNotEmpty) last,
    ];
    return parts.isEmpty ? l10n.mcpFailed : parts.join(' · ');
  }
}

/// A dot in its color and what it says, in a server's row.
class _McpStatusBadge extends StatelessWidget {
  const _McpStatusBadge(this.status);

  final McpProbeResult status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = status.color;
    final badge = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          status.label(l10n),
          style: TextStyle(color: color, fontSize: 11.5),
        ),
      ],
    );
    return switch (status.server) {
      final server? when server.isNotEmpty => IdeHover(
        message: server,
        child: badge,
      ),
      _ => badge,
    };
  }
}

/// An MCP server's status over its entry: why it failed and what it
/// wrote, and the way to ask again.
class _McpStatusPanel extends StatelessWidget {
  const _McpStatusPanel({required this.status, this.onTest});

  final McpProbeResult status;
  final VoidCallback? onTest;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final failed = status.status == McpProbeStatus.failed;
    final reason = status.reason(l10n);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: themeColors['editorWidget.background'],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.partBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _McpStatusBadge(status),
              if (status.server case final server? when server.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    server,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                ),
              ],
              const Spacer(),
              if (onTest case final onTest?)
                _Button(
                  label: l10n.mcpTest,
                  onTap: status.status == McpProbeStatus.checking
                      ? null
                      : onTest,
                ),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              reason,
              style: TextStyle(
                color: themeColors['errorForeground'],
                fontSize: 12,
              ),
            ),
          ],
          if (status.status == McpProbeStatus.needsAuth) ...[
            const SizedBox(height: 6),
            Text(
              l10n.mcpSignInHint,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
          if (failed || status.log.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.mcpLog,
              style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
            ),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: AppColors.code,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.partBorder),
              ),
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: SelectableText(
                  status.log.isEmpty ? l10n.mcpNoLog : status.log,
                  style: AppFonts.uiCodeStyle(11.5).copyWith(
                    color: status.log.isEmpty
                        ? AppColors.textFaint
                        : AppColors.text,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ],
          if (status.status != McpProbeStatus.disabled) ...[
            const SizedBox(height: 6),
            Text(
              l10n.mcpProbeNote,
              style: TextStyle(color: AppColors.textFaint, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final enabled = onTap != null;
    return HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  colors[switch ((primary, hovered && enabled)) {
                    (true, true) => 'button.hoverBackground',
                    (true, false) => 'button.background',
                    (false, true) => 'button.secondaryHoverBackground',
                    (false, false) => 'button.secondaryBackground',
                  }],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                color:
                    colors[primary
                        ? 'button.foreground'
                        : 'button.secondaryForeground'],
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks the name of a new skill, subagent, command or rule.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.kind,
    required this.title,
    required this.taken,
  });

  final CustomizationKind kind;
  final String title;

  /// Names already taken where it is to go.
  final Set<String> taken;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _problem(AppLocalizations l10n) {
    final name = _name.text.trim();
    if (name.isEmpty) return null;
    if (!isCustomizationName(name)) return l10n.customizeNameInvalid;
    if (widget.taken.contains(name)) return l10n.customizeNameTaken;
    return null;
  }

  /// A note, not a [_problem]: the name works, but not everywhere.
  String? _note(AppLocalizations l10n) {
    final name = _name.text.trim();
    if (name.isEmpty || followsOfficialNaming(widget.kind, name)) return null;
    return l10n.customizeNameUnofficial;
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _problem(context.l10n) != null) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final problem = _problem(l10n);
    final note = problem == null ? _note(l10n) : null;
    return Dialog(
      backgroundColor: AppColors.surface,
      shadowColor: colors['widget.shadow'],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                autofocus: true,
                autocorrect: false,
                onSubmitted: (_) => _submit(),
                style: TextStyle(
                  color: colors['input.foreground'],
                  fontSize: 13,
                ),
                cursorColor: AppColors.text,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.customizeNameHint,
                  hintStyle: TextStyle(
                    color: colors['input.placeholderForeground'],
                    fontSize: 13,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  filled: true,
                  fillColor: colors['input.background'],
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: problem == null
                          ? AppColors.borderStrong
                          : colors['inputValidation.errorBorder'],
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: problem == null
                          ? colors['focusBorder']
                          : colors['inputValidation.errorBorder'],
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 22),
                child: problem == null && note == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          problem ?? note!,
                          style: TextStyle(
                            color: problem != null
                                ? colors['errorForeground']
                                : AppColors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _Button(
                    label: l10n.commonCancel,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  _Button(
                    label: l10n.customizeCreate,
                    primary: true,
                    onTap: _name.text.trim().isEmpty || problem != null
                        ? null
                        : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
