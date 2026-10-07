// Builds the macOS distribution: the Release .app, the .dmg that ships it,
// and the .zip the app updates itself from (lib/update/; signed into the
// release manifest by tool/release_manifest.dart). Run from anywhere in the
// repository:
//
//   dart run tool/build_macos.dart                build, then package
//   dart run tool/build_macos.dart --skip-build   package what is built
//
// Both land in build/installers/: BaoCode-<version>.dmg and
// BaoCode-<version>-mac.zip; beside them, remote/<VERSION>/, the remote
// server's gzipped builds, which the app downloads instead of carrying
// them (tool/build_remote_server.dart), to upload with the release.
//
// Not done yet: signing and notarising (the TODO in main). Without them
// Gatekeeper refuses the app on anyone else's machine.
import 'dart:io';

/// Where the .app flutter leaves behind goes, and where the disk image is
/// written. Under build/, which the repository already ignores and flutter
/// clean already removes.
const _bundleRelative = 'build/macos/Build/Products/Release/BaoCode.app';
const _installersRelative = 'build/installers';

/// Where the remote server is built (tool/build_remote_server.dart).
const _remoteRelative = 'build/remote';

/// What has to be in the .app for it to start. As on Windows, a build that
/// failed late still leaves an .app behind that looks complete — these are
/// what tell the difference.
const _required = [
  'Contents/MacOS/BaoCode',
  'Contents/Info.plist',
  'Contents/Frameworks/FlutterMacOS.framework',
  'Contents/Frameworks/App.framework',
  'Contents/Frameworks/App.framework/Resources/flutter_assets',
  // The terminal's native half (bao_pty's hook/build.dart builds it).
  'Contents/Frameworks/bao_pty.framework',
  // Finder's context menu (macos/FinderExtension), which Settings → General
  // turns on.
  'Contents/PlugIns/FinderExtension.appex',
  // The server remote projects run on their host (Linux x64 and arm64;
  // tool/build_remote_server.dart): which build, and where it is
  // downloaded from.
  'Contents/Resources/remote/VERSION',
  'Contents/Resources/remote/servers.json',
];

