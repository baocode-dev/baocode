/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Testing API's main thread side: the extensions' test controllers,
// the test items they publish (an incremental collection of diffs), their
// run profiles, and the runs with each test's state, messages and output.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/testing/common/testTypes.ts (the DTOs, the diff
// ops, `AbstractIncrementalTestCollection.apply`), testId.ts (ids joined
// with `\0`), testingStates.ts (`statePriority`, `maxPriority`,
// `terminalStatePriorities`), getComputedState.ts (`refreshComputedState`,
// simplified to a full recomputation of the parents), testResult.ts
// (`LiveTestResult`: tasks, test chains, state updates, messages, output,
// completion, `toJSONWithMessages`), testResultService.ts (newest result
// first, `getStateById`), testProfileService.ts (`canUseProfileWithTest`,
// the profiles' order, `getDefaultProfileForTest`) and testServiceImpl.ts
// (`runTests`, `runResolvedTests`: trust, save, one request per
// controller, completion; `cancelTestRun`).
//
// Deviations: no coverage (`$appendCoverage` is kept per task, not shown);
// no continuous runs, follow-ups or related code; results are kept for the
// session only (no persisted results across restarts); a test's output is
// kept as text, not as a terminal buffer with marks.

import 'dart:async';
import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

/// `TestResultState`.
abstract final class TestResultState {
  static const unset = 0;
  static const queued = 1;
  static const running = 2;
  static const passed = 3;
  static const failed = 4;
  static const skipped = 5;
  static const errored = 6;

  static bool isFailed(int state) => state == failed || state == errored;
}

/// `statePriority`.
const Map<int, int> testStatePriority = {
  TestResultState.running: 6,
  TestResultState.errored: 5,
  TestResultState.failed: 4,
  TestResultState.queued: 3,
  TestResultState.passed: 2,
  TestResultState.unset: 0,
  TestResultState.skipped: 1,
};

/// `maxPriority`.
int maxTestStatePriority(Iterable<int> states) {
  var max = TestResultState.unset;
  var first = true;
  for (final state in states) {
    if (first || testStatePriority[max]! < testStatePriority[state]!) {
      max = state;
    }
    first = false;
  }
  return max;
}

/// `terminalStatePriorities`.
const Map<int, int> _terminalStatePriorities = {
  TestResultState.passed: 0,
  TestResultState.skipped: 1,
  TestResultState.failed: 2,
  TestResultState.errored: 3,
};

/// `TestRunProfileBitset`'s groups.
abstract final class TestRunGroup {
  static const run = 1 << 1;
  static const debug = 1 << 2;
  static const coverage = 1 << 3;
}

/// `TestControllerCapability`.
abstract final class TestControllerCapability {
  static const refresh = 1 << 1;
}

/// `TestItemExpandState`.
abstract final class TestItemExpandState {
  static const notExpandable = 0;
  static const expandable = 1;
  static const busyExpanding = 2;
  static const expanded = 3;
}

/// `TestId`: the controller's id, then each item's, joined with `\0`.
abstract final class TestIds {
  static const delimiter = '\u0000';

  static String root(String id) {
    final index = id.indexOf(delimiter);
    return index == -1 ? id : id.substring(0, index);
  }

  static bool isRoot(String id) => !id.contains(delimiter);

  static String? parentId(String id) {
    final index = id.lastIndexOf(delimiter);
    return index == -1 ? null : id.substring(0, index);
  }

  /// The item's own id (the last part).
  static String localId(String id) =>
      id.substring(id.lastIndexOf(delimiter) + 1);

  /// The ids from [id] up to its root, [id] first.
  static Iterable<String> toRoot(String id) sync* {
    String? current = id;
    while (current != null) {
      yield current;
      current = parentId(current);
    }
  }
}

/// An `IRange`: one-based lines and columns.
typedef TestRange = ({
  int startLineNumber,
  int startColumn,
  int endLineNumber,
  int endColumn,
});

TestRange? _range(Object? json) => switch (json) {
  {
    'startLineNumber': final num sl,
    'startColumn': final num sc,
    'endLineNumber': final num el,
    'endColumn': final num ec,
  } =>
    (
      startLineNumber: sl.toInt(),
      startColumn: sc.toInt(),
      endLineNumber: el.toInt(),
      endColumn: ec.toInt(),
    ),
  _ => null,
};

