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
// Signed with a Developer ID and notarised when the environment says how
// (docs/release.md has how to get each):
//
//   BAOCODE_MACOS_SIGN_IDENTITY  "Developer ID Application: <name> (<team>)",
//                                its certificate in a keychain searched
//   BAOCODE_NOTARY_KEY           an App Store Connect API key (.p8), its path
//   BAOCODE_NOTARY_KEY_ID        that key's ID
//   BAOCODE_NOTARY_ISSUER        its issuer ID
//
// Without an identity the app stays signed ad hoc, as flutter builds it:
// fine on this machine, refused by Gatekeeper on anyone else's ("BaoCode is
// damaged and can't be opened"). Signed but not notarised, it is refused
// too, with another message.
import 'dart:convert';
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

  final signing = _Signing.fromEnvironment(root);
  if (signing == null) {
    _step('Not signing: \$BAOCODE_MACOS_SIGN_IDENTITY is not set');
    stdout.writeln(
      '  Signed ad hoc, the app opens on this machine only: Gatekeeper\n'
      '  refuses it anywhere else.',
    );
  } else {
    _step('Signing the app as ${signing.identity}');
    await signing.signApp(bundle);
  }

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

  if (signing != null) {
    _step('Signing the disk image');
    await signing.sign(dmg.path);
    if (signing.notary == null) {
      _step('Not notarising: \$BAOCODE_NOTARY_KEY is not set');
      stdout.writeln(
        '  Signed but not notarised, the app is still refused by\n'
        '  Gatekeeper on other machines.',
      );
    } else {
      // Notarising the image notarises the app in it too: the ticket
      // stapled to each is the one for its own signature.
      _step('Notarising the disk image (a few minutes)');
      await signing.notarise(dmg);
      _step('Stapling the tickets');
      await _run('xcrun', ['stapler', 'staple', dmg.path], root.path);
      await _run('xcrun', ['stapler', 'staple', bundle.path], root.path);
    }
  }

  _step('Making the update archive');
  // What the app downloads to update itself: the .app (signed and stapled
  // when it was), zipped as Finder would (ditto keeps its symlinks, permissions and extended attributes,
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
      'https://dl.baocode.dev/releases/remote/$remoteVersion/',
    )
    ..writeln()
    ..writeln('To publish it as an update, sign the zip into the manifest:')
    ..writeln('  dart run tool/release_manifest.dart --macos ${zip.path}');
}

/// Signing with a Developer ID, and notarising, as the environment says
/// (the variables at the top of this file).
class _Signing {
  _Signing(this.root, this.identity, this.notary);

  /// Null when no identity is given: the app stays signed ad hoc.
  static _Signing? fromEnvironment(Directory root) {
    final environment = Platform.environment;
    final identity = environment['BAOCODE_MACOS_SIGN_IDENTITY'] ?? '';
    if (identity.isEmpty) return null;
    final key = environment['BAOCODE_NOTARY_KEY'] ?? '';
    final keyId = environment['BAOCODE_NOTARY_KEY_ID'] ?? '';
    final issuer = environment['BAOCODE_NOTARY_ISSUER'] ?? '';
    if (key.isEmpty) return _Signing(root, identity, null);
    if (keyId.isEmpty || issuer.isEmpty) {
      _fail(
        '\$BAOCODE_NOTARY_KEY is set: \$BAOCODE_NOTARY_KEY_ID and '
        '\$BAOCODE_NOTARY_ISSUER have to be too.',
      );
    }
    if (!File(key).existsSync()) _fail('No API key at $key.');
    return _Signing(root, identity, (key: key, keyId: keyId, issuer: issuer));
  }

  final Directory root;
  final String identity;
  final ({String key, String keyId, String issuer})? notary;

  /// Signs the .app inside out: its frameworks, then the Finder extension,
  /// then the app around them, each with the hardened runtime notarising
  /// asks for and a secure timestamp.
  ///
  /// Not `codesign --deep`: it would give the Finder extension the app's
  /// entitlements, sandbox off, and the system refuses to load an extension
  /// that is not sandboxed. The extension takes its own.
  ///
  /// And the app takes macos/Runner/Release.entitlements, not none: those
  /// turn the sandbox off, which this app needs (it runs the Claude Code
  /// CLI as a child process and reads its sessions under ~/.claude, and
  /// replaces itself to update). Signed without them it would fail at
  /// runtime, not here. Not DebugProfile's either: allow-jit and
  /// network.server are for debugging.
  ///
  /// Once released signed, an update has to be signed by the same team:
  /// the app checks (lib/update/installer_io.dart).
  Future<void> signApp(Directory app) async {
    final frameworks = Directory('${app.path}/Contents/Frameworks');
    for (final entry in frameworks.listSync()) {
      if (entry.path.endsWith('.framework') || entry.path.endsWith('.dylib')) {
        await sign(entry.path);
      }
    }
    await sign(
      '${app.path}/Contents/PlugIns/FinderExtension.appex',
      entitlements: 'macos/FinderExtension/FinderExtension.entitlements',
    );
    await sign(app.path, entitlements: 'macos/Runner/Release.entitlements');
    await _run('codesign', [
      '--verify',
      '--deep',
      '--strict',
      '--verbose=2',
      app.path,
    ], root.path);
  }

  Future<void> sign(String path, {String? entitlements}) => _run('codesign', [
    '--force',
    '--options',
    'runtime',
    '--timestamp',
    if (entitlements != null) ...['--entitlements', entitlements],
    '--sign',
    identity,
    path,
  ], root.path);

  /// Sends [file] to Apple's notary service and waits for its verdict;
  /// stops with Apple's log when it is not accepted.
  Future<void> notarise(File file) async {
    final notary = this.notary!;
    final credentials = [
      '--key',
      notary.key,
      '--key-id',
      notary.keyId,
      '--issuer',
      notary.issuer,
    ];
    final result = await Process.run('xcrun', [
      'notarytool',
      'submit',
      file.path,
      ...credentials,
      '--wait',
      '--output-format',
      'json',
    ]);
    final Map<String, Object?> answer;
    try {
      answer = jsonDecode('${result.stdout}') as Map<String, Object?>;
    } on FormatException {
      _fail('notarytool answered:\n${result.stdout}\n${result.stderr}');
    }
    stdout.writeln('  ${answer['status']} (submission ${answer['id']})');
    if (answer['status'] != 'Accepted') {
      final log = await Process.run('xcrun', [
        'notarytool',
        'log',
        '${answer['id']}',
        ...credentials,
      ]);
      _fail('Apple did not notarise ${file.path}:\n${log.stdout}');
    }
  }
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
