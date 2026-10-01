import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../l10n/l10n.dart';
import '../../notifications/attention_host.dart';
import '../../platform/app_platform.dart';
import '../../platform/data_dir.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/window_controls.dart';
import '../data_dir_service.dart';

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

  static String _revealLabel(AppLocalizations l10n) => AppPlatform.isWindows
      ? l10n.dataDirRevealInFileExplorer
      : l10n.explorerRevealInFinder;

  static bool get _canReveal =>
      WindowControls.canRevealInFileManager || AppPlatform.isWindows;

  Future<void> _reveal(String path) async {
    if (widget.reveal case final reveal?) return reveal(path);
    if (WindowControls.canRevealInFileManager) {
      return WindowControls.revealInFileManager(path);
    }
    await WindowControls.openExternal(path);
  }

  Future<void> _quit() async {
    if (widget.quit case final quit?) return quit();
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
    await _moveTo(path);
  }

  Future<void> _moveTo(String path, {bool toDefault = false}) async {
    final l10n = context.l10n;
    setState(() {
      _busy = l10n.dataDirChecking;
      _progress = null;
      _error = null;
    });
    try {
      final target = await _service.check(path, create: toDefault);
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = target.localizedError(l10n);
      });
      if (!target.ok) return;
      final existing = target.contents == DataDirectoryContents.baocodeData;
      final choice = await showIdeDialog(
        context,
        message: existing
            ? l10n.dataDirAlreadyHolds
            : toDefault
            ? l10n.dataDirMoveBack
            : l10n.dataDirMoveHere,
        detail: [
          target.path,
          if (existing)
            l10n.dataDirUseAsIsDetail
          else ...[
            l10n.dataDirCopyDetail,
            if (target.contents == DataDirectoryContents.other)
              l10n.dataDirOtherFiles,
          ],
        ].join('\n\n'),
        buttons: [
          existing ? l10n.dataDirUseItsData : l10n.dataDirCopyAndSwitch,
        ],
        type: IdeDialogType.question,
      );
      if (choice != 0 || !mounted) return;
      if (existing) {
        await _service.useAsIs(target.path);
      } else {
        setState(() => _busy = l10n.dataDirCopying);
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
        _pending = _service.pendingPath;
      });
      await _offerRestart();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = l10n.dataDirMoveFailed('$error'));
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
    TextStyle muted() =>
        TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Text(
          l10n.dataDirTitle,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.dataDirDescription, style: muted()),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dataDirCurrentFolder,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                current.path,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 12,
                  height: 1.5,
                  fontFamily: AppFonts.mono,
                ),
              ),
              Text(source, style: muted()),
              if (_pending case final pending?) ...[
                const SizedBox(height: 8),
                Text(l10n.dataDirAfterRestart(pending), style: muted()),
                const SizedBox(height: 6),
                IdeButton(label: l10n.dataDirQuitNow, onPressed: _quit),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            IdeButton(
              label: l10n.dataDirChange,
              onPressed: busy || fromEnvironment ? null : _change,
            ),
            IdeButton(
              label: l10n.dataDirResetDefault,
              secondary: true,
              onPressed:
                  busy ||
                      fromEnvironment ||
                      (service.usesDefault && _pending == null)
                  ? null
                  : () => _moveTo(service.defaultPath, toDefault: true),
            ),
            if (_canReveal)
              IdeButton(
                label: _revealLabel(l10n),
                secondary: true,
                onPressed: () => unawaited(_reveal(current.path)),
              ),
          ],
        ),
        if (fromEnvironment) ...[
          const SizedBox(height: 8),
          Text(
            l10n.dataDirEnvDecides(DataDirectory.environmentVariable),
            style: muted(),
          ),
        ],
        if (_busy case final busy?) ...[
          const SizedBox(height: 12),
          Text(busy, style: muted()),
          const SizedBox(height: 6),
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
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(
            error,
            style: TextStyle(
              color: themeColors['errorForeground'],
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