Map<String, Object?>? _rangeJson(TestRange? range) => range == null
    ? null
    : {
        'startLineNumber': range.startLineNumber,
        'startColumn': range.startColumn,
        'endLineNumber': range.endLineNumber,
        'endColumn': range.endColumn,
      };

/// An `IRichLocation`.
typedef TestLocation = ({VsUri uri, TestRange range});

TestLocation? _location(Object? json) {
  if (json is! Map) return null;
  final uri = VsUri.tryRevive(json['uri']);
  final range = _range(json['range']);
  if (uri == null || range == null) return null;
  return (uri: uri, range: range);
}

/// `ITestItem`.
final class TestItem {
  TestItem({
    required this.extId,
    required this.label,
    this.tags = const [],
    this.busy = false,
    this.uri,
    this.range,
    this.description,
    this.error,
    this.sortText,
  });

  factory TestItem.fromJson(Map<String, Object?> json) => TestItem(
    extId: json['extId']! as String,
    label: json['label'] as String? ?? '',
    tags: [...?(json['tags'] as List?)?.cast<String>()],
    busy: json['busy'] == true,
    uri: VsUri.tryRevive(json['uri']),
    range: _range(json['range']),
    description: json['description'] as String?,
    error: _text(json['error']),
    sortText: json['sortText'] as String?,
  );

  final String extId;
  String label;
  List<String> tags;
  bool busy;
  VsUri? uri;
  TestRange? range;
  String? description;
  String? error;
  String? sortText;

  /// `ITestItemUpdate.item`, its fields present when they changed.
  void apply(Map<String, Object?> patch) {
    if (patch.containsKey('label')) label = patch['label'] as String? ?? '';
    if (patch.containsKey('tags')) {
      tags = [...?(patch['tags'] as List?)?.cast<String>()];
    }
    if (patch.containsKey('busy')) busy = patch['busy'] == true;
    if (patch.containsKey('uri')) uri = VsUri.tryRevive(patch['uri']);
    if (patch.containsKey('range')) range = _range(patch['range']);
    if (patch.containsKey('description')) {
      description = patch['description'] as String?;
    }
    if (patch.containsKey('error')) error = _text(patch['error']);
    if (patch.containsKey('sortText')) sortText = patch['sortText'] as String?;
  }

  TestItem copy() => TestItem(
    extId: extId,
    label: label,
    tags: [...tags],
    busy: busy,
    uri: uri,
    range: range,
    description: description,
    error: error,
    sortText: sortText,
  );

  Map<String, Object?> toJson() => {
    'extId': extId,
    'label': label,
    'tags': tags,
    'busy': busy,
    'uri': uri?.toJson(),
    'range': _rangeJson(range),
    'description': description,
    'error': error,
    'sortText': sortText,
  };
}

String? _text(Object? value) => switch (value) {
  final String s => s,
  {'value': final String s} => s,
  _ => null,
};

/// `IncrementalTestCollectionItem`: an item of the collection.
final class TestCollectionItem {
  TestCollectionItem(this.item, this.expand)
    : controllerId = TestIds.root(item.extId);

  final String controllerId;
  final TestItem item;
  int expand;
  final Set<String> children = {};
}

/// `ITestRunProfile`.
final class TestRunProfile {
  TestRunProfile.fromJson(Map<String, Object?> json)
    : controllerId = json['controllerId']! as String,
      profileId = (json['profileId']! as num).toInt(),
      label = json['label'] as String? ?? '',
      group = (json['group'] as num?)?.toInt() ?? TestRunGroup.run,
      isDefault = json['isDefault'] == true,
      tag = json['tag'] as String?,
      hasConfigurationHandler = json['hasConfigurationHandler'] == true,
      supportsContinuousRun = json['supportsContinuousRun'] == true;

  final String controllerId;
  final int profileId;
  String label;
  int group;
  bool isDefault;
  String? tag;
  bool hasConfigurationHandler;
  bool supportsContinuousRun;

  void apply(Map<String, Object?> update) {
    if (update['label'] case final String l) label = l;
    if (update['group'] case final num g) group = g.toInt();
    if (update['isDefault'] case final bool d) isDefault = d;
    if (update.containsKey('tag')) tag = update['tag'] as String?;
    if (update['hasConfigurationHandler'] case final bool h) {
      hasConfigurationHandler = h;
    }
    if (update['supportsContinuousRun'] case final bool c) {
      supportsContinuousRun = c;
    }
  }

