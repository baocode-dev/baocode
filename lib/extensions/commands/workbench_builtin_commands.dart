/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The built-in commands extensions call most, mapped to BaoCode's
// workbench and editor through ports.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0)
// (the handlers' argument handling):
// src/vs/workbench/browser/parts/editor/editorCommands.ts (`vscode.open`,
// `_workbench.open`, `vscode.diff`, `_workbench.diff`, `_workbench.openWith`),
// src/vs/workbench/browser/actions/workspaceCommands.ts (`vscode.openFolder`),
// src/vs/platform/contextkey/browser/contextKeyService.ts (`_setContext`),
// src/vs/editor/browser/coreCommands.ts (`cursorMove`, `revealLine`,
// `type`, `replacePreviousChar`, `compositionType`),
// src/vs/editor/contrib/gotoSymbol/browser/goToCommands.ts
// (`editor.action.goToLocations`, `editor.action.showReferences`),
// src/vs/workbench/contrib/files/browser/fileCommands.ts
// (`revealInExplorer`), src/vs/workbench/contrib/extensions/browser/
// extensions.contribution.ts (`workbench.extensions.installExtension`,
// `workbench.extensions.uninstallExtension`).
//
// Deviations:
// - `workbench.action.reloadWindow` restarts the extension host (BaoCode
//   has no window reload).
// - Commands BaoCode already has under VS Code's id
//   (`workbench.action.files.save`, `workbench.action.closeActiveEditor`,
//   `workbench.action.terminal.*`, `editor.action.formatDocument`…) run
//   BaoCode's command ([ExtensionCommandRegistry.appCommands]); a port
//   method here is only registered where arguments need reading.
// - `command:` URIs passed to `vscode.open` are ignored, as upstream.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:bao_exthost/bao_exthost.dart';

import '../contextkey/context_key_service.dart';
import 'builtin_commands.dart';
import 'command_arguments.dart';

/// The workbench's part of the built-in commands.
abstract interface class WorkbenchCommandsPort {
  /// Opens [resource] in an editor: [column] is an [EditorGroupColumn]
  /// (null: the active group).
  Future<void> openEditor(
    VsUri resource, {
    int? column,
    EditorOpenOptions? options,
    String? label,
  });

  /// Opens [target] (an `http(s):`, `mailto:` URI…) outside, or as the
  /// workbench's opener does for other schemes.
  Future<void> openExternal(String target);

  /// Whether [resource] is one the opener sends outside the editor (the
  /// app's own URIs, as their handler takes them).
  bool isExternal(VsUri resource);

  /// A diff editor of [left] and [right].
  Future<void> openDiff(
    VsUri left,
    VsUri right, {
    String? label,
    String? description,
    int? column,
    EditorOpenOptions? options,
  });

  /// `vscode.openFolder`: [folder] (null: ask), in a new window when
  /// [forceNewWindow].
  Future<void> openFolder(VsUri? folder, {bool forceNewWindow = false});

  /// The settings, searching for [query].
  Future<void> openSettings({String? query});

  /// A view container (`workbench.view.explorer`,
  /// `workbench.view.extension.<id>`): shows and focuses it.
  Future<void> showViewContainer(String id);

  /// `workbench.action.focusActiveEditorGroup`.
  void focusActiveEditorGroup();

  /// `revealInExplorer`.
  Future<void> revealInExplorer(VsUri resource);
}

/// The active editor's part of the built-in commands.
abstract interface class EditorCommandsPort {
  /// `default:type`: types [text] (as the keyboard does).
  void type(String text);

  /// `default:replacePreviousChar`.
  void replacePreviousChar(String text, int replaceCharCnt);

  /// `default:compositionType`.
  void compositionType(
    String text, {
    int replacePrevCharCnt = 0,
    int replaceNextCharCnt = 0,
    int positionDelta = 0,
  });

  /// `cursorMove` with its argument object (`{to, by, value, select}`).
  void cursorMove(Map<String, Object?> args);

