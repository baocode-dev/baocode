import 'package:baocode/extensions/host/extensions_delta.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _ext(String id, String version) => {
  'identifier': {'value': id},
  'version': version,
  'extensionLocation': {
    'scheme': 'file',
    'path': '/ext/${id.toLowerCase()}-$version',
  },
};

void main() {
  test('new, updated and removed extensions not activated are sent', () {
    final delta = extensionsDelta(
      before: [
        _ext('a.Kept', '1.0.0'),
        _ext('a.old', '1.0.0'),
        _ext('a.gone', '1.0.0'),
      ],
      after: [
        _ext('a.Kept', '1.0.0'),
        _ext('a.old', '2.0.0'),
        _ext('a.new', '1.0.0'),
      ],
      activated: (_) => false,
    );
    expect([for (final e in delta.toRemove) e['version']], ['1.0.0', '1.0.0']);
    expect(
      [for (final e in delta.toRemove) extensionDescriptionKey(e)],
      ['a.old', 'a.gone'],
    );
    expect(
      [for (final e in delta.toAdd) extensionDescriptionKey(e)],
      ['a.old', 'a.new'],
    );
    expect(delta.kept, isEmpty);
    expect(
      [for (final e in delta.running) extensionDescriptionKey(e)],
      ['a.kept', 'a.old', 'a.new'],
    );
  });

  test('an activated extension updated or removed runs on as it was', () {
    final delta = extensionsDelta(
      before: [_ext('a.updated', '1.0.0'), _ext('a.gone', '1.0.0')],
      after: [_ext('a.updated', '2.0.0'), _ext('a.new', '1.0.0')],
      activated: (key) => key != 'a.new',
    );
    expect(delta.toRemove, isEmpty);
    expect(
      [for (final e in delta.toAdd) extensionDescriptionKey(e)],
      ['a.new'],
    );
    expect(delta.kept, {'a.updated', 'a.gone'});
    expect(
      {for (final e in delta.running) extensionDescriptionKey(e): e['version']},
      {'a.new': '1.0.0', 'a.updated': '1.0.0', 'a.gone': '1.0.0'},
    );
  });

  test('the same version from the same folder is no change', () {
    final delta = extensionsDelta(
      before: [_ext('a.same', '1.0.0')],
      after: [_ext('a.same', '1.0.0')],
      activated: (_) => true,
    );
    expect(delta.toAdd, isEmpty);
    expect(delta.toRemove, isEmpty);
    expect(delta.kept, isEmpty);
  });
}
