// Goal section 9.4, protocol evidence (not real-extension acceptance):
// MainThreadDebugService against a scripted extension host, carrying the
// existing fake DAP adapter through the same RPC messages as a real one.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/debug/common/debug_types.dart';
import 'package:baocode/debug/common/debug_utils.dart';
import 'package:baocode/debug/common/repl_model.dart';
import 'package:baocode/debug/service/debug_configuration_manager.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/debug/session/debug_session.dart';
import 'package:baocode/extensions/main_thread/main_thread_context.dart';
import 'package:baocode/extensions/main_thread/main_thread_debug_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../debug/support/fake_debug_adapter.dart';
import '../support/scripted_rpc.dart';

final _folder = VsUri.file('/work/app');
final _program = VsUri.file(fakeProgramPath);

Json _config([Json extra = const {}]) => {
  'type': 'fake',
  'request': 'launch',
  'name': 'From extension',
  'program': r'${workspaceFolder}/main.js',
  ...extra,
};

void main() {
  late ScriptedRpc rpc;
  late MainThreadContext context;
  late RpcActor actor;
  late DebugService service;
  late FakeDebugHost host;
  late Map<int, FakeDebugAdapter> adapters;
  late List<Object> wireErrors;

  Future<Object?> call(String method, [List<Object?> args = const []]) async =>
      actor.invoke(method, args);

  setUp(() async {
    final fixture = await createFakeDebugService();
    service = fixture.service;
    host = fixture.host;
    rpc = ScriptedRpc();
    adapters = {};
    wireErrors = [];
    context = MainThreadContext(
      rpc: rpc.protocol,
      services: {DebugService: service},
    );
    actor = MainThreadDebugService.customer(context);
    rpc.handlers[r'ExtHostDebugService.$substituteVariables'] = (args) =>
        args[1];
    rpc.handlers[r'ExtHostDebugService.$startDASession'] = (args) async {
      final handle = args[0]! as int;
      final adapter = adapters[handle] = FakeDebugAdapter();
      adapter.onMessage((message) {
        unawaited(
          call(r'$acceptDAMessage', [
            handle,
            convertToVSCPaths(message, true),
          ]).catchError((Object error) {
            // A host shutdown rejects already queued adapter replies, as upstream.
            if (!context.isDisposed ||
                error is! StateError ||
                error.message != 'Invalid debug adapter') {
              wireErrors.add(error);
            }
            return null;
          }),
        );
      });
      adapter.onExit(
        (code) => unawaited(call(r'$acceptDAExit', [handle, code, null])),
      );
      await adapter.start();
      // This happens before onDidNewSession, during initialization.
      adapter.event('earlyEvent', {'value': 'initializing'});
      return null;
    };
    rpc.handlers[r'ExtHostDebugService.$sendDAMessage'] = (args) {
      adapters[args[0]]!.send(convertToDAPaths(args[1]! as Json, false));
      return null;
    };
    rpc.handlers[r'ExtHostDebugService.$stopDASession'] = (args) =>
        adapters[args[0]]!.stop();
    await call(r'$registerDebugTypes', [
      <String>['fake'],
    ]);
  });

  tearDown(() async {
    await service.stopSession(null);
    await until(() => service.model.getSessions().isEmpty);
    await pumpEventQueue();
    await context.dispose();
    await pumpEventQueue();
    service.dispose();
    for (final adapter in adapters.values) {
      adapter.dispose();
    }
    rpc.dispose();
    expect(wireErrors, isEmpty);
  });

  Future<DebugSession> start({
    Json extra = const {},
    Json options = const {},
  }) async {
    expect(
      await call(r'$startDebugging', [
        _folder.toJson(),
        _config(extra),
        options,
      ]),
      isTrue,
      reason: host.errors.join('\n'),
    );
    await until(() => service.viewModel.focusedStackFrame != null);
    return service.model.getSessions().single;
  }

  test('configuration provider flags, trigger kinds, resolve phases and unregister', () async {
    final config = _config();
    rpc.replies[r'ExtHostDebugService.$provideDebugConfigurations'] = [config];
    rpc.handlers[r'ExtHostDebugService.$resolveDebugConfiguration'] = (args) =>
        {...args[2]! as Json, 'phase': 1};
    rpc.handlers[r'ExtHostDebugService.$resolveDebugConfigurationWithSubstitutedVariables'] =
        (args) => {...args[2]! as Json, 'phase': 2};
    await call(r'$registerDebugConfigurationProvider', [
      'fake',
      1,
      true,
      true,
      true,
      12,
    ]);
    final manager = service.configurationManager;
    expect(
      await manager.provideDebugConfigurations(
        _folder,
        'fake',
        CancellationToken.none,
      ),
      [config],
    );
    final before =
        (await manager.resolveConfigurationByProviders(
              _folder,
              'fake',
              config,
              CancellationToken.none,
            ))!
            as Json;
    expect(before['phase'], 1);
    final after = await manager
        .resolveDebugConfigurationWithSubstitutedVariables(
          _folder,
          'fake',
          before,
          CancellationToken.none,
        );
    expect((after! as Json)['phase'], 2);
    final args = rpc
        .callsTo(r'ExtHostDebugService.$resolveDebugConfiguration')
        .single;
    expect(args[0], 12);
    expect(VsUri.revive(args[1]! as Json), _folder);
    expect(args.last, isA<CancellationToken>());

    await call(r'$registerDebugConfigurationProvider', [
      'fake',
      2,
      true,
      false,
      false,
      13,
    ]);
    final dynamic = manager.providers.providers.last;
    expect(dynamic.triggerKind, DebugConfigurationProviderTriggerKind.dynamic);
    expect(dynamic.resolveDebugConfiguration, isNull);
    expect(dynamic.resolveDebugConfigurationWithSubstitutedVariables, isNull);
    rpc.calls.clear();
    await manager.provideDebugConfigurations(
      _folder,
      'fake',
      CancellationToken.none,
    );
    expect(
      rpc
          .callsTo(r'ExtHostDebugService.$provideDebugConfigurations')
          .single
          .first,
      12,
    );
    await call(r'$unregisterDebugConfigurationProvider', [12]);
    await call(r'$unregisterDebugConfigurationProvider', [13]);
    expect(manager.providers.providers, isEmpty);
  });

  test('both resolver phases distinguish JSON null from undefined and propagate cancellation', () async {
    await call(r'$registerDebugConfigurationProvider', [
      'fake',
      1,
      false,
      true,
      true,
      8,
    ]);
    final provider = service.configurationManager.providers.providers.single;
    for (final (method, resolve) in [
      (
        r'ExtHostDebugService.$resolveDebugConfiguration',
        provider.resolveDebugConfiguration!,
      ),
      (
        r'ExtHostDebugService.$resolveDebugConfigurationWithSubstitutedVariables',
        provider.resolveDebugConfigurationWithSubstitutedVariables!,
      ),
    ]) {
      rpc.replies[method] = rpcNull;
      expect(
        await resolve(null, _config(), CancellationToken.none),
        same(openLaunchJson),
      );
      rpc.replies[method] = null;
      expect(await resolve(null, _config(), CancellationToken.none), isNull);
      final source = CancellationTokenSource();
      final cancelled = Completer<void>();
      rpc.handlers[method] = (args) async {
        final token = args.last! as CancellationToken;
        await token.whenCancelled;
        cancelled.complete();
        throw const CancellationException();
      };
      final pending = resolve(_folder, _config(), source.token);
      final rejected = expectLater(
        pending,
        throwsA(isA<CancellationException>()),
      );
      await pumpEventQueue();
      source.cancel();
      await cancelled.future;
      await rejected;
      rpc.handlers.remove(method);
    }
  });

  test(
    'descriptor factory gets full then cached session DTO and unregisters',
    () async {
      final session = await start();
      rpc.replies[r'ExtHostDebugService.$provideDebugAdapter'] = {
        'type': 'server',
        'port': 9229,
      };
      await call(r'$registerDebugAdapterDescriptorFactory', ['fake', 20]);
      expect(await service.registry.getDebugAdapterDescriptor(session), {
        'type': 'server',
        'port': 9229,
      });
      final first = rpc
          .callsTo(r'ExtHostDebugService.$provideDebugAdapter')
          .single;
      expect(first.first, 20);
      expect((first.last! as Json)['id'], session.getId());
      await call(r'$sessionCached', [session.getId()]);
      await service.registry.getDebugAdapterDescriptor(session);
      expect(
        rpc.callsTo(r'ExtHostDebugService.$provideDebugAdapter').last.last,
        session.getId(),
      );
      await call(r'$unregisterDebugAdapterDescriptorFactory', [20]);
      expect(await service.registry.getDebugAdapterDescriptor(session), isNull);
    },
  );

  test('source/function breakpoints round-trip, initial delta, and no session-only deltas', () async {
    await call(r'$registerBreakpoints', [
      <Json>[
        {
          'type': 'sourceMulti',
          'uri': _program.toJson(),
          'lines': [
            {
              'id': 'bp1',
              'line': 6,
              'character': 0,
              'enabled': true,
              'condition': 'count > 2',
            },
            {
              'id': 'bp2',
              'line': 8,
              'character': 3,
              'enabled': false,
              'hitCondition': '5',
              'logMessage': '{count}',
            },
          ],
        },
        {
          'type': 'function',
          'id': 'fbp',
          'functionName': 'compute',
          'enabled': true,
        },
      ],
    ]);
    await pumpEventQueue();
    final bps = service.model.getBreakpoints();
    expect(bps.map((bp) => bp.lineNumber), [7, 9]);
    expect(bps.first.column, isNull);
    expect(bps.last.column, 4);
    final added = rpc.callsTo(r'ExtHostDebugService.$acceptBreakpointsDelta');
    expect((added.first.single! as Json).objects('added').first['line'], 6);
    expect(service.model.getFunctionBreakpoints().single.getId(), 'fbp');

    // A newly connected host receives existing breakpoints.
    await context.dispose();
    context = MainThreadContext(
      rpc: rpc.protocol,
      services: {DebugService: service},
    );
    rpc.calls.clear();
    actor = MainThreadDebugService.customer(context);
    await call(r'$registerDebugTypes', [
      <String>['fake'],
    ]);
    await pumpEventQueue();
    expect(
      (rpc
                  .callsTo(r'ExtHostDebugService.$acceptBreakpointsDelta')
                  .single
                  .single!
              as Json)
          .objects('added'),
      hasLength(3),
    );
    rpc.calls.clear();
    final session = await start();
    await pumpEventQueue();
    // Adapter verification is session-only, not an extension breakpoint change.
    expect(
      rpc.callsTo(r'ExtHostDebugService.$acceptBreakpointsDelta'),
      isEmpty,
    );
    expect(
      await call(r'$getDebugProtocolBreakpoint', [session.getId(), 'bp1']),
      containsPair('verified', true),
    );
    await call(r'$unregisterBreakpoints', [
      <String>['bp1', 'bp2'],
      <String>['fbp'],
      <String>[],
    ]);
    await pumpEventQueue();
    expect(service.model.getBreakpoints(), isEmpty);
    expect(service.model.getFunctionBreakpoints(), isEmpty);
    expect(
      rpc.callsTo(r'ExtHostDebugService.$acceptBreakpointsDelta'),
      isNotEmpty,
    );
  });

  test('DAP launch, stopped focus, path conversion, custom events, session cache and console', () async {
    await service.addBreakpoints(_program, [
      const BreakpointData(lineNumber: 7),
    ]);
    rpc.calls.clear();
    final session = await start();
    final id = session.getId();
    final adapter = adapters.values.single;
    expect(
      adapter.commands,
      containsAllInOrder([
        'initialize',
        'launch',
        'setBreakpoints',
        'configurationDone',
        'threads',
        'stackTrace',
      ]),
    );
    expect(adapter.breakpointLines[fakeProgramPath], [7]);
    final sent = rpc
        .callsTo(r'ExtHostDebugService.$sendDAMessage')
        .map((a) => a[1]! as Json);
    final source = sent
        .firstWhere((m) => m['command'] == 'setBreakpoints')
        .obj('arguments')!
        .obj('source')!;
    expect(VsUri.revive(source['path']! as Json), _program);
    expect(service.viewModel.focusedStackFrame!.source.uri, _program);
    expect(
      rpc
          .callsTo(r'ExtHostDebugService.$acceptDebugSessionCustomEvent')
          .first
          .last,
      containsPair('event', 'earlyEvent'),
    );
    expect(
      (rpc
              .callsTo(r'ExtHostDebugService.$acceptDebugSessionStarted')
              .single
              .single!
          as Json)['id'],
      id,
    );
    expect(
      (rpc.callsTo(r'ExtHostDebugService.$acceptStackFrameFocus').last.single!
          as Json)['frameId'],
      1000,
    );

    await call(r'$sessionCached', [id]);
    await call(r'$setDebugSessionName', [id, 'Renamed']);
    await pumpEventQueue();
    expect(
      rpc.callsTo(r'ExtHostDebugService.$acceptDebugSessionNameChanged').single,
      [id, 'Renamed'],
    );
    await call(r'$appendDebugConsole', ['from extension\n']);
    expect(
      session.getReplElements().whereType<ReplOutputElement>().last.severity,
      ReplSeverity.warning,
    );
    expect(
      session.getReplElements().whereType<ReplOutputElement>().last.value,
      'from extension\n',
    );
    expect(
      await call(r'$customDebugAdapterRequest', [
        id,
        'evaluate',
        {'expression': 'count'},
      ]),
      containsPair('result', '3'),
    );
    await expectLater(
      call(r'$customDebugAdapterRequest', [id, 'unknown', {}]),
      throwsA(anything),
    );
    await call(r'$stopDebugging', [id]);
    await pumpEventQueue();
    expect(
      rpc
          .callsTo(r'ExtHostDebugService.$acceptDebugSessionTerminated')
          .single
          .single,
      id,
    );
    expect(rpc.callsTo(r'ExtHostDebugService.$stopDASession'), hasLength(1));
    expect(service.state, DebugState.inactive);
    // Error/exit may arrive after close; a message for a stale handle may not.
    await call(r'$acceptDAError', [1, 'Error', 'late error', null]);
    await call(r'$acceptDAExit', [1, 0, null]);
    await expectLater(
      call(r'$acceptDAMessage', [1, <String, Object?>{}]),
      throwsStateError,
    );
  });

  test(
    'attach stops by disconnect; missing sessions reject instead of hanging',
    () async {
      final session = await start(extra: {'request': 'attach'});
      await call(r'$stopDebugging', [session.getId()]);
      expect(adapters.values.single.commands, contains('disconnect'));
      expect(adapters.values.single.commands, isNot(contains('terminate')));
      for (final (method, args) in [
        (r'$stopDebugging', <Object?>['missing']),
        (r'$customDebugAdapterRequest', <Object?>['missing', 'test', null]),
        (r'$getDebugProtocolBreakpoint', <Object?>['missing', 'bp']),
      ]) {
        await expectLater(
          call(method, args),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'debug session not found',
            ),
          ),
        );
      }
    },
  );

  test(
    'runInTerminal delegates to the extension host, without forcing a pid',
    () async {
      rpc.replies[r'ExtHostDebugService.$runInTerminal'] = 4242;
      expect(
        await service.registry.runInTerminal('fake', {
          'args': ['node'],
        }, 'session'),
        4242,
      );
      expect(rpc.callsTo(r'ExtHostDebugService.$runInTerminal').single, [
        {
          'args': ['node'],
        },
        'session',
      ]);
      rpc.replies[r'ExtHostDebugService.$runInTerminal'] = null;
      expect(
        await service.registry.runInTerminal('fake', {}, 'session'),
        isNull,
      );
    },
  );

  test(
    'host disposal unregisters providers/factories and ends live adapters',
    () async {
      final session = await start();
      await call(r'$registerDebugConfigurationProvider', [
        'fake',
        1,
        true,
        false,
        false,
        1,
      ]);
      await call(r'$registerDebugAdapterDescriptorFactory', ['fake', 2]);
      await context.dispose();
      await until(() => session.state == DebugState.inactive);
      expect(service.configurationManager.providers.providers, isEmpty);
      expect(service.registry.createDebugAdapter(session), isNull);
      expect(await service.registry.getDebugAdapterDescriptor(session), isNull);
      final before = rpc.calls.length;
      await service.addBreakpoints(_program, [
        const BreakpointData(lineNumber: 17),
      ]);
      await pumpEventQueue();
      expect(rpc.calls.length, before);
    },
  );
}
