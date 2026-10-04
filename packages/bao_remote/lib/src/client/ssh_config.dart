import 'dart:io';

import 'package:path/path.dart' as p;

/// The hosts `~/.ssh/config` names, for the connect box to suggest: the
/// patterns of its `Host` lines without wildcards or negations, in order,
/// once each. `Include`d files are read too (a `*` in their last part
/// matches as the shell would), relative ones from `~/.ssh`.
Future<List<String>> sshConfigHosts({String? home, int depth = 0}) async {
  home ??= Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return const [];
  final dir = p.join(home, '.ssh');
  return _hostsIn(p.join(dir, 'config'), dir, {}, depth);
}

Future<List<String>> _hostsIn(
  String path,
  String sshDir,
  Set<String> seen,
  int depth,
) async {
  if (depth > 8 || !seen.add(path)) return const [];
  final String text;
  try {
    text = await File(path).readAsString();
  } on FileSystemException {
    return const [];
  }
  final hosts = <String>[];
  for (final (keyword, values) in sshConfigLines(text)) {
    if (keyword == 'host') {
      hosts.addAll(values.where(isConcreteHost));
    } else if (keyword == 'include') {
      for (final pattern in values) {
        final expanded = pattern.startsWith('~/')
            ? p.join(p.dirname(sshDir), pattern.substring(2))
            : p.isAbsolute(pattern)
            ? pattern
            : p.join(sshDir, pattern);
        for (final file in await _glob(expanded)) {
          hosts.addAll(await _hostsIn(file, sshDir, seen, depth + 1));
        }
      }
    }
  }
  return [
    for (final (i, host) in hosts.indexed)
      if (hosts.indexOf(host) == i) host,
  ];
}

/// The files [pattern] names: itself, or the matches of a `*` or `?` in its
/// last part.
Future<List<String>> _glob(String pattern) async {
  final name = p.basename(pattern);
  if (!name.contains(RegExp(r'[*?]'))) return [pattern];
  final regExp = RegExp(
    '^${RegExp.escape(name).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
  );
  try {
    return [
      await for (final entity in Directory(p.dirname(pattern)).list())
        if (entity is File && regExp.hasMatch(p.basename(entity.path)))
          entity.path,
    ]..sort();
  } on FileSystemException {
    return const [];
  }
}

/// The keyword (lower case) and values of each line of an ssh config,
/// comments and blank lines left out; `Keyword=value` and quoted values
/// as ssh reads them.
Iterable<(String, List<String>)> sshConfigLines(String text) sync* {
  for (var line in text.split(RegExp(r'\r?\n'))) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = RegExp(r'^(\S+?)(?:\s*=\s*|\s+)(.*)$').firstMatch(line);
    if (match == null) continue;
    final values = [
      for (final value in RegExp(r'"([^"]*)"|(\S+)').allMatches(match[2]!))
        value[1] ?? value[2]!,
    ];
    yield (match[1]!.toLowerCase(), values);
  }
}

/// Whether a `Host` pattern names one host: no wildcard or negation.
bool isConcreteHost(String pattern) =>
    pattern.isNotEmpty && !pattern.contains(RegExp(r'[*?!]'));
