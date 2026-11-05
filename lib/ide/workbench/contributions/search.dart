// The Search view's commands and context keys, over the window's
// SearchViewService.
//
// Ported from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/search/browser/searchActions*.ts and
// searchActionsBase.ts (`findInFilesCommand`, `findOrReplaceInFiles`,
// `focusNextSearchResult`…).
//
// Deviations:
// - The commands upstream's palette does not list (`f1: false`) are for
//   keybindings alone here too; those on the view's inputs and results
//   run while it shows.

import '../../search/ide_search_view.dart';
import '../../services/search_view.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';

class SearchContribution extends WorkbenchRegistrations {
  SearchContribution(WorkbenchServices services) {
    final search = services.get<SearchViewService>();
    final session = search.session;
    bool hasResults(WorkbenchServices _) => session.results.isNotEmpty;
    bool shown(WorkbenchServices _) => search.view != null;

    /// One for keybindings alone: a search toggle, flipped while the view
    /// shows.
    WorkbenchAction toggle(String id, void Function(IdeSearchSession) flip) =>
        WorkbenchAction.catalog(
          id,
          palette: false,
          precondition: shown,
          run: (_, _) => search.toggleOption(flip),
        );

    /// One on the view's inputs and results, while it shows.
    WorkbenchAction inView(
      String id,
      void Function(IdeSearchViewState view) run, {
      bool Function(WorkbenchServices services)? enabled,
    }) => WorkbenchAction.catalog(
      id,
      palette: false,
      precondition: (services) =>
          search.view != null && (enabled?.call(services) ?? true),
      run: (_, _) {
        if (search.view case final view?) run(view);
      },
    );
    bool replacing(WorkbenchServices _) => session.replaceShown;

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction.catalog(
          'workbench.action.findInFiles',
          takesArgs: true,
          run: (_, args) => search.findInFiles(args),
        ),
        WorkbenchAction.catalog(
          'workbench.action.replaceInFiles',
          run: (_, _) => search.replaceInFiles(),
        ),
        WorkbenchAction.catalog(
          'search.action.focusNextSearchResult',
          precondition: hasResults,
          run: (_, _) => search.focusResult(next: true),
        ),
        WorkbenchAction.catalog(
          'search.action.focusPreviousSearchResult',
          precondition: hasResults,
          run: (_, _) => search.focusResult(next: false),
        ),
        WorkbenchAction.catalog(
          'search.action.focusSearchList',
          run: (_, _) => search.focusResults(),
        ),
        WorkbenchAction.catalog(
          'search.action.cancel',
          precondition: (_) => session.searching,
          run: (_, _) {
            session.cancel();
            if (search.view != null) session.requestFocus();
          },
        ),
        WorkbenchAction.catalog(
          'search.action.refreshSearchResults',
          precondition: (_) => session.query.text.isNotEmpty,
          run: (_, _) => session.search(search.workspace.root),
        ),
        WorkbenchAction.catalog(
          'search.action.clearSearchResults',
          precondition: (_) =>
              session.results.isNotEmpty ||
              session.query.text.isNotEmpty ||
              session.replace.text.isNotEmpty ||
              session.includes.text.isNotEmpty ||
              session.excludes.text.isNotEmpty,
          run: (_, _) => session.clear(),
        ),
        WorkbenchAction.catalog(
          'search.action.collapseSearchResults',
          precondition: (_) =>
              session.results.isNotEmpty && session.anyExpanded,
          run: (_, _) => session.collapseAll(),
        ),
        WorkbenchAction.catalog(
          'search.action.expandSearchResults',
          precondition: (_) =>
              session.results.isNotEmpty && !session.anyExpanded,
          run: (_, _) => session.expandAll(),
        ),
        toggle('toggleSearchCaseSensitive', (s) => s.matchCase = !s.matchCase),
        toggle('toggleSearchWholeWord', (s) => s.wholeWord = !s.wholeWord),
        toggle('toggleSearchRegex', (s) => s.useRegExp = !s.useRegExp),
        WorkbenchAction.catalog(
          'toggleSearchPreserveCase',
          palette: false,
          precondition: shown,
          run: (_, _) {
            session.preserveCase = !session.preserveCase;
            session.notify();
          },
        ),
        inView('search.focus.nextInputBox', (view) => view.focusNextInputBox()),
        inView(
          'search.focus.previousInputBox',
          (view) => view.focusPreviousInputBox(),
        ),
        inView(
          'search.action.focusSearchFromResults',
          (view) => view.focusPreviousInputBox(),
        ),
        inView('search.action.openResult', (view) => view.openFocused()),
        inView('search.action.remove', (view) => view.removeFocused()),
        inView(
          'search.action.replace',
          (view) => view.replaceFocused(),
          enabled: replacing,
        ),
        inView(
          'search.action.replaceAllInFile',
          (view) => view.replaceFocused(),
          enabled: replacing,
        ),
        inView(
          'search.action.replaceAll',
          (view) => view.replaceAll(),
          enabled: (_) =>
              search.layout.sidebarFocus.hasFocus &&
              session.replaceShown &&
              session.results.isNotEmpty,
        ),
        inView('closeReplaceInFilesWidget', (view) => view.closeReplace()),
        inView(
          'workbench.action.search.toggleQueryDetails',
          (view) => view.toggleQueryDetails(),
        ),
        inView('search.action.copyMatch', (view) => view.copyFocused()),
        inView(
          'search.action.copyPath',
          (view) => view.copyFocused(path: true),
        ),
        inView(
          'search.action.copyAll',
          (view) => view.copyAll(),
          enabled: hasResults,
        ),
      ]),
    );
    add(services.get<ContextKeyService>().addProvider(search.contextKey));
  }
}
