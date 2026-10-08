import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../ide/ide_button.dart';
import '../ide/ide_dialog.dart';
import '../l10n/l10n.dart';
import '../platform/data_dir.dart';
import '../theme/codicons.dart';
import '../theme/app_theme.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/window_controls.dart';
import 'app_locale.dart';
import 'data_dir_service.dart';

/// Shows [DataDirectoryRecoveryApp] in place of the app until the user
/// decides how to go on without the data folder [problem] reports, and
/// completes with the folder to use: main.dart calls it before anything is
/// read from the folder, or any process list reaped.
Future<DataDirectory> recoverDataDirectory(DataDirectoryResolution problem) {
  final chosen = Completer<DataDirectory>();
  runApp(
    DataDirectoryRecoveryApp(problem: problem, onResolved: chosen.complete),
  );
  return chosen.future;
}

/// The small app shown before the real one when the data folder set by
/// `BAOCODE_DATA_DIR` or `~/.baocode/config-dir.json` cannot be used (a drive
/// that is gone, a pointer that does not parse): try again, use the
/// platform's default folder this time only (the pointer left as it is), or
/// choose another folder (written to the pointer). The default is never
/// used unasked.
class DataDirectoryRecoveryApp extends StatelessWidget {
  const DataDirectoryRecoveryApp({
    super.key,
    required this.problem,
    required this.onResolved,
    this.resolve,
    this.pickDirectory,
  });

  final DataDirectoryResolution problem;

  /// Hears the folder to use; called once.
  final ValueChanged<DataDirectory> onResolved;

  /// Retry's resolution; [resolveDataDirectory] when null.
  final DataDirectoryResolution Function()? resolve;

  /// Choose Another Folder's picker; the native one when null.
  final Future<String?> Function()? pickDirectory;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BaoCode',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    // The display language setting is in the folder that is not there:
    // the system's language.
    supportedLocales: AppLocale.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: DataDirectoryRecovery(
      problem: problem,
      onResolved: onResolved,
      resolve: resolve,
      pickDirectory: pickDirectory,
    ),
  );
}

/// [DataDirectoryRecoveryApp]'s page.
class DataDirectoryRecovery extends StatefulWidget {
  const DataDirectoryRecovery({
    super.key,
    required this.problem,
    required this.onResolved,
    this.resolve,
    this.pickDirectory,
  });

  final DataDirectoryResolution problem;
  final ValueChanged<DataDirectory> onResolved;
  final DataDirectoryResolution Function()? resolve;
  final Future<String?> Function()? pickDirectory;

  @override
  State<DataDirectoryRecovery> createState() => _DataDirectoryRecoveryState();
}

class _DataDirectoryRecoveryState extends State<DataDirectoryRecovery> {
  late DataDirectoryResolution _problem = widget.problem;
  bool _resolved = false;
  bool _busy = false;

  /// Why the folder chosen cannot be used.
  String? _choiceError;

