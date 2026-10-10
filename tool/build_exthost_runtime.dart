// Builds the extension runtime the app downloads on demand: VSCodium's
// remote extension host (REH, MIT) at the pinned version, rebranded and
// trimmed, for each platform. Run from anywhere in the repository:
//
//   dart run tool/build_exthost_runtime.dart            all five platforms
//   dart run tool/build_exthost_runtime.dart --platforms darwin-arm64,linux-x64
//   dart run tool/build_exthost_runtime.dart --out <dir>   (build/exthost-runtime)
//   dart run tool/build_exthost_runtime.dart --check
//       build, and fail unless the result is what
//       assets/exthost/exthost_runtimes.json says (CI: what is uploaded is
//       what the app checks against)
//
// For each platform it downloads vscodium-reh-<platform>-<version>.tar.gz
// from VSCodium's GitHub release (kept in <out>/downloads/ and reused),
// checks it against the SHA-256 pinned below and the release's .sha256,
// unpacks it, changes it as [_rebrand] and [_strip] say, and packs it again
// as baocode-exthost-<platform>-<version>.tar.gz (.zip for Windows). The
// archives are deterministic: entries sorted, no owners, one date (the
// product's), so the same input gives the same bytes.
//
// Then exthost_runtimes.json, which names each archive's URL, size and
// SHA-256 under https://dl.baocode.dev/releases/exthost/<version>-<hash>/,
// the hash being the first 8 hex digits of the SHA-256 of the archives'
// ("<platform> <sha256>\n", in platform order). With all five platforms it
// also goes to assets/exthost/, which the app ships
// (packages/bao_exthost/lib/src/runtime/runtime_installer.dart reads it). The
// archives are uploaded to that folder (.github/workflows/exthost-runtime.yml),
// never over one that is there.
//
// Upgrading: change _version, _productCommit, _upstream* and the pinned
// hashes, run it, commit the manifest, and port the protocol to the new
// upstream commit (docs/extensions/PROGRESS.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// VSCodium's release (github.com/VSCodium/vscodium/releases/tag/1.135.06055).
const _version = '1.135.06055';

/// Its product.json's `commit`, which the server's handshake checks.
const _productCommit = '1a46a584725d5dd330e0bcd7f5510f24990efcf2';

/// The VS Code release it is built from (VSCodium's upstream/stable.json).
const _upstreamVersion = '1.135.0';
const _upstreamCommit = '08d4889f9ec4a1685d257b9b95de036c8e1ce1e5';

/// The REH archives' SHA-256, as published with the release: a download
/// that differs is refused even when the release's .sha256 agrees.
const _pinned = {
  'darwin-arm64':
      'f645669f423f88fd2626d88f80d3f931b6c21fda93df4177d19a91c46815be1c',
  'darwin-x64':
      'dc80d0c01f870c0c2c4d26469ce3c1ce80dd449b227cd8aee88af4fceb0e7453',
  'win32-x64':
      '3f7d84ba5b4440e4e328dad4fe182f14bba7333db170485e989ac2c1c49b6a0c',
  'linux-x64':
      'bd23015a35b915bac3c6fca962ca5db427f5c8f049702e48ddeb72757ab32745',
  'linux-arm64':
      '697d2cf622152b3b3affbbd18d48e5ff51e1e2fbf5833ad66262bda413c599c5',
};

const _releaseBase =
    'https://github.com/VSCodium/vscodium/releases/download/$_version';
const _downloadsBase = 'https://dl.baocode.dev/releases/exthost';

/// product.json's fields that make it BaoCode's. `commit`, `version`,
/// `quality`, `extensionsGallery` (Open VSX) and
/// `extensionEnabledApiProposals` stay as they are.
const _rebrand = {
  'nameShort': 'BaoCode',
  'nameLong': 'BaoCode',
  'applicationName': 'baocode',
  'serverApplicationName': 'baocode-server',
  'urlProtocol': 'baocode',
  'serverDataFolderName': '.baocode-server',
  'dataFolderName': '.baocode',
};

