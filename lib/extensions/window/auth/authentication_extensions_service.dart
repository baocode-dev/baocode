/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/authentication/browser/authenticationExtensionsService.ts
// (`AuthenticationExtensionsService`: sign-in and access requests in the
// Accounts menu with their badge, account and session preferences, the
// account picker).
//
// Deviations:
// - The Accounts menu's request entries (`MenuId.AccountsContext` items
//   with their commands) are [requests], which the accounts menu shows; the
//   badge (`IActivityService.showAccountsActivity`) is [badgeCount].
// - The workspace storage of preferences is an optional JsonStateStore;
//   without one only the app's is used.
// - The account picker is a quick pick through [AuthQuickInput.pickOne]
//   (no `ignoreFocusOut`).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../extension_descriptions.dart';
import '../json_state_store.dart';
import '../window_ports.dart';
import 'authentication_app_services.dart';
import 'authentication_ports.dart';
import 'authentication_service.dart';
import 'authentication_types.dart';

// OAuth2 prohibits a space in a scope: it joins them.
const _scopesListSeparator = ' ';

/// An entry the Accounts menu shows for a request of an extension: sign in
/// (`2_signInRequests`) or grant access (`3_accessRequests`).
final class AuthMenuRequest {
  AuthMenuRequest._(this.kind, this.label, this.run);

  final AuthMenuRequestKind kind;
  final String label;
  final Future<void> Function() run;
}

enum AuthMenuRequestKind { signIn, access }

final class _SessionRequest {
  _SessionRequest(this.entries, this.requestingExtensionIds);

  final List<AuthMenuRequest> entries;
  final List<String> requestingExtensionIds;
}

final class _AccessRequest {
  _AccessRequest(this.entry, this.possibleSessions);

  final AuthMenuRequest entry;
  final List<AuthSession> possibleSessions;
}

final class AuthenticationExtensionsService extends ChangeNotifier {
  AuthenticationExtensionsService({
    required this.authentication,
    required this.app,
    required this.ui,
    this.workspaceStore,
  }) {
    for (final MapEntry(key: parent, value: children)
        in app.inheritAuthAccountPreference.entries) {
      for (final child in children) {
        _childToParent[child] = parent;
      }
    }
    _subscriptions.add(
      authentication.onDidChangeSessions.listen((e) {
        if (e.event.added?.isNotEmpty ?? false) {
          updateNewSessionRequests(e.providerId, e.event.added!);
        }
        if (e.event.removed?.isNotEmpty ?? false) {
          _updateAccessRequests(e.providerId, e.event.removed!);
        }
      }),
    );
    _subscriptions.add(
      authentication.onDidUnregisterAuthenticationProvider.listen((e) {
        final requests = _accessRequests[e.id] ?? {};
        for (final extensionId in [...requests.keys]) {
          _removeAccessRequest(e.id, extensionId);
        }
      }),
    );
  }

  final AuthenticationService authentication;
  final AuthenticationAppServices app;
  final AuthenticationUi ui;

  /// The workspace's storage for its account preferences; null keeps them
  /// for the app only.
  final JsonStateStore? workspaceStore;

  final _childToParent = <String, String>{};
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// provider id → scopes key → request.
  final _signInRequests = <String, Map<String, _SessionRequest>>{};

  /// provider id → extension id → request.
  final _accessRequests = <String, Map<String, _AccessRequest>>{};

  final _onDidChangeAccountPreference =
      StreamController<({String providerId, List<String> extensionIds})>.broadcast(
        sync: true,
      );

  Stream<({String providerId, List<String> extensionIds})>
  get onDidChangeAccountPreference => _onDidChangeAccountPreference.stream;

  /// The Accounts menu's request entries: sign-in requests, then access
  /// requests.
  List<AuthMenuRequest> get requests => [
    for (final provider in _signInRequests.values)
      for (final request in provider.values) ...request.entries,
    for (final provider in _accessRequests.values)
      for (final request in provider.values) request.entry,
  ];

  /// The number on the Accounts badge (`updateBadgeCount`); 0 for none.
  int get badgeCount {
    var count = 0;
    for (final provider in _signInRequests.values) {
      for (final request in provider.values) {
        count += request.requestingExtensionIds.length;
      }
    }
    for (final provider in _accessRequests.values) {
      count += provider.length;
    }
    return count;
  }

  void updateNewSessionRequests(
    String providerId,
    List<AuthSession> addedSessions,
  ) {
    final existing = _signInRequests[providerId];
    if (existing == null) return;
    for (final requestedScopes in [...existing.keys]) {
      final scopes = requestedScopes.split(_scopesListSeparator);
      if (addedSessions.any((s) => scopesMatch(s.scopes, scopes))) {
        existing.remove(requestedScopes);
        if (existing.isEmpty) _signInRequests.remove(providerId);
        notifyListeners();
      }
    }
  }

