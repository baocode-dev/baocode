// The top of the Run and Debug view: the configuration dropdown, the
// start button (and run without debugging), the gear with its menu, and
// the welcome view when there is nothing to start.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/debugViewlet.ts and
// welcomeView.ts, debugCommands.ts (`debug.start`, `debug.startFromConfig`,
// `debug.openConfigFile`, `debug.addConfiguration`, `workbench.action.debug.run`).
//
// Deviations: the dropdown and the gear menu are [showIdeMenu]s; the
// welcome view's links are actions.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show CancellationTokenSource;
import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../theme/codicons.dart';
import '../base/event.dart';
import '../common/debug_types.dart';
import '../service/debug_configuration_manager.dart';
import '../service/debug_host.dart';
import '../service/debug_service.dart';
import '../service/debugger.dart';
import '../session/debug_session.dart';
import 'debug_icons.dart';
import 'debug_strings.dart';

/// A session is starting or running.
bool debugStartDisabled(DebugService service) =>
    service.state == DebugState.initializing || service.state == DebugState.running;

class RunAndDebugView extends StatefulWidget {
  const RunAndDebugView({super.key, required this.service});

  final DebugService service;

  @override
  State<RunAndDebugView> createState() => RunAndDebugViewState();
}

class RunAndDebugViewState extends State<RunAndDebugView> {
  final DisposableStore _listeners = DisposableStore();

  DebugService get service => widget.service;
  ConfigurationManager get manager => service.configurationManager;

  @override
  void initState() {
    super.initState();
    _listeners
      ..add(service.viewModel.onDidFocusSession((_) => _changed()))
      ..add(service.onDidChangeState((_) => _changed()))
      ..add(manager.onDidSelectConfiguration(_changed));
  }

