// The editors' commands (upstream editorActions.ts, editorCommands.ts,
// fileActions.contribution.ts, the find widget's and the status bar's
// pickers) over the window's EditorService, and the text editor's own
// commands among the window's.
//
// Ported from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/browser/parts/editor/editorActions.ts (Open Next /
// Previous Editor, Open Editor at Index, Close Editors…),
// src/vs/workbench/contrib/files/browser/fileActions.contribution.ts
// (Save, Copy Path, Reveal in Finder), src/vs/workbench/browser/parts/
// editor/editorStatus.ts (`ChangeLanguageAction`, `ChangeEOLAction`).
//
// Deviations:
// - One editor group: "in group" and across groups are the same.
// - Find in a markdown preview finds in its source, which it switches to.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';
import '../../../workspace/window_controls.dart';
import '../../ide_quick_input.dart';
import '../../ide_status_bar.dart' show IdeLanguageNames, ideEolLabel;
import '../../ide_tab_bar.dart' show IdeTabAction;
import '../../ide_workspace.dart';
import '../../language_mode.dart';
import '../../services/commands.dart';
import '../../services/configuration.dart';
import '../../services/editors.dart';
import '../../services/explorer.dart';
import '../../services/language.dart';
import '../../services/markdown_preview.dart';
import '../../services/quick_input.dart';
import '../actions.dart';
import '../contributions.dart';
import '../services.dart';
import '../statusbar.dart';

