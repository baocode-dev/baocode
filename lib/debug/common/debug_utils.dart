/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Helpers of the debug model: error message formatting, paths in DAP
// messages as URIs for the extension host and back, launch configurations'
// presentation order and platform overrides.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/debugUtils.ts.
//
// Deviations: the platform overrides take the target platform as a
// parameter; paths are told absolute for both POSIX and Windows.

import '../../base/uri.dart' show VsUri;

import 'debug_types.dart';

final _formatPIIRegexp = RegExp(r'{([^}]+)}');

/// `formatPII`: [value] with `{name}` replaced by [args]' values.
String formatPII(String value, bool excludePII, Map<String, Object?>? args) =>
    value.replaceAllMapped(_formatPIIRegexp, (match) {
      final group = match[1]!;
      if (excludePII && group.isNotEmpty && group[0] != '_') return match[0]!;
      return args != null && args.containsKey(group)
          ? '${args[group]}'
          : match[0]!;
    });

/// `filterExceptionsFromTelemetry`.
Json filterExceptionsFromTelemetry(Json data) => {
  for (final e in data.entries)
    if (!e.key.startsWith('!')) e.key: e.value,
};

final _schemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]+:');

/// `isUriString`: starts with a scheme of 2 characters or more (not a
/// drive letter).
bool isUriString(String? s) => s != null && _schemePattern.hasMatch(s);

/// An absolute path on POSIX or Windows.
bool isAbsolutePath(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\\') ||
    RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);

bool _looksWindows(String path) =>
    path.startsWith(r'\\') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);

/// `isDebuggerMainContribution`: one with a label, program or runtime.
bool isDebuggerMainContribution(Json contribution) =>
    contribution['type'] != null &&
    (contribution['label'] != null ||
        contribution['program'] != null ||
        contribution['runtime'] != null);

/// `stringToUri`: a source's path as the extension host's URI.
Object? _stringToUri(Json source) {
  final path = source['path'];
  if (path is String) {
    final ref = source['sourceReference'];
    if (ref is num && ref > 0) return path;
    if (isUriString(path)) return VsUri.parse(path).toJson();
    if (isAbsolutePath(path)) {
      return VsUri.file(path, windows: _looksWindows(path)).toJson();
    }
  }
  return path;
}

/// `uriToString`: the extension host's URI as a path again.
Object? _uriToString(Json source, {bool windows = false}) {
  final path = source['path'];
  if (path is Map) {
    final uri = VsUri.tryRevive(path.cast<String, Object?>());
    if (uri != null) {
      return uri.scheme == 'file' ? uri.fsPath(windows: windows) : uri.toString();
    }
  }
  return path;
}

/// `convertToDAPaths`: a copy of [message] whose sources' paths going to
/// the adapter are URIs ([toUri]) or paths.
Json convertToDAPaths(Json message, bool toUri, {bool windows = false}) {
  final msg = cloneJson(message);
  _convertPaths(msg, (toDA, source) {
    if (toDA && source != null) {
      source['path'] = toUri
          ? _stringToUri(source)
          : _uriToString(source, windows: windows);
    }
  });
  return msg;
}

/// `convertToVSCPaths`: a copy of [message] whose sources' paths coming
/// from the adapter are URIs ([toUri]) or paths.
Json convertToVSCPaths(Json message, bool toUri, {bool windows = false}) {
  final msg = cloneJson(message);
  _convertPaths(msg, (toDA, source) {
    if (!toDA && source != null) {
      source['path'] = toUri
          ? _stringToUri(source)
          : _uriToString(source, windows: windows);
    }
  });
  return msg;
}

void _convertPaths(Json msg, void Function(bool toDA, Json? source) fix) {
  Json? body() => msg.obj('body');
  Json? args() => msg.obj('arguments');
  switch (msg['type']) {
    case 'event':
      switch (msg['event']) {
        case 'output':
        case 'loadedSource':
          fix(false, body()?.obj('source'));
        case 'breakpoint':
          fix(false, body()?.obj('breakpoint')?.obj('source'));
      }
    case 'request':
      switch (msg['command']) {
        case 'setBreakpoints':
        case 'breakpointLocations':
        case 'source':
        case 'gotoTargets':
          fix(true, args()?.obj('source'));
        case 'launchVSCode':
          for (final arg in args()?.objects('args') ?? const <Json>[]) {
            fix(false, arg);
          }
      }
    case 'response':
      if (msg['success'] == true && body() != null) {
        final b = body()!;
        switch (msg['command']) {
          case 'stackTrace':
            for (final frame in b.objects('stackFrames')) {
              fix(false, frame.obj('source'));
            }
          case 'loadedSources':
            for (final source in b.objects('sources')) {
              fix(false, source);
            }
          case 'scopes':
            for (final scope in b.objects('scopes')) {
              fix(false, scope.obj('source'));
            }
          case 'setFunctionBreakpoints':
          case 'setBreakpoints':
            for (final bp in b.objects('breakpoints')) {
              fix(false, bp.obj('source'));
            }
          case 'disassemble':
            for (final instruction in b.objects('instructions')) {
              fix(false, instruction.obj('location'));
            }
          case 'locations':
            fix(false, b.obj('source'));
        }
      }
  }
}

