/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The extensions' test controllers, items, profiles and runs, into the
// workspace's [TestService]; runs, expansion, refresh, cancellation and
// the default profiles go back to the extension host.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadTesting.ts.
//
// Deviations: `$subscribeToDiffs` sends the collection as it is (no
// reviver diff of persisted items); coverage is kept, never asked for in
// detail (`$getCoverageDetails` answers none); test follow-ups and related
// code are not offered.

import 'dart:async';
import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';

import '../testing/test_service.dart';
import 'main_thread_context.dart';

final class MainThreadTesting extends MainThreadTestingUnsupported {
  MainThreadTesting(this._service, this._proxy) {
    _service.onCancel = (runId, taskId) => unawaited(
      _proxy.$cancelExtensionTestRun(runId, taskId).catchError((Object _) {}),
    );
    _service.onResultCompleted = (result) {
      if (result.toJson() case final json?) {
        unawaited(_proxy.$publishTestResults([json]).catchError((Object _) {}));
      }
    };
    _service.addListener(_profilesChanged);
  }

  final TestService _service;
  final ExtHostTestingProxy _proxy;
  final Set<String> _controllers = {};
  bool _subscribed = false;
  String _lastDefaults = '';

  static RpcActor customer(MainThreadContext context) {
    final main = MainThreadTesting(
      context.service<TestService>(),
      ExtHostTestingProxy(context.rpc),
    );
    context.onDispose(main.dispose);
    return MainThreadTestingActor(main);
  }

  void dispose() {
    _service.removeListener(_profilesChanged);
    for (final id in _controllers) {
      _service.unregisterController(id);
    }
    _controllers.clear();
    _service
      ..onCancel = null
      ..onResultCompleted = null;
  }

  /// `$setDefaultRunProfiles` as the profiles change.
  void _profilesChanged() {
    final defaults = _service.defaultProfiles();
    final key = jsonEncode(defaults);
    if (key == _lastDefaults) return;
    _lastDefaults = key;
    unawaited(
      _proxy.$setDefaultRunProfiles(defaults).catchError((Object _) {}),
    );
  }

  @override
  void $registerTestController(
    String controllerId,
    String label,
    int capability,
  ) {
    _controllers.add(controllerId);
    _service.registerController(
      TestController(
        id: controllerId,
        label: label,
        capabilities: capability,
        runTests: (requests) async => [
          for (final r in await _proxy.$runControllerTests(requests))
            r['error'] as String?,
        ],
        expandTest: (testId, levels) => _proxy.$expandTest(testId, levels),
        refreshTests: () => _proxy.$refreshTests(controllerId),
        configureRunProfile: (id) =>
            _proxy.$configureRunProfile(controllerId, id),
      ),
    );
  }

  @override
  void $updateController(String controllerId, Map<String, Object?> patch) =>
      _service.updateController(controllerId, patch);

  @override
  void $unregisterTestController(String controllerId) {
    _controllers.remove(controllerId);
    _service.unregisterController(controllerId);
  }

  @override
  void $subscribeToDiffs() {
    if (_subscribed) return;
    _subscribed = true;
    // The collection as Add ops, parents first.
    final ops = <Map<String, Object?>>[];
    void add(TestCollectionItem item) {
      ops.add({
        'op': 0,
        'item': {'expand': item.expand, 'item': item.item.toJson()},
      });
      for (final child in _service.childrenOf(item)) {
        add(child);
      }
    }

    for (final root in _service.roots) {
      add(root);
    }
    unawaited(_proxy.$acceptDiff(ops).catchError((Object _) {}));
  }

  @override
  void $unsubscribeFromDiffs() => _subscribed = false;

  @override
  void $publishDiff(String controllerId, List<Map<String, Object?>> diff) {
    _service.publishDiff(diff);
    if (_subscribed) {
      unawaited(_proxy.$acceptDiff(diff).catchError((Object _) {}));
    }
  }

  @override
  Future<List<Map<String, Object?>>> $getCoverageDetails(
    String resultId,
    num taskIndex,
    VsUri uri,
    CancellationToken token,
  ) async => const [];

  @override
  void $publishTestRunProfile(Map<String, Object?> config) =>
      _service.addProfile(TestRunProfile.fromJson(config));

  @override
  void $updateTestRunConfig(
    String controllerId,
    num configId,
    Map<String, Object?> update,
  ) => _service.updateProfile(controllerId, configId.toInt(), update);

  @override
  void $removeTestProfile(String controllerId, num configId) =>
      _service.removeProfile(controllerId, configId.toInt());

  @override
  Future<String> $runTests(
    Map<String, Object?> req,
    CancellationToken token,
  ) async => (await _service.runResolvedTests(req)).id;

  @override
  void $addTestsToRun(
    String controllerId,
    String runId,
    List<Map<String, Object?>> tests,
  ) => _service.result(runId)?.addTestChainToRun(controllerId, [
    for (final t in tests) TestItem.fromJson(t),
  ]);

  @override
  void $updateTestStateInRun(
    String runId,
    String taskId,
    String testId,
    int state,
    num? duration,
  ) => _service.result(runId)?.updateState(testId, taskId, state, duration);

  @override
  void $appendTestMessagesInRun(
    String runId,
    String taskId,
    String testId,
    List<Map<String, Object?>> messages,
  ) {
    final result = _service.result(runId);
    if (result == null) return;
    for (final message in messages) {
      result.appendMessage(testId, taskId, TestMessage.fromJson(message));
    }
  }

  @override
  void $appendOutputToRun(
    String runId,
    String taskId,
    RpcBuffer output,
    Map<String, Object?>? location,
    String? testId,
  ) {
    final result = _service.result(runId);
    if (result == null) return;
    final uri = VsUri.tryRevive(location?['uri']);
    final range = location?['range'];
    result.appendOutput(
      output.bytes,
      taskId,
      location: uri == null || range is! Map
          ? null
          : (
              uri: uri,
              range: (
                startLineNumber: (range['startLineNumber']! as num).toInt(),
                startColumn: (range['startColumn']! as num).toInt(),
                endLineNumber: (range['endLineNumber']! as num).toInt(),
                endColumn: (range['endColumn']! as num).toInt(),
              ),
            ),
      testId: testId,
    );
    _service.onOutput?.call(utf8.decode(output.bytes, allowMalformed: true));
  }

  @override
  void $appendCoverage(
    String runId,
    String taskId,
    Map<String, Object?> coverage,
  ) {
    final result = _service.result(runId);
    for (final task in result?.tasks ?? const <TestRunTask>[]) {
      if (task.id == taskId) task.coverage.add(coverage);
    }
  }

  @override
  void $startedTestRunTask(String runId, Map<String, Object?> task) =>
      _service.result(runId)?.addTask(task);

  @override
  void $finishedTestRunTask(String runId, String taskId) =>
      _service.result(runId)?.markTaskComplete(taskId);

  @override
  void $startedExtensionTestRun(Map<String, Object?> req) =>
      _service.createLiveResult(req);

  @override
  void $finishedExtensionTestRun(String runId) =>
      _service.result(runId)?.markComplete();

  @override
  void $markTestRetired(List<String>? testIds) {
    for (final result in _service.results) {
      if (!result.isComplete) result.markRetired(testIds);
    }
  }
}
