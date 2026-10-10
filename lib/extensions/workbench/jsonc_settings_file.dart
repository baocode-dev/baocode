// A settings.json as the configuration service reads and writes it.

import 'package:flutter/foundation.dart';

import '../../settings/jsonc_file.dart';
import '../configuration/configuration_service.dart';

/// [SettingsFile] on a [JsoncFile]: its object of dotted keys, written
/// with the JSONC editor (comments and formatting kept).
final class JsoncSettingsFile extends ChangeNotifier implements SettingsFile {
  JsoncSettingsFile(this.file) {
    file.addListener(notifyListeners);
  }

  final JsoncFile file;

  @override
  Map<String, Object?> get values => switch (file.value) {
    final Map<String, Object?> values => values,
    final Map<Object?, Object?> values => values.cast(),
    _ => const {},
  };

  @override
  Future<void> write(List<String> path, Object? value) =>
      file.edit(path, value, remove: value == null);

  @override
  void dispose() {
    file.removeListener(notifyListeners);
    super.dispose();
  }
}
