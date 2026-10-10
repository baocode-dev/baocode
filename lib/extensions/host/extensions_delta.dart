// What a running extension host is told when the installed or enabled
// extensions change (`$deltaExtensions`).
//
// Follows VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/abstractExtensionService.ts
// (`_deltaExtensions`: an extension whose activation started cannot be
// removed (`canRemoveExtension`), and one already known cannot be added
// again unless removed (`_canAddExtension`), so it runs as it was until
// the extensions restart).

typedef ExtensionDescription = Map<String, Object?>;

/// The lowercase id of an extension description.
String extensionDescriptionKey(ExtensionDescription description) =>
    switch (description['identifier']) {
      {'value': final String value} => value,
      final Object? other => '$other',
    }.toLowerCase();

/// What makes two scans of an extension the same one.
String _signatureOf(ExtensionDescription description) =>
    '${description['version']}|${description['extensionLocation']}';

/// The change from [before] (what runs) to [after] (what is installed and
/// enabled now). Those [activated] (lowercase ids whose activation started)
/// that changed or went are [kept] as they run, in [running].
({
  List<ExtensionDescription> toAdd,
  List<ExtensionDescription> toRemove,
  Set<String> kept,
  List<ExtensionDescription> running,
})
extensionsDelta({
  required List<ExtensionDescription> before,
  required List<ExtensionDescription> after,
  required bool Function(String key) activated,
}) {
  final was = {for (final e in before) extensionDescriptionKey(e): e};
  final now = {for (final e in after) extensionDescriptionKey(e): e};
  bool changed(ExtensionDescription? a, ExtensionDescription b) =>
      a == null || _signatureOf(a) != _signatureOf(b);
  final kept = {
    for (final MapEntry(:key, :value) in was.entries)
      if (activated(key) && changed(now[key], value)) key,
  };
  return (
    toRemove: [
      for (final MapEntry(:key, :value) in was.entries)
        if (!kept.contains(key) && changed(now[key], value)) value,
    ],
    toAdd: [
      for (final MapEntry(:key, :value) in now.entries)
        if (!kept.contains(key) && changed(was[key], value)) value,
    ],
    kept: kept,
    running: [
      for (final MapEntry(:key, :value) in now.entries)
        if (!kept.contains(key)) value,
      for (final key in kept) was[key]!,
    ],
  );
}
