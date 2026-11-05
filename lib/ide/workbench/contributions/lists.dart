// The `list.*` commands (listCommands.ts), for keybindings only, and the
// lists' context keys, over the window's ListService.

import '../../services/lists.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';

class ListsContribution extends WorkbenchRegistrations {
  ListsContribution(WorkbenchServices services) {
    final lists = services.get<ListService>();

    /// One in the list with the keyboard, while [enabled] for it.
    WorkbenchAction command(
      String id,
      void Function(WorkbenchList list) run, {
      bool Function(WorkbenchList list)? enabled,
      void Function(WorkbenchList list, Object? args)? withArgs,
    }) => WorkbenchAction.catalog(
      id,
      palette: false,
      takesArgs: withArgs != null,
      precondition: (_) => switch (lists.focused) {
        final list? => enabled?.call(list) ?? true,
        null => false,
      },
      run: (_, args) {
        final list = lists.focused;
        if (list == null) return;
        if (withArgs != null && args != null) return withArgs(list, args);
        run(list);
      },
    );
    // `list.focusDown` / `list.focusUp`'s argument: how many rows.
    int rows(Object? args) => args is num ? args.toInt() : 1;
    bool multiselect(WorkbenchList list) => list.supportsMultiselect;

    add(
      services.get<ActionRegistry>().registerAll([
        command(
          'list.focusDown',
          (list) => list.focusNext(1),
          withArgs: (list, args) => list.focusNext(rows(args)),
        ),
        command(
          'list.focusUp',
          (list) => list.focusNext(-1),
          withArgs: (list, args) => list.focusNext(-rows(args)),
        ),
        command('list.focusPageDown', (list) => list.focusPage(1)),
        command('list.focusPageUp', (list) => list.focusPage(-1)),
        command('list.focusFirst', (list) => list.focusFirst()),
        command('list.focusLast', (list) => list.focusLast()),
        command('list.select', (list) => list.select()),
        command('list.toggleExpand', (list) => list.toggleExpand()),
        command('list.expand', (list) => list.expand()),
        command('list.collapse', (list) => list.collapse()),
        command('list.collapseAll', (list) => list.collapseAll()),
        command(
          'list.expandSelectionDown',
          (list) => list.expandSelection(1),
          enabled: multiselect,
        ),
        command(
          'list.expandSelectionUp',
          (list) => list.expandSelection(-1),
          enabled: multiselect,
        ),
        command(
          'list.selectAll',
          (list) => list.selectAll(),
          enabled: multiselect,
        ),
        command(
          'list.clear',
          (list) => list.clear(),
          enabled: (list) => list.hasSelection,
        ),
      ]),
    );
    add(services.get<ContextKeyService>().addProvider(lists.contextKey));
  }
}
