// An SVG that picks its light or dark drawing with a `<style>`
// (`@media (prefers-color-scheme: dark)` showing and hiding classes, as the
// JetBrains icon theme's "Auto" icons do). The SVG renderer reads no CSS,
// so both drawings would show: [svgForColorScheme] hides, with a
// `display="none"` it does read, the elements the style hides in the
// scheme. Only `display` of class selectors is read.

final _style = RegExp(r'<style[^>]*>([\s\S]*?)</style>');
final _comment = RegExp(r'/\*[\s\S]*?\*/');
final _media = RegExp(
  r'@media\s*\(\s*prefers-color-scheme\s*:\s*(dark|light)\s*\)\s*\{'
  r'((?:[^{}]*\{[^{}]*\})*)[^{}]*\}',
);
final _rule = RegExp(r'([^{}]+)\{([^{}]*)\}');
final _display = RegExp(r'(?:^|;)\s*display\s*:\s*([\w-]+)');
final _classSelector = RegExp(r'^\.([\w-]+)$');
final _startTag = RegExp(r'<([A-Za-z][\w:.-]*)(\s[^<>]*?)?(/?)>');
final _classAttribute = RegExp(r'''\sclass\s*=\s*(?:"([^"]*)"|'([^']*)')''');

/// [svg] with what its style hides in the [dark] or light scheme hidden;
/// [svg] itself when its style does not depend on the scheme.
String svgForColorScheme(String svg, {required bool dark}) {
  if (!svg.contains('prefers-color-scheme')) return svg;
  final display = <String, String>{};
  void apply(String css) {
    for (final rule in _rule.allMatches(css)) {
      final value = _display.firstMatch(rule[2]!)?[1];
      if (value == null) continue;
      for (final selector in rule[1]!.split(',')) {
        if (_classSelector.firstMatch(selector.trim()) case final match?) {
          display[match[1]!] = value;
        }
      }
    }
  }

  for (final style in _style.allMatches(svg)) {
    final css = style[1]!.replaceAll(_comment, '');
    apply(css.replaceAll(_media, ''));
    for (final media in _media.allMatches(css)) {
      if ((media[1] == 'dark') == dark) apply(media[2]!);
    }
  }
  final hidden = {
    for (final MapEntry(:key, :value) in display.entries)
      if (value == 'none') key,
  };
  if (hidden.isEmpty) return svg;
  return svg.replaceAllMapped(_startTag, (tag) {
    final attributes = tag[2];
    if (attributes == null) return tag[0]!;
    final classes = switch (_classAttribute.firstMatch(attributes)) {
      final match? => (match[1] ?? match[2]!).split(RegExp(r'\s+')),
      null => const <String>[],
    };
    if (!classes.any(hidden.contains)) return tag[0]!;
    // Last, over a `display` of its own.
    return '<${tag[1]}$attributes display="none"${tag[3]}>';
  });
}
