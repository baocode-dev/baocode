/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What an extension's manifest (`package.json`, localized by its
// `package.nls.json`) and `extension.vsixmanifest` say about it: who and
// what it is, which VS Code it wants, where it runs and what it
// contributes.
//
// The localization is ported from VS Code
// 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/extensionManagement/common/extensionNls.ts
// (`localizeManifest`, `replaceNLStrings`), and the enabled API proposals'
// names from src/vs/platform/extensions/common/extensions.ts
// (`parseEnabledApiProposalNames`).
//
// Deviations: a command's localized title replaces the original (no
// `ILocalizedString`); missing keys are left as they are, silently.

import 'dart:typed_data';

import 'engine_version.dart';
import 'target_platform.dart';

/// What [ExtensionManifestInfo] is read from.
class ExtensionManifestSource {
  const ExtensionManifestSource({
    required this.manifest,
    this.translations,
    this.fallbackTranslations,
    this.vsixManifest,
    this.iconBytes,
  });

  /// `package.json`, parsed.
  final Map<String, Object?> manifest;

  /// `package.nls.<locale>.json` (or `package.nls.json`), parsed.
  final Map<String, Object?>? translations;

  /// `package.nls.json` when [translations] is a locale's.
  final Map<String, Object?>? fallbackTranslations;

  /// `extension.vsixmanifest`'s text, when there is one.
  final String? vsixManifest;
  final Uint8List? iconBytes;
}

/// An extension's manifest, as the Extensions view and installing need it.
class ExtensionManifestInfo {
  ExtensionManifestInfo({
    required this.publisher,
    required this.name,
    required this.version,
    required this.displayName,
    required this.description,
    required this.engine,
    required this.engineCompatible,
    required this.engineNotices,
    required this.targetPlatform,
    required this.preRelease,
    required this.main,
    required this.browser,
    required this.extensionKind,
    required this.categories,
    required this.activationEvents,
    required this.enabledApiProposals,
    required this.extensionDependencies,
    required this.extensionPack,
    required this.contributions,
    required this.configurationKeys,
    required this.manifest,
    this.icon,
    this.iconBytes,
    this.license,
    this.repository,
    this.homepage,
  });

  /// Reads [source]; [engineVersion] is the VS Code the extension host is.
  factory ExtensionManifestInfo.fromSource(
    ExtensionManifestSource source, {
    String engineVersion = extensionHostEngineVersion,
  }) {
    final manifest = localizeManifest(
      source.manifest,
      source.translations ?? const {},
      source.fallbackTranslations,
    );
    final vsix = source.vsixManifest == null
        ? null
        : VsixManifest.parse(source.vsixManifest!);
    final metadata = manifest['__metadata'];
    String? string(Object? value) =>
        value is String && value.isNotEmpty ? value : null;
    final publisher = string(manifest['publisher']) ?? vsix?.publisher ?? '';
    final name = string(manifest['name']) ?? vsix?.id ?? '';
    final engines = manifest['engines'];
    final engine = engines is Map ? string(engines['vscode']) : null;
    final main = string(manifest['main']);
    final browser = string(manifest['browser']);
    final notices = <EngineNotice>[];
    final compatible = isValidExtensionVersion(
      engine: engine,
      hasCode: main != null || browser != null,
      version: engineVersion,
      notices: notices,
    );
    final targetPlatform =
        vsix?.targetPlatform ??
        switch (metadata) {
          {'targetPlatform': final String id} => ExtensionTargetPlatform.parse(
            id,
          ),
          _ => ExtensionTargetPlatform.undefined,
        };
    final preRelease =
        vsix?.preRelease ??
        switch (metadata) {
          {'isPreReleaseVersion': final bool value} => value,
          _ => false,
        };
    final repository = switch (manifest['repository']) {
      final String url => url,
      {'url': final String url} => url,
      _ => null,
    };
    return ExtensionManifestInfo(
      publisher: publisher,
      name: name,
      version: string(manifest['version']) ?? vsix?.version ?? '0.0.0',
      displayName: string(manifest['displayName']) ?? vsix?.displayName,
      description: string(manifest['description']) ?? vsix?.description,
      engine: engine,
      engineCompatible: compatible,
      engineNotices: List.unmodifiable(notices),
      targetPlatform: targetPlatform,
      preRelease: preRelease,
      main: main,
      browser: browser,
      extensionKind: switch (manifest['extensionKind']) {
        final String kind => [kind],
        final List kinds => [
          for (final kind in kinds)
            if (kind is String) kind,
        ],
        _ => const [],
      },
      categories: _strings(manifest['categories']),
      activationEvents: _strings(manifest['activationEvents']),
      enabledApiProposals: [
        for (final proposal in _strings(manifest['enabledApiProposals']))
          proposal.split('@').first,
      ],
      extensionDependencies: _strings(manifest['extensionDependencies']),
      extensionPack: _strings(manifest['extensionPack']),
      contributions: ContributionsSummary.fromManifest(manifest),
      configurationKeys: configurationKeysOf(manifest),
      manifest: manifest,
      icon: string(manifest['icon']),
      iconBytes: source.iconBytes,
      license: string(manifest['license']),
      repository: repository,
      homepage: string(manifest['homepage']),
    );
  }

