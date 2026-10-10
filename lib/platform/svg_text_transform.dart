// SVG text under a scale, as shields.io's badges draw it (`font-size="110"`
// with `transform="scale(.1)"`). The SVG compiler folds a transform it can
// (a positive scale, a move) into the text's position and drops it, so the
// font keeps its unscaled size: the text is drawn ten times too large. A
// transform it cannot fold it keeps, and the text is drawn under it, font
// and all. [svgWithTextTransforms] gives every `<text>` a skew too small to
// see, so that its transform is kept.

import 'package:flutter_svg/flutter_svg.dart';

/// [SvgBytesLoader] with [svgWithTextTransforms] applied (in the loader's
/// isolate, and cached as the SVG it gives).
class SvgTextBytesLoader extends SvgBytesLoader {
  const SvgTextBytesLoader(super.bytes);

  @override
  String provideSvg(void message) =>
      svgWithTextTransforms(super.provideSvg(message));

  @override
  int get hashCode => Object.hash(SvgTextBytesLoader, super.hashCode);

  @override
  bool operator ==(Object other) =>
      other is SvgTextBytesLoader && super == other;
}

final _textTag = RegExp(r'<text\b([^>]*?)(/?)>');
final _transform = RegExp(r'''\stransform\s*=\s*(?:"([^"]*)"|'([^']*)')''');

/// A skew of a millionth (of a radian, as the compiler reads it; a degree,
/// as the spec does): under 10000px of text, under a hundredth of a pixel.
const _skew = 'skewX(0.000001)';

/// [svg] with its texts' transforms kept when drawn; [svg] itself when it
/// has no text or no transform.
String svgWithTextTransforms(String svg) {
  if (!svg.contains('<text') || !svg.contains('transform')) return svg;
  return svg.replaceAllMapped(_textTag, (tag) {
    final attributes = tag[1]!;
    final close = tag[2]!;
    final transform = _transform.firstMatch(attributes);
    if (transform == null) {
      return '<text$attributes transform="$_skew"$close>';
    }
    final value = transform[1] ?? transform[2]!;
    return '<text${attributes.replaceRange(transform.start, transform.end, ' transform="$value $_skew"')}$close>';
  });
}
