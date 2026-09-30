/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code src/vs/editor/common/services/languagesAssociations.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. Like upstream, the associations
// are global (library-level) state shared by every LanguagesRegistry.
// Deviations: resources are Dart [Uri]s, converted with `URI.fromUri` (see
// uri.dart) before upstream's scheme handling (`file` uses `fsPath`, `data`
// the `label` metadata, `vscode-notebook-cell` has no path, others use
// `path`). Paths are lower-cased with JavaScript semantics (`jsToLowerCase`).
// Overwrite warnings go to `dart:developer` `log` instead of `console.warn`.

import 'dart:developer' as developer;

import '../../../base/common/ecmascript_lower_case.dart';
import '../../../base/common/glob.dart' as glob;
import '../../../base/common/mime.dart';
import '../../../base/common/network.dart';
import '../../../base/common/path.dart' as paths;
import '../../../base/common/resources.dart';
import '../../../base/common/strings.dart' as strings;
import '../../../base/common/uri.dart';
import '../languages/modes_registry.dart';

class ILanguageAssociation {
  const ILanguageAssociation({
    required this.id,
    required this.mime,
    this.filename,
    this.extension,
    this.filepattern,
    this.firstline,
  });

  final String id;
  final String mime;
  final String? filename;
  final String? extension;
  final String? filepattern;
  final RegExp? firstline;
}

class _LanguageAssociationItem extends ILanguageAssociation {
  _LanguageAssociationItem(
    ILanguageAssociation association,
    this.userConfigured,
  ) : filepatternParsed =
          association.filepattern != null && association.filepattern!.isNotEmpty
          ? glob.parse(
              association.filepattern,
              const glob.IGlobOptions(ignoreCase: true),
            )
          : null,
      filepatternOnPath =
          association.filepattern != null &&
          association.filepattern!.isNotEmpty &&
          association.filepattern!.contains(paths.posix.sep),
      super(
        id: association.id,
        mime: association.mime,
        filename: association.filename,
        extension: association.extension,
        filepattern: association.filepattern,
        firstline: association.firstline,
      );

  final bool userConfigured;
  final glob.ParsedPattern? filepatternParsed;
  final bool filepatternOnPath;
}

List<_LanguageAssociationItem> _registeredAssociations = [];
List<_LanguageAssociationItem> _nonUserRegisteredAssociations = [];
List<_LanguageAssociationItem> _userRegisteredAssociations = [];

/// Associates a language with the registry (platform). These lose against
/// [registerConfiguredLanguageAssociation]; [clearPlatformLanguageAssociations]
/// removes them.
void registerPlatformLanguageAssociation(
  ILanguageAssociation association, [
  bool warnOnOverwrite = false,
]) {
  _registerLanguageAssociation(association, false, warnOnOverwrite);
}

/// Associates a language with the registry (configured, e.g. the user's
/// `files.associations`). These win against
/// [registerPlatformLanguageAssociation];
/// [clearConfiguredLanguageAssociations] removes them.
void registerConfiguredLanguageAssociation(ILanguageAssociation association) {
  _registerLanguageAssociation(association, true, false);
}

void _registerLanguageAssociation(
  ILanguageAssociation association,
  bool userConfigured,
  bool warnOnOverwrite,
) {
  // Register
  final associationItem = _LanguageAssociationItem(association, userConfigured);
  _registeredAssociations.add(associationItem);
  if (!associationItem.userConfigured) {
    _nonUserRegisteredAssociations.add(associationItem);
  } else {
    _userRegisteredAssociations.add(associationItem);
  }

  // Check for conflicts unless this is a user configured association.
  if (warnOnOverwrite && !associationItem.userConfigured) {
    for (final a in _registeredAssociations) {
      if (a.mime == associationItem.mime || a.userConfigured) {
        continue; // same mime or userConfigured is ok
      }
      void warn(String message) =>
          developer.log(message, name: 'languagesAssociations');
      final extension = associationItem.extension;
      if (extension != null &&
          extension.isNotEmpty &&
          a.extension == extension) {
        warn(
          'Overwriting extension <<$extension>> to now point to mime '
          '<<${associationItem.mime}>>',
        );
      }
      final filename = associationItem.filename;
      if (filename != null && filename.isNotEmpty && a.filename == filename) {
        warn(
          'Overwriting filename <<$filename>> to now point to mime '
          '<<${associationItem.mime}>>',
        );
      }
      final filepattern = associationItem.filepattern;
      if (filepattern != null &&
          filepattern.isNotEmpty &&
          a.filepattern == filepattern) {
        warn(
          'Overwriting filepattern <<$filepattern>> to now point to mime '
          '<<${associationItem.mime}>>',
        );
      }
      final firstline = associationItem.firstline;
      if (firstline != null && identical(a.firstline, firstline)) {
        warn(
          'Overwriting firstline <<$firstline>> to now point to mime '
          '<<${associationItem.mime}>>',
        );
      }
    }
  }
}

