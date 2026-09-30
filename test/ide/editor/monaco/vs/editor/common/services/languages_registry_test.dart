// Port of VS Code src/vs/editor/test/common/services/languagesRegistry.test.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971. `new LanguagesRegistry(false)`
// is `LanguagesRegistry(useModesRegistry: false)`, `_registerLanguages` is
// `registerLanguages`, and configuration files are strings instead of URIs.

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/editor/monaco/vs/base/common/lifecycle.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/languages/modes_registry.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/services/languages_associations.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/services/languages_registry.dart';
import 'package:monad/ide/editor/monaco/vs/editor/common/tokens/line_tokens.dart';

void main() {
  group('LanguagesRegistry', () {
    // Upstream: ensureNoDisposablesAreLeakedInTestSuite.
    late int instances;
    setUp(() => instances = LanguagesRegistry.instanceCount);
    tearDown(() => expect(LanguagesRegistry.instanceCount, instances));

    test('output language does not have a name', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'outputLangId',
          extensions: [],
          aliases: [],
          mimetypes: ['outputLanguageMimeType'],
        ),
      ]);

      expect(registry.getSortedRegisteredLanguageNames(), isEmpty);

      registry.dispose();
    });

    test('language with alias does have a name', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'langId',
          extensions: [],
          aliases: ['LangName'],
          mimetypes: ['bla'],
        ),
      ]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'LangName', languageId: 'langId'),
      ]);
      expect(registry.getLanguageName('langId'), 'LangName');

      registry.dispose();
    });

    test('language without alias gets a name', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'langId',
          extensions: [],
          mimetypes: ['bla'],
        ),
      ]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'langId', languageId: 'langId'),
      ]);
      expect(registry.getLanguageName('langId'), 'langId');

      registry.dispose();
    });

    test('bug #4360: f# not shown in status bar', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'langId',
          extensions: ['.ext1'],
          aliases: ['LangName'],
          mimetypes: ['bla'],
        ),
      ]);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'langId',
          extensions: ['.ext2'],
          aliases: [],
          mimetypes: ['bla'],
        ),
      ]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'LangName', languageId: 'langId'),
      ]);
      expect(registry.getLanguageName('langId'), 'LangName');

      registry.dispose();
    });

    test('issue #5278: Extension cannot override language name anymore', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'langId',
          extensions: ['.ext1'],
          aliases: ['LangName'],
          mimetypes: ['bla'],
        ),
      ]);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'langId',
          extensions: ['.ext2'],
          aliases: ['BetterLanguageName'],
          mimetypes: ['bla'],
        ),
      ]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'BetterLanguageName', languageId: 'langId'),
      ]);
      expect(registry.getLanguageName('langId'), 'BetterLanguageName');

      registry.dispose();
    });

    test('mimetypes are generated if necessary', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([const ILanguageExtensionPoint(id: 'langId')]);

      expect(registry.getMimeType('langId'), 'text/x-langId');

      registry.dispose();
    });

    test('first mimetype wins', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'langId',
          mimetypes: ['text/langId', 'text/langId2'],
        ),
      ]);

      expect(registry.getMimeType('langId'), 'text/langId');

      registry.dispose();
    });

    test('first mimetype wins 2', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([const ILanguageExtensionPoint(id: 'langId')]);

      registry.registerLanguages([
        const ILanguageExtensionPoint(id: 'langId', mimetypes: ['text/langId']),
      ]);

      expect(registry.getMimeType('langId'), 'text/x-langId');

      registry.dispose();
    });

    test('aliases', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([const ILanguageExtensionPoint(id: 'a')]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'a', languageId: 'a'),
      ]);
      expect(registry.getLanguageIdByLanguageName('a'), 'a');
      expect(registry.getLanguageName('a'), 'a');

      registry.registerLanguages([
        const ILanguageExtensionPoint(id: 'a', aliases: ['A1', 'A2']),
      ]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'A1', languageId: 'a'),
      ]);
      expect(registry.getLanguageIdByLanguageName('a'), 'a');
      expect(registry.getLanguageIdByLanguageName('a1'), 'a');
      expect(registry.getLanguageIdByLanguageName('a2'), 'a');
      expect(registry.getLanguageName('a'), 'A1');

      registry.registerLanguages([
        const ILanguageExtensionPoint(id: 'a', aliases: ['A3', 'A4']),
      ]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'A3', languageId: 'a'),
      ]);
      expect(registry.getLanguageIdByLanguageName('a'), 'a');
      expect(registry.getLanguageIdByLanguageName('a1'), 'a');
      expect(registry.getLanguageIdByLanguageName('a2'), 'a');
      expect(registry.getLanguageIdByLanguageName('a3'), 'a');
      expect(registry.getLanguageIdByLanguageName('a4'), 'a');
      expect(registry.getLanguageName('a'), 'A3');

      registry.dispose();
    });

    test('empty aliases array means no alias', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([const ILanguageExtensionPoint(id: 'a')]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'a', languageId: 'a'),
      ]);
      expect(registry.getLanguageIdByLanguageName('a'), 'a');
      expect(registry.getLanguageName('a'), 'a');

      registry.registerLanguages([
        const ILanguageExtensionPoint(id: 'b', aliases: []),
      ]);

      expect(registry.getSortedRegisteredLanguageNames(), [
        (languageName: 'a', languageId: 'a'),
      ]);
      expect(registry.getLanguageIdByLanguageName('a'), 'a');
      expect(registry.getLanguageIdByLanguageName('b'), 'b');
      expect(registry.getLanguageName('a'), 'a');
      expect(registry.getLanguageName('b'), isNull);

      registry.dispose();
    });

    test('extensions', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'a',
          aliases: ['aName'],
          extensions: ['aExt'],
        ),
      ]);

      expect(registry.getExtensions('a'), ['aExt']);

      registry.registerLanguages([
        const ILanguageExtensionPoint(id: 'a', extensions: ['aExt2']),
      ]);

      expect(registry.getExtensions('a'), ['aExt', 'aExt2']);

      registry.dispose();
    });

    test('extensions of primary language registration come first', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(id: 'a', extensions: ['aExt3']),
      ]);

      expect(registry.getExtensions('a')[0], 'aExt3');

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'a',
          configuration: 'conf.json',
          extensions: ['aExt'],
        ),
      ]);

      expect(registry.getExtensions('a')[0], 'aExt');

      registry.registerLanguages([
        const ILanguageExtensionPoint(id: 'a', extensions: ['aExt2']),
      ]);

      expect(registry.getExtensions('a')[0], 'aExt');

      registry.dispose();
    });

    test('filenames', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'a',
          aliases: ['aName'],
          filenames: ['aFilename'],
        ),
      ]);

      expect(registry.getFilenames('a'), ['aFilename']);

      registry.registerLanguages([
        const ILanguageExtensionPoint(id: 'a', filenames: ['aFilename2']),
      ]);

      expect(registry.getFilenames('a'), ['aFilename', 'aFilename2']);

      registry.dispose();
    });

    test('configuration', () {
      final registry = LanguagesRegistry(useModesRegistry: false);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'a',
          aliases: ['aName'],
          configuration: '/path/to/aFilename',
        ),
      ]);

      expect(registry.getConfigurationFiles('a'), ['/path/to/aFilename']);
      expect(registry.getConfigurationFiles('aname'), isEmpty);
      expect(registry.getConfigurationFiles('aName'), isEmpty);

      registry.registerLanguages([
        const ILanguageExtensionPoint(
          id: 'a',
          configuration: '/path/to/aFilename2',
        ),
      ]);

      expect(registry.getConfigurationFiles('a'), [
        '/path/to/aFilename',
        '/path/to/aFilename2',
      ]);
      expect(registry.getConfigurationFiles('aname'), isEmpty);
      expect(registry.getConfigurationFiles('aName'), isEmpty);

      registry.dispose();
    });
  });

  group('LanguagesRegistry (Dart port)', () {
    tearDown(() {
      clearPlatformLanguageAssociations();
      clearConfiguredLanguageAssociations();
    });

    test('plaintext comes from the modes registry', () {
      final registry = LanguagesRegistry();
      expect(registry.getRegisteredLanguageIds(), [plaintextLanguageId]);
      expect(registry.getLanguageName(plaintextLanguageId), 'Plain Text');
      expect(registry.getLanguageIdByLanguageName('TEXT'), plaintextLanguageId);
      expect(registry.getLanguageIdByMimeType('text/plain'), 'plaintext');
      expect(registry.getLanguageIdByMimeType(null), isNull);
      expect(
        registry.guessLanguageIdByFilepathOrFirstLine(Uri.file('/a/b.txt')),
        ['plaintext', 'plaintext'],
      );
      registry.dispose();
    });

    test('setDynamicLanguages replaces the extension languages', () {
      final registry = LanguagesRegistry();
      var changes = 0;
      final listener = registry.onDidChange(() => changes++);
      registry.setDynamicLanguages([
        const ILanguageExtensionPoint(
          id: 'shellscript',
          aliases: ['Shell Script', 'shellscript'],
          extensions: ['.sh'],
          filenamePatterns: ['.env.*'],
          firstLine: r'^#!.*\b(bash|sh)',
          mimetypes: ['text/x-shellscript'],
        ),
      ]);
      expect(changes, 1);
      expect(registry.isRegisteredLanguageId('shellscript'), isTrue);
      expect(registry.isRegisteredLanguageId(null), isFalse);
      expect(
        registry.guessLanguageIdByFilepathOrFirstLine(Uri.file('/x/run.sh')),
        ['shellscript', 'plaintext'],
      );
      expect(
        registry.guessLanguageIdByFilepathOrFirstLine(
          Uri.file('/x/.env.local'),
        ),
        ['shellscript', 'plaintext'],
      );
      expect(
        registry.guessLanguageIdByFilepathOrFirstLine(
          Uri.file('/x/run'),
          '#!/bin/bash',
        ),
        ['shellscript', 'plaintext'],
      );
      expect(
        registry.guessLanguageIdByFilepathOrFirstLine(Uri.file('/x/run')),
        ['unknown'],
      );
      expect(registry.guessLanguageIdByFilepathOrFirstLine(null), isEmpty);

      registry.setDynamicLanguages(const []);
      expect(changes, 2);
      expect(registry.isRegisteredLanguageId('shellscript'), isFalse);
      expect(
        registry.guessLanguageIdByFilepathOrFirstLine(Uri.file('/x/run.sh')),
        ['unknown'],
      );
      listener.dispose();
      registry.dispose();
    });

    test('configured associations win (files.associations)', () {
      final registry = LanguagesRegistry()
        ..setDynamicLanguages([
          const ILanguageExtensionPoint(id: 'ini', extensions: ['.ini']),
          const ILanguageExtensionPoint(
            id: 'properties',
            extensions: ['.conf'],
          ),
        ]);
      // What WorkbenchLanguageService.updateMime does for
      // {"*.ini": "properties"}.
      registerConfiguredLanguageAssociation(
        ILanguageAssociation(
          id: 'properties',
          mime: registry.getMimeType('properties') ?? 'text/x-properties',
          filepattern: '*.ini',
        ),
      );
      expect(
        registry.guessLanguageIdByFilepathOrFirstLine(Uri.file('/a/b.ini')),
        ['properties', 'plaintext'],
      );
      clearConfiguredLanguageAssociations();
      expect(
        registry.guessLanguageIdByFilepathOrFirstLine(Uri.file('/a/b.ini')),
        ['ini', 'plaintext'],
      );
      registry.dispose();
    });

    test('LanguageIdCodec', () {
      final registry = LanguagesRegistry()
        ..setDynamicLanguages([const ILanguageExtensionPoint(id: 'json')]);
      final ILanguageIdCodec codec = registry.languageIdCodec;
      expect(codec.encodeLanguageId(plaintextLanguageId), 1);
      expect(codec.encodeLanguageId('json'), 2);
      expect(codec.encodeLanguageId('nope'), 0);
      expect(codec.decodeLanguageId(2), 'json');
      expect(codec.decodeLanguageId(0), 'vs.editor.nullLanguage');
      expect(codec.decodeLanguageId(99), 'vs.editor.nullLanguage');
      // Ids stay stable when the languages are replaced.
      registry.setDynamicLanguages([
        const ILanguageExtensionPoint(id: 'css'),
        const ILanguageExtensionPoint(id: 'json'),
      ]);
      expect(codec.encodeLanguageId('json'), 2);
      expect(codec.encodeLanguageId('css'), 3);
      registry.dispose();
    });

    test('dispose stops following the modes registry', () {
      final registry = LanguagesRegistry();
      final IDisposable registration = registry.registerLanguage(
        const ILanguageExtensionPoint(id: 'core-extra'),
      );
      expect(registry.isRegisteredLanguageId('core-extra'), isTrue);
      registration.dispose();
      // As upstream, unregistering does not fire onDidChangeLanguages; the
      // language goes away on the next refresh.
      expect(registry.isRegisteredLanguageId('core-extra'), isTrue);
      registry.setDynamicLanguages(const []);
      expect(registry.isRegisteredLanguageId('core-extra'), isFalse);
      registry.dispose();
      final again = modesRegistry.registerLanguage(
        const ILanguageExtensionPoint(id: 'core-extra-2'),
      );
      expect(registry.isRegisteredLanguageId('core-extra-2'), isFalse);
      again.dispose();
    });
  });
}
