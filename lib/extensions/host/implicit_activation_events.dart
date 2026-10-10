/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The activation events an extension gets from what it contributes
// (`commands` → `onCommand:<id>`, …), on top of those it lists.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/extensionManagement/common/implicitActivationEvents.ts,
// and the `activationEventsGenerator` of every extension point that has one:
// workbench/services/actions/common/menusExtensionPoint.ts (commands),
// workbench/services/language/common/languageService.ts (languages),
// workbench/api/browser/viewsExtensionPoint.ts (views),
// workbench/contrib/tasks/common/taskDefinitionRegistry.ts (taskDefinitions),
// workbench/contrib/customEditor/common/extensionPoint.ts (customEditors),
// workbench/contrib/notebook/browser/notebookExtensionPoint.ts (notebooks,
// notebookRenderer), workbench/contrib/terminal/common/terminal.ts
// (terminal), workbench/contrib/terminalContrib/quickFix/browser/
// terminalQuickFixService.ts (terminalQuickFixes),
// workbench/services/authentication/browser/authenticationService.ts
// (authentication), workbench/contrib/welcomeGettingStarted/browser/
// gettingStartedExtensionPoint.ts (walkthroughs),
// workbench/contrib/debug/common/debugVisualizers.ts (debugVisualizers),
// workbench/services/dataChannel/browser/dataChannelService.ts
// (linkPresentationProviders), workbench/contrib/mcp/common/
// mcpConfiguration.ts (mcpServerDefinitionProviders), and the chat ones
// (chatParticipants, chatOutputRenderers, chatContext, chatSessions,
// languageModelChatProviders, languageModelTools).
//
// Deviations: none; results are not cached per description.

typedef _Generator = Iterable<String> Function(List<Object?> contributions);

Iterable<String> _each(
  List<Object?> contributions,
  String field,
  String prefix,
) sync* {
  for (final c in contributions) {
    if (c is Map) {
      final value = c[field];
      if (value is String && value.isNotEmpty) yield '$prefix$value';
    }
  }
}

final Map<String, _Generator> _generators = {
  'commands': (c) => _each(c, 'command', 'onCommand:'),
  'languages': (c) sync* {
    for (final l in c) {
      if (l is Map && l['id'] is String && l['configuration'] != null) {
        yield 'onLanguage:${l['id']}';
      }
    }
  },
  'views': (c) sync* {
    for (final containers in c) {
      if (containers is! Map) continue;
      for (final views in containers.values) {
        if (views is! List) continue;
        yield* _each(views, 'id', 'onView:');
      }
    }
  },
  'taskDefinitions': (c) => _each(c, 'type', 'onTaskType:'),
  'customEditors': (c) => _each(c, 'viewType', 'onCustomEditor:'),
  'notebooks': (c) => _each(c, 'type', 'onNotebookSerializer:'),
  'notebookRenderer': (c) => _each(c, 'id', 'onRenderer:'),
  'terminal': (c) sync* {
    for (final t in c) {
      final profiles = t is Map ? t['profiles'] : null;
      if (profiles is List) {
        for (final p in profiles) {
          if (p is Map) yield 'onTerminalProfile:${p['id']}';
        }
      }
    }
  },
  'terminalQuickFixes': (c) sync* {
    for (final q in c) {
      if (q is Map) yield 'onTerminalQuickFixRequest:${q['id']}';
    }
  },
  'authentication': (c) => _each(c, 'id', 'onAuthenticationRequest:'),
  'walkthroughs': (c) => _each(c, 'id', 'onWalkthrough:'),
  'debugVisualizers': (c) => _each(c, 'id', 'onDebugVisualizer:'),
  'linkPresentationProviders': (c) => _each(c, 'id', 'onLinkPresentation:'),
  'mcpServerDefinitionProviders': (c) => _each(c, 'id', 'onMcpCollection:'),
  'chatParticipants': (c) sync* {
    for (final p in c) {
      if (p is Map) yield 'onChatParticipant:${p['id']}';
    }
  },
  'chatOutputRenderers': (c) sync* {
    for (final r in c) {
      if (r is Map) yield 'onChatOutputRenderer:${r['viewType']}';
    }
  },
  'chatContext': (c) sync* {
    for (final r in c) {
      if (r is Map) yield 'onChatContextProvider:${r['id']}';
    }
  },
  'chatSessions': (c) sync* {
    for (final r in c) {
      if (r is Map) yield 'onChatSession:${r['type']}';
    }
  },
  'languageModelChatProviders': (c) sync* {
    for (final r in c) {
      if (r is Map) yield 'onLanguageModelChatProvider:${r['vendor']}';
    }
  },
  'languageModelTools': (c) sync* {
    for (final r in c) {
      if (r is Map) yield 'onLanguageModelTool:${r['name']}';
    }
  },
};

/// `ExtensionIdentifier.toKey`.
String extensionKey(String id) => id.toLowerCase();

/// `readActivationEvents`: the events [description] (an
/// `IExtensionDescription` as JSON) activates on.
List<String> readActivationEvents(Map<String, Object?> description) {
  if (description['main'] == null && description['browser'] == null) {
    return const [];
  }
  final id = _identifier(description);
  final events = [
    for (final e in description['activationEvents'] as List? ?? const [])
      if (e is String) e == 'onUri' ? 'onUri:${extensionKey(id)}' : e,
  ];
  final contributes = description['contributes'];
  if (contributes is! Map) return events;
  for (final MapEntry(:key, :value) in contributes.entries) {
    final generator = _generators[key];
    if (generator == null) continue;
    try {
      events.addAll(generator(value is List ? value : [value]));
    } on Object {
      // `onUnexpectedError`: one bad contribution does not hide the rest.
    }
  }
  return events;
}

/// `createActivationEventsMap`: extension key → its events, for those that
/// have any.
Map<String, List<String>> createActivationEventsMap(
  Iterable<Map<String, Object?>> descriptions,
) => {
  for (final d in descriptions)
    if (readActivationEvents(d) case final events when events.isNotEmpty)
      extensionKey(_identifier(d)): events,
};

String _identifier(Map<String, Object?> description) {
  final id = description['identifier'];
  if (id is Map) return '${id['value']}';
  if (id is String) return id;
  return '${description['publisher']}.${description['name']}';
}
