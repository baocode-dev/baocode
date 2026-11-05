// The status bar's items (upstream statusbarPart.ts): the status bar
// service's entries, and those not yet its (the remote indicator, the
// message, the bell), with the priorities they will have.

import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';
import '../../ide_notifications.dart';
import '../../ide_status_bar.dart';
import '../../services/editors.dart';
import '../../services/language.dart';
import '../options.dart';
import '../services.dart';
import '../statusbar.dart';

/// What changes the status bar: typing moves the caret and edits the
/// document, and the status bar is all that shows either; as it is all
/// that shows a language server's progress.
Listenable workbenchStatusChanges(
  WorkbenchServices services,
  WorkbenchOptions options,
) => Listenable.merge([
  options.workspace,
  options.workspace.edits,
  options.workspace.notifications,
  options.remote,
  services.get<EditorService>().caret,
  services.get<StatusbarService>(),
  services.get<LanguageService>(),
  services.get<LanguageService>().languages?.progressChanges,
]);

/// The bar's items now, left and right.
IdeStatusBar workbenchStatusBar(
  BuildContext context,
  WorkbenchServices services,
  WorkbenchOptions options,
) {
  final statusbar = services.get<StatusbarService>();
  final l10n = context.l10n;
  // The entries not yet the status bar service's, with the priorities
  // they will have (the greater, the further left).
  final left = <(double, IdeStatusBarItem)>[
    if (options.remote?.item(context) case final item?) (100, item),
    if (statusbar.message case final message?) (50, IdeStatusBarItem(message)),
  ];
  final bell = ideNotificationsStatusItem(
    options.workspace.notifications,
    l10n: l10n,
  );
  final leftItems = mergeStatusbarItems(
    left,
    statusbar.entries(context, StatusbarAlignment.left),
  );
  return IdeStatusBar(
    left: leftItems,
    right: mergeStatusbarItems([
      (-1000, bell),
    ], statusbar.entries(context, StatusbarAlignment.right)),
  );
}