/// What is taken out, each for a reason; every one must be there (an
/// upgrade that moves one fails here, to be looked at again).
List<(String, String)> _strip(String platform) => [
  (
    'bin/remote-cli',
    'The `codium` command the server puts on its own terminals\' PATH. '
        'BaoCode runs terminals itself (lib/ide/terminal), not through the '
        'server; it would only shadow a VSCodium install\'s `codium` in the '
        'extension host\'s child processes.',
  ),
  (
    'extensions/mermaid-markdown-features',
    'Mermaid diagrams for the Markdown preview, notebooks and chat: all '
        'drawn in webviews, which BaoCode does not have (59 MB).',
  ),
  // ripgrep-universal carries rg for 12 platforms; lib/index.js runs
  // bin/<process.platform>-<process.arch>/rg only (npm_config_arch aside,
  // which the app clears for the server).
  for (final other in _ripgrepPlatforms)
    if (other != platform)
      (
        'node_modules/@vscode/ripgrep-universal/bin/$other',
        'ripgrep for another platform',
      ),
];

const _ripgrepPlatforms = [
  'darwin-arm64',
  'darwin-x64',
  'linux-arm',
  'linux-arm64',
  'linux-ia32',
  'linux-ppc64',
  'linux-riscv64',
  'linux-s390x',
  'linux-x64',
  'win32-arm64',
  'win32-ia32',
  'win32-x64',
];

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent.absolute.path;
  String? option(String name) {
    final at = arguments.indexOf(name);
    return at >= 0 && at + 1 < arguments.length ? arguments[at + 1] : null;
  }

  final out = Directory(
    p.absolute(option('--out') ?? p.join(root, 'build', 'exthost-runtime')),
  )..createSync(recursive: true);
  final platforms =
      option('--platforms')?.split(',').map((s) => s.trim()).toList() ??
      extHostRuntimePlatforms;
  for (final platform in platforms) {
    if (!_pinned.containsKey(platform)) {
      _fail('Unknown platform $platform (${_pinned.keys.join(', ')})');
    }
  }
  final check = arguments.contains('--check');
  final all = extHostRuntimePlatforms.every(platforms.contains);
  final committed = p.join(root, 'assets', 'exthost', 'exthost_runtimes.json');
  if (check && !all) _fail('--check builds all five platforms');

  await _checkUpstream();

  final assets = <String, Map<String, Object?>>{};
  final nodeVersions = <String, String>{};
  for (final platform in extHostRuntimePlatforms) {
    if (!platforms.contains(platform)) continue;
    _step(_describe(platform));
    final source = await _download(platform, p.join(out.path, 'downloads'));
    final staging = Directory(p.join(out.path, 'staging', platform));
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    stdout.writeln('  unpacking');
    final executables = {
      for (final file in await extractTarGzFile(source, staging.path))
        _relative(staging.path, file),
    };
    _checkProduct(staging.path);
    _rewriteProduct(staging.path);
    for (final (path, reason) in _strip(platform)) {
      final target = p.join(staging.path, path);
      if (!FileSystemEntity.isDirectorySync(target)) {
        _fail('$platform: nothing at $path to remove ($reason)');
      }
      Directory(target).deleteSync(recursive: true);
    }
    nodeVersions[platform] = _nodeVersion(staging.path, platform);

    final windows = platform.startsWith('win32');
    final file =
        'baocode-exthost-$platform-$_version.${windows ? 'zip' : 'tar.gz'}';
    final archive = p.join(out.path, file);
    stdout.writeln('  packing $file');
    await _pack(staging.path, archive, executables, zip: windows);
    staging.deleteSync(recursive: true);
    final bytes = File(archive).lengthSync();
    final sha = await _sha256(archive);
    stdout.writeln('  ${(bytes / 1048576).toStringAsFixed(1)} MB, sha256 $sha');
    assets[platform] = {'file': file, 'size': bytes, 'sha256': sha};
  }
  final node = nodeVersions.values.toSet();
  if (node.length != 1) _fail('The platforms differ in Node: $nodeVersions');

  final lines = [
    for (final platform in extHostRuntimePlatforms)
      if (assets[platform] case final asset?) '$platform ${asset['sha256']}\n',
  ].join();
  final hash = sha256.convert(utf8.encode(lines)).toString().substring(0, 8);
  final id = '$_version-$hash';
  final baseUrl = '$_downloadsBase/$id/';
  final manifest = {
    'version': _version,
    'id': id,
    'productCommit': _productCommit,
    'upstreamVersion': _upstreamVersion,
    'upstreamCommit': _upstreamCommit,
    'nodeVersion': node.single,
    'baseUrl': baseUrl,
    'platforms': {
      for (final platform in extHostRuntimePlatforms)
        if (assets[platform] case final asset?)
          platform: {
            'file': asset['file'],
            'url': '$baseUrl${asset['file']}',
            'size': asset['size'],
            'sha256': asset['sha256'],
          },
    },
  };
  // Parsed as the app parses it.
  final json = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  ExtHostRuntimeManifest.parse(json);
  File(p.join(out.path, 'exthost_runtimes.json')).writeAsStringSync(json);

  if (check) {
    final expected = File(committed).existsSync()
        ? File(committed).readAsStringSync()
        : '';
    if (expected != json) {
      stderr.writeln(json);
      _fail(
        'This build is not the one assets/exthost/exthost_runtimes.json '
        'names (above: this one). Build it again where it was built (same '
        'Dart, same machine kind), or commit this manifest.',
      );
    }
    _step('Same as assets/exthost/exthost_runtimes.json');
  } else if (all) {
    File(committed)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(json);
    _step('Wrote ${p.relative(committed, from: root)}');
  } else {
    stdout.writeln(
      '\nNot all platforms: assets/exthost/exthost_runtimes.json is left '
      'as it is.',
    );
  }
  _step('Done: ${out.path} ($id)');
  stdout.writeln('Upload to releases/exthost/$id/ (only if it is not there):');
  for (final asset in assets.values) {
    stdout.writeln(
      '  wrangler r2 object put "\$R2_BUCKET/releases/exthost/$id/${asset['file']}" '
      '--remote --file "${p.join(out.path, '${asset['file']}')}" '
      '--cache-control "public, max-age=31536000, immutable" '
      '--content-type ${'${asset['file']}'.endsWith('.zip') ? 'application/zip' : 'application/gzip'}',
    );
  }
}

