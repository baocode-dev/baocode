import 'file_service.dart';

class LocalIdeFileService implements IdeFileService {
  LocalIdeFileService(this.root);

  final String root;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) =>
      Future.error(UnsupportedError('Local editing requires the desktop app'));

  @override
  Future<void> write(String path, String text, {String? expectedText}) =>
      Future.error(UnsupportedError('Local editing requires the desktop app'));
}

Future<IdeFileListing> walkProjectFiles(
  String root,
  Set<String> excluded,
  int limit,
) async => IdeFileListing(const []);
