// Sets the app's version for a release: pubspec.yaml's `version:` and
// lib/update/version.dart's appVersionString, which have to agree
// (test/update/version_test.dart), with the build number one past the
// current one. Run from anywhere in the repository:
//
//   dart run tool/bump_version.dart patch     1.2.0+12 -> 1.2.1+13
//   dart run tool/bump_version.dart minor     1.2.0+12 -> 1.3.0+13
//   dart run tool/bump_version.dart major     1.2.0+12 -> 2.0.0+13
//   dart run tool/bump_version.dart 1.2.3     1.2.0+12 -> 1.2.3+13
//
// The build number only ever goes up: the app is offered an update when
// the manifest's version is newer than its own, build numbers counted
// (docs/auto-update.md). It drafts the release's notes too
// (tool/draft_release_notes.dart). Rewrite them, make the site's changelog
// (tool/build_changelog.dart), then commit, and push the tag it prints: CI
// builds and publishes the release (.github/workflows/release.yml).
import 'dart:io';

import 'package:baocode/update/version.dart';

import 'draft_release_notes.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || arguments.first.startsWith('-')) {
    _fail('Usage: dart run tool/bump_version.dart <patch|minor|major|x.y.z>');
  }
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final pubspec = File('${root.path}/pubspec.yaml');
  final source = File('${root.path}/lib/update/version.dart');

  final pubspecPattern = RegExp(r'^version:\s*(\S+)', multiLine: true);
  final sourcePattern = RegExp(
    r"^const appVersionString = '([^']*)';",
    multiLine: true,
  );
  final pubspecText = pubspec.readAsStringSync();
  final sourceText = source.readAsStringSync();
  final currentText = pubspecPattern.firstMatch(pubspecText)?.group(1);
  if (currentText == null) _fail('No "version:" line in ${pubspec.path}');
  if (!sourcePattern.hasMatch(sourceText)) {
    _fail('No appVersionString in ${source.path}');
  }
  final current = AppVersion.parse(currentText);

  final argument = arguments.first;
  final marketing = switch (argument) {
    'patch' => '${current.major}.${current.minor}.${current.patch + 1}',
    'minor' => '${current.major}.${current.minor + 1}.0',
    'major' => '${current.major + 1}.0.0',
    _ => argument,
  };
  final parsed = AppVersion.tryParse(marketing);
  if (parsed == null ||
      parsed.build != 0 ||
      !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(marketing)) {
    _fail('Not a version: $argument (give x.y.z, without a build number).');
  }
  final next = AppVersion.parse('$marketing+${current.build + 1}');
  if (next <= current) {
    _fail('$next would not be newer than $current.');
  }

  pubspec.writeAsStringSync(
    pubspecText.replaceFirst(pubspecPattern, 'version: $next'),
  );
  source.writeAsStringSync(
    sourceText.replaceFirst(sourcePattern, "const appVersionString = '$next';"),
  );
  stdout
    ..writeln('$current -> $next')
    ..writeln('  ${pubspec.path}')
    ..writeln('  ${source.path}')
    ..writeln();
  draftReleaseNotes(Directory(root.path), next.marketing);
  stdout
    ..writeln()
    ..writeln('Then commit, and publish with:')
    ..writeln()
    ..writeln(
      '  git tag v${next.marketing} && git push origin v${next.marketing}',
    );
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
