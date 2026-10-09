/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The shapes the extension host protocol carries for debugging: sessions,
// breakpoints (0-based lines there, 1-based here), focus, and the options
// of `$startDebugging`; for the glue's `MainThreadDebugService`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDebugService.ts (`getSessionDto`,
// `convertToDto`, `$registerBreakpoints`, `$unregisterBreakpoints`,
// `$startDebugging`'s options, the `$acceptStackFrameFocus` listener,
// `sendBreakpointsAndListen`).

import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import '../service/debug_service.dart';
import '../session/debug_session.dart';
import 'debug_model.dart';
import 'debug_types.dart';
import 'debug_view_model.dart';

/// `IDebugSessionDto` (always the full object; the glue may send just the
/// id once the extension host said `$sessionCached`).
Json debugSessionDto(DebugSession session) => {
  'id': session.getId(),
  'type': session.configuration['type'],
  'name': session.name,
  'folderUri': ?session.root?.uri.toJson(),
  'configuration': session.configuration,
  'parent': ?session.parentSession?.getId(),
};

/// `convertToDto`: source, function and data breakpoints (instruction and
/// exception breakpoints are not sent).
List<Json> breakpointsToDto(Iterable<Object> breakpoints) => [
  for (final bp in breakpoints)
    if (bp is FunctionBreakpoint)
      {
        'type': 'function',
        'id': bp.getId(),
        'enabled': bp.enabled,
        'condition': ?bp.condition,
        'hitCondition': ?bp.hitCondition,
        'logMessage': ?bp.logMessage,
        'functionName': bp.name,
      }
    else if (bp is DataBreakpoint)
      {
        'type': 'data',
        'id': bp.getId(),
        'dataId': switch (bp.src) {
          DataBreakpointVariable(:final dataId) => dataId,
          DataBreakpointAddress(:final address) => address,
        },
        'enabled': bp.enabled,
        'condition': ?bp.condition,
        'hitCondition': ?bp.hitCondition,
        'logMessage': ?bp.logMessage,
        'accessType': bp.accessType,
        'label': bp.description,
        'canPersist': bp.canPersist,
      }
    else if (bp is Breakpoint)
      {
        'type': 'source',
        'id': bp.getId(),
        'enabled': bp.enabled,
        'condition': ?bp.condition,
        'hitCondition': ?bp.hitCondition,
        'logMessage': ?bp.logMessage,
        'uri': bp.uri.toJson(),
        'line': bp.lineNumber > 0 ? bp.lineNumber - 1 : 0,
        'character': (bp.column ?? 0) > 0 ? bp.column! - 1 : 0,
      },
];

/// `IBreakpointsDeltaDto` for a model change; null when there is nothing
/// for extensions (none, or only session data changed).
Json? breakpointsDeltaDto(BreakpointsChangeEvent? e) {
  if (e == null || e.sessionOnly) return null;
  final delta = <String, Object?>{
    if (e.added != null) 'added': breakpointsToDto(e.added!),
    if (e.removed != null)
      'removed': [
        for (final bp in e.removed!)
          if (bp is Enablement) bp.getId(),
      ],
    if (e.changed != null) 'changed': breakpointsToDto(e.changed!),
  };
  return delta.isEmpty ? null : delta;
}

/// The first delta, with every breakpoint, sent when the extension host
/// starts; null when there are none.
Json? initialBreakpointsDto(DebugModel model) {
  final bps = model.getBreakpoints();
  final fbps = model.getFunctionBreakpoints();
  final dbps = model.getDataBreakpoints();
  if (bps.isEmpty && fbps.isEmpty) return null;
  return {
    'added': breakpointsToDto([...bps, ...fbps, ...dbps]),
  };
}