class EditorCommandsContribution extends WorkbenchRegistrations {
  EditorCommandsContribution(WorkbenchServices services) {
    final editors = services.get<EditorService>();
    final config = services.get<ConfigurationService>();
    IdeWorkspace? workspace() => services.find<IdeWorkspace>();
    IdeDocument? active() => workspace()?.active;
    List<IdeDocument> docs() => workspace()?.documents ?? const [];
    bool editing(WorkbenchServices _) => active() != null;
    bool hasEditors(WorkbenchServices _) => docs().isNotEmpty;
    bool several(WorkbenchServices _) => docs().length > 1;

    /// A text document's (not an image's, nor one that could not open).
    bool textual(WorkbenchServices _) => switch (active()) {
      final doc? => !doc.isMedia && doc.openError == null,
      null => false,
    };

    /// [action] on the active document, as its tab's menu has it.
    void onActive(IdeTabAction action) {
      if (active() case final doc?) editors.tabAction(doc, action);
    }

    WorkbenchAction command(
      String id,
      String category,
      String title,
      void Function() run, {
      bool Function(WorkbenchServices services)? precondition,
    }) => WorkbenchAction(
      id: id,
      category: category,
      title: title,
      precondition: precondition,
      run: (_, _) => run(),
    );
    WorkbenchAction catalog(
      String id,
      void Function() run, {
      bool Function(WorkbenchServices services)? precondition,
      bool palette = true,
    }) => WorkbenchAction.catalog(
      id,
      precondition: precondition,
      palette: palette,
      run: (_, _) => run(),
    );
    WorkbenchAction git(
      String id,
      String title,
      void Function() run, {
      required bool Function() enabled,
      String Function()? titleFor,
    }) => WorkbenchAction(
      id: id,
      category: 'Git',
      title: title,
      titleFor: titleFor == null ? null : (_) => titleFor(),
      precondition: (_) => enabled(),
      run: (_, _) => run(),
    );

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.action.editor.changeLanguageMode',
          title: 'Change Language Mode',
          precondition: textual,
          run: (_, _) => unawaited(_changeLanguageMode(services)),
        ),
        WorkbenchAction(
          id: 'workbench.action.editor.changeEOL',
          title: 'Change End of Line Sequence',
          precondition: textual,
          run: (_, _) => _changeEndOfLine(services),
        ),
        WorkbenchAction(
          id: 'actions.find',
          title: 'Find',
          precondition: editing,
          run: (_, _) => _find(services),
        ),
        WorkbenchAction(
          id: 'editor.action.startFindReplaceAction',
          title: 'Replace',
          precondition: editing,
          run: (_, _) => _find(services, replace: true),
        ),
        command(
          'workbench.action.files.save',
          'File',
          'Save',
          () => unawaited(editors.save()),
          precondition: editing,
        ),
        command(
          'workbench.action.files.saveAll',
          'File',
          'Save All',
          () => unawaited(editors.saveAll()),
          precondition: (_) => docs().any((doc) => doc.dirty),
        ),
        command(
          'workbench.action.files.saveAs',
          'File',
          'Save As...',
          () => unawaited(editors.saveAs()),
          precondition: (_) => switch (active()) {
            final doc? =>
              (doc.isFile || doc.isUntitled) &&
                  doc.label == null &&
                  workspace()?.askSavePath != null,
            null => false,
          },
        ),
        command(
          'workbench.action.files.newUntitledFile',
          'File',
          'New Text File',
          editors.newUntitled,
        ),
        command(
          'workbench.action.closeOtherEditors',
          'View',
          'Close Other Editors',
          () => onActive(IdeTabAction.closeOthers),
          precondition: (services) => editing(services) && several(services),
        ),
        command(
          'workbench.action.closeEditorsToTheRight',
          'View',
          'Close Editors to the Right',
          () => onActive(IdeTabAction.closeToTheRight),
          precondition: (_) => active() != null && docs().last != active(),
        ),
        command(
          'workbench.action.closeUnmodifiedEditors',
          'View',
          'Close Saved Editors',
          () => unawaited(
            editors.closeAll([
              for (final doc in docs())
                if (!doc.dirty) doc,
            ]),
          ),
          precondition: (_) => docs().any((doc) => !doc.dirty),
        ),
        command(
          'workbench.action.closeAllEditors',
          'View',
          'Close All Editors',
          () => unawaited(editors.closeAll(docs())),
          precondition: hasEditors,
        ),
        command(
          'workbench.action.nextEditor',
          'View',
          'Open Next Editor',
          () => editors.cycle(1),
          precondition: several,
        ),
        command(
          'workbench.action.previousEditor',
          'View',
          'Open Previous Editor',
          () => editors.cycle(-1),
          precondition: several,
        ),
        // ⌃9 / Alt+9 opens the last editor when there are fewer.
        for (var i = 1; i <= 9; i++)
          command(
            'workbench.action.openEditorAtIndex$i',
            'View',
            'Open Editor at Index $i',
            () => editors.openAt(i == 9 ? -1 : i - 1),
            precondition: hasEditors,
          ),
        command(
          'workbench.action.lastEditorInGroup',
          'View',
          'Open Last Editor in Group',
          () => editors.openAt(-1),
          precondition: hasEditors,
        ),
        command(
          'copyFilePath',
          'File',
          'Copy Path of Active File',
          () => onActive(IdeTabAction.copyPath),
          precondition: editing,
        ),
        command(
          'copyRelativeFilePath',
          'File',
          'Copy Relative Path of Active File',
          () => onActive(IdeTabAction.copyRelativePath),
          precondition: editing,
        ),
        catalog(
          'workbench.action.files.copyPathOfActiveFile',
          () => onActive(IdeTabAction.copyPath),
          precondition: editing,
          palette: false,
        ),
        catalog(
          'workbench.action.nextEditorInGroup',
          () => editors.cycle(1),
          precondition: several,
        ),
        catalog(
          'workbench.action.previousEditorInGroup',
          () => editors.cycle(-1),
          precondition: several,
        ),
        catalog(
          'workbench.action.firstEditorInGroup',
          () => editors.openAt(0),
          precondition: hasEditors,
        ),
        catalog(
          'workbench.action.closeEditorsInGroup',
          () => unawaited(editors.closeAll(docs())),
          precondition: hasEditors,
        ),
        catalog('workbench.action.closeEditorsToTheLeft', () {
          final all = docs();
          unawaited(editors.closeAll(all.sublist(0, all.indexOf(active()!))));
        }, precondition: (_) => active() != null && docs().first != active()),
        catalog(
          'revealFileInOS',
          () => unawaited(
            WindowControls.revealInFileManager(_revealPath(services)!),
          ),
          precondition: (_) =>
              WindowControls.canRevealInFileManager &&
              _revealPath(services) != null,
        ),
        WorkbenchAction(
          id: 'baocode.ide.toggleFormatOnSave',
          category: 'Preferences',
          title: 'Turn On Format on Save',
          titleFor: (_) => config.formatOnSave
              ? 'Turn Off Format on Save'
              : 'Turn On Format on Save',
          precondition: (services) =>
              services.find<LanguageService>()?.languages != null,
          run: (_, _) => config.formatOnSave = !config.formatOnSave,
        ),
        git(
          'baocode.git.toggleAnnotations',
          'Annotate with Git Blame',
          () => editors.editor?.toggleAnnotations(),
          titleFor: () => editors.editor?.annotated ?? false
              ? 'Close Annotations'
              : 'Annotate with Git Blame',
          enabled: () => editors.editor?.canAnnotate ?? false,
        ),
        git(
          'baocode.git.showFileHistory',
          'Show History',
          () => editors.editor?.showHistory(),
          enabled: () => editors.editor?.canShowHistory ?? false,
        ),
        git(
          'baocode.git.showSelectionHistory',
          'Show History for Selection',
          () => editors.editor?.showHistory(selection: true),
          enabled: () => editors.editor?.selectionHistoryLines != null,
        ),
        WorkbenchAction.catalog(
          'git.blame.toggleEditorDecoration',
          precondition: (_) => workspace()?.git != null,
          run: (_, _) => config.gitBlame = !config.gitBlame,
        ),
        command(
          'baocode.ide.retryLanguageServices',
          'Developer',
          'Retry Language Services',
          () => unawaited(editors.editor?.retryLanguageServer()),
          precondition: editing,
        ),
      ]),
    );
    // The text editor's own (Format Document, Go to Definition…), after
    // the workbench's.
    add(
      services.get<CommandService>().addSource(
        () => editors.editor?.editorCommands ?? const [],
      ),
    );
  }

  /// The path Reveal in Finder shows: the explorer's selection while it
  /// has the keyboard, else the active file's.
  static String? _revealPath(WorkbenchServices services) {
    final explorer = services.find<ExplorerService>();
    if (explorer != null && explorer.focusNode.hasFocus) {
      return explorer.controller.selected;
    }
    final active = services.find<IdeWorkspace>()?.active;
    return active != null && (active.isFile || active.isMedia)
        ? active.path
        : null;
  }

  /// Find in a preview: in its source, as the preview has no find.
  static void _find(WorkbenchServices services, {bool replace = false}) {
    final editors = services.get<EditorService>();
    void open() =>
        replace ? editors.editor?.openReplace() : editors.editor?.openFind();
    final markdown = services.find<MarkdownPreviewService>();
    final context = editors.host.context;
    if (markdown != null &&
        context != null &&
        markdown.previewing(services.find<IdeWorkspace>()?.active)) {
      services.get<StatusbarService>().setMessage(
        context.l10n.markdownFindInSource,
        hideAfter: const Duration(seconds: 4),
      );
      unawaited(
        markdown.setPreview(false).then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (editors.host.context != null) open();
          });
        }),
      );
      return;
    }
    open();
  }

  /// Change Language Mode for the active editor's file (see
  /// [languageModePick]).
  static Future<void> _changeLanguageMode(WorkbenchServices services) async {
    final editors = services.get<EditorService>();
    final workspace = services.find<IdeWorkspace>();
    final active = workspace?.active;
    final context = editors.host.context;
    if (active == null || context == null) return;
    final l10n = context.l10n;
    await IdeLanguageNames.load();
    if (editors.host.context == null || !identical(workspace!.active, active)) {
      return;
    }
    services.get<QuickInputService>().showModel(
      languageModePick(l10n, active.path, onPicked: editors.focus),
    );
  }

  /// VS Code's Change End of Line Sequence (`ChangeEOLAction`): LF or CRLF
  /// for every line of the active document, the current one active.
  static void _changeEndOfLine(WorkbenchServices services) {
    final editors = services.get<EditorService>();
    final quick = services.get<QuickInputService>();
    final workspace = services.find<IdeWorkspace>();
    final active = workspace?.active;
    final context = editors.host.context;
    if (active == null || context == null) return;
    final l10n = context.l10n;
    if (active.readOnly) {
      quick.showModel(
        IdeQuickPick(items: [IdeQuickPickItem(label: l10n.wbEditorReadOnly)]),
      );
      return;
    }
    const lf = IdeQuickPickItem(label: 'LF');
    const crlf = IdeQuickPickItem(label: 'CRLF');
    quick.showModel(
      IdeQuickPick(
        items: const [lf, crlf],
        placeholder: l10n.wbSelectEol,
        activeItems: [ideEolLabel(active.model.snapshot) == 'CRLF' ? crlf : lf],
        onDidAccept: (item) {
          if (item == null) return;
          if (!identical(workspace!.active, active)) return;
          editors.editor?.setEndOfLine(identical(item, crlf) ? '\r\n' : '\n');
          editors.focus();
        },
      ),
    );
  }
}
