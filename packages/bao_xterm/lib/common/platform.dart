// Copyright (c) 2016 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/Platform.ts (c58ea36).
//
// Upstream reads `navigator.userAgent` and `navigator.platform` once, or uses
// `'node'` for both under Node.js. Pure Dart can read neither, so the values
// start as Node's and the embedder reports the host with [initPlatform] before
// creating a terminal. The flags are getters for that reason.

String _userAgent = 'node';
String _platform = 'node';
bool _isNode = true;

bool _isFirefox = false;
bool _isChrome = false;
bool _isLegacyEdge = false;
bool _isSafari = false;
bool _isMac = false;
bool _isWindows = false;
bool _isLinux = false;
bool _isChromeOS = false;

/// Sets the host's `navigator.userAgent` and `navigator.platform` (for
/// example `'MacIntel'`, `'Win32'`, `'Linux x86_64'`), leaving Node mode.
void initPlatform({required String userAgent, required String platform}) {
  _isNode = false;
  _userAgent = userAgent;
  _platform = platform;
  _update();
}

void _update() {
  _isFirefox = _userAgent.contains('Firefox');
  _isChrome = _userAgent.contains('Chrome');
  _isLegacyEdge = _userAgent.contains('Edge');
  _isSafari = RegExp(
    r'^((?!chrome|android).)*safari',
    caseSensitive: false,
  ).hasMatch(_userAgent);
  _isMac = const [
    'Macintosh',
    'MacIntel',
    'MacPPC',
    'Mac68K',
  ].contains(_platform);
  _isWindows = const ['Windows', 'Win16', 'Win32', 'WinCE'].contains(_platform);
  _isLinux = _platform.contains('Linux');
  _isChromeOS = RegExp(r'\bCrOS\b').hasMatch(_userAgent);
}

bool get isNode => _isNode;

bool get isFirefox => _isFirefox;
bool get isChrome => _isChrome;
bool get isLegacyEdge => _isLegacyEdge;
bool get isSafari => _isSafari;

/// Upstream's `IZoomWindow` parameter; always 1.
double getZoomFactor(Object? targetWindow) {
  return 1;
}

int getSafariVersion() {
  if (!isSafari) {
    return 0;
  }
  final majorVersion = RegExp(r'Version\/(\d+)').firstMatch(_userAgent);
  if (majorVersion == null) {
    return 0;
  }
  return int.parse(majorVersion.group(1)!);
}

// Find the user's platform. We use this to interpret the meta key and ISO
// third level shifts. http://stackoverflow.com/q/19877924/577598
bool get isMac => _isMac;
bool get isWindows => _isWindows;
bool get isLinux => _isLinux;

/// When this is true, [isLinux] is also true.
bool get isChromeOS => _isChromeOS;