  /// `canUseProfileWithTest`.
  bool canRun(TestCollectionItem test) =>
      controllerId == test.controllerId &&
      (TestIds.isRoot(test.item.extId) ||
          tag == null ||
          test.item.tags.contains(tag));
}

/// `ITestMessage`: an error (type 0) or output (type 1).
final class TestMessage {
  TestMessage.fromJson(Map<String, Object?> json)
    : type = (json['type'] as num?)?.toInt() ?? 0,
      message = _text(json['message']) ?? '',
      expected = json['expected'] as String?,
      actual = json['actual'] as String?,
      location = _location(json['location']),
      stackTrace = [
        for (final frame in (json['stackTrace'] as List?) ?? const [])
          if (frame is Map)
            (
              label: '${frame['label'] ?? ''}',
              uri: VsUri.tryRevive(frame['uri']),
              position: switch (frame['position']) {
                {'lineNumber': final num l, 'column': final num c} => (
                  lineNumber: l.toInt(),
                  column: c.toInt(),
                ),
                _ => null,
              },
            ),
      ],
      json = json;

  TestMessage.output(this.message, this.location)
    : type = 1,
      expected = null,
      actual = null,
      stackTrace = const [],
      json = null;

  final int type;
  final String message;
  final String? expected;
  final String? actual;
  final TestLocation? location;
  final List<
    ({String label, VsUri? uri, ({int lineNumber, int column})? position})
  >
  stackTrace;

  /// As the extension host sent it.
  final Map<String, Object?>? json;

  bool get isError => type == 0;

  Map<String, Object?> toJson() =>
      json ??
      {
        'type': type,
        'message': message,
        'offset': 0,
        'length': 0,
        'location': location == null
            ? null
            : {
                'uri': location!.uri.toJson(),
                'range': _rangeJson(location!.range),
              },
      };
}

/// `ITestTaskState`.
final class TestTaskState {
  int state = TestResultState.unset;
  num? duration;
  final List<TestMessage> messages = [];
}

/// `ITestRunTask` with its output.
final class TestRunTask {
  TestRunTask({
    required this.id,
    required this.name,
    required this.ctrlId,
    this.running = true,
  });

  final String id;
  final String? name;
  final String ctrlId;
  bool running;
  final StringBuffer output = StringBuffer();
  final List<Map<String, Object?>> coverage = [];
}

/// `TestResultItem` with its children in the run.
final class TestResultItem {
  TestResultItem(this.controllerId, this.item);

  final String controllerId;
  final TestItem item;
  final List<TestResultItem> children = [];
  final List<TestTaskState> tasks = [];
  int ownComputedState = TestResultState.unset;
  int computedState = TestResultState.unset;
  num? ownDuration;
  bool retired = false;

  /// Every error message of its tasks.
  Iterable<TestMessage> get errors => [
    for (final task in tasks)
      for (final message in task.messages)
        if (message.isError) message,
  ];
}

/// `LiveTestResult`: one run.
final class LiveTestResult extends ChangeNotifier {
  LiveTestResult(this.id, this.request, {this.persist = true});

  final String id;
  final Map<String, Object?> request;
  final bool persist;
  final DateTime startedAt = DateTime.now();
  DateTime? completedAt;
  final List<TestRunTask> tasks = [];
  final Map<String, TestResultItem> _tests = {};
  final Map<int, int> counts = {for (final s in testStatePriority.keys) s: 0};

  /// Output not about one test.
  final List<TestMessage> otherMessages = [];

  final _completed = Completer<void>();

  /// Completes when the run does.
  Future<void> get done => _completed.future;

  bool get isComplete => completedAt != null;
  Iterable<TestResultItem> get tests => _tests.values;
  TestResultItem? getStateById(String extId) => _tests[extId];

