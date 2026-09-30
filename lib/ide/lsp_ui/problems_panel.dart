import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../theme/codicons.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/material_file_icons.dart';
import '../editor/monaco/flutter/document_snapshot.dart';
import '../ide_hover.dart';
import '../lsp/language_features.dart';
import '../lsp/lsp_protocol.dart';
import 'diagnostics.dart';
import 'lsp_convert.dart';

enum IdePanelTab { problems, references, terminal }

/// Locations Find References (or several definitions) produced.
class IdeReferences {
  const IdeReferences(this.title, this.locations);

  final String title;
  final List<IdeLocation> locations;
}

/// The bottom panel: Problems (every document's diagnostics, grouped by
/// file), References (the last Find References) and the Terminal, like VS
/// Code's panel. Its card and height are the workbench's.
class IdeBottomPanel extends StatelessWidget {
  const IdeBottomPanel({
    super.key,
    required this.tab,
    required this.root,
    required this.languages,
    required this.references,
    required this.onTab,
    required this.onClose,
    required this.onOpen,
    required this.textOf,
    this.terminal,
    this.terminalActions,
  });

  final IdePanelTab tab;
  final String root;
  final LanguageFeatures? languages;
  final IdeReferences? references;
  final ValueChanged<IdePanelTab> onTab;
  final VoidCallback onClose;

  /// Opens a location; [select] selects its range instead of placing the
  /// caret at its start.
  final void Function(IdeLocation location, {bool select}) onOpen;

  /// A file's text for previews (open documents first, then disk).
  final Future<String?> Function(String path) textOf;

  /// The integrated terminal; none where there are no terminals (the web).
  final Widget? terminal;

  /// The terminal's title actions, before Close Panel while TERMINAL shows.
  final Widget? terminalActions;

