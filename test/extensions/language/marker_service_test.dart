// Mirrors src/vs/platform/markers/test/common/markerService.test.ts
// (VS Code 1.135.0), plus event merging and resource filters.

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:baocode/extensions/language/marker_service.dart';
import 'package:flutter_test/flutter_test.dart';

var _n = 0;

MarkerData data({
  MarkerSeverity severity = MarkerSeverity.error,
  String? message,
  int startLine = 1,
  int startColumn = 1,
  int endLine = 1,
  int endColumn = 1,
  MarkerCode? code,
  int? modelVersionId,
}) => MarkerData(
  severity: severity,
  message: message ?? 'm${_n++}',
  startLineNumber: startLine,
  startColumn: startColumn,
  endLineNumber: endLine,
  endColumn: endColumn,
  code: code,
  modelVersionId: modelVersionId,
);

void main() {
  late MarkerService service;
  setUp(() => service = MarkerService());
  tearDown(() => service.dispose());

  final fileCs = VsUri.parse('file:///c/test/file.cs');

  test('query', () {
    service.changeAll('far', [ResourceMarker(fileCs, data())]);
    expect(service.read().length, 1);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 1);
    expect(service.read(MarkerReadOptions(resource: fileCs)).length, 1);
    expect(
      service.read(MarkerReadOptions(owner: 'far', resource: fileCs)).length,
      1,
    );

    service.changeAll('boo', [
      ResourceMarker(fileCs, data(severity: MarkerSeverity.warning)),
    ]);
    expect(service.read().length, 2);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 1);
    expect(service.read(const MarkerReadOptions(owner: 'boo')).length, 1);

    int bySeverity(int bits) =>
        service.read(MarkerReadOptions(severities: bits)).length;
    expect(bySeverity(MarkerSeverity.error.value), 1);
    expect(bySeverity(MarkerSeverity.warning.value), 1);
    expect(bySeverity(MarkerSeverity.hint.value), 0);
    expect(bySeverity(MarkerSeverity.error.value | MarkerSeverity.warning.value), 2);
  });

  test('changeOne override', () {
    final uri = VsUri.parse('file:///path/only.cs');
    service.changeOne('far', uri, [data()]);
    expect(service.read().length, 1);
    service.changeOne('boo', uri, [data()]);
    expect(service.read().length, 2);
    service.changeOne('far', uri, [data(), data()]);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 2);
    expect(service.read(const MarkerReadOptions(owner: 'boo')).length, 1);
  });

  test('changeOne/All clears', () {
    final uri = VsUri.parse('file:///path/only.cs');
    service.changeOne('far', uri, [data()]);
    service.changeOne('boo', uri, [data()]);
    expect(service.read().length, 2);
    service.changeOne('far', uri, []);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 0);
    expect(service.read(const MarkerReadOptions(owner: 'boo')).length, 1);
    service.changeAll('boo', []);
    expect(service.read().length, 0);
  });

  test('changeAll sends event for cleared (merged per microtask)', () async {
    final uri = VsUri.parse('file:///d/path');
    service.changeAll('far', [ResourceMarker(uri, data()), ResourceMarker(uri, data())]);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 2);
    await Future<void>.delayed(Duration.zero);

    final events = <List<String>>[];
    var notified = 0;
    service.onMarkerChanged.listen(
      (uris) => events.add([for (final u in uris) '$u']),
    );
    service.addListener(() => notified++);
    service.changeAll('far', []);
    service.changeOne('x', VsUri.parse('file:///e'), [data()]);
    service.changeOne('y', uri, [data()]);
    expect(events, isEmpty); // not yet: merged in a microtask
    await Future<void>.delayed(Duration.zero);
    expect(events, [
      ['file:///d/path', 'file:///e'],
    ]);
    expect(notified, 1);
  });

  test('changeAll merges', () {
    service.changeAll('far', [ResourceMarker(fileCs, data()), ResourceMarker(fileCs, data())]);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 2);
  });

  test('changeAll must not break integrity, issue #12635', () {
    final p1 = VsUri.parse('scheme:path1');
    final p2 = VsUri.parse('scheme:path2');
    service.changeAll('far', [ResourceMarker(p1, data()), ResourceMarker(p2, data())]);
    service.changeAll('boo', [ResourceMarker(p1, data())]);
    service.changeAll('far', [ResourceMarker(p1, data()), ResourceMarker(p2, data())]);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 2);
    expect(service.read(MarkerReadOptions(resource: p1)).length, 2);
  });

  test('invalid marker data', () {
    final uri = VsUri.parse('some:uri/path');
    service.changeOne('far', uri, [data(message: '')]);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 0);
    service.changeOne('far', uri, [data(message: 'null')]);
    expect(service.read(const MarkerReadOptions(owner: 'far')).length, 1);
  });

  test('MapMap#remove returns bad values, #13548', () {
    service.changeOne('o', VsUri.parse('some:uri/1'), [data()]);
    service.changeOne('o', VsUri.parse('some:uri/2'), []);
  });

  test('Error code of zero in markers get removed, #31275', () {
    final uri = VsUri.parse('some:thing');
    service.changeOne('far', uri, [
      data(code: const MarkerCode('0'), startColumn: 2, endColumn: 5),
    ]);
    final markers = service.read(MarkerReadOptions(resource: uri));
    expect(markers.length, 1);
    expect(markers[0].code!.value, '0');
  });

  test('modelVersionId is preserved', () {
    final uri = VsUri.parse('file:///path/file.ts');
    service.changeOne('owner', uri, [data(modelVersionId: 42)]);
    expect(service.read(MarkerReadOptions(resource: uri)).single.modelVersionId, 42);
    service.changeOne('owner', uri, [data()]);
    expect(service.read(MarkerReadOptions(resource: uri)).single.modelVersionId, isNull);
  });

  test('sanitizes positions', () {
    service.changeOne('o', fileCs, [
      data(startLine: 0, startColumn: 0, endLine: -3, endColumn: 0),
    ]);
    final m = service.read().single;
    expect(
      (m.startLineNumber, m.startColumn, m.endLineNumber, m.endColumn),
      (1, 1, 1, 1),
    );
  });

  test('take, remove, statistics', () {
    service.changeOne('o', fileCs, [data(), data(), data(severity: MarkerSeverity.warning)]);
    service.changeOne('o', VsUri.parse('inmemory://m/1'), [data()]);
    expect(service.read(const MarkerReadOptions(take: 2)).length, 2);
    final stats = service.getStatistics();
    expect((stats.errors, stats.warnings), (2, 1));
    service.remove('o', [fileCs]);
    expect(service.read(MarkerReadOptions(resource: fileCs)), isEmpty);
  });

  test('resource filter hides markers for the filtered resource', () {
    final r1 = VsUri.parse('file:///path/file1.cs');
    final r2 = VsUri.parse('file:///path/file2.cs');
    service.changeOne('owner1', r1, [data()]);
    service.changeOne('owner1', r2, [data()]);
    expect(service.read().length, 2);

    final resume = service.installResourceFilter(r1, 'Test filtering');
    final filtered = service.read(MarkerReadOptions(resource: r1));
    expect(filtered.length, 1);
    expect(filtered.single.severity, MarkerSeverity.info);
    expect(filtered.single.message, contains('Test filtering'));
    expect(
      service.read(MarkerReadOptions(resource: r1, ignoreResourceFilters: true)).single.severity,
      MarkerSeverity.error,
    );
    expect(service.read(MarkerReadOptions(resource: r2)).single.severity, MarkerSeverity.error);

    resume();
    expect(service.read(MarkerReadOptions(resource: r1)).single.severity, MarkerSeverity.error);
  });

  test('makeKey', () {
    final key = data(message: 'msg', startLine: 1, startColumn: 2, endLine: 3, endColumn: 4).key;
    expect(key, '¦¦¦Error¦msg¦1¦2¦3¦4¦');
  });
}
