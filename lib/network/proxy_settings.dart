/// settings.json's `http.proxyMode`: where the proxy BaoCode and the
/// Claude Code it starts go through comes from.
enum ProxyMode {
  /// The system's (System Settings → Network, Windows' proxy settings):
  /// what Clash and the like set as the system proxy. The environment's
  /// (`HTTPS_PROXY` in the shell's rc file) when the system has none.
  system('system'),

  /// The one given in `http.proxy`.
  manual('manual'),

  /// None: straight to the internet, whatever the system or the
  /// environment say.
  off('off');

  const ProxyMode(this.value);

  /// As settings.json writes it.
  final String value;

  static const settingKey = 'http.proxyMode';

  /// The proxy of [manual], as VS Code's `http.proxy`.
  static const urlKey = 'http.proxy';

  static const defaultMode = ProxyMode.system;

  /// [setting] as a mode: the default where it is unset or not one.
  static ProxyMode parse(Object? setting) => switch (setting) {
    final String value => ProxyMode.values.firstWhere(
      (mode) => mode.value == value.trim(),
      orElse: () => defaultMode,
    ),
    _ => defaultMode,
  };
}

/// An HTTP proxy: where it listens, and who to tell it the user is.
class ProxyServer {
  const ProxyServer(this.host, this.port, {this.username, this.password});

  final String host;
  final int port;
  final String? username;
  final String? password;

  /// [text] as a proxy: `host:port` or `http://[user:pass@]host[:port]`;
  /// null when it is not one. Only HTTP: neither Claude Code nor the app
  /// speaks SOCKS to a proxy (Clash's mixed port takes HTTP as well).
  static ProxyServer? parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final Uri uri;
    try {
      uri = Uri.parse(withScheme);
    } on FormatException {
      return null;
    }
    if (uri.scheme != 'http' || uri.host.isEmpty) return null;
    if (uri.path.isNotEmpty && uri.path != '/') return null;
    String? username;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final colon = uri.userInfo.indexOf(':');
      username = Uri.decodeComponent(
        colon < 0 ? uri.userInfo : uri.userInfo.substring(0, colon),
      );
      password = colon < 0
          ? null
          : Uri.decodeComponent(uri.userInfo.substring(colon + 1));
    }
    return ProxyServer(
      uri.host,
      uri.hasPort ? uri.port : 80,
      username: username,
      password: password,
    );
  }

  /// The host as a URL has it: an IPv6 address in brackets.
  String get _host => host.contains(':') ? '[$host]' : host;

  String get _userInfo => switch (username) {
    final user? => switch (password) {
      final password? =>
        '${Uri.encodeComponent(user)}:${Uri.encodeComponent(password)}@',
      null => '${Uri.encodeComponent(user)}@',
    },
    null => '',
  };

  /// As `HTTPS_PROXY` gives it: `http://[user:pass@]host:port`.
  String get url => 'http://$_userInfo$_host:$port';

  /// As shown: without the password.
  String get display => switch (username) {
    final user? => 'http://${Uri.encodeComponent(user)}@$_host:$port',
    null => 'http://$_host:$port',
  };

  /// As `HttpClient.findProxy` answers for it.
  String get directive => switch (username) {
    final user? => 'PROXY $user:${password ?? ''}@$_host:$port',
    null => 'PROXY $_host:$port',
  };

  @override
  bool operator ==(Object other) =>
      other is ProxyServer &&
      other.host == host &&
      other.port == port &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(host, port, username, password);

  @override
  String toString() => display;
}

/// Where a proxy setting came from, as the settings page says.
enum ProxySource {
  /// The system's proxy settings.
  system,

  /// `HTTPS_PROXY` and the like, as the login shell has them.
  environment,

  /// `http.proxy`.
  manual,

  /// None found: straight to the internet.
  none,

  /// `http.proxyMode` is `off`: straight to the internet, and the
  /// environment's proxy cleared for Claude Code too.
  off,
}

/// What the requests go through: the proxy for `http:` and for `https:`
/// URLs, and the hosts that go around it.
class ProxyRoute {
  const ProxyRoute({
    required this.source,
    this.http,
    this.https,
    this.bypass = const [],
    this.bypassSimpleHostnames = false,
    this.autoConfig = false,
  });

  /// Straight to the internet: [ProxySource.none] or [ProxySource.off].
  const ProxyRoute.direct([this.source = ProxySource.none, this.autoConfig = false])
    : http = null,
      https = null,
      bypass = const [],
      bypassSimpleHostnames = false;

  final ProxySource source;
  final ProxyServer? http;
  final ProxyServer? https;

  /// Hosts that do not go through it, as `NO_PROXY` lists them
  /// (`example.com`, `.example.com`, `*.example.com`, `10.*`).
  final List<String> bypass;

