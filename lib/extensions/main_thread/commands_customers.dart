// The main thread actors of commands, menus, context keys and keybindings.
//
// The lead passes this map as (part of) `ExtensionHostService.customers`,
// or picks the single entry it needs:
//
// ```dart
// final service = ExtensionHostService(
//   …,
//   customers: {
//     ...commandsCustomers(),
//   },
//   services: {
//     ExtensionCommandRegistry: commandRegistry,
//     ContextKeyService: contextKeys,          // when the workbench has one
//     WorkbenchCommandsPort: workbenchPort,    // optional, see the ports
//     EditorCommandsPort: editorPort,          // optional
//   },
// );
// ```
//
// Each customer pulls what it needs from `context.service<T>()`; one that
// is missing is only an error when the extension host calls it
// (`MainThreadCommands` needs `ExtensionCommandRegistry`).

import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_commands.dart';
import 'main_thread_context.dart';

/// The `MainContext` ids this area implements, with their actors.
Map<int, MainThreadCustomer> commandsCustomers() => {
  MainContext.mainThreadCommands.nid: MainThreadCommands.customer,
};
