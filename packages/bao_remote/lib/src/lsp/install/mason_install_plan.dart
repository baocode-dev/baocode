import '../lsp_server_definition.dart';
import 'mason_platform.dart';
import 'mason_purl.dart';
import 'mason_registry.dart';
import 'mason_template.dart';

/// How a package installs: the source types the IDE supports.
enum MasonSourceKind {
  /// GitHub release assets, downloaded and unpacked.
  github,

  /// Files downloaded from the URLs the package lists.
  generic,

  /// `npm install --prefix <dir>`.
  npm,

  /// A Python venv and `pip install`.
  pypi,

  /// `go install` with `GOBIN=<dir>`.
  golang,

  /// `cargo install --root <dir>`.
  cargo;

  /// The executable installing needs on PATH, if any.
  String? get runtime => switch (this) {
    github || generic => null,
    npm => 'npm',
    pypi => 'python3',
    golang => 'go',
    cargo => 'cargo',
  };
}

/// A file to fetch, and where it goes in the package directory (relative,
/// `/`-separated). Archives are unpacked where they land, as mason does.
class MasonDownload {
  const MasonDownload(this.url, this.path);

  final Uri url;
  final String path;

  @override
  String toString() => '$url -> $path';
}

/// How a linked executable runs: directly, or through a runtime.
enum MasonBinKind {
  /// A file in the package: made executable.
  executable,

  /// A file installed by the package manager (npm, pip, go, cargo).
  managed,

  /// A script or jar a wrapper runs with [MasonBin.runtime].
  wrapped,
}

/// One entry of the package's `bin`: the file to link, relative to the
/// package directory.
class MasonBin {
  const MasonBin(this.kind, this.path, {this.runtime, this.runtimeArgs});

  final MasonBinKind kind;
  final String path;

  /// For [MasonBinKind.wrapped]: the interpreter (`node`, `java`, …), or a
  /// path inside the package (a venv's python) when it starts with `./`.
  final String? runtime;
  final List<String>? runtimeArgs;

  @override
  String toString() =>
      runtime == null ? '$kind $path' : '$kind $runtime $runtimeArgs $path';
}

/// What installing [package] on a platform takes; see [MasonInstallPlan.of].
class MasonInstallPlan {
  const MasonInstallPlan({
    required this.package,
    required this.purl,
    required this.kind,
    required this.version,
    required this.bins,
    this.downloads = const [],
    this.extraPackages = const [],
  });

  /// Resolves [package] for [platform]: its source, the asset for the
  /// platform, and each `bin` entry with templates expanded. Throws
  /// [LspInstallException] when the IDE cannot install it here.
  factory MasonInstallPlan.of(MasonPackage package, MasonPlatform platform) {
    final MasonPurl purl;
    try {
      purl = package.purl;
    } on FormatException catch (error) {
      throw LspInstallException(
        '${package.name} has an invalid source',
        detail: error.message,
      );
    }
    final version = purl.version;
    if (version == null) {
      throw LspInstallException('${package.name} names no version');
    }
    final supported = package.source['supported_platforms'];
    if (supported is List && !supported.any(platform.matches)) {
      throw LspInstallException(
        '${package.name} is not available for $platform',
        detail: 'Supported: ${supported.join(', ')}',
      );
    }
    final source = package.source;
    final kind = switch (purl.type) {
      'github' when source['build'] != null => null,
      'github' => MasonSourceKind.github,
      'generic' when source['download'] != null => MasonSourceKind.generic,
      'npm' => MasonSourceKind.npm,
      'pypi' => MasonSourceKind.pypi,
      'golang' => MasonSourceKind.golang,
      'cargo' => MasonSourceKind.cargo,
      _ => null,
    };
    if (kind == null) {
      final how = source['build'] != null
          ? 'builds from source with a script'
          : 'is a ${purl.type} package';
      throw LspInstallException(
        '${package.name} cannot be installed from the IDE: it $how',
        detail: 'Install it yourself so it is on PATH (${purl.fullName}).',
      );
    }

    final context = <String, Object?>{'version': version};
    String expand(String template) {
      try {
        return expandMasonTemplate(template, context, platform);
      } on FormatException catch (error) {
        throw LspInstallException(
          '${package.name} uses a template the IDE cannot expand',
          detail: '${error.message}: $template',
        );
      }
    }

    Object? expandAll(Object? value) => switch (value) {
      final String text => expand(text),
      final List<Object?> list => [for (final item in list) expandAll(item)],
      final Map<Object?, Object?> map => {
        for (final MapEntry(:key, :value) in map.entries)
          '$key': expandAll(value),
      },
      _ => value,
    };

    Map<String, Object?> pick(String key) {
      final selected = platform.select(source[key]);
      if (selected == null) {
        throw LspInstallException(
          '${package.name} has no download for $platform',
        );
      }
      return expandAll(selected) as Map<String, Object?>;
    }

    final downloads = <MasonDownload>[];
    switch (kind) {
      case MasonSourceKind.github:
        final asset = pick('asset');
        context['source'] = {'asset': asset};
        final files = switch (asset['file']) {
          final String file => [file],
          final List<Object?> files => files.whereType<String>().toList(),
          _ => throw LspInstallException('${package.name} names no asset'),
        };
        for (final file in files) {
          final colon = file.indexOf(':');
          final name = colon < 0 ? file : file.substring(0, colon);
          final destination = colon < 0 ? null : file.substring(colon + 1);
          downloads.add(
            MasonDownload(
              Uri.https(
                'github.com',
                '/${purl.fullName}/releases/download/$version/$name',
              ),
              _destination(name, destination),
            ),
          );
        }
      case MasonSourceKind.generic:
        final download = pick('download');
        context['source'] = {'download': download};
        final files = download['files'];
        if (files is! Map || files.isEmpty) {
          throw LspInstallException('${package.name} lists no files');
        }
        for (final MapEntry(:key, :value) in files.entries) {
          final url = Uri.tryParse('$value');
          if (url == null || !(url.isScheme('https') || url.isScheme('http'))) {
            throw LspInstallException('${package.name}: bad URL $value');
          }
          downloads.add(MasonDownload(url, _destination('$key', null)));
        }
      case MasonSourceKind.npm ||
          MasonSourceKind.pypi ||
          MasonSourceKind.golang ||
          MasonSourceKind.cargo:
        context['source'] = source;
    }

    final bins = <String, MasonBin>{};
    for (final MapEntry(:key, :value) in package.bin.entries) {
      final expanded = expand(value);
      if (expanded.isEmpty) {
        throw LspInstallException(
          '${package.name}: no executable "$key" for $platform',
        );
      }
      bins[key] = _bin(package.name, expanded, platform);
    }
    return MasonInstallPlan(
      package: package,
      purl: purl,
      kind: kind,
      version: version,
      bins: bins,
      downloads: downloads,
      extraPackages: [
        ...?(source['extra_packages'] as List?)?.whereType<String>(),
      ],
    );
  }

