// Where a forge is: its scheme (https unless a self-hosted one is served
// over http) and the authority accounts are named by (the host, with the
// port when it is not the scheme's default).

/// [typed] as a user gives it (`gitlab.corp`, `http://gitlab.corp:8080`,
/// `https://gitlab.corp/`): its scheme, and its authority. A path is left
/// out, as a forge is named by its server alone.
({String scheme, String host}) forgeAddress(String typed) {
  final text = typed.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null || uri.host.isEmpty) {
    return (scheme: 'https', host: text.toLowerCase());
  }
  return (
    scheme: uri.scheme == 'http' ? 'http' : 'https',
    host: forgeAuthority(uri),
  );
}

/// [uri]'s authority as accounts are named: its host, lowercased, and the
/// port when it is not the scheme's default (`gitlab.corp:8080`).
String forgeAuthority(Uri uri) {
  final host = uri.host.toLowerCase();
  if (!uri.hasPort) return host;
  return '${host.contains(':') ? '[$host]' : host}:${uri.port}';
}

/// [scheme]`://`[host] with [path] (and [query]).
Uri forgeUri(
  String scheme,
  String host,
  String path, {
  Map<String, String>? query,
}) => Uri.parse('$scheme://$host').replace(path: path, queryParameters: query);
