// Builds the Windows distribution: the Release bundle, then the installer
// Inno Setup makes of it. Run from anywhere in the repository:
//
//   dart run tool/build_windows.dart                build, then package
//   dart run tool/build_windows.dart --skip-build   package what is built
//
// The installer lands in build/installers/; beside it, remote\<VERSION>\,
// the remote server's gzipped builds, which the app downloads instead of
// carrying them (tool/build_remote_server.dart), to upload with the
// release.
import 'dart:io';

/// Where the bundle flutter leaves behind goes, and where the installer is
/// written. Under build/, which the repository already ignores and flutter
/// clean already removes.
const _bundleRelative = r'build\windows\x64\runner\Release';
const _installersRelative = r'build\installers';

/// What has to be in the bundle for the app to start. A Release build that
/// fails at the link step (a running baocode.exe holding the output file) still
/// leaves a baocode.exe behind — but data\ is written by the install step that
/// failure skipped, and the executable cannot start without it.
const _required = [
  'baocode.exe',
  'flutter_windows.dll',
  r'data\app.so',
  r'data\icudtl.dat',
  r'data\flutter_assets',
];

Future<void> main(List<String> arguments) async {
  if (!Platform.isWindows) {
    _fail(
      'This builds the Windows installer, and only runs on Windows.\n'
      'On macOS, use tool/build_macos.dart.',
    );
  }
  final skipBuild = arguments.contains('--skip-build');

  // The script lives in tool/, so the repository is one level above it.
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final bundle = Directory('${root.path}\\$_bundleRelative');
  final installers = Directory('${root.path}\\$_installersRelative');
  final version = _readVersion(File('${root.path}\\pubspec.yaml'));

  if (!skipBuild) {
    _step('Building the Release bundle');
    await _run('flutter', ['build', 'windows', '--release'], root.path);
  } else {
    _step('Using the bundle already built');
  }

  _step('Checking the bundle');
  _checkBundle(bundle, _required);

  // The server remote projects run on their host (Linux x64 and arm64):
  // which build, and where it is downloaded from, beside the executable
  // (the installer takes the bundle whole); not the builds themselves,
  // which the app downloads.
  _step('Building the remote server');
  final remote = Directory('${root.path}\\build\\remote');
  await _run(Platform.resolvedExecutable, [
    'run',
    '${root.path}\\tool\\build_remote_server.dart',
    '--out',
    remote.path,
  ], root.path);
  final bundleRemote = Directory('${bundle.path}\\remote');
  // The builds an older run put there go.
  if (bundleRemote.existsSync()) bundleRemote.deleteSync(recursive: true);
  bundleRemote.createSync(recursive: true);
  for (final name in ['VERSION', 'servers.json']) {
    File('${remote.path}\\$name').copySync('${bundleRemote.path}\\$name');
  }
  _checkBundle(bundle, [r'remote\VERSION', r'remote\servers.json']);
  final remoteVersion = File(
    '${remote.path}\\VERSION',
  ).readAsStringSync().trim();

  _step('Compiling the installer');
  final iscc = _findIscc();
  installers.createSync(recursive: true);
  await _run(iscc, [
    '/DBundleDir=${bundle.path}',
    '/DAppVersion=${version.full}',
    '/DOutDir=${installers.path}',
    '${root.path}\\tool\\baocode.iss',
  ], root.path);

  _step('Putting the remote server\'s builds beside it');
  final downloads = Directory('${installers.path}\\remote\\$remoteVersion')
    ..createSync(recursive: true);
  final servers = [
    for (final file in remote.listSync())
      if (file is File && file.path.endsWith('.gz'))
        file.copySync('${downloads.path}\\${file.uri.pathSegments.last}'),
  ];

  _step('Done');
  final installer = File(
    '${installers.path}\\BaoCode-${version.marketing}-setup.exe',
  );
  for (final file in [installer, ...servers]) {
    if (!file.existsSync()) continue;
    final mb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    stdout.writeln('  ${file.path}  ($mb MB)');
  }
  stdout
    ..writeln()
    ..writeln('Upload the remote server\'s builds, which the app downloads')
    ..writeln('(their folder is named by the build: the macOS one\'s, if it')
    ..writeln('differs, goes beside it):')
    ..writeln(
      '  ${downloads.path}\\*  ->  '
      'https://dl.baocode.dev/releases/remote/$remoteVersion/',
    );
  stdout.writeln();
  stdout.writeln(
    'The app needs the Microsoft Visual C++ Redistributable (x64). Windows\n'
    '10 and 11 normally have it; the installer does not bundle it.',
  );
}

/// The version pubspec.yaml carries, as `1.0.0+1`: the whole of it, the part
/// Windows records as the product version, and the build number after it.
({String full, String marketing, String build}) _readVersion(File pubspec) {
  final text = pubspec.readAsStringSync();
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(text);
  if (match == null) {
    _fail('No "version:" line in ${pubspec.path}');
  }
  final full = match.group(1)!;
  final plus = full.indexOf('+');
  return (
    full: full,
    marketing: plus < 0 ? full : full.substring(0, plus),
    build: plus < 0 ? '0' : full.substring(plus + 1),
  );
}

/// Stops unless [directory] holds every one of [required].
void _checkBundle(Directory directory, List<String> required) {
  if (!directory.existsSync()) {
    _fail(
      'No bundle at ${directory.path}.\n'
      'Build it first, without --skip-build.',
    );
  }
  final missing = [
    for (final item in required)
      if (FileSystemEntity.typeSync('${directory.path}\\$item') ==
          FileSystemEntityType.notFound)
        item,
  ];
  if (missing.isEmpty) {
    stdout.writeln('  ${directory.path} looks complete.');
    return;
  }
  _fail(
    'The bundle at ${directory.path} is incomplete; missing:\n'
    '${missing.map((item) => '  $item').join('\n')}\n'
    '\n'
    'A Release build that failed at the link step leaves exactly this: the\n'
    'install step that writes data\\ never ran. If the build reported\n'
    'LNK1104, a running baocode.exe is holding the output file — close it and\n'
    'build again.',
  );
}

/// The Inno Setup compiler: where winget puts it, then where a manual
/// install does, then wherever the PATH has it.
String _findIscc() {
  final local = Platform.environment['LOCALAPPDATA'];
  final candidates = [
    if (local != null) '$local\\Programs\\Inno Setup 6\\ISCC.exe',
    for (final variable in ['ProgramFiles(x86)', 'ProgramFiles'])
      if (Platform.environment[variable] case final root?)
        '$root\\Inno Setup 6\\ISCC.exe',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  _fail(
    'ISCC.exe (the Inno Setup compiler) was not found. Install it with:\n'
    '\n'
    '  winget install --id JRSoftware.InnoSetup\n'
    '\n'
    'or download it from https://jrsoftware.org/isdl.php',
  );
}

/// Runs [executable], printing the command; stops the script on a non-zero
/// exit. A .bat (flutter's own launcher, on Windows) needs a shell.
Future<void> _run(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  stdout.writeln('  \$ $executable ${arguments.join(' ')}');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: executable == 'flutter',
  );
  final output = '${result.stdout}'.trim();
  if (output.isNotEmpty) stdout.writeln(output);
  final error = '${result.stderr}'.trim();
  if (error.isNotEmpty) stderr.writeln(error);
  if (result.exitCode != 0) {
    _fail('$executable exited with code ${result.exitCode}.');
  }
}

void _step(String message) => stdout.writeln('\n==> $message');

Never _fail(String message) {
  stderr.writeln('\n$message');
  exit(1);
}
