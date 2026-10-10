/// An LSP glob pattern (`*`, `?`, `**`, `{a,b}`, `[a-z]`, `[!a]`), matched
/// against `/`-separated paths.
class LspGlob {
  LspGlob(this.pattern) : _regExp = RegExp('^${_translate(pattern)}\$');

  final String pattern;
  final RegExp _regExp;

  /// Whether [path] (either separator) matches the whole pattern.
  bool matches(String path) => _regExp.hasMatch(path.replaceAll(r'\', '/'));

  static String _translate(String glob) {
    final out = StringBuffer();
    var braces = 0;
    var i = 0;
    while (i < glob.length) {
      final c = glob[i];
      switch (c) {
        case '*':
          if (i + 1 < glob.length && glob[i + 1] == '*') {
            final atStart = i == 0 || glob[i - 1] == '/';
            i += 2;
            if (atStart && i < glob.length && glob[i] == '/') {
              // `**/`: any number of whole segments, none included.
              out.write('(?:[^/]*/)*');
              i++;
            } else {
              out.write('.*');
            }
            continue;
          }
          out.write('[^/]*');
        case '?':
          out.write('[^/]');
        case '{':
          braces++;
          out.write('(?:');
        case '}' when braces > 0:
          braces--;
          out.write(')');
        case ',' when braces > 0:
          out.write('|');
        case '[':
          final close = glob.indexOf(']', i + 2);
          if (close < 0) {
            out.write(r'\[');
          } else {
            var body = glob.substring(i + 1, close);
            final negated = body.startsWith('!') || body.startsWith('^');
            if (negated) body = body.substring(1);
            out
              ..write(negated ? '[^/' : '[')
              ..write(body.replaceAll(r'\', r'\\').replaceAll(']', r'\]'))
              ..write(']');
            i = close + 1;
            continue;
          }
        default:
          out.write(RegExp.escape(c));
      }
      i++;
    }
    for (; braces > 0; braces--) {
      out.write(')');
    }
    return out.toString();
  }
}