  final String publisher;
  final String name;
  final String version;
  final String? displayName;
  final String? description;

  /// `engines.vscode`.
  final String? engine;

  /// Whether [engine] accepts the extension host's VS Code (always for a
  /// declarative extension); [engineNotices] say why not.
  final bool engineCompatible;
  final List<EngineNotice> engineNotices;

  /// From `extension.vsixmanifest` (or an installed extension's
  /// `__metadata`); [ExtensionTargetPlatform.undefined] when neither says.
  final ExtensionTargetPlatform targetPlatform;
  final bool preRelease;

  /// The Node entry point, and the web worker one.
  final String? main;
  final String? browser;

  /// `ui`, `workspace`, `web`, as the manifest has them (empty when it has
  /// none: then VS Code derives them).
  final List<String> extensionKind;
  final List<String> categories;
  final List<String> activationEvents;

  /// Their names, without `@version`.
  final List<String> enabledApiProposals;
  final List<String> extensionDependencies;
  final List<String> extensionPack;
  final ContributionsSummary contributions;

  /// Every setting `contributes.configuration` declares.
  final Set<String> configurationKeys;

  /// `package.json`, localized.
  final Map<String, Object?> manifest;

  /// The icon's path in the extension, and its bytes when read.
  final String? icon;
  final Uint8List? iconBytes;
  final String? license;
  final String? repository;
  final String? homepage;

  /// `publisher.name`, as the manifest cases it.
  String get id => '$publisher.$name';

  /// [id] lower-cased: extension ids compare ignoring case.
  String get key => id.toLowerCase();

  String get label => displayName ?? name;

  /// Whether it has code to run (else only declarative contributions).
  bool get hasCode => main != null || browser != null;

  /// A web worker extension only: the Node extension host does not run
  /// its code.
  bool get browserOnly => main == null && browser != null;

  /// The folder name VS Code installs it under:
  /// `publisher.name-version[-targetPlatform]`, lower-cased.
  String get installFolderName {
    final base = '$key-$version';
    return targetPlatform.isSpecific ? '$base-${targetPlatform.id}' : base;
  }

  @override
  String toString() => 'ExtensionManifestInfo($id@$version)';
}

/// What `contributes` has, by kind, with what to list of each.
class ContributionsSummary {
  const ContributionsSummary(this.entries);

  factory ContributionsSummary.fromManifest(Map<String, Object?> manifest) {
    final contributes = manifest['contributes'];
    if (contributes is! Map) return const ContributionsSummary([]);
    final entries = <ContributionEntry>[];
    for (final MapEntry(:key, :value) in contributes.entries) {
      if (key is! String) continue;
      final items = _contributionItems(key, value);
      if (items.isEmpty && !_present(value)) continue;
      entries.add(
        ContributionEntry(key, items.isEmpty ? 1 : items.length, items),
      );
    }
    entries.sort((a, b) => a.kind.compareTo(b.kind));
    return ContributionsSummary(List.unmodifiable(entries));
  }

  final List<ContributionEntry> entries;

  bool get isEmpty => entries.isEmpty;

  ContributionEntry? operator [](String kind) {
    for (final entry in entries) {
      if (entry.kind == kind) return entry;
    }
    return null;
  }

  int count(String kind) => this[kind]?.count ?? 0;
}

/// One kind of contribution (`commands`, `languages`) and its items'
/// labels.
class ContributionEntry {
  const ContributionEntry(this.kind, this.count, this.items);

  final String kind;
  final int count;
  final List<String> items;

  @override
  String toString() => 'ContributionEntry($kind, $count)';
}

bool _present(Object? value) => switch (value) {
  null => false,
  final List list => list.isNotEmpty,
  final Map map => map.isNotEmpty,
  _ => true,
};

