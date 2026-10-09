/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Source Control view's panes for extensions' source controls: one per
// provider, its `scm/title` actions and count in the header, its input box
// (⌘Enter runs the accept input command), its action button, and its
// resource groups with their resources, each with its inline and context
// menus (`scm/resourceGroup/context`, `scm/resourceState/context`).
//
// Adapted from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/scm/browser/scmViewPane.ts (`RepositoryRenderer`,
// `ResourceGroupRenderer`, `ResourceRenderer`: the label, the
// description, the decorations' strike through and fading, opening a
// resource), menus.ts (the overlays: `scmProvider`, `scmProviderRootUri`,
// `scmProviderHasRootUri`, `scmResourceGroup`, `scmResourceGroupState`,
// `scmResourceState`), scmInput.ts (placeholder `{0}` as the ⌘Enter key,
// the validation) and the action button (`SCMActionButton`).
//
// Deviations: the resources are a list (no tree mode, no sort menu); a
// multiple selection is not offered (an action runs on its one resource);
// the action button's secondary commands are left out.

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/material.dart' hide ImageIcon;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../../ide/ide_hover.dart';
import '../../ide/ide_input.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_panes.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';
import '../commands/command_contributions.dart';
import '../contextkey/context_key_service.dart';
import '../menus/menu_service.dart';
import '../menus/menu_widgets.dart';
import 'scm_service.dart';

/// What the panes need of the workbench.
final class ExtensionScmUi {
  const ExtensionScmUi({
    required this.service,
    required this.menus,
    required this.contextKeys,
    required this.executeCommand,
    this.onError,
  });

  final ScmService service;
  final MenuService menus;
  final ContextKeyService contextKeys;
  final Future<Object?> Function(String id, List<Object?> args) executeCommand;
  final ValueChanged<String>? onError;

  /// `${provider.handle}`: the pane ids, to expand them as they appear.
  static String paneId(ScmProvider provider) => 'ext-scm-${provider.handle}';

  /// The providers' panes.
  List<IdePane> panes() => [
    for (final provider in service.shownProviders)
      IdePane(
        id: paneId(provider),
        title: provider.label,
        description: provider.name,
        weight: 2,
        actions: [_TitleActions(ui: this, provider: provider)],
        badge: switch (provider.count ?? provider.resourceCount) {
          0 => null,
          final count => IdeCountBadge(count),
        },
        body: ExtensionScmProviderBody(
          key: ValueKey(provider),
          ui: this,
          provider: provider,
        ),
      ),
  ];

  /// The provider's context keys (menus.ts).
  ContextKeyValues providerContext(ScmProvider provider) =>
      contextKeys.createOverlay({
        'scmProvider': provider.providerId,
        'scmProviderRootUri': provider.rootUri?.toString(),
        'scmProviderHasRootUri': provider.rootUri != null,
        'scmProviderContext': provider.contextValue,
      });

  ContextKeyValues groupContext(ScmResourceGroup group) =>
      contextKeys.createOverlay({
        'scmProvider': group.provider.providerId,
        'scmProviderRootUri': group.provider.rootUri?.toString(),
        'scmProviderHasRootUri': group.provider.rootUri != null,
        'scmResourceGroup': group.id,
        'scmResourceGroupState': group.contextValue,
      });

  ContextKeyValues resourceContext(ScmResource resource) =>
      contextKeys.createOverlay({
        'scmProvider': resource.group.provider.providerId,
        'scmProviderRootUri': resource.group.provider.rootUri?.toString(),
        'scmProviderHasRootUri': resource.group.provider.rootUri != null,
        'scmResourceGroup': resource.group.id,
        'scmResourceState': resource.contextValue,
      });

  Future<void> run(Map<String, Object?> command) async {
    final id = command['id'];
    if (id is! String) return;
    try {
      await executeCommand(id, [...?command['arguments'] as List?]);
    } on Object catch (error) {
      onError?.call('$error');
    }
  }
}

