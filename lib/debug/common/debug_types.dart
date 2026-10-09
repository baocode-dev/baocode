/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The shapes the debug model shares: DAP messages as JSON maps, a debug
// configuration, the session state, ranges and workspace folders.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/common/debug.ts (`State`, `IConfig`,
// `IDebugSessionOptions`, `IRawStoppedDetails`, `IBreakpointData`,
// `IBreakpointUpdateData`, `IBreakpointsChangeEvent`, `DataBreakpointSetType`,
// `IExceptionInfo`, `IReplElementSource`, `AdapterEndEvent`,
// `isFrameDeemphasized`) and common/debugCompoundRoot.ts.
//
// Deviations: DAP messages stay JSON maps (`Json`) with typed accessors
// where the model reads them, instead of the `DebugProtocol` interfaces.

import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import '../base/event.dart';

/// A JSON object: a DAP message, its body, a debug configuration.
typedef Json = Map<String, Object?>;

/// `State`.
enum DebugState { inactive, initializing, stopped, running }

/// `getStateLabel`.
String debugStateLabel(DebugState state) => switch (state) {
  DebugState.initializing => 'initializing',
  DebugState.stopped => 'stopped',
  DebugState.running => 'running',
  DebugState.inactive => 'inactive',
};

/// Reads a JSON value as the type asked for, else null.
T? jsonAs<T>(Object? value) => value is T ? value : null;

extension JsonRead on Json {
  String? str(String key) => jsonAs<String>(this[key]);
  int? integer(String key) => switch (this[key]) {
    final int i => i,
    final double d when d == d.roundToDouble() => d.toInt(),
    _ => null,
  };
  bool flag(String key) => this[key] == true;
  Json? obj(String key) => switch (this[key]) {
    final Map<String, Object?> m => m,
    final Map m => m.cast<String, Object?>(),
    _ => null,
  };
  List<Object?>? list(String key) => jsonAs<List<Object?>>(this[key]);

  /// The list at [key] as JSON objects (others skipped).
  List<Json> objects(String key) => [
    for (final item in list(key) ?? const <Object?>[])
      if (item is Map) item.cast<String, Object?>(),
  ];
}

/// A copy of [value] deep enough that changing it leaves [value] as it was
/// (`deepClone`, `structuredClone`).
Object? jsonClone(Object? value) => switch (value) {
  final Map m => <String, Object?>{
    for (final e in m.entries) e.key as String: jsonClone(e.value),
  },
  final List l => [for (final v in l) jsonClone(v)],
  _ => value,
};

Json cloneJson(Json value) => jsonClone(value)! as Json;

/// Whether [a] and [b] are equal JSON values (`equals` from objects.ts).
bool jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// A range in a text, 1-based lines and columns (`IRange`).
final class DebugRange {
  const DebugRange(
    this.startLineNumber,
    this.startColumn,
    this.endLineNumber,
    this.endColumn,
  );

  final int startLineNumber;
  final int startColumn;
  final int endLineNumber;
  final int endColumn;

  /// `Range.containsRange`.
  bool containsRange(DebugRange other) {
    if (other.startLineNumber < startLineNumber ||
        other.endLineNumber < startLineNumber) {
      return false;
    }
    if (other.startLineNumber > endLineNumber ||
        other.endLineNumber > endLineNumber) {
      return false;
    }
    if (other.startLineNumber == startLineNumber &&
        other.startColumn < startColumn) {
      return false;
    }
    if (other.endLineNumber == endLineNumber && other.endColumn > endColumn) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is DebugRange &&
      other.startLineNumber == startLineNumber &&
      other.startColumn == startColumn &&
      other.endLineNumber == endLineNumber &&
      other.endColumn == endColumn;

  @override
  int get hashCode =>
      Object.hash(startLineNumber, startColumn, endLineNumber, endColumn);

  @override
  String toString() =>
      '[$startLineNumber,$startColumn -> $endLineNumber,$endColumn]';
}

/// A folder of the workspace (`IWorkspaceFolder`).
final class DebugWorkspaceFolder {
  const DebugWorkspaceFolder({
    required this.uri,
    required this.name,
    this.index = 0,
  });

  final VsUri uri;
  final String name;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is DebugWorkspaceFolder && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

/// `IRawStoppedDetails`: a `stopped` event's body, as the model keeps it.
final class RawStoppedDetails {
  RawStoppedDetails({
    this.reason,
    this.description,
    this.threadId,
    this.text,
    this.totalFrames,
    this.allThreadsStopped = false,
    this.preserveFocusHint = false,
    this.framesErrorMessage,
    this.hitBreakpointIds,
  });

  factory RawStoppedDetails.fromJson(Json body) => RawStoppedDetails(
    reason: body.str('reason'),
    description: body.str('description'),
    threadId: body.integer('threadId'),
    text: body.str('text'),
    allThreadsStopped: body.flag('allThreadsStopped'),
    preserveFocusHint: body.flag('preserveFocusHint'),
    hitBreakpointIds: body
        .list('hitBreakpointIds')
        ?.whereType<num>()
        .map((n) => n.toInt())
        .toList(),
  );

