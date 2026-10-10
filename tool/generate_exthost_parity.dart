// Generates docs/extensions/EXTHOST_PARITY.md: for every main thread shape of
// the extension host protocol, which `$` methods BaoCode implements.
//
// A method is implemented when a class under lib/extensions/ extends the
// shape's generated `MainThread*Unsupported` fallback (directly or through
// another such class) and overrides it. Everything else is answered with
// `RpcUnsupported` and counted at run time by `ExtHostParity`.
//
// Run from the repository root:
//   dart run tool/generate_exthost_parity.dart [--check]
// `--check` fails, writing nothing, when the report is out of date.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart' show exthostProtocolMethods;

const _sources = 'lib/extensions';
const exthostParityOutput = 'docs/extensions/EXTHOST_PARITY.md';

/// A class that (eventually) extends a `MainThread*Unsupported`.
final class _Impl {
  _Impl(this.name, this.superclass, this.file, this.overrides);

  final String name;
  final String superclass;
  final String file;
  final Set<String> overrides;

  /// The `MainContext` key, once resolved.
  String? shape;

  /// [overrides] and what the superclasses override.
  final methods = <String>{};
}

final _classPattern = RegExp(
  r'\bclass\s+(\w+)(?:\s*<[^{>]*>)?\s+extends\s+(\w+)(?:\s*<[^{>]*>)?[^{]*\{',
);
final _overridePattern = RegExp(
  r'@override\s+(?:@[\w.]+(?:\([^)]*\))?\s+)*[^;{}()=]*?(\$\w+)\s*\(',
);

void main(List<String> arguments) {
  final check = arguments.contains('--check');
  final (:report, :warnings) = exthostParityReport();
  for (final w in warnings) {
    stderr.writeln('warning: $w');
  }
  final out = File(exthostParityOutput);
  if (check) {
    if (!out.existsSync() || out.readAsStringSync() != report) {
      stderr.writeln(
        '$exthostParityOutput is out of date: run dart run tool/generate_exthost_parity.dart',
      );
      exit(1);
    }
    return;
  }
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(report);
  stdout.writeln('Wrote $exthostParityOutput');
}

/// The report for the sources under lib/extensions, and what in them did
/// not fit a shape. Read from the current directory (the repository root).
({String report, List<String> warnings}) exthostParityReport() {
  final impls = <String, _Impl>{};
  final dir = Directory(_sources);
  if (dir.existsSync()) {
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final text = _stripComments(file.readAsStringSync());
      for (final match in _classPattern.allMatches(text)) {
        final body = _body(text, match.end - 1);
        final overrides = {
          for (final m in _overridePattern.allMatches(_topLevel(body))) m[1]!,
        };
        impls[match[1]!] = _Impl(
          match[1]!,
          match[2]!,
          file.path.replaceAll(r'\', '/'),
          overrides,
        );
      }
    }
  }

  // Resolve each class's shape and inherited overrides.
  String? resolve(_Impl impl, Set<String> seen) {
    if (impl.shape != null) return impl.shape;
    if (!seen.add(impl.name)) return null;
    final direct = RegExp(r'^(MainThread\w+)Unsupported$')
        .firstMatch(impl.superclass);
    if (direct != null) {
      impl.shape = direct[1];
    } else {
      final parent = impls[impl.superclass];
      if (parent == null || resolve(parent, seen) == null) return null;
      impl.shape = parent.shape;
      impl.methods.addAll(parent.methods);
    }
    impl.methods.addAll(impl.overrides);
    return impl.shape;
  }

  final byShape = <String, List<_Impl>>{};
  final warnings = <String>[];
  for (final impl in impls.values) {
    final shape = resolve(impl, {});
    if (shape == null) continue;
    final known = exthostProtocolMethods[shape];
    if (known == null) {
      warnings.add(
        '${impl.file}: ${impl.name} extends an unknown shape $shape',
      );
      continue;
    }
    for (final m in impl.overrides.difference(known.toSet())) {
      warnings.add('${impl.file}: ${impl.name} overrides $m, not in $shape');
    }
    byShape.putIfAbsent(shape, () => []).add(impl);
  }

  return (report: _render(byShape), warnings: warnings);
}

