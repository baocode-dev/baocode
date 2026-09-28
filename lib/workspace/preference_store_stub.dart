import 'preference_store.dart';

/// Nowhere to keep them (the web): each run starts afresh.
class FilePreferenceStore implements PreferenceStore {
  FilePreferenceStore([this.path]);

  final String? path;

  @override
  Future<Map<String, Object?>> read() async => const {};

  @override
  Future<void> write(Map<String, Object?> preferences) async {}
}
