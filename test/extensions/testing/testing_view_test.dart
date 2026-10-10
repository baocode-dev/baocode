// The Testing view over a TestService fed as the extension host feeds it:
// the collection from diffs, a run through the controller with the default
// profile, each test's state and the parents' computed one, a failure's
// message under its test going to its location, Go to Next Failure, and a
// result that never goes from failed back to passed.

import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/testing/test_service.dart';
import 'package:baocode/extensions/testing/testing_view.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _d = TestIds.delimiter;

Map<String, Object?> _add(String extId, {int expand = 0, int? line}) => {
  'op': 0,
  'item': {
    'expand': expand,
    'item': {
      'extId': extId,
      'label': TestIds.localId(extId),
      'tags': <String>[],
      'busy': false,
      'uri': VsUri.file('/w/a.test.js').toJson(),
      'range': line == null
          ? null
          : {
              'startLineNumber': line,
              'startColumn': 1,
              'endLineNumber': line,
              'endColumn': 10,
            },
      'description': null,
      'error': null,
      'sortText': null,
    },
  },
};

void main() {
  late TestService service;
  late List<List<Map<String, Object?>>> requests;

  setUp(() {
    requests = [];
    service = TestService();
    service.registerController(
      TestController(
        id: 'ctrl',
        label: 'Ctrl',
        capabilities: TestControllerCapability.refresh,
        runTests: (reqs) async {
          requests.add(reqs);
          final runId = reqs.single['runId']! as String;
          final run = service.result(runId)!;
          run
            ..addTask({
              'id': 't',
              'name': null,
              'running': true,
              'ctrlId': 'ctrl',
            })
            ..addTestChainToRun('ctrl', [
              TestItem(extId: 'ctrl', label: 'Ctrl'),
              TestItem(extId: 'ctrl${_d}suite', label: 'suite'),
              TestItem(extId: 'ctrl${_d}suite${_d}a', label: 'a'),
            ])
            ..addTestChainToRun('ctrl', [
              TestItem(extId: 'ctrl${_d}suite', label: 'suite'),
              TestItem(extId: 'ctrl${_d}suite${_d}b', label: 'b'),
            ])
            ..updateState(
              'ctrl${_d}suite${_d}a',
              't',
              TestResultState.passed,
              5,
            )
            ..updateState(
              'ctrl${_d}suite${_d}b',
              't',
              TestResultState.failed,
              7,
            )
            // Not back from failed to passed.
            ..updateState(
              'ctrl${_d}suite${_d}b',
              't',
              TestResultState.passed,
              7,
            )
            ..appendMessage(
              'ctrl${_d}suite${_d}b',
              't',
              TestMessage.fromJson({
                'type': 0,
                'message': 'expected 1\nmore',
                'expected': '1',
                'actual': '2',
                'location': {
                  'uri': VsUri.file('/w/a.test.js').toJson(),
                  'range': {
                    'startLineNumber': 4,
                    'startColumn': 3,
                    'endLineNumber': 4,
                    'endColumn': 3,
                  },
                },
              }),
            )
            ..appendOutput(utf8.encode('log line\n'), 't');
          return [null];
        },
        expandTest: (id, levels) async {},
        refreshTests: () async {},
        configureRunProfile: (_) async {},
      ),
    );
    service
      ..publishDiff([
        _add('ctrl', expand: 3),
        _add('ctrl${_d}suite', expand: 3, line: 1),
        _add('ctrl${_d}suite${_d}b', line: 3),
        _add('ctrl${_d}suite${_d}a', line: 2),
      ])
      ..addProfile(
        TestRunProfile.fromJson({
          'controllerId': 'ctrl',
          'profileId': 1,
          'label': 'Run',
          'group': TestRunGroup.run,
          'isDefault': true,
          'tag': null,
          'hasConfigurationHandler': false,
          'supportsContinuousRun': false,
        }),
      );
  });

  tearDown(() => service.dispose());

  test('the collection from diffs; updates and removals', () {
    final suite = service.item('ctrl${_d}suite')!;
    expect(service.childrenOf(suite).map((c) => c.item.label), ['a', 'b']);
    service.publishDiff([
      {
        'op': 1,
        'item': {
          'extId': 'ctrl${_d}suite${_d}a',
          'item': {'label': 'renamed', 'busy': true},
        },
      },
      {'op': 3, 'itemId': 'ctrl${_d}suite${_d}b'},
    ]);
    expect(service.childrenOf(suite).map((c) => c.item.label), ['renamed']);
    expect(service.item('ctrl${_d}suite${_d}a')!.item.busy, isTrue);
    service.unregisterController('ctrl');
    expect(service.item('ctrl${_d}suite'), isNull);
    expect(service.roots, isEmpty);
  });

  testWidgets('a run: states, a failure under its test that opens its '
      'location, Go to Next Failure', (tester) async {
    final opened = <(String, int?)>[];
    final key = GlobalKey<TestingViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TestingView(
            key: key,
            service: service,
            session: TestingViewSession(),
            onOpen: (uri, range) =>
                opened.add((uri.path, range?.startLineNumber)),
          ),
        ),
      ),
    );
    // One controller: its children are the top.
    expect(find.text('suite'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('Ctrl'), findsNothing);

    await tester.runAsync(() => service.runAll(TestRunGroup.run));
    await tester.pump();
    expect(requests.single.single['testIds'], ['ctrl']);
    expect(requests.single.single['profileId'], 1);
    final result = service.results.first;
    expect(result.isComplete, isTrue);
    expect(
      result.getStateById('ctrl${_d}suite${_d}b')!.ownComputedState,
      TestResultState.failed,
    );
    expect(
      result.getStateById('ctrl${_d}suite')!.computedState,
      TestResultState.failed,
    );
    expect(result.counts[TestResultState.passed], 1);
    expect(find.text('1/2 tests passed (0ms)'), findsNothing);
    expect(find.textContaining('1/2 tests passed'), findsOneWidget);
    // The suite shows its children's worst state.
    expect(
      find.byWidgetPredicate((w) => w is Icon && w.icon == Codicons.error),
      findsWidgets,
    );

    // A click on the failed test shows its message; the message goes to
    // the failure.
    await tester.tap(find.text('b'));
    await tester.pump();
    expect(find.text('expected 1'), findsOneWidget);
    await tester.tap(find.text('expected 1'));
    await tester.pump();
    expect(opened.last, ('/w/a.test.js', 4));

    key.currentState!.goToNextFailure();
    expect(opened.last, ('/w/a.test.js', 4));
    expect(result.tasks.single.output.toString(), 'log line\n');
  });
}
