// The panel's terminals as the workbench shows them (upstream
// `TerminalService` with its view, terminal.contribution.ts): toggled,
// made (on a profile, in a folder), focused, cycled, renamed, a chat's
// background command shown in the terminal's place, and the panel hidden
// once the last terminal is gone (`terminal.integrated.hideOnLastClosed`).

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../ide_layout.dart';
import '../lsp_ui/problems_panel.dart' show IdePanelTab;
import '../terminal/terminal_instance.dart';
import '../terminal/terminal_profile_service.dart';
import '../terminal/terminal_profiles.dart';
import '../terminal/terminal_service.dart';
import '../workbench/contributions.dart';

class TerminalViewService extends ChangeNotifier {
  /// Over [terminals] (none where they cannot run, the web), the IDE's own
  /// where [owned] (disposed with it), else the chat's; the panel is
  /// [layout]'s (the workspace's, which may change).
  TerminalViewService({
    required this.terminals,
    required this.owned,
    required this.host,
    required this._layout,
  }) {
    final terminals = this.terminals;
    if (terminals == null) return;
    terminals.addListener(_terminalsChanged);
    // An extension's `Terminal.show()` and `hide()`.
    _requests = [
      terminals.onDidRequestShow.listen((preserveFocus) {
        _layout().panel = IdePanelTab.terminal;
        if (!preserveFocus) focusSoon();
      }),
      terminals.onDidRequestHide.listen((_) {
        if (_layout().panel == IdePanelTab.terminal) _layout().panel = null;
      }),
    ];
  }

  final TerminalService? terminals;
  final bool owned;
  final WorkbenchHost host;
  final IdeLayout Function() _layout;
  List<StreamSubscription<Object?>> _requests = const [];

  TerminalInstance? get active => terminals?.active;

  /// Whether the panel shows TERMINAL.
  bool get shown => _layout().panel == IdePanelTab.terminal;

  /// The id of the background command (see [IdeWorkbench.terminalTasks])
  /// whose output shows in the terminal's place; null for the terminal.
  String? get task => _task;
  String? _task;

  /// Shows the output of the background command [id] (one of its chat's)
  /// on the panel's TERMINAL tab.
  void showTask(String? id) {
    _task = id;
    if (id != null) _layout().panel = IdePanelTab.terminal;
    notifyListeners();
  }

  /// New terminals start in [root] (the project's first folder); those
  /// running stay where they are. The chat's start where it says.
  set root(String root) {
    if (owned) terminals?.root = root;
  }

  /// The terminal commands follow them. Once the last terminal is gone,
  /// the panel hides, as VS Code's `terminal.integrated.hideOnLastClosed`.
  void _terminalsChanged() {
    if (shown && (terminals?.instances.isEmpty ?? true)) {
      _layout().panel = null;
      // Its keyboard went with it, to the editor.
      host.focusSoon();
    }
    notifyListeners();
  }

  /// Toggle Terminal (⌃`): the panel on TERMINAL, with the keyboard in the
  /// terminal, or hidden.
  void toggle() {
    final layout = _layout();
    layout.panel = layout.panel == IdePanelTab.terminal
        ? null
        : IdePanelTab.terminal;
    if (shown) focusSoon();
  }

  /// Create New Terminal (⌃⇧`), shown and focused: on [profile]'s shell,
  /// else the default profile's; in [cwd], else the workspace's first
  /// folder.
  void create({TerminalProfile? profile, String? cwd}) {
    terminals?.create(profile: profile, cwd: cwd);
    show();
  }

  /// Open in Terminal (the explorer's context menu): a terminal started in
  /// [folder], shown and focused. As VS Code's `openInTerminal`.
  void openIn(String folder) {
    final terminals = this.terminals;
    if (terminals == null) return;
    terminals.create(cwd: folder);
    show();
  }

  /// Create New Terminal (With Profile): the profile [args] names
  /// (`{"profileName": "bash"}`, upstream's keybinding argument), else the
  /// one picked.
  Future<void> createWithProfile([Object? args]) async {
    final profiles = terminals?.profiles;
    if (profiles == null) return;
    await profiles.refresh();
    final context = host.context;
    if (context == null || !context.mounted) return;
    if (args case {'profileName': final String name}) {
      if (profiles.profileNamed(name) case final profile?) {
        create(profile: profile);
      }
      return;
    }
    host.showQuickModel(
      terminalProfilePick(
        profiles: profiles.availableProfiles,
        defaultName: profiles.defaultProfileName,
        placeholder: context.l10n.termSelectProfileToCreate,
        onPick: (profile) => create(profile: profile),
        l10n: context.l10n,
      ),
    );
  }

