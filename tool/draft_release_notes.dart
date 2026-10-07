// Drafts a release's notes from the commits since the last release:
// release-notes/<x.y.z>.en.md and release-notes/<x.y.z>.zh.md, the
// version pubspec.yaml's unless given. tool/bump_version.dart runs it.
//
//   dart run tool/draft_release_notes.dart [x.y.z]
//
// A draft, not notes: the commit subjects (feat → New, perf → Improved,
// fix → Fixed; not the site's, CI's, docs, tests or refactors) under the
// headings the notes keep, to be rewritten for the people who use the app,
// a few lines each, the Chinese ones in Chinese. They show as plain text
// in Settings → Updates (from latest.json), and as Markdown in the GitHub
// release and on the site (tool/build_changelog.dart): plain lines and `-`
// lists read well in all of them. A file already there is left alone.
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1 || arguments.firstOrNull?.startsWith('-') == true) {
    stderr.writeln('Usage: dart run tool/draft_release_notes.dart [x.y.z]');
    exit(1);
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final version = arguments.firstOrNull ?? _pubspecMarketing(root);
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    stderr.writeln('Not a version: $version (give x.y.z).');
    exit(1);
  }
  draftReleaseNotes(root, version);
}

/// Writes the draft notes for [version] in [root], where there are none,
/// and says what it did.
void draftReleaseNotes(Directory root, String version) {
  final since = _lastTag(root, before: 'v$version');
  final commits = _git(root, [
    'log',
    '--no-merges',
    '--format=%s',
    since == null ? 'HEAD' : '$since..HEAD',
  ]).split('\n').where((line) => line.isNotEmpty).toList();
  final sections = draftSections(commits);
  stdout.writeln(
    'Release notes for $version, drafted from ${commits.length} commits '
    'since ${since ?? 'the first'}:',
  );
  for (final (language, headings) in [
    ('en', _headingsEn),
    ('zh', _headingsZh),
  ]) {
    final file = File('${root.path}/release-notes/$version.$language.md');
    if (file.existsSync()) {
      stdout.writeln('  ${file.path} is already there, left alone');
      continue;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(draftText(sections, headings));
    stdout.writeln('  ${file.path}');
  }
  stdout
    ..writeln()
    ..writeln('Rewrite them for the people who use BaoCode (the Chinese in')
    ..writeln('Chinese), then make the site\'s changelog from them:')
    ..writeln()
    ..writeln('  dart run tool/build_changelog.dart');
}

/// The kinds of commit the notes tell of, in the order they do.
enum NoteSection { added, improved, fixed }

const _headingsEn = {
  NoteSection.added: 'New',
  NoteSection.improved: 'Improved',
  NoteSection.fixed: 'Fixed',
};
const _headingsZh = {
  NoteSection.added: '新功能',
  NoteSection.improved: '改进',
  NoteSection.fixed: '修复',
};

/// Scopes whose commits the people using the app do not see.
const _unseenScopes = {'site', 'ci'};

/// [subjects] (Conventional Commits) by the section each goes in, without
/// those no section tells of.
Map<NoteSection, List<String>> draftSections(List<String> subjects) {
  final pattern = RegExp(r'^(\w+)(?:\(([^)]*)\))?!?:\s*(.+)$');
  final sections = <NoteSection, List<String>>{};
  for (final subject in subjects) {
    final match = pattern.firstMatch(subject.trim());
    if (match == null || _unseenScopes.contains(match[2])) continue;
    final section = switch (match[1]) {
      'feat' => NoteSection.added,
      'perf' => NoteSection.improved,
      'fix' => NoteSection.fixed,
      _ => null,
    };
    if (section == null) continue;
    (sections[section] ??= []).add(match[3]!);
  }
  return sections;
}

/// [sections] as a notes file, under [headings].
String draftText(
  Map<NoteSection, List<String>> sections,
  Map<NoteSection, String> headings,
) {
  final blocks = [
    for (final section in NoteSection.values)
      if (sections[section] case final lines?)
        [headings[section], for (final line in lines) '- $line'].join('\n'),
  ];
  return '${blocks.isEmpty ? '- ' : blocks.join('\n\n')}\n';
}

/// The newest `v*` tag reachable from HEAD other than [before] (the
/// release being drafted, when it was tagged already); null when none.
String? _lastTag(Directory root, {required String before}) {
  final tags = _git(root, [
    'tag',
    '--merged',
    'HEAD',
    '--sort=-v:refname',
  ]).split('\n').where((tag) => RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag));
  return tags.where((tag) => tag != before).firstOrNull;
}

String _pubspecMarketing(Directory root) {
  final pubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
  final version = RegExp(
    r'^version:\s*([^+\s]+)',
    multiLine: true,
  ).firstMatch(pubspec)?[1];
  if (version == null) {
    stderr.writeln('No "version:" line in pubspec.yaml');
    exit(1);
  }
  return version;
}

String _git(Directory root, List<String> arguments) {
  final result = Process.runSync('git', arguments, workingDirectory: root.path);
  if (result.exitCode != 0) {
    stderr.writeln('git ${arguments.join(' ')}: ${result.stderr}');
    exit(1);
  }
  return (result.stdout as String).trim();
}
