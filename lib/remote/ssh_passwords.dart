import 'dart:convert';

import 'package:bao_remote/client.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../models/secret_store.dart';

/// What the user answered: [remember] to keep it in the system's keychain.
typedef SshPasswordAnswer = ({String answer, bool remember});

/// Asks the user what [prompt] asks; [keepable] when it may be kept (a
/// password, a passphrase: not a one-time code). Null when cancelled.
typedef SshPasswordAsk = Future<SshPasswordAnswer?> Function(
  SshPrompt prompt, {
  required bool keepable,
});

/// Answers what `ssh` asks while signing in to a host ([SshPrompter]):
/// what was answered before in this run of the app, else what the user
/// kept in the system's keychain, else the user ([ask]). An answer to be
/// remembered is kept once it signed in ([signedIn]); one refused is
/// forgotten, here and in the keychain.
class SshPasswords {
  SshPasswords({this._secrets});

  final SecretStore? _secrets;
  SecretStore get secrets => _secrets ?? SecretStore.instance;

  /// Shows the user the question: the open window's (see Workbench); null
  /// when there is none, so that nothing is answered.
  SshPasswordAsk? ask;

  /// Answers of this run, by id.
  final Map<String, String> _answers = {};

  /// Those to keep once [signedIn], by host and id.
  final Map<String, Map<String, String>> _toKeep = {};

  /// Those answered for each host while it signs in, by id.
  final Map<String, Set<String>> _given = {};

  /// Whether [prompt] asks for a secret worth keeping: a password or a
  /// key's passphrase, not a one-time code.
  static bool keepable(SshPrompt prompt) {
    final text = prompt.text.toLowerCase();
    return (text.contains('password') || text.contains('passphrase')) &&
        !RegExp(r'one-time|otp|verification|token|code').hasMatch(text);
  }

  /// The keychain's name for [prompt]'s answer: the host's, and the
  /// prompt's (`me@host's password`, a key's path), hashed.
  static String idOf(SshPrompt prompt) {
    final hash = crypto.sha256.convert(utf8.encode(prompt.text.trim()));
    return 'ssh:${prompt.target.text}:${'$hash'.substring(0, 16)}';
  }

  Future<String?> answer(SshPrompt prompt) async {
    final keeps = keepable(prompt);
    final host = prompt.target.text;
    final id = idOf(prompt);
    if (keeps) {
      if (prompt.retry) {
        await _forget(host, id);
      } else if (_answers[id] case final answer?) {
        (_given[host] ??= {}).add(id);
        return answer;
      } else if (await _kept(id) case final kept?) {
        _answers[id] = kept;
        (_given[host] ??= {}).add(id);
        return kept;
      }
    }
    final asked = await ask?.call(prompt, keepable: keeps);
    if (asked == null) return null;
    if (keeps) {
      _answers[id] = asked.answer;
      (_given[host] ??= {}).add(id);
      if (asked.remember) {
        (_toKeep[host] ??= {})[id] = asked.answer;
      } else {
        _toKeep[host]?.remove(id);
      }
    }
    return asked.answer;
  }

  /// [host] signed in: what was to be remembered is kept.
  Future<void> signedIn(String host) async {
    _given.remove(host);
    final keep = _toKeep.remove(host) ?? const {};
    for (final MapEntry(key: id, value: answer) in keep.entries) {
      try {
        await secrets.write(id, answer);
      } on SecretStoreException {
        // Asked for again next time.
      }
    }
  }

  /// [host] could not sign in ([failure]): when it refused, what was
  /// answered for it is forgotten.
  Future<void> failed(String host, SshFailure? failure) async {
    final given = _given.remove(host) ?? const {};
    _toKeep.remove(host);
    if (failure != SshFailure.authentication) return;
    for (final id in given) {
      await _forget(host, id);
    }
  }

  Future<String?> _kept(String id) async {
    try {
      return await secrets.read(id);
    } on SecretStoreException {
      return null;
    }
  }

  Future<void> _forget(String host, String id) async {
    _answers.remove(id);
    _toKeep[host]?.remove(id);
    try {
      await secrets.delete(id);
    } on SecretStoreException {
      // Refused again next time, and forgotten then.
    }
  }
}
