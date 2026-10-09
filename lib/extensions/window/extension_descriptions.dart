// Reading the scanned `IExtensionDescription`s the window area needs: an
// extension by id, its display name.

/// `ExtensionIdentifier.toKey`: ids compare without case.
String extensionKey(String id) => id.toLowerCase();

/// The id (`publisher.name`) of [description].
String extensionIdOf(Map<String, Object?> description) =>
    switch (description['identifier']) {
      final Map<Object?, Object?> identifier => '${identifier['value']}',
      final String value => value,
      _ => '${description['publisher']}.${description['name']}',
    };

/// The id of an `ExtensionIdentifier` as sent (`{value, _lower}`) or a
/// string.
String extensionIdFromWire(Object? identifier) => switch (identifier) {
  final Map<Object?, Object?> map => '${map['value']}',
  final String value => value,
  _ => '$identifier',
};

/// What the user knows [description] as: its display name, else its name.
String extensionDisplayName(Map<String, Object?> description) =>
    switch (description['displayName']) {
      final String name when name.isNotEmpty => name,
      _ => '${description['name'] ?? extensionIdOf(description)}',
    };

/// The description of [id] among [descriptions]; null when none.
Map<String, Object?>? findExtension(
  Iterable<Map<String, Object?>> descriptions,
  String id,
) {
  final key = extensionKey(id);
  for (final description in descriptions) {
    if (extensionKey(extensionIdOf(description)) == key) return description;
  }
  return null;
}