  @override
  void didUpdateWidget(DataDirectoryRecovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.problem != oldWidget.problem) {
      _problem = widget.problem;
      _choiceError = null;
    }
  }

  void _resolve(DataDirectory directory) {
    if (_resolved) return;
    _resolved = true;
    widget.onResolved(directory);
  }

  void _retry() {
    final resolution = (widget.resolve ?? resolveDataDirectory)();
    if (resolution.ok) return _resolve(resolution.directory);
    setState(() {
      _problem = resolution;
      _choiceError = null;
    });
  }

  void _useDefault() => _resolve(
    DataDirectory(
      _problem.defaultPath,
      source: DataDirectorySource.temporaryDefault,
    ),
  );

  Future<void> _chooseAnother() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final path =
          await (widget.pickDirectory ?? WindowControls.pickDirectory)();
      if (path == null || !mounted) return;
      final (problem, error) = checkDataDirectory(path);
      if (problem != null) {
        setState(
          () => _choiceError = localizedDataDirectoryProblem(
            l10n,
            problem,
            path,
            error: error,
          ),
        );
        return;
      }
      // What else the pointer says stays, when it can be read.
      DataDirectoryPointer? kept;
      try {
        kept = DataDirectoryPointer.read(File(_problem.pointerFile));
      } on FormatException {
        kept = null;
      }
      await DataDirectoryPointer(
        dataDir: path,
        previousDataDir: kept?.previousDataDir,
      ).write(File(_problem.pointerFile));
      _resolve(DataDirectory(path, source: DataDirectorySource.pointer));
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _choiceError = l10n.dataDirCannotWritePointer(
            _problem.pointerFile,
            error.message,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final problem = _problem;
    final fromEnvironment = problem.source == DataDirectorySource.environment;
    final l10n = context.l10n;
    final title = switch (problem.problem) {
      DataDirectoryProblem.invalidPointer => l10n.dataDirSettingUnreadable,
      DataDirectoryProblem.notWritable => l10n.dataDirCannotWrite,
      _ => l10n.dataDirUnavailable,
    };
    final where = fromEnvironment
        ? l10n.dataDirWhereEnv(DataDirectory.environmentVariable)
        : problem.problem == DataDirectoryProblem.invalidPointer
        ? l10n.dataDirWhereFixPointer(problem.pointerFile)
        : l10n.dataDirWherePointer(problem.pointerFile);
    final error = switch (problem.problem) {
      final kind? => localizedDataDirectoryProblem(
        l10n,
        kind,
        problem.path,
        error: problem.error,
      ),
      null => problem.error ?? '',
    };
    TextStyle text({Color? color, double size = 13, FontWeight? weight}) =>
        TextStyle(
          color: color ?? AppColors.text,
          fontSize: size,
          height: 1.5,
          fontWeight: weight,
        );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: colors['widget.shadow'],
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Codicons.warning,
                        size: 20,
                        color: colors['problemsWarningIcon.foreground'],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: text(
                          color: AppColors.textPrimary,
                          size: 15,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (problem.problem != DataDirectoryProblem.invalidPointer)
                  SelectableText(
                    problem.path,
                    style: text(size: 12).copyWith(
                      fontFamily: AppFonts.mono,
                      fontFamilyFallback: AppFonts.monoFallbacks,
                    ),
                  ),
                SelectableText(error, style: text()),
                const SizedBox(height: 6),
                Text(where, style: text(color: AppColors.textMuted, size: 12)),
                const SizedBox(height: 6),
                Text(
                  l10n.dataDirDefaultIs(problem.defaultPath),
                  style: text(color: AppColors.textMuted, size: 12),
                ),
                if (_choiceError case final error?) ...[
                  const SizedBox(height: 10),
                  Text(
                    error,
                    style: text(color: colors['errorForeground'], size: 12),
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IdeButton(
                      label: l10n.dataDirRetry,
                      onPressed: _busy ? null : _retry,
                    ),
                    IdeButton(
                      label: l10n.dataDirUseDefaultOnce,
                      secondary: true,
                      onPressed: _busy ? null : _useDefault,
                    ),
                    if (!fromEnvironment)
                      IdeButton(
                        label: l10n.dataDirChooseAnother,
                        secondary: true,
                        onPressed: _busy ? null : _chooseAnother,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks, once the app has moved its data to another folder and restarted,
/// whether to remove what is left in the old one: only the app's own
/// entries there ([DataDirectory.items]), never the folder itself or the
/// other files in it. Remove or Keep settle it; dismissing asks again on
/// the next start, as does Remove when a file there is still in use (shown
/// then). The workbench calls it once it shows.
Future<void> offerOldDataDirRemoval(
  BuildContext context, {
  DataDirectoryService? service,
}) async {
  service ??= DataDirectoryService();
  final previous = service.previousDirectory;
  if (previous == null) {
    await service.forgetPrevious();
    return;
  }
  final items = DataDirectoryService.leftoverItems(previous);
  final l10n = context.l10n;
  final choice = await showIdeDialog(
    context,
    message: l10n.dataDirRemoveOldTitle,
    detail:
        '$previous\n\n'
        '${l10n.dataDirRemoveOldDetail(service.current.path, items.join(', '))}',
    buttons: [l10n.dataDirRemove, l10n.dataDirKeep],
    cancel: l10n.dataDirLater,
    type: IdeDialogType.question,
  );
  switch (choice) {
    case 0:
      final left = await service.removeOldData(previous);
      if (left.isEmpty || !context.mounted) return;
      await showIdeDialog(
        context,
        message: l10n.dataDirRemoveOldInUse,
        detail:
            '$previous\n\n${l10n.dataDirRemoveOldInUseDetail(left.join(', '))}',
        buttons: [l10n.commonOk],
        cancel: null,
      );
    case 1:
      await service.forgetPrevious();
  }
}
