// The activity bar (upstream `ActivityBarPart`, activitybarPart.ts): the
// side bar's views, the one showing selected, Source Control's count of
// changes on it; the app's Settings at its foot.

import 'package:flutter/widgets.dart';

import '../../../debug/ui/debug_strings.dart';
import '../../../keybindings/default_keybindings.dart';
import '../../../keybindings/keybinding_service.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/codicons.dart';
import '../../ide_hover.dart';
import '../../ide_modern_ui.dart';
import '../../services/debug_view.dart';
import '../../services/layout.dart';
import '../../services/scm_service.dart';
import '../environment.dart';
import '../services.dart';
import '../style.dart';
import '../views.dart';

class ActivityBarPart extends StatelessWidget {
  const ActivityBarPart({super.key, required this.sidebarShowing});

  /// Whether the side bar shows (its view's item is selected): not where
  /// it gave way to the chat.
  final bool sidebarShowing;

  @override
  Widget build(BuildContext context) {
    final services = WorkbenchScope.of(context);
    final layout = services.get<LayoutService>();
    final scm = services.get<ScmService>();
    return ListenableBuilder(
      listenable: Listenable.merge([layout, scm, KeybindingService.instance]),
      builder: (context, _) =>
          _bar(context, layout, scm, services.get<WorkbenchEnvironment>()),
    );
  }

  Widget _bar(
    BuildContext context,
    LayoutService layout,
    ScmService scm,
    WorkbenchEnvironment environment,
  ) {
    Widget item(IdeSideView view, IconData icon, String label, {int? badge}) {
      // The side bar as it shows: one given way to the chat opens.
      final selected = layout.view == view && sidebarShowing;
      return _ActivityItem(
        icon: icon,
        label: label,
        badge: badge,
        selected: selected,
        onTap: () {
          if (selected) {
            layout.layout.sidebar = false;
          } else {
            layout.view = view;
            layout.layout.showSidebar();
          }
        },
      );
    }

    // Each view's name and the keybinding of the command opening it, as
    // upstream's `CompositeBarActionViewItem.computeTitle`
    // (compositeBarActions.ts), then its badge's description.
    final keys = KeybindingService.instance;
    final l10n = context.l10n;
    final items = [
      item(
        IdeSideView.explorer,
        Codicons.files,
        keys.titleWithKeybinding(l10n.wbExplorer, 'workbench.view.explorer'),
      ),
      item(
        IdeSideView.search,
        Codicons.search,
        // Find in Files has Show Search's ⇧⌘F (workbench_keybindings.dart),
        // which then shows nothing of its own.
        switch (keys.labelFor('workbench.action.findInFiles') ??
            keys.labelFor('workbench.view.search')) {
          final shortcut? => '${l10n.wbSearchFiles} ($shortcut)',
          null => l10n.wbSearchFiles,
        },
      ),
      item(
        IdeSideView.sourceControl,
        Codicons.sourceControl,
        keys.titleWithKeybinding(l10n.scmTitle, 'workbench.view.scm') +
            (scm.count > 0 ? ' - ${l10n.wbPendingChanges(scm.count)}' : ''),
        badge: scm.count,
      ),
      if (debugEntryShown)
        item(
          IdeSideView.debug,
          Codicons.debugAlt,
          keys.titleWithKeybinding(
            DebugStrings.of(context).runAndDebug,
            'workbench.view.debug',
          ),
        ),
      item(
        IdeSideView.extensions,
        Codicons.extensions,
        keys.titleWithKeybinding(l10n.extTitle, 'workbench.view.extensions'),
      ),
    ];
    // Settings at its foot, as upstream's Manage gear: the chat's sidebar
    // has them, the IDE had no way to them but the palette.
    final settings = environment.hostCommand(openSettingsCommandId);
    return SizedBox(
      width: IdeModernUI.activityBarWidth,
      // On the window's color, beside the cards; not islands, a part of
      // its own, its line beside the side bar.
      child: IdePart(
        color: WorkbenchStyle.islands
            ? null
            : IdeModernUI.activityBarBackground,
        border: WorkbenchStyle.islands
            ? null
            : Border(right: IdePart.side('activityBar.border')),
        child: Padding(
          // Half the lane above and below; the items centered across.
          padding: const EdgeInsets.symmetric(
            vertical: IdeModernUI.activityLane / 2,
          ),
          child: Column(
            children: [
              for (final (index, item) in items.indexed) ...[
                if (index > 0)
                  const SizedBox(height: IdeModernUI.activityItemGap),
                item,
              ],
              if (settings != null) ...[
                const Spacer(),
                _ActivityItem(
                  key: const ValueKey('ide.activity.settings'),
                  icon: Codicons.settingsGear,
                  label: keys.titleWithKeybinding(
                    l10n.settingsTitle,
                    openSettingsCommandId,
                  ),
                  selected: false,
                  onTap: settings.run,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An activity bar item: a 24px codicon in a 36px square; the active and
/// the hovered item sit on a rounded 32px box.
class _ActivityItem extends StatefulWidget {
  const _ActivityItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A count shown on the icon (`NumberBadge`); none when null or 0.
  final int? badge;

  @override
  State<_ActivityItem> createState() => _ActivityItemState();
}

class _ActivityItemState extends State<_ActivityItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: widget.label,
    position: IdeHoverPosition.right,
    pointer: true,
    child: Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox.square(
            dimension: IdeModernUI.activityItemSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: _icon()),
                if (widget.badge case final count? when count > 0)
                  Positioned(
                    top: 18,
                    right: 3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: IdeModernUI.activityBadgeBackground,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        ideBadgeLabel(count),
                        style: TextStyle(
                          fontSize: 10,
                          height: 1,
                          color: IdeModernUI.activityBadgeForeground,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _icon() => Container(
    width: IdeModernUI.activityItemSize - 4,
    height: IdeModernUI.activityItemSize - 4,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: widget.selected
          ? IdeModernUI.activityActiveBackground
          : _hover
          ? IdeModernUI.activityHoverBackground
          : null,
      borderRadius: BorderRadius.circular(
        WorkbenchStyle.islands
            ? IdeModernUI.activityItemRadius
            : IdeModernUI.flatActivityItemRadius,
      ),
    ),
    child: Icon(
      widget.icon,
      size: WorkbenchStyle.islands
          ? IdeModernUI.activityIconSize
          : IdeModernUI.flatActivityIconSize,
      color: widget.selected
          ? IdeModernUI.activityActiveForeground
          : _hover
          ? IdeModernUI.activityHoverForeground
          : WorkbenchStyle.islands
          ? IdeModernUI.activityForeground
          : IdeModernUI.flatActivityForeground,
    ),
  );
}
