import 'terminal_link_parsing.dart';

/// The web has no file system to resolve links on.
OperatingSystem get hostOperatingSystem => OperatingSystem.linux;

String? get hostUserHome => null;

Future<bool?> statPath(String path) async => null;
