/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Extensions' `contributes.viewsContainers`, `contributes.views` and
// `contributes.viewsWelcome`: the view containers they add to the activity
// bar and the panel, the views they add to those or to the workbench's own
// containers, and what an empty view shows.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/viewsExtensionPoint.ts
// (`isValidViewsContainer`, `registerCustomViewContainers`, `addViews`,
// `isValidViewDescriptors`, `getViewContainer`, `showCollapsed`) and
// src/vs/workbench/contrib/welcomeViews/common/viewsWelcomeContribution.ts
// with viewsWelcomeExtensionPoint.ts (`ViewIdentifierMap`,
// `parseGroupAndOrder`).
//
// Deviations: the containers are recomputed from every extension at once
// rather than added and removed per extension (orders are the same); a
// `secondarySidebar` container is shown in the side bar; messages for
// extension authors are collected in [ViewContributions.messages]
// (English) instead of an extension message collector; `remote` views
// need no proposal check because BaoCode has no Remote Explorer (they go
// to the Explorer, as views of an unknown container do).

import 'dart:convert';

import '../commands/command_contributions.dart';
import '../contextkey/contextkey.dart';

/// Where a view container shows (`ViewContainerLocation`).
enum ViewContainerLocation { sidebar, panel, auxiliaryBar }

/// The workbench's own containers extensions may add views to.
abstract final class BuiltinViewContainers {
  static const explorer = 'workbench.view.explorer';
  static const scm = 'workbench.view.scm';
  static const debug = 'workbench.view.debug';
  static const remote = 'workbench.view.remote';

  /// The Testing container (upstream registers it under the id an
  /// extension's `test` container would have).
  static const testing = 'workbench.view.extension.test';

  static const all = {explorer, scm, debug, testing};
}

/// A view container an extension contributes.
final class ViewContainerDescriptor {
  const ViewContainerDescriptor({
    required this.id,
    required this.title,
    required this.icon,
    required this.extensionId,
    required this.location,
    required this.order,
  });

  /// `workbench.view.extension.<id>`.
  final String id;
  final String title;

  /// A codicon or the extension's image.
  final ExtensionIcon? icon;
  final String extensionId;
  final ViewContainerLocation location;
  final int order;
}

/// `ViewType`.
enum ExtensionViewType { tree, webview }

/// A view an extension contributes (`ICustomViewDescriptor`).
final class ExtensionViewDescriptor {
  const ExtensionViewDescriptor({
    required this.id,
    required this.name,
    required this.containerId,
    required this.originalContainerId,
    required this.extensionId,
    required this.type,
    this.when,
    this.icon,
    this.contextualTitle,
    this.collapsed = false,
    this.hideByDefault = false,
    this.order,
    this.weight,
    this.group,
  });

  final String id;
  final String name;

  /// The container it shows in: its own, a workbench one, or the
  /// Explorer when the one it names does not exist.
  final String containerId;

  /// The key of `contributes.views` it was under.
  final String originalContainerId;
  final String extensionId;
  final ExtensionViewType type;
  final ContextKeyExpression? when;
  final ExtensionIcon? icon;
  final String? contextualTitle;

  /// Shows collapsed at first.
  final bool collapsed;

  /// `visibility: hidden`.
  final bool hideByDefault;
  final int? order;

  /// `initialSize`, in the extension's own container.
  final double? weight;
  final String? group;
}

/// A `contributes.viewsWelcome` entry (`IViewContentDescriptor`).
final class ViewWelcomeContent {
  const ViewWelcomeContent({
    required this.viewId,
    required this.content,
    required this.extensionId,
    this.when,
    this.precondition,
    this.group,
    this.order,
  });

  final String viewId;

  /// Lines of text with `[label](link)`s; a line that is only a link is a
  /// button.
  final String content;
  final String extensionId;
  final ContextKeyExpression? when;

  /// `enablement`: its buttons are disabled where it does not hold.
  final ContextKeyExpression? precondition;
  final String? group;
  final int? order;
}

/// What the extensions contribute to the workbench's views.
final class ViewContributions {
  ViewContributions(List<ExtensionSource> extensions) {
    _addContainers(extensions);
    _addViews(extensions);
    _addWelcome(extensions);
  }

