/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The panel's terminals, as VS Code's terminal service and group service
// keep them: a list, the active one, and which one's name is being edited.
// Each terminal is a group of its own: there are no splits.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/{terminalService,
// terminalGroupService,terminalEditingService}.ts.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'terminal_instance.dart';

class TerminalService extends ChangeNotifier {
  TerminalService({required this.root, this.backend = const TerminalBackend()});

  /// Where new terminals start: the project's folder.
  String root;
  final TerminalBackend backend;

  final List<TerminalInstance> _instances = [];
  TerminalInstance? _active;
  TerminalInstance? _editing;
  int _nextId = 1;

  List<TerminalInstance> get instances => List.unmodifiable(_instances);

  /// The one the panel shows; null only when there is none.
  TerminalInstance? get active => _active;

  /// The one whose name is being edited in place, in its tab (or in the
  /// panel's title when it is the only one).
  TerminalInstance? get editing => _editing;

  /// A new terminal, made the active one, as big as the others are.
  TerminalInstance create() {
    final instance = TerminalInstance(
      id: _nextId++,
      root: root,
      backend: backend,
      columns: _active?.columns ?? 80,
      rows: _active?.rows ?? 24,
      onExit: _exited,
    );
    _instances.add(instance);
    _active = instance;
    notifyListeners();
    return instance;
  }

  /// The active terminal; a new one if there is none, as VS Code makes one
  /// when its view shows with none.
  TerminalInstance ensureTerminal() => _active ?? create();

  void setActive(TerminalInstance instance) {
    if (_active == instance || !_instances.contains(instance)) return;
    _active = instance;
    notifyListeners();
  }

  /// Focus Next (and Previous) Terminal Group: the one after the active
  /// one, round to the first.
  void focusNext() => _step(1);
  void focusPrevious() => _step(-1);

  void _step(int by) {
    final active = _active;
    if (active == null || _instances.length < 2) return;
    final index = _instances.indexOf(active);
    setActive(_instances[(index + by) % _instances.length]);
  }

  /// Kill Terminal: hangs up [instance]'s process (the active one's by
  /// default) and drops it at once.
  void kill([TerminalInstance? instance]) {
    instance ??= _active;
    if (instance != null) _remove(instance);
  }

  /// Edits [instance]'s name (the active one's by default) in place.
  void startRename([TerminalInstance? instance]) {
    instance ??= _active;
    if (instance == null || _editing == instance) return;
    _editing = instance;
    notifyListeners();
  }

  /// Ends the edit of [instance]'s name: renamed to [title], or left as it
  /// was when null (cancelled).
  void endRename(TerminalInstance instance, [String? title]) {
    if (_editing == instance) _editing = null;
    if (title != null) instance.rename(title);
    notifyListeners();
  }

  /// A terminal is closed once its process exited cleanly; it stays to say
  /// why otherwise.
  void _exited(TerminalInstance instance) {
    if (instance.exitMessage == null) {
      _remove(instance);
    } else {
      notifyListeners();
    }
  }

  /// Drops [instance]: the next one (else the one before) becomes active,
  /// focused if the dropped one was, as VS Code's group service does.
  void _remove(TerminalInstance instance) {
    final index = _instances.indexOf(instance);
    if (index < 0) return;
    final hadFocus = instance.focusNode.hasFocus;
    _instances.removeAt(index);
    if (_editing == instance) _editing = null;
    if (_active == instance) {
      _active = _instances.isEmpty
          ? null
          : _instances[math.min(index, _instances.length - 1)];
      if (hadFocus) _active?.focus();
    }
    instance.dispose();
    notifyListeners();
  }

  /// Hangs up every terminal.
  @override
  void dispose() {
    for (final instance in _instances) {
      instance.dispose();
    }
    _instances.clear();
    _active = null;
    _editing = null;
    super.dispose();
  }
}
