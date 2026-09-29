import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../vs/editor/standalone/common/monarch/monarch_compile.dart' as monarch;
import '../vs/editor/standalone/common/monarch/monarch_common.dart';
import '../vs/editor/standalone/common/monarch/monarch_types.dart';

/// Data exported from Monaco v0.57.0's original language definitions.
/// Patterns are reconstructed before the pinned Monarch compiler sees them.
class MonacoLanguageAssets {
  const MonacoLanguageAssets({this.bundle});

  static const revision = 'd61824269f1377111d34306e4a47172327777083';
  static const _base = 'assets/monaco/languages';
  final AssetBundle? bundle;

  AssetBundle get _assets => bundle ?? rootBundle;

  Future<Map<String, dynamic>> _manifest() async {
    final manifest = jsonDecode(
      await _assets.loadString('$_base/manifest.json'),
    ) as Map<String, dynamic>;
    if (manifest['revision'] != revision) {
      throw const FormatException('Monaco language manifest version mismatch');
    }
    return manifest;
  }

  Future<List<String>> availableLanguages() async {
    final names = ((await _manifest())['grammars'] as List).cast<String>();
    return List<String>.unmodifiable(names);
  }

  Future<List<MonacoLanguageRegistration>> registrations() async =>
      List<MonacoLanguageRegistration>.unmodifiable([
        for (final raw in (await _manifest())['registrations'] as List)
          MonacoLanguageRegistration.fromMap(raw as Map<String, dynamic>),
      ]);

  Future<MonacoLanguage> loadRegistered(String languageId) async {
    final registration = (await registrations()).where(
      (r) => r.id == languageId,
    );
    if (registration.isEmpty) {
      throw ArgumentError.value(
        languageId,
        'languageId',
        'Unknown Monaco registration',
      );
    }
    final grammar = await load(registration.first.assetId);
    return MonacoLanguage(
      languageId,
      grammar.definition,
      grammar.configuration,
    );
  }

  /// Resolves pinned filenames/extensions, including registrations whose ID
  /// differs from the grammar's source folder (e.g. C shares the C++ lexer).
  Future<MonacoLanguage?> forPath(String path, {String? firstLine}) async {
    final filename = p.basename(path);
    final lower = filename.toLowerCase();
    final candidates = await registrations();
    for (final registration in candidates) {
      if (registration.filenames.any((name) => name.toLowerCase() == lower)) {
        return loadRegistered(registration.id);
      }
    }
    final byExtension = <(int, MonacoLanguageRegistration)>[];
    for (final registration in candidates) {
      for (final extension in registration.extensions) {
        if (lower.endsWith(extension.toLowerCase())) {
          byExtension.add((extension.length, registration));
        }
      }
    }
    if (byExtension.isNotEmpty) {
      byExtension.sort((a, b) => b.$1.compareTo(a.$1));
      return loadRegistered(byExtension.first.$2.id);
    }
    if (firstLine != null) {
      for (final registration in candidates) {
        final pattern = registration.firstLinePattern;
        if (pattern != null && RegExp(pattern).hasMatch(firstLine)) {
          return loadRegistered(registration.id);
        }
      }
    }
    return null;
  }

  Future<MonacoLanguage> load(String languageId) async {
    final names = await availableLanguages();
    if (!names.contains(languageId)) {
      throw ArgumentError.value(
        languageId,
        'languageId',
        'Unknown Monaco language',
      );
    }
    final encoded = jsonDecode(
      await _assets.loadString('$_base/$languageId.json'),
    ) as Map<String, dynamic>;
    if (encoded['revision'] != revision ||
        encoded['languageId'] != languageId) {
      throw const FormatException(
        'Monaco language version or identity mismatch',
      );
    }
    return MonacoLanguage(
      languageId,
      _restore(encoded['language']) as IMonarchLanguage,
      _restore(encoded['configuration']) as Map<String, Object?>?,
    );
  }

  Object? _restore(Object? encoded) {
    if (encoded is List) return encoded.map(_restore).toList();
    if (encoded is! Map) return encoded;
    if (encoded.containsKey(r'$regex')) {
      final pattern = encoded[r'$regex'] as String;
      final flags = encoded[r'$flags'] as String;
      return RegExp(
        pattern,
        caseSensitive: !flags.contains('i'),
        multiLine: flags.contains('m'),
        unicode: flags.contains('u'),
        dotAll: flags.contains('s'),
      );
    }
    return <String, Object?>{
      for (final entry in encoded.entries)
        entry.key as String: _restore(entry.value),
    };
  }
}

class MonacoLanguageRegistration {
  MonacoLanguageRegistration.fromMap(Map<String, dynamic> data)
    : id = data['id'] as String,
      assetId = data['assetId'] as String,
      extensions = List<String>.unmodifiable(
        (data['extensions'] as List? ?? const []).cast<String>(),
      ),
      filenames = List<String>.unmodifiable(
        (data['filenames'] as List? ?? const []).cast<String>(),
      ),
      aliases = List<String>.unmodifiable(
        (data['aliases'] as List? ?? const []).cast<String>(),
      ),
      firstLinePattern = data['firstLine'] as String?;

  final String id;
  final String assetId;
  final List<String> extensions;
  final List<String> filenames;
  final List<String> aliases;
  final String? firstLinePattern;
}

class MonacoLanguage {
  const MonacoLanguage(this.id, this.definition, this.configuration);

  final String id;
  final IMonarchLanguage definition;
  final Map<String, Object?>? configuration;

  ILexer compile() => monarch.compile(id, definition);
}
