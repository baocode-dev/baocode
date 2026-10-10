/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Accounts menu and the quick inputs the authentication flows use, on
// BaoCode's own widgets. Ported from VS Code
// 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/accounts/browser/accounts.contribution.ts
// (`registerAccountsActivity`: the Accounts menu — the accounts, then
// "Sign out of N Accounts" — and its badge) and
// src/vs/workbench/contrib/accounts/browser/manageTrustedExtensions.ts
// ("Manage Trusted Extensions": the extensions allowed to use an account).
//
// Deviations: the menu is an item of the app's status bar plus
// `showIdeMenu` (upstream has an activity-bar item and a native menu); its
// accounts come from the providers' `getSessions` (the service keeps no
// account list of its own); "Sign out" asks per account through the app's
// dialog; Manage Trusted Extensions lists them in a dialog rather than a
// quick pick with a trash button.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ide/ide_dialog.dart';
import '../../../ide/ide_menu.dart';
import '../../../ide/ide_status_bar.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/codicons.dart';
import 'authentication_app_services.dart';
import 'authentication_extensions_service.dart';
import 'authentication_ports.dart';
import 'authentication_service.dart';
import 'authentication_types.dart';

/// The accounts the menu shows, by provider: read from the providers'
/// sessions as they change.
final class AccountsMenuModel extends ChangeNotifier {
  AccountsMenuModel({
    required this.authentication,
    required this.app,
    required this.extensions,
  }) {
    authentication.onDidChangeSessions.listen((_) => unawaited(refresh()));
    authentication.onDidRegisterAuthenticationProvider.listen(
      (_) => unawaited(refresh()),
    );
    authentication.onDidUnregisterAuthenticationProvider.listen((_) {
      _accounts.removeWhere((id, _) => !authentication.getProviderIds().contains(id));
      notifyListeners();
    });
    unawaited(refresh());
  }

  final AuthenticationService authentication;
  final AuthenticationAppServices app;
  final AuthenticationExtensionsService extensions;

  final Map<String, List<AuthAccount>> _accounts = {};

  /// Providers whose accounts the menu leaves out (the app's own).
  final Set<String> hiddenProviders = {'vscode.github-authentication'};

  /// The accounts of every provider, in the providers' order.
  List<({AuthenticationProvider provider, List<AuthAccount> accounts})> get
  accounts => [
    for (final id in authentication.getProviderIds())
      if (!hiddenProviders.contains(id) &&
          !id.startsWith(internalAuthProviderPrefix))
        (provider: authentication.getProvider(id), accounts: _accounts[id] ?? const []),
  ];

  /// Reads every provider's accounts.
  Future<void> refresh() async {
    if (authentication.isDisposed) return;
    for (final id in authentication.getProviderIds()) {
      if (id.startsWith(internalAuthProviderPrefix)) continue;
      try {
        _accounts[id] = await authentication.getAccounts(id);
      } on AuthenticationError {
        _accounts.remove(id);
      }
    }
    notifyListeners();
  }

  /// The requests extensions made (`AuthenticationExtensionsService`).
  List<AuthMenuRequest> get requests => extensions.requests;

  /// What the badge counts: the pending requests.
  int get badgeCount => requests.length;
}

/// The status bar's entry for the Accounts menu.
IdeStatusBarItem accountsStatusItem(
  BuildContext context,
  AccountsMenuModel model,
) {
  final l10n = context.l10n;
  final accounts = [
    for (final entry in model.accounts)
      if (entry.accounts.isNotEmpty) entry,
  ];
  final count = accounts.fold<int>(0, (n, e) => n + e.accounts.length);
  return IdeStatusBarItem(
    '',
    icon: Codicons.account,
    tooltip: count == 0 ? l10n.windowAuthAccounts : l10n.windowAuthSignOutMenu(count),
    semanticsLabel: model.badgeCount == 0
        ? l10n.windowAuthAccounts
        : l10n.windowAuthAccountsWithRequests(model.badgeCount),
    onContextMenu: accounts.isEmpty && model.requests.isEmpty
        ? null
        : (position) => unawaited(
            showIdeMenu(
              context,
              position: position,
              entries: _entries(context, model, accounts),
            ),
          ),
    onTap: accounts.isEmpty && model.requests.isEmpty
        ? null
        : () {
            final box = context.findRenderObject();
            if (box is! RenderBox) return;
            unawaited(
              showIdeMenu(
                context,
                anchor: box.localToGlobal(Offset.zero) & box.size,
                entries: _entries(context, model, accounts),
              ),
            );
          },
  );
}

List<IdeMenuEntry> _entries(
  BuildContext context,
  AccountsMenuModel model,
  List<({AuthenticationProvider provider, List<AuthAccount> accounts})> accounts,
) {
  final l10n = context.l10n;
  return ideMenuGroups([
    <IdeMenuEntry>[
      for (final entry in accounts)
        for (final account in entry.accounts)
          IdeMenuAction(
            '${account.label} (${entry.provider.label})',
            submenu: [
              IdeMenuAction(
                l10n.windowAuthSignOut,
                onSelected: () => unawaited(
                  _signOutAccount(context, model, entry.provider, account),
                ),
              ),
            ],
          ),
    ],
    <IdeMenuEntry>[
      for (final request in model.requests)
        IdeMenuAction(
          request.label,
          onSelected: () => unawaited(request.run()),
        ),
    ],
    <IdeMenuEntry>[
      IdeMenuAction(
        l10n.windowAuthManageTrusted,
        onSelected: () => unawaited(_manageTrustedExtensions(context, model)),
      ),
      if (accounts.isNotEmpty)
        IdeMenuAction(
          l10n.windowAuthSignOutAll,
          onSelected: () => unawaited(_signOutAll(context, model, accounts)),
        ),
    ],
  ]);
}

