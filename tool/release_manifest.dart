// Signs a release's installers and writes the manifest the app reads to
// update itself (https://dl.baocode.dev/releases/latest.json; see
// docs/auto-update.md). Run from anywhere in the repository:
//
//   dart run tool/release_manifest.dart \
//     --windows build/installers/BaoCode-1.2.0-setup.exe \
//     [--windows-arm64 build/installers/BaoCode-1.2.0-setup-arm64.exe] \
//     --macos-arm64 build/installers/BaoCode-1.2.0-mac-arm64.zip \
//     --macos-x64 build/installers/BaoCode-1.2.0-mac-x64.zip \
//     [--dmg-arm64 build/installers/BaoCode-1.2.0-arm64.dmg] \
//     [--dmg-x64 build/installers/BaoCode-1.2.0-x64.dmg] \
//     [--linux-x64 build/installers/BaoCode-1.2.0-linux-amd64.deb] \
//     [--linux-arm64 build/installers/BaoCode-1.2.0-linux-arm64.deb] \
//     [--notes-en <text or file>] [--notes-zh <text or file>] \
//     [--minimum-version 1.0.0] [--version 1.2.0+12] \
//     [--manifest build/installers/latest.json]
//
// The channel build's (lib/channel/) beside them, each option with
// -channel after it (--windows-channel, --macos-arm64-channel,
// --dmg-arm64-channel, --linux-x64-channel…): signed for its own platform
// keys (`windows-x64-channel`…), which the channel build alone updates from
// (each edition updates to itself), and given to the download page as
// `downloads.<os>.channel`, for whoever came through the site.
//
//   dart run tool/release_manifest.dart --generate-key <file>
//   dart run tool/release_manifest.dart --public-key
//
// The private key is a file holding 32 random bytes, base64; its path is
// in BAOCODE_UPDATE_SIGNING_KEY. Never in the repository: whoever has it
// can make every installed BaoCode run their program.
//
// The version is pubspec.yaml's unless given. A manifest already there for
// the same version keeps the other platforms' entries, so the Windows and the
// macOS installers can be signed on their own machines one after the other.
//
// Each link ends in `?sha256=<the file's first 16 hex digits>`: a file
// published again under the same name (a release redone) is another address
// to the CDN, which keeps downloads for a year, so no one is served the old
// one. The app names a download by the path alone.
//
// Besides what the app reads, `downloads` gives the download page
// (site/site.js) what it offers: the disk images (--dmg-arm64, --dmg-x64),
// which the app does not update from, the Windows installers (`windows`,
// and `windows-arm64`), and the Linux packages (which the app updates from
// too).
import 'dart:convert';
import 'dart:io';

import 'package:baocode/update/update_manifest.dart';
import 'package:baocode/update/update_signature.dart';
import 'package:baocode/update/version.dart';
import 'package:crypto/crypto.dart' as crypto;

/// Where the downloads go: `<base>/<1.2.0>/<file>`.
const _releasesBase = 'https://dl.baocode.dev/releases';

/// [name]'s link, for the file whose SHA-256 is [sha256].
Uri _link(AppVersion version, String name, String sha256) => Uri.parse(
  '$_releasesBase/${version.marketing}/$name?sha256=${sha256.substring(0, 16)}',
);

/// The Macs built for, each its own download (tool/build_macos.dart), and
/// the app takes its processor's (lib/update/installer_io.dart).
const _macArchitectures = ['arm64', 'x64'];

/// The Linux packages built (tool/package_linux_deb.sh), the same.
const _linuxArchitectures = ['x64', 'arm64'];

/// The Windows installers built (tool/build_windows.dart): `--windows` is
/// the x64 one, as it always was; Arm's is `--windows-arm64`.
const _windowsArchitectures = ['x64', 'arm64'];
String _windowsOption(String arch) =>
    arch == 'x64' ? 'windows' : 'windows-$arch';

/// The editions built: the standard one, and the channel build, whose
/// options and platform keys end in this.
const _channel = '-channel';
const _editions = ['', _channel];

/// Where the private key's path is given.
const _keyVariable = 'BAOCODE_UPDATE_SIGNING_KEY';

const _usage = '''
Usage:
  dart run tool/release_manifest.dart [--windows <setup.exe>]
      [--windows-arm64 <setup-arm64.exe>]
      [--macos-arm64 <mac-arm64.zip>] [--macos-x64 <mac-x64.zip>]
      [--dmg-arm64 <arm64.dmg>] [--dmg-x64 <x64.dmg>]
      [--linux-x64 <amd64.deb>] [--linux-arm64 <arm64.deb>]
      [each of those with -channel after it: the channel build's]
      [--notes-en <text|file>] [--notes-zh <text|file>]
      [--minimum-version <version>] [--version <version>]
      [--manifest <latest.json>]
  dart run tool/release_manifest.dart --generate-key <file>
  dart run tool/release_manifest.dart --public-key

The private key's path is read from \$$_keyVariable.''';

