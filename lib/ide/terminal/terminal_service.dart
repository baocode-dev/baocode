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
// terminalGroupService,terminalEditingService}.ts; its profiles are
// terminal_profile_service.dart's.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'terminal_colors.dart';
import 'terminal_instance.dart';
import 'terminal_profile_service.dart';
import 'terminal_profiles.dart';

class TerminalService extends ChangeNotifier {
  TerminalService({
    required this.root,
    this.backend = const TerminalBackend(),
    this.colorTheme,
  });

  /// Where new terminals start: the project's folder.
  String root;
  final TerminalBackend backend;

  /// Its terminals' colors, if not [terminalColorTheme].
  final ValueListenable<TerminalColorTheme>? colorTheme;

  /// The shells a new terminal can start, and the default one.
  late final TerminalProfileService profiles = TerminalProfileService(backend);

  final List<TerminalInstance> _instances = [];

  /// Those made `hideFromUser`, until shown.
  final Set<TerminalInstance> _hidden = {};
  TerminalInstance? _active;
  TerminalInstance? _editing;
  int _nextId = 1;

  /// The terminals in the panel's tabs.
  List<TerminalInstance> get instances => List.unmodifiable([
    for (final instance in _instances)
      if (!_hidden.contains(instance)) instance,
  ]);

  /// Every terminal, those hidden from the user too (VS Code's
  /// `ITerminalService.instances`, which extensions see).
  List<TerminalInstance> get allInstances => List.unmodifiable(_instances);

  /// The terminal numbered [id].
  TerminalInstance? instanceFromId(int id) {
    for (final instance in _instances) {
      if (instance.id == id) return instance;
    }
    return null;
  }

  /// The extensions' environment variable collections, applied to each new
  /// terminal's environment unless strict.
  void Function(Map<String, String> environment)? environmentMutator;

  final _onDidCreate = StreamController<TerminalInstance>.broadcast(sync: true);
  final _onDidDispose = StreamController<TerminalInstance>.broadcast(
    sync: true,
  );
  final _onDidChangeActive = StreamController<TerminalInstance?>.broadcast(
    sync: true,
  );
  final _onDidRequestShow = StreamController<bool>.broadcast(sync: true);
  final _onDidRequestHide = StreamController<void>.broadcast(sync: true);

  /// Each new terminal, once it is listed (before its process starts).
  Stream<TerminalInstance> get onDidCreate => _onDidCreate.stream;

  /// Each terminal dropped, with its [TerminalInstance.exitReason] set.
  Stream<TerminalInstance> get onDidDispose => _onDidDispose.stream;

  /// The new [active] one.
  Stream<TerminalInstance?> get onDidChangeActive => _onDidChangeActive.stream;

  /// The panel asked to show, focused unless the value says to preserve
  /// focus (`Terminal.show(preserveFocus)`).
  Stream<bool> get onDidRequestShow => _onDidRequestShow.stream;

  /// The panel asked to hide (`Terminal.hide()` of the active one).
  Stream<void> get onDidRequestHide => _onDidRequestHide.stream;

  /// The one the panel shows; null only when there is none.
  TerminalInstance? get active => _active;

  /// The one whose name is being edited in place, in its tab (or in the
  /// panel's title when it is the only one).
  TerminalInstance? get editing => _editing;

  /// A new terminal, made the active one, as big as the others are: on
  /// [profile]'s shell, else the default profile's (see
  /// [TerminalProfileService.defaultShell]).
  ///
  /// An extension's terminal starts as its [config] says; one
  /// `hideFromUser` is not listed in [instances], nor made active, until
  /// [show]n.
  TerminalInstance create({
    TerminalProfile? profile,
    TerminalLaunchConfig? config,
  }) {
    final instance = TerminalInstance(
      id: _nextId++,
      root: root,
      backend: backend,
      columns: _active?.columns ?? 80,
      rows: _active?.rows ?? 24,
      onExit: _exited,
      shell: profile != null
          ? SynchronousFuture(profile.shell)
          : config?.executable != null || config?.customPty != null
          ? null
          : profiles.defaultShell(),
      config: config,
      environmentMutator: environmentMutator,
      colorTheme: colorTheme,
    )..onRequestClose = _closeRequested;
    _instances.add(instance);
    _onDidCreate.add(instance);
    if (config?.hideFromUser ?? false) {
      _hidden.add(instance);
    } else {
      _setActive(instance);
    }
    notifyListeners();
    return instance;
  }

