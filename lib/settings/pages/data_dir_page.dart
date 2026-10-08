import 'dart:async';
import 'dart:io' show FileSystemException;
import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../l10n/l10n.dart';
import '../../notifications/attention_host.dart';
import '../../platform/app_platform.dart';
import '../../platform/data_dir.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/quit_confirmation.dart';
import '../../workspace/window_controls.dart';
import '../data_dir_service.dart';
import 'settings_widgets.dart';

/// Settings → Data Folder: where the app keeps the user's settings and its
/// own state ([DataDirectory]), and moving it elsewhere. A move copies the
/// app's data there (or uses the app's data already there), and applies
/// once the app restarts; the next start offers to remove what is left in
/// the old folder (`offerOldDataDirRemoval`).
class DataDirectoryPage extends StatefulWidget {
  const DataDirectoryPage({
    super.key,
    this.service,
    this.pickDirectory,
    this.reveal,
    this.quit,
  });

  /// The one of [DataDirectory.current] when null.
  final DataDirectoryService? service;

  /// Change's folder picker; the native one when null.
  final Future<String?> Function()? pickDirectory;

  /// Shows a folder in Finder or File Explorer.
  final Future<void> Function(String path)? reveal;

  /// Quits through the app's own exit, which ends its processes first
  /// (see `AppLifecycleListener` in main.dart).
  final Future<void> Function()? quit;

  @override
  State<DataDirectoryPage> createState() => _DataDirectoryPageState();
}

class _DataDirectoryPageState extends State<DataDirectoryPage> {
  late final DataDirectoryService _service =
      widget.service ?? DataDirectoryService();

  /// What is under way: checking, copying.
  String? _busy;
  double? _progress;
  String? _error;

  /// Where the next start keeps the data, when it is to move.
  late String? _pending = _service.pendingPath;

  /// The folder picked, checked, and not yet saved.
  DataDirectoryTarget? _draft;

  static String _revealLabel(AppLocalizations l10n) => AppPlatform.isWindows
      ? l10n.dataDirRevealInFileExplorer
      : l10n.explorerRevealInFinder;

  static bool get _canReveal =>
      WindowControls.canRevealInFileManager || AppPlatform.isWindows;

  Future<void> _reveal(String path) async {
    if (widget.reveal case final reveal?) return reveal(path);
    // Windows opens the folder itself, rather than selecting it in its
    // parent's.
    if (AppPlatform.isMacOS) {
      return WindowControls.revealInFileManager(path);
    }
    await WindowControls.openExternal(path);
  }

  Future<void> _quit() async {
    if (widget.quit case final quit?) return quit();
    // Chosen just now: not asked about again.
    QuitConfirmation.skipNext();
    // On Windows, the way the window's close button goes (which asks the
    // app first just the same): exitApplication was seen to hang there. The
    // engine's answer to it ends the message loop with the window still up,
    // and the runner then takes Flutter down outside the loop, without
    // FlutterWindow::OnDestroy.
    // That is the tray's Quit while there is a tray icon, the close button
    // then hiding the window.
    if (AppPlatform.isWindows) return ChannelAttentionHost.instance.quit();
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
  }

  Future<void> _change() async {
    final path = await (widget.pickDirectory ?? WindowControls.pickDirectory)();
    if (path == null || !mounted) return;
    await _propose(path);
  }