  int _taskIndex(String taskId) {
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) throw StateError('Unknown task $taskId in updateState');
    return index;
  }

  void addTask(Map<String, Object?> task) {
    tasks.add(
      TestRunTask(
        id: task['id']! as String,
        name: task['name'] as String?,
        ctrlId: task['ctrlId'] as String? ?? '',
        running: task['running'] != false,
      ),
    );
    for (final test in _tests.values) {
      test.tasks.add(TestTaskState());
    }
    notifyListeners();
  }

  /// `addTestChainToRun`: the first is a root or known; then each child.
  void addTestChainToRun(String controllerId, List<TestItem> chain) {
    if (chain.isEmpty) return;
    var parent =
        _tests[chain.first.extId] ?? _add(controllerId, chain.first, null);
    for (final item in chain.skip(1)) {
      parent = _tests[item.extId] ?? _add(controllerId, item, parent);
    }
    notifyListeners();
  }

  TestResultItem _add(
    String controllerId,
    TestItem item,
    TestResultItem? parent,
  ) {
    final node = TestResultItem(controllerId, item.copy());
    _tests[item.extId] = node;
    counts[TestResultState.unset] = counts[TestResultState.unset]! + 1;
    parent?.children.add(node);
    for (var i = 0; i < tasks.length; i++) {
      node.tasks.add(TestTaskState());
    }
    return node;
  }

  void updateState(String testId, String taskId, int state, num? duration) {
    final entry = _tests[testId];
    if (entry == null) return;
    final index = _taskIndex(taskId);
    final oldTerminal = _terminalStatePriorities[entry.tasks[index].state];
    final newTerminal = _terminalStatePriorities[state];
    // Not from a terminal state back to a lower one (failed to passed).
    if (oldTerminal != null &&
        (newTerminal == null || newTerminal < oldTerminal)) {
      return;
    }
    _setState(entry, index, state, duration);
    notifyListeners();
  }

  void _setState(TestResultItem entry, int index, int state, [num? duration]) {
    entry.tasks[index].state = state;
    if (duration != null) {
      entry.tasks[index].duration = duration;
      entry.ownDuration = (entry.ownDuration ?? 0) > duration
          ? entry.ownDuration
          : duration;
    }
    final own = maxTestStatePriority(entry.tasks.map((t) => t.state));
    if (own == entry.ownComputedState) return;
    counts[entry.ownComputedState] = counts[entry.ownComputedState]! - 1;
    counts[own] = counts[own]! + 1;
    entry.ownComputedState = own;
    _refreshComputed(entry);
  }

  /// `getComputedState` for [entry] and each of its parents.
  void _refreshComputed(TestResultItem entry) {
    for (final id in TestIds.toRoot(entry.item.extId)) {
      final node = _tests[id];
      if (node == null) continue;
      var computed = node.ownComputedState;
      for (final child in node.children) {
        final state = child.computedState;
        computed =
            state == TestResultState.skipped &&
                computed == TestResultState.unset
            ? TestResultState.skipped
            : maxTestStatePriority([computed, state]);
      }
      node.computedState = computed;
    }
  }

  void appendMessage(String testId, String taskId, TestMessage message) {
    final entry = _tests[testId];
    if (entry == null) return;
    entry.tasks[_taskIndex(taskId)].messages.add(message);
    notifyListeners();
  }

  void appendOutput(
    List<int> output,
    String taskId, {
    TestLocation? location,
    String? testId,
  }) {
    final text = utf8.decode(output, allowMalformed: true);
    final index = _taskIndex(taskId);
    tasks[index].output.write(text);
    final preview = text.length > 100 ? '${text.substring(0, 100)}…' : text;
    final message = TestMessage.output(preview, location);
    final test = testId == null ? null : _tests[testId];
    if (test != null) {
      test.tasks[index].messages.add(message);
    } else {
      otherMessages.add(message);
    }
    notifyListeners();
  }

  void markTaskComplete(String taskId) {
    final index = _taskIndex(taskId);
    tasks[index].running = false;
    for (final test in _tests.values) {
      final state = test.tasks[index].state;
      if (state == TestResultState.queued || state == TestResultState.running) {
        _setState(test, index, TestResultState.skipped);
      }
    }
    notifyListeners();
  }

  void markComplete() {
    if (completedAt != null) return;
    for (final task in tasks) {
      if (task.running) markTaskComplete(task.id);
    }
    completedAt = DateTime.now();
    _completed.complete();
    notifyListeners();
  }

  void markRetired(List<String>? testIds) {
    for (final MapEntry(key: id, value: test) in _tests.entries) {
      if (test.retired) continue;
      if (testIds == null ||
          testIds.any(
            (t) => id == t || id.startsWith('$t${TestIds.delimiter}'),
          )) {
        test.retired = true;
      }
    }
    notifyListeners();
  }

  /// `toJSONWithMessages`: the completed run, for `$publishTestResults`.
  Map<String, Object?>? toJson() {
    final completed = completedAt;
    if (completed == null || !persist) return null;
    return {
      'id': id,
      'completedAt': completed.millisecondsSinceEpoch,
      'tasks': [
        for (final t in tasks)
          {
            'id': t.id,
            'name': t.name,
            'ctrlId': t.ctrlId,
            'hasCoverage': t.coverage.isNotEmpty,
          },
      ],
      'name': 'Test run at $startedAt',
      'request': request,
      'items': [
        for (final test in _tests.values)
          {
            'expand': TestItemExpandState.notExpandable,
            'item': test.item.toJson(),
            'ownComputedState': test.ownComputedState,
            'computedState': test.computedState,
            'tasks': [
              for (final task in test.tasks)
                {
                  'state': task.state,
                  'duration': task.duration,
                  'messages': [for (final m in task.messages) m.toJson()],
                },
            ],
          },
      ],
    };
  }
}

