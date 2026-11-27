/// File paths as arguments at the terminal's prompt, without executing them.
/// Control characters cannot safely be typed into a terminal, even quoted.
String? terminalFileDropText(Iterable<String> paths, {required String shell}) {
  final files = paths.toList();
  if (files.isEmpty ||
      files.any((path) => path.isEmpty || _controls.hasMatch(path))) {
    return null;
  }
  final name = shell.split(RegExp(r'[/\\]')).last.toLowerCase();
  String quote(String path) {
    if (name == 'pwsh' ||
        name == 'powershell' ||
        name == 'pwsh.exe' ||
        name == 'powershell.exe') {
      return "'${path.replaceAll("'", "''")}'";
    }
    if (name == 'cmd' || name == 'cmd.exe') return '"$path"';
    // Backslash quoting works in sh, bash, zsh and fish, including apostrophes.
    return path.replaceAllMapped(_special, (match) => '\\${match[0]}');
  }

  return '${files.map(quote).join(' ')} ';
}

final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');
final _special = RegExp(r'[^a-zA-Z0-9_./\-]', unicode: true);
