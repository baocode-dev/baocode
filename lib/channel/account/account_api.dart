import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/model_provider.dart' show ProviderProtocol;
import '../channel_setup.dart';
import 'login_window.dart';

/// What a request to an account site came back with: its status, its body
/// as JSON (null when it was none), and the cookies it set.
class AccountResponse {
  const AccountResponse(this.status, this.json, {this.cookies = const {}});

  final int status;
  final Object? json;

  /// Name to value, as `Set-Cookie` gave them.
  final Map<String, String> cookies;

  bool get ok => status >= 200 && status < 300;
}

/// Sends a request to an account site: a JSON body, if any, and the
/// headers given. Throws when it could not get through (offline, a
/// timeout).
typedef AccountSend = Future<AccountResponse> Function(
  String method,
  Uri url, {
  Map<String, String> headers,
  Object? json,
});

/// The user, as their account site has them.
@immutable
class AccountProfile {
  const AccountProfile({required this.name, this.email, this.balance});

  /// Their username, or email.
  final String name;
  final String? email;

  /// What is left on the account, in US dollars; null when the site does
  /// not say.
  final double? balance;

  Map<String, Object?> toJson() => {
    'name': name,
    'email': email,
    'balance': balance,
  };

  static AccountProfile? fromJson(Object? json) => switch (json) {
    {'name': final String name} => AccountProfile(
      name: name,
      email: json['email'] as String?,
      balance: (json['balance'] as num?)?.toDouble(),
    ),
    _ => null,
  };
}

/// One of the user's API keys, as listed: the whole key not always with it
/// ([AccountAdapter.reveal]).
@immutable
class AccountKey {
  const AccountKey({
    required this.id,
    required this.name,
    required this.masked,
    this.platform,
  });

  /// The site's, as text.
  final String id;
  final String name;

  /// Shown in the list: never the whole key.
  final String masked;

  /// The models the key is for (sub2api's group's platform: `anthropic`,
  /// `openai`, `gemini`…), where the site says.
  final String? platform;

  /// [key] as a list shows it: its start and its end.
  static String mask(String key) => key.length <= 12
      ? '${key.substring(0, key.length.clamp(0, 3))}••••'
      : '${key.substring(0, 6)}••••••${key.substring(key.length - 4)}';
}

/// A group the user may make a key in: its own models, at its own price.
@immutable
class AccountGroup {
  const AccountGroup({
    required this.id,
    required this.name,
    this.description,
    this.rate,
    this.platform,
  });

  /// What the site knows it by: sub2api's number, as text; new-api's name.
  final String id;
  final String name;
  final String? description;

  /// Its price against the site's own (1 the same); null where the site
  /// gives none (new-api's `auto`, which picks one per call).
  final double? rate;

  /// The models it is for (sub2api's platform: `anthropic`, `openai`…).
  final String? platform;
}

/// The account site said the user is signed out (their session ended,
/// revoked, or never was): they sign in again.
class AccountSignedOut implements Exception {
  const AccountSignedOut([this.message = 'signed out']);

  final String message;

  @override
  String toString() => message;
}

/// What stands in front of the account site (its firewall, its CDN's bot
/// check) refused the app: a 403 that is not the site's own answer. Not a
/// sign-out; the network the app is on (a VPN's or a proxy's address, say)
/// is what the site does not let in.
class AccountBlocked implements Exception {
  const AccountBlocked(this.method, this.url);

  /// What was refused, said to the user: `POST /api/v1/auth/refresh`.
  final String method;
  final Uri url;

  String get host => url.host;

  String get request => '$method ${url.path}';

  @override
  String toString() => '$host refused $request (HTTP 403)';
}

/// The account site refused, or answered what could not be read.
class AccountError implements Exception {
  const AccountError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the app does with a channel's account site, whichever panel it
/// runs: one adapter each ([NewApiAdapter], [Sub2ApiAdapter]).
///
/// Signed in once in the login window, the user's session is what the app
/// keeps: the panel's refresh credential ([credential]), traded for a
/// short-lived access token as the panel's own pages trade it, and
/// replaced by the one each trade gives back ([onCredential]). Signing out
/// ends the session on the site too.
abstract class AccountAdapter {
  AccountAdapter({
    required this.site,
    required this.send,
    required this.credential,
    this.onCredential,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final ChannelAccountSite site;
  final AccountSend send;

  /// The refresh credential, while signed in; null otherwise.
  String? credential;

  /// A new [credential] to keep (null: signed out).
  final void Function(String? credential)? onCredential;
  final DateTime Function() now;

  /// What the login window opens: the site's sign-in page, `/login` on
  /// new-api's and sub2api's both (one signed in already is sent on from
  /// there by the site).
  Uri get loginUrl => site.url.replace(path: '/login');

  /// While the login window is open, asked of it every second: the
  /// session it has signed in to, if it has (its credential); null till
  /// then.
  Future<String?> signedIn(LoginWindow window);

  Future<AccountProfile> profile();

  /// The user's keys, newest first as the site lists them.
  Future<List<AccountKey>> keys();

  /// [key] whole, to call the models with.
  Future<String> reveal(AccountKey key);

  /// The groups the user may make a key in.
  Future<List<AccountGroup>> groups();

  /// A new key named [name], in [group] (one the site would pick, without):
  /// the one made.
  Future<AccountKey> create(String name, {AccountGroup? group});

  /// How [key]'s models are spoken to: the channel's word for it, else the
  /// key's platform's, else Anthropic's.
  ProviderProtocol protocolFor(AccountKey key) {
    if (site.protocol case final id?) {
      return ProviderProtocol.values.firstWhere((p) => p.id == id);
    }
    return switch (key.platform) {
      'openai' => ProviderProtocol.openaiResponses,
      'gemini' => ProviderProtocol.gemini,
      _ => ProviderProtocol.anthropic,
    };
  }

  /// Ends the session on the site, then forgets it; forgotten even if the
  /// site cannot be reached.
  Future<void> signOut();

  /// Forgets the session: signed out.
  void forget() {
    credential = null;
    onCredential?.call(null);
  }

  /// [credential] traded for a new one ([onCredential]), kept.
  void renewed(String credential) {
    if (credential == this.credential) return;
    this.credential = credential;
    onCredential?.call(credential);
  }
}
