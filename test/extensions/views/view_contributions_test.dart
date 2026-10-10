// `contributes.viewsContainers`, `views` and `viewsWelcome` as the
// workbench reads them (viewsExtensionPoint.ts, viewsWelcomeContribution.ts).

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/commands/command_contributions.dart';
import 'package:baocode/extensions/views/view_contributions.dart';
import 'package:flutter_test/flutter_test.dart';

ExtensionSource _extension(
  String id,
  Map<String, Object?> contributes, {
  List<String> proposals = const [],
}) => ExtensionSource.fromDescription({
  'identifier': {'value': id},
  'name': id.split('.').last,
  'publisher': id.split('.').first,
  'extensionLocation': VsUri.file('/ext/$id').toJson(),
  'enabledApiProposals': proposals,
  'contributes': contributes,
});

void main() {
  test('an activity bar container with its views, in order', () {
    final contributions = ViewContributions([
      _extension('acme.deps', {
        'viewsContainers': {
          'activitybar': [
            {'id': 'deps', 'title': 'Dependencies', 'icon': r'$(package)'},
            {'id': 'more', 'title': 'More', 'icon': 'media/more.svg'},
          ],
          'panel': [
            {'id': 'logs', 'title': 'Logs', 'icon': r'$(output)'},
          ],
        },
        'views': {
          'deps': [
            {'id': 'deps.tree', 'name': 'Tree', 'when': 'acme.ready'},
            {'id': 'deps.list', 'name': 'List', 'visibility': 'collapsed'},
          ],
          'logs': [
            {'id': 'logs.view', 'name': 'Log', 'type': 'webview'},
          ],
        },
      }),
    ]);
    expect([for (final c in contributions.containers) c.id], [
      'workbench.view.extension.deps',
      'workbench.view.extension.more',
      'workbench.view.extension.logs',
    ]);
    final deps = contributions.container('workbench.view.extension.deps')!;
    expect(deps.title, 'Dependencies');
    expect(deps.icon, const ThemeIconRef('package'));
    expect(deps.location, ViewContainerLocation.sidebar);
    final more = contributions.container('workbench.view.extension.more')!;
    expect((more.icon! as ImageIcon).dark.path, '/ext/acme.deps/media/more.svg');
    expect(
      contributions.container('workbench.view.extension.logs')!.location,
      ViewContainerLocation.panel,
    );

    final views = contributions.viewsIn('workbench.view.extension.deps');
    expect([for (final v in views) v.id], ['deps.tree', 'deps.list']);
    expect(views.first.when, isNotNull);
    expect(views.first.collapsed, isFalse);
    expect(views.last.collapsed, isTrue);
    expect(views.first.contextualTitle, 'Dependencies');
    expect(
      contributions.view('logs.view')!.type,
      ExtensionViewType.webview,
    );
    expect(contributions.messages, isEmpty);
  });

  test('views of the Explorer show collapsed; an unknown container\'s go '
      'there, with a message', () {
    final contributions = ViewContributions([
      _extension('acme.tools', {
        'views': {
          'explorer': [
            {'id': 'acme.outline', 'name': 'Acme Outline'},
          ],
          'nowhere': [
            {'id': 'acme.lost', 'name': 'Lost'},
          ],
          'test': [
            {'id': 'acme.tests', 'name': 'Tests'},
          ],
        },
      }),
    ]);
    final explorer = contributions.viewsIn(BuiltinViewContainers.explorer);
    expect([for (final v in explorer) v.id], ['acme.outline', 'acme.lost']);
    expect(explorer.first.collapsed, isTrue);
    expect(
      contributions.view('acme.tests')!.containerId,
      BuiltinViewContainers.testing,
    );
    expect(contributions.messages.single, contains("'nowhere' does not exist"));
  });

  test('invalid containers and views are dropped with messages', () {
    final contributions = ViewContributions([
      _extension('acme.bad', {
        'viewsContainers': {
          'activitybar': [
            {'id': 'has space', 'title': 'Bad', 'icon': 'x.svg'},
          ],
        },
        'views': {
          'explorer': [
            {'id': 'acme.one', 'name': 'One'},
            {'id': 'acme.one', 'name': 'Again'},
            {'id': 'acme.two', 'name': 'Two', 'type': 'grid'},
          ],
          'scm': [
            {'id': 'acme.nameless'},
          ],
        },
      }),
    ]);
    expect(contributions.containers, isEmpty);
    expect([for (final v in contributions.views) v.id], ['acme.one']);
    expect(contributions.messages, hasLength(4));
  });

  test('welcome content: by view, the workbench\'s by their container, '
      'groups only with the proposal', () {
    final contributions = ViewContributions([
      _extension('acme.welcome', {
        'viewsWelcome': [
          {'view': 'acme.tree', 'contents': 'B', 'group': 'z@1'},
          {
            'view': 'acme.tree',
            'contents': 'A',
            'when': 'acme.empty',
            'enablement': 'acme.ready',
          },
          {'view': 'explorer', 'contents': 'Clone'},
        ],
      }, proposals: ['contribViewsWelcome']),
      _extension('acme.other', {
        'viewsWelcome': [
          {'view': 'scm', 'contents': 'Init', 'group': 'g'},
        ],
      }),
    ]);
    final tree = contributions.welcomeFor('acme.tree');
    expect([for (final w in tree) w.content], ['A', 'B']);
    expect(tree.first.when, isNotNull);
    expect(tree.first.precondition, isNotNull);
    expect(tree.last.group, 'z');
    expect(tree.last.order, 1);
    expect(
      contributions.welcomeFor('workbench.explorer.emptyView').single.content,
      'Clone',
    );
    expect(contributions.welcomeFor('workbench.scm').single.group, isNull);
    expect(contributions.messages.single, contains('contribViewsWelcome'));
  });

  test('welcome lines: links alone are buttons, others are text', () {
    final lines = parseWelcomeContent(
      'No dependencies yet.\n'
      '[Add Dependency](command:acme.add)\n'
      '\n'
      'Read [the docs](https://acme.dev "Docs") first.',
    );
    expect(lines, hasLength(3));
    expect((lines[0] as WelcomeParagraph).nodes, ['No dependencies yet.']);
    final button = lines[1] as WelcomeButton;
    expect(button.label, 'Add Dependency');
    expect(button.href, 'command:acme.add');
    final nodes = (lines[2] as WelcomeParagraph).nodes;
    expect(nodes.first, 'Read ');
    expect((nodes[1] as WelcomeLink).href, 'https://acme.dev');
    expect((nodes[1] as WelcomeLink).title, 'Docs');
    expect(nodes.last, ' first.');
  });

  test('command links with arguments', () {
    expect(parseCommandLink('command:acme.add')!.id, 'acme.add');
    final withArgs = parseCommandLink(
      'command:acme.open?${Uri.encodeComponent('["a",1]')}',
    )!;
    expect(withArgs.id, 'acme.open');
    expect(withArgs.args, ['a', 1]);
    expect(
      parseCommandLink('command:acme.one?${Uri.encodeComponent('{"x":1}')}')!
          .args,
      [
        {'x': 1},
      ],
    );
    expect(parseCommandLink('https://acme.dev'), isNull);
  });
}