/// `IMainThreadTestController`: what the extension host answers for one.
final class TestController {
  TestController({
    required this.id,
    required this.label,
    required this.capabilities,
    required this.runTests,
    required this.expandTest,
    required this.refreshTests,
    required this.configureRunProfile,
  });

  final String id;
  String label;
  int capabilities;

  /// `$runControllerTests`: each request's error, if any.
  final Future<List<String?>> Function(List<Map<String, Object?>> requests)
  runTests;
  final Future<void> Function(String testId, int levels) expandTest;
  final Future<void> Function() refreshTests;
  final Future<void> Function(int profileId) configureRunProfile;
}

/// `ITestService` with the profile and result services.
final class TestService extends ChangeNotifier {
  TestService({this.requestTrust, this.saveAll});

  /// Asks the user to trust the workspace before running tests.
  final Future<bool> Function()? requestTrust;

  /// Saves dirty editors before a run (`testing.saveBeforeTest`).
  final Future<void> Function()? saveAll;

  final Map<String, TestController> _controllers = {};
  final Map<String, TestCollectionItem> _items = {};
  final Map<String, List<TestRunProfile>> _profiles = {};
  final List<LiveTestResult> _results = [];
  final Map<String, Completer<void>> _uiRuns = {};

  /// The extension host's: tell it a run was cancelled.
  void Function(String? runId, String? taskId)? onCancel;

  /// Each completed run, for `$publishTestResults`.
  void Function(LiveTestResult result)? onResultCompleted;

  /// Output the runs append, for the Test Results channel.
  void Function(String text)? onOutput;

  /// Counts what changes, for the views to rebuild.
  int get version => _version;
  int _version = 0;

  void _changed() {
    _version++;
    notifyListeners();
  }

  List<TestController> get controllers => [..._controllers.values];
  TestController? controller(String id) => _controllers[id];

  /// The roots (one per controller), in registration order.
  List<TestCollectionItem> get roots => [
    for (final id in _controllers.keys) ?_items[id],
  ];

  TestCollectionItem? item(String extId) => _items[extId];

  /// [item]'s children, sorted as upstream's tree (`sortText`, else
  /// label).
  List<TestCollectionItem> childrenOf(TestCollectionItem item) {
    final children = [for (final id in item.children) ?_items[id]];
    children.sort((a, b) {
      final ka = a.item.sortText ?? a.item.label;
      final kb = b.item.sortText ?? b.item.label;
      return ka.compareTo(kb);
    });
    return children;
  }

  /// The results, newest first.
  List<LiveTestResult> get results => List.unmodifiable(_results);

  bool get isRunning => _results.any((r) => !r.isComplete);

  // --- controllers -----------------------------------------------------

  void registerController(TestController controller) {
    _controllers[controller.id] = controller;
    _changed();
  }

  void updateController(String id, Map<String, Object?> patch) {
    final controller = _controllers[id];
    if (controller == null) return;
    if (patch['label'] case final String label) controller.label = label;
    if (patch['capabilities'] case final num c) {
      controller.capabilities = c.toInt();
    }
    _changed();
  }

  void unregisterController(String id) {
    if (_controllers.remove(id) == null) return;
    _profiles.remove(id);
    _remove(id);
    _changed();
  }

  // --- the collection --------------------------------------------------