/// VSCodium's own record of what the release is built from.
Future<void> _checkUpstream() async {
  final url = Uri.parse(
    'https://raw.githubusercontent.com/VSCodium/vscodium/$_version/upstream/stable.json',
  );
  try {
    final json = jsonDecode(utf8.decode(await _get(url))) as Map;
    if (json['tag'] != _upstreamVersion || json['commit'] != _upstreamCommit) {
      _fail(
        'VSCodium $_version is built from VS Code ${json['tag']} '
        '(${json['commit']}), not $_upstreamVersion ($_upstreamCommit)',
      );
    }
  } on IOException catch (error) {
    stdout.writeln('Could not check $url ($error); going on.');
  }
}

/// The REH archive, downloaded unless it is already, and checked.
Future<String> _download(String platform, String directory) async {
  Directory(directory).createSync(recursive: true);
  final name = 'vscodium-reh-$platform-$_version.tar.gz';
  final file = p.join(directory, name);
  final published = p.join(directory, '$name.sha256');
  if (!File(published).existsSync()) {
    File(published)
        .writeAsBytesSync(await _get(Uri.parse('$_releaseBase/$name.sha256')));
  }
  final listed = File(published)
      .readAsStringSync()
      .trim()
      .split(RegExp(r'\s+'))
      .first;
  if (listed != _pinned[platform]) {
    _fail('$name.sha256 says $listed, not the pinned ${_pinned[platform]}');
  }
  if (File(file).existsSync() && await _sha256(file) == listed) {
    stdout.writeln('  $name (downloaded before)');
    return file;
  }
  stdout.writeln('  downloading $name');
  final partial = '$file.part';
  final sink = File(partial).openWrite();
  await sink.addStream(_getStream(Uri.parse('$_releaseBase/$name')));
  await sink.close();
  final sha = await _sha256(partial);
  if (sha != listed) {
    File(partial).deleteSync();
    _fail('$name has SHA-256 $sha, not $listed');
  }
  File(partial).renameSync(file);
  return file;
}

Future<List<int>> _get(Uri url) async {
  final builder = BytesBuilder(copy: false);
  await _getStream(url).forEach(builder.add);
  return builder.takeBytes();
}

Stream<List<int>> _getStream(Uri url) async* {
  final client = HttpClient()..userAgent = 'BaoCode build';
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    yield* response;
  } finally {
    client.close();
  }
}

