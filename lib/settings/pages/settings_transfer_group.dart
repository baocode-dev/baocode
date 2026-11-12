import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart';
import '../../l10n/l10n.dart';
import '../../models/model_providers.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/window_controls.dart';
import '../settings_transfer.dart';
import '../user_settings.dart';
import 'settings_widgets.dart';

/// Settings → Data Folder's Move to Another Computer: the user's settings,
/// keybindings and upstreams exported to a file, and imported from one
/// (see [SettingsTransfer]).
class SettingsTransferGroup extends StatefulWidget {
  const SettingsTransferGroup({
    super.key,
    this.files,
    this.providers,
    this.pickSaveFile,
    this.pickOpenFile,
  });

  /// The app's when null.
  final SettingsFiles? files;
  final ModelProviders? providers;

  /// Where to export to, and the file to import; the native panels when
  /// null.
  final Future<String?> Function(String name)? pickSaveFile;
  final Future<String?> Function()? pickOpenFile;

  @override
  State<SettingsTransferGroup> createState() => _SettingsTransferGroupState();
}

class _SettingsTransferGroupState extends State<SettingsTransferGroup> {
  bool _busy = false;

  /// What the last export or import came to, and whether it failed.
  ({String text, bool failed})? _outcome;

  SettingsFiles get _files => widget.files ?? SettingsFiles.instance;
  ModelProviders get _providers => widget.providers ?? ModelProviders.current;

  Future<String?> _pickSave(String name) =>
      widget.pickSaveFile?.call(name) ??
      WindowControls.pickSaveFile(name: name);

  Future<String?> _pickOpen() async =>
      widget.pickOpenFile?.call() ??
      (await WindowControls.pickOpenFiles(multiple: false)).firstOrNull;

  Future<void> _run(Future<String?> Function() work) async {
    setState(() => _busy = true);
    ({String text, bool failed})? outcome;
    try {
      if (await work() case final text?) outcome = (text: text, failed: false);
    } on Object catch (error) {
      if (mounted) {
        outcome = (
          text: context.l10n.settingsTransferFailed('$error'),
          failed: true,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (outcome != null) _outcome = outcome;
    });
  }

  Future<void> _export() => _run(() async {
    final l10n = context.l10n;
    final asked = await showIdeInputDialog(
      context,
      message: l10n.settingsTransferExportQuestion,
      detail: l10n.settingsTransferExportDetail,
      checkbox: l10n.settingsTransferWithKeys,
      buttons: [l10n.settingsTransferExport],
      type: IdeDialogType.info,
    );
    if (asked == null || asked.button != 0) return null;
    final path = await _pickSave(SettingsTransfer.fileName);
    if (path == null) return null;
    final text = await SettingsTransfer.export(
      settings: _files.settings,
      keybindings: _files.keybindings,
      providers: _providers,
      keys: asked.checked,
    );
    await File(path).writeAsString(text, flush: true);
    return l10n.settingsTransferExported(path);
  });

  Future<void> _import() => _run(() async {
    final l10n = context.l10n;
    final path = await _pickOpen();
    if (path == null) return null;
    final file = SettingsTransfer.parse(await File(path).readAsString());
    if (file == null) throw l10n.settingsTransferNotAFile;
    if (!mounted) return null;
    final chosen = await showIdeDialog(
      context,
      message: l10n.settingsTransferImportQuestion(p.basename(path)),
      detail: l10n.settingsTransferImportDetail,
      buttons: [l10n.settingsTransferImport],
    );
    if (chosen != 0) return null;
    await SettingsTransfer.import(
      file,
      settings: _files.settings,
      keybindings: _files.keybindings,
      providers: _providers,
    );
    return l10n.settingsTransferImported;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final outcome = _outcome;
    return SettingsGroup(
      title: l10n.settingsTransferTitle,
      description: l10n.settingsTransferDescription,
      children: [
        SettingsRow(
          label: l10n.settingsTransferLabel,
          below: [
            if (outcome != null)
              SelectableText(
                outcome.text,
                style: outcome.failed
                    ? SettingsText.description.copyWith(
                        color: themeColors['errorForeground'],
                      )
                    : SettingsText.description,
              ),
          ],
          trailing: SettingsButtons(
            children: [
              IdeButton(
                label: l10n.settingsTransferImport,
                secondary: true,
                onPressed: _busy ? null : () => unawaited(_import()),
              ),
              IdeButton(
                label: l10n.settingsTransferExport,
                secondary: true,
                onPressed: _busy ? null : () => unawaited(_export()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