List<String> _contributionItems(String kind, Object? value) {
  String? label(Object? item, List<String> keys) {
    if (item is String) return item;
    if (item is! Map) return null;
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  List<String> labels(Object? list, List<String> keys) => [
    if (list is List)
      for (final item in list) ?label(item, keys)
    else if (list is Map)
      ?label(list, keys),
  ];

  switch (kind) {
    case 'commands':
      return labels(value, ['title', 'command']);
    case 'languages':
      return labels(value, ['id']);
    case 'grammars':
      return labels(value, ['scopeName', 'language']);
    case 'themes' || 'iconThemes' || 'productIconThemes':
      return labels(value, ['label', 'id', 'path']);
    case 'snippets':
      return labels(value, ['language', 'path']);
    case 'debuggers':
      return labels(value, ['label', 'type']);
    case 'keybindings':
      return labels(value, ['command']);
    case 'customEditors':
      return labels(value, ['displayName', 'viewType']);
    case 'notebooks':
      return labels(value, ['displayName', 'type']);
    case 'notebookRenderer':
      return labels(value, ['displayName', 'id']);
    case 'walkthroughs':
      return labels(value, ['title', 'id']);
    case 'taskDefinitions':
      return labels(value, ['type']);
    case 'jsonValidation':
      return labels(value, ['fileMatch', 'url']);
    case 'authentication':
      return labels(value, ['label', 'id']);
    case 'colors':
      return labels(value, ['id']);
    case 'localizations':
      return labels(value, ['languageName', 'languageId']);
    case 'views' || 'viewsContainers':
      return [
        if (value is Map)
          for (final list in value.values) ...labels(list, ['name', 'id']),
      ];
    case 'menus':
      return [
        if (value is Map)
          for (final key in value.keys)
            if (key is String) key,
      ];
    case 'configuration':
      return [
        ...configurationKeysOf({
          'contributes': {'configuration': value},
        }),
      ];
    default:
      return const [];
  }
}

/// The settings `contributes.configuration` declares (an object, or an
/// array of them): their `properties`' keys.
Set<String> configurationKeysOf(Map<String, Object?> manifest) {
  final contributes = manifest['contributes'];
  if (contributes is! Map) return const {};
  final configuration = contributes['configuration'];
  final keys = <String>{};
  void add(Object? node) {
    if (node is! Map) return;
    final properties = node['properties'];
    if (properties is! Map) return;
    for (final key in properties.keys) {
      if (key is String) keys.add(key);
    }
  }

  if (configuration is List) {
    configuration.forEach(add);
  } else {
    add(configuration);
  }
  return keys;
}

List<String> _strings(Object? value) => switch (value) {
  final List list => [
    for (final item in list)
      if (item is String) item,
  ],
  final String one => [one],
  _ => const [],
};

/// `localizeManifest`: a copy of [manifest] whose `%key%` strings are
/// [translations]' messages (else [fallback]'s).
Map<String, Object?> localizeManifest(
  Map<String, Object?> manifest,
  Map<String, Object?> translations, [
  Map<String, Object?>? fallback,
]) {
  String? message(Object? translated) => switch (translated) {
    final String text => text,
    {'message': final String text} => text,
    _ => null,
  };

  Object? localize(Object? value) {
    if (value is String) {
      if (value.length > 1 && value.startsWith('%') && value.endsWith('%')) {
        final key = value.substring(1, value.length - 1);
        final translated =
            message(translations[key]) ?? message(fallback?[key]);
        if (translated != null && translated.isNotEmpty) return translated;
      }
      return value;
    }
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry(:key, :value) in value.entries)
          '$key': localize(value),
      };
    }
    if (value is List) return [for (final item in value) localize(item)];
    return value;
  }

  return localize(manifest) as Map<String, Object?>;
}

/// What `extension.vsixmanifest` says that `package.json` does not: the
/// target platform and whether it is a pre-release.
class VsixManifest {
  const VsixManifest({
    this.id,
    this.version,
    this.publisher,
    this.displayName,
    this.description,
    this.targetPlatform,
    this.preRelease,
    this.properties = const {},
  });

  /// Reads the XML loosely: the `Identity` element's attributes, the
  /// `DisplayName` and `Description` elements and the `Property` ones.
  factory VsixManifest.parse(String xml) {
    Map<String, String> attributes(String element) => {
      for (final match in _attribute.allMatches(element))
        match[1]!: _unescape(match[2] ?? match[3] ?? ''),
    };
    final identity = RegExp(r'<Identity\b[^>]*>').firstMatch(xml);
    final identityAttributes = identity == null
        ? const <String, String>{}
        : attributes(identity[0]!);
    final properties = <String, String>{};
    for (final match in RegExp(r'<Property\b[^>]*>').allMatches(xml)) {
      final property = attributes(match[0]!);
      final id = property['Id'];
      if (id != null) properties[id] = property['Value'] ?? '';
    }
    String? element(String name) {
      final match = RegExp('<$name\\b[^>]*>([\\s\\S]*?)</$name>')
          .firstMatch(xml);
      final text = match == null ? null : _unescape(match[1]!.trim());
      return text == null || text.isEmpty ? null : text;
    }

    final platform = identityAttributes['TargetPlatform'];
    final preRelease = properties['Microsoft.VisualStudio.Code.PreRelease'];
    return VsixManifest(
      id: identityAttributes['Id'],
      version: identityAttributes['Version'],
      publisher: identityAttributes['Publisher'],
      displayName: element('DisplayName'),
      description: element('Description'),
      targetPlatform: platform == null || platform.isEmpty
          ? null
          : ExtensionTargetPlatform.parse(platform),
      preRelease: preRelease == null ? null : preRelease == 'true',
      properties: properties,
    );
  }

  final String? id;
  final String? version;
  final String? publisher;
  final String? displayName;
  final String? description;
  final ExtensionTargetPlatform? targetPlatform;
  final bool? preRelease;
  final Map<String, String> properties;
}

final _attribute = RegExp(r'''([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
