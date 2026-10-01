import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/flutter/language_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const assets = MonacoLanguageAssets();

  test(
    'loads all pinned language definitions without losing regexes',
    () async {
      final names = await assets.availableLanguages();
      expect(names, hasLength(86));
      expect(
        names,
        containsAll(['dart', 'python', 'typescript', 'freemarker2']),
      );
      for (final id in names) {
        final grammar = await assets.load(id);
        expect(grammar.id, id);
        expect(grammar.definition['tokenizer'], isA<Map>(), reason: id);
      }
    },
  );

  test(
    'resolves upstream registered extensions and shared grammar IDs',
    () async {
      final registrations = await assets.registrations();
      expect(registrations, hasLength(89));
      expect((await assets.forPath('lib/main.dart'))?.id, 'dart');
      expect((await assets.forPath('include/example.h'))?.id, 'c');
      expect((await assets.forPath('lib/main.c'))?.id, 'c');
      expect(
        (await assets.forPath(
          'script',
          firstLine: '#!/usr/bin/env python3',
        ))?.id,
        'python',
      );
      expect((await assets.forPath('unknown.not-a-monaco-language')), isNull);
      final c = await assets.loadRegistered('c');
      expect(c.id, 'c');
      expect(c.definition['tokenizer'], isA<Map>());
    },
  );

  test('compiles the actual pinned Dart grammar', () async {
    final language = await assets.load('dart');
    final lexer = language.compile();
    expect(lexer.languageId, 'dart');
    expect(lexer.tokenizer, contains('root'));
    final patterns = language.definition['tokenizer'] as Map<String, Object?>;
    expect(patterns['root'].toString(), contains('RegExp'));
  });

  test('compiles every bundled Monarch grammar', () async {
    final failed = <String, String>{};
    for (final id in await assets.availableLanguages()) {
      try {
        (await assets.load(id)).compile();
      } catch (error) {
        failed[id] = '$error';
      }
    }
    expect(failed, isEmpty);
  });

  test('rejects unregistered names before loading asset paths', () async {
    await expectLater(assets.load('../../pubspec.yaml'), throwsArgumentError);
  });
}
