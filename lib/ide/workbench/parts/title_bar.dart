// The title bar (upstream titlebarPart.ts), where the window does not
// draw its own header: the layout controls, the command center, back to
// the chat.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../keybindings/keybinding_service.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/app_theme.dart';
import '../../../workspace/back_to_chat_button.dart';
import '../../../workspace/pin_window_button.dart';
import '../../../workspace/title_bar_double_click.dart';
import '../../ide_command_center.dart';
import '../../ide_hover.dart';
import '../../ide_layout.dart';
import '../../services/chat.dart';
import '../../services/navigation_history.dart';
import '../../services/quick_input.dart';
import '../options.dart';
import '../services.dart';

class TitleBarPart extends StatelessWidget {
  const TitleBarPart({super.key, required this.options});

  final WorkbenchOptions options;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      options.workspace,
      KeybindingService.instance,
    ]),
    builder: (context, _) => _bar(context, WorkbenchScope.of(context)),
  );

  Widget _bar(BuildContext context, WorkbenchServices services) {
    final keys = KeybindingService.instance;
    final layout = options.workspace.layout;
    final l10n = context.l10n;
    // A double click on its empty part zooms the window, as the system's
    // title bar does.
    return TitleBarDoubleClick(
      child: SizedBox(
        height: AppMetrics.titleBarHeight,
        child: Row(
          children: [
            SizedBox(width: AppMetrics.trafficLightsWidth + 6),
            // VS Code's layout controls; the side bar's on its side, after
            // the traffic lights.
            IdeLayoutToggle.sidebar(layout),
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                child: IdeCommandCenter(
                  label: options.workspace.hasFolder
                      ? options.project.name
                      : l10n.ideSearchOpenFiles,
                  tooltip: keys.titleWithKeybinding(
                    options.workspace.hasFolder
                        ? l10n.ideSearchProject(options.project.name)
                        : l10n.ideSearchOpenFiles,
                    'workbench.action.quickOpen',
                  ),
                  onSearch: () => services.get<QuickInputService>().show(''),
                  navigation: options.workspace.navigation,
                  onNavigate: (back) =>
                      services.find<NavigationHistoryService>()?.navigate(
                        back: back,
                      ) ??
                      false,
                ),
              ),
            ),
            TitleBarControls(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IdeLayoutToggle.panel(layout),
                  IdeLayoutToggle.chat(layout),
                  if (options.onPinnedChanged case final onPinnedChanged?) ...[
                    const SizedBox(width: 2),
                    PinWindowButton(
                      pinned: options.pinned,
                      onChanged: onPinnedChanged,
                    ),
                  ],
                  const SizedBox(width: 8),
                  // Its label, and the keys that do the same.
                  IdeHover(
                    message: keys.titleWithKeybinding(
                      options.backLabel ?? l10n.workspaceBackToChat,
                      'baocode.ide.backToChat',
                    ),
                    child: BackToChatButton(
                      label: options.backLabel,
                      onPressed: () =>
                          unawaited(services.get<ChatService>().back()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