  String? reason;
  String? description;
  int? threadId;
  String? text;
  int? totalFrames;
  bool allThreadsStopped;
  bool preserveFocusHint;
  String? framesErrorMessage;
  List<int>? hitBreakpointIds;
}

/// `IExceptionInfo`.
final class ExceptionInfo {
  const ExceptionInfo({
    this.id,
    this.description,
    this.breakMode,
    this.details,
  });

  final String? id;
  final String? description;
  final String? breakMode;
  final Json? details;
}

/// `AdapterEndEvent`.
final class AdapterEndEvent {
  const AdapterEndEvent({
    this.error,
    required this.sessionLengthInSeconds,
    required this.emittedStopped,
  });

  final Object? error;
  final double sessionLengthInSeconds;
  final bool emittedStopped;
}

/// `IBreakpointData`: a source breakpoint to add.
final class BreakpointData {
  const BreakpointData({
    this.id,
    required this.lineNumber,
    this.column,
    this.enabled,
    this.condition,
    this.logMessage,
    this.hitCondition,
    this.triggeredBy,
    this.mode,
    this.modeLabel,
  });

  final String? id;
  final int lineNumber;
  final int? column;
  final bool? enabled;
  final String? condition;
  final String? logMessage;
  final String? hitCondition;
  final String? triggeredBy;
  final String? mode;
  final String? modeLabel;
}

/// An absent field of an update, told apart from one set to null.
const Object unset = _Unset();

final class _Unset {
  const _Unset();
}

/// `IBreakpointUpdateData`: only the fields given ([unset] the others)
/// change; a field given as null clears it.
final class BreakpointUpdateData {
  const BreakpointUpdateData({
    this.condition = unset,
    this.hitCondition = unset,
    this.logMessage = unset,
    this.lineNumber,
    this.column = unset,
    this.triggeredBy = unset,
    this.mode = unset,
    this.modeLabel,
  });

  final Object? condition;
  final Object? hitCondition;
  final Object? logMessage;
  final int? lineNumber;
  final Object? column;
  final Object? triggeredBy;
  final Object? mode;
  final String? modeLabel;
}

/// `DataBreakpointSetType` and `DataBreakpointSource`.
sealed class DataBreakpointSource {
  const DataBreakpointSource();

  Json toJson();

  static DataBreakpointSource fromJson(Json json) =>
      json.str('type') == 'address'
      ? DataBreakpointAddress(json.str('address') ?? '', json.integer('bytes') ?? 1)
      : DataBreakpointVariable(json.str('dataId') ?? '');
}

final class DataBreakpointVariable extends DataBreakpointSource {
  const DataBreakpointVariable(this.dataId);

  final String dataId;

  @override
  Json toJson() => {'type': 'variable', 'dataId': dataId};
}

final class DataBreakpointAddress extends DataBreakpointSource {
  const DataBreakpointAddress(this.address, this.bytes);

  final String address;
  final int bytes;

  @override
  Json toJson() => {'type': 'address', 'address': address, 'bytes': bytes};
}

/// `IDebugSessionReplMode`.
enum DebugSessionReplMode { separate, mergeWithParent }

/// `DebugCompoundRoot`: sessions of a compound with `stopAll` stop
/// together.
final class DebugCompoundRoot {
  bool _stopped = false;
  final Emitter<void> _onDidSessionStop = Emitter<void>();

  DebugDisposable onDidSessionStop(void Function() listener) =>
      _onDidSessionStop.listen((_) => listener());

  void sessionStopped() {
    if (!_stopped) {
      _stopped = true;
      _onDidSessionStop.fire(null);
    }
  }
}

/// Where a REPL element was printed from (`IReplElementSource`).
final class ReplElementSource {
  const ReplElementSource({
    required this.source,
    required this.lineNumber,
    required this.column,
  });

  final Object source; // Source; kept loose to avoid an import cycle.
  final int lineNumber;
  final int column;
}

/// How severe REPL output is (`Severity`).
enum ReplSeverity { ignore, info, warning, error }

/// `isFrameDeemphasized`.
bool isFrameDeemphasized({
  required String? sourcePresentationHint,
  required String? framePresentationHint,
}) =>
    sourcePresentationHint == 'deemphasize' ||
    framePresentationHint == 'deemphasize' ||
    framePresentationHint == 'subtle';

/// Breakpoints added, removed or changed (`IBreakpointsChangeEvent`).
final class BreakpointsChangeEvent {
  const BreakpointsChangeEvent({
    this.added,
    this.removed,
    this.changed,
    this.sessionOnly = false,
  });

  final List<Object>? added;
  final List<Object>? removed;
  final List<Object>? changed;
  final bool sessionOnly;
}

/// A DAP request that failed: the adapter's message, as the user is to see
/// it, and whether it is to be shown at all.
final class DebugRequestError implements Exception {
  DebugRequestError(
    this.message, {
    this.showUser,
    this.url,
    this.urlLabel,
    this.response,
  });

  final String message;
  final bool? showUser;
  final String? url;
  final String? urlLabel;

  /// The error response, when there was one.
  final Json? response;

  @override
  String toString() => message;
}

/// A request cancelled before it answered (`CancellationError`).
final class DebugCancelledError implements Exception {
  const DebugCancelledError();

  @override
  String toString() => 'Canceled';
}