  static final empty = ViewContributions(const []);

  /// Upstream's `CUSTOM_VIEWS_START_ORDER`.
  static const _customViewsStartOrder = 7;

  final List<ViewContainerDescriptor> containers = [];
  final List<ExtensionViewDescriptor> views = [];
  final List<ViewWelcomeContent> welcome = [];

  /// Problems with the contributions, for extension authors.
  final List<String> messages = [];

  final Map<String, ViewContainerDescriptor> _containersById = {};

  ViewContainerDescriptor? container(String id) => _containersById[id];

  /// The views shown in [containerId], in order.
  List<ExtensionViewDescriptor> viewsIn(String containerId) {
    final result = [
      for (final (i, view) in views.indexed)
        if (view.containerId == containerId) (i, view),
    ];
    result.sort((a, b) {
      final c = (a.$2.order ?? 1 << 30).compareTo(b.$2.order ?? 1 << 30);
      return c != 0 ? c : a.$1 - b.$1;
    });
    return [for (final (_, view) in result) view];
  }

  ExtensionViewDescriptor? view(String id) {
    for (final view in views) {
      if (view.id == id) return view;
    }
    return null;
  }

  /// The welcome content of [viewId], in order (`group`, then `order`).
  List<ViewWelcomeContent> welcomeFor(String viewId) {
    final result = [
      for (final (i, item) in welcome.indexed)
        if (item.viewId == viewId) (i, item),
    ];
    result.sort((a, b) {
      final ag = a.$2.group ?? '', bg = b.$2.group ?? '';
      if (ag != bg) return ag.compareTo(bg);
      final c = (a.$2.order ?? 0).compareTo(b.$2.order ?? 0);
      return c != 0 ? c : a.$1 - b.$1;
    });
    return [for (final (_, item) in result) item];
  }

  void _addContainers(List<ExtensionSource> extensions) {
    var activityBarOrder = _customViewsStartOrder;
    var panelOrder = 6;
    var auxiliaryBarOrder = 101;
    for (final extension in extensions) {
      final value = extension.contributes['viewsContainers'];
      if (value is! Map) continue;
      for (final MapEntry(:key, :value) in value.entries) {
        final location = switch (key) {
          'activitybar' => ViewContainerLocation.sidebar,
          'panel' => ViewContainerLocation.panel,
          'secondarySidebar' => ViewContainerLocation.auxiliaryBar,
          _ => null,
        };
        if (location == null) continue;
        if (!_isValidViewsContainer(value, extension)) continue;
        for (final descriptor in (value as List).cast<Map<Object?, Object?>>()) {
          final order = switch (location) {
            ViewContainerLocation.sidebar => activityBarOrder++,
            ViewContainerLocation.panel => panelOrder++,
            ViewContainerLocation.auxiliaryBar => auxiliaryBarOrder++,
          };
          final id = 'workbench.view.extension.${descriptor['id']}';
          if (_containersById.containsKey(id) ||
              BuiltinViewContainers.all.contains(id)) {
            continue;
          }
          final title = '${descriptor['title']}';
          final container = ViewContainerDescriptor(
            id: id,
            title: title.trim().isEmpty ? id : title,
            icon: ExtensionIcon.parse(descriptor['icon'], extension.location),
            extensionId: extension.id,
            location: location,
            order: order,
          );
          containers.add(container);
          _containersById[id] = container;
        }
      }
    }
  }

  bool _isValidViewsContainer(Object? value, ExtensionSource extension) {
    if (value is! List) {
      messages.add('${extension.id}: views containers must be an array');
      return false;
    }
    for (final descriptor in value) {
      if (descriptor is! Map) return false;
      final id = descriptor['id'];
      if (id is! String || !RegExp(r'^[a-z0-9_-]+$', caseSensitive: false)
          .hasMatch(id)) {
        messages.add(
          "${extension.id}: property `id` is mandatory and must be of type "
          "`string` with non-empty value. Only alphanumeric characters, '_', "
          "and '-' are allowed.",
        );
        return false;
      }
      for (final property in ['title', 'icon']) {
        if (descriptor[property] is! String) {
          messages.add(
            '${extension.id}: property `$property` is mandatory and must be '
            'of type `string`',
          );
          return false;
        }
      }
    }
    return true;
  }

