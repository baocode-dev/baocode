// Document colors from a real extension host: the built-in CSS extension's
// provider finds a color, and its presentations of a picked color (what the
// color picker previews and writes, see ide_editor_colors_test.dart and
// editor_feature_driver_test.dart for the picker and its undo step) come
// back as edits of the color's text.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'package:baocode/extensions/language/language_types.dart';
import 'package:flutter_test/flutter_test.dart';

import '../acceptance/open_vsx_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    "document colors: the CSS extension's colors and presentations",
    () async {
      final w = await OpenVsxWorkspace.create(
        extensionIds: const [],
        files: {'a.css': 'a {\n  color: #0000ff;\n}\n'},
      );
      final file = await w.open('a.css');
      final languages = w.extensions.languageRoot.language;

      final color = await eventually('the colors', () async {
        final colors = await languages.documentColors(file);
        return colors.isEmpty ? null : colors.single;
      });
      expect('${color.range}', '${Range(2, 10, 2, 17)}');
      expect(
        [color.color.red, color.color.green, color.color.blue],
        [0, 0, 1],
      );
      expect(color.color.alpha, 1);

      // The color's own presentations: its text first.
      final own = await languages.colorPresentations(file, color);
      expect(own.map((p) => p.label), contains('#0000ff'));

      // A picked color (the picker's preview): red, at the color's place.
      final picked = await languages.colorPresentations(
        file,
        color,
        preview: const Color(1, 0, 0, 1),
      );
      final labels = [for (final p in picked) p.label];
      expect(labels, containsAll(['#ff0000', 'rgb(255, 0, 0)']));
      final hex = picked.firstWhere((p) => p.label == '#ff0000');
      expect(hex.textEdit?.text, '#ff0000');
      expect('${hex.textEdit?.range}', '${Range(2, 10, 2, 17)}');
      expect(w.unsupported, isEmpty, reason: w.report());
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: openVsxSkip(),
  );
}
