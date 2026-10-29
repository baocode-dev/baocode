import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The `prompt_cache_key` of Claude Code's session [session]: hashed, so
/// the upstream is not told it. The key a conversation's account is kept
/// by, too ([CodexBalancer]).
String promptCacheKeyOf(String session) {
  final digest = sha256.convert(utf8.encode('baocode:$session'));
  return 'baocode-${'$digest'.substring(0, 32)}';
}
