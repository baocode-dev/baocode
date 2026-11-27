/// File paths as arguments at the terminal's prompt, without executing them.
/// Control characters cannot safely be typed into a terminal, even quoted.
String? terminalFileDropText(Iterable<String> paths, {required String shell}) {
  final files = paths.toList();
  if (files.isEmpty ||
      files.any((path) => path.isEmpty || _controls.hasMatch(path))) {
    return null;
  }
  final name = shell.split(RegExp(r'[/\\]')).last.toLowerCase();
  if (name == 'cmd' || name == 'cmd.exe') {
    if (files.any((path) => path.contains('"'))) return null;
    String quoteCmd(String path) =>
        _cmdSpecial.hasMatch(path) ? '"$path"' : path;
    return '${files.map(quoteCmd).join(' ')} ';
  }
  if (name == 'pwsh' ||
      name == 'powershell' ||
      name == 'pwsh.exe' ||
      name == 'powershell.exe') {
    String quotePowerShell(String path) {
      if (!_powerShellSpecial.hasMatch(path)) return path;
      // PowerShell treats curly single quotes as single-quote delimiters too.
      final escaped = path.replaceAllMapped(
        _powerShellSingleQuote,
        (match) => '${match[0]}${match[0]}',
      );
      return "'$escaped'";
    }

    return '${files.map(quotePowerShell).join(' ')} ';
  }
  // Backslash quoting preserves Unicode names literally and works across
  // sh, bash, zsh, dash and fish, including apostrophes and whitespace.
  String quotePosix(String path) =>
      path.replaceAllMapped(_posixSpecial, (match) => '\\${match[0]}');
  return '${files.map(quotePosix).join(' ')} ';
}

final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');
final _cmdSpecial = RegExp(r'[\s&|<>()^;,=!%]', unicode: true);
final _powerShellSpecial = RegExp(
  r'''[\s'"‘’‚‛$`&;|<>(){}\[\]*?#,@~%!]''',
  unicode: true,
);
final _powerShellSingleQuote = RegExp(r"['‘’‚‛]");
final _posixSpecial = RegExp(
  r'''[\s\\'"`$&;|<>(){}\[\]*?!#~^=%]''',
  unicode: true,
);
