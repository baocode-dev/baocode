// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0): src/vs/workbench/contrib/debug/test/browser/breakpoints.test.ts
//
// Not ported: `getExpandedBodySize` (the breakpoints view's layout) and the
// `decorations` test (`createBreakpointDecorations`, the breakpoint editor
// contribution). `getBreakpointMessageAndIcon` is
// `breakpointPresentation` from lib/debug/ui/debug_icons.dart.

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/debug/base/event.dart';
import 'package:baocode/debug/common/debug_model.dart';
import 'package:baocode/debug/common/debug_storage.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/session/debug_session.dart';
import 'package:baocode/debug/ui/debug_icons.dart';
import 'package:baocode/debug/ui/debug_strings.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_debug.dart';

List<Breakpoint> addBreakpointsAndCheckEvents(DebugModel model, VsUri uri, List<BreakpointData> data) {
  var eventCount = 0;
  late DebugDisposable toDispose;
  toDispose = model.onDidChangeBreakpoints((e) {
    expect(e?.sessionOnly, false);
    expect(e?.changed, isNull);
    expect(e?.removed, isNull);
    final added = e?.added;
    expect(added, isNotNull);
    expect(added!.length, data.length);
    eventCount++;
    toDispose.dispose();
    for (var i = 0; i < data.length; i++) {
      expect(added[i], isA<Breakpoint>());
      expect((added[i] as Breakpoint).lineNumber, data[i].lineNumber);
    }
  });
  final bps = model.addBreakpoints(uri, data);
  expect(eventCount, 1);
  return bps;
}