  void _updateAccessRequests(String providerId, List<AuthSession> removed) {
    final providerRequests = _accessRequests[providerId];
    if (providerRequests == null) return;
    for (final extensionId in [...providerRequests.keys]) {
      final request = providerRequests[extensionId]!;
      for (final session in removed) {
        // Upstream's `if (indexOfSession)` drops the session at an index
        // other than 0 (and the last one for -1).
        final index = request.possibleSessions.indexWhere(
          (s) => s.id == session.id,
        );
        if (index != 0 && request.possibleSessions.isNotEmpty) {
          request.possibleSessions.removeAt(
            index == -1 ? request.possibleSessions.length - 1 : index,
          );
        }
      }
      if (request.possibleSessions.isEmpty) {
        _removeAccessRequest(providerId, extensionId);
      }
    }
  }

  void _removeAccessRequest(String providerId, String extensionId) {
    final providerRequests = _accessRequests[providerId];
    if (providerRequests?.remove(extensionId) != null) {
      if (providerRequests!.isEmpty) _accessRequests.remove(providerId);
      notifyListeners();
    }
  }

  //#region Account/Session Preference

  String _parentOf(String extensionId) {
    final key = extensionKey(extensionId);
    return _childToParent[key] ?? key;
  }

  void updateAccountPreference(
    String extensionId,
    String providerId,
    AuthAccount account,
  ) {
    final parent = _parentOf(extensionId);
    final key = '$parent-$providerId';
    // The workspace's overrides the app's, which new workspaces start with.
    workspaceStore?.set(key, account.label);
    app.store.set(key, account.label);
    final children = app.inheritAuthAccountPreference[parent];
    _onDidChangeAccountPreference.add((
      providerId: providerId,
      extensionIds: children != null ? [parent, ...children] : [parent],
    ));
  }

  String? getAccountPreference(String extensionId, String providerId) {
    final key = '${_parentOf(extensionId)}-$providerId';
    return workspaceStore?.get(key) ?? app.store.get(key);
  }

  void removeAccountPreference(String extensionId, String providerId) {
    final key = '${_parentOf(extensionId)}-$providerId';
    workspaceStore?.remove(key);
    app.store.remove(key);
  }

  String _sessionKey(String providerId, String extensionId, List<String> scopes) =>
      '${extensionKey(extensionId)}-$providerId-${scopes.join(_scopesListSeparator)}';

  void updateSessionPreference(
    String providerId,
    String extensionId,
    AuthSession session,
  ) {
    final key = _sessionKey(providerId, extensionId, session.scopes);
    workspaceStore?.set(key, session.id);
    app.store.set(key, session.id);
  }

  String? getSessionPreference(
    String providerId,
    String extensionId,
    List<String> scopes,
  ) {
    final key = _sessionKey(providerId, extensionId, scopes);
    return workspaceStore?.get(key) ?? app.store.get(key);
  }

  void removeSessionPreference(
    String providerId,
    String extensionId,
    List<String> scopes,
  ) {
    final key = _sessionKey(providerId, extensionId, scopes);
    workspaceStore?.remove(key);
    app.store.remove(key);
  }

  void _updateAccountAndSessionPreferences(
    String providerId,
    String extensionId,
    AuthSession session,
  ) {
    updateAccountPreference(extensionId, providerId, session.account);
    updateSessionPreference(providerId, extensionId, session);
  }

  //#endregion

  Future<bool> _showGetSessionPrompt(
    AuthenticationProvider provider,
    String accountName,
    String extensionId,
    String extensionName,
  ) async {
    final l10n = ui.l10n();
    final answer = await ui.dialogs.prompt(
      severity: ExtensionSeverity.info,
      message: l10n.windowAuthConfirmAccess(
        extensionName,
        provider.label,
        accountName,
      ),
      buttons: [l10n.windowAuthAllow, l10n.windowAuthDeny],
      cancel: l10n.commonCancel,
    );
    // 0 Allow, 1 Deny, null Cancel.
    if (answer.button != null) {
      app.access.updateAllowedExtensions(provider.id, accountName, [
        AllowedExtension(
          id: extensionId,
          name: extensionName,
          allowed: answer.button == 0,
        ),
      ]);
      _removeAccessRequest(provider.id, extensionId);
    }
    return answer.button == 0;
  }

