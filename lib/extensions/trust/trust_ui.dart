// The workspace trust dialogs and status indicator, as VS Code's own
// (`workspace.contribution.ts`'s `WorkspaceTrustUXHandler`,
// `WorkspaceTrustRequestHandler` and the startup modal).
//
// The app's dialogs (lib/ide/ide_dialog.dart) draw them: the startup
// question with its "trust the parent folder" checkbox, an extension's
// request with its buttons, and the folder's, from
// `onDidInitiateResourcesTrustRequest`.

import 'package:flutter/widgets.dart';

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/ide_dialog.dart';
import '../../ide/ide_status_bar.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import 'workspace_trust.dart';

/// [WorkspaceTrustPrompt] on the app's dialogs. [contextOf] gives the
/// context to show them in (the workbench's).
final class IdeWorkspaceTrustPrompt implements WorkspaceTrustPrompt {
  IdeWorkspaceTrustPrompt({
    required this.contextOf,
    this.onManage,
    this.labelOf,
  });

  final BuildContext Function() contextOf;

  /// The "Manage" button's action (opening the trust settings).
  final void Function()? onManage;

  /// How the workspace names itself in the dialog's detail line.
  final String Function()? labelOf;

  @override
  bool get canManage => onManage != null;

  @override
  void manage() => onManage?.call();

  @override
  Future<({bool trust, bool trustParent})> startup({
    required bool workspace,
    required String label,
    String? parentFolderName,
  }) async {
    final l10n = contextOf().l10n;
    final detail = [
      workspace
          ? l10n.trustStartupDetailsWorkspace
          : l10n.trustStartupDetailsFolder,
      l10n.trustLearnMore,
      if (label.isNotEmpty) label,
    ].join('\n');
    final result = await showIdeInputDialog(
      contextOf(),
      type: IdeDialogType.info,
      message: workspace ? l10n.trustWorkspaceTitle : l10n.trustFolderTitle,
      detail: detail,
      buttons: [
        l10n.trustOption,
        l10n.dontTrustOption,
      ],
      checkbox: parentFolderName == null
          ? null
          : l10n.trustParentFolder(parentFolderName),
      // Upstream: the modal cannot be dismissed without answering.
      cancel: null,
    );
    return switch (result?.button) {
      0 => (trust: true, trustParent: result?.checked ?? false),
      _ => (trust: false, trustParent: false),
    };
  }

  @override
  Future<String?> request({
    required bool workspace,
    String? message,
    required List<WorkspaceTrustRequestButton> buttons,
  }) async {
    final l10n = contextOf().l10n;
    final visible = [
      for (final b in buttons)
        if (b.type != 'Cancel')
          (
            type: b.type,
            label: switch (b.type) {
              'ContinueWithTrust' => workspace
                  ? l10n.trustGrantWorkspace
                  : l10n.trustGrantFolder,
              'Manage' => l10n.trustManage,
              _ => b.label.isEmpty ? l10n.trustManage : b.label,
            },
          ),
    ];
    final result = await showIdeDialog(
      contextOf(),
      type: IdeDialogType.info,
      message: workspace ? l10n.trustWorkspaceTitle : l10n.trustImmediateRequestTitle,
      detail: [
        message?.isNotEmpty == true
            ? message!
            : l10n.trustImmediateRequestDetails,
        l10n.trustLearnMore,
      ].join('\n'),
      buttons: [for (final b in visible) b.label],
    );
    if (result == null || result >= visible.length) return null;
    return visible[result].type;
  }

  @override
  Future<bool> resource(VsUri uri, {String? message}) async {
    final l10n = contextOf().l10n;
    final result = await showIdeDialog(
      contextOf(),
      type: IdeDialogType.info,
      message: l10n.trustResourcesTitle,
      detail: [
        message?.isNotEmpty == true ? message! : l10n.trustResourcesDetails,
        l10n.trustResourcesLearnMore,
        uri.fsPath(),
      ].join('\n'),
      buttons: [l10n.trustGrantFolder],
    );
    return result == 0;
  }
}

/// The status bar's Restricted Mode item: a shield and the text (VS
/// Code's `status.workspaceTrust` entry); null when the workspace is
/// trusted (or trust is off).
IdeStatusBarItem? workspaceTrustStatusItem(
  WorkspaceTrustService trust,
  AppLocalizations l10n, {
  required VoidCallback onTrust,
}) {
  if (!trust.isWorkspaceTrustEnabled || trust.isWorkspaceTrusted) return null;
  return IdeStatusBarItem(
    l10n.trustRestrictedMode,
    icon: Codicons.shield,
    tooltip: l10n.trustRestrictedModeTooltip,
    onTap: onTrust,
  );
}
