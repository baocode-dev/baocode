/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/base/common/console.ts (`IRemoteConsoleLog`, `parse`, `log`: the
// `[label] message (top frame)` format),
// src/vs/workbench/services/extensions/common/remoteConsoleUtil.ts
// (`logRemoteEntryIfError`: only errors whose first argument is a string
// go to the log), src/vs/base/common/errors.ts (`SerializedError`,
// `transformErrorFromSerialization`).
//
// Deviations: what upstream writes to the developer tools' console is a
// line of the output panel's "Extension Host" channel, in the log format
// (`<time> [<level>] [Extension Host] …`) so that it is filtered by level;
// objects are written as JSON; a `source` the entry has is written after
// the message like a top frame.

import 'dart:convert';

import '../../host/init_data.dart' show ExtHostLogLevel;

/// `IRemoteConsoleLog` parsed (`parse`).
final class RemoteConsoleEntry {
  const RemoteConsoleEntry({
    required this.severity,
    required this.args,
    this.stack,
    this.source,
  });

  /// `{type: '__$console', severity, arguments: '<JSON array>'}` as the
  /// extension host's console forwarder sends it.
  factory RemoteConsoleEntry.fromJson(Map<String, Object?> entry) {
    final args = <Object?>[];
    String? stack;
    final arguments = entry['arguments'];
    try {
      final parsed = jsonDecode(arguments is String ? arguments : '') as List;
      if (parsed.isNotEmpty) {
        final last = parsed.last;
        if (last is Map && last[r'__$stack'] is String) {
          stack = last[r'__$stack'] as String;
          parsed.removeLast();
        }
      }
      args.addAll(parsed);
    } on Object {
      args.addAll(['Unable to log remote console arguments', arguments]);
    }
    final severity = entry['severity'];
    final source = entry['source'];
    return RemoteConsoleEntry(
      severity: severity is String && severity.isNotEmpty ? severity : 'info',
      args: args,
      stack: stack,
      source: source is String && source.isNotEmpty ? source : null,
    );
  }

  /// `log`, `info`, `warn`, `error`, `debug`.
  final String severity;
  final List<Object?> args;
  final String? stack;
  final String? source;

  ExtHostLogLevel get level => switch (severity) {
    'error' => ExtHostLogLevel.error,
    'warn' => ExtHostLogLevel.warning,
    'debug' => ExtHostLogLevel.debug,
    'trace' => ExtHostLogLevel.trace,
    _ => ExtHostLogLevel.info,
  };

  /// What `logRemoteEntryIfError` writes to the log: an error whose first
  /// argument is a string, labelled; null for anything else.
  String? get errorMessage {
    if (severity != 'error' || args.isEmpty || args.first is! String) {
      return null;
    }
    return '[Extension Host] ${[for (final a in args) _text(a)].join(' ')}';
  }

  /// `log(entry, label)`: `[label] first rest… (top frame)`.
  String format(String label) {
    var topFrame = _firstLine(stack)?.trim();
    if (topFrame != null && topFrame.isEmpty) topFrame = null;
    final parts = <String>['[$label]'];
    if (args.isNotEmpty) parts.addAll(args.map(_text));
    if (topFrame != null) parts.add('($topFrame)');
    if (source != null) parts.add('($source)');
    return parts.join(' ');
  }

  static String? _firstLine(String? s) {
    if (s == null) return null;
    final i = s.indexOf('\n');
    return i < 0 ? s : s.substring(0, i);
  }
}

String _text(Object? value) {
  if (value is String) return value;
  try {
    return jsonEncode(value);
  } on Object {
    return '$value';
  }
}

/// An error the extension host reported (`transformErrorFromSerialization`).
final class ExtensionHostError implements Exception {
  const ExtensionHostError({
    required this.name,
    required this.message,
    this.stack,
    this.code,
    this.cause,
  });

  /// [err] as `$onUnexpectedError` gets it: a `SerializedError`
  /// (`$isError`), else anything the extension host threw.
  factory ExtensionHostError.fromWire(Object? err) {
    if (err is Map && err[r'$isError'] == true) {
      final cause = err['cause'];
      return ExtensionHostError(
        name: err['noTelemetry'] == true
            ? 'CodeExpectedError'
            : '${err['name'] ?? 'Error'}',
        message: '${err['message'] ?? ''}',
        stack: err['stack'] is String ? err['stack'] as String : null,
        code: err['code'] is String ? err['code'] as String : null,
        cause: cause is Map ? ExtensionHostError.fromWire(cause) : null,
      );
    }
    return ExtensionHostError(name: 'Error', message: _text(err));
  }

  final String name;
  final String message;
  final String? stack;
  final String? code;
  final ExtensionHostError? cause;

  /// The stack without its first line when that is `name: message`.
  String? get frames {
    final s = stack;
    if (s == null || s.isEmpty) return null;
    final first = s.indexOf('\n');
    final head = first < 0 ? s : s.substring(0, first);
    if (head.contains(message) || head.startsWith(name)) {
      return first < 0 ? null : s.substring(first + 1);
    }
    return s;
  }

  /// `name: message`, the stack's frames, then each cause's.
  String describe() {
    final lines = [toString()];
    final f = frames;
    if (f != null) lines.add(f);
    if (cause case final cause?) lines.add('Caused by: ${cause.describe()}');
    return lines.join('\n');
  }

  @override
  String toString() => message.isEmpty ? name : '$name: $message';
}
