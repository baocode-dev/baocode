import 'package:flutter/foundation.dart';

import '../model_provider.dart';
import 'codex_usage.dart';

/// What Settings → Models does with a ChatGPT (Codex) provider's
/// accounts: signs in to one, shows how much of each one's quota is used,
/// signs one out. What it learned of them is not kept past the app.
abstract class CodexService extends ChangeNotifier {
  /// Starts signing in to an account for provider [providerId]: the
  /// browser opened at it. Throws [CodexException] when it cannot start
  /// (the port it comes back to taken).
  Future<CodexLogin> login(String providerId);

  /// Asks how much of each of [provider]'s accounts' quota is used.
  Future<void> refreshUsage(ModelProvider provider);

  /// Account [accountId]'s quota, as last known.
  CodexUsage? usage(String providerId, String accountId);

  /// Why account [accountId] last failed, while it is not known to work.
  String? error(String providerId, String accountId);

  /// Until when account [accountId] is out of quota; null when it is not.
  DateTime? limitedUntil(String providerId, String accountId);

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
  Future<void> refreshUsage(ModelProvider provider) async {}

  @override
  CodexUsage? usage(String providerId, String accountId) => null;

  @override
  String? error(String providerId, String accountId) => null;

  @override
  DateTime? limitedUntil(String providerId, String accountId) => null;

  @override
  Future<void> removeAccount(String providerId, String accountId) async {}
}
