import 'dart:typed_data';

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

  @override
  Future<void> create(String path, {bool directory = false}) =>
      Future.error(UnsupportedError('Local editing requires the desktop app'));

  @override
  Future<void> rename(String from, String to) =>
      Future.error(UnsupportedError('Local editing requires the desktop app'));

  @override
  Future<void> copy(String from, String to) =>
      Future.error(UnsupportedError('Local editing requires the desktop app'));

  @override
  Future<void> delete(String path) =>
      Future.error(UnsupportedError('Local editing requires the desktop app'));

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      Future.error(UnsupportedError('Local editing requires the desktop app'));
}

Future<Uint8List> readFileBytes(String path) =>
    Future.error(UnsupportedError('Local editing requires the desktop app'));

Future<void> copyLocalTo(IdeFileService files, String from, String to) =>
    Future.error(UnsupportedError('Local editing requires the desktop app'));

Future<void> saveCopyTo(
  IdeFileService files,
  String from,
  String to, {
  String? text,
}) => Future.error(UnsupportedError('Local editing requires the desktop app'));

Future<IdeFileListing> walkProjectFiles(
  String root,
  Set<String> excluded,
  int limit,
) async => IdeFileListing(const []);

Stream<void> watchDirectory(String directory) => const Stream.empty();
