import 'pty.dart';

/// The web has no processes: nothing starts on a pseudo terminal there.
bool get supported => false;

Future<Pty> spawn(PtyLaunch launch) async => throw const PtyException(
  'Pseudo terminals need dart:io',
  detail: 'The browser cannot start local processes.',
);
