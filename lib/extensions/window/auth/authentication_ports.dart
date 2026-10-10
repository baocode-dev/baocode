// What the authentication services need from the app: the OS's secret
// storage, quick picks and input boxes, the clipboard, and the extension
// host the providers live in. Adapters on BaoCode's widgets are in
// authentication_ui_adapters.dart; tests use fakes.

import 'dart:async';

import '../../../ide/ide_notifications.dart';
import '../../../l10n/l10n.dart';
import '../window_ports.dart';

/// The OS's secret storage (VS Code's `ISecretStorageService`): dynamic
/// providers' client registrations and tokens, MCP client secrets.
abstract interface class AuthSecretStore {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<void> delete(String key);

  /// The key of every secret set or deleted (`onDidChangeSecret`).
  Stream<String> get onDidChange;
}

/// An in-memory [AuthSecretStore] (tests, or no secret storage).
final class MemoryAuthSecretStore implements AuthSecretStore {
  final values = <String, String>{};
  final _changes = StreamController<String>.broadcast(sync: true);

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    values[key] = value;
    _changes.add(key);
  }

  @override
  Future<void> delete(String key) async {
    if (values.remove(key) != null) _changes.add(key);
  }

  @override
  Stream<String> get onDidChange => _changes.stream;
}

/// A row of a quick pick (`IQuickPickItem`), or a separator with an
/// optional label.
final class AuthPickItem {
  const AuthPickItem(
    this.label, {
    this.description,
    this.tooltip,
    this.picked = false,
    this.disabled = false,
  }) : separator = false;

  const AuthPickItem.separator([this.label = ''])
    : description = null,
      tooltip = null,
      picked = false,
      disabled = false,
      separator = true;

  final String label;
  final String? description;
  final String? tooltip;

  /// Checked at first (many) or active at first (one).
  final bool picked;

  /// Shown but cannot be changed.
  final bool disabled;
  final bool separator;
}

/// Quick picks and input boxes (VS Code's `IQuickInputService`).
abstract interface class AuthQuickInput {
  /// One of [items]: its index; null when dismissed.
  Future<int?> pickOne({
    String? title,
    String? placeholder,
    required List<AuthPickItem> items,
  });

  /// Several of [items] (`canPickMany`): the indexes checked when accepted;
  /// null when dismissed.
  Future<Set<int>?> pickMany({
    String? title,
    String? placeholder,
    required List<AuthPickItem> items,
  });

  /// A line of text (`input`); null when dismissed. [validate] returns the
  /// message of a value that cannot be accepted.
  Future<String?> input({
    String? title,
    String? prompt,
    String? placeholder,
    bool password = false,
    String? Function(String value)? validate,
  });
}

/// The system clipboard (VS Code's `IClipboardService.writeText`).
abstract interface class AuthClipboard {
  Future<void> writeText(String text);
}

/// The extension host of a workspace, as its authentication service needs
/// it: activation, and the scanned extensions (their `contributes.
/// authentication` and names).
abstract interface class AuthenticationExtensionHost {
  /// `IExtensionService.activateByEvent`; [immediate] is
  /// `ActivationKind.Immediate`.
  Future<void> activateByEvent(String event, {bool immediate = false});

  /// The scanned `IExtensionDescription`s.
  Iterable<Map<String, Object?>> get extensions;
}

/// The UI a workspace's authentication uses.
final class AuthenticationUi {
  AuthenticationUi({
    required this.dialogs,
    required this.quickInput,
    required this.clipboard,
    required this.opener,
    this.notifications,
    AppLocalizations Function()? l10n,
  }) : l10n = l10n ?? (() => englishLocalizations);

  final ExtensionDialogs dialogs;
  final AuthQuickInput quickInput;
  final AuthClipboard clipboard;
  final ExtensionExternalOpener opener;

  /// Where `$showContinueNotification` and errors show; null shows none
  /// (and a continue prompt answers No).
  final IdeNotifications? notifications;

  /// The display language's strings.
  final AppLocalizations Function() l10n;

  /// Asks for the client registration of an authorization server that does
  /// not support dynamic registration
  /// (`$promptForClientRegistration`): `{clientId, clientSecret?}`, or null
  /// when the user gave up. Set by the app's adapter (dialogs and inputs);
  /// null answers null.
  Future<Map<String, Object?>?> Function(String authorizationServerUrl)?
  promptForClientRegistration;

  /// Asks for the client secret of a resource (`$promptForResourceClientSecret`);
  /// null when the user gave up.
  Future<String?> Function(String resourceClientId, String resource)?
  promptForResourceClientSecret;
}
