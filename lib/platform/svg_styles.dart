// flutter_svg reads presentation attributes and inline styles, but skips
// <style> elements. Resolve the static rules commonly emitted by SVG tools
// before handing the drawing to its compiler.

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as css;
import 'package:xml/xml.dart';

/// Inlines SVG styles with type, class, ID and compound selectors.
///
/// Only drawings with a <style> element are rewritten, and only the elements a
/// rule matches; inline declarations stay as written. Unsupported selectors and
/// conditional rules (such as @media) are skipped; they must not accidentally
/// become unconditional rules. No external sheets are fetched. Only allowlisted
/// drawing properties and inert values are taken from the stylesheet; URLs may
/// refer only to an ID in this SVG. A drawing past the limits below is given
/// back as it is, as flutter_svg would have drawn it without this step.
String svgWithStyles(String svg) {
  if (!svg.contains('<style')) return svg;
  try {
    return _inline(svg);
  } on _OverLimit {
    return svg;
  } on XmlException {
    return svg; // Left for the compiler to report.
  }
}

String _inline(String svg) {
  if (svg.length > _maxSvgLength) throw const _OverLimit();
  final document = XmlDocument.parse(svg);
  final elements = document.descendants
      .whereType<XmlElement>()
      .take(_maxElements + 1)
      .toList();
  if (elements.length > _maxElements) throw const _OverLimit();
  final budget = _StyleBudget();
  final rules = _Rules();
  for (final element in elements) {
    if (element.name.local != 'style') continue;
    final type = element.getAttribute('type');
    if (type != null && type != 'text/css') continue;
    final source = element.innerText;
    budget.addCss(source);
    for (final rule in css.parse(source).topLevels.whereType<css.RuleSet>()) {
      rules.add(rule, budget);
    }
  }
  // Do not leave ignored directives or malicious source text in the result.
  for (final element in elements.where((e) => e.name.local == 'style')) {
    element.parent?.children.remove(element);
  }

  for (final element in elements) {
    if (element.name.local == 'style') continue;
    final type = element.name.local;
    final id = element.getAttribute('id');
    final classes = (element.getAttribute('class') ?? '')
        .split(RegExp(r'\s+'))
        .where((name) => name.isNotEmpty)
        .toSet();
    final values = <String, _Value>{};
    for (final rule in rules.candidates(type, id, classes)) {
      budget.spend(1);
      if (!rule.matches(type, id, classes)) continue;
      for (final declaration in rule.declarations) {
        budget.spend(1);
        final value = _Value(declaration.text, declaration.important, rule);
        final previous = values[declaration.property];
        if (previous == null || value.overrides(previous)) {
          values[declaration.property] = value;
        }
      }
    }
    if (values.isEmpty) continue;

    // Inline declarations outrank selectors, except for stylesheet !important.
    final inline = <String, String>{};
    for (final declaration in (element.getAttribute('style') ?? '').split(
      ';',
    )) {
      final colon = declaration.indexOf(':');
      if (colon < 0) continue;
      final property = declaration.substring(0, colon).trim();
      var value = declaration.substring(colon + 1).trim();
      final important = _important.hasMatch(value);
      if (important) value = value.replaceFirst(_important, '').trim();
      if (property.isEmpty || value.isEmpty) continue;
      if (important || !(values[property]?.important ?? false)) {
        values.remove(property);
        inline[property] = value;
      }
    }
    // The compiler lets a later attribute override an earlier one, and
    // presentation attributes rank below styles: keep the style last.
    element.removeAttribute('style');
    element.setAttribute(
      'style',
      [
        for (final entry in values.entries) '${entry.key}:${entry.value.text}',
        for (final entry in inline.entries) '${entry.key}:${entry.value}',
      ].join(';'),
    );
  }
  return document.toXmlString();
}

// Like Zed's bounded SVG rasterization (gpui/src/svg_renderer.rs), this
// preprocessing stage needs its own limits. The work limit bounds the rules
// tried per element; these are not raster image dimensions.
const _maxSvgLength = 8 * 1024 * 1024;
const _maxCssLength = 256 * 1024;
const _maxElements = 20000;
const _maxStyleWork = 1000000;

class _OverLimit implements Exception {
  const _OverLimit();
}

class _StyleBudget {
  var _cssLength = 0;
  var _work = 0;

  void addCss(String source) {
    _cssLength += source.length;
    if (_cssLength > _maxCssLength) throw const _OverLimit();
  }

