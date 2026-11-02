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
/// Options it does not know are left out, as are the values of those VS
/// Code's take. Those that ask VS Code about itself or its extensions
/// (`--version`, `--list-extensions`, `--install-extension <id>`…), which
/// tools run in the background to find out what editor there is, open
/// nothing: see [opensNothing].
class CodeArgs {
  const CodeArgs({
    this.paths = const [],
    this.newWindow = false,
    this.reuseWindow = false,
    this.goto = false,
    this.opensNothing = false,
  });

  /// The paths, absolute, each with the line and column `-g` gave it.
  final List<CodeTarget> paths;
  final bool newWindow;
  final bool reuseWindow;

  /// Whether the paths were given as `file:line[:col]`.
  final bool goto;

  /// Whether it asked something of VS Code's CLI that is no window's to
  /// show ([queryOptions]): an empty window, or one of a file named after
  /// an extension, would open out of nowhere.
  final bool opensNothing;

  /// VS Code's options that do their work in the terminal, not a window.
  static const queryOptions = {
    '-h',
    '--help',
    '-v',
    '--version',
    '-s',
    '--status',
    '--list-extensions',
    '--show-versions',
    '--install-extension',
    '--uninstall-extension',
    '--update-extensions',
    '--locate-extension',
    '--locate-shell-integration-path',
    '--telemetry',
    '--add-mcp',
  };

  /// VS Code's options that take a value (unless given as `--option=value`),
  /// which is not a path to open.
  static const _valueOptions = {
    '--locale',
    '--user-data-dir',
    '--profile',
    '--extensions-dir',
    '--category',
    '--install-extension',
    '--uninstall-extension',
    '--locate-extension',
    '--enable-proposed-api',
    '--disable-extension',
    '--log',
    '--sync',
    '--remove',
    '--locate-shell-integration-path',
    '--add-mcp',
    '--crash-reporter-directory',
  };

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

  /// The marker of Open with BaoCode (Explorer's context menu, which the
  /// Windows installer or the settings add; Finder's, the macOS app's
  /// Finder extension, see AppDelegate.swift), the paths next: each in a
  /// new agent, in the chat's window (see AppWindows.openAgent).
  static const agentRequestMarker = '\u0000agent';

  /// The flag that menu starts the app with, the path next; the runner
  /// hands it over as a request ([agentRequestMarker]).
  static const windowsAgentFlag = '--baocode-agent';

  /// The marker of a `baocode://` link, the link next: a site's one-click
  /// import of an upstream (`baocode://provider/import?…`, see
  /// UpstreamImport), asked about in the main window, which comes in front
  /// for it; the channel build's setup (`baocode://activate?…`); a file to
  /// open in the IDE (`baocode://file/…`, see [FileLink]).
  static const importRequestMarker = '\u0000import';

  /// The flag Windows starts the app with for a `baocode://` link (the URL
  /// scheme the installer registers), the link next; the runner hands it
  /// over as a request ([importRequestMarker]).
  static const windowsLinkFlag = '--baocode-link';

