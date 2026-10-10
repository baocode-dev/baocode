/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/output/browser/outputView.ts (the view: the
// active channel's text, word wrapped, no line numbers, revealing the last
// line unless scroll lock; level filters of log channels) and
// src/vs/workbench/contrib/output/browser/output.contribution.ts (the view
// title's actions: Switch Output with extension channels first
// (`0_ext_outputchannels`) then the others, Set Log Level… with Set As
// Default, Clear Output, Toggle Auto Scrolling, Open Output in Editor).
//
// Deviations: a list of lines instead of a read-only editor (selectable
// with the mouse, copied with the platform's shortcut); no text filter, no
// category filter, no Save Output As; Open in Editor opens the channel's
// file (disabled for the in-memory "Extension Host" channel); Set As
// Default sets the default level of all loggers (upstream: the
// extension's default).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ide/ide_hover.dart';
import '../../../ide/ide_menu.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/code_font.dart';
import '../../../theme/codicons.dart';
import '../../../theme/workbench_theme.dart' show themeColors;
import 'extension_output_service.dart';
import 'output_text.dart';

/// The Output panel: the active channel's text under a toolbar. The
/// workbench puts it in its bottom panel and sets
/// [ExtensionOutputService.panelVisible] as that shows and hides it.
class ExtensionOutputPanel extends StatefulWidget {
  const ExtensionOutputPanel({
    super.key,
    required this.service,
    this.onOpenInEditor,
  });

  final ExtensionOutputService service;

  /// Opens a channel's file in an editor (Open Output in Editor); the
  /// action is hidden when null.
  final void Function(String filePath)? onOpenInEditor;

  static const _levels = [
    ExtHostLogLevel.trace,
    ExtHostLogLevel.debug,
    ExtHostLogLevel.info,
    ExtHostLogLevel.warning,
    ExtHostLogLevel.error,
  ];

  @override
  State<ExtensionOutputPanel> createState() => _ExtensionOutputPanelState();
}

class _ExtensionOutputPanelState extends State<ExtensionOutputPanel> {
  final _scroll = ScrollController();
  ExtensionOutputChannel? _channel;

  // The lines shown when a level filter hides some: by revision.
  List<int>? _filtered;
  Object? _filteredFor;

  ExtensionOutputService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onService);
    _service.followTail.addListener(_onFollow);
    _service.shownLevels.addListener(_onContent);
    _watch(_service.activeChannel);
  }

  @override
  void didUpdateWidget(ExtensionOutputPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service
        ..removeListener(_onService)
        ..followTail.removeListener(_onFollow)
        ..shownLevels.removeListener(_onContent);
      _service.addListener(_onService);
      _service.followTail.addListener(_onFollow);
      _service.shownLevels.addListener(_onContent);
      _watch(_service.activeChannel);
    }
  }

  @override
  void dispose() {
    _channel?.removeListener(_onContent);
    _service
      ..removeListener(_onService)
      ..followTail.removeListener(_onFollow)
      ..shownLevels.removeListener(_onContent);
    _scroll.dispose();
    super.dispose();
  }

  void _watch(ExtensionOutputChannel? channel) {
    if (channel == _channel) return;
    _channel?.removeListener(_onContent);
    _channel = channel;
    channel?.addListener(_onContent);
    _filtered = null;
    _scrollToEnd();
  }

  void _onService() {
    if (!mounted) return;
    setState(() => _watch(_service.activeChannel));
  }

  void _onContent() {
    if (!mounted) return;
    setState(() {});
    _scrollToEnd();
  }

  void _onFollow() {
    if (!mounted) return;
    setState(() {});
    _scrollToEnd();
  }

  /// Reveals the last line unless scrolling is locked (twice: the list's
  /// extent is an estimate until its end is laid out).
  void _scrollToEnd([int again = 1]) {
    if (!_service.followTail.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels != position.maxScrollExtent) {
        _scroll.jumpTo(position.maxScrollExtent);
        if (again > 0) _scrollToEnd(again - 1);
      }
    });
  }

  /// The indices of the lines shown.
  List<int>? _visibleLines(ExtensionOutputChannel channel) {
    final shown = _service.shownLevels.value;
    if (!channel.log ||
        ExtensionOutputPanel._levels.every(shown.contains)) {
      return null;
    }
    final key = (channel, channel.text.revision, channel.text.length, shown);
    if (_filtered != null && _filteredFor == key) return _filtered;
    final text = channel.text;
    _filteredFor = key;
    return _filtered = [
      for (var i = 0; i < text.length; i++)
        if (text.levelAt(i) case final level
            when level == null || shown.contains(level))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final channel = _channel;
    return ColoredBox(
      color: themeColors['panel.background'],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(context, l10n, channel),
          Expanded(
            child: channel == null
                ? Center(
                    child: Text(
                      l10n.windowOutputNoChannels,
                      style: TextStyle(
                        fontSize: 12,
                        color: themeColors['descriptionForeground'],
                      ),
                    ),
                  )
                : _content(l10n, channel),
          ),
        ],
      ),
    );
  }

  String _levelLabel(AppLocalizations l10n, ExtHostLogLevel level) =>
      switch (level) {
        ExtHostLogLevel.trace => l10n.windowOutputLevelTrace,
        ExtHostLogLevel.debug => l10n.windowOutputLevelDebug,
        ExtHostLogLevel.info => l10n.windowOutputLevelInfo,
        ExtHostLogLevel.warning => l10n.windowOutputLevelWarning,
        ExtHostLogLevel.error => l10n.windowOutputLevelError,
        ExtHostLogLevel.off => l10n.windowOutputLevelOff,
      };

  Widget _toolbar(
    BuildContext context,
    AppLocalizations l10n,
    ExtensionOutputChannel? channel,
  ) {
    final follow = _service.followTail.value;
    final level = channel == null ? null : _service.channelLogLevel(channel);
    final open = widget.onOpenInEditor;
    final path = channel?.filePath;
    return SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: _ChannelSelect(
                key: const ValueKey('windowOutput.channels'),
                tooltip: l10n.windowOutputSwitch,
                label: channel?.label ?? '',
                entries: () => _channelEntries(),
              ),
            ),
            const SizedBox(width: 4),
            if (channel != null && channel.log)
              IdeMenuButton(
                key: const ValueKey('windowOutput.filter'),
                icon: Codicons.filter,
                tooltip: l10n.windowOutputFilter,
                entries: () => [
                  for (final level in ExtensionOutputPanel._levels)
                    IdeMenuAction(
                      _levelLabel(l10n, level),
                      checked: _service.shownLevels.value.contains(level),
                      onSelected: () {
                        final shown = {..._service.shownLevels.value};
                        if (!shown.remove(level)) shown.add(level);
                        _service.shownLevels.value = shown;
                      },
                    ),
                ],
              ),
            if (channel != null && _service.canSetLogLevel(channel))
              IdeMenuButton(
                key: const ValueKey('windowOutput.logLevel'),
                icon: Codicons.gear,
                tooltip: l10n.windowOutputSetLogLevel,
                entries: () => ideMenuGroups([
                  [
                    for (final value in [
                      ...ExtensionOutputPanel._levels,
                      ExtHostLogLevel.off,
                    ])
                      IdeMenuAction(
                        _levelLabel(l10n, value),
                        checked: value == level,
                        onSelected: () =>
                            _service.setChannelLogLevel(channel, value),
                      ),
                  ],
                  [
                    IdeMenuAction(
                      l10n.windowOutputSetAsDefault,
                      enabled: level != null &&
                          level != _service.defaultLogLevel,
                      onSelected: () {
                        if (level != null) _service.setDefaultLogLevel(level);
                      },
                    ),
                  ],
                ]),
              ),
            IdeActionButton(
              key: const ValueKey('windowOutput.clear'),
              icon: Codicons.clearAll,
              tooltip: l10n.windowOutputClear,
              onPressed: channel == null ? null : _service.clearActive,
            ),
            IdeActionButton(
              key: const ValueKey('windowOutput.scrollLock'),
              icon: follow ? Codicons.lock : Codicons.unlock,
              tooltip: follow
                  ? l10n.windowOutputScrollOff
                  : l10n.windowOutputScrollOn,
              checked: !follow,
              onPressed: () => _service.followTail.value = !follow,
            ),
            if (open != null)
              IdeActionButton(
                key: const ValueKey('windowOutput.openInEditor'),
                icon: Codicons.goToFile,
                tooltip: l10n.windowOutputOpenInEditor,
                onPressed: path == null ? null : () => open(path),
              ),
          ],
        ),
      ),
    );
  }

  /// Extension channels, then the others; each by label.
  List<IdeMenuEntry> _channelEntries() {
    final active = _service.activeChannel;
    int byLabel(ExtensionOutputChannel a, ExtensionOutputChannel b) =>
        a.label.toLowerCase().compareTo(b.label.toLowerCase());
    final channels = _service.channels;
    IdeMenuAction entry(ExtensionOutputChannel c) => IdeMenuAction(
      c.label,
      checked: c == active,
      onSelected: () => _service.setActiveChannel(c.id),
    );
    return ideMenuGroups([
      [
        for (final c in channels.where((c) => c.extensionId != null).toList()
          ..sort(byLabel))
          entry(c),
      ],
      [
        for (final c in channels.where((c) => c.extensionId == null).toList()
          ..sort(byLabel))
          entry(c),
      ],
    ]);
  }

  Widget _content(AppLocalizations l10n, ExtensionOutputChannel channel) {
    final text = channel.text;
    final visible = _visibleLines(channel);
    final count = visible?.length ?? text.length;
    final truncated = channel.skippedBytes > 0 || text.droppedLines > 0;
    final font = CodeFont.families.value;
    final style = TextStyle(
      fontFamily: font.isEmpty ? 'monospace' : font.first,
      fontFamilyFallback: font.length > 1 ? font.sublist(1) : null,
      fontSize: 12,
      height: 18 / 12,
      color: themeColors['editor.foreground'],
    );
    final head = truncated ? 1 : 0;
    return SelectionArea(
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          key: ValueKey('windowOutput.lines.${channel.id}'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          itemCount: count + head,
          itemBuilder: (context, i) {
            if (i < head) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.windowOutputTruncated(
                    '${(_service.maxChannelBytes / (1024 * 1024)).round()} MB',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: themeColors['descriptionForeground'],
                  ),
                ),
              );
            }
            final index = visible == null ? i - head : visible[i - head];
            final line = text[index];
            return Text.rich(
              channel.log ? _logLine(line) : TextSpan(text: line),
              style: style,
              softWrap: true,
            );
          },
        ),
      ),
    );
  }

  /// A log entry's time and level in the colors of upstream's log
  /// language.
  TextSpan _logLine(String line) {
    final match = logEntryPattern.firstMatch(line);
    if (match == null) return TextSpan(text: line);
    final time = match.group(1)!;
    final level = match.group(2)!;
    final rest = line.substring(time.length + 1 + level.length);
    final levelColor = switch (match.group(3)) {
      'error' => themeColors.get('editorError.foreground'),
      'warning' => themeColors.get('editorWarning.foreground'),
      'info' => themeColors.get('editorInfo.foreground'),
      _ => themeColors.get('descriptionForeground'),
    };
    return TextSpan(
      children: [
        TextSpan(
          text: time,
          style: TextStyle(color: themeColors['descriptionForeground']),
        ),
        const TextSpan(text: ' '),
        TextSpan(
          text: level,
          style: TextStyle(color: levelColor),
        ),
        TextSpan(text: rest),
      ],
    );
  }
}

