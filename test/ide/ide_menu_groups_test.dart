// Extensions' menu groups merged into the workbench's own, as menus sort
// groups: into the same group, else in order of their ids.

import 'package:baocode/ide/ide_menu.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _labels(List<IdeMenuEntry> entries) => [
  for (final entry in entries)
    switch (entry) {
      IdeMenuAction(:final label) => label,
      IdeMenuSeparator() => '-',
    },
];

IdeMenuGroup _group(String id, List<String> labels) => (
  id: id,
  entries: [for (final label in labels) IdeMenuAction(label)],
);

void main() {
  test('merged by id, inserted by order, the built-in order kept', () {
    final entries = ideMergedMenuGroups(
      [
        _group('navigation', ['Go']),
        _group('1_modification', ['Rename']),
        _group('9_cutcopypaste', ['Copy']),
        _group('z_commands', ['Palette']),
      ],
      [
        _group('navigation', ['Ext Go']),
        _group('5_ext', ['Ext Five']),
        _group('', ['Unnamed']),
        _group('zz', []),
      ],
    );
    expect(_labels(entries), [
      'Go',
      'Ext Go',
      '-',
      'Rename',
      '-',
      'Ext Five',
      '-',
      'Copy',
      '-',
      'Palette',
      '-',
      'Unnamed',
    ]);
  });

  test('a navigation group of extensions comes first', () {
    final entries = ideMergedMenuGroups(
      [
        _group('1_close', ['Close']),
      ],
      [
        _group('navigation', ['Open']),
      ],
    );
    expect(_labels(entries), ['Open', '-', 'Close']);
  });
}