Future<void> main(List<String> arguments) async {
  final options = _parse(arguments);
  if (options.containsKey('help')) {
    stdout.writeln(_usage);
    return;
  }
  if (options['generate-key'] case final path?) return _generateKey(path);
  final seed = _readKey();
  final publicKey = UpdateSignature.publicKeyOf(seed);
  if (options.containsKey('public-key')) {
    stdout.writeln(publicKey);
    return;
  }
  if (publicKey != updatePublicKey) {
    _fail(
      'The key in \$$_keyVariable is not the one the app checks against.\n'
      '  its public key:   $publicKey\n'
      '  the app expects:  $updatePublicKey (lib/update/update_signature.dart)\n'
      'Releases signed with it would be refused by every installed BaoCode.',
    );
  }

  final root = File.fromUri(Platform.script).parent.parent.absolute;
  final version = AppVersion.parse(
    options['version'] ?? _pubspecVersion(File('${root.path}/pubspec.yaml')),
  );
  final files = {
    for (final edition in _editions) ...{
      for (final arch in _windowsArchitectures)
        if (options['${_windowsOption(arch)}$edition'] case final path?)
          'windows-$arch$edition': File(path),
      for (final arch in _macArchitectures)
        if (options['macos-$arch$edition'] case final path?)
          'macos-$arch$edition': File(path),
      for (final arch in _linuxArchitectures)
        if (options['linux-$arch$edition'] case final path?)
          'linux-$arch$edition': File(path),
    },
  };
  if (files.isEmpty) {
    _fail(
      'Nothing to sign: give --windows, --windows-arm64, --macos-arm64, '
      '--macos-x64, '
      '--linux-x64 or --linux-arm64.\n\n'
      '$_usage',
    );
  }
  final manifestFile = File(
    options['manifest'] ?? '${root.path}/build/installers/latest.json',
  );

  // The other platform's entry, signed before for the same version.
  var previous = <String, UpdateAsset>{};
  var notes = <String, String>{};
  var downloads = <String, Object?>{};
  AppVersion? minimum;
  if (manifestFile.existsSync()) {
    final text = manifestFile.readAsStringSync();
    final old = UpdateManifest.parse(text);
    if (old.version == version) {
      previous = {
        for (final platform in old.platforms) platform: old.assetFor(platform)!,
      };
      notes = {...old.notes};
      minimum = old.minimumVersion;
      if (jsonDecode(text) case {'downloads': final Map<String, Object?> d}) {
        downloads = {...d};
      }
    }
  }
  for (final language in ['en', 'zh']) {
    if (options['notes-$language'] case final value?) {
      notes[language] = _textOrFile(value);
    }
  }
  if (options['minimum-version'] case final value?) {
    minimum = AppVersion.parse(value);
  }

  final assets = {...previous};
  for (final MapEntry(key: platform, value: file) in files.entries) {
    if (!file.existsSync()) _fail('No such file: ${file.path}');
    stdout.writeln('Signing ${file.path} for $platform');
    final size = file.lengthSync();
    final sha256 = '${await crypto.sha256.bind(file.openRead()).first}';
    final payload = UpdateSignature.payload(
      version: '$version',
      platform: platform,
      size: size,
      sha256: sha256,
    );
    final signature = UpdateSignature.sign(payload: payload, seed: seed);
    if (!UpdateSignature.verify(payload: payload, signature: signature)) {
      _fail('The signature does not check out against the app\'s key.');
    }
    final name = file.uri.pathSegments.last;
    assets[platform] = UpdateAsset(
      url: _link(version, name, sha256),
      size: size,
      sha256: sha256,
      signature: signature,
    );
  }
  // [os]'s download for [edition]: the entry itself, the channel build's
  // in it as `channel`.
  void offer(String os, String edition, Map<String, Object?> file) {
    final entry = {
      if (downloads[os] case final Map<String, Object?> before) ...before,
    };
    if (edition == _channel) {
      entry['channel'] = file;
    } else {
      entry.addAll(file);
    }
    downloads[os] = entry;
  }

  for (final edition in _editions) {
    for (final arch in _windowsArchitectures) {
      if (assets['windows-$arch$edition'] case final installer?) {
        offer(_windowsOption(arch), edition, {
          'url': '${installer.url}',
          'size': installer.size,
          'sha256': installer.sha256,
        });
      }
    }
    // The packages as they are: the page's links, and the app's updates.
    for (final arch in _linuxArchitectures) {
      if (assets['linux-$arch$edition'] case final package?) {
        offer('linux-$arch', edition, {
          'url': '${package.url}',
          'size': package.size,
          'sha256': package.sha256,
        });
      }
    }
  }
  final dmgs = {
    for (final edition in _editions)
      for (final arch in _macArchitectures)
        if (options['dmg-$arch$edition'] case final path?)
          (os: 'macos-$arch', edition: edition): File(path),
  };
  for (final MapEntry(key: (:os, :edition), value: dmg) in dmgs.entries) {
    if (!dmg.existsSync()) _fail('No such file: ${dmg.path}');
    final sha256 = '${await crypto.sha256.bind(dmg.openRead()).first}';
    offer(os, edition, {
      'url': '${_link(version, dmg.uri.pathSegments.last, sha256)}',
      'size': dmg.lengthSync(),
      'sha256': sha256,
    });
  }

  final manifest = UpdateManifest(
    version: version,
    pubDate: DateTime.now().toUtc(),
    notes: notes,
    minimumVersion: minimum,
    platforms: assets,
  );
  final json = {
    ...manifest.toJson(),
    if (downloads.isNotEmpty) 'downloads': downloads,
  };
  final text = '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  // What the app will read: it has to read it back the same.
  UpdateManifest.parse(text);
  manifestFile.parent.createSync(recursive: true);
  manifestFile.writeAsStringSync(text);

  stdout
    ..writeln()
    ..writeln('Wrote ${manifestFile.path}')
    ..writeln()
    ..writeln('Upload, the installers first, the manifest last:');
  for (final MapEntry(key: platform, value: file) in files.entries) {
    stdout.writeln('  ${file.path}\n    -> ${assets[platform]!.url}');
  }
  for (final MapEntry(key: (:os, :edition), value: dmg) in dmgs.entries) {
    final entry = downloads[os] as Map;
    final file = edition == _channel ? entry['channel'] as Map : entry;
    stdout.writeln('  ${dmg.path}\n    -> ${file['url']}');
  }
  stdout.writeln('  ${manifestFile.path}\n    -> $defaultManifestUrl');
  // The channel build's too, once there is one.
  final missing = {
    for (final edition in _editions)
      if (edition.isEmpty ||
          assets.keys.any((key) => key.endsWith(edition))) ...{
        for (final arch in _windowsArchitectures) 'windows-$arch$edition',
        for (final arch in _macArchitectures) 'macos-$arch$edition',
        for (final arch in _linuxArchitectures) 'linux-$arch$edition',
      },
  }.difference(assets.keys.toSet());
  if (missing.isNotEmpty) {
    stdout.writeln(
      '\nNo download for ${missing.join(', ')} yet: those users are not '
      'offered $version until it is signed into this manifest too.',
    );
  }
}

