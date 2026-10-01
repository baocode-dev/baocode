// Replays test/fixtures/textmate/language_detection.json, recorded by
// tool/generate_language_detection_fixtures.mjs from the real VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971 languagesRegistry.ts,
// languagesAssociations.ts and glob.ts running in Node on darwin, linux and
// win32, against the Dart port with the same registrations. Every recorded
// result must match.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/vs/base/common/glob.dart' as glob;
import 'package:bao_editor/monaco/vs/base/common/platform.dart';
import 'package:bao_editor/monaco/vs/editor/common/services/languages_registry.dart';

final Map<String, Object?> _fixture = jsonDecode(
  File('test/fixtures/textmate/language_detection.json').readAsStringSync(),
) as Map<String, Object?>;

const Map<String, OperatingSystem> _platforms = {
  'darwin': OperatingSystem.macintosh,
  'linux': OperatingSystem.linux,
  'win32': OperatingSystem.windows,
};

List<ILanguageExtensionPoint> get _registrations => [
  for (final r in _fixture['registrations']! as List<Object?>)
    ILanguageExtensionPoint.fromJson(r! as Map<String, Object?>),
];

Uri? _uri(Object? spec, {required bool windows}) {
  if (spec == null) return null;
  final map = spec as Map<String, Object?>;
  if (map['file'] case final String path) {
    return Uri.file(path, windows: windows);
  }
  if (map['parse'] case final String value) return Uri.parse(value);
  final components = map['components']! as Map<String, Object?>;
  // Dart's Uri.parse rejects VS Code's `data:` metadata form.
  return Uri(
    scheme: components['scheme']! as String,
    path: components['path'] as String?,
  );
}

LanguagesRegistry _registry() =>
    LanguagesRegistry()..setDynamicLanguages(_registrations);

void main() {
  test('fixture provenance', () {
    expect(_fixture['revision'], '6a598d4a13031703d483d103c1d934a36ad27971');
    final registrations = _fixture['registrations']! as List<Object?>;
    expect(registrations, hasLength(greaterThan(80)));
    // The core plain text language comes from ModesRegistry, not the list.
    expect(
      registrations.every(
        (r) => (r! as Map<String, Object?>)['id'] != 'plaintext',
      ),
      isTrue,
    );
  });

  for (final MapEntry(key: platform, value: os) in _platforms.entries) {
    group(platform, () {
      final results =
          (_fixture['platforms']! as Map<String, Object?>)[platform]!
              as Map<String, Object?>;

      setUp(() => debugOperatingSystemOverride = os);
      tearDown(() => debugOperatingSystemOverride = null);

      test('guessLanguageIdByFilepathOrFirstLine', () {
        final cases = _fixture['cases']! as List<Object?>;
        final guesses = results['guesses']! as List<Object?>;
        final registry = _registry();
        final differences = <String>[];
        for (final entry in guesses) {
          final [index as int, expected as List<Object?>] =
              entry! as List<Object?>;
          final c = cases[index]! as Map<String, Object?>;
          final uri = _uri(c['uri'], windows: os == OperatingSystem.windows);
          final firstLine = c['firstLine'] as String?;
          final actual = registry.guessLanguageIdByFilepathOrFirstLine(
            uri,
            firstLine,
          );
          if (!listEquals(actual, expected.cast<String>())) {
            differences.add(
              '${jsonEncode(c)}: expected $expected, got $actual',
            );
          }
        }
        registry.dispose();
        expect(guesses, hasLength(greaterThan(1500)));
        expect(differences, isEmpty, reason: differences.join('\n'));
      });

      test('name, mime and codec lookups', () {
        final lookups = _fixture['lookups']! as Map<String, Object?>;
        final registry = _registry();
        final codec = registry.languageIdCodec;
        final differences = <String>[];
        void check(String what, Object? actual, Object? expected) {
          if (jsonEncode(actual) != jsonEncode(expected)) {
            differences.add('$what: expected $expected, got $actual');
          }
        }

        check(
          'getRegisteredLanguageIds',
          registry.getRegisteredLanguageIds(),
          lookups['registeredLanguageIds'],
        );
        check('getSortedRegisteredLanguageNames', [
          for (final p in registry.getSortedRegisteredLanguageNames())
            [p.languageName, p.languageId],
        ], lookups['sortedLanguageNames']);
        final languages = lookups['languages']! as Map<String, Object?>;
        for (final MapEntry(key: id, :value) in languages.entries) {
          check(id, {
            'name': registry.getLanguageName(id),
            'mimeType': registry.getMimeType(id),
            'extensions': registry.getExtensions(id),
            'filenames': registry.getFilenames(id),
            'configurationFiles': registry.getConfigurationFiles(id).length,
            'encoded': codec.encodeLanguageId(id),
          }, value);
        }
        for (final (key, lookup) in <(String, Object? Function(Object?))>[
          ('languageName', (id) => registry.getLanguageName(id! as String)),
          (
            'languageIdByName',
            (name) => registry.getLanguageIdByLanguageName(name! as String),
          ),
          (
            'languageIdByMime',
            (mime) => registry.getLanguageIdByMimeType(mime as String?),
          ),
          ('encode', (id) => codec.encodeLanguageId(id! as String)),
          ('decode', (id) => codec.decodeLanguageId(id! as int)),
          (
            'isRegistered',
            (id) => registry.isRegisteredLanguageId(id as String?),
          ),
        ]) {
          final pairs = lookups[key]! as List<Object?>;
          expect(pairs, isNotEmpty);
          for (final pair in pairs) {
            final [input, expected] = pair! as List<Object?>;
            check('$key(${jsonEncode(input)})', lookup(input), expected);
          }
        }
        registry.dispose();
        expect(differences, isEmpty, reason: differences.join('\n'));
      });

      test('glob.match matrix', () {
        final patterns = (_fixture['globPatterns']! as List<Object?>)
            .cast<String>();
        final paths = (_fixture['globPaths']! as List<Object?>).cast<String>();
        final expected = results['glob']! as Map<String, Object?>;
        final differences = <String>[];
        for (final ignoreCase in [false, true]) {
          final rows =
              expected[ignoreCase ? 'ignoreCase' : 'caseSensitive']!
                  as List<Object?>;
          for (var i = 0; i < patterns.length; i++) {
            final row = rows[i]! as String;
            for (var j = 0; j < paths.length; j++) {
              final actual = glob.match(
                patterns[i],
                paths[j],
                glob.IGlobOptions(ignoreCase: ignoreCase),
              );
              if (actual != (row[j] == '1')) {
                differences.add(
                  'match(${jsonEncode(patterns[i])}, ${jsonEncode(paths[j])}, '
                  'ignoreCase: $ignoreCase) should be ${row[j] == '1'}',
                );
              }
            }
          }
        }
        expect(differences, isEmpty, reason: differences.join('\n'));
      });
    });
  }
}