  /// Select Default Profile: the one picked is written to settings.json's
  /// `terminal.integrated.defaultProfile.<os>`.
  Future<void> selectDefaultProfile() async {
    final profiles = terminals?.profiles;
    if (profiles == null || !profiles.canSetDefault) return;
    await profiles.refresh();
    final context = host.context;
    if (context == null || !context.mounted) return;
    host.showQuickModel(
      terminalProfilePick(
        profiles: profiles.availableProfiles,
        defaultName: profiles.defaultProfileName,
        placeholder: context.l10n.termChooseDefaultProfile,
        onPick: (profile) => unawaited(
          profiles.setDefaultProfile(profile).catchError(host.report),
        ),
        l10n: context.l10n,
      ),
    );
  }

  /// The panel on TERMINAL (a terminal made if there is none), the active
  /// terminal focused, as VS Code's `showPanel(true)`.
  void show() {
    if (terminals == null) return;
    _layout().panel = IdePanelTab.terminal;
    if (_task != null) {
      _task = null;
      notifyListeners();
    }
    focusSoon();
  }

  /// Once the panel shows (and lets its terminals have the keyboard).
  void focusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host.context != null) terminals?.active?.focus();
    });
  }

  /// Focus Next (Previous) Terminal Group.
  void cycle({required bool next}) {
    final terminals = this.terminals;
    if (terminals == null) return;
    next ? terminals.focusNext() : terminals.focusPrevious();
    show();
  }

  /// Rename...: the active terminal's name, edited in its tab (in the
  /// panel's title when it is the only one).
  void rename() {
    final terminals = this.terminals;
    if (terminals?.active == null) return;
    _layout().panel = IdePanelTab.terminal;
    terminals!.startRename();
  }

  /// Kill All Terminals.
  void killAll() {
    final terminals = this.terminals;
    if (terminals == null) return;
    for (final instance in [...terminals.instances]) {
      terminals.kill(instance);
    }
  }

  /// Send Sequence: [args]' `text` to the active terminal as typed, its
  /// line breaks as Enter, the terminal scrolled to its end (upstream
  /// `terminalSendSequenceCommand`, `sendText(text, false)`).
  void sendSequence(Object? args) {
    final terminal = active;
    final text = args is Map ? args['text'] : null;
    if (terminal == null || text is! String || text.isEmpty) return;
    terminal.writeText(text.replaceAll(RegExp(r'\r?\n'), '\r'));
    terminal.terminal.scrollToBottom();
  }

  /// Focus Find: the find widget revealed, its input focused; the
  /// terminal's panel shown first if it is not.
  void focusFind(TerminalInstance terminal) {
    if (shown) return terminal.find.reveal();
    _layout().panel = IdePanelTab.terminal;
    WidgetsBinding.instance.addPostFrameCallback((_) => terminal.find.reveal());
  }

  /// Whether the panel's terminals run: a shell alive, or
  /// ([childProcesses]) one running a command
  /// (`terminal.integrated.confirmOnExit`).
  bool running({required bool childProcesses}) {
    for (final terminal in terminals?.instances ?? const <TerminalInstance>[]) {
      if (terminal.exited) continue;
      if (!childProcesses) return true;
      final command =
          terminal.shellIntegration?.commandDetection?.executingCommand;
      if (command != null && command.isNotEmpty) return true;
    }
    return false;
  }

  /// The terminal's context keys (terminalContextKey.ts); null for
  /// others.
  Object? contextKey(String key) {
    final terminals = this.terminals;
    final terminal = shown ? terminals?.active : null;
    final focused = terminal?.focusNode.hasFocus ?? false;
    final selected = terminal?.selection.hasSelection ?? false;
    return switch (key) {
      'terminalFocus' => focused,
      'terminalFocusInAny' => focused,
      'terminalTextSelected' => selected,
      'terminalTextSelectedInFocused' => focused && selected,
      'terminalProcessSupported' => terminals != null,
      'terminalHasBeenCreated' ||
      'terminalIsOpen' => terminals?.instances.isNotEmpty ?? false,
      'terminalCount' => terminals?.instances.length ?? 0,
      'terminalViewShowing' => terminal != null,
      'terminalAltBufferActive' => terminal?.source.isAlternateBuffer ?? false,
      'terminalFindVisible' => terminal?.find.isVisible ?? false,
      'terminalFindFocused' ||
      'terminalFindInputFocused' => terminal?.find.focused ?? false,
      'terminalSplitPaneActive' ||
      'terminalTabsFocus' ||
      'terminalEditorFocus' => false,
      _ => null,
    };
  }

  @override
  void dispose() {
    for (final subscription in _requests) {
      unawaited(subscription.cancel());
    }
    terminals?.removeListener(_terminalsChanged);
    if (owned) terminals?.dispose();
    super.dispose();
  }
}