/// Writes a new private key to [path] (never over one) and prints its
/// public half, for lib/update/update_signature.dart.
void _generateKey(String path) {
  final file = File(path);
  if (file.existsSync()) _fail('$path exists: not overwritten.');
  file.parent.createSync(recursive: true);
  final seed = UpdateSignature.generateSeed();
  file.writeAsStringSync('$seed\n');
  if (!Platform.isWindows) Process.runSync('chmod', ['600', path]);
  stdout
    ..writeln('Wrote the private key to $path. Keep it safe, and out of the')
    ..writeln('repository; point \$$_keyVariable at it to sign releases.')
    ..writeln()
    ..writeln('Its public key, for updatePublicKey in')
    ..writeln('lib/update/update_signature.dart:')
    ..writeln()
    ..writeln('  ${UpdateSignature.publicKeyOf(seed)}');
}

String _readKey() {
  final path = Platform.environment[_keyVariable];
  if (path == null || path.isEmpty) {
    _fail('\$$_keyVariable is not set: it is the private key file\'s path.');
  }
  final file = File(path);
  if (!file.existsSync()) _fail('No key at $path (\$$_keyVariable).');
  final seed = file.readAsStringSync().trim();
  try {
    if (base64.decode(seed).length == 32) return seed;
  } on FormatException {
    // Below.
  }
  _fail('$path does not hold a key (32 bytes, base64).');
}

String _pubspecVersion(File pubspec) {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) _fail('No "version:" line in ${pubspec.path}');
  return match.group(1)!;
}

/// [value] itself, or the file it names.
String _textOrFile(String value) {
  final file = File(value);
  return file.existsSync() ? file.readAsStringSync().trim() : value;
}

/// `--name value` pairs; `--flag` alone for those without one.
Map<String, String?> _parse(List<String> arguments) {
  const flags = {'public-key', 'help'};
  const files = {
    'windows',
    'windows-arm64',
    'macos-arm64',
    'macos-x64',
    'dmg-arm64',
    'dmg-x64',
    'linux-x64',
    'linux-arm64',
  };
  final valued = {
    for (final edition in _editions)
      for (final file in files) '$file$edition',
    'notes-en',
    'notes-zh',
    'minimum-version',
    'version',
    'manifest',
    'generate-key',
  };
  final options = <String, String?>{};
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    final name = argument.startsWith('--') ? argument.substring(2) : null;
    if (name == null || !(flags.contains(name) || valued.contains(name))) {
      _fail('Unknown argument: $argument\n\n$_usage');
    }
    if (flags.contains(name)) {
      options[name] = null;
    } else if (i + 1 < arguments.length) {
      options[name] = arguments[++i];
    } else {
      _fail('--$name needs a value.\n\n$_usage');
    }
  }
  return options;
}

Never _fail(String message) {
  stderr.writeln('\n$message');
  exit(1);
}
