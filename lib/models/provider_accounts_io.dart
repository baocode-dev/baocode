import 'antigravity/antigravity_accounts_io.dart';
import 'codex/codex_accounts_io.dart';
import 'codex/codex_service.dart';
import 'codex/codex_usage.dart';
import 'model_provider.dart';
import 'model_providers.dart';

/// The accounts of every provider signed in to with them, as one
/// [CodexService]: ChatGPT's ([CodexAccounts]) and Antigravity's
/// ([AntigravityAccounts]), each provider's asked of its own.
class ProviderAccounts extends CodexService {
  ProviderAccounts({
    required this._providers,
    required this.codex,
    required this.antigravity,
  }) {
    codex.addListener(notifyListeners);
    antigravity.addListener(notifyListeners);
  }

  final ModelProviders Function() _providers;
  final CodexAccounts codex;
  final AntigravityAccounts antigravity;

  CodexService _of(ProviderProtocol? protocol) =>
      protocol == ProviderProtocol.antigravity ? antigravity : codex;

  CodexService _for(ModelProvider provider) => _of(provider.protocol);

  CodexService _byId(String providerId) =>
      _of(_providers().provider(providerId)?.protocol);

  @override
  Future<CodexLogin> login(String providerId) =>
      _byId(providerId).login(providerId);

  @override
  Future<List<CodexImportResult>> importAccountsJson(
    String providerId,
    String contents, {
    required bool confirmed,
  }) =>
      _byId(providerId)
          .importAccountsJson(providerId, contents, confirmed: confirmed);

  @override
  Future<void> refreshUsage(ModelProvider provider, {bool force = true}) =>
      _for(provider).refreshUsage(provider, force: force);

  @override
  Future<void> refreshAccountUsage(
    ModelProvider provider,
    String accountId, {
    bool force = true,
  }) => _for(provider).refreshAccountUsage(provider, accountId, force: force);

  @override
  ProviderAccount? accountFor(ModelProvider provider, {String? session}) =>
      _for(provider).accountFor(provider, session: session);

  @override
  ProviderAccount? accountForModel(
    ModelProvider provider, {
    String? session,
    String? model,
  }) =>
      _for(provider).accountForModel(provider, session: session, model: model);

  @override
  DateTime? backAt(ModelProvider provider) => _for(provider).backAt(provider);

  @override
  DateTime? backAtFor(ModelProvider provider, {String? model}) =>
      _for(provider).backAtFor(provider, model: model);

  @override
  CodexUsage? usage(String providerId, String accountId) =>
      _byId(providerId).usage(providerId, accountId);

  @override
  List<CodexResetCredit>? resetCredits(String providerId, String accountId) =>
      _byId(providerId).resetCredits(providerId, accountId);

  @override
  bool resetting(String providerId, String accountId) =>
      _byId(providerId).resetting(providerId, accountId);

  @override
  Future<void> useResetCredit(ModelProvider provider, String accountId) =>
      _for(provider).useResetCredit(provider, accountId);

  @override
  String? error(String providerId, String accountId) =>
      _byId(providerId).error(providerId, accountId);

  @override
  DateTime? limitedUntil(String providerId, String accountId) =>
      _byId(providerId).limitedUntil(providerId, accountId);

  @override
  bool signedOut(String providerId, String accountId) =>
      _byId(providerId).signedOut(providerId, accountId);

  @override
  Future<void> removeAccount(String providerId, String accountId) =>
      _byId(providerId).removeAccount(providerId, accountId);

  @override
  void dispose() {
    codex.removeListener(notifyListeners);
    antigravity.removeListener(notifyListeners);
    super.dispose();
  }
}
