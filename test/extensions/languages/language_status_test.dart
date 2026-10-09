// Language status items: an `ILanguageStatus` as `$setLanguageStatus`
// sends it, matched by its selector to a document, ordered most severe
// first, then by source and id; a handle's update replaces its item.

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/languages/language_status.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _dto(
  String id, {
  Object? selector = 'python',
  int severity = LanguageStatusSeverity.info,
  String source = 'Python',
  String label = '3.12',
  bool busy = false,
}) => {
  'id': id,
  'name': 'Interpreter',
  'source': source,
  'selector': selector,
  'label': label,
  'detail': 'venv',
  'severity': severity,
  'busy': busy,
  'command': {'id': 'python.setInterpreter', 'title': 'Select'},
};

void main() {
  test('matching, order and updates', () {
    final service = LanguageStatusService();
    addTearDown(service.dispose);
    var changes = 0;
    service.addListener(() => changes++);
    service
      ..setStatus(1, LanguageStatus.fromJson(_dto('py/b')))
      ..setStatus(
        2,
        LanguageStatus.fromJson(
          _dto('py/a', severity: LanguageStatusSeverity.error),
        ),
      )
      ..setStatus(
        3,
        LanguageStatus.fromJson(
          _dto(
            'any/c',
            selector: [
              {'language': 'python', 'scheme': 'file'},
            ],
            source: 'Aaa',
          ),
        ),
      )
      ..setStatus(
        4,
        LanguageStatus.fromJson(_dto('ts/v', selector: 'typescript')),
      );
    final file = VsUri.file('/w/main.py');
    expect(service.forDocument(file, 'python').map((s) => s.id), [
      'py/a',
      'any/c',
      'py/b',
    ]);
    expect(service.forDocument(file, 'typescript').map((s) => s.id), ['ts/v']);

    service.setStatus(
      1,
      LanguageStatus.fromJson(_dto('py/b', label: 'loading', busy: true)),
    );
    final updated = service
        .forDocument(file, 'python')
        .firstWhere((s) => s.id == 'py/b');
    expect(updated.text, r'loading $(loading~spin)');
    expect(updated.command?['id'], 'python.setInterpreter');
    service.removeStatus(2);
    expect(service.forDocument(file, 'python').map((s) => s.id), [
      'any/c',
      'py/b',
    ]);
    expect(changes, 6);
  });
}
