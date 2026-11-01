/// BaoCode's relays, for when two ends cannot reach each other directly:
/// both keep to them, and a connection goes through one until a direct
/// path is found, or for good when none is. More than one, in different
/// places: an end sends through all it knows of the other's until a path
/// is chosen, so one being down holds nothing up.
///
/// A relay only passes along what is sealed between the two ends; it
/// cannot read it.
const defaultLinkRelays = [
  'https://relay-us1.baocode.dev',
  'https://relay-hk1.baocode.dev',
  'https://relay-jp1.baocode.dev',
];

/// [text] as a relay URL (`https://host[:port]`, a bare host taken as
/// https), or null when it is not one.
String? parseRelayUrl(String text) {
  var value = text.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) return null;
  if (!value.contains('://')) value = 'https://$value';
  final Uri uri;
  try {
    uri = Uri.parse(value);
  } on FormatException {
    return null;
  }
  if ((uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
    return null;
  }
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  final port = uri.hasPort ? ':${uri.port}' : '';
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  return '${uri.scheme}://$host$port';
}

/// The relays to keep to: BaoCode's, and the user's own [custom] ones (a
/// self-hosted one, say). iroh keeps to the nearest that answers.
List<String> linkRelays([List<String> custom = const []]) => {
  ...defaultLinkRelays,
  for (final url in custom) ?parseRelayUrl(url),
}.toList();
