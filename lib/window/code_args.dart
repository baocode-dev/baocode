import 'package:path/path.dart' as p;

/// What the `code` command asks, as VS Code's CLI takes it: the paths to
/// open (relative ones from [cwd]) and how.
///
///   code [paths…]                 a folder: its window, or a new one; a
///                                 file: the window that has it, else the
///                                 last used, else a new one
///   code -n | --new-window        in a new window
///   code -r | --reuse-window      in the last used window
///   code -g | --goto file:line[:col]
///                                 the file, at the line and column
///   code                          the last used window, or a new one
///
/// Options it does not know are left out, as are their values.
class CodeArgs {
  const CodeArgs({
    this.paths = const [],
    this.newWindow = false,
    this.reuseWindow = false,
    this.goto = false,
  });

  /// The paths, absolute, each with the line and column `-g` gave it.
  final List<CodeTarget> paths;
  final bool newWindow;
  final bool reuseWindow;

  /// Whether the paths were given as `file:line[:col]`.
  final bool goto;

  /// The marker of a request the `code` command sends (see [isRequest]):
  /// the working directory comes next, then its arguments as typed.
  static const requestMarker = '\u0000code';

  /// The suffix of the file the macOS script writes a request to, which
  /// the system hands the app as one to open (see shell_command_io.dart):
  /// the working directory on the first line, the arguments on the rest.
  static const requestFileSuffix = '.baocode-cli';

  /// The flag the Windows script (code.cmd) starts the app with, the
  /// console's folder and the arguments next; the runner hands them over
  /// as a request ([requestMarker]; see open_requests.cpp).
  static const windowsRequestFlag = '--baocode-cli';

  /// Whether [paths], as the system hands them over, are a request of the
  /// `code` command rather than paths.
  static bool isRequest(List<String> paths) =>
      paths.isNotEmpty && paths.first == requestMarker;

  /// Reads a request ([requestMarker], the working directory, then the
  /// arguments).
  static CodeArgs fromRequest(List<String> request) {
    if (!isRequest(request) || request.length < 2) return const CodeArgs();
    return parse(request.sublist(2), cwd: request[1]);
  }

  /// Reads the request file the macOS script wrote ([requestFileSuffix]):
  /// its lines.
  static CodeArgs fromRequestFile(String contents) {
    final lines = contents.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    if (lines.isEmpty) return const CodeArgs();
    return parse(lines.sublist(1), cwd: lines.first);
  }

  /// Reads [args] as typed in [cwd].
  static CodeArgs parse(List<String> args, {required String cwd}) {
    var newWindow = false, reuseWindow = false, goto = false;
    var options = true;
    final raw = <String>[];
    for (final arg in args) {
      if (options && arg == '--') {
        options = false;
        continue;
      }
      if (options && arg.startsWith('-') && arg.length > 1) {
        switch (arg) {
          case '-n' || '--new-window':
            newWindow = true;
          case '-r' || '--reuse-window':
            reuseWindow = true;
          case '-g' || '--goto':
            goto = true;
        }
        continue;
      }
      if (arg.isNotEmpty) raw.add(arg);
    }
    return CodeArgs(
      paths: [for (final path in raw) CodeTarget.parse(path, cwd, goto: goto)],
      newWindow: newWindow,
      // `-n` wins, as VS Code's.
      reuseWindow: reuseWindow && !newWindow,
      goto: goto,
    );
  }
}

/// A path the `code` command gave, absolute, with where to go in it.
class CodeTarget {
  const CodeTarget(this.path, {this.line, this.column});

  final String path;

  /// From 1; null for none.
  final int? line;
  final int? column;

  /// [arg] from [cwd]; with [goto], `path:line[:col]`.
  static CodeTarget parse(String arg, String cwd, {bool goto = false}) {
    int? line, column;
    var path = arg;
    if (goto) {
      final match = RegExp(r'^(.*?)(?::(\d+))(?::(\d+))?$').firstMatch(arg);
      // A Windows drive's colon (C:\…) is no line.
      if (match != null && match.group(1)!.isNotEmpty) {
        path = match.group(1)!;
        line = int.tryParse(match.group(2)!);
        column = int.tryParse(match.group(3) ?? '');
      }
    }
    final context = _contextFor(cwd);
    final absolute = context.isAbsolute(path) ? path : context.join(cwd, path);
    return CodeTarget(context.normalize(absolute), line: line, column: column);
  }

  static p.Context _contextFor(String cwd) =>
      RegExp(r'^[A-Za-z]:[\\/]|^\\\\').hasMatch(cwd)
      ? p.windows
      : cwd.startsWith('/')
      ? p.posix
      : p.context;

  @override
  bool operator ==(Object other) =>
      other is CodeTarget &&
      other.path == path &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(path, line, column);

  @override
  String toString() => [path, ?line, ?column].join(':');
}
