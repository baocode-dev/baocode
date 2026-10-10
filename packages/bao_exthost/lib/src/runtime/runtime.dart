// An installed extension runtime: VSCodium's REH, as
// tool/build_exthost_runtime.dart repacks it.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'runtime_errors.dart';

/// The runtime in [root]: `node` (`node.exe`), `out/server-main.js`,
/// `product.json`, `extensions/` (the built-in extensions),
/// `node_modules/`, `bin/`.
final class ExtHostRuntime {
  const ExtHostRuntime({
    required this.root,
    required this.windows,
    required this.productCommit,
    required this.productVersion,
    required this.quality,
    this.id,
  });

  /// Reads [root]'s product.json, and checks that the files the server
  /// needs are there. [windows]: whether it is a Windows build (`node.exe`);
  /// by default, whether this machine is Windows.
  static Future<ExtHostRuntime> load(
    String root, {
    bool? windows,
    String? id,
  }) async {
    final runtime = p.normalize(p.absolute(root));
    final isWindows = windows ?? Platform.isWindows;
    final product = File(p.join(runtime, 'product.json'));
    final Object? json;
    try {
      json = jsonDecode(await product.readAsString());
    } on IOException catch (error) {
      throw ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.layout,
        'No product.json in $runtime',
        cause: error,
      );
    } on FormatException catch (error) {
      throw ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.layout,
        'Broken product.json in $runtime',
        cause: error,
      );
    }
    if (json is! Map<String, Object?> ||
        json['commit'] is! String ||
        json['version'] is! String) {
      throw ExtHostRuntimeException(
        ExtHostRuntimeErrorKind.layout,
        'product.json in $runtime has no commit or version',
      );
    }
    final result = ExtHostRuntime(
      root: runtime,
      windows: isWindows,
      productCommit: json['commit']! as String,
      productVersion: json['version']! as String,
      quality: json['quality'] as String?,
      id: id,
    );
    for (final path in [result.nodeExecutable, result.serverMain]) {
      if (!await File(path).exists()) {
        throw ExtHostRuntimeException(
          ExtHostRuntimeErrorKind.layout,
          'The extension runtime in $runtime has no ${p.relative(path, from: runtime)}',
        );
      }
    }
    return result;
  }

  final String root;

  /// A Windows build: `node.exe`.
  final bool windows;

  /// product.json's `commit`: what the server's handshake expects.
  final String productCommit;

  /// product.json's `version` (VSCodium's: `1.135.06055`).
  final String productVersion;

  /// product.json's `quality` (`stable`).
  final String? quality;

  /// The installed build (`1.135.06055-0123abcd`); null for a runtime
  /// given by `BAOCODE_EXTHOST_DIR`.
  final String? id;

  String get nodeExecutable => p.join(root, windows ? 'node.exe' : 'node');
  String get serverMain => p.join(root, 'out', 'server-main.js');
  String get productJson => p.join(root, 'product.json');

  /// The built-in extensions.
  String get builtinExtensions => p.join(root, 'extensions');

  @override
  String toString() => 'ExtHostRuntime($root, $productVersion, $productCommit)';
}
