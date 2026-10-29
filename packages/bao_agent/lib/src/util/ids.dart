import 'dart:math' as math;

final _random = math.Random.secure();

/// A random UUID (v4), as sessions and conversation lines are named.
String newUuid() {
  String hex(int length) =>
      [for (var i = 0; i < length; i++) _random.nextInt(16).toRadixString(16)]
          .join();
  final variant = (8 + _random.nextInt(4)).toRadixString(16);
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
}

/// [length] random letters and digits, lower case: a task's id, a file's
/// name.
String randomId(int length) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return [
    for (var i = 0; i < length; i++) alphabet[_random.nextInt(alphabet.length)],
  ].join();
}

/// [bytes] random bytes, in hex.
String randomHex(int bytes) => [
  for (var i = 0; i < bytes; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

/// Whether [id] is fit to name a session's files: nothing that walks out
/// of a folder.
bool isSafeId(String id) => RegExp(r'^[0-9a-zA-Z][0-9a-zA-Z_-]*$').hasMatch(id);

/// Three words, as plans are named (`gentle-wandering-otter`).
String randomSlug() {
  const first = [
    'amber',
    'brave',
    'calm',
    'clever',
    'cosy',
    'crisp',
    'eager',
    'fuzzy',
    'gentle',
    'golden',
    'happy',
    'lively',
    'lucky',
    'mellow',
    'nimble',
    'plucky',
    'quiet',
    'rapid',
    'sunny',
    'tidy',
    'velvet',
    'witty',
  ];
  const second = [
    'baking',
    'dancing',
    'drifting',
    'gliding',
    'hopping',
    'humming',
    'leaping',
    'painting',
    'roaming',
    'singing',
    'skipping',
    'spinning',
    'strolling',
    'tinkering',
    'wandering',
    'whistling',
  ];
  const third = [
    'badger',
    'comet',
    'falcon',
    'fern',
    'harbor',
    'kettle',
    'lantern',
    'maple',
    'meadow',
    'otter',
    'pebble',
    'quokka',
    'river',
    'sparrow',
    'teapot',
    'willow',
  ];
  String pick(List<String> words) => words[_random.nextInt(words.length)];
  return '${pick(first)}-${pick(second)}-${pick(third)}';
}
