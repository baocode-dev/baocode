// Create Project, as Codex's: a name, and its source folder on this
// computer or on a remote host, picked from a menu over the folder box.

import 'dart:async';

import 'package:bao_remote/client.dart' show sshConfigHosts;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/floating/floating_placement.dart';
import '../ide/ide_button.dart';
import '../ide/ide_input.dart';
import '../l10n/l10n.dart';
import '../remote/remote_location.dart';
import '../sidebar/sidebar_menu.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'window_controls.dart';
import 'workspace.dart';

/// What the dialog asks the window to do for the folder: pick one on this
/// computer, or browse [host] for one (null to add a host first); each
/// completes with the folder's location, or null when dismissed.
typedef PickLocalFolder = Future<String?> Function();
typedef PickRemoteFolder = Future<String?> Function(String? host);

/// Asks for a project's name and folder; completes with the project made
/// (listed in the sidebar, a new agent there), or null when dismissed.
Future<Project?> showCreateProjectDialog(
  BuildContext context, {
  required Workspace workspace,
  required PickRemoteFolder pickRemote,
  PickLocalFolder? pickLocal,
}) => showGeneralDialog<Project>(
  context: context,
  barrierDismissible: true,
  barrierLabel: context.l10n.commonDismiss,
  barrierColor: const Color(0x80000000),
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => CreateProjectDialog(
    workspace: workspace,
    pickLocal: pickLocal ?? WindowControls.pickDirectory,
    pickRemote: pickRemote,
  ),
);

class CreateProjectDialog extends StatefulWidget {
  const CreateProjectDialog({
    super.key,
    required this.workspace,
    required this.pickLocal,
    required this.pickRemote,
  });

  final Workspace workspace;
  final PickLocalFolder pickLocal;
  final PickRemoteFolder pickRemote;

  /// The SSH hosts to offer; `~/.ssh/config`'s, replaceable under test.
  @visibleForTesting
  static Future<List<String>> Function() hosts = sshConfigHosts;

  @override
  State<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<CreateProjectDialog> {
  final _name = TextEditingController();

  /// Where the folder is picked: null for this computer.
  String? _host;
  String? _folder;
  List<String> _hosts = const [];
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final hosts = await CreateProjectDialog.hosts();
        if (mounted) setState(() => _hosts = hosts);
      } on Object {
        // None to offer: this computer, or one added.
      }
    }());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final folder = _host == null
        ? await widget.pickLocal()
        : await widget.pickRemote(_host);
    if (folder == null || !mounted) return;
    setState(() => _folder = folder);
  }

  Future<void> _addHost() async {
    final folder = await widget.pickRemote(null);
    if (folder == null || !mounted) return;
    setState(() {
      _host = RemoteLocation.hostOf(folder);
      _folder = folder;
    });
  }

  void _create() {
    final folder = _folder;
    if (folder == null) {
      setState(() => _tried = true);
      return;
    }
    final workspace = widget.workspace;
    unawaited(workspace.openFolder(folder));
    final project = workspace.projectAt(folder);
    if (_name.text.trim().isNotEmpty) {
      workspace.renameProject(project, _name.text);
    }
    Navigator.pop(context, workspace.projectAt(folder));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = themeColors;
    final foreground = colors['editorWidget.foreground'];
    final muted = colors['descriptionForeground'];
    final where = _host ?? l10n.projectThisComputer;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: FocusScope(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.4),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: 500,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: switch (colors.get('widget.border')) {
                  final border? => Border.all(color: border),
                  null => null,
                },
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 32),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.projectCreateTitle,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.dialogCloseDialog,
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        color: muted,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  IdeInputBox(
                    controller: _name,
                    autofocus: true,
                    placeholder: l10n.projectNameHint,
                    semanticsLabel: l10n.projectNameHint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.projectSourceFolder,
                    style: TextStyle(fontSize: 13, color: foreground),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(minHeight: 96),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _tried && _folder == null
                            ? colors['inputValidation.errorBorder']
                            : colors['input.border'],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _folder == null
                        ? _buildAddFolder(where)
                        : _buildFolder(_folder!),
                  ),
                  if (_tried && _folder == null) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.projectNoFolder,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors['errorForeground'],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IdeButton(
                        label: l10n.commonCancel,
                        secondary: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      IdeButton(
                        label: l10n.projectCreate,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        onPressed: _create,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Add a folder on `This computer` ˅": the place a menu, the rest picks.
  Widget _buildAddFolder(String where) {
    final l10n = context.l10n;
    final muted = themeColors['descriptionForeground'];
    final style = TextStyle(fontSize: 13, color: muted);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Link(label: l10n.projectAddFolderOn, style: style, onTap: _pick),
        _buildPlaceMenu(where),
        _Link(label: l10n.projectAddFolderSuffix, style: style, onTap: _pick),
      ],
    );
  }

  Widget _buildPlaceMenu(String where) {
    final l10n = context.l10n;
    final foreground = themeColors['editorWidget.foreground'];
    return SidebarMenu(
      width: 220,
      placement: (side: FloatingSide.bottom, align: FloatingAlign.center),
      items: () => [
        SidebarMenuItem(
          l10n.projectThisComputer,
          icon: Icons.laptop_mac_rounded,
          checked: _host == null,
          onSelected: () => setState(() {
            _host = null;
            _folder = null;
          }),
        ),
        SidebarMenuItem(
          l10n.projectAddRemoteHost,
          icon: Icons.add_rounded,
          onSelected: () => unawaited(_addHost()),
        ),
        if (_hosts.isNotEmpty) ...[
          SidebarMenuItem.heading(l10n.projectRemoteDevices),
          for (final host in _hosts)
            SidebarMenuItem(
              host,
              icon: Icons.dns_outlined,
              checked: _host == host,
              onSelected: () => setState(() {
                _host = host;
                _folder = null;
              }),
            ),
        ],
      ],
      builder: (context, menu) => _Link(
        label: where,
        style: TextStyle(
          fontSize: 13,
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
        trailing: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 16,
          color: foreground,
        ),
        onTap: menu.open,
      ),
    );
  }

  /// The folder picked: where it is, and a way to pick another.
  Widget _buildFolder(String folder) {
    final colors = themeColors;
    final host = RemoteLocation.hostOf(folder);
    return Row(
      children: [
        Icon(
          host == null ? Icons.folder_outlined : Icons.dns_outlined,
          size: 20,
          color: colors['descriptionForeground'],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                RemoteLocation.nameOf(folder),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: colors['editorWidget.foreground'],
                ),
              ),
              Text(
                host == null
                    ? folder
                    : '$host:${RemoteLocation.pathOf(folder)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colors['descriptionForeground'],
                ),
              ),
            ],
          ),
        ),
        IdeButton(
          label: context.l10n.projectChangeFolder,
          secondary: true,
          onPressed: _pick,
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: context.l10n.commonDismiss,
          iconSize: 15,
          visualDensity: VisualDensity.compact,
          color: AppColors.textMuted,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => setState(() => _folder = null),
        ),
      ],
    );
  }
}

class _Link extends StatefulWidget {
  const _Link({
    required this.label,
    required this.style,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (widget.label.isEmpty) return const SizedBox.shrink();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: widget.style.copyWith(
                decoration: _hover ? TextDecoration.underline : null,
              ),
            ),
            ?widget.trailing,
          ],
        ),
      ),
    );
  }
}