  /// Whether a name without a dot (`intranet`) goes around it, as
  /// Windows' `<local>` and macOS's Exclude simple hostnames say.
  final bool bypassSimpleHostnames;

  /// Whether the system sets its proxy by a PAC file, which is not
  /// followed: the settings page says so.
  final bool autoConfig;

  /// This machine's: never through a proxy, as the local model proxy is
  /// on it, and a model served here (Ollama, LM Studio) too.
  static const loopback = ['localhost', '127.0.0.1', '::1'];

  bool get direct => http == null && https == null;

  /// The proxy of [url]; null for one that goes straight to it.
  ProxyServer? serverFor(Uri url) {
    final server = switch (url.scheme) {
      'https' || 'wss' => https,
      'http' || 'ws' => http,
      _ => null,
    };
    if (server == null || bypasses(url.host)) return null;
    return server;
  }

  /// `HttpClient.findProxy`'s answer for [url].
  String findProxy(Uri url) => serverFor(url)?.directive ?? 'DIRECT';

  /// Whether [host] goes around the proxy.
  bool bypasses(String host) {
    var name = host.toLowerCase();
    if (name.startsWith('[') && name.endsWith(']')) {
      name = name.substring(1, name.length - 1);
    }
    if (loopback.contains(name) || name.startsWith('127.')) return true;
    if (bypassSimpleHostnames && !name.contains('.') && !name.contains(':')) {
      return true;
    }
    return bypass.any((entry) => _matches(name, entry));
  }

  static bool _matches(String host, String entry) {
    var pattern = entry.trim().toLowerCase();
    if (pattern.isEmpty) return false;
    if (pattern == '*') return true;
    if (pattern.startsWith('[') && pattern.contains(']')) {
      pattern = pattern.substring(1, pattern.indexOf(']'));
    } else if (':'.allMatches(pattern).length == 1) {
      // `host:port`: any port.
      pattern = pattern.substring(0, pattern.indexOf(':'));
    }
    if (pattern.startsWith('*.')) pattern = pattern.substring(1);
    if (pattern.contains('*')) {
      final glob = RegExp(
        '^${pattern.split('*').map(RegExp.escape).join('.*')}\$',
      );
      return glob.hasMatch(host);
    }
    if (pattern.startsWith('.')) {
      return host.endsWith(pattern) || host == pattern.substring(1);
    }
    return host == pattern || host.endsWith('.$pattern');
  }

  /// `NO_PROXY` for it: the entries other programs read, this machine's
  /// first.
  String get noProxy => {
    ...loopback,
    for (final entry in bypass)
      // `10.*` and the like only Windows reads.
      if (_portable(entry)) entry.trim(),
  }.join(',');

  static bool _portable(String entry) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty || trimmed.contains('/')) return false;
    final rest = trimmed.startsWith('*.') ? trimmed.substring(2) : trimmed;
    return trimmed == '*' || !rest.contains('*');
  }

  /// What a child process (Claude Code) is given for it, over the
  /// environment it would inherit: both spellings of each variable, as
  /// some programs read the one and some the other. Nothing for
  /// [ProxySource.none], which leaves the inherited as it is; empty ones
  /// for [ProxySource.off], which clear it.
  Map<String, String> get environment {
    if (source == ProxySource.off) {
      return {for (final name in variables) name: ''};
    }
    if (direct) return const {};
    final noProxy = this.noProxy;
    return {
      'HTTP_PROXY': http?.url ?? '',
      'http_proxy': http?.url ?? '',
      'HTTPS_PROXY': https?.url ?? '',
      'https_proxy': https?.url ?? '',
      'NO_PROXY': noProxy,
      'no_proxy': noProxy,
    };
  }

  /// The variables a proxy is set by.
  static const variables = [
    'HTTP_PROXY',
    'http_proxy',
    'HTTPS_PROXY',
    'https_proxy',
    'ALL_PROXY',
    'all_proxy',
    'NO_PROXY',
    'no_proxy',
  ];

  /// The proxy [environment] names (`HTTPS_PROXY`, `HTTP_PROXY`, else an
  /// HTTP `ALL_PROXY`; `NO_PROXY`), the lowercase first as curl reads
  /// them; direct when it names none.
  static ProxyRoute fromEnvironment(Map<String, String> environment) {
    String? value(String name) =>
        switch (environment[name.toLowerCase()] ?? environment[name]) {
          final value? when value.trim().isNotEmpty => value.trim(),
          _ => null,
        };
    ProxyServer? server(String name) => switch (value(name)) {
      final text? => ProxyServer.parse(text),
      null => null,
    };
    final all = server('ALL_PROXY');
    final http = server('HTTP_PROXY') ?? all;
    final https = server('HTTPS_PROXY') ?? all;
    if (http == null && https == null) return const ProxyRoute.direct();
    return ProxyRoute(
      source: ProxySource.environment,
      http: http,
      https: https,
      bypass: [...?value('NO_PROXY')?.split(',')],
    );
  }

  /// [server] for both kinds of URL, as `http.proxy` gives it.
  static ProxyRoute manual(ProxyServer server, {List<String> bypass = const []}) =>
      ProxyRoute(
        source: ProxySource.manual,
        http: server,
        https: server,
        bypass: bypass,
      );

  @override
  bool operator ==(Object other) =>
      other is ProxyRoute &&
      other.source == source &&
      other.http == http &&
      other.https == https &&
      _sameList(other.bypass, bypass) &&
      other.bypassSimpleHostnames == bypassSimpleHostnames &&
      other.autoConfig == autoConfig;

  @override
  int get hashCode => Object.hash(
    source,
    http,
    https,
    Object.hashAll(bypass),
    bypassSimpleHostnames,
    autoConfig,
  );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'ProxyRoute($source, http: $http, https: $https, bypass: $bypass)';
}