/// `$registerBreakpoints`.
Future<void> registerBreakpointsFromDto(DebugService service, List<Json> dtos) async {
  for (final dto in dtos) {
    switch (dto['type']) {
      case 'sourceMulti':
        final uri = VsUri.revive(dto.obj('uri') ?? const {});
        await service.addBreakpoints(uri, [
          for (final l in dto.objects('lines'))
            BreakpointData(
              id: l.str('id'),
              enabled: l['enabled'] as bool?,
              lineNumber: (l.integer('line') ?? 0) + 1,
              // A column of 0 means none #46784.
              column: (l.integer('character') ?? 0) > 0 ? l.integer('character')! + 1 : null,
              condition: l.str('condition'),
              hitCondition: l.str('hitCondition'),
              logMessage: l.str('logMessage'),
              mode: l.str('mode'),
            ),
        ]);
      case 'function':
        await service.addFunctionBreakpoint(
          FunctionBreakpoint(
            name: dto.str('functionName') ?? '',
            mode: dto.str('mode'),
            condition: dto.str('condition'),
            hitCondition: dto.str('hitCondition'),
            enabled: dto['enabled'] as bool?,
            logMessage: dto.str('logMessage'),
            id: dto.str('id'),
          ),
        );
      case 'data':
        await service.addDataBreakpoint(
          DataBreakpoint(
            description: dto.str('label') ?? '',
            src: DataBreakpointVariable(dto.str('dataId') ?? ''),
            canPersist: dto.flag('canPersist'),
            accessTypes: dto.list('accessTypes')?.whereType<String>().toList(),
            accessType: dto.str('accessType') ?? 'write',
            mode: dto.str('mode'),
          ),
        );
    }
  }
}

/// `$unregisterBreakpoints`.
Future<void> unregisterBreakpointsFromDto(
  DebugService service,
  List<String> breakpointIds,
  List<String> functionBreakpointIds,
  List<String> dataBreakpointIds,
) async {
  if (breakpointIds.isNotEmpty) await service.removeBreakpoints(breakpointIds);
  for (final id in functionBreakpointIds) {
    await service.removeFunctionBreakpoints(id);
  }
  for (final id in dataBreakpointIds) {
    await service.removeDataBreakpoints(id);
  }
}

/// `IStackFrameFocusDto` / `IThreadFocusDto`, null when nothing is
/// focused (`$acceptStackFrameFocus`).
Json? stackFrameFocusDto(DebugViewModel viewModel) {
  final stackFrame = viewModel.focusedStackFrame;
  final thread = viewModel.focusedThread;
  if (stackFrame != null) {
    return {
      'kind': 'stackFrame',
      'threadId': stackFrame.thread.threadId,
      'frameId': stackFrame.frameId,
      'sessionId': stackFrame.thread.session.getId(),
    };
  }
  if (thread != null) {
    return {'kind': 'thread', 'threadId': thread.threadId, 'sessionId': thread.session.getId()};
  }
  return null;
}

/// `$startDebugging`'s `IStartDebuggingOptions` as session options.
DebugSessionOptions sessionOptionsFromDto(DebugModel model, Json options) {
  final parentId = options.str('parentSessionID');
  final parentSession = parentId != null ? model.getSession(parentId, includeInactive: true) : null;
  final suppressSave = options['suppressSaveBeforeStart'];
  return DebugSessionOptions(
    noDebug: options['noDebug'] as bool?,
    parentSession: parentSession,
    lifecycleManagedByParent: options.flag('lifecycleManagedByParent'),
    repl: options['repl'] == 'mergeWithParent' ? DebugSessionReplMode.mergeWithParent : DebugSessionReplMode.separate,
    compact: options.flag('compact'),
    compoundRoot: parentSession?.compoundRoot,
    saveBeforeRestart: suppressSave is bool ? !suppressSave : null,
    suppressDebugStatusbar: options.flag('suppressDebugStatusbar'),
    suppressDebugToolbar: options.flag('suppressDebugToolbar'),
    suppressDebugView: options.flag('suppressDebugView'),
  );
}

/// `$startDebugging`'s save-before-start (null: the default).
bool? saveBeforeStartFromDto(Json options) {
  final suppress = options['suppressSaveBeforeStart'];
  return suppress is bool ? !suppress : null;
}
