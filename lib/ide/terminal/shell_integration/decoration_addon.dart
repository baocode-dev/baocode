/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The decorations of a terminal's commands and marks: one in the gutter left
// of each command's first line (its status's icon and color) and one in the
// overview ruler, a placeholder for the command being typed or run.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/xterm/decorationAddon.ts.
//
// Upstream renders each gutter decoration as an element of xterm.js; here
// the decorations are a model ([decorations], [onDidChangeDecorations]) for
// the view to paint, each registered with the terminal's decoration service
// for its overview ruler mark and its lifetime (it goes when its marker
// does). What upstream does on an element's first render is done when the
// decoration is registered. The context menu (run, copy, chat), hovers,
// accessibility signals and settings changes are the view's or not ported;
// `terminal.integrated.shellIntegration.decorationsEnabled` is the
// constructor's `showGutterDecorations` and `showOverviewRulerDecorations`.
// The theme service is the constructor's `colorTheme` (the workbench's
// [terminalColorTheme] by default); a change of it, which recolors
// upstream's elements through CSS variables, fires
// [DecorationAddon.onDidChangeDecorations] for the view to paint.

import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart' show IconData;

import '../terminal_colors.dart';
import '../xterm/common/event.dart';
import '../xterm/common/lifecycle.dart';
import '../xterm/common/services/services.dart';
import '../xterm/headless/terminal.dart';
import '../xterm/typings/xterm.dart'
    show
        IDecoration,
        IDecorationOptions,
        IDecorationOverviewRulerOptions,
        IMarker;
import 'capabilities/capabilities.dart';
import 'decoration_styles.dart';

export '../terminal_colors.dart' show cssColor;

/// A gutter decoration (upstream `IDisposableDecoration` with the classes
/// `_updateClasses` gives its element).
class TerminalCommandDecoration {
  TerminalCommandDecoration._(
    this.decoration,
    this.command,
    this.markProperties,
    this._addon,
  );

  /// Its overview ruler mark, and its [marker].
  final IDecoration decoration;

  /// The command, or null for a mark.
  final ITerminalCommand? command;

  /// Set for a mark (or a command with mark properties).
  final IMarkProperties? markProperties;

  final DecorationAddon _addon;

  /// The line it sits on: [IMarker.line] is its buffer line.
  IMarker get marker => decoration.marker;

  /// Whether it is the placeholder of the command being typed or run.
  bool get isPlaceholder =>
      identical(decoration, _addon._placeholderDecoration);

  /// Upstream `getTerminalCommandDecorationState(command)`; null for a mark.
  TerminalCommandDecorationState? get state => markProperties != null
      ? null
      : getTerminalCommandDecorationState(command);

  /// Its CSS classes upstream (see [DecorationSelector]).
  List<String> get classNames => [
    DecorationSelector.commandDecoration,
    DecorationSelector.codicon,
    DecorationSelector.xtermDecoration,
    if (markProperties case final markProperties?) ...[
      DecorationSelector.defaultColor,
      //disable the mouse pointer
      if (markProperties.hoverMessage == null ||
          markProperties.hoverMessage!.isEmpty)
        DecorationSelector.defaultClass,
    ] else ...[
      if (!_addon._showGutterDecorations) DecorationSelector.hide,
      ...state!.classNames,
    ],
  ];

  IconData get icon =>
      markProperties != null ? terminalDecorationMark : state!.icon;

  /// Its color in the current theme; none when the theme has none.
  Color? get color => decorationColorOf(classNames, _addon._colorTheme.value);

  /// Whether it is drawn in the gutter (`hide` is `visibility: hidden`).
  bool get isVisible => !classNames.contains(DecorationSelector.hide);

  /// Whether it takes the pointer (a click opens the command's actions
  /// upstream): not with the `default` class.
  bool get isInteractive =>
      !classNames.contains(DecorationSelector.defaultClass);

  /// The hover's markdown, as upstream `_createDisposables` sets it up: null
  /// when there is none (a mark, or a command still running).
  String? get hoverMessage {
    final command = this.command;
    if (command == null ||
        (command.exitCode == null && command.markProperties == null)) {
      return null;
    }
    final content = getTerminalDecorationHoverContent(command, null, true);
    return content.isEmpty ? null : content;
  }
}

class DecorationAddon extends Disposable {
  DecorationAddon(
    this._capabilities,
    this._decorationService, {
    this._showGutterDecorations = true,
    this._showOverviewRulerDecorations = true,
    ValueListenable<TerminalColorTheme>? colorTheme,
  }) : _colorTheme = colorTheme ?? terminalColorTheme {
    register(toDisposable(_dispose));
    _colorTheme.addListener(_handleColorThemeChange);
    register(
      toDisposable(() => _colorTheme.removeListener(_handleColorThemeChange)),
    );
    _updateDecorationVisibility();
    register(
      _capabilities.onDidAddCapability(
        (c) => _createCapabilityDisposables(c.id),
      ),
    );
    register(
      _capabilities.onDidRemoveCapability(
        (c) => _removeCapabilityDisposables(c.id),
      ),
    );
  }

