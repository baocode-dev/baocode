// Signs a release's installers and writes the manifest the app reads to
// update itself (https://baocode.dev/releases/latest.json; see
// docs/auto-update.md). Run from anywhere in the repository:
//
//   dart run tool/release_manifest.dart \
//     --windows build/installers/BaoCode-1.2.0-setup.exe \
//     --macos build/installers/BaoCode-1.2.0-mac.zip \
//     [--notes-en <text or file>] [--notes-zh <text or file>] \
//     [--minimum-version 1.0.0] [--version 1.2.0+12] \
//     [--manifest build/installers/latest.json]
//
//   dart run tool/release_manifest.dart --generate-key <file>
//   dart run tool/release_manifest.dart --public-key
//
// The private key is a file holding 32 random bytes, base64; its path is
// in BAOCODE_UPDATE_SIGNING_KEY. Never in the repository: whoever has it
// can make every installed BaoCode run their program.
//
// The version is pubspec.yaml's unless given. A manifest already there for
// the same version keeps its other platform's entry, so the Windows and the
// macOS installers can be signed on their own machines one after the other.
import 'dart:convert';
import 'dart:io';

import 'package:baocode/update/update_manifest.dart';
import 'package:baocode/update/update_signature.dart';
import 'package:baocode/update/version.dart';
import 'package:crypto/crypto.dart' as crypto;

/// Where the downloads go: `<base>/<1.2.0>/<file>`.
const _releasesBase = 'https://baocode.dev/releases';

/// Where the private key's path is given.
const _keyVariable = 'BAOCODE_UPDATE_SIGNING_KEY';

const _usage = '''
Usage:
  dart run tool/release_manifest.dart [--windows <setup.exe>] [--macos <mac.zip>]
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
    if (options['windows'] case final path?) 'windows-x64': File(path),
    if (options['macos'] case final path?) 'macos-universal': File(path),
  };
  if (files.isEmpty) {
    _fail('Nothing to sign: give --windows and/or --macos.\n\n$_usage');
  }
  final manifestFile = File(
    options['manifest'] ?? '${root.path}/build/installers/latest.json',
  );

  // The other platform's entry, signed before for the same version.
  var previous = <String, UpdateAsset>{};
  var notes = <String, String>{};
  AppVersion? minimum;
  if (manifestFile.existsSync()) {
    final old = UpdateManifest.parse(manifestFile.readAsStringSync());
    if (old.version == version) {
      previous = {
        for (final platform in old.platforms) platform: old.assetFor(platform)!,
      };
      notes = {...old.notes};
      minimum = old.minimumVersion;
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
      url: Uri.parse('$_releasesBase/${version.marketing}/$name'),
      size: size,
      sha256: sha256,
      signature: signature,
    );
  }

  final manifest = UpdateManifest(
    version: version,
    pubDate: DateTime.now().toUtc(),
    notes: notes,
    minimumVersion: minimum,
    platforms: assets,
  );
  final text =
      '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n';
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
  stdout.writeln('  ${manifestFile.path}\n    -> $defaultManifestUrl');
  final missing = {
    'windows-x64',
    'macos-universal',
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
  const valued = {
    'windows',
    'macos',
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
