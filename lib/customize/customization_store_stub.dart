import 'customizations.dart';

/// No files to customize Claude Code with on the web.
class CustomizationStore {
  CustomizationStore({this.configDir, this.homeDir});

  final String? configDir;
  final String? homeDir;

  bool get supported => false;

  Future<String> config() async => configDir ?? '';

  Future<List<Customization>> list(
    CustomizationKind kind, {
    String? project,
  }) async => const [];

  Future<String> read(String path) async => '';

  Future<void> write(String path, String text) async {}

  Future<String> create(
    CustomizationKind kind,
    CustomizationScope scope,
    String name, {
    String? project,
  }) => throw UnsupportedError('No files on the web');

  Future<void> delete(Customization item) async {}
}
