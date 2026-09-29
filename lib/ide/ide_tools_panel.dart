import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../theme/cursor_theme.dart';
import 'project_tools.dart';

/// The compact, independent tools shown beside the IDE workbench.
enum IdeToolMode { search, sourceControl }

class IdeToolsPanel extends StatefulWidget {
  const IdeToolsPanel({
    super.key,
    required this.root,
    required this.mode,
    required this.onOpen,
  });

  final String root;
  final IdeToolMode mode;
  final void Function(String path, int? line) onOpen;

  @override
  State<IdeToolsPanel> createState() => _IdeToolsPanelState();
}

class _IdeToolsPanelState extends State<IdeToolsPanel> {
  late final IdeProjectTools _tools = IdeProjectTools(widget.root);
  late final TextEditingController _queryController = TextEditingController();
  Timer? _searchDebounce;
  IdeSearchCancellation? _searchCancellation;
  Future<IdeSearchResult>? _searchFuture;
  Future<IdeGitSnapshot>? _gitFuture;
  int _searchVersion = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCancellation?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _scheduleSearch(String query) {
    _searchDebounce?.cancel();
    _searchCancellation?.cancel();
    final cancellation = IdeSearchCancellation();
    _searchCancellation = cancellation;
    final version = ++_searchVersion;
    if (query.trim().isEmpty) {
      setState(() => _searchFuture = null);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      final future = _tools.search(query, cancellation: cancellation);
      if (!mounted || version != _searchVersion) return;
      setState(() => _searchFuture = future);
    });
  }

  void _refreshGit() {
    setState(() => _gitFuture = _tools.gitStatus());
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CursorColors.sidebarSurface,
      child: widget.mode == IdeToolMode.search
          ? _buildSearch(context)
          : _buildSourceControl(context),
    );
  }

  Widget _buildSearch(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: 'SEARCH',
          trailing: _searchFuture == null && _queryController.text.isNotEmpty
              ? null
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: TextField(
            controller: _queryController,
            autofocus: true,
            onChanged: _scheduleSearch,
            style: const TextStyle(
              color: CursorColors.textPrimary,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search files',
              hintStyle: const TextStyle(color: CursorColors.textFaint),
              prefixIcon: const Icon(Icons.search, size: 16),
              prefixIconConstraints: const BoxConstraints(minWidth: 30),
              filled: true,
              fillColor: CursorColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: CursorColors.accent),
              ),
            ),
          ),
        ),
        Expanded(child: _buildSearchResults()),
      ],
    );
  }

  Widget _buildSearchResults() {
    final future = _searchFuture;
    if (future == null) {
      return const _PanelMessage('Type to search this project.');
    }
    return FutureBuilder<IdeSearchResult>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PanelMessage('Searching…', busy: true);
        }
        if (snapshot.hasError) {
          return _PanelMessage('Search failed: ${snapshot.error}');
        }
        final result = snapshot.data;
        if (result == null) return const _PanelMessage('No results.');
        if (result.matches.isEmpty) {
          return _PanelMessage(
            result.cancelled
                ? 'Search cancelled.'
                : 'No matches${result.truncated ? ' in the search limit' : ''}.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: result.matches.length + 1,
          itemBuilder: (context, index) {
            if (index == result.matches.length) {
              return _SearchFooter(result: result);
            }
            final match = result.matches[index];
            return _SearchRow(
              match: match,
              onTap: () => widget.onOpen(match.path, match.line),
            );
          },
        );
      },
    );
  }

  Widget _buildSourceControl(BuildContext context) {
    final future = _gitFuture ??= _tools.gitStatus();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeader(
          title: 'SOURCE CONTROL',
          trailing: IconButton(
            onPressed: _refreshGit,
            icon: const Icon(Icons.refresh, size: 16),
            color: CursorColors.textMuted,
            tooltip: 'Refresh Git status',
            splashRadius: 16,
          ),
        ),
        Expanded(
          child: FutureBuilder<IdeGitSnapshot>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _PanelMessage('Reading Git status…', busy: true);
              }
              if (snapshot.hasError) {
                return _PanelMessage('Git unavailable: ${snapshot.error}');
              }
              final status = snapshot.data;
              if (status == null) return const _PanelMessage('No Git status.');
              return _GitChanges(
                snapshot: status,
                root: widget.root,
                onOpen: widget.onOpen,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: CursorColors.textMuted,
                  fontSize: 11,
                  letterSpacing: .4,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage(this.message, {this.busy = false});

  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (busy) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: CursorColors.textMuted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.match, required this.onTap});

  final IdeSearchMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: CursorColors.hover,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 10, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CursorColors.text,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${match.line}:${match.column}',
                  style: const TextStyle(
                    color: CursorColors.textFaint,
                    fontSize: 10,
                    fontFamily: CursorFonts.mono,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              match.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CursorColors.textMuted,
                fontSize: 11,
                fontFamily: CursorFonts.mono,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchFooter extends StatelessWidget {
  const _SearchFooter({required this.result});

  final IdeSearchResult result;

  @override
  Widget build(BuildContext context) {
    final suffix = result.truncated ? 'Search limit reached. ' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 5),
      child: Text(
        '$suffix${result.matches.length} result${result.matches.length == 1 ? '' : 's'}',
        style: const TextStyle(color: CursorColors.textFaint, fontSize: 10),
      ),
    );
  }
}

class _GitChanges extends StatelessWidget {
  const _GitChanges({
    required this.snapshot,
    required this.root,
    required this.onOpen,
  });

  final IdeGitSnapshot snapshot;
  final String root;
  final void Function(String path, int? line) onOpen;

  @override
  Widget build(BuildContext context) {
    if (snapshot.changes.isEmpty) {
      return _PanelMessage('No changes on ${snapshot.branch}.');
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: snapshot.changes.length + 1,
      itemBuilder: (context, index) {
        if (index == snapshot.changes.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              '${snapshot.branch}${snapshot.truncated ? ' · more changes not shown' : ''}',
              style: const TextStyle(
                color: CursorColors.textFaint,
                fontSize: 10,
              ),
            ),
          );
        }
        final change = snapshot.changes[index];
        final disabled = change.isDeleted;
        return InkWell(
          onTap: disabled
              ? null
              : () => onOpen(p.join(root, change.relativePath), null),
          hoverColor: CursorColors.hover,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    change.label,
                    style: TextStyle(
                      color: disabled
                          ? CursorColors.removed
                          : change.label == 'A'
                          ? CursorColors.added
                          : CursorColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    change.relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: disabled
                          ? CursorColors.textFaint
                          : CursorColors.text,
                      fontSize: 11,
                      decoration: disabled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