  /// `publishDiff`: `TestsDiffOp`s.
  void publishDiff(List<Map<String, Object?>> diff) {
    for (final op in diff) {
      switch (op['op']) {
        case 0: // Add
          final internal = (op['item']! as Map).cast<String, Object?>();
          final item = TestItem.fromJson(
            (internal['item']! as Map).cast<String, Object?>(),
          );
          final parentId = TestIds.parentId(item.extId);
          final created = TestCollectionItem(
            item,
            (internal['expand'] as num?)?.toInt() ?? 0,
          );
          if (parentId != null) {
            final parent = _items[parentId];
            if (parent == null) continue;
            parent.children.add(item.extId);
          }
          _items[item.extId] = created;
        case 1: // Update
          final update = (op['item']! as Map).cast<String, Object?>();
          final existing = _items[update['extId']];
          if (existing == null) continue;
          if (update['expand'] case final num expand) {
            existing.expand = expand.toInt();
          }
          if (update['item'] case final Map patch) {
            existing.item.apply(patch.cast());
          }
        case 3: // Remove
          _remove(op['itemId']! as String);
        case 5: // Retire
          for (final result in _results) {
            result.markRetired([op['itemId']! as String]);
          }
      }
    }
    _changed();
  }

  void _remove(String itemId) {
    final toRemove = _items[itemId];
    if (toRemove == null) return;
    final parentId = TestIds.parentId(itemId);
    if (parentId != null) _items[parentId]?.children.remove(itemId);
    final queue = [itemId];
    while (queue.isNotEmpty) {
      final existing = _items.remove(queue.removeLast());
      if (existing != null) queue.addAll(existing.children);
    }
  }

  /// `collection.expand`: asks the controller for [extId]'s children.
  Future<void> expand(String extId, int levels) async {
    final item = _items[extId];
    if (item == null ||
        item.expand == TestItemExpandState.notExpandable ||
        item.expand == TestItemExpandState.expanded) {
      return;
    }
    await _controllers[item.controllerId]?.expandTest(extId, levels);
  }

  Future<void> refresh() => Future.wait([
    for (final c in _controllers.values)
      if (c.capabilities & TestControllerCapability.refresh != 0)
        c.refreshTests(),
  ]);

  // --- profiles --------------------------------------------------------

  void addProfile(TestRunProfile profile) {
    if (!_controllers.containsKey(profile.controllerId)) return;
    (_profiles[profile.controllerId] ??= []).add(profile);
    _changed();
  }

  void updateProfile(
    String controllerId,
    int profileId,
    Map<String, Object?> update,
  ) {
    for (final p in _profiles[controllerId] ?? const <TestRunProfile>[]) {
      if (p.profileId == profileId) p.apply(update);
    }
    _changed();
  }

  void removeProfile(String controllerId, int profileId) {
    _profiles[controllerId]?.removeWhere((p) => p.profileId == profileId);
    _changed();
  }

