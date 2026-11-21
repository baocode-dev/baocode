// After magpie's internal/gateway/gemini_signature.go and gemini_sigstore.go
// (MIT License; see NOTICE.md beside this file).

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Gemini's thought signatures on its function calls. Gemini signs the
/// first call of each step it thinks through and refuses the next request
/// without the signature back on it; Claude Code knows no place for it, but
/// sends every call's id back as it was given. So the signature rides in
/// the id, as a short key to where it is kept ([SignatureStore]):
/// `<id>__tsk16__<key>`; where it could not be kept, itself:
/// `<id>__ts<n>__<base64url>`.
abstract interface class SignatureStore {
  /// Keeps [signature]; the key it is kept by, or null when it could not be.
  String? keep(String signature);

  /// The signature kept by [key]; null when it is not (any more).
  String? kept(String key);
}

/// The key a signature is kept by: 12 bytes of its SHA-256, 16 characters.
String signatureKey(String signature) => base64Url
    .encode(sha256.convert(utf8.encode(signature)).bytes.sublist(0, 12))
    .replaceAll('=', '');

const _mark = '__ts';
const _kept = 'k';
const _end = '__';

/// [id] carrying [signature]; [id] as it is without one.
String signedToolId(String id, String? signature, SignatureStore? store) {
  if (signature == null || signature.isEmpty) return id;
  if (store?.keep(signature) case final key?) {
    return '$id$_mark$_kept${key.length}$_end$key';
  }
  final encoded = base64Url.encode(utf8.encode(signature)).replaceAll('=', '');
  return '$id${_mark}r${encoded.length}$_end$encoded';
}

/// [id] split into the call's own id and the signature it carries; [id]
/// and null for any other, or one whose signature was cut short or is no
/// longer kept.
(String, String?) unsignedToolId(String id, SignatureStore? store) {
  var at = 1;
  while (at < id.length) {
    final i = id.indexOf(_mark, at);
    if (i < 0) break;
    at = i + 1;
    var rest = id.substring(i + _mark.length);
    final raw = rest.startsWith('r');
    if (raw) rest = rest.substring(1);
    final kept = !raw && rest.startsWith(_kept);
    if (kept) rest = rest.substring(1);
    var digits = 0;
    while (digits < rest.length &&
        rest.codeUnitAt(digits) >= 0x30 &&
        rest.codeUnitAt(digits) <= 0x39) {
      digits++;
    }
    if (!rest.substring(digits).startsWith(_end)) continue;
    if (digits == 0) continue;
    final encoded = rest.substring(digits + _end.length);
    // A signature cut short is none.
    if (rest.substring(0, digits) != '${encoded.length}') return (id, null);
    if (kept) {
      return switch (store?.kept(encoded)) {
        final signature? => (id.substring(0, i), signature),
        null => (id, null),
      };
    }
    if (!raw) return (id, null);
    try {
      final padded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');
      final text = utf8.decode(base64Url.decode(padded));
      return text.isEmpty ? (id, null) : (id.substring(0, i), text);
    } on FormatException {
      return (id, null);
    }
  }
  return (id, null);
}

/// Signatures kept in memory alone: for tests, and while none can be kept
/// on disk.
class MemorySignatureStore implements SignatureStore {
  final Map<String, String> _signatures = {};

  @override
  String? keep(String signature) {
    final key = signatureKey(signature);
    _signatures[key] = signature;
    return key;
  }

  @override
  String? kept(String key) => _signatures[key];
}
