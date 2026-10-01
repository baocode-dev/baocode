import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:hooks/hooks.dart';

/// Points the native build at MSVC without asking native_toolchain_c to run
/// vswhere.
///
/// That package requests UTF-8 JSON (`vswhere -utf8`) and then decodes it
/// with the Windows ANSI code page. When the page is not UTF-8, a localized
/// Visual Studio description becomes a control character and JSON parsing
/// throws before cl.exe is found. The compiler path on the hook config is
/// used instead of that search.
Future<void> configureWindowsCompiler(HookConfig config) async {
  final installation = await _visualStudio();
  final tools = _newestMsvc(installation);
  final codeAssets = _codeAssets(config);
  final target = _targetDirectory(codeAssets['target_architecture']);
  final host = switch (Abi.current()) {
    Abi.windowsArm64 => 'arm64',
    Abi.windowsIA32 => 'x86',
    _ => 'x64',
  };
  final bin = Directory('${tools.path}\\bin\\Host$host\\$target');
  String tool(String name) {
    final file = File('${bin.path}\\$name');
    if (!file.existsSync()) {
      throw Exception('MSVC $name was not found at ${file.path}.');
    }
    return file.path;
  }

  final script = switch (target) {
    'x86' => 'vcvars32.bat',
    'arm64' => 'vcvarsamd64_arm64.bat',
    _ => 'vcvars64.bat',
  };
  final vcvars = File('${installation.path}\\VC\\Auxiliary\\Build\\$script');
  if (!vcvars.existsSync()) {
    throw Exception(
      'The MSVC environment script was not found at ${vcvars.path}.',
    );
  }
  codeAssets['c_compiler'] = {
    'ar': tool('lib.exe'),
    'cc': tool('cl.exe'),
    'ld': tool('link.exe'),
    'windows': {
      'developer_command_prompt': {
        'script': vcvars.path,
        'arguments': <String>[],
      },
    },
  };
}

Map<dynamic, dynamic> _codeAssets(HookConfig config) {
  final extensions = config.json['extensions'];
  if (extensions is! Map) {
    throw Exception('The hook config has no extensions.');
  }
  final codeAssets = extensions['code_assets'];
  if (codeAssets is! Map) {
    throw Exception('The hook config has no code assets.');
  }
  return codeAssets;
}

String _targetDirectory(Object? architecture) => switch (architecture) {
  'x64' => 'x64',
  'arm64' => 'arm64',
  'ia32' => 'x86',
  _ => throw Exception('No MSVC tools for architecture $architecture.'),
};

/// The newest `VC\Tools\MSVC\<version>` under [installation].
Directory _newestMsvc(Directory installation) {
  final root = Directory('${installation.path}\\VC\\Tools\\MSVC');
  if (!root.existsSync()) {
    throw Exception('MSVC was not found under ${root.path}.');
  }
  final versions = root.listSync().whereType<Directory>().toList()
    ..sort(_compareVersions);
  if (versions.isEmpty) {
    throw Exception('MSVC was not found under ${root.path}.');
  }
  return versions.last;
}

int _compareVersions(Directory a, Directory b) {
  final left = _version(a);
  final right = _version(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

List<int> _version(Directory directory) => directory.uri.pathSegments
    .lastWhere((segment) => segment.isNotEmpty)
    .split('.')
    .map((part) => int.tryParse(part) ?? 0)
    .toList();

/// Visual Studio, or its Build Tools, that has the x64 C++ toolset.
///
/// vswhere is asked for UTF-8 and decoded as UTF-8. native_toolchain_c
/// decodes that same output as the ANSI code page, which is what fails.
Future<Directory> _visualStudio() async {
  final vswhere = _vswhere();
  final process = await Process.start(vswhere, const [
    '-format',
    'json',
    '-utf8',
    '-latest',
    '-products',
    '*',
    '-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
  ]);
  final stdoutBytes = BytesBuilder(copy: false);
  final stderrBytes = BytesBuilder(copy: false);
  await Future.wait([
    process.stdout.forEach(stdoutBytes.add),
    process.stderr.forEach(stderrBytes.add),
  ]);
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw Exception(
      'vswhere exited with code $exitCode.\n'
      '${utf8.decode(stderrBytes.takeBytes(), allowMalformed: true)}',
    );
  }
  final installations =
      json.decode(utf8.decode(stdoutBytes.takeBytes())) as List;
  if (installations.isEmpty) {
    throw Exception(
      'Visual Studio with the MSVC toolset was not found.\n'
      'Install the "Desktop development with C++" workload.',
    );
  }
  final path = (installations.first as Map)['installationPath'] as String?;
  if (path == null) {
    throw Exception('vswhere did not report an installation path.');
  }
  return Directory(path);
}

String _vswhere() {
  const candidates = [
    r'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe',
    r'C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  throw Exception(
    'vswhere.exe was not found next to the Visual Studio Installer.',
  );
}