  /// Checks [path] and, when it can be used, shows it with Cancel and
  /// Save; nothing moves until Save.
  Future<void> _propose(String path, {bool toDefault = false}) async {
    final l10n = context.l10n;
    setState(() {
      _busy = l10n.dataDirChecking;
      _progress = null;
      _error = null;
      _draft = null;
    });
    try {
      final target = await _service.check(path, create: toDefault);
      if (!mounted) return;
      setState(() {
        _error = target.localizedError(l10n);
        if (target.ok) _draft = target;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = l10n.dataDirMoveFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _cancel() => setState(() => _draft = null);

  /// Copies the data to the folder chosen (or uses the data already
  /// there), then offers to restart.
  Future<void> _save() async {
    final target = _draft;
    if (target == null) return;
    final l10n = context.l10n;
    setState(() {
      _busy = l10n.dataDirCopying;
      _progress = null;
      _error = null;
    });
    try {
      if (target.contents == DataDirectoryContents.baocodeData) {
        await _service.useAsIs(target.path);
      } else {
        await _service.migrate(
          target.path,
          onProgress: (done, total) {
            if (!mounted) return;
            setState(() {
              _busy = l10n.dataDirCopyingProgress(done, total);
              _progress = total == 0 ? null : done / total;
            });
          },
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = null;
        _draft = null;
        _pending = _service.pendingPath;
      });
      await _offerRestart();
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error) {
            FileSystemException(:final path?) when isFileInUse(error) =>
              l10n.dataDirMoveInUse(path),
            _ => l10n.dataDirMoveFailed('$error'),
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _progress = null;
        });
      }
    }
  }

  Future<void> _offerRestart() async {
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.dataDirRestartTitle,
      detail: l10n.dataDirRestartDetail(
        _service.current.path,
        _pending ?? l10n.dataDirTheNewFolder,
      ),
      buttons: [l10n.dataDirQuitNow],
      cancel: l10n.dataDirLater,
      type: IdeDialogType.info,
    );
    if (choice == 0) await _quit();
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final current = service.current;
    final fromEnvironment = service.setByEnvironment;
    final busy = _busy != null;
    final l10n = context.l10n;
    final source = switch (current.source) {
      DataDirectorySource.environment => l10n.dataDirSetByEnv(
        DataDirectory.environmentVariable,
      ),
      DataDirectorySource.pointer => l10n.dataDirSetIn(service.pointerFile),
      DataDirectorySource.defaultLocation => l10n.dataDirDefaultLocation,
      DataDirectorySource.temporaryDefault => l10n.dataDirTemporaryDefault(
        service.pointerFile,
      ),
    };
    final draft = _draft;
    final reset =
        busy || fromEnvironment || (service.usesDefault && _pending == null)
        ? null
        : () => _propose(service.defaultPath, toDefault: true);
    return SettingsPage(
      title: l10n.dataDirTitle,
      description: l10n.dataDirDescription,
      children: [
        SettingsCard(
          children: [
            SettingsRow(
              label: draft == null
                  ? l10n.dataDirCurrentFolder
                  : l10n.dataDirNewFolder,
              below: [
                SelectableText(
                  draft?.path ?? current.path,
                  style: SettingsText.path,
                ),
                if (draft != null) ...[
                  Text(
                    draft.contents == DataDirectoryContents.baocodeData
                        ? l10n.dataDirUseAsIsDetail
                        : l10n.dataDirCopyDetail,
                    style: SettingsText.description,
                  ),
                  if (draft.contents == DataDirectoryContents.other)
                    Text(
                      l10n.dataDirOtherFiles,
                      style: SettingsText.description,
                    ),
                ] else ...[
                  Text(source, style: SettingsText.description),
                  if (fromEnvironment)
                    Text(
                      l10n.dataDirEnvDecides(DataDirectory.environmentVariable),
                      style: SettingsText.description,
                    ),
                  if (_pending case final pending?)
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n.dataDirAfterRestart(pending),
                          style: SettingsText.description,
                        ),
                        IdeButton(label: l10n.dataDirQuitNow, onPressed: _quit),
                      ],
                    ),
                ],
                if (_busy case final busy?) ...[
                  Text(busy, style: SettingsText.description),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 2,
                      color: themeColors['progressBar.background'],
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ],
                if (_error case final error?)
                  Text(
                    error,
                    style: SettingsText.description.copyWith(
                      color: themeColors['errorForeground'],
                    ),
                  ),
              ],
              trailing: SettingsButtons(
                children: draft != null
                    ? [
                        IdeButton(
                          label: l10n.commonCancel,
                          secondary: true,
                          onPressed: busy ? null : _cancel,
                        ),
                        IdeButton(
                          label: l10n.commonSave,
                          onPressed: busy ? null : _save,
                        ),
                      ]
                    : [
                        if (_canReveal)
                          IdeButton(
                            label: _revealLabel(l10n),
                            secondary: true,
                            onPressed: () => unawaited(_reveal(current.path)),
                          ),
                        IdeButton(
                          label: l10n.dataDirChange,
                          secondary: true,
                          onPressed: busy || fromEnvironment ? null : _change,
                        ),
                        IdeButton(
                          label: l10n.dataDirResetDefault,
                          secondary: true,
                          onPressed: reset,
                        ),
                      ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