/// What the REH must be: the pinned build, its gallery Open VSX.
void _checkProduct(String root) {
  final product =
      jsonDecode(File(p.join(root, 'product.json')).readAsStringSync()) as Map;
  if (product['commit'] != _productCommit || product['version'] != _version) {
    _fail(
      'product.json is ${product['version']} (${product['commit']}), not '
      '$_version ($_productCommit)',
    );
  }
  final gallery = product['extensionsGallery'];
  if (gallery is! Map ||
      !'${gallery['serviceUrl']}'.startsWith('https://open-vsx.org/')) {
    _fail('product.json\'s extensionsGallery is not Open VSX: $gallery');
  }
  if (product['extensionEnabledApiProposals'] is! Map) {
    _fail('product.json has no extensionEnabledApiProposals');
  }
}

void _rewriteProduct(String root) {
  final file = File(p.join(root, 'product.json'));
  final product = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  for (final MapEntry(:key, :value) in _rebrand.entries) {
    if (!product.containsKey(key)) _fail('product.json has no "$key"');
    product[key] = value;
  }
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(product)}\n',
  );
}

/// Node's version, from the binary (`process.release`'s headers URL), as
/// another platform's cannot be run here.
String _nodeVersion(String root, String platform) {
  final node = p.join(root, platform.startsWith('win32') ? 'node.exe' : 'node');
  final text = latin1.decode(File(node).readAsBytesSync());
  final versions = RegExp(r'nodejs\.org/download/release/v(\d+\.\d+\.\d+)/')
      .allMatches(text)
      .map((m) => m[1]!)
      .toSet();
  if (versions.length != 1) {
    _fail('$platform: cannot tell the Node version ($versions)');
  }
  return versions.single;
}

/// Packs [root] into [archive], entries sorted by path, all dated as the
/// product is.
Future<void> _pack(
  String root,
  String archive,
  Set<String> executables, {
  required bool zip,
}) async {
  final product =
      jsonDecode(File(p.join(root, 'product.json')).readAsStringSync()) as Map;
  final mtime =
      DateTime.parse(product['date'] as String).millisecondsSinceEpoch ~/ 1000;
  final entries = <(String, bool)>[];
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is Link) _fail('Unexpected link: ${entity.path}');
    entries.add((_relative(root, entity.path), entity is Directory));
  }
  entries.sort((a, b) => a.$1.compareTo(b.$1));
  int mode(String path) => executables.contains(path) ? 0x1ED : 0x1A4;

  final out = File(archive).openSync(mode: FileMode.write);
  if (zip) {
    final writer = ZipWriter(out);
    for (final (path, directory) in entries) {
      if (directory) {
        writer.addDirectory(path);
      } else {
        writer.addFile(
          path,
          File(p.join(root, path)).readAsBytesSync(),
          mode: mode(path),
        );
      }
    }
    writer.close();
    return;
  }
  final gzip = ZLibEncoder(
    gzip: true,
    level: 9,
  ).startChunkedConversion(_FileSink(out));
  final tar = TarWriter(gzip, mtime: mtime);
  for (final (path, directory) in entries) {
    if (directory) {
      tar.addDirectory(path);
    } else {
      tar.addFile(
        path,
        File(p.join(root, path)).readAsBytesSync(),
        mode: mode(path),
      );
    }
  }
  tar.close();
  // gzip's OS byte is the zlib build's; "unknown" for all.
  final patch = File(archive).openSync(mode: FileMode.append)
    ..setPositionSync(9)
    ..writeByteSync(0xFF);
  patch.closeSync();
}

final class _FileSink implements Sink<List<int>> {
  _FileSink(this._file);

  final RandomAccessFile _file;

  @override
  void add(List<int> data) => _file.writeFromSync(data);

  @override
  void close() => _file.closeSync();
}

String _relative(String root, String path) =>
    p.posix.joinAll(p.split(p.relative(path, from: root)));

Future<String> _sha256(String file) async =>
    (await sha256.bind(File(file).openRead()).first).toString();

String _describe(String platform) => switch (platform) {
  'darwin-arm64' => 'macOS arm64',
  'darwin-x64' => 'macOS x64',
  'win32-x64' => 'Windows x64',
  'linux-x64' => 'Linux x64',
  'linux-arm64' => 'Linux arm64',
  _ => platform,
};

void _step(String message) => stdout.writeln('\n==> $message');

Never _fail(String message) {
  stderr.writeln('\n$message');
  exit(1);
}
