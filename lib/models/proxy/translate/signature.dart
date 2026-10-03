// Ported from CLIProxyAPI's internal/signature (MIT License; see NOTICE.md
// beside this file): the checks a GPT target needs. Its Claude and Gemini
// envelope validators are not ported: a signature is only ever replayed
// here to an OpenAI upstream, which takes GPT reasoning signatures alone.

import 'dart:convert';
import 'dart:math' as math;

/// The provider families signatures are told apart by.
enum SignatureProvider { unknown, claude, gemini, gpt, kimi, grok, swe }

/// The provider named by the explicit prefix CLIProxyAPI caches signatures
/// under (`gpt#…`), and the signature without it.
(SignatureProvider, String)? splitSignatureProviderPrefix(String raw) {
  final trimmed = raw.trim();
  final hash = trimmed.indexOf('#');
  if (hash < 0) return null;
  final provider = switch (trimmed.substring(0, hash).trim().toLowerCase()) {
    'claude' ||
    'anthropic' ||
    'cais' ||
    'claude-cais' ||
    'claude_cais' ||
    'ccmax' ||
    'claude-code-max' ||
    'claude_code_max' => SignatureProvider.claude,
    'gemini' || 'google' => SignatureProvider.gemini,
    'openai' || 'gpt' || 'codex' => SignatureProvider.gpt,
    'swe' || 'sealed' => SignatureProvider.swe,
    _ => SignatureProvider.unknown,
  };
  if (provider == SignatureProvider.unknown) return null;
  return (provider, trimmed.substring(hash + 1).trim());
}

/// Longest GPT reasoning signature taken.
const maxGptReasoningSignatureLength = 32 * 1024 * 1024;

/// Whether [raw] has the Fernet-like shape of GPT/Codex reasoning
/// `encrypted_content`: `gAAAA`, base64url, version 0x80, then a
/// timestamp, an IV, AES blocks and an HMAC. Its shape only: not that it
/// decrypts.
bool isValidGptReasoningSignature(String raw) {
  final signature = raw.trim();
  if (signature.isEmpty || signature.length > maxGptReasoningSignatureLength) {
    return false;
  }
  if (!signature.startsWith('gAAAA')) return false;
  if (!_inAlphabet(signature, _base64Url)) return false;
  final decoded = _decodeBase64Url(signature);
  if (decoded == null || decoded.length < 73 || decoded[0] != 0x80) {
    return false;
  }
  final ciphertext = decoded.length - 1 - 8 - 16 - 32;
  return ciphertext > 0 && ciphertext % 16 == 0;
}

/// [raw] as a GPT upstream can replay it, without a cache prefix; null
/// when it is not a GPT reasoning signature.
String? compatibleGptSignature(String raw) {
  final signature = raw.trim();
  if (signature.isEmpty) return null;
  if (splitSignatureProviderPrefix(signature) case (
    final provider,
    final rest,
  )) {
    return provider == SignatureProvider.gpt &&
            isValidGptReasoningSignature(rest)
        ? rest
        : null;
  }
  if (signature.contains('#')) return null;
  return isValidGptReasoningSignature(signature) ? signature : null;
}

/// Longest Grok `encrypted_content` taken.
const maxGrokEncryptedContentLength = 8 * 1024 * 1024;

/// Fewest decoded bytes a Grok `encrypted_content` has: a loose floor.
const minGrokEncryptedContentDecodedLength = 32;

/// Least entropy ratio a Grok `encrypted_content` has: ciphertext's.
const minGrokEncryptedContentEntropyRatio = 0.85;

/// Whether [raw] has the shape of xAI's `encrypted_content`: unpadded
/// standard base64 of high-entropy bytes. Not a classifier (xAI's blobs
/// have no envelope): ask only of what a Grok model sent.
bool isValidGrokEncryptedContent(String raw) {
  final signature = raw.trim();
  if (signature.isEmpty || signature.length > maxGrokEncryptedContentLength) {
    return false;
  }
  if (signature != raw || signature.contains('=')) return false;
  if (!_inAlphabet(signature, _base64Std)) return false;
  if (splitSignatureProviderPrefix(signature) != null) return false;
  if (signature.startsWith('gAAAA')) return false;
  if (isValidKimiThinkingSignature(signature)) return false;
  final decoded = _decodeBase64Std(signature);
  if (decoded == null ||
      decoded.length < minGrokEncryptedContentDecodedLength) {
    return false;
  }
  return byteEntropyRatio(decoded) >= minGrokEncryptedContentEntropyRatio;
}

/// The lengths Kimi's thinking signatures come in: non-streaming and
/// streaming replies.
const kimiThinkingSignatureLengths = {12946, 4340};

/// Whether [raw] has the size and character class of a Kimi Messages
/// thinking signature.
bool isValidKimiThinkingSignature(String raw) {
  final signature = raw.trim();
  if (signature.isEmpty || signature != raw) return false;
  if (!kimiThinkingSignatureLengths.contains(signature.length)) return false;
  if (signature.contains('=')) return false;
  if (!_inAlphabet(signature, _base64Std)) return false;
  if (splitSignatureProviderPrefix(signature) != null) return false;
  if (signature.startsWith('gAAAA')) return false;
  final decoded = _decodeBase64Std(signature);
  return decoded != null &&
      byteEntropyRatio(decoded) >= minGrokEncryptedContentEntropyRatio;
}

/// The bytes' entropy over the most a sample of their size can have.
double byteEntropyRatio(List<int> bytes) {
  if (bytes.isEmpty) return 0;
  final counts = List.filled(256, 0);
  for (final byte in bytes) {
    counts[byte]++;
  }
  final n = bytes.length.toDouble();
  var entropy = 0.0;
  for (final count in counts) {
    if (count == 0) continue;
    final p = count / n;
    entropy -= p * math.log(p) / math.ln2;
  }
  final symbols = math.min(bytes.length, 256);
  if (symbols <= 1) return 0;
  return entropy / (math.log(symbols) / math.ln2);
}

const _alphanumeric =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
final _base64Url = '$_alphanumeric-_='.codeUnits.toSet();
final _base64Std = '$_alphanumeric+/'.codeUnits.toSet();

bool _inAlphabet(String text, Set<int> alphabet) =>
    text.codeUnits.every(alphabet.contains);

List<int>? _decodeBase64Url(String text) {
  try {
    return base64Url.decode(base64Url.normalize(text));
  } on FormatException {
    return null;
  }
}

List<int>? _decodeBase64Std(String text) {
  try {
    return base64.decode(base64.normalize(text));
  } on FormatException {
    return null;
  }
}
