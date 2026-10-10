import '../model_provider.dart';

/// Which of a provider's accounts a request goes to ([AccountBalance]). A
/// conversation is kept on the account it went to while that one can take
/// it: its prompt is cached there, and its reasoning encrypted for it.
class CodexBalancer {
  /// How many conversations are remembered, the oldest forgotten first.
  static const _remembered = 2000;

  final Map<String, String> _sticky = {};
  final Map<String, int> _turns = {};

  /// One of [available] (in the provider's order) for [session] of
  /// provider [providerId]; null when there is none. [used] is how much
  /// of an account's quota is used, 0 to 100, null when not known.
  ProviderAccount? pick(
    String providerId,
    List<ProviderAccount> available,
    AccountBalance mode, {
    String? session,
    double? Function(ProviderAccount account)? used,
  }) {
    if (available.isEmpty) return null;
    final key = session == null ? null : '$providerId/$session';
    if (mode == AccountBalance.fillFirst) return available.first;
    if (key != null) {
      final kept = _sticky[key];
      final account = available.where((a) => a.id == kept).firstOrNull;
      if (account != null) return account;
    }
    final ProviderAccount account;
    if (mode == AccountBalance.mostRemaining) {
      // Unknown, taken as unused: it is asked, and so learned.
      account = available.reduce(
        (best, next) =>
            (used?.call(next) ?? 0) < (used?.call(best) ?? 0) ? next : best,
      );
    } else {
      final turn = _turns[providerId] ?? 0;
      _turns[providerId] = turn + 1;
      account = available[turn % available.length];
    }
    if (key != null) {
      _sticky.remove(key);
      _sticky[key] = account.id;
      if (_sticky.length > _remembered) _sticky.remove(_sticky.keys.first);
    }
    return account;
  }

  /// Forgets the conversations of [providerId]'s account [accountId].
  void forget(String providerId, String accountId) => _sticky.removeWhere(
    (key, value) => value == accountId && key.startsWith('$providerId/'),
  );
}