/// The Switch Output dropdown: a select box showing the active channel.
class _ChannelSelect extends StatefulWidget {
  const _ChannelSelect({
    super.key,
    required this.tooltip,
    required this.label,
    required this.entries,
  });

  final String tooltip;
  final String label;
  final List<IdeMenuEntry> Function() entries;

  @override
  State<_ChannelSelect> createState() => _ChannelSelectState();
}

class _ChannelSelectState extends State<_ChannelSelect> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final border = themeColors.get('dropdown.border') ??
        themeColors['dropdown.background'];
    return IdeMenuAnchorScope(
      onMenu: (open) {
        if (mounted) setState(() => _open = open);
      },
      child: Builder(
        builder: (context) => IdeHover(
          message: widget.tooltip,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final box = context.findRenderObject()! as RenderBox;
                unawaited(
                  showIdeMenu(
                    context,
                    anchor: box.localToGlobal(Offset.zero) & box.size,
                    entries: widget.entries(),
                  ),
                );
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120, maxWidth: 260),
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.only(left: 6, right: 2),
                  decoration: BoxDecoration(
                    color: themeColors['dropdown.background'],
                    border: Border.all(
                      color: _open
                          ? themeColors.get('focusBorder') ?? border
                          : border,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: themeColors['dropdown.foreground'],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Codicons.chevronDown,
                        size: 16,
                        color: themeColors['dropdown.foreground'],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