  String? _containerOf(String key) => switch (key) {
    'explorer' => BuiltinViewContainers.explorer,
    'debug' => BuiltinViewContainers.debug,
    'scm' => BuiltinViewContainers.scm,
    'test' => BuiltinViewContainers.testing,
    _ => _containersById.containsKey('workbench.view.extension.$key')
        ? 'workbench.view.extension.$key'
        : null,
  };

  static bool _showCollapsed(String container) => switch (container) {
    BuiltinViewContainers.explorer ||
    BuiltinViewContainers.scm ||
    BuiltinViewContainers.debug => true,
    _ => false,
  };

  void _addViews(List<ExtensionSource> extensions) {
    final ids = <String>{};
    for (final extension in extensions) {
      final value = extension.contributes['views'];
      if (value is! Map) continue;
      for (final MapEntry(:key, :value) in value.entries) {
        if (!_isValidViewDescriptors(value, extension)) continue;
        final known = _containerOf('$key');
        if (known == null) {
          messages.add(
            "${extension.id}: View container '$key' does not exist and all "
            "views registered to it will be added to 'Explorer'.",
          );
        }
        final containerId = known ?? BuiltinViewContainers.explorer;
        final container = _containersById[containerId];
        final ownContainer = container?.extensionId == extension.id;
        for (final (index, item)
            in (value as List).cast<Map<Object?, Object?>>().indexed) {
          final id = item['id'] as String;
          if (!ids.add(id)) {
            messages.add(
              '${extension.id}: Cannot register multiple views with same id '
              '`$id`',
            );
            continue;
          }
          final type = switch (item['type']) {
            null || 'tree' => ExtensionViewType.tree,
            'webview' => ExtensionViewType.webview,
            _ => null,
          };
          if (type == null) {
            messages.add(
              '${extension.id}: Unknown view type `${item['type']}`.',
            );
            ids.remove(id);
            continue;
          }
          final visibility = item['visibility'];
          views.add(
            ExtensionViewDescriptor(
              id: id,
              name: item['name'] as String,
              containerId: containerId,
              originalContainerId: '$key',
              extensionId: extension.id,
              type: type,
              when: ContextKeyExpr.deserialize(item['when'] as String?),
              icon: switch (item['icon']) {
                final String icon => ExtensionIcon.parse(
                  icon,
                  extension.location,
                ),
                _ => null,
              },
              contextualTitle:
                  item['contextualTitle'] as String? ?? container?.title,
              collapsed:
                  _showCollapsed(containerId) || visibility == 'collapsed',
              hideByDefault: visibility == 'hidden',
              order: ownContainer ? index + 1 : null,
              weight: ownContainer
                  ? (item['initialSize'] as num?)?.toDouble()
                  : null,
              group: item['group'] as String?,
            ),
          );
        }
      }
    }
  }

  bool _isValidViewDescriptors(Object? value, ExtensionSource extension) {
    if (value is! List) {
      messages.add('${extension.id}: views must be an array');
      return false;
    }
    for (final descriptor in value) {
      if (descriptor is! Map) return false;
      for (final property in ['id', 'name']) {
        if (descriptor[property] is! String) {
          messages.add(
            '${extension.id}: property `$property` is mandatory and must be '
            'of type `string`',
          );
          return false;
        }
      }
      for (final property in ['when', 'icon', 'contextualTitle']) {
        final v = descriptor[property];
        if (v != null && v != '' && v is! String) {
          messages.add(
            '${extension.id}: property `$property` can be omitted or must be '
            'of type `string`',
          );
          return false;
        }
      }
      final visibility = descriptor['visibility'];
      if (visibility != null &&
          visibility != '' &&
          !const {'visible', 'hidden', 'collapsed'}.contains(visibility)) {
        messages.add(
          '${extension.id}: property `visibility` can be omitted or must be '
          'one of visible, hidden, collapsed',
        );
        return false;
      }
    }
    return true;
  }

