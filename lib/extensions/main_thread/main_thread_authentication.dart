/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadAuthentication.ts (all of the
// shape's methods): `$registerAuthenticationProvider`/
// `$unregisterAuthenticationProvider`/`$ensureProvider` (activation on
// `onAuthenticationRequest:<id>`), `$sendDidChangeSessions`,
// `$getSession`/`$getAccounts`/`$removeSession` with `doGetSession`'s
// flows (the invalid option combinations, the account preference, the
// allowed-extension checks, `loginPrompt`, `selectSession`,
// `continueWithIncorrectAccountPrompt`, `updateNewSessionRequests`),
// `$waitForUriHandler` (the URL service's handler and its five-minute
// timeout), `$showContinueNotification`, `$showDeviceCodeModal`,
// `$promptForClientRegistration`/`$promptForResourceClientSecret`, and the
// dynamic providers (`$registerDynamicAuthenticationProvider`,
// `$setSessionsForDynamicAuthProvider`, `$sendDidChangeDynamicProviderInfo`).
//
// Deviations: the interactive dialogs and quick picks go through the
// AuthenticationUi ports (the app's dialogs and IDE menu) rather than
// upstream's dialog/quick-input services, so `$promptForClientRegistration`
// asks for both values in one dialog instead of two input boxes;
// `learnMore` opens the address through the app's URL launcher;
// telemetry (`authentication.providerUsage`) is not sent, as telemetry is
// off; the accounts menu is the app's own (see the auth UI).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/ide_notifications.dart';
import '../extension_host_service_io.dart';
import '../host/extension_host_manager.dart' show ActivationKind;
import '../window/auth/authentication_access_service.dart';
import '../window/auth/authentication_app_services.dart';
import '../window/auth/authentication_extensions_service.dart';
import '../window/auth/authentication_ports.dart';
import '../window/auth/authentication_service.dart';
import '../window/auth/authentication_types.dart';
import '../window/url_service.dart';
import '../window/window_ports.dart' show ExtensionSeverity;
import 'main_thread_context.dart';

/// What the authentication shapes need from the app: the provider registry
/// (one per extension host), the app-wide services, and the UI's ports.
final class ExtensionAuthenticationUi {
  const ExtensionAuthenticationUi({
    required this.authentication,
    required this.app,
    required this.extensions,
    required this.ui,
    this.urls,
  });

  final AuthenticationService authentication;
  final AuthenticationAppServices app;
  final AuthenticationExtensionsService extensions;
  final AuthenticationUi ui;

  /// The app's URI handling (for `$waitForUriHandler`); null waits for
  /// nothing and the call fails after its timeout.
  final ExtensionUrlService? urls;
}

/// A `vscode.authentication` provider registered by an extension: the
/// shape forwards every call to the extension host
/// (`ExtHostAuthenticationProxy`).
final class _ExtHostAuthenticationProvider implements AuthenticationProvider {
  _ExtHostAuthenticationProvider({
    required this.id,
    required this.label,
    required this.supportsMultipleAccounts,
    required this.authorizationServers,
    required this.resourceServer,
    required this.proxy,
    required this.clientId,
    required this.clientSecret,
    this.dynamic = false,
  });

  /// The session's `ExtHostAuthentication` (the extension host side of
  /// the provider).
  final ExtHostAuthenticationProxy proxy;
  final String clientId;
  final String clientSecret;
  final bool dynamic;

  @override
  final String id;

  @override
  final String label;

  @override
  final bool supportsMultipleAccounts;

  @override
  final List<VsUri> authorizationServers;

  @override
  final VsUri? resourceServer;

  @override
  bool get supportsChallenges => true;

  final _sessions = StreamController<AuthSessionsChangeEvent>.broadcast();

  @override
  Stream<AuthSessionsChangeEvent> get onDidChangeSessions => _sessions.stream;

  /// `$sendDidChangeSessions`.
  void sessionsChanged(AuthSessionsChangeEvent event) {
    if (!_sessions.isClosed) _sessions.add(event);
  }

  /// A provider's own consent message; the host answers `$getSession`, so
  /// the app's default wording is used.
  @override
  String? confirmation(String extensionName, bool recreatingSession) => null;

  @override
  Future<List<AuthSession>> getSessions(
    List<String>? scopes,
    Map<String, Object?> options,
  ) async => authSessionsFrom(
    await proxy.$getSessions(id, scopes, options),
  );

  @override
  Future<AuthSession> createSession(
    List<String> scopes,
    Map<String, Object?> options,
  ) async => AuthSession(
    (await proxy.$createSession(id, scopes, options)).cast<String, Object?>(),
  );

  @override
  Future<void> removeSession(String sessionId) =>
      proxy.$removeSession(id, sessionId);

  @override
  Future<List<AuthSession>> getSessionsFromChallenges(
    Map<String, Object?> constraint,
    Map<String, Object?> options,
  ) async => authSessionsFrom(
    await proxy.$getSessionsFromChallenges(id, constraint, options),
  );

  @override
  Future<AuthSession> createSessionFromChallenges(
    Map<String, Object?> constraint,
    Map<String, Object?> options,
  ) async => AuthSession(
    (await proxy.$createSessionFromChallenges(id, constraint, options))
        .cast<String, Object?>(),
  );

  @override
  void dispose() {
    if (!_sessions.isClosed) unawaited(_sessions.close());
  }
}

final class MainThreadAuthentication
    extends MainThreadAuthenticationUnsupported {
  MainThreadAuthentication(this._ui, this._proxy, this._host) {
    // ignore: prefer_initializing_formals
    // ignore: prefer_initializing_formals
    _subscriptions.add(
      _ui.authentication.onDidChangeSessions.listen((e) {
        unawaited(
          _proxy
              .$onDidChangeAuthenticationSessions(e.providerId, e.label)
              .catchError((Object _) {}),
        );
      }),
    );
    // Unregistered providers are told (upstream's
    // `onDidUnregisterAuthenticationProvider`); a registration needs no
    // event, since the registering extension is the one that asked.
    _subscriptions.add(
      _ui.authentication.onDidUnregisterAuthenticationProvider.listen((e) {
        _providers.remove(e.id);
        unawaited(
          _proxy.$onDidUnregisterAuthenticationProvider(e.id).catchError(
            (Object _) {},
          ),
        );
      }),
    );
  }

  final ExtensionAuthenticationUi _ui;
  final ExtHostAuthenticationProxy _proxy;
  final ExtensionHostService _host;

  AuthenticationAccessService get _access => _ui.app.access;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final Map<String, _ExtHostAuthenticationProvider> _providers = {};

  static RpcActor customer(MainThreadContext context) {
    final ui = context.service<ExtensionAuthenticationUi>();
    final host = context.service<ExtensionHostService>();
    ui.authentication.host ??= _HostExtensions(host);
    final actor = MainThreadAuthentication(
      ui,
      ExtHostAuthenticationProxy(context.rpc),
      host,
    );
    context.onDispose(actor.dispose);
    return MainThreadAuthenticationActor(actor);
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  @override
  Future<void> $registerAuthenticationProvider(
    Map<String, Object?> details,
  ) async {
    final id = details['id'];
    final label = details['label'];
    if (id is! String || id.isEmpty || label is! String || label.isEmpty) {
      return;
    }
    final scopes = details['declaredScopes'];
    final authorizationServers = [
      for (final server in details['authorizationServers'] as List? ?? const [])
        ?VsUri.tryRevive(server),
    ];
    final provider = _ExtHostAuthenticationProvider(
      id: id,
      label: label,
      supportsMultipleAccounts: details['supportsMultipleAccounts'] == true,
      authorizationServers: authorizationServers,
      resourceServer: VsUri.tryRevive(details['resourceServer']),
      proxy: _proxy,
      clientId: '${details['clientId'] ?? ''}',
      clientSecret: '${details['clientSecret'] ?? ''}',
      dynamic: details['isDynamicAuthProvider'] == true,
    );
    _providers[id] = provider;
    _ui.authentication.registerAuthenticationProvider(id, provider);
    // What the extension declared in its manifest, with the registered
    // provider's details.
    switch (scopes) {
      case final List<Object?> list:
        _declaredScopes[id] = [for (final scope in list) '$scope'];
    }
    if (details['dynamic'] == true) _dynamic.add(id);
  }

  final _declaredScopes = <String, List<String>>{};
  final _dynamic = <String>{};

  @override
  Future<void> $unregisterAuthenticationProvider(String id) async {
    _providers.remove(id);
    _ui.authentication.unregisterAuthenticationProvider(id);
  }

  @override
  Future<void> $ensureProvider(String id) async {
    if (_ui.authentication.isAuthenticationProviderRegistered(id)) return;
    await _host.activateByEvent(authenticationProviderActivationEvent(id));
  }

  @override
  Future<void> $sendDidChangeSessions(
    String providerId,
    Map<String, Object?> event,
  ) async {
    _providers[providerId]?.sessionsChanged(
      AuthSessionsChangeEvent.fromJson(event),
    );
  }

  @override
  Future<Map<String, Object?>?> $getSession(
    String providerId,
    Object? scopeListOrRequest,
    String extensionId,
    String extensionName,
    Map<String, Object?> options,
  ) async {
    await $ensureProvider(providerId);
    final session = await _getSession(
      providerId,
      scopeListOrRequest,
      extensionId,
      extensionName,
      options,
    );
    return session?.json;
  }

  Future<AuthSession?> _getSession(
    String providerId,
    Object? scopeListOrRequest,
    String extensionId,
    String extensionName,
    Map<String, Object?> options,
  ) async {
    // The invalid combinations upstream rejects.
    if (options['forceNewSession'] != null && options['createIfNone'] != null) {
      throw const AuthenticationError(
        'Invalid combination of options. Please remove one of the following: '
        'forceNewSession, createIfNone',
      );
    }
    if (options['forceNewSession'] != null && options['silent'] == true) {
      throw const AuthenticationError(
        'Invalid combination of options. Please remove one of the following: '
        'forceNewSession, silent',
      );
    }
    if (options['createIfNone'] != null && options['silent'] == true) {
      throw const AuthenticationError(
        'Invalid combination of options. Please remove one of the following: '
        'createIfNone, silent',
      );
    }
    final authentication = _ui.authentication;
    final authorizationServer = VsUri.tryRevive(options['authorizationServer']);
    final sessions = await authentication.getSessions(
      providerId,
      scopeListOrRequest: scopeListOrRequest,
      account: switch (options['account']) {
        final Map<Object?, Object?> account => AuthAccount(
          account.cast<String, Object?>(),
        ),
        _ => null,
      },
      authorizationServer: authorizationServer,
      activateImmediate: true,
    );
    final provider = authentication.getProvider(providerId);
    final extensions = _ui.extensions;
    final forceNew = options['forceNewSession'] != null;
    final silent = options['silent'] == true;
    if (options['clearSessionPreference'] == true) {
      extensions.removeAccountPreference(extensionId, providerId);
    }
    final accountPreference = options['account'] != null
        ? sessions.firstOrNull
        : _accountPreference(extensionId, providerId, sessions);
    if (!forceNew && sessions.isNotEmpty) {
      if (accountPreference != null &&
          _access.isAccessAllowed(
                providerId,
                accountPreference.account.label,
                extensionId,
              ) ==
              true) {
        return accountPreference;
      }
      if (!provider.supportsMultipleAccounts &&
          _access.isAccessAllowed(
                providerId,
                sessions.first.account.label,
                extensionId,
              ) ==
              true) {
        return sessions.first;
      }
    }
    if (options['createIfNone'] != null || forceNew) {
      final interactive = switch (options['forceNewSession']) {
        final Map<Object?, Object?> value => value.cast<String, Object?>(),
        _ => switch (options['createIfNone']) {
          final Map<Object?, Object?> value => value.cast<String, Object?>(),
          _ => null,
        },
      };
      final recreating = forceNew && sessions.isNotEmpty;
      final allowed = await _loginPrompt(
        provider,
        extensionName,
        recreating,
        interactive,
      );
      if (!allowed) {
        throw const AuthenticationError('User did not consent to login.');
      }
      AuthSession session;
      if (sessions.isNotEmpty && !forceNew) {
        session = provider.supportsMultipleAccounts && options['account'] == null
            ? await extensions.selectSession(
                providerId,
                extensionId,
                extensionName,
                scopeListOrRequest,
                sessions,
              )
            : sessions.first;
      } else {
        final accountToCreate = switch (options['account']) {
          final Map<Object?, Object?> account => account.cast<String, Object?>(),
          _ => accountPreference?.account.json,
        };
        while (true) {
          session = await authentication.createSession(
            providerId,
            scopeListOrRequest,
            activateImmediate: true,
            account: accountToCreate == null
                ? null
                : AuthAccount(accountToCreate),
            authorizationServer: authorizationServer,
          );
          final requested = accountToCreate?['label'];
          if (accountToCreate == null ||
              requested == null ||
              requested == session.account.label) {
            break;
          }
          if (await _incorrectAccountPrompt(
            session.account.label,
            '$requested',
          )) {
            continue;
          }
          break;
        }
      }
      _ui.app.access.updateAllowedExtensions(providerId, session.account.label, [
        AllowedExtension(
          id: extensionId,
          name: extensionName,
          allowed: true,
        ),
      ]);
      extensions.updateNewSessionRequests(providerId, [session]);
      extensions.updateAccountPreference(
        extensionId,
        providerId,
        session.account,
      );
      return session;
    }
    // The default (and silent) flows: a session the extension may already
    // use is returned — the one the preference names, or the only one
    // there is; otherwise the accounts menu gets an entry the user can act
    // on (upstream's `requestSessionAccess`/`requestNewSession`) and the
    // call answers undefined, as upstream's non-interactive flows do.
    if (accountPreference != null) {
      if (_access.isAccessAllowed(
            providerId,
            accountPreference.account.label,
            extensionId,
          ) ==
          true) {
        return accountPreference;
      }
    } else {
      final valid = [
        for (final session in sessions)
          if (_access.isAccessAllowed(
                providerId,
                session.account.label,
                extensionId,
              ) ==
              true)
            session,
      ];
      if (valid.length == 1) return valid.first;
    }
    if (!silent) {
      if (sessions.isNotEmpty) {
        extensions.requestSessionAccess(
          providerId,
          extensionId,
          extensionName,
          scopeListOrRequest,
          sessions,
        );
      } else {
        await extensions.requestNewSession(
          providerId,
          scopeListOrRequest,
          extensionId,
          extensionName,
        );
      }
    }
    return null;
  }

  AuthSession? _accountPreference(
    String extensionId,
    String providerId,
    List<AuthSession> sessions,
  ) {
    if (sessions.isEmpty) return null;
    final preference = _ui.extensions.getAccountPreference(
      extensionId,
      providerId,
    );
    if (preference == null) return null;
    for (final session in sessions) {
      if (session.account.label == preference) return session;
    }
    return null;
  }

  /// `loginPrompt`: "The extension '{0}' wants to sign in using {1}."
  Future<bool> _loginPrompt(
    AuthenticationProvider provider,
    String extensionName,
    bool recreatingSession,
    Map<String, Object?>? options,
  ) async {
    final ui = _ui.ui;
    final l10n = ui.l10n();
    final custom = provider.confirmation(extensionName, recreatingSession);
    final message =
        custom ??
        (recreatingSession
            ? l10n.windowAuthConfirmRelogin(extensionName, provider.label)
            : l10n.windowAuthConfirmLogin(extensionName, provider.label));
    final learnMore = VsUri.tryRevive(options?['learnMore']);
    while (true) {
      final answer = await ui.dialogs.prompt(
        severity: ExtensionSeverity.info,
        message: message,
        detail: options?['detail'] as String?,
        buttons: [
          l10n.windowAuthAllow,
          if (learnMore != null) l10n.windowAuthLearnMore,
        ],
        cancel: l10n.commonCancel,
      );
      if (answer.button == 0) return true;
      if (answer.button == 1 && learnMore != null) {
        unawaited(ui.opener.openExternal(Uri.parse(learnMore.toString())));
        continue;
      }
      return false;
    }
  }

  Future<bool> _incorrectAccountPrompt(
    String chosenAccountLabel,
    String requestedAccountLabel,
  ) async {
    final l10n = _ui.ui.l10n();
    final answer = await _ui.ui.dialogs.prompt(
      severity: ExtensionSeverity.info,
      message: l10n.windowAuthIncorrectAccount,
      detail: l10n.windowAuthIncorrectAccountDetail(
        chosenAccountLabel,
        requestedAccountLabel,
      ),
      buttons: [l10n.windowAuthContinue],
      cancel: l10n.commonCancel,
    );
    return answer.button == 0;
  }

  @override
  Future<List<Map<String, Object?>>> $getAccounts(String providerId) async {
    await $ensureProvider(providerId);
    final accounts = await _ui.authentication.getAccounts(providerId);
    return [for (final account in accounts) account.json];
  }

  @override
  Future<void> $removeSession(String providerId, String sessionId) async {
    await _ui.authentication.removeSession(providerId, sessionId);
  }

  @override
  Future<VsUri> $waitForUriHandler(VsUri expectedUri) async {
    final completer = Completer<VsUri>();
    void Function()? remove;
    remove = _ui.urls?.registerHandler((uri) async {
      if (uri.scheme != expectedUri.scheme ||
          uri.authority != expectedUri.authority ||
          uri.path != expectedUri.path) {
        return false;
      }
      if (!completer.isCompleted) completer.complete(uri);
      remove?.call();
      return true;
    });
    try {
      final result = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw const AuthenticationError(
          'Timed out waiting for URI handler',
        ),
      );
      return result;
    } finally {
      remove?.call();
    }
  }

  @override
  Future<bool> $showContinueNotification(String message) async {
    final notifications = _ui.ui.notifications;
    if (notifications == null) return false;
    final l10n = _ui.ui.l10n();
    final completer = Completer<bool>();
    notifications.notify(
      IdeSeverity.info,
      message,
      primary: [
        IdeNotificationAction(
          l10n.windowAuthContinue,
          () => completer.complete(true),
        ),
      ],
      onClose: () => scheduleMicrotask(() {
        if (!completer.isCompleted) completer.complete(false);
      }),
    );
    return completer.future;
  }

  @override
  Future<bool> $showDeviceCodeModal(
    String userCode,
    String verificationUri,
  ) async {
    final ui = _ui.ui;
    final l10n = ui.l10n();
    final answer = await ui.dialogs.prompt(
      severity: ExtensionSeverity.info,
      message: l10n.windowAuthDeviceCodeTitle,
      detail: l10n.windowAuthDeviceCodeDetail(userCode, verificationUri),
      buttons: [l10n.windowAuthCopyAndContinue],
      cancel: l10n.commonCancel,
    );
    if (answer.button != 0) return false;
    await ui.clipboard.writeText(userCode);
    return ui.opener.openExternal(Uri.parse(verificationUri));
  }

  @override
  Future<Map<String, Object?>?> $promptForClientRegistration(
    String authorizationServerUrl,
  ) async {
    final ask = _ui.ui.promptForClientRegistration;
    return ask == null ? null : await ask(authorizationServerUrl);
  }

  @override
  Future<String?> $promptForResourceClientSecret(
    String resourceClientId,
    String resource,
  ) async {
    final ask = _ui.ui.promptForResourceClientSecret;
    return ask == null ? null : await ask(resourceClientId, resource);
  }

  @override
  Future<void> $registerDynamicAuthenticationProvider(
    Map<String, Object?> details,
  ) async {
    await $registerAuthenticationProvider(details);
    final id = '${details['id']}';
    _dynamic.add(id);
    final server = VsUri.tryRevive(details['authorizationServer']);
    final clientId = details['clientId'] as String?;
    if (server != null && clientId != null) {
      await _ui.app.dynamicProviders.storeClientRegistration(
        id,
        server.toString(),
        clientId,
        details['clientSecret'] as String?,
        details['label'] as String?,
      );
    }
  }

  @override
  Future<void> $setSessionsForDynamicAuthProvider(
    String authProviderId,
    String clientId,
    List<Map<String, Object?>> sessions,
  ) => _ui.app.dynamicProviders.setSessionsForDynamicAuthProvider(
    authProviderId,
    clientId,
    sessions,
  );

  @override
  Future<void> $sendDidChangeDynamicProviderInfo(
    Map<String, Object?> arg0,
  ) async {}
}

/// A workspace's extension host as the authentication service sees it.
final class _HostExtensions implements AuthenticationExtensionHost {
  _HostExtensions(this._host);

  final ExtensionHostService _host;

  @override
  Future<void> activateByEvent(String event, {bool immediate = false}) =>
      _host.manager.activateByEvent(
        event,
        kind: immediate ? ActivationKind.immediate : ActivationKind.normal,
      );

  @override
  Iterable<Map<String, Object?>> get extensions => _host.extensions.value;
}