/// A launch configuration's or compound's `presentation`
/// (`IConfigPresentation`).
final class ConfigPresentation {
  const ConfigPresentation({this.hidden = false, this.group, this.order});

  factory ConfigPresentation.fromJson(Json? json) => ConfigPresentation(
    hidden: json?.flag('hidden') ?? false,
    group: json?.str('group'),
    order: json?.integer('order'),
  );

  final bool hidden;
  final String? group;
  final int? order;
}

/// `getVisibleAndSorted`: those not hidden, by group then order.
List<T> getVisibleAndSorted<T>(
  List<T> items,
  ConfigPresentation? Function(T) presentation,
) {
  final visible = [
    for (final item in items)
      if (!(presentation(item)?.hidden ?? false)) item,
  ];
  int compareOrders(int? first, int? second) {
    if (first == null) return second == null ? 0 : 1;
    if (second == null) return -1;
    return first - second;
  }

  // A stable sort, as Array.prototype.sort is.
  final indexed = visible.indexed.toList()
    ..sort((a, b) {
      final first = presentation(a.$2);
      final second = presentation(b.$2);
      int result;
      if (first == null) {
        result = second == null ? 0 : 1;
      } else if (second == null) {
        result = -1;
      } else if (first.group == null) {
        result = second.group == null
            ? compareOrders(first.order, second.order)
            : 1;
      } else if (second.group == null) {
        result = -1;
      } else if (first.group != second.group) {
        result = first.group!.compareTo(second.group!);
      } else {
        result = compareOrders(first.order, second.order);
      }
      return result != 0 ? result : a.$1 - b.$1;
    });
  return [for (final (_, item) in indexed) item];
}

/// The platforms launch configurations have overrides for.
enum DebugTargetOs { windows, macintosh, linux }

/// The overrides' key for [os].
String platformConfigKey(DebugTargetOs os) => switch (os) {
  DebugTargetOs.windows => 'windows',
  DebugTargetOs.macintosh => 'osx',
  DebugTargetOs.linux => 'linux',
};

/// `getEffectiveConfigForPlatform`.
Json getEffectiveConfigForPlatform(Json config, DebugTargetOs os) {
  final platformConfig = config.obj(platformConfigKey(os));
  if (platformConfig == null) return config;
  final presentation = platformConfig.obj('presentation');
  return {
    ...config,
    ...platformConfig,
    'presentation': presentation != null
        ? {...?config.obj('presentation'), ...presentation}
        : config['presentation'],
  }..removeWhere((key, value) => key == 'presentation' && value == null);
}

/// `sourcesEqual`.
bool sourcesEqual(Json? a, Json? b) => a == null || b == null
    ? identical(a, b)
    : a['name'] == b['name'] &&
          a['path'] == b['path'] &&
          a['sourceReference'] == b['sourceReference'];

/// The last path segment of [uri], else its authority
/// (`basenameOrAuthority`).
String basenameOrAuthority(VsUri uri) {
  final path = uri.path;
  final trimmed = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  final slash = trimmed.lastIndexOf('/');
  final base = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
  return base.isEmpty ? uri.authority : base;
}

/// `getExactExpressionStartAndEnd` (1-based columns): the expression
/// around [looseStart]..[looseEnd] in [lineContent], as hovers evaluate.
({int start, int end}) getExactExpressionStartAndEnd(
  String lineContent,
  int looseStart,
  int looseEnd,
) {
  String? matchingExpression;
  var startOffset = 0;
  final expression = RegExp(
    r'([^()\[\]{}<>\s+\-/%~#^;=|,`!]|->)+',
  );
  for (final result in expression.allMatches(lineContent)) {
    final start = result.start + 1;
    final end = start + result[0]!.length;
    if (start <= looseStart && end >= looseEnd) {
      matchingExpression = result[0];
      startOffset = start;
      break;
    }
  }
  // Spread syntax: just the identifier after `...`.
  if (matchingExpression != null) {
    final spread = RegExp(r'^\.\.\.(.+)').firstMatch(matchingExpression);
    if (spread != null) {
      matchingExpression = spread[1];
      startOffset += 3;
    }
  }
  // Non-word characters after the cursor end it: `a.b` of `a.b.c.d` with
  // the cursor on `b`.
  if (matchingExpression != null) {
    final subExpression = RegExp(r'(\w|\p{L})+', unicode: true);
    for (final result in subExpression.allMatches(matchingExpression)) {
      final subEnd = result.start + 1 + startOffset + result[0]!.length;
      if (subEnd >= looseEnd) {
        matchingExpression = matchingExpression!.substring(0, result.end);
        break;
      }
    }
  }
  return matchingExpression != null
      ? (start: startOffset, end: startOffset + matchingExpression.length - 1)
      : (start: 0, end: 0);
}
