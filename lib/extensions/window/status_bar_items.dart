// The extensions' status bar entries as the workbench's status bar items
// (lib/ide/ide_status_bar.dart), and the menu that hides them: upstream's
// statusbarItem.ts (colors, the error/warning kinds' theme colors, the
// command with its arguments, a Markdown tooltip or one the extension
// provides) and statusbarActions.ts (`ToggleStatusbarEntryVisibilityAction`,
// `HideStatusbarEntryAction`).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_menu.dart';
import '../../ide/ide_status_bar.dart';
import '../../ide/lsp_ui/hover_markdown.dart';
import '../../l10n/l10n.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'status_bar_service.dart';
import 'window_ports.dart';

/// A tooltip an extension provides on hover (`$provideTooltip`): a string
/// or an `IMarkdownString`.
typedef ExtensionTooltipProvider = Future<Object?> Function(String entryId);

/// [service]'s visible entries of a side as status bar items, in order.
/// A click runs the entry's command through [commands]; a secondary click
/// opens [showExtensionStatusBarMenu] when [onContextMenu] is null.
List<IdeStatusBarItem> extensionStatusBarItems(
  ExtensionStatusBarService service, {
  required bool left,
  ExtensionCommandExecutor? commands,
  ExtensionTooltipProvider? provideTooltip,
  void Function(Offset position, ExtensionStatusBarEntry entry)? onContextMenu,
}) => [
  for (final entry in service.visible(left: left))
    _item(
      entry,
      commands,
      provideTooltip ?? service.tooltipProvider,
      onContextMenu,
    ),
];

IdeStatusBarItem _item(
  ExtensionStatusBarEntry entry,
  ExtensionCommandExecutor? commands,
  ExtensionTooltipProvider? provideTooltip,
  void Function(Offset position, ExtensionStatusBarEntry entry)? onContextMenu,
) {
  final colors = themeColors;
  final (background, hoverBackground, foreground) = switch (entry.kind) {
    ExtensionStatusBarKind.error => (
      colors.get('statusBarItem.errorBackground'),
      colors.get('statusBarItem.errorHoverBackground'),
      colors.get('statusBarItem.errorForeground'),
    ),
    ExtensionStatusBarKind.warning => (
      colors.get('statusBarItem.warningBackground'),
      colors.get('statusBarItem.warningHoverBackground'),
      colors.get('statusBarItem.warningForeground'),
    ),
    ExtensionStatusBarKind.standard => (null, null, null),
  };
  final command = entry.command;
  final commandId = command?['id'];
  Widget? tooltipContent;
  if (entry.hasTooltipProvider && provideTooltip != null) {
    tooltipContent = _ProvidedTooltip(
      future: () => provideTooltip(entry.entryId),
      fallback: entry.tooltipText,
    );
  } else if (entry.tooltipIsMarkdown && entry.tooltipText != null) {
    tooltipContent = _tooltipWidget(entry.tooltip);
  }
  return IdeStatusBarItem(
    entry.text,
    key: ValueKey('ext-status:${entry.entryId}'),
    tooltip: tooltipContent == null ? entry.tooltipText : null,
    tooltipContent: tooltipContent,
    color: resolveExtensionColor(entry.color) ?? foreground,
    background: background,
    hoverBackground: hoverBackground,
    semanticsLabel: entry.ariaLabel,
    onTap: commandId is String && commandId.isNotEmpty && commands != null
        ? () => unawaited(
            commands
                .executeCommand(commandId, [
                  ...?(command!['arguments'] as List?),
                ])
                .catchError((Object _) => null),
          )
        : null,
    onContextMenu: onContextMenu == null
        ? null
        : (position) => onContextMenu(position, entry),
  );
}

Widget? _tooltipWidget(Object? tooltip) => switch (tooltip) {
  final String text => Text(text),
  final Map<Object?, Object?> markdown when markdown['value'] is String =>
    IdeHoverMarkdown(markdown['value']! as String),
  _ => null,
};

class _ProvidedTooltip extends StatefulWidget {
  const _ProvidedTooltip({required this.future, required this.fallback});

  final Future<Object?> Function() future;
  final String? fallback;

  @override
  State<_ProvidedTooltip> createState() => _ProvidedTooltipState();
}

class _ProvidedTooltipState extends State<_ProvidedTooltip> {
  late final Future<Object?> _tooltip = widget.future().catchError(
    (Object _) => widget.fallback,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Object?>(
    future: _tooltip,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Text(context.l10n.windowStatusBarLoading);
      }
      return _tooltipWidget(snapshot.data ?? widget.fallback) ??
          const SizedBox.shrink();
    },
  );
}

/// A color as extensions give it: a CSS color (`#rgb`, `#rgba`, `#rrggbb`,
/// `#rrggbbaa`) or a `ThemeColor` (`{id}`) of the color theme.
Color? resolveExtensionColor(Object? color) {
  switch (color) {
    case final Map<Object?, Object?> theme when theme['id'] is String:
      return themeColors.get(theme['id']! as String);
    case final String css when css.startsWith('#'):
      var hex = css.substring(1);
      if (hex.length == 3 || hex.length == 4) {
        hex = [for (final c in hex.split('')) '$c$c'].join();
      }
      if (hex.length == 6) hex = '${hex}ff';
      if (hex.length != 8) return null;
      final value = int.tryParse(hex, radix: 16);
      if (value == null) return null;
      // #rrggbbaa → 0xaarrggbb.
      return Color(((value & 0xff) << 24) | (value >> 8));
    default:
      return null;
  }
}

/// The status bar's context menu for [entry]: hide it, and every entry's
/// visibility toggle (upstream lists them with check marks).
Future<void> showExtensionStatusBarMenu(
  BuildContext context,
  Offset position,
  ExtensionStatusBarService service,
  ExtensionStatusBarEntry entry,
) {
  final l10n = context.l10n;
  final seen = <String>{};
  final toggles = <IdeMenuEntry>[
    for (final other in service.entries)
      if (seen.add(other.id))
        IdeMenuAction(
          other.name,
          checked: !service.isHidden(other.id),
          onSelected: () =>
              service.setHidden(other.id, !service.isHidden(other.id)),
        ),
  ];
  return showIdeMenu(
    context,
    position: position,
    entries: ideMenuGroups([
      toggles,
      [
        IdeMenuAction(
          l10n.windowStatusBarHide(entry.name),
          onSelected: () => service.setHidden(entry.id, true),
        ),
      ],
    ]),
  );
}
