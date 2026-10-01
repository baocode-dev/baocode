/// No home folder (the web).
String? get homeDirectory => null;

/// No local files (the web).
Future<bool> isDirectory(String path) async => false;
