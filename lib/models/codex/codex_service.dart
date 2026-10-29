import 'package:flutter/foundation.dart';

import '../model_provider.dart';
import 'codex_usage.dart';

/// What Settings → Models does with a ChatGPT (Codex) provider's
/// accounts: signs in to one, shows how much of each one's quota is used,
/// signs one out. What it learned of them is not kept past the app.
abstract class CodexService extends ChangeNotifier {
  /// How long an account's quota, learned, is not asked again by
  /// [refreshUsage] not forced: unless a window of it starts over first.
  static const usageMaxAge = Duration(minutes: 5);

  /// Starts signing in to an account for provider [providerId]: the
  /// browser opened at it. Throws [CodexException] when it cannot start
  /// (the port it comes back to taken).
  Future<CodexLogin> login(String providerId);

  /// Asks how much of each of [provider]'s accounts' quota is used.
  /// With [force] false, those learned (or tried) in [usageMaxAge] are
  /// not asked again, unless a window of theirs started over since.
  Future<void> refreshUsage(ModelProvider provider, {bool force = true});

  /// The account a request of Claude Code's session [session] goes to
  /// now: the one it is kept on, or the next by [provider]'s balance;
  /// null when none can take it.
  ProviderAccount? accountFor(ModelProvider provider, {String? session});

  /// When the first of [provider]'s accounts can take a request again,
  /// every one in use being out of quota; null while one can (or none is
  /// in use).
  DateTime? backAt(ModelProvider provider);

  /// Account [accountId]'s quota, as last known.
  CodexUsage? usage(String providerId, String accountId);

  /// Why account [accountId] last failed, while it is not known to work.
  String? error(String providerId, String accountId);

  /// Until when account [accountId] is out of quota; null when it is not.
  DateTime? limitedUntil(String providerId, String accountId);

  /// Whether account [accountId] is signed out: to be signed in again.
  bool signedOut(String providerId, String accountId);

  /// Removes account [accountId] from provider [providerId], and its token.
  Future<void> removeAccount(String providerId, String accountId);
}

/// A sign-in under way.
abstract interface class CodexLogin {
  /// Where the browser was sent: to be opened by hand if it was not.
  Uri get url;

  /// The account signed in to, once kept; [CodexException] if it failed,
  /// [CodexCancelled] if [cancel]led.
  Future<ProviderAccount> get result;

  /// Whether the browser comes back to this machine by itself: not when
  /// another program has the port it comes back to, and the address it
  /// lands on is to be [submit]ted.
  bool get listening;

  /// The address the browser landed on after signing in, pasted. Throws
  /// [CodexException] when it is not this sign-in's.
  void submit(String callback);

  void cancel();
}

class CodexException implements Exception {
  const CodexException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CodexCancelled extends CodexException {
  const CodexCancelled() : super('Sign-in cancelled.');
}

/// Where there is no machine to sign in from (the web).
class CodexUnavailable extends CodexService {
  @override
  Future<CodexLogin> login(String providerId) async =>
      throw const CodexException('Not available on the web.');

  @override
  Future<void> refreshUsage(
    ModelProvider provider, {
    bool force = true,
  }) async {}

  @override
  ProviderAccount? accountFor(ModelProvider provider, {String? session}) =>
      null;

  @override
  DateTime? backAt(ModelProvider provider) => null;

  @override
  CodexUsage? usage(String providerId, String accountId) => null;

  @override
  String? error(String providerId, String accountId) => null;

  @override
  DateTime? limitedUntil(String providerId, String accountId) => null;

  @override
  bool signedOut(String providerId, String accountId) => false;

  @override
  Future<void> removeAccount(String providerId, String accountId) async {}
}
