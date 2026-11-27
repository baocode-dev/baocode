import 'dart:convert';

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
    final zsh = name == 'zsh' || name == 'zsh.exe';
    final bash = name == 'bash' || name == 'bash.exe';
    if ((zsh || bash) && path.runes.any(_escapeUnicode)) {
      // ZLE renders joiners as <200d>; emoji widths also differ between
      // shells and terminals. ANSI-C quoting keeps the input line printable
      // while the shell still receives the original Unicode filename.
      final escaped = path.runes.map((rune) {
        final char = String.fromCharCode(rune);
        if (_escapeUnicode(rune)) {
          if (zsh) {
            final width = rune > 0xffff ? 8 : 4;
            final prefix = rune > 0xffff ? r'\U' : r'\u';
            return '$prefix${rune.toRadixString(16).padLeft(width, '0')}';
          }
          // macOS's bash 3.2 supports octal UTF-8, but not \\u/\\U.
          return utf8
              .encode(char)
              .map((byte) => '\\${byte.toRadixString(8).padLeft(3, '0')}')
              .join();
        }
        return char == r'\' || char == "'" ? '\\$char' : char;
      }).join();
      return "\$'$escaped'";
    }
    // Backslash quoting works in sh, bash, zsh and fish, including apostrophes.
    return path.replaceAllMapped(_special, (match) => '\\${match[0]}');
  }

  return '${files.map(quote).join(' ')} ';
}

bool _escapeUnicode(int rune) =>
    rune > 0x7f &&
    ((rune >= 0xfe00 && rune <= 0xfe0f) ||
        (rune >= 0xe0100 && rune <= 0xe01ef) ||
        _unicodeSymbols.hasMatch(String.fromCharCode(rune)));

final _unicodeSymbols = RegExp(r'[\p{So}\p{Sk}\p{Cf}\p{Me}]', unicode: true);
final _controls = RegExp(r'[\x00-\x1f\x7f-\x9f]');
// Preserve Unicode names (including combining marks and emoji sequences).
// Only whitespace and shell syntax need backslash quoting.
final _special = RegExp(r'''[\s\\'"`$&;|<>(){}\[\]*?!#~^=]''', unicode: true);