/// Signs the one account [account] out of [provider].
Future<void> _signOutAccount(
  BuildContext context,
  AccountsMenuModel model,
  AuthenticationProvider provider,
  AuthAccount account,
) async {
  final l10n = context.l10n;
  final answer = await showIdeDialog(
    context,
    message: l10n.windowAuthSignOutConfirm(account.label, provider.label),
    buttons: [l10n.windowAuthSignOut],
    type: IdeDialogType.question,
  );
  if (answer != 0) return;
  for (final session in await _sessionsOf(model, provider.id)) {
    if (session.account.label != account.label) continue;
    await model.authentication.removeSession(provider.id, session.id);
  }
}

/// Signs every account of every provider out, asking per account.
Future<void> _signOutAll(
  BuildContext context,
  AccountsMenuModel model,
  List<({AuthenticationProvider provider, List<AuthAccount> accounts})> accounts,
) async {
  for (final entry in accounts) {
    for (final account in entry.accounts) {
      if (!context.mounted) return;
      await _signOutAccount(context, model, entry.provider, account);
    }
  }
}

Future<List<AuthSession>> _sessionsOf(
  AccountsMenuModel model,
  String providerId,
) async {
  try {
    return await model.authentication.getSessions(providerId);
  } on AuthenticationError {
    return const [];
  }
}

/// "Manage Trusted Extensions": the extensions allowed to use an account,
/// with a way to remove one.
Future<void> _manageTrustedExtensions(
  BuildContext context,
  AccountsMenuModel model,
) async {
  final l10n = context.l10n;
  final allowed = <({String providerId, String account, AllowedExtension e})>[
    for (final entry in model.accounts)
      for (final account in entry.accounts)
        for (final extension in model.app.access.readAllowedExtensions(
          entry.provider.id,
          account.label,
        ))
          (
            providerId: entry.provider.id,
            account: account.label,
            e: extension,
          ),
  ];
  if (allowed.isEmpty) {
    await showIdeDialog(
      context,
      message: l10n.windowAuthNoTrustedExtensions,
      buttons: [l10n.commonOk],
      cancel: '',
      type: IdeDialogType.info,
    );
    return;
  }
  final answer = await showIdeDialog(
    context,
    message: l10n.windowAuthManageTrusted,
    detail: [
      for (final entry in allowed)
        '${entry.e.name} — ${entry.providerId}/${entry.account}',
    ].join('\n'),
    buttons: [l10n.windowAuthRemoveAllTrusted],
    cancel: l10n.commonCancel,
    type: IdeDialogType.info,
  );
  if (answer != 0) return;
  for (final entry in allowed) {
    model.app.access.updateAllowedExtensions(
      entry.providerId,
      entry.account,
      [
        AllowedExtension(id: entry.e.id, name: entry.e.name, allowed: false),
      ],
    );
  }
}

/// The pickers the authentication flows use, on the app's dialogs (the
/// account picker, upstream's quick pick).
final class DialogAuthQuickInput implements AuthQuickInput {
  const DialogAuthQuickInput(this.context);

  final BuildContext Function() context;

  @override
  Future<int?> pickOne({
    String? title,
    String? placeholder,
    required List<AuthPickItem> items,
  }) async {
    final selectable = [
      for (final (index, item) in items.indexed)
        if (!item.separator && !item.disabled) index,
    ];
    if (selectable.isEmpty) return null;
    final answer = await showIdeDialog(
      context(),
      message: title ?? placeholder ?? '',
      detail: [
        for (final item in items)
          if (!item.separator && item.description != null)
            '${item.label} — ${item.description}',
      ].join('\n'),
      buttons: [for (final index in selectable) items[index].label],
      cancel: context().l10n.commonCancel,
      type: IdeDialogType.info,
    );
    return answer == null ? null : selectable[answer];
  }

  @override
  Future<Set<int>?> pickMany({
    String? title,
    String? placeholder,
    required List<AuthPickItem> items,
  }) async {
    final index = await pickOne(
      title: title,
      placeholder: placeholder,
      items: items,
    );
    return index == null ? null : {index};
  }

  @override
  Future<String?> input({
    String? title,
    String? prompt,
    String? placeholder,
    bool password = false,
    String? Function(String value)? validate,
  }) async {
    final result = await showIdeInputDialog(
      context(),
      message: title ?? prompt ?? '',
      inputs: [IdeDialogInput(placeholder: placeholder, obscure: password)],
      buttons: [context().l10n.commonOk],
      cancel: context().l10n.commonCancel,
      type: IdeDialogType.info,
    );
    if (result == null || result.values.isEmpty) return null;
    return result.values.first;
  }
}

/// [AuthClipboard] on Flutter's clipboard (the app's adapter passes
/// `Clipboard.setData`).
final class FunctionAuthClipboard implements AuthClipboard {
  const FunctionAuthClipboard(this.write);

  final Future<void> Function(String text) write;

  @override
  Future<void> writeText(String text) => write(text);
}