String _render(Map<String, List<_Impl>> byShape) {
  var total = 0;
  var implemented = 0;
  var shapesStarted = 0;
  final rows = <String>[];
  final details = <String>[];
  for (final MapEntry(key: shape, value: methods)
      in exthostProtocolMethods.entries) {
    final impls = byShape[shape] ?? const [];
    // A method counts when any implementation of the shape overrides it.
    final done = {
      for (final impl in impls) ...impl.methods.where(methods.contains),
    };
    total += methods.length;
    implemented += done.length;
    if (done.isNotEmpty) shapesStarted++;
    final where = impls.isEmpty
        ? '—'
        : impls.map((i) => '`${i.name}` (${i.file})').join(', ');
    rows.add('| $shape | ${done.length}/${methods.length} | $where |');
    final missing = methods.where((m) => !done.contains(m)).toList();
    details
      ..add('### $shape')
      ..add('')
      ..add(
        '- Implemented (${done.length}): '
        '${done.isEmpty ? '—' : [for (final m in methods.where(done.contains)) '`$m`'].join(', ')}',
      )
      ..add(
        '- Unsupported (${missing.length}): '
        '${missing.isEmpty ? '—' : [for (final m in missing) '`$m`'].join(', ')}',
      )
      ..add('');
  }
  final percent = total == 0 ? 0 : (implemented * 100 / total).round();
  return [
    '# Extension host protocol parity',
    '',
    '<!-- Generated by tool/generate_exthost_parity.dart; do not edit. -->',
    '',
    'The main thread shapes of VS Code 1.135.0\'s extension host protocol',
    '(`extHost.protocol.ts`) and which of their methods BaoCode implements: a class',
    'under `$_sources/` that extends a generated `MainThread*Unsupported` and',
    'overrides the method. Every other method replies `RpcUnsupported` and is counted',
    'at run time by `ExtHostParity`.',
    '',
    '**Total: $implemented/$total methods ($percent%), '
        '$shapesStarted/${exthostProtocolMethods.length} shapes started.**',
    '',
    '| Shape | Implemented | Implementations |',
    '| --- | --- | --- |',
    ...rows,
    '',
    '## Methods by shape',
    '',
    ...details,
  ].join('\n');
}

/// [text] without comments, and with every string literal emptied (and a
/// space after it: two emptied next to each other, as in `'${m['k']}'`,
/// would read as a triple quote).
String _stripComments(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text.startsWith('//', i)) {
      final end = text.indexOf('\n', i);
      i = end == -1 ? text.length : end;
    } else if (text.startsWith('/*', i)) {
      final end = text.indexOf('*/', i + 2);
      i = end == -1 ? text.length : end + 2;
    } else if (text[i] == "'" || text[i] == '"') {
      i = _stringEnd(text, i);
      out.write("'' ");
    } else {
      out.write(text[i]);
      i++;
    }
  }
  return out.toString();
}

/// Where the string literal starting at [start] ends (single-line and
/// triple-quoted, raw or not; interpolations are skipped over as text).
int _stringEnd(String text, int start) {
  final raw = start > 0 && text[start - 1] == 'r';
  final q = text[start];
  final triple = text.startsWith('$q$q$q', start);
  final close = triple ? '$q$q$q' : q;
  var i = start + close.length;
  while (i < text.length) {
    if (!raw && text[i] == r'\') {
      i += 2;
      continue;
    }
    if (text.startsWith(close, i)) return i + close.length;
    if (!triple && text[i] == '\n') return i;
    i++;
  }
  return text.length;
}

/// The class body whose `{` is at [open], without the braces.
String _body(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    final c = text[i];
    if (c == "'" || c == '"') {
      i = _stringEnd(text, i) - 1;
    } else if (c == '{') {
      depth++;
    } else if (c == '}' && --depth == 0) {
      return text.substring(open + 1, i);
    }
  }
  return text.substring(open + 1);
}

/// [body] with nested braces' contents blanked, so that only the class's own
/// members are seen.
String _topLevel(String body) {
  final out = StringBuffer();
  var depth = 0;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (c == "'" || c == '"') {
      final end = _stringEnd(body, i);
      if (depth == 0) out.write(body.substring(i, end));
      i = end - 1;
      continue;
    }
    if (c == '{') depth++;
    if (depth == 0) out.write(c);
    if (c == '}') {
      depth--;
      if (depth == 0) out.write(';');
    }
  }
  return out.toString();
}