Future<void> main(List<String> arguments) async {
  if (!Platform.isMacOS) {
    _fail(
      'This builds the macOS disk image, and only runs on macOS.\n'
      'On Windows, use tool/build_windows.dart.',
    );
  }
  final skipBuild = arguments.contains('--skip-build');

  // The script lives in tool/, so the repository is one level above it.
  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final bundle = Directory('${root.path}/$_bundleRelative');
  final installers = Directory('${root.path}/$_installersRelative');
  final remote = Directory('${root.path}/$_remoteRelative');
  final version = _readVersion(File('${root.path}/pubspec.yaml'));

  if (!skipBuild) {
    _step('Building the Release app');
    await _run('flutter', ['build', 'macos', '--release'], root.path);
    _step('Building the remote server');
    await _run(Platform.resolvedExecutable, [
      'run',
      'tool/build_remote_server.dart',
      '--out',
      remote.path,
    ], root.path);
  } else {
    _step('Using the app already built');
  }

  // Into the .app before it is signed: its files are resources, sealed
  // with the rest. Not the builds themselves, which the app downloads.
  _step('Putting the remote server\'s download list in the app');
  final remoteVersion = _bundleRemote(
    remote,
    Directory('${bundle.path}/Contents/Resources/remote'),
  );

  _step('Checking the app');
  _checkBundle(bundle, _required);
  // An app built before pubspec.yaml's version changed (--skip-build) would
  // be shipped as the new version, and offered as an update to itself.
  final built = await _plist(bundle, 'CFBundleShortVersionString');
  final build = await _plist(bundle, 'CFBundleVersion');
  if (built != version.marketing || build != version.build) {
    _fail(
      'The app is version $built ($build), pubspec.yaml says '
      '${version.full}.\nBuild it again, without --skip-build.',
    );
  }

  // TODO(macos): sign and notarise here, before the disk image and the zip
  // are made of the app. Without both, Gatekeeper refuses the app on anyone
  // else's machine ("BaoCode is damaged and can't be opened"), and the .dmg
  // is only good for people who can run `xattr -d com.apple.quarantine` on
  // it. Both need an Apple Developer account ($99/year) and a "Developer ID
  // Application" certificate:
  //   codesign --deep --force --options runtime \
  //     --entitlements macos/Runner/Release.entitlements \
  //     --sign "Developer ID Application: <name> (<team>)" <the .app>
  //   xcrun notarytool submit <the .dmg> --wait \
  //     --apple-id <id> --team-id <team> --password <app-specific>
  //   xcrun stapler staple <the .dmg>
  // Sign before making the image, staple after: the ticket goes on the
  // .dmg, and the .app inside it has to be signed already. The update's zip
  // is made of the signed .app too (staple the .app itself before zipping
  // it, so the zip carries the ticket).
  //
  // Not --deep, though: it would give the Finder extension
  // (Contents/PlugIns/FinderExtension.appex) the app's entitlements, sandbox
  // off, and the system refuses to load an extension that is not
  // sandboxed. Sign the extension first, with its own, then the app around
  // it (the frameworks under Contents/Frameworks, signed without
  // entitlements, before the app too):
  //   codesign --force --options runtime \
  //     --entitlements macos/FinderExtension/FinderExtension.entitlements \
  //     --sign "Developer ID Application: <name> (<team>)" \
  //     <the .app>/Contents/PlugIns/FinderExtension.appex
  //
  // --entitlements is not optional here. macos/Runner/Release.entitlements
  // turns the sandbox OFF, which this app needs: it runs the Claude Code
  // CLI as a child process and reads its sessions under ~/.claude, and a
  // sandboxed app can do neither — nor could it replace itself to update.
  // Signing without it would silently re-enable the sandbox and the app
  // would fail at runtime, not at build time. Do not take the Xcode default
  // of DebugProfile's entitlements either: that one adds allow-jit and
  // network.server, which are for debugging.
  //
  // Once signed, an update has to be signed by the same team: the app
  // checks (lib/update/installer_io.dart).

  installers.createSync(recursive: true);

  _step('Making the disk image');
  final dmg = File('${installers.path}/BaoCode-${version.marketing}.dmg');
  // hdiutil gives a bare folder in a window; for a background picture and
  // an Applications shortcut, `brew install create-dmg` and drive that
  // instead.
  await _run('hdiutil', [
    'create',
    '-volname',
    'BaoCode ${version.marketing}',
    '-srcfolder',
    bundle.path,
    '-ov',
    // LZMA: a quarter smaller than the default UDZO's zlib; opens on
    // macOS 10.15 and later (the app needs 12).
    '-format',
    'ULMO',
    dmg.path,
  ], root.path);

  _step('Making the update archive');
  // What the app downloads to update itself: the .app, zipped as Finder
  // would (ditto keeps its symlinks, permissions and extended attributes,
  // which a framework's signature depends on).
  final zip = File('${installers.path}/BaoCode-${version.marketing}-mac.zip');
  if (zip.existsSync()) zip.deleteSync();
  await _run('ditto', [
    '-c',
    '-k',
    '--sequesterRsrc',
    '--keepParent',
    bundle.path,
    zip.path,
  ], root.path);

  _step('Putting the remote server\'s builds beside them');
  final downloads = Directory('${installers.path}/remote/$remoteVersion')
    ..createSync(recursive: true);
  final servers = [
    for (final file in remote.listSync())
      if (file is File && file.path.endsWith('.gz'))
        file.copySync('${downloads.path}/${file.uri.pathSegments.last}'),
  ];

  _step('Done');
  for (final file in [dmg, zip, ...servers]) {
    final mb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
    stdout.writeln('  ${file.path}  ($mb MB)');
  }
  stdout
    ..writeln()
    ..writeln('Upload the remote server\'s builds, which the app downloads:')
    ..writeln(
      '  ${downloads.path}/*  ->  '
      'https://baocode.dev/releases/remote/$remoteVersion/',
    )
    ..writeln()
    ..writeln('To publish it as an update, sign the zip into the manifest:')
    ..writeln('  dart run tool/release_manifest.dart --macos ${zip.path}');
}

/// Puts [remote]'s VERSION and servers.json (tool/build_remote_server.dart)
/// in [target], and nothing else: the builds an older run put there go.
/// Answers the VERSION.
String _bundleRemote(Directory remote, Directory target) {
  if (!File('${remote.path}/servers.json').existsSync()) {
    _fail(
      'No remote server built in ${remote.path}.\n'
      'Build it first, without --skip-build '
      '(or: dart run tool/build_remote_server.dart).',
    );
  }
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);
  for (final name in ['VERSION', 'servers.json']) {
    File('${remote.path}/$name').copySync('${target.path}/$name');
  }
  return File('${remote.path}/VERSION').readAsStringSync().trim();
}

/// The version pubspec.yaml carries, as `1.0.0+1`: the whole of it, the part
/// the app shows (CFBundleShortVersionString), and the build number after it
/// (CFBundleVersion).
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

/// [key] of the app's Info.plist; null when it has none.
Future<String?> _plist(Directory app, String key) async {
  final result = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    'Print :$key',
    '${app.path}/Contents/Info.plist',
  ]);
  return result.exitCode == 0 ? '${result.stdout}'.trim() : null;
}

/// Stops unless [directory] holds every one of [required].
void _checkBundle(Directory directory, List<String> required) {
  if (!directory.existsSync()) {
    _fail(
      'No app at ${directory.path}.\n'
      'Build it first, without --skip-build.',
    );
  }
  final missing = [
    for (final item in required)
      if (FileSystemEntity.typeSync('${directory.path}/$item') ==
          FileSystemEntityType.notFound)
        item,
  ];
  if (missing.isEmpty) {
    stdout.writeln('  ${directory.path} looks complete.');
    return;
  }
  _fail(
    'The app at ${directory.path} is incomplete; missing:\n'
    '${missing.map((item) => '  $item').join('\n')}\n'
    '\n'
    'A build that failed late leaves an app that looks whole and will not\n'
    'start. Build it again.',
  );
}

/// Runs [executable], printing the command; stops the script on a non-zero
/// exit.
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
