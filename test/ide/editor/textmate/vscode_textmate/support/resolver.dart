// Adapted from vscode-textmate 9.3.2 (25b68dad…): src/tests/resolver.ts
// (MIT, see fixtures/LICENSE.md).

import 'dart:io';

import 'package:monad/ide/editor/textmate/vscode_textmate/main.dart';

class ILanguageRegistration {
  ILanguageRegistration(this.id, this.extensions, this.filenames);

  factory ILanguageRegistration.fromJson(Map<String, Object?> json) =>
      ILanguageRegistration(
        json['id']! as String,
        (json['extensions'] as List?)?.cast<String>(),
        (json['filenames'] as List?)?.cast<String>(),
      );

  final String id;
  final List<String>? extensions;
  final List<String>? filenames;
}

class IGrammarRegistration {
  IGrammarRegistration(
    this.language,
    this.scopeName,
    this.path,
    this.embeddedLanguages,
  );

  factory IGrammarRegistration.fromJson(
    Map<String, Object?> json,
    String basePath,
  ) => IGrammarRegistration(
    json['language'] as String?,
    json['scopeName']! as String,
    _join(basePath, json['path']! as String),
    (json['embeddedLanguages'] as Map?)?.cast<String, String>(),
  );

  final String? language;
  final String scopeName;
  final String path;
  final Map<String, String>? embeddedLanguages;
  Future<IRawGrammar>? grammar;
}

String _join(String base, String relative) {
  final r = relative.startsWith('./') ? relative.substring(2) : relative;
  return '$base/$r';
}

/// `path.extname`.
String extname(String filename) {
  final base = filename.substring(filename.lastIndexOf('/') + 1);
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? '' : base.substring(dot);
}

class Resolver {
  Resolver(this._grammars, this._languages, this.onigLib) {
    for (var i = 0; i < _languages.length; i++) {
      final languageId = ++_lastLanguageId;
      language2id[_languages[i].id] = languageId;
      _id2language[languageId] = _languages[i].id;
    }
  }

  final Map<String, int> language2id = <String, int>{};
  int _lastLanguageId = 0;
  final Map<int, String> _id2language = <int, String>{};
  final List<IGrammarRegistration> _grammars;
  final List<ILanguageRegistration> _languages;
  final Future<IOnigLib> onigLib;

  RegistryOptions get options =>
      RegistryOptions(onigLib: onigLib, loadGrammar: loadGrammar);

  String? findLanguageByExtension(String fileExtension) {
    for (final language in _languages) {
      final extensions = language.extensions;
      if (extensions == null) continue;
      for (final extension in extensions) {
        if (extension == fileExtension) {
          return language.id;
        }
      }
    }
    return null;
  }

  String? findLanguageByFilename(String filename) {
    for (final language in _languages) {
      final filenames = language.filenames;
      if (filenames == null) continue;
      for (final lFilename in filenames) {
        if (filename == lFilename) {
          return language.id;
        }
      }
    }
    return null;
  }

  String? findScopeByFilename(String filename) {
    final language =
        findLanguageByExtension(extname(filename)) ??
        findLanguageByFilename(filename);
    if (language != null) {
      return findGrammarByLanguage(language).scopeName;
    }
    return null;
  }

  IGrammarRegistration findGrammarByLanguage(String language) {
    for (final grammar in _grammars) {
      if (grammar.language == language) {
        return grammar;
      }
    }
    throw StateError('Could not findGrammarByLanguage for $language');
  }

  Future<IRawGrammar?> loadGrammar(String scopeName) async {
    for (final grammar in _grammars) {
      if (grammar.scopeName == scopeName) {
        return grammar.grammar ??= _readGrammarFromPath(grammar.path);
      }
    }
    return null;
  }
}

Future<IRawGrammar> _readGrammarFromPath(String path) async {
  final content = await File(path).readAsString();
  return parseRawGrammar(content, path);
}