  /// Whether [argument] starts a request ([requestMarker],
  /// [agentRequestMarker], [importRequestMarker]) among what the system
  /// hands over.
  static bool isMarker(String argument) => argument.startsWith('\u0000');

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
    var options = true, value = false;
    final raw = <String>[];
    for (final arg in args) {
      if (value) {
        value = false;
        continue;
      }
      if (options && arg == '--') {
        options = false;
        continue;
      }
      if (options && arg.startsWith('-') && arg.length > 1) {
        final name = arg.split('=').first;
        if (queryOptions.contains(name)) {
          return const CodeArgs(opensNothing: true);
        }
        value = name == arg && _valueOptions.contains(name);
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
    final target = (goto ? _split(arg) : null) ?? CodeTarget(arg);
    final context = _contextFor(cwd);
    final path = target.path;
    final absolute = context.isAbsolute(path) ? path : context.join(cwd, path);
    return CodeTarget(
      context.normalize(absolute),
      line: target.line,
      column: target.column,
    );
  }

  /// This path read as `file:line[:col]`, as tools that start an editor
  /// give it without `-g` (launch-editor's, for one it does not know; see
  /// AppWindows.handleCode): null if it has no line at its end, or was
  /// given one already.
  CodeTarget? get atLine => line == null ? _split(path) : null;

  static CodeTarget? _split(String arg) {
    final match = RegExp(r'^(.*?)(?::(\d+))(?::(\d+))?$').firstMatch(arg);
    // A Windows drive's colon (C:\…) is no line.
    if (match == null || match.group(1)!.isEmpty) return null;
    return CodeTarget(
      match.group(1)!,
      line: int.tryParse(match.group(2)!),
      column: int.tryParse(match.group(3) ?? ''),
    );
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

/// A link to a file, as VS Code's `vscode://file/…`, for pages, reports
/// and tools outside the app to open one in the IDE (#383):
///
///   `baocode://file/{absolute path}[:line[:col]][?windowId=_blank]`
///
/// `baocode://file/Users/me/app/src/main.ts:12:5` on macOS,
/// `baocode://file/C:/Users/me/app/src/main.ts:12` on Windows (a UNC path
/// after two slashes: `baocode://file//server/share/a.ts`). Percent-encoded
/// as URLs are. The IDE opens it as `code -g` does (see
/// AppWindows.handleCode): a file in the window whose folder has it, else
/// the last used, at the line and column; a folder in its window;
/// `windowId=_blank`, in a new window.
///
/// It comes as other `baocode://` links do ([CodeArgs.importRequestMarker]),
/// and goes to the IDE, never the chat.
abstract final class FileLink {
  /// [link] as the `code` command would ask it; null if it is not a file
  /// link, or names no absolute path.
  static CodeArgs? parse(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || uri.scheme != 'baocode' || uri.host != 'file') {
      return null;
    }
    final String path;
    try {
      path = _local(Uri.decodeComponent(uri.path));
    } on FormatException {
      // Not UTF-8 once decoded.
      return null;
    } on ArgumentError {
      return null;
    }
    if (path.isEmpty) return null;
    return CodeArgs(
      // Absolute, so read from itself: only how it is spelled is taken.
      paths: [CodeTarget.parse(path, path, goto: true)],
      newWindow: uri.queryParameters['windowId'] == '_blank',
      goto: true,
    );
  }

  /// Whether [link] is one.
  static bool isLink(String link) => parse(link) != null;

  /// The URL's path as this machine's: `/C:/a` is `C:/a` (Dart's URLs
  /// turn a Windows path's backslashes to slashes), `//server/share/…` a
  /// UNC path; any other `/…` a POSIX one. Empty for none.
  static String _local(String path) {
    if (RegExp(r'^/[A-Za-z]:([\\/]|$)').hasMatch(path)) {
      final drive = path.substring(1);
      return drive.length == 2 ? '$drive\\' : drive;
    }
    if (path.startsWith('//') && path.length > 2) {
      // As a UNC path only with backslashes.
      return p.windows.normalize(path.replaceAll('/', r'\'));
    }
    return path.length > 1 ? path : '';
  }
}

/// What the app was started for, by its command line (the Windows app's,
/// which Flutter is given as `main`'s arguments; the macOS app's comes as
/// paths handed over as it starts: see `OpenRequests.launchRequest`): it
/// opens that alone, nothing of the last run.
enum LaunchRequest {
  /// Started as itself: the windows of the last run.
  none,

  /// Open with BaoCode ([CodeArgs.windowsAgentFlag]): the chat's window.
  agent,

  /// Paths to open in the IDE (Open with Fast Ide, the `code` command,
  /// Explorer's Open with): their windows.
  ide;

  static LaunchRequest of(List<String> arguments) {
    final first = arguments.firstOrNull;
    if (first == CodeArgs.windowsAgentFlag) return agent;
    if (first == CodeArgs.windowsRequestFlag) return ide;
    // A file link opens in the IDE alone; any other link asks in the main
    // window, as the app shows at any launch.
    if (first == CodeArgs.windowsLinkFlag) {
      final link = arguments.elementAtOrNull(1);
      return link != null && FileLink.isLink(link) ? ide : none;
    }
    final paths = arguments.where((a) => a.isNotEmpty && !a.startsWith('-'));
    return paths.isEmpty ? none : ide;
  }
}
