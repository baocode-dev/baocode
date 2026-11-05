// The quick input's commands and quick accesses, over the window's
// QuickInputService.
//
// Ported from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/platform/quickinput/browser/quickInputActions.ts and
// src/vs/workbench/browser/actions/quickAccessActions.ts (the quick
// input's commands), src/vs/workbench/browser/parts/editor/
// editorActions.ts (the editor pickers, `AbstractQuickAccessEditorAction`,
// Open Next/Previous Recently Used Editor), and the quick accesses of
// src/vs/workbench/contrib/search/browser/anythingQuickAccess.ts (files),
// commandsQuickAccess.ts (`>`), gotoLineQuickAccess.ts (`:`),
// gotoSymbolQuickAccess.ts (`@`) and editorQuickAccess.ts (`edt `).
//
// Deviations:
// - Accepting a file in the background opens it where the text says, but
//   keeps the keyboard in the quick input.
// - Quick input commands are not in the palette, which is the quick input.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';
import '../../ide_quick_input.dart';
import '../../ide_quick_open.dart';
import '../../file_service.dart' show IdeHostFiles;
import '../../ide_workspace.dart';
import '../../lsp/lsp_protocol.dart';
import '../../lsp_ui/document_symbols.dart';
import '../../services/commands.dart';
import '../../services/editors.dart';
import '../../services/explorer.dart';
import '../../services/language.dart';
import '../../services/navigation_history.dart';
import '../../services/quick_input.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../quick_access.dart';
import '../services.dart';

/// Upstream `ActiveGroupEditorsByMostRecentlyUsedQuickAccess.PREFIX`.
const editorsInGroupPrefix = 'edt active ';

/// Upstream `AllEditorsByMostRecentlyUsedQuickAccess.PREFIX`.
const editorsByRecentlyUsedPrefix = 'edt mru ';

/// Upstream `AllEditorsByAppearanceQuickAccess.PREFIX`.
const editorsByAppearancePrefix = 'edt ';

/// How old a remote project's listing is before Quick Open lists it again.
const _remoteListingAge = Duration(seconds: 30);