  /// Asks which of the accounts [extensionId] is to use, only when there
  /// are sessions to choose between.
  Future<AuthSession> selectSession(
    String providerId,
    String extensionId,
    String extensionName,
    Object? scopeListOrRequest,
    List<AuthSession> availableSessions,
  ) async {
    final allAccounts = await authentication.getAccounts(providerId);
    if (allAccounts.isEmpty) {
      throw const AuthenticationError('No accounts available');
    }
    final l10n = ui.l10n();
    final accountsWithSessions = <String>{};
    final items = <({String label, AuthSession? session, AuthAccount? account})>[
      for (final session in availableSessions)
        if (accountsWithSessions.add(session.account.label))
          (label: session.account.label, session: session, account: null),
    ];
    for (final account in allAccounts) {
      if (!accountsWithSessions.contains(account.label)) {
        items.add((label: account.label, session: null, account: account));
      }
    }
    items.add((label: l10n.windowAuthUseOtherAccount, session: null, account: null));
    final picked = await ui.quickInput.pickOne(
      title: l10n.windowAuthSelectAccount(
        extensionName,
        authentication.getProvider(providerId).label,
      ),
      placeholder: l10n.windowAuthSelectAccountPlaceholder(extensionName),
      items: [for (final item in items) AuthPickItem(item.label)],
    );
    if (picked == null) {
      throw const AuthenticationError('User did not consent to account access');
    }
    final item = items[picked];
    final session =
        item.session ??
        await authentication.createSession(
          providerId,
          scopeListOrRequest,
          account: item.account,
        );
    app.access.updateAllowedExtensions(providerId, session.account.label, [
      AllowedExtension(id: extensionId, name: extensionName, allowed: true),
    ]);
    _updateAccountAndSessionPreferences(providerId, extensionId, session);
    _removeAccessRequest(providerId, extensionId);
    return session;
  }

  Future<void> _completeSessionAccessRequest(
    AuthenticationProvider provider,
    String extensionId,
    String extensionName,
    Object? scopeListOrRequest,
  ) async {
    final existing = _accessRequests[provider.id]?[extensionId];
    if (existing == null) return;
    final possibleSessions = existing.possibleSessions;
    AuthSession? session;
    if (provider.supportsMultipleAccounts) {
      try {
        session = await selectSession(
          provider.id,
          extensionId,
          extensionName,
          scopeListOrRequest,
          possibleSessions,
        );
      } on Object {
        // Cancelled.
      }
    } else if (await _showGetSessionPrompt(
      provider,
      possibleSessions.first.account.label,
      extensionId,
      extensionName,
    )) {
      session = possibleSessions.first;
    }
    if (session != null) {
      app.usage.addAccountUsage(
        provider.id,
        session.account.label,
        session.scopes,
        extensionId,
        extensionName,
      );
    }
  }

  /// Adds "Grant access to {provider} for {extension}..." to the Accounts
  /// menu: [extensionId] may use one of [possibleSessions] once allowed.
  void requestSessionAccess(
    String providerId,
    String extensionId,
    String extensionName,
    Object? scopeListOrRequest,
    List<AuthSession> possibleSessions,
  ) {
    final providerRequests = _accessRequests[providerId] ?? {};
    if (providerRequests.containsKey(extensionId)) return;
    final provider = authentication.getProvider(providerId);
    final entry = AuthMenuRequest._(
      AuthMenuRequestKind.access,
      ui.l10n().windowAuthAccessRequest(provider.label, extensionName),
      () => _completeSessionAccessRequest(
        provider,
        extensionId,
        extensionName,
        scopeListOrRequest,
      ),
    );
    providerRequests[extensionId] = _AccessRequest(entry, [
      ...possibleSessions,
    ]);
    _accessRequests[providerId] = providerRequests;
    notifyListeners();
  }

  /// Adds "Sign in with {provider} to use {extension}" to the Accounts menu.
  Future<void> requestNewSession(
    String providerId,
    Object? scopeListOrRequest,
    String extensionId,
    String extensionName,
  ) async {
    if (!authentication.isAuthenticationProviderRegistered(providerId)) {
      // Activation was asked for; wait for the provider to register.
      await authentication.onDidRegisterAuthenticationProvider.firstWhere(
        (e) => e.id == providerId,
      );
    }
    final AuthenticationProvider provider;
    try {
      provider = authentication.getProvider(providerId);
    } on Object {
      return;
    }
    final providerRequests = _signInRequests[providerId];
    final key = switch (scopeListOrRequest) {
      final Map<Object?, Object?> request
          when isWwwAuthenticateRequest(request) =>
        '${request['wwwAuthenticate']}:'
            '${scopesOf(request)?.join(_scopesListSeparator) ?? ''}',
      _ => (scopesOf(scopeListOrRequest) ?? const []).join(
        _scopesListSeparator,
      ),
    };
    if (providerRequests?[key]?.requestingExtensionIds.contains(extensionId) ??
        false) {
      return;
    }
    final entry = AuthMenuRequest._(
      AuthMenuRequestKind.signIn,
      ui.l10n().windowAuthSignInRequest(provider.label, extensionName),
      () async {
        final session = await authentication.createSession(
          providerId,
          scopeListOrRequest,
        );
        app.access.updateAllowedExtensions(providerId, session.account.label, [
          AllowedExtension(id: extensionId, name: extensionName, allowed: true),
        ]);
        _updateAccountAndSessionPreferences(providerId, extensionId, session);
      },
    );
    final requests = providerRequests ?? {};
    final existing = requests[key];
    requests[key] = _SessionRequest(
      [...?existing?.entries, entry],
      [...?existing?.requestingExtensionIds, extensionId],
    );
    _signInRequests[providerId] = requests;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_onDidChangeAccountPreference.close());
    super.dispose();
  }
}
