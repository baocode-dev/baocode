// The "Running Extensions" view: every extension of the running hosts,
// the slowest activation first, with what activated it and the errors it
// raised (VS Code's Toggle Running Extensions editor, see
// runtime_extensions.dart).

import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'runtime_extensions.dart';

/// What a row shows: the name, when it activated, what activated it, and
/// its errors.
class ExtensionRunningExtensionsView extends StatelessWidget {
  const ExtensionRunningExtensionsView({super.key, required this.service});

  final RunningExtensionsService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final extensions = service.sorted();
      if (extensions.isEmpty) {
        return Center(
          child: Text(
            context.l10n.windowRunningExtensionsEmpty,
            style: TextStyle(
              fontSize: 13,
              color: themeColors['descriptionForeground'],
            ),
          ),
        );
      }
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: extensions.length,
        itemBuilder: (context, index) =>
            _Row(extension: extensions[index], service: service),
      );
    },
  );
}

class _Row extends StatefulWidget {
  const _Row({required this.extension, required this.service});

  final RunningExtension extension;
  final RunningExtensionsService service;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;
  bool _expanded = false;

  RunningExtension get _extension => widget.extension;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final extension = _extension;
    final times = extension.activationTimes;
    final activation = extension.isActivating
        ? l10n.windowRunningExtensionsActivating
        : times == null
        ? ''
        : (times.reason.startup
              ? l10n.windowRunningExtensionsStartup(
                  '${times.syncTime.round()}',
                )
              : l10n.windowRunningExtensionsActivation(
                  '${times.syncTime.round()}',
                ));
    final errors = extension.errors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: errors.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: _hover
                  ? themeColors['list.hoverBackground']
                  : Colors.transparent,
              child: Row(
                children: [
                  Icon(
                    errors.isEmpty
                        ? Codicons.extensions
                        : Codicons.bug,
                    size: 16,
                    color: errors.isEmpty
                        ? themeColors['icon.foreground']
                        : themeColors['errorForeground'],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          extension.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: themeColors['foreground'],
                          ),
                        ),
                        Text(
                          [
                            extension.id,
                            if (extension.version.isNotEmpty) extension.version,
                          ].join('  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: themeColors['descriptionForeground'],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (errors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        l10n.windowRunningExtensionsErrors(errors.length),
                        style: TextStyle(
                          fontSize: 12,
                          color: themeColors['errorForeground'],
                        ),
                      ),
                    ),
                  if (activation.isNotEmpty)
                    IdeHover(
                      message: times?.reason.description,
                      position: IdeHoverPosition.below,
                      child: Text(
                        activation,
                        style: TextStyle(
                          fontSize: 12,
                          color: themeColors['descriptionForeground'],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          for (final error in errors)
            Padding(
              padding: const EdgeInsets.fromLTRB(34, 4, 10, 8),
              child: SelectableText(
                error.stack == null
                    ? error.summary
                    : '${error.summary}\n${error.stack}',
                style: TextStyle(
                  fontSize: 12,
                  color: themeColors['errorForeground'],
                ),
              ),
            ),
        Divider(
          height: 1,
          thickness: 1,
          color: themeColors.get('treeTableColumnsSeparator') ??
              themeColors['panel.border'],
        ),
      ],
    );
  }
}

/// The view's title bar: its name and a button that clears the recorded
/// errors.
class ExtensionRunningExtensionsTitle extends StatelessWidget {
  const ExtensionRunningExtensionsTitle({
    super.key,
    required this.service,
  });

  final RunningExtensionsService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              context.l10n.windowRunningExtensionsTitle,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: .5,
                color: themeColors['panelTitle.inactiveForeground'],
              ),
            ),
          ),
        ),
        IdeActionButton(
          icon: Codicons.clearAll,
          tooltip: context.l10n.notificationsClearAll,
          onPressed: () {
            for (final extension in service.withErrors) {
              service.clearErrors(extension.id);
            }
          },
        ),
        const SizedBox(width: 4),
      ],
    ),
  );
}
