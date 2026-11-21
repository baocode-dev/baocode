// Ported from magpie's internal/gateway/codeassist.go (antigravityCloak and
// what it uses; MIT License; see NOTICE.md beside this file).

/// Lines of a system prompt Antigravity answers with a 429 "Resource has
/// been exhausted", whatever quota is left, lower-cased: each is sent
/// reworded with the same meaning ([antigravityCloak]).
const _turnedAway = [
  _billingLine,
  "built on anthropic's claude agent sdk",
  'you are codex, an agent based on gpt-5',
  'you are codex, a coding agent based on gpt-5',
  'an intelligent ai assistant created by nous research',
  _rfcLine,
  'you are hermes agent',
  'you are opencode',
  'you are a coding agent running in the codex cli',
  'a coding assistant running inside pi',
];

/// Claude Code's billing line: sent not at all, to the end of its line.
const _billingLine = 'x-anthropic-billing-header:';

const _rfcLine =
    'rfc 2119 keywords: must, required, should, recommended, may, optional.';

/// A run of white space as Google's check reads it.
const _space =
    r'[\s\u000b\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+';

/// Characters Google's check reads past.
const _invisible = r'[\u00ad\u180e\u200b-\u200f\u2060-\u2064\ufeff]';

final _invisibleRe = RegExp(_invisible);

/// [line] in any case, with any run of white space between its words and
/// invisible characters inside them.
RegExp _lineRe(String line) {
  final words = [
    for (final word in line.split(' '))
      [for (final c in word.split('')) RegExp.escape(c)].join('$_invisible*'),
  ];
  var source = words.join('$_invisible*$_space$_invisible*');
  if (line == _billingLine) source += r'[^\n]*\n?';
  return RegExp(source, caseSensitive: false);
}

final _turnedAwayRes = [for (final line in _turnedAway) _lineRe(line)];

final _sdk = RegExp(
  "^(built$_space"
  "on$_space)anthropic's($_space)(claude${_space}agent${_space}sdk)\$",
  caseSensitive: false,
);
final _basedOn = RegExp('based($_space)on', caseSensitive: false);
final _createdBy = RegExp('created($_space)by', caseSensitive: false);
final _keywords = RegExp('(key)(words)', caseSensitive: false);
final _youAre = RegExp('^(you)${_space}are', caseSensitive: false);
final _inside = RegExp('inside', caseSensitive: false);

String _youre(String m) => m.replaceFirstMapped(_youAre, (g) => "${g[1]}'re");

/// How each of [_turnedAway] goes instead, in the same order.
final List<String Function(String)> _saidAs = [
  (_) => '',
  (m) => m.replaceFirstMapped(
    _sdk,
    (g) => '${g[1]}the${g[2]}${g[3]} by Anthropic',
  ),
  (m) => m.replaceAllMapped(_basedOn, (g) => 'built${g[1]}on'),
  (m) => m.replaceAllMapped(_basedOn, (g) => 'built${g[1]}on'),
  (m) => m.replaceAllMapped(_createdBy, (g) => 'built${g[1]}by'),
  (m) => m.replaceAllMapped(_keywords, (g) => '${g[1]} ${g[2]}'),
  _youre,
  _youre,
  _youre,
  (m) => m.replaceAll(_inside, 'within'),
];

/// [system] with each line Antigravity turns away reworded, every other
/// word as written.
String antigravityCloak(String system) => _cloak(system, null);

/// [text], a user's turn's, with the lines Antigravity turns away there
/// too (Codex's GPT-5 identity lines) reworded.
String antigravityCloakUserText(String text) => _cloak(text, const {2, 3});

String _cloak(String text, Set<int>? only) {
  final matches = <(int, int, String Function(String))>[];
  for (final (i, re) in _turnedAwayRes.indexed) {
    if (only != null && !only.contains(i)) continue;
    for (final match in re.allMatches(text)) {
      matches.add((match.start, match.end, _saidAs[i]));
    }
  }
  if (matches.isEmpty) return text;
  matches.sort((a, b) => a.$1 - b.$1);
  final out = StringBuffer();
  var previous = 0;
  for (final (from, to, said) in matches) {
    if (from < previous) continue;
    out
      ..write(text.substring(previous, from))
      ..write(said(text.substring(from, to).replaceAll(_invisibleRe, '')));
    previous = to;
  }
  out.write(text.substring(previous));
  return out.toString();
}
