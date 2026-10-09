// Problem matchers on lines: the built-in multi-line `$eslint-stylish`, a
// contributed pattern by name, `base` with overrides, and a background
// matcher's begin and end with its problems; each into the markers.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/language/marker_service.dart';
import 'package:baocode/extensions/tasks/problem_collectors.dart';
import 'package:baocode/extensions/tasks/problem_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProblemPatternRegistry patterns;
  late ProblemMatcherRegistry matchers;
  late MarkerService markers;

  setUp(() {
    patterns = ProblemPatternRegistry();
    matchers = ProblemMatcherRegistry(patterns);
    markers = MarkerService();
  });

  Future<void> feed(
    AbstractProblemCollector collector,
    List<String> lines,
  ) async {
    for (final line in lines) {
      collector.processLine(line);
    }
    await collector.idle;
  }

  test(r'$eslint-stylish: the file line, then its problems', () async {
    final collector = StartStopProblemCollector([
      matchers.get('eslint-stylish')!,
    ], markers);
    await feed(collector, [
      '/w/src/a.js',
      '  3:10  error    Unexpected var  no-var',
      '  5:1   warning  Missing semicolon  semi',
      '',
    ]);
    collector.done();
    await collector.idle;
    final found = markers.read(const MarkerReadOptions(owner: 'eslint'));
    expect(
      found.map(
        (m) => (m.resource.path, m.startLineNumber, m.startColumn, m.severity),
      ),
      [
        ('/w/src/a.js', 3, 10, MarkerSeverity.error),
        ('/w/src/a.js', 5, 1, MarkerSeverity.warning),
      ],
    );
    expect(found.first.message, 'Unexpected var');
    expect(found.first.code?.value, 'no-var');
    expect(collector.numberOfMatches, 2);
    expect(collector.maxMarkerSeverity, MarkerSeverity.error);
  });

  test('a contributed pattern by name and a matcher based on another, '
      'with its owner and file location', () async {
    final errors = <String>[];
    patterns.setContributions([
      {
        'name': 'mine',
        'regexp': r'^(\S+)\((\d+)\): (.*)$',
        'file': 1,
        'line': 2,
        'message': 3,
      },
    ], errors: errors);
    matchers.setContributions([
      {
        'name': 'mine',
        'owner': 'mine',
        'fileLocation': ['absolute'],
        'severity': 'warning',
        'pattern': r'$mine',
      },
    ], errors: errors);
    expect(errors, isEmpty);
    final parsed = ProblemMatcherParser(
      ProblemReporter(),
      patterns,
      matchers,
    ).parse({'base': r'$mine', 'owner': 'other'})!;
    final collector = StartStopProblemCollector([parsed], markers);
    await feed(collector, ['/x/b.txt(4): not good', 'noise']);
    collector.done();
    await collector.idle;
    final found = markers.read(const MarkerReadOptions(owner: 'other'));
    expect(found.single.resource, VsUri.file('/x/b.txt'));
    expect(found.single.startLineNumber, 4);
    expect(found.single.severity, MarkerSeverity.warning);
    expect(found.single.message, 'not good');
  });

  test('background: begin and end patterns change its state; problems '
      'between them are delivered', () async {
    final parsed = ProblemMatcherParser(ProblemReporter(), patterns, matchers)
        .parse({
          'owner': 'watch',
          'fileLocation': 'absolute',
          'pattern': {
            'regexp': r'^(.*):(\d+): (error): (.*)$',
            'file': 1,
            'line': 2,
            'severity': 3,
            'message': 4,
          },
          'background': {
            'activeByDefault': false,
            'beginsPattern': '^Starting',
            'endsPattern': '^Finished',
          },
        })!;
    final collector = WatchingProblemCollector([parsed], markers);
    final states = <String>[];
    final subscription = collector.onDidStateChange.listen(
      (e) => states.add(e.kind.name),
    );
    addTearDown(subscription.cancel);
    collector.aboutToStart();
    await feed(collector, [
      'Starting build',
      '/c/d.ts:9: error: broken',
      'Finished',
    ]);
    expect(states, ['backgroundProcessingBegins', 'backgroundProcessingEnds']);
    final found = markers.read(const MarkerReadOptions(owner: 'watch'));
    expect(found.single.resource, VsUri.file('/c/d.ts'));
    expect(found.single.message, 'broken');
    collector.dispose();
  });
}