  @override
  Widget build(BuildContext context) {
    final languages = this.languages;
    return ListenableBuilder(
      listenable: languages ?? _never,
      builder: (context, _) {
        final all = languages?.allDiagnostics ?? const {};
        final counts = ideDiagnosticCounts(all);
        final total = counts.errors + counts.warnings + counts.infos;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 30,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  _Tab(
                    label: 'PROBLEMS',
                    badge: total == 0 ? null : '$total',
                    selected: tab == IdePanelTab.problems,
                    onTap: () => onTab(IdePanelTab.problems),
                  ),
                  _Tab(
                    label: 'REFERENCES',
                    badge: references == null
                        ? null
                        : '${references!.locations.length}',
                    selected: tab == IdePanelTab.references,
                    onTap: () => onTab(IdePanelTab.references),
                  ),
                  if (terminal != null)
                    _Tab(
                      label: 'TERMINAL',
                      selected: tab == IdePanelTab.terminal,
                      onTap: () => onTab(IdePanelTab.terminal),
                    ),
                  const Spacer(),
                  if (tab == IdePanelTab.terminal) ?terminalActions,
                  IdeActionButton(
                    icon: Codicons.close,
                    tooltip: 'Close Panel',
                    onPressed: onClose,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: switch (tab) {
                IdePanelTab.problems => _problems(all),
                IdePanelTab.references => _references(),
                IdePanelTab.terminal =>
                  terminal ?? _message('The terminal is not available.'),
              },
            ),
          ],
        );
      },
    );
  }

  static final _never = ChangeNotifier();

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: CursorColors.textMuted),
    ),
  );

  Widget _problems(Map<String, List<LspDiagnostic>> all) {
    final paths = [
      for (final MapEntry(key: path, value: list) in all.entries)
        if (list.any((d) => d.severity != LspDiagnosticSeverity.hint)) path,
    ]..sort();
    if (paths.isEmpty) {
      return _message('No problems have been detected in the workspace.');
    }
    final rows = <Widget>[];
    for (final path in paths) {
      final list =
          [
            for (final d in all[path]!)
              if (d.severity != LspDiagnosticSeverity.hint) d,
          ]..sort((a, b) {
            final bySeverity = a.severity.index.compareTo(b.severity.index);
            return bySeverity != 0
                ? bySeverity
                : a.range.start.compareTo(b.range.start);
          });
      rows.add(_FileHeader(path: path, root: root, count: list.length));
      for (final d in list) {
        rows.add(
          _Row(
            key: ValueKey(('problem', path, d)),
            leading: Icon(
              ideDiagnosticIcon(d.severity),
              size: 14,
              color: ideDiagnosticColor(d.severity),
            ),
            text: TextSpan(
              text: d.message.split('\n').first,
              children: [
                if (d.source != null || d.code != null)
                  TextSpan(
                    text:
                        '  ${d.source ?? ''}'
                        '${d.code == null ? '' : '(${d.code})'}',
                    style: const TextStyle(color: CursorColors.textFaint),
                  ),
                TextSpan(
                  text:
                      '  [Ln ${d.range.start.line + 1}, '
                      'Col ${d.range.start.character + 1}]',
                  style: const TextStyle(color: CursorColors.textFaint),
                ),
              ],
            ),
            onTap: () => onOpen(IdeLocation(path, d.range), select: true),
          ),
        );
      }
    }
    return ListView(children: rows);
  }

  Widget _references() {
    final references = this.references;
    if (references == null) {
      return _message('No references yet: use Go to References (⇧F12).');
    }
    final byPath = <String, List<IdeLocation>>{};
    for (final location in references.locations) {
      byPath.putIfAbsent(location.path, () => []).add(location);
    }
    final files = byPath.length;
    final count = references.locations.length;
    final rows = <Widget>[
      _message(
        '${references.title} — $count result${count == 1 ? '' : 's'} '
        'in $files file${files == 1 ? '' : 's'}',
      ),
    ];
    for (final MapEntry(key: path, value: locations) in byPath.entries) {
      locations.sort((a, b) => a.range.start.compareTo(b.range.start));
      rows.add(_FileHeader(path: path, root: root, count: locations.length));
      for (final location in locations) {
        rows.add(
          _ReferenceRow(
            key: ValueKey(('reference', location)),
            location: location,
            textOf: textOf,
            onTap: () => onOpen(location, select: true),
          ),
        );
      }
    }
    return ListView(children: rows);
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? CursorColors.accent : Colors.transparent,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.3,
                color: selected
                    ? CursorColors.textPrimary
                    : CursorColors.textMuted,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: CursorColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: CursorColors.text,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({
    required this.path,
    required this.root,
    required this.count,
  });

  final String path;
  final String root;
  final int count;

  @override
  Widget build(BuildContext context) {
    final name = p.basename(path);
    final folder = p.isWithin(root, path)
        ? p.dirname(p.relative(path, from: root))
        : p.dirname(path);
    return Container(
      height: 22,
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: Row(
        children: [
          FileIcon(name, size: 14),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(fontSize: 12.5, color: CursorColors.text),
          ),
          if (folder != '.') ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                folder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: CursorColors.textFaint,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: CursorColors.surfaceRaised,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 10.5, color: CursorColors.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    super.key,
    required this.leading,
    required this.text,
    required this.onTap,
  });

  final Widget leading;
  final InlineSpan text;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        height: 22,
        color: _hover ? CursorColors.hover : null,
        padding: const EdgeInsets.only(left: 32, right: 12),
        child: Row(
          children: [
            widget.leading,
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                widget.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
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

class _ReferenceRow extends StatefulWidget {
  const _ReferenceRow({
    super.key,
    required this.location,
    required this.textOf,
    required this.onTap,
  });

  final IdeLocation location;
  final Future<String?> Function(String path) textOf;
  final VoidCallback onTap;

  @override
  State<_ReferenceRow> createState() => _ReferenceRowState();
}

class _ReferenceRowState extends State<_ReferenceRow> {
  String? _line;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    String? text;
    try {
      text = await widget.textOf(widget.location.path);
    } catch (_) {
      return;
    }
    if (text == null || !mounted) return;
    final snapshot = DocumentSnapshot(text);
    final line = widget.location.range.start.line;
    if (line >= snapshot.lineCount) return;
    setState(() {
      _line = text!.substring(
        snapshot.lineStarts[line],
        snapshot.contentEnds[line],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final range = widget.location.range;
    final line = _line;
    final spans = <InlineSpan>[];
    if (line != null) {
      final start = range.start.character.clamp(0, line.length);
      final end = range.start.line == range.end.line
          ? range.end.character.clamp(start, line.length)
          : line.length;
      final lead = line.substring(0, start);
      final trimmed = lead.trimLeft();
      spans
        ..add(TextSpan(text: trimmed))
        ..add(
          TextSpan(
            text: line.substring(start, end),
            style: const TextStyle(
              backgroundColor: Color(0x55EA5C00),
              color: CursorColors.textPrimary,
            ),
          ),
        )
        ..add(TextSpan(text: line.substring(end)));
    }
    spans.add(
      TextSpan(
        text: '  Ln ${range.start.line + 1}, Col ${range.start.character + 1}',
        style: const TextStyle(color: CursorColors.textFaint),
      ),
    );
    return _Row(
      leading: const SizedBox(width: 0),
      text: TextSpan(
        children: spans,
        style: const TextStyle(fontFamily: CursorFonts.mono, fontSize: 12),
      ),
      onTap: widget.onTap,
    );
  }
}