  void spend(int amount) {
    _work += amount;
    if (_work > _maxStyleWork) throw const _OverLimit();
  }
}

final _important = RegExp(r'!\s*important$', caseSensitive: false);

/// The supported rules of the stylesheets in source order, indexed by the ID,
/// a class or the type their selector requires, so an element only tries the
/// rules it may match.
class _Rules {
  final _byId = <String, List<_Rule>>{};
  final _byClass = <String, List<_Rule>>{};
  final _byType = <String, List<_Rule>>{};
  final _any = <_Rule>[];
  var _order = 0;

  void add(css.RuleSet rule, _StyleBudget budget) {
    final declarations = <_Declaration>[];
    for (final declaration
        in rule.declarationGroup.declarations.whereType<css.Declaration>()) {
      budget.spend(1);
      if (!_drawingProperties.contains(declaration.property)) continue;
      final expression = declaration.expression;
      if (expression == null) continue;
      final printer = css.CssPrinter();
      expression.visit(printer);
      final text = printer.toString().trim();
      budget.spend(text.length);
      if (!_safeValue(declaration.property, text)) continue;
      declarations.add(
        _Declaration(declaration.property, text, declaration.important),
      );
    }
    if (declarations.isEmpty) return;
    for (final selector in rule.selectorGroup?.selectors ?? <css.Selector>[]) {
      budget.spend(1 + selector.simpleSelectorSequences.length);
      final parsed = _Rule.parse(selector, declarations, _order++);
      if (parsed == null) continue;
      if (parsed.id case final id?) {
        (_byId[id] ??= []).add(parsed);
      } else if (parsed.classes.isNotEmpty) {
        (_byClass[parsed.classes.first] ??= []).add(parsed);
      } else if (parsed.type case final type?) {
        (_byType[type] ??= []).add(parsed);
      } else {
        _any.add(parsed);
      }
    }
  }

  /// Each rule at most once, in source order.
  List<_Rule> candidates(String type, String? id, Set<String> classes) => [
    ..._any,
    ...?_byType[type],
    if (id != null) ...?_byId[id],
    for (final name in classes) ...?_byClass[name],
  ]..sort((a, b) => a.order.compareTo(b.order));
}

class _Rule {
  const _Rule(
    this.id,
    this.classes,
    this.type,
    this.specificity,
    this.declarations,
    this.order,
  );

  /// The rule for a compound selector, or null for one this does not support
  /// (combinators, attributes, pseudo-classes, namespaces).
  static _Rule? parse(
    css.Selector selector,
    List<_Declaration> declarations,
    int order,
  ) {
    String? id;
    final classes = <String>[];
    String? type;
    var ids = 0;
    for (final sequence in selector.simpleSelectorSequences) {
      if (!sequence.isCombinatorNone) return null;
      final simple = sequence.simpleSelector;
      if (simple is css.IdSelector) {
        if (id != null && id != simple.name) return null;
        id = simple.name;
        ids++;
      } else if (simple is css.ClassSelector) {
        classes.add(simple.name);
      } else if (simple is css.ElementSelector) {
        if (!simple.isWildcard) {
          if (type != null && type != simple.name) return null;
          type = simple.name;
        }
      } else {
        return null;
      }
    }
    return _Rule(
      id,
      classes,
      type,
      (ids, classes.length, type == null ? 0 : 1),
      declarations,
      order,
    );
  }

  final String? id;
  final List<String> classes;
  final String? type;
  final (int, int, int) specificity;
  final List<_Declaration> declarations;
  final int order;

  bool matches(String type, String? id, Set<String> classes) =>
      (this.type == null || this.type == type) &&
      (this.id == null || this.id == id) &&
      this.classes.every(classes.contains);
}

class _Declaration {
  const _Declaration(this.property, this.text, this.important);

  final String property;
  final String text;
  final bool important;
}

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
  'mix-blend-mode',
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
final _colorValue = RegExp(r'^(?:rgb|rgba|hsl|hsla)\([0-9.,%+\-\s/]+\)$');
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

class _Value {
  const _Value(this.text, this.important, this.rule);

  final String text;
  final bool important;
  final _Rule rule;

  /// Rules arrive in source order, so the later one wins at equal specificity.
  bool overrides(_Value other) {
    if (important != other.important) return important;
    final (a1, a2, a3) = rule.specificity;
    final (b1, b2, b3) = other.rule.specificity;
    if (a1 != b1) return a1 > b1;
    if (a2 != b2) return a2 > b2;
    return a3 >= b3;
  }
}