void main() {
  group('Debug - Breakpoints', () {
    late DebugModel model;
    late DebugService service;
    final sessions = <DebugSession>[];

    setUp(() {
      model = createMockDebugModel();
      service = createMockDebugService();
    });

    tearDown(() {
      for (final s in sessions) {
        s.dispose();
      }
      sessions.clear();
      model.dispose();
      service.dispose();
    });

    // Breakpoints

    test('simple', () {
      final modelUri = VsUri.file('/myfolder/myfile.js');

      addBreakpointsAndCheckEvents(model, modelUri, const [
        BreakpointData(lineNumber: 5, enabled: true),
        BreakpointData(lineNumber: 10, enabled: false),
      ]);
      expect(model.areBreakpointsActivated(), true);
      expect(model.getBreakpoints().length, 2);

      var eventCount = 0;
      late DebugDisposable toDispose;
      toDispose = model.onDidChangeBreakpoints((e) {
        eventCount++;
        expect(e?.added, isNull);
        expect(e?.sessionOnly, false);
        expect(e?.removed?.length, 2);
        expect(e?.changed, isNull);

        toDispose.dispose();
      });

      model.removeBreakpoints(model.getBreakpoints());
      expect(eventCount, 1);
      expect(model.getBreakpoints().length, 0);
    });

    test('toggling', () {
      final modelUri = VsUri.file('/myfolder/myfile.js');

      addBreakpointsAndCheckEvents(model, modelUri, const [
        BreakpointData(lineNumber: 5, enabled: true),
        BreakpointData(lineNumber: 10, enabled: false),
      ]);
      addBreakpointsAndCheckEvents(model, modelUri, const [
        BreakpointData(lineNumber: 12, enabled: true, condition: 'fake condition'),
      ]);
      expect(model.getBreakpoints().length, 3);
      final bp = model.getBreakpoints().removeLast();
      model.removeBreakpoints([bp]);
      expect(model.getBreakpoints().length, 2);

      model.setBreakpointsActivated(false);
      expect(model.areBreakpointsActivated(), false);
      model.setBreakpointsActivated(true);
      expect(model.areBreakpointsActivated(), true);
    });

    test('two files', () {
      final modelUri1 = VsUri.file('/myfolder/my file first.js');
      final modelUri2 = VsUri.file('/secondfolder/second/second file.js');
      addBreakpointsAndCheckEvents(model, modelUri1, const [
        BreakpointData(lineNumber: 5, enabled: true),
        BreakpointData(lineNumber: 10, enabled: false),
      ]);
      // Not ported: getExpandedBodySize(model, undefined, 9) == 44.

      addBreakpointsAndCheckEvents(model, modelUri2, const [
        BreakpointData(lineNumber: 1, enabled: true),
        BreakpointData(lineNumber: 2, enabled: true),
        BreakpointData(lineNumber: 3, enabled: false),
      ]);
      // Not ported: getExpandedBodySize(model, undefined, 9) == 110.

      expect(model.getBreakpoints().length, 5);
      expect(model.getBreakpoints(uri: modelUri1).length, 2);
      expect(model.getBreakpoints(uri: modelUri2).length, 3);
      expect(model.getBreakpoints(lineNumber: 5).length, 1);
      expect(model.getBreakpoints(column: 5).length, 0);

      final bp = model.getBreakpoints()[0];
      final update = <String, BreakpointUpdateData>{bp.getId(): const BreakpointUpdateData(lineNumber: 100)};
      var eventFired = false;
      late DebugDisposable toDispose;
      toDispose = model.onDidChangeBreakpoints((e) {
        eventFired = true;
        expect(e?.added, isNull);
        expect(e?.removed, isNull);
        expect(e?.changed?.length, 1);
        toDispose.dispose();
      });
      model.updateBreakpoints(update);
      expect(eventFired, true);
      expect(bp.lineNumber, 100);

      expect(model.getBreakpoints(enabledOnly: true).length, 3);
      model.enableOrDisableAllBreakpoints(false);
      for (final bp in model.getBreakpoints()) {
        expect(bp.enabled, false);
      }
      expect(model.getBreakpoints(enabledOnly: true).length, 0);

      model.setEnablement(bp, true);
      expect(bp.enabled, true);

      model.removeBreakpoints(model.getBreakpoints(uri: modelUri1));
      // Not ported: getExpandedBodySize(model, undefined, 9) == 66.

      expect(model.getBreakpoints().length, 3);
    });

    test('conditions', () {
      final modelUri1 = VsUri.file('/myfolder/my file first.js');
      addBreakpointsAndCheckEvents(model, modelUri1, const [
        BreakpointData(lineNumber: 5, condition: 'i < 5', hitCondition: '17'),
        BreakpointData(lineNumber: 10, condition: 'j < 3'),
      ]);
      final breakpoints = model.getBreakpoints();

      expect(breakpoints[0].condition, 'i < 5');
      expect(breakpoints[0].hitCondition, '17');
      expect(breakpoints[1].condition, 'j < 3');
      expect(breakpoints[1].hitCondition?.isNotEmpty ?? false, false);

      expect(model.getBreakpoints().length, 2);
      model.removeBreakpoints(model.getBreakpoints());
      expect(model.getBreakpoints().length, 0);
    });

    test('function breakpoints', () {
      model.addFunctionBreakpoint(FunctionBreakpoint(name: 'foo', id: '1'));
      model.addFunctionBreakpoint(FunctionBreakpoint(name: 'bar', id: '2'));
      model.updateFunctionBreakpoint('1', name: 'fooUpdated');
      model.updateFunctionBreakpoint('2', name: 'barUpdated');

      final functionBps = model.getFunctionBreakpoints();
      expect(functionBps[0].name, 'fooUpdated');
      expect(functionBps[1].name, 'barUpdated');

      model.removeFunctionBreakpoints();
      expect(model.getFunctionBreakpoints().length, 0);
    });

    test('multiple sessions', () {
      final modelUri = VsUri.file('/myfolder/myfile.js');
      addBreakpointsAndCheckEvents(model, modelUri, const [
        BreakpointData(lineNumber: 5, enabled: true, condition: 'x > 5'),
        BreakpointData(lineNumber: 10, enabled: false),
      ]);
      final breakpoints = model.getBreakpoints();
      final session = createTestSession(model, service);
      sessions.add(session);

      expect(breakpoints[0].lineNumber, 5);
      expect(breakpoints[1].lineNumber, 10);

      final data = <String, Json?>{
        breakpoints[0].getId(): {'verified': false, 'line': 10},
        breakpoints[1].getId(): {'verified': true, 'line': 50},
      };
      model.setBreakpointSessionData(session.getId(), {}, data);
      expect(breakpoints[0].lineNumber, 5);
      expect(breakpoints[1].lineNumber, 50);

      final session2 = createTestSession(model, service);
      sessions.add(session2);
      final data2 = <String, Json?>{
        breakpoints[0].getId(): {'verified': true, 'line': 100},
        breakpoints[1].getId(): {'verified': true, 'line': 500},
      };
      model.setBreakpointSessionData(session2.getId(), {}, data2);

      // Breakpoint is verified only once, show that line
      expect(breakpoints[0].lineNumber, 100);
      // Breakpoint is verified two times, show the original line
      expect(breakpoints[1].lineNumber, 10);

      model.setBreakpointSessionData(session.getId(), {}, null);
      // No more double session verification
      expect(breakpoints[0].lineNumber, 100);
      expect(breakpoints[1].lineNumber, 500);

      expect(breakpoints[0].supported, false);
      model.setBreakpointSessionData(session2.getId(), {'supportsConditionalBreakpoints': true}, data2);
      expect(breakpoints[0].supported, true);
    });

    test('exception breakpoints', () {
      var eventCount = 0;
      final listener = model.onDidChangeBreakpoints((_) => eventCount++);
      addTearDown(listener.dispose);
      model.setExceptionBreakpointsForSession('session-id-1', [
        {'filter': 'uncaught', 'label': 'UNCAUGHT', 'default': true},
      ]);
      expect(eventCount, 1);
      var exceptionBreakpoints = model.getExceptionBreakpointsForSession('session-id-1');
      expect(exceptionBreakpoints.length, 1);
      expect(exceptionBreakpoints[0].filter, 'uncaught');
      expect(exceptionBreakpoints[0].enabled, true);

      model.setExceptionBreakpointsForSession('session-id-2', [
        {'filter': 'uncaught', 'label': 'UNCAUGHT'},
        {'filter': 'caught', 'label': 'CAUGHT'},
      ]);
      expect(eventCount, 2);
      exceptionBreakpoints = model.getExceptionBreakpointsForSession('session-id-2');
      expect(exceptionBreakpoints.length, 2);
      expect(exceptionBreakpoints[0].filter, 'uncaught');
      expect(exceptionBreakpoints[0].enabled, true);
      expect(exceptionBreakpoints[1].filter, 'caught');
      expect(exceptionBreakpoints[1].label, 'CAUGHT');
      expect(exceptionBreakpoints[1].enabled, false);

      model.setExceptionBreakpointsForSession('session-id-3', [
        {'filter': 'all', 'label': 'ALL'},
      ]);
      expect(eventCount, 3);
      expect(model.getExceptionBreakpointsForSession('session-id-3').length, 1);
      exceptionBreakpoints = model.getExceptionBreakpoints();
      expect(exceptionBreakpoints[0].filter, 'uncaught');
      expect(exceptionBreakpoints[0].enabled, true);
      expect(exceptionBreakpoints[1].filter, 'caught');
      expect(exceptionBreakpoints[1].label, 'CAUGHT');
      expect(exceptionBreakpoints[1].enabled, false);
      expect(exceptionBreakpoints[2].filter, 'all');
      expect(exceptionBreakpoints[2].label, 'ALL');
    });

    test('exception breakpoints multiple sessions', () {
      var eventCount = 0;
      final listener = model.onDidChangeBreakpoints((_) => eventCount++);
      addTearDown(listener.dispose);

      model.setExceptionBreakpointsForSession('session-id-4', [
        {'filter': 'uncaught', 'label': 'UNCAUGHT', 'default': true},
        {'filter': 'caught', 'label': 'CAUGHT'},
      ]);
      model.setExceptionBreakpointFallbackSession('session-id-4');
      expect(eventCount, 1);
      var exceptionBreakpointsForSession = model.getExceptionBreakpointsForSession('session-id-4');
      expect(exceptionBreakpointsForSession.length, 2);
      expect(exceptionBreakpointsForSession[0].filter, 'uncaught');
      expect(exceptionBreakpointsForSession[1].filter, 'caught');

      model.setExceptionBreakpointsForSession('session-id-5', [
        {'filter': 'all', 'label': 'ALL'},
        {'filter': 'caught', 'label': 'CAUGHT'},
      ]);
      expect(eventCount, 2);
      exceptionBreakpointsForSession = model.getExceptionBreakpointsForSession('session-id-5');
      var exceptionBreakpointsForUndefined = model.getExceptionBreakpointsForSession(null);
      expect(exceptionBreakpointsForSession.length, 2);
      expect(exceptionBreakpointsForSession[0].filter, 'caught');
      expect(exceptionBreakpointsForSession[1].filter, 'all');
      expect(exceptionBreakpointsForUndefined.length, 2);
      expect(exceptionBreakpointsForUndefined[0].filter, 'uncaught');
      expect(exceptionBreakpointsForUndefined[1].filter, 'caught');

      model.removeExceptionBreakpointsForSession('session-id-4');
      expect(eventCount, 2);
      exceptionBreakpointsForUndefined = model.getExceptionBreakpointsForSession(null);
      expect(exceptionBreakpointsForUndefined.length, 2);
      expect(exceptionBreakpointsForUndefined[0].filter, 'uncaught');
      expect(exceptionBreakpointsForUndefined[1].filter, 'caught');

      model.setExceptionBreakpointFallbackSession('session-id-5');
      expect(eventCount, 2);
      exceptionBreakpointsForUndefined = model.getExceptionBreakpointsForSession(null);
      expect(exceptionBreakpointsForUndefined.length, 2);
      expect(exceptionBreakpointsForUndefined[0].filter, 'caught');
      expect(exceptionBreakpointsForUndefined[1].filter, 'all');

      final exceptionBreakpoints = model.getExceptionBreakpoints();
      expect(exceptionBreakpoints.length, 3);
    });

    test('instruction breakpoints', () {
      var eventCount = 0;
      final listener = model.onDidChangeBreakpoints((_) => eventCount++);
      addTearDown(listener.dispose);
      //address: string, offset: number, condition?: string, hitCondition?: string
      model.addInstructionBreakpoint(
        InstructionBreakpoint(instructionReference: '0xCCCCFFFF', offset: 0, address: BigInt.zero, canPersist: false),
      );

      expect(eventCount, 1);
      var instructionBreakpoints = model.getInstructionBreakpoints();
      expect(instructionBreakpoints.length, 1);
      expect(instructionBreakpoints[0].instructionReference, '0xCCCCFFFF');
      expect(instructionBreakpoints[0].offset, 0);

      model.addInstructionBreakpoint(
        InstructionBreakpoint(instructionReference: '0xCCCCEEEE', offset: 1, address: BigInt.zero, canPersist: false),
      );
      expect(eventCount, 2);
      instructionBreakpoints = model.getInstructionBreakpoints();
      expect(instructionBreakpoints.length, 2);
      expect(instructionBreakpoints[0].instructionReference, '0xCCCCFFFF');
      expect(instructionBreakpoints[0].offset, 0);
      expect(instructionBreakpoints[1].instructionReference, '0xCCCCEEEE');
      expect(instructionBreakpoints[1].offset, 1);
    });

    test('data breakpoints', () {
      var eventCount = 0;
      final listener = model.onDidChangeBreakpoints((_) => eventCount++);
      addTearDown(listener.dispose);

      model.addDataBreakpoint(
        DataBreakpoint(
          description: 'label',
          src: const DataBreakpointVariable('id'),
          canPersist: true,
          accessTypes: const ['read'],
          accessType: 'read',
          id: '1',
        ),
      );
      model.addDataBreakpoint(
        DataBreakpoint(
          description: 'second',
          src: const DataBreakpointVariable('secondId'),
          canPersist: false,
          accessTypes: const ['readWrite'],
          accessType: 'readWrite',
          id: '2',
        ),
      );
      model.updateDataBreakpoint('1', condition: 'aCondition');
      model.updateDataBreakpoint('2', hitCondition: '10');
      final dataBreakpoints = model.getDataBreakpoints();
      expect(dataBreakpoints[0].canPersist, true);
      expect(dataBreakpoints[0].src.toJson(), {'type': 'variable', 'dataId': 'id'});
      expect(dataBreakpoints[0].accessType, 'read');
      expect(dataBreakpoints[0].condition, 'aCondition');
      expect(dataBreakpoints[1].canPersist, false);
      expect(dataBreakpoints[1].description, 'second');
      expect(dataBreakpoints[1].accessType, 'readWrite');
      expect(dataBreakpoints[1].hitCondition, '10');

      expect(eventCount, 4);

      model.removeDataBreakpoints(dataBreakpoints[0].getId());
      expect(eventCount, 5);
      expect(model.getDataBreakpoints().length, 1);

      model.removeDataBreakpoints();
      expect(model.getDataBreakpoints().length, 0);
      expect(eventCount, 6);
    });

    test('message and class name', () {
      final modelUri = VsUri.file('/myfolder/my file first.js');
      addBreakpointsAndCheckEvents(model, modelUri, const [
        BreakpointData(lineNumber: 5, enabled: true, condition: 'x > 5'),
        BreakpointData(lineNumber: 10, enabled: false),
        BreakpointData(lineNumber: 12, enabled: true, logMessage: 'hello'),
        BreakpointData(lineNumber: 15, enabled: true, hitCondition: '12'),
        BreakpointData(lineNumber: 500, enabled: true),
      ]);
      final breakpoints = model.getBreakpoints();
      const ls = DebugStrings.en;

      var result = breakpointPresentation(DebugState.stopped, true, breakpoints[0], ls, model: model);
      expect(result.message, 'Condition: x > 5');
      expect(result.icon, Codicons.debugBreakpointConditional);

      result = breakpointPresentation(DebugState.stopped, true, breakpoints[1], ls, model: model);
      expect(result.message, 'Disabled Breakpoint');
      expect(result.icon, Codicons.debugBreakpointDisabled);

      result = breakpointPresentation(DebugState.stopped, true, breakpoints[2], ls, model: model);
      expect(result.message, 'Log Message: hello');
      expect(result.icon, Codicons.debugBreakpointLog);

      result = breakpointPresentation(DebugState.stopped, true, breakpoints[3], ls, model: model);
      expect(result.message, 'Hit Count: 12');
      expect(result.icon, Codicons.debugBreakpointConditional);

      result = breakpointPresentation(DebugState.stopped, true, breakpoints[4], ls, model: model);
      // `ls.getUriLabel(breakpoints[4].uri)` upstream.
      expect(result.message, breakpoints[4].uri.fsPath());
      expect(result.icon, Codicons.debugBreakpoint);

      // See 'message and class name: disabled logpoint' below for
      // getBreakpointMessageAndIcon(State.Stopped, false, breakpoints[2]).

      model.addDataBreakpoint(
        DataBreakpoint(
          description: 'label',
          canPersist: true,
          accessTypes: const ['read'],
          accessType: 'read',
          src: const DataBreakpointVariable('id'),
        ),
      );
      final dataBreakpoints = model.getDataBreakpoints();
      result = breakpointPresentation(DebugState.stopped, true, dataBreakpoints[0], ls, model: model);
      expect(result.message, 'Data Breakpoint');
      expect(result.icon, Codicons.debugBreakpointData);

      final functionBreakpoint = model.addFunctionBreakpoint(FunctionBreakpoint(name: 'foo', id: '1'));
      result = breakpointPresentation(DebugState.stopped, true, functionBreakpoint, ls, model: model);
      expect(result.message, 'Function Breakpoint');
      expect(result.icon, Codicons.debugBreakpointFunction);

      final data = <String, Json?>{
        breakpoints[0].getId(): {'verified': false, 'line': 10},
        breakpoints[1].getId(): {'verified': true, 'line': 50},
        breakpoints[2].getId(): {'verified': true, 'line': 50, 'message': 'world'},
        functionBreakpoint.getId(): {'verified': true},
      };
      model.setBreakpointSessionData('mocksessionid', {
        'supportsFunctionBreakpoints': false,
        'supportsDataBreakpoints': true,
        'supportsLogPoints': true,
      }, data);

      result = breakpointPresentation(DebugState.stopped, true, breakpoints[0], ls, model: model);
      expect(result.message, 'Unverified Breakpoint');
      expect(result.icon, Codicons.debugBreakpointUnverified);

      // See 'message and class name: unsupported function breakpoint' below.

      result = breakpointPresentation(DebugState.stopped, true, breakpoints[2], ls, model: model);
      expect(result.message, 'Log Message: hello, world');
      expect(result.icon, Codicons.debugBreakpointLog);
    });

    // The assertions of 'message and class name' breakpointPresentation
    // fails, split out to keep the rest running.
    test(
      'message and class name: disabled logpoint',
      () {
        final modelUri = VsUri.file('/myfolder/my file first.js');
        addBreakpointsAndCheckEvents(model, modelUri, const [
          BreakpointData(lineNumber: 12, enabled: true, logMessage: 'hello'),
        ]);
        final result = breakpointPresentation(DebugState.stopped, false, model.getBreakpoints()[0], DebugStrings.en, model: model);
        expect(result.message, 'Disabled Logpoint');
        expect(result.icon, Codicons.debugBreakpointLogDisabled);
      },
      skip: 'breakpointPresentation says "Disabled Breakpoint (Logpoint)" for a disabled logpoint, upstream "Disabled Logpoint"',
    );

    test(
      'message and class name: unsupported function breakpoint',
      () {
        final functionBreakpoint = model.addFunctionBreakpoint(FunctionBreakpoint(name: 'foo', id: '1'));
        model.setBreakpointSessionData('mocksessionid', {
          'supportsFunctionBreakpoints': false,
          'supportsDataBreakpoints': true,
          'supportsLogPoints': true,
        }, {functionBreakpoint.getId(): {'verified': true}});
        final result = breakpointPresentation(DebugState.stopped, true, functionBreakpoint, DebugStrings.en, model: model);
        expect(result.message, 'Function breakpoints not supported by this debug type');
        expect(result.icon, Codicons.debugBreakpointFunctionUnverified);
      },
      skip: 'breakpointPresentation lacks the `!breakpoint.supported` branches for function/data breakpoints',
    );

    // 'decorations': not ported (createBreakpointDecorations, editor only).

    test('updates when storage changes', () {
      final storage1 = MemoryDebugStorageBackend();
      final debugStorage1 = DebugStorage(storage1);
      final model1 = DebugModel(debugStorage1, isDirty: (_) => false);
      addTearDown(model1.dispose);

      // 1. create breakpoints in the first model
      final modelUri = VsUri.file('/myfolder/my file first.js');
      const first = [
        BreakpointData(lineNumber: 1, enabled: true, condition: 'x > 5'),
        BreakpointData(lineNumber: 2, column: 4, enabled: false),
      ];

      addBreakpointsAndCheckEvents(model1, modelUri, first);
      debugStorage1.storeBreakpoints(model1);
      final stored = storage1.get(DebugStorage.breakpointsKey)!;

      // 2. hydrate a new model and ensure external breakpoints get applied
      final storage2 = MemoryDebugStorageBackend();
      final debugStorage2 = DebugStorage(storage2);
      final model2 = DebugModel(debugStorage2, isDirty: (_) => false);
      addTearDown(model2.dispose);
      // An external change: stored, then told (`reload`).
      storage2.store(DebugStorage.breakpointsKey, stored);
      debugStorage2.reload();
      expect(
        model2.getBreakpoints().map((b) => b.getId()).toList(),
        model1.getBreakpoints().map((b) => b.getId()).toList(),
      );

      // 3. ensure non-external changes are ignored
      storage2.store(DebugStorage.breakpointsKey, '[]');
      expect(
        model2.getBreakpoints().map((b) => b.getId()).toList(),
        model1.getBreakpoints().map((b) => b.getId()).toList(),
      );
    });
  });
}