class QuickInputContribution extends WorkbenchRegistrations {
  QuickInputContribution(WorkbenchServices services) {
    final quick = services.get<QuickInputService>();
    final editors = services.get<EditorService>();
    IdeWorkspace? workspace() => services.find<IdeWorkspace>();
    bool hasEditors(WorkbenchServices services) =>
        workspace()?.documents.isNotEmpty ?? false;

    /// One of the quick input's own, while it shows: for keybindings only.
    WorkbenchAction inInput(
      String id,
      void Function(IdeQuickInputState input) run,
    ) => WorkbenchAction.catalog(
      id,
      palette: false,
      precondition: (_) => quick.input != null,
      run: (_, _) {
        if (quick.input case final input?) run(input);
      },
    );
    WorkbenchAction focus(String id, IdeQuickPickFocus what) =>
        inInput(id, (input) => input.focus(what));
    WorkbenchAction navigate(String id, {required bool next}) => inInput(
      id,
      (input) => input.navigate(next: next, quickNavigate: singleChordsOf(id)),
    );
    WorkbenchAction quickNavigate(
      String id,
      String prefix, {
      IdeQuickPickFocus? Function()? itemActivation,
      bool Function(WorkbenchServices services)? precondition,
    }) => WorkbenchAction.catalog(
      id,
      precondition: precondition,
      run: (_, _) => quick.quickNavigate(
        id,
        prefix,
        itemActivation: itemActivation?.call(),
      ),
    );
    WorkbenchAction showWith(String id, String prefix) =>
        WorkbenchAction.catalog(id, run: (_, _) => quick.show(prefix));

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.action.showCommands',
          title: 'Show All Commands',
          run: (_, _) => quick.show('>'),
        ),
        // A keybinding's `args` is the text to open with (upstream's
        // `prefix`: `"args": ">"` opens the commands).
        WorkbenchAction(
          id: 'workbench.action.quickOpen',
          title: 'Go to File…',
          takesArgs: true,
          run: (_, args) => quick.show(args is String ? args : ''),
        ),
        WorkbenchAction(
          id: 'workbench.action.gotoLine',
          title: 'Go to Line/Column…',
          run: (_, _) => quick.show(':'),
        ),
        WorkbenchAction(
          id: 'workbench.action.gotoSymbol',
          title: 'Go to Symbol in Editor...',
          precondition: (_) => workspace()?.active != null,
          run: (_, _) => quick.show('@'),
        ),
        focus('quickInput.next', IdeQuickPickFocus.next),
        focus('quickInput.previous', IdeQuickPickFocus.previous),
        focus('quickInput.first', IdeQuickPickFocus.first),
        focus('quickInput.last', IdeQuickPickFocus.last),
        focus('quickInput.pageNext', IdeQuickPickFocus.nextPage),
        focus('quickInput.pagePrevious', IdeQuickPickFocus.previousPage),
        inInput('quickInput.accept', (input) => input.accept()),
        inInput(
          'quickInput.acceptInBackground',
          (input) => input.accept(inBackground: true),
        ),
        inInput('quickInput.hide', (input) => input.hide()),
        inInput('workbench.action.closeQuickOpen', (input) => input.hide()),
        inInput(
          'workbench.action.acceptSelectedQuickOpenItem',
          (input) => input.accept(),
        ),
        inInput(
          'workbench.action.focusQuickOpen',
          (input) => input.focusInput(),
        ),
        inInput(
          'workbench.action.quickOpenSelectNext',
          (input) => input.navigate(next: true),
        ),
        inInput(
          'workbench.action.quickOpenSelectPrevious',
          (input) => input.navigate(next: false),
        ),
        navigate('workbench.action.quickOpenNavigateNext', next: true),
        navigate('workbench.action.quickOpenNavigatePrevious', next: false),
        navigate(
          'workbench.action.quickOpenNavigateNextInFilePicker',
          next: true,
        ),
        navigate(
          'workbench.action.quickOpenNavigatePreviousInFilePicker',
          next: false,
        ),
        navigate(
          'workbench.action.quickOpenNavigateNextInEditorPicker',
          next: true,
        ),
        navigate(
          'workbench.action.quickOpenNavigatePreviousInEditorPicker',
          next: false,
        ),
        WorkbenchAction.catalog(
          'workbench.action.quickOpenPreviousEditor',
          palette: false,
          run: (_, _) =>
              quick.show('', itemActivation: IdeQuickPickFocus.second),
        ),
        showWith('workbench.action.showAllEditors', editorsByAppearancePrefix),
        showWith(
          'workbench.action.showEditorsInActiveGroup',
          editorsInGroupPrefix,
        ),
        showWith(
          'workbench.action.showAllEditorsByMostRecentlyUsed',
          editorsByRecentlyUsedPrefix,
        ),
        quickNavigate(
          'workbench.action.quickOpenPreviousRecentlyUsedEditor',
          editorsByRecentlyUsedPrefix,
        ),
        quickNavigate(
          'workbench.action.quickOpenLeastRecentlyUsedEditor',
          editorsByRecentlyUsedPrefix,
        ),
        quickNavigate(
          'workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup',
          editorsInGroupPrefix,
          precondition: hasEditors,
        ),
        quickNavigate(
          'workbench.action.quickOpenLeastRecentlyUsedEditorInGroup',
          editorsInGroupPrefix,
          itemActivation: () => IdeQuickPickFocus.last,
          precondition: hasEditors,
        ),
        quickNavigate(
          'workbench.action.openPreviousEditorFromHistory',
          '',
          itemActivation: () =>
              hasEditors(services) ? null : IdeQuickPickFocus.first,
        ),
      ]),
    );
    add(services.get<ContextKeyService>().addProvider(quick.contextKey));

    final registry = services.get<QuickAccessRegistry>();
    add(registry.register(_files(services)));
    add(registry.register(_commands(services)));
    add(registry.register(_gotoLine(services, editors)));
    add(registry.register(_symbols(services)));
    for (final prefix in const [
      editorsByAppearancePrefix,
      editorsInGroupPrefix,
      editorsByRecentlyUsedPrefix,
    ]) {
      add(registry.register(_editors(services, editors, prefix)));
    }
  }

  /// Quick Open's files (no prefix): the workspace's, the recently opened
  /// first.
  static QuickAccessProvider _files(WorkbenchServices services) {
    final explorer = services.get<ExplorerService>();
    final editors = services.get<EditorService>();
    final quick = services.get<QuickInputService>();
    return QuickAccessProvider(
      prefix: '',
      placeholder: (l10n) => l10n.wbQuickFiles,
      contextKey: 'inFilesPicker',
      refresh: () => explorer.fileIndex,
      // A remote project's files come over the connection, all of them:
      // listed again once a while old, not each time.
      onShow: () => unawaited(
        services.find<IdeWorkspace>()?.files is IdeHostFiles
            ? explorer.fileIndex.refreshIfOlder(_remoteListingAge)
            : explorer.fileIndex.refresh(),
      ),
      picks: (context, text) => fileQuickPicks(
        text,
        index: explorer.fileIndex,
        recent:
            services.find<NavigationHistoryService>()?.recentFiles.items ??
            const [],
        onOpen: (path, line, column) => unawaited(
          editors.open(path, line: line, column: column, focusEditor: true),
        ),
        // Accepted in the background: opened (at the line and column if
        // given), the keyboard kept in the quick input.
        onOpenInBackground: (path, line, column) {
          final at = line != null && line > 0
              ? LspPosition(line - 1, math.max(0, (column ?? 1) - 1))
              : null;
          unawaited(
            editors.open(
              path,
              range: at == null ? null : LspRange(at, at),
              afterReveal: () => quick.input?.focusInput(),
            ),
          );
        },
        l10n: context.l10n,
      ),
    );
  }

  /// `>`: the palette's commands, the recently run first.
  static QuickAccessProvider _commands(WorkbenchServices services) {
    final commands = services.get<CommandService>();
    return QuickAccessProvider(
      prefix: '>',
      placeholder: (l10n) => l10n.wbQuickCommands,
      picks: (context, filter) => commandQuickPicks(
        filter,
        commands: commands.palette(),
        recent: commands.recent,
        onRun: commands.run,
        l10n: context.l10n,
      ),
    );
  }

  /// `:`: a line (and column) of the active editor.
  static QuickAccessProvider _gotoLine(
    WorkbenchServices services,
    EditorService editors,
  ) => QuickAccessProvider(
    prefix: ':',
    picks: (context, filter) => gotoLineQuickPicks(
      filter,
      lineCount: services
          .find<IdeWorkspace>()
          ?.active
          ?.model
          .snapshot
          .lineCount,
      currentLine: editors.position.lineNumber,
      currentColumn: editors.caret.value.statusColumn,
      onGo: (line, column) => editors.revealLine(line, column ?? 1),
      l10n: context.l10n,
    ),
  );

  /// `@`: a symbol of the active editor's file.
  static QuickAccessProvider _symbols(WorkbenchServices services) {
    final language = services.get<LanguageService>();
    return QuickAccessProvider(
      prefix: '@',
      placeholder: (l10n) => l10n.wbQuickSymbols,
      refresh: () => language.symbols,
      picks: (context, filter) {
        final symbols = language.symbols;
        final active = services.find<IdeWorkspace>()?.active;
        return symbolQuickPicks(
          filter,
          symbols: symbols != null && symbols.path == active?.path
              ? symbols.symbols
              : const [],
          loaded: symbols?.loaded ?? true,
          supported: symbols != null && active != null && symbols.supported,
          onGo: language.revealSymbol,
          l10n: context.l10n,
        );
      },
    );
  }

  /// `edt `, `edt active `, `edt mru `: the open editors, as their tabs
  /// have them or the recently used first.
  static QuickAccessProvider _editors(
    WorkbenchServices services,
    EditorService editors,
    String prefix,
  ) => QuickAccessProvider(
    prefix: prefix,
    placeholder: (l10n) => l10n.wbQuickEditors,
    contextKey: 'inEditorsPicker',
    picks: (context, filter) {
      final workspace = services.find<IdeWorkspace>();
      if (workspace == null) return const [];
      return editorQuickPicks(
        filter,
        editors: prefix == editorsByAppearancePrefix
            ? workspace.documents
            : services
                      .find<NavigationHistoryService>()
                      ?.editorsByRecentlyUsed() ??
                  workspace.documents,
        root: workspace.root,
        paths: workspace.paths,
        // Brought to the front, with the keyboard unless in the
        // background (upstream `openEditor(editor, {preserveFocus})`).
        onOpen: (doc, {required inBackground}) {
          if (!workspace.documents.contains(doc)) return;
          unawaited(
            editors.select(doc).then((_) {
              if (inBackground || editors.host.context == null) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (editors.host.context != null) editors.focus();
              });
            }),
          );
        },
        l10n: context.l10n,
      );
    },
  );
}