  final ITerminalCapabilityStore _capabilities;
  final IDecorationService _decorationService;
  final ValueListenable<TerminalColorTheme> _colorTheme;
  Terminal? _terminal;
  final Map<TerminalCapability, DisposableStore> _capabilityDisposables = {};

  /// By marker id, in the order they were added.
  final Map<int, TerminalCommandDecoration> _decorations = {};
  IDecoration? _placeholderDecoration;
  bool _showGutterDecorations;
  bool _showOverviewRulerDecorations;

  late final _onDidChangeDecorations = register(Emitter<void>());

  /// Fired when a decoration is added, removed or changes.
  late final IEvent<void> onDidChangeDecorations =
      _onDidChangeDecorations.event;

  /// The gutter decorations, oldest first.
  Iterable<TerminalCommandDecoration> get decorations => _decorations.values;

  /// Upstream's `terminal.integrated.shellIntegration.decorationsEnabled`
  /// change: `both` is both true, `never` both false.
  void setDecorationsEnabled({
    required bool gutter,
    required bool overviewRuler,
  }) {
    _removeCapabilityDisposables(TerminalCapability.commandDetection);
    _showGutterDecorations = gutter;
    _showOverviewRulerDecorations = overviewRuler;
    _updateDecorationVisibility();
  }

  /// Upstream's `onDidColorThemeChange` listener.
  void _handleColorThemeChange() {
    _refreshStyles(true);
    _onDidChangeDecorations.fire(null);
  }

  void _refreshStyles([bool refreshOverviewRulerColors = false]) {
    if (refreshOverviewRulerColors) {
      for (final decoration in _decorations.values) {
        final color = _getDecorationCssColor(decoration.command) ?? '';
        final options = decoration.decoration.options;
        if (options.overviewRulerOptions case final overviewRulerOptions?) {
          overviewRulerOptions.color = color;
        } else {
          // As upstream, one registered without a mark gets one.
          options.overviewRulerOptions = IDecorationOverviewRulerOptions(
            color: color,
          );
        }
      }
    }
    // Upstream's `_updateClasses` of each element: the classes here are
    // [TerminalCommandDecoration.classNames], computed when read.
  }

  void _createCapabilityDisposables(TerminalCapability c) {
    final capability = _capabilitiesGet(c);
    if (capability == null || _capabilityDisposables.containsKey(c)) {
      return;
    }
    final store = DisposableStore();
    switch (capability) {
      case IBufferMarkCapability():
        store.add(capability.onMarkAdded(registerMarkDecoration));
      case ICommandDetectionCapability():
        for (final d in _getCommandDetectionListeners(capability)) {
          store.add(d);
        }
    }
    _capabilityDisposables[c] = store;
  }

  Object? _capabilitiesGet(TerminalCapability c) => switch (c) {
    TerminalCapability.bufferMarkDetection => _capabilities.get(
      TerminalCapability.bufferMarkDetection,
    ),
    TerminalCapability.commandDetection => _capabilities.get(
      TerminalCapability.commandDetection,
    ),
    _ => null,
  };

  void _removeCapabilityDisposables(TerminalCapability c) {
    _capabilityDisposables.remove(c)?.dispose();
  }

  IDecoration? registerMarkDecoration(IMarkProperties mark) {
    if (_terminal == null ||
        (!_showGutterDecorations && !_showOverviewRulerDecorations)) {
      return null;
    }
    if (mark.hidden ?? false) {
      return null;
    }
    return registerCommandDecoration(null, false, mark);
  }

  void _updateDecorationVisibility() {
    _disposeAllDecorations();
    if (_showGutterDecorations || _showOverviewRulerDecorations) {
      _attachToCommandCapability();
    }
    final currentCommand = _capabilities
        .get(TerminalCapability.commandDetection)
        ?.executingCommandObject;
    if (currentCommand != null) {
      registerCommandDecoration(currentCommand, true);
    }
    _onDidChangeDecorations.fire(null);
  }

  void _disposeAllDecorations() {
    _placeholderDecoration?.dispose();
    for (final value in _decorations.values.toList()) {
      value.decoration.dispose();
    }
  }

  void _dispose() {
    for (final disposable in _capabilityDisposables.values) {
      disposable.dispose();
    }
    _capabilityDisposables.clear();
    clearDecorations();
  }

  void _clearPlaceholder() {
    _placeholderDecoration?.dispose();
    _placeholderDecoration = null;
  }

  void clearDecorations() {
    _placeholderDecoration?.marker.dispose();
    _clearPlaceholder();
    _disposeAllDecorations();
    _decorations.clear();
    _onDidChangeDecorations.fire(null);
  }