  /// `revealLine` (`{lineNumber, at}`: 0-based line, `top`, `center`,
  /// `bottom`).
  void revealLine(int lineNumber, String at);

  /// `editor.action.showReferences`: [locations] around [position] of
  /// [uri], in the references view.
  Future<void> showReferences(
    VsUri uri,
    CommandPosition position,
    List<CommandLocation> locations,
  );

  /// `editor.action.goToLocations` (`multiple`: `peek`, `gotoAndPeek`,
  /// `goto`).
  Future<void> goToLocations(
    VsUri uri,
    CommandPosition position,
    List<CommandLocation> locations, {
    String? multiple,
    String? noResultsMessage,
  });

  /// `editor.action.triggerSuggest`.
  void triggerSuggest();

  /// `editor.action.triggerParameterHints`.
  void triggerParameterHints();
}

/// Installing and uninstalling extensions for extensions.
abstract interface class ExtensionManagementCommandsPort {
  /// `workbench.extensions.installExtension`: an id (`publisher.name`,
  /// `@version` allowed) or a VSIX [vsix].
  Future<void> install({
    String? id,
    VsUri? vsix,
    Map<String, Object?>? options,
  });

  /// `workbench.extensions.uninstallExtension`.
  Future<void> uninstall(String id);
}

int _num(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

/// Registers the built-in commands BaoCode maps itself, on [commands];
/// returns what removes them. Commands whose port is not given are left
/// to BaoCode's own commands of the same id, if any.
void Function() registerWorkbenchBuiltinCommands(
  BuiltinCommands commands, {
  required ContextKeyFeed contextKeys,
  WorkbenchCommandsPort? workbench,
  EditorCommandsPort? editor,
  ExtensionManagementCommandsPort? extensions,
  Future<void> Function()? restartExtensionHost,
}) {
  final stops = <void Function()>[];
  void reg(String id, BuiltinCommandHandler handler) =>
      stops.add(commands.register(id, handler));
  void regVoid(String id, Future<void> Function(List<Object?> args) f) =>
      reg(id, (args) async {
        await f(args);
        return null;
      });
  Object? arg(List<Object?> args, int i) => i < args.length ? args[i] : null;

  // --- context keys
  Object? setContext(List<Object?> args) {
    setContextFromCommand(contextKeys, arg(args, 0), arg(args, 1));
    return null;
  }

  reg('_setContext', setContext);
  // `getContextKeyInfo` (and its developer twin): the keys areas declare
  // with [RawContextKey], sorted by name.
  reg('getContextKeyInfo', (args) {
    final infos = [...RawContextKey.all()]
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final info in infos)
        {
          'key': info.key,
          if (info.type != null) 'type': info.type,
          if (info.description != null) 'description': info.description,
        },
    ];
  });
  reg('_generateContextKeyInfo', (args) {
    final seen = <String>{};
    final result = <Map<String, Object?>>[
      for (final info in RawContextKey.all())
        if (seen.add(info.key))
          {
            'key': info.key,
            if (info.type != null) 'type': info.type,
            if (info.description != null) 'description': info.description,
          },
    ]..sort((a, b) => '${a['key']}'.compareTo('${b['key']}'));
    debugPrint(const JsonEncoder.withIndent('  ').convert(result));
    return null;
  });
  // The extension host maps `setContext` to `_setContext`; this is for
  // callers that do not go through it (a keybinding's command).
  reg('setContext', setContext);

  // --- editors
  if (workbench != null) {
    Future<void> open(List<Object?> args) async {
      final resourceArg = arg(args, 0);
      final (:column, :options) = columnAndOptionsArg(arg(args, 1));
      final label = arg(args, 2);
      final resource = switch (resourceArg) {
        final String s => VsUri.parse(s),
        _ => uriArg(resourceArg),
      };
      if (resource == null) return;
      if (options != null || column != null || resource.scheme == 'untitled') {
        await workbench.openEditor(
          resource,
          column: column,
          options: options,
          label: label is String ? label : null,
        );
      } else if (resource.scheme == 'command') {
        return;
      } else if (const {
            'mailto',
            'http',
            'https',
            'vsls',
          }.contains(resource.scheme) ||
          workbench.isExternal(resource)) {
        // The opener service's default opener: outside.
        await workbench.openExternal(
          resourceArg is String ? resourceArg : resource.toString(),
        );
      } else {
        // `EditorOpener`: any other resource in an editor.
        await workbench.openEditor(
          resource,
          label: label is String ? label : null,
        );
      }
    }

    reg('_workbench.open', open);
    reg('vscode.open', (args) => open([arg(args, 0)]));
    regVoid('_workbench.openWith', (args) async {
      final resource = uriArg(arg(args, 0));
      if (resource == null) return;
      final (:column, :options) = columnAndOptionsArg(arg(args, 2));
      await workbench.openEditor(resource, column: column, options: options);
    });

    Future<void> diff(List<Object?> args) async {
      final left = uriArg(arg(args, 0));
      final right = uriArg(arg(args, 1));
      if (left == null || right == null) {
        throw ArgumentError('vscode.diff: two resources are needed');
      }
      final labelArg = arg(args, 2);
      final (:column, :options) = columnAndOptionsArg(arg(args, 3));
      await workbench.openDiff(
        left,
        right,
        label: switch (labelArg) {
          final String s => s,
          final Map<Object?, Object?> m => m['label'] as String?,
          _ => null,
        },
        description: labelArg is Map
            ? labelArg['description'] as String?
            : null,
        column: column,
        options: options,
      );
    }

    reg('_workbench.diff', diff);
    reg(
      'vscode.diff',
      (args) => diff([arg(args, 0), arg(args, 1), arg(args, 2)]),
    );

    regVoid('vscode.openFolder', (args) async {
      final folder = uriArg(arg(args, 0));
      final options = arg(args, 1);
      final forceNewWindow = switch (options) {
        final bool b => b,
        final Map<Object?, Object?> m => m['forceNewWindow'] == true,
        _ => false,
      };
      await workbench.openFolder(folder, forceNewWindow: forceNewWindow);
    });
    reg(
      'vscode.newWindow',
      (args) => workbench.openFolder(null, forceNewWindow: true),
    );

    reg('workbench.action.openSettings', (args) {
      final a = arg(args, 0);
      return workbench.openSettings(
        query: switch (a) {
          final String s => s,
          final Map<Object?, Object?> m => m['query'] as String?,
          _ => null,
        },
      );
    });
    reg('workbench.action.openSettings2', (args) {
      final a = arg(args, 0);
      return workbench.openSettings(
        query: a is Map
            ? a['query'] as String?
            : a is String
            ? a
            : null,
      );
    });
    stops.add(
      commands.registerPrefix(
        'workbench.view.extension.',
        (id, args) => workbench.showViewContainer(id),
      ),
    );
    for (final id in const [
      'workbench.view.explorer',
      'workbench.view.search',
      'workbench.view.scm',
      'workbench.view.debug',
      'workbench.view.extensions',
    ]) {
      reg(id, (args) => workbench.showViewContainer(id));
    }
    reg('workbench.action.focusActiveEditorGroup', (args) {
      workbench.focusActiveEditorGroup();
      return null;
    });
    regVoid('revealInExplorer', (args) async {
      final resource = uriArg(arg(args, 0));
      if (resource != null) await workbench.revealInExplorer(resource);
    });
  }

  if (restartExtensionHost != null) {
    reg('workbench.action.reloadWindow', (args) {
      // Not awaited: the host that asked ends with the restart.
      unawaited(restartExtensionHost().catchError((Object _) {}));
      return null;
    });
    reg('workbench.action.restartExtensionHost', (args) {
      unawaited(restartExtensionHost().catchError((Object _) {}));
      return null;
    });
  }

  // --- the editor
  if (editor != null) {
    String text(List<Object?> args) {
      final a = arg(args, 0);
      return a is Map ? '${a['text'] ?? ''}' : '';
    }

    reg('type', (args) {
      editor.type(text(args));
      return null;
    });
    reg('default:type', (args) {
      editor.type(text(args));
      return null;
    });
    Object? replacePreviousChar(List<Object?> args) {
      final a = arg(args, 0);
      if (a is Map) {
        editor.replacePreviousChar(
          '${a['text'] ?? ''}',
          _num(a['replaceCharCnt']),
        );
      }
      return null;
    }

    reg('replacePreviousChar', replacePreviousChar);
    reg('default:replacePreviousChar', replacePreviousChar);
    Object? compositionType(List<Object?> args) {
      final a = arg(args, 0);
      if (a is Map) {
        editor.compositionType(
          '${a['text'] ?? ''}',
          replacePrevCharCnt: _num(a['replacePrevCharCnt']),
          replaceNextCharCnt: _num(a['replaceNextCharCnt']),
          positionDelta: _num(a['positionDelta']),
        );
      }
      return null;
    }

    reg('compositionType', compositionType);
    reg('default:compositionType', compositionType);
    reg('cursorMove', (args) {
      final a = arg(args, 0);
      if (a is Map) editor.cursorMove(a.cast<String, Object?>());
      return null;
    });
    reg('revealLine', (args) {
      final a = arg(args, 0);
      if (a is Map) {
        final line = a['lineNumber'];
        editor.revealLine(
          line is num ? line.toInt() : int.tryParse('$line') ?? 0,
          '${a['at'] ?? 'center'}',
        );
      }
      return null;
    });
    List<CommandLocation> locations(Object? value) => [
      if (value is List)
        for (final l in value) ?locationArg(l),
    ];
    regVoid('editor.action.showReferences', (args) async {
      final uri = uriArg(arg(args, 0));
      final position = positionArg(arg(args, 1));
      if (uri == null || position == null) {
        throw ArgumentError('editor.action.showReferences: bad arguments');
      }
      await editor.showReferences(uri, position, locations(arg(args, 2)));
    });
    regVoid('editor.action.goToLocations', (args) async {
      final uri = uriArg(arg(args, 0));
      final position = positionArg(arg(args, 1));
      if (uri == null || position == null) {
        throw ArgumentError('editor.action.goToLocations: bad arguments');
      }
      await editor.goToLocations(
        uri,
        position,
        locations(arg(args, 2)),
        multiple: arg(args, 3) as String?,
        noResultsMessage: arg(args, 4) as String?,
      );
    });
    regVoid('editor.action.peekLocations', (args) async {
      final uri = uriArg(arg(args, 0));
      final position = positionArg(arg(args, 1));
      if (uri == null || position == null) return;
      await editor.goToLocations(
        uri,
        position,
        locations(arg(args, 2)),
        multiple: (arg(args, 3) as String?) ?? 'peek',
      );
    });
    reg('editor.action.triggerSuggest', (args) {
      editor.triggerSuggest();
      return null;
    });
    reg('editor.action.triggerParameterHints', (args) {
      editor.triggerParameterHints();
      return null;
    });
  }

  // --- extensions
  if (extensions != null) {
    regVoid('workbench.extensions.installExtension', (args) async {
      final a = arg(args, 0);
      final options = arg(args, 1);
      final opts = options is Map ? options.cast<String, Object?>() : null;
      if (a is String) {
        await extensions.install(id: a, options: opts);
      } else if (uriArg(a) case final vsix?) {
        await extensions.install(vsix: vsix, options: opts);
      } else {
        throw ArgumentError(
          'workbench.extensions.installExtension: an id or a URI',
        );
      }
    });
    regVoid('workbench.extensions.uninstallExtension', (args) async {
      final id = arg(args, 0);
      if (id is! String) {
        throw ArgumentError('workbench.extensions.uninstallExtension: an id');
      }
      await extensions.uninstall(id);
    });
  }

  return () {
    for (final stop in stops) {
      stop();
    }
  };
}
