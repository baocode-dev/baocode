import 'preference_store_stub.dart'
    if (dart.library.io) 'preference_store_io.dart'
    as platform;

/// Where what the user picks is kept between runs, e.g. the model new
/// agents start with.
abstract interface class PreferenceStore {
  /// A file in the user's app data, or at [path] (none on the web).
  factory PreferenceStore.file([String? path]) = platform.FilePreferenceStore;

  /// What was kept; empty the first time, or when it cannot be read.
  Future<Map<String, Object?>> read();

  Future<void> write(Map<String, Object?> preferences);
}

/// Kept only while it lives, e.g. under test.
class MemoryPreferenceStore implements PreferenceStore {
  MemoryPreferenceStore([Map<String, Object?>? preferences])
    : preferences = {...?preferences};

  Map<String, Object?> preferences;

  @override
  Future<Map<String, Object?>> read() async => preferences;

  @override
  Future<void> write(Map<String, Object?> preferences) async =>
      this.preferences = preferences;
}