/// Clears the platform language associations.
void clearPlatformLanguageAssociations() {
  _registeredAssociations = _registeredAssociations
      .where((a) => a.userConfigured)
      .toList();
  _nonUserRegisteredAssociations = [];
}

/// Clears the configured language associations.
void clearConfiguredLanguageAssociations() {
  _registeredAssociations = _registeredAssociations
      .where((a) => !a.userConfigured)
      .toList();
  _userRegisteredAssociations = [];
}

typedef _IdAndMime = ({String id, String mime});

/// The best matching mime types for [resource], based on the registered
/// language associations.
List<String> getMimeTypes(Uri? resource, [String? firstLine]) => [
  for (final item in _getAssociations(resource, firstLine)) item.mime,
];

/// Like [getMimeTypes], for language ids.
List<String> getLanguageIds(Uri? resource, [String? firstLine]) => [
  for (final item in _getAssociations(resource, firstLine)) item.id,
];

List<_IdAndMime> _getAssociations(Uri? resource, String? firstLine) {
  String? path;
  if (resource != null) {
    final uri = URI.fromUri(resource);
    switch (uri.scheme) {
      case Schemas.file:
        path = uri.fsPath;
      case Schemas.data:
        final metadata = DataUri.parseMetaData(uri);
        path = metadata[DataUri.metaDataLabel];
      case Schemas.vscodeNotebookCell:
        // File path not relevant for language detection of cell.
        path = null;
      default:
        path = uri.path;
    }
  }

  if (path == null || path.isEmpty) {
    return [(id: 'unknown', mime: Mimes.unknown)];
  }

  path = jsToLowerCase(path);
  final filename = paths.basename(path);

  // 1.) User configured mappings have highest priority.
  final configuredLanguage = _getAssociationByPath(
    path,
    filename,
    _userRegisteredAssociations,
  );
  if (configuredLanguage != null) {
    return [
      (id: configuredLanguage.id, mime: configuredLanguage.mime),
      (id: plaintextLanguageId, mime: Mimes.text),
    ];
  }

  // 2.) Registered mappings have middle priority.
  final registeredLanguage = _getAssociationByPath(
    path,
    filename,
    _nonUserRegisteredAssociations,
  );
  if (registeredLanguage != null) {
    return [
      (id: registeredLanguage.id, mime: registeredLanguage.mime),
      (id: plaintextLanguageId, mime: Mimes.text),
    ];
  }

  // 3.) Firstline has lowest priority.
  if (firstLine != null && firstLine.isNotEmpty) {
    final firstlineLanguage = _getAssociationByFirstline(firstLine);
    if (firstlineLanguage != null) {
      return [
        (id: firstlineLanguage.id, mime: firstlineLanguage.mime),
        (id: plaintextLanguageId, mime: Mimes.text),
      ];
    }
  }

  return [(id: 'unknown', mime: Mimes.unknown)];
}

_LanguageAssociationItem? _getAssociationByPath(
  String path,
  String filename,
  List<_LanguageAssociationItem> associations,
) {
  _LanguageAssociationItem? filenameMatch;
  _LanguageAssociationItem? patternMatch;
  _LanguageAssociationItem? extensionMatch;

  // The last registered association wins over all others
  // (https://github.com/microsoft/vscode/issues/20074).
  for (var i = associations.length - 1; i >= 0; i--) {
    final association = associations[i];

    // First exact name match.
    if (strings.equals(filename, association.filename, true)) {
      filenameMatch = association;
      break; // take it!
    }

    // Longest pattern match.
    final filepattern = association.filepattern;
    if (filepattern != null && filepattern.isNotEmpty) {
      if (patternMatch == null ||
          filepattern.length > patternMatch.filepattern!.length) {
        // Match on the full path if the pattern contains a path separator.
        final target = association.filepatternOnPath ? path : filename;
        if (association.filepatternParsed?.call(target) ?? false) {
          patternMatch = association;
        }
      }
    }

    // Longest extension match.
    final extension = association.extension;
    if (extension != null && extension.isNotEmpty) {
      if (extensionMatch == null ||
          extension.length > extensionMatch.extension!.length) {
        if (strings.endsWithIgnoreCase(filename, extension)) {
          extensionMatch = association;
        }
      }
    }
  }

  // 1.) Exact name match has second highest priority.
  if (filenameMatch != null) return filenameMatch;

  // 2.) Match on pattern.
  if (patternMatch != null) return patternMatch;

  // 3.) Match on extension comes next.
  if (extensionMatch != null) return extensionMatch;

  return null;
}

_LanguageAssociationItem? _getAssociationByFirstline(String firstLine) {
  if (strings.startsWithUTF8BOM(firstLine)) {
    firstLine = firstLine.substring(1);
  }
  if (firstLine.isNotEmpty) {
    // The last registered association wins over all others
    // (https://github.com/microsoft/vscode/issues/20074).
    for (var i = _registeredAssociations.length - 1; i >= 0; i--) {
      final association = _registeredAssociations[i];
      final firstline = association.firstline;
      if (firstline == null) continue;
      if (firstline.hasMatch(firstLine)) return association;
    }
  }
  return null;
}