class _TitleActions extends StatelessWidget {
  const _TitleActions({required this.ui, required this.provider});

  final ExtensionScmUi ui;
  final ScmProvider provider;

  @override
  Widget build(BuildContext context) => IdeMenuActions(
    groups: ui.menus.menuItems(
      'scm/title',
      ui.providerContext(provider),
      args: [provider.toArgument()],
    ),
  );
}

/// One provider's input box, action button and resources.
class ExtensionScmProviderBody extends StatefulWidget {
  const ExtensionScmProviderBody({
    super.key,
    required this.ui,
    required this.provider,
  });

  final ExtensionScmUi ui;
  final ScmProvider provider;

  @override
  State<ExtensionScmProviderBody> createState() =>
      _ExtensionScmProviderBodyState();
}

class _ExtensionScmProviderBodyState extends State<ExtensionScmProviderBody> {
  late final TextEditingController _input = TextEditingController(
    text: widget.provider.input.value,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'extension scm list');
  final Set<int> _collapsed = {};
  String? _selected;
  Timer? _validating;
  void Function()? _stopContext;

  ScmProvider get _provider => widget.provider;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_changed);
    _provider.input.addListener(_inputChanged);
    _stopContext = widget.ui.contextKeys.onDidChangeContext((event) {
      if (mounted &&
          event.affectsSome({
            ...widget.ui.menus.contextKeysOf('scm/resourceState/context'),
            ...widget.ui.menus.contextKeysOf('scm/resourceGroup/context'),
          })) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _provider.removeListener(_changed);
    _provider.input.removeListener(_inputChanged);
    _stopContext?.call();
    _validating?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _inputChanged() {
    final value = _provider.input.value;
    if (_input.text != value) {
      _input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    _changed();
  }

  void _typed(String value) {
    _provider.input.setValue(value, fromView: true);
    final validate = _provider.input.validate;
    if (validate == null) return;
    _validating?.cancel();
    _validating = Timer(const Duration(milliseconds: 200), () async {
      final cursor = _input.selection.baseOffset.clamp(0, value.length);
      try {
        final result = await validate(value, cursor);
        if (_provider.input.value == value) {
          _provider.input.showValidationMessage(result);
        }
      } on Object {
        // The extension host ended meanwhile.
      }
    });
  }

  Future<void> _accept() async {
    final command = _provider.acceptInputCommand;
    if (command == null) return;
    await widget.ui.run(command);
  }

  @override
  Widget build(BuildContext context) {
    final input = _provider.input;
    final button = _provider.actionButton;
    final rows = <Widget>[];
    for (final group in _provider.groups) {
      if (group.hideWhenEmpty && group.resources.isEmpty) continue;
      final collapsed = _collapsed.contains(group.handle);
      rows.add(
        _GroupRow(
          ui: widget.ui,
          group: group,
          collapsed: collapsed,
          selected: _selected == 'g${group.handle}',
          focused: _focus.hasFocus,
          onTap: () => setState(() {
            _selected = 'g${group.handle}';
            if (!_collapsed.remove(group.handle)) _collapsed.add(group.handle);
          }),
        ),
      );
      if (collapsed) continue;
      for (final resource in group.resources) {
        final key = 'r${group.handle}:${resource.handle}';
        rows.add(
          _ResourceRow(
            key: ValueKey(key),
            ui: widget.ui,
            resource: resource,
            selected: _selected == key,
            focused: _focus.hasFocus,
            onTap: () {
              setState(() => _selected = key);
              _focus.requestFocus();
              unawaited(
                resource.open(preserveFocus: true).catchError((Object e) {
                  widget.ui.onError?.call('$e');
                }),
              );
            },
          ),
        );
      }
    }
    return Focus(
      focusNode: _focus,
      onFocusChange: (_) => _changed(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          if (input.visible)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: IdeInputBox(
                controller: _input,
                placeholder: input.placeholder.replaceAll(
                  '{0}',
                  Platform.isMacOS ? '⌘Enter' : 'Ctrl+Enter',
                ),
                maxLines: 6,
                validation: switch (input.validation) {
                  final v? => IdeInputValidation(v.message, switch (v.type) {
                    ScmInputValidationType.error => IdeValidationSeverity.error,
                    ScmInputValidationType.warning =>
                      IdeValidationSeverity.warning,
                    ScmInputValidationType.information =>
                      IdeValidationSeverity.info,
                  }),
                  null => null,
                },
                onChanged: input.enabled ? _typed : null,
                shortcuts: {
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    meta: true,
                  ): () =>
                      unawaited(_accept()),
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): () =>
                      unawaited(_accept()),
                },
              ),
            ),
          if (button != null)
            if (button['command'] case final Map command)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                child: _ActionButton(
                  title: '${command['title'] ?? ''}',
                  tooltip:
                      (command['tooltip'] ?? button['description']) as String?,
                  enabled: button['enabled'] != false,
                  onPressed: () => unawaited(widget.ui.run(command.cast())),
                ),
              ),
          ...rows,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.title,
    required this.enabled,
    required this.onPressed,
    this.tooltip,
  });

  final String title;
  final String? tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = ExtensionLabel.parse(title);
    final child = SizedBox(
      height: 26,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          backgroundColor: themeColors['button.background'],
          foregroundColor: themeColors['button.foreground'],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: label.build(
          fontSize: 13,
          color: themeColors['button.foreground'],
        ),
      ),
    );
    return tooltip == null ? child : IdeHover(message: tooltip!, child: child);
  }
}

