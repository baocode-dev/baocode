/// A new terminal's shell and environment, as VS Code (`6a598d4a`) picks
/// them when no terminal profile is set: pure, with the platform and the
/// file system passed in.
library;

import 'package:path/path.dart' as p;

/// The system a terminal runs on.
enum TerminalOs { macOS, linux, windows }

/// A shell to start.
typedef TerminalShell = ({String executable, List<String> arguments});

/// What `TERM_PROGRAM` says in a terminal. Not `vscode`: programs (the
/// Claude Code CLI among them) change what they do on that.
const terminalProgram = 'monad';

/// The shell a new terminal runs: on macOS and Linux, `$SHELL`; on Windows,
/// the first PowerShell installed (see [windowsPowerShells]), else
/// `ComSpec`.
///
/// [exists] says whether a file is there, [list] the names in a folder
/// (none when it is missing).
TerminalShell defaultTerminalShell(
  TerminalOs os,
  Map<String, String> environment, {
  required bool Function(String path) exists,
  required List<String> Function(String directory) list,
}) {
  if (os == TerminalOs.windows) {
    for (final path in windowsPowerShells(environment, list: list)) {
      if (exists(path)) return (executable: path, arguments: const []);
    }
    final comspec = _lookUp(environment, 'ComSpec', os) ?? '';
    return (
      executable: comspec.isEmpty ? 'cmd.exe' : comspec,
      arguments: const [],
    );
  }
  // VS Code's getSystemShell reads the user's entry in /etc/passwd when
  // $SHELL is unset; the macOS default stands in for it here.
  var shell = environment['SHELL'] ?? '';
  if (shell.isEmpty) {
    shell = os == TerminalOs.macOS && exists('/bin/zsh')
        ? '/bin/zsh'
        : '/bin/sh';
  }
  // Some systems set it to /bin/false, which would end the terminal at once.
  if (shell == '/bin/false') shell = '/bin/bash';
  return (executable: shell, arguments: terminalShellArguments(os, shell));
}

/// The arguments [shell] starts with. On macOS a terminal runs a login
/// shell, as Terminal does: VS Code's default profiles give bash, zsh and
/// fish `-l`, and any other shell named like zsh or bash `--login`.
List<String> terminalShellArguments(TerminalOs os, String shell) {
  if (os != TerminalOs.macOS) return const [];
  final name = p.posix.basenameWithoutExtension(shell);
  if (const {'bash', 'zsh', 'fish'}.contains(name)) return const ['-l'];
  if (const {'tmux', 'pwsh'}.contains(name)) return const [];
  return RegExp('zsh|bash').hasMatch(name) ? const ['--login'] : const [];
}

/// Where PowerShell may be installed, most wanted first, as VS Code's
/// enumerateDefaultPowerShellInstallations looks: PowerShell 7 and later
/// (Program Files, then the other bitness, the Store, the .NET tool),
/// previews of it, Scoop's, and last Windows PowerShell. Whether each is
/// there is for the caller to check.
List<String> windowsPowerShells(
  Map<String, String> environment, {
  required List<String> Function(String directory) list,
}) {
  String? get(String name) {
    final value = _lookUp(environment, name, TerminalOs.windows);
    return value == null || value.isEmpty ? null : value;
  }

  final home = get('USERPROFILE') ?? '';
  final programFiles = get('ProgramFiles');
  // The other bitness: 32-bit programs, for a 64-bit app. An Arm app has
  // none.
  final otherProgramFiles =
      get('PROCESSOR_ARCHITECTURE')?.toUpperCase() == 'ARM64' &&
          get('PROCESSOR_ARCHITEW6432') == null
      ? null
      : get('ProgramFiles(x86)');
  final windowsApps = switch (get('LOCALAPPDATA')) {
    final local? => '$local\\Microsoft\\WindowsApps',
    null => null,
  };

  // The highest version under <Program Files>\PowerShell: `7`, or with
  // [preview] `7-preview`.
  String? installed(String? programFiles, {bool preview = false}) {
    if (programFiles == null) return null;
    final base = '$programFiles\\PowerShell';
    final pattern = preview ? RegExp(r'^(\d+)-preview$') : RegExp(r'^(\d+)$');
    String? best;
    var highest = -1;
    for (final name in list(base)) {
      final version = int.tryParse(pattern.firstMatch(name)?.group(1) ?? '');
      if (version == null || version <= highest) continue;
      highest = version;
      best = '$base\\$name\\pwsh.exe';
    }
    return best;
  }

  String? store({bool preview = false}) {
    if (windowsApps == null) return null;
    final pattern = preview
        ? RegExp(r'^Microsoft\.PowerShellPreview_')
        : RegExp(r'^Microsoft\.PowerShell_');
    for (final name in list(windowsApps)) {
      if (pattern.hasMatch(name)) return '$windowsApps\\$name\\pwsh.exe';
    }
    return null;
  }

  final windir = get('windir') ?? get('SystemRoot') ?? r'C:\Windows';
  return [
    ?installed(programFiles),
    ?installed(otherProgramFiles),
    ?store(),
    if (home.isNotEmpty) '$home\\.dotnet\\tools\\pwsh.exe',
    ?installed(programFiles, preview: true),
    ?store(preview: true),
    ?installed(otherProgramFiles, preview: true),
    if (home.isNotEmpty) '$home\\scoop\\apps\\pwsh\\current\\pwsh.exe',
    '$windir\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
  ];
}

