/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of VS Code src/vs/editor/common/languages/modesRegistry.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971, plus `ILanguageExtensionPoint`
// and `ILanguageIcon` from src/vs/editor/common/languages/language.ts.
// Deviations: `onDidChangeLanguages` takes a listener instead of exposing an
// `Event`; the `Registry` platform entry and the `[plaintext]`/`[go]`/…
// configuration defaults are not ported; the "Plain Text" alias is not
// localized. `ILanguageExtensionPoint.configuration` and the icon paths are
// strings (upstream: `URI`s built with `joinPath(extensionLocation, …)`).

import '../../../base/common/lifecycle.dart';
import '../../../base/common/mime.dart';

/// Upstream `ILanguageIcon`.
class ILanguageIcon {
  const ILanguageIcon({required this.light, required this.dark});

  final String light;
  final String dark;
}

/// A `contributes.languages` entry, as the workbench hands it to the
/// registry. A missing list (`null`) and an empty one differ: `aliases: []`
/// means "no name", while `null` makes the id the name.
class ILanguageExtensionPoint {
  const ILanguageExtensionPoint({
    required this.id,
    this.extensions,
    this.filenames,
    this.filenamePatterns,
    this.firstLine,
    this.aliases,
    this.mimetypes,
    this.configuration,
    this.icon,
  });

  /// Reads the JSON shape of `contributes.languages` (and of
  /// test/fixtures/textmate/language_detection.json `registrations`),
  /// keeping absent lists `null`. Other keys are ignored; unlike upstream's
  /// `isValidLanguageExtensionPoint` it throws on wrongly typed values.
  factory ILanguageExtensionPoint.fromJson(Map<String, Object?> json) {
    List<String>? strings(String key) =>
        (json[key] as List<Object?>?)?.cast<String>().toList();
    final icon = json['icon'] as Map<String, Object?>?;
    return ILanguageExtensionPoint(
      id: json['id']! as String,
      extensions: strings('extensions'),
      filenames: strings('filenames'),
      filenamePatterns: strings('filenamePatterns'),
      firstLine: json['firstLine'] as String?,
      aliases: strings('aliases'),
      mimetypes: strings('mimetypes'),
      configuration: json['configuration'] as String?,
      icon: icon == null
          ? null
          : ILanguageIcon(
              light: icon['light']! as String,
              dark: icon['dark']! as String,
            ),
    );
  }

  final String id;
  final List<String>? extensions;
  final List<String>? filenames;
  final List<String>? filenamePatterns;

  /// A JavaScript regular expression for the first line; `^` is prepended
  /// when missing.
  final String? firstLine;
  final List<String>? aliases;
  final List<String>? mimetypes;

  /// The language configuration file.
  final String? configuration;
  final ILanguageIcon? icon;
}

/// Upstream `EditorModesRegistry`: the core language registrations.
class EditorModesRegistry extends Disposable {
  final List<ILanguageExtensionPoint> _languages = [];
  final List<void Function()> _listeners = [];

  /// Upstream `onDidChangeLanguages`: calls [listener] after each
  /// [registerLanguage] until the returned disposable is disposed.
  IDisposable onDidChangeLanguages(void Function() listener) {
    _listeners.add(listener);
    return toDisposable(() => _listeners.remove(listener));
  }

  @override
  void dispose() {
    _listeners.clear(); // upstream disposes its Emitter
    super.dispose();
  }

  IDisposable registerLanguage(ILanguageExtensionPoint def) {
    _languages.add(def);
    for (final listener in _listeners.toList()) {
      listener();
    }
    return toDisposable(() {
      for (var i = 0, len = _languages.length; i < len; i++) {
        if (identical(_languages[i], def)) {
          _languages.removeAt(i);
          return;
        }
      }
    });
  }

  List<ILanguageExtensionPoint> getLanguages() => List.unmodifiable(_languages);
}

/// Upstream `PLAINTEXT_LANGUAGE_ID`.
const String plaintextLanguageId = 'plaintext';

/// Upstream `PLAINTEXT_EXTENSION`.
const String plaintextExtension = '.txt';

/// Upstream `ModesRegistry`, created with the plain text language.
final EditorModesRegistry modesRegistry = EditorModesRegistry()
  ..registerLanguage(
    const ILanguageExtensionPoint(
      id: plaintextLanguageId,
      extensions: [plaintextExtension],
      aliases: ['Plain Text', 'text'],
      mimetypes: [Mimes.text],
    ),
  );