/// A label with `$(codicon)`s in it, as a button's title has.
final class ExtensionLabel {
  ExtensionLabel._(this.parts);

  static final _icon = RegExp(r'\$\(([a-zA-Z0-9-]+)(?:~[a-zA-Z]+)?\)');

  factory ExtensionLabel.parse(String text) {
    final parts = <Object>[];
    var index = 0;
    for (final match in _icon.allMatches(text)) {
      if (match.start > index) parts.add(text.substring(index, match.start));
      parts.add(Codicons.byName[match[1]!] ?? Codicons.circleOutline);
      index = match.end;
    }
    if (index < text.length) parts.add(text.substring(index));
    return ExtensionLabel._(parts);
  }

  /// Text and [IconData]s.
  final List<Object> parts;

  Widget build({required double fontSize, required Color color}) => Text.rich(
    TextSpan(
      children: [
        for (final part in parts)
          if (part is IconData)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(part, size: fontSize + 2, color: color),
            )
          else
            TextSpan(text: '$part'),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: fontSize, color: color),
  );
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.ui,
    required this.group,
    required this.collapsed,
    required this.selected,
    required this.focused,
    required this.onTap,
  });

  final ExtensionScmUi ui;
  final ScmResourceGroup group;
  final bool collapsed;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;

  List<MenuGroup> _menu() => ui.menus.menuItems(
    'scm/resourceGroup/context',
    ui.groupContext(group),
    args: [group.toArgument()],
  );

  @override
  Widget build(BuildContext context) => IdeListRow(
    selected: selected,
    focused: focused,
    onTap: onTap,
    onContextMenu: (position) => _contextMenu(context, _menu(), position),
    builder: (context, hovered) {
      final inline = hovered || selected
          ? [
              for (final g in _menu())
                if (g.id == 'inline') ...g.actions,
            ]
          : const <MenuAction>[];
      return Padding(
        padding: const EdgeInsets.only(left: IdeListColors.inset, right: 4),
        child: Row(
          children: [
            Icon(
              collapsed ? Codicons.chevronRight : Codicons.chevronDown,
              size: 16,
              color: themeColors['icon.foreground'],
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: IdeListColors.foreground,
                ),
              ),
            ),
            for (final action in inline) _inlineButton(action),
            if (group.resources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: IdeCountBadge(group.resources.length),
              ),
          ],
        ),
      );
    },
  );
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    super.key,
    required this.ui,
    required this.resource,
    required this.selected,
    required this.focused,
    required this.onTap,
  });

  final ExtensionScmUi ui;
  final ScmResource resource;
  final bool selected;
  final bool focused;
  final VoidCallback onTap;

  List<MenuGroup> _menu() => ui.menus.menuItems(
    'scm/resourceState/context',
    ui.resourceContext(resource),
    args: [resource.toArgument()],
  );

  @override
  Widget build(BuildContext context) {
    final uri = resource.sourceUri;
    final path = uri.scheme == 'file' ? uri.fsPath() : uri.path;
    final root = resource.group.provider.rootUri;
    final rootPath = root == null
        ? null
        : root.scheme == 'file'
        ? root.fsPath()
        : root.path;
    final directory = p.dirname(path);
    final description = rootPath != null && p.isWithin(rootPath, directory)
        ? p.relative(directory, from: rootPath)
        : rootPath == directory
        ? null
        : directory;
    final decorations = resource.decorations;
    return IdeListRow(
      selected: selected,
      focused: focused,
      tooltip: decorations.tooltip,
      onTap: onTap,
      onContextMenu: (position) => _contextMenu(context, _menu(), position),
      builder: (context, hovered) {
        final foreground = selected && focused
            ? IdeListColors.activeSelectionForeground
            : IdeListColors.foreground;
        final inline = hovered || selected
            ? [
                for (final g in _menu())
                  if (g.id == 'inline') ...g.actions,
              ]
            : const <MenuAction>[];
        final icon = themeColors.dark
            ? decorations.iconDark ?? decorations.icon
            : decorations.icon;
        return Opacity(
          opacity: decorations.faded ? .7 : 1,
          child: Padding(
            padding: const EdgeInsets.only(
              left: IdeListColors.inset + 20,
              right: 4,
            ),
            child: Row(
              children: [
                FileIcon(path, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    p.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: foreground,
                      decoration: decorations.strikeThrough
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                if (description != null && description != '.')
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: IdeListColors.description,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                for (final action in inline) _inlineButton(action),
                if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 8),
                    child: _decorationIcon(icon),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Widget _inlineButton(MenuAction action) => IdeActionButton(
  icon: ideMenuActionIcon(action),
  iconWidget: ideMenuActionImage(action, 16),
  tooltip: action.title,
  size: 20,
  onPressed: action is MenuCommandAction && action.enabled
      ? () => unawaited(action.run())
      : null,
);

Widget _decorationIcon(ExtensionIcon icon) => switch (icon) {
  ThemeIconRef(:final id) => Icon(
    Codicons.byName[id] ?? Codicons.circleOutline,
    size: 16,
    color: themeColors['icon.foreground'],
  ),
  ImageIcon(:final dark, :final light) => _image(
    themeColors.dark ? dark : light ?? dark,
  ),
};

Widget _image(VsUri uri) {
  if (uri.scheme != 'file') return const SizedBox.square(dimension: 16);
  final path = uri.fsPath();
  return path.toLowerCase().endsWith('.svg')
      ? SvgPicture.file(File(path), width: 16, height: 16)
      : Image.file(
          File(path),
          width: 16,
          height: 16,
          errorBuilder: (_, _, _) => const SizedBox.square(dimension: 16),
        );
}

Future<void> _contextMenu(
  BuildContext context,
  List<MenuGroup> menu,
  Offset position,
) async {
  final entries = ideMenuGroups([
    for (final group in menu)
      if (group.id != 'inline')
        [for (final action in group.actions) ?ideMenuEntryOf(action)],
  ]);
  if (entries.isEmpty) return;
  await showIdeMenu(context, position: position, entries: entries);
}