/// The environment a terminal's shell starts with, as VS Code's
/// createTerminalEnvironment makes it: [base] (the login shell's
/// environment) without what belongs to the app that launched this one,
/// then `TERM` (not on Windows, where node-pty sets none), `TERM_PROGRAM`,
/// `LANG` from [locale] when [base] has none in UTF-8, and `COLORTERM`.
Map<String, String> terminalEnvironment(
  Map<String, String> base, {
  required TerminalOs os,
  String? locale,
  String? version,
}) {
  final environment = {...base}
    ..removeWhere((name, _) => _appVariables.any((app) => app.hasMatch(name)));
  void put(String name, String? value) {
    final key = os == TerminalOs.windows
        ? environment.keys.firstWhere(
            (key) => key.toUpperCase() == name.toUpperCase(),
            orElse: () => name,
          )
        : name;
    value == null ? environment.remove(key) : environment[key] = value;
  }

  if (os != TerminalOs.windows) put('TERM', 'xterm-256color');
  put('TERM_PROGRAM', terminalProgram);
  // One the app inherited belongs to another terminal.
  put('TERM_PROGRAM_VERSION', version);
  if (_needsLang(_lookUp(environment, 'LANG', os))) {
    put('LANG', terminalLang(locale));
  }
  put('COLORTERM', 'truecolor');
  return environment;
}

/// Variables of Electron, VS Code, Snap and GTK's pixbuf loader, which
/// VS Code's sanitizeProcessEnvironment keeps out of a terminal.
final _appVariables = [
  RegExp(r'^ELECTRON_.+$'),
  RegExp(
    r'^VSCODE_(?!(PORTABLE|SHELL_LOGIN|ENV_REPLACE|ENV_APPEND|ENV_PREPEND)).+$',
  ),
  RegExp(r'^SNAP(|_.*)$'),
  RegExp(r'^GDK_PIXBUF_.+$'),
];

/// Whether `LANG` is missing or names no UTF-8 (or EUC) encoding: VS Code's
/// `terminal.integrated.detectLocale` at its default, `auto`.
bool _needsLang(String? lang) =>
    lang == null ||
    lang.isEmpty ||
    !RegExp(r'\.UTF-8$|\.utf8$|\.euc.+').hasMatch(lang);

/// `LANG` for [locale] (`en`, `zh-CN`, `en_US`, `zh-Hans-CN`…), as VS
/// Code's getLangEnvVariable makes it: a language alone gets its main
/// region, and an unknown locale is `en_US.UTF-8`.
String terminalLang(String? locale) {
  // LANG names a language and a region: no script (`Hans`), encoding
  // (`.UTF-8`) or modifier (`@euro`).
  final parts = (locale ?? '')
      .split(RegExp('[.@]'))
      .first
      .split(RegExp('[-_]'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.first == 'C' || parts.first == 'POSIX') {
    return 'en_US.UTF-8';
  }
  final language = parts.first.toLowerCase();
  final region = parts
      .skip(1)
      .where((part) => RegExp(r'^([A-Za-z]{2}|\d{3})$').hasMatch(part))
      .lastOrNull;
  if (region != null) return '${language}_${region.toUpperCase()}.UTF-8';
  // Traditional Chinese without a region is Taiwan's.
  final variant = language == 'zh' && parts.skip(1).contains('Hant')
      ? 'TW'
      : _languageRegions[language];
  return variant == null ? '$language.UTF-8' : '${language}_$variant.UTF-8';
}

/// The region VS Code picks for a language given alone.
const _languageRegions = {
  'af': 'ZA',
  'am': 'ET',
  'be': 'BY',
  'bg': 'BG',
  'ca': 'ES',
  'cs': 'CZ',
  'da': 'DK',
  'de': 'DE',
  'el': 'GR',
  'en': 'US',
  'es': 'ES',
  'et': 'EE',
  'eu': 'ES',
  'fi': 'FI',
  'fr': 'FR',
  'he': 'IL',
  'hr': 'HR',
  'hu': 'HU',
  'hy': 'AM',
  'is': 'IS',
  'it': 'IT',
  'ja': 'JP',
  'kk': 'KZ',
  'ko': 'KR',
  'lt': 'LT',
  'nl': 'NL',
  'no': 'NO',
  'pl': 'PL',
  'pt': 'BR',
  'ro': 'RO',
  'ru': 'RU',
  'sk': 'SK',
  'sl': 'SI',
  'sr': 'YU',
  'sv': 'SE',
  'tr': 'TR',
  'uk': 'UA',
  'zh': 'CN',
};

/// [name] in [environment]; on Windows, in any case.
String? _lookUp(Map<String, String> environment, String name, TerminalOs os) {
  if (environment[name] case final value?) return value;
  if (os != TerminalOs.windows) return null;
  final upper = name.toUpperCase();
  for (final MapEntry(:key, :value) in environment.entries) {
    if (key.toUpperCase() == upper) return value;
  }
  return null;
}
