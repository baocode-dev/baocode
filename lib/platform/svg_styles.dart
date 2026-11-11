// flutter_svg reads presentation attributes and inline styles, but skips
// <style> elements. Resolve the static rules commonly emitted by SVG tools
// before handing the drawing to its compiler.

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as css;
import 'package:xml/xml.dart';

/// Inlines SVG styles with type, class, ID and compound selectors.
///
/// Unsupported selectors and conditional rules (such as @media) are skipped;
/// they must not accidentally become unconditional rules. No external sheets
/// are fetched. Only allowlisted drawing properties and inert values survive;
/// URLs may refer only to an ID in this SVG. This handles CSS, not arbitrary
/// SVG content such as image attributes or event handlers.
String svgWithStyles(String svg) {
  if (!svg.contains('<style') && !_inlineStyle.hasMatch(svg)) return svg;
  if (svg.length > _maxSvgLength) {
    throw const FormatException('SVG exceeds the stylesheet input limit');
  }
  final document = XmlDocument.parse(svg);
  final elements = document.descendants
      .whereType<XmlElement>()
      .take(_maxElements + 1)
      .toList();
  if (elements.length > _maxElements) {
    throw const FormatException('SVG has too many elements for styling');
  }
  final budget = _StyleBudget();
  final rules = <css.RuleSet>[];
  for (final element in elements) {
    if (element.name.local != 'style') continue;
    final type = element.getAttribute('type');
    if (type != null && type != 'text/css') continue;
    final source = element.innerText;
    budget.addCss(source);
    rules.addAll(css.parse(source).topLevels.whereType<css.RuleSet>());
  }
  // Do not leave ignored directives or malicious source text in the result.
  for (final element in elements.where((e) => e.name.local == 'style')) {
    element.parent?.children.remove(element);
  }

  for (final element in elements) {
    if (element.name.local == 'style') continue;
    final values = <String, _Value>{};
    final classes = (element.getAttribute('class') ?? '')
        .split(RegExp(r'\s+'))
        .toSet();
    void apply(Iterable<css.TreeNode> declarations, (int, int, int, int) rank) {
      for (final declaration in declarations.whereType<css.Declaration>()) {
        budget.spend(1);
        if (!_drawingProperties.contains(declaration.property)) continue;
        final expression = declaration.expression;
        if (expression == null) continue;
        final printer = css.CssPrinter();
        expression.visit(printer);
        final text = printer.toString().trim();
        budget.spend(text.length);
        if (!_safeValue(declaration.property, text)) continue;
        final value = _Value(text, declaration.important, rank);
        final previous = values[declaration.property];
        if (previous == null || value.overrides(previous)) {
          values[declaration.property] = value;
        }
      }
    }

    for (final rule in rules) {
      for (final selector
          in rule.selectorGroup?.selectors ?? <css.Selector>[]) {
        budget.spend(1 + selector.simpleSelectorSequences.length);
        final rank = _matchingRank(selector, element, classes);
        if (rank != null) apply(rule.declarationGroup.declarations, rank);
      }
    }
    // Sanitize inline declarations even if no stylesheet rule matched.
    // Inline declarations outrank selectors, except for stylesheet !important.
    final inline = element.getAttribute('style');
    if (inline != null) {
      budget.addCss(inline);
      for (final rule
          in css.parse('svg {$inline}').topLevels.whereType<css.RuleSet>()) {
        apply(rule.declarationGroup.declarations, (1, 0, 0, 0));
      }
    }
    if (values.isEmpty) {
      element.removeAttribute('style');
      continue;
    }
    element.setAttribute(
      'style',
      values.entries
          .map((entry) => '${entry.key}:${entry.value.text}')
          .join(';'),
    );
  }
  return document.toXmlString();
}

// Like Zed's bounded SVG rasterization (gpui/src/svg_renderer.rs), this
// preprocessing stage needs its own limits. The selector work limit bounds
// the elements × rules expansion; these are not raster image dimensions.
const _maxSvgLength = 8 * 1024 * 1024;
const _maxCssLength = 256 * 1024;
const _maxElements = 20000;
const _maxStyleWork = 1000000;

class _StyleBudget {
  var _cssLength = 0;
  var _work = 0;

  void addCss(String source) {
    _cssLength += source.length;
    if (_cssLength > _maxCssLength) {
      throw const FormatException('SVG exceeds the CSS input limit');
    }
  }

  void spend(int amount) {
    _work += amount;
    if (_work > _maxStyleWork) {
      throw const FormatException('SVG exceeds the CSS processing limit');
    }
  }
}

final _inlineStyle = RegExp(r'\bstyle\s*=');

const _drawingProperties = {
  'fill',
  'fill-opacity',
  'fill-rule',
  'stroke',
  'stroke-opacity',
  'stroke-width',
  'stroke-linecap',
  'stroke-linejoin',
  'stroke-miterlimit',
  'stroke-dasharray',
  'stroke-dashoffset',
  'opacity',
  'color',
  'stop-color',
  'stop-opacity',
  'clip-path',
  'clip-rule',
  'mask',
  'font-family',
  'font-size',
  'font-style',
  'font-weight',
  'text-anchor',
  'text-decoration',
  'text-decoration-color',
  'text-decoration-style',
  'dominant-baseline',
  'alignment-baseline',
  'letter-spacing',
  'word-spacing',
  'display',
  'visibility',
};

// Validate the parser's serialized value, so escapes/comments cannot hide a
// function or URL. Plain values have no CSS delimiters or executable syntax.
final _plainValue = RegExp(r'''^[a-zA-Z0-9_\u0080-￿\s#.,%+"'\-]+$''');
final _colorValue = RegExp(r'^(?:rgb|rgba|hsl|hsla)\([0-9.,%+\-\s]+\)$');
final _localUrl = RegExp(
  r'''^url\((?:#[a-zA-Z_][\w.\-]*|"#[a-zA-Z_][\w.\-]*"|'#[a-zA-Z_][\w.\-]*')\)$''',
);

bool _safeValue(String property, String value) {
  if (_plainValue.hasMatch(value)) return true;
  if ({
        'fill',
        'stroke',
        'color',
        'stop-color',
        'text-decoration-color',
      }.contains(property) &&
      _colorValue.hasMatch(value)) {
    return true;
  }
  return {'fill', 'stroke', 'clip-path', 'mask'}.contains(property) &&
      _localUrl.hasMatch(value);
}

(int, int, int, int)? _matchingRank(
  css.Selector selector,
  XmlElement element,
  Set<String> elementClasses,
) {
  var ids = 0;
  var classes = 0;
  var types = 0;
  for (final sequence in selector.simpleSelectorSequences) {
    if (!sequence.isCombinatorNone) return null;
    final simple = sequence.simpleSelector;
    if (simple is css.IdSelector) {
      if (element.getAttribute('id') != simple.name) return null;
      ids++;
    } else if (simple is css.ClassSelector) {
      if (!elementClasses.contains(simple.name)) return null;
      classes++;
    } else if (simple is css.ElementSelector) {
      if (!simple.isWildcard) {
        if (element.name.local != simple.name) return null;
        types++;
      }
    } else {
      return null;
    }
  }
  return (0, ids, classes, types);
}

class _Value {
  const _Value(this.text, this.important, this.rank);

  final String text;
  final bool important;
  final (int, int, int, int) rank;

  bool overrides(_Value other) {
    if (important != other.important) return important;
    final a = [rank.$1, rank.$2, rank.$3, rank.$4];
    final b = [other.rank.$1, other.rank.$2, other.rank.$3, other.rank.$4];
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return true; // The last declaration wins at equal specificity.
  }
}