  /// `ViewIdentifierMap`: the workbench views a `viewsWelcome` entry may
  /// name by their container.
  static const _welcomeViewIds = {
    'explorer': 'workbench.explorer.emptyView',
    'debug': 'workbench.debug.welcome',
    'scm': 'workbench.scm',
    'testing': 'workbench.view.testing',
  };

  void _addWelcome(List<ExtensionSource> extensions) {
    for (final extension in extensions) {
      final value = extension.contributes['viewsWelcome'];
      if (value is! List) continue;
      final proposals = switch (extension.description['enabledApiProposals']) {
        final List<Object?> list => list,
        _ => const <Object?>[],
      };
      for (final item in value) {
        if (item is! Map) continue;
        final view = item['view'];
        final contents = item['contents'];
        if (view is! String || contents is! String) continue;
        String? group;
        int? order;
        if (item['group'] case final String value) {
          if (!proposals.contains('contribViewsWelcome')) {
            messages.add(
              "The viewsWelcome contribution in '${extension.id}' requires "
              "'enabledApiProposals: [\"contribViewsWelcome\"]' in order to "
              "use the 'group' proposed property.",
            );
          } else {
            final at = value.lastIndexOf('@');
            if (at > 0) {
              group = value.substring(0, at);
              order = int.tryParse(value.substring(at + 1));
              if (order == 0) order = null;
            } else {
              group = value;
            }
          }
        }
        welcome.add(
          ViewWelcomeContent(
            viewId: _welcomeViewIds[view] ?? view,
            content: contents,
            extensionId: extension.id,
            when: ContextKeyExpr.deserialize(item['when'] as String?),
            precondition: ContextKeyExpr.deserialize(
              item['enablement'] as String?,
            ),
            group: group,
            order: order,
          ),
        );
      }
    }
  }
}

/// One line of welcome content: text and links, or a button.
sealed class WelcomeLine {
  const WelcomeLine();
}

/// A line that is only a link: a button.
final class WelcomeButton extends WelcomeLine {
  const WelcomeButton(this.label, this.href, {this.title});

  final String label;
  final String href;
  final String? title;
}

/// A paragraph: text and inline links.
final class WelcomeParagraph extends WelcomeLine {
  const WelcomeParagraph(this.nodes);

  /// Strings and [WelcomeLink]s.
  final List<Object> nodes;
}

final class WelcomeLink {
  const WelcomeLink(this.label, this.href, {this.title});

  final String label;
  final String href;
  final String? title;
}

final _linkPattern = RegExp(
  r'''\[([^\]]+)\]\(((?:https?:\/\/|command:|file:)[^\)\s]+)(?: (["'])(.+?)(\3))?\)''',
  caseSensitive: false,
);

/// `parseLinkedText` over each line of [content] (viewPane.ts's
/// `WelcomeView`): a line that is a link alone is a button.
List<WelcomeLine> parseWelcomeContent(String content) {
  final lines = <WelcomeLine>[];
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final nodes = <Object>[];
    var index = 0;
    for (final match in _linkPattern.allMatches(line)) {
      if (match.start > index) nodes.add(line.substring(index, match.start));
      nodes.add(WelcomeLink(match[1]!, match[2]!, title: match[4]));
      index = match.end;
    }
    if (index < line.length) nodes.add(line.substring(index));
    if (nodes case [final WelcomeLink link]) {
      lines.add(WelcomeButton(link.label, link.href, title: link.title));
    } else {
      lines.add(WelcomeParagraph(nodes));
    }
  }
  return lines;
}

/// A `command:` link's command and its arguments (a JSON array, or one
/// JSON value, URI-encoded after the `?`).
({String id, List<Object?> args})? parseCommandLink(String href) {
  if (!href.startsWith('command:')) return null;
  final rest = href.substring('command:'.length);
  final query = rest.indexOf('?');
  if (query < 0) return (id: rest, args: const []);
  final id = rest.substring(0, query);
  try {
    final decoded = jsonDecode(
      Uri.decodeComponent(rest.substring(query + 1)),
    );
    return (
      id: id,
      args: switch (decoded) {
        final List<Object?> list => list,
        final value => [value],
      },
    );
  } on Object {
    return (id: id, args: const []);
  }
}
