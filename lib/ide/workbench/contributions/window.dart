// The window's own commands: the chat's beside the editor (Add Selection
// to Chat, Back to Chat), the preferences the app has (Color Theme,
// Settings), and the app's commands among the window's.

import 'dart:async';

import '../../../keybindings/chat_keybindings.dart' show ChatCommandIds;
import '../../../keybindings/default_keybindings.dart'
    show openSettingsCommandId;
import '../../../l10n/l10n.dart';
import '../../ide_color_theme_picker.dart';
import '../../services/chat.dart';
import '../../services/commands.dart';
import '../../services/editors.dart';
import '../../services/quick_input.dart';
import '../actions.dart';
import '../contributions.dart';
import '../environment.dart';
import '../services.dart';

class WindowContribution extends WorkbenchRegistrations {
  WindowContribution(WorkbenchServices services) {
    final chat = services.get<ChatService>();
    final environment = services.get<WorkbenchEnvironment>();
    final host = services.get<WorkbenchHost>();
    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: ChatCommandIds.attachSelection,
          category: 'Chat',
          title: 'Add Selection to Chat',
          precondition: (services) =>
              chat.canAddCode && services.get<EditorService>().editor != null,
          run: (_, _) => chat.addSelection(),
        ),
        WorkbenchAction(
          id: ideSelectColorThemeCommandId,
          category: 'Preferences',
          title: 'Color Theme',
          precondition: (_) => environment.colorThemes != null,
          run: (_, _) {
            final themes = environment.colorThemes;
            final context = host.context;
            if (themes == null || context == null) return;
            services.get<QuickInputService>().showModel(
              ideColorThemePick(
                themes,
                onError: host.report,
                l10n: context.l10n,
              ),
            );
          },
        ),
        WorkbenchAction(
          id: 'baocode.ide.backToChat',
          category: 'View',
          title: 'Back to Chat',
          run: (_, _) => unawaited(chat.back()),
        ),
        // The app's Settings, by the id VS Code's keybindings have.
        WorkbenchAction.catalog(
          'workbench.action.openGlobalSettings',
          precondition: (_) =>
              environment.hostCommand(openSettingsCommandId)?.enabled ?? false,
          run: (_, _) =>
              environment.hostCommand(openSettingsCommandId)?.invoke(),
        ),
      ]),
    );
    add(
      services.get<CommandService>().addSource(() => environment.hostCommands),
    );
  }
}
