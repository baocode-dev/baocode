/// A mason-registry package source id, a package URL
/// (https://github.com/package-url/purl-spec):
/// `pkg:<type>/<namespace>/<name>@<version>?<qualifiers>#<subpath>`.
class MasonPurl {
  const MasonPurl({
    required this.type,
    required this.name,
    this.namespace,
    this.version,
    this.qualifiers = const {},
    this.subpath,
  });

  /// Parses [purl]; throws [FormatException] when it is not one. Segments
  /// are percent-decoded, so `pkg:npm/%40vue/language-server@3` has the
  /// namespace `@vue`.
  factory MasonPurl.parse(String purl) {
    if (!purl.startsWith('pkg:')) {
      throw FormatException('Not a package URL', purl);
    }
    var rest = purl.substring(4);
    String? subpath;
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      subpath = rest
          .substring(hash + 1)
          .split('/')
          .where((segment) => segment.isNotEmpty && segment != '.')
          .map(Uri.decodeComponent)
          .join('/');
      rest = rest.substring(0, hash);
    }
    final qualifiers = <String, String>{};
    final question = rest.indexOf('?');
    if (question >= 0) {
      for (final pair in rest.substring(question + 1).split('&')) {
        if (pair.isEmpty) continue;
        final equals = pair.indexOf('=');
        if (equals <= 0) throw FormatException('Bad qualifier "$pair"', purl);
        qualifiers[pair.substring(0, equals).toLowerCase()] =
            Uri.decodeComponent(pair.substring(equals + 1));
      }
      rest = rest.substring(0, question);
    }
    String? version;
    final at = rest.lastIndexOf('@');
    if (at > rest.lastIndexOf('/')) {
      version = Uri.decodeComponent(rest.substring(at + 1));
      rest = rest.substring(0, at);
    }
    final segments = rest.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) {
      throw FormatException('A package URL needs a type and a name', purl);
    }
    return MasonPurl(
      type: segments.first.toLowerCase(),
      namespace: segments.length > 2
          ? segments
                .sublist(1, segments.length - 1)
                .map(Uri.decodeComponent)
                .join('/')
          : null,
      name: Uri.decodeComponent(segments.last),
      version: version,
      qualifiers: qualifiers,
      subpath: subpath == null || subpath.isEmpty ? null : subpath,
    );
  }

  final String type;
  final String? namespace;
  final String name;
  final String? version;
  final Map<String, String> qualifiers;
  final String? subpath;

  /// Namespace and name: an npm `@scope/name`, a Go module path, a GitHub
  /// `owner/repo`.
  String get fullName => namespace == null ? name : '$namespace/$name';

  @override
  String toString() {
    final buffer = StringBuffer('pkg:$type/$fullName');
    if (version != null) buffer.write('@$version');
    if (qualifiers.isNotEmpty) {
      buffer.write('?');
      buffer.write(
        qualifiers.entries
            .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
            .join('&'),
      );
    }
    if (subpath != null) buffer.write('#$subpath');
    return buffer.toString();
  }
}