/// The system proxy as `scutil --proxy` prints it (macOS): the HTTP and
/// HTTPS proxies where enabled, and the exceptions.
ProxyRoute parseScutilProxy(String output) {
  final values = <String, String>{};
  final exceptions = <String>[];
  var inExceptions = false;
  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (inExceptions) {
      if (line.startsWith('}')) {
        inExceptions = false;
      } else if (_arrayItem.firstMatch(line) case final match?) {
        exceptions.add(match.group(1)!.trim());
      }
      continue;
    }
    if (line.startsWith('ExceptionsList') && line.endsWith('{')) {
      inExceptions = true;
      continue;
    }
    final colon = line.indexOf(' : ');
    if (colon > 0) {
      values[line.substring(0, colon).trim()] = line.substring(colon + 3).trim();
    }
  }
  ProxyServer? server(String kind) {
    if (values['${kind}Enable'] != '1') return null;
    final host = values['${kind}Proxy'];
    final port = int.tryParse(values['${kind}Port'] ?? '');
    if (host == null || host.isEmpty || port == null) return null;
    return ProxyServer(host, port);
  }

  final http = server('HTTP');
  final https = server('HTTPS');
  final autoConfig = values['ProxyAutoConfigEnable'] == '1';
  if (http == null && https == null) {
    return ProxyRoute.direct(ProxySource.none, autoConfig);
  }
  return ProxyRoute(
    source: ProxySource.system,
    http: http,
    https: https,
    bypass: exceptions,
    bypassSimpleHostnames: values['ExcludeSimpleHostnames'] == '1',
    autoConfig: autoConfig,
  );
}

final _arrayItem = RegExp(r'^\d+\s*:\s*(.+)$');

/// The system proxy as `reg query` prints Windows' Internet Settings
/// (`HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`):
/// `ProxyEnable`, `ProxyServer` (`host:port`, or `http=…;https=…` a
/// protocol each) and `ProxyOverride` (`;` between them, `<local>` for
/// names without a dot).
ProxyRoute parseWindowsInternetSettings(String output) {
  final values = <String, String>{};
  for (final line in output.split(RegExp(r'\r?\n'))) {
    final match = _regValue.firstMatch(line);
    if (match != null) values[match.group(1)!] = match.group(3)!.trim();
  }
  final autoConfig = (values['AutoConfigURL'] ?? '').isNotEmpty;
  final enabled = switch (values['ProxyEnable']) {
    final value? => (int.tryParse(value.replaceFirst('0x', ''), radix: 16) ?? 0) != 0,
    null => false,
  };
  final setting = values['ProxyServer'] ?? '';
  if (!enabled || setting.isEmpty) {
    return ProxyRoute.direct(ProxySource.none, autoConfig);
  }
  ProxyServer? http;
  ProxyServer? https;
  if (setting.contains('=')) {
    for (final part in setting.split(';')) {
      final equals = part.indexOf('=');
      if (equals < 0) continue;
      final kind = part.substring(0, equals).trim().toLowerCase();
      final server = ProxyServer.parse(part.substring(equals + 1));
      if (kind == 'http') http = server;
      if (kind == 'https') https = server;
    }
  } else {
    http = https = ProxyServer.parse(setting);
  }
  if (http == null && https == null) {
    return ProxyRoute.direct(ProxySource.none, autoConfig);
  }
  final overrides = (values['ProxyOverride'] ?? '')
      .split(';')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
  return ProxyRoute(
    source: ProxySource.system,
    http: http,
    https: https,
    bypass: [
      for (final entry in overrides)
        if (entry.toLowerCase() != '<local>') entry,
    ],
    bypassSimpleHostnames: overrides.any(
      (entry) => entry.toLowerCase() == '<local>',
    ),
    autoConfig: autoConfig,
  );
}

final _regValue = RegExp(r'^\s+(\S+)\s+(REG_\w+)\s+(.*)$');
