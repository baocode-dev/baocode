import 'package:baocode/extensions/commands/builtin_commands.dart';
import 'package:baocode/extensions/commands/command_contributions.dart';
import 'package:baocode/extensions/contextkey/context_key_service.dart';
import 'package:baocode/extensions/views/views_service.dart';
import 'package:flutter_test/flutter_test.dart';

ExtensionSource _extension(List<Map<String, Object?>> views) =>
    ExtensionSource.fromDescription({
      'identifier': {'value': 'acme.git'},
      'name': 'git',
      'publisher': 'acme',
      'contributes': {
        'viewsContainers': {
          'activitybar': [
            {'id': 'acme', 'title': 'Acme', 'icon': 'media/acme.svg'},
          ],
        },
        'views': {'acme': views},
      },
    });

void main() {
  late BuiltinCommands builtins;
  late ExtensionViewsService views;
  final opened = <(String, bool)>[];

  setUp(() {
    opened.clear();
    builtins = BuiltinCommands();
    views = ExtensionViewsService(commands: builtins)
      ..opener = (id, {required focus}) async => opened.add((id, focus));
  });

  tearDown(() {
    views.dispose();
    builtins.dispose();
  });

  test('each view has <viewId>.focus, gone with the view', () async {
    views.setExtensions([
      _extension([
        {'id': 'acme.commits', 'name': 'Commits'},
        {'id': 'acme.graph', 'name': 'Graph', 'type': 'webview'},
      ]),
    ]);

    await builtins.lookup('acme.commits.focus')!(const []);
    await builtins.lookup('acme.graph.focus')!(const [
      {'preserveFocus': true},
    ]);
    expect(opened, [('acme.commits', true), ('acme.graph', false)]);

    // In the palette under the container's title, while its `when` holds.
    final context = ContextKeyService();
    addTearDown(context.dispose);
    expect(views.focusCommands(context), [
      (
        id: 'acme.commits.focus',
        title: 'Focus on Commits View',
        category: 'Acme',
      ),
      (id: 'acme.graph.focus', title: 'Focus on Graph View', category: 'Acme'),
    ]);

    views.setExtensions([
      _extension([
        {'id': 'acme.commits', 'name': 'Commits', 'when': 'acme.on'},
      ]),
    ]);
    expect(builtins.has('acme.graph.focus'), isFalse);
    expect(builtins.has('acme.commits.focus'), isTrue);
    expect(views.focusCommands(context), isEmpty);

    views.dispose();
    expect(builtins.has('acme.commits.focus'), isFalse);
    views = ExtensionViewsService(commands: builtins);
  });
}