  void _attachToCommandCapability() {
    final capability = _capabilities.get(TerminalCapability.commandDetection);
    if (capability != null) {
      final disposables = _getCommandDetectionListeners(capability);
      final store = DisposableStore();
      for (final d in disposables) {
        store.add(d);
      }
      _capabilityDisposables[TerminalCapability.commandDetection] = store;
    }
  }

  List<IDisposable> _getCommandDetectionListeners(
    ICommandDetectionCapability capability,
  ) {
    _removeCapabilityDisposables(TerminalCapability.commandDetection);

    final commandDetectionListeners = <IDisposable>[];
    // Command started
    final executingCommandObject = capability.executingCommandObject;
    if (executingCommandObject?.marker != null) {
      registerCommandDecoration(executingCommandObject, true);
    }
    commandDetectionListeners.add(
      capability.onCommandStarted(
        (command) => registerCommandDecoration(command, true),
      ),
    );
    // Command finished
    for (final command in capability.commands) {
      registerCommandDecoration(command);
    }
    commandDetectionListeners.add(
      capability.onCommandFinished((command) {
        final buffer = _terminal?.buffer;
        final marker = command.promptStartMarker;

        // Edge case: Handle case where tsc watch commands clears buffer, but
        // decoration of that tsc command re-appears
        final shouldRegisterDecoration =
            command.exitCode == null ||
            // Only register decoration if the cursor is at or below the
            // promptStart marker.
            (buffer != null &&
                marker != null &&
                buffer.ybase + buffer.y >= marker.line);

        if (shouldRegisterDecoration) {
          registerCommandDecoration(command);
        }
      }),
    );
    // Command invalidated
    commandDetectionListeners.add(
      capability.onCommandInvalidated((commands) {
        for (final command in commands) {
          final id = command.marker?.id;
          if (id != null && id != 0) {
            _decorations[id]?.decoration.dispose();
          }
        }
      }),
    );
    // Current command invalidated
    commandDetectionListeners.add(
      capability.onCurrentCommandInvalidated((request) {
        if (request.reason == CommandInvalidationReason.noProblemsReported) {
          if (_decorations.isNotEmpty) {
            _decorations.values.last.decoration.dispose();
          }
        } else if (request.reason == CommandInvalidationReason.windows) {
          _clearPlaceholder();
          _onDidChangeDecorations.fire(null);
        }
      }),
    );
    return commandDetectionListeners;
  }

  void activate(Terminal terminal) {
    _terminal = terminal;
    _attachToCommandCapability();
    _onDidChangeDecorations.fire(null);
  }

  IDecoration? registerCommandDecoration([
    ITerminalCommand? command,
    bool beforeCommandExecution = false,
    IMarkProperties? markProperties,
  ]) {
    if (_terminal == null ||
        (beforeCommandExecution && command == null) ||
        (!_showGutterDecorations && !_showOverviewRulerDecorations)) {
      return null;
    }
    final marker = command?.marker ?? markProperties?.marker;
    if (marker == null) {
      throw StateError(
        'cannot add a decoration for a command '
        '${jsonEncode(command?.command)} with no marker',
      );
    }
    _clearPlaceholder();
    final color = _getDecorationCssColor(command) ?? '';
    final decoration = _decorationService.registerDecoration(
      IDecorationOptions(
        marker: marker,
        overviewRulerOptions: _showOverviewRulerDecorations
            ? (beforeCommandExecution
                  ? IDecorationOverviewRulerOptions(
                      color: color,
                      position: 'left',
                    )
                  : IDecorationOverviewRulerOptions(
                      color: color,
                      position:
                          command?.exitCode != null && command!.exitCode != 0
                          ? 'right'
                          : 'left',
                    ))
            : null,
      ),
    );
    if (decoration == null) {
      _onDidChangeDecorations.fire(null);
      return null;
    }
    if (beforeCommandExecution) {
      _placeholderDecoration = decoration;
    }
    // Upstream's first `onRender` of the element.
    final id = decoration.marker.id;
    if (!_decorations.containsKey(id)) {
      decoration.onDispose((_) {
        // Upstream removes whichever is under the marker's id.
        if (identical(_decorations[id]?.decoration, decoration)) {
          _decorations.remove(id);
          _onDidChangeDecorations.fire(null);
        }
      });
      _decorations[id] = TerminalCommandDecoration._(
        decoration,
        command,
        command?.markProperties ?? markProperties,
        this,
      );
    }
    _onDidChangeDecorations.fire(null);
    return decoration;
  }

  /// Upstream's `_getDecorationCssColor`: the theme's color as CSS; none
  /// when the theme has none.
  String? _getDecorationCssColor(ITerminalCommand? command) {
    final theme = _colorTheme.value;
    final Color? color;
    if (command?.exitCode == null) {
      color = theme.commandDecorationDefaultBackground;
    } else {
      color = command!.exitCode != 0
          ? theme.commandDecorationErrorBackground
          : theme.commandDecorationSuccessBackground;
    }
    return color == null ? null : cssColor(color);
  }
}