  @override
  void dispose() {
    _listeners.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Starts the selected configuration, or [config]/[name].
  Future<void> start({bool noDebug = false, String? name, Json? config, Launch? launch}) async {
    final selected = manager.selectedConfiguration;
    launch ??= selected.launch;
    final configOrName = config ?? (name ?? selected.name);
    if (configOrName == null || (configOrName is String && configOrName.isEmpty)) {
      // Nothing selected: pick a configuration, or create launch.json.
      final picked = await _pickConfiguration();
      if (picked == null) return;
      await start(noDebug: noDebug, launch: picked.launch, name: picked.name);
      return;
    }
    await service.startDebugging(
      launch,
      configOrName,
      options: DebugSessionOptions(noDebug: noDebug, startedByUser: true),
    );
  }

  /// The configuration picker of the dropdown.
  Future<LaunchConfigurationEntry?> _pickConfiguration() async {
    final all = manager.getAllConfigurations();
    if (all.isEmpty) {
      await openConfigFile();
      return null;
    }
    final picked = await service.host.pick<LaunchConfigurationEntry>([
      for (final e in all) DebugPickItem(e.name, e, description: e.launch.hidden ? null : e.launch.name),
    ], placeholder: 'Select a debug configuration');
    if (picked != null) {
      await manager.selectConfiguration(picked.launch, name: picked.name);
    }
    return picked;
  }

  /// Opens (creating it when needed) the selected folder's launch.json.
  Future<void> openConfigFile({String? type}) async {
    final selected = manager.selectedConfiguration;
    final launch = selected.launch ?? manager.getLaunches().firstOrNull;
    if (launch == null) return;
    await launch.openConfigFile(type: type);
    await manager.reload();
  }

  /// The gear menu (`debug.addConfiguration`, open launch.json, the
  /// debuggers).
  Future<void> showGearMenu(Rect anchor) async {
    final s = DebugStrings.of(context);
    await showIdeMenu(
      context,
      anchor: anchor,
      alignRight: true,
      entries: ideMenuGroups([
        [
          IdeMenuAction(s.addConfiguration, onSelected: () => unawaited(_addConfiguration())),
          IdeMenuAction(s.openLaunchJson, onSelected: () => unawaited(openConfigFile())),
          IdeMenuAction(s.selectDebugger, onSelected: () => unawaited(_createLaunchJson())),
        ],
      ]),
    );
  }

  /// "Add Configuration": a debugger, then its initial configurations.
  Future<void> _addConfiguration() async {
    final debugger = await _pickDebugger();
    if (debugger == null) return;
    await _writeInitialConfiguration(debugger);
  }

  Future<void> _createLaunchJson() async {
    final debugger = await _pickDebugger();
    if (debugger == null) return;
    await openConfigFile(type: debugger.type);
  }

  Future<Debugger?> _pickDebugger() {
    final debuggers = service.registry.debuggers.where((d) => d.enabled).toList();
    if (debuggers.isEmpty) {
      service.host.showError(DebugStrings.of(context).noDebuggers);
      return Future.value(null);
    }
    if (debuggers.length == 1) return Future.value(debuggers.first);
    return service.host.pick<Debugger>(
      [for (final d in debuggers) DebugPickItem(d.label, d)],
      placeholder: DebugStrings.of(context).selectDebugger,
    );
  }

  /// Appends the debugger's initial configurations to launch.json,
  /// creating the file where there is none.
  Future<void> _writeInitialConfiguration(Debugger debugger) async {
    final token = CancellationTokenSource().token;
    final folder = manager.selectedConfiguration.launch?.workspace ?? service.host.workspaceFolders.firstOrNull;
    final configs = await manager.provideDebugConfigurations(folder?.uri, debugger.type, token);
    final launch = manager.selectedConfiguration.launch;
    if (launch is FolderLaunch) {
      if (launch.getConfig() == null) {
        await launch.openConfigFile(type: debugger.type, suppressInitialConfigs: configs.isEmpty);
      } else if (configs.isNotEmpty) {
        for (final config in configs) {
          await launch.writeConfiguration(config);
        }
      }
      await manager.reload();
      final added = configs.isNotEmpty ? configs.first.str('name') : null;
      if (added != null) {
        final l = manager.getLaunch(folder?.uri);
        if (l != null) await manager.selectConfiguration(l, name: added);
      }
    } else {
      await openConfigFile(type: debugger.type);
    }
  }

  /// Runs the active file without debugging (`workbench.action.debug.run`).
  Future<void> runWithoutDebugging() async {
    final selected = manager.selectedConfiguration;
    if (selected.name != null && selected.launch != null) {
      await start(noDebug: true);
      return;
    }
    final debugger = await _pickDebugger();
    if (debugger == null) return;
    await service.startDebugging(
      null,
      {'type': debugger.type, 'request': 'launch', 'name': debugger.label, 'noDebug': true},
      options: const DebugSessionOptions(noDebug: true, startedByUser: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    final selected = manager.selectedConfiguration;
    final configurations = manager.getAllConfigurations();
    final hasLaunch = manager.getLaunches().any((l) => !l.hidden);
    return Column(
      children: [
        _ConfigRow(
          label: selected.name ?? s.noConfigurations,
          enabled: configurations.isNotEmpty,
          onTap: (anchor) => unawaited(_showConfigMenu(anchor)),
          onStart: debugStartDisabled(service) ? null : () => unawaited(start()),
          onGear: (anchor) => unawaited(showGearMenu(anchor)),
        ),
        if (selected.name != null)
          _StartRow(
            s: s,
            onStart: debugStartDisabled(service) ? null : () => unawaited(start()),
            onRun: debugStartDisabled(service) ? null : () => unawaited(runWithoutDebugging()),
          ),
        if (configurations.isEmpty && service.debugUx == 'simple' && service.state == DebugState.inactive)
          _Welcome(
            s: s,
            hasFolder: service.host.workspaceFolders.isNotEmpty,
            hasLaunch: hasLaunch,
            onCreate: () => unawaited(_createLaunchJson()),
          ),
      ],
    );
  }

  Future<void> _showConfigMenu(Rect anchor) async {
    final all = manager.getAllConfigurations();
    await showIdeMenu(
      context,
      anchor: anchor,
      entries: [
        for (final e in all)
          IdeMenuAction(
            e.launch.hidden ? '${e.name}  (${e.launch.name})' : e.name,
            checked: e.name == manager.selectedConfiguration.name &&
                e.launch == manager.selectedConfiguration.launch,
            onSelected: () => unawaited(manager.selectConfiguration(e.launch, name: e.name)),
          ),
        if (all.isNotEmpty) const IdeMenuSeparator(),
        IdeMenuAction(DebugStrings.of(context).addConfiguration, onSelected: () => unawaited(_addConfiguration())),
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.onStart,
    required this.onGear,
  });

  final String label;
  final bool enabled;
  final void Function(Rect anchor) onTap;
  final VoidCallback? onStart;
  final void Function(Rect anchor) onGear;

  void _anchor(BuildContext context, void Function(Rect) action) {
    final box = context.findRenderObject()! as RenderBox;
    action(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: Builder(
            builder: (context) => MouseRegion(
              cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                onTap: enabled ? () => _anchor(context, onTap) : null,
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: debugColor('dropdown.background'),
                    border: Border.all(color: debugColor('dropdown.border')),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: debugColor('dropdown.foreground')),
                        ),
                      ),
                      Icon(Codicons.chevronDown, size: 14, color: debugColor('dropdown.foreground')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Builder(
          builder: (context) => IdeActionButton(
            icon: Codicons.debugStart,
            tooltip: DebugStrings.of(context).startDebugging,
            color: onStart == null ? null : debugColor('debugIcon.startForeground'),
            onPressed: onStart,
          ),
        ),
        Builder(
          builder: (context) => IdeActionButton(
            icon: Codicons.gear,
            tooltip: DebugStrings.of(context).moreActions,
            onPressed: () => _anchor(context, onGear),
          ),
        ),
      ],
    ),
  );
}

class _StartRow extends StatelessWidget {
  const _StartRow({required this.s, required this.onStart, required this.onRun});

  final DebugStrings s;
  final VoidCallback? onStart;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Row(
      children: [
        Icon(Codicons.debugStart, size: 16, color: debugColor('debugIcon.startForeground')),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            s.startDebugging,
            style: TextStyle(fontSize: 13, color: debugIconLinkColor),
          ),
        ),
        IdeHover(
          message: s.runWithoutDebugging,
          child: IdeActionButton(icon: Codicons.play, tooltip: s.runWithoutDebugging, size: 20, onPressed: onRun),
        ),
      ],
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.s, required this.hasFolder, required this.hasLaunch, required this.onCreate});

  final DebugStrings s;
  final bool hasFolder;
  final bool hasLaunch;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.welcomeRun, style: TextStyle(fontSize: 20, color: IdeListColors.foreground)),
        const SizedBox(height: 12),
        if (!hasFolder)
          Text(s.welcomeNoFolder, style: TextStyle(fontSize: 13, height: 1.5, color: IdeListColors.foreground))
        else ...[
          Text(
            hasLaunch ? s.welcomeCustomize.replaceAll('{link}', s.createLaunchJson) : s.welcomeNoFolder,
            style: TextStyle(fontSize: 13, height: 1.5, color: IdeListColors.foreground),
          ),
          const SizedBox(height: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onCreate,
              child: Text(s.createLaunchJson, style: TextStyle(fontSize: 13, color: debugIconLinkColor)),
            ),
          ),
        ],
      ],
    ),
  );
}

/// The debug link color (`textLink.foreground`).
Color get debugIconLinkColor => debugColor('textLink.foreground');

