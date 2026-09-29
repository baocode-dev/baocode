import 'package:flutter/material.dart';

import '../theme/cursor_theme.dart';
import 'file_service.dart';
import 'ide_workspace.dart';

class IdeExplorer extends StatelessWidget {
  const IdeExplorer({super.key, required this.workspace, required this.onOpen});

  final IdeWorkspace workspace;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CursorColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 12, 12),
            child: Text(
              'EXPLORER',
              style: TextStyle(fontSize: 11, color: CursorColors.textMuted),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: _Folder(
                path: workspace.root,
                name: workspace.root.split(RegExp(r'[/\\]')).last,
                workspace: workspace,
                onOpen: onOpen,
                depth: 0,
                initiallyExpanded: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Folder extends StatefulWidget {
  const _Folder({
    super.key,
    required this.path,
    required this.name,
    required this.workspace,
    required this.onOpen,
    required this.depth,
    this.initiallyExpanded = false,
  });

  final String path;
  final String name;
  final IdeWorkspace workspace;
  final ValueChanged<String> onOpen;
  final int depth;
  final bool initiallyExpanded;

  @override
  State<_Folder> createState() => _FolderState();
}

class _FolderState extends State<_Folder> {
  late bool _expanded = widget.initiallyExpanded;
  Future<List<IdeFile>>? _entries;

  @override
  void initState() {
    super.initState();
    if (_expanded) _entries = widget.workspace.files.list(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExplorerRow(
          depth: widget.depth,
          icon: _expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
          name: widget.name,
          onTap: () => setState(() {
            _expanded = !_expanded;
            if (_expanded) {
              _entries ??= widget.workspace.files.list(widget.path);
            }
          }),
        ),
        if (_expanded)
          FutureBuilder<List<IdeFile>>(
            future: _entries,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: EdgeInsets.only(left: 20.0 + widget.depth * 14),
                  child: Text(
                    'Cannot read folder: ${snapshot.error}',
                    style: const TextStyle(
                      color: CursorColors.removed,
                      fontSize: 11,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in snapshot.data!)
                    if (entry.isDirectory)
                      _Folder(
                        key: ValueKey(entry.path),
                        path: entry.path,
                        name: entry.name,
                        workspace: widget.workspace,
                        onOpen: widget.onOpen,
                        depth: widget.depth + 1,
                      )
                    else
                      _ExplorerRow(
                        depth: widget.depth + 1,
                        icon: Icons.insert_drive_file_outlined,
                        name: entry.name,
                        onTap: () => widget.onOpen(entry.path),
                      ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _ExplorerRow extends StatelessWidget {
  const _ExplorerRow({
    required this.depth,
    required this.icon,
    required this.name,
    required this.onTap,
  });

  final int depth;
  final IconData icon;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: CursorColors.hover,
      child: SizedBox(
        height: 25,
        child: Padding(
          padding: EdgeInsets.only(left: 8.0 + depth * 14, right: 8),
          child: Row(
            children: [
              Icon(icon, size: 15, color: CursorColors.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CursorColors.text,
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