  final MasonPackage package;
  final MasonPurl purl;
  final MasonSourceKind kind;
  final String version;

  /// Executable name → the file it links to.
  final Map<String, MasonBin> bins;
  final List<MasonDownload> downloads;

  /// Further packages the package manager installs alongside
  /// (`typescript@5.9.3`).
  final List<String> extraPackages;

  /// Runtimes needed on PATH: to install, then to run the wrapped bins.
  List<String> get runtimes => {
    ?kind.runtime,
    for (final bin in bins.values)
      if (bin.runtime case final runtime? when !runtime.startsWith('./'))
        runtime,
  }.toList();

  /// Where a downloaded [name] goes: mason's `file:dest` puts it in `dest`
  /// when that ends with `/`, else renames it to `dest`.
  static String _destination(String name, String? destination) {
    final base = name.split('/').last;
    final path = switch (destination) {
      null || '' => base,
      final dir when dir.endsWith('/') => '$dir$base',
      final file => file,
    };
    _checkRelative(path);
    return path;
  }

  static void _checkRelative(String path) {
    final segments = path.split(RegExp(r'[/\\]'));
    if (path.startsWith('/') || path.contains(':') || segments.contains('..')) {
      throw LspInstallException('Refusing to write outside the package: $path');
    }
  }

  static MasonBin _bin(String package, String value, MasonPlatform platform) {
    final colon = value.indexOf(':');
    final prefix = colon > 0 ? value.substring(0, colon) : null;
    final target = colon > 0 ? value.substring(colon + 1) : value;
    final exe = platform.isWindows ? '.exe' : '';
    MasonBin wrapped(String runtime, [List<String> args = const []]) {
      _checkRelative(target);
      return MasonBin(
        MasonBinKind.wrapped,
        target,
        runtime: runtime,
        runtimeArgs: args,
      );
    }

    final bin = switch (prefix) {
      null || 'exec' => MasonBin(MasonBinKind.executable, target),
      'npm' => MasonBin(
        MasonBinKind.managed,
        'node_modules/.bin/$target${platform.isWindows ? '.cmd' : ''}',
      ),
      'pypi' => MasonBin(
        MasonBinKind.managed,
        platform.isWindows ? 'venv/Scripts/$target.exe' : 'venv/bin/$target',
      ),
      'golang' => MasonBin(MasonBinKind.managed, '$target$exe'),
      'cargo' => MasonBin(MasonBinKind.managed, 'bin/$target$exe'),
      'node' => wrapped('node'),
      'python' => wrapped(platform.isWindows ? 'python' : 'python3'),
      'dotnet' => wrapped('dotnet'),
      'java-jar' => wrapped('java', ['-jar']),
      'ruby' => wrapped('ruby'),
      'php' => wrapped('php'),
      'pyvenv' => MasonBin(
        MasonBinKind.wrapped,
        '',
        runtime: platform.isWindows
            ? './venv/Scripts/python.exe'
            : './venv/bin/python',
        runtimeArgs: ['-m', target],
      ),
      _ => throw LspInstallException(
        '$package links "$value", which the IDE cannot run',
      ),
    };
    if (bin.path.isNotEmpty) _checkRelative(bin.path);
    return bin;
  }
}