  void _setActive(TerminalInstance? instance) {
    if (_active == instance) return;
    _active = instance;
    _onDidChangeActive.add(instance);
  }

  /// `Terminal.show`: [instance] in the panel (listed if it was hidden from
  /// the user) and active, and the panel shown.
  void show(TerminalInstance instance, {bool preserveFocus = false}) {
    if (!_instances.contains(instance)) return;
    _hidden.remove(instance);
    _setActive(instance);
    notifyListeners();
    _onDidRequestShow.add(preserveFocus);
  }

  /// `Terminal.hide`: the panel hidden, when [instance] is the one it
  /// shows.
  void hide(TerminalInstance instance) {
    if (_active == instance) _onDidRequestHide.add(null);
  }

  /// The active terminal; a new one if there is none, as VS Code makes one
  /// when its view shows with none.
  TerminalInstance ensureTerminal() => _active ?? create();

  void setActive(TerminalInstance instance) {
    if (_active == instance || !_instances.contains(instance)) return;
    _hidden.remove(instance);
    _setActive(instance);
    notifyListeners();
  }

  /// Focus Next (and Previous) Terminal Group: the one after the active
  /// one, round to the first.
  void focusNext() => _step(1);
  void focusPrevious() => _step(-1);

  void _step(int by) {
    final active = _active;
    final instances = this.instances;
    if (active == null || instances.length < 2) return;
    final index = instances.indexOf(active);
    setActive(instances[(index + by) % instances.length]);
  }

  /// Kill Terminal: hangs up [instance]'s process (the active one's by
  /// default) and drops it at once; [reason] says who asked.
  void kill([
    TerminalInstance? instance,
    TerminalExitReason reason = TerminalExitReason.user,
  ]) {
    instance ??= _active;
    if (instance == null) return;
    instance.exitReason ??= reason;
    _remove(instance);
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
  ///
  /// An extension's terminal closes as VS Code's do, whatever the exit,
  /// unless it waits for a key.
  void _exited(TerminalInstance instance) {
    if (instance.waitingForKey) {
      notifyListeners();
    } else if (instance.exitMessage == null || instance.config != null) {
      _remove(instance);
    } else {
      notifyListeners();
    }
  }

  void _closeRequested(TerminalInstance instance) => _remove(instance);

  /// Drops [instance]: the next one (else the one before) becomes active,
  /// focused if the dropped one was, as VS Code's group service does.
  void _remove(TerminalInstance instance) {
    final index = _instances.indexOf(instance);
    if (index < 0) return;
    final hadFocus = instance.focusNode.hasFocus;
    final shownIndex = instances.indexOf(instance);
    _instances.removeAt(index);
    _hidden.remove(instance);
    if (_editing == instance) _editing = null;
    if (_active == instance) {
      final shown = instances;
      _setActive(
        shown.isEmpty
            ? null
            : shown[math.min(math.max(shownIndex, 0), shown.length - 1)],
      );
      if (hadFocus) _active?.focus();
    }
    instance.exitReason ??= TerminalExitReason.unknown;
    _onDidDispose.add(instance);
    instance.dispose();
    notifyListeners();
  }

  /// Hangs up every terminal.
  @override
  void dispose() {
    profiles.dispose();
    for (final instance in _instances) {
      instance.exitReason ??= TerminalExitReason.shutdown;
      _onDidDispose.add(instance);
      instance.dispose();
    }
    _instances.clear();
    _hidden.clear();
    _active = null;
    _editing = null;
    unawaited(_onDidCreate.close());
    unawaited(_onDidDispose.close());
    unawaited(_onDidChangeActive.close());
    unawaited(_onDidRequestShow.close());
    unawaited(_onDidRequestHide.close());
    super.dispose();
  }
}