  /// `getControllerProfiles`: defaults first, then by label.
  List<TestRunProfile> profilesOf(String controllerId) =>
      [...?_profiles[controllerId]]..sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.label.compareTo(b.label);
      });

  /// Whether any controller can run tests in [group].
  bool hasGroup(int group) => _profiles.values.any(
    (profiles) => profiles.any((p) => p.group & group != 0),
  );

  /// The default profiles' ids by controller, for `$setDefaultRunProfiles`.
  Map<String, List<num>> defaultProfiles() => {
    for (final MapEntry(key: id, value: profiles) in _profiles.entries)
      id: [
        for (final p in profiles)
          if (p.isDefault) p.profileId,
      ],
  };

  // --- results ---------------------------------------------------------

  int _runCounter = 0;

  /// `createLiveResult`: a run the extension started (with its id) or the
  /// view did.
  LiveTestResult createLiveResult(Map<String, Object?> request) {
    final id = request['id'] as String? ?? 'bao-run-${++_runCounter}';
    final result = LiveTestResult(
      id,
      request,
      persist: request['persist'] != false,
    );
    result.addListener(_changed);
    unawaited(
      result.done.then((_) {
        onResultCompleted?.call(result);
        _changed();
      }),
    );
    _results.insert(0, result);
    // `RETAIN_MAX_RESULTS`.
    while (_results.length > 128) {
      _results.removeLast().removeListener(_changed);
    }
    _changed();
    return result;
  }

  LiveTestResult? result(String id) {
    for (final result in _results) {
      if (result.id == id) return result;
    }
    return null;
  }

  /// `getStateById`: the newest result that has [extId].
  (LiveTestResult, TestResultItem)? stateOf(String extId) {
    for (final result in _results) {
      if (result.getStateById(extId) case final item?) return (result, item);
    }
    return null;
  }

  /// The newest run's failures with a location, in the tree's order.
  List<(TestResultItem, TestMessage)> failures() {
    final out = <(TestResultItem, TestMessage)>[];
    final result = _results.firstOrNull;
    if (result == null) return out;
    for (final test in result.tests) {
      if (!TestResultState.isFailed(test.ownComputedState)) continue;
      for (final message in test.errors) {
        out.add((test, message));
      }
    }
    return out;
  }

  // --- runs ------------------------------------------------------------

  /// `runTests`: [extIds] in [group] with each controller's default
  /// profile that can run them (else any of its profiles in the group).
  Future<LiveTestResult?> runTests(int group, List<String> extIds) {
    final tests = [for (final id in extIds) ?_items[id]];
    final targets = <({TestRunProfile profile, List<String> testIds})>[];
    for (final test in tests) {
      final existing = targets
          .where((t) => t.profile.canRun(test) && t.profile.group & group != 0)
          .firstOrNull;
      if (existing != null) {
        existing.testIds.add(test.item.extId);
        continue;
      }
      final profiles = profilesOf(test.controllerId)
          .where((p) => p.group & group != 0 && p.canRun(test))
          .toList();
      final best =
          profiles.where((p) => p.isDefault).firstOrNull ??
          profiles.firstOrNull;
      if (best == null) continue;
      targets.add((profile: best, testIds: [test.item.extId]));
    }
    if (targets.isEmpty) return Future.value();
    return runResolvedTests({
      'group': group,
      'targets': [
        for (final t in targets)
          {
            'testIds': t.testIds,
            'controllerId': t.profile.controllerId,
            'profileId': t.profile.profileId,
          },
      ],
      'exclude': <String>[],
    });
  }

  /// Every root with the run (debug) group.
  Future<LiveTestResult?> runAll(int group) =>
      runTests(group, [for (final r in roots) r.item.extId]);

  /// `runResolvedTests`.
  Future<LiveTestResult> runResolvedTests(Map<String, Object?> request) async {
    final result = createLiveResult(request);
    final trusted = await (requestTrust?.call() ?? Future.value(true));
    if (!trusted) {
      result.markComplete();
      return result;
    }
    final cancel = Completer<void>();
    _uiRuns[result.id] = cancel;
    try {
      final targets = [
        for (final t in (request['targets']! as List).cast<Map>())
          t.cast<String, Object?>(),
      ];
      final exclude = [...?(request['exclude'] as List?)?.cast<String>()];
      final byController = <String, List<Map<String, Object?>>>{};
      for (final target in targets) {
        (byController[target['controllerId']! as String] ??= []).add(target);
      }
      await saveAll?.call();
      final errors = <String>[];
      await Future.wait([
        for (final MapEntry(key: id, value: group) in byController.entries)
          if (_controllers[id] case final controller?)
            controller
                .runTests([
                  for (final target in group)
                    {
                      'runId': result.id,
                      'excludeExtIds': [
                        for (final e in exclude)
                          if (!(target['testIds']! as List).contains(e)) e,
                      ],
                      'profileId': target['profileId'],
                      'controllerId': id,
                      'testIds': target['testIds'],
                    },
                ])
                .then((errs) => errors.addAll(errs.nonNulls))
                .catchError((Object e) => errors.add('$e')),
      ]);
      if (errors.isNotEmpty) {
        onOutput?.call(
          'An error occurred attempting to run tests: ${errors.join(' ')}\n',
        );
      }
      return result;
    } finally {
      _uiRuns.remove(result.id);
      result.markComplete();
    }
  }

  /// `cancelTestRun`: [runId]'s, or every run.
  void cancel([String? runId]) {
    if (runId == null) {
      for (final result in _results.where((r) => !r.isComplete)) {
        onCancel?.call(result.id, null);
      }
      return;
    }
    onCancel?.call(runId, null);
  }

  /// Every controller and item gone (the extension host ended).
  void clear() {
    _controllers.clear();
    _items.clear();
    _profiles.clear();
    for (final result in _results) {
      if (!result.isComplete) result.markComplete();
    }
    _changed();
  }
}
