// The language servers' part of the workbench: the Problems and References
// views' commands and context keys (markers.contribution.ts, the
// references-view extension's), Go to Next Problem in Files, and the status
// bar's problems and language status (`MarkersStatusBarContributions`,
// `LanguageStatus`), over the window's Language, Problems and References
// services.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../keybindings/keybinding_service.dart';
import '../../../l10n/l10n.dart';
import '../../ide_status_bar.dart';
import '../../ide_workspace.dart';
import '../../lsp_ui/language_status.dart';
import '../../lsp_ui/diagnostics.dart' show ideDiagnosticCounts;
import '../../services/language.dart';
import '../../services/problems.dart';
import '../../services/references.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';
import '../statusbar.dart';

/// The status bar's problems: right of the branch.
const problemsPriority = 70.0;

/// The active file's language status: right of the problems.
const languageStatusPriority = 60.0;

class LanguageContribution extends WorkbenchRegistrations {
  LanguageContribution(WorkbenchServices services) {
    final language = services.get<LanguageService>();
    final problems = services.get<ProblemsService>();
    final references = services.get<ReferencesService>();
    bool hasServers(WorkbenchServices _) => language.languages != null;
    bool problemFocused(WorkbenchServices _) =>
        problems.focused && problems.list.focused != null;
    bool hasReferences(WorkbenchServices _) => references.hasResult;

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.actions.view.problems',
          category: 'View',
          title: 'Toggle Problems',
          run: (_, _) => problems.toggle(),
        ),
        WorkbenchAction(
          id: 'editor.action.marker.nextInFiles',
          title: 'Go to Next Problem in Files (Error, Warning, Info)',
          precondition: hasServers,
          run: (_, _) => problems.go(next: true),
        ),
        WorkbenchAction(
          id: 'editor.action.marker.prevInFiles',
          title: 'Go to Previous Problem in Files (Error, Warning, Info)',
          precondition: hasServers,
          run: (_, _) => problems.go(next: false),
        ),
        WorkbenchAction.catalog(
          'workbench.action.problems.focus',
          run: (_, _) => problems.focus(),
        ),
        WorkbenchAction.catalog(
          'references-view.clear',
          precondition: hasReferences,
          run: (_, _) => references.clear(),
        ),
        // For keybindings only (upstream's are not in the palette).
        WorkbenchAction.catalog(
          'problems.action.open',
          palette: false,
          precondition: (_) => problems.focused && problems.list.entryFocused,
          run: (_, _) => problems.openFocused(),
        ),
        WorkbenchAction.catalog(
          'problems.action.copy',
          palette: false,
          precondition: problemFocused,
          run: (_, _) => unawaited(problems.copy()),
        ),
        WorkbenchAction.catalog(
          'problems.action.copyMessage',
          palette: false,
          precondition: problemFocused,
          run: (_, _) => unawaited(problems.copyMessage()),
        ),
        WorkbenchAction.catalog(
          'references-view.next',
          palette: false,
          precondition: hasReferences,
          run: (_, _) => references.go(next: true),
        ),
        WorkbenchAction.catalog(
          'references-view.prev',
          palette: false,
          precondition: hasReferences,
          run: (_, _) => references.go(next: false),
        ),
      ]),
    );
    final keys = services.get<ContextKeyService>();
    add(keys.addProvider(problems.contextKey));
    add(keys.addProvider(references.contextKey));
    add(
      keys.addProvider(
        (key) => key == 'editorHasFormattingProvider'
            ? language.languages != null
            : null,
      ),
    );

    final statusbar = services.get<StatusbarService>();
    final changes = Listenable.merge([language, KeybindingService.instance]);
    add(
      statusbar.addEntry(
        'status.problems',
        StatusbarAlignment.left,
        priority: problemsPriority,
        changes: changes,
        (context) {
          final languages = language.languages;
          if (languages == null) return null;
          final l10n = context.l10n;
          final counts = ideDiagnosticCounts(languages.allDiagnostics);
          return IdeStatusBarItem(
            '\$(error) ${counts.errors} \$(warning) ${counts.warnings}'
            '${counts.infos > 0 ? ' \$(info) ${counts.infos}' : ''}',
            tooltip: KeybindingService.instance.titleWithKeybinding(
              counts.errors + counts.warnings + counts.infos == 0
                  ? l10n.wbNoProblems
                  : counts.infos > 0
                  ? l10n.wbProblemCountsInfos(
                      counts.errors,
                      counts.warnings,
                      counts.infos,
                    )
                  : l10n.wbProblemCounts(counts.errors, counts.warnings),
              'workbench.actions.view.problems',
            ),
            onTap: problems.togglePanel,
          );
        },
      ).dispose,
    );
    add(
      statusbar
          .addEntries(
            'status.languageStatus',
            StatusbarAlignment.left,
            priority: languageStatusPriority,
            changes: changes,
            (context) => switch ((
              language.languages,
              services.find<IdeWorkspace>()?.active,
            )) {
              (final languages?, final doc?) => ideLanguageStatusItems(
                languages,
                doc.path,
                l10n: context.l10n,
              ),
              _ => const [],
            },
          )
          .dispose,
    );
  }
}
